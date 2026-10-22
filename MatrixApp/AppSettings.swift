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

    /// "Require PIN to dismiss." Only the switch lives here; the PIN
    /// itself is a salted hash in the Keychain (`PINStore`). Read it
    /// through `pinLockActive`, never on its own: "enabled but no
    /// Keychain item" must behave as off.
    var pinLockEnabled: Bool
    /// "Also when I start it myself." Off by default: the PIN guards
    /// the walk-away case (idle activation). Someone who just pressed
    /// the hotkey on purpose usually doesn't want to type a PIN to get
    /// back to work.
    var pinLockAppliesToManual: Bool

    /// True iff a session started for `reason` should be PIN-locked.
    /// Hits the Keychain, so call at activation time, not per frame.
    func pinLockActive(for reason: ActivationReason) -> Bool {
        guard pinLockEnabled else { return false }
        switch reason {
        case .idle: break
        case .manual: guard pinLockAppliesToManual else { return false }
        }
        return PINStore.hasPIN
    }

    static let defaults = AppSettings(
        matrix: .defaults,
        autoActivateOnIdle: true,
        idleThresholdMinutes: 5,
        wallpaperEnabled: false,
        lockScreenEnabled: false,
        pinLockEnabled: false,
        pinLockAppliesToManual: false
    )
}

extension AppSettings {
    private enum Key {
        static let autoActivateOnIdle    = "matrix.autoActivateOnIdle"
        static let idleThresholdMinutes  = "matrix.idleThresholdMinutes"
        static let wallpaperEnabled      = "matrix.wallpaperEnabled"
        static let lockScreenEnabled     = "matrix.lockScreenEnabled"
        static let pinLockEnabled        = "matrix.pinLockEnabled"
        static let pinLockAppliesToManual = "matrix.pinLockAppliesToManual"
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
        self.pinLockEnabled = (defaults.object(forKey: Key.pinLockEnabled) as? Bool)
            ?? AppSettings.defaults.pinLockEnabled
        self.pinLockAppliesToManual = (defaults.object(forKey: Key.pinLockAppliesToManual) as? Bool)
            ?? AppSettings.defaults.pinLockAppliesToManual
    }

    func save(to defaults: UserDefaults) {
        // matrix.save handles speedMultiplier + theme name.
        matrix.save(to: defaults)
        defaults.set(autoActivateOnIdle, forKey: Key.autoActivateOnIdle)
        defaults.set(idleThresholdMinutes, forKey: Key.idleThresholdMinutes)
        defaults.set(wallpaperEnabled, forKey: Key.wallpaperEnabled)
        defaults.set(lockScreenEnabled, forKey: Key.lockScreenEnabled)
        defaults.set(pinLockEnabled, forKey: Key.pinLockEnabled)
        defaults.set(pinLockAppliesToManual, forKey: Key.pinLockAppliesToManual)
    }
}
