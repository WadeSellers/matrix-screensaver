import Cocoa
import MatrixCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarItem: MenuBarItem?
    private var session: MatrixSession?
    private var idleMonitor: IdleMonitor?
    private var wallpaperManager: MatrixWallpaperManager?
    private let systemWallpaperManager = SystemWallpaperManager()
    private var hotKeyManager: GlobalHotKeyManager?
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingSheetController?
    // Owns the three "Support development" Consumable IAPs. Constructed
    // at launch so its Transaction.updates listener is live from the
    // first run-loop tick (StoreKit 2 requirement: finish every
    // transaction promptly or Apple will redeliver it forever).
    private let tipJar = TipJarManager()
    // Fullscreen "Decode" thank-you Easter egg fired after a verified
    // tip purchase. Lives at the app level (not Preferences) because
    // the animation needs to take over every display.
    private let thankYouController = ThankYouController()
    private var settings: AppSettings = .defaults

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load persisted settings.
        settings = AppSettings(loadedFrom: defaults)

        // Hook the tip-jar success path into the fullscreen "Decode"
        // thank-you takeover. Set after AppDelegate's properties are
        // initialized so `[weak self]` is meaningful.
        tipJar.onPurchaseSucceeded = { [weak self] product in
            self?.thankYouController.present(for: product)
        }

        // Wire up the session, status bar, idle monitor, settings, wallpaper.
        let session = MatrixSession()
        session.applySettings(settings.matrix)

        let menuBarItem = MenuBarItem(
            onToggle: { [weak session] in
                session?.toggle()
            },
            onPreferences: { [weak self] in
                self?.openPreferences()
            },
            onMeetTheMaker: { [weak self] in
                self?.openPreferences(jumpToTab: .support)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        // Seed the live menu-bar icon AND the popover preview with the
        // persisted settings so neither briefly animates in Matrix
        // Classic before catching up.
        menuBarItem.applySettings(settings.matrix)

        // Live-window wallpaper manager. Static-image side is handled
        // separately via systemWallpaperManager so the two toggles are
        // independent under the hood.
        let wallpaperManager = MatrixWallpaperManager()
        wallpaperManager.applySettings(settings.matrix)
        wallpaperManager.setEnabled(settings.wallpaperEnabled)
        self.wallpaperManager = wallpaperManager

        // System wallpaper still — install on launch if the persisted
        // sub-toggle is on. This regenerates fresh PNGs every launch, so
        // the lock screen always tracks the most recent theme even if
        // the user changed wallpapers in System Settings while we were
        // closed.
        if settings.lockScreenStillActive {
            systemWallpaperManager.installMatrixStill(settings: settings.matrix)
        }

        session.statusObserver = { [weak menuBarItem, weak self] isActive in
            menuBarItem?.setActive(isActive)
            // Pause the idle monitor while a session is running (no point
            // polling) and the settings-window live preview (no point
            // rendering an invisible second copy that competes with the
            // fullscreen session for main-thread / GPU time). Same logic
            // for the wallpaper — it's invisible under the session.
            self?.idleMonitor?.isEnabled = !isActive
            self?.settingsController?.setPreviewActive(!isActive)
            self?.wallpaperManager?.setSessionActive(isActive)
            if !isActive {
                self?.idleMonitor?.resetEdgeTrigger()
            }
        }
        self.session = session
        self.menuBarItem = menuBarItem

        let idleMonitor = IdleMonitor(thresholdSeconds: settings.idleThresholdMinutes * 60)
        idleMonitor.isEnabled = settings.autoActivateOnIdle
        idleMonitor.onIdle = { [weak session] in
            session?.activate()
        }
        idleMonitor.start()
        self.idleMonitor = idleMonitor

        // Global hotkey: ⌃⌥⌘M from anywhere → toggle Matrix.
        let hotKeyManager = GlobalHotKeyManager()
        hotKeyManager.onPressed = { [weak session] in
            session?.toggle()
        }
        hotKeyManager.register()
        self.hotKeyManager = hotKeyManager

        // First-launch onboarding. Deferred via main.async so the menu
        // bar icon installs first — the sheet visually points at it.
        DispatchQueue.main.async { [weak self] in
            self?.presentOnboardingIfNeeded()
        }
    }

    /// Present the first-launch onboarding sheet exactly once. Persists
    /// a UserDefaults flag on dismiss so subsequent launches skip it.
    /// The onboarding's first page is the red/green pill choice, which
    /// reaches back here via `applyPillChoice` to seed live settings.
    private func presentOnboardingIfNeeded() {
        guard !OnboardingSheetController.hasSeenOnboarding(defaults) else { return }
        let controller = OnboardingSheetController(
            defaults: defaults,
            onPillChosen: { [weak self] pill in
                self?.applyPillChoice(pill)
            }
        )
        onboardingController = controller
        controller.present()
    }

    /// Map a first-launch pill choice onto the app's actual settings.
    /// Red pill = maximum-immersion preset; blue pill = leave the user
    /// in the lightweight "just a menu-bar icon" mode. Applied through
    /// `applyAndPersist` so live managers (wallpaper window, system
    /// wallpaper still, idle monitor) reconfigure in the same frame.
    private func applyPillChoice(_ pill: OnboardingPillChoice) {
        var next = settings
        switch pill {
        case .red:
            next.wallpaperEnabled = true
            next.lockScreenEnabled = true
            next.autoActivateOnIdle = true
            next.idleThresholdMinutes = 5
        case .blue:
            next.wallpaperEnabled = false
            next.lockScreenEnabled = false
            next.autoActivateOnIdle = false
        }
        applyAndPersist(next)
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.deactivate()
        idleMonitor?.stop()
        wallpaperManager?.setEnabled(false)
        hotKeyManager?.unregister()
        // Note: we do NOT restore the wallpaper on quit. The user may
        // want our still to survive across app restarts (it's their
        // chosen wallpaper). Restore only happens on explicit toggle-off.
    }

    /// Handle `fallingcode://` URLs.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "fallingcode" else { continue }
            let action = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch action {
            case "activate":   session?.activate()
            case "dismiss":    session?.deactivate()
            case "toggle":     session?.toggle()
            case "preferences": openPreferences()
            default:
                NSLog("Falling Code: ignoring unknown URL action '\(action)'")
            }
        }
    }

    /// Open the Preferences window. Pass `jumpToTab` to land on a
    /// specific tab — used by the "Meet the maker" popover entry to
    /// open straight to Support.
    private func openPreferences(jumpToTab: SettingsTab? = nil) {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                initial: settings,
                tipJar: tipJar,
                onChange: { [weak self] newSettings in
                    self?.applyAndPersist(newSettings)
                }
            )
        }
        settingsController?.show(jumpToTab: jumpToTab)
    }

    private func applyAndPersist(_ newSettings: AppSettings) {
        let oldSettings = settings
        settings = newSettings
        newSettings.save(to: defaults)

        // Renderer settings → live propagate to active session, wallpaper,
        // AND the menu-bar (animated icon + popover preview).
        if newSettings.matrix != oldSettings.matrix {
            session?.applySettings(newSettings.matrix)
            wallpaperManager?.applySettings(newSettings.matrix)
            menuBarItem?.applySettings(newSettings.matrix)
        }
        // Idle settings → reconfigure the monitor.
        idleMonitor?.thresholdSeconds = newSettings.idleThresholdMinutes * 60
        idleMonitor?.isEnabled = newSettings.autoActivateOnIdle && session?.isActive == false

        // Wallpaper toggle → enable / disable the live-window manager.
        if newSettings.wallpaperEnabled != oldSettings.wallpaperEnabled {
            wallpaperManager?.setEnabled(newSettings.wallpaperEnabled)
        }

        // System-wallpaper still: gated on BOTH toggles. Cascade is built
        // into AppSettings.lockScreenStillActive (= wallpaperEnabled &&
        // lockScreenEnabled), so turning wallpaper off automatically
        // reverts the still without losing the user's lockScreenEnabled
        // preference.
        let wasActive = oldSettings.lockScreenStillActive
        let isActive  = newSettings.lockScreenStillActive
        let themeChanged = newSettings.matrix.theme != oldSettings.matrix.theme

        if isActive && (!wasActive || themeChanged) {
            // Either we're newly active, or the theme changed while
            // active — render and install fresh PNGs. (The unique
            // timestamped filename inside the manager bypasses the
            // wallpaper URL cache so the lock screen actually refreshes.)
            systemWallpaperManager.installMatrixStill(settings: newSettings.matrix)
        } else if wasActive && !isActive {
            // Newly inactive — put the user's original wallpaper back.
            systemWallpaperManager.restorePreviousWallpapers()
        }

        // If the change originated outside the SwiftUI form (e.g. via the
        // B/C hotkeys during a fullscreen session), keep the form in sync
        // without re-triggering this method.
        settingsController?.syncFromExternal(newSettings)
    }
}
