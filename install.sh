#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
LABEL="com.caixinyun.thermal-fan-guard"
APP="/Applications/MyFans.app"
OLD_APP="/Applications/Thermal Fan Guard.app"
AGENT="$LABEL-menubar"
cd "$ROOT"

swift build -c release --product thermal-fan-guard
swift build -c release --product ThermalFanGuardApp

ICON_ASSET_DIR=$(mktemp -d)
trap 'rm -rf "$ICON_ASSET_DIR"' EXIT
"$ROOT/scripts/compile-app-icon.sh" "$ICON_ASSET_DIR"

sudo mkdir -p /usr/local/libexec
sudo launchctl bootout system "/Library/LaunchDaemons/$LABEL.plist" 2>/dev/null || true
sudo install -o root -g wheel -m 0755 .build/release/thermal-fan-guard /usr/local/libexec/thermal-fan-guard
sudo install -o root -g wheel -m 0644 "$ROOT/$LABEL.plist" "/Library/LaunchDaemons/$LABEL.plist"
sudo launchctl bootstrap system "/Library/LaunchDaemons/$LABEL.plist"
sudo launchctl enable "system/$LABEL"

sudo mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
sudo install -o root -g wheel -m 0755 .build/release/ThermalFanGuardApp "$APP/Contents/MacOS/ThermalFanGuardApp"
sudo install -o root -g wheel -m 0644 ThermalFanGuardApp-Info.plist "$APP/Contents/Info.plist"
sudo install -o root -g wheel -m 0644 "$ICON_ASSET_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sudo install -o root -g wheel -m 0644 "$ICON_ASSET_DIR/Assets.car" "$APP/Contents/Resources/Assets.car"
sudo install -o root -g wheel -m 0644 README.md "$APP/Contents/Resources/README.md"
sudo codesign --force --deep --sign - "$APP"
sudo touch "$APP"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Drop stale registrations of the same bundle ID (staging build artifacts),
# then make /Applications the only claim, so Notification Center resolves the
# app icon from the installed bundle.
"$LSREGISTER" -f -u "$ROOT/dist/staging/MyFans.app" 2>/dev/null || true
"$LSREGISTER" -f "$APP" 2>/dev/null || true
# Notification Center caches the app icon per bundle ID; restart usernoted so
# a changed icon shows up on new notifications without a reboot.
killall usernoted 2>/dev/null || true

# Remove legacy app bundle name if present.
if [[ -d "$OLD_APP" && "$OLD_APP" != "$APP" ]]; then
  sudo rm -rf "$OLD_APP"
fi

launchctl bootout "gui/$UID" "$HOME/Library/LaunchAgents/$AGENT.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$AGENT.plist"

echo "Installed daemon and menu bar app: $APP"
echo "Enable login item in the app Settings if needed."
echo "Log: tail -f /var/log/thermal-fan-guard.log"
