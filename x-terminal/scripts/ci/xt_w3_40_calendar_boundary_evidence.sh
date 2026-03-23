#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
REPORT_DIR="${XT_W3_40_REPORT_DIR:-${ROOT_DIR}/build/reports}"
REPORT_FILE="${XT_W3_40_REPORT_FILE:-${REPORT_DIR}/xt_w3_40_calendar_boundary_evidence.v1.json}"
LOG_DIR="${XT_W3_40_LOG_DIR:-${REPORT_DIR}/xt_w3_40_calendar_boundary_logs}"
CASE_TABLE="${LOG_DIR}/cases.tsv"
BUILD_LOG="${LOG_DIR}/swift-build.log"
SWIFT_CHECK_HOME="${XT_W3_40_SWIFT_HOME:-${ROOT_DIR}/.axcoder/swift-home}"
SWIFT_CLANG_CACHE="${XT_W3_40_CLANG_MODULE_CACHE:-${ROOT_DIR}/.build/clang-module-cache}"
SWIFT_SCRATCH_PATH="${XT_W3_40_SWIFT_SCRATCH_PATH:-${ROOT_DIR}/.build/xt_w3_40_gate}"
SOURCE_SNAPSHOT_DIR="${XT_W3_40_SOURCE_SNAPSHOT_DIR:-${REPO_ROOT}/build/.xt_w3_40_source_snapshot}"
PACKAGE_ROOT="${SOURCE_SNAPSHOT_DIR}/x-terminal"

mkdir -p "${REPORT_DIR}" "${SWIFT_CHECK_HOME}" "${SWIFT_CLANG_CACHE}" "${SWIFT_SCRATCH_PATH}"
rm -rf "${LOG_DIR}"
mkdir -p "${LOG_DIR}"
: > "${CASE_TABLE}"
rm -f "${REPORT_FILE}"

rm -rf "${SOURCE_SNAPSHOT_DIR}"
mkdir -p "${SOURCE_SNAPSHOT_DIR}"

sync_tree() {
  local source_path="$1"
  local destination_path="$2"
  mkdir -p "$(dirname "${destination_path}")"
  rsync -a --delete \
    --exclude '.git' \
    --exclude '*/.git' \
    --exclude '.axcoder' \
    --exclude '*/.axcoder' \
    --exclude '.ax-test-cache' \
    --exclude '*/.ax-test-cache' \
    --exclude '.scratch' \
    --exclude '*/.scratch' \
    --exclude '.scratch-*' \
    --exclude '*/.scratch-*' \
    --exclude '.scratch-memory*' \
    --exclude '*/.scratch-memory*' \
    --exclude '.scratch-registry' \
    --exclude '*/.scratch-registry' \
    --exclude '.sandbox_home' \
    --exclude '*/.sandbox_home' \
    --exclude '.sandbox_tmp' \
    --exclude '*/.sandbox_tmp' \
    --exclude '.clang-module-cache' \
    --exclude '*/.clang-module-cache' \
    --exclude '.swift-module-cache' \
    --exclude '*/.swift-module-cache' \
    --exclude '.build' \
    --exclude '*/.build' \
    --exclude 'build' \
    --exclude '*/build' \
    --exclude '.xt_w3_40_source_snapshot' \
    --exclude '*/.xt_w3_40_source_snapshot' \
    --exclude '.swiftpm' \
    --exclude '*/.swiftpm' \
    --exclude '.DS_Store' \
    --exclude '*/.DS_Store' \
    --exclude 'node_modules' \
    --exclude '*/node_modules' \
    "${source_path}" "${destination_path}"
}

sync_file() {
  local source_path="$1"
  local destination_path="$2"
  mkdir -p "$(dirname "${destination_path}")"
  cp -f "${source_path}" "${destination_path}"
}

sync_tree "${REPO_ROOT}/x-terminal/" "${SOURCE_SNAPSHOT_DIR}/x-terminal/"
sync_tree "${REPO_ROOT}/docs/" "${SOURCE_SNAPSHOT_DIR}/docs/"
sync_tree "${REPO_ROOT}/x-hub/macos/app_template/" "${SOURCE_SNAPSHOT_DIR}/x-hub/macos/app_template/"
sync_tree "${REPO_ROOT}/x-hub/macos/RELFlowHub/Sources/RELFlowHub/" "${SOURCE_SNAPSHOT_DIR}/x-hub/macos/RELFlowHub/Sources/RELFlowHub/"
sync_tree "${REPO_ROOT}/x-hub/tools/" "${SOURCE_SNAPSHOT_DIR}/x-hub/tools/"
sync_file "${REPO_ROOT}/X_MEMORY.md" "${SOURCE_SNAPSHOT_DIR}/X_MEMORY.md"

overall_ok=1

run_case() {
  local case_id="$1"
  local filter="$2"
  local description="$3"
  local log_file="${LOG_DIR}/${case_id}.log"
  local status="passed"
  local exit_code="0"
  local cmd_status="0"

  if (
    cd "${PACKAGE_ROOT}"
    HOME="${SWIFT_CHECK_HOME}" \
    CLANG_MODULE_CACHE_PATH="${SWIFT_CLANG_CACHE}" \
      swift test --disable-sandbox --skip-build --scratch-path "${SWIFT_SCRATCH_PATH}" --filter "${filter}" >"${log_file}" 2>&1
  ); then
    :
  else
    cmd_status="$?"
    status="failed"
    exit_code="${cmd_status}"
    overall_ok=0
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
  cd "${PACKAGE_ROOT}"
  HOME="${SWIFT_CHECK_HOME}" \
  CLANG_MODULE_CACHE_PATH="${SWIFT_CLANG_CACHE}" \
    swift build --disable-sandbox --build-tests --scratch-path "${SWIFT_SCRATCH_PATH}" >"${BUILD_LOG}" 2>&1
); then
  :
else
  cmd_status="$?"
  build_status="failed"
  build_exit_code="${cmd_status}"
  overall_ok=0
fi

run_case \
  "calendar_boundary_docs_truth_sync" \
  "XTCalendarBoundaryDocsTruthSyncTests" \
  "hub/xt calendar ownership boundary stays aligned across templates, surfaces, and docs"

run_case \
  "calendar_privacy_targets" \
  "XTSystemSettingsPrivacyTargetTests" \
  "calendar privacy deep links keep legacy and extension forms"

run_case \
  "calendar_settings_defaults" \
  "calendarReminderSettingsDefaultToXtOwnedMeetingReminderProfile" \
  "xt settings default to XT-owned calendar reminder preferences"

run_case \
  "calendar_doctor_readiness" \
  "XTUnifiedDoctorCalendarReminderReadinessTests" \
  "xt unified doctor classifies xt-owned calendar reminder readiness from optional-off through permission repair"

run_case \
  "calendar_doctor_output_projection" \
  "XTCalendarDoctorOutputProjectionTests" \
  "xt doctor export projects calendar readiness into machine-readable checks and next steps"

run_case \
  "calendar_reminder_scheduler" \
  "SupervisorCalendarReminderSchedulerTests" \
  "meeting phase windows, dedupe, and all-day suppression stay stable"

run_case \
  "calendar_voice_bridge" \
  "SupervisorCalendarVoiceBridgeTests" \
  "voice preview, live delivery routing, and notification fallback stay stable"

REPORT_FILE="${REPORT_FILE}" CASE_TABLE="${CASE_TABLE}" BUILD_LOG="${BUILD_LOG}" \
build_status="${build_status}" build_exit_code="${build_exit_code}" overall_ok="${overall_ok}" \
node <<'NODE'
const fs = require("fs");

const reportFile = process.env.REPORT_FILE;
const rows = fs
  .readFileSync(process.env.CASE_TABLE, "utf8")
  .trim()
  .split("\n")
  .filter(Boolean)
  .map((line) => {
    const [case_id, filter, description, status, exit_code, log_file] = line.split("\t");
    return {
      case_id,
      filter,
      description,
      status,
      exit_code: Number(exit_code || "0"),
      log_file
    };
  });

const passedCount = rows.filter((row) => row.status === "passed").length;
const failedCount = rows.filter((row) => row.status !== "passed").length;

const coverageChain = [
  {
    id: "template_permission_boundary",
    label: "Hub stays calendar-permission-free while XT owns calendar permission strings and entitlements",
    covered_by: ["calendar_boundary_docs_truth_sync"]
  },
  {
    id: "calendar_privacy_repair_entry",
    label: "XT keeps working Calendar privacy deep links for repair UX",
    covered_by: ["calendar_privacy_targets"]
  },
  {
    id: "calendar_settings_defaults",
    label: "XT settings keep conservative calendar reminder defaults",
    covered_by: ["calendar_settings_defaults"]
  },
  {
    id: "calendar_doctor_readiness_projection",
    label: "XT unified doctor keeps XT-owned calendar reminder readiness and export projection aligned",
    covered_by: ["calendar_doctor_readiness", "calendar_doctor_output_projection"]
  },
  {
    id: "scheduler_phase_and_dedupe",
    label: "Reminder scheduler keeps phase windows and duplicate suppression stable",
    covered_by: ["calendar_reminder_scheduler"]
  },
  {
    id: "voice_route_and_notification_fallback",
    label: "Voice reminder routing keeps quiet-hours fallback and simulated live delivery stable",
    covered_by: ["calendar_voice_bridge"]
  }
].map((item) => ({
  ...item,
  covered: item.covered_by.every((caseId) => rows.some((row) => row.case_id === caseId && row.status === "passed"))
}));

const coveredCount = coverageChain.filter((item) => item.covered).length;
const digest = `${coveredCount}/${coverageChain.length} calendar boundary dimensions covered`;

const report = {
  schema_version: "xt_w3_40_calendar_boundary_evidence.v1",
  generated_at: new Date().toISOString(),
  ok: process.env.overall_ok === "1",
  summary: {
    build_status: process.env.build_status,
    build_exit_code: Number(process.env.build_exit_code || "0"),
    passed_case_count: passedCount,
    failed_case_count: failedCount,
    covered_dimension_count: coveredCount,
    total_dimension_count: coverageChain.length
  },
  digest: {
    human_summary: digest
  },
  evidence: {
    build_log: process.env.BUILD_LOG,
    cases: rows
  },
  coverage: {
    calendar_boundary_chain: coverageChain
  }
};

fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`, "utf8");
NODE

echo "[xt-w3-40] report=${REPORT_FILE}"
if [[ "${overall_ok}" != "1" ]]; then
  echo "[xt-w3-40] calendar boundary evidence failed" >&2
  exit 1
fi
