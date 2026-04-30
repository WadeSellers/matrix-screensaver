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
        // Bloom and CRT are always on — not user-configurable. We hardcode
        // them to true regardless of any previously-persisted values from
        // when they were toggleable.
        let m = MatrixSettings(
            speedMultiplier: (defaults.object(forKey: Key.speedMultiplier) as? Double).map(Float.init)
                ?? AppSettings.defaults.matrix.speedMultiplier,
            bloomEnabled: true,
            crtEnabled: true
        )
        self.matrix = m
        self.autoActivateOnIdle = (defaults.object(forKey: Key.autoActivateOnIdle) as? Bool)
            ?? AppSettings.defaults.autoActivateOnIdle
        self.idleThresholdMinutes = (defaults.object(forKey: Key.idleThresholdMinutes) as? Double)
            ?? AppSettings.defaults.idleThresholdMinutes
    }

    func save(to defaults: UserDefaults) {
        defaults.set(Double(matrix.speedMultiplier), forKey: Key.speedMultiplier)
        defaults.set(autoActivateOnIdle, forKey: Key.autoActivateOnIdle)
        defaults.set(idleThresholdMinutes, forKey: Key.idleThresholdMinutes)
    }
}
