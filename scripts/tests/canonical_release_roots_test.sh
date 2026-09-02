#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
RELEASE_COMMAND="$ROOT_DIR/scripts/package_macos_release.command"

expect_rejected() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "[FAIL] Expected rejection: $label" >&2
    exit 1
  fi
}

"$RELEASE_COMMAND" --check-canonical-roots >/dev/null

XHUB_RUST_HUB_SOURCE_ROOT="$ROOT_DIR/rust/xhubd" \
XTERMINAL_SOURCE_ROOT="$ROOT_DIR/x-terminal" \
  "$RELEASE_COMMAND" --check-canonical-roots >/dev/null

expect_rejected "external Rust source" \
  env XHUB_RUST_HUB_SOURCE_ROOT=/tmp "$RELEASE_COMMAND" --check-canonical-roots

expect_rejected "external X-Terminal source" \
  env XTERMINAL_SOURCE_ROOT=/tmp "$RELEASE_COMMAND" --check-canonical-roots

expect_rejected "release external-package override" \
  env XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE=1 "$RELEASE_COMMAND" --check-canonical-roots

expect_rejected "prebuilt Rust package override" \
  env XHUB_RUST_HUB_PACKAGE_DIR=/tmp "$RELEASE_COMMAND" --check-canonical-roots

echo "canonical release root guards: PASS"
