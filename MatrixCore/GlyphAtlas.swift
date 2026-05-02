import CoreGraphics
import CoreText
import Foundation
import Metal

public final class GlyphAtlas {
    /// Crisp CoreText rendering — Hiragino Sans W3, clean antialiased glyphs.
    public let texture: MTLTexture
    /// Hand-drawn variant — same glyph set rendered in Hiragino Mincho ProN W3,
    /// a calligraphic serif with natural thick/thin stroke variation that gives
    /// characters an inked, brush-drawn quality. No post-process; the font itself
    /// carries all the character.
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

        // Crisp: geometric sans-serif.
        let crispFont = CTFontCreateWithName(
            "HiraginoSans-W3" as CFString, CGFloat(glyphSize) * 0.78, nil)
        // Hand-drawn: calligraphic Mincho. Slightly larger scale because
        // Mincho's ink-trap details fill the cell well at 0.80.
        let drawnFont = CTFontCreateWithName(
            "HiraMinProN-W3" as CFString, CGFloat(glyphSize) * 0.80, nil)

        guard
            let crispTex = GlyphAtlas.renderAtlas(
                glyphs: glyphs, font: crispFont,
                atlasSize: atlasSize, cellsPerRow: cellsPerRow,
                glyphSize: glyphSize, device: device),
            let drawnTex = GlyphAtlas.renderAtlas(
                glyphs: glyphs, font: drawnFont,
                atlasSize: atlasSize, cellsPerRow: cellsPerRow,
                glyphSize: glyphSize, device: device)
        else { return nil }

        self.texture        = crispTex
        self.wobbledTexture = drawnTex
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

        let attrs = [
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

            drawGlyph(ch: ch, attrs: attrs, glyphSize: CGFloat(glyphSize), ctx: ctx)

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

    // MARK: - Glyph drawing

    private static func drawGlyph(
        ch: String, attrs: CFDictionary,
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
}
