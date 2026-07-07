#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
LABEL="com.caixinyun.thermal-fan-guard"
STAGE="$ROOT/dist/staging"
APP="$STAGE/MyFans.app"
BUILD_PATH="$ROOT/dist/swift-build"
BIN="$BUILD_PATH/release"

cd "$ROOT"

swift build -c release --build-path "$BUILD_PATH" --product thermal-fan-guard
swift build -c release --build-path "$BUILD_PATH" --product ThermalFanGuardApp

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m 0755 "$BIN/ThermalFanGuardApp" "$APP/Contents/MacOS/ThermalFanGuardApp"
install -m 0644 ThermalFanGuardApp-Info.plist "$APP/Contents/Info.plist"
install -m 0755 "$BIN/thermal-fan-guard" "$APP/Contents/Resources/thermal-fan-guard"
install -m 0644 "$LABEL.plist" "$APP/Contents/Resources/$LABEL.plist"

if [[ -f Resources/AppIcon.icns ]]; then
  install -m 0644 Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

install -m 0644 README.md "$APP/Contents/Resources/README.md"

xattr -cr "$APP"
chmod +x "$APP/Contents/MacOS/ThermalFanGuardApp"
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Staged: $APP"
