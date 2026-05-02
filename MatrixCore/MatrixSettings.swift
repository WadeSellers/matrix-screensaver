import Foundation

// MARK: - GlyphStyle

/// Controls which glyph atlas variant the renderer uses.
public enum GlyphStyle: String, Equatable, Hashable, CaseIterable, Sendable {
    /// Default CoreText rendering — clean, crisp, antialiased.
    case crisp = "crisp"
    /// Wobble-pass variant — each glyph's pixels are column- and
    /// row-shifted by a small sine-wave offset so strokes look
    /// hand-inked rather than digital. Generated once at startup.
    case handDrawn = "hand-drawn"
}

// MARK: - MatrixSettings

public struct MatrixSettings: Equatable, Sendable {
    public var speedMultiplier: Float
    public var bloomEnabled: Bool
    public var crtEnabled: Bool
    public var theme: MatrixTheme
    public var glyphStyle: GlyphStyle

    public init(
        speedMultiplier: Float = 1.0,
        bloomEnabled: Bool = true,
        crtEnabled: Bool = true,
        theme: MatrixTheme = .classic,
        glyphStyle: GlyphStyle = .crisp
    ) {
        self.speedMultiplier = speedMultiplier
        self.bloomEnabled = bloomEnabled
        self.crtEnabled = crtEnabled
        self.theme = theme
        self.glyphStyle = glyphStyle
    }

    public static let defaults = MatrixSettings()
}

public extension MatrixSettings {
    private enum Key {
        static let speedMultiplier = "matrix.speedMultiplier"
        static let bloomEnabled    = "matrix.bloomEnabled"
        static let crtEnabled      = "matrix.crtEnabled"
        static let themeName       = "matrix.themeName"
        static let glyphStyle      = "matrix.glyphStyle"
    }

    init(loadedFrom defaults: UserDefaults) {
        let savedThemeName = defaults.string(forKey: Key.themeName)
        let theme = MatrixTheme.allPresets.first { $0.name == savedThemeName }
            ?? MatrixSettings.defaults.theme

        let rawStyle = defaults.string(forKey: Key.glyphStyle) ?? GlyphStyle.crisp.rawValue
        let glyphStyle = GlyphStyle(rawValue: rawStyle) ?? .crisp

        self.init(
            speedMultiplier: (defaults.object(forKey: Key.speedMultiplier) as? Double)
                .map(Float.init) ?? MatrixSettings.defaults.speedMultiplier,
            bloomEnabled: true,   // always on — not user-configurable
            crtEnabled:   true,   // always on — not user-configurable
            theme: theme,
            glyphStyle: glyphStyle
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(Double(speedMultiplier), forKey: Key.speedMultiplier)
        defaults.set(bloomEnabled,            forKey: Key.bloomEnabled)
        defaults.set(crtEnabled,              forKey: Key.crtEnabled)
        defaults.set(theme.name,              forKey: Key.themeName)
        defaults.set(glyphStyle.rawValue,     forKey: Key.glyphStyle)
    }
}
