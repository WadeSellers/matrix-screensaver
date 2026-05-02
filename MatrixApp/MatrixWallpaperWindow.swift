import Cocoa
import MatrixCore

/// Borderless, mouse-transparent window pinned at desktop wallpaper level
/// to host a live Matrix render in place of the system wallpaper. One
/// instance per `NSScreen`. Owned by `MatrixWallpaperManager`.
///
/// Window-level math: `CGWindowLevelForKey(.desktopWindow)` is the level
/// the system uses for its own wallpaper image — below the Finder's
/// desktop-icon layer, above… well, nothing. Sitting here means we look
/// like a wallpaper to every other window on the system, including
/// Stage Manager, Mission Control, and ⌘`-cycled apps (none of which
/// see us, by design).
final class MatrixWallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow))
        )
        self.isOpaque = true
        self.hasShadow = false
        self.backgroundColor = .black
        // Appear on every Space and stay put when the user switches Spaces.
        // `ignoresCycle` keeps us out of ⌘` and Mission Control thumbnails.
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Mouse events pass straight through to the desktop / icons / app
        // windows above us. Indistinguishable from a static wallpaper.
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false
        self.setFrame(screen.frame, display: false)

        // Reuse the layer-hosting content view from the screensaver path:
        // same Metal renderer, same install/teardown lifecycle.
        let content = MatrixWindowContentView(frame: screen.frame)
        self.contentView = content
    }

    // A wallpaper must never take key/main status — that would steal
    // focus from real app windows the user is trying to use.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
