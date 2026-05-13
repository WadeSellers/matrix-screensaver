import Cocoa
import SwiftUI

/// Hosts the floating "Send Feedback" window. Mirrors
/// `OnboardingSheetController` in shape — `NSPanel` with a transparent
/// title bar at `.floating` level, draggable by background, fresh
/// `FeedbackManager` per presentation.
///
/// Owned by `AppDelegate`. Presented in response to a tap on the
/// Feedback card in the Support tab.
@MainActor
final class FeedbackController: NSObject {
    private var panel: NSPanel?
    private weak var manager: FeedbackManager?
    private var panelDelegate: FeedbackPanelDelegate?

    /// Strong self-reference held while the panel is on-screen so the
    /// caller doesn't have to retain the controller. Cleared on dismiss.
    private static var live: FeedbackController?

    func present() {
        if let existing = panel {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let frameRect = NSRect(x: 0, y: 0, width: 500, height: 620)

        // Fresh manager every time — the form should never inherit
        // state from a previous (cancelled or successful) submission.
        let manager = FeedbackManager()
        self.manager = manager

        let onClose: @MainActor () -> Void = { [weak self] in
            self?.dismiss()
        }

        let rootView = FeedbackView(manager: manager, onClose: onClose)
        let host = NSHostingView(rootView: rootView)
        host.frame = frameRect
        // Don't let SwiftUI's intrinsic content size shove the panel
        // around as the form's height changes (e.g. when the error
        // message appears). Panel stays at our fixed size.
        host.sizingOptions = []

        // NSPanel with a titled, closable, HUD-styled appearance —
        // same recipe as OnboardingSheetController. Floating level so
        // it sits above the Preferences window.
        let panel = NSPanel(
            contentRect: frameRect,
            styleMask: [.titled, .closable, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Send Feedback"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = host

        let delegate = FeedbackPanelDelegate { [weak self] in
            self?.handleClose()
        }
        panel.delegate = delegate

        self.panel = panel
        self.panelDelegate = delegate

        panel.center()
        // LSUIElement apps don't activate via the normal path because
        // they have no Dock icon. Temporarily promote to .regular so
        // the panel can become key and visibly front; restore
        // .accessory on dismiss.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        FeedbackController.live = self
    }

    private func dismiss() {
        panel?.close()
        // delegate's windowWillClose runs handleClose() to release.
    }

    private func handleClose() {
        panel?.orderOut(nil)
        panel = nil
        manager = nil
        // Restore .accessory so we don't leave a Dock icon hanging
        // around after the feedback window closes.
        NSApp.setActivationPolicy(.accessory)
        FeedbackController.live = nil
    }
}

/// Forwards close events to the controller.
private final class FeedbackPanelDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
