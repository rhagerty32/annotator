#!/usr/bin/env bash
# Build dist/Annotator.app from the SwiftPM binaries.
#
# Local and pull-request builds are ad-hoc signed so the bundle launches on
# the build machine. A publishable release sets SIGNING_IDENTITY to a
# Developer ID Application certificate before calling this script.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

VERSION="$(resolve_version)"
PUBLIC_KEY="$(resolve_sparkle_public_key)"
IDENTITY="$(codesign_identity)"

if [[ -n "${ANNOTATOR_RELEASE_MODE:-}" && "$IDENTITY" == "-" ]]; then
  die "release packaging requires SIGNING_IDENTITY (Developer ID Application). Refusing to build an unsigned app."
fi

echo "==> Building release binaries (version ${VERSION})"
build_release_binaries
BIN_DIR="$(product_dir)"

APP="$ROOT/dist/Annotator.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

echo "==> Assembling ${APP}"
ditto "$BIN_DIR/Annotator" "$APP/Contents/MacOS/Annotator"
ditto "$BIN_DIR/Capture" "$APP/Contents/MacOS/Capture"
chmod +x "$APP/Contents/MacOS/Annotator" "$APP/Contents/MacOS/Capture"
printf 'APPL????' > "$APP/Contents/PkgInfo"
render_info_plist "$APP/Contents/Info.plist" "$VERSION" "$PUBLIC_KEY"
build_icns "$APP/Contents/Resources/AppIcon.icns"
ditto "$ROOT/packaging/Sparkle-LICENSE.txt" "$APP/Contents/Resources/Sparkle-LICENSE.txt"

FRAMEWORK="$(find_sparkle_framework)"
echo "==> Embedding Sparkle.framework"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
ensure_rpath "$APP/Contents/MacOS/Annotator" "@executable_path/../Frameworks"

if [[ "$IDENTITY" == "-" ]]; then
  ENTITLEMENTS="$ROOT/packaging/entitlements-dev.plist"
  echo "==> Ad-hoc signing (not for distribution)"
else
  ENTITLEMENTS="$ROOT/packaging/entitlements.plist"
  echo "==> Signing with ${IDENTITY}"
fi

sign_sparkle_framework "$APP/Contents/Frameworks/Sparkle.framework"
sign_item "$APP/Contents/MacOS/Capture"
sign_item "$APP" "$ENTITLEMENTS"
codesign --verify --strict --verbose=2 "$APP"

echo "Built: $APP"
echo "Version: $VERSION"
echo "Bundle ID: com.rhagerty32.annotator"
echo "Capture helper: $APP/Contents/MacOS/Capture"
