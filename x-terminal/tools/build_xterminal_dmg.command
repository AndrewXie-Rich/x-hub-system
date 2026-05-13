#!/bin/bash
set -euo pipefail

# Build a distributable DMG for the X-Terminal app.
# Assumes the .app is already built at: build/X-Terminal.app

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$ROOT_DIR/build/X-Terminal.app"
APP_PLIST="$APP_PATH/Contents/Info.plist"
SRC_PLIST="$ROOT_DIR/x-terminal/Info.plist"

if [ ! -d "$APP_PATH" ]; then
  echo "X-Terminal app not found: $APP_PATH" >&2
  echo "Run: bash x-terminal/tools/build_xterminal_app.command" >&2
  exit 1
fi

VER="${XTERMINAL_DMG_VERSION:-}"
if [ -z "$VER" ] && [ -f "$APP_PLIST" ]; then
  VER="$(plutil -extract CFBundleShortVersionString raw "$APP_PLIST" 2>/dev/null || true)"
fi
if [ -z "$VER" ] && [ -f "$SRC_PLIST" ]; then
  VER="$(plutil -extract CFBundleShortVersionString raw "$SRC_PLIST" 2>/dev/null || true)"
fi
VER="${VER:-0.0}"

OUT_DMG="${XTERMINAL_DMG_OUTPUT:-$ROOT_DIR/build/X-Terminal v${VER}.dmg}"
VOLNAME="${XTERMINAL_DMG_VOLUME_NAME:-X-Terminal v${VER}}"

STAGE="$ROOT_DIR/build/xterminal_dmg_stage"
rm -rf "$STAGE" 2>/dev/null || true
mkdir -p "$STAGE"

echo "[DMG] Staging app + install note..."
cp -R "$APP_PATH" "$STAGE/X-Terminal.app"

{
  echo "X-Terminal (macOS)"
  echo
  echo "Install:"
  echo "1) Drag X-Terminal.app to Applications"
  echo
  echo "First run:"
  echo "- Launch X-Hub first, then launch X-Terminal"
  echo "- Pair X-Terminal with X-Hub before relying on governed routes"
  echo
  echo "Notes:"
  echo "- X-Terminal is the paired deep client for X-Hub-System."
  echo "- It does not replace Hub-side grants, routing, memory truth, or policy."
  echo "- This DMG contains the single X-Terminal.app bundle only."
} > "$STAGE/README.txt"

ln -s "/Applications" "$STAGE/Applications"

echo "[DMG] Creating DMG: $OUT_DMG"
rm -f "$OUT_DMG" 2>/dev/null || true
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT_DMG" >/dev/null

echo "[DMG] Done: $OUT_DMG"
