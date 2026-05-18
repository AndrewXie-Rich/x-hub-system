#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ "${XHUB_ALLOW_LEGACY_XTERMINAL_RUN:-0}" != "1" ]; then
  cat >&2 <<'EOF'
ERROR: Refusing to run legacy X-Terminal from x-hub-system/x-terminal.

This tree is legacy/read-only and must not be used for active XT development.

Active XT source:
  /Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal

Active XT build command:
  /Users/andrew.xie/Documents/AX/rust/rust xt/commands/build_xt.command

For archival/debug-only legacy runs, rerun with:
  XHUB_ALLOW_LEGACY_XTERMINAL_RUN=1
EOF
  exit 64
fi

XT_DIR="$ROOT_DIR/x-terminal"
SOURCE_RUN_HOME="${XTERMINAL_SOURCE_RUN_HOME:-$HOME}"
SOURCE_RUN_TMPDIR="${XTERMINAL_SOURCE_RUN_TMPDIR:-${TMPDIR:-/tmp}}"
SOURCE_RUN_SCRATCH_PATH="${XTERMINAL_SOURCE_RUN_SCRATCH_PATH:-}"
SOURCE_RUN_CLANG_MODULE_CACHE_PATH="${XTERMINAL_SOURCE_RUN_CLANG_MODULE_CACHE_PATH:-}"
SOURCE_RUN_SWIFT_MODULE_CACHE_PATH="${XTERMINAL_SOURCE_RUN_SWIFT_MODULE_CACHE_PATH:-}"
SOURCE_RUN_DISABLE_SANDBOX="${XTERMINAL_SOURCE_RUN_DISABLE_SANDBOX:-0}"
SOURCE_RUN_DISABLE_INDEX_STORE="${XTERMINAL_SOURCE_RUN_DISABLE_INDEX_STORE:-0}"
SWIFT_ARGS=(run)

if [ "$SOURCE_RUN_DISABLE_SANDBOX" = "1" ]; then
  SWIFT_ARGS+=(--disable-sandbox)
fi

if [ "$SOURCE_RUN_DISABLE_INDEX_STORE" = "1" ]; then
  SWIFT_ARGS+=(--disable-index-store)
fi

if [ -n "$SOURCE_RUN_SCRATCH_PATH" ]; then
  mkdir -p "$SOURCE_RUN_SCRATCH_PATH"
  SWIFT_ARGS+=(--scratch-path "$SOURCE_RUN_SCRATCH_PATH")
fi

if [ -n "$SOURCE_RUN_CLANG_MODULE_CACHE_PATH" ]; then
  mkdir -p "$SOURCE_RUN_CLANG_MODULE_CACHE_PATH"
  SWIFT_ARGS+=(-Xcc "-fmodules-cache-path=$SOURCE_RUN_CLANG_MODULE_CACHE_PATH")
fi

if [ -n "$SOURCE_RUN_SWIFT_MODULE_CACHE_PATH" ]; then
  mkdir -p "$SOURCE_RUN_SWIFT_MODULE_CACHE_PATH"
  SWIFT_ARGS+=(-Xswiftc -module-cache-path -Xswiftc "$SOURCE_RUN_SWIFT_MODULE_CACHE_PATH")
fi

mkdir -p "$SOURCE_RUN_HOME" "$SOURCE_RUN_TMPDIR"

cd "$XT_DIR"
exec env HOME="$SOURCE_RUN_HOME" TMPDIR="$SOURCE_RUN_TMPDIR" swift "${SWIFT_ARGS[@]}" XTerminal "$@"
