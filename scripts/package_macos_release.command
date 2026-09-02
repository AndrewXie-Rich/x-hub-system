#!/bin/bash
set -euo pipefail

# Build macOS release assets for GitHub Releases.
# The generated DMGs are release artifacts and must not be committed to Git.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
CHECK_CANONICAL_ROOTS=0
case "${1:-}" in
  "") ;;
  --check-canonical-roots)
    CHECK_CANONICAL_ROOTS=1
    shift
    ;;
  -h|--help)
    echo "Usage: $0 [--check-canonical-roots]"
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo "Usage: $0 [--check-canonical-roots]" >&2
    exit 64
    ;;
esac
if [ "$#" -ne 0 ]; then
  echo "Unexpected arguments: $*" >&2
  exit 64
fi

RUST_HUB_SOURCE_ROOT="${XHUB_RUST_HUB_SOURCE_ROOT:-$ROOT_DIR/rust/xhubd}"
XT_SOURCE_ROOT="${XTERMINAL_SOURCE_ROOT:-$ROOT_DIR/x-terminal}"

# Load the guard from the repository path, never from a caller-selected source.
# shellcheck source=../x-terminal/scripts/lib/canonical_root_guard.sh
source "$ROOT_DIR/x-terminal/scripts/lib/canonical_root_guard.sh"

release_flag_enabled() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

release_realpath_dir() {
  local path="${1:-}"
  [ -n "$path" ] && [ -d "$path" ] || return 1
  (cd "$path" && pwd -P)
}

assert_canonical_rust_release_root() {
  local candidate_real=""
  local canonical_real=""
  candidate_real="$(release_realpath_dir "$RUST_HUB_SOURCE_ROOT" 2>/dev/null || true)"
  canonical_real="$(release_realpath_dir "$ROOT_DIR/rust/xhubd" 2>/dev/null || true)"

  if [ -z "$candidate_real" ] || [ -z "$canonical_real" ] || [ "$candidate_real" != "$canonical_real" ]; then
    echo "[release] Refusing non-canonical Rust Hub source: $RUST_HUB_SOURCE_ROOT" >&2
    echo "[release] Canonical Rust Hub source: $ROOT_DIR/rust/xhubd" >&2
    exit 1
  fi
  if ! git -C "$ROOT_DIR" ls-files --error-unmatch \
    rust/xhubd/Cargo.toml \
    rust/xhubd/tools/package_rust_hub.command >/dev/null 2>&1; then
    echo "[release] Canonical Rust Hub markers are not tracked by this repository." >&2
    exit 1
  fi
}

assert_canonical_release_roots() {
  assert_canonical_rust_release_root
  xterminal_assert_canonical_root "$ROOT_DIR" "$XT_SOURCE_ROOT"

  if release_flag_enabled "${XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE:-0}"; then
    echo "[release] XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE is forbidden for release builds." >&2
    exit 1
  fi
  if [ -n "${XHUB_RUST_HUB_PACKAGE_DIR:-}" ]; then
    echo "[release] XHUB_RUST_HUB_PACKAGE_DIR is forbidden for release builds." >&2
    echo "[release] The release packages a fresh runtime from: $ROOT_DIR/rust/xhubd" >&2
    exit 1
  fi
}

assert_canonical_release_roots
if [ "$CHECK_CANONICAL_ROOTS" = "1" ]; then
  echo "[release] Canonical root preflight passed."
  echo "[release] Rust Hub: $ROOT_DIR/rust/xhubd"
  echo "[release] X-Terminal: $ROOT_DIR/x-terminal"
  exit 0
fi

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

APP_VERSION="${VERSION#v}"
BUILD_NUMBER="${XHUB_RELEASE_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
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

echo "[1/7] Packaging Rust Hub runtime from repository source..."
bash "$RUST_HUB_SOURCE_ROOT/tools/package_rust_hub.command"

echo "[2/7] Building X-Hub.app..."
XHUB_APP_VERSION="$APP_VERSION" \
XHUB_BUILD_VERSION="$BUILD_NUMBER" \
XHUB_RUST_HUB_SOURCE_ROOT="$RUST_HUB_SOURCE_ROOT" \
XHUB_RUST_HUB_PACKAGE_DIR= \
XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE=0 \
XHUB_RELEASE_BUILD=1 \
XHUB_EMBED_RUST_HUB=1 \
  "$ROOT_DIR/x-hub/tools/build_hub_app.command"

echo "[3/7] Building X-Terminal.app and Rust XT sidecar..."
XTERMINAL_APP_VERSION="$APP_VERSION" \
XTERMINAL_BUILD_VERSION="$BUILD_NUMBER" \
  bash "$XT_SOURCE_ROOT/tools/build_xt_with_rust_sidecar.command"

echo "[4/7] Building X-Hub DMG..."
XHUB_DMG_OUTPUT="$HUB_DMG" \
XHUB_DMG_VERSION="$APP_VERSION" \
  "$ROOT_DIR/x-hub/tools/build_hub_dmg.command"

echo "[5/7] Building X-Terminal DMG..."
XTERMINAL_DMG_OUTPUT="$XT_DMG" \
XTERMINAL_DMG_VERSION="$APP_VERSION" \
  bash "$XT_SOURCE_ROOT/tools/build_xterminal_dmg.command"

echo "[6/7] Building combined XHub-System DMG..."
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

echo "[7/7] Writing SHA256SUMS.txt..."
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
