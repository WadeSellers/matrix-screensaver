# Matrix Screensaver

A screen-accurate macOS screensaver that replicates the digital rain effect from *The Matrix* (1999): mirrored half-width katakana flowing in green columns down a black screen, white-green leading characters, fading green trails, occasional stammer flickers, soft bloom on the heads, optional CRT post-process.

Built in Swift + Metal for macOS Sequoia (14.0+) and Apple Silicon. Runs at 60fps on a 2022 MacBook Air M2; auto-throttles to 30fps on battery or under thermal pressure.

## Install

Requires Xcode 26+, Apple Silicon, and `xcodegen` (`brew install xcodegen`).

```bash
git clone https://github.com/WadeSellers/matrix-screensaver.git
cd matrix-screensaver
./scripts/install.sh
```

The script regenerates the Xcode project, builds Release, ad-hoc codesigns, copies the bundle to `~/Library/Screen Savers/MatrixSaver.saver`, and kills `legacyScreenSaver` so the new build picks up immediately.

Open **System Settings → Screen Saver**, pick **MatrixSaver**, click **Test**.

### Gatekeeper note

Sequoia tightened Gatekeeper. The first time you select MatrixSaver you may see "MatrixSaver can't be opened" — the bundle is ad-hoc signed, not notarized. Fix:

**System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to the MatrixSaver entry.

## Configure

Click **Screen Saver Options…** in System Settings.

- **Speed** — global multiplier from 0.5× to 2.0×.
- **Bloom glow on heads** — soft halo around white-green leading characters. On by default.
- **CRT mode** — adds horizontal scanlines and a soft radial vignette. Off by default.

Settings persist in `ScreenSaverDefaults` per the bundle module name.

## Iteration

`SaverTest` is a regular macOS app target that hosts the same `MatrixView` in an `NSWindow` — much faster to iterate against than reinstalling the `.saver` and re-triggering System Settings on every change.

```bash
xcodegen generate
xcodebuild -scheme SaverTest -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/SaverTest.app
```

In SaverTest:
- **⌘N** new window (test multi-renderer isolation)
- **⌘T** toggle CRT
- **⌘B** toggle bloom
- **⌘-** / **⌘=** slower / faster

## Architecture

Three Xcode targets generated from `project.yml`:

| Target | Type | What |
| --- | --- | --- |
| `MatrixCore` | macOS framework | Renderer, glyph atlas, shaders, post-process. Shared. |
| `SaverTest` | macOS app | Iteration host; mirrors per-screen renderer model. |
| `MatrixSaver` | `.saver` bundle | Ships to `~/Library/Screen Savers/`. |

### Render pipeline

```
columns ──► sceneTexture ──► [extract] ──► [blur H] ──► [blur V] ──► [composite + CRT] ──► drawable
                                       ╲                           ╱
                                        bloomA / bloomB (half-res ping-pong)
```

- **Column shader** (`fragment_columns`): one fullscreen-triangle pass. For each fragment, derives `(col, row)` from pixel coords, looks up the column's `headRow` from a per-column buffer, computes `trailDist = headRow - row`, and emits the color from a piecewise gradient (#DDFFDD head → #00FF66 → #008833 → #003311 → black). Per-cell glyph index is `hash3(col, row, seed ^ frameBucket) mod glyphCount`; trail glyphs are stable per `(col, row, seed)`, head glyphs cycle every 3 frames.
- **Glyph atlas** (`GlyphAtlas`): 2048×2048 R8 single-channel texture built once at startup. ~64 glyphs from mirrored half-width katakana + Latin digits + symbols, rendered via Core Text + Hiragino Sans into a flipped CGContext. Mirroring the katakana is what produces the "alien" Matrix look.
- **Bloom** (`BloomPipeline`): half-resolution ping-pong. Threshold extract pulls only pixels above luminance 0.55 (so heads bloom but trails don't smear). Two-pass separable 9-tap Gaussian. Composite adds at 0.85 strength.
- **CRT post-process**: bundled into `fragment_bloom_composite` as a uniform-driven optional path. Crisp every-6-pixel scanlines, radial vignette.

### Lifecycle

- `MatrixSaverView` (`ScreenSaverView` subclass) listens for `com.apple.screensaver.willstop` distributed notifications and calls `exit(0)` — Sonoma's `stopAnimation()` is unreliable.
- `MatrixView` observes `ProcessInfo.thermalStateDidChangeNotification`, `NSWorkspace.willSleepNotification`, and `NSWorkspace.didWakeNotification`. Pauses on sleep, unpauses on wake, drops framerate via `PowerProfile`:
  - `nominal` (plugged + cool) → 60fps, full bloom
  - `balanced` (battery or `.fair` thermal) → 30fps, full bloom
  - `low` (`.serious` / `.critical` thermal) → 20fps, no bloom
- Per-screen state is automatic — macOS instantiates one `ScreenSaverView` per `NSScreen`, and each one creates its own `MatrixView` + `MatrixRenderer` (no shared mutable state).

## Known limitations

- **Multi-display: only the primary screen renders.** On macOS Sequoia (15) and Tahoe (26), `legacyScreenSaver` instantiates a `ScreenSaverView` for each connected display but mounts the secondary display's window at coordinates that don't intersect any `NSScreen`, so the rendered frames never reach the panel. We attempt a runtime workaround (find the matching `NSScreen` and call `setFrame` to the correct origin), but the framework silently reverts our `setFrame` — the OS owns window placement here and ignores plugins. Apple's own native screensavers go through a separate `.appex` API that's not exposed to third parties. **Workaround:** if you want both displays dark when the screensaver triggers, switch your external monitor's input to a different source before walking away, or set its energy-saver to sleep on a short idle.

## Visual reference

Color stops, fall speed, glyph swap rate, and trail length come from [carlnewton's frame analysis](https://carlnewton.github.io/digital-rain-analysis/) and the defaults in [Rezmason/matrix](https://github.com/Rezmason/matrix). The film itself has no published spec.

## License

TBD. The code is yours to read; the `Hiragino Sans` font is shipped with macOS and used at runtime via Core Text (no font is bundled in this repo).
