#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xhub-provider-route-http-smoke-XXXXXX")"
RUNTIME_DIR="$TMP_ROOT/runtime"
DB_PATH="$TMP_ROOT/hub.sqlite3"
LOG_FILE="$TMP_ROOT/xhubd.log"
COMPARE_PAYLOAD="$TMP_ROOT/provider_compare_payload.json"
PORT="$((51000 + ($$ % 1000)))"
PID=""

cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$RUNTIME_DIR"
cat >"$RUNTIME_DIR/hub_provider_keys.json" <<'JSON'
{
  "schema_version": "hub_provider_keys.v1",
  "providers": {
    "openai": {
      "routing_strategy": "fill-first",
      "accounts": [
        {
          "account_key": "openai:http-smoke",
          "provider": "openai",
          "api_key": "sk-http-smoke-redacted",
          "models": ["gpt-4o"],
          "priority": 1
        }
      ]
    }
  }
}
JSON

(
  export XHUB_RUST_HUB_HTTP_PORT="$PORT"
  export HUB_RUNTIME_BASE_DIR="$RUNTIME_DIR"
  export HUB_DB_PATH="$DB_PATH"
  export XHUB_RUST_HUB_ROOT="$ROOT_DIR"
  if [ -x "$ROOT_DIR/bin/xhubd" ]; then
    exec "$ROOT_DIR/bin/xhubd" serve
  fi
  cd "$ROOT_DIR"
  exec cargo run --bin xhubd -- serve
) >"$LOG_FILE" 2>&1 &
PID="$!"

for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo "xhubd serve exited before health was ready" >&2
    cat "$LOG_FILE" >&2 || true
    exit 1
  fi
  sleep 0.1
done

curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null
curl -fsS "http://127.0.0.1:$PORT/provider/reports?limit=3" >/dev/null
READINESS="$(curl -fsS "http://127.0.0.1:$PORT/provider/readiness?min_compare_reports=0&max_mismatches=0&limit=3")"
RESPONSE="$(curl -fsS "http://127.0.0.1:$PORT/provider/route?model_id=gpt-4o&provider=openai&runtime_base_dir=$RUNTIME_DIR&now_ms=1000")"
cat >"$COMPARE_PAYLOAD" <<JSON
{
  "runtime_base_dir": "$RUNTIME_DIR",
  "model_id": "gpt-4o",
  "provider": "openai",
  "now_ms": 1000,
  "node_decision": {
    "requested_provider": "openai",
    "requested_model_id": "gpt-4o",
    "resolved_provider": "openai",
    "strategy": "fill-first",
    "selection_scope": "openai::gpt-4o",
    "selected_account_key": "openai:http-smoke",
    "fallback_reason_code": "",
    "available_count": 1,
    "total_count": 1,
    "candidates": [
      {
        "account_key": "openai:http-smoke",
        "provider": "openai",
        "provider_group": "openai",
        "state": "ready",
        "reason_code": "selected_by_scheduler",
        "selected": true,
        "model_state_key": ""
      }
    ],
    "updated_at_ms": 1000
  }
}
JSON
COMPARE_RESPONSE="$(curl -fsS -X POST "http://127.0.0.1:$PORT/provider/compare" -H "content-type: application/json" --data-binary @"$COMPARE_PAYLOAD")"
READINESS_AFTER_COMPARE="$(curl -fsS "http://127.0.0.1:$PORT/provider/readiness?min_compare_reports=1&max_mismatches=0&limit=3")"

if [[ "$READINESS" != *'"ok":true'* || "$READINESS" != *'"command":"readiness"'* || "$READINESS" != *'"ready":true'* ]]; then
  echo "provider readiness HTTP smoke failed" >&2
  echo "$READINESS" >&2
  echo "--- xhubd log ---" >&2
  cat "$LOG_FILE" >&2 || true
  exit 1
fi

if [[ "$RESPONSE" != *'"ok":true'* || "$RESPONSE" != *'"command":"route"'* || "$RESPONSE" != *'"selected_account_key":"openai:http-smoke"'* ]]; then
  echo "provider route HTTP smoke failed" >&2
  echo "$RESPONSE" >&2
  echo "--- xhubd log ---" >&2
  cat "$LOG_FILE" >&2 || true
  exit 1
fi
echo "$RESPONSE"

if [[ "$COMPARE_RESPONSE" != *'"ok":true'* || "$COMPARE_RESPONSE" != *'"command":"compare"'* || "$COMPARE_RESPONSE" != *'"match":true'* ]]; then
  echo "provider compare HTTP smoke failed" >&2
  echo "$COMPARE_RESPONSE" >&2
  echo "--- xhubd log ---" >&2
  cat "$LOG_FILE" >&2 || true
  exit 1
fi
echo "$COMPARE_RESPONSE"

if [[ "$READINESS_AFTER_COMPARE" != *'"ok":true'* || "$READINESS_AFTER_COMPARE" != *'"command":"readiness"'* || "$READINESS_AFTER_COMPARE" != *'"ready":true'* ]]; then
  echo "provider readiness after compare HTTP smoke failed" >&2
  echo "$READINESS_AFTER_COMPARE" >&2
  echo "--- xhubd log ---" >&2
  cat "$LOG_FILE" >&2 || true
  exit 1
fi
echo "$READINESS_AFTER_COMPARE"
