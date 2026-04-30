#!/usr/bin/env swift
//
// generate-icon.swift — produces MatrixApp/Resources/AppIcon.icns
//
// Single bright-green half-width katakana glyph centered on a black
// rounded square. Uses Hiragino Sans (system font, same one our atlas
// uses) for visual consistency with the rendered Matrix code.
//
// Run: swift scripts/generate-icon.swift

import AppKit
import CoreGraphics
import CoreText
import Foundation

// Three katakana glyphs stacked vertically: head (white-green) →
// mid-trail (bright green) → trail-tail (dim green). Reads as "rain"
// immediately, not as one lonely character.
let topGlyph: String    = "\u{FF85}"  // ﾅ
let middleGlyph: String = "\u{FF98}"  // ﾘ
let bottomGlyph: String = "\u{FF7C}"  // ｼ
let outDir = URL(fileURLWithPath: "MatrixApp/Resources")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let iconsetDir = URL(fileURLWithPath: "/tmp/Matrix.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

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

func renderIcon(sizePx: Int) -> Data {
    let size = CGFloat(sizePx)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    guard let ctx = CGContext(
        data: nil,
        width: sizePx,
        height: sizePx,
        bitsPerComponent: 8,
        bytesPerRow: sizePx * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("ctx") }

    // Rounded-square black background, ~22% radius (matches Big Sur/macOS app icon shape).
    let radius = size * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()

    // Outer green glow (additive). Sample the bloom from our renderer.
    let glowAlpha: CGFloat = 0.18
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: size * 0.10,
        color: CGColor(red: 0, green: 1.0, blue: 0.40, alpha: glowAlpha)
    )
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Stack of three glyphs: head (white-green), mid-trail (bright green),
    // trail-tail (dim green). All mirrored horizontally for the Matrix
    // alien-katakana look.
    let fontSize = size * 0.30
    let font = CTFontCreateWithName("HiraginoSans-W3" as CFString, fontSize, nil)

    // Trail color stops (matches Shaders.metal trailColor function):
    //   head     → #DDFFDD
    //   trail-1  → #00FF66  (≈ trailDist 1)
    //   trail-8  → #008833  (≈ trailDist 8)
    let stack: [(glyph: String, color: CGColor)] = [
        (topGlyph,    CGColor(red: 0.87, green: 1.00, blue: 0.87, alpha: 1.00)),
        (middleGlyph, CGColor(red: 0.00, green: 1.00, blue: 0.40, alpha: 1.00)),
        (bottomGlyph, CGColor(red: 0.00, green: 0.53, blue: 0.20, alpha: 1.00))
    ]

    // Vertical layout: three glyph centers, evenly spaced about the
    // icon's vertical midpoint, span ~56% of icon height.
    let cellHeight = size * 0.28
    let topY = size * 0.78
    for (i, item) in stack.enumerated() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: item.color
        ]
        let attr = NSAttributedString(string: item.glyph, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        ctx.saveGState()
        let cellCenterY = topY - (CGFloat(i) * cellHeight)
        let dx = (size - bounds.width) / 2 - bounds.minX
        let dy = cellCenterY - bounds.height / 2 - bounds.minY
        ctx.translateBy(x: dx + bounds.width, y: dy)
        ctx.scaleBy(x: -1, y: 1)  // horizontal mirror
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in sizes {
    let data = renderIcon(sizePx: px)
    let url = iconsetDir.appendingPathComponent(name)
    try data.write(to: url)
    print("✓ \(name) (\(px)px)")
}

// Bundle into .icns via iconutil.
let icnsURL = outDir.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("✓ \(icnsURL.path)")
} else {
    print("✗ iconutil failed with status \(task.terminationStatus)")
    exit(1)
}
