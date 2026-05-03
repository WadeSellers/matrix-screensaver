import Foundation
import MatrixCore

/// App-level settings: extends `MatrixSettings` (renderer params) with
/// app-specific concerns like the idle-timer threshold and whether
/// auto-activate is enabled at all.
struct AppSettings: Equatable, Sendable {
    var matrix: MatrixSettings
    var autoActivateOnIdle: Bool
    var idleThresholdMinutes: Double  // double so the slider can be smooth
    var wallpaperEnabled: Bool
    /// Sub-option of wallpaper: when both are on, we install a per-screen
    /// Matrix still as the macOS system wallpaper so the lock screen
    /// shows Matrix instead of the user's previous wallpaper. When
    /// wallpaper is off, this preference is preserved but has no effect.
    var lockScreenEnabled: Bool

    /// True iff the static Matrix PNG should currently be installed as
    /// the system wallpaper. Both toggles must be on.
    var lockScreenStillActive: Bool { wallpaperEnabled && lockScreenEnabled }

    static let defaults = AppSettings(
        matrix: .defaults,
        autoActivateOnIdle: true,
        idleThresholdMinutes: 5,
        wallpaperEnabled: false,
        lockScreenEnabled: false
    )
}

extension AppSettings {
    private enum Key {
        static let autoActivateOnIdle    = "matrix.autoActivateOnIdle"
        static let idleThresholdMinutes  = "matrix.idleThresholdMinutes"
        static let wallpaperEnabled      = "matrix.wallpaperEnabled"
        static let lockScreenEnabled     = "matrix.lockScreenEnabled"
    }

    init(loadedFrom defaults: UserDefaults) {
        // MatrixSettings.init(loadedFrom:) handles speedMultiplier, bloom,
        // CRT (always on), and theme name → preset lookup.
        self.matrix = MatrixSettings(loadedFrom: defaults)
        self.autoActivateOnIdle = (defaults.object(forKey: Key.autoActivateOnIdle) as? Bool)
            ?? AppSettings.defaults.autoActivateOnIdle
        self.idleThresholdMinutes = (defaults.object(forKey: Key.idleThresholdMinutes) as? Double)
            ?? AppSettings.defaults.idleThresholdMinutes
        self.wallpaperEnabled = (defaults.object(forKey: Key.wallpaperEnabled) as? Bool)
            ?? AppSettings.defaults.wallpaperEnabled
        self.lockScreenEnabled = (defaults.object(forKey: Key.lockScreenEnabled) as? Bool)
            ?? AppSettings.defaults.lockScreenEnabled
    }

    func save(to defaults: UserDefaults) {
        // matrix.save handles speedMultiplier + theme name.
        matrix.save(to: defaults)
        defaults.set(autoActivateOnIdle, forKey: Key.autoActivateOnIdle)
        defaults.set(idleThresholdMinutes, forKey: Key.idleThresholdMinutes)
        defaults.set(wallpaperEnabled, forKey: Key.wallpaperEnabled)
        defaults.set(lockScreenEnabled, forKey: Key.lockScreenEnabled)
    }
}
