#!/usr/bin/env bash

xhub_prune_old_snapshot_dirs() {
  local snapshot_dir="${1:-}"
  local keep_count="${2:-}"
  local parent_dir=""
  local base_name=""
  local old_dirs=()
  local trim_dirs=()

  [ -n "$snapshot_dir" ] || return 0

  if ! [[ "$keep_count" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  parent_dir="$(dirname "$snapshot_dir")"
  base_name="$(basename "$snapshot_dir")"
  [ -d "$parent_dir" ] || return 0

  while IFS= read -r old_dir; do
    [ -n "$old_dir" ] || continue
    old_dirs+=("$old_dir")
  done < <(
    find "$parent_dir" -maxdepth 1 -mindepth 1 -type d -name "${base_name}-*" -print | sort -r
  )

  if [ "${#old_dirs[@]}" -le "$keep_count" ]; then
    return 0
  fi

  trim_dirs=("${old_dirs[@]:$keep_count}")
  if [ "${#trim_dirs[@]}" -gt 0 ]; then
    echo "[prep] Pruning stale build snapshots: ${trim_dirs[*]}"
    rm -rf "${trim_dirs[@]}"
  fi
}
