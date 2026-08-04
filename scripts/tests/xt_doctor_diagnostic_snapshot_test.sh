#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
SOURCE_WRAPPER="$REPO_ROOT/scripts/run_xhub_doctor_from_source.command"
SOURCE_RUNNER="$REPO_ROOT/scripts/lib/run_xt_doctor_diagnostic_snapshot.command"
SOURCE_INVENTORY_TOOL="$REPO_ROOT/scripts/lib/xt_doctor_snapshot_inventory.py"
SOURCE_ROOT_GUARD="$REPO_ROOT/x-terminal/scripts/lib/canonical_root_guard.sh"
XT_SOURCE_SMOKE="$REPO_ROOT/scripts/smoke_xhub_doctor_xt_source_export.sh"
ALL_SOURCE_SMOKE="$REPO_ROOT/scripts/smoke_xhub_doctor_all_source_export.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xt_doctor_snapshot_test.XXXXXX")"
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

FIXTURE_ROOT="$TMP_ROOT/canonical repo"
WRAPPER="$FIXTURE_ROOT/scripts/run_xhub_doctor_from_source.command"
RUNNER="$FIXTURE_ROOT/scripts/lib/run_xt_doctor_diagnostic_snapshot.command"
INVENTORY_TOOL="$FIXTURE_ROOT/scripts/lib/xt_doctor_snapshot_inventory.py"
CALL_LOG="$TMP_ROOT/calls.log"
FAKE_BIN="$TMP_ROOT/fake-bin"

mkdir -p \
  "$FIXTURE_ROOT/scripts/lib" \
  "$FIXTURE_ROOT/x-terminal/scripts/lib" \
  "$FIXTURE_ROOT/x-terminal/tools" \
  "$FIXTURE_ROOT/x-hub/tools" \
  "$FAKE_BIN"

cp "$SOURCE_WRAPPER" "$WRAPPER"
cp "$SOURCE_RUNNER" "$RUNNER"
cp "$SOURCE_INVENTORY_TOOL" "$INVENTORY_TOOL"
cp "$SOURCE_ROOT_GUARD" "$FIXTURE_ROOT/x-terminal/scripts/lib/canonical_root_guard.sh"

printf '%s\n' '// fixture package' >"$FIXTURE_ROOT/x-terminal/Package.swift"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
  >"$FIXTURE_ROOT/x-terminal/tools/build_xterminal_app.command"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "canonical_helper_arg=%s\\n" "$@" >>"${XHUB_TEST_CALL_LOG:?}"' \
  >"$FIXTURE_ROOT/x-terminal/tools/run_xterminal_from_source.command"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
  >"$FIXTURE_ROOT/x-hub/tools/run_xhub_from_source.command"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "swift_cwd=%s\\n" "$PWD" >>"${XHUB_TEST_CALL_LOG:?}"' \
  'printf "swift_arg=%s\\n" "$@" >>"${XHUB_TEST_CALL_LOG:?}"' \
  'previous=""' \
  'for argument in "$@"; do' \
  '  if [ "$previous" = "--out-json" ]; then' \
  '    printf "%s\\n" "{}" >"$argument"' \
  '  fi' \
  '  previous="$argument"' \
  'done' \
  >"$FAKE_BIN/swift"

chmod +x \
  "$WRAPPER" \
  "$RUNNER" \
  "$INVENTORY_TOOL" \
  "$FIXTURE_ROOT/x-terminal/tools/build_xterminal_app.command" \
  "$FIXTURE_ROOT/x-terminal/tools/run_xterminal_from_source.command" \
  "$FIXTURE_ROOT/x-hub/tools/run_xhub_from_source.command" \
  "$FAKE_BIN/swift"

git -C "$FIXTURE_ROOT" init -q
git -C "$FIXTURE_ROOT" config user.name "XT Doctor Snapshot Test"
git -C "$FIXTURE_ROOT" config user.email "xt-doctor-snapshot@example.invalid"
git -C "$FIXTURE_ROOT" add .
git -c commit.gpgsign=false -C "$FIXTURE_ROOT" commit -qm "fixture"
mkdir -p "$TMP_ROOT/workspace"

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

expect_rejected() {
  local label="$1"
  local expected_pattern="$2"
  shift 2
  local rejection_log="$TMP_ROOT/rejection.log"
  if "$@" >"$rejection_log" 2>&1; then
    fail "expected rejection: $label"
  fi
  if ! grep -Fq -- "$expected_pattern" "$rejection_log"; then
    echo "[FAIL] rejection did not contain expected text: $label" >&2
    cat "$rejection_log" >&2
    exit 1
  fi
}

make_snapshot() {
  local label="$1"
  local snapshot_parent="$TMP_ROOT/$label"
  local snapshot_root="$snapshot_parent/x-terminal"
  local inventory_path="$TMP_ROOT/$label.inventory.json"

  mkdir -p "$snapshot_parent"
  cp -R "$FIXTURE_ROOT/x-terminal" "$snapshot_root"
  python3 "$INVENTORY_TOOL" create \
    --repo-root "$FIXTURE_ROOT" \
    --snapshot-root "$snapshot_root" \
    --inventory "$inventory_path" >/dev/null
}

# Normal source execution remains pinned to the canonical in-repo helper.
: >"$CALL_LOG"
XHUB_TEST_CALL_LOG="$CALL_LOG" \
  bash "$WRAPPER" xt --workspace-root "$TMP_ROOT/workspace" --out-json "$TMP_ROOT/normal.json"
grep -Fq 'canonical_helper_arg=--xt-unified-doctor-export' "$CALL_LOG" \
  || fail "normal XT run did not use the canonical helper"
grep -Fq "canonical_helper_arg=--project-root" "$CALL_LOG" \
  || fail "normal XT run did not forward --project-root"

make_snapshot clean-snapshot
clean_snapshot_root="$TMP_ROOT/clean-snapshot/x-terminal"
clean_inventory="$TMP_ROOT/clean-snapshot.inventory.json"

: >"$CALL_LOG"
PATH="$FAKE_BIN:$PATH" \
XHUB_TEST_CALL_LOG="$CALL_LOG" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$clean_snapshot_root" \
    --xt-snapshot-inventory "$clean_inventory" \
    --workspace-root "$TMP_ROOT/workspace" \
    --out-json "$TMP_ROOT/snapshot-output.json" >/dev/null

grep -Fq "swift_cwd=$clean_snapshot_root" "$CALL_LOG" \
  || fail "diagnostic run did not execute from the verified snapshot"
[ "$(grep -Fc 'swift_arg=--xt-unified-doctor-export' "$CALL_LOG")" -eq 1 ] \
  || fail "diagnostic run did not issue exactly one unified doctor export flag"
grep -Fq "swift_arg=--project-root" "$CALL_LOG" \
  || fail "diagnostic run did not forward --project-root"
grep -Fq "swift_arg=--out-json" "$CALL_LOG" \
  || fail "diagnostic run did not forward --out-json"
[ -f "$TMP_ROOT/snapshot-output.json" ] \
  || fail "diagnostic report was not written to the caller-selected external path"
[ ! -e "$FIXTURE_ROOT/.axcoder" ] \
  || fail "diagnostic run wrote .axcoder state into the canonical repository"
[ ! -e "$clean_snapshot_root/.axcoder" ] \
  || fail "diagnostic run wrote .axcoder state into the source snapshot"

make_snapshot extra-snapshot
extra_snapshot_root="$TMP_ROOT/extra-snapshot/x-terminal"
extra_inventory="$TMP_ROOT/extra-snapshot.inventory.json"
printf '%s\n' 'unexpected' >"$extra_snapshot_root/unexpected.txt"
expect_rejected \
  "extra snapshot file" \
  "extra=unexpected.txt" \
  env PATH="$FAKE_BIN:$PATH" XHUB_TEST_CALL_LOG="$CALL_LOG" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$extra_snapshot_root" \
    --xt-snapshot-inventory "$extra_inventory" \
    --workspace-root "$TMP_ROOT/workspace" \
    --out-json "$TMP_ROOT/extra-output.json"

make_snapshot missing-snapshot
missing_snapshot_root="$TMP_ROOT/missing-snapshot/x-terminal"
missing_inventory="$TMP_ROOT/missing-snapshot.inventory.json"
rm "$missing_snapshot_root/Package.swift"
expect_rejected \
  "missing snapshot file" \
  "missing=Package.swift" \
  env PATH="$FAKE_BIN:$PATH" XHUB_TEST_CALL_LOG="$CALL_LOG" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$missing_snapshot_root" \
    --xt-snapshot-inventory "$missing_inventory" \
    --workspace-root "$TMP_ROOT/workspace" \
    --out-json "$TMP_ROOT/missing-output.json"

make_snapshot changed-snapshot
changed_snapshot_root="$TMP_ROOT/changed-snapshot/x-terminal"
changed_inventory="$TMP_ROOT/changed-snapshot.inventory.json"
printf '%s\n' '// changed after inventory' >>"$changed_snapshot_root/Package.swift"
expect_rejected \
  "changed snapshot file" \
  "changed=Package.swift" \
  env PATH="$FAKE_BIN:$PATH" XHUB_TEST_CALL_LOG="$CALL_LOG" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$changed_snapshot_root" \
    --xt-snapshot-inventory "$changed_inventory" \
    --workspace-root "$TMP_ROOT/workspace" \
    --out-json "$TMP_ROOT/changed-output.json"

make_snapshot symlink-snapshot
symlink_snapshot_root="$TMP_ROOT/symlink-snapshot/x-terminal"
symlink_inventory="$TMP_ROOT/symlink-snapshot.inventory.json"
ln -s Package.swift "$symlink_snapshot_root/unexpected-link"
expect_rejected \
  "snapshot symlink" \
  "snapshot symlinks are not allowed: unexpected-link" \
  env PATH="$FAKE_BIN:$PATH" XHUB_TEST_CALL_LOG="$CALL_LOG" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$symlink_snapshot_root" \
    --xt-snapshot-inventory "$symlink_inventory" \
    --workspace-root "$TMP_ROOT/workspace" \
    --out-json "$TMP_ROOT/symlink-output.json"

make_snapshot foreign-snapshot
foreign_snapshot_root="$TMP_ROOT/foreign-snapshot/x-terminal"
foreign_inventory="$TMP_ROOT/foreign-snapshot.inventory.json"
python3 - "$foreign_inventory" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
payload["source_repo_root_realpath"] = "/tmp/not-the-canonical-repository"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
expect_rejected \
  "foreign inventory origin" \
  "was not created from this canonical repository root" \
  env PATH="$FAKE_BIN:$PATH" XHUB_TEST_CALL_LOG="$CALL_LOG" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$foreign_snapshot_root" \
    --xt-snapshot-inventory "$foreign_inventory" \
    --workspace-root "$TMP_ROOT/workspace" \
    --out-json "$TMP_ROOT/foreign-output.json"

expect_rejected \
  "legacy XT bypass" \
  "XHUB_ALLOW_LEGACY_XTERMINAL_RUN is unsupported" \
  env XHUB_ALLOW_LEGACY_XTERMINAL_RUN=1 \
  bash "$WRAPPER" xt

expect_rejected \
  "arbitrary XT helper" \
  "XHUB_XT_SOURCE_HELPER is unsupported" \
  env XHUB_XT_SOURCE_HELPER="$TMP_ROOT/not-canonical.command" \
  bash "$WRAPPER" xt

expect_rejected \
  "snapshot without inventory" \
  "--xt-diagnostic-snapshot requires --xt-snapshot-inventory" \
  bash "$WRAPPER" xt --xt-diagnostic-snapshot "$clean_snapshot_root"

expect_rejected \
  "snapshot on Hub-only surface" \
  "XT diagnostic snapshots are only supported for the 'xt' or 'all' surfaces" \
  bash "$WRAPPER" hub \
    --xt-diagnostic-snapshot "$clean_snapshot_root" \
    --xt-snapshot-inventory "$clean_inventory"

expect_rejected \
  "snapshot workspace inside canonical repository" \
  "diagnostic workspace root must be outside the canonical repository root" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$clean_snapshot_root" \
    --xt-snapshot-inventory "$clean_inventory" \
    --workspace-root "$FIXTURE_ROOT" \
    --out-json "$TMP_ROOT/canonical-workspace-output.json"

expect_rejected \
  "snapshot output inside canonical repository" \
  "diagnostic output directory must be outside the canonical repository root" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$clean_snapshot_root" \
    --xt-snapshot-inventory "$clean_inventory" \
    --workspace-root "$TMP_ROOT/workspace" \
    --out-json "$FIXTURE_ROOT/doctor-output.json"

expect_rejected \
  "flag-shaped workspace value" \
  "diagnostic workspace root must be an absolute path" \
  bash "$WRAPPER" xt \
    --xt-diagnostic-snapshot "$clean_snapshot_root" \
    --xt-snapshot-inventory "$clean_inventory" \
    --workspace-root --xt-route-smoke \
    --out-json "$TMP_ROOT/flag-shaped-output.json"

expect_rejected \
  "non-doctor snapshot executable mode" \
  "unsupported diagnostic snapshot argument: --xt-route-smoke" \
  bash "$RUNNER" \
    --snapshot-root "$clean_snapshot_root" \
    --inventory "$clean_inventory" \
    --project-root "$TMP_ROOT/workspace" \
    --out-json "$TMP_ROOT/direct-runner-output.json" \
    --xt-route-smoke

for migrated_smoke in "$XT_SOURCE_SMOKE" "$ALL_SOURCE_SMOKE"; do
  if grep -Eq 'XHUB_ALLOW_LEGACY_XTERMINAL_RUN|XHUB_XT_SOURCE_HELPER' "$migrated_smoke"; then
    fail "source smoke still contains a legacy XT helper bypass: $migrated_smoke"
  fi
  grep -Fq 'scripts/lib/xt_doctor_snapshot_inventory.py" create' "$migrated_smoke" \
    || fail "source smoke does not create a canonical XT inventory: $migrated_smoke"
  grep -Fq 'bash "$ROOT_DIR/scripts/run_xhub_doctor_from_source.command"' "$migrated_smoke" \
    || fail "source smoke does not invoke the canonical wrapper: $migrated_smoke"
  grep -Fq -- '--xt-diagnostic-snapshot "$SNAPSHOT_DIR/x-terminal"' "$migrated_smoke" \
    || fail "source smoke does not select explicit XT snapshot mode: $migrated_smoke"
  grep -Fq -- '--xt-snapshot-inventory "$XT_SNAPSHOT_INVENTORY_PATH"' "$migrated_smoke" \
    || fail "source smoke does not pass its detached inventory: $migrated_smoke"
done

grep -Fq 'XHUB_HUB_SOURCE_HELPER="$SNAPSHOT_DIR/x-hub/tools/run_xhub_from_source.command"' "$ALL_SOURCE_SMOKE" \
  || fail "all-source smoke no longer exercises its Hub source snapshot"

echo "XT doctor diagnostic snapshot guard: PASS"
