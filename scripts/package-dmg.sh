#!/usr/bin/env bash
# Build a drag-to-Applications disk image from dist/Annotator.app.
# Signs the DMG only when SIGNING_IDENTITY is a Developer ID.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

APP="$ROOT/dist/Annotator.app"
DMG="$ROOT/dist/Annotator.dmg"
[[ -d "$APP" ]] || die "missing $APP. Run scripts/package-app.sh first."

STAGE="$(mktemp -d)"
WORK="$(mktemp -d)"
MOUNT="$(mktemp -d)"
cleanup() {
  local mounted
  mounted="$(mount || true)"
  if [[ "$mounted" == *" on ${MOUNT} "* ]]; then
    hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force || true
  fi
  rm -rf "$STAGE" "$WORK"
  rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

ditto "$APP" "$STAGE/Annotator.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating Annotator.dmg"
KB="$(du -sk "$STAGE" | awk '{print $1}')"
MB="$(( KB / 1024 + 80 ))"
RW="$WORK/Annotator-rw.dmg"
hdiutil create -size "${MB}m" -fs HFS+ -volname "Annotator" -ov "$RW" >/dev/null
hdiutil attach "$RW" -mountpoint "$MOUNT" -nobrowse -quiet

ditto "$STAGE/Annotator.app" "$MOUNT/Annotator.app"
ln -s /Applications "$MOUNT/Applications"
rm -f "$MOUNT/.DS_Store" "$MOUNT/Annotator.app/.DS_Store"

# Finder layout is best-effort. The Applications alias is what makes the
# disk image drag-to-install; a plain icon view is enough when Finder is
# unavailable (some CI sessions).
perl -e 'alarm shift; exec @ARGV' 30 osascript <<'APPLESCRIPT' >/dev/null 2>&1 || echo "Finder layout skipped; the DMG still contains Annotator.app and an Applications alias."
tell application "Finder"
  tell disk "Annotator"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 760, 440}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set position of item "Annotator.app" of container window to {160, 180}
    set position of item "Applications" of container window to {460, 180}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force
mkdir -p "$ROOT/dist"
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -o "$DMG" >/dev/null

IDENTITY="$(codesign_identity)"
if [[ "$IDENTITY" != "-" ]]; then
  echo "==> Signing DMG with ${IDENTITY}"
  sign_args=(--force --sign "$IDENTITY" --timestamp)
  if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then
    sign_args+=(--keychain "$CODESIGN_KEYCHAIN")
  fi
  codesign "${sign_args[@]}" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

echo "Built: $DMG"
