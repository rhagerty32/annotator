#!/usr/bin/env bash
# Write a one-item Sparkle appcast for a DMG that sign_update has already signed.
# Usage: write-appcast.sh --version 1.2.3 --signature SIG --length BYTES --output appcast.xml
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

VERSION=""
SIGNATURE=""
LENGTH=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --signature) SIGNATURE="${2:-}"; shift 2 ;;
    --length) LENGTH="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "write-appcast: --version must be MAJOR.MINOR.PATCH"
is_blank "$SIGNATURE" && die "write-appcast: --signature is required"
[[ "$LENGTH" =~ ^[0-9]+$ ]] || die "write-appcast: --length must be a byte count"
[[ -n "$OUTPUT" ]] || die "write-appcast: --output is required"

FEED="$(feed_url)"
ENCLOSURE="$(release_download_url "$VERSION" "Annotator.dmg")"
NOTES="$(release_notes_url "$VERSION")"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

python3 - "$OUTPUT" "$VERSION" "$FEED" "$ENCLOSURE" "$NOTES" "$SIGNATURE" "$LENGTH" "$PUBDATE" <<'PY'
import sys
from xml.sax.saxutils import escape

out, version, feed, enclosure, notes, signature, length, pubdate = sys.argv[1:]
xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Annotator</title>
    <link>{escape(feed)}</link>
    <description>Annotator updates</description>
    <language>en</language>
    <item>
      <title>Version {escape(version)}</title>
      <pubDate>{escape(pubdate)}</pubDate>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>{escape(notes)}</sparkle:releaseNotesLink>
      <description>Annotator {escape(version)}. Download the disk image, or choose Check for Updates in the app.</description>
      <enclosure
        url="{escape(enclosure)}"
        sparkle:version="{escape(version)}"
        sparkle:shortVersionString="{escape(version)}"
        sparkle:edSignature="{escape(signature)}"
        length="{escape(length)}"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
with open(out, "w", encoding="utf-8") as handle:
    handle.write(xml)
PY

echo "Wrote: $OUTPUT"
