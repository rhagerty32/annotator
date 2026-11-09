#!/usr/bin/env bash
# Build a Developer ID signed, notarized, stapled Annotator.dmg and appcast.
# Does not upload the GitHub Release. See docs/release.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

if [[ "${ANNOTATOR_RELEASE_MODE:-}" == "ci" ]]; then
  require_ci_secrets
fi

VERSION="$(resolve_version)"
if [[ "$VERSION" == "0.0.0" ]]; then
  die "refusing to release version 0.0.0. Push a vX.Y.Z tag or set ANNOTATOR_VERSION."
fi

PUBLIC_KEY="$(resolve_sparkle_public_key)"
if is_blank "$PUBLIC_KEY"; then
  die "Sparkle public key is missing. Set SPARKLE_EDDSA_PUBLIC_KEY or commit packaging/SUPublicEDKey. Refusing to ship an app that cannot verify updates."
fi

if is_blank "${SIGNING_IDENTITY:-}"; then
  team="${APPLE_TEAM_ID:-}"
  SIGNING_IDENTITY="$(security find-identity -p codesigning -v | awk -F'"' -v team="$team" '
    /Developer ID Application/ {
      if (team == "" || index($2, team)) { print $2; exit }
    }')"
  export SIGNING_IDENTITY
fi
if is_blank "${SIGNING_IDENTITY:-}" || [[ "$SIGNING_IDENTITY" == "-" ]]; then
  die "no Developer ID Application identity is available. Refusing to build an unsigned release."
fi
case "$SIGNING_IDENTITY" in
  "Developer ID Application:"*) ;;
  *) die "SIGNING_IDENTITY must be a Developer ID Application certificate, not: ${SIGNING_IDENTITY}" ;;
esac
if [[ -n "${APPLE_TEAM_ID:-}" && "$SIGNING_IDENTITY" != *"$APPLE_TEAM_ID"* ]]; then
  die "SIGNING_IDENTITY does not contain APPLE_TEAM_ID (${APPLE_TEAM_ID}). Refusing to sign with a different team."
fi

export ANNOTATOR_VERSION="$VERSION"
export ANNOTATOR_RELEASE_MODE="${ANNOTATOR_RELEASE_MODE:-local}"

"$ROOT/scripts/package-app.sh"
"$ROOT/scripts/notarize.sh" "$ROOT/dist/Annotator.app"
"$ROOT/scripts/package-dmg.sh"
"$ROOT/scripts/notarize.sh" "$ROOT/dist/Annotator.dmg"

DMG="$ROOT/dist/Annotator.dmg"
codesign --verify --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
sig_info="$(codesign -dv --verbose=4 "$ROOT/dist/Annotator.app" 2>&1 || true)"
if [[ "$sig_info" != *"Authority=Developer ID Application"* ]]; then
  printf '%s\n' "$sig_info" >&2
  die "Annotator.app is not signed by a Developer ID Application certificate."
fi

SIGN_UPDATE="$(find_sign_update)"
echo "==> Signing the DMG for Sparkle"
sig_line=""
sign_err="$(mktemp)"
if ! is_blank "${SPARKLE_EDDSA_PRIVATE_KEY:-}"; then
  key="$(printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" | tr -d '[:space:]')"
  if ! sig_line="$(printf '%s\n' "$key" | "$SIGN_UPDATE" --ed-key-file - "$DMG" 2>"$sign_err")"; then
    rm -f "$sign_err"
    unset key
    die "sign_update failed. The Sparkle private key was not printed. Check SPARKLE_EDDSA_PRIVATE_KEY."
  fi
  unset key
elif [[ -n "${SPARKLE_EDDSA_PRIVATE_KEY_FILE:-}" ]]; then
  if ! sig_line="$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_EDDSA_PRIVATE_KEY_FILE" "$DMG" 2>"$sign_err")"; then
    rm -f "$sign_err"
    die "sign_update failed using SPARKLE_EDDSA_PRIVATE_KEY_FILE."
  fi
else
  if ! sig_line="$("$SIGN_UPDATE" --account "${SPARKLE_KEYCHAIN_ACCOUNT:-annotator}" "$DMG" 2>"$sign_err")"; then
    if [[ -s "$sign_err" ]]; then
      cat "$sign_err" >&2
    fi
    rm -f "$sign_err"
    die "sign_update failed. Run generate_keys --account ${SPARKLE_KEYCHAIN_ACCOUNT:-annotator}, or set SPARKLE_EDDSA_PRIVATE_KEY."
  fi
fi
rm -f "$sign_err"
signature="$(printf '%s\n' "$sig_line" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
length="$(printf '%s\n' "$sig_line" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
if is_blank "$signature" || is_blank "$length"; then
  die "sign_update did not return a Sparkle EdDSA signature. The DMG will not be published."
fi

"$ROOT/scripts/write-appcast.sh" \
  --version "$VERSION" \
  --signature "$signature" \
  --length "$length" \
  --output "$ROOT/dist/appcast.xml"

echo "Release artifacts:"
echo "  $DMG"
echo "  $ROOT/dist/appcast.xml"
echo "Version ${VERSION} is signed, notarized, and stapled."
