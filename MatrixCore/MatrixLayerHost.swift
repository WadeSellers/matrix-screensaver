import Foundation
import AppKit
import Metal
import QuartzCore

/// Layer-hosting wrapper around `MatrixRenderer`.
///
/// The screensaver path (`MatrixSaverView`) needs to install a `CAMetalLayer`
/// directly inside the saver's host layer (i.e. as a sublayer of `self.layer`,
/// **not** as the backing layer of an `MTKView` subview). On macOS Tahoe the
/// `legacyScreenSaver` compositor only captures the screensaver view's own
/// backing surface; `MTKView` subviews get composited locally on first
/// activation and then dropped on subsequent ones, producing the
/// "every-other-activation goes black" symptom.
///
/// Pattern adapted from `JohnCoates/Aerial`'s `AerialView+Player.swift`,
/// which uses the equivalent layer-hosting pattern with `AVPlayerLayer`.
@MainActor
public final class MatrixLayerHost {
    public let metalLayer: CAMetalLayer
    public let renderer: MatrixRenderer

    // nonisolated(unsafe) so deinit can invalidate the link to break the
    // CADisplayLink → target retain. We only mutate from main-actor code.
    private nonisolated(unsafe) var displayLink: CADisplayLink?
    private nonisolated(unsafe) var displayLinkTarget: DisplayLinkTarget?

    public var settings: MatrixSettings {
        get { renderer.settings }
        set { renderer.settings = newValue }
    }

    public init?(device: MTLDevice) {
        guard let renderer = MatrixRenderer(device: device) else { return nil }
        self.renderer = renderer

        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = false  // we sample the drawable in composite
        metalLayer.contentsGravity = .resizeAspectFill
        metalLayer.needsDisplayOnBoundsChange = true
        // Leave allowsNextDrawableTimeout at its default (true). Setting it
        // to false makes nextDrawable() block forever if the drawable pool
        // is exhausted, which on the main thread deadlocks the run loop —
        // observed as "screensaver disappears after a moment".
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        self.metalLayer = metalLayer
    }

    /// Inserts our metal layer into the given host layer (typically the
    /// saver view's `self.layer`). Sets initial size + scale.
    public func install(in hostLayer: CALayer, scale: CGFloat) {
        metalLayer.frame = hostLayer.bounds
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: hostLayer.bounds.width * scale,
            height: hostLayer.bounds.height * scale
        )
        metalLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        hostLayer.addSublayer(metalLayer)
    }

    /// Update geometry for the host layer's current bounds + scale. Call
    /// from `viewDidChangeBackingProperties` and on layout changes.
    public func resize(bounds: CGRect, scale: CGFloat) {
        metalLayer.frame = bounds
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }

    /// Start the render loop bound to the given screen's vsync.
    /// (`NSScreen.displayLink` is the only public way to get a `CADisplayLink`
    /// on macOS — there is no `init(target:selector:)` on macOS.)
    public func start(screen: NSScreen) {
        stop()
        let target = DisplayLinkTarget { [weak self] in self?.tick() }
        let link = screen.displayLink(
            target: target,
            selector: #selector(DisplayLinkTarget.fire)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
        displayLinkTarget = target
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    public var isPaused: Bool {
        get { displayLink?.isPaused ?? true }
        set { displayLink?.isPaused = newValue }
    }

    deinit {
        // displayLink uses a weak ref so this is safe to call from deinit.
        displayLink?.invalidate()
    }

    private func tick() {
        guard let drawable = metalLayer.nextDrawable() else { return }
        renderer.renderFrame(into: drawable, drawableSize: metalLayer.drawableSize)
    }
}

/// Tiny wrapper so CADisplayLink doesn't retain the host through a strong
/// `target:` reference (CADisplayLink retains its target).
private final class DisplayLinkTarget: NSObject {
    let callback: () -> Void
    init(callback: @escaping () -> Void) { self.callback = callback }
    @objc func fire() { callback() }
}
