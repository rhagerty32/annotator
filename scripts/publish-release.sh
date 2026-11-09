#!/usr/bin/env bash
# Attach dist/Annotator.dmg and dist/appcast.xml to the GitHub Release for this tag.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

TAG="${GITHUB_REF_NAME:-}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "tag ${TAG:-<empty>} is not vMAJOR.MINOR.PATCH"
version="${TAG#v}"
DMG="$ROOT/dist/Annotator.dmg"
APPCAST="$ROOT/dist/appcast.xml"
[[ -f "$DMG" && -f "$APPCAST" ]] || die "missing notarized artifacts in dist/"

notes="$(mktemp)"
write_release_notes "$notes" "$version" "$DMG"

if [[ "${ANNOTATOR_SKIP_UPLOAD:-}" == "1" ]]; then
  cat "$notes"
  exit 0
fi

command -v gh >/dev/null || die "gh is required to publish the release"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" "$APPCAST" --clobber
  gh release edit "$TAG" --title "Annotator ${version}" --notes-file "$notes"
else
  gh release create "$TAG" \
    "$DMG" \
    "$APPCAST" \
    --title "Annotator ${version}" \
    --notes-file "$notes" \
    --verify-tag
fi

echo "Published ${TAG}"
