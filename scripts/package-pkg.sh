#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"

"$ROOT/scripts/build-pkg.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/ThermalFanGuardApp-Info.plist" 2>/dev/null || echo "1.0")"
echo "Release artifact: $ROOT/dist/pkg-build/MyFans-${VERSION}.pkg"
