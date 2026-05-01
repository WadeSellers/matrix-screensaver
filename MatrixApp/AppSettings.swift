import Foundation
import MatrixCore

/// App-level settings: extends `MatrixSettings` (renderer params) with
/// app-specific concerns like the idle-timer threshold and whether
/// auto-activate is enabled at all.
struct AppSettings: Equatable, Sendable {
    var matrix: MatrixSettings
    var autoActivateOnIdle: Bool
    var idleThresholdMinutes: Double  // double so the slider can be smooth

    static let defaults = AppSettings(
        matrix: .defaults,
        autoActivateOnIdle: true,
        idleThresholdMinutes: 5
    )
}

extension AppSettings {
    private enum Key {
        static let speedMultiplier = "matrix.speedMultiplier"
        static let autoActivateOnIdle = "matrix.autoActivateOnIdle"
        static let idleThresholdMinutes = "matrix.idleThresholdMinutes"
    }

    init(loadedFrom defaults: UserDefaults) {
        // MatrixSettings.init(loadedFrom:) handles speedMultiplier, bloom,
        // CRT (always on), and theme name → preset lookup.
        self.matrix = MatrixSettings(loadedFrom: defaults)
        self.autoActivateOnIdle = (defaults.object(forKey: Key.autoActivateOnIdle) as? Bool)
            ?? AppSettings.defaults.autoActivateOnIdle
        self.idleThresholdMinutes = (defaults.object(forKey: Key.idleThresholdMinutes) as? Double)
            ?? AppSettings.defaults.idleThresholdMinutes
    }

    func save(to defaults: UserDefaults) {
        // matrix.save handles speedMultiplier + theme name.
        matrix.save(to: defaults)
        defaults.set(autoActivateOnIdle, forKey: Key.autoActivateOnIdle)
        defaults.set(idleThresholdMinutes, forKey: Key.idleThresholdMinutes)
    }
}
