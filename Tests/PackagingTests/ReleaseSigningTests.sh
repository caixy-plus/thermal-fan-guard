#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
STAGE_SCRIPT="$ROOT/scripts/stage-app.sh"
PKG_SCRIPT="$ROOT/scripts/build-pkg.sh"

require_text() {
  local file="$1"
  local text="$2"
  if ! /usr/bin/grep -Fq -- "$text" "$file"; then
    echo "missing release signing contract in ${file:t}: $text" >&2
    exit 1
  fi
}

require_text "$STAGE_SCRIPT" 'APPLICATION_SIGN_IDENTITY'
require_text "$STAGE_SCRIPT" '--options runtime'
require_text "$STAGE_SCRIPT" '--timestamp'
require_text "$STAGE_SCRIPT" 'codesign --verify --deep --strict'
require_text "$STAGE_SCRIPT" 'codesign --verify --strict --verbose=2 "$BIN/thermal-fan-guard"'
require_text "$PKG_SCRIPT" 'INSTALLER_SIGN_IDENTITY'
require_text "$PKG_SCRIPT" 'REQUIRE_RELEASE_SIGNING'
require_text "$PKG_SCRIPT" 'NOTARY_KEYCHAIN_PATH'
require_text "$PKG_SCRIPT" 'NOTARYTOOL_ARGS'
require_text "$PKG_SCRIPT" '--keychain "$NOTARY_KEYCHAIN_PATH"'
require_text "$PKG_SCRIPT" 'pkgutil --check-signature'
require_text "$PKG_SCRIPT" 'xcrun stapler validate'

zsh -n "$STAGE_SCRIPT"
zsh -n "$PKG_SCRIPT"

echo "Release signing packaging checks passed."
