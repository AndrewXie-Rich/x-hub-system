#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xhub-release-inputs.XXXXXX")"
pass_count=0

cleanup() {
  case "$FIXTURE_ROOT" in
    "${TMPDIR:-/tmp}"/xhub-release-inputs.*) rm -rf -- "$FIXTURE_ROOT" ;;
  esac
}
trap cleanup EXIT

pass() {
  pass_count=$((pass_count + 1))
  printf '[release-inputs-test] PASS: %s\n' "$1"
}

expect_pass() {
  local label="$1"
  if "$FIXTURE_ROOT/scripts/package_macos_release.command" \
    --check-release-inputs >"$FIXTURE_ROOT/run.log" 2>&1; then
    pass "$label"
    return
  fi
  echo "[release-inputs-test] FAIL: $label" >&2
  sed -n '1,160p' "$FIXTURE_ROOT/run.log" >&2
  exit 1
}

expect_fail_path() {
  local label="$1"
  local expected_path="$2"
  if "$FIXTURE_ROOT/scripts/package_macos_release.command" \
    --check-release-inputs >"$FIXTURE_ROOT/run.log" 2>&1; then
    echo "[release-inputs-test] FAIL: $label unexpectedly passed" >&2
    exit 1
  fi
  if ! rg -q --fixed-strings "$expected_path" "$FIXTURE_ROOT/run.log"; then
    echo "[release-inputs-test] FAIL: $label did not report $expected_path" >&2
    sed -n '1,160p' "$FIXTURE_ROOT/run.log" >&2
    exit 1
  fi
  pass "$label"
}

mkdir -p \
  "$FIXTURE_ROOT/scripts" \
  "$FIXTURE_ROOT/x-terminal/scripts/lib" \
  "$FIXTURE_ROOT/x-terminal/tools" \
  "$FIXTURE_ROOT/x-terminal/Sources" \
  "$FIXTURE_ROOT/x-terminal/Tests" \
  "$FIXTURE_ROOT/rust/xhubd/tools" \
  "$FIXTURE_ROOT/rust/xhubd/skills/sample" \
  "$FIXTURE_ROOT/rust/xhubd/migrations"
cp "$REPOSITORY_ROOT/scripts/package_macos_release.command" \
  "$FIXTURE_ROOT/scripts/package_macos_release.command"
cp "$REPOSITORY_ROOT/x-terminal/scripts/lib/canonical_root_guard.sh" \
  "$FIXTURE_ROOT/x-terminal/scripts/lib/canonical_root_guard.sh"
cp "$REPOSITORY_ROOT/x-terminal/scripts/lib/release_codesign_guard.sh" \
  "$FIXTURE_ROOT/x-terminal/scripts/lib/release_codesign_guard.sh"
touch \
  "$FIXTURE_ROOT/x-terminal/Package.swift" \
  "$FIXTURE_ROOT/x-terminal/Sources/Tracked.swift" \
  "$FIXTURE_ROOT/x-terminal/Tests/TrackedTests.swift" \
  "$FIXTURE_ROOT/x-terminal/tools/build_xterminal_app.command" \
  "$FIXTURE_ROOT/rust/xhubd/Cargo.toml" \
  "$FIXTURE_ROOT/rust/xhubd/skills/sample/SKILL.md" \
  "$FIXTURE_ROOT/rust/xhubd/migrations/0001_tracked.sql" \
  "$FIXTURE_ROOT/rust/xhubd/tools/package_rust_hub.command"
cat >"$FIXTURE_ROOT/.gitignore" <<'EOF'
.axcoder/
.build/
.scratch/
build/
data/
archive/
target/
dist/
EOF

git -C "$FIXTURE_ROOT" init -q
git -C "$FIXTURE_ROOT" add \
  .gitignore \
  scripts/package_macos_release.command \
  x-terminal/Package.swift \
  x-terminal/Sources/Tracked.swift \
  x-terminal/Tests/TrackedTests.swift \
  x-terminal/scripts/lib/canonical_root_guard.sh \
  x-terminal/scripts/lib/release_codesign_guard.sh \
  x-terminal/tools/build_xterminal_app.command \
  rust/xhubd/Cargo.toml \
  rust/xhubd/skills/sample/SKILL.md \
  rust/xhubd/migrations/0001_tracked.sql \
  rust/xhubd/tools/package_rust_hub.command

mkdir -p \
  "$FIXTURE_ROOT/build/cache" \
  "$FIXTURE_ROOT/x-terminal/.axcoder/reports" \
  "$FIXTURE_ROOT/x-terminal/.build/cache" \
  "$FIXTURE_ROOT/x-terminal/.scratch/cache" \
  "$FIXTURE_ROOT/rust/xtd/target/release" \
  "$FIXTURE_ROOT/rust/xhubd/target/release" \
  "$FIXTURE_ROOT/rust/xhubd/dist/old"
touch \
  "$FIXTURE_ROOT/build/cache/output" \
  "$FIXTURE_ROOT/x-terminal/.axcoder/reports/report.json" \
  "$FIXTURE_ROOT/x-terminal/.build/cache/output" \
  "$FIXTURE_ROOT/x-terminal/.scratch/cache/output" \
  "$FIXTURE_ROOT/rust/xtd/target/release/xtd" \
  "$FIXTURE_ROOT/rust/xhubd/target/release/xhubd" \
  "$FIXTURE_ROOT/rust/xhubd/dist/old/provenance.json"
expect_pass "normal generated caches remain outside the build-material guard"

mkdir -p "$FIXTURE_ROOT/x-terminal/Sources/archive"
touch "$FIXTURE_ROOT/x-terminal/Sources/archive/Injected.swift"
expect_fail_path \
  "ignored XT source is rejected" \
  "x-terminal/Sources/archive/"
rm -rf -- "$FIXTURE_ROOT/x-terminal/Sources/archive"

mkdir -p "$FIXTURE_ROOT/x-terminal/Tests/data"
touch "$FIXTURE_ROOT/x-terminal/Tests/data/InjectedTests.swift"
expect_fail_path \
  "ignored XT test source is rejected" \
  "x-terminal/Tests/data/"
rm -rf -- "$FIXTURE_ROOT/x-terminal/Tests/data"

mkdir -p "$FIXTURE_ROOT/rust/xhubd/skills/sample/data"
touch "$FIXTURE_ROOT/rust/xhubd/skills/sample/data/extra"
expect_fail_path \
  "ignored packaged skill material is rejected" \
  "rust/xhubd/skills/sample/data/"
rm -rf -- "$FIXTURE_ROOT/rust/xhubd/skills/sample/data"

printf '%s\n' "rust/xhubd/migrations/0999_injected.sql" \
  >>"$FIXTURE_ROOT/.git/info/exclude"
touch "$FIXTURE_ROOT/rust/xhubd/migrations/0999_injected.sql"
expect_fail_path \
  "git-info-excluded migration is rejected" \
  "rust/xhubd/migrations/0999_injected.sql"

printf '[release-inputs-test] %d checks passed\n' "$pass_count"
