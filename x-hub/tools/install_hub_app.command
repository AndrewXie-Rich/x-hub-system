#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_SRC="$SOURCE_ROOT/build/X-Hub.app"
APP_DEST="/Applications/X-Hub.app"
LEGACY_DEST="/Applications/RELFlowHub.app"

if [ ! -d "$APP_SRC" ]; then
  echo "[ERROR] Missing built app: $APP_SRC" >&2
  echo "Run: x-hub/tools/build_hub_app.command" >&2
  exit 1
fi

if [ "$(basename "$APP_DEST")" != "X-Hub.app" ]; then
  echo "[ERROR] Refusing to install Hub to a non-canonical app name: $APP_DEST" >&2
  exit 1
fi

stop_running_target_app() {
  local targets=(
    "$APP_DEST/Contents/MacOS/XHub"
    "$APP_DEST/Contents/MacOS/RELFlowHub"
    "$APP_DEST/Contents/Resources/relflowhub_node"
    "$APP_SRC/Contents/MacOS/XHub"
    "$APP_SRC/Contents/MacOS/RELFlowHub"
    "$APP_SRC/Contents/Resources/relflowhub_node"
  )

  local ps_output=""
  ps_output="$(ps ax -o pid=,command= 2>/dev/null || true)"
  [ -n "$ps_output" ] || return 0

  local pids=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    local pid="${line%% *}"
    local cmd="${line#* }"
    [ -n "$pid" ] || continue
    for target in "${targets[@]}"; do
      if [[ "$cmd" == *"$target"* ]]; then
        pids+=("$pid")
        break
      fi
    done
  done <<< "$ps_output"

  [ "${#pids[@]}" -gt 0 ] || return 0

  echo "[install] Stopping running X-Hub processes before replace: ${pids[*]}"
  kill "${pids[@]}" 2>/dev/null || true

  local deadline=$((SECONDS + 5))
  local survivors=()
  while [ "$SECONDS" -lt "$deadline" ]; do
    survivors=()
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        survivors+=("$pid")
      fi
    done
    [ "${#survivors[@]}" -eq 0 ] && return 0
    sleep 0.2
  done

  if [ "${#survivors[@]}" -gt 0 ]; then
    echo "[install] Force stopping lingering X-Hub processes: ${survivors[*]}"
    kill -9 "${survivors[@]}" 2>/dev/null || true
  fi
}

echo "[install] Installing X-Hub.app"
echo "[install] Source: $APP_SRC"
echo "[install] Target: $APP_DEST"
stop_running_target_app
if [ -e "$APP_DEST" ]; then
  echo "[install] Removing previous target bundle before copy"
  rm -rf "$APP_DEST"
fi
ditto --rsrc "$APP_SRC" "$APP_DEST"

if [ -e "$LEGACY_DEST" ]; then
  echo "[warn] Legacy app still exists and is not used by this installer: $LEGACY_DEST" >&2
  echo "[warn] Remove it separately if you no longer need the old bundle." >&2
fi

echo "[install] Done. You can run:"
echo "  open \"$APP_DEST\""
