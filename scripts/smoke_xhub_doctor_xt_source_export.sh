#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="${XHUB_DOCTOR_XT_SOURCE_SMOKE_REPORT_DIR:-${ROOT_DIR}/build/reports}"
TMP_BASE_DIR="${TMPDIR:-/tmp}"
TMP_ROOT="${XHUB_DOCTOR_XT_SOURCE_SMOKE_TMP_ROOT:-}"
MIN_FREE_KB="${XHUB_DOCTOR_XT_SOURCE_SMOKE_MIN_FREE_KB:-1572864}"
SMOKE_LABEL="xhub-doctor-xt-source-smoke"

free_space_probe_path() {
  if [ -n "$TMP_ROOT" ]; then
    dirname "$TMP_ROOT"
    return
  fi
  printf '%s\n' "$TMP_BASE_DIR"
}

available_kb_for_path() {
  local probe_path="$1"
  df -Pk "$probe_path" 2>/dev/null | awk 'NR==2 { print $4 }'
}

check_free_space_or_fail() {
  local probe_path=""
  local available_kb=""
  probe_path="$(free_space_probe_path)"
  available_kb="$(available_kb_for_path "$probe_path")"
  if ! [[ "$available_kb" =~ ^[0-9]+$ ]]; then
    echo "[$SMOKE_LABEL] failed_to_read_free_space path=$probe_path" >&2
    exit 1
  fi
  if [ "$available_kb" -lt "$MIN_FREE_KB" ]; then
    echo "[$SMOKE_LABEL] insufficient_free_space_kb=$available_kb required_kb=$MIN_FREE_KB path=$probe_path" >&2
    echo "[$SMOKE_LABEL] hint=clean build/ or stale xhub_doctor_* temp roots, or lower XHUB_DOCTOR_XT_SOURCE_SMOKE_MIN_FREE_KB for a local retry if you know the disk is safe" >&2
    exit 1
  fi
}

check_free_space_or_fail

if [ -z "$TMP_ROOT" ]; then
  TMP_ROOT="$(mktemp -d "${TMP_BASE_DIR%/}/xhub_doctor_xt_source_smoke.XXXXXX")"
else
  mkdir -p "$TMP_ROOT"
fi
SNAPSHOT_DIR="$TMP_ROOT/repo_snapshot"
WORKSPACE_DIR="$TMP_ROOT/workspace"
REPORTS_DIR="$WORKSPACE_DIR/.axcoder/reports"
SOURCE_REPORT_PATH="$REPORTS_DIR/xt_unified_doctor_report.json"
OUTPUT_REPORT_PATH="$REPORTS_DIR/xhub_doctor_output_xt.json"
REPAIR_LEDGER_PATH="$REPORTS_DIR/xt_connectivity_repair_ledger.json"
FIRST_PAIR_PROOF_PATH="$REPORTS_DIR/xt_first_pair_completion_proof.v1.json"
PAIRED_ROUTE_SET_PATH="$REPORTS_DIR/xt_paired_route_set.v1.json"
EVIDENCE_PATH="${XHUB_DOCTOR_XT_SOURCE_SMOKE_EVIDENCE_PATH:-${REPORT_DIR}/xhub_doctor_xt_source_smoke_evidence.v1.json}"

cleanup() {
  if [ "${XHUB_KEEP_SMOKE_TMP:-0}" = "1" ] || [ -n "${XHUB_DOCTOR_XT_SOURCE_SMOKE_TMP_ROOT:-}" ]; then
    echo "[xhub-doctor-xt-source-smoke] kept_tmp_root=$TMP_ROOT"
    return
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$SNAPSHOT_DIR/scripts" "$WORKSPACE_DIR" "$REPORTS_DIR" "$REPORT_DIR"

rsync -a --delete \
  --exclude '.build' \
  --exclude '.axcoder' \
  --exclude '.scratch' \
  --exclude '.sandbox_home' \
  --exclude '.sandbox_tmp' \
  --exclude '.clang-module-cache' \
  --exclude '.swift-module-cache' \
  --exclude 'DerivedData' \
  --exclude '__pycache__' \
  --exclude '.DS_Store' \
  "$ROOT_DIR/x-terminal/" "$SNAPSHOT_DIR/x-terminal/"

cp -f "$ROOT_DIR/scripts/run_xhub_doctor_from_source.command" \
  "$SNAPSHOT_DIR/scripts/run_xhub_doctor_from_source.command"
chmod +x \
  "$SNAPSHOT_DIR/scripts/run_xhub_doctor_from_source.command" \
  "$SNAPSHOT_DIR/x-terminal/tools/run_xterminal_from_source.command"

python3 - "$SOURCE_REPORT_PATH" "$REPAIR_LEDGER_PATH" <<'PY'
import json
import sys

source_report_path, repair_ledger_path = sys.argv[1:3]
memory_route_truth_projection = {
    "projectionSource": "xt_model_route_diagnostics_summary",
    "completeness": "partial_xt_projection",
    "requestSnapshot": {
        "jobType": "unknown",
        "mode": "unknown",
        "projectIDPresent": "true",
        "sensitivity": "unknown",
        "trustLevel": "unknown",
        "budgetClass": "unknown",
        "remoteAllowedByPolicy": "unknown",
        "killSwitchState": "unknown",
    },
    "resolutionChain": [
        {
            "scopeKind": "project_mode",
            "scopeRefRedacted": "unknown",
            "matched": "unknown",
            "profileID": "unknown",
            "selectionStrategy": "unknown",
            "skipReason": "upstream_route_truth_unavailable_in_xt_export",
        },
        {
            "scopeKind": "project",
            "scopeRefRedacted": "unknown",
            "matched": "unknown",
            "profileID": "unknown",
            "selectionStrategy": "unknown",
            "skipReason": "upstream_route_truth_unavailable_in_xt_export",
        },
    ],
    "winningProfile": {
        "resolvedProfileID": "unknown",
        "scopeKind": "unknown",
        "scopeRefRedacted": "unknown",
        "selectionStrategy": "unknown",
        "policyVersion": "unknown",
        "disabled": "unknown",
    },
    "winningBinding": {
        "bindingKind": "unknown",
        "bindingKey": "unknown",
        "provider": "mlx",
        "modelID": "mlx.qwen",
        "selectedByUser": "unknown",
    },
    "routeResult": {
        "routeSource": "local_fallback_after_remote_error",
        "routeReasonCode": "remote_unreachable",
        "fallbackApplied": "true",
        "fallbackReason": "remote_unreachable",
        "remoteAllowed": "unknown",
        "auditRef": "route_event_1",
        "denyCode": "unknown",
    },
    "constraintSnapshot": {
        "remoteAllowedAfterUserPref": "unknown",
        "remoteAllowedAfterPolicy": "unknown",
        "budgetClass": "unknown",
        "budgetBlocked": "unknown",
        "policyBlockedRemote": "unknown",
    },
}
project_context_presentation = {
    "sourceKind": "latest_coder_usage",
    "projectLabel": "Smoke Project",
    "sourceBadge": "Latest Usage",
    "statusLine": "最近一次 coder context assembly 已被捕获，Doctor 现在显示的是 runtime 实际喂给 project AI 的背景，而不只是静态配置。",
    "dialogueMetric": "Extended 40 Pairs · 40 pairs · selected 18p",
    "depthMetric": "Full · m4_full_scan",
    "dialogueLine": "Recent Project Dialogue：Extended 40 Pairs · 40 pairs · 本轮选中 18 pairs · floor 8 已满足 · source xt_cache · low-signal drop 2",
    "depthLine": "Project Context Depth：Full · serving m4_full_scan · memory unknown",
    "coverageMetric": "wf yes · ev yes · gd no · xlink 2",
    "coverageLine": "Coverage：workflow present · evidence present · guidance absent · cross-link hints 2",
    "boundaryMetric": "personal excluded",
    "boundaryLine": "Boundary：personal memory excluded · project_ai_default_scopes_to_project_memory_only",
    "userSourceBadge": "实际运行",
    "userStatusLine": "这里显示的是最近一次真正喂给 project AI 的背景，不是静态配置。",
    "userDialogueMetric": "Extended 40 Pairs · 40 pairs",
    "userDepthMetric": "Full",
    "userCoverageSummary": "已带工作流、执行证据、关联线索",
    "userBoundarySummary": "默认不读取你的个人记忆",
    "userDialogueLine": "这轮保留了 40 pairs 的最近项目对话窗口，本轮实际选中 18 组对话。",
    "userDepthLine": "Full 背景深度会决定这轮带入多少项目工作流、review 和执行证据。"
}
project_memory_policy_projection = {
    "schema_version": "xhub.project_memory_policy.v1",
    "configured_recent_project_dialogue_profile": "auto_max",
    "configured_project_context_depth": "auto",
    "recommended_recent_project_dialogue_profile": "extended_40_pairs",
    "recommended_project_context_depth": "deep",
    "effective_recent_project_dialogue_profile": "extended_40_pairs",
    "effective_project_context_depth": "deep",
    "a_tier_memory_ceiling": "m3_deep_dive",
    "audit_ref": "audit-project-memory-policy-1",
}
project_memory_assembly_resolution_projection = {
    "schema_version": "xhub.memory_assembly_resolution.v1",
    "role": "project_ai",
    "dominant_mode": "execution",
    "trigger": "active_project_chat",
    "configured_depth": "auto",
    "recommended_depth": "deep",
    "effective_depth": "deep",
    "ceiling_from_tier": "m3_deep_dive",
    "ceiling_hit": True,
    "selected_slots": [
        "recent_project_dialogue_window",
        "focused_project_anchor_pack",
        "active_workflow",
        "selected_cross_link_hints",
        "guidance",
    ],
    "selected_planes": [
        "project_dialogue_plane",
        "project_anchor_plane",
        "workflow_plane",
        "cross_link_plane",
        "guidance_plane",
    ],
    "selected_serving_objects": [
        "recent_project_dialogue_window",
        "focused_project_anchor_pack",
        "active_workflow",
        "selected_cross_link_hints",
        "guidance",
    ],
    "excluded_blocks": ["assistant_plane", "personal_memory", "portfolio_brief"],
    "budget_summary": "selected 5 serving objects under A-tier deep ceiling",
    "audit_ref": "audit-project-memory-resolution-1",
}
supervisor_memory_policy_projection = {
    "schema_version": "xhub.supervisor_memory_policy.v1",
    "configured_supervisor_recent_raw_context_profile": "auto_max",
    "configured_review_memory_depth": "auto",
    "recommended_supervisor_recent_raw_context_profile": "extended_40_pairs",
    "recommended_review_memory_depth": "deep_dive",
    "effective_supervisor_recent_raw_context_profile": "extended_40_pairs",
    "effective_review_memory_depth": "deep_dive",
    "s_tier_review_memory_ceiling": "m4_full_scan",
    "audit_ref": "audit-supervisor-memory-policy-1",
}
supervisor_memory_assembly_resolution_projection = {
    "schema_version": "xhub.memory_assembly_resolution.v1",
    "role": "supervisor",
    "dominant_mode": "project_first",
    "trigger": "heartbeat_no_progress_review",
    "configured_depth": "auto",
    "recommended_depth": "deep_dive",
    "effective_depth": "deep_dive",
    "ceiling_from_tier": "m4_full_scan",
    "ceiling_hit": False,
    "selected_slots": [
        "recent_raw_dialogue_window",
        "portfolio_brief",
        "focused_project_anchor_pack",
        "delta_feed",
        "conflict_set",
        "context_refs",
        "evidence_pack",
    ],
    "selected_planes": ["continuity_lane", "project_plane", "cross_link_plane"],
    "selected_serving_objects": [
        "recent_raw_dialogue_window",
        "portfolio_brief",
        "focused_project_anchor_pack",
        "delta_feed",
        "conflict_set",
        "context_refs",
        "evidence_pack",
    ],
    "excluded_blocks": [],
    "budget_summary": "selected 7 review objects under S-tier full-scan ceiling",
    "audit_ref": "audit-supervisor-memory-resolution-1",
}
durable_candidate_mirror_projection = {
    "status": "mirrored_to_hub",
    "target": "hub_candidate_carrier_shadow_thread",
    "attempted": True,
    "errorCode": None,
    "localStoreRole": "cache|fallback|edit_buffer",
}
local_store_write_projection = {
    "personalMemoryIntent": "manual_edit_buffer_commit",
    "crossLinkIntent": "after_turn_cache_refresh",
    "personalReviewIntent": "derived_refresh",
}
hub_memory_prompt_projection = {
    "projection_source": "hub_generate_done_metadata",
    "canonical_item_count": 3,
    "working_set_turn_count": 18,
    "runtime_truth_item_count": 2,
    "runtime_truth_source_kinds": [
        "guidance_injection",
        "heartbeat_projection",
    ],
}
project_remote_snapshot_cache_projection = {
    "source": "hub_memory_v1_grpc",
    "freshness": "ttl_cache",
    "cacheHit": True,
    "scope": "mode=project_chat project_id=smoke-project",
    "cachedAtMs": 1741300111000,
    "ageMs": 6000,
    "ttlRemainingMs": 9000,
}
supervisor_remote_snapshot_cache_projection = {
    "source": "hub",
    "freshness": "ttl_cache",
    "cacheHit": True,
    "scope": "mode=supervisor_orchestration project_id=(none)",
    "cachedAtMs": 1741300114000,
    "ageMs": 3000,
    "ttlRemainingMs": 12000,
}
heartbeat_governance_projection = {
    "projectId": "project-alpha",
    "projectName": "Alpha",
    "statusDigest": "done candidate",
    "currentStateSummary": "Validation is wrapping up for release",
    "nextStepSummary": "Ship release once final review clears",
    "blockerSummary": "Pending pre-done review",
    "lastHeartbeatAtMs": 1741300000000,
    "latestQualityBand": "weak",
    "latestQualityScore": 38,
    "weakReasons": ["evidence_weak", "completion_confidence_low"],
    "openAnomalyTypes": ["weak_done_claim"],
    "projectPhase": "release",
    "executionStatus": "done_candidate",
    "riskTier": "high",
    "digestVisibility": "shown",
    "digestReasonCodes": [
        "weak_done_claim",
        "quality_weak",
        "review_candidate_active",
    ],
    "digestWhatChangedText": "项目已接近完成，但完成声明证据偏弱。",
    "digestWhyImportantText": "完成声明证据偏弱，系统不能把“快做完了”直接当成真实完成。",
    "digestSystemNextStepText": "Ship release once final review clears",
    "progressHeartbeat": {
        "dimension": "progress_heartbeat",
        "configuredSeconds": 600,
        "recommendedSeconds": 180,
        "effectiveSeconds": 180,
        "effectiveReasonCodes": ["adjusted_for_project_phase_release"],
        "nextDueAtMs": 1741300120000,
        "nextDueReasonCodes": ["waiting_for_heartbeat_window"],
        "isDue": False,
    },
    "reviewPulse": {
        "dimension": "review_pulse",
        "configuredSeconds": 1200,
        "recommendedSeconds": 600,
        "effectiveSeconds": 600,
        "effectiveReasonCodes": [
            "adjusted_for_project_phase_release",
            "tightened_for_done_candidate_status",
        ],
        "nextDueAtMs": 1741299980000,
        "nextDueReasonCodes": ["pulse_review_window_elapsed"],
        "isDue": True,
    },
    "brainstormReview": {
        "dimension": "brainstorm_review",
        "configuredSeconds": 2400,
        "recommendedSeconds": 1200,
        "effectiveSeconds": 1200,
        "effectiveReasonCodes": ["adjusted_for_project_phase_release"],
        "nextDueAtMs": 1741300240000,
        "nextDueReasonCodes": ["waiting_for_brainstorm_window"],
        "isDue": False,
    },
    "nextReviewDue": {
        "kind": "review_pulse",
        "due": True,
        "atMs": 1741299980000,
        "reasonCodes": ["pulse_review_window_elapsed"],
    },
    "recoveryDecision": {
        "action": "queue_strategic_review",
        "urgency": "urgent",
        "reasonCode": "heartbeat_or_lane_signal_requires_governance_review",
        "summary": "Queue a deeper governance review before resuming autonomous execution.",
        "sourceSignals": [
            "anomaly:weak_done_claim",
            "review_candidate:pre_done_summary:r3_rescue:event_driven",
        ],
        "anomalyTypes": ["weak_done_claim"],
        "blockedLaneReasons": [],
        "blockedLaneCount": 0,
        "stalledLaneCount": 0,
        "failedLaneCount": 0,
        "recoveringLaneCount": 0,
        "requiresUserAction": False,
        "queuedReviewTrigger": "pre_done_summary",
        "queuedReviewLevel": "r3_rescue",
        "queuedReviewRunKind": "event_driven",
    },
    "projectMemoryReady": False,
    "projectMemoryStatusLine": "最近一次 Project AI memory 装配真相不可用，review explainability 会退回 heartbeat + cadence。",
    "projectMemoryIssueCodes": ["project_memory_usage_missing"],
    "projectMemoryTopIssueSummary": "最近一次 memory 装配真相不可用，Doctor 无法确认 review 是否看到了 Project AI 的最新工作流与执行证据。",
}
paired_route_set_snapshot = {
    "schemaVersion": "xt.paired_route_set.v1",
    "readiness": "local_ready",
    "readinessReasonCode": "local_pairing_ready_remote_unverified",
    "summaryLine": "当前已完成同网首配，但正式异网入口仍未完成验证。",
    "hubInstanceID": "hub-smoke-1",
    "pairingProfileEpoch": 4,
    "routePackVersion": "route-pack-2026-03-30",
    "activeRoute": {
        "routeKind": "lan",
        "host": "10.0.0.8",
        "pairingPort": 50052,
        "grpcPort": 50051,
        "hostKind": "private_ipv4",
        "source": "active_connection",
    },
    "lanRoute": {
        "routeKind": "lan",
        "host": "10.0.0.8",
        "pairingPort": 50052,
        "grpcPort": 50051,
        "hostKind": "private_ipv4",
        "source": "cached_profile_host",
    },
    "stableRemoteRoute": {
        "routeKind": "internet",
        "host": "hub.tailnet.example",
        "pairingPort": 50052,
        "grpcPort": 50051,
        "hostKind": "stable_named",
        "source": "cached_profile_internet_host",
    },
    "lastKnownGoodRoute": {
        "routeKind": "lan",
        "host": "10.0.0.8",
        "pairingPort": 50052,
        "grpcPort": 50051,
        "hostKind": "private_ipv4",
        "source": "fresh_pair_reconnect_smoke",
    },
    "cachedReconnectSmokeStatus": "succeeded",
    "cachedReconnectSmokeReasonCode": None,
    "cachedReconnectSmokeSummary": "same-LAN cached reconnect succeeded",
}
first_pair_completion_proof_snapshot = {
    "schema_version": "xt.first_pair_completion_proof.v1",
    "generated_at_ms": 1741300123000,
    "readiness": "local_ready",
    "same_lan_verified": True,
    "owner_local_approval_verified": True,
    "pairing_material_issued": True,
    "cached_reconnect_smoke_passed": True,
    "stable_remote_route_present": True,
    "remote_shadow_smoke_passed": False,
    "remote_shadow_smoke_status": "running",
    "remote_shadow_smoke_source": "dedicated_stable_remote_probe",
    "remote_shadow_triggered_at_ms": 1741300122500,
    "remote_shadow_completed_at_ms": None,
    "remote_shadow_route": "internet",
    "remote_shadow_reason_code": None,
    "remote_shadow_summary": "verifying stable remote route shadow path ...",
    "summary_line": "first pair is local ready; stable remote route verification is still running.",
}
payload = {
    "schemaVersion": "xt.unified_doctor_report.v1",
    "generatedAtMs": 1741300123,
    "overallState": "ready",
    "overallSummary": "Ready for first task",
    "readyForFirstTask": True,
    "currentFailureCode": "",
    "currentFailureIssue": None,
    "configuredModelRoles": 4,
    "availableModelCount": 1,
    "loadedModelCount": 1,
    "currentSessionID": "session-ready",
    "currentRoute": {
        "transportMode": "local",
        "routeLabel": "paired-local",
        "pairingPort": 50052,
        "grpcPort": 50051,
        "internetHost": "127.0.0.1",
    },
    "sections": [
        {
            "kind": "hub_reachability",
            "state": "ready",
            "headline": "Hub reachability is ready",
            "summary": "Hub pairing and gRPC are reachable.",
            "nextStep": "Start the first task.",
            "repairEntry": "home_supervisor_first_task",
            "detailLines": ["route=paired-local"],
        },
        {
            "kind": "model_route_readiness",
            "state": "ready",
            "headline": "Model route is ready, but recent project routes degraded",
            "summary": "Assigned models are visible, but recent project requests degraded during execution.",
            "nextStep": "Inspect route diagnostics for the affected project.",
            "repairEntry": "xt_choose_model",
            "memoryRouteTruthProjection": memory_route_truth_projection,
            "detailLines": [
                "configured_models=1",
                "recent_route_events_24h=2",
                "recent_route_failures_24h=1",
                "recent_remote_retry_recoveries_24h=1"
            ],
        },
        {
            "kind": "session_runtime_readiness",
            "state": "ready",
            "headline": "Session runtime is ready",
            "summary": "Runtime is healthy and project context assembly is available.",
            "nextStep": "Open the project and continue execution.",
            "repairEntry": "xt_diagnostics",
            "projectContextPresentation": project_context_presentation,
            "hubMemoryPromptProjection": hub_memory_prompt_projection,
            "projectMemoryPolicyProjection": project_memory_policy_projection,
            "projectMemoryAssemblyResolutionProjection": project_memory_assembly_resolution_projection,
            "projectRemoteSnapshotCacheProjection": project_remote_snapshot_cache_projection,
            "heartbeatGovernanceProjection": heartbeat_governance_projection,
            "supervisorMemoryPolicyProjection": supervisor_memory_policy_projection,
            "supervisorMemoryAssemblyResolutionProjection": supervisor_memory_assembly_resolution_projection,
            "supervisorRemoteSnapshotCacheProjection": supervisor_remote_snapshot_cache_projection,
            "durableCandidateMirrorProjection": durable_candidate_mirror_projection,
            "localStoreWriteProjection": local_store_write_projection,
            "detailLines": [
                "runtime_state=ready",
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=Smoke Project",
                "project_memory_v1_source=hub_memory_v1_grpc",
                "memory_v1_freshness=ttl_cache",
                "memory_v1_cache_hit=true",
                "memory_v1_remote_snapshot_cache_scope=mode=project_chat project_id=smoke-project",
                "memory_v1_remote_snapshot_cached_at_ms=1741300111000",
                "memory_v1_remote_snapshot_age_ms=6000",
                "memory_v1_remote_snapshot_ttl_remaining_ms=9000",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_selected_pairs=18",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=2",
                "project_context_depth=full",
                "effective_project_serving_profile=m4_full_scan",
                "workflow_present=true",
                "execution_evidence_present=true",
                "review_guidance_present=false",
                "cross_link_hints_selected=2",
                "personal_memory_excluded_reason=project_ai_default_scopes_to_project_memory_only",
                "hub_memory_prompt_projection_projection_source=hub_generate_done_metadata",
                "hub_memory_prompt_projection_canonical_item_count=3",
                "hub_memory_prompt_projection_working_set_turn_count=18",
                "hub_memory_prompt_projection_runtime_truth_item_count=2",
                "hub_memory_prompt_projection_runtime_truth_source_kinds=guidance_injection,heartbeat_projection",
                "heartbeat_project=Alpha (project-alpha)",
                "heartbeat_truth status_digest=done candidate",
                "heartbeat_quality_band=weak",
                "heartbeat_quality_score=38",
                "heartbeat_open_anomalies=weak_done_claim",
                "heartbeat_project_phase=release",
                "heartbeat_execution_status=done_candidate",
                "heartbeat_risk_tier=high",
                "heartbeat_project_memory_ready=false",
                "heartbeat_project_memory_status_line=最近一次 Project AI memory 装配真相不可用，review explainability 会退回 heartbeat + cadence。",
                "heartbeat_project_memory_issue_codes=project_memory_usage_missing",
                "heartbeat_project_memory_top_issue_summary=最近一次 memory 装配真相不可用，Doctor 无法确认 review 是否看到了 Project AI 的最新工作流与执行证据。",
                "memory_source=hub",
                "memory_freshness=ttl_cache",
                "memory_cache_hit=true",
                "remote_snapshot_cache_scope=mode=supervisor_orchestration project_id=(none)",
                "remote_snapshot_cached_at_ms=1741300114000",
                "remote_snapshot_age_ms=3000",
                "remote_snapshot_ttl_remaining_ms=12000",
                "heartbeat_effective_cadence progress=180s pulse=600s brainstorm=1200s",
                "heartbeat_next_review_due kind=review_pulse due=true at_ms=1741299980000 reasons=pulse_review_window_elapsed",
                "xt_local_store_writes personal_memory=manual_edit_buffer_commit cross_link=after_turn_cache_refresh personal_review=derived_refresh"
            ],
        }
    ],
    "consumedContracts": [
        "xt.ui_surface_state_contract.v1",
        "xt.unified_doctor_report_contract.v1"
    ],
    "firstPairCompletionProofSnapshot": first_pair_completion_proof_snapshot,
    "pairedRouteSetSnapshot": paired_route_set_snapshot,
    "reportPath": source_report_path,
}

with open(source_report_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")

repair_ledger_payload = {
    "schema_version": "xt.connectivity_repair_ledger_snapshot.v1",
    "updated_at_ms": 1741300124000,
    "entries": [
        {
            "schema_version": "xt.connectivity_repair_ledger_entry.v1",
            "entry_id": "repair-entry-1",
            "recorded_at_ms": 1741300123000,
            "trigger": "background_keepalive",
            "failure_code": "local_pairing_ready",
            "reason_family": "route_connectivity",
            "action": "wait_for_route_ready",
            "owner": "xt_runtime",
            "result": "deferred",
            "verify_result": "local_pairing_ready",
            "final_route": "none",
            "decision_reason_code": "waiting_for_same_lan_or_formal_remote_route",
            "incident_reason_code": "local_pairing_ready",
            "summary_line": "waiting to return to LAN or add a formal remote route."
        },
        {
            "schema_version": "xt.connectivity_repair_ledger_entry.v1",
            "entry_id": "repair-entry-2",
            "recorded_at_ms": 1741300124000,
            "trigger": "background_keepalive",
            "failure_code": "grpc_unavailable",
            "reason_family": "route_connectivity",
            "action": "remote_reconnect",
            "owner": "xt_runtime",
            "result": "succeeded",
            "verify_result": "remote_route_active",
            "final_route": "internet",
            "decision_reason_code": "retry_degraded_remote_route",
            "incident_reason_code": "remote_route_active",
            "summary_line": "remote route verified"
        }
    ],
}

with open(repair_ledger_path, "w", encoding="utf-8") as handle:
    json.dump(repair_ledger_payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

mkdir -p \
  "$SNAPSHOT_DIR/.sandbox_home" \
  "$SNAPSHOT_DIR/.sandbox_tmp" \
  "$SNAPSHOT_DIR/.scratch" \
  "$SNAPSHOT_DIR/.clang-module-cache" \
  "$SNAPSHOT_DIR/.swift-module-cache"

env \
  XTERMINAL_SOURCE_RUN_HOME="$SNAPSHOT_DIR/.sandbox_home" \
  XTERMINAL_SOURCE_RUN_TMPDIR="$SNAPSHOT_DIR/.sandbox_tmp" \
  XTERMINAL_SOURCE_RUN_SCRATCH_PATH="$SNAPSHOT_DIR/.scratch" \
  XTERMINAL_SOURCE_RUN_CLANG_MODULE_CACHE_PATH="$SNAPSHOT_DIR/.clang-module-cache" \
  XTERMINAL_SOURCE_RUN_SWIFT_MODULE_CACHE_PATH="$SNAPSHOT_DIR/.swift-module-cache" \
  XTERMINAL_SOURCE_RUN_DISABLE_SANDBOX=1 \
  XTERMINAL_SOURCE_RUN_DISABLE_INDEX_STORE=1 \
  bash "$SNAPSHOT_DIR/scripts/run_xhub_doctor_from_source.command" \
    xt \
    --workspace-root "$WORKSPACE_DIR" \
    --out-json "$OUTPUT_REPORT_PATH"

python3 - "$SOURCE_REPORT_PATH" "$OUTPUT_REPORT_PATH" "$REPAIR_LEDGER_PATH" "$FIRST_PAIR_PROOF_PATH" "$PAIRED_ROUTE_SET_PATH" "$EVIDENCE_PATH" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

source_report_path, output_report_path, repair_ledger_path, first_pair_proof_path, paired_route_set_path, evidence_path = sys.argv[1:7]
source_report_path = os.path.realpath(source_report_path)
output_report_path = os.path.realpath(output_report_path)
repair_ledger_path = os.path.realpath(repair_ledger_path)
first_pair_proof_path = os.path.realpath(first_pair_proof_path)
paired_route_set_path = os.path.realpath(paired_route_set_path)

with open(output_report_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

with open(repair_ledger_path, "r", encoding="utf-8") as handle:
    connectivity_repair_ledger = json.load(handle)

with open(first_pair_proof_path, "r", encoding="utf-8") as handle:
    first_pair_completion_proof = json.load(handle)

with open(paired_route_set_path, "r", encoding="utf-8") as handle:
    paired_route_set = json.load(handle)

assert payload["schema_version"] == "xhub.doctor_output.v1", payload["schema_version"]
assert payload["surface"] == "xt_export", payload["surface"]
assert payload["overall_state"] == "ready", payload["overall_state"]
assert payload["ready_for_first_task"] is True, payload["ready_for_first_task"]
assert payload["summary"]["failed"] == 0, payload["summary"]
assert os.path.realpath(payload["report_path"]) == output_report_path, payload["report_path"]
assert os.path.realpath(payload["source_report_path"]) == source_report_path, payload["source_report_path"]
assert "xt.unified_doctor_report_contract.v1" in payload["consumed_contracts"], payload["consumed_contracts"]
first_pair_payload = payload["first_pair_completion_proof_snapshot"]
paired_route_payload = payload["paired_route_set_snapshot"]
assert first_pair_payload is not None, payload
assert paired_route_payload is not None, payload
assert first_pair_payload["readiness"] == "local_ready", first_pair_payload
assert first_pair_payload["remote_shadow_smoke_status"] == "running", first_pair_payload
assert first_pair_payload["remote_shadow_smoke_source"] == "dedicated_stable_remote_probe", first_pair_payload
assert first_pair_payload["stable_remote_route_present"] is True, first_pair_payload
assert paired_route_payload["readiness"] == "local_ready", paired_route_payload
assert paired_route_payload["readiness_reason_code"] == "local_pairing_ready_remote_unverified", paired_route_payload
assert paired_route_payload["stable_remote_route"]["host"] == "hub.tailnet.example", paired_route_payload
assert paired_route_payload["cached_reconnect_smoke_status"] == "succeeded", paired_route_payload
assert first_pair_completion_proof["readiness"] == "local_ready", first_pair_completion_proof
assert first_pair_completion_proof["remote_shadow_smoke_status"] == "running", first_pair_completion_proof
assert paired_route_set["readiness"] == "local_ready", paired_route_set
assert paired_route_set["stable_remote_route"]["host"] == "hub.tailnet.example", paired_route_set

session_runtime = next(
    check for check in payload["checks"]
    if check["check_id"] == "session_runtime_readiness"
)
model_route = next(
    check for check in payload["checks"]
    if check["check_id"] == "model_route_readiness"
)
project_context_summary = session_runtime.get("project_context_summary")
hub_memory_prompt_projection_snapshot = session_runtime.get("hub_memory_prompt_projection")
project_memory_policy = session_runtime.get("project_memory_policy")
project_memory_assembly_resolution = session_runtime.get("project_memory_assembly_resolution")
project_remote_snapshot_cache_snapshot = session_runtime.get("project_remote_snapshot_cache_snapshot")
heartbeat_governance_snapshot = session_runtime.get("heartbeat_governance_snapshot")
supervisor_memory_policy = session_runtime.get("supervisor_memory_policy")
supervisor_memory_assembly_resolution = session_runtime.get("supervisor_memory_assembly_resolution")
supervisor_remote_snapshot_cache_snapshot = session_runtime.get("supervisor_remote_snapshot_cache_snapshot")
durable_candidate_mirror_snapshot = session_runtime.get("durable_candidate_mirror_snapshot")
local_store_write_snapshot = session_runtime.get("local_store_write_snapshot")
memory_route_truth_snapshot = model_route.get("memory_route_truth_snapshot")
assert project_context_summary is not None, session_runtime
assert hub_memory_prompt_projection_snapshot is not None, session_runtime
assert project_memory_policy is not None, session_runtime
assert project_memory_assembly_resolution is not None, session_runtime
assert project_remote_snapshot_cache_snapshot is not None, session_runtime
assert heartbeat_governance_snapshot is not None, session_runtime
assert supervisor_memory_policy is not None, session_runtime
assert supervisor_memory_assembly_resolution is not None, session_runtime
assert supervisor_remote_snapshot_cache_snapshot is not None, session_runtime
assert durable_candidate_mirror_snapshot is not None, session_runtime
assert local_store_write_snapshot is not None, session_runtime
assert memory_route_truth_snapshot is not None, model_route
assert project_context_summary["source_kind"] == "latest_coder_usage", project_context_summary
assert project_context_summary["project_label"] == "Smoke Project", project_context_summary
assert "40 pairs" in project_context_summary["dialogue_metric"], project_context_summary
assert "Full" in project_context_summary["depth_metric"], project_context_summary
assert hub_memory_prompt_projection_snapshot["projection_source"] == "hub_generate_done_metadata", hub_memory_prompt_projection_snapshot
assert hub_memory_prompt_projection_snapshot["canonical_item_count"] == 3, hub_memory_prompt_projection_snapshot
assert hub_memory_prompt_projection_snapshot["working_set_turn_count"] == 18, hub_memory_prompt_projection_snapshot
assert hub_memory_prompt_projection_snapshot["runtime_truth_item_count"] == 2, hub_memory_prompt_projection_snapshot
assert hub_memory_prompt_projection_snapshot["runtime_truth_source_kinds"] == ["guidance_injection", "heartbeat_projection"], hub_memory_prompt_projection_snapshot
assert project_memory_policy["effective_project_context_depth"] == "deep", project_memory_policy
assert project_memory_policy["a_tier_memory_ceiling"] == "m3_deep_dive", project_memory_policy
assert project_memory_assembly_resolution["role"] == "project_ai", project_memory_assembly_resolution
assert project_memory_assembly_resolution["trigger"] == "active_project_chat", project_memory_assembly_resolution
assert project_memory_assembly_resolution["ceiling_hit"] is True, project_memory_assembly_resolution
assert "recent_project_dialogue_window" in project_memory_assembly_resolution["selected_slots"], project_memory_assembly_resolution
assert project_remote_snapshot_cache_snapshot["source"] == "hub_memory_v1_grpc", project_remote_snapshot_cache_snapshot
assert project_remote_snapshot_cache_snapshot["freshness"] == "ttl_cache", project_remote_snapshot_cache_snapshot
assert project_remote_snapshot_cache_snapshot["cache_hit"] is True, project_remote_snapshot_cache_snapshot
assert project_remote_snapshot_cache_snapshot["scope"] == "mode=project_chat project_id=smoke-project", project_remote_snapshot_cache_snapshot
assert project_remote_snapshot_cache_snapshot["age_ms"] == 6000, project_remote_snapshot_cache_snapshot
assert project_remote_snapshot_cache_snapshot["ttl_remaining_ms"] == 9000, project_remote_snapshot_cache_snapshot
assert heartbeat_governance_snapshot["project_id"] == "project-alpha", heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["project_name"] == "Alpha", heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["latest_quality_band"] == "weak", heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["review_pulse"]["configured_seconds"] == 1200, heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["review_pulse"]["recommended_seconds"] == 600, heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["review_pulse"]["effective_seconds"] == 600, heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["next_review_due"]["kind"] == "review_pulse", heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["next_review_due"]["due"] is True, heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["recovery_decision"]["action_display_text"] == "排队治理复盘", heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["recovery_decision"]["reason_display_text"] == "heartbeat 或 lane 信号要求先做治理复盘", heartbeat_governance_snapshot
assert heartbeat_governance_snapshot["recovery_decision"]["system_next_step_display_text"] == "系统会先基于事件触发 · pre-done 信号排队一次救援复盘，并在下一个 safe point 注入 guidance", heartbeat_governance_snapshot
assert supervisor_memory_policy["effective_review_memory_depth"] == "deep_dive", supervisor_memory_policy
assert supervisor_memory_policy["s_tier_review_memory_ceiling"] == "m4_full_scan", supervisor_memory_policy
assert supervisor_memory_assembly_resolution["role"] == "supervisor", supervisor_memory_assembly_resolution
assert supervisor_memory_assembly_resolution["trigger"] == "heartbeat_no_progress_review", supervisor_memory_assembly_resolution
assert "continuity_lane" in supervisor_memory_assembly_resolution["selected_planes"], supervisor_memory_assembly_resolution
assert supervisor_remote_snapshot_cache_snapshot["source"] == "hub", supervisor_remote_snapshot_cache_snapshot
assert supervisor_remote_snapshot_cache_snapshot["freshness"] == "ttl_cache", supervisor_remote_snapshot_cache_snapshot
assert supervisor_remote_snapshot_cache_snapshot["cache_hit"] is True, supervisor_remote_snapshot_cache_snapshot
assert supervisor_remote_snapshot_cache_snapshot["scope"] == "mode=supervisor_orchestration project_id=(none)", supervisor_remote_snapshot_cache_snapshot
assert supervisor_remote_snapshot_cache_snapshot["age_ms"] == 3000, supervisor_remote_snapshot_cache_snapshot
assert supervisor_remote_snapshot_cache_snapshot["ttl_remaining_ms"] == 12000, supervisor_remote_snapshot_cache_snapshot
assert durable_candidate_mirror_snapshot["status"] == "mirrored_to_hub", durable_candidate_mirror_snapshot
assert durable_candidate_mirror_snapshot["target"] == "hub_candidate_carrier_shadow_thread", durable_candidate_mirror_snapshot
assert durable_candidate_mirror_snapshot["attempted"] is True, durable_candidate_mirror_snapshot
assert durable_candidate_mirror_snapshot["local_store_role"] == "cache|fallback|edit_buffer", durable_candidate_mirror_snapshot
assert local_store_write_snapshot["personal_memory_intent"] == "manual_edit_buffer_commit", local_store_write_snapshot
assert local_store_write_snapshot["cross_link_intent"] == "after_turn_cache_refresh", local_store_write_snapshot
assert local_store_write_snapshot["personal_review_intent"] == "derived_refresh", local_store_write_snapshot
assert memory_route_truth_snapshot["projection_source"] == "xt_model_route_diagnostics_summary", memory_route_truth_snapshot
assert memory_route_truth_snapshot["completeness"] == "partial_xt_projection", memory_route_truth_snapshot
assert memory_route_truth_snapshot["route_result"]["route_source"] == "local_fallback_after_remote_error", memory_route_truth_snapshot
assert memory_route_truth_snapshot["route_result"]["fallback_applied"] == "true", memory_route_truth_snapshot
assert memory_route_truth_snapshot["winning_binding"]["provider"] == "mlx", memory_route_truth_snapshot
assert connectivity_repair_ledger["schema_version"] == "xt.connectivity_repair_ledger_snapshot.v1", connectivity_repair_ledger
assert len(connectivity_repair_ledger["entries"]) == 2, connectivity_repair_ledger
assert connectivity_repair_ledger["entries"][-1]["action"] == "remote_reconnect", connectivity_repair_ledger
assert connectivity_repair_ledger["entries"][-1]["result"] == "succeeded", connectivity_repair_ledger
assert connectivity_repair_ledger["entries"][-1]["verify_result"] == "remote_route_active", connectivity_repair_ledger
assert connectivity_repair_ledger["entries"][-1]["final_route"] == "internet", connectivity_repair_ledger

evidence = {
    "schema_version": "xhub.doctor_xt_source_smoke_evidence.v1",
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": "pass",
    "smoke_kind": "xt_source_export",
    "source_report_path": source_report_path,
    "output_report_path": output_report_path,
    "first_pair_completion_proof_sidecar_path": first_pair_proof_path,
    "paired_route_set_sidecar_path": paired_route_set_path,
    "model_route_check_id": model_route["check_id"],
    "session_runtime_check_id": session_runtime["check_id"],
    "first_pair_completion_proof": first_pair_completion_proof,
    "paired_route_set": paired_route_set,
    "memory_route_truth_snapshot": memory_route_truth_snapshot,
    "project_context_summary": project_context_summary,
    "hub_memory_prompt_projection": hub_memory_prompt_projection_snapshot,
    "project_memory_policy": project_memory_policy,
    "project_memory_assembly_resolution": project_memory_assembly_resolution,
    "project_remote_snapshot_cache_snapshot": project_remote_snapshot_cache_snapshot,
    "heartbeat_governance_snapshot": heartbeat_governance_snapshot,
    "supervisor_memory_policy": supervisor_memory_policy,
    "supervisor_memory_assembly_resolution": supervisor_memory_assembly_resolution,
    "supervisor_remote_snapshot_cache_snapshot": supervisor_remote_snapshot_cache_snapshot,
    "durable_candidate_mirror_snapshot": durable_candidate_mirror_snapshot,
    "local_store_write_snapshot": local_store_write_snapshot,
    "connectivity_repair_ledger": connectivity_repair_ledger,
    "assertions": {
        "source_kind": {
            "expected": "latest_coder_usage",
            "actual": project_context_summary["source_kind"],
            "pass": project_context_summary["source_kind"] == "latest_coder_usage",
        },
        "project_label": {
            "expected": "Smoke Project",
            "actual": project_context_summary["project_label"],
            "pass": project_context_summary["project_label"] == "Smoke Project",
        },
        "project_source_badge": {
            "expected": "Latest Usage",
            "actual": project_context_summary["source_badge"],
            "pass": project_context_summary["source_badge"] == "Latest Usage",
        },
        "dialogue_metric_contains": {
            "expected_substring": "40 pairs",
            "actual": project_context_summary["dialogue_metric"],
            "pass": "40 pairs" in project_context_summary["dialogue_metric"],
        },
        "depth_metric_contains": {
            "expected_substring": "Full",
            "actual": project_context_summary["depth_metric"],
            "pass": "Full" in project_context_summary["depth_metric"],
        },
        "hub_memory_projection_source": {
            "expected": "hub_generate_done_metadata",
            "actual": hub_memory_prompt_projection_snapshot["projection_source"],
            "pass": hub_memory_prompt_projection_snapshot["projection_source"] == "hub_generate_done_metadata",
        },
        "hub_memory_canonical_item_count": {
            "expected": 3,
            "actual": hub_memory_prompt_projection_snapshot["canonical_item_count"],
            "pass": hub_memory_prompt_projection_snapshot["canonical_item_count"] == 3,
        },
        "hub_memory_working_set_turn_count": {
            "expected": 18,
            "actual": hub_memory_prompt_projection_snapshot["working_set_turn_count"],
            "pass": hub_memory_prompt_projection_snapshot["working_set_turn_count"] == 18,
        },
        "hub_memory_runtime_truth_item_count": {
            "expected": 2,
            "actual": hub_memory_prompt_projection_snapshot["runtime_truth_item_count"],
            "pass": hub_memory_prompt_projection_snapshot["runtime_truth_item_count"] == 2,
        },
        "hub_memory_runtime_truth_source_kinds": {
            "expected": ["guidance_injection", "heartbeat_projection"],
            "actual": hub_memory_prompt_projection_snapshot["runtime_truth_source_kinds"],
            "pass": hub_memory_prompt_projection_snapshot["runtime_truth_source_kinds"] == ["guidance_injection", "heartbeat_projection"],
        },
        "project_memory_effective_depth": {
            "expected": "deep",
            "actual": project_memory_policy["effective_project_context_depth"],
            "pass": project_memory_policy["effective_project_context_depth"] == "deep",
        },
        "project_memory_ceiling": {
            "expected": "m3_deep_dive",
            "actual": project_memory_policy["a_tier_memory_ceiling"],
            "pass": project_memory_policy["a_tier_memory_ceiling"] == "m3_deep_dive",
        },
        "project_memory_resolution_role": {
            "expected": "project_ai",
            "actual": project_memory_assembly_resolution["role"],
            "pass": project_memory_assembly_resolution["role"] == "project_ai",
        },
        "project_memory_resolution_trigger": {
            "expected": "active_project_chat",
            "actual": project_memory_assembly_resolution["trigger"],
            "pass": project_memory_assembly_resolution["trigger"] == "active_project_chat",
        },
        "project_remote_snapshot_cache_scope": {
            "expected": "mode=project_chat project_id=smoke-project",
            "actual": project_remote_snapshot_cache_snapshot["scope"],
            "pass": project_remote_snapshot_cache_snapshot["scope"] == "mode=project_chat project_id=smoke-project",
        },
        "project_remote_snapshot_cache_ttl_remaining_ms": {
            "expected": 9000,
            "actual": project_remote_snapshot_cache_snapshot["ttl_remaining_ms"],
            "pass": project_remote_snapshot_cache_snapshot["ttl_remaining_ms"] == 9000,
        },
        "heartbeat_project_id": {
            "expected": "project-alpha",
            "actual": heartbeat_governance_snapshot["project_id"],
            "pass": heartbeat_governance_snapshot["project_id"] == "project-alpha",
        },
        "heartbeat_latest_quality_band": {
            "expected": "weak",
            "actual": heartbeat_governance_snapshot["latest_quality_band"],
            "pass": heartbeat_governance_snapshot["latest_quality_band"] == "weak",
        },
        "heartbeat_review_pulse_effective_seconds": {
            "expected": 600,
            "actual": heartbeat_governance_snapshot["review_pulse"]["effective_seconds"],
            "pass": heartbeat_governance_snapshot["review_pulse"]["effective_seconds"] == 600,
        },
        "heartbeat_next_review_kind": {
            "expected": "review_pulse",
            "actual": heartbeat_governance_snapshot["next_review_due"]["kind"],
            "pass": heartbeat_governance_snapshot["next_review_due"]["kind"] == "review_pulse",
        },
        "heartbeat_next_review_due": {
            "expected": True,
            "actual": heartbeat_governance_snapshot["next_review_due"]["due"],
            "pass": heartbeat_governance_snapshot["next_review_due"]["due"] is True,
        },
        "supervisor_memory_effective_depth": {
            "expected": "deep_dive",
            "actual": supervisor_memory_policy["effective_review_memory_depth"],
            "pass": supervisor_memory_policy["effective_review_memory_depth"] == "deep_dive",
        },
        "supervisor_memory_ceiling": {
            "expected": "m4_full_scan",
            "actual": supervisor_memory_policy["s_tier_review_memory_ceiling"],
            "pass": supervisor_memory_policy["s_tier_review_memory_ceiling"] == "m4_full_scan",
        },
        "supervisor_memory_resolution_role": {
            "expected": "supervisor",
            "actual": supervisor_memory_assembly_resolution["role"],
            "pass": supervisor_memory_assembly_resolution["role"] == "supervisor",
        },
        "supervisor_memory_resolution_trigger": {
            "expected": "heartbeat_no_progress_review",
            "actual": supervisor_memory_assembly_resolution["trigger"],
            "pass": supervisor_memory_assembly_resolution["trigger"] == "heartbeat_no_progress_review",
        },
        "supervisor_remote_snapshot_cache_scope": {
            "expected": "mode=supervisor_orchestration project_id=(none)",
            "actual": supervisor_remote_snapshot_cache_snapshot["scope"],
            "pass": supervisor_remote_snapshot_cache_snapshot["scope"] == "mode=supervisor_orchestration project_id=(none)",
        },
        "supervisor_remote_snapshot_cache_ttl_remaining_ms": {
            "expected": 12000,
            "actual": supervisor_remote_snapshot_cache_snapshot["ttl_remaining_ms"],
            "pass": supervisor_remote_snapshot_cache_snapshot["ttl_remaining_ms"] == 12000,
        },
        "durable_candidate_mirror_status": {
            "expected": "mirrored_to_hub",
            "actual": durable_candidate_mirror_snapshot["status"],
            "pass": durable_candidate_mirror_snapshot["status"] == "mirrored_to_hub",
        },
        "durable_candidate_mirror_target": {
            "expected": "hub_candidate_carrier_shadow_thread",
            "actual": durable_candidate_mirror_snapshot["target"],
            "pass": durable_candidate_mirror_snapshot["target"] == "hub_candidate_carrier_shadow_thread",
        },
        "durable_candidate_local_store_role": {
            "expected": "cache|fallback|edit_buffer",
            "actual": durable_candidate_mirror_snapshot["local_store_role"],
            "pass": durable_candidate_mirror_snapshot["local_store_role"] == "cache|fallback|edit_buffer",
        },
        "local_store_write_personal_memory_intent": {
            "expected": "manual_edit_buffer_commit",
            "actual": local_store_write_snapshot["personal_memory_intent"],
            "pass": local_store_write_snapshot["personal_memory_intent"] == "manual_edit_buffer_commit",
        },
        "local_store_write_cross_link_intent": {
            "expected": "after_turn_cache_refresh",
            "actual": local_store_write_snapshot["cross_link_intent"],
            "pass": local_store_write_snapshot["cross_link_intent"] == "after_turn_cache_refresh",
        },
        "local_store_write_personal_review_intent": {
            "expected": "derived_refresh",
            "actual": local_store_write_snapshot["personal_review_intent"],
            "pass": local_store_write_snapshot["personal_review_intent"] == "derived_refresh",
        },
        "memory_projection_source": {
            "expected": "xt_model_route_diagnostics_summary",
            "actual": memory_route_truth_snapshot["projection_source"],
            "pass": memory_route_truth_snapshot["projection_source"] == "xt_model_route_diagnostics_summary",
        },
        "memory_completeness": {
            "expected": "partial_xt_projection",
            "actual": memory_route_truth_snapshot["completeness"],
            "pass": memory_route_truth_snapshot["completeness"] == "partial_xt_projection",
        },
        "memory_route_source": {
            "expected": "local_fallback_after_remote_error",
            "actual": memory_route_truth_snapshot["route_result"]["route_source"],
            "pass": memory_route_truth_snapshot["route_result"]["route_source"] == "local_fallback_after_remote_error",
        },
        "memory_binding_provider": {
            "expected": "mlx",
            "actual": memory_route_truth_snapshot["winning_binding"]["provider"],
            "pass": memory_route_truth_snapshot["winning_binding"]["provider"] == "mlx",
        },
        "connectivity_repair_entry_count": {
            "expected": 2,
            "actual": len(connectivity_repair_ledger["entries"]),
            "pass": len(connectivity_repair_ledger["entries"]) == 2,
        },
        "connectivity_repair_latest_action": {
            "expected": "remote_reconnect",
            "actual": connectivity_repair_ledger["entries"][-1]["action"],
            "pass": connectivity_repair_ledger["entries"][-1]["action"] == "remote_reconnect",
        },
        "connectivity_repair_latest_result": {
            "expected": "succeeded",
            "actual": connectivity_repair_ledger["entries"][-1]["result"],
            "pass": connectivity_repair_ledger["entries"][-1]["result"] == "succeeded",
        },
        "source_report_contract_present": {
            "expected": "xt.unified_doctor_report_contract.v1",
            "actual": payload["consumed_contracts"],
            "pass": "xt.unified_doctor_report_contract.v1" in payload["consumed_contracts"],
        },
        "first_pair_readiness": {
            "expected": "local_ready",
            "actual": first_pair_completion_proof["readiness"],
            "pass": first_pair_completion_proof["readiness"] == "local_ready",
        },
        "first_pair_remote_shadow_status": {
            "expected": "running",
            "actual": first_pair_completion_proof["remote_shadow_smoke_status"],
            "pass": first_pair_completion_proof["remote_shadow_smoke_status"] == "running",
        },
        "paired_route_readiness": {
            "expected": "local_ready",
            "actual": paired_route_set["readiness"],
            "pass": paired_route_set["readiness"] == "local_ready",
        },
        "paired_route_stable_remote_host": {
            "expected": "hub.tailnet.example",
            "actual": paired_route_set["stable_remote_route"]["host"],
            "pass": paired_route_set["stable_remote_route"]["host"] == "hub.tailnet.example",
        },
    },
}

os.makedirs(os.path.dirname(evidence_path), exist_ok=True)
with open(evidence_path, "w", encoding="utf-8") as handle:
    json.dump(evidence, handle, indent=2, sort_keys=True)
    handle.write("\n")

print("[xhub-doctor-xt-source-smoke] PASS")
print(f"[xhub-doctor-xt-source-smoke] source={source_report_path}")
print(f"[xhub-doctor-xt-source-smoke] output={output_report_path}")
print(f"[xhub-doctor-xt-source-smoke] evidence={os.path.realpath(evidence_path)}")
PY
