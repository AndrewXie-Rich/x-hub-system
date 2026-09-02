#!/usr/bin/env bash

xterminal_realpath_dir() {
  local path="${1:-}"
  [ -n "$path" ] && [ -d "$path" ] || return 1
  (cd "$path" && pwd -P)
}

xterminal_assert_canonical_root() {
  local workspace_root="${1:-}"
  local xt_root="${2:-}"
  local workspace_real=""
  local xt_real=""
  local expected_real=""
  local git_root=""
  local git_root_real=""

  workspace_real="$(xterminal_realpath_dir "$workspace_root" 2>/dev/null || true)"
  xt_real="$(xterminal_realpath_dir "$xt_root" 2>/dev/null || true)"
  expected_real="$(xterminal_realpath_dir "$workspace_root/x-terminal" 2>/dev/null || true)"

  if [ -z "$workspace_real" ] || [ -z "$xt_real" ] || [ -z "$expected_real" ]; then
    echo "[XT ROOT] Missing canonical repository or X-Terminal directory." >&2
    echo "[XT ROOT] Expected: $workspace_root/x-terminal" >&2
    return 1
  fi

  if [ "$xt_real" != "$expected_real" ]; then
    echo "[XT ROOT] Refusing non-canonical X-Terminal source: $xt_root" >&2
    echo "[XT ROOT] Canonical source: $workspace_real/x-terminal" >&2
    return 1
  fi

  git_root="$(git -C "$workspace_real" rev-parse --show-toplevel 2>/dev/null || true)"
  git_root_real="$(xterminal_realpath_dir "$git_root" 2>/dev/null || true)"
  if [ -z "$git_root_real" ] || [ "$git_root_real" != "$workspace_real" ]; then
    echo "[XT ROOT] Refusing X-Terminal outside the enclosing version-controlled X Hub root." >&2
    echo "[XT ROOT] Expected Git root: $workspace_real" >&2
    return 1
  fi

  if ! git -C "$workspace_real" ls-files --error-unmatch \
    x-terminal/Package.swift \
    x-terminal/tools/build_xterminal_app.command >/dev/null 2>&1; then
    echo "[XT ROOT] Canonical X-Terminal markers are not tracked by the enclosing repository." >&2
    return 1
  fi
}
