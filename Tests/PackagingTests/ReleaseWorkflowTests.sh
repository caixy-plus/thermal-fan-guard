#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
WORKFLOW="$ROOT/.github/workflows/release.yml"

require_text() {
  local text="$1"
  if ! /usr/bin/grep -Fq -- "$text" "$WORKFLOW"; then
    echo "missing GitHub release workflow contract: $text" >&2
    exit 1
  fi
}

require_text 'DEVELOPER_ID_P12_BASE64'
require_text 'DEVELOPER_ID_P12_PASSWORD'
require_text 'security create-keychain'
require_text 'security import'
require_text 'security set-key-partition-list'
require_text 'Developer ID Application: xinyun Cai (PU2Y2C2PT8)'
require_text 'Developer ID Installer: xinyun Cai (PU2Y2C2PT8)'
require_text 'APPLE_APP_SPECIFIC_PASSWORD'
require_text 'notarytool store-credentials'
require_text 'NOTARY_KEYCHAIN_PATH'
require_text 'REQUIRE_RELEASE_SIGNING: "1"'
require_text 'pkgutil --check-signature'
require_text 'stapler validate'
require_text 'spctl -a -vv --type install'
require_text 'security delete-keychain'
require_text 'if: ${{ always() }}'

/usr/bin/ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$WORKFLOW"

echo "GitHub release workflow signing checks passed."
