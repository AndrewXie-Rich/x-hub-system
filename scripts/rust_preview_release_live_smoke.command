#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_PATH="${1:-${XHUB_RELEASE_SMOKE_TARGET:-}}"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/rust_preview_release_live_smoke.command <release-stage-dir-or-X-Hub.app>

Examples:
  scripts/rust_preview_release_live_smoke.command /private/tmp/xhub_release_smoke/stage/XHub-System-Rust-v0.1.0-alpha.5-rust-preview-macos-arm64
  scripts/rust_preview_release_live_smoke.command /Applications/X-Hub.app

This smoke starts the packaged Rust kernel and packaged Hub Node sidecar without
launching the Swift UI. It verifies:
  - Rust kernel /health, /ready, /xt/hub-contract, /network/remote-entry-candidates
  - Swift shell pairing /pairing/discovery
  - Swift shell /xt/hub-contract proxy to the Rust kernel
EOF
}

if [ -z "$TARGET_PATH" ] || [ "$TARGET_PATH" = "-h" ] || [ "$TARGET_PATH" = "--help" ]; then
  usage
  exit 2
fi

if [ -d "$TARGET_PATH/X-Hub.app" ]; then
  HUB_APP="$TARGET_PATH/X-Hub.app"
else
  HUB_APP="$TARGET_PATH"
fi

RESOURCES_DIR="$HUB_APP/Contents/Resources"
NODE_DIR="$RESOURCES_DIR/hub_grpc_server"
NODE_BIN="$RESOURCES_DIR/relflowhub_node"
RUST_ROOT="$RESOURCES_DIR/rust-hub"
XHUBD="$RUST_ROOT/bin/xhubd"

require_executable() {
  local path="$1"
  local label="$2"
  if [ ! -x "$path" ]; then
    echo "[smoke] missing executable $label: $path" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    echo "[smoke] missing $label: $path" >&2
    exit 1
  fi
}

require_dir() {
  local path="$1"
  local label="$2"
  if [ ! -d "$path" ]; then
    echo "[smoke] missing $label: $path" >&2
    exit 1
  fi
}

require_executable "$HUB_APP/Contents/MacOS/RELFlowHub" "X-Hub app binary"
require_executable "$NODE_BIN" "packaged Node runtime"
require_executable "$XHUBD" "embedded Rust kernel"
require_executable "$RUST_ROOT/tools/xt_hub_contract_smoke.command" "XT contract smoke tool"
require_dir "$NODE_DIR/src" "packaged hub_grpc_server source"
require_file "$NODE_DIR/src/pairing_http.js" "packaged pairing HTTP server"
require_file "$NODE_DIR/src/server.js" "packaged Hub Node sidecar"
require_file "$RESOURCES_DIR/protocol/hub_protocol_v1.proto" "packaged Hub protocol"

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xhub_release_live_smoke.XXXXXX")"
RUST_LOG="$SMOKE_ROOT/xhubd.log"
NODE_LOG="$SMOKE_ROOT/node-sidecar.log"

BASE_PORT=$((52000 + ($$ % 1000)))
RUST_PORT="${XHUB_RELEASE_SMOKE_RUST_PORT:-$BASE_PORT}"
GRPC_PORT="${XHUB_RELEASE_SMOKE_GRPC_PORT:-$((BASE_PORT + 1))}"
PAIRING_PORT="${XHUB_RELEASE_SMOKE_PAIRING_PORT:-$((BASE_PORT + 2))}"
RUST_BASE_URL="http://127.0.0.1:$RUST_PORT"
PAIRING_BASE_URL="http://127.0.0.1:$PAIRING_PORT"

RUST_PID=""
NODE_PID=""

cleanup() {
  if [ -n "$NODE_PID" ]; then
    kill "$NODE_PID" >/dev/null 2>&1 || true
    wait "$NODE_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$RUST_PID" ]; then
    kill "$RUST_PID" >/dev/null 2>&1 || true
    wait "$RUST_PID" >/dev/null 2>&1 || true
  fi
  if [ "${XHUB_RELEASE_SMOKE_KEEP_TMP:-0}" != "1" ]; then
    rm -rf "$SMOKE_ROOT"
  else
    echo "[smoke] kept temp root: $SMOKE_ROOT"
  fi
}
trap cleanup EXIT

wait_for_url() {
  local url="$1"
  local label="$2"
  local deadline=$((SECONDS + 20))
  local last_status=1
  while [ "$SECONDS" -lt "$deadline" ]; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    last_status=$?
    sleep 0.25
  done
  echo "[smoke] timed out waiting for $label: $url" >&2
  echo "[smoke] curl status: $last_status" >&2
  echo "[smoke] xhubd log:" >&2
  tail -n 80 "$RUST_LOG" >&2 2>/dev/null || true
  echo "[smoke] node sidecar log:" >&2
  tail -n 80 "$NODE_LOG" >&2 2>/dev/null || true
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" "$file"; then
    echo "[smoke] expected $label to contain: $needle" >&2
    echo "[smoke] actual $label:" >&2
    cat "$file" >&2
    exit 1
  fi
}

echo "[smoke] Hub app: $HUB_APP"
echo "[smoke] temp: $SMOKE_ROOT"
echo "[smoke] ports: rust=$RUST_PORT grpc=$GRPC_PORT pairing=$PAIRING_PORT"

mkdir -p "$SMOKE_ROOT/rust/data" "$SMOKE_ROOT/rust/runtime" "$SMOKE_ROOT/node/runtime"

(
  cd "$RUST_ROOT"
  export XHUB_RUST_HUB_ROOT="$RUST_ROOT"
  export XHUB_RUST_HUB_HOST="127.0.0.1"
  export XHUB_RUST_HUB_HTTP_PORT="$RUST_PORT"
  export HUB_DB_PATH="$SMOKE_ROOT/rust/data/hub.sqlite3"
  export HUB_RUNTIME_BASE_DIR="$SMOKE_ROOT/rust/runtime"
  export XHUB_RUST_MEMORY_DIR="$SMOKE_ROOT/rust/data/memory"
  exec "$XHUBD" serve
) >"$RUST_LOG" 2>&1 &
RUST_PID="$!"

wait_for_url "$RUST_BASE_URL/health" "Rust kernel health"
wait_for_url "$RUST_BASE_URL/ready" "Rust kernel readiness"

curl -fsS "$RUST_BASE_URL/xt/hub-contract" > "$SMOKE_ROOT/rust_contract.json"
assert_contains "$SMOKE_ROOT/rust_contract.json" '"schema_version":"xhub.rust_hub.xt_contract.v1"' "Rust contract"
assert_contains "$SMOKE_ROOT/rust_contract.json" '"source_of_truth":"hub"' "Rust contract"
assert_contains "$SMOKE_ROOT/rust_contract.json" '"canonical_writer":"hub_only"' "Rust contract"
assert_contains "$SMOKE_ROOT/rust_contract.json" '"lease_required":true' "Rust contract"

curl -fsS "$RUST_BASE_URL/network/remote-entry-candidates" > "$SMOKE_ROOT/remote_entry.json"
assert_contains "$SMOKE_ROOT/remote_entry.json" '"schema_version":"xhub.rust_hub.remote_entry_candidates.v1"' "remote-entry candidates"
assert_contains "$SMOKE_ROOT/remote_entry.json" '"no_domain_private_network_supported":true' "remote-entry candidates"

(
  cd "$NODE_DIR"
  export HUB_HOST="127.0.0.1"
  export HUB_PORT="$GRPC_PORT"
  export HUB_PAIRING_ENABLE="1"
  export HUB_PAIRING_HOST="127.0.0.1"
  export HUB_PAIRING_PORT="$PAIRING_PORT"
  export HUB_PAIRING_ALLOWED_CIDRS="any"
  export HUB_RUNTIME_BASE_DIR="$SMOKE_ROOT/node/runtime"
  export HUB_DB_PATH="$SMOKE_ROOT/node/hub.sqlite3"
  export HUB_PROTO_PATH="$RESOURCES_DIR/protocol/hub_protocol_v1.proto"
  export XHUB_RUST_HUB_EMBEDDED="1"
  export XHUB_RUST_HUB_ROOT="$RUST_ROOT"
  export XHUB_RUST_HUB_HTTP_BASE_URL="$RUST_BASE_URL"
  export XHUB_RUST_HTTP_ACCESS_KEY_FILE="$RUST_ROOT/secrets/xhubd_http_access_key"
  exec "$NODE_BIN" src/server.js
) >"$NODE_LOG" 2>&1 &
NODE_PID="$!"

wait_for_url "$PAIRING_BASE_URL/health" "Swift shell pairing health"

curl -fsS "$PAIRING_BASE_URL/pairing/discovery" > "$SMOKE_ROOT/discovery.json"
assert_contains "$SMOKE_ROOT/discovery.json" '"service":"pairing"' "pairing discovery"
assert_contains "$SMOKE_ROOT/discovery.json" '"xt_contract_endpoint":"/xt/hub-contract"' "pairing discovery"
assert_contains "$SMOKE_ROOT/discovery.json" '"xt_contract_schema_version":"xhub.rust_hub.xt_contract.v1"' "pairing discovery"
assert_contains "$SMOKE_ROOT/discovery.json" '"hub_product_boundary":"swift_shell_rust_kernel"' "pairing discovery"
assert_contains "$SMOKE_ROOT/discovery.json" '"rust_kernel_contract_bridge":true' "pairing discovery"

curl -fsS "$PAIRING_BASE_URL/xt/hub-contract" > "$SMOKE_ROOT/shell_contract.json"
assert_contains "$SMOKE_ROOT/shell_contract.json" '"schema_version":"xhub.rust_hub.xt_contract.v1"' "Swift shell contract proxy"
assert_contains "$SMOKE_ROOT/shell_contract.json" '"source_of_truth":"hub"' "Swift shell contract proxy"
assert_contains "$SMOKE_ROOT/shell_contract.json" '"canonical_writer":"hub_only"' "Swift shell contract proxy"
assert_contains "$SMOKE_ROOT/shell_contract.json" '"lease_required":true' "Swift shell contract proxy"

echo "[smoke] OK: packaged X-Hub.app exposes Swift shell discovery and proxies XT Hub contract to embedded Rust kernel."
