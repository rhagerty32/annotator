#!/usr/bin/env bash
# Submit a zip, dmg, or app to Apple notarytool and staple the ticket.
# An .app is zipped for upload; the ticket is stapled onto the app itself.
#
# Credentials, one of:
#   NOTARYTOOL_KEYCHAIN_PROFILE
#   APP_STORE_CONNECT_API_KEY_ID + APP_STORE_CONNECT_API_ISSUER_ID
#     + APP_STORE_CONNECT_API_KEY_PATH (a .p8 file)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

TARGET="${1:-}"
[[ -n "$TARGET" && -e "$TARGET" ]] || die "usage: scripts/notarize.sh <app-or-dmg-or-zip>"

notary_args=()
if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
  notary_args=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
elif [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" && -n "${APP_STORE_CONNECT_API_KEY_ID:-}" && -n "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]]; then
  notary_args=(
    --key "$APP_STORE_CONNECT_API_KEY_PATH"
    --key-id "$APP_STORE_CONNECT_API_KEY_ID"
    --issuer "$APP_STORE_CONNECT_API_ISSUER_ID"
  )
else
  die "notarization credentials are missing. Set NOTARYTOOL_KEYCHAIN_PROFILE, or APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID, and APP_STORE_CONNECT_API_KEY_PATH. Refusing to publish an app Gatekeeper will block."
fi

submit_path="$TARGET"
tmp_zip=""
staple_path="$TARGET"
cleanup() {
  if [[ -n "$tmp_zip" ]]; then
    rm -f "$tmp_zip"
  fi
}
trap cleanup EXIT

if [[ "$TARGET" == *.app ]]; then
  tmp_zip="$(mktemp -d)/Annotator.zip"
  ditto -c -k --keepParent "$TARGET" "$tmp_zip"
  submit_path="$tmp_zip"
  staple_path="$TARGET"
fi

echo "==> Notarizing $(basename "$submit_path")"
xcrun notarytool submit "$submit_path" "${notary_args[@]}" --wait
echo "==> Stapling $(basename "$staple_path")"
xcrun stapler staple "$staple_path"
xcrun stapler validate "$staple_path"
