#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # repo root (x-hub-system/)
# shellcheck source=../../scripts/lib/build_snapshot_retention.sh
source "$SOURCE_ROOT/scripts/lib/build_snapshot_retention.sh"
OUT_DIR="$SOURCE_ROOT/build"
BUILD_ROOT="$SOURCE_ROOT"
APP_DIR="$OUT_DIR/X-Hub.app"
LOG_DIR="$OUT_DIR/logs"
LOG_FILE="$LOG_DIR/build_hub_app.log"
LOG_PIPE="$LOG_DIR/build_hub_app.pipe"

USE_BUILD_SNAPSHOT="${XHUB_USE_BUILD_SNAPSHOT:-1}"
BUILD_SNAPSHOT_RETENTION_COUNT="${XHUB_BUILD_SNAPSHOT_RETENTION_COUNT:-2}"
RESET_BUILD_SNAPSHOT="${XHUB_RESET_BUILD_SNAPSHOT:-0}"
BUILD_HEARTBEAT_SECONDS="${XHUB_BUILD_HEARTBEAT_SECONDS:-15}"

run_with_heartbeat() {
  local label="${1:-[build]}"
  shift

  if ! [[ "$BUILD_HEARTBEAT_SECONDS" =~ ^[0-9]+$ ]] || [ "$BUILD_HEARTBEAT_SECONDS" -le 0 ]; then
    "$@"
    return
  fi

  local started_at=$SECONDS
  "$@" &
  local command_pid=$!

  while kill -0 "$command_pid" 2>/dev/null; do
    sleep "$BUILD_HEARTBEAT_SECONDS"
    kill -0 "$command_pid" 2>/dev/null || break
    echo "$label still running... $((SECONDS - started_at))s elapsed"
  done

  wait "$command_pid"
}

sync_snapshot_tree() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"
  rsync -a --delete \
    --exclude '.git' \
    --exclude '.DS_Store' \
    --exclude '.build' \
    --exclude '.scratch' \
    --exclude '.sandbox_home' \
    --exclude '.sandbox_tmp' \
    --exclude '.clang-module-cache' \
    --exclude '.swift-module-cache' \
    "$src" "$dest"
}

create_build_snapshot() {
  SNAPSHOT_DIR="${XHUB_BUILD_SNAPSHOT_DIR:-$OUT_DIR/.xhub-build-src}"
  xhub_prune_old_snapshot_dirs "$SNAPSHOT_DIR" "$BUILD_SNAPSHOT_RETENTION_COUNT"
  echo "[prep] Creating frozen source snapshot at: $SNAPSHOT_DIR"
  if [ "$RESET_BUILD_SNAPSHOT" = "1" ] && [ -d "$SNAPSHOT_DIR" ]; then
    echo "[prep] Resetting cached build snapshot"
  fi
  rm -rf "$SNAPSHOT_DIR"
  mkdir -p "$SNAPSHOT_DIR"
  sync_snapshot_tree "$SOURCE_ROOT/x-hub/" "$SNAPSHOT_DIR/x-hub/"
  if [ -d "$SOURCE_ROOT/protocol" ]; then
    sync_snapshot_tree "$SOURCE_ROOT/protocol/" "$SNAPSHOT_DIR/protocol/"
  fi
  BUILD_ROOT="$SNAPSHOT_DIR"
}

if [ "$USE_BUILD_SNAPSHOT" = "1" ]; then
  create_build_snapshot
fi

configure_build_paths() {
  XHUB_DIR="$BUILD_ROOT/x-hub"
  PKG_DIR="$XHUB_DIR/macos/RELFlowHub"
  TPL_DIR="$XHUB_DIR/macos/app_template"
}

prepare_swift_build_dirs() {
  mkdir -p \
    "$PKG_DIR/.sandbox_home" \
    "$PKG_DIR/.sandbox_tmp" \
    "$PKG_DIR/.scratch" \
    "$PKG_DIR/.clang-module-cache" \
    "$PKG_DIR/.swift-module-cache"
}

configure_swift_build_args() {
  COMMON_ARGS=(
    -c release
    --disable-sandbox
    --scratch-path "$PKG_DIR/.scratch"
    -Xcc -fmodules-cache-path="$PKG_DIR/.clang-module-cache"
    -Xswiftc -module-cache-path -Xswiftc "$PKG_DIR/.swift-module-cache"
    --package-path "$PKG_DIR"
  )

  MAIN_BUILD_ARGS=("${COMMON_ARGS[@]}" --product RELFlowHub)
}

is_retryable_swift_build_failure() {
  local attempt_log="$1"
  grep -Eiq \
    "unknown argument: '-isysroot'|accessing build database \".*\.scratch/build\.db\": disk I/O error|disk I/O error" \
    "$attempt_log"
}

reset_swift_build_state() {
  echo "[1a/4] Clearing Swift scratch + module caches before retry…"
  rm -rf \
    "$PKG_DIR/.scratch" \
    "$PKG_DIR/.clang-module-cache" \
    "$PKG_DIR/.swift-module-cache" \
    "$PKG_DIR/.sandbox_tmp"
  prepare_swift_build_dirs
}

run_swift_build_once() {
  local attempt_log="$1"
  : > "$attempt_log"

  run_with_heartbeat "[1/4] swift build" \
    env HOME="$PKG_DIR/.sandbox_home" TMPDIR="$PKG_DIR/.sandbox_tmp" \
    swift build "${MAIN_BUILD_ARGS[@]}" > >(tee "$attempt_log") 2>&1
}

build_swift_package() {
  local attempt_log=""
  attempt_log="$(mktemp -t xhub_swift_build)"

  if run_swift_build_once "$attempt_log"; then
    rm -f "$attempt_log"
    return 0
  fi

  if is_retryable_swift_build_failure "$attempt_log"; then
    echo "[1a/4] Detected a retryable Swift build failure (build DB / SDK arg issue). Retrying once with a clean local build state…"
    reset_swift_build_state
    if run_swift_build_once "$attempt_log"; then
      rm -f "$attempt_log"
      return 0
    fi
  fi

  if [ "$USE_BUILD_SNAPSHOT" = "1" ] && is_retryable_swift_build_failure "$attempt_log"; then
    echo "[1b/4] Snapshot build still failed. Falling back to source-tree build for this run…"
    BUILD_ROOT="$SOURCE_ROOT"
    configure_build_paths
    prepare_swift_build_dirs
    configure_swift_build_args
    if run_swift_build_once "$attempt_log"; then
      rm -f "$attempt_log"
      return 0
    fi
  fi

  rm -f "$attempt_log"
  return 1
}

configure_build_paths

mkdir -p "$LOG_DIR"
rm -f "$LOG_PIPE"
mkfifo "$LOG_PIPE"
tee "$LOG_FILE" < "$LOG_PIPE" &
TEE_PID=$!
exec > "$LOG_PIPE" 2>&1

pause_on_failure() {
  if [ "${XHUB_PAUSE_ON_FAILURE:-1}" != "1" ]; then
    return 0
  fi
  if [ -t 0 ]; then
    echo
    read -r -p "Build failed. Press Enter to close this window..." _
  fi
}

on_error() {
  local exit_code=$?
  local line_no="${BASH_LINENO[0]:-unknown}"
  echo
  echo "[ERROR] build_hub_app.command failed at line $line_no (exit $exit_code)."
  echo "[ERROR] Full log: $LOG_FILE"
  pause_on_failure
  exit "$exit_code"
}

cleanup_logging() {
  rm -f "$LOG_PIPE" 2>/dev/null || true
}

trap on_error ERR
trap cleanup_logging EXIT

echo "[LOG] Writing build log to: $LOG_FILE"

stop_replaced_app_processes() {
  local targets=(
    "$APP_DIR/Contents/MacOS/RELFlowHub"
    "$APP_DIR/Contents/MacOS/relflowhub_node"
    "$OUT_DIR/RELFlowHubBridge.app/Contents/MacOS/RELFlowHubBridge"
    "$OUT_DIR/RELFlowHubDockAgent.app/Contents/MacOS/RELFlowHubDockAgent"
    "$OUT_DIR/X-Hub Bridge.app/Contents/MacOS/X-Hub Bridge"
    "$OUT_DIR/X-Hub Dock Agent.app/Contents/MacOS/X-Hub Dock Agent"
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

  echo "[prep] Stopping running app processes that would be replaced: ${pids[*]}"
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
    echo "[prep] Force stopping lingering replaced processes: ${survivors[*]}"
    kill -9 "${survivors[@]}" 2>/dev/null || true
  fi
}

echo "[1/4] Building Swift package (release)…"
prepare_swift_build_dirs
configure_swift_build_args
build_swift_package

BIN_DIR=$(env HOME="$PKG_DIR/.sandbox_home" TMPDIR="$PKG_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}" --show-bin-path)
BIN_PATH="$BIN_DIR/RELFlowHub"
if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
  echo "Build output not found at: $BIN_PATH" >&2
  exit 1
fi

stop_replaced_app_processes

echo "[2/4] Creating app bundle at: $APP_DIR"
rm -rf "$APP_DIR"
for legacy_bundle in \
  "$OUT_DIR/RELFlowHubBridge.app" \
  "$OUT_DIR/RELFlowHubDockAgent.app" \
  "$OUT_DIR/X-Hub Bridge.app" \
  "$OUT_DIR/X-Hub Dock Agent.app"
do
  rm -rf "$legacy_bundle"
done
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp -f "$BIN_PATH" "$APP_DIR/Contents/MacOS/RELFlowHub"
chmod +x "$APP_DIR/Contents/MacOS/RELFlowHub"

cp -f "$TPL_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# SwiftPM materializes target resources as a sibling .bundle next to the built executable.
# Keep that bundle in Contents/Resources so packaged builds can load the processed resource tree.
if find "$BIN_DIR" -maxdepth 1 -name 'RELFlowHub_*.bundle' | grep -q .; then
  while IFS= read -r bundle_path; do
    rsync -a --delete "$bundle_path" "$APP_DIR/Contents/Resources/"
    bundle_name="$(basename "$bundle_path")"
    bundle_dest="$APP_DIR/Contents/Resources/$bundle_name"
    if [ -d "$bundle_dest" ] && [ ! -f "$bundle_dest/Contents/Info.plist" ] && [ ! -f "$bundle_dest/Info.plist" ]; then
      echo "[BUNDLE] Normalizing resource bundle layout for: $bundle_name"
      mkdir -p "$bundle_dest/Contents/Resources"
      find "$bundle_dest" -mindepth 1 -maxdepth 1 ! -name Contents -exec mv {} "$bundle_dest/Contents/Resources/" \;
      cat > "$bundle_dest/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleIdentifier</key>
  <string>com.rel.flowhub.resources.${bundle_name%.bundle}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${bundle_name%.bundle}</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
</dict>
</plist>
EOF
    fi
  done < <(find "$BIN_DIR" -maxdepth 1 -name 'RELFlowHub_*.bundle' | sort)
fi

APP_RESOURCE_BUNDLE="$(find "$APP_DIR/Contents/Resources" -maxdepth 1 -name 'RELFlowHub_*.bundle' | sort | head -n 1)"
APP_RESOURCE_ROOT=""
if [ -n "$APP_RESOURCE_BUNDLE" ]; then
  if [ -d "$APP_RESOURCE_BUNDLE/Contents/Resources" ]; then
    APP_RESOURCE_ROOT="$APP_RESOURCE_BUNDLE/Contents/Resources"
  else
    APP_RESOURCE_ROOT="$APP_RESOURCE_BUNDLE"
  fi
fi

LMSTUDIO_NODE_MODULES_SRC=""
for candidate in \
  "$HOME/.lmstudio/extensions/plugins/lmstudio/rag-v1/node_modules" \
  "$HOME/.lmstudio/extensions/plugins/lmstudio/js-code-sandbox/node_modules"
do
  if [ -d "$candidate/@lmstudio/sdk" ]; then
    LMSTUDIO_NODE_MODULES_SRC="$candidate"
    break
  fi
done

if [ -n "$APP_RESOURCE_ROOT" ] && [ -n "$LMSTUDIO_NODE_MODULES_SRC" ]; then
  echo "[LMSTUDIO] Bundling market SDK dependencies into app Resources…"
  mkdir -p "$APP_RESOURCE_ROOT/node_modules"
  rsync -a --delete \
    --exclude '.DS_Store' \
    "$LMSTUDIO_NODE_MODULES_SRC/" \
    "$APP_RESOURCE_ROOT/node_modules/"
elif [ -n "$APP_RESOURCE_ROOT" ]; then
  echo "[LMSTUDIO] Warning: LM Studio SDK node_modules not found; packaged market discovery will fall back to external paths." >&2
fi

# Bundle the full python_service runtime tree so DMG installs can start the
# canonical local runtime entrypoint and its provider registry without referencing the repo.
RUNTIME_SRC_DIR="$XHUB_DIR/python-runtime/python_service"
if [ -d "$RUNTIME_SRC_DIR" ]; then
  rsync -a --delete \
    --exclude '__pycache__' \
    --exclude '.pytest_cache' \
    "$RUNTIME_SRC_DIR/" \
    "$APP_DIR/Contents/Resources/python_service/"
fi

# Bundle the Node gRPC server + proto so LAN clients can connect without running `npm start`.
GRPC_SRC="$XHUB_DIR/grpc-server/hub_grpc_server"
PROTO_SRC="$BUILD_ROOT/protocol"
HUB_GRPC_RSYNC_EXCLUDES=(
  --exclude '.DS_Store'
  --exclude '.package-lock.json'
  --exclude 'README.md'
  --exclude 'data'
  --exclude 'package-lock.json'
  --exclude 'scripts'
  --exclude '*.spec.js'
  --exclude '*.test.js'
)
if [ -d "$GRPC_SRC" ]; then
  # Installing Node deps may require network access. Keep this step fail-soft by default so
  # offline builds can still produce the .app (the gRPC server just won't run until deps exist).
  XHUB_NPM_INSTALL="${XHUB_NPM_INSTALL:-auto}" # auto|never|always
  if [ ! -d "$GRPC_SRC/node_modules" ]; then
    if [ "$XHUB_NPM_INSTALL" = "never" ]; then
      echo "[GRPC] node_modules missing; skipping npm install (XHUB_NPM_INSTALL=never)." >&2
    elif command -v npm >/dev/null 2>&1; then
      echo "[GRPC] node_modules missing; running npm ci (XHUB_NPM_INSTALL=$XHUB_NPM_INSTALL)…"
      NPM_RC=0
      (cd "$GRPC_SRC" && npm ci --omit=dev --no-audit --no-fund) || NPM_RC=$?
      if [ "$NPM_RC" != "0" ]; then
        if [ "$XHUB_NPM_INSTALL" = "always" ]; then
          echo "[GRPC] npm ci failed (rc=$NPM_RC) and XHUB_NPM_INSTALL=always; aborting." >&2
          exit "$NPM_RC"
        fi
        echo "[GRPC] Warning: npm ci failed (rc=$NPM_RC). Continuing without node_modules." >&2
        echo "[GRPC] To fix: (cd \"$GRPC_SRC\" && npm ci --omit=dev)" >&2
      fi
    else
      echo "[GRPC] node_modules missing and npm not found; continuing (gRPC server won't run until deps are installed)." >&2
    fi
  fi
  echo "[GRPC] Bundling hub_grpc_server into app Resources…"
  rsync -a --delete \
    "${HUB_GRPC_RSYNC_EXCLUDES[@]}" \
    "$GRPC_SRC/" \
    "$APP_DIR/Contents/Resources/hub_grpc_server/"
fi
if [ -d "$PROTO_SRC" ]; then
  echo "[GRPC] Bundling protocol/ into app Resources…"
  rsync -a --delete \
    --exclude '.DS_Store' \
    "$PROTO_SRC/" \
    "$APP_DIR/Contents/Resources/protocol/"
fi

# Bundle a Node runtime so sandboxed Hub builds can start the gRPC server without relying on system Node.
find_node_bin() {
  local c=""
  c="$(command -v node 2>/dev/null || true)"
  if [ -n "$c" ] && [ -x "$c" ]; then
    echo "$c"
    return 0
  fi

  for c in "/opt/homebrew/bin/node" "/usr/local/bin/node" "/usr/bin/node" "$HOME/.volta/bin/node"; do
    if [ -n "$c" ] && [ -x "$c" ]; then
      echo "$c"
      return 0
    fi
  done

  # nvm installs are common but are not always on PATH in non-interactive scripts.
  local nvm_root="$HOME/.nvm/versions/node"
  if [ -d "$nvm_root" ]; then
    local best=""
    best="$(ls -1 "$nvm_root" 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$best" ] && [ -x "$nvm_root/$best/bin/node" ]; then
      echo "$nvm_root/$best/bin/node"
      return 0
    fi
  fi

  # asdf installs (real binaries live under installs/, shims may not work here).
  local asdf_root="$HOME/.asdf/installs/nodejs"
  if [ -d "$asdf_root" ]; then
    local best=""
    best="$(ls -1 "$asdf_root" 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$best" ] && [ -x "$asdf_root/$best/bin/node" ]; then
      echo "$asdf_root/$best/bin/node"
      return 0
    fi
  fi

  # fnm layout: ~/.fnm/node-versions/vX.Y.Z/installation/bin/node
  local fnm_root="$HOME/.fnm/node-versions"
  if [ -d "$fnm_root" ]; then
    local best=""
    best="$(find "$fnm_root" -maxdepth 3 -type f -path '*/installation/bin/node' 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$best" ] && [ -x "$best" ]; then
      echo "$best"
      return 0
    fi
  fi

  return 1
}

NODE_BIN="$(find_node_bin || true)"
if [ -n "$NODE_BIN" ] && [ -x "$NODE_BIN" ]; then
  echo "[GRPC] Bundling node binary from: $NODE_BIN"
  echo "[GRPC] Node version: $("$NODE_BIN" --version 2>/dev/null || echo 'unknown')"
  NODE_OUT="$APP_DIR/Contents/Resources/relflowhub_node"
  cp -f "$NODE_BIN" "$NODE_OUT"
  chmod +x "$NODE_OUT"

  # Reduce DMG size: if node is universal, thin it to the current arch and strip symbols.
  ARCH="$(uname -m)"
  if command -v lipo >/dev/null 2>&1; then
    ARCHS="$(lipo -archs "$NODE_OUT" 2>/dev/null || true)"
    if echo "$ARCHS" | grep -q " " && echo "$ARCHS" | grep -q "$ARCH"; then
      echo "[GRPC] Thinning node to arch: $ARCH"
      lipo -thin "$ARCH" "$NODE_OUT" -output "$NODE_OUT.thin"
      mv -f "$NODE_OUT.thin" "$NODE_OUT"
      chmod +x "$NODE_OUT"
    fi
  fi
  if command -v strip >/dev/null 2>&1; then
    strip -x "$NODE_OUT" 2>/dev/null || true
  fi
else
  echo "[GRPC] Note: node not found on this machine; Hub will require Node.js to run gRPC." >&2
fi

# Validate that the bundled gRPC client dependencies still contain their compiled entrypoints.
# A broad rsync exclude can otherwise strip nested dependency build/ trees and produce a broken client kit.
validate_grpc_bundle() {
  local grpc_root="$1"
  [ -d "$grpc_root" ] || return 0

  local missing=0
  local required_paths=(
    "$grpc_root/package.json"
    "$grpc_root/src/list_models_client.js"
    "$grpc_root/node_modules/@grpc/grpc-js/build/src/index.js"
    "$grpc_root/node_modules/@grpc/proto-loader/build/src/index.js"
  )

  for required in "${required_paths[@]}"; do
    if [ ! -f "$required" ]; then
      echo "[GRPC] Missing required bundled file: $required" >&2
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    echo "[GRPC] Refusing to build a broken Hub client kit. Check snapshot rsync excludes and reinstall grpc deps if needed." >&2
    exit 1
  fi
}

# Build a downloadable "client kit" tarball for brand new Terminal devices.
# Served by the pairing HTTP server at:
#   http://<hub>:<pairing_port>/install/axhub_client_kit.tgz
#
# The kit is extracted by `axhubctl install-client` and should work on a fresh machine
# without cloning any repo. We also include a bundled Node runtime when available, so
# the client doesn't need to install Node separately.
if [ -d "$APP_DIR/Contents/Resources/hub_grpc_server" ] && [ -d "$APP_DIR/Contents/Resources/protocol" ]; then
  validate_grpc_bundle "$APP_DIR/Contents/Resources/hub_grpc_server"
  echo "[GRPC] Building downloadable client kit (axhub_client_kit.tgz)…"
  KIT_TMP="$OUT_DIR/axhub_client_kit.tgz.tmp"
  KIT_STAGE="$OUT_DIR/axhub_client_kit.stage"
  KIT_OUT="$APP_DIR/Contents/Resources/hub_grpc_server/assets/axhub_client_kit.tgz"
  rm -rf "$KIT_STAGE" 2>/dev/null || true
  rm -f "$KIT_TMP" "$KIT_OUT" 2>/dev/null || true
  mkdir -p "$KIT_STAGE"

  rsync -a --delete \
    --exclude '.DS_Store' \
    --exclude '*/.DS_Store' \
    --exclude 'assets/axhub_client_kit.tgz' \
    --exclude 'assets/axhub_client_kit.tgz.sha256' \
    "$APP_DIR/Contents/Resources/hub_grpc_server/" \
    "$KIT_STAGE/hub_grpc_server/"

  rsync -a --delete \
    --exclude '.DS_Store' \
    --exclude '*/.DS_Store' \
    "$APP_DIR/Contents/Resources/protocol/" \
    "$KIT_STAGE/protocol/"

  if [ -f "$APP_DIR/Contents/Resources/relflowhub_node" ]; then
    mkdir -p "$KIT_STAGE/bin"
    cp -f "$APP_DIR/Contents/Resources/relflowhub_node" "$KIT_STAGE/bin/relflowhub_node"
    chmod +x "$KIT_STAGE/bin/relflowhub_node"
  fi

  tar -czf "$KIT_TMP" -C "$KIT_STAGE" .
  mkdir -p "$(dirname "$KIT_OUT")"
  mv -f "$KIT_TMP" "$KIT_OUT"
  rm -rf "$KIT_STAGE" 2>/dev/null || true
fi

# App icon (optional; prefer a repo-local PNG if present).
AX_ICON_PNG="$XHUB_DIR/macos/assets/AX FlowHub app_icon.png"
if [ -f "$AX_ICON_PNG" ]; then
  echo "[ICON] Generating AppIcon.icns from: $AX_ICON_PNG"
  ICON_RC=0
  ICON_TMP_ICNS="$OUT_DIR/ax_flowhub.generated.icns"
  rm -f "$ICON_TMP_ICNS" 2>/dev/null || true

  if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" >/dev/null 2>&1; then
    AX_ICON_SRC="$AX_ICON_PNG" AX_ICON_OUT="$ICON_TMP_ICNS" python3 - <<'PY' || ICON_RC=$?
from PIL import Image
import os

src = os.environ["AX_ICON_SRC"]
out = os.environ["AX_ICON_OUT"]
img = Image.open(src).convert("RGBA")
side = max(img.size)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
offset = ((side - img.size[0]) // 2, (side - img.size[1]) // 2)
canvas.paste(img, offset, img)
if canvas.size != (1024, 1024):
    canvas = canvas.resize((1024, 1024), Image.LANCZOS)
canvas.save(
    out,
    format="ICNS",
    sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)],
)
PY
  else
    ICONSET="$OUT_DIR/ax_flowhub.iconset"
    rm -rf "$ICONSET" 2>/dev/null || true
    mkdir -p "$ICONSET"

    sips -z 16 16     "$AX_ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32     "$AX_ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$AX_ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64     "$AX_ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$AX_ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256   "$AX_ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$AX_ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512   "$AX_ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$AX_ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$AX_ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$ICONSET" -o "$ICON_TMP_ICNS" || ICON_RC=$?
    rm -rf "$ICONSET" 2>/dev/null || true
  fi

  if [ "$ICON_RC" = "0" ] && [ -f "$ICON_TMP_ICNS" ]; then
    cp -f "$ICON_TMP_ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -f "$ICON_TMP_ICNS" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
  else
    echo "[ICON] Warning: iconutil failed ($ICON_RC); keeping existing icon" >&2
  fi
elif [ -f "$SOURCE_ROOT/app_icon.icns" ]; then
  cp -f "$SOURCE_ROOT/app_icon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
fi

echo "[3/4] Codesigning with sandbox entitlements (single-app Bridge mode)…"
ENT="$TPL_DIR/RELFlowHub.entitlements"
IDENTITY="${REL_FLOW_HUB_CODESIGN_IDENTITY:--}"
ENT_TO_USE="$ENT"
DEV_ENT="$OUT_DIR/RELFlowHub.dev.entitlements"
if [ "$IDENTITY" = "-" ]; then
  cp -f "$ENT" "$DEV_ENT"
  /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$DEV_ENT" 2>/dev/null || true
  ENT_TO_USE="$DEV_ENT"
fi

# Sign the embedded Node runtime (if bundled) before signing the app bundle.
if [ -f "$APP_DIR/Contents/Resources/relflowhub_node" ]; then
  echo "[3a/4] Codesigning embedded node runtime…"
  codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/Resources/relflowhub_node"
fi

# Sign the bundle in one shot, so the main executable keeps the entitlements.
codesign --force --sign "$IDENTITY" --entitlements "$ENT_TO_USE" "$APP_DIR"

echo "[4/4] Verifying signature…"
codesign --verify --verbose=4 "$APP_DIR"
if [ -f "$APP_DIR/Contents/Resources/relflowhub_node" ]; then
  codesign --verify --verbose=4 "$APP_DIR/Contents/Resources/relflowhub_node"
fi

echo
echo "Done. You can run:"
echo "  open \"$APP_DIR\""
echo
echo "Log:"
echo "  $LOG_FILE"
echo
echo "Notes:"
echo "- This build enables App Sandbox and grants network client entitlement (single-app Bridge mode)."
echo "- It also grants network server entitlement to accept local AF_UNIX IPC connections."
echo "- Calendar access was removed from X-Hub; device-local meeting reminders now belong on X-Terminal."
echo "- Standalone Bridge.app and Dock Agent.app were removed; X-Hub now ships as a single app bundle."
