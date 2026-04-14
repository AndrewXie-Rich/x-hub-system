#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

print_usage() {
  cat <<'EOF'
usage: bash scripts/run_xhub_doctor_from_source.command <hub|xt|all> [--workspace-root /path] [--out-json /path] [--out-dir /path]

examples:
  bash scripts/run_xhub_doctor_from_source.command hub --out-json /tmp/xhub_doctor_output_hub.json
  bash scripts/run_xhub_doctor_from_source.command xt --workspace-root /path/to/workspace --out-json /tmp/xhub_doctor_output_xt.json
  bash scripts/run_xhub_doctor_from_source.command all --workspace-root /path/to/workspace --out-dir /tmp/xhub_doctor_bundle

notes:
  - `hub` forwards to `bash x-hub/tools/run_xhub_from_source.command doctor`
  - `xt` forwards to `bash x-terminal/tools/run_xterminal_from_source.command --xt-unified-doctor-export`
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
hub_helper="${XHUB_HUB_SOURCE_HELPER:-$ROOT_DIR/x-hub/tools/run_xhub_from_source.command}"
xt_helper="${XHUB_XT_SOURCE_HELPER:-$ROOT_DIR/x-terminal/tools/run_xterminal_from_source.command}"
aggregate_exit_code=0
surface_cmd=()

expand_path() {
  local value="$1"
  if [ -z "$value" ]; then
    printf '%s' ""
    return
  fi
  printf '%s\n' "${value/#\~/$HOME}"
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
      surface_cmd=(bash "$xt_helper" --xt-unified-doctor-export)
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

if [ "$surface" != "all" ]; then
  build_surface_cmd "$surface"
  exec "${surface_cmd[@]}"
fi

run_surface_and_capture "hub"
run_surface_and_capture "xt"
echo "[xhub-doctor-wrapper] final_exit_code=$aggregate_exit_code"
exit "$aggregate_exit_code"
