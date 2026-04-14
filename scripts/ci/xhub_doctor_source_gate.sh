#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${XHUB_DOCTOR_SOURCE_GATE_REPORT_DIR:-${ROOT_DIR}/build/reports}"
LOG_DIR="${XHUB_DOCTOR_SOURCE_GATE_LOG_DIR:-${REPORT_DIR}/xhub_doctor_source_gate_logs}"
SUMMARY_PATH="${XHUB_DOCTOR_SOURCE_GATE_SUMMARY_PATH:-${REPORT_DIR}/xhub_doctor_source_gate_summary.v1.json}"

mkdir -p "${REPORT_DIR}" "${LOG_DIR}"

overall_status="pass"
pass_count=0
fail_count=0

wrapper_step_status="not_run"
wrapper_step_log="${LOG_DIR}/wrapper_dispatch_tests.log"
wrapper_step_command="node scripts/run_xhub_doctor_from_source.test.js"

build_snapshot_retention_step_status="not_run"
build_snapshot_retention_step_log="${LOG_DIR}/build_snapshot_retention_smoke.log"
build_snapshot_retention_step_command="bash scripts/smoke_build_snapshot_retention.sh"

build_snapshot_inventory_step_status="not_run"
build_snapshot_inventory_step_log="${LOG_DIR}/build_snapshot_inventory_report.log"
build_snapshot_inventory_report_path="${REPORT_DIR}/build_snapshot_inventory.v1.json"
build_snapshot_inventory_step_command="node scripts/generate_build_snapshot_inventory_report.js --out-json ${build_snapshot_inventory_report_path}"

hub_local_service_snapshot_step_status="not_run"
hub_local_service_snapshot_step_log="${LOG_DIR}/hub_local_service_snapshot_smoke.log"
hub_local_service_snapshot_step_command="bash scripts/smoke_xhub_doctor_hub_local_service_snapshot.sh"

xt_smoke_step_status="not_run"
xt_smoke_step_log="${LOG_DIR}/xt_source_smoke.log"
xt_smoke_step_command="bash scripts/smoke_xhub_doctor_xt_source_export.sh"

xt_pairing_repair_step_status="not_run"
xt_pairing_repair_step_log="${LOG_DIR}/xt_pairing_repair_smoke.log"
xt_pairing_repair_step_command="bash scripts/smoke_xhub_doctor_xt_pairing_repair.sh"

xt_memory_truth_closure_step_status="not_run"
xt_memory_truth_closure_step_log="${LOG_DIR}/xt_memory_truth_closure_smoke.log"
xt_memory_truth_closure_step_command="bash scripts/smoke_xhub_doctor_xt_memory_truth_closure.sh"

smoke_step_status="not_run"
smoke_step_log="${LOG_DIR}/all_source_smoke.log"
smoke_step_command="bash scripts/smoke_xhub_doctor_all_source_export.sh"

run_step() {
  local step_id="$1"
  local description="$2"
  local log_path="$3"
  shift 3

  echo "[xhub-doctor-source-gate] start step=${step_id} description=${description}"
  if (
    cd "${ROOT_DIR}"
    "$@"
  ) >"${log_path}" 2>&1; then
    echo "[xhub-doctor-source-gate] pass step=${step_id} log=${log_path}"
    pass_count=$((pass_count + 1))
    return 0
  fi

  echo "[xhub-doctor-source-gate] fail step=${step_id} log=${log_path}" >&2
  echo "[xhub-doctor-source-gate] last_log_lines step=${step_id}" >&2
  tail -n 40 "${log_path}" >&2 || true
  fail_count=$((fail_count + 1))
  overall_status="fail"
  return 1
}

if run_step \
  "wrapper_dispatch_tests" \
  "Wrapper dispatch tests" \
  "${wrapper_step_log}" \
  node scripts/run_xhub_doctor_from_source.test.js; then
  wrapper_step_status="pass"
else
  wrapper_step_status="fail"
fi

if run_step \
  "build_snapshot_retention_smoke" \
  "Build snapshot retention smoke" \
  "${build_snapshot_retention_step_log}" \
  bash scripts/smoke_build_snapshot_retention.sh; then
  build_snapshot_retention_step_status="pass"
else
  build_snapshot_retention_step_status="fail"
fi

if run_step \
  "hub_local_service_snapshot_smoke" \
  "Hub local-service snapshot smoke" \
  "${hub_local_service_snapshot_step_log}" \
  bash scripts/smoke_xhub_doctor_hub_local_service_snapshot.sh; then
  hub_local_service_snapshot_step_status="pass"
else
  hub_local_service_snapshot_step_status="fail"
fi

if run_step \
  "xt_source_smoke" \
  "XT source smoke" \
  "${xt_smoke_step_log}" \
  bash scripts/smoke_xhub_doctor_xt_source_export.sh; then
  xt_smoke_step_status="pass"
else
  xt_smoke_step_status="fail"
fi

if run_step \
  "xt_pairing_repair_smoke" \
  "XT pairing repair closure smoke" \
  "${xt_pairing_repair_step_log}" \
  bash scripts/smoke_xhub_doctor_xt_pairing_repair.sh; then
  xt_pairing_repair_step_status="pass"
else
  xt_pairing_repair_step_status="fail"
fi

if run_step \
  "xt_memory_truth_closure_smoke" \
  "XT memory truth and canonical sync closure smoke" \
  "${xt_memory_truth_closure_step_log}" \
  bash scripts/smoke_xhub_doctor_xt_memory_truth_closure.sh; then
  xt_memory_truth_closure_step_status="pass"
else
  xt_memory_truth_closure_step_status="fail"
fi

if run_step \
  "all_source_smoke" \
  "Aggregate Hub + XT source smoke" \
  "${smoke_step_log}" \
  bash scripts/smoke_xhub_doctor_all_source_export.sh; then
  smoke_step_status="pass"
else
  smoke_step_status="fail"
fi

if run_step \
  "build_snapshot_inventory_report" \
  "Build snapshot inventory report" \
  "${build_snapshot_inventory_step_log}" \
  node scripts/generate_build_snapshot_inventory_report.js --out-json "${build_snapshot_inventory_report_path}"; then
  build_snapshot_inventory_step_status="pass"
else
  build_snapshot_inventory_step_status="fail"
fi

export XHUB_DOCTOR_SOURCE_GATE_OVERALL_STATUS="${overall_status}"
export XHUB_DOCTOR_SOURCE_GATE_PASS_COUNT="${pass_count}"
export XHUB_DOCTOR_SOURCE_GATE_FAIL_COUNT="${fail_count}"
export XHUB_DOCTOR_SOURCE_GATE_WRAPPER_STATUS="${wrapper_step_status}"
export XHUB_DOCTOR_SOURCE_GATE_WRAPPER_COMMAND="${wrapper_step_command}"
export XHUB_DOCTOR_SOURCE_GATE_BUILD_SNAPSHOT_RETENTION_STATUS="${build_snapshot_retention_step_status}"
export XHUB_DOCTOR_SOURCE_GATE_BUILD_SNAPSHOT_RETENTION_COMMAND="${build_snapshot_retention_step_command}"
export XHUB_DOCTOR_SOURCE_GATE_BUILD_SNAPSHOT_INVENTORY_STATUS="${build_snapshot_inventory_step_status}"
export XHUB_DOCTOR_SOURCE_GATE_BUILD_SNAPSHOT_INVENTORY_COMMAND="${build_snapshot_inventory_step_command}"
export XHUB_DOCTOR_SOURCE_GATE_HUB_LOCAL_SERVICE_SNAPSHOT_STATUS="${hub_local_service_snapshot_step_status}"
export XHUB_DOCTOR_SOURCE_GATE_HUB_LOCAL_SERVICE_SNAPSHOT_COMMAND="${hub_local_service_snapshot_step_command}"
export XHUB_DOCTOR_SOURCE_GATE_XT_SMOKE_STATUS="${xt_smoke_step_status}"
export XHUB_DOCTOR_SOURCE_GATE_XT_SMOKE_COMMAND="${xt_smoke_step_command}"
export XHUB_DOCTOR_SOURCE_GATE_XT_PAIRING_REPAIR_STATUS="${xt_pairing_repair_step_status}"
export XHUB_DOCTOR_SOURCE_GATE_XT_PAIRING_REPAIR_COMMAND="${xt_pairing_repair_step_command}"
export XHUB_DOCTOR_SOURCE_GATE_XT_MEMORY_TRUTH_CLOSURE_STATUS="${xt_memory_truth_closure_step_status}"
export XHUB_DOCTOR_SOURCE_GATE_XT_MEMORY_TRUTH_CLOSURE_COMMAND="${xt_memory_truth_closure_step_command}"
export XHUB_DOCTOR_SOURCE_GATE_SMOKE_STATUS="${smoke_step_status}"
export XHUB_DOCTOR_SOURCE_GATE_SMOKE_COMMAND="${smoke_step_command}"

python3 - "${SUMMARY_PATH}" "${REPORT_DIR}" "${wrapper_step_log}" "${build_snapshot_retention_step_log}" "${hub_local_service_snapshot_step_log}" "${xt_smoke_step_log}" "${xt_pairing_repair_step_log}" "${xt_memory_truth_closure_step_log}" "${smoke_step_log}" "${build_snapshot_inventory_step_log}" <<'PY'
import json
import os
import sys
import time

summary_path, report_dir, wrapper_log, build_snapshot_retention_log, hub_local_service_snapshot_log, xt_smoke_log, xt_pairing_repair_log, xt_memory_truth_closure_log, smoke_log, build_snapshot_inventory_log = sys.argv[1:11]


def load_json_if_exists(path):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def compact_project_context_summary(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "source_kind": payload.get("source_kind"),
        "source_badge": payload.get("source_badge"),
        "status_line": payload.get("status_line"),
        "project_label": payload.get("project_label"),
        "dialogue_metric": payload.get("dialogue_metric"),
        "depth_metric": payload.get("depth_metric"),
        "dialogue_line": payload.get("dialogue_line"),
        "depth_line": payload.get("depth_line"),
        "coverage_metric": payload.get("coverage_metric"),
        "boundary_metric": payload.get("boundary_metric"),
        "coverage_line": payload.get("coverage_line"),
        "boundary_line": payload.get("boundary_line"),
    }


def compact_hub_memory_prompt_projection(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "projection_source": payload.get("projection_source"),
        "canonical_item_count": payload.get("canonical_item_count"),
        "working_set_turn_count": payload.get("working_set_turn_count"),
        "runtime_truth_item_count": payload.get("runtime_truth_item_count"),
        "runtime_truth_source_kinds": payload.get("runtime_truth_source_kinds") if isinstance(payload.get("runtime_truth_source_kinds"), list) else [],
    }


def compact_project_memory_policy(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "configured_recent_project_dialogue_profile": payload.get("configured_recent_project_dialogue_profile"),
        "configured_project_context_depth": payload.get("configured_project_context_depth"),
        "recommended_recent_project_dialogue_profile": payload.get("recommended_recent_project_dialogue_profile"),
        "recommended_project_context_depth": payload.get("recommended_project_context_depth"),
        "effective_recent_project_dialogue_profile": payload.get("effective_recent_project_dialogue_profile"),
        "effective_project_context_depth": payload.get("effective_project_context_depth"),
        "a_tier_memory_ceiling": payload.get("a_tier_memory_ceiling"),
        "audit_ref": payload.get("audit_ref"),
    }


def compact_supervisor_memory_policy(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "configured_supervisor_recent_raw_context_profile": payload.get("configured_supervisor_recent_raw_context_profile"),
        "configured_review_memory_depth": payload.get("configured_review_memory_depth"),
        "recommended_supervisor_recent_raw_context_profile": payload.get("recommended_supervisor_recent_raw_context_profile"),
        "recommended_review_memory_depth": payload.get("recommended_review_memory_depth"),
        "effective_supervisor_recent_raw_context_profile": payload.get("effective_supervisor_recent_raw_context_profile"),
        "effective_review_memory_depth": payload.get("effective_review_memory_depth"),
        "s_tier_review_memory_ceiling": payload.get("s_tier_review_memory_ceiling"),
        "audit_ref": payload.get("audit_ref"),
    }


def compact_memory_assembly_resolution(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "role": payload.get("role"),
        "dominant_mode": payload.get("dominant_mode"),
        "trigger": payload.get("trigger"),
        "configured_depth": payload.get("configured_depth"),
        "recommended_depth": payload.get("recommended_depth"),
        "effective_depth": payload.get("effective_depth"),
        "ceiling_from_tier": payload.get("ceiling_from_tier"),
        "ceiling_hit": payload.get("ceiling_hit"),
        "selected_slots": payload.get("selected_slots") if isinstance(payload.get("selected_slots"), list) else [],
        "selected_planes": payload.get("selected_planes") if isinstance(payload.get("selected_planes"), list) else [],
        "selected_serving_objects": payload.get("selected_serving_objects") if isinstance(payload.get("selected_serving_objects"), list) else [],
        "excluded_blocks": payload.get("excluded_blocks") if isinstance(payload.get("excluded_blocks"), list) else [],
        "budget_summary": payload.get("budget_summary"),
        "audit_ref": payload.get("audit_ref"),
    }


def compact_memory_route_truth_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    route_result = payload.get("route_result") or {}
    winning_binding = payload.get("winning_binding") or {}
    return {
        "projection_source": payload.get("projection_source"),
        "completeness": payload.get("completeness"),
        "route_source": route_result.get("route_source"),
        "route_reason_code": route_result.get("route_reason_code"),
        "binding_provider": winning_binding.get("provider"),
        "binding_model_id": winning_binding.get("model_id"),
    }


def compact_durable_candidate_mirror_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "status": payload.get("status"),
        "target": payload.get("target"),
        "attempted": payload.get("attempted"),
        "error_code": payload.get("error_code"),
        "local_store_role": payload.get("local_store_role"),
    }


def compact_local_store_write_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "personal_memory_intent": payload.get("personal_memory_intent"),
        "cross_link_intent": payload.get("cross_link_intent"),
        "personal_review_intent": payload.get("personal_review_intent"),
    }


def compact_remote_snapshot_cache_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "source": payload.get("source"),
        "freshness": payload.get("freshness"),
        "cache_hit": payload.get("cache_hit"),
        "scope": payload.get("scope"),
        "cached_at_ms": payload.get("cached_at_ms"),
        "age_ms": payload.get("age_ms"),
        "ttl_remaining_ms": payload.get("ttl_remaining_ms"),
    }


def compact_connectivity_repair_ledger(payload):
    if not isinstance(payload, dict):
        return None
    entries = payload.get("entries") or []
    compact_entries = []
    for entry in entries[-3:]:
        if not isinstance(entry, dict):
            continue
        compact_entries.append({
            "recorded_at_ms": entry.get("recorded_at_ms"),
            "trigger": entry.get("trigger"),
            "failure_code": entry.get("failure_code"),
            "reason_family": entry.get("reason_family"),
            "action": entry.get("action"),
            "owner": entry.get("owner"),
            "result": entry.get("result"),
            "verify_result": entry.get("verify_result"),
            "final_route": entry.get("final_route"),
            "decision_reason_code": entry.get("decision_reason_code"),
            "incident_reason_code": entry.get("incident_reason_code"),
        })
    latest = compact_entries[-1] if compact_entries else None
    return {
        "entry_count": len(entries),
        "updated_at_ms": payload.get("updated_at_ms"),
        "latest": latest,
        "recent_entries": compact_entries,
    }


def compact_heartbeat_governance_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    progress_heartbeat = payload.get("progress_heartbeat") or {}
    review_pulse = payload.get("review_pulse") or {}
    brainstorm_review = payload.get("brainstorm_review") or {}
    next_review_due = payload.get("next_review_due") or {}
    return {
        "project_id": payload.get("project_id"),
        "project_name": payload.get("project_name"),
        "status_digest": payload.get("status_digest"),
        "latest_quality_band": payload.get("latest_quality_band"),
        "latest_quality_score": payload.get("latest_quality_score"),
        "weak_reasons": payload.get("weak_reasons"),
        "open_anomaly_types": payload.get("open_anomaly_types"),
        "project_phase": payload.get("project_phase"),
        "execution_status": payload.get("execution_status"),
        "risk_tier": payload.get("risk_tier"),
        "progress_heartbeat_effective_seconds": progress_heartbeat.get("effective_seconds"),
        "review_pulse_effective_seconds": review_pulse.get("effective_seconds"),
        "brainstorm_review_effective_seconds": brainstorm_review.get("effective_seconds"),
        "next_review_kind": next_review_due.get("kind"),
        "next_review_due": next_review_due.get("due"),
        "recovery_decision": compact_heartbeat_recovery_decision(payload.get("recovery_decision")),
    }


def compact_heartbeat_recovery_decision(payload):
    if not isinstance(payload, dict):
        return None

    compacted = {}
    scalar_fields = [
        "action",
        "action_display_text",
        "urgency",
        "urgency_display_text",
        "reason_code",
        "reason_display_text",
        "system_next_step_display_text",
        "summary",
        "doctor_explainability_text",
        "queued_review_trigger",
        "queued_review_trigger_display_text",
        "queued_review_level",
        "queued_review_level_display_text",
        "queued_review_run_kind",
        "queued_review_run_kind_display_text",
    ]
    for field in scalar_fields:
        value = payload.get(field)
        if value not in (None, ""):
            compacted[field] = value

    array_fields = [
        "source_signals",
        "source_signal_display_texts",
        "anomaly_types",
        "anomaly_type_display_texts",
        "blocked_lane_reasons",
        "blocked_lane_reason_display_texts",
    ]
    for field in array_fields:
        value = payload.get(field)
        if isinstance(value, list) and value:
            compacted[field] = value

    count_fields = [
        "blocked_lane_count",
        "stalled_lane_count",
        "failed_lane_count",
        "recovering_lane_count",
    ]
    for field in count_fields:
        value = payload.get(field)
        if isinstance(value, int):
            compacted[field] = value

    requires_user_action = payload.get("requires_user_action")
    if isinstance(requires_user_action, bool):
        compacted["requires_user_action"] = requires_user_action

    return compacted or None


def compact_hub_local_service_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    primary_issue = payload.get("primary_issue") or {}
    doctor_projection = payload.get("doctor_projection") or {}
    providers = payload.get("providers") or []
    provider = providers[0] if isinstance(providers, list) and providers else {}
    managed = provider.get("managed_service_state") or {}
    return {
        "provider_count": payload.get("provider_count"),
        "ready_provider_count": payload.get("ready_provider_count"),
        "primary_issue_reason_code": primary_issue.get("reason_code"),
        "doctor_failure_code": doctor_projection.get("current_failure_code"),
        "doctor_provider_check_status": doctor_projection.get("provider_check_status"),
        "provider_id": provider.get("provider_id"),
        "service_state": provider.get("service_state"),
        "runtime_reason_code": provider.get("runtime_reason_code"),
        "managed_process_state": managed.get("processState") or managed.get("process_state"),
        "managed_start_attempt_count": managed.get("startAttemptCount") or managed.get("start_attempt_count"),
    }


def compact_hub_local_service_recovery_guidance(payload):
    if not isinstance(payload, dict):
        return None
    recommended_actions = payload.get("recommended_actions") or []
    support_faq = payload.get("support_faq") or []
    top_action = recommended_actions[0] if isinstance(recommended_actions, list) and recommended_actions else {}
    top_faq = support_faq[0] if isinstance(support_faq, list) and support_faq else {}
    primary_issue = payload.get("primary_issue") or {}
    return {
        "guidance_present": payload.get("guidance_present"),
        "current_failure_code": payload.get("current_failure_code"),
        "current_failure_issue": payload.get("current_failure_issue"),
        "provider_check_status": payload.get("provider_check_status"),
        "provider_check_blocking": payload.get("provider_check_blocking"),
        "action_category": payload.get("action_category"),
        "severity": payload.get("severity"),
        "install_hint": payload.get("install_hint"),
        "repair_destination_ref": payload.get("repair_destination_ref"),
        "service_base_url": payload.get("service_base_url"),
        "managed_process_state": payload.get("managed_process_state"),
        "managed_start_attempt_count": payload.get("managed_start_attempt_count"),
        "managed_last_start_error": payload.get("managed_last_start_error"),
        "primary_issue_reason_code": primary_issue.get("reason_code"),
        "blocked_capabilities": payload.get("blocked_capabilities") if isinstance(payload.get("blocked_capabilities"), list) else [],
        "top_recommended_action": {
            "rank": top_action.get("rank"),
            "action_id": top_action.get("action_id"),
            "title": top_action.get("title"),
            "command_or_ref": top_action.get("command_or_ref"),
        } if isinstance(top_action, dict) and top_action else None,
        "top_support_faq": {
            "faq_id": top_faq.get("faq_id"),
            "question": top_faq.get("question"),
            "answer": top_faq.get("answer"),
        } if isinstance(top_faq, dict) and top_faq else None,
    }


def compact_hub_doctor_next_step(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "step_id": payload.get("step_id"),
        "kind": payload.get("kind"),
        "label": payload.get("label"),
        "owner": payload.get("owner"),
        "blocking": payload.get("blocking"),
        "destination_ref": payload.get("destination_ref"),
        "instruction": payload.get("instruction"),
    }


def compact_hub_doctor_check(payload):
    if not isinstance(payload, dict):
        return None
    detail_lines = payload.get("detail_lines")
    lines = detail_lines if isinstance(detail_lines, list) else []
    providers = []
    error_codes = []
    fetch_errors = []
    required_next_steps = []
    for line in lines:
        text = str(line or "").strip()
        if not text:
            continue
        if text.startswith("fetch_error="):
            fetch_errors.append(text.split("=", 1)[1])
        if "required_next_step=" in text:
            required_next_step = text.split("required_next_step=", 1)[1].strip()
            if required_next_step and required_next_step != "none" and required_next_step not in required_next_steps:
                required_next_steps.append(required_next_step)
        tokens = [segment for segment in text.split(" ") if "=" in segment]
        parsed = {}
        for token in tokens:
            key, value = token.split("=", 1)
            parsed[key] = value
        provider = str(parsed.get("provider") or "").strip()
        if provider and provider not in providers:
            providers.append(provider)
        for code_key in ("last_error_code", "deny_code"):
            value = str(parsed.get(code_key) or "").strip()
            if value and value != "none" and value not in error_codes:
                error_codes.append(value)
    return {
        "check_id": payload.get("check_id"),
        "check_kind": payload.get("check_kind"),
        "status": payload.get("status"),
        "severity": payload.get("severity"),
        "blocking": payload.get("blocking"),
        "headline": payload.get("headline"),
        "message": payload.get("message"),
        "next_step": payload.get("next_step"),
        "repair_destination_ref": payload.get("repair_destination_ref"),
        "provider_ids": providers,
        "error_codes": error_codes,
        "fetch_errors": fetch_errors,
        "required_next_steps": required_next_steps,
    }


def compact_hub_channel_onboarding_report(payload):
    if not isinstance(payload, dict):
        return None
    summary = payload.get("summary") or {}
    checks = payload.get("checks") if isinstance(payload.get("checks"), list) else []
    next_steps = payload.get("next_steps") if isinstance(payload.get("next_steps"), list) else []
    current_failure_issue = str(payload.get("current_failure_issue") or "").strip()

    primary_check = None
    if current_failure_issue:
        for item in checks:
            if str(item.get("check_kind") or "").strip() == current_failure_issue:
                primary_check = item
                break
    if primary_check is None:
        primary_check = next((item for item in checks if str(item.get("status") or "") == "fail"), None)
    if primary_check is None:
        primary_check = next((item for item in checks if str(item.get("status") or "") == "warn"), None)

    blocking_step = next((item for item in next_steps if item.get("blocking") is True), None)
    advisory_step = next((item for item in next_steps if item.get("blocking") is not True), None)

    return {
        "bundle_kind": payload.get("bundle_kind"),
        "surface": payload.get("surface"),
        "overall_state": payload.get("overall_state"),
        "ready_for_first_task": payload.get("ready_for_first_task"),
        "current_failure_code": payload.get("current_failure_code"),
        "current_failure_issue": payload.get("current_failure_issue"),
        "summary_headline": summary.get("headline"),
        "summary_failed": summary.get("failed"),
        "summary_warned": summary.get("warned"),
        "summary_passed": summary.get("passed"),
        "summary_skipped": summary.get("skipped"),
        "primary_check": compact_hub_doctor_check(primary_check),
        "blocking_next_step": compact_hub_doctor_next_step(blocking_step),
        "advisory_next_step": compact_hub_doctor_next_step(advisory_step),
        "report_path": payload.get("report_path"),
        "source_report_path": payload.get("source_report_path"),
    }


def compact_hub_doctor_cli_summary(payload):
    if not isinstance(payload, dict):
        return None
    runtime = payload.get("runtime") or {}
    channel = payload.get("channel") or {}
    return {
        "runtime": {
            "output_path": runtime.get("output_path"),
            "current_failure_code": runtime.get("current_failure_code"),
            "current_failure_issue": runtime.get("current_failure_issue"),
            "primary_next_step": compact_hub_doctor_next_step(runtime.get("primary_next_step")),
            "blocking_next_step": compact_hub_doctor_next_step(runtime.get("blocking_next_step")),
            "advisory_next_step": compact_hub_doctor_next_step(runtime.get("advisory_next_step")),
        },
        "channel": {
            "output_path": channel.get("output_path"),
            "current_failure_code": channel.get("current_failure_code"),
            "current_failure_issue": channel.get("current_failure_issue"),
            "primary_next_step": compact_hub_doctor_next_step(channel.get("primary_next_step")),
            "blocking_next_step": compact_hub_doctor_next_step(channel.get("blocking_next_step")),
            "advisory_next_step": compact_hub_doctor_next_step(channel.get("advisory_next_step")),
        },
    }


def compact_xt_pairing_repair_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    scenarios = payload.get("scenarios") or []
    compact_scenarios = []
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            continue
        compact_scenarios.append({
            "failure_code": scenario.get("failure_code"),
            "mapped_issue": scenario.get("mapped_issue"),
            "guide_destinations": scenario.get("guide_destinations") if isinstance(scenario.get("guide_destinations"), list) else [],
            "wizard_primary_action_id": scenario.get("wizard_primary_action_id"),
            "settings_primary_action_id": scenario.get("settings_primary_action_id"),
            "repair_entry_title": scenario.get("repair_entry_title"),
            "doctor_headline": scenario.get("doctor_headline"),
            "doctor_repair_entry": scenario.get("doctor_repair_entry"),
        })
    return {
        "scenario_count": len(compact_scenarios),
        "scenarios": compact_scenarios,
    }


def compact_xt_route_target_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "route_kind": payload.get("route_kind"),
        "host": payload.get("host"),
        "pairing_port": payload.get("pairing_port"),
        "grpc_port": payload.get("grpc_port"),
        "host_kind": payload.get("host_kind"),
        "source": payload.get("source"),
    }


def compact_xt_first_pair_completion_proof_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "readiness": payload.get("readiness"),
        "same_lan_verified": payload.get("same_lan_verified"),
        "owner_local_approval_verified": payload.get("owner_local_approval_verified"),
        "pairing_material_issued": payload.get("pairing_material_issued"),
        "cached_reconnect_smoke_passed": payload.get("cached_reconnect_smoke_passed"),
        "stable_remote_route_present": payload.get("stable_remote_route_present"),
        "remote_shadow_smoke_passed": payload.get("remote_shadow_smoke_passed"),
        "remote_shadow_smoke_status": payload.get("remote_shadow_smoke_status"),
        "remote_shadow_smoke_source": payload.get("remote_shadow_smoke_source"),
        "remote_shadow_route": payload.get("remote_shadow_route"),
        "remote_shadow_reason_code": payload.get("remote_shadow_reason_code"),
        "remote_shadow_summary": payload.get("remote_shadow_summary"),
        "summary_line": payload.get("summary_line"),
    }


def compact_xt_paired_route_set_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    return {
        "readiness": payload.get("readiness"),
        "readiness_reason_code": payload.get("readiness_reason_code"),
        "summary_line": payload.get("summary_line"),
        "hub_instance_id": payload.get("hub_instance_id"),
        "pairing_profile_epoch": payload.get("pairing_profile_epoch"),
        "route_pack_version": payload.get("route_pack_version"),
        "active_route": compact_xt_route_target_snapshot(payload.get("active_route")),
        "lan_route": compact_xt_route_target_snapshot(payload.get("lan_route")),
        "stable_remote_route": compact_xt_route_target_snapshot(payload.get("stable_remote_route")),
        "last_known_good_route": compact_xt_route_target_snapshot(payload.get("last_known_good_route")),
        "cached_reconnect_smoke_status": payload.get("cached_reconnect_smoke_status"),
        "cached_reconnect_smoke_reason_code": payload.get("cached_reconnect_smoke_reason_code"),
        "cached_reconnect_smoke_summary": payload.get("cached_reconnect_smoke_summary"),
    }


def compact_xt_memory_truth_closure_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    project_context = payload.get("project_context") or {}
    supervisor_memory = payload.get("supervisor_memory") or {}
    canonical_sync = payload.get("canonical_sync_closure") or {}
    truth_examples = payload.get("truth_examples") or []
    compact_truth_examples = []
    for example in truth_examples:
        if not isinstance(example, dict):
            continue
        compact_truth_examples.append({
            "raw_source": example.get("rawSource"),
            "label": example.get("label"),
            "explainable_label": example.get("explainableLabel"),
            "truth_hint": example.get("truthHint"),
        })
    return {
        "truth_examples": compact_truth_examples,
        "project_context": {
            "memory_source": project_context.get("memorySource"),
            "memory_source_label": project_context.get("memorySourceLabel"),
            "writer_gate_boundary_present": project_context.get("writerGateBoundaryPresent"),
        },
        "supervisor_memory": {
            "memory_source": supervisor_memory.get("memorySource"),
            "mode_source_text": supervisor_memory.get("modeSourceText"),
            "continuity_detail_line": supervisor_memory.get("continuityDetailLine"),
        },
        "canonical_sync_closure": {
            "doctor_summary_line": canonical_sync.get("doctorSummaryLine"),
            "audit_ref": canonical_sync.get("auditRef"),
            "evidence_ref": canonical_sync.get("evidenceRef"),
            "writeback_ref": canonical_sync.get("writebackRef"),
            "strict_issue_code": canonical_sync.get("strictIssueCode"),
        },
    }


def compact_hub_pairing_smoke_snapshot(payload):
    if not isinstance(payload, dict):
        return None
    launch = payload.get("launch") or {}
    discovery = payload.get("discovery") or {}
    discovery_response = discovery.get("response") or {}
    admin_token = payload.get("adminToken") or {}
    pairing = payload.get("pairing") or {}
    errors = payload.get("errors") if isinstance(payload.get("errors"), list) else []
    return {
        "mode": payload.get("mode"),
        "ok": payload.get("ok"),
        "launch": {
            "action": launch.get("action"),
            "background_launch_evidence_found": launch.get("backgroundLaunchEvidenceFound"),
            "main_panel_shown_after_launch": launch.get("mainPanelShownAfterLaunch"),
        },
        "discovery": {
            "ok": discovery.get("ok"),
            "status": discovery.get("status"),
            "pairing_enabled": discovery_response.get("pairing_enabled"),
            "hub_instance_id": discovery_response.get("hub_instance_id"),
            "lan_discovery_name": discovery_response.get("lan_discovery_name"),
            "hub_host_hint": discovery_response.get("hub_host_hint"),
            "grpc_port": discovery_response.get("grpc_port"),
            "pairing_port": discovery_response.get("pairing_port"),
            "tls_mode": discovery_response.get("tls_mode"),
            "internet_host_hint": discovery_response.get("internet_host_hint"),
        },
        "admin_token": {
            "resolved": admin_token.get("resolved"),
            "token_source": admin_token.get("tokenSource"),
        },
        "pairing": {
            "request_id": pairing.get("requestId"),
            "pairing_request_id": pairing.get("pairingRequestId"),
            "device_name": pairing.get("deviceName"),
            "post_status": pairing.get("postStatus"),
            "pending_list_status": pairing.get("pendingListStatus"),
            "pending_list_contains_request": pairing.get("pendingListContainsRequest"),
            "cleanup_status": pairing.get("cleanupStatus"),
            "cleanup_verified": pairing.get("cleanupVerified"),
        },
        "error_count": len(errors),
    }


def support_payload_status(payload):
    if not isinstance(payload, dict):
        return "not_present"
    return "pass" if payload.get("ok") is True else "fail"


def compact_build_snapshot_inventory_surface(payload):
    if not isinstance(payload, dict):
        return None
    current_snapshot = payload.get("current_snapshot") or {}
    prune_preview = payload.get("prune_preview") or {}
    keep_refs = prune_preview.get("would_keep_history_refs")
    prune_refs = prune_preview.get("would_prune_history_refs")
    return {
        "status": payload.get("status"),
        "snapshot_root_ref": payload.get("snapshot_root_ref"),
        "snapshot_root_exists": payload.get("snapshot_root_exists"),
        "retention_keep_count": payload.get("retention_keep_count"),
        "current_snapshot_ref": current_snapshot.get("snapshot_ref"),
        "current_snapshot_size_bytes": current_snapshot.get("size_bytes"),
        "historical_snapshot_count": payload.get("historical_snapshot_count"),
        "historical_snapshot_total_bytes": payload.get("historical_snapshot_total_bytes"),
        "would_prune_history_count": prune_preview.get("would_prune_history_count"),
        "would_prune_total_bytes": prune_preview.get("would_prune_total_bytes"),
        "would_keep_history_refs": keep_refs if isinstance(keep_refs, list) else [],
        "would_prune_history_refs": prune_refs if isinstance(prune_refs, list) else [],
    }


def compact_build_snapshot_inventory_report(payload):
    if not isinstance(payload, dict):
        return None
    summary = payload.get("summary") or {}
    totals = payload.get("totals") or {}
    surfaces = payload.get("surfaces") or {}
    stale_surface_ids = summary.get("stale_history_surface_ids")
    return {
        "summary_status": summary.get("status"),
        "verdict_reason": summary.get("verdict_reason"),
        "stale_history_surface_ids": stale_surface_ids if isinstance(stale_surface_ids, list) else [],
        "largest_reclaim_candidate_surface_id": summary.get("largest_reclaim_candidate_surface_id"),
        "current_snapshot_total_bytes": totals.get("current_snapshot_total_bytes"),
        "historical_snapshot_total_bytes": totals.get("historical_snapshot_total_bytes"),
        "projected_prune_total_bytes": totals.get("projected_prune_total_bytes"),
        "projected_prune_history_count": totals.get("projected_prune_history_count"),
        "hub": compact_build_snapshot_inventory_surface(surfaces.get("hub")),
        "xterminal": compact_build_snapshot_inventory_surface(surfaces.get("xterminal")),
    }


hub_local_service_snapshot_evidence_ref = os.path.join(report_dir, "xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json")
xt_smoke_evidence_ref = os.path.join(report_dir, "xhub_doctor_xt_source_smoke_evidence.v1.json")
xt_pairing_repair_evidence_ref = os.path.join(report_dir, "xhub_doctor_xt_pairing_repair_smoke_evidence.v1.json")
xt_memory_truth_closure_evidence_ref = os.path.join(report_dir, "xhub_doctor_xt_memory_truth_closure_smoke_evidence.v1.json")
all_smoke_evidence_ref = os.path.join(report_dir, "xhub_doctor_all_source_smoke_evidence.v1.json")
hub_pairing_launch_only_evidence_ref = os.path.join(report_dir, "xhub_background_launch_only_smoke_evidence.v1.json")
hub_pairing_verify_only_evidence_ref = os.path.join(report_dir, "xhub_pairing_roundtrip_verify_only_smoke_evidence.v1.json")
build_snapshot_inventory_report_ref = os.path.join(report_dir, "build_snapshot_inventory.v1.json")
hub_local_service_snapshot_status = os.environ["XHUB_DOCTOR_SOURCE_GATE_HUB_LOCAL_SERVICE_SNAPSHOT_STATUS"]
xt_smoke_status = os.environ["XHUB_DOCTOR_SOURCE_GATE_XT_SMOKE_STATUS"]
xt_pairing_repair_status = os.environ["XHUB_DOCTOR_SOURCE_GATE_XT_PAIRING_REPAIR_STATUS"]
xt_memory_truth_closure_status = os.environ["XHUB_DOCTOR_SOURCE_GATE_XT_MEMORY_TRUTH_CLOSURE_STATUS"]
all_smoke_status = os.environ["XHUB_DOCTOR_SOURCE_GATE_SMOKE_STATUS"]
build_snapshot_inventory_status = os.environ["XHUB_DOCTOR_SOURCE_GATE_BUILD_SNAPSHOT_INVENTORY_STATUS"]

hub_local_service_snapshot_evidence = (
    load_json_if_exists(hub_local_service_snapshot_evidence_ref)
    if hub_local_service_snapshot_status == "pass"
    else None
)
xt_smoke_evidence = (
    load_json_if_exists(xt_smoke_evidence_ref)
    if xt_smoke_status == "pass"
    else None
)
xt_pairing_repair_evidence = (
    load_json_if_exists(xt_pairing_repair_evidence_ref)
    if xt_pairing_repair_status == "pass"
    else None
)
xt_memory_truth_closure_evidence = (
    load_json_if_exists(xt_memory_truth_closure_evidence_ref)
    if xt_memory_truth_closure_status == "pass"
    else None
)
hub_pairing_launch_only_evidence = load_json_if_exists(hub_pairing_launch_only_evidence_ref)
hub_pairing_verify_only_evidence = load_json_if_exists(hub_pairing_verify_only_evidence_ref)
build_snapshot_inventory_report = (
    load_json_if_exists(build_snapshot_inventory_report_ref)
    if build_snapshot_inventory_status == "pass"
    else None
)
all_smoke_evidence = (
    load_json_if_exists(all_smoke_evidence_ref)
    if all_smoke_status == "pass"
    else None
)

payload = {
    "schema_version": "xhub_doctor_source_gate_summary.v1",
    "generated_at_ms": int(time.time() * 1000),
    "overall_status": os.environ["XHUB_DOCTOR_SOURCE_GATE_OVERALL_STATUS"],
    "summary": {
        "passed": int(os.environ["XHUB_DOCTOR_SOURCE_GATE_PASS_COUNT"]),
        "failed": int(os.environ["XHUB_DOCTOR_SOURCE_GATE_FAIL_COUNT"]),
    },
    "steps": [
        {
            "step_id": "wrapper_dispatch_tests",
            "status": os.environ["XHUB_DOCTOR_SOURCE_GATE_WRAPPER_STATUS"],
            "command": os.environ["XHUB_DOCTOR_SOURCE_GATE_WRAPPER_COMMAND"],
            "log_path": os.path.realpath(wrapper_log),
        },
        {
            "step_id": "build_snapshot_retention_smoke",
            "status": os.environ["XHUB_DOCTOR_SOURCE_GATE_BUILD_SNAPSHOT_RETENTION_STATUS"],
            "command": os.environ["XHUB_DOCTOR_SOURCE_GATE_BUILD_SNAPSHOT_RETENTION_COMMAND"],
            "log_path": os.path.realpath(build_snapshot_retention_log),
        },
        {
            "step_id": "hub_local_service_snapshot_smoke",
            "status": hub_local_service_snapshot_status,
            "command": os.environ["XHUB_DOCTOR_SOURCE_GATE_HUB_LOCAL_SERVICE_SNAPSHOT_COMMAND"],
            "log_path": os.path.realpath(hub_local_service_snapshot_log),
            "evidence_ref": os.path.realpath(hub_local_service_snapshot_evidence_ref) if hub_local_service_snapshot_evidence else "",
            "structured_hub_local_service_snapshot": compact_hub_local_service_snapshot(
                hub_local_service_snapshot_evidence.get("hub_local_service_snapshot") if hub_local_service_snapshot_evidence else None
            ),
            "structured_hub_local_service_recovery_guidance": compact_hub_local_service_recovery_guidance(
                hub_local_service_snapshot_evidence.get("hub_local_service_recovery_guidance") if hub_local_service_snapshot_evidence else None
            ),
        },
        {
            "step_id": "xt_source_smoke",
            "status": xt_smoke_status,
            "command": os.environ["XHUB_DOCTOR_SOURCE_GATE_XT_SMOKE_COMMAND"],
            "log_path": os.path.realpath(xt_smoke_log),
            "evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
            "structured_project_context_summary": compact_project_context_summary(
                xt_smoke_evidence.get("project_context_summary") if xt_smoke_evidence else None
            ),
            "structured_hub_memory_prompt_projection": compact_hub_memory_prompt_projection(
                xt_smoke_evidence.get("hub_memory_prompt_projection") if xt_smoke_evidence else None
            ),
            "structured_project_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
                xt_smoke_evidence.get("project_remote_snapshot_cache_snapshot") if xt_smoke_evidence else None
            ),
            "structured_heartbeat_governance_snapshot": compact_heartbeat_governance_snapshot(
                xt_smoke_evidence.get("heartbeat_governance_snapshot") if xt_smoke_evidence else None
            ),
            "structured_durable_candidate_mirror_snapshot": compact_durable_candidate_mirror_snapshot(
                xt_smoke_evidence.get("durable_candidate_mirror_snapshot") if xt_smoke_evidence else None
            ),
            "structured_local_store_write_snapshot": compact_local_store_write_snapshot(
                xt_smoke_evidence.get("local_store_write_snapshot") if xt_smoke_evidence else None
            ),
            "structured_supervisor_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
                xt_smoke_evidence.get("supervisor_remote_snapshot_cache_snapshot") if xt_smoke_evidence else None
            ),
            "structured_connectivity_repair_ledger": compact_connectivity_repair_ledger(
                xt_smoke_evidence.get("connectivity_repair_ledger") if xt_smoke_evidence else None
            ),
            "structured_first_pair_completion_proof": compact_xt_first_pair_completion_proof_snapshot(
                xt_smoke_evidence.get("first_pair_completion_proof") if xt_smoke_evidence else None
            ),
            "structured_paired_route_set": compact_xt_paired_route_set_snapshot(
                xt_smoke_evidence.get("paired_route_set") if xt_smoke_evidence else None
            ),
            "structured_memory_route_truth_snapshot": compact_memory_route_truth_snapshot(
                xt_smoke_evidence.get("memory_route_truth_snapshot") if xt_smoke_evidence else None
            ),
        },
        {
            "step_id": "xt_pairing_repair_smoke",
            "status": xt_pairing_repair_status,
            "command": os.environ["XHUB_DOCTOR_SOURCE_GATE_XT_PAIRING_REPAIR_COMMAND"],
            "log_path": os.path.realpath(xt_pairing_repair_log),
            "evidence_ref": os.path.realpath(xt_pairing_repair_evidence_ref) if xt_pairing_repair_evidence else "",
            "structured_pairing_repair_snapshot": compact_xt_pairing_repair_snapshot(
                xt_pairing_repair_evidence if xt_pairing_repair_evidence else None
            ),
        },
        {
            "step_id": "xt_memory_truth_closure_smoke",
            "status": xt_memory_truth_closure_status,
            "command": os.environ["XHUB_DOCTOR_SOURCE_GATE_XT_MEMORY_TRUTH_CLOSURE_COMMAND"],
            "log_path": os.path.realpath(xt_memory_truth_closure_log),
            "evidence_ref": os.path.realpath(xt_memory_truth_closure_evidence_ref) if xt_memory_truth_closure_evidence else "",
            "structured_memory_truth_closure_snapshot": compact_xt_memory_truth_closure_snapshot(
                xt_memory_truth_closure_evidence if xt_memory_truth_closure_evidence else None
            ),
        },
        {
            "step_id": "all_source_smoke",
            "status": all_smoke_status,
            "command": os.environ["XHUB_DOCTOR_SOURCE_GATE_SMOKE_COMMAND"],
            "log_path": os.path.realpath(smoke_log),
            "smoke_tmp_root": os.environ.get("XHUB_DOCTOR_ALL_SOURCE_SMOKE_TMP_ROOT", ""),
            "evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
            "structured_project_context_summary": compact_project_context_summary(
                all_smoke_evidence.get("xt_project_context_summary") if all_smoke_evidence else None
            ),
            "structured_hub_memory_prompt_projection": compact_hub_memory_prompt_projection(
                all_smoke_evidence.get("xt_hub_memory_prompt_projection") if all_smoke_evidence else None
            ),
            "structured_project_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
                all_smoke_evidence.get("xt_project_remote_snapshot_cache_snapshot") if all_smoke_evidence else None
            ),
            "structured_heartbeat_governance_snapshot": compact_heartbeat_governance_snapshot(
                all_smoke_evidence.get("xt_heartbeat_governance_snapshot") if all_smoke_evidence else None
            ),
            "structured_durable_candidate_mirror_snapshot": compact_durable_candidate_mirror_snapshot(
                all_smoke_evidence.get("xt_durable_candidate_mirror_snapshot") if all_smoke_evidence else None
            ),
            "structured_local_store_write_snapshot": compact_local_store_write_snapshot(
                all_smoke_evidence.get("xt_local_store_write_snapshot") if all_smoke_evidence else None
            ),
            "structured_supervisor_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
                all_smoke_evidence.get("xt_supervisor_remote_snapshot_cache_snapshot") if all_smoke_evidence else None
            ),
            "structured_connectivity_repair_ledger": compact_connectivity_repair_ledger(
                all_smoke_evidence.get("xt_connectivity_repair_ledger") if all_smoke_evidence else None
            ),
            "structured_xt_first_pair_completion_proof": compact_xt_first_pair_completion_proof_snapshot(
                all_smoke_evidence.get("xt_first_pair_completion_proof") if all_smoke_evidence else None
            ),
            "structured_xt_paired_route_set": compact_xt_paired_route_set_snapshot(
                all_smoke_evidence.get("xt_paired_route_set") if all_smoke_evidence else None
            ),
            "structured_memory_route_truth_snapshot": compact_memory_route_truth_snapshot(
                all_smoke_evidence.get("xt_memory_route_truth_snapshot") if all_smoke_evidence else None
            ),
            "structured_hub_channel_onboarding_report": compact_hub_channel_onboarding_report(
                all_smoke_evidence.get("hub_channel_onboarding_report") if all_smoke_evidence else None
            ),
            "structured_hub_doctor_cli_summary": compact_hub_doctor_cli_summary(
                all_smoke_evidence.get("hub_doctor_cli_summary") if all_smoke_evidence else None
            ),
        },
        {
            "step_id": "build_snapshot_inventory_report",
            "status": build_snapshot_inventory_status,
            "command": os.environ["XHUB_DOCTOR_SOURCE_GATE_BUILD_SNAPSHOT_INVENTORY_COMMAND"],
            "log_path": os.path.realpath(build_snapshot_inventory_log),
            "report_ref": os.path.realpath(build_snapshot_inventory_report_ref) if build_snapshot_inventory_report else "",
            "structured_build_snapshot_inventory": compact_build_snapshot_inventory_report(
                build_snapshot_inventory_report
            ),
        },
    ],
    "project_context_summary_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_project_context_summary": compact_project_context_summary(
            xt_smoke_evidence.get("project_context_summary") if xt_smoke_evidence else None
        ),
        "all_source_project_context_summary": compact_project_context_summary(
            all_smoke_evidence.get("xt_project_context_summary") if all_smoke_evidence else None
        ),
    },
    "hub_memory_prompt_projection_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_hub_memory_prompt_projection": compact_hub_memory_prompt_projection(
            xt_smoke_evidence.get("hub_memory_prompt_projection") if xt_smoke_evidence else None
        ),
        "all_source_hub_memory_prompt_projection": compact_hub_memory_prompt_projection(
            all_smoke_evidence.get("xt_hub_memory_prompt_projection") if all_smoke_evidence else None
        ),
    },
    "project_memory_policy_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_project_memory_policy": compact_project_memory_policy(
            xt_smoke_evidence.get("project_memory_policy") if xt_smoke_evidence else None
        ),
        "all_source_project_memory_policy": compact_project_memory_policy(
            all_smoke_evidence.get("xt_project_memory_policy") if all_smoke_evidence else None
        ),
    },
    "project_memory_assembly_resolution_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_project_memory_assembly_resolution": compact_memory_assembly_resolution(
            xt_smoke_evidence.get("project_memory_assembly_resolution") if xt_smoke_evidence else None
        ),
        "all_source_project_memory_assembly_resolution": compact_memory_assembly_resolution(
            all_smoke_evidence.get("xt_project_memory_assembly_resolution") if all_smoke_evidence else None
        ),
    },
    "project_remote_snapshot_cache_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_project_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
            xt_smoke_evidence.get("project_remote_snapshot_cache_snapshot") if xt_smoke_evidence else None
        ),
        "all_source_project_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
            all_smoke_evidence.get("xt_project_remote_snapshot_cache_snapshot") if all_smoke_evidence else None
        ),
    },
    "heartbeat_governance_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_heartbeat_governance_snapshot": compact_heartbeat_governance_snapshot(
            xt_smoke_evidence.get("heartbeat_governance_snapshot") if xt_smoke_evidence else None
        ),
        "all_source_heartbeat_governance_snapshot": compact_heartbeat_governance_snapshot(
            all_smoke_evidence.get("xt_heartbeat_governance_snapshot") if all_smoke_evidence else None
        ),
    },
    "supervisor_memory_policy_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_supervisor_memory_policy": compact_supervisor_memory_policy(
            xt_smoke_evidence.get("supervisor_memory_policy") if xt_smoke_evidence else None
        ),
        "all_source_supervisor_memory_policy": compact_supervisor_memory_policy(
            all_smoke_evidence.get("xt_supervisor_memory_policy") if all_smoke_evidence else None
        ),
    },
    "supervisor_memory_assembly_resolution_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_supervisor_memory_assembly_resolution": compact_memory_assembly_resolution(
            xt_smoke_evidence.get("supervisor_memory_assembly_resolution") if xt_smoke_evidence else None
        ),
        "all_source_supervisor_memory_assembly_resolution": compact_memory_assembly_resolution(
            all_smoke_evidence.get("xt_supervisor_memory_assembly_resolution") if all_smoke_evidence else None
        ),
    },
    "supervisor_remote_snapshot_cache_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_supervisor_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
            xt_smoke_evidence.get("supervisor_remote_snapshot_cache_snapshot") if xt_smoke_evidence else None
        ),
        "all_source_supervisor_remote_snapshot_cache_snapshot": compact_remote_snapshot_cache_snapshot(
            all_smoke_evidence.get("xt_supervisor_remote_snapshot_cache_snapshot") if all_smoke_evidence else None
        ),
    },
    "durable_candidate_mirror_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_durable_candidate_mirror_snapshot": compact_durable_candidate_mirror_snapshot(
            xt_smoke_evidence.get("durable_candidate_mirror_snapshot") if xt_smoke_evidence else None
        ),
        "all_source_durable_candidate_mirror_snapshot": compact_durable_candidate_mirror_snapshot(
            all_smoke_evidence.get("xt_durable_candidate_mirror_snapshot") if all_smoke_evidence else None
        ),
    },
    "local_store_write_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_local_store_write_snapshot": compact_local_store_write_snapshot(
            xt_smoke_evidence.get("local_store_write_snapshot") if xt_smoke_evidence else None
        ),
        "all_source_local_store_write_snapshot": compact_local_store_write_snapshot(
            all_smoke_evidence.get("xt_local_store_write_snapshot") if all_smoke_evidence else None
        ),
    },
    "connectivity_repair_ledger_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_connectivity_repair_ledger": compact_connectivity_repair_ledger(
            xt_smoke_evidence.get("connectivity_repair_ledger") if xt_smoke_evidence else None
        ),
        "all_source_connectivity_repair_ledger": compact_connectivity_repair_ledger(
            all_smoke_evidence.get("xt_connectivity_repair_ledger") if all_smoke_evidence else None
        ),
    },
    "xt_pairing_readiness_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_first_pair_completion_proof": compact_xt_first_pair_completion_proof_snapshot(
            xt_smoke_evidence.get("first_pair_completion_proof") if xt_smoke_evidence else None
        ),
        "xt_source_paired_route_set": compact_xt_paired_route_set_snapshot(
            xt_smoke_evidence.get("paired_route_set") if xt_smoke_evidence else None
        ),
        "all_source_first_pair_completion_proof": compact_xt_first_pair_completion_proof_snapshot(
            all_smoke_evidence.get("xt_first_pair_completion_proof") if all_smoke_evidence else None
        ),
        "all_source_paired_route_set": compact_xt_paired_route_set_snapshot(
            all_smoke_evidence.get("xt_paired_route_set") if all_smoke_evidence else None
        ),
    },
    "memory_route_truth_support": {
        "xt_source_smoke_evidence_ref": os.path.realpath(xt_smoke_evidence_ref) if xt_smoke_evidence else "",
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "xt_source_smoke_status": xt_smoke_status,
        "all_source_smoke_status": all_smoke_status,
        "xt_source_memory_route_truth_snapshot": compact_memory_route_truth_snapshot(
            xt_smoke_evidence.get("memory_route_truth_snapshot") if xt_smoke_evidence else None
        ),
        "all_source_memory_route_truth_snapshot": compact_memory_route_truth_snapshot(
            all_smoke_evidence.get("xt_memory_route_truth_snapshot") if all_smoke_evidence else None
        ),
    },
    "hub_local_service_snapshot_support": {
        "hub_local_service_snapshot_smoke_evidence_ref": os.path.realpath(hub_local_service_snapshot_evidence_ref) if hub_local_service_snapshot_evidence else "",
        "hub_local_service_snapshot_smoke_status": hub_local_service_snapshot_status,
        "hub_local_service_snapshot": compact_hub_local_service_snapshot(
            hub_local_service_snapshot_evidence.get("hub_local_service_snapshot") if hub_local_service_snapshot_evidence else None
        ),
    },
    "hub_local_service_recovery_guidance_support": {
        "hub_local_service_snapshot_smoke_evidence_ref": os.path.realpath(hub_local_service_snapshot_evidence_ref) if hub_local_service_snapshot_evidence else "",
        "hub_local_service_recovery_guidance_smoke_status": (
            hub_local_service_snapshot_status
            if hub_local_service_snapshot_evidence and isinstance(hub_local_service_snapshot_evidence.get("hub_local_service_recovery_guidance"), dict)
            else "not_present"
        ),
        "hub_local_service_recovery_guidance": compact_hub_local_service_recovery_guidance(
            hub_local_service_snapshot_evidence.get("hub_local_service_recovery_guidance") if hub_local_service_snapshot_evidence else None
        ),
    },
    "hub_channel_onboarding_support": {
        "all_source_smoke_evidence_ref": os.path.realpath(all_smoke_evidence_ref) if all_smoke_evidence else "",
        "all_source_smoke_status": all_smoke_status,
        "hub_channel_onboarding_report": compact_hub_channel_onboarding_report(
            all_smoke_evidence.get("hub_channel_onboarding_report") if all_smoke_evidence else None
        ),
        "hub_doctor_cli_summary": compact_hub_doctor_cli_summary(
            all_smoke_evidence.get("hub_doctor_cli_summary") if all_smoke_evidence else None
        ),
    },
    "hub_pairing_roundtrip_support": {
        "launch_only_smoke_evidence_ref": (
            os.path.realpath(hub_pairing_launch_only_evidence_ref) if hub_pairing_launch_only_evidence else ""
        ),
        "launch_only_smoke_status": support_payload_status(hub_pairing_launch_only_evidence),
        "launch_only_snapshot": compact_hub_pairing_smoke_snapshot(
            hub_pairing_launch_only_evidence
        ),
        "verify_only_smoke_evidence_ref": (
            os.path.realpath(hub_pairing_verify_only_evidence_ref) if hub_pairing_verify_only_evidence else ""
        ),
        "verify_only_smoke_status": support_payload_status(hub_pairing_verify_only_evidence),
        "verify_only_snapshot": compact_hub_pairing_smoke_snapshot(
            hub_pairing_verify_only_evidence
        ),
    },
    "xt_pairing_repair_support": {
        "xt_pairing_repair_smoke_evidence_ref": os.path.realpath(xt_pairing_repair_evidence_ref) if xt_pairing_repair_evidence else "",
        "xt_pairing_repair_smoke_status": xt_pairing_repair_status,
        "xt_pairing_repair_snapshot": compact_xt_pairing_repair_snapshot(
            xt_pairing_repair_evidence if xt_pairing_repair_evidence else None
        ),
    },
    "xt_memory_truth_closure_support": {
        "xt_memory_truth_closure_smoke_evidence_ref": (
            os.path.realpath(xt_memory_truth_closure_evidence_ref) if xt_memory_truth_closure_evidence else ""
        ),
        "xt_memory_truth_closure_smoke_status": xt_memory_truth_closure_status,
        "xt_memory_truth_closure_snapshot": compact_xt_memory_truth_closure_snapshot(
            xt_memory_truth_closure_evidence if xt_memory_truth_closure_evidence else None
        ),
    },
    "build_snapshot_inventory_support": {
        "report_ref": os.path.realpath(build_snapshot_inventory_report_ref) if build_snapshot_inventory_report else "",
        "build_snapshot_inventory_generation_status": build_snapshot_inventory_status,
        "inventory_summary": compact_build_snapshot_inventory_report(build_snapshot_inventory_report),
    },
}

os.makedirs(os.path.dirname(summary_path), exist_ok=True)
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "[xhub-doctor-source-gate] summary=${SUMMARY_PATH}"
echo "[xhub-doctor-source-gate] overall_status=${overall_status} passed=${pass_count} failed=${fail_count}"

if [[ "${overall_status}" != "pass" ]]; then
  exit 1
fi
