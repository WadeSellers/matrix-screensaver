#!/bin/bash
#
# install-app.sh — build Cipherfall.app (Release) and install to /Applications.
#
# Usage:
#   ./scripts/install-app.sh
#
# After install, drag Cipherfall.app to System Settings → General → Login Items
# if you want it to launch on boot.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "→ Generating Xcode project..."
xcodegen generate

echo "→ Building Cipherfall.app (Release)..."
xcodebuild \
  -project MatrixSaver.xcodeproj \
  -scheme MatrixApp \
  -configuration Release \
  -derivedDataPath build \
  build 2>&1 | tail -5

APP_SRC="build/Build/Products/Release/Cipherfall.app"
APP_DEST="/Applications/Cipherfall.app"

if [ ! -d "$APP_SRC" ]; then
  echo "✗ Build did not produce $APP_SRC"
  exit 1
fi

echo "→ Ad-hoc signing..."
codesign --force --deep --sign - "$APP_SRC"

# Quit any running copy so we can replace the bundle.
pkill -x Cipherfall 2>/dev/null || true
sleep 0.5

if [ -d "$APP_DEST" ]; then
  echo "→ Removing existing $APP_DEST..."
  rm -rf "$APP_DEST"
fi

echo "→ Copying to $APP_DEST..."
cp -R "$APP_SRC" "$APP_DEST"

# Strip the quarantine attribute so Gatekeeper doesn't prompt about
# "downloaded from the internet" — it wasn't, we just built it.
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

echo ""
echo "✓ Installed: $APP_DEST"
echo ""
echo "  Next steps:"
echo "    1. open $APP_DEST              # launch it"
echo "    2. Look for the Cipherfall glyph in your menu bar"
echo "    3. Left-click → menu, right-click → fullscreen rain"
echo "    4. ⌃⌥⌘M from anywhere also toggles fullscreen"
echo ""
echo "  Optional — auto-launch on login:"
echo "    System Settings → General → Login Items → '+' → /Applications/Cipherfall.app"
