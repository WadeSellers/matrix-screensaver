import Foundation

public struct MatrixSettings: Equatable, Sendable {
    public var speedMultiplier: Float
    public var bloomEnabled: Bool
    public var crtEnabled: Bool

    public init(
        speedMultiplier: Float = 1.0,
        bloomEnabled: Bool = true,
        crtEnabled: Bool = false
    ) {
        self.speedMultiplier = speedMultiplier
        self.bloomEnabled = bloomEnabled
        self.crtEnabled = crtEnabled
    }

    public static let defaults = MatrixSettings()
}

public extension MatrixSettings {
    private enum Key {
        static let speedMultiplier = "matrix.speedMultiplier"
        static let bloomEnabled = "matrix.bloomEnabled"
        static let crtEnabled = "matrix.crtEnabled"
    }

    init(loadedFrom defaults: UserDefaults) {
        self.init(
            speedMultiplier: (defaults.object(forKey: Key.speedMultiplier) as? Double).map(Float.init)
                ?? Self.defaults.speedMultiplier,
            bloomEnabled: (defaults.object(forKey: Key.bloomEnabled) as? Bool)
                ?? Self.defaults.bloomEnabled,
            crtEnabled: (defaults.object(forKey: Key.crtEnabled) as? Bool)
                ?? Self.defaults.crtEnabled
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(Double(speedMultiplier), forKey: Key.speedMultiplier)
        defaults.set(bloomEnabled, forKey: Key.bloomEnabled)
        defaults.set(crtEnabled, forKey: Key.crtEnabled)
    }
}
