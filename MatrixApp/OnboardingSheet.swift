import Cocoa
import SwiftUI
import Metal
import MatrixCore

// MARK: - Controller

/// Hosts the first-launch onboarding sheet. One-shot — present once,
/// flip the UserDefaults flag on dismiss, never show again.
///
/// Visual: an `NSPanel` (titled, transparent title bar, hud-like) with a
/// live Matrix render behind a darkening gradient and the SwiftUI
/// onboarding pages on top. Same layer-hosting pattern as
/// `MenuPopoverPreviewView` and `SettingsPreviewView` so the live
/// render plays nicely with SwiftUI without first-paint deferral bugs.
@MainActor
final class OnboardingSheetController: NSObject {
    /// UserDefaults key. Persists across launches.
    static let hasSeenOnboardingKey = "falling-code.hasSeenOnboarding"

    /// Convenience: read the flag.
    static func hasSeenOnboarding(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hasSeenOnboardingKey)
    }

    /// Convenience: write the flag.
    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: hasSeenOnboardingKey)
    }

    private var panel: NSPanel?
    private weak var previewView: OnboardingPreviewView?
    private var panelDelegate: OnboardingPanelDelegate?
    private let defaults: UserDefaults

    /// Strong self-reference held while the panel is on-screen so the
    /// caller doesn't have to retain the controller. Cleared on dismiss.
    private static var live: OnboardingSheetController?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    /// Build and show the panel centered on the main screen. Holds a
    /// strong reference to `self` until dismissed.
    func present() {
        // Already showing? Just bring forward.
        if let existing = panel {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let frameRect = NSRect(x: 0, y: 0, width: 520, height: 480)

        // Two sibling subviews inside a regular content view — same
        // pattern as SettingsWindowController so SwiftUI's first-paint
        // logic runs in a vanilla container instead of inside a
        // layer-hosted parent (which causes deferred drawing).
        let contentView = NSView(frame: frameRect)

        let preview = OnboardingPreviewView(frame: frameRect)
        preview.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(preview)

        let onDismiss: @MainActor () -> Void = { [weak self] in
            self?.dismiss()
        }

        let pages = OnboardingRootView(onFinish: onDismiss)
        let host = NSHostingView(rootView: pages)
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: contentView.topAnchor),
            preview.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            host.topAnchor.constraint(equalTo: contentView.topAnchor),
            host.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        // NSPanel rather than NSWindow — proper auxiliary/sheet feel.
        // .titled keeps a draggable title bar; transparent so the rain
        // extends underneath. .hudWindow gives the dark vibrancy that
        // matches the rest of the app. Crucially we do NOT pass
        // .nonactivatingPanel — for an LSUIElement app, the panel
        // needs to be able to activate (and we explicitly call
        // NSApp.activate below) or it'll appear behind whatever was
        // frontmost when the user launched us.
        let panel = NSPanel(
            contentRect: frameRect,
            styleMask: [.titled, .closable, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Falling Code"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = contentView
        panel.level = .floating

        // Tear-down on close (red-button or programmatic). Treats close
        // as a dismiss, sets the flag, and releases self.
        let delegate = OnboardingPanelDelegate { [weak self] in
            self?.handleClose()
        }
        panel.delegate = delegate

        self.panel = panel
        self.previewView = preview
        self.panelDelegate = delegate

        panel.center()
        // LSUIElement apps don't activate via the normal path because
        // they have no Dock icon. Temporarily promote to .regular so
        // the panel can become key and visibly front. Restore .accessory
        // on dismiss so we don't keep a Dock icon around.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // Hold a strong self-reference until dismissed.
        OnboardingSheetController.live = self

        // Wait one runloop tick so window.screen is populated, then
        // start the preview render.
        DispatchQueue.main.async { [weak preview] in
            preview?.startPreviewIfNeeded(settings: .defaults)
        }
    }

    /// User clicked Skip / Get Started. Persist the flag and close.
    private func dismiss() {
        OnboardingSheetController.markSeen(defaults)
        previewView?.stopPreview()
        panel?.close()
        // delegate's windowWillClose will run handleClose to release.
    }

    /// Called from the panel delegate on any close path (button, red x,
    /// programmatic). Idempotent.
    private func handleClose() {
        // If the user closed via the red traffic-light button without
        // clicking Skip / Get Started, still mark as seen — we don't
        // want a half-finished flow re-prompting on next launch.
        OnboardingSheetController.markSeen(defaults)
        previewView?.stopPreview()
        // Restore .accessory (LSUIElement) so we don't leave a Dock
        // icon hanging around after the onboarding closes.
        NSApp.setActivationPolicy(.accessory)
        OnboardingSheetController.live = nil
    }
}

/// Panel delegate that just forwards close events to the controller.
private final class OnboardingPanelDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - Live Matrix preview behind the sheet

/// Layer-hosted view that owns the onboarding sheet's live `MatrixLayerHost`.
/// Mirrors `SettingsPreviewView` and `MenuPopoverPreviewView` exactly —
/// `self.layer` is assigned BEFORE `wantsLayer = true` so AppKit treats
/// us as layer-hosting (not layer-backed) and doesn't trample the
/// CAMetalLayer with redraws.
final class OnboardingPreviewView: NSView {
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

// MARK: - SwiftUI root

/// The whole onboarding flow. Three pages controlled by a `currentPage`
/// state — manual transitions rather than `TabView(.page)` so we can
/// drive the per-page advance/dismiss buttons cleanly.
private struct OnboardingRootView: View {
    let onFinish: () -> Void

    @State private var currentPage: Int = 0

    private let totalPages = 3

    var body: some View {
        ZStack {
            // Darkening overlay so the live Matrix backdrop reads as
            // *atmosphere* rather than competing with the body copy.
            // Vertical gradient: nearly opaque top + bottom (where
            // headline and buttons sit), slightly lighter middle.
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.78), location: 0.00),
                    .init(color: Color.black.opacity(0.55), location: 0.40),
                    .init(color: Color.black.opacity(0.55), location: 0.60),
                    .init(color: Color.black.opacity(0.85), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top bar — Skip lives here, top-right.
                topBar

                // Page content. Switch on currentPage so we can use
                // distinct subviews per page (each owns its own visual).
                Group {
                    switch currentPage {
                    case 0: WelcomePage()
                    case 1: HowToUsePage()
                    default: GetStartedPage()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                // .id forces SwiftUI to treat each page as a distinct
                // view so the .transition actually plays.
                .id(currentPage)

                // Page dots + advance button.
                bottomBar
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: Subviews

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: onFinish) {
                Text("Skip")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        // Match the height the .titled style would have reserved so
        // body content sits below the would-be title-bar area.
        .frame(height: 28)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack {
            // Page dots — three round indicators showing position.
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage
                              ? Color.white.opacity(0.85)
                              : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            Button(action: advance) {
                Text(currentPage == totalPages - 1 ? "Get Started" : "Next →")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            // The signature Matrix near-trail green —
                            // hand-tuned to be readable as a button
                            // without screaming "neon highlighter".
                            .fill(Color(red: 0.40, green: 0.95, blue: 0.55))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 16)
    }

    private func advance() {
        if currentPage >= totalPages - 1 {
            onFinish()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage += 1
        }
    }
}

// MARK: - Pages

/// Shared container so each page's headline / body / visual live in a
/// consistent vertical layout.
private struct PageScaffold<Visual: View, Content: View>: View {
    let headline: String
    @ViewBuilder var visual: () -> Visual
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            visual()

            Text(headline)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.85), radius: 2, x: 0, y: 0)
                .multilineTextAlignment(.center)

            content()
                .frame(maxWidth: 420)

            Spacer(minLength: 0)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        PageScaffold(
            headline: "Welcome to Falling Code",
            visual: {
                // Menubar-shaped visual with arrow pointing at it,
                // hinting where the icon will live after dismiss.
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: 140, height: 80)

                    VStack(spacing: 6) {
                        Image(systemName: "menubar.rectangle")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Color(red: 0.40, green: 0.95, blue: 0.55))
                            .shadow(
                                color: Color(red: 0.40, green: 0.95, blue: 0.55).opacity(0.6),
                                radius: 6, x: 0, y: 0
                            )
                        Text("Look for the icon up here")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .frame(height: 100)
            },
            content: {
                Text("The digital rain from *The Matrix* (1999), brought to your Mac as a live wallpaper, lock-screen still, screensaver replacement, and on-demand fullscreen takeover.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.9), radius: 1.5, x: 0, y: 0)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        )
    }
}

private struct HowToUsePage: View {
    var body: some View {
        PageScaffold(
            headline: "How to use it",
            visual: {
                OnboardingKeyboardShortcutBadge(shortcut: "⌃⌥⌘M")
                    .frame(height: 64)
            },
            content: {
                // Markdown bullets — SwiftUI parses **bold** and `code`
                // inline, which avoids the fragile Text+Text+Text
                // concatenation that broke page 2 layout.
                VStack(alignment: .leading, spacing: 12) {
                    bullet(number: 1, markdown:
                        "**Left-click** the icon in your menu bar to open the menu (themes, preferences, etc.)")
                    bullet(number: 2, markdown:
                        "**Right-click** or `⌃⌥⌘M` to summon fullscreen rain instantly — works from any app")
                    bullet(number: 3, markdown:
                        "**Any input** dismisses fullscreen — mouse, scroll, keypress, gesture")
                }
            }
        )
    }

    @ViewBuilder
    private func bullet(number: Int, markdown: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.40, green: 0.95, blue: 0.55))
                .frame(width: 18, alignment: .trailing)
            Text(.init(markdown))
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.9), radius: 1.5)
                .lineSpacing(2)
        }
    }
}

private struct GetStartedPage: View {
    var body: some View {
        PageScaffold(
            headline: "You're set",
            visual: {
                // Themed sparkle / preferences glyph, no text label
                // needed — body copy below names the destination.
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .frame(width: 96, height: 96)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(Color(red: 0.40, green: 0.95, blue: 0.55))
                        .shadow(
                            color: Color(red: 0.40, green: 0.95, blue: 0.55).opacity(0.6),
                            radius: 6, x: 0, y: 0
                        )
                }
                .frame(height: 100)
            },
            content: {
                (
                    Text("Open ")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                    + Text("Preferences")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    + Text(" from the menu bar icon to switch between five color themes, set Falling Code as your live wallpaper, or tune the speed.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                )
                .shadow(color: .black.opacity(0.9), radius: 1.5, x: 0, y: 0)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
        )
    }
}

// MARK: - Reusable key-cap visual (mirrors `KeyCap` in SettingsWindowController)

/// One physical-looking key cap. Same recipe as the private `KeyCap` in
/// SettingsWindowController — duplicated here rather than promoted to a
/// shared file because that file's KeyCap is `private` and the brief
/// asked us not to refactor existing code.
private struct OnboardingKeyCap: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
    }
}

private struct OnboardingKeyboardShortcutBadge: View {
    let keys: [String]

    init(shortcut: String) {
        self.keys = shortcut.map { String($0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                VStack(spacing: 4) {
                    OnboardingKeyCap(symbol: key)
                    Text(Self.name(for: key))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private static func name(for symbol: String) -> String {
        switch symbol {
        case "⌃": return "Control"
        case "⌥": return "Option"
        case "⌘": return "Command"
        case "⇧": return "Shift"
        default:  return symbol
        }
    }
}
