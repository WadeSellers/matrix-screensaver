# Falling Code — Handoff & Launch Runbook

> **Purpose:** cross-machine, cross-session continuity. If you're a new
> Claude Code session (on the MacBook, the Mac mini, or anywhere), read
> this first — it carries the context that doesn't live in code.
> **Keep it current:** whenever project state changes materially,
> update this doc in the same commit.

Last updated: 2026-09-12 (Mac mini session, pre-submission)

---

## Where the project stands

Falling Code is **feature-complete for v1.0** and has been since May
2026. Everything below is DONE, shipped to `main`, and verified:

| Area | State |
| --- | --- |
| Core app (rain renderer, wallpaper, fullscreen, hotkey, idle) | ✅ Done |
| Tip jar (3 Consumable IAPs via StoreKit 2) | ✅ Code done, tested in Xcode StoreKit sandbox |
| IAP records in App Store Connect | ✅ Created, all three were "Ready to Submit" as of May 2026 |
| Decode thank-you animation (fullscreen Easter egg on tip) | ✅ Done |
| Onboarding red/blue pill choice (rain inside the capsules) | ✅ Done |
| Six themes (Classic, Crimson, Cobalt, Amber CRT, Sepia, Solarized) | ✅ Done |
| "Meet the maker" (replaces About; jumps to Support tab) | ✅ Done |
| Feedback → Cloudflare Worker → GitHub Issues | ✅ Done, live, health-checked Sept 2026 |
| FAQ (`docs/FAQ.md`, linked from Support tab) | ✅ Done |
| Privacy policy (`PRIVACY.md`) | ✅ Current (discloses tips + feedback flows) |
| MIT license (`LICENSE`) | ✅ Done |
| Version 1.0.0 (project.yml + all four Info.plists) | ✅ Done; `CFBundleVersion` = 1 |
| App Store listing copy (`docs/app-store-listing.md`) | ✅ Drafted & current (six themes, free app) |
| W-9 tax form in App Store Connect | ✅ Done (May 2026) |
| Small Business Program | ✅ Applied May 2026 — approval status unconfirmed |
| App icon (menu-bar code-fall design, Asset Catalog) | ✅ Done |

**Pricing decision (locked):** the app is **FREE**. Tips are the only
monetization. The tip jar is deliberately NOT mentioned in the App
Store description — users discover it via "Meet the maker."

## Open questions only Wade can answer

1. Was the **App Store Connect listing text** ever filled in? (Wade
   was about to paste it from `docs/app-store-listing.md` on
   2026-05-14. Unconfirmed since.)
2. Were the **six theme screenshots** ever taken? (Planned for the
   MacBook, never confirmed.)
3. Did the **Small Business Program** application get approved?
   (Check App Store Connect → Business, or Apple confirmation email.
   Determines 15% vs 30% commission on tips. Not a launch blocker.)

---

## Remaining path to the App Store

Four steps, in order:

### 1. Screenshots (MacBook — Wade's hands)

Apple accepts 1280×800 / 1440×900 / 2560×1600 / **2880×1800** (best),
16:10, PNG. Up to 10 screenshots. Use the MacBook (native 16:10 —
the AOC 4K monitors are 16:9 and would need cropping).

Recommended 7-shot sequence (screenshot #1 is the store thumbnail):

1. **Hero** — fullscreen rain, Classic green, NO text overlay
2. **Live wallpaper context** — real desktop, 2-3 app windows
   (Finder, terminal), rain visible behind icons, dock visible,
   no personal info anywhere
3. **Theme gallery** — Preferences open showing all six theme tiles
4. **Alternate theme fullscreen** — Cobalt (or Crimson)
5. **Preferences General tab** — speed slider + activation options
6. **The Decode** — "THANK YOU" mid-reveal (screen-record the
   animation, scrub in QuickTime, screenshot the best frame)
7. **Menu bar close-up** — the animated icon (⇧⌘4 selection capture)

Optional text overlays on #2–#7 only (3-5 words, small, monospaced);
keep #1 pure. Figma has free Mac App Store templates if desired —
raw screenshots are acceptable too.

**App Preview video (recommended, up to 3 allowed):** 15–30s,
.mov/.mp4 H.264, same resolution as screenshots, silent. Capture via
⇧⌘5 → Record Entire Screen. Suggested cut: fullscreen Classic (4s) →
Cobalt (4s) → Crimson (4s) → wallpaper-behind-windows (4s) → Decode
animation (4s). iMovie is fine for cuts.

### 2. Fill in the App Store Connect listing (if not already done)

Open `docs/app-store-listing.md` side-by-side with App Store Connect →
Falling Code → macOS App → version 1.0. Every field maps to a numbered
section in that doc (name, subtitle, promo text, description,
keywords, URLs, categories, age rating, copyright). Also:

- **Pricing and Availability → Free**, all countries
- **App Information:** SKU (suggest `FALLINGCODE001`), primary
  language English (U.S.), bundle ID `com.wadesellers.cipherfall`
  (already bound)
- Age rating questionnaire: answer "None" to everything → 4+

### 3. Release archive build + upload (either Mac; MacBook is fine)

Never done yet — this is the one piece of the pipeline that hasn't
been exercised. The `scripts/install-app.sh` path is ad-hoc-signed
local install ONLY; App Store needs a distribution archive:

1. Prereq: Xcode signed into Wade's Apple ID (Xcode → Settings →
   Accounts), team `GV76VP4G8V`.
2. `xcodegen generate` in the repo root (regenerates the project;
   scheme comes back automatically thanks to `scheme: {}` in
   project.yml).
3. Open `MatrixSaver.xcodeproj`, select the **MatrixApp** scheme,
   destination **My Mac**.
4. **Product → Archive** (builds Release + archives).
5. Organizer window opens → select the archive → **Distribute App**
   → **App Store Connect** → **Upload** → accept the automatic
   signing prompts (Xcode will mint the Apple Distribution cert +
   Mac App Store provisioning profile on first run).
6. Wait for the "processing completed" email from Apple (~5-30 min).

Gotchas:
- If the Metal shader compile fails with "missing Metal Toolchain,"
  run `xcodebuild -downloadComponent MetalToolchain` (~700MB). This
  recurs after most major Xcode updates — it has bitten twice
  (May 2026, Sept 2026).
- If a second upload is ever needed (rejected build, forgotten
  asset), bump `CFBundleVersion`/`CURRENT_PROJECT_VERSION` from 1 →
  2 in project.yml first (all four targets). Marketing version
  stays 1.0.0.
- App Store Connect will ask about **export compliance /
  encryption**: the app uses only HTTPS (feedback submission) →
  answer that it uses only exempt encryption. Optionally add
  `ITSAppUsesNonExemptEncryption: false` to the MatrixApp target's
  Info properties in project.yml to suppress the question on
  future uploads.

### 4. Assemble the version page + submit

On the App Store Connect version 1.0 page, after the build finishes
processing:

1. **Build section** → select the uploaded build.
2. **In-App Purchases and Subscriptions section** → attach all three
   tip IAPs (coffee / lunch / awesome) so they go through review with
   the app (required for FIRST submission — IAPs can't be reviewed
   standalone until the app itself has shipped once).
3. Upload the screenshots + app preview video.
4. **Submit for Review.** Typical Mac App Review turnaround: 1-3 days.

---

## Operational reference

### Cloudflare Worker (feedback backend)

- **URL:** `https://falling-code-feedback.wadesellers.workers.dev/submit`
- **Source:** `worker/falling-code-feedback.js` + `worker/wrangler.toml`
- **Secrets** (stored in Cloudflare, set via `wrangler secret put`):
  `GITHUB_TOKEN` (fine-grained PAT, Issues R+W on this repo only) and
  `APP_SECRET` (matches the constant in
  `MatrixApp/FeedbackManager.swift` — public by design; see the
  comment there).
- **Health check** (expects 401, creates nothing):
  `curl -s -o /dev/null -w "%{http_code}" -X POST <URL> -H "Content-Type: application/json" -d '{"kind":"bug","title":"x","description":"y"}'`
- **Redeploy** (only needed if worker JS changes): `wrangler login`
  once per machine, then `wrangler deploy` from `worker/`.
- **Live logs:** `wrangler tail` from `worker/`.
- Cloudflare account: wade@wadesellers.com (credentials in Apple
  Passwords). Worker survives indefinitely with zero maintenance.

### GitHub PAT (used by the Worker)

- Fine-grained token `falling-code-feedback`, scoped to Issues
  R+W on `WadeSellers/matrix-screensaver` only.
- **Expires ~May 2027.** Wade has a calendar reminder (~2027-04-25).
- Rotation dance: GitHub → Settings → Personal access tokens →
  regenerate → `wrangler secret put GITHUB_TOKEN` → paste → done.
  Also update the copy in Apple Passwords.

### IAP catalog

See `docs/iap-products.md`. Product IDs (hardcoded in
`MatrixApp/TipJarManager.swift`, must match App Store Connect):

- `com.wadesellers.cipherfall.tip.coffee` — $2.99
- `com.wadesellers.cipherfall.tip.lunch` — $9.99
- `com.wadesellers.cipherfall.tip.awesome` — $19.99

All Consumable. Local testing: attach `Configuration.storekit` to the
MatrixApp scheme (Edit Scheme → Run → Options → StoreKit
Configuration). **This attachment is per-machine, per-scheme, and is
WIPED every time xcodegen regenerates the project** — re-attach it
whenever you need IAP testing after a regen.

### Credentials (never in the repo)

All in Wade's Apple Passwords: Cloudflare login, GitHub PAT,
APP_SECRET reference copy, Cloudflare account ID. Signing
certificates live in the Keychain / Apple Developer portal.

---

## Development conventions

- **Commit style:** `Topic: short description` + body when useful.
  Attribution trailer per current tooling (as of Sept 2026:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`).
- **Never `git add .`** — stage files explicitly. `.claude/` (local
  IDE state) and `worker/.wrangler/` (Cloudflare cache, holds the
  account ID) must never be committed; the latter is gitignored.
- **`MatrixSaver.xcodeproj` is generated** — never hand-edit;
  change `project.yml` and run `xcodegen generate` (install-app.sh
  does this automatically). The project file is gitignored.
- **Info.plists are tracked AND regenerated** by xcodegen from
  project.yml. When project.yml changes version/properties, commit
  the regenerated plists in the same commit.
- **Parallel Claude sessions** work well for scoped tasks (FAQ,
  license, version bump were all done this way). Pattern: a
  self-contained prompt with context / exact steps / content / repo
  conventions / done-criteria. Sessions land on `claude/*` branches →
  PR → merge. Plan mode only when the task has real design decisions
  in it.
- **The wallpaper render loop uses CVDisplayLink** (deprecated but
  deliberate) — `screen.displayLink(...)` gets throttled to ~2fps on
  desktop-level windows. Don't "modernize" this without re-testing
  the pause bug (see commit `75c53fc`).

## Doc index

- `docs/app-store-listing.md` — every App Store Connect text field, ready to paste
- `docs/iap-products.md` — IAP catalog + StoreKit testing setup
- `docs/feedback-feature.md` — feedback feature design (app + Worker)
- `docs/FAQ.md` — user-facing FAQ (linked from the app's Support tab)
- `docs/HANDOFF.md` — this file
- `ROADMAP.md` — long-term phases (Scene Coalescing, Commit Flare, tablet sync…)
- `PRIVACY.md` — privacy policy (App Store Privacy Policy URL points here)
