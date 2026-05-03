import Cocoa
import MatrixCore

/// Owns the `NSStatusItem` in the menu bar. The icon is a tiny live
/// Matrix render — a 4×7 grid of theme-colored falling cells animated
/// at 10 fps. Click the icon to toggle activation; right-click (or
/// option-click) opens the context menu.
@MainActor
final class MenuBarItem {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onPreferences: () -> Void
    private var menu: NSMenu = NSMenu()
    private var onQuit: (() -> Void)?

    // MARK: - Live-icon animation state

    /// Per-column head positions (in cell-rows). Floats so heads can
    /// move at sub-row speeds and the rain doesn't visibly tick.
    private var heads: [Float] = []
    /// Per-column fall speeds (rows per tick). Mild variance gives the
    /// icon the same "desynced columns" feel as the fullscreen render.
    private var speeds: [Float] = []
    private var animationTimer: Timer?
    private var theme: MatrixTheme = .classic

    // MARK: - Icon geometry

    /// Status-item visual size. `NSStatusItem.squareLength` resolves to
    /// roughly 22pt at standard menu-bar height; we hard-code the
    /// matching pixel size for the off-screen render.
    private let iconSize: CGFloat = 22
    private let columnCount = 4
    private let rowCount = 7
    /// Tick rate for the icon animation. 10 fps is plenty alive while
    /// using a tiny fraction of the CPU budget the fullscreen render
    /// takes — important since the menu-bar icon runs ALL the time.
    private let tickInterval: TimeInterval = 0.1

    init(
        onToggle: @escaping () -> Void,
        onPreferences: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onPreferences = onPreferences

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = item

        // Click handling: left-click toggles; right-click (or
        // control-click) opens the menu. Distinguished manually via
        // sendAction:to: so we get both behaviours from one button.
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
        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(triggerPreferences),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem(
            title: "About Matrix",
            action: #selector(triggerAbout),
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

        startAnimation()
    }

    /// Update the menu's first item label between Activate / Dismiss
    /// based on whether the fullscreen session is showing. The animated
    /// icon itself is unchanged — it's "always on," giving the menu
    /// bar a constant Matrix presence regardless of activation state.
    func setActive(_ isActive: Bool) {
        if let firstItem = menu.items.first {
            firstItem.title = isActive ? "Dismiss" : "Activate"
        }
    }

    /// Push a new theme into the live icon. Called on launch with the
    /// persisted theme and on every settings change. Takes effect on
    /// the next tick (≤100ms).
    func setTheme(_ newTheme: MatrixTheme) {
        theme = newTheme
    }

    // MARK: - Live icon rendering

    private func startAnimation() {
        // Stagger initial heads so columns don't all spawn at the same
        // row on launch.
        heads = (0..<columnCount).map { _ in Float.random(in: -3 ... 0) }
        speeds = (0..<columnCount).map { _ in Float.random(in: 0.5 ... 1.1) }

        let timer = Timer.scheduledTimer(
            withTimeInterval: tickInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so the animation keeps running while menus are open
        // (the default mode pauses timers during tracking).
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer

        // Render once immediately so the icon isn't blank for the first
        // tick interval after launch.
        tick()
    }

    private func tick() {
        // Advance every column's head; respawn off-screen when one
        // falls past the bottom + a little trail buffer.
        let respawnBeyond = Float(rowCount) + 4
        for i in heads.indices {
            heads[i] += speeds[i]
            if heads[i] > respawnBeyond {
                heads[i] = Float.random(in: -3 ... 0)
                speeds[i] = Float.random(in: 0.5 ... 1.1)
            }
        }
        statusItem.button?.image = renderIcon()
    }

    /// Build a fresh `NSImage` of the current rain state. Done in
    /// CoreGraphics rather than NSImage's drawingHandler closure
    /// because the latter is invoked lazily by AppKit on an unspecified
    /// queue, which violates @MainActor isolation under Swift 6.
    private func renderIcon() -> NSImage {
        // Render at 2× and let NSImage do the downsampling for a crisp
        // result on Retina menu bars.
        let scale: CGFloat = 2
        let pxW = Int(iconSize * scale)
        let pxH = Int(iconSize * scale)

        guard let ctx = CGContext(
            data: nil,
            width: pxW, height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage() }
        ctx.scaleBy(x: scale, y: scale)

        // Tiny "monitor" frame: rounded near-black panel. Keeps the
        // colored rain readable on both light and dark menu bars (the
        // Matrix's own dark colors would disappear against a dark menu
        // bar without this).
        let inset: CGFloat = 0.5
        let frameRect = CGRect(
            x: inset, y: inset,
            width: iconSize - 2 * inset,
            height: iconSize - 2 * inset
        )
        let framePath = CGPath(
            roundedRect: frameRect,
            cornerWidth: 3, cornerHeight: 3,
            transform: nil
        )
        ctx.addPath(framePath)
        ctx.setFillColor(CGColor(gray: 0.06, alpha: 1.0))
        ctx.fillPath()

        // Clip subsequent rain rendering to the rounded frame so cells
        // can't poke past the corners.
        ctx.addPath(framePath)
        ctx.clip()

        // Cell grid sits inside a 2pt margin from the frame edge.
        let pad: CGFloat = 2
        let cellW = (iconSize - 2 * pad) / CGFloat(columnCount)
        let cellH = (iconSize - 2 * pad) / CGFloat(rowCount)

        for col in 0..<columnCount {
            let head = heads[col]
            for row in 0..<rowCount {
                let trailDist = head - Float(row)
                guard let color = colorFor(trailDist: trailDist) else { continue }
                ctx.setFillColor(color)
                // CGContext is Y-up; row 0 at top → high Y.
                let cellRect = CGRect(
                    x: pad + CGFloat(col) * cellW,
                    y: pad + CGFloat(rowCount - 1 - row) * cellH,
                    width: cellW - 0.6,
                    height: cellH - 0.6
                )
                ctx.fill(cellRect)
            }
        }

        guard let cgImage = ctx.makeImage() else { return NSImage() }
        let img = NSImage(
            cgImage: cgImage,
            size: NSSize(width: iconSize, height: iconSize)
        )
        // Full-color icon — explicitly NOT a template so theme colors
        // come through. Most macOS menu bar icons are template
        // (monochrome, system-tinted), but Matrix's identity is its
        // color palette and the per-theme color is the whole point.
        img.isTemplate = false
        return img
    }

    /// Pick a color for a cell `trailDist` rows behind its column's
    /// head. Mirrors the fragment-shader color bands in the main
    /// renderer (head → near → mid → far → off).
    private func colorFor(trailDist: Float) -> CGColor? {
        guard trailDist >= -0.4, trailDist <= Float(rowCount) else { return nil }
        switch trailDist {
        case ..<0.5: return cgColor(theme.headColor)
        case ..<2.0: return cgColor(theme.nearTrailColor)
        case ..<4.0: return cgColor(theme.midTrailColor)
        default:     return cgColor(theme.farTrailColor)
        }
    }

    private func cgColor(_ c: SIMD4<Float>) -> CGColor {
        CGColor(
            red: CGFloat(c.x),
            green: CGFloat(c.y),
            blue: CGFloat(c.z),
            alpha: 1.0
        )
    }

    // MARK: - Click handling

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

    @objc private func triggerPreferences() {
        onPreferences()
    }

    @objc private func triggerAbout() {
        // Bring our accessory app forward briefly so the About panel
        // becomes key. Without activating, it can appear behind other apps.
        NSApp.activate(ignoringOtherApps: true)

        // Custom credits with a clickable GitHub link, rendered through
        // the standard About panel so we still get the system look.
        let credits = NSMutableAttributedString(
            string: "A screen-accurate replica of the digital rain from " +
                    "The Matrix (1999), built in Swift + Metal.\n\n" +
                    "github.com/WadeSellers/matrix-screensaver",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: { () -> NSParagraphStyle in
                    let p = NSMutableParagraphStyle()
                    p.alignment = .center
                    return p
                }()
            ]
        )
        // Make the URL clickable.
        let urlRange = (credits.string as NSString).range(of: "github.com/WadeSellers/matrix-screensaver")
        if urlRange.location != NSNotFound {
            credits.addAttribute(
                .link,
                value: "https://github.com/WadeSellers/matrix-screensaver",
                range: urlRange
            )
        }

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits
        ])
    }
}
