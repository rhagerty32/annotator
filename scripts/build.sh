#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN="$ROOT/.build/release/Annotator"
CAP="$ROOT/.build/release/Capture"
echo "Built: $BIN"
echo "Built: $CAP"
echo "Run:   $BIN --capture"
