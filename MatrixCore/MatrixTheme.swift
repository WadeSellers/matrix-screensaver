import Foundation
import simd

/// All visual parameters that define how the rain looks. Passed to the
/// GPU as a `ColorUniforms` struct (colour channel) and read by
/// `BloomPipeline` (post-process channel).
///
/// Colours are perceptual sRGB-normalised floats — the same convention
/// as the hard-coded values in the shader they replace. The GPU
/// framebuffer is `.bgra8Unorm_srgb`, so the hardware applies the
/// display-space gamma automatically.
public struct MatrixTheme: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { name }

    /// Display name used in the Settings picker.
    public var name: String

    // MARK: - Rain colours
    // Each is SIMD4<Float>: .xyz = RGB, .w = 0 (unused, satisfies
    // Metal's float4 16-byte alignment requirement).

    /// The leading cell — white-green in the classic look.
    public var headColor: SIMD4<Float>
    /// 1–7 cells behind the head — the bright part of the trail.
    public var nearTrailColor: SIMD4<Float>
    /// 8–15 cells behind the head — the mid-fade.
    public var midTrailColor: SIMD4<Float>
    /// 16+ cells — fades to black over remaining trail length.
    public var farTrailColor: SIMD4<Float>

    // MARK: - Post-process overrides
    public var bloomStrength: Float    // 0..2; default 1.20
    public var scanlineDarken: Float   // 0..1; 0 = no lines, 1 = full black
    public var vignetteAmount: Float   // 0..1

    public init(
        name: String,
        headColor: SIMD4<Float>,
        nearTrailColor: SIMD4<Float>,
        midTrailColor: SIMD4<Float>,
        farTrailColor: SIMD4<Float>,
        bloomStrength: Float = 1.20,
        scanlineDarken: Float = 0.45,
        vignetteAmount: Float = 0.70
    ) {
        self.name = name
        self.headColor = headColor
        self.nearTrailColor = nearTrailColor
        self.midTrailColor = midTrailColor
        self.farTrailColor = farTrailColor
        self.bloomStrength = bloomStrength
        self.scanlineDarken = scanlineDarken
        self.vignetteAmount = vignetteAmount
    }
}

// MARK: - Preset themes

public extension MatrixTheme {

    /// Movie-accurate green — the current default.
    static let classic = MatrixTheme(
        name: "Classic",
        headColor:      SIMD4(0.87, 1.00, 0.87, 0),  // #DDFFDD
        nearTrailColor: SIMD4(0.00, 1.00, 0.40, 0),  // #00FF66
        midTrailColor:  SIMD4(0.00, 0.53, 0.20, 0),  // #008833
        farTrailColor:  SIMD4(0.00, 0.20, 0.07, 0)   // #003311
    )

    /// Matrix Reloaded — cranked up. Pure-white head, brighter green
    /// near-trail, bigger bloom halos.
    static let reloaded = MatrixTheme(
        name: "Reloaded",
        headColor:      SIMD4(1.00, 1.00, 1.00, 0),  // white
        nearTrailColor: SIMD4(0.00, 1.00, 0.60, 0),  // #00FF99
        midTrailColor:  SIMD4(0.00, 0.67, 0.27, 0),  // #00AA44
        farTrailColor:  SIMD4(0.00, 0.20, 0.08, 0),
        bloomStrength: 1.50
    )

    /// Matrix Resurrections — red/pink palette.
    static let resurrections = MatrixTheme(
        name: "Resurrections",
        headColor:      SIMD4(1.00, 0.87, 0.87, 0),  // #FFDDDD
        nearTrailColor: SIMD4(1.00, 0.27, 0.40, 0),  // #FF4566
        midTrailColor:  SIMD4(0.53, 0.07, 0.20, 0),  // #881133
        farTrailColor:  SIMD4(0.20, 0.00, 0.07, 0),  // #330011
        vignetteAmount: 0.80
    )

    /// Amber CRT — 1980s amber phosphor terminal. Max scanlines,
    /// prominent vignette.
    static let amberCRT = MatrixTheme(
        name: "Amber CRT",
        headColor:      SIMD4(1.00, 1.00, 0.67, 0),  // #FFFFAA
        nearTrailColor: SIMD4(1.00, 0.80, 0.00, 0),  // #FFCC00
        midTrailColor:  SIMD4(0.53, 0.40, 0.00, 0),  // #886600
        farTrailColor:  SIMD4(0.20, 0.13, 0.00, 0),  // #332200
        bloomStrength: 1.00,
        scanlineDarken: 0.60,
        vignetteAmount: 0.85
    )

    /// Animatrix — desaturated, sepia-tinted. Softer bloom and lighter
    /// scanlines for a pencil-and-ink anime feel.
    static let animatrix = MatrixTheme(
        name: "Animatrix",
        headColor:      SIMD4(0.87, 0.87, 0.80, 0),  // #DDDDCC
        nearTrailColor: SIMD4(0.67, 0.73, 0.53, 0),  // #AABB88
        midTrailColor:  SIMD4(0.33, 0.40, 0.27, 0),  // #556644
        farTrailColor:  SIMD4(0.13, 0.20, 0.07, 0),  // #223311
        bloomStrength: 0.90,
        scanlineDarken: 0.25,
        vignetteAmount: 0.55
    )

    /// Solarized — Ethan Schoonover's palette. Dev-humour variant.
    /// Base3 head, Solarized green trail, base01 mid-fade, base03 far.
    static let solarized = MatrixTheme(
        name: "Solarized",
        headColor:      SIMD4(0.99, 0.96, 0.89, 0),  // base3  #FDF6E3
        nearTrailColor: SIMD4(0.52, 0.60, 0.00, 0),  // green  #859900
        midTrailColor:  SIMD4(0.40, 0.48, 0.51, 0),  // base01 #657B83
        farTrailColor:  SIMD4(0.03, 0.21, 0.26, 0),  // base03 #073642
        bloomStrength: 1.00,
        scanlineDarken: 0.35,
        vignetteAmount: 0.65
    )

    /// Ordered list used to populate the Settings picker.
    static let allPresets: [MatrixTheme] = [
        .classic, .reloaded, .resurrections, .amberCRT, .animatrix, .solarized
    ]
}
