#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/build_snapshot_retention.sh
source "$ROOT_DIR/scripts/lib/build_snapshot_retention.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xhub_build_snapshot_retention.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  echo "[smoke-build-snapshot-retention] $1" >&2
  exit 1
}

assert_exists() {
  local path="$1"
  [ -e "$path" ] || fail "missing_expected_path=$path"
}

assert_missing() {
  local path="$1"
  [ ! -e "$path" ] || fail "unexpected_path_present=$path"
}

run_keep_two_scenario() {
  local scenario_root="$TMP_ROOT/keep_two"
  local snapshot_dir="$scenario_root/.xhub-build-src"
  mkdir -p \
    "$snapshot_dir" \
    "$scenario_root/.xhub-build-src-20260317-2310" \
    "$scenario_root/.xhub-build-src-20260318-0702" \
    "$scenario_root/.xhub-build-src-20260318-0730" \
    "$scenario_root/.xhub-build-src-20260318-0739"

  xhub_prune_old_snapshot_dirs "$snapshot_dir" 2

  assert_exists "$snapshot_dir"
  assert_exists "$scenario_root/.xhub-build-src-20260318-0739"
  assert_exists "$scenario_root/.xhub-build-src-20260318-0730"
  assert_missing "$scenario_root/.xhub-build-src-20260318-0702"
  assert_missing "$scenario_root/.xhub-build-src-20260317-2310"
}

run_invalid_keep_count_scenario() {
  local scenario_root="$TMP_ROOT/invalid_keep_count"
  local snapshot_dir="$scenario_root/.xterminal-build-src"
  mkdir -p \
    "$snapshot_dir" \
    "$scenario_root/.xterminal-build-src-20260317-2310" \
    "$scenario_root/.xterminal-build-src-20260318-0702"

  xhub_prune_old_snapshot_dirs "$snapshot_dir" "not-a-number"

  assert_exists "$snapshot_dir"
  assert_exists "$scenario_root/.xterminal-build-src-20260317-2310"
  assert_exists "$scenario_root/.xterminal-build-src-20260318-0702"
}

run_zero_keep_scenario() {
  local scenario_root="$TMP_ROOT/keep_zero"
  local snapshot_dir="$scenario_root/.xhub-build-src"
  mkdir -p \
    "$snapshot_dir" \
    "$scenario_root/.xhub-build-src-20260318-0730" \
    "$scenario_root/.xhub-build-src-20260318-0739"

  xhub_prune_old_snapshot_dirs "$snapshot_dir" 0

  assert_exists "$snapshot_dir"
  assert_missing "$scenario_root/.xhub-build-src-20260318-0730"
  assert_missing "$scenario_root/.xhub-build-src-20260318-0739"
}

run_keep_two_scenario
run_invalid_keep_count_scenario
run_zero_keep_scenario

echo "[smoke-build-snapshot-retention] pass"
