#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
LABEL="com.caixinyun.thermal-fan-guard"
COMPONENTS="$ROOT/dist/pkg-components"
PKG_BUILD="$ROOT/dist/pkg-build"
APP_ROOT="$COMPONENTS/app-root"
DAEMON_ROOT="$COMPONENTS/daemon-root"
SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEYCHAIN_PATH="${NOTARY_KEYCHAIN_PATH:-}"
REQUIRE_RELEASE_SIGNING="${REQUIRE_RELEASE_SIGNING:-0}"

if [[ "$REQUIRE_RELEASE_SIGNING" == "1" ]]; then
  if [[ -z "${APPLICATION_SIGN_IDENTITY:-}" ]]; then
    echo "APPLICATION_SIGN_IDENTITY is required for release packaging" >&2
    exit 1
  fi
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "INSTALLER_SIGN_IDENTITY is required for release packaging" >&2
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "NOTARY_KEYCHAIN_PROFILE is required for release packaging" >&2
    exit 1
  fi
fi

cd "$ROOT"

VERSION="$("$ROOT/scripts/set-version.sh")"
PRODUCT_PKG="$PKG_BUILD/MyFans-${VERSION}.pkg"

"$ROOT/scripts/stage-app.sh"

rm -rf "$COMPONENTS" "$PKG_BUILD"
mkdir -p "$APP_ROOT/Applications" \
  "$DAEMON_ROOT/usr/local/libexec" \
  "$DAEMON_ROOT/Library/LaunchDaemons" \
  "$PKG_BUILD"

cp -R "$ROOT/dist/staging/MyFans.app" "$APP_ROOT/Applications/MyFans.app"
install -m 0755 "$ROOT/dist/swift-build/release/thermal-fan-guard" \
  "$DAEMON_ROOT/usr/local/libexec/thermal-fan-guard"
install -m 0644 "$LABEL.plist" "$DAEMON_ROOT/Library/LaunchDaemons/$LABEL.plist"

chmod +x "$ROOT/packaging/pkg/scripts/postinstall"

pkgbuild \
  --root "$APP_ROOT" \
  --install-location / \
  --identifier "com.caixinyun.thermal-fan-guard.app" \
  --version "$VERSION" \
  "$COMPONENTS/MyFans-app.pkg"

pkgbuild \
  --root "$DAEMON_ROOT" \
  --install-location / \
  --scripts "$ROOT/packaging/pkg/scripts" \
  --identifier "com.caixinyun.thermal-fan-guard.daemon" \
  --version "$VERSION" \
  "$COMPONENTS/MyFans-daemon.pkg"

/usr/bin/sed "s/__VERSION__/$VERSION/g" "$ROOT/packaging/pkg/distribution.xml" \
  > "$PKG_BUILD/distribution.xml"

PRODUCTBUILD_ARGS=(
  --distribution "$PKG_BUILD/distribution.xml"
  --package-path "$COMPONENTS"
  --resources "$ROOT/packaging/pkg/resources"
)

if [[ -n "$SIGN_IDENTITY" ]]; then
  PRODUCTBUILD_ARGS+=(--sign "$SIGN_IDENTITY")
fi

productbuild "${PRODUCTBUILD_ARGS[@]}" "$PRODUCT_PKG"

if [[ -n "$SIGN_IDENTITY" ]]; then
  pkgutil --check-signature "$PRODUCT_PKG"
fi

echo "Created: $PRODUCT_PKG"

if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "Submitting for notarization..."
  NOTARYTOOL_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  if [[ -n "$NOTARY_KEYCHAIN_PATH" ]]; then
    NOTARYTOOL_ARGS+=(--keychain "$NOTARY_KEYCHAIN_PATH")
  fi
  xcrun notarytool submit "$PRODUCT_PKG" "${NOTARYTOOL_ARGS[@]}" --wait
  xcrun stapler staple "$PRODUCT_PKG"
  xcrun stapler validate "$PRODUCT_PKG"
  echo "Notarized and stapled: $PRODUCT_PKG"
fi
