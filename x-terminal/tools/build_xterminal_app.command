#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$XT_DIR/.." && pwd)"
ROOT_DIR="$XT_DIR"
# shellcheck source=../scripts/lib/canonical_root_guard.sh
source "$XT_DIR/scripts/lib/canonical_root_guard.sh"
xterminal_assert_canonical_root "$WORKSPACE_ROOT" "$XT_DIR"
# shellcheck source=../scripts/lib/release_codesign_guard.sh
source "$XT_DIR/scripts/lib/release_codesign_guard.sh"
# shellcheck source=../scripts/lib/build_snapshot_retention.sh
source "$XT_DIR/scripts/lib/build_snapshot_retention.sh"
OUT_DIR="${XTERMINAL_BUILD_OUT_DIR:-$WORKSPACE_ROOT/build}"
APP_DIR="$OUT_DIR/X-Terminal.app"
PROVENANCE_MANIFEST="$OUT_DIR/X-Terminal.provenance.json"
BUILD_CONFIG="${XTERMINAL_SWIFT_BUILD_CONFIG:-release}"
INSTALL_TARGET="${XTERMINAL_INSTALL_TARGET:-}"
INSTALL_TARGET_EXPANDED="${INSTALL_TARGET/#\~/$HOME}"
USE_BUILD_SNAPSHOT="${XTERMINAL_USE_BUILD_SNAPSHOT:-1}"
BUILD_SNAPSHOT_RETENTION_COUNT="${XTERMINAL_BUILD_SNAPSHOT_RETENTION_COUNT:-2}"
RELEASE_DISABLE_WMO="${XTERMINAL_RELEASE_DISABLE_WMO:-1}"
RESET_BUILD_SNAPSHOT="${XTERMINAL_RESET_BUILD_SNAPSHOT:-0}"
BUILD_HEARTBEAT_SECONDS="${XTERMINAL_BUILD_HEARTBEAT_SECONDS:-15}"
BUILD_SRC_DIR="$XT_DIR"
PROVENANCE_RELEASE_BUILD=0

case "${XTERMINAL_RELEASE_BUILD:-0}" in
  1|true|TRUE|yes|YES|on|ON) PROVENANCE_RELEASE_BUILD=1 ;;
  0|false|FALSE|no|NO|off|OFF|'') ;;
  *)
    echo "XTERMINAL_RELEASE_BUILD must be a boolean flag." >&2
    exit 64
    ;;
esac
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  case "$SOURCE_DATE_EPOCH" in
    *[!0-9]*|'')
      echo "SOURCE_DATE_EPOCH must be a non-negative integer." >&2
      exit 64
      ;;
  esac
  # SOURCE_DATE_EPOCH is supplied by the signed-tag release path. Treat it as
  # release intent even before all callers have adopted XTERMINAL_RELEASE_BUILD.
  PROVENANCE_RELEASE_BUILD=1
fi
if [ "$PROVENANCE_RELEASE_BUILD" = "1" ] && [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  echo "Release provenance requires SOURCE_DATE_EPOCH." >&2
  exit 64
fi
# Never leave a previous successful manifest looking current after a failed or
# partial build. The path is a single generated output, not source input.
rm -f "$PROVENANCE_MANIFEST"

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

if [ "$USE_BUILD_SNAPSHOT" = "1" ]; then
  SNAPSHOT_DIR="${XTERMINAL_BUILD_SNAPSHOT_DIR:-$OUT_DIR/.xterminal-build-src}"
  xhub_prune_old_snapshot_dirs "$SNAPSHOT_DIR" "$BUILD_SNAPSHOT_RETENTION_COUNT"
  echo "[prep] Syncing frozen source snapshot at: $SNAPSHOT_DIR"
  if [ "$RESET_BUILD_SNAPSHOT" = "1" ] && [ -d "$SNAPSHOT_DIR" ]; then
    echo "[prep] Resetting cached build snapshot"
    rm -rf "$SNAPSHOT_DIR"
  fi
  mkdir -p "$SNAPSHOT_DIR"
  rsync -a --delete \
    --exclude '.build' \
    --exclude '.swiftpm' \
    --exclude '.scratch' \
    --exclude '.scratch-*' \
    --exclude '.scratch-memory*' \
    --exclude '.scratch-registry' \
    --exclude '.axcoder' \
    --exclude '.tmp-home' \
    --exclude '.sandbox_home' \
    --exclude '.sandbox_tmp' \
    --exclude '.clang-module-cache' \
    --exclude '.swift-module-cache' \
    --exclude '.ax-test-cache' \
    --exclude '(A Document Being Saved By swift-build*' \
    --exclude '(A Document Being Saved By swift-test*' \
    --exclude '.DS_Store' \
    "$XT_DIR/" "$SNAPSHOT_DIR/"
  BUILD_SRC_DIR="$SNAPSHOT_DIR"
fi

echo "[1/4] Building Swift package ($BUILD_CONFIG)..."
mkdir -p "$BUILD_SRC_DIR/.sandbox_home" \
  "$BUILD_SRC_DIR/.sandbox_tmp" \
  "$BUILD_SRC_DIR/.scratch" \
  "$BUILD_SRC_DIR/.clang-module-cache" \
  "$BUILD_SRC_DIR/.swift-module-cache"

COMMON_ARGS=(
  -c "$BUILD_CONFIG"
  --disable-sandbox
  --scratch-path "$BUILD_SRC_DIR/.scratch"
  -Xcc -fmodules-cache-path="$BUILD_SRC_DIR/.clang-module-cache"
  -Xswiftc -module-cache-path -Xswiftc "$BUILD_SRC_DIR/.swift-module-cache"
  --package-path "$BUILD_SRC_DIR"
)

if [ "$BUILD_CONFIG" = "release" ] && [ "$RELEASE_DISABLE_WMO" = "1" ]; then
  echo "[1a/4] Release WMO disabled via XTERMINAL_RELEASE_DISABLE_WMO=1"
  COMMON_ARGS+=(-Xswiftc -no-whole-module-optimization)
fi

run_with_heartbeat "[1/4] swift build" \
  env HOME="$BUILD_SRC_DIR/.sandbox_home" TMPDIR="$BUILD_SRC_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}"
BIN_DIR="$(env HOME="$BUILD_SRC_DIR/.sandbox_home" TMPDIR="$BUILD_SRC_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}" --show-bin-path)"
BIN_PATH="$BIN_DIR/XTerminal"
if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
  echo "Build output not found at: $BIN_PATH" >&2
  exit 1
fi

echo "[2/4] Creating app bundle at: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp -f "$BIN_PATH" "$APP_DIR/Contents/MacOS/XTerminal"
chmod +x "$APP_DIR/Contents/MacOS/XTerminal"

cp -f "$BUILD_SRC_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

PLIST_BUDDY="/usr/libexec/PlistBuddy"
APP_VERSION="${XTERMINAL_APP_VERSION:-1.0}"
BUILD_VERSION="${XTERMINAL_BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"
BUNDLE_ID="${XTERMINAL_BUNDLE_ID:-com.xterminal.app}"

"$PLIST_BUDDY" -c "Set :CFBundleExecutable XTerminal" "$APP_DIR/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleName X-Terminal" "$APP_DIR/Contents/Info.plist"
"$PLIST_BUDDY" -c "Add :CFBundleDisplayName string X-Terminal" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
  "$PLIST_BUDDY" -c "Set :CFBundleDisplayName X-Terminal" "$APP_DIR/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_VERSION" "$APP_DIR/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :LSMinimumSystemVersion 13.0" "$APP_DIR/Contents/Info.plist"

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

  local nvm_root="$HOME/.nvm/versions/node"
  if [ -d "$nvm_root" ]; then
    local best=""
    best="$(ls -1 "$nvm_root" 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$best" ] && [ -x "$nvm_root/$best/bin/node" ]; then
      echo "$nvm_root/$best/bin/node"
      return 0
    fi
  fi

  local asdf_root="$HOME/.asdf/installs/nodejs"
  if [ -d "$asdf_root" ]; then
    local best=""
    best="$(ls -1 "$asdf_root" 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$best" ] && [ -x "$asdf_root/$best/bin/node" ]; then
      echo "$asdf_root/$best/bin/node"
      return 0
    fi
  fi

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
  echo "[2a/4] Bundling node runtime from: $NODE_BIN"
  cp -f "$NODE_BIN" "$APP_DIR/Contents/Resources/relflowhub_node"
  chmod +x "$APP_DIR/Contents/Resources/relflowhub_node"
else
  echo "[2a/4] Warning: node not found on this machine; bundled app will still rely on system/client-kit node." >&2
fi

AXHUBCTL_SRC=""
for candidate in \
  "$WORKSPACE_ROOT/assets/axhubctl" \
  "$XT_DIR/assets/axhubctl"; do
  if [ -f "$candidate" ]; then
    AXHUBCTL_SRC="$candidate"
    break
  fi
done

if [ -n "$AXHUBCTL_SRC" ]; then
  echo "[2b/4] Bundling axhubctl from: $AXHUBCTL_SRC"
  cp -f "$AXHUBCTL_SRC" "$APP_DIR/Contents/Resources/axhubctl"
  chmod +x "$APP_DIR/Contents/Resources/axhubctl"
else
  echo "[2b/4] Warning: axhubctl not found; remote Hub pairing/install-client will rely on PATH." >&2
fi

XTD_SRC=""
XTD_SOURCE_IS_CANONICAL=0
for candidate in \
  "$WORKSPACE_ROOT/rust/xtd/target/release/xtd" \
  "$WORKSPACE_ROOT/rust/xtd/target/debug/xtd" \
  "$WORKSPACE_ROOT/rust-xtd/target/release/xtd" \
  "$WORKSPACE_ROOT/rust-xtd/target/debug/xtd" \
  "$XT_DIR/../rust/xtd/target/release/xtd" \
  "$XT_DIR/../rust/xtd/target/debug/xtd" \
  "$XT_DIR/../rust-xtd/target/release/xtd" \
  "$XT_DIR/../rust-xtd/target/debug/xtd"; do
  if [ -f "$candidate" ]; then
    XTD_SRC="$candidate"
    case "$candidate" in
      "$WORKSPACE_ROOT/rust/xtd/target/release/xtd"|"$WORKSPACE_ROOT/rust/xtd/target/debug/xtd")
        XTD_SOURCE_IS_CANONICAL=1
        ;;
    esac
    break
  fi
done

if [ -n "$XTD_SRC" ]; then
  if [ "$PROVENANCE_RELEASE_BUILD" = "1" ] && \
     { [ "$XTD_SOURCE_IS_CANONICAL" != "1" ] || \
       [ "$XTD_SRC" != "$WORKSPACE_ROOT/rust/xtd/target/release/xtd" ]; }; then
    echo "[2c/4] Release build requires canonical release xtd: $WORKSPACE_ROOT/rust/xtd/target/release/xtd" >&2
    echo "[2c/4] Refusing xtd candidate: $XTD_SRC" >&2
    exit 1
  fi
  echo "[2c/4] Bundling xtd from: $XTD_SRC"
  cp -f "$XTD_SRC" "$APP_DIR/Contents/Resources/xtd"
  chmod +x "$APP_DIR/Contents/Resources/xtd"
else
  if [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
    echo "[2c/4] Release build requires canonical Rust xtd." >&2
    exit 1
  fi
  echo "[2c/4] Warning: xtd not found; XT core projection client will rely on XTERMINAL_XTD_PATH/PATH fallback." >&2
fi

IDENTITY="${XTERMINAL_CODESIGN_IDENTITY:--}"
ENABLE_APP_SANDBOX="${XTERMINAL_ENABLE_APP_SANDBOX:-0}"
ENT="$BUILD_SRC_DIR/X-Terminal.entitlements"

if [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
  xterminal_assert_release_codesign_identity "$IDENTITY"
fi

echo "[3/4] Codesigning app bundle..."
if [ -f "$APP_DIR/Contents/Resources/relflowhub_node" ]; then
  codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/Resources/relflowhub_node"
fi
if [ -f "$APP_DIR/Contents/Resources/axhubctl" ]; then
  codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/Resources/axhubctl"
fi
if [ -f "$APP_DIR/Contents/Resources/xtd" ]; then
  codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/Resources/xtd"
fi
if [ "$ENABLE_APP_SANDBOX" = "1" ]; then
  echo "[3a/4] App sandbox enabled via XTERMINAL_ENABLE_APP_SANDBOX=1"
  codesign --force --sign "$IDENTITY" --entitlements "$ENT" "$APP_DIR"
else
  echo "[3a/4] App sandbox disabled for direct-copy distribution"
  codesign --force --sign "$IDENTITY" "$APP_DIR"
fi

echo "[4/4] Verifying signature..."
codesign --verify --deep --strict "$APP_DIR"
if [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
  VERIFIED_TEAM_ID="$(
    xterminal_verify_pinned_codesign "$APP_DIR" "$WORKSPACE_ROOT" 1
  )"
  echo "[4/4] Verified release Team ID: $VERIFIED_TEAM_ID"
fi

EMBEDDED_XTD="$APP_DIR/Contents/Resources/xtd"
if [ -f "$EMBEDDED_XTD" ] && [ "$XTD_SOURCE_IS_CANONICAL" = "1" ] && \
   "$EMBEDDED_XTD" provenance help >/dev/null 2>&1; then
  echo "[4a/4] Creating detached XT provenance manifest..."
  PROVENANCE_CREATE_ARGS=(
    provenance create
    --manifest "$PROVENANCE_MANIFEST"
    --repository-root "$WORKSPACE_ROOT"
    --artifact-root "$OUT_DIR"
    --swift-path "X-Terminal.app/Contents/MacOS/XTerminal"
    --xtd-path "X-Terminal.app/Contents/Resources/xtd"
    --inventory-root "X-Terminal.app"
  )
  PROVENANCE_VERIFY_ARGS=(
    provenance verify
    --manifest "$PROVENANCE_MANIFEST"
    --artifact-root "$OUT_DIR"
    --repository-root "$WORKSPACE_ROOT"
  )
  if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    PROVENANCE_CREATE_ARGS+=(--source-date-epoch "$SOURCE_DATE_EPOCH")
  fi
  if [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
    PROVENANCE_CREATE_ARGS+=(--release)
    PROVENANCE_VERIFY_ARGS+=(--require-release)
  fi
  "$EMBEDDED_XTD" "${PROVENANCE_CREATE_ARGS[@]}" >/dev/null
  "$EMBEDDED_XTD" "${PROVENANCE_VERIFY_ARGS[@]}" >/dev/null
  echo "[4a/4] Provenance verified: $PROVENANCE_MANIFEST"
elif [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
  echo "[4a/4] Release build cannot create verified XT provenance with bundled xtd." >&2
  exit 1
else
  rm -f "$PROVENANCE_MANIFEST"
  echo "[4a/4] Warning: detached provenance unavailable; build through build_xt_with_rust_sidecar.command to enable it." >&2
fi

if [ -n "$INSTALL_TARGET_EXPANDED" ]; then
  INSTALL_PARENT="$(dirname "$INSTALL_TARGET_EXPANDED")"
  echo "[4b/4] Installing app to: $INSTALL_TARGET_EXPANDED"
  mkdir -p "$INSTALL_PARENT"
  if [ "$(basename "$INSTALL_TARGET_EXPANDED")" = "X-Terminal.app" ] && \
     [ -f "$PROVENANCE_MANIFEST" ]; then
    INSTALLED_PROVENANCE="$INSTALL_PARENT/X-Terminal.provenance.json"
    if [ -L "$INSTALL_TARGET_EXPANDED" ] || [ -L "$INSTALLED_PROVENANCE" ]; then
      echo "[4b/4] Refusing symlinked install target or provenance path." >&2
      exit 1
    fi
    if [ -e "$INSTALL_TARGET_EXPANDED" ] && [ ! -d "$INSTALL_TARGET_EXPANDED" ]; then
      echo "[4b/4] Install target exists and is not an app directory: $INSTALL_TARGET_EXPANDED" >&2
      exit 1
    fi
    if [ -e "$INSTALLED_PROVENANCE" ] && [ ! -f "$INSTALLED_PROVENANCE" ]; then
      echo "[4b/4] Installed provenance path exists and is not a regular file: $INSTALLED_PROVENANCE" >&2
      exit 1
    fi
    if [ -d "$INSTALL_TARGET_EXPANDED" ] && \
       [ -n "$(find "$INSTALL_TARGET_EXPANDED" -type l -print -quit 2>/dev/null)" ]; then
      echo "[4b/4] Refusing existing install target containing symlinks." >&2
      exit 1
    fi

    ditto "$APP_DIR" "$INSTALL_TARGET_EXPANDED"
    cp -f "$PROVENANCE_MANIFEST" "$INSTALLED_PROVENANCE"
    INSTALLED_VERIFY_ARGS=(
      provenance verify
      --manifest "$INSTALLED_PROVENANCE"
      --artifact-root "$INSTALL_PARENT"
      --repository-root "$WORKSPACE_ROOT"
    )
    if [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
      INSTALLED_VERIFY_ARGS+=(--require-release)
    fi
    "$INSTALL_TARGET_EXPANDED/Contents/Resources/xtd" \
      "${INSTALLED_VERIFY_ARGS[@]}" >/dev/null
    codesign --verify --deep --strict "$INSTALL_TARGET_EXPANDED"
    echo "[4b/4] Installed provenance verified: $INSTALLED_PROVENANCE"
  elif [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
    echo "[4b/4] Release install requires X-Terminal.app plus detached provenance." >&2
    exit 1
  else
    ditto "$APP_DIR" "$INSTALL_TARGET_EXPANDED"
    echo "[4b/4] Warning: non-canonical development install has no detached provenance." >&2
  fi
fi

echo
echo "Done."
echo "App bundle: $APP_DIR"
if [ -f "$PROVENANCE_MANIFEST" ]; then
  echo "Detached provenance: $PROVENANCE_MANIFEST"
fi
if [ -n "$INSTALL_TARGET_EXPANDED" ]; then
  echo "Installed app: $INSTALL_TARGET_EXPANDED"
  if [ -n "${INSTALLED_PROVENANCE:-}" ] && [ -f "$INSTALLED_PROVENANCE" ]; then
    echo "Installed provenance: $INSTALLED_PROVENANCE"
  fi
fi
if [ "$ENABLE_APP_SANDBOX" = "1" ]; then
  echo "Sandbox mode: enabled"
else
  echo "Sandbox mode: disabled"
fi
echo "Run hint: for end-user testing, launch the app from ~/Applications or /Applications instead of a repo checkout under Documents."
echo "Calendar note: X-Terminal now owns the optional Calendar permission and local Supervisor meeting reminders."
echo "Copy this app to another Mac, then open it directly."
echo "Self-contained XT workspace: $WORKSPACE_ROOT"
