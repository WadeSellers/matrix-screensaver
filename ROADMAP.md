# Matrix Roadmap

This document is the long-term plan for the Matrix project. The original
goal was a macOS screensaver. After hitting unsolvable Tahoe-era bugs in
`legacyScreenSaver`, we pivoted to a standalone macOS app that reuses the
existing `MatrixCore` Metal renderer.

The `.saver` bundle still exists in the repo (`MatrixSaver/`) for nostalgia
and as a cautionary tale, but is **deprecated**. The app is the future.

---

## Phase 1 — V1: Standalone Mac App (in progress)

The minimum viable app: launch it, get Matrix everywhere, dismiss with
input. Half a day of focused work.

- [ ] **1.1 — Target scaffolding.** Add `MatrixApp` target to `project.yml`.
  `LSUIElement = true` so no Dock icon. Reuses `MatrixCore` framework.
- [ ] **1.2 — Menu bar icon.** Single `NSStatusItem` showing a small Matrix
  glyph. Click → activate. Click again → dismiss. Right-click later for
  preferences and quit.
- [ ] **1.3 — Per-screen fullscreen takeover.** A `MatrixSession` class
  manages activation state. On activate: for each `NSScreen`, create a
  borderless `NSWindow` at `.screenSaver` level covering its full frame.
  Each window hosts a `MatrixLayerHost` (the same Metal renderer + display
  link we already wrote). Cursor hidden while active.
- [ ] **1.4 — Dismiss on input.** Global `NSEvent` monitor for mouse move,
  key down, scroll, magnify. Any input → tear down all windows, restore
  cursor, return to idle. Status icon goes "inactive."
- [ ] **1.5 — App icon and About box.** Real polish so it feels like an
  app, not a hack.
- [ ] **1.6 — Notarization-ready build pipeline.** A signed-and-notarized
  `.app` you can drag into Applications and run without "Open Anyway."

V1 ships with no settings window and no preferences — defaults baked in,
exactly what the `.saver` bundle has now (white-green head, 1.0× speed,
bloom on, CRT off). That's V2.1.

---

## Phase 2 — V2: Activation surface + settings

Now that the activation engine is solid, broaden how it gets triggered
and let you tune it.

- **2.1 Settings window** with live preview. Real `NSWindow` with
  ⌘, shortcut. Sliders/toggles for speed, bloom strength, CRT, head
  color, trail length, glyph swap rate. Changes propagate to active
  session immediately. Settings persist via `UserDefaults`.
- **2.2 Global keyboard shortcut.** Default ⌃⌥⌘M activates/dismisses.
  Configurable in Preferences. Uses `NSEvent.addGlobalMonitorForEvents`
  for the trigger, no Accessibility permission needed (just for trigger,
  not for blocking).
- **2.3 URL scheme.** `matrix://activate` and `matrix://dismiss`.
  Lets you wire it up via Raycast, Alfred, Stream Deck, AppleScript,
  Hammerspoon. One-line integration with anything that can open a URL.
- **2.4 Hot-corner via Shortcuts.app.** Provide a Shortcuts action so
  the user can map any hot corner (or any input) to Matrix.
- **2.5 Idle-timer auto-launch.** Built-in idle detection via IOKit's
  `kIOHIDIdleTimeKey`. Configurable threshold ("activate after N
  minutes idle"). This recreates the classic screensaver behavior under
  our control — and crucially, **works reliably** on Tahoe.
- **2.6 Quit confirmation.** Cmd-Q from menu bar item.

---

## Phase 3 — V3: Themes and visual extensions

Hot stuff once activation is solid.

- **3.1 Theme presets.** Drop-down in Preferences:
  - **Classic** (movie-accurate green)
  - **Reloaded** (more saturated, faster)
  - **Resurrections** (red/pink tint)
  - **CRT 1999** (heavy scanlines, low-res look, soft glow)
  - **Cyber** (custom — neon cyan / magenta)
- **3.2 Custom HSL color picker.** Pick your own head color, trail
  gradient stops. Save as a named theme. Import/export theme files.
- **3.3 Per-display config.** Different speed, bloom, theme on each
  monitor. Lets you do "subtle on the main, blazing on the secondary"
  setups.
- **3.4 User glyph sets.** Drop in your own font or PNG atlas. Halloween
  cyrillic, your kid's handwriting, Wingdings, whatever. Theme files
  reference glyph sets so the whole package travels together.

---

## Phase 4 — V4: Interactivity (the fun part)

Things screensavers fundamentally cannot do. The Matrix becomes
something you can poke at.

- **4.1 Type-to-glyph.** Press a key while Matrix is active → that
  character cascades down the screen as a brighter-than-normal head.
  Type "WAKE UP" and watch it ripple through the rain.
- **4.2 Click-to-seed.** Click anywhere → bright burst of cells radiating
  from the cursor that fades into the rain. Hold mouse down for a
  sustained spotlight effect.
- **4.3 Audio reactivity.** Sample system audio output via
  `AVAudioEngine` tap. Drive head intensity / fall speed / stammer
  rate / per-column flash from beat detection. Music makes it dance.
- **4.4 Konami code easter eggs.** ↑↑↓↓←→←→BA → Reloaded mode for 30s.
  Other secret codes for other modes.

---

## Phase 5 — V5: System-data integration

The Matrix isn't just rain — it's **your** rain, reflecting what's
happening on your machine.

- **5.1 Notification flares.** New macOS notification arrives → green
  flare blooms across the screen for 2 seconds, sender's name briefly
  visible woven into the rain.
- **5.2 Calendar integration.** "Meeting in 5 minutes" appears as a
  bright row of glyphs at a deterministic position. Configurable by
  calendar.
- **5.3 Time / weather embedding.** Subtle: real time embedded in the
  rain at a fixed position. Weather conditions tint the rain (rainy
  outside → faster, more density; clear → calmer, less stammer).
- **5.4 Custom data sources via URL scheme.** `matrix://text?value=DEPLOY`
  drops "DEPLOY" into the rain for a few seconds. Let CI pipelines
  notify you of deploys, etc.
- **5.5 Shortcuts.app actions.** Make Matrix scriptable. "Activate
  Matrix when I finish a Pomodoro" becomes a 5-second Shortcut.

---

## Phase 6 — V6: Cross-device sync (the office vision)

This is the one Wade asked for: when Matrix activates on the laptop, it
ripples to every screen in the room — the iPad on the desk, the Apple
TV on the wall, the phone on the dock — all running synchronized
Matrix. Office-wide takeover.

- **6.1 Companion iOS / iPadOS app.** Same `MatrixCore` framework,
  recompiled for UIKit/SwiftUI host. Renders the same Matrix on iPad
  / iPhone screens.
- **6.2 Local-network discovery via Bonjour / `NWConnection`.** Mac app
  publishes a `_matrix._tcp` service on the local network. Companion
  app listens. Devices register with each other automatically when on
  the same WiFi.
- **6.3 Sync protocol.** Tiny TCP/UDP messages over the local net:
  `ACTIVATE timestamp seed` and `DISMISS`. The seed makes the rain
  pattern identical across all devices — synchronized columns, same
  head positions, same glyphs at the same time.
- **6.4 Apple TV companion.** tvOS target running the same renderer.
  Mounts as ambient art when Matrix activates.
- **6.5 Lead/follower roles.** Leader (usually the laptop) drives
  activation. Followers pick up the seed and replay. Optional
  "follow-only" mode for devices that shouldn't be able to trigger
  activation themselves.

---

## Phase 7 — V7: Distribution polish

- **7.1 Sparkle auto-update.** Push releases via GitHub; users get
  in-app update prompts.
- **7.2 Mac App Store** (decision: free? paid? donations?). Tradeoff is
  sandbox restrictions vs. distribution reach.
- **7.3 Theme marketplace** — a `.matrixtheme` file format. People can
  share themes via GitHub or a small website.
- **7.4 Documentation site.** A real landing page with screenshots,
  videos, theme gallery, install instructions. Hosted on
  `wadesellers.com/matrix` or its own subdomain.

---

## Architecture invariant across all phases

`MatrixCore` is the renderer. It does not care about how it's hosted. It
takes a `CAMetalDrawable` and a size, and produces frames. Every host —
the deprecated `.saver` bundle, the upcoming Mac app, the future iOS
companion, the future tvOS companion — just provides a different way to
get drawables to the renderer.

This is why the work invested in `MatrixCore` so far transfers cleanly.
Every phase above reuses it.

---

## Open questions / blue sky

- **Live wallpaper mode.** Run as desktop background instead of
  fullscreen takeover. Productivity-friendly.
- **Picture-in-picture window mode.** Small Matrix window in a corner
  while you work.
- **Recording mode.** Capture Matrix as `.mov` for video calls, slide
  decks, screen-share backgrounds.
- **Vision Pro / spatial mode.** When the time comes.
