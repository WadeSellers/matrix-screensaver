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

    /// Push an externally-changed AppSettings into the model without
    /// triggering the onChange feedback (which would re-call applyAndPersist
    /// in a loop). Called by AppDelegate when a hotkey or other code path
    /// changes settings outside the SwiftUI form.
    func syncFromExternal(_ newSettings: AppSettings) {
        guard model.settings != newSettings else { return }
        let saved = model.onChange
        model.onChange = nil
        model.settings = newSettings
        model.onChange = saved
    }

    /// Pause / resume the live preview render loop. Called by AppDelegate
    /// when the fullscreen session activates so we don't compete with it
    /// on the main thread or GPU. Idempotent.
    func setPreviewActive(_ shouldRun: Bool) {
        guard let preview = previewView else { return }
        if shouldRun {
            preview.startPreviewIfNeeded(settings: model.settings.matrix)
        } else {
            preview.stopPreview()
        }
    }

    func show() {
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            previewView?.startPreviewIfNeeded(settings: model.settings.matrix)
            return
        }

        let frameRect = NSRect(x: 0, y: 0, width: 480, height: 520)

        // Two sibling subviews inside a regular content view:
        //   - preview (layer-hosting, has the CAMetalLayer)
        //   - formHost (NSHostingView with the SwiftUI Form)
        // They share a normal NSView parent so SwiftUI's first-paint logic
        // runs in a "vanilla" context. Nesting NSHostingView inside a
        // layer-hosting parent caused SwiftUI to defer drawing until first
        // user interaction.
        let contentView = NSView(frame: frameRect)

        let preview = SettingsPreviewView(frame: frameRect)
        preview.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(preview)

        let formHost = NSHostingView(rootView: SettingsView(model: model))
        formHost.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(formHost)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: contentView.topAnchor),
            preview.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            formHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            formHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            formHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            formHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
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
        window.contentView = contentView

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

// MARK: - Theme tile / gallery (custom theme picker)

/// SwiftUI's stock `Picker` only renders text in its menu, which is a
/// tragic affordance for an app whose entire identity is six visually
/// distinct color themes. This tile gallery shows each theme's color
/// progression as a vertical gradient — head color at the top fading
/// through near/mid/far trail to black, exactly like a Matrix column.
/// Strips every Button decoration except a subtle press dim. macOS's
/// default + `.plain` styles both render a hover/focus visual that
/// looks identical to our explicit selection chrome, producing the
/// "two tiles selected after I move the mouse" ghost.
private struct ThemeTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

private struct ThemeTile: View {
    let theme: MatrixTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Stops are weighted to mirror an actual Matrix column:
                // a real head "cap" at the top (so head-color identity is
                // visible — white vs pale-green vs amber reads at a
                // glance), a bright near-trail zone, then a long fade
                // through mid → far → black. Even-spaced stops compress
                // the head into a 1-pixel sliver and the tiles all look
                // alike.
                LinearGradient(
                    stops: [
                        .init(color: theme.headColor.color,      location: 0.00),
                        .init(color: theme.headColor.color,      location: 0.14),
                        .init(color: theme.nearTrailColor.color, location: 0.28),
                        .init(color: theme.midTrailColor.color,  location: 0.55),
                        .init(color: theme.farTrailColor.color,  location: 0.88),
                        .init(color: .black,                     location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 48, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )

                Text(theme.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            // Selection state uses BOTH a filled background AND a stroke
            // so it's unambiguous — a stroke alone reads similarly to
            // ambient glow, especially on the leftmost tile.
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(ThemeTileButtonStyle())
        // Suppress macOS's automatic focus ring. Without this, the
        // last-clicked tile retains a focus visual that's
        // indistinguishable from our selection chrome, so two tiles
        // appear selected on hover.
        .focusEffectDisabled()
    }
}

private struct ThemeGallery: View {
    @Binding var selection: MatrixTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(MatrixTheme.allPresets) { theme in
                    ThemeTile(
                        theme: theme,
                        isSelected: theme == selection,
                        action: { selection = theme }
                    )
                }
            }
        }
    }
}

private extension SIMD4 where Scalar == Float {
    /// Treat .x/.y/.z as sRGB-normalised RGB (which is how MatrixTheme
    /// stores them); .w is the unused alignment-padding slot.
    var color: Color {
        Color(red: Double(x), green: Double(y), blue: Double(z))
    }
}

// MARK: - Keyboard shortcut badge

/// Small monospaced pill that displays a keyboard shortcut like a real
/// key cap. Used as a read-only Settings element to surface the global
/// hotkey without implying it's user-editable.
private struct KeyboardShortcutBadge: View {
    let shortcut: String

    var body: some View {
        Text(shortcut)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
    }
}

// MARK: - Settings form

private struct SettingsView: View {
    @Bindable var model: SettingsModel

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v ?? "0.1"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    ThemeGallery(selection: Binding(
                        get: { model.settings.matrix.theme },
                        set: { model.settings.matrix.theme = $0 }
                    ))
                }

                LabeledContent("Speed") {
                    HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(model.settings.matrix.speedMultiplier) },
                            set: { model.settings.matrix.speedMultiplier = Float($0) }
                        ), in: 0.25...3.0)
                        Text(String(format: "%.2f×", model.settings.matrix.speedMultiplier))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            } header: {
                Label("Rendering", systemImage: "paintbrush.fill")
            }

            Section {
                Toggle("Use Matrix as desktop wallpaper", isOn: Binding(
                    get: { model.settings.wallpaperEnabled },
                    set: { model.settings.wallpaperEnabled = $0 }
                ))

                Toggle("Also show on lock screen", isOn: Binding(
                    get: { model.settings.lockScreenEnabled },
                    set: { model.settings.lockScreenEnabled = $0 }
                ))
                .disabled(!model.settings.wallpaperEnabled)
                Text("Lock screen will show a still of your current theme.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Desktop", systemImage: "desktopcomputer")
            }

            Section {
                LabeledContent("Toggle anywhere") {
                    KeyboardShortcutBadge(
                        shortcut: GlobalHotKeyManager.defaultDisplayString
                    )
                }

                Toggle("Activate when idle", isOn: Binding(
                    get: { model.settings.autoActivateOnIdle },
                    set: { model.settings.autoActivateOnIdle = $0 }
                ))

                LabeledContent("Idle threshold") {
                    HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { model.settings.idleThresholdMinutes },
                            set: { model.settings.idleThresholdMinutes = $0 }
                        ), in: 1...30, step: 1)
                        .disabled(!model.settings.autoActivateOnIdle)
                        Text("\(Int(model.settings.idleThresholdMinutes)) min")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            } header: {
                Label("Activation", systemImage: "bolt.fill")
            }

            Section {
                HStack {
                    Text("Changes save automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("v\(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Button("Reset to Defaults") {
                        model.settings = .defaults
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        // Hide the form's solid scroll background so Matrix shows through
        // between section cards.
        .scrollContentBackground(.hidden)
        .padding()
    }
}
