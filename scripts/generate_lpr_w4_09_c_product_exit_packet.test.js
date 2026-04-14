#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildProductExitPacket,
  buildRefreshReleasePreflight,
} = require("./generate_lpr_w4_09_c_product_exit_packet.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function makeOperatorRecovery(overrides = {}) {
  return {
    gate_verdict:
      "PASS(operator_recovery_report_generated_from_structured_snapshot_truth)",
    release_stance: "candidate_go",
    machine_decision: {
      support_ready: true,
      release_ready: true,
      source_gate_status: "pass",
      snapshot_smoke_status: "pass",
      require_real_release_stance: "candidate_go",
      action_category: "inspect_snapshot_before_retry",
    },
    local_service_truth: {
      primary_issue_reason_code: "xhub_local_service_unreachable",
      managed_process_state: "down",
      managed_start_attempt_count: 2,
    },
    recovery_classification: {
      action_category: "inspect_snapshot_before_retry",
      severity: "high",
      install_hint: "Inspect the managed service snapshot before retrying startup.",
    },
    recommended_actions: [
      {
        rank: 1,
        action_id: "inspect_managed_service_snapshot",
        title: "Inspect managed service snapshot before retry",
        command_or_ref:
          "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json",
      },
    ],
    support_faq: [
      {
        faq_id: "next_operator_move",
        question: "What should the operator do next?",
        answer: "Inspect managed service snapshot before retry.",
      },
    ],
    release_wording: {
      external_status_line:
        "Structured xhub_local_service doctor/export/recovery truth is integrated, and require-real closure is candidate_go.",
    },
    ...overrides,
  };
}

function makeOperatorChannelRecovery(overrides = {}) {
  return {
    gate_verdict:
      "PASS(channel_onboarding_recovery_report_generated_from_structured_doctor_truth)",
    release_stance: "preview_working",
    verdict_reason:
      "Structured operator-channel onboarding truth is available for channel_runtime_missing, so operator/support wording can reuse one machine-readable diagnosis.",
    machine_decision: {
      support_ready: true,
      source: "source_gate_summary",
      source_gate_status: "pass",
      all_source_smoke_status: "pass",
      overall_state: "degraded",
      ready_for_first_task: true,
      current_failure_code: "channel_runtime_missing",
      current_failure_issue: "channel_runtime",
      action_category: "restore_channel_admin_surface",
    },
    onboarding_truth: {
      overall_state: "degraded",
      ready_for_first_task: true,
      current_failure_code: "channel_runtime_missing",
      current_failure_issue: "channel_runtime",
      primary_check_kind: "channel_runtime",
      primary_check_status: "warn",
      primary_check_blocking: false,
      repair_destination_ref: "hub://settings/operator_channels",
      provider_ids: ["slack", "telegram"],
      error_codes: [],
      fetch_errors: [],
      required_next_steps: ["inspect_operator_channel_diagnostics"],
    },
    recovery_classification: {
      action_category: "restore_channel_admin_surface",
      severity: "high",
      install_hint:
        "Restore the Hub admin/onboarding surface before trusting any remote channel readiness snapshot.",
    },
    recommended_actions: [
      {
        rank: 1,
        action_id: "restore_channel_admin_surface",
        title: "Restore operator channel admin surface",
        command_or_ref: "hub://settings/operator_channels",
      },
      {
        rank: 2,
        action_id: "inspect_operator_channel_diagnostics",
        title: "查看诊断",
        command_or_ref: "hub://settings/diagnostics",
      },
    ],
    support_faq: [
      {
        faq_id: "why_fail_closed",
        question: "Why are remote requests still fail-closed?",
        answer:
          "Because operator-channel onboarding truth is degraded, governed remote approval must not proceed yet.",
      },
    ],
    release_wording: {
      external_status_line:
        "Structured operator-channel onboarding doctor truth is available, but this surface remains preview-working rather than validated.",
    },
    ...overrides,
  };
}

function makeRequireReal(overrides = {}) {
  return {
    gate_verdict: "PASS(require_real_samples_complete)",
    release_stance: "candidate_go",
    verdict_reason: "All require-real samples are captured.",
    machine_decision: {
      pending_samples: [],
      failed_samples: [],
      invalid_samples: [],
      synthetic_samples: [],
      missing_evidence_samples: [],
      all_samples_executed: true,
      all_samples_passed: true,
    },
    gate_readiness: {
      "LPR-G6": "candidate_pass(require_real_complete)",
    },
    ...overrides,
  };
}

function makeBoundary(overrides = {}) {
  return {
    status: "delivered(validated_mainline_release_oss_boundary_ready)",
    blockers: [],
    scope_boundary: {
      external_claims_limited_to: [
        "Hub doctor/export can emit structured xhub_local_service failure truth.",
      ],
    },
    ...overrides,
  };
}

function makeOssReadiness(overrides = {}) {
  return {
    status: "delivered(oss_minimal_runnable_package_go)",
    release_stance: "GO",
    missing_evidence: [],
    hard_lines: ["validated_mainline_only"],
    ...overrides,
  };
}

function makeDoctorSourceGate(overrides = {}) {
  return {
    overall_status: "pass",
    summary: { passed: 8, failed: 0 },
    project_memory_policy_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_project_memory_policy: {
        configured_recent_project_dialogue_profile: "auto",
        configured_project_context_depth: "auto",
        recommended_recent_project_dialogue_profile: "extended_40_pairs",
        recommended_project_context_depth: "deep",
        effective_recent_project_dialogue_profile: "extended_40_pairs",
        effective_project_context_depth: "deep",
        a_tier_memory_ceiling: "m3_deep_dive",
        audit_ref: "audit-project-memory-policy-1",
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_project_memory_policy: {
        configured_recent_project_dialogue_profile: "balanced_20_pairs",
        configured_project_context_depth: "plan_review",
        recommended_recent_project_dialogue_profile: "balanced_20_pairs",
        recommended_project_context_depth: "plan_review",
        effective_recent_project_dialogue_profile: "balanced_20_pairs",
        effective_project_context_depth: "plan_review",
        a_tier_memory_ceiling: "m2_plan_review",
        audit_ref: "audit-project-memory-policy-2",
      },
    },
    project_memory_assembly_resolution_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_project_memory_assembly_resolution: {
        role: "project_ai",
        dominant_mode: "execution",
        trigger: "active_project_chat",
        configured_depth: "auto",
        recommended_depth: "deep",
        effective_depth: "deep",
        ceiling_from_tier: "m3_deep_dive",
        ceiling_hit: true,
        selected_slots: [
          "recent_project_dialogue_window",
          "focused_project_anchor_pack",
          "active_workflow",
        ],
        selected_planes: [
          "project_dialogue_plane",
          "project_anchor_plane",
          "workflow_plane",
        ],
        selected_serving_objects: [
          "recent_project_dialogue_window",
          "focused_project_anchor_pack",
          "active_workflow",
        ],
        excluded_blocks: ["assistant_plane", "personal_memory"],
        budget_summary: "selected 3 serving objects under A-tier deep ceiling",
        audit_ref: "audit-project-memory-resolution-1",
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_project_memory_assembly_resolution: {
        role: "project_ai",
        dominant_mode: "plan_review",
        trigger: "pre_done_review",
        configured_depth: "plan_review",
        recommended_depth: "plan_review",
        effective_depth: "plan_review",
        ceiling_from_tier: "m2_plan_review",
        ceiling_hit: false,
        selected_slots: ["recent_project_dialogue_window", "focused_project_anchor_pack"],
        selected_planes: ["project_dialogue_plane", "project_anchor_plane"],
        selected_serving_objects: ["recent_project_dialogue_window", "focused_project_anchor_pack"],
        excluded_blocks: ["portfolio_brief"],
        budget_summary: "selected 2 serving objects under A-tier plan-review ceiling",
        audit_ref: "audit-project-memory-resolution-2",
      },
    },
    project_remote_snapshot_cache_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_project_remote_snapshot_cache_snapshot: {
        source: "hub_memory_v1_grpc",
        freshness: "ttl_cache",
        cache_hit: true,
        scope: "mode=project_chat project_id=proj-fixture",
        cached_at_ms: 1774000000000,
        age_ms: 6000,
        ttl_remaining_ms: 9000,
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_project_remote_snapshot_cache_snapshot: {
        source: "hub_memory_v1_grpc",
        freshness: "ttl_cache",
        cache_hit: true,
        scope: "mode=project_chat project_id=proj-fixture",
        cached_at_ms: 1774000000000,
        age_ms: 6000,
        ttl_remaining_ms: 9000,
      },
    },
    heartbeat_governance_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_heartbeat_governance_snapshot: {
        project_id: "project-alpha",
        project_name: "Alpha",
        status_digest: "done candidate",
        latest_quality_band: "weak",
        latest_quality_score: 38,
        weak_reasons: ["evidence_weak", "completion_confidence_low"],
        open_anomaly_types: ["weak_done_claim"],
        project_phase: "release",
        execution_status: "done_candidate",
        risk_tier: "high",
        progress_heartbeat_effective_seconds: 180,
        review_pulse_effective_seconds: 600,
        brainstorm_review_effective_seconds: 1200,
        next_review_kind: "review_pulse",
        next_review_due: true,
        recovery_decision: {
          action: "queue_strategic_review",
          action_display_text: "排队治理复盘",
          urgency: "urgent",
          urgency_display_text: "紧急处理",
          reason_code: "heartbeat_or_lane_signal_requires_governance_review",
          reason_display_text: "heartbeat 或 lane 信号要求先做治理复盘",
          system_next_step_display_text:
            "系统会先基于事件触发 · pre-done 信号排队一次救援复盘，并在下一个 safe point 注入 guidance",
          summary: "Queue a deeper governance review before resuming autonomous execution.",
          doctor_explainability_text:
            "系统会先基于事件触发 · pre-done 信号排队一次救援复盘，并在下一个 safe point 注入 guidance · 紧急度 紧急处理 · 原因 heartbeat 或 lane 信号要求先做治理复盘",
          source_signals: [
            "anomaly:weak_done_claim",
            "review_candidate:pre_done_summary:r3_rescue:event_driven",
          ],
          source_signal_display_texts: [
            "异常 完成声明证据偏弱",
            "复盘候选 pre-done 信号 / 一次救援复盘 / 事件触发",
          ],
          anomaly_types: ["weak_done_claim"],
          anomaly_type_display_texts: ["完成声明证据偏弱"],
          queued_review_trigger: "pre_done_summary",
          queued_review_trigger_display_text: "pre-done 信号",
          queued_review_level: "r3_rescue",
          queued_review_level_display_text: "一次救援复盘",
          queued_review_run_kind: "event_driven",
          queued_review_run_kind_display_text: "事件触发",
          requires_user_action: false,
          ignored_extra_field: "should_not_survive_compaction",
        },
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_heartbeat_governance_snapshot: {
        project_id: "project-beta",
        project_name: "Beta",
        status_digest: "blocked",
        latest_quality_band: "weak",
        latest_quality_score: 21,
        weak_reasons: ["blocker_unclear"],
        open_anomaly_types: ["queue_stall"],
        project_phase: "validation",
        execution_status: "blocked",
        risk_tier: "high",
        progress_heartbeat_effective_seconds: 300,
        review_pulse_effective_seconds: 450,
        brainstorm_review_effective_seconds: 900,
        next_review_kind: "review_pulse",
        next_review_due: false,
        recovery_decision: {
          action: "request_grant_follow_up",
          action_display_text: "grant / 授权跟进",
          urgency: "active",
          urgency_display_text: "主动处理",
          reason_code: "grant_follow_up_required",
          reason_display_text: "需要先发起 grant 跟进",
          system_next_step_display_text: "系统会先发起所需 grant 跟进，待放行后再继续恢复执行",
          summary: "Request the required grant follow-up before resuming autonomous execution.",
          doctor_explainability_text:
            "系统会先发起所需 grant 跟进，待放行后再继续恢复执行 · 紧急度 主动处理 · 原因 需要先发起 grant 跟进 · 需要用户动作",
          source_signals: ["lane_blocked_reason:grant_pending", "lane_blocked_count:1"],
          source_signal_display_texts: ["阻塞原因 等待授权", "阻塞 lane 1 条"],
          blocked_lane_reasons: ["grant_pending"],
          blocked_lane_reason_display_texts: ["等待授权"],
          blocked_lane_count: 1,
          requires_user_action: true,
        },
      },
    },
    supervisor_memory_policy_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_supervisor_memory_policy: {
        configured_supervisor_recent_raw_context_profile: "auto_max",
        configured_review_memory_depth: "auto",
        recommended_supervisor_recent_raw_context_profile: "extended_40_pairs",
        recommended_review_memory_depth: "deep_dive",
        effective_supervisor_recent_raw_context_profile: "extended_40_pairs",
        effective_review_memory_depth: "deep_dive",
        s_tier_review_memory_ceiling: "m4_full_scan",
        audit_ref: "audit-supervisor-memory-policy-1",
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_supervisor_memory_policy: {
        configured_supervisor_recent_raw_context_profile: "balanced_20_pairs",
        configured_review_memory_depth: "plan_review",
        recommended_supervisor_recent_raw_context_profile: "balanced_20_pairs",
        recommended_review_memory_depth: "plan_review",
        effective_supervisor_recent_raw_context_profile: "balanced_20_pairs",
        effective_review_memory_depth: "plan_review",
        s_tier_review_memory_ceiling: "m2_plan_review",
        audit_ref: "audit-supervisor-memory-policy-2",
      },
    },
    supervisor_memory_assembly_resolution_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_supervisor_memory_assembly_resolution: {
        role: "supervisor",
        dominant_mode: "project_first",
        trigger: "heartbeat_no_progress_review",
        configured_depth: "auto",
        recommended_depth: "deep_dive",
        effective_depth: "deep_dive",
        ceiling_from_tier: "m4_full_scan",
        ceiling_hit: false,
        selected_slots: [
          "recent_raw_dialogue_window",
          "portfolio_brief",
          "focused_project_anchor_pack",
          "delta_feed",
        ],
        selected_planes: ["continuity_lane", "project_plane", "cross_link_plane"],
        selected_serving_objects: [
          "recent_raw_dialogue_window",
          "portfolio_brief",
          "focused_project_anchor_pack",
          "delta_feed",
        ],
        excluded_blocks: [],
        budget_summary: "selected 4 review objects under S-tier full-scan ceiling",
        audit_ref: "audit-supervisor-memory-resolution-1",
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_supervisor_memory_assembly_resolution: {
        role: "supervisor",
        dominant_mode: "conversation",
        trigger: "periodic_pulse",
        configured_depth: "plan_review",
        recommended_depth: "plan_review",
        effective_depth: "plan_review",
        ceiling_from_tier: "m2_plan_review",
        ceiling_hit: false,
        selected_slots: ["recent_raw_dialogue_window", "focused_project_anchor_pack"],
        selected_planes: ["continuity_lane", "project_plane"],
        selected_serving_objects: ["recent_raw_dialogue_window", "focused_project_anchor_pack"],
        excluded_blocks: ["portfolio_brief"],
        budget_summary: "selected 2 review objects under S-tier plan-review ceiling",
        audit_ref: "audit-supervisor-memory-resolution-2",
      },
    },
    supervisor_remote_snapshot_cache_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_supervisor_remote_snapshot_cache_snapshot: {
        source: "hub",
        freshness: "ttl_cache",
        cache_hit: true,
        scope: "mode=supervisor_orchestration project_id=(none)",
        cached_at_ms: 1774000005000,
        age_ms: 3000,
        ttl_remaining_ms: 12000,
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_supervisor_remote_snapshot_cache_snapshot: {
        source: "hub",
        freshness: "ttl_cache",
        cache_hit: true,
        scope: "mode=supervisor_orchestration project_id=(none)",
        cached_at_ms: 1774000005000,
        age_ms: 3000,
        ttl_remaining_ms: 12000,
      },
    },
    durable_candidate_mirror_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_durable_candidate_mirror_snapshot: {
        status: "mirrored_to_hub",
        target: "hub_candidate_carrier",
        attempted: true,
        error_code: null,
        local_store_role: "cache_fallback_edit_buffer",
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_durable_candidate_mirror_snapshot: {
        status: "local_only",
        target: "hub_candidate_carrier",
        attempted: true,
        error_code: "hub_unreachable",
        local_store_role: "cache_fallback_edit_buffer",
      },
    },
    local_store_write_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_local_store_write_snapshot: {
        personal_memory_intent: "manual_edit_buffer_commit",
        cross_link_intent: "after_turn_cache_refresh",
        personal_review_intent: "derived_refresh",
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_local_store_write_snapshot: {
        personal_memory_intent: "manual_edit_buffer_commit",
        cross_link_intent: "after_turn_cache_refresh",
        personal_review_intent: "derived_refresh",
      },
    },
    xt_pairing_readiness_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_first_pair_completion_proof: {
        readiness: "local_ready",
        same_lan_verified: true,
        owner_local_approval_verified: true,
        pairing_material_issued: true,
        cached_reconnect_smoke_passed: false,
        stable_remote_route_present: true,
        remote_shadow_smoke_passed: false,
        remote_shadow_smoke_status: "running",
        remote_shadow_smoke_source: "dedicated_stable_remote_probe",
        remote_shadow_route: "internet",
        remote_shadow_reason_code: "remote_shadow_probe_inflight",
        remote_shadow_summary: "verifying stable remote route shadow path ...",
        summary_line: "local_ready waiting for stable remote route shadow verification",
        ignored_extra_field: "should_not_survive_compaction",
      },
      xt_source_paired_route_set: {
        readiness: "local_ready",
        readiness_reason_code: "remote_shadow_probe_running",
        summary_line: "LAN route active while remote shadow probe is still running",
        hub_instance_id: "hub_fixture_1",
        pairing_profile_epoch: "pair-epoch-20260322",
        route_pack_version: 7,
        active_route: {
          route_kind: "lan",
          host: "192.168.1.20",
          pairing_port: 50055,
          grpc_port: 50054,
          host_kind: "ipv4",
          source: "lan_discovery",
          ignored_extra_field: "should_not_survive_compaction",
        },
        lan_route: {
          route_kind: "lan",
          host: "192.168.1.20",
          pairing_port: 50055,
          grpc_port: 50054,
          host_kind: "ipv4",
          source: "lan_discovery",
        },
        stable_remote_route: {
          route_kind: "internet",
          host: "hub.tailnet.example",
          pairing_port: 50055,
          grpc_port: 50054,
          host_kind: "dns",
          source: "stable_remote_cache",
        },
        last_known_good_route: {
          route_kind: "lan",
          host: "192.168.1.20",
          pairing_port: 50055,
          grpc_port: 50054,
          host_kind: "ipv4",
          source: "last_known_good_cache",
        },
        cached_reconnect_smoke_status: "not_run",
        cached_reconnect_smoke_reason_code: "missing_cached_remote_session",
        cached_reconnect_smoke_summary: "cached reconnect smoke has not run yet",
        ignored_extra_field: "should_not_survive_compaction",
      },
      all_source_first_pair_completion_proof: {
        readiness: "remote_ready",
        same_lan_verified: true,
        owner_local_approval_verified: true,
        pairing_material_issued: true,
        cached_reconnect_smoke_passed: true,
        stable_remote_route_present: true,
        remote_shadow_smoke_passed: true,
        remote_shadow_smoke_status: "passed",
        remote_shadow_smoke_source: "cached_remote_reconnect_evidence",
        remote_shadow_route: "internet",
        remote_shadow_reason_code: "stable_remote_route_verified",
        remote_shadow_summary: "stable remote route was already verified by cached reconnect smoke.",
        summary_line: "remote_ready via cached reconnect smoke",
      },
      all_source_paired_route_set: {
        readiness: "remote_ready",
        readiness_reason_code: "stable_remote_route_verified",
        summary_line: "stable remote route promoted to active route after reconnect smoke",
        hub_instance_id: "hub_fixture_1",
        pairing_profile_epoch: "pair-epoch-20260322",
        route_pack_version: 7,
        active_route: {
          route_kind: "internet",
          host: "hub.tailnet.example",
          pairing_port: 50055,
          grpc_port: 50054,
          host_kind: "dns",
          source: "stable_remote_cache",
        },
        lan_route: {
          route_kind: "lan",
          host: "192.168.1.20",
          pairing_port: 50055,
          grpc_port: 50054,
          host_kind: "ipv4",
          source: "lan_discovery",
        },
        stable_remote_route: {
          route_kind: "internet",
          host: "hub.tailnet.example",
          pairing_port: 50055,
          grpc_port: 50054,
          host_kind: "dns",
          source: "stable_remote_cache",
        },
        last_known_good_route: {
          route_kind: "internet",
          host: "hub.tailnet.example",
          pairing_port: 50055,
          grpc_port: 50054,
          host_kind: "dns",
          source: "cached_reconnect_smoke",
        },
        cached_reconnect_smoke_status: "pass",
        cached_reconnect_smoke_reason_code: "cached_remote_reconnect_verified",
        cached_reconnect_smoke_summary: "cached reconnect smoke verified stable remote route",
      },
    },
    xt_memory_truth_closure_support: {
      xt_memory_truth_closure_smoke_status: "pass",
      xt_memory_truth_closure_snapshot: {
        truth_examples: [
          {
            raw_source: "hub",
            label: "Hub 记忆",
            explainable_label: "Hub 记忆（Hub durable truth）",
            truth_hint: "Hub durable truth",
          },
          {
            raw_source: "hub_memory_v1_grpc",
            label: "Hub 快照 + 本地 overlay",
            explainable_label: "Hub 快照 + 本地 overlay（快照拼接，非 durable 真相）",
            truth_hint: "快照拼接，非 durable 真相",
          },
        ],
        project_context: {
          memory_source: "hub_memory_v1_grpc",
          memory_source_label: "Hub 快照 + 本地 overlay",
          writer_gate_boundary_present: true,
        },
        supervisor_memory: {
          memory_source: "hub",
          mode_source_text: "当前记忆来源：Hub 记忆（Hub durable truth） · 用途：Supervisor 编排",
          continuity_detail_line: "本轮从Hub 记忆（Hub durable truth）带入连续对话与背景记忆。",
        },
        canonical_sync_closure: {
          doctor_summary_line: "Canonical memory 同步链路最近失败",
          audit_ref: "audit-project-alpha-incident-1",
          evidence_ref: "canonical_memory_item:item-project-alpha-incident-1",
          writeback_ref: "canonical_memory_item:item-project-alpha-incident-1",
          strict_issue_code: "memory:memory_canonical_sync_delivery_failed",
        },
      },
    },
    build_snapshot_inventory_support: {
      report_ref: "build/reports/build_snapshot_inventory.v1.json",
      build_snapshot_inventory_generation_status: "pass",
      inventory_summary: {
        summary_status: "within_retention_budget",
        verdict_reason: "Build snapshot roots exist, but timestamped historical siblings are already within the configured retention budget.",
        stale_history_surface_ids: [],
        largest_reclaim_candidate_surface_id: "hub",
        current_snapshot_total_bytes: 880553886,
        historical_snapshot_total_bytes: 3556349728,
        projected_prune_total_bytes: 0,
        projected_prune_history_count: 0,
        hub: {
          status: "within_retention_budget",
          snapshot_root_ref: "build/.xhub-build-src",
          snapshot_root_exists: true,
          retention_keep_count: 2,
          current_snapshot_ref: "build/.xhub-build-src",
          current_snapshot_size_bytes: 209339786,
          historical_snapshot_count: 2,
          historical_snapshot_total_bytes: 3556349728,
          would_prune_history_count: 0,
          would_prune_total_bytes: 0,
          would_keep_history_refs: [
            "build/.xhub-build-src-20260318-0751",
            "build/.xhub-build-src-20260318-0739",
          ],
          would_prune_history_refs: [],
        },
        xterminal: {
          status: "within_retention_budget",
          snapshot_root_ref: "build/.xterminal-build-src",
          snapshot_root_exists: true,
          retention_keep_count: 2,
          current_snapshot_ref: "build/.xterminal-build-src",
          current_snapshot_size_bytes: 671214100,
          historical_snapshot_count: 0,
          historical_snapshot_total_bytes: 0,
          would_prune_history_count: 0,
          would_prune_total_bytes: 0,
          would_keep_history_refs: [],
          would_prune_history_refs: [],
        },
      },
    },
    ...overrides,
  };
}

run("product exit packet fails closed when release-facing artifacts are still missing", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery({
      release_stance: "no_go",
      machine_decision: {
        support_ready: true,
        release_ready: false,
        source_gate_status: "pass",
        snapshot_smoke_status: "pass",
        require_real_release_stance: "no_go",
        action_category: "inspect_snapshot_before_retry",
      },
      release_wording: {
        external_status_line:
          "Structured xhub_local_service doctor/export/recovery truth is integrated, but release remains blocked until require-real closure reaches candidate_go.",
      },
    }),
    requireReal: makeRequireReal({
      gate_verdict: "NO_GO(require_real_samples_pending)",
      release_stance: "no_go",
      verdict_reason: "Current machine still lacks a native-loadable real embedding dir.",
      next_required_artifacts: [
        "execute real sample: lpr_rr_01_embedding_real_model_dir_executes",
        "sample1 recommended action: source_native_loadable_embedding_model_dir",
      ],
      machine_decision: {
        pending_samples: ["lpr_rr_01_embedding_real_model_dir_executes"],
        failed_samples: [],
        invalid_samples: [],
        synthetic_samples: [],
        missing_evidence_samples: ["lpr_rr_01_embedding_real_model_dir_executes"],
        all_samples_executed: false,
        all_samples_passed: false,
        sample1_current_blockers: [
          "unsupported_quantization_config",
          "helper_local_service_disabled_before_probe",
        ],
        sample1_runtime_ready: true,
        sample1_execution_ready: false,
        sample1_overall_recommended_action_id: "source_native_loadable_embedding_model_dir",
        sample1_overall_recommended_action_summary:
          "Current embedding dirs are not torch/transformers-native loadable.",
        sample1_preferred_route: {
          route_id: "native_embedding_model_dir",
          ready: false,
          blocker:
            "current_embedding_dirs_not_torch_transformers_native_loadable(unsupported_quantization_config)",
          next_step:
            "source_one_native_torch_transformers_loadable_real_embedding_model_dir_or_restore_lmstudio_helper_daemon_then_rerun_sample1",
        },
        sample1_secondary_route: {
          route_id: "helper_bridge_reference",
          ready: false,
          blocker: "helper_local_service_disabled_before_probe",
          next_step:
            "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
        },
        sample1_operator_handoff: {
          handoff_state: "blocked",
          blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
          top_recommended_action: {
            action_id: "source_native_loadable_embedding_model_dir",
            action_summary:
              "Current embedding dirs look like LM Studio / MLX quantized layouts, not torch/transformers-native dirs. Source one native-loadable real embedding model dir first.",
          },
          operator_steps: [
            "Source or register one real torch/transformers-native embedding model directory on this machine.",
          ],
          helper_local_service_recovery: {
            helper_route_contract: {
              helper_route_ready_verdict:
                "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)",
            },
            top_recommended_action: {
              action_id: "enable_lm_studio_local_service",
            },
          },
        },
        sample1_candidate_acceptance_present: true,
        sample1_candidate_acceptance: {
          current_machine_state: {
            runtime_ready: true,
            filtered_out_task_mismatch_count: 4,
            top_recommended_action: {
              action_id: "source_or_import_different_native_embedding_model_dir",
            },
          },
          acceptance_contract: {
            required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
            required_loadability_verdict: "native_loadable",
          },
          current_no_go_example: {
            normalized_model_dir: "/models/quantized-embed",
            loadability_blocker: "unsupported_quantization_config",
          },
          filtered_out_examples: [
            {
              normalized_model_dir: "/models/text-generate",
              task_kind_status: "mismatch",
              inferred_task_hint: "text_generate",
            },
          ],
        },
        sample1_candidate_registration_present: true,
        sample1_candidate_registration: {
          requested_model_path: "/models/quantized-embed",
          normalized_model_dir: "/models/quantized-embed",
          candidate_validation: {
            gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
            loadability_blocker: "unsupported_quantization_config",
          },
          proposed_catalog_entry_payload: {
            id: "hf-embed-qwen",
            name: "Qwen Embed",
            backend: "transformers",
            modelPath: "/models/quantized-embed",
            taskKinds: ["embedding"],
          },
          machine_decision: {
            catalog_write_allowed_now: false,
            validation_pass_required_before_catalog_write: true,
            already_registered_in_catalog: false,
            top_recommended_action: {
              action_id: "source_different_native_embedding_model_dir",
              action_summary: "This dir is not sample1-ready.",
            },
          },
          target_catalog_paths: [
            {
              catalog_path: "/catalog/models_catalog.json",
              present: true,
              exact_model_dir_registered: false,
              proposed_model_id_conflict: false,
              recommended_action: "do_not_write_before_validator_pass",
            },
          ],
        },
      },
      sample1_require_real_support: {
        operator_handoff: {
          handoff_state: "blocked",
          blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
          search_recovery: {
            exact_path_known: true,
            exact_path_exists: true,
            exact_path_shortlist_refresh_command:
              "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --model-path /models/quantized-embed",
            exact_path_validation_command:
              "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js \\\n  --model-path /models/quantized-embed \\\n  --task-kind embedding",
            wide_shortlist_search_command:
              "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --wide-common-user-roots",
          },
          candidate_registration: {
            search_recovery_plan: {
              exact_path_known: true,
              exact_path_exists: true,
              exact_path_validation_command:
                "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js \\\n  --model-path /models/quantized-embed \\\n  --task-kind embedding",
              wide_shortlist_search_command:
                "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --wide-common-user-roots",
            },
          },
        },
      },
    }),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    boundary: null,
    ossReadiness: null,
    doctorSourceGate: makeDoctorSourceGate({ summary: { passed: 4, failed: 0 } }),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: false,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: false,
        },
      ],
    },
  });

  assert.equal(packet.gate_verdict, "NO_GO(product_exit_packet_fail_closed)");
  assert.equal(packet.machine_decision.exit_ready, false);
  assert.equal(packet.machine_decision.current_action_category, "inspect_snapshot_before_retry");
  assert.equal(packet.operator_handoff.top_recommended_action.action_id, "inspect_managed_service_snapshot");
  assert.deepEqual(packet.blockers, [
    "require_real_not_ready",
    "release_boundary_report_missing",
    "oss_release_readiness_missing",
    "release_refresh_inputs_missing",
  ]);
  assert.deepEqual(packet.release_refresh_preflight.missing_inputs, [
    "build/reports/xt_w3_release_ready_decision.v1.json",
    "build/reports/xt_w3_require_real_provenance.v2.json",
  ]);
  assert.deepEqual(packet.support_truth.require_real.machine_decision.sample1_current_blockers, [
    "unsupported_quantization_config",
    "helper_local_service_disabled_before_probe",
  ]);
  assert.deepEqual(packet.support_truth.require_real.next_required_artifacts, [
    "execute real sample: lpr_rr_01_embedding_real_model_dir_executes",
    "sample1 recommended action: source_native_loadable_embedding_model_dir",
  ]);
  assert.equal(
    packet.support_truth.require_real.machine_decision.sample1_overall_recommended_action_id,
    "source_native_loadable_embedding_model_dir"
  );
  assert.equal(packet.support_truth.require_real.machine_decision.sample1_preferred_route.ready, false);
  assert.equal(
    packet.support_truth.require_real.sample1_operator_handoff.blocker_class,
    "current_embedding_dirs_incompatible_with_native_transformers_load"
  );
  assert.equal(
    packet.operator_handoff.require_real_focus.top_recommended_action.action_id,
    "source_native_loadable_embedding_model_dir"
  );
  assert.equal(
    packet.operator_handoff.require_real_focus.verdict_reason,
    "Current machine still lacks a native-loadable real embedding dir."
  );
  assert.deepEqual(packet.operator_handoff.require_real_focus.next_required_artifacts, [
    "execute real sample: lpr_rr_01_embedding_real_model_dir_executes",
    "sample1 recommended action: source_native_loadable_embedding_model_dir",
  ]);
  assert.equal(
    packet.operator_handoff.require_real_focus.candidate_acceptance.acceptance_contract.required_gate_verdict,
    "PASS(sample1_candidate_native_loadable_for_real_execution)"
  );
  assert.equal(
    packet.operator_handoff.require_real_focus.helper_local_service_recovery.top_recommended_action.action_id,
    "enable_lm_studio_local_service"
  );
  assert.equal(
    packet.operator_handoff.require_real_focus.current_machine_state.filtered_out_task_mismatch_count,
    4
  );
  assert.equal(
    packet.operator_handoff.require_real_focus.filtered_out_examples[0].normalized_model_dir,
    "/models/text-generate"
  );
  assert.equal(
    packet.support_truth.require_real.sample1_candidate_acceptance.current_no_go_example.loadability_blocker,
    "unsupported_quantization_config"
  );
  assert.equal(
    packet.support_truth.require_real.sample1_candidate_registration.machine_decision.catalog_write_allowed_now,
    false
  );
  assert.equal(
    packet.operator_handoff.require_real_focus.candidate_registration.machine_decision.top_recommended_action.action_id,
    "source_different_native_embedding_model_dir"
  );
  assert.equal(
    packet.operator_handoff.require_real_focus.search_recovery.exact_path_validation_command.includes("--model-path /models/quantized-embed"),
    true
  );
  assert.equal(
    packet.operator_handoff.require_real_focus.candidate_registration.search_recovery_plan.wide_shortlist_search_command.includes("--wide-common-user-roots"),
    true
  );
});

run("product exit packet turns green only when operator, require-real, boundary, and OSS readiness all align", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.equal(
    packet.gate_verdict,
    "PASS(product_exit_packet_ready_for_operator_and_release_handoff)"
  );
  assert.equal(packet.machine_decision.exit_ready, true);
  assert.equal(packet.machine_decision.oss_release_ready, true);
  assert.equal(packet.machine_decision.operator_channel_support_ready, true);
  assert.equal(packet.release_handoff.oss_release_stance, "GO");
  assert.equal(
    packet.operator_handoff.channel_onboarding_focus.top_recommended_action.action_id,
    "restore_channel_admin_surface"
  );
  assert.match(
    packet.release_handoff.remote_channel_status_line,
    /preview-working/
  );
  assert.equal(packet.blockers.length, 0);
});

run("product exit packet highlights heartbeat governance visibility gaps in channel handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery({
      machine_decision: {
        support_ready: true,
        source: "source_gate_summary",
        source_gate_status: "pass",
        all_source_smoke_status: "pass",
        overall_state: "degraded",
        ready_for_first_task: true,
        current_failure_code: "channel_live_test_heartbeat_visibility_missing",
        current_failure_issue: "channel_live_test",
        action_category: "restore_heartbeat_governance_visibility",
      },
      onboarding_truth: {
        overall_state: "degraded",
        ready_for_first_task: true,
        current_failure_code: "channel_live_test_heartbeat_visibility_missing",
        current_failure_issue: "channel_live_test",
        primary_check_kind: "channel_live_test",
        primary_check_status: "warn",
        primary_check_blocking: false,
        repair_destination_ref: "hub://settings/operator_channels",
        provider_ids: ["slack"],
        error_codes: [],
        fetch_errors: [],
        required_next_steps: ["inspect_operator_channel_diagnostics"],
      },
      recovery_classification: {
        action_category: "restore_heartbeat_governance_visibility",
        severity: "high",
        install_hint:
          "Refresh first smoke proof until heartbeat governance visibility is present.",
      },
      recommended_actions: [
        {
          rank: 1,
          action_id: "restore_heartbeat_governance_visibility",
          title: "Restore heartbeat governance visibility",
          command_or_ref: "hub://settings/diagnostics",
        },
      ],
    }),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.equal(
    packet.operator_handoff.channel_onboarding_focus.heartbeat_governance_visibility_gap,
    true
  );
  assert.equal(
    packet.operator_handoff.channel_onboarding_focus.channel_focus_highlight,
    "First smoke proof still lacks heartbeat governance visibility."
  );
  assert.equal(
    packet.release_handoff.remote_channel_focus_highlight,
    "First smoke proof still lacks heartbeat governance visibility."
  );
});

run("product exit packet keeps release gate green when operator channel recovery report is absent", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.equal(
    packet.gate_verdict,
    "PASS(product_exit_packet_ready_for_operator_and_release_handoff)"
  );
  assert.equal(packet.machine_decision.operator_channel_support_ready, false);
  assert.equal(packet.artifact_status.operator_channel_recovery.present, false);
  assert.equal(packet.operator_handoff.channel_onboarding_focus, null);
  assert.equal(
    packet.release_handoff.remote_channel_status_line,
    "Structured operator-channel onboarding recovery wording is not available."
  );
  assert.equal(packet.blockers.length, 0);
});

run("product exit packet preserves compact durable candidate mirror support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.durable_candidate_mirror_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_durable_candidate_mirror_snapshot: {
      status: "mirrored_to_hub",
      target: "hub_candidate_carrier",
      attempted: true,
      error_code: null,
      local_store_role: "cache_fallback_edit_buffer",
    },
    all_source_durable_candidate_mirror_snapshot: {
      status: "local_only",
      target: "hub_candidate_carrier",
      attempted: true,
      error_code: "hub_unreachable",
      local_store_role: "cache_fallback_edit_buffer",
    },
  });
});

run("product exit packet preserves compact heartbeat governance support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.heartbeat_governance_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_heartbeat_governance_snapshot: {
      project_id: "project-alpha",
      project_name: "Alpha",
      status_digest: "done candidate",
      latest_quality_band: "weak",
      latest_quality_score: 38,
      weak_reasons: ["evidence_weak", "completion_confidence_low"],
      open_anomaly_types: ["weak_done_claim"],
      project_phase: "release",
      execution_status: "done_candidate",
      risk_tier: "high",
      progress_heartbeat_effective_seconds: 180,
      review_pulse_effective_seconds: 600,
      brainstorm_review_effective_seconds: 1200,
      next_review_kind: "review_pulse",
      next_review_due: true,
      recovery_decision: {
        action: "queue_strategic_review",
        action_display_text: "排队治理复盘",
        urgency: "urgent",
        urgency_display_text: "紧急处理",
        reason_code: "heartbeat_or_lane_signal_requires_governance_review",
        reason_display_text: "heartbeat 或 lane 信号要求先做治理复盘",
        system_next_step_display_text:
          "系统会先基于事件触发 · pre-done 信号排队一次救援复盘，并在下一个 safe point 注入 guidance",
        summary: "Queue a deeper governance review before resuming autonomous execution.",
        doctor_explainability_text:
          "系统会先基于事件触发 · pre-done 信号排队一次救援复盘，并在下一个 safe point 注入 guidance · 紧急度 紧急处理 · 原因 heartbeat 或 lane 信号要求先做治理复盘",
        source_signals: [
          "anomaly:weak_done_claim",
          "review_candidate:pre_done_summary:r3_rescue:event_driven",
        ],
        source_signal_display_texts: [
          "异常 完成声明证据偏弱",
          "复盘候选 pre-done 信号 / 一次救援复盘 / 事件触发",
        ],
        anomaly_types: ["weak_done_claim"],
        anomaly_type_display_texts: ["完成声明证据偏弱"],
        queued_review_trigger: "pre_done_summary",
        queued_review_trigger_display_text: "pre-done 信号",
        queued_review_level: "r3_rescue",
        queued_review_level_display_text: "一次救援复盘",
        queued_review_run_kind: "event_driven",
        queued_review_run_kind_display_text: "事件触发",
        requires_user_action: false,
      },
    },
    all_source_heartbeat_governance_snapshot: {
      project_id: "project-beta",
      project_name: "Beta",
      status_digest: "blocked",
      latest_quality_band: "weak",
      latest_quality_score: 21,
      weak_reasons: ["blocker_unclear"],
      open_anomaly_types: ["queue_stall"],
      project_phase: "validation",
      execution_status: "blocked",
      risk_tier: "high",
      progress_heartbeat_effective_seconds: 300,
      review_pulse_effective_seconds: 450,
      brainstorm_review_effective_seconds: 900,
      next_review_kind: "review_pulse",
      next_review_due: false,
      recovery_decision: {
        action: "request_grant_follow_up",
        action_display_text: "grant / 授权跟进",
        urgency: "active",
        urgency_display_text: "主动处理",
        reason_code: "grant_follow_up_required",
        reason_display_text: "需要先发起 grant 跟进",
        system_next_step_display_text: "系统会先发起所需 grant 跟进，待放行后再继续恢复执行",
        summary: "Request the required grant follow-up before resuming autonomous execution.",
        doctor_explainability_text:
          "系统会先发起所需 grant 跟进，待放行后再继续恢复执行 · 紧急度 主动处理 · 原因 需要先发起 grant 跟进 · 需要用户动作",
        source_signals: ["lane_blocked_reason:grant_pending", "lane_blocked_count:1"],
        source_signal_display_texts: ["阻塞原因 等待授权", "阻塞 lane 1 条"],
        blocked_lane_reasons: ["grant_pending"],
        blocked_lane_reason_display_texts: ["等待授权"],
        blocked_lane_count: 1,
        requires_user_action: true,
      },
    },
  });
});

run("product exit packet preserves compact project memory policy support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.project_memory_policy_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_project_memory_policy: {
      configured_recent_project_dialogue_profile: "auto",
      configured_project_context_depth: "auto",
      recommended_recent_project_dialogue_profile: "extended_40_pairs",
      recommended_project_context_depth: "deep",
      effective_recent_project_dialogue_profile: "extended_40_pairs",
      effective_project_context_depth: "deep",
      a_tier_memory_ceiling: "m3_deep_dive",
      audit_ref: "audit-project-memory-policy-1",
    },
    all_source_project_memory_policy: {
      configured_recent_project_dialogue_profile: "balanced_20_pairs",
      configured_project_context_depth: "plan_review",
      recommended_recent_project_dialogue_profile: "balanced_20_pairs",
      recommended_project_context_depth: "plan_review",
      effective_recent_project_dialogue_profile: "balanced_20_pairs",
      effective_project_context_depth: "plan_review",
      a_tier_memory_ceiling: "m2_plan_review",
      audit_ref: "audit-project-memory-policy-2",
    },
  });
  assert.deepEqual(packet.support_truth.doctor_source_gate.project_memory_assembly_resolution_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_project_memory_assembly_resolution: {
      role: "project_ai",
      dominant_mode: "execution",
      trigger: "active_project_chat",
      configured_depth: "auto",
      recommended_depth: "deep",
      effective_depth: "deep",
      ceiling_from_tier: "m3_deep_dive",
      ceiling_hit: true,
      selected_slots: ["recent_project_dialogue_window", "focused_project_anchor_pack", "active_workflow"],
      selected_planes: ["project_dialogue_plane", "project_anchor_plane", "workflow_plane"],
      selected_serving_objects: ["recent_project_dialogue_window", "focused_project_anchor_pack", "active_workflow"],
      excluded_blocks: ["assistant_plane", "personal_memory"],
      budget_summary: "selected 3 serving objects under A-tier deep ceiling",
      audit_ref: "audit-project-memory-resolution-1",
    },
    all_source_project_memory_assembly_resolution: {
      role: "project_ai",
      dominant_mode: "plan_review",
      trigger: "pre_done_review",
      configured_depth: "plan_review",
      recommended_depth: "plan_review",
      effective_depth: "plan_review",
      ceiling_from_tier: "m2_plan_review",
      ceiling_hit: false,
      selected_slots: ["recent_project_dialogue_window", "focused_project_anchor_pack"],
      selected_planes: ["project_dialogue_plane", "project_anchor_plane"],
      selected_serving_objects: ["recent_project_dialogue_window", "focused_project_anchor_pack"],
      excluded_blocks: ["portfolio_brief"],
      budget_summary: "selected 2 serving objects under A-tier plan-review ceiling",
      audit_ref: "audit-project-memory-resolution-2",
    },
  });
});

run("product exit packet preserves compact project remote snapshot cache support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.project_remote_snapshot_cache_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_project_remote_snapshot_cache_snapshot: {
      source: "hub_memory_v1_grpc",
      freshness: "ttl_cache",
      cache_hit: true,
      scope: "mode=project_chat project_id=proj-fixture",
      cached_at_ms: 1774000000000,
      age_ms: 6000,
      ttl_remaining_ms: 9000,
    },
    all_source_project_remote_snapshot_cache_snapshot: {
      source: "hub_memory_v1_grpc",
      freshness: "ttl_cache",
      cache_hit: true,
      scope: "mode=project_chat project_id=proj-fixture",
      cached_at_ms: 1774000000000,
      age_ms: 6000,
      ttl_remaining_ms: 9000,
    },
  });
});

run("product exit packet preserves compact supervisor memory policy support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.supervisor_memory_policy_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_supervisor_memory_policy: {
      configured_supervisor_recent_raw_context_profile: "auto_max",
      configured_review_memory_depth: "auto",
      recommended_supervisor_recent_raw_context_profile: "extended_40_pairs",
      recommended_review_memory_depth: "deep_dive",
      effective_supervisor_recent_raw_context_profile: "extended_40_pairs",
      effective_review_memory_depth: "deep_dive",
      s_tier_review_memory_ceiling: "m4_full_scan",
      audit_ref: "audit-supervisor-memory-policy-1",
    },
    all_source_supervisor_memory_policy: {
      configured_supervisor_recent_raw_context_profile: "balanced_20_pairs",
      configured_review_memory_depth: "plan_review",
      recommended_supervisor_recent_raw_context_profile: "balanced_20_pairs",
      recommended_review_memory_depth: "plan_review",
      effective_supervisor_recent_raw_context_profile: "balanced_20_pairs",
      effective_review_memory_depth: "plan_review",
      s_tier_review_memory_ceiling: "m2_plan_review",
      audit_ref: "audit-supervisor-memory-policy-2",
    },
  });
  assert.deepEqual(packet.support_truth.doctor_source_gate.supervisor_memory_assembly_resolution_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_supervisor_memory_assembly_resolution: {
      role: "supervisor",
      dominant_mode: "project_first",
      trigger: "heartbeat_no_progress_review",
      configured_depth: "auto",
      recommended_depth: "deep_dive",
      effective_depth: "deep_dive",
      ceiling_from_tier: "m4_full_scan",
      ceiling_hit: false,
      selected_slots: ["recent_raw_dialogue_window", "portfolio_brief", "focused_project_anchor_pack", "delta_feed"],
      selected_planes: ["continuity_lane", "project_plane", "cross_link_plane"],
      selected_serving_objects: ["recent_raw_dialogue_window", "portfolio_brief", "focused_project_anchor_pack", "delta_feed"],
      excluded_blocks: [],
      budget_summary: "selected 4 review objects under S-tier full-scan ceiling",
      audit_ref: "audit-supervisor-memory-resolution-1",
    },
    all_source_supervisor_memory_assembly_resolution: {
      role: "supervisor",
      dominant_mode: "conversation",
      trigger: "periodic_pulse",
      configured_depth: "plan_review",
      recommended_depth: "plan_review",
      effective_depth: "plan_review",
      ceiling_from_tier: "m2_plan_review",
      ceiling_hit: false,
      selected_slots: ["recent_raw_dialogue_window", "focused_project_anchor_pack"],
      selected_planes: ["continuity_lane", "project_plane"],
      selected_serving_objects: ["recent_raw_dialogue_window", "focused_project_anchor_pack"],
      excluded_blocks: ["portfolio_brief"],
      budget_summary: "selected 2 review objects under S-tier plan-review ceiling",
      audit_ref: "audit-supervisor-memory-resolution-2",
    },
  });
});

run("product exit packet preserves compact supervisor remote snapshot cache support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.supervisor_remote_snapshot_cache_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_supervisor_remote_snapshot_cache_snapshot: {
      source: "hub",
      freshness: "ttl_cache",
      cache_hit: true,
      scope: "mode=supervisor_orchestration project_id=(none)",
      cached_at_ms: 1774000005000,
      age_ms: 3000,
      ttl_remaining_ms: 12000,
    },
    all_source_supervisor_remote_snapshot_cache_snapshot: {
      source: "hub",
      freshness: "ttl_cache",
      cache_hit: true,
      scope: "mode=supervisor_orchestration project_id=(none)",
      cached_at_ms: 1774000005000,
      age_ms: 3000,
      ttl_remaining_ms: 12000,
    },
  });
});

run("product exit packet preserves compact local store write support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.local_store_write_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_local_store_write_snapshot: {
      personal_memory_intent: "manual_edit_buffer_commit",
      cross_link_intent: "after_turn_cache_refresh",
      personal_review_intent: "derived_refresh",
    },
    all_source_local_store_write_snapshot: {
      personal_memory_intent: "manual_edit_buffer_commit",
      cross_link_intent: "after_turn_cache_refresh",
      personal_review_intent: "derived_refresh",
    },
  });
});

run("product exit packet preserves compact XT pairing readiness support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.xt_pairing_readiness_support, {
    xt_source_smoke_status: "pass",
    all_source_smoke_status: "pass",
    xt_source_first_pair_completion_proof: {
      readiness: "local_ready",
      same_lan_verified: true,
      owner_local_approval_verified: true,
      pairing_material_issued: true,
      cached_reconnect_smoke_passed: false,
      stable_remote_route_present: true,
      remote_shadow_smoke_passed: false,
      remote_shadow_smoke_status: "running",
      remote_shadow_smoke_source: "dedicated_stable_remote_probe",
      remote_shadow_route: "internet",
      remote_shadow_reason_code: "remote_shadow_probe_inflight",
      remote_shadow_summary: "verifying stable remote route shadow path ...",
      summary_line: "local_ready waiting for stable remote route shadow verification",
    },
    xt_source_paired_route_set: {
      readiness: "local_ready",
      readiness_reason_code: "remote_shadow_probe_running",
      summary_line: "LAN route active while remote shadow probe is still running",
      hub_instance_id: "hub_fixture_1",
      pairing_profile_epoch: "pair-epoch-20260322",
      route_pack_version: 7,
      active_route: {
        route_kind: "lan",
        host: "192.168.1.20",
        pairing_port: 50055,
        grpc_port: 50054,
        host_kind: "ipv4",
        source: "lan_discovery",
      },
      lan_route: {
        route_kind: "lan",
        host: "192.168.1.20",
        pairing_port: 50055,
        grpc_port: 50054,
        host_kind: "ipv4",
        source: "lan_discovery",
      },
      stable_remote_route: {
        route_kind: "internet",
        host: "hub.tailnet.example",
        pairing_port: 50055,
        grpc_port: 50054,
        host_kind: "dns",
        source: "stable_remote_cache",
      },
      last_known_good_route: {
        route_kind: "lan",
        host: "192.168.1.20",
        pairing_port: 50055,
        grpc_port: 50054,
        host_kind: "ipv4",
        source: "last_known_good_cache",
      },
      cached_reconnect_smoke_status: "not_run",
      cached_reconnect_smoke_reason_code: "missing_cached_remote_session",
      cached_reconnect_smoke_summary: "cached reconnect smoke has not run yet",
    },
    all_source_first_pair_completion_proof: {
      readiness: "remote_ready",
      same_lan_verified: true,
      owner_local_approval_verified: true,
      pairing_material_issued: true,
      cached_reconnect_smoke_passed: true,
      stable_remote_route_present: true,
      remote_shadow_smoke_passed: true,
      remote_shadow_smoke_status: "passed",
      remote_shadow_smoke_source: "cached_remote_reconnect_evidence",
      remote_shadow_route: "internet",
      remote_shadow_reason_code: "stable_remote_route_verified",
      remote_shadow_summary: "stable remote route was already verified by cached reconnect smoke.",
      summary_line: "remote_ready via cached reconnect smoke",
    },
    all_source_paired_route_set: {
      readiness: "remote_ready",
      readiness_reason_code: "stable_remote_route_verified",
      summary_line: "stable remote route promoted to active route after reconnect smoke",
      hub_instance_id: "hub_fixture_1",
      pairing_profile_epoch: "pair-epoch-20260322",
      route_pack_version: 7,
      active_route: {
        route_kind: "internet",
        host: "hub.tailnet.example",
        pairing_port: 50055,
        grpc_port: 50054,
        host_kind: "dns",
        source: "stable_remote_cache",
      },
      lan_route: {
        route_kind: "lan",
        host: "192.168.1.20",
        pairing_port: 50055,
        grpc_port: 50054,
        host_kind: "ipv4",
        source: "lan_discovery",
      },
      stable_remote_route: {
        route_kind: "internet",
        host: "hub.tailnet.example",
        pairing_port: 50055,
        grpc_port: 50054,
        host_kind: "dns",
        source: "stable_remote_cache",
      },
      last_known_good_route: {
        route_kind: "internet",
        host: "hub.tailnet.example",
        pairing_port: 50055,
        grpc_port: 50054,
        host_kind: "dns",
        source: "cached_reconnect_smoke",
      },
      cached_reconnect_smoke_status: "pass",
      cached_reconnect_smoke_reason_code: "cached_remote_reconnect_verified",
      cached_reconnect_smoke_summary: "cached reconnect smoke verified stable remote route",
    },
  });
});

run("product exit packet preserves compact memory truth closure support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.xt_memory_truth_closure_support, {
    xt_memory_truth_closure_smoke_status: "pass",
    xt_memory_truth_closure_snapshot: {
      truth_examples: [
        {
          raw_source: "hub",
          label: "Hub 记忆",
          explainable_label: "Hub 记忆（Hub durable truth）",
          truth_hint: "Hub durable truth",
        },
        {
          raw_source: "hub_memory_v1_grpc",
          label: "Hub 快照 + 本地 overlay",
          explainable_label: "Hub 快照 + 本地 overlay（快照拼接，非 durable 真相）",
          truth_hint: "快照拼接，非 durable 真相",
        },
      ],
      project_context: {
        memory_source: "hub_memory_v1_grpc",
        memory_source_label: "Hub 快照 + 本地 overlay",
        writer_gate_boundary_present: true,
      },
      supervisor_memory: {
        memory_source: "hub",
        mode_source_text: "当前记忆来源：Hub 记忆（Hub durable truth） · 用途：Supervisor 编排",
        continuity_detail_line: "本轮从Hub 记忆（Hub durable truth）带入连续对话与背景记忆。",
      },
      canonical_sync_closure: {
        doctor_summary_line: "Canonical memory 同步链路最近失败",
        audit_ref: "audit-project-alpha-incident-1",
        evidence_ref: "canonical_memory_item:item-project-alpha-incident-1",
        writeback_ref: "canonical_memory_item:item-project-alpha-incident-1",
        strict_issue_code: "memory:memory_canonical_sync_delivery_failed",
      },
    },
  });
});

run("product exit packet preserves compact build snapshot inventory support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.doctor_source_gate.build_snapshot_inventory_support, {
    report_ref: "build/reports/build_snapshot_inventory.v1.json",
    build_snapshot_inventory_generation_status: "pass",
    summary_status: "within_retention_budget",
    verdict_reason: "Build snapshot roots exist, but timestamped historical siblings are already within the configured retention budget.",
    stale_history_surface_ids: [],
    largest_reclaim_candidate_surface_id: "hub",
    current_snapshot_total_bytes: 880553886,
    historical_snapshot_total_bytes: 3556349728,
    projected_prune_total_bytes: 0,
    projected_prune_history_count: 0,
    hub: {
      status: "within_retention_budget",
      snapshot_root_ref: "build/.xhub-build-src",
      snapshot_root_exists: true,
      retention_keep_count: 2,
      current_snapshot_ref: "build/.xhub-build-src",
      current_snapshot_size_bytes: 209339786,
      historical_snapshot_count: 2,
      historical_snapshot_total_bytes: 3556349728,
      would_prune_history_count: 0,
      would_prune_total_bytes: 0,
      would_keep_history_refs: [
        "build/.xhub-build-src-20260318-0751",
        "build/.xhub-build-src-20260318-0739",
      ],
      would_prune_history_refs: [],
    },
    xterminal: {
      status: "within_retention_budget",
      snapshot_root_ref: "build/.xterminal-build-src",
      snapshot_root_exists: true,
      retention_keep_count: 2,
      current_snapshot_ref: "build/.xterminal-build-src",
      current_snapshot_size_bytes: 671214100,
      historical_snapshot_count: 0,
      historical_snapshot_total_bytes: 0,
      would_prune_history_count: 0,
      would_prune_total_bytes: 0,
      would_keep_history_refs: [],
      would_prune_history_refs: [],
    },
  });
});

run("product exit packet preserves compact operator channel recovery support for operator handoff", () => {
  const packet = buildProductExitPacket({
    operatorRecovery: makeOperatorRecovery(),
    operatorChannelRecovery: makeOperatorChannelRecovery(),
    requireReal: makeRequireReal(),
    boundary: makeBoundary(),
    ossReadiness: makeOssReadiness(),
    doctorSourceGate: makeDoctorSourceGate(),
    releaseRefreshPreflight: {
      required_inputs: [
        {
          ref: "build/reports/xt_w3_release_ready_decision.v1.json",
          present: true,
        },
        {
          ref: "build/reports/xt_w3_require_real_provenance.v2.json",
          present: true,
        },
      ],
    },
  });

  assert.deepEqual(packet.support_truth.operator_channel_recovery, {
    gate_verdict:
      "PASS(channel_onboarding_recovery_report_generated_from_structured_doctor_truth)",
    release_stance: "preview_working",
    verdict_reason:
      "Structured operator-channel onboarding truth is available for channel_runtime_missing, so operator/support wording can reuse one machine-readable diagnosis.",
    machine_decision: {
      support_ready: true,
      source: "source_gate_summary",
      source_gate_status: "pass",
      all_source_smoke_status: "pass",
      overall_state: "degraded",
      ready_for_first_task: true,
      current_failure_code: "channel_runtime_missing",
      current_failure_issue: "channel_runtime",
      action_category: "restore_channel_admin_surface",
    },
    heartbeat_governance_visibility_gap: false,
    channel_focus_highlight: "",
    onboarding_truth: {
      overall_state: "degraded",
      ready_for_first_task: true,
      current_failure_code: "channel_runtime_missing",
      current_failure_issue: "channel_runtime",
      primary_check_kind: "channel_runtime",
      primary_check_status: "warn",
      primary_check_blocking: false,
      repair_destination_ref: "hub://settings/operator_channels",
      provider_ids: ["slack", "telegram"],
      error_codes: [],
      fetch_errors: [],
      required_next_steps: ["inspect_operator_channel_diagnostics"],
    },
    recovery_classification: {
      action_category: "restore_channel_admin_surface",
      severity: "high",
      install_hint:
        "Restore the Hub admin/onboarding surface before trusting any remote channel readiness snapshot.",
    },
    release_wording: {
      external_status_line:
        "Structured operator-channel onboarding doctor truth is available, but this surface remains preview-working rather than validated.",
    },
    top_recommended_action: {
      rank: 1,
      action_id: "restore_channel_admin_surface",
      title: "Restore operator channel admin surface",
      command_or_ref: "hub://settings/operator_channels",
    },
    recommended_actions: [
      {
        rank: 1,
        action_id: "restore_channel_admin_surface",
        title: "Restore operator channel admin surface",
        command_or_ref: "hub://settings/operator_channels",
      },
      {
        rank: 2,
        action_id: "inspect_operator_channel_diagnostics",
        title: "查看诊断",
        command_or_ref: "hub://settings/diagnostics",
      },
    ],
    support_faq: [
      {
        faq_id: "why_fail_closed",
        question: "Why are remote requests still fail-closed?",
        answer:
          "Because operator-channel onboarding truth is degraded, governed remote approval must not proceed yet.",
      },
    ],
  });
});

run("refresh release preflight accepts preferred XT-ready require-real artifacts", () => {
  const presentRefs = new Set([
    "build/reports/lpr_w3_03_a_require_real_evidence.v1.json",
    "build/reports/xhub_doctor_source_gate_summary.v1.json",
    "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json",
    "x-terminal/.axcoder/reports/xt-report-index.json",
    "x-terminal/.axcoder/reports/xt-gate-report.md",
    "x-terminal/.axcoder/reports/xt-rollback-last.json",
    "x-terminal/.axcoder/reports/xt-rollback-verify.json",
    "x-terminal/.axcoder/reports/secrets-dry-run-report.json",
    "build/xt_ready_gate_e2e_require_real_report.json",
    "build/xt_ready_evidence_source.require_real.json",
    "build/connector_ingress_gate_snapshot.require_real.json",
  ]);

  const preflight = buildRefreshReleasePreflight({
    existsFn: (ref) => presentRefs.has(ref),
  });

  assert.equal(preflight.ready, true);
  assert.equal(preflight.xt_ready_preferred_input.mode, "require_real_release_chain");
  assert.equal(
    preflight.xt_ready_preferred_input.selected_report_ref,
    "build/xt_ready_gate_e2e_require_real_report.json"
  );
  assert.equal(
    preflight.xt_ready_preferred_input.selected_source_ref,
    "build/xt_ready_evidence_source.require_real.json"
  );
  assert.equal(
    preflight.xt_ready_preferred_input.selected_connector_ref,
    "build/connector_ingress_gate_snapshot.require_real.json"
  );
  assert.equal(preflight.missing_inputs.length, 0);
});

run("refresh release preflight fails closed when strict XT-ready connector snapshot is missing", () => {
  const presentRefs = new Set([
    "build/reports/lpr_w3_03_a_require_real_evidence.v1.json",
    "build/reports/xhub_doctor_source_gate_summary.v1.json",
    "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json",
    "x-terminal/.axcoder/reports/xt-report-index.json",
    "x-terminal/.axcoder/reports/xt-gate-report.md",
    "x-terminal/.axcoder/reports/xt-rollback-last.json",
    "x-terminal/.axcoder/reports/xt-rollback-verify.json",
    "x-terminal/.axcoder/reports/secrets-dry-run-report.json",
    "build/xt_ready_gate_e2e_require_real_report.json",
    "build/xt_ready_evidence_source.require_real.json",
  ]);

  const preflight = buildRefreshReleasePreflight({
    existsFn: (ref) => presentRefs.has(ref),
  });

  assert.equal(preflight.ready, false);
  assert.equal(preflight.xt_ready_preferred_input.mode, "require_real_release_chain");
  assert.equal(preflight.xt_ready_preferred_input.selected_connector_ref, null);
  assert(
    preflight.missing_inputs.includes(
      "build/connector_ingress_gate_snapshot.require_real.json | build/connector_ingress_gate_snapshot.json"
    )
  );
});
