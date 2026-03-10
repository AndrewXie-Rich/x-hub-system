#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
AXHUBCTL="${AXHUBCTL:-$REPO_ROOT/x-hub/grpc-server/hub_grpc_server/assets/axhubctl}"

if [[ ! -f "$AXHUBCTL" ]]; then
  echo "axhubctl not found: $AXHUBCTL"
  exit 2
fi

PAIRING_PORT="${PAIRING_PORT:-}"
GRPC_PORT="${GRPC_PORT:-}"
LAN_FAIL_PAIRING_PORT="${LAN_FAIL_PAIRING_PORT:-9}"
INTERNET_HOST="${INTERNET_HOST:-127.0.0.1}"
DIRECT_FAIL_HOST="${DIRECT_FAIL_HOST:-203.0.113.10}"

LOG_DIR="${LOG_DIR:-$REPO_ROOT/x-terminal/x-terminal-legacy/logs/smoke}"
mkdir -p "$LOG_DIR"
RUN_TS="$(date +%Y%m%d_%H%M%S)"
STATE_DIR_BASE="${AXHUBCTL_STATE_DIR:-/tmp/xterminal_hub_smoke_${USER}_${RUN_TS}}"
STATE_DIR_LAN="$STATE_DIR_BASE/lan"
STATE_DIR_OFFLINE="$STATE_DIR_BASE/offline"
mkdir -p "$STATE_DIR_LAN" "$STATE_DIR_OFFLINE"
LOG_FILE="$LOG_DIR/hub_route_switch_${RUN_TS}.log"

detect_ports_if_needed() {
  if [[ -n "$PAIRING_PORT" && -n "$GRPC_PORT" ]]; then
    return 0
  fi

  local probe
  local rc
  local p
  for p in 50052 50053 50054; do
    set +e
    probe="$(env AXHUBCTL_STATE_DIR="$STATE_DIR_LAN" HUB_DISCOVERY_HINTS="127.0.0.1" \
      bash "$AXHUBCTL" discover --pairing-port "$p" --timeout-sec 1 2>&1)"
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
      local parsed_pairing parsed_grpc
      parsed_pairing="$(printf '%s\n' "$probe" | sed -n 's/^[[:space:]]*pairing_port[[:space:]]*:[[:space:]]*//p' | head -n 1 | tr -d '\r')"
      parsed_grpc="$(printf '%s\n' "$probe" | sed -n 's/^[[:space:]]*grpc_port[[:space:]]*:[[:space:]]*//p' | head -n 1 | tr -d '\r')"
      if [[ -z "$PAIRING_PORT" ]]; then
        PAIRING_PORT="${parsed_pairing:-$p}"
      fi
      if [[ -z "$GRPC_PORT" ]]; then
        GRPC_PORT="${parsed_grpc:-50051}"
      fi
      return 0
    fi
  done

  if [[ -z "$PAIRING_PORT" ]]; then
    PAIRING_PORT="50052"
  fi
  if [[ -z "$GRPC_PORT" ]]; then
    GRPC_PORT="50051"
  fi
}

run_step() {
  local name="$1"
  local expect="$2"
  shift 2

  echo "===== $name =====" | tee -a "$LOG_FILE"
  echo "cmd: $*" | tee -a "$LOG_FILE"
  set +e
  local out
  out="$("$@" 2>&1)"
  local rc=$?
  set -e
  printf '%s\n' "$out" | tee -a "$LOG_FILE"
  echo "rc=$rc expected=$expect" | tee -a "$LOG_FILE"
  echo "{\"step\":\"$name\",\"rc\":$rc,\"expected\":\"$expect\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" | tee -a "$LOG_FILE"
  echo | tee -a "$LOG_FILE"

  case "$expect" in
    ok)
      [[ $rc -eq 0 ]]
      ;;
    fail)
      [[ $rc -ne 0 ]]
      ;;
    *)
      echo "invalid expect value: $expect" | tee -a "$LOG_FILE"
      return 2
      ;;
  esac
}

echo "Hub route-switch smoke baseline" | tee "$LOG_FILE"
detect_ports_if_needed
echo "state_dir_base=$STATE_DIR_BASE" | tee -a "$LOG_FILE"
echo "pairing_port=$PAIRING_PORT grpc_port=$GRPC_PORT" | tee -a "$LOG_FILE"
echo "internet_host=$INTERNET_HOST direct_fail_host=$DIRECT_FAIL_HOST" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"

run_step \
  "lan_discover" \
  ok \
  env AXHUBCTL_STATE_DIR="$STATE_DIR_LAN" HUB_DISCOVERY_HINTS="127.0.0.1" \
  bash "$AXHUBCTL" discover --pairing-port "$PAIRING_PORT" --timeout-sec 2

run_step \
  "lan_connect_auto" \
  ok \
  env AXHUBCTL_STATE_DIR="$STATE_DIR_LAN" HUB_DISCOVERY_HINTS="127.0.0.1" \
  bash "$AXHUBCTL" connect --hub auto --pairing-port "$PAIRING_PORT" --grpc-port "$GRPC_PORT" --timeout-sec 2

run_step \
  "simulate_wifi_off_auto_discovery_fail" \
  fail \
  env AXHUBCTL_STATE_DIR="$STATE_DIR_OFFLINE" HUB_DISCOVERY_HINTS="192.0.2.1" \
  bash "$AXHUBCTL" connect --hub auto --pairing-port "$LAN_FAIL_PAIRING_PORT" --grpc-port "$GRPC_PORT" --timeout-sec 1

run_step \
  "internet_direct_connect" \
  ok \
  env AXHUBCTL_STATE_DIR="$STATE_DIR_OFFLINE" \
  bash "$AXHUBCTL" connect --hub "$INTERNET_HOST" --pairing-port "$PAIRING_PORT" --grpc-port "$GRPC_PORT" --timeout-sec 2

run_step \
  "internet_direct_fail" \
  fail \
  env AXHUBCTL_STATE_DIR="$STATE_DIR_OFFLINE" \
  bash "$AXHUBCTL" connect --hub "$DIRECT_FAIL_HOST" --pairing-port "$PAIRING_PORT" --grpc-port "$GRPC_PORT" --timeout-sec 2

run_step \
  "tunnel_localhost_connect" \
  ok \
  env AXHUBCTL_STATE_DIR="$STATE_DIR_OFFLINE" \
  bash "$AXHUBCTL" connect --hub 127.0.0.1 --pairing-port "$PAIRING_PORT" --grpc-port "$GRPC_PORT" --timeout-sec 2

echo "Smoke done. Baseline log: $LOG_FILE"
