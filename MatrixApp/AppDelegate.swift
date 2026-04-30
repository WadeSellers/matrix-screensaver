import Cocoa
import MatrixCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarItem: MenuBarItem?
    private var session: MatrixSession?
    private var idleMonitor: IdleMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let session = MatrixSession()
        let menuBarItem = MenuBarItem(
            onToggle: { [weak session] in
                session?.toggle()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        session.statusObserver = { [weak menuBarItem, weak self] isActive in
            menuBarItem?.setActive(isActive)
            // Pause the idle monitor while a session is running so we don't
            // re-fire while the user is "still idle" but already seeing
            // Matrix. Reset the edge-trigger when the session ends so the
            // next idle period can activate.
            self?.idleMonitor?.isEnabled = !isActive
            if !isActive {
                self?.idleMonitor?.resetEdgeTrigger()
            }
        }
        self.session = session
        self.menuBarItem = menuBarItem

        // Auto-activate after 5 minutes of HID inactivity. Configurable
        // via the Settings window in V2.1.
        let idleMonitor = IdleMonitor(thresholdSeconds: 5 * 60)
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

    /// Handle `matrix://` URLs. Wired up via CFBundleURLTypes in Info.plist.
    /// Supported actions:
    ///   matrix://activate
    ///   matrix://dismiss
    ///   matrix://toggle
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "matrix" else { continue }
            let action = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch action {
            case "activate":
                session?.activate()
            case "dismiss":
                session?.deactivate()
            case "toggle":
                session?.toggle()
            default:
                NSLog("Matrix: ignoring unknown URL action '\(action)'")
            }
        }
    }
}
