# In-app feedback → GitHub Issues

## Context

The Support tab has a meet-the-maker beat and a way to tip, but no way to
actually *talk* to the maker. Wade wants the same flow the Usage for Claude
app demonstrates: a "Send Feedback" card that opens a small floating form
(Bug or Feature, title, description, optional email), submits to a backend,
and shows a success screen with the resulting **issue number** — implying
the submission becomes a real GitHub Issue on the public repo.

The good news: this is **fully free** to run at any reasonable scale.

- **Cloudflare Workers** free tier: 100,000 requests/day. We'll use maybe
  dozens, ever.
- **GitHub Issues API**: free for public repos.
- No paid services. The whole pipeline is App → Cloudflare Worker →
  GitHub Issues API → response with `issueNumber`.

The Worker exists because we can't ship a GitHub personal-access token
inside the app binary (anyone who decompiles the app would steal it). The
Worker keeps the token as a secret and proxies submissions on the app's
behalf. ~50 lines of JS. One-time deploy.

### Decisions confirmed

- **Launch surface:** A FAQ card and a Feedback card side-by-side below
  the three tip cards. Matches the Usage-for-Claude reference exactly.
  FAQ for v1.0 simply links to the repo README (no FAQ content to write
  yet — that's a future task).
- **GitHub target:** Existing `WadeSellers/matrix-screensaver` repo.
  Submissions get the `feedback` label plus `bug` or `enhancement`
  depending on the user's toggle. Filter the Issues tab by `feedback` to
  see only user-submitted reports.

---

## Implementation

The work splits into four phases. Phase A and D are pure app/repo work I
can do without you. Phases B and C need ~15 minutes of your time setting
up Cloudflare and labels (with me walking you through each click).

### Phase A — App side (Swift / SwiftUI)

#### A1. New `MatrixApp/FeedbackController.swift`

Mirrors `OnboardingSheetController`. Owns a floating `NSPanel` (titled,
closable, `.hudWindow`, level `.floating`, draggable by background) that
hosts a SwiftUI `FeedbackView`. Presents from `AppDelegate` on user
request, dismisses on close button or after a successful submission.
Uses the same activation-policy dance OnboardingSheetController already
uses (`.regular` while panel is up, restore `.accessory` on close) so the
panel reliably comes to front from an `LSUIElement` app.

#### A2. New `MatrixApp/FeedbackManager.swift`

`@MainActor @Observable`. Owns the submit flow.

- Holds form state: `kind: FeedbackKind` (`.bug` / `.feature`), `title`,
  `description`, `email`.
- `submit() async` — builds a JSON payload, POSTs to a hardcoded Worker
  URL constant (`https://falling-code-feedback.<wade>.workers.dev/submit`),
  parses `{ issueNumber: Int, url: String }` from the response, exposes
  `submissionResult: .idle / .submitting / .success(Int) / .failure(String)`.
- Includes auto-collected device info in the payload — keep it minimal:
  app version, app build, macOS version string, locale identifier. No
  hardware model, no user identifiers, no IP (Worker will see IP but
  doesn't log it). All readable via `Bundle.main` + `ProcessInfo`, both
  already imported elsewhere in the app.
- Includes a static `X-App-Secret` header so the Worker can reject random
  internet POSTs. Reverse-engineerable but raises the bar against bots.

#### A3. New `MatrixApp/FeedbackView.swift`

The SwiftUI form. Visual structure (top to bottom):

```
┌──────────────────────────────────────────┐
│ 🪲  Send Feedback                        │
│     Report an issue you've encountered   │
│                                          │
│   ┌─────────────┐  ┌─────────────┐       │
│   │ 🪲 Bug      │  │ ✨ Feature  │       │
│   └─────────────┘  └─────────────┘       │
│                                          │
│ TITLE                                    │
│ ┌──────────────────────────────────────┐ │
│ │ Brief summary of your feedback       │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ DESCRIPTION                    0 / 1000  │
│ ┌──────────────────────────────────────┐ │
│ │                                      │ │
│ │ Please describe in detail…           │ │
│ │                                      │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ ✉️  EMAIL  (Optional)                    │
│ ┌──────────────────────────────────────┐ │
│ │ email@example.com                    │ │
│ └──────────────────────────────────────┘ │
│ So we can reach out for more details     │
│                                          │
│ 📱 Device information will be included   │
│                                          │
│             [ Submit Feedback  ➤ ]       │
└──────────────────────────────────────────┘
```

Two-step state. Once `submit()` returns `.success(issueNumber)`, the
whole form swaps out for a success view:

```
            ┌──────────┐
            │    ✓     │
            └──────────┘

         Feedback Sent

   Thank you! Your feedback helps
       us improve the app.

         ┌─────────────┐
         │  # Issue #316  │
         └─────────────┘

           [    Done    ]
```

The `Done` button calls the controller's dismiss path.

Visual language: reuses the `Color.white.opacity(0.06)` fill /
`Color.white.opacity(0.15)` stroke / `cornerRadius: 12` recipe from the
tip cards. Submit button is filled Matrix green like the "Get Started"
button in the onboarding sheet. Bug/Feature toggle is a 2-segment custom
control matching the General/Support tab pill recipe (selected state =
green background, black text).

#### A4. Modify `MatrixApp/SupportView.swift`

Insert a new HStack of two cards between the existing `cardRow` (tip
cards) and the footer:

```swift
HStack(spacing: 12) {
    faqCard      // links out to GitHub README in default browser
    feedbackCard // opens the Feedback window via AppDelegate
}
```

Each card: same RoundedRectangle recipe as the tip cards but with an
icon + 2 lines of text (label + subtitle). Heights ~80pt so the row
doesn't push the footer off-screen.

Bump window height (`SettingsWindowController` line 75) from 560 to
about 640 to fit. Then re-check spacings as before — we may need to
tighten VStack gaps to 12.

#### A5. Modify `MatrixApp/AppDelegate.swift`

Add a `FeedbackController` instance and an `openFeedback()` method.
Pass a callback into `SettingsWindowController` so the new "Feedback"
card can trigger it (same way `onMeetTheMaker` is plumbed).

---

### Phase B — Cloudflare Worker (one-time setup)

#### B1. New file `worker/falling-code-feedback.js`

Single-file Worker, ~70 lines. Pseudocode:

```js
export default {
  async fetch(request, env) {
    if (request.method !== "POST" || pathname !== "/submit") return 404;
    if (header("X-App-Secret") !== env.APP_SECRET)            return 401;
    const { kind, title, description, email, deviceInfo } = await json();
    validate(...);                                            // length caps
    const body = buildMarkdown({ description, email, deviceInfo });
    const labels = ["feedback", kind === "bug" ? "bug" : "enhancement"];
    const issue = await githubAPI.createIssue({
      repo: "WadeSellers/matrix-screensaver",
      title: `[${kind === "bug" ? "Bug" : "Feature"}] ${title}`,
      body, labels,
      token: env.GITHUB_TOKEN,
    });
    return Response.json({ issueNumber: issue.number, url: issue.html_url });
  }
}
```

GitHub issue body markdown structure:

```markdown
<user's description>

---

<details>
<summary>Device info</summary>

- App: Falling Code 0.1.0 (build 1)
- macOS: 14.5 (Build 23F79)
- Locale: en_US

</details>

<!-- Contact: wade@example.com -->   ← only if email provided
```

Email is in an HTML comment so it's there for Wade when he opens the
issue but not displayed in the public-facing rendered view. Lightweight
privacy hedge.

#### B2. Cloudflare account + wrangler

You'll do this part once, walked through:

1. Sign up at cloudflare.com (free).
2. `npm install -g wrangler` (or `brew install cloudflare-wrangler`).
3. `wrangler login`.
4. From `worker/`: `wrangler init`, then drop in the JS file above.
5. Set two secrets:
   - `wrangler secret put GITHUB_TOKEN` — paste a fine-grained PAT with
     **Issues: Read + Write** on `matrix-screensaver`.
   - `wrangler secret put APP_SECRET` — any random string; same string
     gets hardcoded into `FeedbackManager.swift` as the
     `X-App-Secret` header value.
6. `wrangler deploy`. You get a URL like
   `https://falling-code-feedback.<your-name>.workers.dev`.
7. Paste that URL into the `submitURL` constant in `FeedbackManager.swift`.

Total time: ~15 minutes if you've never used Cloudflare; ~3 minutes
if you have.

#### B3. Abuse protections (already in the Worker)

- Reject non-POST methods.
- Reject missing `X-App-Secret`.
- Reject payloads with missing required fields, title > 200 chars, or
  description > 5000 chars.
- Cloudflare's edge applies basic rate limiting and bot detection
  automatically.

If spam ever becomes a problem, we can add per-IP rate limits via
Cloudflare's KV store. Not needed at the scale you'll be at.

---

### Phase C — GitHub repo setup

#### C1. Create three labels on `WadeSellers/matrix-screensaver`

Via the repo's `Issues → Labels` UI, ensure these exist (GitHub creates
`bug` and `enhancement` by default for new repos; verify they're there):

| Label | Color | Purpose |
| --- | --- | --- |
| `feedback` | gray-ish (e.g. `#D1D5DB`) | All user-submitted via the app |
| `bug` | red (default) | User reported a bug |
| `enhancement` | blue (default) | User requested a feature |

You can then filter the Issues tab to `label:feedback` to see only
user submissions.

#### C2. Optional: pinned issue templates

Not required, but if you want users browsing the Issues tab to see
nicely formatted entries, you could add a `.github/ISSUE_TEMPLATE/`
directory later. Out of scope for this plan.

---

### Phase D — Privacy disclosure

`PRIVACY.md` currently claims "no network requests." That's now half
true (StoreKit submits purchase data to Apple, which is a different
story). With this change it becomes meaningfully outdated.

Update it to disclose the feedback flow plainly:

```markdown
# Privacy Policy — Falling Code

Last updated: 2026-05-11

Falling Code does not collect, transmit, store, or share any personal
data **except in two cases, both of which you explicitly initiate:**

1. **In-app tips** (the Support tab). Purchase data is handled by
   Apple via StoreKit. We do not see your payment details.
2. **Feedback submission** (the Send Feedback form). If you submit
   feedback, the title, description, and (optionally) your email are
   sent to a developer-controlled Cloudflare Worker which creates a
   public GitHub Issue at
   https://github.com/WadeSellers/matrix-screensaver/issues on your
   behalf. We also include basic device info (app version, macOS
   version, locale) to help reproduce the issue. **Do not include
   sensitive data in feedback submissions** — these issues are public
   on GitHub.

Outside of those two flows, the app:

- Makes no network requests.
- Contains no analytics, telemetry, or tracking.
- Contains no advertising or third-party SDKs.
- Stores its settings only in your local macOS user defaults.

…
```

---

## Critical files

**Create:**
- `MatrixApp/FeedbackController.swift` — NSPanel host
- `MatrixApp/FeedbackManager.swift` — `@Observable` state + submit logic
- `MatrixApp/FeedbackView.swift` — SwiftUI form + success state
- `worker/falling-code-feedback.js` — the Cloudflare Worker
- `worker/wrangler.toml` — Worker config

**Modify:**
- `MatrixApp/SupportView.swift` — add FAQ + Feedback card row
- `MatrixApp/SettingsWindowController.swift` — bump window height to 640
- `MatrixApp/AppDelegate.swift` — own `FeedbackController`, wire callback
- `PRIVACY.md` — disclose the feedback submission flow
- `project.yml` — register `worker/` so xcodegen doesn't choke (probably
  unnecessary since worker isn't a source folder, but verify)

Reuse:
- `OnboardingSheetController` (`MatrixApp/OnboardingSheet.swift` lines
  113–157) — exact NSPanel recipe to mirror for the feedback window.
- Tip card visual recipe (`MatrixApp/SupportView.swift` lines 98–129)
  — for the FAQ + Feedback cards and for the form's input chrome.
- General/Support tab pill recipe (`MatrixApp/SettingsWindowController.swift`)
  — for the Bug/Feature toggle in the form.

---

## Verification

1. **Phase A only** — without deploying the Worker yet, build and run.
   - Open Preferences → Support. Confirm the FAQ + Feedback cards
     appear below the tip cards.
   - Click "Send Feedback" → form window opens, draggable, hosts the
     form correctly. Type into all fields, toggle Bug/Feature. No
     submit yet.
   - Click "Submit Feedback" → expect a `.failure` state since the
     Worker isn't deployed. Confirm the failure message renders.

2. **After Worker deployment** — repeat the submit.
   - Confirm the request reaches the Worker (Wrangler tail shows it).
   - Confirm a new issue appears in the matrix-screensaver repo with
     the right labels.
   - Confirm the app receives `issueNumber` and shows the "Feedback
     Sent" success view with the correct number.
   - Click Done → window dismisses.

3. **Abuse path** — `curl` the Worker without the `X-App-Secret`
   header. Confirm 401. Curl with the secret but malformed JSON →
   confirm 400. Curl with a title longer than 200 chars → confirm
   400.

4. **Repo verification** — filter Issues by `label:feedback`. Confirm
   only feedback-submitted issues appear, in chronological order with
   their issue numbers.

5. **Privacy** — re-read `PRIVACY.md`. Confirm the disclosure is plain
   English and accurate.

---

## Out of scope

- **Real FAQ content.** The FAQ card just opens the README on GitHub
  for v1.0. Building a proper in-app FAQ view with searchable Q&A is
  a future task.
- **Email reply automation.** If users include email, you reach out
  manually from the GitHub Issue page. No automated reply system.
- **Issue templates / forms** on the repo side. Not needed for
  Worker-submitted issues; would be a nice-to-have for users who
  open issues directly via the GitHub UI.
- **Anonymous diagnostics** (crash logs, performance traces). Not in
  scope and would change the privacy story considerably.
