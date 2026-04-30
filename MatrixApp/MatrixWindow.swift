import Cocoa
import Metal
import MatrixCore

/// Borderless, screensaver-level window that covers a single `NSScreen` and
/// hosts a `MatrixLayerHost` for rendering. One per screen during activation.
final class MatrixWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.isOpaque = true
        self.hasShadow = false
        self.backgroundColor = .black
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isReleasedWhenClosed = false
        self.setFrame(screen.frame, display: false)

        // Plain layer-hosting NSView as content. We put the Metal layer in
        // it ourselves.
        let content = MatrixWindowContentView(frame: screen.frame)
        self.contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Layer-hosting view that owns a `MatrixLayerHost`. Built using the same
/// pattern Aerial uses for its `AVPlayerLayer`: assign `self.layer` BEFORE
/// `wantsLayer = true` so the view is layer-hosting (not layer-backed) and
/// AppKit doesn't redraw or invalidate our sublayers.
final class MatrixWindowContentView: NSView {
    private(set) var layerHost: MatrixLayerHost?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-HOSTING setup, in this exact order.
        let host = CALayer()
        host.backgroundColor = NSColor.black.cgColor
        host.frame = self.bounds
        self.layer = host
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        let host = CALayer()
        host.backgroundColor = NSColor.black.cgColor
        host.frame = self.bounds
        self.layer = host
        self.wantsLayer = true
    }

    /// Install a `MatrixLayerHost` and start its render loop on the given
    /// screen. Idempotent.
    func install(on screen: NSScreen, settings: MatrixSettings) {
        guard layerHost == nil,
              let device = MTLCreateSystemDefaultDevice(),
              let host = MatrixLayerHost(device: device),
              let hostLayer = self.layer else {
            return
        }
        host.install(in: hostLayer, scale: screen.backingScaleFactor)
        host.settings = settings
        host.start(screen: screen)
        layerHost = host
    }

    func teardown() {
        layerHost?.stop()
        layerHost = nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let host = layerHost, let hostLayer = self.layer else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        host.resize(bounds: hostLayer.bounds, scale: scale)
    }

    override func layout() {
        super.layout()
        guard let host = layerHost, let hostLayer = self.layer else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        host.resize(bounds: hostLayer.bounds, scale: scale)
    }
}
