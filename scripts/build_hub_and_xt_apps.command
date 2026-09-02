#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT_DIR/build"
LOG_DIR="$OUT_DIR/logs"
LOG_FILE="$LOG_DIR/build_hub_and_xt_apps.log"
ACTIVE_XT_ROOT="$ROOT_DIR/x-terminal"
# shellcheck source=../x-terminal/scripts/lib/canonical_root_guard.sh
source "$ACTIVE_XT_ROOT/scripts/lib/canonical_root_guard.sh"
xterminal_assert_canonical_root "$ROOT_DIR" "$ACTIVE_XT_ROOT"
ACTIVE_XT_BUILD_COMMAND="${XHUB_ACTIVE_XT_BUILD_COMMAND:-$ACTIVE_XT_ROOT/tools/build_xt_with_rust_sidecar.command}"
ACTIVE_XT_APP_DIR="${XHUB_ACTIVE_XT_APP_DIR:-$OUT_DIR/X-Terminal.app}"

BUILD_HUB=1
BUILD_XT=1
BUILD_ORDER="hub_first"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--hub-only | --xt-only] [--xt-first] [--hub-first]

Build both app bundles in one go:
  - X-Hub.app via x-hub/tools/build_hub_app.command
  - X-Terminal.app via the canonical in-repo XT build command:
    $ACTIVE_XT_BUILD_COMMAND

Options:
  --hub-only   Build only X-Hub.app
  --xt-only    Build only X-Terminal.app
  --xt-first   Build X-Terminal.app before X-Hub.app
  --hub-first  Build X-Hub.app before X-Terminal.app (default)
  -h, --help   Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --hub-only)
      BUILD_HUB=1
      BUILD_XT=0
      ;;
    --xt-only)
      BUILD_HUB=0
      BUILD_XT=1
      ;;
    --xt-first)
      BUILD_ORDER="xt_first"
      ;;
    --hub-first)
      BUILD_ORDER="hub_first"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() {
  echo "$1" | tee -a "$LOG_FILE"
}

on_error() {
  local exit_code=$?
  log ""
  log "[ERROR] Combined Hub + XT build failed (exit $exit_code)."
  log "[ERROR] Full log: $LOG_FILE"
  exit "$exit_code"
}

trap on_error ERR

run_step() {
  local label="$1"
  local script_path="$2"
  if [ ! -x "$script_path" ]; then
    log "[ERROR] Build script is not executable or missing: $script_path"
    exit 1
  fi
  log ""
  log "==> $label"
  log "    $script_path"
  "$script_path"
}

log "[LOG] Writing combined build log to: $LOG_FILE"
log "[INFO] Root: $ROOT_DIR"
log "[INFO] Build order: $BUILD_ORDER"

if [ "$BUILD_HUB" = "0" ] && [ "$BUILD_XT" = "0" ]; then
  log "[WARN] Nothing to build."
  exit 0
fi

if [ "$BUILD_ORDER" = "xt_first" ]; then
  if [ "$BUILD_XT" = "1" ]; then
    run_step "Building X-Terminal.app" "$ACTIVE_XT_BUILD_COMMAND"
  fi
  if [ "$BUILD_HUB" = "1" ]; then
    run_step "Building X-Hub.app" "$ROOT_DIR/x-hub/tools/build_hub_app.command"
  fi
else
  if [ "$BUILD_HUB" = "1" ]; then
    run_step "Building X-Hub.app" "$ROOT_DIR/x-hub/tools/build_hub_app.command"
  fi
  if [ "$BUILD_XT" = "1" ]; then
    run_step "Building X-Terminal.app" "$ACTIVE_XT_BUILD_COMMAND"
  fi
fi

log ""
log "Done."
if [ "$BUILD_HUB" = "1" ]; then
  log "X-Hub app: $OUT_DIR/X-Hub.app"
  log "Install X-Hub only: $ROOT_DIR/x-hub/tools/install_hub_app.command"
fi
if [ "$BUILD_XT" = "1" ]; then
  log "X-Terminal app: $ACTIVE_XT_APP_DIR"
fi
log "Combined log: $LOG_FILE"
