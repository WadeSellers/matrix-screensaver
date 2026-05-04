import AppKit
import CoreImage
import Metal
import MatrixCore
import os.log

private let log = OSLog(subsystem: "com.wadesellers.cipherfall", category: "wallpaper-still")

/// Manages the macOS system wallpaper setting (the static image shown
/// behind the desktop and on the lock screen) so we can install a
/// rendered Matrix still that matches the user's current theme.
///
/// Lifecycle:
/// - `installMatrixStill(settings:)` — captures the user's current
///   wallpaper URLs (once, on first install), renders a per-screen PNG
///   into Application Support, sets each as the system wallpaper.
/// - `restorePreviousWallpapers()` — reverts each screen to its
///   captured original. Call this on disable (or app uninstall — but we
///   can't hook that, so disable is the user's escape hatch).
///
/// Originals are persisted in `UserDefaults` keyed by `CGDirectDisplayID`
/// so multi-monitor restore lines up correctly across launches even if
/// the user rearranges displays in System Settings.
@MainActor
final class SystemWallpaperManager {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let originals = "matrix.previousWallpaperURLs"
        // Marker so we know the install has been done and don't
        // re-capture our own image as the "original" on subsequent
        // installs (e.g. theme change → regenerate).
        static let isInstalled = "matrix.wallpaperStillInstalled"
    }

    /// Render and set a Matrix still per `NSScreen`. Captures the
    /// user's current wallpapers on first call so they can be restored.
    func installMatrixStill(settings: MatrixSettings) {
        captureOriginalsIfNeeded()
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MatrixRenderer(device: device) else {
            os_log("could not create Metal device / renderer; skipping still",
                   log: log, type: .error)
            return
        }

        let dir = stillDirectory()
        // Unique-per-call filename. macOS caches the wallpaper image keyed
        // by URL, so writing fresh bytes to the SAME URL doesn't trigger a
        // re-read — the lock screen would keep showing the previous theme.
        // A new URL each time forces a refresh; we sweep stale files at
        // the end so App Support doesn't accumulate.
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        for screen in NSScreen.screens {
            let id = screen.displayIDString
            let url = dir.appendingPathComponent("matrix-\(id)-\(timestamp).png")
            do {
                try renderStill(renderer: renderer,
                                settings: settings,
                                screen: screen,
                                device: device,
                                to: url)
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                deleteStaleStills(for: id, except: url)
                os_log("installed Matrix still on screen %{public}@ → %{public}@",
                       log: log, type: .info, id, url.lastPathComponent)
            } catch {
                os_log("install failed on screen %{public}@: %{public}@",
                       log: log, type: .error, id, String(describing: error))
            }
        }

        defaults.set(true, forKey: Key.isInstalled)
    }

    /// Remove any `matrix-<id>-*.png` for the given screen except the
    /// one we just wrote. Keeps Application Support tidy across many
    /// theme changes.
    private func deleteStaleStills(for displayID: String, except keep: URL) {
        let dir = stillDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }
        let prefix = "matrix-\(displayID)-"
        for url in contents where url.lastPathComponent.hasPrefix(prefix) && url != keep {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Revert each screen to the URL we captured before installing.
    /// Best-effort: if we can't find an original for a screen, that
    /// screen is left as-is (still showing our Matrix PNG, which the
    /// user can clear in System Settings → Wallpaper).
    func restorePreviousWallpapers() {
        guard let originals = defaults.dictionary(forKey: Key.originals) as? [String: String] else {
            os_log("no captured originals to restore", log: log, type: .info)
            return
        }
        for screen in NSScreen.screens {
            let id = screen.displayIDString
            guard let urlString = originals[id], let url = URL(string: urlString) else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                os_log("restored screen %{public}@ to %{public}@",
                       log: log, type: .info, id, urlString)
            } catch {
                os_log("restore failed on screen %{public}@: %{public}@",
                       log: log, type: .error, id, String(describing: error))
            }
        }
        defaults.removeObject(forKey: Key.originals)
        defaults.removeObject(forKey: Key.isInstalled)
    }

    // MARK: - Originals capture

    private func captureOriginalsIfNeeded() {
        // Skip if we've already installed; otherwise we'd capture our
        // own Matrix PNG as the "original" on the second install.
        guard !defaults.bool(forKey: Key.isInstalled) else { return }
        var captured: [String: String] = [:]
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                captured[screen.displayIDString] = url.absoluteString
            }
        }
        defaults.set(captured, forKey: Key.originals)
        os_log("captured %{public}d original wallpaper URL(s)",
               log: log, type: .info, captured.count)
    }

    // MARK: - Rendering

    private func renderStill(
        renderer: MatrixRenderer,
        settings: MatrixSettings,
        screen: NSScreen,
        device: MTLDevice,
        to url: URL
    ) throws {
        let scale = screen.backingScaleFactor
        let pxW = max(1, Int(screen.frame.size.width  * scale))
        let pxH = max(1, Int(screen.frame.size.height * scale))

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: pxW, height: pxH,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: desc) else {
            throw NSError(domain: "MatrixWallpaper", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "couldn't allocate target texture"])
        }

        renderer.snapshot(into: target, settings: settings, warmupSeconds: 3.0)

        // CIImage wraps Metal textures Y-flipped relative to image
        // conventions; `.downMirrored` brings PNG output back upright.
        guard let ci = CIImage(mtlTexture: target, options: nil) else {
            throw NSError(domain: "MatrixWallpaper", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "CIImage(mtlTexture:) returned nil"])
        }
        let oriented = ci.oriented(.downMirrored)

        let ctx = CIContext(mtlDevice: device)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        try ctx.writePNGRepresentation(of: oriented,
                                       to: url,
                                       format: .RGBA8,
                                       colorSpace: colorSpace)
    }

    // MARK: - Paths

    private func stillDirectory() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Matrix", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - NSScreen helpers

private extension NSScreen {
    /// Stable per-display identifier (`CGDirectDisplayID`) as a string,
    /// suitable for use as a UserDefaults dictionary key.
    var displayIDString: String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let n = deviceDescription[key] as? NSNumber {
            return String(n.uint32Value)
        }
        return "unknown"
    }
}
