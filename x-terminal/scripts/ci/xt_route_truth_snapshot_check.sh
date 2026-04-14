#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${XT_GATE_REPORT_DIR:-${ROOT_DIR}/.axcoder/reports}"
REPORT_JSON="${XT_ROUTE_TRUTH_REPORT_JSON:-${REPORT_DIR}/xt-route-truth-snapshot-report.json}"
SNAPSHOT_DIR="${XT_ROUTE_TRUTH_SNAPSHOT_DIR:-$(mktemp -d /tmp/xterminal_route_truth_snapshot.XXXXXX)}"
SCRATCH_DIR="${XT_ROUTE_TRUTH_SCRATCH_DIR:-/tmp/xt_route_truth_snapshot_checks}"
KEEP_SNAPSHOT="${XT_ROUTE_TRUTH_KEEP_SNAPSHOT:-0}"
SWIFT_CHECK_HOME="${XT_ROUTE_TRUTH_SWIFT_HOME:-${SNAPSHOT_DIR}/.axcoder/swift-home}"
SWIFT_CLANG_CACHE="${XT_ROUTE_TRUTH_CLANG_MODULE_CACHE:-${SNAPSHOT_DIR}/.build/clang-module-cache}"

TEST_FILTERS=(
  "LaneAllocatorRouteTruthTests"
  "TaskAssignerGovernanceTests"
  "SupervisorOrchestratorRouteTruthTests"
)

if [[ -n "${XT_ROUTE_TRUTH_TEST_FILTERS:-}" ]]; then
  IFS=',' read -r -a TEST_FILTERS <<< "${XT_ROUTE_TRUTH_TEST_FILTERS}"
fi

cleanup() {
  if [[ "${KEEP_SNAPSHOT}" == "1" ]]; then
    printf '[xt-route-truth] keeping snapshot: %s\n' "${SNAPSHOT_DIR}"
    return
  fi

  rm -rf "${SNAPSHOT_DIR}"
}

trap cleanup EXIT

mkdir -p "${REPORT_DIR}"

printf '[xt-route-truth] source root: %s\n' "${ROOT_DIR}"
printf '[xt-route-truth] snapshot root: %s\n' "${SNAPSHOT_DIR}"
printf '[xt-route-truth] scratch path: %s\n' "${SCRATCH_DIR}"

rm -rf "${SNAPSHOT_DIR}"
mkdir -p "${SNAPSHOT_DIR}"
rm -rf "${SCRATCH_DIR}"

rsync -a --delete \
  --exclude '.build' \
  --exclude '.git' \
  --exclude '.ax-test-cache' \
  "${ROOT_DIR}/" "${SNAPSHOT_DIR}/"

mkdir -p "${SWIFT_CHECK_HOME}" "${SWIFT_CLANG_CACHE}"

build_log="/tmp/xt_route_truth_snapshot_build.log"
printf '[xt-route-truth] swift build in snapshot\n'
(
  cd "${SNAPSHOT_DIR}" &&
    HOME="${SWIFT_CHECK_HOME}" \
    CLANG_MODULE_CACHE_PATH="${SWIFT_CLANG_CACHE}" \
      swift build --disable-sandbox --scratch-path "${SCRATCH_DIR}"
) | tee "${build_log}"

results_json="[]"
for test_filter in "${TEST_FILTERS[@]}"; do
  safe_name="$(printf '%s' "${test_filter}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_')"
  test_log="/tmp/${safe_name}.log"

  printf '[xt-route-truth] swift test --filter %s\n' "${test_filter}"
  (
    cd "${SNAPSHOT_DIR}" &&
      HOME="${SWIFT_CHECK_HOME}" \
      CLANG_MODULE_CACHE_PATH="${SWIFT_CLANG_CACHE}" \
        swift test --disable-sandbox --scratch-path "${SCRATCH_DIR}" --filter "${test_filter}"
  ) | tee "${test_log}"

  escaped_log_path="${test_log//\"/\\\"}"
  escaped_filter="${test_filter//\"/\\\"}"
  results_json="$(RESULTS_JSON="${results_json}" TEST_FILTER="${escaped_filter}" TEST_LOG="${escaped_log_path}" node - <<'NODE'
const results = JSON.parse(process.env.RESULTS_JSON || "[]");
results.push({
  filter: process.env.TEST_FILTER || "",
  status: "pass",
  log_path: process.env.TEST_LOG || ""
});
process.stdout.write(JSON.stringify(results));
NODE
)"
done

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
escaped_root="${ROOT_DIR//\"/\\\"}"
escaped_snapshot="${SNAPSHOT_DIR//\"/\\\"}"
escaped_scratch="${SCRATCH_DIR//\"/\\\"}"
escaped_build_log="${build_log//\"/\\\"}"

REPORT_JSON_PATH="${REPORT_JSON}" \
REPORT_GENERATED_AT="${generated_at}" \
REPORT_ROOT="${escaped_root}" \
REPORT_SNAPSHOT="${escaped_snapshot}" \
REPORT_SCRATCH="${escaped_scratch}" \
REPORT_BUILD_LOG="${escaped_build_log}" \
REPORT_SWIFT_HOME="${SWIFT_CHECK_HOME}" \
REPORT_CLANG_CACHE="${SWIFT_CLANG_CACHE}" \
REPORT_RESULTS="${results_json}" \
node - <<'NODE'
const fs = require("fs");
const path = require("path");

const reportPath = process.env.REPORT_JSON_PATH || "";
if (!reportPath) {
  throw new Error("missing REPORT_JSON_PATH");
}

const report = {
  schema_version: "xt.route_truth_snapshot_check.v1",
  generated_at: process.env.REPORT_GENERATED_AT || "",
  source_root: process.env.REPORT_ROOT || "",
  snapshot_root: process.env.REPORT_SNAPSHOT || "",
  scratch_path: process.env.REPORT_SCRATCH || "",
  build_log_path: process.env.REPORT_BUILD_LOG || "",
  swift_home: process.env.REPORT_SWIFT_HOME || "",
  clang_module_cache_path: process.env.REPORT_CLANG_CACHE || "",
  tests: JSON.parse(process.env.REPORT_RESULTS || "[]")
};

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
NODE

printf '[xt-route-truth] report written: %s\n' "${REPORT_JSON}"
printf '[xt-route-truth] all checks passed\n'
