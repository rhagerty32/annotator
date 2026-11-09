#!/usr/bin/env bash
# Rebuild Annotator + the Raycast extension, then bounce Raycast so a git pull
# actually shows up (binary, commands, and icon).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

log() { printf '→ %s\n' "$*"; }

log "Building Annotator"
bash "$ROOT/scripts/build.sh"

if [[ ! -d raycast/node_modules ]]; then
  log "Installing Raycast extension deps"
  npm --prefix raycast install
fi

log "Building Raycast extension"
npm --prefix raycast run build

quit_if_running() {
  local name="$1"
  local pattern="$2"
  if pgrep -f "$pattern" >/dev/null 2>&1; then
    log "Quitting $name"
    killall "$name" >/dev/null 2>&1 || true
    return 0
  fi
  return 1
}

restart=()
if quit_if_running "Raycast Beta" "/Applications/Raycast Beta.app/Contents/MacOS/Raycast Beta"; then
  restart+=("Raycast Beta")
fi
if quit_if_running "Raycast" "/Applications/Raycast.app/Contents/MacOS/Raycast"; then
  restart+=("Raycast")
fi

if (( ${#restart[@]} == 0 )); then
  if [[ -d "/Applications/Raycast.app" ]]; then
    restart+=("Raycast")
  elif [[ -d "/Applications/Raycast Beta.app" ]]; then
    restart+=("Raycast Beta")
  fi
fi

sleep 1
for app in "${restart[@]}"; do
  if [[ -d "/Applications/${app}.app" ]]; then
    log "Opening $app"
    open -a "$app"
  fi
done

BIN="$ROOT/.build/release/Annotator"
log "Done. Binary: $BIN"
log "First time? In Raycast: Import Extension → $ROOT/raycast"
