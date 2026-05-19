#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$XT_DIR/.." && pwd)"
RUST_XTD_DIR="$ROOT_DIR/rust/xtd"

echo "[1/2] Building Rust XT sidecar..."
if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found. Install Rust toolchain before building xtd." >&2
  exit 127
fi

cargo build --release --manifest-path "$RUST_XTD_DIR/Cargo.toml"

echo "[2/2] Building X-Terminal app bundle..."
bash "$XT_DIR/tools/build_xterminal_app.command"

echo
echo "Build complete."
echo "App bundle: $ROOT_DIR/build/X-Terminal.app"
echo "Rust sidecar: $RUST_XTD_DIR/target/release/xtd"
