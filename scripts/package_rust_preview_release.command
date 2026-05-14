#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${XHUB_RELEASE_VERSION:-v0.1.0-alpha.3-rust-preview}"
ARCH="${XHUB_RELEASE_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64) PLATFORM="macos-arm64" ;;
  x86_64) PLATFORM="macos-x86_64" ;;
  *) PLATFORM="macos-$ARCH" ;;
esac

OUT_DIR="${XHUB_RELEASE_DIR:-$ROOT_DIR/build/release/$VERSION}"
STAGE="$OUT_DIR/stage/XHub-System-Rust-$VERSION-$PLATFORM"
HUB_DIST_ROOT="$ROOT_DIR/rust/xhubd/dist"
XT_DIST_ROOT="$ROOT_DIR/build/release"
SYSTEM_ZIP="$OUT_DIR/XHub-System-Rust-$VERSION-$PLATFORM.zip"
SYSTEM_DMG="$OUT_DIR/XHub-System-Rust-$VERSION-$PLATFORM.dmg"
HUB_ZIP="$OUT_DIR/XHub-Rust-Hub-$VERSION-$PLATFORM.zip"
XT_ZIP="$OUT_DIR/X-Terminal-RustXT-$VERSION-$PLATFORM.zip"

echo "[release] Version: $VERSION"
echo "[release] Platform: $PLATFORM"
echo "[release] Output: $OUT_DIR"

mkdir -p "$OUT_DIR"

echo "[1/6] Packaging Rust Hub..."
bash "$ROOT_DIR/rust/xhubd/tools/package_rust_hub.command"
HUB_PACKAGE_DIR="$(find "$HUB_DIST_ROOT" -maxdepth 1 -type d -name 'rust-hub-*' | sort | tail -n 1)"
if [ -z "$HUB_PACKAGE_DIR" ] || [ ! -d "$HUB_PACKAGE_DIR" ]; then
  echo "Rust Hub package not found under: $HUB_DIST_ROOT" >&2
  exit 1
fi

echo "[2/6] Packaging X-Terminal + Rust sidecar..."
XTERMINAL_RUNTIME_DIST_ROOT="$XT_DIST_ROOT" bash "$ROOT_DIR/x-terminal/tools/package_xt_runtime.command"
XT_PACKAGE_DIR="$(find "$XT_DIST_ROOT" -maxdepth 1 -type d -name 'xt-runtime-*' | sort | tail -n 1)"
if [ -z "$XT_PACKAGE_DIR" ] || [ ! -d "$XT_PACKAGE_DIR" ]; then
  echo "XT runtime package not found under: $XT_DIST_ROOT" >&2
  exit 1
fi

echo "[3/6] Creating release archives..."
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$HUB_PACKAGE_DIR" "$STAGE/Rust-Hub"
ditto "$XT_PACKAGE_DIR" "$STAGE/X-Terminal-Runtime"
if [ -d "$XT_PACKAGE_DIR/app/X-Terminal.app" ]; then
  ditto "$XT_PACKAGE_DIR/app/X-Terminal.app" "$STAGE/X-Terminal.app"
fi

HUB_LAUNCHER_APP="$STAGE/X-Hub Rust.app"
mkdir -p "$HUB_LAUNCHER_APP/Contents/MacOS" "$HUB_LAUNCHER_APP/Contents/Resources"
ditto "$HUB_PACKAGE_DIR" "$HUB_LAUNCHER_APP/Contents/Resources/Rust-Hub"
cat > "$HUB_LAUNCHER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>xhub-rust-launcher</string>
  <key>CFBundleIdentifier</key>
  <string>com.ax.xhub.rust.preview</string>
  <key>CFBundleName</key>
  <string>X-Hub Rust</string>
  <key>CFBundleDisplayName</key>
  <string>X-Hub Rust</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
</dict>
</plist>
PLIST
cat > "$HUB_LAUNCHER_APP/Contents/MacOS/xhub-rust-launcher" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HUB_DIR="$APP_DIR/Resources/Rust-Hub"
LOG_DIR="$HOME/Library/Logs/XHubSystem"
LOG_FILE="$LOG_DIR/xhub-rust-launcher.log"
mkdir -p "$LOG_DIR"

if [ ! -x "$HUB_DIR/tools/xhubd_daemon.command" ]; then
  osascript -e 'display dialog "Rust Hub runtime was not found inside X-Hub Rust.app." buttons {"OK"} default button "OK"' >/dev/null 2>&1 || true
  exit 127
fi

{
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] starting Rust Hub from $HUB_DIR"
  bash "$HUB_DIR/tools/xhubd_daemon.command" start || true
  bash "$HUB_DIR/tools/xhubd_daemon.command" ready || true
} >>"$LOG_FILE" 2>&1

open "http://127.0.0.1:50151/" >/dev/null 2>&1 || true
LAUNCHER
chmod +x "$HUB_LAUNCHER_APP/Contents/MacOS/xhub-rust-launcher"
codesign --force --sign "${XHUB_RUST_LAUNCHER_CODESIGN_IDENTITY:--}" "$HUB_LAUNCHER_APP" >/dev/null 2>&1 || true

cat > "$STAGE/Open Rust Hub.command" <<'OPENHUB'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/Rust-Hub/tools/xhubd_daemon.command" start
bash "$SCRIPT_DIR/Rust-Hub/tools/xhubd_daemon.command" ready || true
open "http://127.0.0.1:50151/"
OPENHUB
chmod +x "$STAGE/Open Rust Hub.command"

cat > "$STAGE/Open X-Terminal.command" <<'OPENXT'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/X-Terminal.app" ]; then
  open "$SCRIPT_DIR/X-Terminal.app"
else
  open "$SCRIPT_DIR/X-Terminal-Runtime/app/X-Terminal.app"
fi
OPENXT
chmod +x "$STAGE/Open X-Terminal.command"

cat > "$STAGE/README.txt" <<EOF
XHub-System Rust Preview $VERSION

Contents:
- X-Hub Rust.app: double-click launcher for the Rust Hub daemon and browser status page
- X-Terminal.app: latest X-Terminal app built from the Rust preview source lane
- Rust-Hub/: packaged xhubd daemon, config, migrations, tools, skills, and docs
- X-Terminal-Runtime/: X-Terminal.app plus Rust xtd sidecar and run helper

Double-click:
  X-Hub Rust.app
  X-Terminal.app

Run Rust Hub foreground:
  bash Rust-Hub/tools/run_rust_hub.command serve

Run Rust Hub daemon helper:
  bash Rust-Hub/tools/xhubd_daemon.command start
  bash Rust-Hub/tools/xhubd_daemon.command ready

Run X-Terminal:
  bash X-Terminal-Runtime/RUN_XT.command

Important:
- This is the Rust preview distribution.
- Rust Hub is packaged as xhubd runtime/daemon, not as the legacy X-Hub.app GUI.
- Mark the GitHub Release as prerelease.
EOF

rm -f "$HUB_ZIP" "$XT_ZIP" "$SYSTEM_ZIP" "$SYSTEM_DMG"
ditto -c -k --keepParent "$HUB_PACKAGE_DIR" "$HUB_ZIP"
ditto -c -k --keepParent "$XT_PACKAGE_DIR" "$XT_ZIP"
ditto -c -k --keepParent "$STAGE" "$SYSTEM_ZIP"

echo "[4/6] Creating combined DMG..."
if command -v hdiutil >/dev/null 2>&1; then
  hdiutil create -volname "XHub Rust Preview" -srcfolder "$STAGE" -ov -format UDZO "$SYSTEM_DMG" >/dev/null
else
  echo "hdiutil not found; skipping DMG creation" >&2
fi

echo "[5/6] Writing SHA256SUMS.txt..."
(
  cd "$OUT_DIR"
  checksum_inputs=(./*.zip)
  if [ -f "$SYSTEM_DMG" ]; then
    checksum_inputs+=("$(basename "$SYSTEM_DMG")")
  fi
  shasum -a 256 "${checksum_inputs[@]}" > SHA256SUMS.txt
)

echo "[6/6] Done."
echo "Upload these files to the GitHub Release for $VERSION:"
echo "  $SYSTEM_ZIP"
if [ -f "$SYSTEM_DMG" ]; then
  echo "  $SYSTEM_DMG"
fi
echo "  $HUB_ZIP"
echo "  $XT_ZIP"
echo "  $OUT_DIR/SHA256SUMS.txt"
