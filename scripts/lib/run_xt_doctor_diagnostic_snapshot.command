#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
INVENTORY_TOOL="$SCRIPT_DIR/xt_doctor_snapshot_inventory.py"
CANONICAL_XT_ROOT="$ROOT_DIR/x-terminal"

fail_usage() {
  echo "[xt-doctor-snapshot] FAIL: $1" >&2
  exit 2
}

expand_path() {
  local value="$1"
  printf '%s\n' "${value/#\~/$HOME}"
}

assert_runtime_path_outside_snapshot() {
  local label="$1"
  local runtime_path="$2"
  local runtime_real=""

  runtime_real="$(cd "$runtime_path" && pwd -P)"
  case "$runtime_real/" in
    "$snapshot_root_real/"*)
      fail_usage "$label must be outside the verified snapshot root: $runtime_real"
      ;;
  esac
  case "$runtime_real/" in
    "$ROOT_DIR/"*)
      fail_usage "$label must be outside the canonical repository root: $runtime_real"
      ;;
  esac
}

assert_external_directory() {
  local label="$1"
  local directory_path="$2"
  local directory_real=""

  case "$directory_path" in
    /*) ;;
    *) fail_usage "$label must be an absolute path" ;;
  esac
  [ -d "$directory_path" ] || fail_usage "$label is unavailable: $directory_path"
  directory_real="$(cd "$directory_path" && pwd -P)"
  case "$directory_real/" in
    "$snapshot_root_real/"*)
      fail_usage "$label must be outside the verified snapshot root: $directory_real"
      ;;
  esac
  case "$directory_real/" in
    "$ROOT_DIR/"*)
      fail_usage "$label must be outside the canonical repository root: $directory_real"
      ;;
  esac
  printf '%s\n' "$directory_real"
}

snapshot_root=""
inventory_path=""
project_root=""
out_json=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --snapshot-root)
      [ "$#" -ge 2 ] || fail_usage "missing value after --snapshot-root"
      snapshot_root="$2"
      shift 2
      ;;
    --inventory)
      [ "$#" -ge 2 ] || fail_usage "missing value after --inventory"
      inventory_path="$2"
      shift 2
      ;;
    --project-root)
      [ "$#" -ge 2 ] || fail_usage "missing value after --project-root"
      project_root="$2"
      shift 2
      ;;
    --out-json)
      [ "$#" -ge 2 ] || fail_usage "missing value after --out-json"
      out_json="$2"
      shift 2
      ;;
    *)
      fail_usage "unsupported diagnostic snapshot argument: $1"
      ;;
  esac
done

[ -n "$snapshot_root" ] || fail_usage "missing --snapshot-root"
[ -n "$inventory_path" ] || fail_usage "missing --inventory"
[ -n "$project_root" ] || fail_usage "missing --project-root for diagnostic snapshot export"
[ -n "$out_json" ] || fail_usage "missing --out-json for diagnostic snapshot export"

snapshot_root="$(expand_path "$snapshot_root")"
inventory_path="$(expand_path "$inventory_path")"
project_root="$(expand_path "$project_root")"
out_json="$(expand_path "$out_json")"

# The runner itself must remain inside the canonical Git worktree. Snapshot
# source is verified separately and is never accepted as a normal XT root.
# shellcheck source=../../x-terminal/scripts/lib/canonical_root_guard.sh
source "$CANONICAL_XT_ROOT/scripts/lib/canonical_root_guard.sh"
xterminal_assert_canonical_root "$ROOT_DIR" "$CANONICAL_XT_ROOT"

[ -d "$snapshot_root" ] || fail_usage "diagnostic snapshot root is unavailable: $snapshot_root"
snapshot_root_real="$(cd "$snapshot_root" && pwd -P)"
project_root="$(assert_external_directory "diagnostic workspace root" "$project_root")"

case "$out_json" in
  /*) ;;
  *) fail_usage "diagnostic output path must be absolute" ;;
esac
[ ! -d "$out_json" ] || fail_usage "diagnostic output path is a directory: $out_json"
[ ! -L "$out_json" ] || fail_usage "diagnostic output path must not be a symlink: $out_json"
out_json_parent="$(dirname "$out_json")"
out_json_name="$(basename "$out_json")"
[ "$out_json_name" != "." ] && [ "$out_json_name" != ".." ] \
  || fail_usage "diagnostic output path must name a file"
out_json_parent="$(assert_external_directory "diagnostic output directory" "$out_json_parent")"
out_json="$out_json_parent/$out_json_name"

runtime_base="$(mktemp -d "${TMPDIR:-/tmp}/xhub_xt_doctor_snapshot_runtime.XXXXXX")"
cleanup() {
  rm -rf "$runtime_base"
}
trap cleanup EXIT

source_run_home="${XTERMINAL_SOURCE_RUN_HOME:-$runtime_base/home}"
source_run_tmpdir="${XTERMINAL_SOURCE_RUN_TMPDIR:-$runtime_base/tmp}"
source_run_scratch_path="${XTERMINAL_SOURCE_RUN_SCRATCH_PATH:-$runtime_base/scratch}"
source_run_clang_module_cache_path="${XTERMINAL_SOURCE_RUN_CLANG_MODULE_CACHE_PATH:-$runtime_base/clang-module-cache}"
source_run_swift_module_cache_path="${XTERMINAL_SOURCE_RUN_SWIFT_MODULE_CACHE_PATH:-$runtime_base/swift-module-cache}"
source_run_disable_sandbox="${XTERMINAL_SOURCE_RUN_DISABLE_SANDBOX:-0}"
source_run_disable_index_store="${XTERMINAL_SOURCE_RUN_DISABLE_INDEX_STORE:-0}"

for runtime_path in \
  "$source_run_home" \
  "$source_run_tmpdir" \
  "$source_run_scratch_path" \
  "$source_run_clang_module_cache_path" \
  "$source_run_swift_module_cache_path"; do
  case "$runtime_path" in
    /*) ;;
    *) fail_usage "diagnostic runtime paths must be absolute: $runtime_path" ;;
  esac
done

mkdir -p \
  "$source_run_home" \
  "$source_run_tmpdir" \
  "$source_run_scratch_path" \
  "$source_run_clang_module_cache_path" \
  "$source_run_swift_module_cache_path"

assert_runtime_path_outside_snapshot "XTERMINAL_SOURCE_RUN_HOME" "$source_run_home"
assert_runtime_path_outside_snapshot "XTERMINAL_SOURCE_RUN_TMPDIR" "$source_run_tmpdir"
assert_runtime_path_outside_snapshot "XTERMINAL_SOURCE_RUN_SCRATCH_PATH" "$source_run_scratch_path"
assert_runtime_path_outside_snapshot \
  "XTERMINAL_SOURCE_RUN_CLANG_MODULE_CACHE_PATH" \
  "$source_run_clang_module_cache_path"
assert_runtime_path_outside_snapshot \
  "XTERMINAL_SOURCE_RUN_SWIFT_MODULE_CACHE_PATH" \
  "$source_run_swift_module_cache_path"

swift_args=(run)
if [ "$source_run_disable_sandbox" = "1" ]; then
  swift_args+=(--disable-sandbox)
elif [ "$source_run_disable_sandbox" != "0" ]; then
  fail_usage "XTERMINAL_SOURCE_RUN_DISABLE_SANDBOX must be 0 or 1"
fi
if [ "$source_run_disable_index_store" = "1" ]; then
  swift_args+=(--disable-index-store)
elif [ "$source_run_disable_index_store" != "0" ]; then
  fail_usage "XTERMINAL_SOURCE_RUN_DISABLE_INDEX_STORE must be 0 or 1"
fi
swift_args+=(--scratch-path "$source_run_scratch_path")
swift_args+=(-Xcc "-fmodules-cache-path=$source_run_clang_module_cache_path")
swift_args+=(-Xswiftc -module-cache-path -Xswiftc "$source_run_swift_module_cache_path")
swift_args+=(XTerminal --xt-unified-doctor-export)
if [ -n "$project_root" ]; then
  swift_args+=(--project-root "$project_root")
fi
if [ -n "$out_json" ]; then
  swift_args+=(--out-json "$out_json")
fi

# This is deliberately the last source operation before Swift starts. It
# compares the live canonical worktree, the detached inventory, and every file
# present in the snapshot. Any missing, extra, changed, symlinked, or
# foreign-origin entry fails closed.
python3 "$INVENTORY_TOOL" verify \
  --repo-root "$ROOT_DIR" \
  --snapshot-root "$snapshot_root_real" \
  --inventory "$inventory_path"

cd "$snapshot_root_real"
if env \
  HOME="$source_run_home" \
  TMPDIR="$source_run_tmpdir" \
  swift "${swift_args[@]}"; then
  exit 0
else
  exit $?
fi
