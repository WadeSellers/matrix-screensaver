import Cocoa
import MatrixCore

/// Owns the `NSStatusItem` in the menu bar. The icon is a tiny live
/// Matrix render — a 4×7 grid of theme-colored falling cells animated
/// at 10 fps. Click the icon to toggle activation; right-click (or
/// option-click) opens the context menu.
@MainActor
final class MenuBarItem: NSObject {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onPreferences: () -> Void
    private var onQuit: (() -> Void)?

    /// Anchored popover that replaces the standard NSMenu on right-/
    /// control-click. Hosts a live Matrix render behind custom rows so
    /// the menu visually matches the rest of the app.
    private let popover = NSPopover()
    private let popoverController: MenuPopoverViewController

    // MARK: - Live-icon animation state

    /// Per-column head positions (in cell-rows). Floats so heads can
    /// move at sub-row speeds and the rain doesn't visibly tick.
    private var heads: [Float] = []
    /// Per-column fall speeds (rows per tick). Mild variance gives the
    /// icon the same "desynced columns" feel as the fullscreen render.
    private var speeds: [Float] = []
    /// Per-column, per-row glyph assignment. Regenerated when a column
    /// respawns so each "burst" of rain has fresh characters.
    private var cellGlyphs: [[String]] = []
    private var animationTimer: Timer?
    private var theme: MatrixTheme = .classic

    // MARK: - Icon geometry

    /// Status-item visual size. `NSStatusItem.squareLength` resolves to
    /// roughly 22pt at standard menu-bar height; we hard-code the
    /// matching pixel size for the off-screen render.
    private let iconSize: CGFloat = 22
    /// 3×5 instead of 4×7: less density, but each cell is 6×3.6pt —
    /// finally big enough to render an actual glyph rather than a dot.
    private let columnCount = 3
    private let rowCount = 5
    /// Tick rate for the icon animation. 10 fps is plenty alive while
    /// using a tiny fraction of the CPU budget the fullscreen render
    /// takes — important since the menu-bar icon runs ALL the time.
    private let tickInterval: TimeInterval = 0.1

    /// Curated glyph pool — picked for silhouette variety at tiny
    /// sizes. Mirrored half-width katakana would be authentic but most
    /// of them blur into identical blobs at <5pt; numbers and simple
    /// symbols hold their shape and read as "characters falling" even
    /// when you can't make out the specific character.
    private let glyphPool: [String] = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "+", "*", "=", "<", ">", ":", ".", "-", "/", "|"
    ]

    init(
        onToggle: @escaping () -> Void,
        onPreferences: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onPreferences = onPreferences
        self.onQuit = onQuit

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = item

        // Build the popover controller before super.init so the
        // `let popoverController` constant is satisfied. The About
        // action is owned by the controller itself (as a method) so
        // we don't need a back-reference to `self` here.
        let model = MenuPopoverModel()
        popoverController = MenuPopoverViewController(
            model: model,
            onToggle: onToggle,
            onPreferences: onPreferences,
            onQuit: onQuit
        )

        super.init()

        // Wire the popover's dismiss closure so SwiftUI rows can close
        // the popover after firing their action.
        model.dismiss = { [weak self] in
            self?.popover.performClose(nil)
        }

        // Configure the popover itself.
        popover.contentViewController = popoverController
        popover.behavior = .transient   // dismiss on click outside
        popover.animates = true
        popover.delegate = self

        // Click handling: left-click toggles; right-click (or
        // control-click) opens the popover. Distinguished manually via
        // sendAction:to: so we get both behaviours from one button.
        if let button = item.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        startAnimation()
    }

    /// Update internal active state. The menu row label ("Activate" vs
    /// "Dismiss") follows the popover model directly. The animated icon
    /// itself is unchanged — it's "always on," giving the menu bar a
    /// constant Matrix presence regardless of activation state.
    func setActive(_ isActive: Bool) {
        popoverController.model.isActive = isActive
    }

    /// Push fresh renderer settings into both the animated menu-bar
    /// icon (theme colours) AND the live Matrix render behind the
    /// popover (full settings). Called on launch with the persisted
    /// settings and again on every settings change.
    func applySettings(_ settings: MatrixSettings) {
        theme = settings.theme
        popoverController.applySettings(settings)
    }

    // MARK: - Live icon rendering

    private func startAnimation() {
        // Stagger initial heads so columns don't all spawn at the same
        // row on launch.
        heads = (0..<columnCount).map { _ in Float.random(in: -3 ... 0) }
        speeds = (0..<columnCount).map { _ in Float.random(in: 0.5 ... 1.1) }
        // Initial per-column glyph assignment.
        cellGlyphs = (0..<columnCount).map { _ in
            (0..<rowCount).map { _ in glyphPool.randomElement()! }
        }

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
        // falls past the bottom + a little trail buffer. On respawn,
        // re-roll that column's glyphs so each new "burst" of rain
        // shows a fresh set of characters.
        let respawnBeyond = Float(rowCount) + 4
        for i in heads.indices {
            heads[i] += speeds[i]
            if heads[i] > respawnBeyond {
                heads[i] = Float.random(in: -3 ... 0)
                speeds[i] = Float.random(in: 0.5 ... 1.1)
                cellGlyphs[i] = (0..<rowCount).map { _ in glyphPool.randomElement()! }
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

        // Cell grid sits inside a 1.5pt margin from the frame edge.
        let pad: CGFloat = 1.5
        let cellW = (iconSize - 2 * pad) / CGFloat(columnCount)
        let cellH = (iconSize - 2 * pad) / CGFloat(rowCount)
        // Bold monospaced font sized to the cell. Slightly under cell
        // height so glyphs don't visually touch their neighbors above
        // and below (which would muddy the falling-rain effect).
        let font = NSFont.monospacedSystemFont(
            ofSize: cellH * 0.95,
            weight: .bold
        )

        for col in 0..<columnCount {
            let head = heads[col]
            for row in 0..<rowCount {
                let trailDist = head - Float(row)
                guard let color = nsColorFor(trailDist: trailDist) else { continue }

                // CGContext is Y-up; row 0 at top → high Y.
                let cellRect = CGRect(
                    x: pad + CGFloat(col) * cellW,
                    y: pad + CGFloat(rowCount - 1 - row) * cellH,
                    width: cellW,
                    height: cellH
                )

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                let attrStr = NSAttributedString(
                    string: cellGlyphs[col][row],
                    attributes: attrs
                )
                let line = CTLineCreateWithAttributedString(attrStr)
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                let dx = (cellRect.width - bounds.width) / 2 - bounds.minX
                let dy = (cellRect.height - bounds.height) / 2 - bounds.minY
                ctx.textPosition = CGPoint(
                    x: cellRect.minX + dx,
                    y: cellRect.minY + dy
                )
                CTLineDraw(line, ctx)
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
    private func nsColorFor(trailDist: Float) -> NSColor? {
        guard trailDist >= -0.4, trailDist <= Float(rowCount) else { return nil }
        switch trailDist {
        case ..<0.5: return nsColor(theme.headColor)
        case ..<2.0: return nsColor(theme.nearTrailColor)
        case ..<4.0: return nsColor(theme.midTrailColor)
        default:     return nsColor(theme.farTrailColor)
        }
    }

    private func nsColor(_ c: SIMD4<Float>) -> NSColor {
        NSColor(
            srgbRed: CGFloat(c.x),
            green:   CGFloat(c.y),
            blue:    CGFloat(c.z),
            alpha:   1.0
        )
    }

    // MARK: - Click handling

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            togglePopover()
        } else {
            onToggle()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            // popoverWillShow (delegate method below) starts the live
            // render once the window exists.
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }
}

// MARK: - Popover lifecycle

extension MenuBarItem: NSPopoverDelegate {
    nonisolated func popoverWillShow(_ notification: Notification) {
        // Delegate methods aren't @MainActor-isolated in the SDK, so
        // hop explicitly. AppKit calls these on main in practice.
        Task { @MainActor in
            popoverController.startRender()
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            popoverController.stopRender()
        }
    }
}
