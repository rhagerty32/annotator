#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN="$ROOT/.build/release/Annotator"
echo "Built: $BIN"
echo "Run:   $BIN --capture"
