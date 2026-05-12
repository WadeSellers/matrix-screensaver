#!/usr/bin/env swift
//
// generate-icon.swift — populates MatrixApp/Assets.xcassets/AppIcon.appiconset/
// and writes docs/app-icon-1024.png (the canonical 1024×1024 PNG also
// used in App Store screenshots / press kit).
//
// Renders a static snapshot of the menu-bar code-fall: a 3-column x
// 9-row grid of falling characters with staggered heads and the same
// head→near→mid→far color fade as MenuBarItem.swift. Glyph pool is the
// menu-bar set (digits + symbols) plus a few mirrored half-width
// katakana for Matrix flavor.
//
// Xcode's asset-catalog compiler builds the runtime .icns from the
// PNGs in the appiconset at build time, so there's no standalone .icns
// generation step here.
//
// Run: swift scripts/generate-icon.swift

import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - Layout constants

let cols = 3
let rows = 9

// Per-column head row in the same coordinate system MenuBarItem uses:
// row 0 = top, increasing downward; head is a Float so trail bands fall
// cleanly across cell boundaries. Hand-tuned so the three columns are
// clearly at different points in their fall — short trail / long trail
// / mid trail — which gives the "staggered rain" read. Each head value
// is chosen so floor(head)+ε lands within [-0.4, 0.5) for some row,
// guaranteeing a visible white "head" cell in every column.
let heads: [Float] = [3.7, 7.2, 5.3]

// Menu-bar glyph pool (Cipherfall MenuBarItem.swift:55-58) with three
// half-width katakana sprinkled in for Matrix flavor. Katakana glyphs
// are rendered mirrored horizontally to match the classic Matrix look.
let glyphPool: [String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "+", "*", "=", "<", ">", ":", ".", "-", "/", "|",
    "\u{FF85}", "\u{FF98}", "\u{FF7C}"  // ﾅ ﾘ ｼ
]
let katakanaSet: Set<String> = ["\u{FF85}", "\u{FF98}", "\u{FF7C}"]

/// Deterministic glyph pick so the icon is reproducible across runs.
func glyph(col: Int, row: Int) -> String {
    let idx = abs(col &* 31 &+ row &* 97 &+ 17) % glyphPool.count
    return glyphPool[idx]
}

// Trail color stops — copied verbatim from MatrixTheme.swift .classic
// and MenuBarItem.nsColorFor(trailDist:) so the app icon and the live
// menu-bar icon use the same palette.
let headColor = CGColor(srgbRed: 0.87, green: 1.00, blue: 0.87, alpha: 1.0)  // #DDFFDD
let nearColor = CGColor(srgbRed: 0.00, green: 1.00, blue: 0.40, alpha: 1.0)  // #00FF66
let midColor  = CGColor(srgbRed: 0.00, green: 0.53, blue: 0.20, alpha: 1.0)  // #008833
let farColor  = CGColor(srgbRed: 0.00, green: 0.20, blue: 0.07, alpha: 1.0)  // #003311

/// Mirrors MenuBarItem.nsColorFor(trailDist:) including the -0.4 head
/// extension and rowCount upper bound.
func color(trailDist: Float) -> CGColor? {
    guard trailDist >= -0.4, trailDist <= Float(rows) else { return nil }
    switch trailDist {
    case ..<0.5: return headColor
    case ..<2.0: return nearColor
    case ..<4.0: return midColor
    default:     return farColor
    }
}

// MARK: - Output paths

// Xcode asset-catalog AppIcon set. The build-time asset-catalog
// compiler reads PNGs from here, fuses them into a .icns, and embeds
// it in the app bundle along with CFBundleIconName for App Store
// submission.
let appiconsetDir = URL(fileURLWithPath: "MatrixApp/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: appiconsetDir, withIntermediateDirectories: true)

let docsDir = URL(fileURLWithPath: "docs")
try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

// macOS .iconset expected filenames + sizes.
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

// MARK: - Renderer

func renderIcon(sizePx: Int) -> Data {
    let size = CGFloat(sizePx)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: sizePx,
        height: sizePx,
        bitsPerComponent: 8,
        bytesPerRow: sizePx * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("ctx") }

    // Big Sur+ app-icon squircle (~22.5% radius). Background is the
    // same near-black the menu-bar icon uses (MenuBarItem.swift:209)
    // so colored rain reads against a dark frame.
    let radius = size * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Subtle green outer-glow bloom — soft halo around the icon shape.
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: size * 0.10,
        color: CGColor(srgbRed: 0.0, green: 1.0, blue: 0.40, alpha: 0.18)
    )
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(gray: 0.06, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip rain rendering to the squircle so corner glyphs can't poke
    // past the rounded edge (same pattern as MenuBarItem.swift:214-215).
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Cell grid. The menu bar uses a ~6.8% pad (1.5pt / 22pt) — keep
    // the same proportion so cell-to-frame ratio matches.
    let pad: CGFloat = size * 0.068
    let cellW = (size - 2 * pad) / CGFloat(cols)
    let cellH = (size - 2 * pad) / CGFloat(rows)

    // Bold monospaced system font sized to cellH * 0.95 — same recipe
    // as MenuBarItem.swift:224-227.
    let monoFont = NSFont.monospacedSystemFont(ofSize: cellH * 0.95, weight: .bold)
    // Hiragino for the katakana — bold monospaced renders half-width
    // katakana inconsistently across system versions; Hiragino is what
    // the fullscreen glyph atlas uses, so visuals stay coherent.
    let kataFont = NSFont(name: "HiraginoSans-W6", size: cellH * 0.90)
        ?? NSFont(name: "HiraginoSans-W3", size: cellH * 0.90)
        ?? monoFont

    for col in 0..<cols {
        let head = heads[col]
        for row in 0..<rows {
            let trailDist = head - Float(row)
            guard let cellColor = color(trailDist: trailDist) else { continue }
            let ch = glyph(col: col, row: row)
            let isKatakana = katakanaSet.contains(ch)
            let font = isKatakana ? kataFont : monoFont

            // CGContext is Y-up; row 0 at top → high Y. Matches
            // MenuBarItem.swift:236-241.
            let cellRect = CGRect(
                x: pad + CGFloat(col) * cellW,
                y: pad + CGFloat(rows - 1 - row) * cellH,
                width: cellW,
                height: cellH
            )

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: cellColor
            ]
            let attrStr = NSAttributedString(string: ch, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let dx = (cellRect.width - bounds.width) / 2 - bounds.minX
            let dy = (cellRect.height - bounds.height) / 2 - bounds.minY

            ctx.saveGState()
            if isKatakana {
                // Mirror horizontally for the classic Matrix flipped
                // look. Translate to the cell's right edge then negate
                // X — text then draws back into the cell.
                ctx.translateBy(x: cellRect.minX + dx + bounds.width, y: cellRect.minY + dy)
                ctx.scaleBy(x: -1, y: 1)
                ctx.textPosition = .zero
            } else {
                ctx.textPosition = CGPoint(x: cellRect.minX + dx, y: cellRect.minY + dy)
            }
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }
    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Generate

for (name, px) in sizes {
    let data = renderIcon(sizePx: px)
    let url = appiconsetDir.appendingPathComponent(name)
    try data.write(to: url)
    print("✓ \(name) (\(px)px)")
}

// Mirror the 1024px PNG (512x512@2x is exactly 1024 pixels) to docs/
// as a canonical reference for marketing / press kit use.
let docsPNG = docsDir.appendingPathComponent("app-icon-1024.png")
let source1024 = appiconsetDir.appendingPathComponent("icon_512x512@2x.png")
try? FileManager.default.removeItem(at: docsPNG)
try FileManager.default.copyItem(at: source1024, to: docsPNG)
print("✓ \(docsPNG.path)")
