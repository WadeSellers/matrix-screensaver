import Cocoa
import MatrixCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarItem: MenuBarItem?
    private var session: MatrixSession?

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
        session.statusObserver = { [weak menuBarItem] isActive in
            menuBarItem?.setActive(isActive)
        }
        self.session = session
        self.menuBarItem = menuBarItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.deactivate()
    }
}
