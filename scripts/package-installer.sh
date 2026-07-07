#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUT_DIR="$ROOT/dist"
INSTALLER_APP="$OUT_DIR/Install MyFans.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/ThermalFanGuardApp-Info.plist" 2>/dev/null || echo "1.0")"
ZIP_PATH="$OUT_DIR/Install-MyFans-${VERSION}.zip"

cd "$ROOT"

"$ROOT/scripts/stage-installer.sh"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$INSTALLER_APP" "$ZIP_PATH"

echo "Created: $INSTALLER_APP"
echo "Created: $ZIP_PATH"
