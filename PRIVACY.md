# Privacy Policy — Falling Code

Last updated: 2026-05-12

Falling Code does not collect, transmit, store, or share any personal data
**except in two cases, both of which you explicitly initiate from inside
the app:**

1. **In-app tips.** When you tap a tip tier in the Support tab, Apple's
   StoreKit handles the purchase. Payment details (card, Apple Account)
   never leave Apple's systems — the app never sees them. Apple may
   share aggregate purchase counts with us via App Store Connect; no
   individual purchaser is identifiable to us.

2. **Feedback submission.** When you tap "Submit Feedback" in the Send
   Feedback window, the app sends the following to a developer-controlled
   Cloudflare Worker, which then creates a public GitHub Issue at
   <https://github.com/WadeSellers/matrix-screensaver/issues> on your
   behalf:

   - The feedback type (bug or feature)
   - The title and description you typed
   - Your email address, **only if you chose to provide it**
   - Basic device info (Falling Code version + build, macOS version
     string, current locale identifier)

   These submissions become public GitHub Issues. **Please do not
   include sensitive information** (passwords, account details, etc.)
   in feedback submissions. If you provide an email, it's included in
   the issue as an HTML comment so it doesn't render publicly, but
   anyone with read access to the repo can see the raw issue source.

Outside of those two flows, the app:

- Makes no network requests.
- Contains no analytics, telemetry, or tracking.
- Contains no advertising or third-party SDKs.
- Stores its settings (theme, speed, idle threshold, etc.) only in your local
  macOS user defaults on your own device. These settings never leave your Mac.
- Reads system idle state via standard macOS APIs solely to trigger the
  screensaver-replacement feature locally. No idle data is logged or sent.
- Optionally writes a per-screen still image of the digital-rain effect to
  your sandbox container at `~/Library/Containers/com.wadesellers.cipherfall/`
  to set as your system wallpaper, when you enable the lock-screen option in
  Preferences. The image is generated on-device and never uploaded anywhere.

If this ever changes in a future version, this policy will be updated and the
update will be called out in that version's release notes.

Questions: open an issue at
<https://github.com/WadeSellers/matrix-screensaver/issues> or use the in-app
Send Feedback form.

— Wade Sellers
