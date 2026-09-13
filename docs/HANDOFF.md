# Falling Code — Handoff & Launch Runbook

> **Purpose:** cross-machine, cross-session continuity. If you're a new
> Claude Code session (on the MacBook, the Mac mini, or anywhere), read
> this first — it carries the context that doesn't live in code.
> **Keep it current:** whenever project state changes materially,
> update this doc in the same commit.

Last updated: 2026-09-13 (MacBook session — build 1 uploaded to Apple)

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
| App Store screenshots (9 @ 2880x1800, in `screenshots/`) | ✅ Done 2026-09-13 |
| Trademark cleanup (no "Matrix" in shipped UI or listing copy) | ✅ Done 2026-09-13 |
| `LSApplicationCategoryType` = Utilities | ✅ Done 2026-09-13 |
| **Release archive built + uploaded to App Store Connect** | ✅ **Done 2026-09-13, build 1** |

**Pricing decision (locked):** the app is **FREE**. Tips are the only
monetization. The tip jar is deliberately NOT mentioned in the App
Store description — users discover it via "Meet the maker."

## Open questions only Wade can answer

1. Was the **App Store Connect listing text** ever filled in? (Wade
   was about to paste it from `docs/app-store-listing.md` on
   2026-05-14. Still unconfirmed as of 2026-09-13.)
2. Did the **Small Business Program** application get approved?
   (Check App Store Connect → Business, or Apple confirmation email.
   Determines 15% vs 30% commission on tips. Not a launch blocker.)

~~Were the six theme screenshots ever taken?~~ — resolved 2026-09-13,
they weren't; shot fresh that night. See below.

---

## Remaining path to the App Store

Steps 1 and 3 are **done** (2026-09-13). What's left is steps 2 and 4,
both entirely inside App Store Connect.

### 1. Screenshots — ✅ DONE 2026-09-13

Nine shots live in `screenshots/`, all 2880×1800, ready to upload:

| File | Shot |
| --- | --- |
| `01-hero.png` | Fullscreen Classic rain, no overlay (store thumbnail) |
| `02-wallpaper-widgets.png` | Rain behind Calendar/Reminders widgets + sticky |
| `03-wallpaper-finder.png` | Rain behind a Finder window (list view) |
| `04-themes.png` | Preferences open on all six theme tiles |
| `05-theme-crimson.png` | Crimson fullscreen |
| `06-theme-cobalt.png` | Cobalt fullscreen |
| `07-theme-amber.png` | Amber CRT fullscreen |
| `08-decode.png` | The Decode, "THANK YOU" locked with signature line |
| `09-menubar.png` | Menu-bar popover open, live-rain background |

Source masters and screen recordings are in `screenshots/masters/`,
which is **gitignored** (~200MB).

**Correction to the old plan: the MacBook is NOT 16:10.** The Air
reports 2940×1912 in its current scaled mode (2560×1664 native) — no
Apple-accepted size matches. A raw ⇧⌘3 will be rejected. The fix used
here: resize to 1800px tall, then pad horizontally to 2880 on black.
Padding beats cropping because cropping 112px of height eats either the
menu bar or the dock. On the pure-black Decode frame, cropping to
2940×1838 → 2880×1800 was used instead (no menu bar or dock to
protect).

Sepia and Solarized were deliberately **left out**. Both are
low-contrast by design and read as washed-out gray at thumbnail size;
`04-themes.png` already proves they exist.

Capture gotchas worth remembering:
- Turn off ⇧⌘5 → Options → **Show Floating Thumbnail**, or it lands in
  the next shot.
- Clear the Desktop first. Stray screenshot and `.mov` files show their
  filenames in the shot.
- Screen recordings include the **mouse cursor** and the orange
  **recording indicator** in the menu-bar corner. Both had to be
  blacked out of `08-decode.png`.
- Densest rain frame wins. Shoot 4-5 and rank by mean luminance rather
  than eyeballing.

**App Preview video** (optional, up to 3, still not done): 15–30s,
.mov/.mp4 H.264, same resolution rules as screenshots, silent.

### 2. Fill in the App Store Connect listing — ⬜ REMAINING (if not already done)

Open `docs/app-store-listing.md` side-by-side with App Store Connect →
Falling Code → macOS App → version 1.0. Every field maps to a numbered
section in that doc (name, subtitle, promo text, description,
keywords, URLs, categories, age rating, copyright). Also:

- **Pricing and Availability → Free**, all countries
- **App Information:** SKU (suggest `FALLINGCODE001`), primary
  language English (U.S.), bundle ID `com.wadesellers.cipherfall`
  (already bound)
- Age rating questionnaire: answer "None" to everything → 4+

### 3. Release archive build + upload — ✅ DONE 2026-09-13

**Build 1 uploaded to App Store Connect at 04:29 UTC on 2026-09-13,
zero errors.** Apple ID `6767600495`. This was the one piece of the
pipeline that had never been exercised; it works.

What the archive is built from:

- Scheme **MatrixApp** — the only shared scheme, generated by xcodegen
  from `scheme: {}` in project.yml.
- Its **Archive action uses Release**; Run/Test/Analyze use Debug.
  That split is why `#if DEBUG` code and the scheme's StoreKit
  configuration can never reach a shipped build.

Command used (headless, no Xcode UI needed for the archive itself):

```
xcodebuild -project MatrixSaver.xcodeproj -scheme MatrixApp \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath ~/Library/Developer/Xcode/Archives/<date>/<name>.xcarchive \
  -allowProvisioningUpdates archive
```

The **upload** still needs Xcode's UI (it carries the Apple ID
session): Window → Organizer → Distribute App → App Store Connect →
Upload.

Gotchas:
- **Organizer files archives under the scheme name**, not the app name.
  Look for **MatrixApp**, not "Falling Code", in the sidebar.
- If the Metal shader compile fails with "missing Metal Toolchain,"
  run `xcodebuild -downloadComponent MetalToolchain` (~700MB). Has now
  bitten three times (May 2026, Sept 12 2026, Sept 13 2026) — assume
  it recurs after every major Xcode update.
- The archive's recorded `SigningIdentity` reads `Apple Development`.
  That's expected — Xcode re-signs with Apple Distribution during the
  Distribute step.
- For a second upload (rejected build, forgotten asset), bump
  `CFBundleVersion`/`CURRENT_PROJECT_VERSION` from 1 → 2 in project.yml
  (all four targets). Marketing version stays 1.0.0.
- Export compliance: the app uses only HTTPS → exempt encryption.
  `ITSAppUsesNonExemptEncryption: false` is still **not** set in
  project.yml; adding it would suppress the question on future uploads.

### 4. Assemble the version page + submit — ⬜ REMAINING

On the App Store Connect version 1.0 page, after the build finishes
processing:

1. **Build section** → select the uploaded build.
2. **In-App Purchases and Subscriptions section** → attach all three
   tip IAPs (coffee / lunch / awesome) so they go through review with
   the app (required for FIRST submission — IAPs can't be reviewed
   standalone until the app itself has shipped once).
3. Upload the nine screenshots from `screenshots/` (app preview video
   optional, still unmade).
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

**The Xcode StoreKit test payment sheet is broken on macOS (Xcode
26.6):** it renders the product card and a Cancel button but *no
confirm button*, and Return does nothing. A purchase cannot be
completed, so the Decode animation can't be reached that way.

Workaround, added 2026-09-13: a `#if DEBUG` URL route fires the Decode
directly with a real `Product`, no payment sheet.

```
open -a <path-to-Debug-build>/"Falling Code.app" "fallingcode://decode"
```

Optional `?tier=coffee|lunch|awesome`; defaults to the top tier. Lives
in `AppDelegate.application(_:open:)` and is verified absent from the
Release binary.

**Always target the bundle explicitly with `open -a`.** A bare
`open "fallingcode://..."` asks LaunchServices to pick a handler, and
this machine has **three** copies of Falling Code registered under the
same bundle ID (stale DerivedData builds). It will silently launch the
wrong one — which looks exactly like the URL scheme being broken.

### Credentials (never in the repo)

All in Wade's Apple Passwords: Cloudflare login, GitHub PAT,
APP_SECRET reference copy, Cloudflare account ID. Signing
certificates live in the Keychain / Apple Developer portal.

---

## Development conventions

- **Commit style:** `Topic: short description` + body when useful.
  Attribution trailer per current tooling (as of Sept 13 2026:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`).
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
- `screenshots/` — the nine App Store screenshots (masters gitignored)
- `ROADMAP.md` — long-term phases (Scene Coalescing, Commit Flare, tablet sync…)
- `PRIVACY.md` — privacy policy (App Store Privacy Policy URL points here)
