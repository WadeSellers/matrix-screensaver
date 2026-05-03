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
    private var settings: AppSettings = .defaults

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load persisted settings.
        settings = AppSettings(loadedFrom: defaults)

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
            onQuit: {
                NSApp.terminate(nil)
            }
        )

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

    /// Handle `matrix://` URLs.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "matrix" else { continue }
            let action = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch action {
            case "activate":   session?.activate()
            case "dismiss":    session?.deactivate()
            case "toggle":     session?.toggle()
            case "preferences": openPreferences()
            default:
                NSLog("Matrix: ignoring unknown URL action '\(action)'")
            }
        }
    }

    private func openPreferences() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                initial: settings,
                onChange: { [weak self] newSettings in
                    self?.applyAndPersist(newSettings)
                }
            )
        }
        settingsController?.show()
    }

    private func applyAndPersist(_ newSettings: AppSettings) {
        let oldSettings = settings
        settings = newSettings
        newSettings.save(to: defaults)

        // Renderer settings → live propagate to active session AND wallpaper.
        if newSettings.matrix != oldSettings.matrix {
            session?.applySettings(newSettings.matrix)
            wallpaperManager?.applySettings(newSettings.matrix)
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
