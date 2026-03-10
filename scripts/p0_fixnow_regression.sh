#!/usr/bin/env bash
set -euo pipefail

BASE_DEFAULT="$HOME/Library/Containers/com.rel.flowhub/Data/RELFlowHub"
BASE_DIR="${AX_HUB_BASE_DIR:-$BASE_DEFAULT}"
PORT_PID_FILE="$BASE_DIR/.p0_port_conflict.pid"
LOCK_PID_FILE="$BASE_DIR/.p0_runtime_lock_holder.pid"

usage() {
  cat <<'EOF'
Usage:
  scripts/p0_fixnow_regression.sh inject-port [port]
  scripts/p0_fixnow_regression.sh clear-port
  scripts/p0_fixnow_regression.sh inject-runtime-lock
  scripts/p0_fixnow_regression.sh clear-runtime-lock
  scripts/p0_fixnow_regression.sh inject-tls-pem
  scripts/p0_fixnow_regression.sh clear-tls-pem
  scripts/p0_fixnow_regression.sh tail-fix-codes

Notes:
  - Default Hub base dir:
      ~/Library/Containers/com.rel.flowhub/Data/RELFlowHub
  - Override with:
      AX_HUB_BASE_DIR=/path/to/base scripts/p0_fixnow_regression.sh ...
EOF
}

require_base() {
  mkdir -p "$BASE_DIR"
}

inject_port() {
  local port="${1:-50052}"
  require_base
  clear_port || true

  if command -v nc >/dev/null 2>&1; then
    nohup nc -lk "$port" >/dev/null 2>&1 &
  else
    echo "error: nc is required for inject-port" >&2
    exit 1
  fi

  local pid="$!"
  sleep 0.2
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "error: failed to bind test listener on :$port" >&2
    exit 1
  fi
  echo "$pid" >"$PORT_PID_FILE"
  echo "ok: injected port conflict on :$port (pid=$pid)"
}

clear_port() {
  if [[ -f "$PORT_PID_FILE" ]]; then
    local pid
    pid="$(cat "$PORT_PID_FILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PORT_PID_FILE"
    echo "ok: cleared injected port conflict"
  else
    echo "ok: no injected port conflict pid file"
  fi
}

inject_runtime_lock() {
  require_base
  clear_runtime_lock || true

  local lock_file="$BASE_DIR/ai_runtime.lock"
  : >"$lock_file"

  if command -v python3 >/dev/null 2>&1; then
    nohup python3 - "$lock_file" <<'PY' >/dev/null 2>&1 &
import fcntl
import os
import sys
import time

lock_path = sys.argv[1]
fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
while True:
    time.sleep(1)
PY
  else
    echo "error: python3 is required for inject-runtime-lock" >&2
    exit 1
  fi

  local pid="$!"
  sleep 0.2
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "error: failed to start runtime lock holder" >&2
    exit 1
  fi
  echo "$pid" >"$LOCK_PID_FILE"
  echo "ok: injected runtime lock holder (pid=$pid, lock=$lock_file)"
}

clear_runtime_lock() {
  if [[ -f "$LOCK_PID_FILE" ]]; then
    local pid
    pid="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$LOCK_PID_FILE"
  fi
  rm -f "$BASE_DIR/ai_runtime.lock"
  echo "ok: cleared injected runtime lock"
}

inject_tls_pem() {
  require_base
  local tls_dir="$BASE_DIR/hub_grpc_tls"
  mkdir -p "$tls_dir"
  : >"$tls_dir/server.cert.pem"
  echo "BROKEN PEM" >"$tls_dir/server.cert.pem"
  echo "ok: injected broken TLS server cert at $tls_dir/server.cert.pem"
}

clear_tls_pem() {
  local tls_dir="$BASE_DIR/hub_grpc_tls"
  rm -f "$tls_dir/server.cert.pem" "$tls_dir/server.csr.pem" "$tls_dir/server.ext"
  echo "ok: cleared injected TLS cert files"
}

tail_fix_codes() {
  local log="$BASE_DIR/hub_debug.log"
  if [[ ! -f "$log" ]]; then
    echo "no hub_debug.log at: $log"
    return 0
  fi
  rg -n "diagnostics\\.fix result code=" "$log" | tail -n 30
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    inject-port)
      shift
      inject_port "${1:-50052}"
      ;;
    clear-port)
      clear_port
      ;;
    inject-runtime-lock)
      inject_runtime_lock
      ;;
    clear-runtime-lock)
      clear_runtime_lock
      ;;
    inject-tls-pem)
      inject_tls_pem
      ;;
    clear-tls-pem)
      clear_tls_pem
      ;;
    tail-fix-codes)
      tail_fix_codes
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
