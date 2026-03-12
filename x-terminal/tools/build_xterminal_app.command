#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
XT_DIR="$ROOT_DIR/x-terminal"
OUT_DIR="$ROOT_DIR/build"
APP_DIR="$OUT_DIR/X-Terminal.app"

echo "[1/4] Building Swift package (release)..."
mkdir -p "$XT_DIR/.sandbox_home" "$XT_DIR/.sandbox_tmp" "$XT_DIR/.scratch" "$XT_DIR/.clang-module-cache" "$XT_DIR/.swift-module-cache"

COMMON_ARGS=(
  -c release
  --disable-sandbox
  --scratch-path "$XT_DIR/.scratch"
  -Xcc -fmodules-cache-path="$XT_DIR/.clang-module-cache"
  -Xswiftc -module-cache-path -Xswiftc "$XT_DIR/.swift-module-cache"
  --package-path "$XT_DIR"
)

env HOME="$XT_DIR/.sandbox_home" TMPDIR="$XT_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}"
BIN_DIR="$(env HOME="$XT_DIR/.sandbox_home" TMPDIR="$XT_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}" --show-bin-path)"
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

cp -f "$XT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

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
  "$ROOT_DIR/x-hub/grpc-server/hub_grpc_server/assets/axhubctl" \
  "$HOME/Documents/AX/x-hub-system/x-hub/grpc-server/hub_grpc_server/assets/axhubctl"; do
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

IDENTITY="${XTERMINAL_CODESIGN_IDENTITY:--}"
ENABLE_APP_SANDBOX="${XTERMINAL_ENABLE_APP_SANDBOX:-0}"
ENT="$XT_DIR/X-Terminal.entitlements"

echo "[3/4] Codesigning app bundle..."
if [ -f "$APP_DIR/Contents/Resources/relflowhub_node" ]; then
  codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/Resources/relflowhub_node"
fi
if [ -f "$APP_DIR/Contents/Resources/axhubctl" ]; then
  codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/Resources/axhubctl"
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

echo
echo "Done."
echo "App bundle: $APP_DIR"
if [ "$ENABLE_APP_SANDBOX" = "1" ]; then
  echo "Sandbox mode: enabled"
else
  echo "Sandbox mode: disabled"
fi
echo "Copy this app to another Mac, then open it directly."
