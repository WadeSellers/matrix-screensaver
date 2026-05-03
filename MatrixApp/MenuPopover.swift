import Cocoa
import SwiftUI
import MatrixCore
import Metal

// MARK: - Model

/// State the popover view observes. Mutating these from the controller
/// triggers a SwiftUI update inside the popover.
@MainActor
@Observable
final class MenuPopoverModel {
    var settings: MatrixSettings = .defaults
    var isActive: Bool = false
    /// Closure the SwiftUI rows call to dismiss the popover after a
    /// menu item is chosen. Set by `MenuBarItem` after construction.
    var dismiss: (() -> Void)?
}

// MARK: - View controller

/// Hosts the Matrix-render preview *behind* the SwiftUI menu rows.
/// Same two-sibling layout as `SettingsWindowController`: a layer-hosted
/// preview view plus an `NSHostingView`, both filling the popover.
@MainActor
final class MenuPopoverViewController: NSViewController {
    let model: MenuPopoverModel
    private weak var previewView: MenuPopoverPreviewView?

    private let onToggle: () -> Void
    private let onPreferences: () -> Void
    private let onQuit: () -> Void

    init(
        model: MenuPopoverModel,
        onToggle: @escaping () -> Void,
        onPreferences: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.model = model
        self.onToggle = onToggle
        self.onPreferences = onPreferences
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let frameSize = NSSize(width: 230, height: 200)
        let container = NSView(frame: NSRect(origin: .zero, size: frameSize))

        let preview = MenuPopoverPreviewView(frame: container.bounds)
        preview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(preview)
        previewView = preview

        let menuView = MenuPopoverView(
            model: model,
            onToggle: onToggle,
            onPreferences: onPreferences,
            onAbout: { [weak self] in self?.showAboutPanel() },
            onQuit: onQuit
        )
        let host = NSHostingView(rootView: menuView)
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        view = container
    }

    /// Spin up the live Matrix render behind the menu. Call from
    /// `popoverWillShow` so the GPU only burns cycles when the popover
    /// is visible.
    func startRender() {
        previewView?.startPreviewIfNeeded(settings: model.settings)
    }

    /// Tear down the render when the popover closes — hidden popovers
    /// shouldn't render at 60 fps.
    func stopRender() {
        previewView?.stopPreview()
    }

    /// Push fresh settings into both the SwiftUI model and the live
    /// render. Called from `MenuBarItem.applySettings` whenever the
    /// user changes a theme/speed in the main Settings window.
    func applySettings(_ settings: MatrixSettings) {
        model.settings = settings
        previewView?.layerHost?.settings = settings
    }

    /// Show macOS's standard About panel with our custom credits.
    /// Lives on the controller so the SwiftUI menu can call it via a
    /// `[weak self]` thunk created at view-load time — sidesteps the
    /// ordering problem of needing `MenuBarItem.self` before its
    /// `super.init` completes.
    fileprivate func showAboutPanel() {
        // Bring our accessory app forward so the panel becomes key,
        // otherwise it can appear behind other apps.
        NSApp.activate(ignoringOtherApps: true)

        let credits = NSMutableAttributedString(
            string: "A screen-accurate replica of the digital rain from " +
                    "The Matrix (1999), built in Swift + Metal.\n\n" +
                    "github.com/WadeSellers/matrix-screensaver",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: { () -> NSParagraphStyle in
                    let p = NSMutableParagraphStyle()
                    p.alignment = .center
                    return p
                }()
            ]
        )
        let urlRange = (credits.string as NSString)
            .range(of: "github.com/WadeSellers/matrix-screensaver")
        if urlRange.location != NSNotFound {
            credits.addAttribute(
                .link,
                value: "https://github.com/WadeSellers/matrix-screensaver",
                range: urlRange
            )
        }
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

// MARK: - Preview view (Matrix renderer behind the menu)

/// Layer-hosted view that owns the popover's `MatrixLayerHost`. Same
/// pattern as `SettingsPreviewView` and `MatrixWindowContentView` —
/// `self.layer` assigned BEFORE `wantsLayer = true` so AppKit treats
/// this as layer-hosting (not layer-backed) and doesn't trample our
/// Metal layer with redraws.
final class MenuPopoverPreviewView: NSView {
    private(set) var layerHost: MatrixLayerHost?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let host = CALayer()
        host.backgroundColor = NSColor.black.cgColor
        host.frame = self.bounds
        self.layer = host
        self.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

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

// MARK: - SwiftUI menu

private struct MenuPopoverView: View {
    @Bindable var model: MenuPopoverModel
    let onToggle: () -> Void
    let onPreferences: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuPopoverRow(
                label: model.isActive ? "Dismiss Matrix" : "Activate Matrix",
                shortcut: GlobalHotKeyManager.defaultDisplayString
            ) {
                onToggle()
                model.dismiss?()
            }

            menuDivider

            MenuPopoverRow(label: "Preferences…") {
                onPreferences()
                model.dismiss?()
            }
            MenuPopoverRow(label: "About Matrix") {
                onAbout()
                model.dismiss?()
            }

            menuDivider

            MenuPopoverRow(label: "Quit Matrix", shortcut: "⌘Q") {
                onQuit()
            }
        }
        .padding(.vertical, 6)
    }

    /// Faint horizontal line between menu groups. A real `Divider()`
    /// renders too dark/opaque against the Matrix backdrop and reads
    /// as a hard separator; this is more like the airy spacers you see
    /// in modern macOS popovers.
    private var menuDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

private struct MenuPopoverRow: View {
    let label: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(.white)
                    // Subtle shadow so text stays readable against any
                    // theme colour bleeding through from the rain.
                    .shadow(color: .black.opacity(0.85), radius: 1.5, x: 0, y: 0)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        // Per-character spacing so ⌃⌥⌘M doesn't smush
                        // into a single illegible glyph.
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.9), radius: 1.5, x: 0, y: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered
                    ? Color.white.opacity(0.18)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // Same focus-ring suppression as the theme tiles — without it
        // the last-clicked row keeps a system focus indicator that
        // looks like a hover state long after the cursor moved away.
        .focusEffectDisabled()
    }
}
