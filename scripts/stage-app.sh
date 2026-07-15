#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
LABEL="com.caixinyun.thermal-fan-guard"
STAGE="$ROOT/dist/staging"
APP="$STAGE/MyFans.app"
BUILD_PATH="$ROOT/dist/swift-build"
BIN="$BUILD_PATH/release"
APPLICATION_SIGN_IDENTITY="${APPLICATION_SIGN_IDENTITY:-}"
REQUIRE_RELEASE_SIGNING="${REQUIRE_RELEASE_SIGNING:-0}"

if [[ "$REQUIRE_RELEASE_SIGNING" == "1" && -z "$APPLICATION_SIGN_IDENTITY" ]]; then
  echo "APPLICATION_SIGN_IDENTITY is required for a release-signed build" >&2
  exit 1
fi

cd "$ROOT"

swift build -c release --build-path "$BUILD_PATH" --product thermal-fan-guard
swift build -c release --build-path "$BUILD_PATH" --product ThermalFanGuardApp

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m 0755 "$BIN/ThermalFanGuardApp" "$APP/Contents/MacOS/ThermalFanGuardApp"
install -m 0644 ThermalFanGuardApp-Info.plist "$APP/Contents/Info.plist"
install -m 0755 "$BIN/thermal-fan-guard" "$APP/Contents/Resources/thermal-fan-guard"
install -m 0644 "$LABEL.plist" "$APP/Contents/Resources/$LABEL.plist"

"$ROOT/scripts/compile-app-icon.sh" "$APP/Contents/Resources"

install -m 0644 README.md "$APP/Contents/Resources/README.md"

xattr -cr "$APP"
chmod +x "$APP/Contents/MacOS/ThermalFanGuardApp"
if [[ -n "$APPLICATION_SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$APPLICATION_SIGN_IDENTITY" \
    "$BIN/thermal-fan-guard"
  codesign --force --options runtime --timestamp --sign "$APPLICATION_SIGN_IDENTITY" \
    "$APP/Contents/Resources/thermal-fan-guard"
  codesign --force --options runtime --timestamp --sign "$APPLICATION_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$BIN/thermal-fan-guard"
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$BIN/thermal-fan-guard"
codesign --verify --deep --strict --verbose=2 "$APP"
touch "$APP"
# Do NOT lsregister the staging bundle: it would claim the app's bundle ID in
# LaunchServices and Notification Center may then resolve the app icon from
# this build artifact instead of /Applications/MyFans.app.

echo "Staged: $APP"
