#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
RELEASE_COMMAND="$ROOT_DIR/scripts/package_macos_release.command"
COMBINED_BUILD_COMMAND="$ROOT_DIR/scripts/build_hub_and_xt_apps.command"
XT_GATE="$ROOT_DIR/x-terminal/scripts/ci/xt_release_gate.sh"

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

expect_rejected "combined build command override" \
  env XHUB_ACTIVE_XT_BUILD_COMMAND=/tmp/not-canonical "$COMBINED_BUILD_COMMAND" --help

expect_rejected "combined app output override" \
  env XHUB_ACTIVE_XT_APP_DIR=/tmp/not-canonical.app "$COMBINED_BUILD_COMMAND" --help

if ! "$COMBINED_BUILD_COMMAND" --help | grep -Fq "$ROOT_DIR/x-terminal/tools/build_xt_with_rust_sidecar.command"; then
  echo "[FAIL] Combined build help did not report the canonical XT build command." >&2
  exit 1
fi

if ! grep -Fq 'xterminal_assert_canonical_root "$WORKSPACE_ROOT" "$ROOT_DIR"' "$XT_GATE"; then
  echo "[FAIL] XT release gate does not enforce the canonical root guard." >&2
  exit 1
fi

echo "canonical release root guards: PASS"
