import Foundation
import AppKit
import CoreVideo
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
    // nonisolated(unsafe) so the CoreVideo render-thread callback can
    // touch them. They're `let` (never reassigned), and CAMetalLayer +
    // MatrixRenderer are safe for the single-writer access pattern used
    // by the CV callback.
    public nonisolated(unsafe) let metalLayer: CAMetalLayer
    public nonisolated(unsafe) let renderer: MatrixRenderer

    // CVDisplayLink instead of `screen.displayLink(target:selector:)`
    // (CADisplayLink) because the latter was throttled to ~2fps for ~1s
    // every ~2s on windows at `CGWindowLevelForKey(.desktopWindow)` —
    // macOS treats wallpaper-level surfaces as low-priority for
    // compositor scheduling. CVDisplayLink runs on a CoreVideo-owned
    // thread tied to the display device, not the window, and isn't
    // subject to that throttling.
    //
    // CVDisplayLink is technically deprecated in macOS 15 in favour of
    // NSScreen.displayLink — but the replacement is what we just rejected,
    // so we use the deprecated API.
    private nonisolated(unsafe) var displayLink: CVDisplayLink?

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

    /// Start the render loop bound to the given screen's vsync via
    /// CVDisplayLink.
    public func start(screen: NSScreen) {
        stop()

        let displayID: CGDirectDisplayID = {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let n = screen.deviceDescription[key] as? NSNumber {
                return CGDirectDisplayID(n.uint32Value)
            }
            return CGMainDisplayID()
        }()

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithCGDisplay(displayID, &link)
        guard let link else { return }

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, ctx -> CVReturn in
            guard let ctx else { return kCVReturnSuccess }
            let host = Unmanaged<MatrixLayerHost>.fromOpaque(ctx).takeUnretainedValue()
            host.cvTick()
            return kCVReturnSuccess
        }, opaque)
        CVDisplayLinkStart(link)
        displayLink = link
    }

    public func stop() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    public var isPaused: Bool {
        get {
            guard let link = displayLink else { return true }
            return !CVDisplayLinkIsRunning(link)
        }
        set {
            guard let link = displayLink else { return }
            if newValue { CVDisplayLinkStop(link) } else { CVDisplayLinkStart(link) }
        }
    }

    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
    }

    /// Called from a CoreVideo-owned thread. Renders directly without
    /// hopping to main: hopping would re-introduce the same wallpaper-
    /// level window throttling we're escaping.
    private nonisolated func cvTick() {
        guard let drawable = metalLayer.nextDrawable() else { return }
        renderer.renderFrame(into: drawable, drawableSize: metalLayer.drawableSize)
    }
}
