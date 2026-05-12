#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$ROOT_DIR/bin/xhubd"

if [ ! -x "$BIN" ]; then
  echo "Packaged xhubd binary not found or not executable: $BIN" >&2
  exit 127
fi

exec "$BIN" "$@"
