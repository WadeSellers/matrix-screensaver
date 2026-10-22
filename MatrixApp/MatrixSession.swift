import Cocoa
import CoreGraphics
import MatrixCore

/// The activation state machine. Tracks whether Matrix is showing,
/// owns the per-screen windows during an active session, and listens
/// for input that should dismiss it.
///
/// A session can be *locked* (PIN to dismiss). Locked, input raises
/// the keypad instead of dismissing, external dismiss paths (hotkey,
/// URL scheme, menu) are refused, the Dock / menu bar / app switching
/// / force quit are disabled, and only three things end it: the right
/// PIN, Touch ID / the Mac password, or the Mac's own screen lock.
@MainActor
final class MatrixSession {
    /// Called whenever active state changes (true = showing Matrix).
    var statusObserver: ((Bool) -> Void)?
    /// Asked once per activation: should this session be PIN-locked?
    /// AppDelegate answers from settings + the Keychain. Nil = never
    /// lock.
    var lockPolicy: (() -> Bool)?

    private(set) var isActive: Bool = false
    /// True while a PIN is required to dismiss.
    private(set) var isLocked: Bool = false
    /// Unlocked and fading out; input is ignored for the last beat.
    private var isFadingOut: Bool = false
    private var windows: [MatrixWindow] = []
    private var localEventMonitor: Any?
    private var screensChangedObserver: NSObjectProtocol?
    private var screenLockedObserver: NSObjectProtocol?
    private(set) var settings: MatrixSettings = .defaults

    private let lock = PINLockController()
    /// Presentation options in force before we locked, restored on
    /// dismiss. Nil when we haven't touched them.
    private var savedPresentationOptions: NSApplication.PresentationOptions?
    private var cursorHidden = false
    /// Rain windows currently dropped below the Touch ID prompt.
    private var windowsLowered = false
    /// Where the pointer was when we last started watching for a
    /// "real" move. Mouse-moved events closer than ~5pt to this are
    /// the cursor settling, not the user.
    private var pointerOrigin: NSPoint?

    /// Everything that keeps a locked session from being walked
    /// around. AppKit validates the combination and throws an
    /// Objective-C exception (which Swift can't catch) on an illegal
    /// one, so the rules matter:
    /// - `.disableProcessSwitching` needs `.hideDock` (or autoHide).
    /// - `.hideMenuBar` needs `.hideDock`.
    /// - `.disableAppleMenu` needs `.hideMenuBar` (or autoHide).
    /// - `.disableForceQuit`, `.disableSessionTermination` and
    ///   `.disableHideApplication` stand alone.
    private static let lockedPresentationOptions: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableAppleMenu,
        .disableProcessSwitching,
        .disableForceQuit,
        .disableSessionTermination,
        .disableHideApplication
    ]

    init() {
        // The Touch ID button isn't exposed as a normal key event (it's
        // wired straight through Secure Enclave), so we can't see the
        // press. We CAN see what tapping it triggers — a screen lock —
        // and dismiss Matrix on that. Net effect: tap Touch ID → screen
        // locks for a beat → Matrix tears down → finger-unlock lands on
        // a clean desktop. Same flow for ⌃⌘Q (macOS's lock shortcut).
        //
        // This deliberately bypasses the PIN lock: getting back past
        // the Mac's own lock screen already authenticates the user,
        // and it's the one exit that always works, so nobody can be
        // trapped behind a forgotten PIN.
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.lock.resetAttempts()
                self.deactivate()
            }
        }

        lock.onUnlock = { [weak self] in self?.fadeOutAndDeactivate() }
        lock.onKeypadVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            if visible {
                self.showCursor()
            } else {
                self.hideCursor()
                self.pointerOrigin = NSEvent.mouseLocation
            }
        }
        lock.onSystemAuthPrompt = { [weak self] showing in
            self?.setWindowsLowered(showing)
        }
    }

    // No deinit: MatrixSession is a singleton owned by AppDelegate for
    // the lifetime of the process. The distributed-notification observer
    // is cleaned up automatically when the process exits. Swift 6 strict
    // concurrency disallows touching @MainActor state from a non-isolated
    // deinit anyway.

    /// Update the renderer settings used by future activations and the
    /// currently-running session if any. Call from the Settings window
    /// for live-preview behavior.
    func applySettings(_ newSettings: MatrixSettings) {
        settings = newSettings
        for window in windows {
            (window.contentView as? MatrixWindowContentView)?
                .layerHost?.settings = newSettings
        }
        lock.applyTheme(newSettings.theme)
    }

    /// Hotkey / menu / URL toggle. Stopping goes through
    /// `requestDismiss`, so it respects the lock.
    func toggle() {
        if isActive { requestDismiss() } else { activate() }
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        isFadingOut = false
        pointerOrigin = nil

        // Bring our app forward so the screensaver-level windows actually
        // become key and receive input. With LSUIElement=true we're an
        // accessory app, so without an explicit activate we may stay
        // backgrounded and the cursor-hide call below is a no-op.
        NSApp.activate(ignoringOtherApps: true)

        buildWindows()
        hideCursor()
        installInputMonitor()
        observeScreenChanges()

        // Decide the lock once, up front. The Keychain record is the
        // source of truth for the PIN length; no record = no lock,
        // whatever the settings say.
        if lockPolicy?() == true, let record = PINStore.loadRecord() {
            engageLock(pinLength: record.length)
        }
        statusObserver?(true)
    }

    /// A dismiss request from outside the rain: the hotkey, the menu,
    /// `fallingcode://dismiss`. Unlocked, it dismisses. Locked, it is
    /// refused — the hotkey and menu raise the keypad instead, which
    /// is the closest useful thing; a URL is just ignored — so no
    /// script or shortcut can lift the curtain without the PIN.
    func requestDismiss(raiseKeypadIfLocked: Bool = true) {
        guard isActive else { return }
        if isLocked {
            if raiseKeypadIfLocked, !isFadingOut {
                lock.raiseKeypad(on: screenUnderPointer())
            }
            return
        }
        deactivate()
    }

    /// Unconditional teardown. Only for paths that have already
    /// established it's the owner (right PIN, Touch ID / password, the
    /// Mac's screen lock) or that aren't locked to begin with — never
    /// wire an external trigger straight to this; use `requestDismiss`.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        isFadingOut = false

        lock.disengage()
        disengageLockChrome()

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let observer = screensChangedObserver {
            NotificationCenter.default.removeObserver(observer)
            screensChangedObserver = nil
        }
        teardownWindows()
        showCursor()
        statusObserver?(false)
    }

    // MARK: - Windows

    private func buildWindows() {
        // One window per screen.
        for screen in NSScreen.screens {
            let window = MatrixWindow(screen: screen)
            if let content = window.contentView as? MatrixWindowContentView {
                content.install(on: screen, settings: settings)
            }
            if windowsLowered { window.level = Self.loweredLevel }
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
    }

    private func teardownWindows() {
        for window in windows {
            (window.contentView as? MatrixWindowContentView)?.teardown()
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    /// Window level for the rain while the system's Touch ID /
    /// password prompt is up. Measured on macOS 26 (CGWindowList): the
    /// prompt is a `coreautha` window at layer 1000 — exactly
    /// `.screenSaver` — so a same-level rain window can bury it. One
    /// level below keeps the prompt on top while the rain still covers
    /// everything an ordinary app (and the Dock, menu bar, floating
    /// panels) can put on screen.
    private static let loweredLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)

    /// Drop the rain just under the system auth prompt (see
    /// `loweredLevel`) or put it back.
    private func setWindowsLowered(_ lowered: Bool) {
        windowsLowered = lowered
        for window in windows {
            window.level = lowered ? Self.loweredLevel : .screenSaver
            if !lowered { window.orderFrontRegardless() }
        }
    }

    /// Unlocked: fade the rain out instead of cutting to the desktop.
    private func fadeOutAndDeactivate() {
        guard isActive, !isFadingOut else { return }
        isFadingOut = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.45
            for window in windows {
                window.isOpaque = false
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isFadingOut else { return }
                self.deactivate()
            }
        })
    }

    // MARK: - Lock chrome

    private func engageLock(pinLength: Int) {
        isLocked = true
        if savedPresentationOptions == nil {
            savedPresentationOptions = NSApp.presentationOptions
        }
        NSApp.presentationOptions = Self.lockedPresentationOptions
        lock.engage(pinLength: pinLength, theme: settings.theme)
    }

    private func disengageLockChrome() {
        isLocked = false
        windowsLowered = false
        if let saved = savedPresentationOptions {
            NSApp.presentationOptions = saved
            savedPresentationOptions = nil
        }
    }

    // MARK: - Cursor

    // Counted on both sides (NSCursor and CGDisplay keep hide counts),
    // so every hide must be matched by exactly one show. The flag
    // makes these idempotent.

    private func hideCursor() {
        guard !cursorHidden else { return }
        cursorHidden = true
        // Aggressive cursor hide. NSCursor.hide() only works while the app
        // is foreground; CGDisplayHideCursor goes through WindowServer and
        // is reliable for fullscreen takeover scenarios. Belt-and-suspenders.
        CGDisplayHideCursor(CGMainDisplayID())
        NSCursor.hide()
    }

    private func showCursor() {
        guard cursorHidden else { return }
        cursorHidden = false
        CGDisplayShowCursor(CGMainDisplayID())
        NSCursor.unhide()
    }

    // MARK: - Input

    private func installInputMonitor() {
        // Local monitor: catches events while our windows are key.
        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved,
            .scrollWheel,
            .magnify, .swipe
        ]
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            // Local monitors run on the main thread.
            guard let self else { return event }
            if self.isFadingOut {
                // Last beat of an unlock: swallow keys so a stray
                // trailing digit doesn't land in another app.
                return event.type == .keyDown ? nil : event
            }
            return self.isLocked ? self.handleLocked(event) : self.handleUnlocked(event)
        }
    }

    /// Unlocked session: any real input dismisses.
    private func handleUnlocked(_ event: NSEvent) -> NSEvent? {
        if event.type == .mouseMoved, !pointerMovedMeaningfully() { return event }
        deactivate()
        return event
    }

    /// Locked session: input raises (or feeds) the keypad. Keys are
    /// always swallowed so no shortcut reaches AppKit; clicks pass
    /// through only to the keypad's own buttons.
    private func handleLocked(_ event: NSEvent) -> NSEvent? {
        // While the system auth prompt is up our windows sit under it;
        // keep their clicks and keys from doing anything.
        if lock.isAuthenticating {
            return event.type == .mouseMoved ? event : nil
        }

        let screen = screenUnderPointer()
        switch event.type {
        case .keyDown:
            lock.handleKeyDown(event, screen: screen)
            return nil

        case .mouseMoved:
            if lock.isKeypadVisible {
                lock.pointerMoved(to: screen)
            } else if pointerMovedMeaningfully() {
                lock.raiseKeypad(on: screen)
            }
            return event

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if lock.isKeypadVisible && lock.ownsWindow(event.window) {
                lock.noteActivity()
                return event
            }
            lock.raiseKeypad(on: screen)
            return nil

        default:
            // Scroll, magnify, swipe.
            lock.raiseKeypad(on: screen)
            return nil
        }
    }

    /// Mouse-moved jitter filter — the cursor settling into position
    /// when the windows first appear isn't the user. True once the
    /// pointer is ~5pt from where we started watching.
    private func pointerMovedMeaningfully() -> Bool {
        let now = NSEvent.mouseLocation
        guard let origin = pointerOrigin else {
            pointerOrigin = now
            return false
        }
        let dx = now.x - origin.x
        let dy = now.y - origin.y
        return dx * dx + dy * dy >= 25
    }

    private func screenUnderPointer() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - Screen changes

    private func observeScreenChanges() {
        // If a display is plugged in or unplugged mid-session, re-build
        // the window set so we cover the new layout. Rebuilding only the
        // windows (not deactivate + activate) keeps a locked session
        // locked — a monitor hot-plug must never be a way past the PIN.
        screensChangedObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive, !self.isFadingOut else { return }
                self.teardownWindows()
                self.buildWindows()
                if self.lock.isKeypadVisible {
                    self.lock.raiseKeypad(on: self.screenUnderPointer())
                }
            }
        }
    }
}
