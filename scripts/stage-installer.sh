#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
LABEL="com.caixinyun.thermal-fan-guard"
INSTALLER_APP="$ROOT/dist/Install MyFans.app"
PAYLOAD="$INSTALLER_APP/Contents/Resources/Payload"

cd "$ROOT"

"$ROOT/scripts/stage-app.sh"
swift build -c release --build-path "$ROOT/dist/swift-build" --product MyFansInstaller

BIN="$ROOT/dist/swift-build/release"

rm -rf "$INSTALLER_APP"
mkdir -p "$INSTALLER_APP/Contents/MacOS" "$PAYLOAD"

install -m 0755 "$BIN/MyFansInstaller" "$INSTALLER_APP/Contents/MacOS/MyFansInstaller"
install -m 0644 MyFansInstaller-Info.plist "$INSTALLER_APP/Contents/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
  install -m 0644 Resources/AppIcon.icns "$INSTALLER_APP/Contents/Resources/AppIcon.icns"
fi

cp -R "$ROOT/dist/staging/MyFans.app" "$PAYLOAD/MyFans.app"
install -m 0755 "$BIN/thermal-fan-guard" "$PAYLOAD/thermal-fan-guard"
install -m 0644 "$LABEL.plist" "$PAYLOAD/$LABEL.plist"

xattr -cr "$INSTALLER_APP"
chmod +x "$INSTALLER_APP/Contents/MacOS/MyFansInstaller"
codesign --force --deep --sign - "$INSTALLER_APP" 2>/dev/null || true

echo "Staged: $INSTALLER_APP"
