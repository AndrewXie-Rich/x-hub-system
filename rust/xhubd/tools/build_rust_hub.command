#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found. Install Rust toolchain before building Rust Hub." >&2
  exit 127
fi

cd "$ROOT_DIR"
exec cargo build --workspace "$@"
