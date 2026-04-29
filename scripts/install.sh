#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "→ Generating Xcode project..."
xcodegen generate

echo "→ Building MatrixSaver bundle (Release)..."
xcodebuild \
  -project MatrixSaver.xcodeproj \
  -scheme MatrixSaver \
  -configuration Release \
  -derivedDataPath build \
  build | tail -10

SAVER_PATH="build/Build/Products/Release/MatrixSaver.saver"
DEST="$HOME/Library/Screen Savers/MatrixSaver.saver"

if [ ! -d "$SAVER_PATH" ]; then
  echo "✗ Build did not produce $SAVER_PATH"
  exit 1
fi

echo "→ Ad-hoc signing..."
codesign --force --deep --sign - "$SAVER_PATH"

echo "→ Removing existing install (if any)..."
rm -rf "$DEST"

mkdir -p "$HOME/Library/Screen Savers"
echo "→ Copying to $DEST..."
cp -R "$SAVER_PATH" "$DEST"

echo "→ Killing legacyScreenSaver / ScreenSaverEngine to refresh preview cache..."
killall legacyScreenSaver 2>/dev/null || true
killall ScreenSaverEngine 2>/dev/null || true

echo ""
echo "✓ Installed to $DEST"
echo "  Open System Settings → Screen Saver, pick 'MatrixSaver'."
echo "  First time: Privacy & Security → 'Open Anyway' (ad-hoc signed)."
