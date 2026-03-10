#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${XT_GATE_REPORT_DIR:-${ROOT_DIR}/.axcoder/reports}"
VALID_FIXTURE="${XT_SPLIT_AUDIT_FIXTURE:-${ROOT_DIR}/scripts/fixtures/split_audit_payload_events.sample.json}"
INVALID_FIXTURE="${XT_SPLIT_AUDIT_INVALID_FIXTURE:-${ROOT_DIR}/scripts/fixtures/split_audit_payload_events.invalid.sample.json}"
REPORT_JSON="${XT_SPLIT_AUDIT_CONTRACT_REPORT:-${REPORT_DIR}/split-audit-contract-report.json}"
SKIP_SWIFT_TESTS="${XT_SPLIT_AUDIT_SKIP_SWIFT_TESTS:-0}"
SWIFT_CHECK_HOME="${XT_SPLIT_AUDIT_SWIFT_HOME:-${ROOT_DIR}/.axcoder/swift-home}"
SWIFT_CLANG_CACHE="${XT_SPLIT_AUDIT_CLANG_MODULE_CACHE:-${ROOT_DIR}/.build/clang-module-cache}"

mkdir -p "${REPORT_DIR}"
mkdir -p "${SWIFT_CHECK_HOME}" "${SWIFT_CLANG_CACHE}"

run_targeted_swift_test() {
  local test_filter="$1"
  (
    cd "${ROOT_DIR}"
    HOME="${SWIFT_CHECK_HOME}" \
    CLANG_MODULE_CACHE_PATH="${SWIFT_CLANG_CACHE}" \
      swift test --disable-sandbox --filter "${test_filter}"
  )
}

echo "[xt-split-audit-contract] validating fixture contract"
node "${ROOT_DIR}/scripts/check_split_audit_fixture_contract.js" \
  --fixture "${VALID_FIXTURE}" \
  --out-json "${REPORT_JSON}"

echo "[xt-split-audit-contract] validating negative fixture behavior"
if node "${ROOT_DIR}/scripts/check_split_audit_fixture_contract.js" --fixture "${INVALID_FIXTURE}"; then
  echo "[xt-split-audit-contract] expected invalid fixture to fail but it passed" >&2
  exit 1
fi

echo "[xt-split-audit-contract] running contract unit checks"
node "${ROOT_DIR}/scripts/check_split_audit_fixture_contract.test.js"

if [[ "${SKIP_SWIFT_TESTS}" == "1" ]]; then
  echo "[xt-split-audit-contract] skipping swift tests by XT_SPLIT_AUDIT_SKIP_SWIFT_TESTS=1"
else
  echo "[xt-split-audit-contract] running targeted decoder regression tests"
  run_targeted_swift_test "OrchestratorAuditPayloadTests/decodeResultReturnsActionableErrorCodes"
  run_targeted_swift_test "OrchestratorAuditPayloadTests/decodeAndDecodeResultStayConsistentForFixtureEvents"
  run_targeted_swift_test "OrchestratorAuditPayloadTests/invalidFixtureEventsAreRejectedByDecoder"
fi

echo "[xt-split-audit-contract] all checks passed"
