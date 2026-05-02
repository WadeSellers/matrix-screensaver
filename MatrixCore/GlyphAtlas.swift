import CoreGraphics
import CoreText
import Foundation
import Metal

/// Renders the Matrix glyph set (mirrored half-width katakana + digits +
/// symbols) into a single grayscale `MTLTexture`. Built once at launch.
public final class GlyphAtlas {
    public let texture: MTLTexture
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

        let font = CTFontCreateWithName(
            "HiraginoSans-W3" as CFString,
            CGFloat(glyphSize) * 0.78,
            nil)

        guard let tex = GlyphAtlas.renderAtlas(
            glyphs: glyphs,
            font: font,
            atlasSize: atlasSize,
            cellsPerRow: cellsPerRow,
            glyphSize: glyphSize,
            device: device
        ) else { return nil }

        self.texture     = tex
        self.glyphCount  = glyphs.count
        self.cellsPerRow = cellsPerRow
        self.glyphSizePx = glyphSize
        self.atlasSize   = atlasSize
    }

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
            // Mirror katakana — matches the iconic Matrix look.
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
