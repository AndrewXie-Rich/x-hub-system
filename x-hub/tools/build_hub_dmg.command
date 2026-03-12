#!/bin/bash
set -euo pipefail

# Build a distributable DMG for the Hub app.
# Assumes the .app is already built at: build/X-Hub.app

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$ROOT_DIR/build/X-Hub.app"
BRIDGE_APP_PATH="$ROOT_DIR/build/RELFlowHubBridge.app"
DOCK_AGENT_APP_PATH="$ROOT_DIR/build/RELFlowHubDockAgent.app"
PLIST_SRC="$ROOT_DIR/x-hub/macos/app_template/Info.plist"

if [ ! -d "$APP_PATH" ]; then
  echo "Hub app not found: $APP_PATH" >&2
  echo "Run: x-hub/tools/build_hub_app.command" >&2
  exit 1
fi

VER=$(plutil -extract CFBundleShortVersionString raw "$PLIST_SRC" 2>/dev/null || echo "0.0")
VER=${VER:-0.0}

OUT_DMG="$ROOT_DIR/build/X-Hub v${VER}.dmg"
VOLNAME="X-Hub v${VER}"

STAGE="$ROOT_DIR/build/dmg_stage"
rm -rf "$STAGE" 2>/dev/null || true
mkdir -p "$STAGE"

echo "[DMG] Staging apps + docs..."
cp -R "$APP_PATH" "$STAGE/X-Hub.app"

if [ -d "$BRIDGE_APP_PATH" ]; then
  cp -R "$BRIDGE_APP_PATH" "$STAGE/X-Hub Bridge.app"
fi

if [ -d "$DOCK_AGENT_APP_PATH" ]; then
  cp -R "$DOCK_AGENT_APP_PATH" "$STAGE/X-Hub Dock Agent.app"
fi

cat > "$STAGE/README.txt" <<'TXT'
X-Hub (macOS)

Install:
1) Drag X-Hub.app to Applications
2) (Recommended) Drag X-Hub Dock Agent.app to Applications
3) (Optional) Drag X-Hub Bridge.app to Applications

First run / Permissions:
- Open X-Hub.app -> Settings -> Doctor
- Calendar: turn on Calendar integration and click Enable Calendar if needed
- Accessibility: click Request and enable X-Hub (and Dock Agent if you use it)

Optional:
- In Doctor, you can enable X-Hub Dock Agent "Start at login" for Slack/Messages counts.

Notes:
- Slack/Messages unread counts may require X-Hub Dock Agent on newer macOS versions.
- X-Hub Bridge enables optional networking features; the main Hub stays offline.
TXT

# Optional docs (user guide + security statement)
DOC_DIR="$ROOT_DIR/docs"
if [ -d "$DOC_DIR" ]; then
  if [ -f "$DOC_DIR/AX_RELFlowHub_User_Guide_v${VER}.txt" ]; then
    cp -f "$DOC_DIR/AX_RELFlowHub_User_Guide_v${VER}.txt" "$STAGE/"
  fi
fi

# Drag-to-install
ln -s "/Applications" "$STAGE/Applications"

echo "[DMG] Creating DMG: $OUT_DMG"
rm -f "$OUT_DMG" 2>/dev/null || true
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT_DMG" >/dev/null

echo "[DMG] Done: $OUT_DMG"
