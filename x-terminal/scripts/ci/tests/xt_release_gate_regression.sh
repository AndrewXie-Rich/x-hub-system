#!/usr/bin/env bash
set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GATE_SCRIPT="${CI_DIR}/xt_release_gate.sh"
FIXTURE_DIR="${CI_DIR}/tests/fixtures"
MOCK_BIN_DIR="${FIXTURE_DIR}/mock-bin"
TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xt-release-gate-regression.XXXXXX")"
TEST_LOG="${TEST_TMP_DIR}/last-command.log"
pass_count=0

cleanup() {
  rm -rf "${TEST_TMP_DIR}"
}
trap cleanup EXIT

pass() {
  pass_count=$((pass_count + 1))
  printf '[xt-release-gate-regression] PASS: %s\n' "$1"
}

expect_pass() {
  local label="$1"
  shift
  if "$@" >"${TEST_LOG}" 2>&1; then
    pass "${label}"
    return 0
  fi
  echo "[xt-release-gate-regression] FAIL: ${label}" >&2
  sed -n '1,160p' "${TEST_LOG}" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local expected_pattern="$2"
  shift 2
  if "$@" >"${TEST_LOG}" 2>&1; then
    echo "[xt-release-gate-regression] FAIL: ${label} unexpectedly passed" >&2
    exit 1
  fi
  if ! rg -q --fixed-strings "${expected_pattern}" "${TEST_LOG}"; then
    echo "[xt-release-gate-regression] FAIL: ${label} did not emit ${expected_pattern}" >&2
    sed -n '1,160p' "${TEST_LOG}" >&2
    exit 1
  fi
  pass "${label}"
}

expect_pass \
  "baseline keeps its existing skip compatibility" \
  env XT_GATE_MODE=baseline XT_GATE_SKIP_BUILD=1 \
  bash "${GATE_SCRIPT}" --check-configuration

expect_pass \
  "strict accepts explicitly disabled skip variables" \
  env XT_GATE_MODE=strict XT_GATE_SKIP_BUILD=0 \
  bash "${GATE_SCRIPT}" --check-configuration

expect_fail \
  "strict refuses a known skip bypass" \
  "release-grade gate refuses XT_GATE_SKIP_* bypasses" \
  env XT_GATE_MODE=strict XT_GATE_SKIP_BUILD=1 \
  bash "${GATE_SCRIPT}" --check-configuration

expect_fail \
  "release preset refuses future unknown skip bypasses" \
  "XT_GATE_SKIP_FUTURE=1" \
  env XT_GATE_MODE=baseline XT_GATE_RELEASE_PRESET=1 XT_GATE_SKIP_FUTURE=1 \
  bash "${GATE_SCRIPT}" --check-configuration

expect_fail \
  "release-grade Doctor age cannot be relaxed beyond fifteen minutes" \
  "expected 1..900" \
  env XT_GATE_MODE=strict XT_GATE_UNIFIED_DOCTOR_MAX_AGE_SECONDS=901 \
  bash "${GATE_SCRIPT}" --check-configuration

expect_pass \
  "fresh ready unified Doctor with zero blockers passes" \
  bash "${GATE_SCRIPT}" --validate-unified-doctor \
  "${FIXTURE_DIR}/unified_doctor_ready.json" 900 1700000300000

expect_fail \
  "stale unified Doctor fails closed" \
  "unified Doctor is stale" \
  bash "${GATE_SCRIPT}" --validate-unified-doctor \
  "${FIXTURE_DIR}/unified_doctor_ready.json" 900 1700001000001

expect_fail \
  "blocking unified Doctor fails closed" \
  "blocking_count must be 0" \
  bash "${GATE_SCRIPT}" --validate-unified-doctor \
  "${FIXTURE_DIR}/unified_doctor_blocked.json" 900 1700000300000

expect_fail \
  "not-ready unified Doctor fails closed" \
  "readyForFirstTask must be true" \
  bash "${GATE_SCRIPT}" --validate-unified-doctor \
  "${FIXTURE_DIR}/unified_doctor_not_ready.json" 900 1700000300000

MOCK_LOG="${TEST_TMP_DIR}/mock-swift.log"
MOCK_COUNTER="${TEST_TMP_DIR}/mock-swift.counter"
STRICT_REPORT_DIR="${TEST_TMP_DIR}/strict-pass-reports"
STRICT_EVIDENCE="${STRICT_REPORT_DIR}/strict-evidence.json"

expect_pass \
  "strict pipeline compiles tests, runs three shards, then full swift test" \
  env \
  PATH="${MOCK_BIN_DIR}:${PATH}" \
  XT_GATE_MODE=strict \
  XT_GATE_INTERNAL_REGRESSION=1 \
  XT_GATE_REPORT_DIR="${STRICT_REPORT_DIR}" \
  XT_GATE_STRICT_TEST_EVIDENCE_FILE="${STRICT_EVIDENCE}" \
  XT_GATE_SWIFT_HOME="${TEST_TMP_DIR}/swift-home" \
  XT_GATE_CLANG_MODULE_CACHE="${TEST_TMP_DIR}/clang-cache" \
  XT_GATE_SWIFT_SCRATCH_PATH="${TEST_TMP_DIR}/swift-scratch" \
  XT_GATE_MOCK_SWIFT_LOG="${MOCK_LOG}" \
  XT_GATE_MOCK_SWIFT_COUNTER="${MOCK_COUNTER}" \
  bash "${GATE_SCRIPT}" --internal-test-strict-swift-pipeline

if [[ "$(wc -l < "${MOCK_LOG}" | tr -d '[:space:]')" != "5" ]]; then
  echo "[xt-release-gate-regression] FAIL: strict pipeline did not invoke Swift exactly five times" >&2
  exit 1
fi
if ! sed -n '1p' "${MOCK_LOG}" | rg -q --fixed-strings 'build --build-tests'; then
  echo "[xt-release-gate-regression] FAIL: first strict command did not compile the test target" >&2
  exit 1
fi
if ! sed -n '2,4p' "${MOCK_LOG}" | rg -q --fixed-strings -- '--filter'; then
  echo "[xt-release-gate-regression] FAIL: strict test shards did not use filters" >&2
  exit 1
fi
if sed -n '5p' "${MOCK_LOG}" | rg -q --fixed-strings -- '--filter'; then
  echo "[xt-release-gate-regression] FAIL: final swift test was filtered" >&2
  exit 1
fi
pass "strict Swift command ordering is fixed and the final test is unfiltered"

node -e '
const fs = require("fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (report.schema_version !== "xt.strict_test_evidence.v1") throw new Error("bad schema");
if (report.ok !== true || report.command_sequence_complete !== true) throw new Error("evidence not complete");
if (!/^[0-9a-f]{40,64}$/.test(report.source.commit)) throw new Error("commit missing");
if (typeof report.source.dirty !== "boolean") throw new Error("dirty must be boolean");
for (const key of ["sources_sha256", "tests_sha256", "sources_tests_sha256_before", "sources_tests_sha256_after"]) {
  if (!/^[0-9a-f]{64}$/.test(report.source[key])) throw new Error(`${key} missing`);
}
if (report.source.stable_during_test !== true) throw new Error("source hash changed");
if (report.commands.length !== 5 || report.commands.some((entry) => entry.exit_code !== 0)) {
  throw new Error("command exit evidence incomplete");
}
' "${STRICT_EVIDENCE}"
pass "strict evidence records commit, dirty state, source hashes, commands, and exit codes"

node -e '
const fs = require("fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (report.release_grade !== true || report.strict_test.status !== "pass") {
  throw new Error("strict result missing from report index");
}
if (report.source.commit.length < 40 || report.source.sources_sha256.length !== 64) {
  throw new Error("source truth missing from report index");
}
' "${STRICT_REPORT_DIR}/xt-report-index.json"
pass "report index carries release-grade source and strict-test evidence"

FAIL_MOCK_LOG="${TEST_TMP_DIR}/mock-swift-fail.log"
FAIL_MOCK_COUNTER="${TEST_TMP_DIR}/mock-swift-fail.counter"
FAIL_REPORT_DIR="${TEST_TMP_DIR}/strict-fail-reports"
FAIL_EVIDENCE="${FAIL_REPORT_DIR}/strict-evidence.json"

expect_fail \
  "non-zero full swift test exit fails the strict pipeline" \
  "internal strict test pipeline failed" \
  env \
  PATH="${MOCK_BIN_DIR}:${PATH}" \
  XT_GATE_MODE=strict \
  XT_GATE_INTERNAL_REGRESSION=1 \
  XT_GATE_REPORT_DIR="${FAIL_REPORT_DIR}" \
  XT_GATE_STRICT_TEST_EVIDENCE_FILE="${FAIL_EVIDENCE}" \
  XT_GATE_SWIFT_HOME="${TEST_TMP_DIR}/fail-swift-home" \
  XT_GATE_CLANG_MODULE_CACHE="${TEST_TMP_DIR}/fail-clang-cache" \
  XT_GATE_SWIFT_SCRATCH_PATH="${TEST_TMP_DIR}/fail-swift-scratch" \
  XT_GATE_MOCK_SWIFT_LOG="${FAIL_MOCK_LOG}" \
  XT_GATE_MOCK_SWIFT_COUNTER="${FAIL_MOCK_COUNTER}" \
  XT_GATE_MOCK_SWIFT_FAIL_AT=5 \
  XT_GATE_MOCK_SWIFT_FAIL_CODE=42 \
  bash "${GATE_SCRIPT}" --internal-test-strict-swift-pipeline

node -e '
const fs = require("fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (report.ok !== false) throw new Error("failed pipeline evidence must fail");
if (report.commands.length !== 5) throw new Error("failed pipeline must retain all commands");
if (report.commands[4].label !== "full swift test" || report.commands[4].exit_code !== 42) {
  throw new Error("full swift test exit code not retained");
}
' "${FAIL_EVIDENCE}"
pass "failed full-test exit code remains auditable"

printf '[xt-release-gate-regression] %s checks passed\n' "${pass_count}"
