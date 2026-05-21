#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_APP="${XHUB_REFRESH_APP_PATH:-$SOURCE_ROOT/build/X-Hub.app}"
APP_DEST="/Applications/X-Hub.app"
CANONICAL_RUST_SOURCE_ROOT="$SOURCE_ROOT/rust/xhubd"
INSTALL_AFTER_REFRESH="${XHUB_INSTALL_AFTER_RESOURCE_REFRESH:-1}"
REFRESH_PYTHON_SERVICE=1
RUST_PACKAGE_DIR="${XHUB_RUST_HUB_PACKAGE_DIR:-}"

usage() {
  cat <<'EOF'
Usage: refresh_hub_runtime_resources.command [options]

Refresh runtime resources in build/X-Hub.app without rebuilding Swift.

Options:
  --app <path>                 App bundle to refresh, default build/X-Hub.app
  --rust-hub-package <path>    Also replace Contents/Resources/rust-hub
  --no-python-service          Do not refresh python_service
  --install                    Install refreshed app to /Applications/X-Hub.app (default)
  --no-install                 Only refresh and sign the build app
  -h, --help                   Show this help

Safety:
  External Rust Hub packages are refused unless XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE=1.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      [ "$#" -ge 2 ] || { echo "[ERROR] --app requires a path" >&2; exit 2; }
      BUILD_APP="$2"
      shift 2
      ;;
    --rust-hub-package)
      [ "$#" -ge 2 ] || { echo "[ERROR] --rust-hub-package requires a path" >&2; exit 2; }
      RUST_PACKAGE_DIR="$2"
      shift 2
      ;;
    --no-python-service)
      REFRESH_PYTHON_SERVICE=0
      shift
      ;;
    --install)
      INSTALL_AFTER_REFRESH=1
      shift
      ;;
    --no-install)
      INSTALL_AFTER_REFRESH=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

is_enabled() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

path_realpath_dir() {
  local path="$1"
  if [ -z "$path" ] || [ ! -d "$path" ]; then
    return 1
  fi
  (cd "$path" && pwd -P)
}

external_rust_package_allowed() {
  is_enabled "${XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE:-0}"
}

validate_app_bundle() {
  if [ ! -d "$BUILD_APP" ] || [ ! -f "$BUILD_APP/Contents/MacOS/XHub" ]; then
    echo "[ERROR] Missing built X-Hub.app: $BUILD_APP" >&2
    echo "Run: $SCRIPT_DIR/build_hub_app.command" >&2
    exit 1
  fi
}

validate_rust_package_dir() {
  local package_dir="$1"
  local package_real=""
  local canonical_real=""
  [ -n "$package_dir" ] || return 0
  if [ ! -d "$package_dir" ] || [ ! -x "$package_dir/bin/xhubd" ] || [ ! -f "$package_dir/tools/run_rust_hub.command" ]; then
    echo "[ERROR] Invalid Rust Hub package: $package_dir" >&2
    echo "[ERROR] Expected bin/xhubd and tools/run_rust_hub.command." >&2
    exit 1
  fi

  package_real="$(path_realpath_dir "$package_dir" 2>/dev/null || true)"
  canonical_real="$(path_realpath_dir "$CANONICAL_RUST_SOURCE_ROOT" 2>/dev/null || true)"
  if [ -n "$package_real" ] && [ -n "$canonical_real" ]; then
    case "$package_real/" in
      "$canonical_real"/dist/rust-hub-*) ;;
      *)
        if ! external_rust_package_allowed; then
          echo "[ERROR] Refusing external Rust Hub package: $package_dir" >&2
          echo "[ERROR] Unified Hub builds must embed packages from: $CANONICAL_RUST_SOURCE_ROOT/dist" >&2
          echo "[ERROR] Set XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE=1 only for a deliberate one-off diagnostic build." >&2
          exit 1
        fi
        echo "[warn] Using external Rust Hub package by explicit opt-in: $package_dir" >&2
        ;;
    esac
  fi

  local help_text=""
  help_text="$("$package_dir/bin/xhubd" --help 2>&1 || true)"
  case "$help_text" in
    *"model <inventory|capabilities"*) ;;
    *)
      echo "[ERROR] Refusing stale Rust Hub package without model capabilities support: $package_dir" >&2
      echo "[ERROR] Repackage with: $CANONICAL_RUST_SOURCE_ROOT/tools/package_rust_hub.command" >&2
      exit 1
      ;;
  esac
}

refresh_python_service() {
  local src="$SOURCE_ROOT/x-hub/python-runtime/python_service"
  local dst="$BUILD_APP/Contents/Resources/python_service"
  if [ ! -d "$src" ]; then
    echo "[ERROR] Missing python_service source: $src" >&2
    exit 1
  fi
  echo "[refresh] Syncing python_service"
  mkdir -p "$dst"
  rsync -a --delete \
    --exclude '__pycache__' \
    --exclude '.pytest_cache' \
    "$src/" \
    "$dst/"
}

refresh_rust_hub_package() {
  local package_dir="$1"
  local dst="$BUILD_APP/Contents/Resources/rust-hub"
  validate_rust_package_dir "$package_dir"
  echo "[refresh] Syncing Rust Hub package"
  echo "[refresh] Source: $package_dir"
  echo "[refresh] Target: $dst"
  rm -rf "$dst"
  mkdir -p "$dst"
  rsync -a --delete \
    --exclude '.DS_Store' \
    "$package_dir/" \
    "$dst/"
  cat > "$dst/embedded_manifest.json" <<EOF
{
  "schema_version": "xhub.embedded_rust_hub.v1",
  "source_package_dir": "$package_dir",
  "embedded_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

codesign_app() {
  local identity="${REL_FLOW_HUB_CODESIGN_IDENTITY:--}"
  local ent="$SOURCE_ROOT/x-hub/macos/app_template/RELFlowHub.entitlements"
  local ent_to_use="$ent"
  local dev_ent="$SOURCE_ROOT/build/RELFlowHub.dev.entitlements"

  if [ ! -f "$ent" ]; then
    echo "[ERROR] Missing entitlements: $ent" >&2
    exit 1
  fi

  if [ "$identity" = "-" ]; then
    cp -f "$ent" "$dev_ent"
    /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$dev_ent" 2>/dev/null || true
    ent_to_use="$dev_ent"
  fi

  if [ -f "$BUILD_APP/Contents/Resources/relflowhub_node" ]; then
    echo "[sign] Signing embedded node runtime"
    codesign --force --sign "$identity" "$BUILD_APP/Contents/Resources/relflowhub_node"
  fi
  if [ -f "$BUILD_APP/Contents/Resources/rust-hub/bin/xhubd" ]; then
    echo "[sign] Signing embedded Rust Hub daemon"
    codesign --force --sign "$identity" "$BUILD_APP/Contents/Resources/rust-hub/bin/xhubd"
  fi
  echo "[sign] Signing X-Hub.app"
  codesign --force --sign "$identity" --entitlements "$ent_to_use" "$BUILD_APP"
  codesign --verify --deep --strict "$BUILD_APP"
}

validate_app_bundle

if is_enabled "$REFRESH_PYTHON_SERVICE"; then
  refresh_python_service
fi

if [ -n "$RUST_PACKAGE_DIR" ]; then
  refresh_rust_hub_package "$RUST_PACKAGE_DIR"
fi

codesign_app

if is_enabled "$INSTALL_AFTER_REFRESH"; then
  echo "[install] Installing refreshed app to $APP_DEST"
  "$SCRIPT_DIR/install_hub_app.command"
else
  echo "[done] Refreshed and signed: $BUILD_APP"
fi
