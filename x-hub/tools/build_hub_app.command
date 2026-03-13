#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"   # repo root (x-hub-system/)
XHUB_DIR="$ROOT_DIR/x-hub"
PKG_DIR="$XHUB_DIR/macos/RELFlowHub"
TPL_DIR="$XHUB_DIR/macos/app_template"
OUT_DIR="$ROOT_DIR/build"
APP_DIR="$OUT_DIR/X-Hub.app"
BRIDGE_APP_DIR="$OUT_DIR/X-Hub Bridge.app"
DOCK_AGENT_APP_DIR="$OUT_DIR/X-Hub Dock Agent.app"

echo "[1/4] Building Swift package (release)…"
mkdir -p "$PKG_DIR/.sandbox_home" "$PKG_DIR/.sandbox_tmp" "$PKG_DIR/.scratch" "$PKG_DIR/.clang-module-cache" "$PKG_DIR/.swift-module-cache"

COMMON_ARGS=(
  -c release
  --disable-sandbox
  --scratch-path "$PKG_DIR/.scratch"
  -Xcc -fmodules-cache-path="$PKG_DIR/.clang-module-cache"
  -Xswiftc -module-cache-path -Xswiftc "$PKG_DIR/.swift-module-cache"
  --package-path "$PKG_DIR"
)

env HOME="$PKG_DIR/.sandbox_home" TMPDIR="$PKG_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}"

BIN_DIR=$(env HOME="$PKG_DIR/.sandbox_home" TMPDIR="$PKG_DIR/.sandbox_tmp" swift build "${COMMON_ARGS[@]}" --show-bin-path)
BIN_PATH="$BIN_DIR/RELFlowHub"
BRIDGE_BIN_PATH="$BIN_DIR/RELFlowHubBridge"
DOCK_AGENT_BIN_PATH="$BIN_DIR/RELFlowHubDockAgent"
if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
  echo "Build output not found at: $BIN_PATH" >&2
  exit 1
fi
if [ -z "$BRIDGE_BIN_PATH" ] || [ ! -f "$BRIDGE_BIN_PATH" ]; then
  echo "Build output not found at: $BRIDGE_BIN_PATH" >&2
  exit 1
fi
if [ -z "$DOCK_AGENT_BIN_PATH" ] || [ ! -f "$DOCK_AGENT_BIN_PATH" ]; then
  echo "Build output not found at: $DOCK_AGENT_BIN_PATH" >&2
  exit 1
fi

echo "[2/4] Creating .app bundles at: $APP_DIR and $BRIDGE_APP_DIR"
rm -rf "$APP_DIR"
rm -rf "$BRIDGE_APP_DIR"
rm -rf "$DOCK_AGENT_APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$BRIDGE_APP_DIR/Contents/MacOS" "$BRIDGE_APP_DIR/Contents/Resources"
mkdir -p "$DOCK_AGENT_APP_DIR/Contents/MacOS" "$DOCK_AGENT_APP_DIR/Contents/Resources"

cp -f "$BIN_PATH" "$APP_DIR/Contents/MacOS/RELFlowHub"
chmod +x "$APP_DIR/Contents/MacOS/RELFlowHub"

cp -f "$TPL_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

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
PROTO_SRC="$ROOT_DIR/protocol"
if [ -d "$GRPC_SRC" ]; then
  # Installing Node deps may require network access. Keep this step fail-soft by default so
  # offline builds can still produce the .app (the gRPC server just won't run until deps exist).
  XHUB_NPM_INSTALL="${XHUB_NPM_INSTALL:-auto}" # auto|never|always
  if [ ! -d "$GRPC_SRC/node_modules" ]; then
    if [ "$XHUB_NPM_INSTALL" = "never" ]; then
      echo "[GRPC] node_modules missing; skipping npm install (XHUB_NPM_INSTALL=never)." >&2
    elif command -v npm >/dev/null 2>&1; then
      echo "[GRPC] node_modules missing; running npm ci (XHUB_NPM_INSTALL=$XHUB_NPM_INSTALL)…"
      set +e
      (cd "$GRPC_SRC" && npm ci --omit=dev --no-audit --no-fund)
      NPM_RC=$?
      set -e
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
    --exclude '.DS_Store' \
    --exclude 'data' \
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
  NODE_OUT="$APP_DIR/Contents/MacOS/relflowhub_node"
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

# Build a downloadable "client kit" tarball for brand new Terminal devices.
# Served by the pairing HTTP server at:
#   http://<hub>:<pairing_port>/install/axhub_client_kit.tgz
#
# The kit is extracted by `axhubctl install-client` and should work on a fresh machine
# without cloning any repo. We also include a bundled Node runtime when available, so
# the client doesn't need to install Node separately.
if [ -d "$APP_DIR/Contents/Resources/hub_grpc_server" ] && [ -d "$APP_DIR/Contents/Resources/protocol" ]; then
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

  if [ -f "$APP_DIR/Contents/MacOS/relflowhub_node" ]; then
    mkdir -p "$KIT_STAGE/bin"
    cp -f "$APP_DIR/Contents/MacOS/relflowhub_node" "$KIT_STAGE/bin/relflowhub_node"
    chmod +x "$KIT_STAGE/bin/relflowhub_node"
  fi

  tar -czf "$KIT_TMP" -C "$KIT_STAGE" .
  mkdir -p "$(dirname "$KIT_OUT")"
  mv -f "$KIT_TMP" "$KIT_OUT"
  rm -rf "$KIT_STAGE" 2>/dev/null || true
fi

BR_TPL_DIR="$XHUB_DIR/macos/app_template_bridge"
cp -f "$BRIDGE_BIN_PATH" "$BRIDGE_APP_DIR/Contents/MacOS/RELFlowHubBridge"
chmod +x "$BRIDGE_APP_DIR/Contents/MacOS/RELFlowHubBridge"
cp -f "$BR_TPL_DIR/Info.plist" "$BRIDGE_APP_DIR/Contents/Info.plist"

echo "[2b/4] Creating Dock Agent app bundle at: $DOCK_AGENT_APP_DIR"
cp -f "$DOCK_AGENT_BIN_PATH" "$DOCK_AGENT_APP_DIR/Contents/MacOS/RELFlowHubDockAgent"
chmod +x "$DOCK_AGENT_APP_DIR/Contents/MacOS/RELFlowHubDockAgent"

DA_TPL_DIR="$XHUB_DIR/macos/app_template_dock_agent"
cp -f "$DA_TPL_DIR/Info.plist" "$DOCK_AGENT_APP_DIR/Contents/Info.plist"

# App icon (optional; prefer a repo-local PNG if present).
AX_ICON_PNG="$XHUB_DIR/macos/assets/AX FlowHub app_icon.png"
if [ -f "$AX_ICON_PNG" ]; then
  echo "[ICON] Generating AppIcon.icns from: $AX_ICON_PNG"
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

  set +e
  iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  ICON_RC=$?
  set -e
  rm -rf "$ICONSET" 2>/dev/null || true

  if [ "$ICON_RC" = "0" ]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
  else
    echo "[ICON] Warning: iconutil failed ($ICON_RC); keeping existing icon" >&2
  fi
elif [ -f "$ROOT_DIR/app_icon.icns" ]; then
  cp -f "$ROOT_DIR/app_icon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
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
if [ -f "$APP_DIR/Contents/MacOS/relflowhub_node" ]; then
  echo "[3a/4] Codesigning embedded node runtime…"
  codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/MacOS/relflowhub_node"
fi

# Sign the bundle in one shot, so the main executable keeps the entitlements.
codesign --force --sign "$IDENTITY" --entitlements "$ENT_TO_USE" "$APP_DIR"

echo "[3b/4] Codesigning Bridge with network client entitlement…"
BR_ENT="$BR_TPL_DIR/RELFlowHubBridge.entitlements"
BR_ENT_TO_USE="$BR_ENT"
BR_DEV_ENT="$OUT_DIR/RELFlowHubBridge.dev.entitlements"
if [ "$IDENTITY" = "-" ]; then
  cp -f "$BR_ENT" "$BR_DEV_ENT"
  /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$BR_DEV_ENT" 2>/dev/null || true
  BR_ENT_TO_USE="$BR_DEV_ENT"
fi
codesign --force --sign "$IDENTITY" --entitlements "$BR_ENT_TO_USE" "$BRIDGE_APP_DIR"

echo "[3c/4] Codesigning Dock Agent (no sandbox)…"
codesign --force --sign "$IDENTITY" "$DOCK_AGENT_APP_DIR"

echo "[4/4] Verifying signature…"
codesign --verify --deep --strict "$APP_DIR"
codesign --verify --deep --strict "$BRIDGE_APP_DIR"
codesign --verify --deep --strict "$DOCK_AGENT_APP_DIR"

echo
echo "Done. You can run:"
echo "  open \"$APP_DIR\""
echo "  open \"$BRIDGE_APP_DIR\""
echo "  open \"$DOCK_AGENT_APP_DIR\""
echo
echo "Notes:"
echo "- This build enables App Sandbox and grants network client entitlement (single-app Bridge mode)."
echo "- It also grants network server entitlement to accept local AF_UNIX IPC connections."
echo "- Calendar access still requires user permission; Info.plist includes NSCalendarsUsageDescription."
