#!/usr/bin/env bash
# Build an Annotator release, sign the update zip with Sparkle EdDSA, and write appcast.xml.
# Apple Developer ID and notarization are optional. When they are absent the app is ad-hoc signed.
# Check for Updates still accepts the zip when sparkle:edSignature matches SUPublicEDKey.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SPARKLE_VERSION="2.7.1"
FEED_REPO="rhagerty32/annotator"

if [[ -z "${TAG:-}" ]]; then
  echo "::error::TAG is required (for example v1.2.0)."
  exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "::error::SPARKLE_PRIVATE_KEY is required to sign the update zip."
  echo "Apple Developer ID and notarization secrets are not required."
  echo "Set SPARKLE_PRIVATE_KEY to the Sparkle EdDSA private key (base64 seed from generate_keys -x)."
  exit 1
fi

if [[ "${GITHUB_REPOSITORY:-$FEED_REPO}" != "$FEED_REPO" ]]; then
  echo "::error::SUFeedURL points at ${FEED_REPO}. Refusing to publish an appcast for ${GITHUB_REPOSITORY}."
  exit 1
fi

VERSION="${TAG#v}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "::error::Release tag must look like v1.2.0 (got ${TAG})."
  exit 1
fi

apple_ready=0
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" \
   && -n "${DEVELOPER_ID_APPLICATION_P12_BASE64:-}" \
   && -n "${DEVELOPER_ID_APPLICATION_P12_PASSWORD:-}" \
   && -n "${APPLE_NOTARY_KEY_ID:-}" \
   && -n "${APPLE_NOTARY_ISSUER_ID:-}" \
   && -n "${APPLE_NOTARY_KEY_P8:-}" ]]; then
  apple_ready=1
fi

WORK="$(mktemp -d)"
cleanup() {
  if [[ -n "${KEYCHAIN:-}" ]]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

SPARKLE_KEY="$WORK/sparkle_ed25519_private"
SPARKLE_KEY_PATH="$SPARKLE_KEY" python3 -c 'import os, pathlib; pathlib.Path(os.environ["SPARKLE_KEY_PATH"]).write_text(os.environ["SPARKLE_PRIVATE_KEY"].strip() + "\n")'
chmod 600 "$SPARKLE_KEY"

if [[ "$apple_ready" -eq 1 ]]; then
  echo "Apple signing secrets are present. Signing with Developer ID and notarizing."
  KEYCHAIN="$WORK/annotator-release.keychain-db"
  KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
  P12="$WORK/developer-id.p12"
  P8="$WORK/AuthKey.p8"
  P12_PATH="$P12" python3 -c 'import base64, os, pathlib; raw = "".join(os.environ["DEVELOPER_ID_APPLICATION_P12_BASE64"].split()); pathlib.Path(os.environ["P12_PATH"]).write_bytes(base64.b64decode(raw))'
  printf '%s\n' "$APPLE_NOTARY_KEY_P8" > "$P8"
  chmod 600 "$P12" "$P8"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security import "$P12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_APPLICATION_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
  security default-keychain -s "$KEYCHAIN"
  if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "$DEVELOPER_ID_APPLICATION" >/dev/null; then
    echo "::error::Imported certificate does not contain identity: $DEVELOPER_ID_APPLICATION"
    exit 1
  fi
  export DEVELOPER_ID_APPLICATION
  export APPLE_NOTARY_KEY_ID
  export APPLE_NOTARY_ISSUER_ID
  export APPLE_NOTARY_KEY_PATH="$P8"
else
  echo "Publishing an ad-hoc signed build. Developer ID and notarization are not required."
  unset DEVELOPER_ID_APPLICATION || true
  unset APPLE_NOTARY_KEY_ID || true
  unset APPLE_NOTARY_ISSUER_ID || true
  unset APPLE_NOTARY_KEY_PATH || true
fi

mkdir -p "$WORK/sparkle"
# Same official 2.7.1 zip SwiftPM uses. It includes bin/sign_update, so the
# release job does not download Sparkle-*.tar.xz from the release CDN.
VENDORED="$ROOT/vendor/sparkle/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
EXPECTED_SPARKLE_SHA="3b9d424d79b1f3453cc44d23c3b0105bdff1298f5321aad8722f98b9149d5e95"
if [[ ! -f "$VENDORED" ]]; then
  echo "::error::Vendored Sparkle ${SPARKLE_VERSION} package zip is missing (${VENDORED})."
  exit 1
fi
actual="$(shasum -a 256 "$VENDORED" | awk '{print $1}')"
if [[ "$actual" != "$EXPECTED_SPARKLE_SHA" ]]; then
  echo "::error::Vendored Sparkle zip checksum ${actual} != ${EXPECTED_SPARKLE_SHA}."
  exit 1
fi
unzip -q "$VENDORED" -d "$WORK/sparkle"
SIGN_UPDATE="$WORK/sparkle/bin/sign_update"
if [[ ! -f "$SIGN_UPDATE" ]]; then
  echo "::error::Sparkle ${SPARKLE_VERSION} archive did not contain bin/sign_update."
  exit 1
fi
chmod +x "$SIGN_UPDATE"

export ANNOTATOR_VERSION="$VERSION"
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  export SPARKLE_PUBLIC_ED_KEY
fi

python3 scripts/package-dmg.py

ZIP="dist/Annotator-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent dist/Annotator.app "$ZIP"

set +e
SIGN_OUT="$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY" "$ZIP" 2>"$WORK/sign.err")"
SIGN_STATUS=$?
set -e
if [[ "$SIGN_STATUS" -ne 0 ]]; then
  echo "::error::sign_update failed."
  # sign_update writes errors to stderr. Do not print the key file.
  sed -e 's/[A-Za-z0-9+/=]\{40,\}/[redacted]/g' "$WORK/sign.err" || true
  exit "$SIGN_STATUS"
fi
printf '%s\n' "$SIGN_OUT" > "$WORK/sign.txt"

NOTES="${RELEASE_NOTES:-}"
if [[ -z "$NOTES" ]]; then
  NOTES="Update to ${VERSION}."
fi
printf '%s\n' "$NOTES" > "$WORK/notes.txt"

URL="https://github.com/${FEED_REPO}/releases/download/${TAG}/Annotator-${VERSION}.zip"
python3 scripts/write_appcast.py \
  --version "$VERSION" \
  --zip "$ZIP" \
  --sign-file "$WORK/sign.txt" \
  --url "$URL" \
  --notes-file "$WORK/notes.txt" \
  --output dist/appcast.xml

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "version=${VERSION}" >> "$GITHUB_OUTPUT"
  echo "tag=${TAG}" >> "$GITHUB_OUTPUT"
fi

echo "Prepared Annotator ${VERSION}. Upload the dmg, zip, and appcast to ${TAG}."
