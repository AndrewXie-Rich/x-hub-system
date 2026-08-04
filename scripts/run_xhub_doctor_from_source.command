#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

print_usage() {
  cat <<'EOF'
usage: bash scripts/run_xhub_doctor_from_source.command <hub|xt|all> [--workspace-root /path] [--out-json /path] [--out-dir /path]
       [--xt-diagnostic-snapshot /path/to/x-terminal --xt-snapshot-inventory /path/to/inventory.json]

examples:
  bash scripts/run_xhub_doctor_from_source.command hub --out-json /tmp/xhub_doctor_output_hub.json
  bash scripts/run_xhub_doctor_from_source.command xt --workspace-root /path/to/workspace --out-json /tmp/xhub_doctor_output_xt.json
  bash scripts/run_xhub_doctor_from_source.command all --workspace-root /path/to/workspace --out-dir /tmp/xhub_doctor_bundle
  bash scripts/run_xhub_doctor_from_source.command xt --xt-diagnostic-snapshot /tmp/snapshot/x-terminal --xt-snapshot-inventory /tmp/evidence/snapshot.inventory.json --workspace-root /tmp/doctor-workspace --out-json /tmp/evidence/xhub_doctor_output_xt.json

notes:
  - `hub` forwards to `bash x-hub/tools/run_xhub_from_source.command doctor`
  - `xt` forwards to the canonical in-repo helper under `x-terminal/`
  - XT diagnostic snapshots are accepted only with a detached, exact SHA-256 inventory and run only `--xt-unified-doctor-export`
  - snapshot, inventory, workspace, runtime caches, and output must remain outside both source roots
  - `all` runs both surfaces sequentially and returns `0`, `1`, or `2` using the highest-severity result
  - `--workspace-root` is the preferred unified alias; `--project-root` remains supported for XT compatibility
  - `--out-json` is only valid for a single surface; use `--out-dir` when running `all`
EOF
}

fail_usage() {
  echo "$1" >&2
  echo >&2
  print_usage >&2
  exit 2
}

surface=""
workspace_root=""
project_root=""
out_json=""
out_dir=""
xt_diagnostic_snapshot=""
xt_snapshot_inventory=""
hub_helper="${XHUB_HUB_SOURCE_HELPER:-$ROOT_DIR/x-hub/tools/run_xhub_from_source.command}"
xt_root="$ROOT_DIR/x-terminal"
xt_helper="$xt_root/tools/run_xterminal_from_source.command"
xt_snapshot_runner="$SCRIPT_DIR/lib/run_xt_doctor_diagnostic_snapshot.command"
xt_snapshot_inventory_tool="$SCRIPT_DIR/lib/xt_doctor_snapshot_inventory.py"
aggregate_exit_code=0
surface_cmd=()

# shellcheck source=../x-terminal/scripts/lib/canonical_root_guard.sh
source "$ROOT_DIR/x-terminal/scripts/lib/canonical_root_guard.sh"
xterminal_assert_canonical_root "$ROOT_DIR" "$xt_root"

expand_path() {
  local value="$1"
  if [ -z "$value" ]; then
    printf '%s' ""
    return
  fi
  printf '%s\n' "${value/#\~/$HOME}"
}

external_directory_for_snapshot() {
  local label="$1"
  local value="$2"
  local resolved=""

  case "$value" in
    /*) ;;
    *) fail_usage "$label must be an absolute path in diagnostic snapshot mode" ;;
  esac
  [ -d "$value" ] || fail_usage "$label is unavailable: $value"
  resolved="$(cd "$value" && pwd -P)"
  case "$resolved/" in
    "$ROOT_DIR/"*) fail_usage "$label must be outside the canonical repository root" ;;
  esac
  case "$resolved/" in
    "$xt_diagnostic_snapshot/"*) fail_usage "$label must be outside the XT diagnostic snapshot root" ;;
  esac
  printf '%s\n' "$resolved"
}

preflight_xt_diagnostic_snapshot() {
  local inventory_parent=""
  local inventory_name=""
  local output_parent=""
  local output_name=""

  [ -n "$workspace_root" ] \
    || fail_usage "--workspace-root is required in XT diagnostic snapshot mode"
  if [ -z "$out_json" ] && [ -z "$out_dir" ]; then
    fail_usage "--out-json or --out-dir is required in XT diagnostic snapshot mode"
  fi
  [ -d "$xt_diagnostic_snapshot" ] \
    || fail_usage "XT diagnostic snapshot root is unavailable: $xt_diagnostic_snapshot"
  xt_diagnostic_snapshot="$(cd "$xt_diagnostic_snapshot" && pwd -P)"

  workspace_root="$(external_directory_for_snapshot "diagnostic workspace root" "$workspace_root")"

  if [ -n "$out_dir" ]; then
    out_dir="$(external_directory_for_snapshot "diagnostic output directory" "$out_dir")"
  fi
  if [ -n "$out_json" ]; then
    case "$out_json" in
      /*) ;;
      *) fail_usage "diagnostic output path must be absolute" ;;
    esac
    [ ! -d "$out_json" ] || fail_usage "diagnostic output path is a directory: $out_json"
    [ ! -L "$out_json" ] || fail_usage "diagnostic output path must not be a symlink: $out_json"
    output_parent="$(dirname "$out_json")"
    output_name="$(basename "$out_json")"
    output_parent="$(external_directory_for_snapshot "diagnostic output directory" "$output_parent")"
    out_json="$output_parent/$output_name"
  fi

  [ -f "$xt_snapshot_inventory" ] && [ ! -L "$xt_snapshot_inventory" ] \
    || fail_usage "XT diagnostic snapshot inventory is unavailable or symlinked: $xt_snapshot_inventory"
  inventory_parent="$(dirname "$xt_snapshot_inventory")"
  inventory_name="$(basename "$xt_snapshot_inventory")"
  inventory_parent="$(external_directory_for_snapshot "diagnostic inventory directory" "$inventory_parent")"
  xt_snapshot_inventory="$inventory_parent/$inventory_name"

  python3 "$xt_snapshot_inventory_tool" verify \
    --repo-root "$ROOT_DIR" \
    --snapshot-root "$xt_diagnostic_snapshot" \
    --inventory "$xt_snapshot_inventory" >/dev/null
}

default_output_filename() {
  case "$1" in
    hub)
      printf '%s\n' "xhub_doctor_output_hub.json"
      ;;
    xt)
      printf '%s\n' "xhub_doctor_output_xt.json"
      ;;
    *)
      fail_usage "unsupported surface for output naming: $1"
      ;;
  esac
}

output_path_for_surface() {
  local surface_name="$1"
  local filename=""
  if [ -n "$out_json" ]; then
    printf '%s\n' "$out_json"
    return
  fi
  if [ -n "$out_dir" ]; then
    mkdir -p "$out_dir"
    filename="$(default_output_filename "$surface_name")"
    printf '%s/%s\n' "$out_dir" "$filename"
    return
  fi
  printf '%s' ""
}

build_surface_cmd() {
  local surface_name="$1"
  local output_path=""
  output_path="$(output_path_for_surface "$surface_name")"
  surface_cmd=()

  case "$surface_name" in
    hub)
      surface_cmd=(bash "$hub_helper" doctor)
      ;;
    xt)
      if [ -n "$xt_diagnostic_snapshot" ]; then
        surface_cmd=(
          bash "$xt_snapshot_runner"
          --snapshot-root "$xt_diagnostic_snapshot"
          --inventory "$xt_snapshot_inventory"
        )
      else
        surface_cmd=(bash "$xt_helper" --xt-unified-doctor-export)
      fi
      if [ -n "$workspace_root" ]; then
        surface_cmd+=(--project-root "$workspace_root")
      fi
      ;;
    *)
      fail_usage "unsupported surface: $surface_name"
      ;;
  esac

  if [ -n "$output_path" ]; then
    surface_cmd+=(--out-json "$output_path")
  fi
}

normalize_exit_code() {
  case "$1" in
    0|1|2)
      printf '%s\n' "$1"
      ;;
    *)
      printf '%s\n' "2"
      ;;
  esac
}

run_surface_and_capture() {
  local surface_name="$1"
  local raw_exit_code=0
  local normalized_exit_code=0

  build_surface_cmd "$surface_name"
  echo "[xhub-doctor-wrapper] start surface=$surface_name"
  if "${surface_cmd[@]}"; then
    raw_exit_code=0
  else
    raw_exit_code=$?
  fi
  normalized_exit_code="$(normalize_exit_code "$raw_exit_code")"
  echo "[xhub-doctor-wrapper] done surface=$surface_name raw_exit_code=$raw_exit_code normalized_exit_code=$normalized_exit_code"

  if [ "$normalized_exit_code" -gt "$aggregate_exit_code" ]; then
    aggregate_exit_code="$normalized_exit_code"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    hub|xt|all)
      if [ -n "$surface" ]; then
        fail_usage "surface already set to '$surface'"
      fi
      surface="$1"
      shift
      ;;
    --surface)
      if [ "$#" -lt 2 ]; then
        fail_usage "missing value after --surface"
      fi
      if [ -n "$surface" ]; then
        fail_usage "surface already set to '$surface'"
      fi
      surface="$2"
      shift 2
      ;;
    --workspace-root)
      if [ "$#" -lt 2 ]; then
        fail_usage "missing value after --workspace-root"
      fi
      workspace_root="$2"
      shift 2
      ;;
    --project-root)
      if [ "$#" -lt 2 ]; then
        fail_usage "missing value after --project-root"
      fi
      project_root="$2"
      shift 2
      ;;
    --out-json)
      if [ "$#" -lt 2 ]; then
        fail_usage "missing value after --out-json"
      fi
      out_json="$2"
      shift 2
      ;;
    --out-dir)
      if [ "$#" -lt 2 ]; then
        fail_usage "missing value after --out-dir"
      fi
      out_dir="$2"
      shift 2
      ;;
    --xt-diagnostic-snapshot)
      if [ "$#" -lt 2 ]; then
        fail_usage "missing value after --xt-diagnostic-snapshot"
      fi
      xt_diagnostic_snapshot="$2"
      shift 2
      ;;
    --xt-snapshot-inventory)
      if [ "$#" -lt 2 ]; then
        fail_usage "missing value after --xt-snapshot-inventory"
      fi
      xt_snapshot_inventory="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      fail_usage "unknown argument: $1"
      ;;
  esac
done

if [ -z "$surface" ]; then
  fail_usage "missing surface: choose 'hub', 'xt', or 'all'"
fi

workspace_root="$(expand_path "$workspace_root")"
project_root="$(expand_path "$project_root")"
out_json="$(expand_path "$out_json")"
out_dir="$(expand_path "$out_dir")"
xt_diagnostic_snapshot="$(expand_path "$xt_diagnostic_snapshot")"
xt_snapshot_inventory="$(expand_path "$xt_snapshot_inventory")"

if [ "$surface" = "xt" ] || [ "$surface" = "all" ]; then
  if [ -n "${XHUB_XT_SOURCE_HELPER:-}" ]; then
    fail_usage "XHUB_XT_SOURCE_HELPER is unsupported; use the canonical XT root or the explicit diagnostic snapshot mode"
  fi
  if [ -n "${XHUB_ACTIVE_XT_ROOT:-}" ]; then
    fail_usage "XHUB_ACTIVE_XT_ROOT is unsupported; use the canonical XT root or the explicit diagnostic snapshot mode"
  fi
  if [ -n "${XHUB_ALLOW_LEGACY_XTERMINAL_RUN:-}" ]; then
    fail_usage "XHUB_ALLOW_LEGACY_XTERMINAL_RUN is unsupported"
  fi
fi

if [ -n "$xt_diagnostic_snapshot" ] && [ -z "$xt_snapshot_inventory" ]; then
  fail_usage "--xt-diagnostic-snapshot requires --xt-snapshot-inventory"
fi

if [ -z "$xt_diagnostic_snapshot" ] && [ -n "$xt_snapshot_inventory" ]; then
  fail_usage "--xt-snapshot-inventory requires --xt-diagnostic-snapshot"
fi

if [ -n "$xt_diagnostic_snapshot" ] && [ "$surface" != "xt" ] && [ "$surface" != "all" ]; then
  fail_usage "XT diagnostic snapshots are only supported for the 'xt' or 'all' surfaces"
fi

if [ -n "$workspace_root" ] && [ -n "$project_root" ] && [ "$workspace_root" != "$project_root" ]; then
  fail_usage "--workspace-root and --project-root must point to the same path when both are provided"
fi

if [ -z "$workspace_root" ] && [ -n "$project_root" ]; then
  workspace_root="$project_root"
fi

if [ -n "$out_json" ] && [ -n "$out_dir" ]; then
  fail_usage "--out-json and --out-dir cannot be used together"
fi

if [ "$surface" = "hub" ] && [ -n "$workspace_root" ]; then
  fail_usage "--workspace-root is only supported for the 'xt' or 'all' surfaces"
fi

if [ "$surface" = "all" ] && [ -n "$out_json" ]; then
  fail_usage "--out-json is only supported for a single surface; use --out-dir with 'all'"
fi

if [ -n "$xt_diagnostic_snapshot" ]; then
  preflight_xt_diagnostic_snapshot
fi

if [ "$surface" != "all" ]; then
  build_surface_cmd "$surface"
  exec "${surface_cmd[@]}"
fi

run_surface_and_capture "hub"
run_surface_and_capture "xt"
echo "[xhub-doctor-wrapper] final_exit_code=$aggregate_exit_code"
exit "$aggregate_exit_code"
