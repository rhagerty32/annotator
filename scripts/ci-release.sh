#!/usr/bin/env bash
# GitHub Actions entry point. Fails closed when signing secrets are absent.
# Never prints certificate material, the API key, or the Sparkle private key.
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

export ANNOTATOR_RELEASE_MODE=ci
if [[ -z "${ANNOTATOR_VERSION:-}" && -n "${GITHUB_REF_NAME:-}" ]]; then
  export ANNOTATOR_VERSION="${GITHUB_REF_NAME#v}"
fi
version="$(resolve_version)"
if [[ "$version" == "0.0.0" ]]; then
  die "refusing to release version 0.0.0. Push a vX.Y.Z tag."
fi
require_ci_secrets

WORK="$(mktemp -d)"
KEYCHAIN="$WORK/annotator-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
P12="$WORK/developer-id.p12"
API_KEY="$WORK/AuthKey.p8"

cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

decode_base64() {
  local value="$1"
  local dest="$2"
  if printf '%s' "$value" | base64 -D > "$dest" 2>/dev/null; then
    return 0
  fi
  printf '%s' "$value" | base64 -d > "$dest"
}

decode_base64 "$DEVELOPER_ID_CERTIFICATE_BASE64" "$P12"
decode_base64 "$APP_STORE_CONNECT_API_KEY_BASE64" "$API_KEY"
chmod 600 "$P12" "$API_KEY"
unset DEVELOPER_ID_CERTIFICATE_BASE64
unset APP_STORE_CONNECT_API_KEY_BASE64

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security default-keychain -s "$KEYCHAIN"
existing="$(security list-keychains -d user | sed -e 's/^ *//' -e 's/"//g')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $existing
security import "$P12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security
rm -f "$P12"
unset DEVELOPER_ID_CERTIFICATE_PASSWORD
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
unset KEYCHAIN_PASSWORD

SIGNING_IDENTITY="$(security find-identity -p codesigning -v "$KEYCHAIN" | awk -F'"' -v team="$APPLE_TEAM_ID" '
  /Developer ID Application/ && index($2, team) { print $2; exit }')"
if is_blank "$SIGNING_IDENTITY"; then
  die "the imported certificate has no Developer ID Application identity for team ${APPLE_TEAM_ID}."
fi

export SIGNING_IDENTITY
export CODESIGN_KEYCHAIN="$KEYCHAIN"
export APP_STORE_CONNECT_API_KEY_PATH="$API_KEY"
export ANNOTATOR_VERSION="$version"

"$ROOT/scripts/release.sh"
echo "Signed and notarized dist/Annotator.dmg"
