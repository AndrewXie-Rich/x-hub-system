#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -eq 0 ]; then
  ROUTE_ARGS=(provider route --model-id gpt-4o)
else
  ROUTE_ARGS=(provider route "$@")
fi

if [ -x "$ROOT_DIR/bin/xhubd" ]; then
  exec "$ROOT_DIR/bin/xhubd" "${ROUTE_ARGS[@]}"
fi

cd "$ROOT_DIR"
exec cargo run --bin xhubd -- "${ROUTE_ARGS[@]}"
