#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_BIN="$ROOT_DIR/build/X-Hub.app/Contents/MacOS/RELFlowHub"

if [ ! -x "$APP_BIN" ]; then
  echo "X-Hub app binary not found: $APP_BIN" >&2
  echo "build it first with:" >&2
  echo "  x-hub/tools/build_hub_app.command" >&2
  exit 1
fi

exec bash "$ROOT_DIR/scripts/with_local_dev_agent_skills_env.sh" -- \
  "$APP_BIN" "$@"
