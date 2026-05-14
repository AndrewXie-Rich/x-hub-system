#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${XHUB_RELEASE_VERSION:-v0.1.0-alpha.2-rust-preview}"
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

cat > "$STAGE/README.txt" <<EOF
XHub-System Rust Preview $VERSION

Contents:
- Rust-Hub/: packaged xhubd daemon, config, migrations, tools, skills, and docs
- X-Terminal-Runtime/: X-Terminal.app plus Rust xtd sidecar and run helper

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
