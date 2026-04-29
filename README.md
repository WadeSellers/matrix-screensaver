# Matrix Screensaver

A screen-accurate macOS screensaver replicating the digital rain effect from *The Matrix* (1999) — green katakana streaming down a black screen, white-green leading characters, fading green trails, occasional stammer flickers, soft bloom, optional CRT post-process.

## Status

Active development. Currently at **Step 1 of 8** — project skeleton + black Metal view.

## Build

Requires Xcode 26+ and `xcodegen` (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -scheme SaverTest -configuration Release -derivedDataPath build build
open build/Build/Products/Release/SaverTest.app
```

The `SaverTest` host app embeds the same `MatrixView` used by the screensaver bundle in a regular `NSWindow`, so iteration is fast — no need to reinstall a `.saver` and re-trigger System Settings on every change.

## Architecture

Three Xcode targets generated from `project.yml`:

- **`MatrixCore`** — Metal renderer, glyph atlas, shaders, post-process pipeline. Shared framework consumed by both other targets.
- **`SaverTest`** — macOS app for fast iteration. Embeds `MatrixView` in an `NSWindow`.
- **`MatrixSaver`** — `.saver` bundle for installation to `~/Library/Screen Savers/`. (Added in Step 2.)

## Visual target

Glyphs painted in place on a fixed grid (head advances, trail fades — not falling). Head color `#DDFFDD`, trail gradient `#00FF66` → `#008833` → `#003311` → black over 12–20 cells. ~80 columns at 1080p, square cells. Fall speed 10–25 cells/sec, randomized per column. Glyphs hold ~3 frames with ~50% swap chance. ~1 in 5 columns gets a brighter "stammer" flicker. Dual-filter (Kawase) bloom. Optional CRT scanline post-process.

Glyph source: [Rezmason/matrix](https://github.com/Rezmason/matrix) — reconstructed from the official 2007 Matrix Online vector glyphs.

## License

TBD.
