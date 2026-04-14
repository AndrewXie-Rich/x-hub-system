#!/bin/bash
set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${XHUB_PAIRING_SMOKE_APP_PATH:-${ROOT_DIR}/build/X-Hub.app}"
REPORT_PATH="${XHUB_PAIRING_SMOKE_REPORT_PATH:-${ROOT_DIR}/build/reports/xhub_background_pairing_smoke_evidence.v1.json}"
DISCOVERY_URL="${XHUB_PAIRING_SMOKE_DISCOVERY_URL:-http://127.0.0.1:50055/pairing/discovery}"
DISCOVERY_TIMEOUT_MS="${XHUB_PAIRING_SMOKE_DISCOVERY_TIMEOUT_MS:-20000}"
PRELAUNCH_DISCOVERY_RETRY_MS="${XHUB_PAIRING_SMOKE_PRELAUNCH_DISCOVERY_RETRY_MS:-3000}"
PENDING_TIMEOUT_MS="${XHUB_PAIRING_SMOKE_PENDING_TIMEOUT_MS:-8000}"
PAIRING_SMOKE_MODE_RAW="${XHUB_PAIRING_SMOKE_MODE:-auto}"
PAIRING_SMOKE_SKIP_LAUNCH_RAW="${XHUB_PAIRING_SMOKE_SKIP_LAUNCH:-}"
HUB_DB_REL_PATH="hub_grpc/hub.sqlite3"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xhub_background_pairing_smoke.XXXXXX")"

STARTED_AT_MS="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
FINISHED_AT_MS=""
EXIT_CODE=0
ERRORS=""
LAUNCH_ACTION=""
OPEN_STATUS=""
OPEN_STDERR=""
DISCOVERY_OK=0
DISCOVERY_STATUS=0
DISCOVERY_RESPONSE_JSON=""
PAIRING_BASE_URL=""
PAIRING_POST_URL=""
PENDING_LIST_URL=""
DENY_BASE_URL=""
HUB_STATUS_FILE=""
HUB_BASE_DIR=""
HUB_PID=0
HUB_UPDATED_AT=0
HUB_AI_READY=""
HUB_STATUS_APP_PATH=""
ADMIN_TOKEN_RESOLVED=0
ADMIN_TOKEN_SOURCE=""
TOKENS_FILE=""
KEY_FILE=""
ADMIN_TOKEN=""
REQUEST_ID=""
PAIRING_REQUEST_ID=""
DEVICE_NAME=""
POST_STATUS=0
PENDING_LIST_STATUS=0
PENDING_LIST_CONTAINS_REQUEST=0
CLEANUP_STATUS=""
CLEANUP_VERIFIED=0
DB_EVIDENCE=""
BACKGROUND_LAUNCH_EVIDENCE_FOUND=0
BACKGROUND_LAUNCH_EVIDENCE_LINES=""
MAIN_PANEL_SHOWN_AFTER_LAUNCH=0
PAIRING_SMOKE_MODE=""

cleanup_tmp() {
  rm -rf "$TMP_ROOT"
}
trap cleanup_tmp EXIT

append_error() {
  local message="$1"
  EXIT_CODE=1
  ERRORS+="${message}"$'\n'
}

is_truthy() {
  local raw=""
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_smoke_mode() {
  local raw=""
  raw="$(printf '%s' "$PAIRING_SMOKE_MODE_RAW" | tr '[:upper:]' '[:lower:]')"
  [ -n "$raw" ] || raw="auto"
  if is_truthy "$PAIRING_SMOKE_SKIP_LAUNCH_RAW" && [ "$raw" = "auto" ]; then
    raw="verify_only"
  fi
  case "$raw" in
    auto|launch_only|verify_only)
      printf '%s\n' "$raw"
      ;;
    *)
      return 1
      ;;
  esac
}

mode_allows_launch() {
  [ "$PAIRING_SMOKE_MODE" != "verify_only" ]
}

mode_runs_pairing_roundtrip() {
  [ "$PAIRING_SMOKE_MODE" != "launch_only" ]
}

json_quote() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
}

capture_discovery() {
  local out_file="$1"
  local err_file="$2"
  local body=""
  body="$(curl -fsS "$DISCOVERY_URL" 2>"$err_file")"
  local status=$?
  if [ $status -ne 0 ] || [ -z "$body" ]; then
    return 1
  fi
  printf '%s\n' "$body" >"$out_file"
  return 0
}

wait_for_discovery() {
  local out_file="$1"
  local err_file="$2"
  local timeout_ms="${3:-$DISCOVERY_TIMEOUT_MS}"
  local deadline=""
  deadline="$(python3 - "$timeout_ms" <<'PY'
import sys
import time
timeout_ms = int(float(sys.argv[1] or "20000"))
print(time.time() + (timeout_ms / 1000.0))
PY
)"
  while python3 - "$deadline" <<'PY'
import sys
import time
sys.exit(0 if time.time() < float(sys.argv[1]) else 1)
PY
  do
    if capture_discovery "$out_file" "$err_file"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

resolve_pairing_base_url() {
  python3 - "$1" <<'PY'
import json
import sys
from urllib.parse import urlparse

discovery_url = sys.argv[1]
obj = json.loads(sys.stdin.read() or "{}")
pairing_port = obj.get("pairing_port") or obj.get("pairingPort") or 0
try:
    pairing_port = int(pairing_port)
except Exception:
    pairing_port = 0
if pairing_port > 0:
    print(f"http://127.0.0.1:{pairing_port}")
else:
    parsed = urlparse(discovery_url)
    print(f"{parsed.scheme}://{parsed.netloc}")
PY
}

resolve_hub_status() {
  python3 - "$ROOT_DIR" <<'PY'
import json
import os
import shlex
import signal
import sys
import time

root_dir = sys.argv[1]
ttl_sec = 12.0
home = os.environ.get("XHUB_SOURCE_RUN_HOME", "").strip() or os.path.expanduser("~")
bundle_id = "com.rel.flowhub"
group_id = "group.rel.flowhub"
explicit = os.environ.get("REL_FLOW_HUB_BASE_DIR", "").strip()
container_base = os.path.join(home, "Library", "Containers", bundle_id, "Data")

dirs = []
for value in [
    explicit,
    os.path.join(home, "Library", "Group Containers", group_id),
    os.path.join(container_base, "XHub"),
    os.path.join(container_base, "RELFlowHub"),
    os.path.join(home, "XHub"),
    os.path.join(home, "RELFlowHub"),
    "/private/tmp/XHub",
    "/private/tmp/RELFlowHub",
    "/tmp/XHub",
    "/tmp/RELFlowHub",
]:
    value = (value or "").strip()
    if value and value not in dirs:
        dirs.append(value)

def pid_alive(pid_value):
    try:
        pid = int(pid_value or 0)
    except Exception:
        return True
    if pid <= 1:
        return True
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except ProcessLookupError:
        return False
    except Exception:
        return False

best = None
for dir_path in dirs:
    status_path = os.path.join(dir_path, "hub_status.json")
    try:
        with open(status_path, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except Exception:
        continue
    updated_at = float(obj.get("updatedAt") or obj.get("updated_at") or 0.0)
    if updated_at <= 0 or (time.time() - updated_at) >= ttl_sec:
        continue
    if not pid_alive(obj.get("pid")):
        continue
    if best is None or updated_at > best["updatedAt"]:
        best = {
            "file_path": status_path,
            "base_dir": str(obj.get("baseDir") or obj.get("base_dir") or dir_path).strip(),
            "pid": int(obj.get("pid") or 0),
            "updatedAt": updated_at,
            "ai_ready": obj.get("aiReady"),
            "app_path": str(obj.get("appPath") or obj.get("app_path") or "").strip(),
        }

if not best:
    print("HUB_STATUS_FILE=''")
    print("HUB_BASE_DIR=''")
    print("HUB_PID=0")
    print("HUB_UPDATED_AT=0")
    print("HUB_AI_READY=''")
    print("HUB_STATUS_APP_PATH=''")
    sys.exit(0)

print(f"HUB_STATUS_FILE={shlex.quote(best['file_path'])}")
print(f"HUB_BASE_DIR={shlex.quote(best['base_dir'])}")
print(f"HUB_PID={best['pid']}")
print(f"HUB_UPDATED_AT={best['updatedAt']}")
ai_ready = "" if best["ai_ready"] is None else str(best["ai_ready"]).lower()
print(f"HUB_AI_READY={shlex.quote(ai_ready)}")
print(f"HUB_STATUS_APP_PATH={shlex.quote(best['app_path'])}")
PY
}

resolve_admin_token() {
  local base_dir="$1"
  local resolution_json="$TMP_ROOT/admin_token_resolution.json"

  TOKENS_FILE=""
  KEY_FILE=""
  ADMIN_TOKEN=""
  ADMIN_TOKEN_SOURCE=""

  if ! node "$SCRIPT_DIR/resolve_xhub_local_admin_token.js" \
    --hub-dir "$base_dir" \
    --out-json "$resolution_json" \
    >/dev/null 2>"$TMP_ROOT/admin_token.err"; then
    :
  fi

  if [ ! -s "$resolution_json" ]; then
    ADMIN_TOKEN_SOURCE="resolution_cli_failed"
    return 1
  fi

  eval "$(python3 - "$resolution_json" <<'PY'
import json
import shlex
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        obj = json.load(fh)
except Exception:
    print("ADMIN_TOKEN=''")
    print("ADMIN_TOKEN_SOURCE='invalid_resolution_json'")
    print("TOKENS_FILE=''")
    print("KEY_FILE=''")
    sys.exit(0)

print(f"ADMIN_TOKEN={shlex.quote(str(obj.get('admin_token') or '').strip())}")
print(f"ADMIN_TOKEN_SOURCE={shlex.quote(str(obj.get('token_source') or '').strip())}")
print(f"TOKENS_FILE={shlex.quote(str(obj.get('tokens_file') or '').strip())}")
print(f"KEY_FILE={shlex.quote(str(obj.get('key_file') or '').strip())}")
PY
)"

  if [ -n "$ADMIN_TOKEN" ]; then
    ADMIN_TOKEN_RESOLVED=1
    return 0
  fi

  [ -n "$ADMIN_TOKEN_SOURCE" ] || ADMIN_TOKEN_SOURCE="unknown"
  return 1
}

launch_hub_background() {
  local app_path="$1"
  local executable_path="$app_path/Contents/MacOS/RELFlowHub"
  local open_err_file="$TMP_ROOT/open.err"
  local fallback_err_file="$TMP_ROOT/direct_launch.err"

  : >"$open_err_file"
  open -g "$app_path" --args --background >/dev/null 2>"$open_err_file"
  OPEN_STATUS=$?
  OPEN_STDERR="$(cat "$open_err_file")"
  if [ $OPEN_STATUS -eq 0 ]; then
    LAUNCH_ACTION="launched_background"
    return 0
  fi

  if [ ! -x "$executable_path" ]; then
    return 1
  fi

  : >"$fallback_err_file"
  "$executable_path" --background >/dev/null 2>"$fallback_err_file" &
  local fallback_status=$?
  local fallback_stderr=""
  if [ -f "$fallback_err_file" ]; then
    fallback_stderr="$(cat "$fallback_err_file")"
  fi
  if [ $fallback_status -ne 0 ]; then
    if [ -n "$fallback_stderr" ]; then
      OPEN_STDERR="${OPEN_STDERR}"$'\n'"direct_exec_failed:${fallback_stderr}"
    fi
    return 1
  fi

  LAUNCH_ACTION="launched_background_direct_exec"
  if [ -n "$fallback_stderr" ]; then
    OPEN_STDERR="${OPEN_STDERR}"$'\n'"direct_exec_stderr:${fallback_stderr}"
  fi
  OPEN_STDERR="${OPEN_STDERR}"$'\n'"direct_exec_fallback=used path=${executable_path}"
  OPEN_STATUS=0
  return 0
}

wait_for_pending_request() {
  local pairing_request_id="$1"
  local out_file="$2"
  local deadline=""
  deadline="$(python3 - "$PENDING_TIMEOUT_MS" <<'PY'
import sys
import time
timeout_ms = int(float(sys.argv[1] or "8000"))
print(time.time() + (timeout_ms / 1000.0))
PY
)"
  while python3 - "$deadline" <<'PY'
import sys
import time
sys.exit(0 if time.time() < float(sys.argv[1]) else 1)
PY
  do
    local tmp_body="$TMP_ROOT/pending.json"
    local http_code=""
    http_code="$(curl -sS \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Accept: application/json" \
      -o "$tmp_body" \
      -w "%{http_code}" \
      "$PENDING_LIST_URL" 2>"$TMP_ROOT/pending.err")"
    if [[ "$http_code" =~ ^[0-9]+$ ]]; then
      PENDING_LIST_STATUS="$http_code"
      if python3 - "$pairing_request_id" "$tmp_body" <<'PY'
import json
import sys
pairing_request_id = sys.argv[1]
path = sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as fh:
        obj = json.load(fh)
except Exception:
    sys.exit(1)
requests = obj.get("requests") or []
for item in requests:
    current = str(item.get("pairing_request_id") or "").strip()
    if current == pairing_request_id:
        sys.exit(0)
sys.exit(1)
PY
      then
        cp "$tmp_body" "$out_file"
        return 0
      fi
    fi
    sleep 0.4
  done
  return 1
}

pairing_db_row() {
  local db_path="$1"
  local pairing_request_id="$2"
  if [ ! -f "$db_path" ]; then
    return 0
  fi
  sqlite3 "$db_path" "select pairing_request_id,status,coalesce(deny_reason,''),coalesce(request_id,''),coalesce(device_name,'') from pairing_requests where pairing_request_id='${pairing_request_id//\'/\'\'}';" 2>/dev/null
}

if ! PAIRING_SMOKE_MODE="$(normalize_smoke_mode)"; then
  PAIRING_SMOKE_MODE="invalid"
  append_error "invalid_mode:${PAIRING_SMOKE_MODE_RAW:-}"
fi

DISCOVERY_BODY_FILE="$TMP_ROOT/discovery.json"
DISCOVERY_ERR_FILE="$TMP_ROOT/discovery.err"

if [ "$PAIRING_SMOKE_MODE" != "invalid" ] && capture_discovery "$DISCOVERY_BODY_FILE" "$DISCOVERY_ERR_FILE"; then
  if [ "$PAIRING_SMOKE_MODE" = "verify_only" ]; then
    LAUNCH_ACTION="verify_only_existing_hub"
  else
    LAUNCH_ACTION="already_ready"
  fi
elif [ "$PAIRING_SMOKE_MODE" != "invalid" ]; then
  if wait_for_discovery "$DISCOVERY_BODY_FILE" "$DISCOVERY_ERR_FILE" "$PRELAUNCH_DISCOVERY_RETRY_MS"; then
    if [ "$PAIRING_SMOKE_MODE" = "verify_only" ]; then
      LAUNCH_ACTION="verify_only_existing_hub_retry"
    else
      LAUNCH_ACTION="already_ready_retry"
    fi
  else
    eval "$(resolve_hub_status)"
    if [ -n "$HUB_BASE_DIR" ] && wait_for_discovery "$DISCOVERY_BODY_FILE" "$DISCOVERY_ERR_FILE"; then
      if [ "$PAIRING_SMOKE_MODE" = "verify_only" ]; then
        LAUNCH_ACTION="verify_only_existing_hub_retry_after_status"
      else
        LAUNCH_ACTION="already_ready_retry_after_status"
      fi
    elif mode_allows_launch; then
      if ! launch_hub_background "$APP_PATH"; then
        append_error "open_failed:${OPEN_STDERR:-$OPEN_STATUS}"
      fi
      if ! wait_for_discovery "$DISCOVERY_BODY_FILE" "$DISCOVERY_ERR_FILE"; then
        append_error "discovery_not_ready:$(tr '\n' ' ' <"$DISCOVERY_ERR_FILE" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')"
      fi
    else
      LAUNCH_ACTION="verify_only_launch_skipped"
      append_error "discovery_not_ready_verify_only:$(tr '\n' ' ' <"$DISCOVERY_ERR_FILE" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')"
    fi
  fi
fi

if [ -f "$DISCOVERY_BODY_FILE" ] && [ -s "$DISCOVERY_BODY_FILE" ]; then
  DISCOVERY_OK=1
  DISCOVERY_STATUS=200
  DISCOVERY_RESPONSE_JSON="$(cat "$DISCOVERY_BODY_FILE")"
  PAIRING_BASE_URL="$(resolve_pairing_base_url "$DISCOVERY_URL" <"$DISCOVERY_BODY_FILE")"
  PAIRING_POST_URL="${PAIRING_BASE_URL}/pairing/requests"
  PENDING_LIST_URL="${PAIRING_BASE_URL}/admin/pairing/requests?status=pending&limit=200"
  DENY_BASE_URL="$PAIRING_BASE_URL"
else
  DISCOVERY_OK=0
fi

if [ "$PAIRING_SMOKE_MODE" != "invalid" ]; then
  eval "$(resolve_hub_status)"

  if [ -z "$HUB_BASE_DIR" ]; then
    append_error "fresh_hub_status_missing"
  fi

  if mode_runs_pairing_roundtrip && [ -n "$HUB_BASE_DIR" ]; then
    if resolve_admin_token "$HUB_BASE_DIR"; then
      :
    else
      append_error "admin_token_unavailable:${ADMIN_TOKEN_SOURCE}"
    fi
  fi
fi

if [[ "$LAUNCH_ACTION" == launched_background* ]] && [ -n "$HUB_BASE_DIR" ]; then
  DEBUG_LOG_PATH="$HUB_BASE_DIR/hub_debug.log"
  if [ -f "$DEBUG_LOG_PATH" ]; then
    BACKGROUND_LAUNCH_EVIDENCE_LINES="$(rg -n "presentation=background|background_mode_ready|mainPanel.show" "$DEBUG_LOG_PATH" | tail -n 20 || true)"
    if printf '%s\n' "$BACKGROUND_LAUNCH_EVIDENCE_LINES" | rg -q "presentation=background" && \
       printf '%s\n' "$BACKGROUND_LAUNCH_EVIDENCE_LINES" | rg -q "background_mode_ready"; then
      BACKGROUND_LAUNCH_EVIDENCE_FOUND=1
    fi
    if printf '%s\n' "$BACKGROUND_LAUNCH_EVIDENCE_LINES" | rg -q "mainPanel.show"; then
      MAIN_PANEL_SHOWN_AFTER_LAUNCH=1
    fi
  fi
fi

if mode_runs_pairing_roundtrip && [ $DISCOVERY_OK -eq 1 ] && [ $ADMIN_TOKEN_RESOLVED -eq 1 ]; then
  REQUEST_ID="xhub_bg_pairing_smoke_${STARTED_AT_MS}"
  DEVICE_NAME="XHub Background Smoke ${STARTED_AT_MS}"
  RANDOM_SECRET_SUFFIX="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(6))
PY
)"

  POST_BODY_FILE="$TMP_ROOT/post_body.json"
  python3 - "$REQUEST_ID" "$DEVICE_NAME" "$RANDOM_SECRET_SUFFIX" >"$POST_BODY_FILE" <<'PY'
import json
import sys
request_id = sys.argv[1]
device_name = sys.argv[2]
suffix = sys.argv[3]
payload = {
    "app_id": "x-terminal",
    "request_id": request_id,
    "pairing_secret": f"xhub_bg_pairing_secret_{suffix}",
    "device_name": device_name,
    "device_id": f"xhub_bg_pairing_probe_{request_id}",
    "requested_scopes": ["models", "events", "memory", "skills", "ai.generate.local", "web.fetch"],
    "device_info": {"probe": True, "source": "xhub_background_pairing_smoke"},
}
print(json.dumps(payload))
PY

  POST_RESPONSE_FILE="$TMP_ROOT/post_response.json"
  POST_STATUS="$(curl -sS \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -o "$POST_RESPONSE_FILE" \
    -w "%{http_code}" \
    --data-binary @"$POST_BODY_FILE" \
    "$PAIRING_POST_URL" 2>"$TMP_ROOT/post.err")"

  if [ "$POST_STATUS" != "200" ] && [ "$POST_STATUS" != "201" ]; then
    append_error "pairing_post_failed:${POST_STATUS}"
  else
    PAIRING_REQUEST_ID="$(python3 - "$POST_RESPONSE_FILE" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        obj = json.load(fh)
except Exception:
    print("")
    sys.exit(0)
print(str(obj.get("pairing_request_id") or "").strip())
PY
)"
    if [ -z "$PAIRING_REQUEST_ID" ]; then
      append_error "pairing_request_id_missing"
    fi
  fi

  if [ -n "$PAIRING_REQUEST_ID" ]; then
    PENDING_RESPONSE_FILE="$TMP_ROOT/pending_list.json"
    if wait_for_pending_request "$PAIRING_REQUEST_ID" "$PENDING_RESPONSE_FILE"; then
      PENDING_LIST_CONTAINS_REQUEST=1
    else
      append_error "pending_list_missing_request"
    fi

    DB_PATH="$HUB_BASE_DIR/hub_grpc/hub.sqlite3"
    DB_EVIDENCE="$(pairing_db_row "$DB_PATH" "$PAIRING_REQUEST_ID")"
    if ! printf '%s\n' "$DB_EVIDENCE" | rg -q "pending"; then
      append_error "pairing_db_pending_evidence_missing"
    fi
  fi
fi

if [ -n "$PAIRING_REQUEST_ID" ] && [ -n "$ADMIN_TOKEN" ] && [ -n "$DENY_BASE_URL" ]; then
  DENY_RESPONSE_FILE="$TMP_ROOT/deny_response.json"
  DENY_HTTP_STATUS="$(curl -sS \
    -X POST \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -o "$DENY_RESPONSE_FILE" \
    -w "%{http_code}" \
    --data-binary '{"deny_reason":"xhub_background_pairing_smoke_cleanup"}' \
    "${DENY_BASE_URL}/admin/pairing/requests/${PAIRING_REQUEST_ID}/deny" 2>"$TMP_ROOT/deny.err")"
  if [ "$DENY_HTTP_STATUS" = "200" ]; then
    CLEANUP_STATUS="$(python3 - "$DENY_RESPONSE_FILE" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        obj = json.load(fh)
except Exception:
    print("")
    sys.exit(0)
print(str(obj.get("status") or "").strip())
PY
)"
  else
    CLEANUP_STATUS="http_${DENY_HTTP_STATUS}"
    append_error "cleanup_failed:${CLEANUP_STATUS}"
  fi

  if [ -n "$HUB_BASE_DIR" ]; then
    CLEANUP_ROW="$(pairing_db_row "$HUB_BASE_DIR/$HUB_DB_REL_PATH" "$PAIRING_REQUEST_ID")"
    if printf '%s\n' "$CLEANUP_ROW" | rg -q "denied"; then
      CLEANUP_VERIFIED=1
      DB_EVIDENCE="$CLEANUP_ROW"
    fi
  fi
fi

FINISHED_AT_MS="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"

mkdir -p "$(dirname "$REPORT_PATH")"

export STARTED_AT_MS EXIT_CODE LAUNCH_ACTION APP_PATH OPEN_STATUS OPEN_STDERR
export PAIRING_SMOKE_MODE
export BACKGROUND_LAUNCH_EVIDENCE_FOUND BACKGROUND_LAUNCH_EVIDENCE_LINES MAIN_PANEL_SHOWN_AFTER_LAUNCH
export DISCOVERY_URL DISCOVERY_OK DISCOVERY_STATUS DISCOVERY_RESPONSE_JSON
export HUB_STATUS_FILE HUB_BASE_DIR HUB_PID HUB_UPDATED_AT HUB_AI_READY HUB_STATUS_APP_PATH
export ADMIN_TOKEN_RESOLVED ADMIN_TOKEN_SOURCE TOKENS_FILE KEY_FILE
export REQUEST_ID PAIRING_REQUEST_ID DEVICE_NAME POST_STATUS PENDING_LIST_STATUS
export PENDING_LIST_CONTAINS_REQUEST CLEANUP_STATUS CLEANUP_VERIFIED DB_EVIDENCE
export ERRORS FINISHED_AT_MS

python3 - "$REPORT_PATH" <<'PY'
import json
import os
import sys

def env_bool(name):
    return os.environ.get(name, "0") == "1"

def env_int(name):
    raw = os.environ.get(name, "0")
    try:
        return int(float(raw))
    except Exception:
        return 0

errors = [line for line in os.environ.get("ERRORS", "").splitlines() if line.strip()]
report = {
    "schemaVersion": "xhub.background_pairing_smoke.v1",
    "mode": os.environ.get("PAIRING_SMOKE_MODE", ""),
    "startedAtMs": env_int("STARTED_AT_MS"),
    "ok": os.environ.get("EXIT_CODE", "1") == "0",
    "launch": {
        "action": os.environ.get("LAUNCH_ACTION", ""),
        "appPath": os.environ.get("APP_PATH", ""),
        "openStatus": env_int("OPEN_STATUS") if os.environ.get("OPEN_STATUS", "") else None,
        "openStderr": os.environ.get("OPEN_STDERR", ""),
        "backgroundLaunchEvidenceFound": env_bool("BACKGROUND_LAUNCH_EVIDENCE_FOUND"),
        "backgroundLaunchEvidenceLines": [line for line in os.environ.get("BACKGROUND_LAUNCH_EVIDENCE_LINES", "").splitlines() if line.strip()],
        "mainPanelShownAfterLaunch": env_bool("MAIN_PANEL_SHOWN_AFTER_LAUNCH"),
    },
    "discovery": {
        "url": os.environ.get("DISCOVERY_URL", ""),
        "ok": env_bool("DISCOVERY_OK"),
        "status": env_int("DISCOVERY_STATUS"),
        "response": json.loads((os.environ.get("DISCOVERY_RESPONSE_JSON", "") or "null")),
    },
    "hubStatus": {
        "filePath": os.environ.get("HUB_STATUS_FILE", ""),
        "baseDir": os.environ.get("HUB_BASE_DIR", ""),
        "pid": env_int("HUB_PID"),
        "updatedAt": float(os.environ.get("HUB_UPDATED_AT", "0") or "0"),
        "aiReady": os.environ.get("HUB_AI_READY", ""),
        "appPath": os.environ.get("HUB_STATUS_APP_PATH", ""),
    },
    "adminToken": {
        "resolved": env_bool("ADMIN_TOKEN_RESOLVED"),
        "tokenSource": os.environ.get("ADMIN_TOKEN_SOURCE", ""),
        "tokensFile": os.environ.get("TOKENS_FILE", ""),
        "keyFile": os.environ.get("KEY_FILE", ""),
    },
    "pairing": {
        "requestId": os.environ.get("REQUEST_ID", ""),
        "pairingRequestId": os.environ.get("PAIRING_REQUEST_ID", ""),
        "deviceName": os.environ.get("DEVICE_NAME", ""),
        "requestedScopes": ["models", "events", "memory", "skills", "ai.generate.local", "web.fetch"],
        "postStatus": env_int("POST_STATUS"),
        "pendingListStatus": env_int("PENDING_LIST_STATUS"),
        "pendingListContainsRequest": env_bool("PENDING_LIST_CONTAINS_REQUEST"),
        "cleanupStatus": os.environ.get("CLEANUP_STATUS", ""),
        "cleanupVerified": env_bool("CLEANUP_VERIFIED"),
        "dbEvidence": os.environ.get("DB_EVIDENCE", ""),
    },
    "errors": errors,
    "finishedAtMs": env_int("FINISHED_AT_MS"),
}

with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(report, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

echo "[xhub-background-pairing-smoke] report=${REPORT_PATH}"
echo "[xhub-background-pairing-smoke] ok=$([ "$EXIT_CODE" = "0" ] && echo yes || echo no) mode=${PAIRING_SMOKE_MODE} launch=${LAUNCH_ACTION} pairing_cleanup=$([ "$CLEANUP_VERIFIED" = "1" ] && echo yes || echo no)"

if [ -n "$ERRORS" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "[xhub-background-pairing-smoke] error=${line}" >&2
  done <<<"$ERRORS"
fi

exit "$EXIT_CODE"
