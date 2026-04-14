#!/bin/bash
set -euo pipefail

# Build a distributable DMG for the Hub app.
# Assumes the .app is already built at: build/X-Hub.app

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$ROOT_DIR/build/X-Hub.app"
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

{
  echo "X-Hub (macOS)"
  echo
  echo "Install:"
  echo "1) Drag X-Hub.app to Applications"
  echo
  echo "First run / Permissions:"
  echo "- Open X-Hub.app -> Settings -> Doctor"
  echo "- Accessibility: click Request and enable X-Hub if you use those integrations"
  echo
  echo "Notes:"
  echo "- Calendar reminders moved to X-Terminal Supervisor so Hub launch stays permission-free."
  echo "- This DMG contains the single X-Hub.app bundle only."
} > "$STAGE/README.txt"

# Optional docs (user guide + security statement)
DOC_DIR="$ROOT_DIR/docs"
if [ -d "$DOC_DIR" ]; then
  for doc in \
    "$DOC_DIR/AX_X-Hub_User_Guide_v${VER}.txt" \
    "$DOC_DIR/AX_RELFlowHub_User_Guide_v${VER}.txt"
  do
    if [ -f "$doc" ]; then
      cp -f "$doc" "$STAGE/"
      break
    fi
  done
fi

# Drag-to-install
ln -s "/Applications" "$STAGE/Applications"

echo "[DMG] Creating DMG: $OUT_DMG"
rm -f "$OUT_DMG" 2>/dev/null || true
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT_DMG" >/dev/null

echo "[DMG] Done: $OUT_DMG"
