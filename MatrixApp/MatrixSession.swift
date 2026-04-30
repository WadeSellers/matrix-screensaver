import Cocoa
import CoreGraphics
import MatrixCore

/// The activation state machine. Tracks whether Matrix is showing,
/// owns the per-screen windows during an active session, and listens
/// for input that should dismiss it.
@MainActor
final class MatrixSession {
    /// Called whenever active state changes (true = showing Matrix).
    var statusObserver: ((Bool) -> Void)?

    private(set) var isActive: Bool = false
    private var windows: [MatrixWindow] = []
    private var localEventMonitor: Any?
    private var screensChangedObserver: NSObjectProtocol?
    private var settings: MatrixSettings = .defaults

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Bring our app forward so the screensaver-level windows actually
        // become key and receive input. With LSUIElement=true we're an
        // accessory app, so without an explicit activate we may stay
        // backgrounded and the cursor-hide call below is a no-op.
        NSApp.activate(ignoringOtherApps: true)

        // One window per screen.
        for screen in NSScreen.screens {
            let window = MatrixWindow(screen: screen)
            if let content = window.contentView as? MatrixWindowContentView {
                content.install(on: screen, settings: settings)
            }
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        // Aggressive cursor hide. NSCursor.hide() only works while the app
        // is foreground; CGDisplayHideCursor goes through WindowServer and
        // is reliable for fullscreen takeover scenarios. Belt-and-suspenders.
        CGDisplayHideCursor(CGMainDisplayID())
        NSCursor.hide()
        installInputDismissMonitor()
        observeScreenChanges()
        statusObserver?(true)
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let observer = screensChangedObserver {
            NotificationCenter.default.removeObserver(observer)
            screensChangedObserver = nil
        }
        for window in windows {
            (window.contentView as? MatrixWindowContentView)?.teardown()
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        CGDisplayShowCursor(CGMainDisplayID())
        NSCursor.unhide()
        statusObserver?(false)
    }

    // MARK: - Input dismiss

    private func installInputDismissMonitor() {
        // Local monitor: catches events while our windows are key.
        // Any user input dismisses Matrix.
        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved,
            .scrollWheel,
            .magnify, .swipe
        ]
        // Track initial cursor position; require a small delta to dismiss
        // on mouseMoved (otherwise we self-dismiss the moment the cursor
        // jumps under our windows).
        var startLocation: NSPoint?
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.type == .mouseMoved {
                if startLocation == nil {
                    startLocation = NSEvent.mouseLocation
                    return event
                }
                let now = NSEvent.mouseLocation
                let dx = now.x - (startLocation?.x ?? now.x)
                let dy = now.y - (startLocation?.y ?? now.y)
                if dx * dx + dy * dy < 25 {
                    // <5pt motion — ignore (cursor settling).
                    return event
                }
            }
            self.deactivate()
            return event
        }
    }

    // MARK: - Screen changes

    private func observeScreenChanges() {
        // If a display is plugged in or unplugged mid-session, re-build
        // the window set so we cover the new layout.
        screensChangedObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            // Tear down and reactivate to pick up the new screen layout.
            self.deactivate()
            self.activate()
        }
    }
}
