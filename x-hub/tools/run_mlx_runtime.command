#!/bin/zsh
set -euo pipefail

# Start REL Flow Hub MLX runtime (offline). This is a separate helper process
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

"$PY_BIN" "$ROOT_DIR/python-runtime/python_service/relflowhub_mlx_runtime.py"
