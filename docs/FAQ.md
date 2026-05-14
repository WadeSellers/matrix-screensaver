# Falling Code — Frequently Asked Questions

Answers to the questions people ask most about Falling Code. If you don't see your question here, use the **Send Feedback** button in the app's Support tab.

**Will Falling Code slow down my Mac?**
No. It's built in Swift + Metal, native to Apple Silicon, and renders
at 60fps using a tiny amount of GPU. It's designed to run all day
without affecting battery life or performance.

**Does it work with multiple monitors?**
Yes — automatically. The rain renders on every connected display at
the right resolution and DPI. Plug or unplug a monitor and it adapts.

**How do I make Falling Code launch at startup?**
System Settings → General → Login Items → click `+` → choose Falling
Code from `/Applications`. Then it'll start every time you log in.

**Will the live wallpaper drain my laptop battery?**
On a desktop or plugged-in laptop, no. On battery, the renderer
automatically reduces frame rate and bloom quality to save power. You
can also turn the live wallpaper off in Preferences if you only want
the menu-bar features.

**How do I uninstall Falling Code?**
Drag Falling Code from `/Applications` to the Trash. Your settings
and any installed lock-screen wallpaper are cleaned up automatically
when macOS removes the app's sandbox container.

**Why doesn't Falling Code appear in the Dock?**
It's a menu-bar app by design — no Dock icon to keep your workspace
clean. Click the green glyph in your menu bar to access everything,
or use ⌃⌥⌘M to summon fullscreen rain from anywhere.

**My fullscreen rain is being dismissed too easily. Can I make it
stay longer?**
Fullscreen mode is intentionally dismissed by any input (mouse,
scroll, keypress) — it's meant to be a quick atmospheric moment, not
a persistent state. For an always-on look, use the live wallpaper
feature instead.

**Can I use this on multiple Macs with one purchase?**
Yes. Falling Code is part of Apple's Family Sharing program — once
you've purchased it, anyone in your Family Sharing group can install
it on their devices. You can also use it across all your own Macs
signed into the same Apple Account.

**How do I report a bug or request a feature?**
Use the **Send Feedback** button on the Support tab in Preferences.
It opens a quick form that creates a tracked issue with Wade directly.

**Is the source code available?**
Yes — Falling Code is open source. The repo lives at
<https://github.com/WadeSellers/matrix-screensaver>. You can read
the code, file issues, and even contribute PRs if you like.
