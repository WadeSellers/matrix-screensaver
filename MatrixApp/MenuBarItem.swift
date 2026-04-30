import Cocoa

/// Owns the `NSStatusItem` in the menu bar. Click toggles activation;
/// right-click (or option-click) opens a small context menu with Quit.
@MainActor
final class MenuBarItem {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // SF Symbol that reads as Matrix-y. "rectangle.split.3x1" is a
            // close stand-in for "rain columns"; we'll swap for a custom
            // template image once we have an app icon designed.
            button.image = NSImage(
                systemSymbolName: "rectangle.split.3x1",
                accessibilityDescription: "Matrix"
            )
            button.image?.isTemplate = true
            button.target = nil
            button.action = nil
        }
        self.statusItem = item

        // Click handling: left-click toggles; right-click (or control-click)
        // opens the menu. We do this manually with sendAction:to: so we can
        // distinguish event types.
        if let button = item.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Activate",
            action: #selector(triggerToggle),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(
            title: "Quit Matrix",
            action: #selector(triggerQuit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        for menuItem in menu.items where menuItem.target == nil {
            menuItem.target = self
        }
        self.menu = menu
        self.onQuit = onQuit
    }

    private var menu: NSMenu = NSMenu()
    private var onQuit: (() -> Void)?

    func setActive(_ isActive: Bool) {
        guard let button = statusItem.button else { return }
        let symbolName = isActive ? "rectangle.split.3x1.fill" : "rectangle.split.3x1"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Matrix"
        )
        button.image?.isTemplate = true

        // Update menu's first item to reflect state.
        if let firstItem = menu.items.first {
            firstItem.title = isActive ? "Dismiss" : "Activate"
        }
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onToggle()
        }
    }

    @objc private func triggerToggle() {
        onToggle()
    }

    @objc private func triggerQuit() {
        onQuit?()
    }
}
