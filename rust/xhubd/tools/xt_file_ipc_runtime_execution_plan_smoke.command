#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "$SCRIPT_DIR/xt_file_ipc_runtime_execution_plan_smoke.js" "$@"
