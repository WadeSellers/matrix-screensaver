import CoreGraphics
import CoreText
import Foundation
import Metal

public final class GlyphAtlas {
    public let texture: MTLTexture
    public let glyphCount: Int
    public let cellsPerRow: Int
    public let glyphSizePx: Int
    public let atlasSize: Int

    public init?(device: MTLDevice) {
        // The Matrix code: mirrored half-width katakana (U+FF66–U+FF9D) +
        // Latin digits + a handful of symbols. The mirroring is what makes
        // them look "alien" instead of like real Japanese.
        let katakana: [String] = (0xFF66...0xFF9D).compactMap {
            UnicodeScalar($0).map { String($0) }
        }
        let digits: [String] = "0123456789".map { String($0) }
        let symbols: [String] = [":", ".", "-", "*", "+", "<", ">", "|", "=", "/"]
        let glyphs = katakana + digits + symbols

        let atlasSize = 2048
        let cellsPerRow = Int(ceil(Double(glyphs.count).squareRoot()))
        let glyphSize = atlasSize / cellsPerRow

        guard let context = CGContext(
            data: nil,
            width: atlasSize,
            height: atlasSize,
            bitsPerComponent: 8,
            bytesPerRow: atlasSize,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Flip Y so we work in top-origin image coordinates throughout.
        context.translateBy(x: 0, y: CGFloat(atlasSize))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: atlasSize, height: atlasSize))

        let fontSize = CGFloat(glyphSize) * 0.78
        let font = CTFontCreateWithName("HiraginoSans-W3" as CFString, fontSize, nil)

        let whiteAttrs = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)
        ] as CFDictionary

        for (i, ch) in glyphs.enumerated() {
            let col = i % cellsPerRow
            let row = i / cellsPerRow
            let cellX = CGFloat(col * glyphSize)
            let cellY = CGFloat(row * glyphSize)

            let scalar = ch.unicodeScalars.first?.value ?? 0
            let isKatakana = (0xFF66...0xFF9D).contains(Int(scalar))

            context.saveGState()
            // Move to bottom-left of cell in image coords, then un-flip Y so
            // CoreText's natural baseline-up drawing produces upright glyphs.
            context.translateBy(x: cellX, y: cellY + CGFloat(glyphSize))
            context.scaleBy(x: 1, y: -1)

            if isKatakana {
                // Mirror horizontally for the iconic "alien" Matrix look.
                context.translateBy(x: CGFloat(glyphSize), y: 0)
                context.scaleBy(x: -1, y: 1)
            }

            let cfString = ch as CFString
            guard let attrString = CFAttributedStringCreate(kCFAllocatorDefault, cfString, whiteAttrs)
            else {
                context.restoreGState()
                continue
            }

            let line = CTLineCreateWithAttributedString(attrString)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let dx = (CGFloat(glyphSize) - bounds.width) / 2 - bounds.minX
            let dy = (CGFloat(glyphSize) - bounds.height) / 2 - bounds.minY
            context.textPosition = CGPoint(x: dx, y: dy)
            CTLineDraw(line, context)
            context.restoreGState()
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasSize,
            height: atlasSize,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor),
              let bytes = context.data else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: atlasSize
        )

        self.texture = texture
        self.glyphCount = glyphs.count
        self.cellsPerRow = cellsPerRow
        self.glyphSizePx = glyphSize
        self.atlasSize = atlasSize
    }
}
