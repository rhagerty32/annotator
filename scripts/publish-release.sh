#!/usr/bin/env bash
# Build, sign, notarize, and describe one Annotator release.
# The GitHub workflow is the caller. It fails closed when signing secrets are
# missing, and it does not upload an appcast unless Sparkle can sign the zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SPARKLE_VERSION="2.7.1"
FEED_REPO="rhagerty32/annotator"

required=(
  TAG
  SPARKLE_PRIVATE_KEY
  SPARKLE_PUBLIC_ED_KEY
  DEVELOPER_ID_APPLICATION_P12_BASE64
  DEVELOPER_ID_APPLICATION_P12_PASSWORD
  DEVELOPER_ID_APPLICATION
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_ISSUER_ID
  APPLE_NOTARY_KEY_P8
)

missing=()
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("$name")
  fi
done
if (( ${#missing[@]} > 0 )); then
  echo "::error::Missing GitHub secrets or env: ${missing[*]}"
  echo "No appcast was published. Check for Updates cannot verify a release until these exist."
  echo "See CONTRIBUTING.md for how to create each one."
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

WORK="$(mktemp -d)"
cleanup() {
  security delete-keychain "$WORK/annotator-release.keychain-db" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

KEYCHAIN="$WORK/annotator-release.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
P12="$WORK/developer-id.p12"
P8="$WORK/AuthKey.p8"
SPARKLE_KEY="$WORK/sparkle_ed25519_private"
P12_PATH="$P12" python3 -c 'import base64, os, pathlib; raw = "".join(os.environ["DEVELOPER_ID_APPLICATION_P12_BASE64"].split()); pathlib.Path(os.environ["P12_PATH"]).write_bytes(base64.b64decode(raw))'
printf '%s\n' "$APPLE_NOTARY_KEY_P8" > "$P8"
SPARKLE_KEY_PATH="$SPARKLE_KEY" python3 -c 'import os, pathlib; pathlib.Path(os.environ["SPARKLE_KEY_PATH"]).write_text(os.environ["SPARKLE_PRIVATE_KEY"].strip() + "\n")'
chmod 600 "$P12" "$P8" "$SPARKLE_KEY"

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

mkdir -p "$WORK/sparkle"
curl -fsSL -o "$WORK/sparkle.tar.xz" \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
tar -xJf "$WORK/sparkle.tar.xz" -C "$WORK/sparkle"
SIGN_UPDATE="$(find "$WORK/sparkle" -name sign_update -type f -print -quit)"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "::error::Sparkle ${SPARKLE_VERSION} archive did not contain sign_update."
  exit 1
fi

export ANNOTATOR_VERSION="$VERSION"
export DEVELOPER_ID_APPLICATION
export SPARKLE_PUBLIC_ED_KEY
export APPLE_NOTARY_KEY_ID
export APPLE_NOTARY_ISSUER_ID
export APPLE_NOTARY_KEY_PATH="$P8"

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
  cat "$WORK/sign.err"
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

echo "Signed Annotator ${VERSION}. Upload the dmg, zip, and appcast to ${TAG}."
