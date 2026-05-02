import Cocoa
import MatrixCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarItem: MenuBarItem?
    private var session: MatrixSession?
    private var idleMonitor: IdleMonitor?
    private var settingsController: SettingsWindowController?
    private var settings: AppSettings = .defaults

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load persisted settings.
        settings = AppSettings(loadedFrom: defaults)

        // Wire up the session, status bar, idle monitor, settings.
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
        session.statusObserver = { [weak menuBarItem, weak self] isActive in
            menuBarItem?.setActive(isActive)
            // Pause the idle monitor while a session is running (no point
            // polling) and the settings-window live preview (no point
            // rendering an invisible second copy that competes with the
            // fullscreen session for main-thread / GPU time).
            self?.idleMonitor?.isEnabled = !isActive
            self?.settingsController?.setPreviewActive(!isActive)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.deactivate()
        idleMonitor?.stop()
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
                },
                onRequestKeyboardAccess: { [weak self] in
                    self?.idleMonitor?.requestKeyboardAccessExplicitly()
                }
            )
        }
        settingsController?.show()
    }

    private func applyAndPersist(_ newSettings: AppSettings) {
        let oldSettings = settings
        settings = newSettings
        newSettings.save(to: defaults)

        // Renderer settings → live propagate to active session.
        if newSettings.matrix != oldSettings.matrix {
            session?.applySettings(newSettings.matrix)
        }
        // Idle settings → reconfigure the monitor.
        idleMonitor?.thresholdSeconds = newSettings.idleThresholdMinutes * 60
        idleMonitor?.isEnabled = newSettings.autoActivateOnIdle && session?.isActive == false

        // If the change originated outside the SwiftUI form (e.g. via the
        // B/C hotkeys during a fullscreen session), keep the form in sync
        // without re-triggering this method.
        settingsController?.syncFromExternal(newSettings)
    }
}
