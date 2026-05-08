# Falling Code — App Store Connect Listing

Drafts for every text field in App Store Connect. Character counts are next to each heading. Limits noted in parentheses.

---

## 1. App Name *(12 / 30 chars)*

```
Falling Code
```

Well under the 30-char limit. Locked per spec.

---

## 2. Subtitle *(27 / 30 chars)*

```
Live digital rain wallpaper
```

**Why this:** "digital rain" is the single highest-volume search term for this aesthetic that doesn't trip the trademark. "Live wallpaper" signals the product's biggest differentiator versus the older `.saver`-bundle competitors on the store. Reads naturally, no keyword-stuffing smell.

**Alternates if you want a different angle:**
- `Cyberpunk code rain for macOS` *(29 chars — leans aesthetic over feature)*
- `Digital rain. Menu bar. Hotkey.` *(31 — over by 1, but punchy if trimmed)*
- `Green code rain on your desktop` *(31 — over by 1)*

---

## 3. Promotional Text *(155 / 170 chars)*

```
The green code from 1999, falling on your desktop in real time. Five themes, animated menu-bar icon, global hotkey, and a fullscreen takeover from any app.
```

Visible above the description, editable without resubmitting a build — good place for the hook. Leads with the cultural reference (1999) and lists the four standout features in one breath.

---

## 4. Description *(1,880 / 4,000 chars)*

```
If you've seen green code falling down a black screen, you'll recognize this.

Falling Code brings the digital rain — inspired by the iconic 1999 cypherpunk film — to every corner of your Mac. Mirrored half-width katakana streaming in green columns. White-green leading characters with soft bloom on the heads. Fading trails. Occasional stammer flickers. CRT scanlines and a gentle vignette. Built ground-up in Swift and Metal for Apple Silicon, so it runs cool and quiet at full frame rate.

— WHAT IT DOES —

• Live wallpaper — animated rain renders behind your icons all day
• Lock-screen still — your lock screen matches your current theme
• Animated menu-bar icon — a tiny live render that animates 24/7
• Global hotkey ⌃⌥⌘M — summon a fullscreen takeover from any app, even fullscreen ones, without losing focus
• Auto-activate on idle — full screensaver-replacement behavior, 1 to 30-minute threshold
• Themed popover menu — left-click the icon, the menu background is itself live rain
• Touch ID dismiss — finger-unlock lands you on a clean desktop, behind the lock screen

— FIVE COLOR THEMES —

• Classic — the green you remember
• Crimson — deep red phosphor
• Amber CRT — warm vintage terminal
• Sepia — paper and ink
• Solarized — desaturated developer palette

Click a tile in Preferences to switch. A live preview updates as you change settings.

— TECHNICAL —

• Swift + Metal, Apple Silicon native
• Hand-tuned bloom and CRT post-process
• Mirrored katakana glyph atlas (the alien-looking characters)
• Per-display rendering, no shared mutable state
• fallingcode:// URL scheme for Raycast, Alfred, Stream Deck, Hammerspoon
• Zero data collected. No network calls. No analytics.

Requires macOS 14 Sonoma or later. Apple Silicon only.

This is an unaffiliated, unofficial fan project. The Matrix and related marks are trademarks of Warner Bros. Entertainment Inc.
```

**Notes on the draft:**
- First sentence is the recognition hook — it's how a casual scroller decides to keep reading.
- Section breaks use em-dashes and ALL-CAPS headers, which render cleanly on App Store and break up the wall of text on a phone scroll.
- Bulleted feature lists where they earn it; paragraph form where they don't.
- Closing trademark disclaimer mirrors the README — defensible fair use, sets expectations.
- Aimed for ~1500 chars per spec; landed at 1,880. Slightly over target but every section earns its space — strip the Technical block if you want to come down to ~1,500.

**Tip for App Store Connect:** that 4,000-char ceiling is the *byte* limit on the platform; em-dashes and unicode bullets count as multiple bytes in some validators. If you see an over-limit error, swap `—` for `--` and `•` for `-`.

---

## 5. Keywords *(96 / 100 chars)*

```
katakana,cyberpunk,cypherpunk,1999,hacker,terminal,CRT,phosphor,green,glitch,screensaver,menubar
```

**Strategy:** Apple already weights every word in the App Name and Subtitle, so this field deliberately avoids "falling", "code", "digital", "rain", "live", "wallpaper" — those are covered. Every comma-separated entry here is a distinct search term someone might actually type. No spaces after commas (Apple's documented best practice — saves bytes, no SEO penalty). No repeats. No "matrix" — Apple's review team flags trademark terms in keywords as a rejection trigger.

Coverage of distinct intents:
- Aesthetic terms: katakana, cyberpunk, cypherpunk, hacker, glitch
- Era/cultural: 1999
- Visual qualities: CRT, phosphor, green
- Adjacent app categories: terminal, screensaver, menubar

**Backup terms** (if a future update changes app metadata and frees up budget): `desktop`, `animated`, `dynamic`, `mac`, `bloom`, `scanlines`, `retro`, `vintage`, `monochrome`, `geek`, `coder`.

---

## 6. What's New in This Version (v1.0) *(25 / 4,000 chars)*

```
Initial release. Welcome.
```

Short and confident. For a 1.0 there's nothing to update; the hype lives in Promotional Text.

---

## 7. Support URL

```
https://github.com/WadeSellers/matrix-screensaver/issues
```

Repo Issues tab is the right surface — users can search existing reports, file new ones, see your responses. Apple accepts GitHub URLs without complaint.

*Heads-up:* the repo name is `matrix-screensaver` (the codename), not `falling-code`. Reviewers won't care, but if you're rebranding the repo before submission, update this URL too.

---

## 8. Marketing URL *(optional — recommend filling it)*

**Recommended:**

```
https://github.com/WadeSellers/matrix-screensaver
```

The README functions as a marketing page: feature list, demo GIF, screenshot. Better than leaving the field blank (a blank Marketing URL is a small signal of unfinished listing to some reviewers).

**Alternatives to consider:**
- `https://wadesellers.com/falling-code` — if you want to stand up a one-page marketing site on your existing domain. Worth doing post-launch but not blocking for v1.0.
- Omit the field entirely — Apple doesn't require it.

My pick: **GitHub repo for v1.0. Move to wadesellers.com/falling-code in a later update once you have one.**

---

## 9. Privacy Policy URL *(required)*

**Recommended URL:**

```
https://github.com/WadeSellers/matrix-screensaver/blob/main/PRIVACY.md
```

**To make that URL valid, add `PRIVACY.md` to the repo root before submission. Suggested contents:**

```markdown
# Privacy Policy — Falling Code

Last updated: 2026-05-08

Falling Code does not collect, transmit, store, or share any personal data.

The app:

- Makes no network requests.
- Contains no analytics, telemetry, or tracking.
- Contains no advertising or third-party SDKs.
- Stores its settings (theme, speed, idle threshold, etc.) only in your local
  macOS user defaults on your own device. These settings never leave your Mac.
- Reads system idle state via standard macOS APIs solely to trigger the
  screensaver-replacement feature locally. No idle data is logged or sent.

If this ever changes in a future version, this policy will be updated and the
update will be called out in that version's release notes.

Questions: open an issue at
https://github.com/WadeSellers/matrix-screensaver/issues

— Wade Sellers
```

**Hosting alternatives:**
- A page on `wadesellers.com/privacy/falling-code` — slightly more "real" feeling than a GitHub blob URL. Equally accepted by Apple.
- A GitHub Pages deploy of the same markdown — overkill.

GitHub blob URLs work fine for App Review and are the lowest-friction option for v1.0.

---

## 10. Primary Category

```
Utilities
```

**Justification:** Falling Code is a desktop customization / system enhancement tool — it lives in the menu bar, replaces the screensaver, customizes the wallpaper. That's the textbook Utilities profile, and it aligns with similar apps already shelved there (Bartender, Rectangle, AlDente, Itsycal). Utilities is also a more commercially serious category than Entertainment for a paid app — buyers in Utilities have higher conversion intent.

---

## 11. Secondary Category

```
Entertainment
```

**Justification:** secondary slot expands discovery surface. The visual is fundamentally entertainment — a beautiful animation referencing a beloved film. Casts a wider net for the "I just want my Mac to look cool" buyer who's browsing Entertainment, not Utilities.

---

## 12. Age Rating

```
4+
```

**Justification:** zero objectionable content. No violence, no profanity, no in-app communication, no user-generated content, no web access, no data collection, no purchases inside the app. The age-rating questionnaire in App Store Connect should answer "None" to every category, which yields 4+ automatically.

---

## 13. Copyright

```
© 2026 Wade Sellers
```

Standard form. Year matches launch year per spec.

---

## Checklist before you submit

- [ ] Add `PRIVACY.md` to repo root with the text above
- [ ] Confirm `https://github.com/WadeSellers/matrix-screensaver/blob/main/PRIVACY.md` resolves
- [ ] Verify the repo Issues tab is enabled (Settings → Features → Issues)
- [ ] Take fresh App Store screenshots in all five themes (separate task, not text-side)
- [ ] Decide: keep the GitHub repo name `matrix-screensaver` or rename to `falling-code`? If renaming, update the two URLs above.
