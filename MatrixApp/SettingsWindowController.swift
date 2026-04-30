import Cocoa
import SwiftUI
import Metal
import MatrixCore

/// Hosts the Settings SwiftUI view in an NSWindow, with a live Matrix
/// preview rendering as the window's background. Singleton-style: one
/// shared window, brought to front on each show().
@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private weak var previewView: SettingsPreviewView?
    private var windowDelegate: SettingsWindowDelegate?

    private let model: SettingsModel
    private let externalOnChange: (AppSettings) -> Void

    init(initial: AppSettings, onChange: @escaping (AppSettings) -> Void) {
        self.externalOnChange = onChange
        self.model = SettingsModel(initial: initial)
        super.init()
        // After super.init, self is available — wire model.onChange to push
        // updates both to the persistence callback and to the live preview.
        model.onChange = { [weak self] newSettings in
            guard let self else { return }
            self.externalOnChange(newSettings)
            self.previewView?.layerHost?.settings = newSettings.matrix
        }
    }

    func show() {
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            previewView?.startPreviewIfNeeded(settings: model.settings.matrix)
            return
        }

        let frameRect = NSRect(x: 0, y: 0, width: 460, height: 460)

        // Custom layer-hosted contentView. Matrix preview renders as its
        // background; the SwiftUI form sits on top with translucent
        // section backgrounds so the rain shows through.
        let preview = SettingsPreviewView(frame: frameRect)
        let formHost = NSHostingView(rootView: SettingsView(model: model))
        formHost.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(formHost)
        NSLayoutConstraint.activate([
            formHost.topAnchor.constraint(equalTo: preview.topAnchor),
            formHost.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
            formHost.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            formHost.trailingAnchor.constraint(equalTo: preview.trailingAnchor)
        ])

        let window = NSWindow(
            contentRect: frameRect,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Matrix Settings"
        // Title bar transparent so Matrix extends underneath it. Keeps the
        // close/minimize buttons visible against whatever rains under them.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.contentView = preview

        let delegate = SettingsWindowDelegate { [weak preview] in
            preview?.stopPreview()
        }
        window.delegate = delegate

        self.window = window
        self.previewView = preview
        self.windowDelegate = delegate

        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Wait one runloop tick so window.screen is populated, then start
        // the preview render loop.
        DispatchQueue.main.async { [weak preview] in
            preview?.startPreviewIfNeeded(settings: self.model.settings.matrix)
        }
    }
}

/// Layer-hosted view that owns the live preview's `MatrixLayerHost`.
/// Same layer-hosting pattern (self.layer assigned BEFORE wantsLayer=true)
/// we use for the fullscreen `MatrixWindowContentView`.
final class SettingsPreviewView: NSView {
    private(set) var layerHost: MatrixLayerHost?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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

    func startPreviewIfNeeded(settings: MatrixSettings) {
        guard layerHost == nil,
              let device = MTLCreateSystemDefaultDevice(),
              let host = MatrixLayerHost(device: device),
              let hostLayer = self.layer,
              let screen = window?.screen ?? NSScreen.main else { return }
        host.install(in: hostLayer, scale: screen.backingScaleFactor)
        host.settings = settings
        host.start(screen: screen)
        layerHost = host
    }

    func stopPreview() {
        layerHost?.stop()
        layerHost = nil
    }

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

/// Stops the preview render loop when the user closes the window so we
/// don't burn GPU cycles on a hidden render.
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

/// Observable model bridging SwiftUI bindings to AppSettings + a callback.
/// `onChange` is set after init by the controller (it needs a `self`-
/// referencing closure that can't be captured in the controller's init
/// before `super.init`).
@MainActor
@Observable
final class SettingsModel {
    var settings: AppSettings {
        didSet {
            if settings != oldValue {
                onChange?(settings)
            }
        }
    }
    var onChange: ((AppSettings) -> Void)?

    init(initial: AppSettings) {
        self.settings = initial
    }
}

private struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section("Rendering") {
                HStack {
                    Text("Speed")
                        .frame(width: 80, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(model.settings.matrix.speedMultiplier) },
                            set: { model.settings.matrix.speedMultiplier = Float($0) }
                        ),
                        in: 0.25...3.0
                    )
                    Text(String(format: "%.2f×", model.settings.matrix.speedMultiplier))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }

                Toggle(
                    "Bloom glow on heads",
                    isOn: Binding(
                        get: { model.settings.matrix.bloomEnabled },
                        set: { model.settings.matrix.bloomEnabled = $0 }
                    )
                )

                Toggle(
                    "CRT mode (scanlines + vignette)",
                    isOn: Binding(
                        get: { model.settings.matrix.crtEnabled },
                        set: { model.settings.matrix.crtEnabled = $0 }
                    )
                )
            }

            Section("Auto-activate") {
                Toggle(
                    "Activate when idle",
                    isOn: Binding(
                        get: { model.settings.autoActivateOnIdle },
                        set: { model.settings.autoActivateOnIdle = $0 }
                    )
                )

                HStack {
                    Text("Idle threshold")
                        .frame(width: 110, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { model.settings.idleThresholdMinutes },
                            set: { model.settings.idleThresholdMinutes = $0 }
                        ),
                        in: 1...30,
                        step: 1
                    )
                    .disabled(!model.settings.autoActivateOnIdle)
                    Text("\(Int(model.settings.idleThresholdMinutes)) min")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }

            Section {
                Text("Live preview behind the window. Changes save automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Hide the form's solid scroll background so Matrix shows through
        // between section cards.
        .scrollContentBackground(.hidden)
        .padding()
    }
}
