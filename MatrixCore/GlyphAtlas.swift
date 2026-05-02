import CoreGraphics
import CoreText
import Foundation
import Metal

public final class GlyphAtlas {
    /// Crisp CoreText rendering — normal antialiased glyphs.
    public let texture: MTLTexture
    /// Hand-drawn variant — each glyph's pixels are displaced by a
    /// small per-column + per-row sine-wave offset so strokes look
    /// ink-on-paper rather than pixel-perfect. Generated once at
    /// startup from the same rasterised source; zero per-frame cost.
    public let wobbledTexture: MTLTexture

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

        // ---- Shared texture descriptor ----
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasSize,
            height: atlasSize,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        guard let crispTexture = device.makeTexture(descriptor: descriptor),
              let bytes = context.data else {
            return nil
        }

        // ---- Upload crisp texture ----
        crispTexture.replace(
            region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: atlasSize
        )

        // ---- Build and upload wobbled texture ----
        // Read from the original CGContext bytes and write a perturbed
        // copy into a fresh buffer. Then upload that as the second texture.
        let byteCount = atlasSize * atlasSize
        var wobbled = [UInt8](repeating: 0, count: byteCount)

        wobbled.withUnsafeMutableBytes { destPtr in
            let dest = destPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let src  = bytes.assumingMemoryBound(to: UInt8.self)
            GlyphAtlas.applyWobble(
                from: src,
                to: dest,
                atlasSize: atlasSize,
                cellSize: glyphSize,
                cellsPerRow: cellsPerRow,
                glyphCount: glyphs.count
            )
        }

        guard let wobbleTex = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        wobbled.withUnsafeBytes { srcPtr in
            wobbleTex.replace(
                region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
                mipmapLevel: 0,
                withBytes: srcPtr.baseAddress!,
                bytesPerRow: atlasSize
            )
        }

        self.texture        = crispTexture
        self.wobbledTexture = wobbleTex
        self.glyphCount     = glyphs.count
        self.cellsPerRow    = cellsPerRow
        self.glyphSizePx    = glyphSize
        self.atlasSize      = atlasSize
    }

    // MARK: - Wobble pass

    /// Read pixels from `original` (crisp atlas bytes), write a
    /// sine-displaced version into `dest`.
    ///
    /// Two orthogonal displacements are combined:
    ///   • Column wobble: each pixel column x gets a y-shift driven by
    ///     `sin(2π · x/cellSize / period + phase)`.
    ///   • Row wobble: each pixel row y gets a smaller x-shift driven
    ///     by a second sine at a different phase and frequency.
    ///
    /// Both phases are derived per-glyph using the golden ratio and e
    /// as incommensurable multipliers so adjacent glyphs never look
    /// identical.
    private static func applyWobble(
        from original: UnsafePointer<UInt8>,
        to dest: UnsafeMutablePointer<UInt8>,
        atlasSize: Int,
        cellSize: Int,
        cellsPerRow: Int,
        glyphCount: Int
    ) {
        // Start with a straight copy so background / unused atlas cells
        // stay black without needing a separate fill step.
        memcpy(dest, original, atlasSize * atlasSize)

        let yAmp    = 5.0   // pixels — vertical column displacement
        let xAmp    = 2.5   // pixels — horizontal row displacement (subtler)
        let period  = 0.55  // fraction of cellSize per sine cycle (~1.8 cycles)

        // Scratch arrays reused across glyphs to avoid repeated allocation.
        var yShifts = [Int](repeating: 0, count: cellSize)
        var xShifts = [Int](repeating: 0, count: cellSize)

        for glyphIdx in 0..<glyphCount {
            let col   = glyphIdx % cellsPerRow
            let row   = glyphIdx / cellsPerRow
            let cellX = col * cellSize
            let cellY = row * cellSize

            // Unique phase per glyph.  Golden ratio (φ) and e spread
            // phases so no two adjacent glyphs share a wobble pattern.
            let phaseY = Double(glyphIdx) * 1.61803398874989 * 2.0 * .pi
            let phaseX = Double(glyphIdx) * 2.71828182845905 * 2.0 * .pi

            // Precompute shifts for this glyph — one sin() per pixel
            // edge rather than one per interior pixel.
            for px in 0..<cellSize {
                let t = Double(px) / Double(cellSize)
                yShifts[px] = Int((yAmp * sin(2 * .pi * t / period + phaseY)).rounded())
            }
            for py in 0..<cellSize {
                let t = Double(py) / Double(cellSize)
                xShifts[py] = Int((xAmp * sin(2 * .pi * t / period + phaseX)).rounded())
            }

            // Write the wobbled cell.
            for py in 0..<cellSize {
                let xOff = xShifts[py]
                for px in 0..<cellSize {
                    let destIdx = (cellY + py) * atlasSize + (cellX + px)

                    let srcPx = px + xOff
                    let srcPy = py + yShifts[px]

                    if srcPx >= 0 && srcPx < cellSize &&
                       srcPy >= 0 && srcPy < cellSize {
                        dest[destIdx] = original[(cellY + srcPy) * atlasSize + (cellX + srcPx)]
                    } else {
                        dest[destIdx] = 0
                    }
                }
            }
        }
    }
}
