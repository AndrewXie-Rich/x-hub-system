#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec bash "$ROOT_DIR/scripts/with_local_dev_agent_skills_env.sh" -- \
  node "$ROOT_DIR/scripts/smoke_local_dev_agent_skills_baseline.js" "$@"
