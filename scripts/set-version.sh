#!/bin/zsh
# Set app/installer version from VERSION env or current git tag (v-prefix stripped).
set -euo pipefail

ROOT="${0:A:h:h}"
APP_PLIST="$ROOT/ThermalFanGuardApp-Info.plist"
INSTALLER_PLIST="$ROOT/MyFansInstaller-Info.plist"

resolve_version() {
  if [[ -n "${VERSION:-}" ]]; then
    print -r -- "$VERSION"
    return
  fi

  local tag
  if tag="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)"; then
    print -r -- "${tag#v}"
    return
  fi

  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST" 2>/dev/null || echo "1.0"
}

VERSION="$(resolve_version)"

for plist in "$APP_PLIST" "$INSTALLER_PLIST"; do
  [[ -f "$plist" ]] || continue
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$plist"
done

print -r -- "$VERSION"
