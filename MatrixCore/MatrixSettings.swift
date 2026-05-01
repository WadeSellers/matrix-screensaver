import Foundation

public struct MatrixSettings: Equatable, Sendable {
    public var speedMultiplier: Float
    public var bloomEnabled: Bool
    public var crtEnabled: Bool
    public var theme: MatrixTheme

    public init(
        speedMultiplier: Float = 1.0,
        bloomEnabled: Bool = true,
        crtEnabled: Bool = true,
        theme: MatrixTheme = .classic
    ) {
        self.speedMultiplier = speedMultiplier
        self.bloomEnabled = bloomEnabled
        self.crtEnabled = crtEnabled
        self.theme = theme
    }

    public static let defaults = MatrixSettings()
}

public extension MatrixSettings {
    private enum Key {
        static let speedMultiplier = "matrix.speedMultiplier"
        static let bloomEnabled    = "matrix.bloomEnabled"
        static let crtEnabled      = "matrix.crtEnabled"
        static let themeName       = "matrix.themeName"
    }

    init(loadedFrom defaults: UserDefaults) {
        let savedThemeName = defaults.string(forKey: Key.themeName)
        let theme = MatrixTheme.allPresets.first { $0.name == savedThemeName }
            ?? MatrixSettings.defaults.theme

        self.init(
            speedMultiplier: (defaults.object(forKey: Key.speedMultiplier) as? Double)
                .map(Float.init) ?? MatrixSettings.defaults.speedMultiplier,
            bloomEnabled: true,   // always on — not user-configurable
            crtEnabled:   true,   // always on — not user-configurable
            theme: theme
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(Double(speedMultiplier), forKey: Key.speedMultiplier)
        defaults.set(bloomEnabled,            forKey: Key.bloomEnabled)
        defaults.set(crtEnabled,              forKey: Key.crtEnabled)
        defaults.set(theme.name,              forKey: Key.themeName)
    }
}
