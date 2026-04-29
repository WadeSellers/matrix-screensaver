import Cocoa
import Metal
import MatrixCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("Metal not supported on this system. Exiting.")
            NSApp.terminate(nil)
            return
        }

        spawnWindow()
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func spawnNewWindow(_ sender: Any?) {
        spawnWindow()
    }

    private func spawnWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Matrix SaverTest #\(windows.count + 1) — MatrixCore v\(MatrixCore.version)"
        window.center()

        // Each window gets its own MatrixView with its own MatrixRenderer —
        // mirrors the real screensaver's per-NSScreen instance model.
        let device = MTLCreateSystemDefaultDevice()
        let view = MatrixView(frame: frame, device: device)
        window.contentView = view

        // Cascade additional windows so they don't stack identically.
        if let last = windows.last {
            window.setFrameTopLeftPoint(NSPoint(
                x: last.frame.origin.x + 30,
                y: last.frame.origin.y + last.frame.size.height - 30
            ))
        }

        window.makeKeyAndOrderFront(nil)
        windows.append(window)
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

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(
            title: "New Window",
            action: #selector(spawnNewWindow(_:)),
            keyEquivalent: "n"
        ))
        fileMenuItem.submenu = fileMenu

        NSApp.mainMenu = mainMenu
    }
}
