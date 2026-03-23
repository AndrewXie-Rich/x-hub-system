#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
REPORT_DIR="${XT_W3_36_REPORT_DIR:-${ROOT_DIR}/build/reports}"
REPORT_FILE="${XT_W3_36_REPORT_FILE:-${REPORT_DIR}/xt_w3_36_project_governance_evidence.v1.json}"
LOG_DIR="${XT_W3_36_LOG_DIR:-${REPORT_DIR}/xt_w3_36_project_governance_logs}"
CASE_TABLE="${LOG_DIR}/cases.tsv"
BUILD_LOG="${LOG_DIR}/swift-build.log"
SWIFT_CHECK_HOME="${XT_W3_36_SWIFT_HOME:-${ROOT_DIR}/.axcoder/swift-home}"
SWIFT_CLANG_CACHE="${XT_W3_36_CLANG_MODULE_CACHE:-${ROOT_DIR}/.build/clang-module-cache}"
SWIFT_SCRATCH_PATH="${XT_W3_36_SWIFT_SCRATCH_PATH:-${ROOT_DIR}/.build/xt_w3_36_gate}"
SOURCE_SNAPSHOT_DIR="${XT_W3_36_SOURCE_SNAPSHOT_DIR:-${REPO_ROOT}/build/.xt_w3_36_source_snapshot}"
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
    --exclude '.xt_w3_36_source_snapshot' \
    --exclude '*/.xt_w3_36_source_snapshot' \
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
sync_file "${REPO_ROOT}/README.md" "${SOURCE_SNAPSHOT_DIR}/README.md"
sync_file "${REPO_ROOT}/X_MEMORY.md" "${SOURCE_SNAPSHOT_DIR}/X_MEMORY.md"

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
  "create_project_governance_transition" \
  "CreateProjectGovernanceTransitionTests" \
  "create flow keeps review cadence while enforcing minimum supervisor floor and normalized triggers" \
  "invalid_governance_combo_execution_count"

run_case \
  "project_governance_presentation_summary" \
  "ProjectGovernancePresentationSummaryTests" \
  "governance badge/home summary keeps invalid-warning-clamp messaging stable" \
  ""

run_case \
  "project_detail_governance_summary" \
  "ProjectDetailGovernanceSummaryTests" \
  "project detail summary keeps execution tier, supervisor tier, clamp, and guidance signals readable" \
  ""

run_case \
  "project_governance_docs_truth_sync" \
  "ProjectGovernanceDocsTruthSyncTests" \
  "docs truth stays aligned with A-tier/S-tier/Heartbeat-and-Review governance language" \
  ""

run_case \
  "project_model_capability_catalog" \
  "XTModelCatalogTests" \
  "model capability labels remain consistent across create/settings/detail surfaces" \
  ""

run_case \
  "project_model_routing_picker_state" \
  "HubModelRoutingPickerStateTests" \
  "shared routing picker state keeps explicit vs inherited model semantics stable" \
  ""

run_case \
  "supervisor_project_model_override_routing" \
  "SupervisorProjectModelOverrideRoutingTests" \
  "supervisor project override writes stay scoped to the selected project" \
  ""

run_case \
  "project_governance_activity_presentation" \
  "ProjectGovernanceActivityPresentationTests" \
  "governance activity timeline summary + pending ack visibility" \
  "guidance_without_ack_tracking"

run_case \
  "project_model_governance_binding" \
  "ProjectModelGovernanceBindingTests" \
  "multi-project card binding resolves stable project context before root fallback" \
  ""

run_case \
  "appmodel_multi_project_governance" \
  "AppModelMultiProjectGovernanceTests" \
  "new project creation paths stay conservative by default and do not reintroduce legacy overgrant" \
  "legacy_project_overgrant_after_migration"

run_case \
  "supervisor_auto_launch_policy" \
  "SupervisorAutoLaunchPolicyTests" \
  "one-shot auto-launch policy follows execution tier and refuses legacy shadow escalation" \
  "legacy_project_overgrant_after_migration"

run_case \
  "supervisor_multilane_flow" \
  "SupervisorMultilaneFlowTests" \
  "lane allocation and child project materialization prefer governance tiers over legacy autonomyLevel shadows" \
  "legacy_project_overgrant_after_migration"

run_case \
  "directed_unblock_router" \
  "DirectedUnblockRouterTests" \
  "directed unblock resume flow stays scoped after conservative governance default tightening" \
  ""

run_case \
  "supervisor_runtime_reliability_kernel" \
  "SupervisorRuntimeReliabilityKernelTests" \
  "runtime failure, cancel, and fallback cleanup paths stay deterministic under governed execution" \
  ""

run_case \
  "supervisor_auto_continue_executor" \
  "SupervisorAutoContinueExecutorTests" \
  "auto-continue resumes dependency-ready lanes without bypassing governed follow-up checkpoints" \
  ""

run_case \
  "supervisor_intake_acceptance" \
  "SupervisorIntakeAcceptanceTests" \
  "project intake and acceptance workflows keep governed bootstrap and fail-closed validation boundaries intact" \
  ""

run_case \
  "delivery_scope_freeze" \
  "DeliveryScopeFreezeTests" \
  "delivery freeze keeps validated scope boundaries fail-closed before governed continuation or replay" \
  ""

run_case \
  "task_assigner_governance" \
  "TaskAssignerGovernanceTests" \
  "task assignment prefers execution and supervisor governance tiers over misleading legacy autonomyLevel shadows" \
  "legacy_project_overgrant_after_migration"

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
const caseById = new Map(rows.map((row) => [row.case_id, row]));

function coverageItem(key, label, caseIds, capabilities) {
  const supportingCases = caseIds
    .map((caseId) => caseById.get(caseId))
    .filter(Boolean)
    .map((row) => ({
      case_id: row.case_id,
      filter: row.filter,
      status: row.status
    }));

  return {
    key,
    label,
    covered: supportingCases.length === caseIds.length && supportingCases.every((row) => row.status === "passed"),
    capabilities,
    supporting_cases: supportingCases
  };
}

const reviewGuidanceChain = [
  coverageItem(
    "review_policy_resolution",
    "Supervisor review policy resolution and event trigger scheduling",
    ["supervisor_review_policy_engine"],
    ["review_trigger_resolution", "intervention_policy_resolution"]
  ),
  coverageItem(
    "cadence_editing_and_visibility",
    "Review cadence editing and governance visibility stay aligned across create/settings/detail surfaces",
    [
      "project_settings_governance_ui",
      "create_project_governance_transition",
      "project_detail_governance_summary"
    ],
    ["review_cadence_editing", "trigger_normalization", "detail_visibility"]
  ),
  coverageItem(
    "guidance_queue_and_ack",
    "Guidance queue state, pending ack visibility, and ack durability remain tracked",
    [
      "project_governance_activity_presentation",
      "supervisor_guidance_injection_store"
    ],
    ["guidance_queue", "ack_tracking", "pending_ack_visibility"]
  ),
  coverageItem(
    "safe_point_delivery",
    "Guidance delivery respects safe-point boundaries before interruption",
    ["supervisor_safe_point_coordinator"],
    ["safe_point_delivery", "interrupt_boundary_control"]
  ),
  coverageItem(
    "dependency_ready_follow_up",
    "Dependency-ready auto-continue keeps governed follow-up checkpoints intact",
    ["supervisor_auto_continue_executor"],
    ["dependency_ready_resume", "follow_up_checkpoint_respect"]
  )
];
const reviewGuidanceCoveredCount = reviewGuidanceChain.filter((item) => item.covered).length;
const ingressRuntimeChain = [
  coverageItem(
    "intake_acceptance_boundaries",
    "Project intake, bootstrap binding, and acceptance validation stay fail-closed",
    ["supervisor_intake_acceptance"],
    ["project_intake_bootstrap_binding", "acceptance_fail_closed_validation"]
  ),
  coverageItem(
    "scope_freeze_enforcement",
    "Validated delivery scope freeze stays enforced before replay or governed continuation",
    ["delivery_scope_freeze"],
    ["validated_scope_freeze", "replay_scope_fail_closed"]
  ),
  coverageItem(
    "assignment_prefers_governance_tiers",
    "Lane and task assignment prefer execution/supervisor tiers over legacy autonomyLevel shadows",
    ["task_assigner_governance", "supervisor_multilane_flow"],
    ["task_assignment_governance", "lane_materialization_governance"]
  ),
  coverageItem(
    "creation_and_launch_overgrant_guard",
    "Project creation and one-shot launch paths refuse legacy-shadow overgrant",
    ["appmodel_multi_project_governance", "supervisor_auto_launch_policy"],
    ["conservative_project_creation", "one_shot_launch_overgrant_guard"]
  ),
  coverageItem(
    "runtime_capability_clamp",
    "Runtime capability clamp and deny paths stay governed at tool execution time",
    ["tool_runtime_governance_clamp", "tool_executor_runtime_policy"],
    ["runtime_capability_clamp", "tool_deny_path_governance"]
  )
];
const ingressRuntimeCoveredCount = ingressRuntimeChain.filter((item) => item.covered).length;
const reviewGuidanceCapabilities = Array.from(
  new Set(reviewGuidanceChain.flatMap((item) => item.capabilities || []))
);
const ingressRuntimeCapabilities = Array.from(
  new Set(ingressRuntimeChain.flatMap((item) => item.capabilities || []))
);
const governanceCoverageDigest = {
  review_guidance: {
    covered_count: reviewGuidanceCoveredCount,
    total_count: reviewGuidanceChain.length,
    covered_labels: reviewGuidanceChain.filter((item) => item.covered).map((item) => item.label),
    capabilities: reviewGuidanceCapabilities
  },
  ingress_runtime: {
    covered_count: ingressRuntimeCoveredCount,
    total_count: ingressRuntimeChain.length,
    covered_labels: ingressRuntimeChain.filter((item) => item.covered).map((item) => item.label),
    capabilities: ingressRuntimeCapabilities
  }
};
governanceCoverageDigest.human_summary_lines = [
  `review_guidance ${governanceCoverageDigest.review_guidance.covered_count}/${governanceCoverageDigest.review_guidance.total_count}: ${governanceCoverageDigest.review_guidance.covered_labels.join("; ")}`,
  `ingress_runtime ${governanceCoverageDigest.ingress_runtime.covered_count}/${governanceCoverageDigest.ingress_runtime.total_count}: ${governanceCoverageDigest.ingress_runtime.covered_labels.join("; ")}`
];

const report = {
  schema_version: "xt_w3_36_project_governance_evidence.v1",
  generated_at: process.env.generated_at,
  ok: process.env.overall_ok === "1",
  summary: {
    build_status: process.env.build_status,
    build_exit_code: Number(process.env.build_exit_code),
    passed_case_count: passedCount,
    failed_case_count: failedCount,
    review_guidance_covered_dimension_count: reviewGuidanceCoveredCount,
    review_guidance_total_dimension_count: reviewGuidanceChain.length,
    ingress_runtime_covered_dimension_count: ingressRuntimeCoveredCount,
    ingress_runtime_total_dimension_count: ingressRuntimeChain.length
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
  },
  coverage: {
    review_guidance_chain: reviewGuidanceChain,
    ingress_runtime_chain: ingressRuntimeChain
  },
  digest: {
    governance_coverage: governanceCoverageDigest
  }
};

fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`, "utf8");
NODE

echo "[xt-w3-36] report=${REPORT_FILE}"
if [[ "${overall_ok}" != "1" ]]; then
  echo "[xt-w3-36] governance evidence failed" >&2
  exit 1
fi
