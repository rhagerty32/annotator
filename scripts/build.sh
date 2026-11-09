#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

build_release_binaries
bin_dir="$(product_dir)"
dest="$ROOT/.build/release"
mkdir -p "$dest"
if [[ "$(cd "$bin_dir" && pwd -P)" != "$(cd "$dest" && pwd -P)" ]]; then
  ditto "$bin_dir/Annotator" "$dest/Annotator"
  ditto "$bin_dir/Capture" "$dest/Capture"
  chmod +x "$dest/Annotator" "$dest/Capture"
fi
embed_sparkle_beside_binary "$dest"

BIN="$dest/Annotator"
CAP="$dest/Capture"
echo "Built: $BIN"
echo "Built: $CAP"
echo "Run:   $BIN --capture"
