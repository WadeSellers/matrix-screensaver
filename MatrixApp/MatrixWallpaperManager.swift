import Cocoa
import MatrixCore
import os.log

private let log = OSLog(subsystem: "com.wadesellers.matrix", category: "wallpaper")

/// Owns the per-screen `MatrixWallpaperWindow` instances. Mirrors
/// `MatrixSession` in shape, but runs continuously while enabled rather
/// than activating on demand.
///
/// Pauses (tears down its windows) while a fullscreen Matrix session is
/// active — the screensaver covers the wallpaper anyway, so rendering a
/// hidden second copy at 60 fps is wasted GPU. Recreates on session end.
@MainActor
final class MatrixWallpaperManager {
    private(set) var isEnabled: Bool = false
    private(set) var isPausedForSession: Bool = false
    private(set) var settings: MatrixSettings = .defaults

    private var windows: [MatrixWallpaperWindow] = []
    private var screensChangedObserver: NSObjectProtocol?

    /// Owns the static-image side of "wallpaper mode" — the PNG that
    /// macOS uses for the lock screen and any moment our live render
    /// isn't covering the desktop (app launch, app crash, etc.).
    private let stillManager = SystemWallpaperManager()

    /// Turn the wallpaper on or off. Idempotent.
    func setEnabled(_ enable: Bool) {
        guard enable != isEnabled else { return }
        isEnabled = enable
        os_log("wallpaper %{public}@",
               log: log, type: .info, enable ? "ENABLED" : "DISABLED")
        if enable {
            observeScreenChanges()
            startWindowsIfPossible()
            // Set a per-screen Matrix still as the system wallpaper so
            // the lock screen and any not-rendering-yet moments show
            // Matrix instead of the user's old wallpaper.
            stillManager.installMatrixStill(settings: settings)
        } else {
            stopObservingScreenChanges()
            tearDownWindows()
            // Put the user's original wallpaper back.
            stillManager.restorePreviousWallpapers()
        }
    }

    /// Push fresh renderer settings to the live wallpaper render. If the
    /// theme changed and we're enabled, regenerate the system still so
    /// the lock screen matches the new theme.
    func applySettings(_ newSettings: MatrixSettings) {
        let themeChanged = newSettings.theme != settings.theme
        settings = newSettings
        for window in windows {
            (window.contentView as? MatrixWindowContentView)?
                .layerHost?.settings = newSettings
        }
        if isEnabled && themeChanged {
            stillManager.installMatrixStill(settings: newSettings)
        }
    }

    /// Notify us when a fullscreen Matrix session starts/ends. We tear
    /// down our windows during the session and rebuild them afterwards.
    func setSessionActive(_ active: Bool) {
        guard isEnabled else { return }
        isPausedForSession = active
        if active {
            tearDownWindows()
        } else {
            startWindowsIfPossible()
        }
    }

    // MARK: - Window lifecycle

    private func startWindowsIfPossible() {
        guard isEnabled, !isPausedForSession, windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = MatrixWallpaperWindow(screen: screen)
            if let content = window.contentView as? MatrixWindowContentView {
                content.install(on: screen, settings: settings)
            }
            // orderFront, NOT makeKeyAndOrderFront — we never become key.
            window.orderFront(nil)
            windows.append(window)
        }
        os_log("wallpaper started across %{public}d screen(s)",
               log: log, type: .info, windows.count)
    }

    private func tearDownWindows() {
        guard !windows.isEmpty else { return }
        for window in windows {
            (window.contentView as? MatrixWindowContentView)?.teardown()
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        os_log("wallpaper torn down", log: log, type: .info)
    }

    // MARK: - Screen-change handling

    private func observeScreenChanges() {
        screensChangedObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabled, !self.isPausedForSession else { return }
                // Rebuild from scratch: simplest correct way to handle a
                // monitor plug/unplug or resolution change.
                self.tearDownWindows()
                self.startWindowsIfPossible()
            }
        }
    }

    private func stopObservingScreenChanges() {
        if let observer = screensChangedObserver {
            NotificationCenter.default.removeObserver(observer)
            screensChangedObserver = nil
        }
    }
}
