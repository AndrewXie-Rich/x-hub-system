#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${XT_W3_24_S_GATE_REPORT_DIR:-${ROOT_DIR}/build/reports}"
LOG_DIR="${XT_W3_24_S_GATE_LOG_DIR:-${REPORT_DIR}/xt_w3_24_s_safe_onboarding_gate_logs}"
SUMMARY_PATH="${XT_W3_24_S_GATE_SUMMARY_PATH:-${REPORT_DIR}/xt_w3_24_s_safe_onboarding_gate_summary.v1.json}"
TRACKED_EVIDENCE_PATH="${XT_W3_24_S_TRACKED_EVIDENCE_PATH:-${ROOT_DIR}/docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json}"
GENERATED_AT="${XT_W3_24_S_GENERATED_AT:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
SWIFT_GATE_HOME="${XT_W3_24_S_SWIFT_HOME:-${REPORT_DIR}/xt_w3_24_s_swift_home}"
SWIFT_GATE_CACHE_DIR="${XT_W3_24_S_SWIFT_CACHE_DIR:-${REPORT_DIR}/xt_w3_24_s_swift_cache}"

mkdir -p "${REPORT_DIR}" "${LOG_DIR}"
mkdir -p \
  "${SWIFT_GATE_HOME}" \
  "${SWIFT_GATE_CACHE_DIR}" \
  "${SWIFT_GATE_CACHE_DIR}/clang-module-cache" \
  "${SWIFT_GATE_CACHE_DIR}/swiftpm-module-cache"

swift_test_env_command="env HOME=\"${SWIFT_GATE_HOME}\" XDG_CACHE_HOME=\"${SWIFT_GATE_CACHE_DIR}\" CLANG_MODULE_CACHE_PATH=\"${SWIFT_GATE_CACHE_DIR}/clang-module-cache\" SWIFTPM_MODULECACHE_OVERRIDE=\"${SWIFT_GATE_CACHE_DIR}/swiftpm-module-cache\" swift test"

overall_status="pass"
pass_count=0
fail_count=0

live_test_step_status="not_run"
live_test_step_log="${LOG_DIR}/hub_live_test_evidence.log"
live_test_step_command="node x-hub/grpc-server/hub_grpc_server/src/operator_channel_live_test_evidence.test.js"

admin_http_step_status="not_run"
admin_http_step_log="${LOG_DIR}/hub_admin_http_live_test.log"
admin_http_step_command="node x-hub/grpc-server/hub_grpc_server/src/channel_onboarding_admin_http.test.js"

recovery_report_step_status="not_run"
recovery_report_step_log="${LOG_DIR}/operator_channel_recovery_report.log"
recovery_report_step_command="node scripts/generate_xhub_operator_channel_recovery_report.test.js"

pairing_replay_step_status="not_run"
pairing_replay_step_log="${LOG_DIR}/pairing_http_preauth_replay.log"
pairing_replay_step_command="node x-hub/grpc-server/hub_grpc_server/src/pairing_http_preauth_replay.test.js"

swift_onboarding_step_status="not_run"
swift_onboarding_step_log="${LOG_DIR}/swift_operator_channels_onboarding_support.log"
swift_onboarding_step_command="cd x-hub/macos/RELFlowHub && ${swift_test_env_command} --filter OperatorChannelsOnboardingSupportTests"

swift_model_library_section_step_status="not_run"
swift_model_library_section_step_log="${LOG_DIR}/swift_model_library_section_planner.log"
swift_model_library_section_step_command="cd x-hub/macos/RELFlowHub && ${swift_test_env_command} --filter ModelLibrarySectionPlannerTests"

swift_model_library_usage_step_status="not_run"
swift_model_library_usage_step_log="${LOG_DIR}/swift_model_library_usage_description_builder.log"
swift_model_library_usage_step_command="cd x-hub/macos/RELFlowHub && ${swift_test_env_command} --filter ModelLibraryUsageDescriptionBuilderTests"

evidence_generator_test_step_status="not_run"
evidence_generator_test_step_log="${LOG_DIR}/safe_onboarding_evidence_generator_test.log"
evidence_generator_test_step_command="node scripts/generate_xt_w3_24_s_safe_onboarding_release_evidence.test.js"

evidence_refresh_step_status="not_run"
evidence_refresh_step_log="${LOG_DIR}/safe_onboarding_evidence_refresh.log"
evidence_refresh_step_command="node scripts/generate_xt_w3_24_s_safe_onboarding_release_evidence.js --out \"${TRACKED_EVIDENCE_PATH}\" --generated-at \"${GENERATED_AT}\""

run_step() {
  local step_id="$1"
  local description="$2"
  local log_path="$3"
  local command="$4"

  echo "[xt-w3-24-s-gate] start step=${step_id} description=${description}"
  if (
    cd "${ROOT_DIR}"
    bash -lc "${command}"
  ) >"${log_path}" 2>&1; then
    echo "[xt-w3-24-s-gate] pass step=${step_id} log=${log_path}"
    pass_count=$((pass_count + 1))
    return 0
  fi

  echo "[xt-w3-24-s-gate] fail step=${step_id} log=${log_path}" >&2
  echo "[xt-w3-24-s-gate] last_log_lines step=${step_id}" >&2
  tail -n 40 "${log_path}" >&2 || true
  fail_count=$((fail_count + 1))
  overall_status="fail"
  return 1
}

if run_step \
  "hub_live_test_evidence" \
  "Hub live-test evidence repair-next-step regression" \
  "${live_test_step_log}" \
  "${live_test_step_command}"; then
  live_test_step_status="pass"
else
  live_test_step_status="fail"
fi

if run_step \
  "hub_admin_http_live_test" \
  "Hub admin HTTP live-test evidence regression" \
  "${admin_http_step_log}" \
  "${admin_http_step_command}"; then
  admin_http_step_status="pass"
else
  admin_http_step_status="fail"
fi

if run_step \
  "operator_channel_recovery_report" \
  "Operator channel recovery summary regression" \
  "${recovery_report_step_log}" \
  "${recovery_report_step_command}"; then
  recovery_report_step_status="pass"
else
  recovery_report_step_status="fail"
fi

if run_step \
  "pairing_http_preauth_replay" \
  "Pairing preauth replay fail-closed regression" \
  "${pairing_replay_step_log}" \
  "${pairing_replay_step_command}"; then
  pairing_replay_step_status="pass"
else
  pairing_replay_step_status="fail"
fi

if run_step \
  "swift_operator_channels_onboarding_support" \
  "RELFlowHub Swift onboarding evidence parity" \
  "${swift_onboarding_step_log}" \
  "${swift_onboarding_step_command}"; then
  swift_onboarding_step_status="pass"
else
  swift_onboarding_step_status="fail"
fi

if run_step \
  "swift_model_library_section_planner" \
  "RELFlowHub model library section planner regression" \
  "${swift_model_library_section_step_log}" \
  "${swift_model_library_section_step_command}"; then
  swift_model_library_section_step_status="pass"
else
  swift_model_library_section_step_status="fail"
fi

if run_step \
  "swift_model_library_usage_description_builder" \
  "RELFlowHub model library usage builder regression" \
  "${swift_model_library_usage_step_log}" \
  "${swift_model_library_usage_step_command}"; then
  swift_model_library_usage_step_status="pass"
else
  swift_model_library_usage_step_status="fail"
fi

if run_step \
  "safe_onboarding_evidence_generator_test" \
  "Tracked safe-onboarding evidence generator regression" \
  "${evidence_generator_test_step_log}" \
  "${evidence_generator_test_step_command}"; then
  evidence_generator_test_step_status="pass"
else
  evidence_generator_test_step_status="fail"
fi

if run_step \
  "safe_onboarding_evidence_refresh" \
  "Refresh tracked safe-onboarding release packet" \
  "${evidence_refresh_step_log}" \
  "${evidence_refresh_step_command}"; then
  evidence_refresh_step_status="pass"
else
  evidence_refresh_step_status="fail"
fi

export XT_W3_24_S_GATE_STATUS="${overall_status}"
export XT_W3_24_S_GATE_PASS_COUNT="${pass_count}"
export XT_W3_24_S_GATE_FAIL_COUNT="${fail_count}"
export XT_W3_24_S_GATE_GENERATED_AT="${GENERATED_AT}"
export XT_W3_24_S_GATE_TRACKED_EVIDENCE_PATH="${TRACKED_EVIDENCE_PATH}"

export XT_W3_24_S_GATE_LIVE_TEST_STATUS="${live_test_step_status}"
export XT_W3_24_S_GATE_LIVE_TEST_COMMAND="${live_test_step_command}"
export XT_W3_24_S_GATE_ADMIN_HTTP_STATUS="${admin_http_step_status}"
export XT_W3_24_S_GATE_ADMIN_HTTP_COMMAND="${admin_http_step_command}"
export XT_W3_24_S_GATE_RECOVERY_REPORT_STATUS="${recovery_report_step_status}"
export XT_W3_24_S_GATE_RECOVERY_REPORT_COMMAND="${recovery_report_step_command}"
export XT_W3_24_S_GATE_PAIRING_REPLAY_STATUS="${pairing_replay_step_status}"
export XT_W3_24_S_GATE_PAIRING_REPLAY_COMMAND="${pairing_replay_step_command}"
export XT_W3_24_S_GATE_SWIFT_ONBOARDING_STATUS="${swift_onboarding_step_status}"
export XT_W3_24_S_GATE_SWIFT_ONBOARDING_COMMAND="${swift_onboarding_step_command}"
export XT_W3_24_S_GATE_SWIFT_MODEL_LIBRARY_SECTION_STATUS="${swift_model_library_section_step_status}"
export XT_W3_24_S_GATE_SWIFT_MODEL_LIBRARY_SECTION_COMMAND="${swift_model_library_section_step_command}"
export XT_W3_24_S_GATE_SWIFT_MODEL_LIBRARY_USAGE_STATUS="${swift_model_library_usage_step_status}"
export XT_W3_24_S_GATE_SWIFT_MODEL_LIBRARY_USAGE_COMMAND="${swift_model_library_usage_step_command}"
export XT_W3_24_S_GATE_EVIDENCE_GENERATOR_TEST_STATUS="${evidence_generator_test_step_status}"
export XT_W3_24_S_GATE_EVIDENCE_GENERATOR_TEST_COMMAND="${evidence_generator_test_step_command}"
export XT_W3_24_S_GATE_EVIDENCE_REFRESH_STATUS="${evidence_refresh_step_status}"
export XT_W3_24_S_GATE_EVIDENCE_REFRESH_COMMAND="${evidence_refresh_step_command}"

python3 - "${SUMMARY_PATH}" "${ROOT_DIR}" "${REPORT_DIR}" "${LOG_DIR}" "${TRACKED_EVIDENCE_PATH}" "${live_test_step_log}" "${admin_http_step_log}" "${recovery_report_step_log}" "${pairing_replay_step_log}" "${swift_onboarding_step_log}" "${swift_model_library_section_step_log}" "${swift_model_library_usage_step_log}" "${evidence_generator_test_step_log}" "${evidence_refresh_step_log}" <<'PY'
import json
import os
import sys

summary_path, root_dir, report_dir, log_dir, tracked_evidence_path, live_test_log, admin_http_log, recovery_report_log, pairing_replay_log, swift_onboarding_log, swift_model_library_section_log, swift_model_library_usage_log, evidence_generator_test_log, evidence_refresh_log = sys.argv[1:15]


def rel(path):
    return os.path.relpath(path, root_dir)


def load_json(path):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


tracked_evidence = load_json(tracked_evidence_path) or {}

summary = {
    "schema_version": "xt_w3_24_s_safe_onboarding_gate_summary.v1",
    "generated_at": os.environ.get("XT_W3_24_S_GATE_GENERATED_AT", ""),
    "work_order": "XT-W3-24-S",
    "status": os.environ.get("XT_W3_24_S_GATE_STATUS", "fail"),
    "rerun_command": "bash scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh",
    "counts": {
        "pass": int(os.environ.get("XT_W3_24_S_GATE_PASS_COUNT", "0")),
        "fail": int(os.environ.get("XT_W3_24_S_GATE_FAIL_COUNT", "0")),
    },
    "artifacts": {
        "report_dir": rel(report_dir),
        "log_dir": rel(log_dir),
        "tracked_evidence_packet": {
            "path": rel(tracked_evidence_path),
            "exists": os.path.exists(tracked_evidence_path),
            "schema_version": tracked_evidence.get("schema_version"),
            "status": tracked_evidence.get("status"),
            "generated_at": tracked_evidence.get("generated_at"),
        },
    },
    "steps": [
        {
            "id": "hub_live_test_evidence",
            "description": "Hub live-test evidence repair-next-step regression",
            "status": os.environ.get("XT_W3_24_S_GATE_LIVE_TEST_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_LIVE_TEST_COMMAND", ""),
            "log_path": rel(live_test_log),
        },
        {
            "id": "hub_admin_http_live_test",
            "description": "Hub admin HTTP live-test evidence regression",
            "status": os.environ.get("XT_W3_24_S_GATE_ADMIN_HTTP_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_ADMIN_HTTP_COMMAND", ""),
            "log_path": rel(admin_http_log),
        },
        {
            "id": "operator_channel_recovery_report",
            "description": "Operator channel recovery summary regression",
            "status": os.environ.get("XT_W3_24_S_GATE_RECOVERY_REPORT_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_RECOVERY_REPORT_COMMAND", ""),
            "log_path": rel(recovery_report_log),
        },
        {
            "id": "pairing_http_preauth_replay",
            "description": "Pairing preauth replay fail-closed regression",
            "status": os.environ.get("XT_W3_24_S_GATE_PAIRING_REPLAY_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_PAIRING_REPLAY_COMMAND", ""),
            "log_path": rel(pairing_replay_log),
        },
        {
            "id": "swift_operator_channels_onboarding_support",
            "description": "RELFlowHub Swift onboarding evidence parity",
            "status": os.environ.get("XT_W3_24_S_GATE_SWIFT_ONBOARDING_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_SWIFT_ONBOARDING_COMMAND", ""),
            "log_path": rel(swift_onboarding_log),
        },
        {
            "id": "swift_model_library_section_planner",
            "description": "RELFlowHub model library section planner regression",
            "status": os.environ.get("XT_W3_24_S_GATE_SWIFT_MODEL_LIBRARY_SECTION_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_SWIFT_MODEL_LIBRARY_SECTION_COMMAND", ""),
            "log_path": rel(swift_model_library_section_log),
        },
        {
            "id": "swift_model_library_usage_description_builder",
            "description": "RELFlowHub model library usage builder regression",
            "status": os.environ.get("XT_W3_24_S_GATE_SWIFT_MODEL_LIBRARY_USAGE_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_SWIFT_MODEL_LIBRARY_USAGE_COMMAND", ""),
            "log_path": rel(swift_model_library_usage_log),
        },
        {
            "id": "safe_onboarding_evidence_generator_test",
            "description": "Tracked safe-onboarding evidence generator regression",
            "status": os.environ.get("XT_W3_24_S_GATE_EVIDENCE_GENERATOR_TEST_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_EVIDENCE_GENERATOR_TEST_COMMAND", ""),
            "log_path": rel(evidence_generator_test_log),
        },
        {
            "id": "safe_onboarding_evidence_refresh",
            "description": "Refresh tracked safe-onboarding release packet",
            "status": os.environ.get("XT_W3_24_S_GATE_EVIDENCE_REFRESH_STATUS", "not_run"),
            "command": os.environ.get("XT_W3_24_S_GATE_EVIDENCE_REFRESH_COMMAND", ""),
            "log_path": rel(evidence_refresh_log),
        },
    ],
}

os.makedirs(os.path.dirname(summary_path), exist_ok=True)
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2)
    handle.write("\n")
PY

echo "[xt-w3-24-s-gate] summary=${SUMMARY_PATH}"

if [[ "${overall_status}" != "pass" ]]; then
  exit 1
fi
