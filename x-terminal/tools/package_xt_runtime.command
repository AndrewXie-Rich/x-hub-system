#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$XT_DIR/.." && pwd)"
RUST_XTD_DIR="$ROOT_DIR/rust/xtd"
DIST_ROOT="${XTERMINAL_RUNTIME_DIST_ROOT:-$ROOT_DIR/build/release}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PACKAGE_NAME="${XTERMINAL_RUNTIME_PACKAGE_NAME:-xt-runtime-$STAMP}"
PACKAGE_DIR="$DIST_ROOT/$PACKAGE_NAME"
ARCHIVE_PATH="$DIST_ROOT/$PACKAGE_NAME.zip"

bash "$XT_DIR/tools/build_xt_with_rust_sidecar.command"

rm -rf "$PACKAGE_DIR" "$ARCHIVE_PATH"
mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/app" "$PACKAGE_DIR/docs" "$PACKAGE_DIR/protocol" "$PACKAGE_DIR/assets"

if [ ! -d "$ROOT_DIR/build/X-Terminal.app" ]; then
  echo "missing app bundle: $ROOT_DIR/build/X-Terminal.app" >&2
  exit 1
fi
ditto "$ROOT_DIR/build/X-Terminal.app" "$PACKAGE_DIR/app/X-Terminal.app"

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
open "$SCRIPT_DIR/app/X-Terminal.app"
RUNXT
chmod +x "$PACKAGE_DIR/RUN_XT.command"

mkdir -p "$DIST_ROOT"
(cd "$DIST_ROOT" && ditto -c -k --keepParent "$PACKAGE_NAME" "$ARCHIVE_PATH")

echo
echo "Package complete."
echo "Folder: $PACKAGE_DIR"
echo "Archive: $ARCHIVE_PATH"
