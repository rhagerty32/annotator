#!/usr/bin/env bash
# Host-independent checks for release metadata, the Info.plist, and the appcast.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for script in scripts/*.sh; do
  bash -n "$script"
done

sparkle_ver="$(tr -d '[:space:]' < packaging/sparkle-version)"
grep -q "exact: \"${sparkle_ver}\"" Package.swift || fail "Package.swift Sparkle pin does not match packaging/sparkle-version (${sparkle_ver})"
[[ "$sparkle_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "sparkle version is not MAJOR.MINOR.PATCH"

repo="$(tr -d '[:space:]' < packaging/github-repo)"
[[ "$repo" == "rhagerty32/annotator" ]] || fail "unexpected github repo: $repo"

(
  export ANNOTATOR_VERSION="v1.2.3"
  # shellcheck source=lib.sh
  source "$ROOT/scripts/lib.sh"
  [[ "$(resolve_version)" == "1.2.3" ]] || exit 1
  [[ "$(feed_url)" == "https://github.com/rhagerty32/annotator/releases/latest/download/appcast.xml" ]] || exit 1
  [[ "$(release_download_url "1.2.3" "Annotator.dmg")" == "https://github.com/rhagerty32/annotator/releases/download/v1.2.3/Annotator.dmg" ]] || exit 1
) || fail "version or feed URL helpers"

if (
  export ANNOTATOR_VERSION="1.2"
  # shellcheck source=lib.sh
  source "$ROOT/scripts/lib.sh"
  resolve_version
) >/dev/null 2>&1; then
  fail "partial version should be rejected"
fi

(
  unset DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD APPLE_TEAM_ID
  unset APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_API_ISSUER_ID APP_STORE_CONNECT_API_KEY_BASE64
  unset SPARKLE_EDDSA_PRIVATE_KEY SPARKLE_EDDSA_PUBLIC_KEY
  # shellcheck source=lib.sh
  source "$ROOT/scripts/lib.sh"
  log="$(mktemp)"
  if require_ci_secrets >"$log" 2>&1; then
    exit 1
  fi
  grep -q "Refusing to publish an unsigned Annotator release" "$log"
  grep -q "DEVELOPER_ID_CERTIFICATE_BASE64" "$log"
  grep -q "SPARKLE_EDDSA_PRIVATE_KEY" "$log"
  grep -q "APP_STORE_CONNECT_API_KEY_BASE64" "$log"
) || fail "missing secrets should fail closed"

(
  export DEVELOPER_ID_CERTIFICATE_BASE64="present"
  export DEVELOPER_ID_CERTIFICATE_PASSWORD="present"
  export APPLE_TEAM_ID="present"
  export APP_STORE_CONNECT_API_KEY_ID="present"
  export APP_STORE_CONNECT_API_ISSUER_ID="present"
  export APP_STORE_CONNECT_API_KEY_BASE64="present"
  export SPARKLE_EDDSA_PRIVATE_KEY="present"
  export SPARKLE_EDDSA_PUBLIC_KEY="test-public-key"
  # shellcheck source=lib.sh
  source "$ROOT/scripts/lib.sh"
  require_ci_secrets
) || fail "complete secrets should pass"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
(
  # shellcheck source=lib.sh
  source "$ROOT/scripts/lib.sh"
  render_info_plist "$tmp/empty.plist" "1.2.3" ""
  render_info_plist "$tmp/keyed.plist" "2.0.1" "abc+/="
)
python3 - "$tmp/empty.plist" "$tmp/keyed.plist" <<'PY'
import plistlib
import sys

empty = plistlib.load(open(sys.argv[1], "rb"))
keyed = plistlib.load(open(sys.argv[2], "rb"))
assert empty["CFBundleIdentifier"] == "com.rhagerty32.annotator"
assert empty["CFBundleShortVersionString"] == "1.2.3"
assert empty["CFBundleVersion"] == "1.2.3"
assert empty["LSUIElement"] is True
assert empty["LSMinimumSystemVersion"] == "14.0"
assert empty["SUEnableAutomaticChecks"] is False
assert empty["SUFeedURL"] == "https://github.com/rhagerty32/annotator/releases/latest/download/appcast.xml"
assert "SUPublicEDKey" not in empty
assert keyed["SUPublicEDKey"] == "abc+/="
assert keyed["CFBundleVersion"] == "2.0.1"
print("plist ok")
PY

bash scripts/write-appcast.sh \
  --version 1.2.3 \
  --signature 'sig+/abc=' \
  --length 42 \
  --output "$tmp/appcast.xml"
python3 - "$tmp/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
channel = root.find("channel")
assert channel.find("link").text == "https://github.com/rhagerty32/annotator/releases/latest/download/appcast.xml"
enclosure = channel.find("item/enclosure")
assert enclosure.get("url") == "https://github.com/rhagerty32/annotator/releases/download/v1.2.3/Annotator.dmg"
assert enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}version") == "1.2.3"
assert enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString") == "1.2.3"
assert enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature") == "sig+/abc="
assert enclosure.get("length") == "42"
notes = channel.find("item/{http://www.andymatuschak.org/xml-namespaces/sparkle}releaseNotesLink")
assert notes.text == "https://github.com/rhagerty32/annotator/releases/tag/v1.2.3"
print("appcast ok")
PY

if bash scripts/write-appcast.sh --version 1.2.3 --signature "" --length 1 --output "$tmp/bad.xml" >/dev/null 2>&1; then
  fail "empty Sparkle signature should be rejected"
fi

printf 'dmg-bytes' > "$tmp/Annotator.dmg"
notes="$(
  # shellcheck source=lib.sh
  source "$ROOT/scripts/lib.sh"
  write_release_notes "$tmp/notes.txt" "1.2.3" "$tmp/Annotator.dmg"
  cat "$tmp/notes.txt"
)"
grep -q "drag Annotator to Applications" <<<"$notes" || fail "release notes missing install instructions"
grep -q "Check for Updates" <<<"$notes" || fail "release notes missing update instructions"
grep -q "Annotator 1.2.3" <<<"$notes" || fail "release notes missing version"
grep -q "SHA-256:" <<<"$notes" || fail "release notes missing checksum"

echo "release tooling ok"
