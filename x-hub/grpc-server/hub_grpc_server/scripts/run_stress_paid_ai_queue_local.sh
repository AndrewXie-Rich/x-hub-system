#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HUB_RUNTIME_BASE_DIR="${HUB_RUNTIME_BASE_DIR:-$HOME/Library/Containers/com.rel.flowhub/Data/RELFlowHub}"
HUB_HOST="${HUB_HOST:-127.0.0.1}"
HUB_PORT="${HUB_PORT:-50061}"
HUB_PAIRING_PORT="${HUB_PAIRING_PORT:-50062}"
HUB_PAID_AI_GLOBAL_CONCURRENCY="${HUB_PAID_AI_GLOBAL_CONCURRENCY:-1}"
HUB_PAID_AI_PER_PROJECT_CONCURRENCY="${HUB_PAID_AI_PER_PROJECT_CONCURRENCY:-1}"
HUB_PAID_AI_QUEUE_TIMEOUT_MS="${HUB_PAID_AI_QUEUE_TIMEOUT_MS:-30000}"

HUB_LOG_PATH="${HUB_LOG_PATH:-/tmp/hub_stress_$(date +%Y%m%d_%H%M%S).log}"

hub_pid=""
cleanup() {
  if [[ -n "$hub_pid" ]]; then
    kill "$hub_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if lsof -nP -iTCP:"$HUB_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "[stress-local] reusing existing hub on :$HUB_PORT"
else
  echo "[stress-local] starting hub on :$HUB_PORT (log: $HUB_LOG_PATH)"
  HUB_RUNTIME_BASE_DIR="$HUB_RUNTIME_BASE_DIR" \
  HUB_HOST=0.0.0.0 \
  HUB_PORT="$HUB_PORT" \
  HUB_PAIRING_PORT="$HUB_PAIRING_PORT" \
  HUB_PAID_AI_GLOBAL_CONCURRENCY="$HUB_PAID_AI_GLOBAL_CONCURRENCY" \
  HUB_PAID_AI_PER_PROJECT_CONCURRENCY="$HUB_PAID_AI_PER_PROJECT_CONCURRENCY" \
  HUB_PAID_AI_QUEUE_TIMEOUT_MS="$HUB_PAID_AI_QUEUE_TIMEOUT_MS" \
    npm run start --prefix "$ROOT_DIR" >"$HUB_LOG_PATH" 2>&1 &
  hub_pid="$!"

  ready=0
  for _ in $(seq 1 60); do
    if lsof -nP -iTCP:"$HUB_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      ready=1
      break
    fi
    if ! kill -0 "$hub_pid" 2>/dev/null; then
      echo "[stress-local] hub exited early. tail log:"
      tail -n 120 "$HUB_LOG_PATH" || true
      exit 1
    fi
    sleep 0.25
  done
  if [[ "$ready" -ne 1 ]]; then
    echo "[stress-local] hub did not become ready on :$HUB_PORT"
    tail -n 120 "$HUB_LOG_PATH" || true
    exit 1
  fi
fi

HUB_RUNTIME_BASE_DIR="$HUB_RUNTIME_BASE_DIR" \
HUB_HOST="$HUB_HOST" \
HUB_PORT="$HUB_PORT" \
  "$ROOT_DIR/scripts/stress_paid_ai_queue.sh" "$@"
