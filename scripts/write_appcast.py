#!/usr/bin/env python3
"""Write a one-item Sparkle appcast for a zip produced by the release workflow.

sparkle:version and sparkle:shortVersionString are both the dotted release
version. packaging/Info.plist (or ANNOTATOR_VERSION) must use that same string
for CFBundleVersion, which is what Sparkle compares.
"""

from __future__ import annotations

import argparse
import html
import re
import time
from pathlib import Path


def parse_signature(text: str) -> tuple[str, int]:
    match = re.search(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"', text)
    if not match:
        raise SystemExit(
            "sign_update did not print sparkle:edSignature and length. "
            "Refusing to publish an appcast without a signature."
        )
    return match.group(1), int(match.group(2))


def cdata(text: str) -> str:
    cleaned = text.replace("]]>", "]]]]><![CDATA[>")
    return f"<![CDATA[{cleaned}]]>"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--zip", required=True, type=Path)
    parser.add_argument("--sign-file", required=True, type=Path)
    parser.add_argument("--url", required=True)
    parser.add_argument("--notes-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9]+(\.[0-9]+){1,2}", args.version):
        raise SystemExit(f"version must look like 1.2.0, got {args.version!r}")
    if not args.zip.is_file():
        raise SystemExit(f"missing zip {args.zip}")

    signature, length = parse_signature(args.sign_file.read_text())
    actual = args.zip.stat().st_size
    if length != actual:
        raise SystemExit(f"sign_update length {length} does not match {args.zip} ({actual} bytes)")

    notes = args.notes_file.read_text().strip() or f"Update to {args.version}."
    published = time.strftime("%a, %d %b %Y %H:%M:%S +0000", time.gmtime())
    url = html.escape(args.url, quote=True)
    version = html.escape(args.version, quote=True)
    document = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Annotator</title>
    <link>https://github.com/rhagerty32/annotator/releases</link>
    <description>Annotator updates</description>
    <language>en</language>
    <item>
      <title>Version {version}</title>
      <pubDate>{published}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <description>{cdata(notes)}</description>
      <enclosure
        url="{url}"
        sparkle:edSignature="{html.escape(signature, quote=True)}"
        length="{length}"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(document)
    print(f"Wrote {args.output} for {args.version} ({length} bytes)")


if __name__ == "__main__":
    main()
