#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIR="${1:?usage: compile-app-icon.sh OUTPUT_DIR}"
PARTIAL_PLIST=$(mktemp)
LEGACY_CATALOG=$(mktemp -d)
trap 'rm -f "$PARTIAL_PLIST"; rm -rf "$LEGACY_CATALOG"' EXIT

mkdir -p "$OUTPUT_DIR"

compile_catalog() {
  xcrun actool "$1" \
    --compile "$OUTPUT_DIR" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$PARTIAL_PLIST" \
    --warnings \
    --notices \
    >/dev/null
}

if [[ "${FORCE_LEGACY_APP_ICON:-0}" != "1" ]]; then
  compile_catalog "$ROOT/Resources/AppIcon.icon"
fi

# Xcode 16 (including GitHub's macos-15 runner) does not understand Icon
# Composer's .icon format. Fall back to a conventional macOS app-icon catalog;
# Xcode 26 keeps using the layered/tintable source above.
if [[ ! -f "$OUTPUT_DIR/Assets.car" || ! -f "$OUTPUT_DIR/AppIcon.icns" ]]; then
  rm -f "$OUTPUT_DIR/Assets.car" "$OUTPUT_DIR/AppIcon.icns"
  appiconset="$LEGACY_CATALOG/AppIcon.xcassets/AppIcon.appiconset"
  mkdir -p "$appiconset"
  source_png="$ROOT/Resources/AppIcon.icon/Assets/icon_512x512@2x.png"

  for size in 16 32 128 256 512; do
    for scale in 1 2; do
      pixels=$((size * scale))
      filename="icon_${size}x${size}@${scale}x.png"
      /usr/bin/sips -z "$pixels" "$pixels" "$source_png" \
        --out "$appiconset/$filename" >/dev/null
    done
  done

  /bin/cp "$ROOT/Resources/AppIcon.icon/legacy-Contents.json" \
    "$appiconset/Contents.json"
  compile_catalog "$LEGACY_CATALOG/AppIcon.xcassets"
fi
