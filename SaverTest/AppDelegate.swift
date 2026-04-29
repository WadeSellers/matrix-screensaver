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

    @objc func toggleCRT(_ sender: Any?) {
        forEachRenderer { $0.settings.crtEnabled.toggle() }
    }

    @objc func toggleBloom(_ sender: Any?) {
        forEachRenderer { $0.settings.bloomEnabled.toggle() }
    }

    @objc func slower(_ sender: Any?) {
        forEachRenderer { $0.settings.speedMultiplier = max(0.25, $0.settings.speedMultiplier - 0.25) }
    }

    @objc func faster(_ sender: Any?) {
        forEachRenderer { $0.settings.speedMultiplier = min(3.0, $0.settings.speedMultiplier + 0.25) }
    }

    private func forEachRenderer(_ apply: (MatrixRenderer) -> Void) {
        for window in windows {
            if let view = window.contentView as? MatrixView, let r = view.renderer {
                apply(r)
            }
        }
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

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(
            title: "Toggle CRT Mode",
            action: #selector(toggleCRT(_:)),
            keyEquivalent: "t"
        ))
        viewMenu.addItem(NSMenuItem(
            title: "Toggle Bloom",
            action: #selector(toggleBloom(_:)),
            keyEquivalent: "b"
        ))
        viewMenu.addItem(NSMenuItem.separator())
        let slowerItem = NSMenuItem(
            title: "Slower",
            action: #selector(slower(_:)),
            keyEquivalent: "-"
        )
        slowerItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(slowerItem)
        let fasterItem = NSMenuItem(
            title: "Faster",
            action: #selector(faster(_:)),
            keyEquivalent: "="
        )
        fasterItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(fasterItem)
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }
}
