#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIR="${1:?usage: compile-app-icon.sh OUTPUT_DIR}"
PARTIAL_PLIST=$(mktemp)
trap 'rm -f "$PARTIAL_PLIST"' EXIT

mkdir -p "$OUTPUT_DIR"
xcrun actool "$ROOT/Resources/AppIcon.icon" \
  --compile "$OUTPUT_DIR" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$PARTIAL_PLIST" \
  --warnings \
  --notices \
  >/dev/null
