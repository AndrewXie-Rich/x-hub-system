#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec bash "$ROOT_DIR/scripts/with_local_dev_agent_skills_env.sh" -- \
  bash "$ROOT_DIR/x-hub/tools/run_xhub_from_source.command" "$@"
