#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${XT_W3_36_REPORT_DIR:-${ROOT_DIR}/build/reports}"
REPORT_FILE="${XT_W3_36_REPORT_FILE:-${REPORT_DIR}/xt_w3_36_project_governance_evidence.v1.json}"
LOG_DIR="${XT_W3_36_LOG_DIR:-${REPORT_DIR}/xt_w3_36_project_governance_logs}"
CASE_TABLE="${LOG_DIR}/cases.tsv"
BUILD_LOG="${LOG_DIR}/swift-build.log"
SWIFT_CHECK_HOME="${XT_W3_36_SWIFT_HOME:-${ROOT_DIR}/.axcoder/swift-home}"
SWIFT_CLANG_CACHE="${XT_W3_36_CLANG_MODULE_CACHE:-${ROOT_DIR}/.build/clang-module-cache}"

mkdir -p "${REPORT_DIR}" "${LOG_DIR}" "${SWIFT_CHECK_HOME}" "${SWIFT_CLANG_CACHE}"
: > "${CASE_TABLE}"

overall_ok=1
invalid_governance_combo_execution_count=0
guidance_without_ack_tracking=0
device_action_under_subminimum_supervision=0
legacy_project_overgrant_after_migration=0

record_metric_failures() {
  local metrics_csv="${1:-}"
  local metric
  local -a metric_list=()
  if [[ -n "${metrics_csv}" ]]; then
    IFS=',' read -r -a metric_list <<< "${metrics_csv}"
  fi
  if [[ ${#metric_list[@]} -eq 0 ]]; then
    return 0
  fi
  for metric in "${metric_list[@]}"; do
    case "${metric}" in
      invalid_governance_combo_execution_count)
        invalid_governance_combo_execution_count=1
        ;;
      guidance_without_ack_tracking)
        guidance_without_ack_tracking=1
        ;;
      device_action_under_subminimum_supervision)
        device_action_under_subminimum_supervision=1
        ;;
      legacy_project_overgrant_after_migration)
        legacy_project_overgrant_after_migration=1
        ;;
      "" )
        ;;
      * )
        echo "[xt-w3-36] warning: unknown metric key '${metric}'" >&2
        ;;
    esac
  done
}

run_case() {
  local case_id="$1"
  local filter="$2"
  local description="$3"
  local metrics_csv="$4"
  local log_file="${LOG_DIR}/${case_id}.log"
  local status="passed"
  local exit_code="0"
  local cmd_status="0"

  if (
    cd "${ROOT_DIR}"
    HOME="${SWIFT_CHECK_HOME}" \
    CLANG_MODULE_CACHE_PATH="${SWIFT_CLANG_CACHE}" \
      swift test --disable-sandbox --filter "${filter}" >"${log_file}" 2>&1
  ); then
    :
  else
    cmd_status="$?"
    status="failed"
    exit_code="${cmd_status}"
    overall_ok=0
    record_metric_failures "${metrics_csv}"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${case_id}" \
    "${filter}" \
    "${description}" \
    "${status}" \
    "${exit_code}" \
    "${log_file}" >> "${CASE_TABLE}"
}

build_status="passed"
build_exit_code="0"
if (
  cd "${ROOT_DIR}"
  HOME="${SWIFT_CHECK_HOME}" \
  CLANG_MODULE_CACHE_PATH="${SWIFT_CLANG_CACHE}" \
    swift build --disable-sandbox >"${BUILD_LOG}" 2>&1
); then
  :
else
  cmd_status="$?"
  build_status="failed"
  build_exit_code="${cmd_status}"
  overall_ok=0
fi

run_case \
  "project_governance_resolver" \
  "ProjectGovernanceResolverTests" \
  "resolver fail-closed + legacy migration compat" \
  "invalid_governance_combo_execution_count,legacy_project_overgrant_after_migration"

run_case \
  "project_settings_governance_ui" \
  "ProjectSettingsGovernanceUITests" \
  "governance UI explainability and draft warnings" \
  ""

run_case \
  "tool_runtime_governance_clamp" \
  "XTToolRuntimePolicyGovernanceClampTests" \
  "governance tier vs runtime clamp precedence" \
  "invalid_governance_combo_execution_count,device_action_under_subminimum_supervision"

run_case \
  "tool_executor_runtime_policy" \
  "ToolExecutorRuntimePolicyTests" \
  "end-to-end runtime policy deny path coverage" \
  "device_action_under_subminimum_supervision"

run_case \
  "supervisor_review_policy_engine" \
  "SupervisorReviewPolicyEngineTests" \
  "supervisor review scheduling + intervention policy" \
  ""

run_case \
  "supervisor_guidance_injection_store" \
  "SupervisorGuidanceInjectionStoreTests" \
  "guidance queue ack tracking durability" \
  "guidance_without_ack_tracking"

run_case \
  "supervisor_safe_point_coordinator" \
  "SupervisorSafePointCoordinatorTests" \
  "guidance delivery on safe-point boundaries" \
  "guidance_without_ack_tracking"

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
export REPORT_FILE CASE_TABLE BUILD_LOG generated_at build_status build_exit_code overall_ok
export invalid_governance_combo_execution_count guidance_without_ack_tracking
export device_action_under_subminimum_supervision legacy_project_overgrant_after_migration

node <<'NODE'
const fs = require("fs");

const reportFile = process.env.REPORT_FILE;
const caseTable = process.env.CASE_TABLE;
const rows = fs.readFileSync(caseTable, "utf8")
  .split("\n")
  .filter(Boolean)
  .map((line) => {
    const [caseId, filter, description, status, exitCode, logFile] = line.split("\t");
    return {
      case_id: caseId,
      filter,
      description,
      status,
      exit_code: Number(exitCode),
      log_file: logFile
    };
  });

const passedCount = rows.filter((row) => row.status === "passed").length;
const failedCount = rows.filter((row) => row.status !== "passed").length;

const report = {
  schema_version: "xt_w3_36_project_governance_evidence.v1",
  generated_at: process.env.generated_at,
  ok: process.env.overall_ok === "1",
  summary: {
    build_status: process.env.build_status,
    build_exit_code: Number(process.env.build_exit_code),
    passed_case_count: passedCount,
    failed_case_count: failedCount
  },
  metrics: {
    invalid_governance_combo_execution_count: Number(process.env.invalid_governance_combo_execution_count || "0"),
    guidance_without_ack_tracking: Number(process.env.guidance_without_ack_tracking || "0"),
    device_action_under_subminimum_supervision: Number(process.env.device_action_under_subminimum_supervision || "0"),
    legacy_project_overgrant_after_migration: Number(process.env.legacy_project_overgrant_after_migration || "0")
  },
  evidence: {
    build_log: process.env.BUILD_LOG,
    cases: rows
  }
};

fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`, "utf8");
NODE

echo "[xt-w3-36] report=${REPORT_FILE}"
