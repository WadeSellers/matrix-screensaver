import CoreGraphics
import CoreText
import Foundation
import Metal

public final class GlyphAtlas {
    /// Crisp CoreText rendering — clean antialiased glyphs.
    public let texture: MTLTexture
    /// Hand-drawn variant. Each glyph's vector outline is jittered
    /// before rasterisation: Bezier control points are perturbed by
    /// pseudo-random noise so the strokes look drawn with an unsteady
    /// hand rather than rendered by a computer. Generated once at
    /// startup; zero per-frame cost.
    public let wobbledTexture: MTLTexture

    public let glyphCount: Int
    public let cellsPerRow: Int
    public let glyphSizePx: Int
    public let atlasSize: Int

    public init?(device: MTLDevice) {
        let katakana: [String] = (0xFF66...0xFF9D).compactMap {
            UnicodeScalar($0).map { String($0) }
        }
        let digits:  [String] = "0123456789".map { String($0) }
        let symbols: [String] = [":", ".", "-", "*", "+", "<", ">", "|", "=", "/"]
        let glyphs = katakana + digits + symbols

        let atlasSize   = 2048
        let cellsPerRow = Int(ceil(Double(glyphs.count).squareRoot()))
        let glyphSize   = atlasSize / cellsPerRow
        let fontSize    = CGFloat(glyphSize) * 0.78
        let font        = CTFontCreateWithName("HiraginoSans-W3" as CFString, fontSize, nil)

        guard
            let crispTex = GlyphAtlas.renderAtlas(
                glyphs: glyphs, font: font,
                atlasSize: atlasSize, cellsPerRow: cellsPerRow,
                glyphSize: glyphSize, handDrawn: false, device: device),
            let wobbleTex = GlyphAtlas.renderAtlas(
                glyphs: glyphs, font: font,
                atlasSize: atlasSize, cellsPerRow: cellsPerRow,
                glyphSize: glyphSize, handDrawn: true, device: device)
        else { return nil }

        self.texture        = crispTex
        self.wobbledTexture = wobbleTex
        self.glyphCount     = glyphs.count
        self.cellsPerRow    = cellsPerRow
        self.glyphSizePx    = glyphSize
        self.atlasSize      = atlasSize
    }

    // MARK: - Atlas rendering

    private static func renderAtlas(
        glyphs: [String],
        font: CTFont,
        atlasSize: Int,
        cellsPerRow: Int,
        glyphSize: Int,
        handDrawn: Bool,
        device: MTLDevice
    ) -> MTLTexture? {
        guard let ctx = CGContext(
            data: nil,
            width: atlasSize, height: atlasSize,
            bitsPerComponent: 8, bytesPerRow: atlasSize,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Flip Y → top-origin image coordinates.
        ctx.translateBy(x: 0, y: CGFloat(atlasSize))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: atlasSize, height: atlasSize))

        let whiteAttrs = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)
        ] as CFDictionary

        for (i, ch) in glyphs.enumerated() {
            let col   = i % cellsPerRow
            let row   = i / cellsPerRow
            let cellX = CGFloat(col * glyphSize)
            let cellY = CGFloat(row * glyphSize)

            let scalar     = ch.unicodeScalars.first?.value ?? 0
            let isKatakana = (0xFF66...0xFF9D).contains(Int(scalar))

            ctx.saveGState()
            // Move to cell bottom-left, flip Y back to CoreText's upward axis.
            ctx.translateBy(x: cellX, y: cellY + CGFloat(glyphSize))
            ctx.scaleBy(x: 1, y: -1)
            if isKatakana {
                ctx.translateBy(x: CGFloat(glyphSize), y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }

            if handDrawn {
                drawHandDrawn(ch: ch, glyphIndex: i, font: font,
                              glyphSize: CGFloat(glyphSize), ctx: ctx)
            } else {
                drawCrisp(ch: ch, font: font, attrs: whiteAttrs,
                          glyphSize: CGFloat(glyphSize), ctx: ctx)
            }

            ctx.restoreGState()
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasSize, height: atlasSize,
            mipmapped: false)
        desc.usage       = .shaderRead
        desc.storageMode = .shared

        guard let tex = device.makeTexture(descriptor: desc),
              let bytes = ctx.data else { return nil }

        tex.replace(
            region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
            mipmapLevel: 0, withBytes: bytes, bytesPerRow: atlasSize)
        return tex
    }

    // MARK: - Crisp (unchanged CTLineDraw path)

    private static func drawCrisp(
        ch: String, font: CTFont, attrs: CFDictionary,
        glyphSize: CGFloat, ctx: CGContext
    ) {
        guard let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, ch as CFString, attrs)
        else { return }
        let line   = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let dx = (glyphSize - bounds.width)  / 2 - bounds.minX
        let dy = (glyphSize - bounds.height) / 2 - bounds.minY
        ctx.textPosition = CGPoint(x: dx, y: dy)
        CTLineDraw(line, ctx)
    }

    // MARK: - Hand-drawn (path-jitter)

    /// Draw `ch` by fetching its vector outline from `font`, perturbing
    /// every Bezier control point with pseudo-random noise, then filling
    /// the resulting wobbly shape.
    ///
    /// This is the correct technique for a hand-drawn look: the
    /// *outlines* of the strokes are deformed before rasterisation, so
    /// the result looks like ink drawn with an unsteady hand — curves
    /// squiggle, straight strokes bow, endpoints drift. A pixel-shift
    /// post-process (the previous approach) can't achieve this because
    /// it only smears already-rendered pixels.
    private static func drawHandDrawn(
        ch: String, glyphIndex: Int, font: CTFont,
        glyphSize: CGFloat, ctx: CGContext
    ) {
        let utf16chars = Array(ch.utf16)
        var glyphID: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, utf16chars, &glyphID, 1),
              let cleanPath = CTFontCreatePathForGlyph(font, glyphID, nil)
        else { return }

        // Centre in cell — same math as the crisp path uses.
        let b  = cleanPath.boundingBox
        let cx = (glyphSize - b.width)  / 2 - b.minX
        let cy = (glyphSize - b.height) / 2 - b.minY

        // 7 pt amplitude on a ~177 pt font ≈ 4 % — clearly visible
        // wobble without making glyphs illegible.
        let path = jitterPath(cleanPath,
                              center: CGPoint(x: cx, y: cy),
                              amplitude: 7.0,
                              glyphIndex: glyphIndex)

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// Rebuild `source` as a new `CGMutablePath` where every point
    /// (endpoints AND Bezier control points) is displaced by a
    /// deterministic pseudo-random offset based on `(glyphIndex, pointIndex)`.
    /// `center` is added first so the glyph is correctly positioned in
    /// its atlas cell; jitter is layered on top.
    private static func jitterPath(
        _ source: CGPath,
        center: CGPoint,
        amplitude: CGFloat,
        glyphIndex: Int
    ) -> CGPath {
        var pi = 0          // point index — increments per control point
        let out = CGMutablePath()

        // Integer hash (Murmur-inspired) that maps two seeds to a
        // float in [−1, +1].  Deterministic → same atlas every launch.
        func rand(_ a: Int, _ b: Int) -> CGFloat {
            var h = UInt32(truncatingIfNeeded: a &* 2654435761 &+ b &* 40503)
            h ^= h >> 16; h &*= 0x85ebca6b
            h ^= h >> 13; h &*= 0xc2b2ae35
            h ^= h >> 16
            return (CGFloat(h & 0xffff) / 65535.0 - 0.5) * 2.0
        }

        // Jitter a single point: add centering offset + noise.
        func j(_ p: CGPoint, idx: Int) -> CGPoint {
            CGPoint(
                x: p.x + center.x + rand(glyphIndex &* 31 &+ idx &* 7,  idx)      * amplitude,
                y: p.y + center.y + rand(glyphIndex &* 17 &+ idx &* 13, idx &+ 1) * amplitude
            )
        }

        source.applyWithBlock { elem in
            let pts = elem.pointee.points
            switch elem.pointee.type {
            case .moveToPoint:
                out.move(to: j(pts[0], idx: pi)); pi += 1
            case .addLineToPoint:
                out.addLine(to: j(pts[0], idx: pi)); pi += 1
            case .addQuadCurveToPoint:
                out.addQuadCurve(to:      j(pts[1], idx: pi + 1),
                                 control: j(pts[0], idx: pi))
                pi += 2
            case .addCurveToPoint:
                out.addCurve(to:      j(pts[2], idx: pi + 2),
                             control1: j(pts[0], idx: pi),
                             control2: j(pts[1], idx: pi + 1))
                pi += 3
            case .closeSubpath:
                out.closeSubpath()
            @unknown default:
                break
            }
        }
        return out
    }
}
