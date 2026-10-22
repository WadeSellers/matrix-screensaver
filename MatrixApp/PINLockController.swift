import Cocoa
import SwiftUI
import LocalAuthentication
import MatrixCore

/// Runs the PIN keypad for a locked `MatrixSession`: raises it over
/// the rain on whichever screen the input came from, takes digits
/// from the keyboard or the on-screen pad, checks them against the
/// Keychain hash, throttles wrong guesses, and offers Touch ID /
/// the Mac password as the forgot-PIN escape hatch.
///
/// The session stays in charge of the rain windows, the cursor and
/// the presentation options; this class only owns the overlay window
/// and reports back through the three callbacks.
@MainActor
final class PINLockController {
    /// The owner proved themselves (right PIN or system auth). The
    /// session should fade out and deactivate.
    var onUnlock: (() -> Void)?
    /// The keypad came up (true) or went away (false). The session
    /// shows the cursor only while it's up.
    var onKeypadVisibilityChanged: ((Bool) -> Void)?
    /// The Touch ID / password prompt is about to appear (true) or
    /// failed and went away (false). The session drops its rain
    /// windows below the prompt and puts them back.
    var onSystemAuthPrompt: ((Bool) -> Void)?

    private(set) var isEngaged = false
    private(set) var isKeypadVisible = false
    private(set) var isAuthenticating = false
    private var isUnlocking = false

    /// How long the keypad lingers with no input before fading.
    private static let idleHideDelay: TimeInterval = 8

    private let state = PINKeypadState(palette: PINPalette(theme: .classic))
    private var overlay: PINOverlayWindow?
    private var overlayScreen: NSScreen?
    private var attempts = PINAttemptPolicy()
    private var pinLength = PINRules.minLength
    private var hideTimer: Timer?
    private var cooldownTimer: Timer?
    private var verifyTask: Task<Void, Never>?
    private var authContext: LAContext?
    /// Bumped on every show/hide so a slow fade-out completion can't
    /// order out a keypad that was raised again mid-fade.
    private var overlayGeneration = 0

    init() {
        state.onDigit = { [weak self] digit in self?.enterDigit(digit) }
        state.onDelete = { [weak self] in self?.deleteDigit() }
        state.onSystemAuth = { [weak self] in self?.beginSystemAuth() }
    }

    // MARK: - Lifecycle

    /// Start guarding a session. The keypad stays hidden until the
    /// first input; the rain is the screensaver, the keypad is not.
    func engage(pinLength: Int, theme: MatrixTheme) {
        self.pinLength = pinLength
        isEngaged = true
        isUnlocking = false
        state.palette = PINPalette(theme: theme)
        state.systemAuthLabel = Self.systemAuthLabel()
        state.entry.configure(length: pinLength)
        refreshCooldown(resetCaption: true)
    }

    /// Stop guarding: tear down the overlay and timers. Called by the
    /// session on every deactivate, locked or not.
    func disengage() {
        isEngaged = false
        isUnlocking = false
        verifyTask?.cancel()
        verifyTask = nil
        hideTimer?.invalidate()
        hideTimer = nil
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        authContext?.invalidate()
        authContext = nil
        isAuthenticating = false
        overlayGeneration += 1
        overlay?.orderOut(nil)
        overlay?.close()
        overlay = nil
        overlayScreen = nil
        state.entry.stopAnimating()
        state.entry.clear()
        if isKeypadVisible {
            isKeypadVisible = false
            onKeypadVisibilityChanged?(false)
        }
    }

    /// Forget wrong guesses. Called whenever the Mac itself vouches
    /// for the user (its screen lock), on top of our own unlock paths.
    func resetAttempts() {
        attempts.reset()
        refreshCooldown(resetCaption: true)
    }

    func applyTheme(_ theme: MatrixTheme) {
        state.palette = PINPalette(theme: theme)
    }

    func ownsWindow(_ window: NSWindow?) -> Bool {
        guard let window, let overlay else { return false }
        return window === overlay
    }

    // MARK: - Keypad visibility

    /// Show the keypad on `screen`, or move it there if it's already
    /// up elsewhere. Entry in progress survives a move.
    func raiseKeypad(on screen: NSScreen) {
        guard isEngaged, !isUnlocking, !isAuthenticating else { return }
        noteActivity()

        let window = overlay ?? makeOverlay()
        if overlayScreen != screen || window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
            overlayScreen = screen
        }

        guard !isKeypadVisible else { return }
        isKeypadVisible = true
        overlayGeneration += 1
        state.entry.clear()
        refreshCooldown(resetCaption: true)
        state.entry.startAnimating()

        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1
        }
        onKeypadVisibilityChanged?(true)
    }

    /// Fade the keypad away and drop any half-typed digits.
    func hideKeypad() {
        guard isKeypadVisible, !isAuthenticating, !isUnlocking else { return }
        isKeypadVisible = false
        hideTimer?.invalidate()
        hideTimer = nil
        verifyTask?.cancel()
        fadeOutOverlay(duration: 0.35)
        onKeypadVisibilityChanged?(false)
    }

    /// Pointer moved while the keypad is up: follow it across screens
    /// and keep the keypad alive.
    func pointerMoved(to screen: NSScreen) {
        guard isKeypadVisible, !isAuthenticating else { return }
        if screen != overlayScreen { raiseKeypad(on: screen) } else { noteActivity() }
    }

    /// Restart the idle-hide countdown.
    func noteActivity() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.idleHideDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideKeypad() }
        }
    }

    // MARK: - Keyboard

    /// Route a key press. The session swallows every key while locked
    /// (so ⌘Q, ⌘H and friends never reach AppKit); this decides what,
    /// if anything, it means.
    func handleKeyDown(_ event: NSEvent, screen: NSScreen) {
        guard isEngaged, !isUnlocking, !isAuthenticating else { return }

        let escape: UInt16 = 53
        if event.keyCode == escape {
            hideKeypad()
            return
        }

        // Any other key raises the keypad; a digit also counts, so the
        // user can just start typing at the rain.
        raiseKeypad(on: overlayScreen ?? screen)

        // Command/Control chords are never PIN input.
        if !event.modifierFlags.intersection([.command, .control]).isEmpty { return }

        switch event.keyCode {
        case 51, 117:       // Delete, Forward Delete
            deleteDigit()
        case 36, 76:        // Return, keypad Enter
            // Full rows auto-submit, so Return only ever sees a
            // partial entry. A nudge, not a strike.
            if state.entry.enteredCount > 0 { state.entry.nudge() }
        default:
            // Top-row and numpad digits both arrive as "0"–"9".
            if let c = event.charactersIgnoringModifiers?.first, PINRules.isDigit(c) {
                enterDigit(c)
            }
        }
    }

    // MARK: - Entry

    private func enterDigit(_ digit: Character) {
        guard isEngaged, !isUnlocking, !isAuthenticating else { return }
        noteActivity()
        guard !attempts.isCoolingDown() else {
            state.entry.nudge()
            return
        }
        guard state.entry.append(digit) else { return }
        if state.entry.isFull { submit() }
    }

    private func deleteDigit() {
        noteActivity()
        state.entry.deleteLast()
    }

    private func submit() {
        let candidate = state.entry.takePIN()
        verifyTask?.cancel()
        verifyTask = Task { @MainActor [weak self] in
            // PBKDF2 is ~40ms; keep it off the main thread so the
            // last slot's lock-in pulse doesn't hitch.
            let ok = await Task.detached(priority: .userInitiated) {
                PINStore.verify(candidate)
            }.value
            guard let self, !Task.isCancelled, self.isEngaged else { return }
            if ok { self.succeed() } else { self.failAttempt() }
        }
    }

    private func succeed() {
        isUnlocking = true
        attempts.reset()
        hideTimer?.invalidate()
        state.caption = "unlocked"
        state.entry.succeed()
        // A beat on the bright row before the curtain lifts.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self, self.isEngaged else { return }
            self.fadeOutOverlay(duration: 0.4)
            self.onUnlock?()
        }
    }

    private func failAttempt() {
        let wait = attempts.recordFailure()
        let left = PINAttemptPolicy.freeAttempts - attempts.failures
        if wait > 0 {
            state.caption = "too many tries"
        } else if left <= 2 {
            state.caption = left == 1 ? "wrong pin · 1 try left" : "wrong pin · \(left) tries left"
        } else {
            state.caption = "wrong pin"
        }
        state.entry.fail { [weak self] in
            self?.refreshCooldown()
        }
    }

    // MARK: - Cooldown

    /// Sync the countdown display with the attempt policy, and keep a
    /// one-second ticker running for as long as a cooldown lasts.
    /// `resetCaption` puts the caption back to its resting "enter pin"
    /// (fresh keypad); otherwise a "wrong pin" line is left standing.
    private func refreshCooldown(resetCaption: Bool = false) {
        let remaining = attempts.remainingCooldown()
        if remaining > 0 {
            state.entry.setCountdown(seconds: Int(remaining.rounded(.up)))
            state.caption = "too many tries"
            if cooldownTimer == nil {
                cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshCooldown() }
                }
            }
            return
        }
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        let wasCounting = !state.entry.countdown.isEmpty
        state.entry.setCountdown(seconds: nil)
        if wasCounting || resetCaption {
            state.caption = "enter pin"
        }
    }

    // MARK: - Touch ID / password

    private static func systemAuthLabel() -> String {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
           context.biometryType == .touchID {
            return "Use Touch ID or password"
        }
        return "Use your Mac password"
    }

    /// Forgot-PIN path: hand off to LocalAuthentication. The system
    /// prompt is another process's window at `.screenSaver` level —
    /// the same level as the rain, and below this keypad — so the
    /// session drops the rain one level under it for the duration and
    /// we take the keypad off screen entirely.
    /// On failure or cancel everything goes back exactly as it was.
    private func beginSystemAuth() {
        guard isEngaged, !isAuthenticating, !isUnlocking else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            state.caption = "not available"
            return
        }

        isAuthenticating = true
        authContext = context
        hideTimer?.invalidate()
        state.systemAuthEnabled = false
        overlay?.orderOut(nil)
        onSystemAuthPrompt?(true)

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "dismiss the Falling Code screensaver"
        ) { [weak self] success, _ in
            Task { @MainActor in
                self?.finishSystemAuth(success: success)
            }
        }
    }

    private func finishSystemAuth(success: Bool) {
        guard isAuthenticating else { return }
        isAuthenticating = false
        authContext = nil
        state.systemAuthEnabled = true

        if success {
            isUnlocking = true
            attempts.reset()
            onUnlock?()
            return
        }

        // The prompt took key focus (and may have made us inactive,
        // which lifts our presentation options); take both back.
        NSApp.activate(ignoringOtherApps: true)
        onSystemAuthPrompt?(false)
        if isEngaged, isKeypadVisible, let overlay {
            overlay.alphaValue = 1
            overlay.orderFrontRegardless()
            overlay.makeKey()
            noteActivity()
        }
    }

    // MARK: - Overlay window

    private func makeOverlay() -> PINOverlayWindow {
        let window = PINOverlayWindow()
        let host = NSHostingView(rootView: PINKeypadView(state: state))
        // Fixed to the screen; SwiftUI's ideal size must not drive it.
        host.sizingOptions = []
        window.contentView = host
        overlay = window
        return window
    }

    private func fadeOutOverlay(duration: TimeInterval) {
        guard let window = overlay else { return }
        overlayGeneration += 1
        let generation = overlayGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.overlayGeneration == generation else { return }
                window.orderOut(nil)
                self.state.entry.stopAnimating()
                self.state.entry.clear()
                self.refreshCooldown(resetCaption: true)
            }
        })
    }
}

/// Transparent full-screen window one level above the rain. Full
/// screen (rather than keypad-sized) so the soft dark pool behind the
/// keypad can feather out into the rain without a visible edge.
final class PINOverlayWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
