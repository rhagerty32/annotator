#!/usr/bin/env bash
# Sign and notarize on this Mac, using the login keychain instead of GitHub secrets.
# Usage: scripts/release-local.sh 1.2.3
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ge 1 ]]; then
  export ANNOTATOR_VERSION="$1"
fi
export ANNOTATOR_RELEASE_MODE=local
if [[ -z "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
  if xcrun notarytool history --keychain-profile annotator-notary >/dev/null 2>&1; then
    export NOTARYTOOL_KEYCHAIN_PROFILE=annotator-notary
  fi
fi

"$ROOT/scripts/release.sh"

version="${ANNOTATOR_VERSION#v}"
cat <<EOF

Notarized artifacts are in dist/. Upload them to GitHub Releases:

  gh release create "v${version}" \\
    dist/Annotator.dmg \\
    dist/appcast.xml \\
    --title "Annotator ${version}" \\
    --notes "Download Annotator.dmg, open it, and drag Annotator to Applications."

Do not push a v${version} tag to trigger GitHub Actions unless the signing
secrets in docs/release.md are set. Without those secrets the workflow
fails on purpose and does not publish an unsigned app.
EOF
