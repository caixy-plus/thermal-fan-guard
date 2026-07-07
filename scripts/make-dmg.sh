#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUT_DIR="$ROOT/dist"
DMG_STAGE="$OUT_DIR/dmg-staging"
INSTALLER_APP="$OUT_DIR/Install MyFans.app"
DMG_NAME="MyFans"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/ThermalFanGuardApp-Info.plist" 2>/dev/null || echo "1.0")"
DMG_PATH="$OUT_DIR/${DMG_NAME}-${VERSION}.dmg"
BACKGROUND="$ROOT/packaging/dmg/background.png"
VOLICON="$ROOT/Resources/AppIcon.icns"

cd "$ROOT"

"$ROOT/scripts/package-installer.sh"
python3 "$ROOT/packaging/dmg/generate-background.py"

rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
ditto "$INSTALLER_APP" "$DMG_STAGE/Install MyFans.app"

mkdir -p "$OUT_DIR"
rm -f "$DMG_PATH"

create-dmg \
  --volname "$DMG_NAME" \
  --volicon "$VOLICON" \
  --background "$BACKGROUND" \
  --window-pos 220 120 \
  --window-size 660 440 \
  --icon-size 112 \
  --text-size 12 \
  --icon "Install MyFans.app" 330 230 \
  --hide-extension "Install MyFans.app" \
  --format UDZO \
  "$DMG_PATH" \
  "$DMG_STAGE"

echo "Created: $DMG_PATH"
