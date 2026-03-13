#!/bin/zsh
set -euo pipefail

# Start the X-Hub local provider runtime (offline). This is a separate helper process
# so the Swift UI stays lightweight.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export PYTHONUNBUFFERED=1
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export HF_DATASETS_OFFLINE=1
export TOKENIZERS_PARALLELISM=false

# If you have a dedicated python (with mlx/mlx_lm installed), set it here:
#   export REL_FLOW_HUB_PY=/path/to/python
PY_BIN="${REL_FLOW_HUB_PY:-python3}"
RUNTIME_ROOT="$ROOT_DIR/python-runtime/python_service"
RUNTIME_ENTRY="$RUNTIME_ROOT/relflowhub_local_runtime.py"
if [ ! -f "$RUNTIME_ENTRY" ]; then
  RUNTIME_ENTRY="$RUNTIME_ROOT/relflowhub_mlx_runtime.py"
fi

"$PY_BIN" "$RUNTIME_ENTRY"
