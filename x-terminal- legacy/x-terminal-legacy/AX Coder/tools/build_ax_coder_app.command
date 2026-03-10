#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PKG_DIR="$ROOT_DIR/AX Coder/AXCoder"
TPL_DIR="$ROOT_DIR/AX Coder/app_template"
AXHUBCTL_SRC="$ROOT_DIR/../../x-hub/grpc-server/hub_grpc_server/assets/axhubctl"
OUT_DIR="$ROOT_DIR/build"
APP_DIR="$OUT_DIR/X-Terminal.app"
APP_DIR_LEGACY="$OUT_DIR/AXCoder.app"
NODE_HELPER_DST="$APP_DIR/Contents/Resources/relflowhub_node"

echo "[1/3] Building X-Terminal (release)…"

reset_build_caches() {
  rm -rf \
    "$PKG_DIR/.scratch" \
    "$PKG_DIR/.clang-module-cache" \
    "$PKG_DIR/.swift-module-cache" \
    "$PKG_DIR/.sandbox_tmp" \
    "$PKG_DIR/.sandbox_home/.cache"
  mkdir -p \
    "$PKG_DIR/.scratch" \
    "$PKG_DIR/.clang-module-cache" \
    "$PKG_DIR/.swift-module-cache" \
    "$PKG_DIR/.sandbox_tmp" \
    "$PKG_DIR/.sandbox_home"
}

mkdir -p "$PKG_DIR/.sandbox_home"
mkdir -p "$PKG_DIR/.sandbox_tmp" "$PKG_DIR/.scratch" "$PKG_DIR/.clang-module-cache" "$PKG_DIR/.swift-module-cache"

COMMON_ARGS=(
  -c release
  --disable-sandbox
  --scratch-path "$PKG_DIR/.scratch"
  -Xcc -fmodules-cache-path="$PKG_DIR/.clang-module-cache"
  -Xswiftc -module-cache-path -Xswiftc "$PKG_DIR/.swift-module-cache"
  --package-path "$PKG_DIR"
)

build_release() {
  env HOME="$PKG_DIR/.sandbox_home" TMPDIR="$PKG_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}"
}

if ! build_release; then
  echo "Build failed once. Retrying after clearing module caches…"
  reset_build_caches
  build_release
fi

BIN_DIR=$(env HOME="$PKG_DIR/.sandbox_home" TMPDIR="$PKG_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}" --show-bin-path)
BIN_PATH="$BIN_DIR/XTerminal"

if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
  echo "Build output not found at: $BIN_PATH" >&2
  exit 1
fi

echo "[2/3] Creating .app bundle at: $APP_DIR"
rm -rf "$APP_DIR"
rm -rf "$APP_DIR_LEGACY"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp -f "$BIN_PATH" "$APP_DIR/Contents/MacOS/XTerminal"
chmod +x "$APP_DIR/Contents/MacOS/XTerminal"
cp -f "$TPL_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$AXHUBCTL_SRC" ]; then
  cp -f "$AXHUBCTL_SRC" "$APP_DIR/Contents/Resources/axhubctl"
  chmod +x "$APP_DIR/Contents/Resources/axhubctl" 2>/dev/null || true
else
  echo "Warning: axhubctl not found at $AXHUBCTL_SRC" >&2
fi

NODE_HELPER_SRC=""
for CANDIDATE in \
  "$ROOT_DIR/../../build/X-Hub.app/Contents/MacOS/relflowhub_node" \
  "/Applications/X-Hub.app/Contents/MacOS/relflowhub_node" \
  "/Applications/RELFlowHub.app/Contents/MacOS/relflowhub_node"; do
  if [ -x "$CANDIDATE" ]; then
    NODE_HELPER_SRC="$CANDIDATE"
    break
  fi
done
if [ -z "$NODE_HELPER_SRC" ]; then
  if command -v node >/dev/null 2>&1; then
    NODE_HELPER_SRC="$(command -v node)"
  fi
fi

if [ -n "$NODE_HELPER_SRC" ] && [ -x "$NODE_HELPER_SRC" ]; then
  cp -f "$NODE_HELPER_SRC" "$NODE_HELPER_DST"
  chmod +x "$NODE_HELPER_DST" 2>/dev/null || true
else
  echo "Warning: no node helper found for bundling (tried X-Hub/RELFlowHub/system node)." >&2
fi

# Keep legacy app bundle name for old launch shortcuts.
cp -R "$APP_DIR" "$APP_DIR_LEGACY"
# Keep legacy binary path for old scripts that execute AXCoder.app/Contents/MacOS/AXCoder.
cp -f "$APP_DIR/Contents/MacOS/XTerminal" "$APP_DIR_LEGACY/Contents/MacOS/AXCoder"
chmod +x "$APP_DIR_LEGACY/Contents/MacOS/AXCoder"

echo "[3/3] Codesigning (ad-hoc, non-sandbox)…"
IDENTITY="${XTERMINAL_CODESIGN_IDENTITY:-${AX_CODER_CODESIGN_IDENTITY:--}}"
if [ -f "$NODE_HELPER_DST" ]; then
  codesign --force --sign "$IDENTITY" "$NODE_HELPER_DST" || true
fi
codesign --force --sign "$IDENTITY" "$APP_DIR"
codesign --force --sign "$IDENTITY" "$APP_DIR_LEGACY"
# Verifying can fail on unsigned local builds; keep it non-fatal.
codesign --verify --deep --strict "$APP_DIR" || true
codesign --verify --deep --strict "$APP_DIR_LEGACY" || true

echo
echo "Done. You can run:"
echo "  open \"$APP_DIR\""
