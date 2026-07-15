#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
APP_PLIST="$ROOT/ThermalFanGuardApp-Info.plist"

icon_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$APP_PLIST" 2>/dev/null || true)
if [[ "$icon_name" != "AppIcon" ]]; then
  echo "expected CFBundleIconName=AppIcon, got: ${icon_name:-<missing>}" >&2
  exit 1
fi

if [[ ! -f "$ROOT/Resources/AppIcon.icon/icon.json" ]]; then
  echo "missing Icon Composer source" >&2
  exit 1
fi

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

"$ROOT/scripts/compile-app-icon.sh" "$temp_dir"

if [[ ! -f "$temp_dir/Assets.car" ]]; then
  echo "app icon compiler did not produce Assets.car" >&2
  exit 1
fi

if [[ ! -f "$temp_dir/AppIcon.icns" ]]; then
  echo "app icon compiler did not produce AppIcon.icns" >&2
  exit 1
fi

/usr/bin/assetutil --info "$temp_dir/Assets.car" > "$temp_dir/asset-info.json"

if ! /usr/bin/grep -q '"Name" : "AppIcon"' "$temp_dir/asset-info.json"; then
  echo "compiled asset catalog does not contain AppIcon" >&2
  exit 1
fi

if ! /usr/bin/grep -q '"AssetType" : "IconImageStack"' "$temp_dir/asset-info.json"; then
  echo "compiled AppIcon is missing the macOS 26 layered icon stack" >&2
  exit 1
fi

if ! /usr/bin/grep -q '"ISAppearanceTintable"' "$temp_dir/asset-info.json"; then
  echo "compiled AppIcon is missing the monochrome notification appearance" >&2
  exit 1
fi

echo "App icon packaging checks passed."
