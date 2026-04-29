import Cocoa
import Metal
import MatrixCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var matrixView: MatrixView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal not supported on this system. Exiting.")
            NSApp.terminate(nil)
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Matrix SaverTest — MatrixCore v\(MatrixCore.version)"
        window.center()

        matrixView = MatrixView(frame: frame, device: device)
        window.contentView = matrixView

        buildMenu()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "Quit Matrix SaverTest",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
