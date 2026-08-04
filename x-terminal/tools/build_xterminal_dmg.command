#!/bin/bash
set -euo pipefail

# Build a distributable DMG for the X-Terminal app.
# Assumes the .app is already built at: build/X-Terminal.app

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
XT_DIR="$ROOT_DIR/x-terminal"
# shellcheck source=../scripts/lib/canonical_root_guard.sh
source "$XT_DIR/scripts/lib/canonical_root_guard.sh"
xterminal_assert_canonical_root "$ROOT_DIR" "$XT_DIR"
# shellcheck source=../scripts/lib/release_codesign_guard.sh
source "$XT_DIR/scripts/lib/release_codesign_guard.sh"
APP_PATH="$ROOT_DIR/build/X-Terminal.app"
PROVENANCE_PATH="$ROOT_DIR/build/X-Terminal.provenance.json"
APP_PLIST="$APP_PATH/Contents/Info.plist"
SRC_PLIST="$XT_DIR/Info.plist"
RELEASE_BUILD=0
IDENTITY="${XTERMINAL_CODESIGN_IDENTITY:--}"
MOUNT_POINT=""
MOUNT_ATTACHED=0
MOUNT_POINT_OWNED=0

case "${XTERMINAL_RELEASE_BUILD:-0}" in
  1|true|TRUE|yes|YES|on|ON) RELEASE_BUILD=1 ;;
  0|false|FALSE|no|NO|off|OFF|'') ;;
  *)
    echo "XTERMINAL_RELEASE_BUILD must be a boolean flag." >&2
    exit 64
    ;;
esac
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  case "$SOURCE_DATE_EPOCH" in
    ''|*[!0-9]*)
      echo "SOURCE_DATE_EPOCH must be a non-negative integer." >&2
      exit 64
      ;;
  esac
  RELEASE_BUILD=1
fi
if [ "$RELEASE_BUILD" = "1" ]; then
  [ -n "${SOURCE_DATE_EPOCH:-}" ] || {
    echo "Release DMG requires SOURCE_DATE_EPOCH." >&2
    exit 64
  }
  xterminal_assert_release_codesign_identity "$IDENTITY"
fi

detach_mount() {
  local mount_point="${MOUNT_POINT:-}"
  if [ -z "$mount_point" ]; then
    return 0
  fi
  if [ "$MOUNT_ATTACHED" = "1" ]; then
    if ! hdiutil detach "$mount_point" >/dev/null; then
      echo "[DMG] Failed to detach verification mount: $mount_point" >&2
      return 1
    fi
    MOUNT_ATTACHED=0
  fi
  if ! rmdir "$mount_point"; then
    echo "[DMG] Failed to remove verification mount point: $mount_point" >&2
    return 1
  fi
  MOUNT_POINT=""
  MOUNT_POINT_OWNED=0
}

mount_point_is_owned() {
  local mount_point="$1"
  local temp_root=""
  local parent_root=""

  [ "$MOUNT_POINT_OWNED" = "1" ] || return 1
  temp_root="$(cd -- "${TMPDIR:-/tmp}" && pwd -P 2>/dev/null)" || return 1
  parent_root="$(
    cd -- "$(dirname -- "$mount_point")" && pwd -P 2>/dev/null
  )" || return 1
  [ "$parent_root" = "$temp_root" ] || return 1
  case "$(basename -- "$mount_point")" in
    xterminal-dmg-verify.*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup_mount() {
  local mount_point="${MOUNT_POINT:-}"
  if [ -z "$mount_point" ]; then
    return 0
  fi

  if [ "$MOUNT_ATTACHED" = "1" ]; then
    if hdiutil detach "$mount_point" >/dev/null 2>&1; then
      MOUNT_ATTACHED=0
    elif mount_point_is_owned "$mount_point" && \
         hdiutil detach -force "$mount_point" >/dev/null 2>&1; then
      MOUNT_ATTACHED=0
    else
      echo "[DMG] Warning: verification mount is still attached: $mount_point" >&2
    fi
  fi

  if rmdir "$mount_point" >/dev/null 2>&1; then
    MOUNT_POINT=""
    MOUNT_ATTACHED=0
    MOUNT_POINT_OWNED=0
  elif [ "$MOUNT_ATTACHED" = "0" ]; then
    echo "[DMG] Warning: could not remove verification mount point: $mount_point" >&2
  fi
  return 0
}
trap cleanup_mount EXIT

normalize_dmg_output_path() {
  local raw_path="${1:-}"
  local parent=""
  local parent_real=""
  local basename_value=""
  local output_path=""

  if [ -z "$raw_path" ]; then
    echo "[DMG] Output path must not be empty." >&2
    return 1
  fi
  parent="$(dirname -- "$raw_path")"
  basename_value="$(basename -- "$raw_path")"
  case "$basename_value" in
    ''|.|..|/)
      echo "[DMG] Output path has no safe file name: $raw_path" >&2
      return 1
      ;;
  esac
  if [ ! -d "$parent" ]; then
    echo "[DMG] Output directory does not exist: $parent" >&2
    return 1
  fi
  parent_real="$(cd -- "$parent" && pwd -P)" || {
    echo "[DMG] Output directory cannot be resolved: $parent" >&2
    return 1
  }
  output_path="$parent_real/$basename_value"
  if [ -L "$output_path" ] || [ -d "$output_path" ]; then
    echo "[DMG] Output must not be a symlink or directory: $output_path" >&2
    return 1
  fi
  if [ -e "$output_path" ] && [ ! -f "$output_path" ]; then
    echo "[DMG] Output must be a regular file when it already exists: $output_path" >&2
    return 1
  fi
  printf '%s\n' "$output_path"
}

verify_xt_artifact_root() {
  local artifact_root="$1"
  local manifest="$artifact_root/X-Terminal.provenance.json"
  local app="$artifact_root/X-Terminal.app"
  local verifier="$app/Contents/Resources/xtd"
  local -a verify_args=(
    provenance verify
    --manifest "$manifest"
    --artifact-root "$artifact_root"
    --repository-root "$ROOT_DIR"
  )

  if [ ! -d "$app" ] || [ -L "$app" ]; then
    echo "[DMG] X-Terminal app is missing or symlinked: $app" >&2
    return 1
  fi
  if [ ! -f "$manifest" ] || [ -L "$manifest" ]; then
    echo "[DMG] XT provenance is missing or symlinked: $manifest" >&2
    return 1
  fi
  if [ ! -x "$verifier" ] || [ -L "$verifier" ]; then
    echo "[DMG] Trusted XT provenance verifier is missing: $verifier" >&2
    return 1
  fi
  if [ "$RELEASE_BUILD" = "1" ]; then
    verify_args+=(--require-release)
    xterminal_verify_pinned_codesign "$app" "$ROOT_DIR" 1 >/dev/null
    xterminal_verify_pinned_codesign "$verifier" "$ROOT_DIR" 0 >/dev/null
  else
    codesign --verify --deep --strict "$app"
  fi
  "$verifier" "${verify_args[@]}" >/dev/null
}

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

OUT_DMG="$(
  normalize_dmg_output_path \
    "${XTERMINAL_DMG_OUTPUT:-$ROOT_DIR/build/X-Terminal v${VER}.dmg}"
)"
VOLNAME="${XTERMINAL_DMG_VOLUME_NAME:-X-Terminal v${VER}}"

STAGE="$ROOT_DIR/build/xterminal_dmg_stage"
rm -rf "$STAGE" 2>/dev/null || true
mkdir -p "$STAGE"

if [ -f "$PROVENANCE_PATH" ]; then
  verify_xt_artifact_root "$ROOT_DIR/build"
elif [ "$RELEASE_BUILD" = "1" ]; then
  echo "[DMG] Formal release requires detached XT provenance: $PROVENANCE_PATH" >&2
  exit 1
else
  echo "[DMG] Warning: building a development DMG without detached provenance." >&2
  codesign --verify --deep --strict "$APP_PATH"
fi

echo "[DMG] Staging app, provenance, and install note..."
cp -R "$APP_PATH" "$STAGE/X-Terminal.app"
if [ -f "$PROVENANCE_PATH" ]; then
  cp -f "$PROVENANCE_PATH" "$STAGE/X-Terminal.provenance.json"
  verify_xt_artifact_root "$STAGE"
fi

{
  echo "X-Terminal (macOS)"
  echo
  echo "Install:"
  echo "1) Copy X-Terminal.app and X-Terminal.provenance.json to Applications"
  echo
  echo "First run:"
  echo "- Launch X-Hub first, then launch X-Terminal"
  echo "- Pair X-Terminal with X-Hub before relying on governed routes"
  echo
  echo "Notes:"
  echo "- X-Terminal is the paired deep client for X-Hub-System."
  echo "- It does not replace Hub-side grants, routing, memory truth, or policy."
  echo "- Keep X-Terminal.provenance.json beside X-Terminal.app for verification."
} > "$STAGE/README.txt"

ln -s "/Applications" "$STAGE/Applications"

echo "[DMG] Creating DMG: $OUT_DMG"
rm -f "$OUT_DMG" 2>/dev/null || true
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT_DMG" >/dev/null

if [ "$RELEASE_BUILD" = "1" ]; then
  echo "[DMG] Signing release disk image..."
  codesign --force --sign "$IDENTITY" "$OUT_DMG"
  xterminal_verify_pinned_codesign "$OUT_DMG" "$ROOT_DIR" 0 >/dev/null
fi

echo "[DMG] Mounting disk image for final verification..."
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/xterminal-dmg-verify.XXXXXX")"
MOUNT_POINT_OWNED=1
if ! hdiutil attach -nobrowse -readonly \
  -mountpoint "$MOUNT_POINT" "$OUT_DMG" >/dev/null; then
  echo "[DMG] Failed to attach disk image for verification: $OUT_DMG" >&2
  exit 1
fi
MOUNT_ATTACHED=1
if [ -f "$MOUNT_POINT/X-Terminal.provenance.json" ]; then
  verify_xt_artifact_root "$MOUNT_POINT"
elif [ "$RELEASE_BUILD" = "1" ]; then
  echo "[DMG] Mounted release image lost XT provenance." >&2
  exit 1
else
  codesign --verify --deep --strict "$MOUNT_POINT/X-Terminal.app"
fi
detach_mount

echo "[DMG] Done: $OUT_DMG"
