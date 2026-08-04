#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$XT_DIR/.." && pwd)"
# shellcheck source=../scripts/lib/canonical_root_guard.sh
source "$XT_DIR/scripts/lib/canonical_root_guard.sh"
xterminal_assert_canonical_root "$ROOT_DIR" "$XT_DIR"
RUST_XTD_DIR="$ROOT_DIR/rust/xtd"
DIST_ROOT="${XTERMINAL_RUNTIME_DIST_ROOT:-$ROOT_DIR/build/release}"
BUILD_OUT_DIR="${XTERMINAL_BUILD_OUT_DIR:-$ROOT_DIR/build}"
BUILD_APP="$BUILD_OUT_DIR/X-Terminal.app"
BUILD_PROVENANCE="$BUILD_OUT_DIR/X-Terminal.provenance.json"
PROVENANCE_RELEASE_BUILD=0

release_stamp() {
  if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    date -u +%Y%m%dT%H%M%SZ
    return
  fi
  if date -u -r "$SOURCE_DATE_EPOCH" +%Y%m%dT%H%M%SZ 2>/dev/null; then
    return
  fi
  if date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%dT%H%M%SZ 2>/dev/null; then
    return
  fi
  echo "Unable to convert SOURCE_DATE_EPOCH with the installed date command." >&2
  return 1
}

case "${XTERMINAL_RELEASE_BUILD:-0}" in
  1|true|TRUE|yes|YES|on|ON) PROVENANCE_RELEASE_BUILD=1 ;;
  0|false|FALSE|no|NO|off|OFF|'') ;;
  *)
    echo "XTERMINAL_RELEASE_BUILD must be a boolean flag." >&2
    exit 64
    ;;
esac
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  case "$SOURCE_DATE_EPOCH" in
    *[!0-9]*|'')
      echo "SOURCE_DATE_EPOCH must be a non-negative integer." >&2
      exit 64
      ;;
  esac
  PROVENANCE_RELEASE_BUILD=1
fi
if [ "$PROVENANCE_RELEASE_BUILD" = "1" ] && [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  echo "Release packaging requires SOURCE_DATE_EPOCH." >&2
  exit 64
fi

STAMP="$(release_stamp)"
PACKAGE_NAME="${XTERMINAL_RUNTIME_PACKAGE_NAME:-xt-runtime-$STAMP}"
case "$PACKAGE_NAME" in
  ''|'.'|'..'|*/*|*[!A-Za-z0-9._-]*)
    echo "XTERMINAL_RUNTIME_PACKAGE_NAME must be a single safe path component." >&2
    exit 64
    ;;
esac
mkdir -p "$DIST_ROOT"
DIST_ROOT="$(cd "$DIST_ROOT" && pwd -P)"
PACKAGE_DIR="$DIST_ROOT/$PACKAGE_NAME"
ARCHIVE_PATH="$DIST_ROOT/$PACKAGE_NAME.zip"
PACKAGE_PROVENANCE="$PACKAGE_DIR/provenance.json"
ARCHIVE_VERIFY_ROOT=""

cleanup_archive_verification() {
  if [ -n "$ARCHIVE_VERIFY_ROOT" ] && [ -d "$ARCHIVE_VERIFY_ROOT" ]; then
    case "$ARCHIVE_VERIFY_ROOT" in
      "$DIST_ROOT"/.xt-runtime-verify.*) rm -rf -- "$ARCHIVE_VERIFY_ROOT" ;;
      *) echo "Refusing to clean unexpected archive verification path: $ARCHIVE_VERIFY_ROOT" >&2 ;;
    esac
  fi
}
trap cleanup_archive_verification EXIT

if [ -e "$PACKAGE_DIR" ] || [ -e "$ARCHIVE_PATH" ]; then
  echo "Refusing to overwrite an existing XT runtime package or archive." >&2
  echo "Package: $PACKAGE_DIR" >&2
  echo "Archive: $ARCHIVE_PATH" >&2
  exit 1
fi

bash "$XT_DIR/tools/build_xt_with_rust_sidecar.command"

if [ ! -x "$RUST_XTD_DIR/target/release/xtd" ]; then
  echo "missing canonical Rust sidecar: $RUST_XTD_DIR/target/release/xtd" >&2
  exit 1
fi
BUILD_VERIFY_ARGS=(
  provenance verify
  --manifest "$BUILD_PROVENANCE"
  --artifact-root "$BUILD_OUT_DIR"
  --repository-root "$ROOT_DIR"
)
if [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
  BUILD_VERIFY_ARGS+=(--require-release)
fi
"$RUST_XTD_DIR/target/release/xtd" "${BUILD_VERIFY_ARGS[@]}" >/dev/null

mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/app" "$PACKAGE_DIR/docs" "$PACKAGE_DIR/protocol" "$PACKAGE_DIR/assets"

if [ ! -d "$BUILD_APP" ]; then
  echo "missing app bundle: $BUILD_APP" >&2
  exit 1
fi
ditto "$BUILD_APP" "$PACKAGE_DIR/app/X-Terminal.app"

if [ ! -f "$RUST_XTD_DIR/target/release/xtd" ]; then
  echo "missing Rust sidecar: $RUST_XTD_DIR/target/release/xtd" >&2
  exit 1
fi
cp -f "$RUST_XTD_DIR/target/release/xtd" "$PACKAGE_DIR/bin/xtd"
chmod +x "$PACKAGE_DIR/bin/xtd"

if [ -f "$XT_DIR/assets/axhubctl" ]; then
  cp -f "$XT_DIR/assets/axhubctl" "$PACKAGE_DIR/assets/axhubctl"
  chmod +x "$PACKAGE_DIR/assets/axhubctl"
fi

if [ -f "$ROOT_DIR/protocol/hub_protocol_v1.proto" ]; then
  cp -f "$ROOT_DIR/protocol/hub_protocol_v1.proto" "$PACKAGE_DIR/protocol/hub_protocol_v1.proto"
elif [ -f "$XT_DIR/protocol/hub_protocol_v1.proto" ]; then
  cp -f "$XT_DIR/protocol/hub_protocol_v1.proto" "$PACKAGE_DIR/protocol/hub_protocol_v1.proto"
fi

if [ -f "$XT_DIR/README.md" ]; then
  cp -f "$XT_DIR/README.md" "$PACKAGE_DIR/README.md"
fi

cat > "$PACKAGE_DIR/RUN_XT.command" <<'RUNXT'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -x "$SCRIPT_DIR/bin/xtd" ] || [ ! -f "$SCRIPT_DIR/provenance.json" ]; then
  echo "XT runtime provenance verifier is missing; refusing to launch." >&2
  exit 1
fi
"$SCRIPT_DIR/bin/xtd" provenance verify \
  --manifest "$SCRIPT_DIR/provenance.json" \
  --artifact-root "$SCRIPT_DIR" >/dev/null
codesign --verify --deep --strict "$SCRIPT_DIR/app/X-Terminal.app"
open "$SCRIPT_DIR/app/X-Terminal.app"
RUNXT
chmod +x "$PACKAGE_DIR/RUN_XT.command"

PACKAGED_XTD="$PACKAGE_DIR/bin/xtd"
if ! "$PACKAGED_XTD" provenance help >/dev/null 2>&1; then
  echo "packaged xtd does not support provenance verification" >&2
  exit 1
fi
PROVENANCE_CREATE_ARGS=(
  provenance create
  --manifest "$PACKAGE_PROVENANCE"
  --repository-root "$ROOT_DIR"
  --artifact-root "$PACKAGE_DIR"
  --swift-path "app/X-Terminal.app/Contents/MacOS/XTerminal"
  --xtd-path "app/X-Terminal.app/Contents/Resources/xtd"
  --packaged-xtd-path "bin/xtd"
  --inventory-root "."
)
PROVENANCE_VERIFY_ARGS=(
  provenance verify
  --manifest "$PACKAGE_PROVENANCE"
  --artifact-root "$PACKAGE_DIR"
  --repository-root "$ROOT_DIR"
)
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  PROVENANCE_CREATE_ARGS+=(--source-date-epoch "$SOURCE_DATE_EPOCH")
fi
if [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
  PROVENANCE_CREATE_ARGS+=(--release)
  PROVENANCE_VERIFY_ARGS+=(--require-release)
fi
"$PACKAGED_XTD" "${PROVENANCE_CREATE_ARGS[@]}" >/dev/null
"$PACKAGED_XTD" "${PROVENANCE_VERIFY_ARGS[@]}" >/dev/null

(cd "$DIST_ROOT" && ditto -c -k --keepParent "$PACKAGE_NAME" "$ARCHIVE_PATH")
ARCHIVE_VERIFY_ROOT="$(mktemp -d "$DIST_ROOT/.xt-runtime-verify.XXXXXX")"
ditto -x -k "$ARCHIVE_PATH" "$ARCHIVE_VERIFY_ROOT"
EXTRACTED_PACKAGE="$ARCHIVE_VERIFY_ROOT/$PACKAGE_NAME"
EXTRACTED_VERIFY_ARGS=(
  provenance verify
  --manifest "$EXTRACTED_PACKAGE/provenance.json"
  --artifact-root "$EXTRACTED_PACKAGE"
  --repository-root "$ROOT_DIR"
)
if [ "$PROVENANCE_RELEASE_BUILD" = "1" ]; then
  EXTRACTED_VERIFY_ARGS+=(--require-release)
fi
"$EXTRACTED_PACKAGE/bin/xtd" "${EXTRACTED_VERIFY_ARGS[@]}" >/dev/null
codesign --verify --deep --strict "$EXTRACTED_PACKAGE/app/X-Terminal.app"
cleanup_archive_verification
ARCHIVE_VERIFY_ROOT=""

echo
echo "Package complete."
echo "Folder: $PACKAGE_DIR"
echo "Archive: $ARCHIVE_PATH"
echo "Verified provenance: $PACKAGE_PROVENANCE"
