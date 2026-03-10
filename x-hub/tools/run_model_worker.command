#!/bin/zsh
set -euo pipefail

# Start the offline model command worker for REL Flow Hub.
# This is intentionally a separate helper process (easy to audit / kill).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export PYTHONUNBUFFERED=1
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export HF_DATASETS_OFFLINE=1
export TOKENIZERS_PARALLELISM=false

python3 "$ROOT_DIR/python-runtime/python_service/relflowhub_model_worker.py"
