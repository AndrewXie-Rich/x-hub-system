#!/bin/bash
set -euo pipefail

# Build macOS release assets for GitHub Releases.
# The generated DMGs are release artifacts and must not be committed to Git.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

VERSION="${XHUB_RELEASE_VERSION:-}"
if [ -z "$VERSION" ]; then
  if git -C "$ROOT_DIR" describe --tags --exact-match >/dev/null 2>&1; then
    VERSION="$(git -C "$ROOT_DIR" describe --tags --exact-match)"
  else
    VERSION="v0.1.0-alpha.1"
  fi
fi

ARCH="${XHUB_RELEASE_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64) PLATFORM="macos-arm64" ;;
  x86_64) PLATFORM="macos-x86_64" ;;
  *) PLATFORM="macos-$ARCH" ;;
esac

RELEASE_DIR="${XHUB_RELEASE_DIR:-$ROOT_DIR/build/release/$VERSION}"
HUB_APP="$ROOT_DIR/build/X-Hub.app"
XT_APP="$ROOT_DIR/build/X-Terminal.app"
HUB_DMG="$RELEASE_DIR/X-Hub-${VERSION}-${PLATFORM}.dmg"
XT_DMG="$RELEASE_DIR/X-Terminal-${VERSION}-${PLATFORM}.dmg"
SYSTEM_DMG="$RELEASE_DIR/XHub-System-${VERSION}-${PLATFORM}.dmg"
SYSTEM_STAGE="$ROOT_DIR/build/xhub_system_release_stage"

echo "[release] Version: $VERSION"
echo "[release] Platform: $PLATFORM"
echo "[release] Output: $RELEASE_DIR"

mkdir -p "$RELEASE_DIR"

echo "[1/6] Building X-Hub.app..."
"$ROOT_DIR/x-hub/tools/build_hub_app.command"

echo "[2/6] Building X-Terminal.app..."
bash "$ROOT_DIR/x-terminal/tools/build_xterminal_app.command"

echo "[3/6] Building X-Hub DMG..."
XHUB_DMG_OUTPUT="$HUB_DMG" \
XHUB_DMG_VERSION="${VERSION#v}" \
  "$ROOT_DIR/x-hub/tools/build_hub_dmg.command"

echo "[4/6] Building X-Terminal DMG..."
XTERMINAL_DMG_OUTPUT="$XT_DMG" \
XTERMINAL_DMG_VERSION="${VERSION#v}" \
  bash "$ROOT_DIR/x-terminal/tools/build_xterminal_dmg.command"

echo "[5/6] Building combined XHub-System DMG..."
if [ ! -d "$HUB_APP" ]; then
  echo "Hub app not found: $HUB_APP" >&2
  exit 1
fi
if [ ! -d "$XT_APP" ]; then
  echo "X-Terminal app not found: $XT_APP" >&2
  exit 1
fi

rm -rf "$SYSTEM_STAGE" 2>/dev/null || true
mkdir -p "$SYSTEM_STAGE"

cp -R "$HUB_APP" "$SYSTEM_STAGE/X-Hub.app"
cp -R "$XT_APP" "$SYSTEM_STAGE/X-Terminal.app"
ln -s "/Applications" "$SYSTEM_STAGE/Applications"

{
  echo "XHub-System $VERSION"
  echo
  echo "Install:"
  echo "1) Drag X-Hub.app and X-Terminal.app to Applications"
  echo "2) Launch X-Hub first"
  echo "3) Launch X-Terminal and pair it with X-Hub"
  echo
  echo "Release assets:"
  echo "- The combined DMG is the recommended download for normal users."
  echo "- The separate Hub and X-Terminal DMGs are for advanced users and partial updates."
  echo
  echo "Preview status:"
  echo "- This is a public tech preview unless the GitHub Release notes say otherwise."
  echo "- If the apps are not notarized, macOS may require an explicit user approval on first launch."
} > "$SYSTEM_STAGE/README.txt"

rm -f "$SYSTEM_DMG" 2>/dev/null || true
hdiutil create -volname "XHub-System $VERSION" -srcfolder "$SYSTEM_STAGE" -ov -format UDZO "$SYSTEM_DMG" >/dev/null

echo "[6/6] Writing SHA256SUMS.txt..."
(
  cd "$RELEASE_DIR"
  shasum -a 256 ./*.dmg > SHA256SUMS.txt
)

echo
echo "[release] Done."
echo "Upload these files to the GitHub Release for $VERSION:"
echo "  $SYSTEM_DMG"
echo "  $HUB_DMG"
echo "  $XT_DMG"
echo "  $RELEASE_DIR/SHA256SUMS.txt"
