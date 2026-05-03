# Matrix Roadmap

Long-term plan for the Matrix project. The original goal was a macOS
screensaver. After hitting unsolvable Tahoe-era bugs in
`legacyScreenSaver`, we pivoted to a standalone menu-bar app that
reuses the existing `MatrixCore` Metal renderer.

The `.saver` bundle still exists in `MatrixSaver/` for nostalgia and as
a cautionary tale, but is **deprecated**. The app is the path forward.

---

## Status

- ✅ **Phase 1 — V1: Standalone Mac App** — shipped
- ✅ **Phase 2 — Activation surface + settings** — shipped, including
  idle timer rewritten on top of `NSEvent` global monitors after
  `IOHIDSystem.HIDIdleTime` proved unreliable on Wade's machine
- ✅ **Phase 3 — Theme Studio** — shipped (6 presets); hand-drawn
  variant explored and dropped — see Phase 3 notes
- ✅ **Phase 4 — Dynamic Wallpaper** — shipped
- 🎬 **Phase 5 — Scene Coalescing**
- ⚡ **Phase 6 — Commit Flare**
- 📡 **Phase 7 — Samsung Tablet Sync via Desk Quotes**
- 🥚 Parked: Easter eggs, full Apple cross-device cathedral, audio
  reactivity, notification flares (see "Open questions" at bottom)

---

## Phase 1 — V1: Standalone Mac App ✅

The minimum viable app: launch it, get Matrix everywhere, dismiss with
input. Shipped.

- [x] Target scaffolding — `MatrixApp` target, `LSUIElement = true`
- [x] Menu bar icon — `NSStatusItem`, click + right-click menu
- [x] Per-screen fullscreen takeover at `.screenSaver` window level
- [x] Dismiss on input via `NSEvent` local monitor
- [x] App icon (programmatically generated katakana stack) and About
- [x] Ad-hoc-signed installable build via `scripts/install-app.sh`

## Phase 2 — Activation surface + settings ✅

Broadened how Matrix gets triggered, plus a settings window with live
preview. Shipped.

- [x] Settings window (live preview as background — Wade's idea)
- [x] `matrix://activate` / `dismiss` / `toggle` / `preferences` URL
  scheme — usable by Raycast, Alfred, Stream Deck, Shortcuts, scripts
- [x] Idle-timer auto-launch via `NSEvent` global monitor (mouse,
  scroll, gestures — keyboard intentionally excluded so the
  Accessibility permission dialog never appears)
- [x] Edge-triggered firing — won't re-fire until user is active again
- [x] Auto-pause idle monitor and preview render when fullscreen
  session is active (no double-rendering)

---

## Phase 3 — Theme Studio ✅

Visible-payoff phase. Dropdown picker in Settings with film- and
dev-themed presets. Shipped.

- [x] **3.1 — Theme model.** `MatrixTheme` struct holding color
  triplets (head, near-trail, mid-trail, far-trail) and per-theme
  bloom / scanline / vignette multipliers.
- [x] **3.2 — Five presets:** `.classic` (Matrix Classic),
  `.resurrections`, `.amberCRT`, `.animatrix`, `.solarized`.
  (Reloaded was retired — too close to Classic to read distinctly in
  the picker, and the name implies a separation that doesn't really
  exist in the visual.)
- [x] **3.3 — Settings dropdown.** SwiftUI `Picker` with live
  propagation to active session and preview.
- ❌ **3.4 — Hand-drawn variant.** Tried twice and abandoned:
  - Path-jitter (perturb glyph Bezier control points before
    rasterisation, fill the wobbly outline). Math worked but the 7pt
    amplitude on a ~177pt font scaled down to ~0.6px on screen — sub-
    pixel, invisible after texture sampling.
  - Font swap (render the second atlas in `HiraMinProN-W3` instead of
    `HiraginoSans-W3`). Mincho's calligraphic stroke variation is real,
    but at the screen-size cell (~18px) it's still indistinguishable
    from the geometric sans.
  - Cut the feature entirely. The dual-atlas plumbing, `GlyphStyle`
    enum, and Settings toggle are all gone. If we revisit, the right
    next move is probably an actual handwritten font with explicit
    coverage at the rendered size, not a derivation of a clean font.

**Acceptance:** select each preset; live preview updates instantly;
relaunch, theme persists. ✅

---

## Phase 4 — Dynamic Wallpaper ✅

Live, animated Matrix as the desktop. Shipped.

- [x] **4.1 — Wallpaper window mode.** `MatrixWallpaperWindow`:
  borderless, `ignoresMouseEvents=true`, pinned at
  `CGWindowLevelForKey(.desktopWindow)`, `canBecomeKey=false`. One per
  `NSScreen`. Reuses `MatrixWindowContentView` for the layer-hosted
  Metal render — same renderer, different host.
- [x] **4.2 — Toggle in Settings.** "Use Matrix as desktop wallpaper"
  in a new Desktop section. Persists across launches.
- [x] **4.3 — Multi-screen handling.** `MatrixWallpaperManager`
  observes `didChangeScreenParametersNotification`; tears down and
  rebuilds the window set on screen plug/unplug or resolution change.
- [x] **4.4 — Session pause.** While a fullscreen Matrix session is
  active, the wallpaper is invisible underneath it — so the manager
  tears down its windows during the session and rebuilds them on
  dismissal. Saves a full second 60 fps render pass.

**Lock-screen behavior** (no code, just OS interaction): macOS captures
the wallpaper as a static image for the lock screen, so a frozen Matrix
frame appears on lock. Animation resumes on unlock.

---

## Phase 5 — Scene Coalescing 🎬

Rare moments where the rain forms a recognizable still from the first
film, then dissolves back. Uses actual film stills for the local build;
swappable to original art if ever distributed publicly.

- [ ] **5.1 — Mask shader pass.** New shader uniform: a fullscreen
  R8 mask texture and a `coalesceStrength` float (0.0 = pure rain,
  1.0 = fully formed image). The shader biases head selection / cell
  brightness toward bright pixels in the mask, weighted by strength.
- [ ] **5.2 — Curated still library.** ~6-8 high-contrast B&W mask
  textures derived from first-film moments (Neo in the pod, the green
  phone, "follow the white rabbit," lobby silhouette, Smith's
  sunglasses, hallway dodge). Bundled locally; `Resources/Stills/` is
  gitignored so they don't end up in the public repo.
- [ ] **5.3 — Trigger logic.** Configurable interval
  (`sceneIntervalMinutes`, default 15). On trigger: pick a random
  still, ramp `coalesceStrength` 0 → 1 over 0.8s, hold 0.5s, ramp back
  0.8s. Total ~2s per occurrence.
- [ ] **5.4 — Settings toggle.** "Show film moments" on/off. Default: on.

**Acceptance:** running for 15+ minutes produces at least one
recognizable moment. Effect feels organic, not jarring. Toggling off
fully disables it. Wade evaluates whether it ships in the public
README/branding.

---

## Phase 6 — Commit Flare ⚡

Tiny dopamine hit when you (or Claude Code on your behalf) push a git
commit. Best paired with Phase 4 — without wallpaper mode, the flare
only fires when the screensaver is already showing.

- [ ] **6.1 — `flare` URL action.** Add `matrix://flare` → 1-second
  white-bright accent on a single random column.
- [ ] **6.2 — Global git hook.** `post-push` hook installed via a
  one-shot script that calls `open matrix://flare`. Optional per-repo
  override.

---

## Phase 7 — Samsung Tablet Sync via Desk Quotes 📡

The "office cathedral" delivered for Wade's actual setup: when Matrix
activates on the Mac, the Samsung tablet's Desk Quotes display flips to
rain. When Matrix dismisses, it returns to quotes.

- [ ] **7.1 — Investigate Desk Quotes.** Read the repo, understand
  tech stack, pick integration approach (overlay layer in Desk Quotes
  vs. separate Matrix page the slideshow rotates to).
- [ ] **7.2 — Cloudflare Worker relay.** ~50 lines: WebSocket pub/sub
  keyed by a private room name. $0/mo on the free tier.
- [ ] **7.3 — Mac broadcast hook.** `MatrixSession.statusObserver`
  fires a fire-and-forget WebSocket message on every
  activate/deactivate. Local change happens immediately; broadcast
  happens in parallel.
- [ ] **7.4 — Web Matrix port.** JS + WebGL port of `MatrixCore` for
  the tablet. Trimmed scope: head + trail + glyph atlas, no bloom or
  CRT (keeps tablet CPU/GPU happy).
- [ ] **7.5 — Desk Quotes integration.** Cross-fade between quotes
  mode and Matrix mode on state change.

**Acceptance:** Mac goes idle → tablet flips to rain within ~200ms.
Mouse movement on Mac → tablet returns to quotes within ~200ms.

---

## Open questions / parked

Things we like but aren't building yet:

- **🥚 Easter eggs.** Once-an-hour rare coherent strings ("follow the
  white rabbit," "knock knock," "wake up Neo"); Konami-code →
  WAKE UP NEO across all columns; one-time red pill / blue pill
  onboarding gag in Preferences. Wade liked the idea but wants core
  features first. Sticky in the back pocket.
- **Full Apple cross-device cathedral.** iPad (Single App Mode), Apple
  TV, iPhone all running `MatrixCore` and syncing via the same Worker
  as Phase 7. Wade isn't running these as kiosk devices today. On
  hold until office setup changes.
- **Audio reactivity.** System audio drives column speeds / head
  intensity. Cool, not requested.
- **Notification flares.** Slack/email arrives → column lights up
  with sender. Cool, not requested.
- **Calendar awareness.** Meeting-in-5-min visual cue.
- **Picture-in-picture window mode.** Small Matrix window while you
  work. (Likely subsumed by wallpaper mode.)
- **Recording mode.** Capture as `.mov` for video calls.
- **visionOS / spatial mode.** When Wade owns one.

---

## Architecture invariant

`MatrixCore` is the renderer. It does not care about how it's hosted.
It takes a `CAMetalDrawable` and a size and produces frames. Every host
— the deprecated `.saver` bundle, the current Mac app, the upcoming
wallpaper window, the future web port — just provides a different way
to feed it drawables.

This is why work invested in `MatrixCore` transfers cleanly. Every
phase reuses it (the web port in Phase 7 is the only one that needs a
fresh implementation, in JS/WebGL).
