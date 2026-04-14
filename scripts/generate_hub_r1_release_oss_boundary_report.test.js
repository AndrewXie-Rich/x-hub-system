#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  createReleaseSurfaceFixture,
} = require("./release_surface_fixture_test_lib.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("boundary readiness carries doctor heartbeat governance, durable candidate mirror, and local store write support", () => {
  const root = createReleaseSurfaceFixture();

  try {
    const result = spawnSync(process.execPath, [path.join(__dirname, "generate_hub_r1_release_oss_boundary_report.js")], {
      cwd: root,
      env: {
        ...process.env,
        TZ: "Asia/Shanghai",
        XHUB_RELEASE_ROOT: root,
      },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);

    const readiness = JSON.parse(
      fs.readFileSync(path.join(root, "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json"), "utf8")
    );
    const delta = JSON.parse(
      fs.readFileSync(path.join(root, "build/reports/hub_l5_r1_release_oss_boundary_delta_3line.v1.json"), "utf8")
    );
    const projectMemoryPolicySupport =
      readiness.release_alignment.doctor_source_gate.project_memory_policy_support;
    const projectMemoryAssemblyResolutionSupport =
      readiness.release_alignment.doctor_source_gate.project_memory_assembly_resolution_support;
    const projectRemoteSnapshotCacheSupport =
      readiness.release_alignment.doctor_source_gate.project_remote_snapshot_cache_support;
    const heartbeatSupport =
      readiness.release_alignment.doctor_source_gate.heartbeat_governance_support;
    const supervisorMemoryPolicySupport =
      readiness.release_alignment.doctor_source_gate.supervisor_memory_policy_support;
    const supervisorMemoryAssemblyResolutionSupport =
      readiness.release_alignment.doctor_source_gate.supervisor_memory_assembly_resolution_support;
    const supervisorRemoteSnapshotCacheSupport =
      readiness.release_alignment.doctor_source_gate.supervisor_remote_snapshot_cache_support;
    const mirrorSupport =
      readiness.release_alignment.doctor_source_gate.durable_candidate_mirror_support;
    const localStoreWriteSupport =
      readiness.release_alignment.doctor_source_gate.local_store_write_support;
    const xtPairingReadinessSupport =
      readiness.release_alignment.doctor_source_gate.xt_pairing_readiness_support;
    const memoryTruthClosureSupport =
      readiness.release_alignment.doctor_source_gate.xt_memory_truth_closure_support;
    const buildSnapshotInventorySupport =
      readiness.release_alignment.doctor_source_gate.build_snapshot_inventory_support;
    const hubPairingRoundtripSupport =
      readiness.release_alignment.doctor_source_gate.hub_pairing_roundtrip_support;
    const xtReadyDiagnostics =
      readiness.release_alignment.xt_ready_diagnostics;

    assert.equal(
      readiness.status,
      "delivered(validated_mainline_release_oss_boundary_ready)"
    );
    assert.equal(
      xtReadyDiagnostics.summary.current_release_strict_ready,
      true
    );
    assert.equal(xtReadyDiagnostics.blockers.length, 0);
    assert.deepEqual(projectMemoryPolicySupport.xt_source_project_memory_policy, {
      configured_recent_project_dialogue_profile: "auto",
      configured_project_context_depth: "auto",
      recommended_recent_project_dialogue_profile: "extended_40_pairs",
      recommended_project_context_depth: "deep",
      effective_recent_project_dialogue_profile: "extended_40_pairs",
      effective_project_context_depth: "deep",
      a_tier_memory_ceiling: "m3_deep_dive",
      audit_ref: "audit-project-memory-policy-1",
    });
    assert.deepEqual(projectMemoryAssemblyResolutionSupport.all_source_project_memory_assembly_resolution, {
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
    });
    assert.deepEqual(projectRemoteSnapshotCacheSupport.xt_source_project_remote_snapshot_cache_snapshot, {
      source: "hub_memory_v1_grpc",
      freshness: "ttl_cache",
      cache_hit: true,
      scope: "mode=project_chat project_id=proj-fixture",
      cached_at_ms: 1774000000000,
      age_ms: 6000,
      ttl_remaining_ms: 9000,
    });
    assert.deepEqual(heartbeatSupport.xt_source_heartbeat_governance_snapshot, {
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
    });
    assert.deepEqual(heartbeatSupport.all_source_heartbeat_governance_snapshot, {
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
    });
    assert.deepEqual(supervisorMemoryPolicySupport.xt_source_supervisor_memory_policy, {
      configured_supervisor_recent_raw_context_profile: "auto_max",
      configured_review_memory_depth: "auto",
      recommended_supervisor_recent_raw_context_profile: "extended_40_pairs",
      recommended_review_memory_depth: "deep_dive",
      effective_supervisor_recent_raw_context_profile: "extended_40_pairs",
      effective_review_memory_depth: "deep_dive",
      s_tier_review_memory_ceiling: "m4_full_scan",
      audit_ref: "audit-supervisor-memory-policy-1",
    });
    assert.deepEqual(supervisorMemoryAssemblyResolutionSupport.all_source_supervisor_memory_assembly_resolution, {
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
    });
    assert.deepEqual(supervisorRemoteSnapshotCacheSupport.all_source_supervisor_remote_snapshot_cache_snapshot, {
      source: "hub",
      freshness: "ttl_cache",
      cache_hit: true,
      scope: "mode=supervisor_orchestration project_id=(none)",
      cached_at_ms: 1774000005000,
      age_ms: 3000,
      ttl_remaining_ms: 12000,
    });
    assert.deepEqual(mirrorSupport.xt_source_durable_candidate_mirror_snapshot, {
      status: "mirrored_to_hub",
      target: "hub_candidate_carrier",
      attempted: true,
      error_code: null,
      local_store_role: "cache_fallback_edit_buffer",
    });
    assert.deepEqual(mirrorSupport.all_source_durable_candidate_mirror_snapshot, {
      status: "local_only",
      target: "hub_candidate_carrier",
      attempted: true,
      error_code: "hub_unreachable",
      local_store_role: "cache_fallback_edit_buffer",
    });
    assert.deepEqual(localStoreWriteSupport.xt_source_local_store_write_snapshot, {
      personal_memory_intent: "manual_edit_buffer_commit",
      cross_link_intent: "after_turn_cache_refresh",
      personal_review_intent: "derived_refresh",
    });
    assert.deepEqual(localStoreWriteSupport.all_source_local_store_write_snapshot, {
      personal_memory_intent: "manual_edit_buffer_commit",
      cross_link_intent: "after_turn_cache_refresh",
      personal_review_intent: "derived_refresh",
    });
    assert.deepEqual(xtPairingReadinessSupport, {
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
        remote_shadow_summary:
          "stable remote route was already verified by cached reconnect smoke.",
        summary_line: "remote_ready via cached reconnect smoke",
      },
      all_source_paired_route_set: {
        readiness: "remote_ready",
        readiness_reason_code: "stable_remote_route_verified",
        summary_line:
          "stable remote route promoted to active route after reconnect smoke",
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
        cached_reconnect_smoke_summary:
          "cached reconnect smoke verified stable remote route",
      },
      xt_source_smoke_evidence_ref:
        "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref:
        "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
    });
    assert.equal(memoryTruthClosureSupport.xt_memory_truth_closure_smoke_status, "pass");
    assert.equal(hubPairingRoundtripSupport.launch_only_smoke_status, "pass");
    assert.equal(hubPairingRoundtripSupport.verify_only_smoke_status, "pass");
    assert.equal(
      hubPairingRoundtripSupport.verify_only_snapshot.pairing.cleanup_verified,
      true
    );
    assert.equal(
      xtReadyDiagnostics.support.hub_pairing_roundtrip.verify_only.cleanup_verified,
      true
    );
    assert.equal(
      xtReadyDiagnostics.support.hub_pairing_roundtrip.launch_only.launch_action,
      "already_ready"
    );
    assert.deepEqual(memoryTruthClosureSupport.xt_memory_truth_closure_snapshot.canonical_sync_closure, {
      doctor_summary_line: "Canonical memory 同步链路最近失败",
      audit_ref: "audit-project-alpha-incident-1",
      evidence_ref: "canonical_memory_item:item-project-alpha-incident-1",
      writeback_ref: "canonical_memory_item:item-project-alpha-incident-1",
      strict_issue_code: "memory:memory_canonical_sync_delivery_failed",
    });
    assert.equal(buildSnapshotInventorySupport.build_snapshot_inventory_generation_status, "pass");
    assert.equal(buildSnapshotInventorySupport.summary_status, "within_retention_budget");
    assert.equal(buildSnapshotInventorySupport.projected_prune_total_bytes, 0);
    assert.deepEqual(buildSnapshotInventorySupport.hub.would_keep_history_refs, [
      "build/.xhub-build-src-20260318-0751",
      "build/.xhub-build-src-20260318-0739",
    ]);
    assert.equal(buildSnapshotInventorySupport.xterminal.current_snapshot_ref, "build/.xterminal-build-src");
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.blocker_class,
      "current_embedding_dirs_incompatible_with_native_transformers_load"
    );
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.machine_decision.require_real_focus_helper_local_service_recovery_present,
      true
    );
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.helper_local_service_recovery.top_recommended_action.action_id,
      "enable_lm_studio_local_service"
    );
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.helper_local_service_recovery.helper_route_contract.helper_route_ready_verdict,
      "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)"
    );
    assert.deepEqual(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.checked_sources.scan_roots,
      [
        { path: "/fixture/models", present: true },
        { path: "/Users/demo/Downloads", present: true },
      ]
    );
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.search_recovery.wide_shortlist_search_command.includes("--wide-common-user-roots"),
      true
    );
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.candidate_acceptance.acceptance_contract.required_gate_verdict,
      "PASS(sample1_candidate_native_loadable_for_real_execution)"
    );
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.candidate_registration.machine_decision.catalog_write_allowed_now,
      false
    );
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.candidate_registration.candidate_validation.gate_verdict,
      "NO_GO(sample1_candidate_validation_failed_closed)"
    );
    assert.equal(
      readiness.release_alignment.xhub_local_service_operator_recovery.require_real_focus.candidate_registration.catalog_patch_plan_summary.blocked_reason,
      "validator_not_pass"
    );
    assert.equal(
      readiness.release_alignment.xhub_operator_channel_recovery.machine_decision.action_category,
      "restore_channel_admin_surface"
    );
    assert.equal(
      readiness.release_alignment.xhub_operator_channel_recovery.top_recommended_action.action_id,
      "restore_channel_admin_surface"
    );
    assert.match(
      readiness.release_alignment.xhub_operator_channel_recovery.release_wording.external_status_line,
      /preview-working/
    );
    assert.equal(
      delta.support_context.operator_channel_action_category,
      "restore_channel_admin_surface"
    );
    assert.match(
      delta.support_context.operator_channel_external_status_line,
      /preview-working/
    );
    const diagnosticsArtifact = JSON.parse(
      fs.readFileSync(
        path.join(root, "build/reports/xt_ready_release_diagnostics.v1.json"),
        "utf8"
      )
    );
    assert.equal(
      diagnosticsArtifact.summary.current_release_strict_ready,
      true
    );
    assert.equal(
      diagnosticsArtifact.summary.xt_ready_artifact_mode,
      "current_gate"
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("boundary readiness surfaces operator heartbeat governance visibility gaps in release alignment and delta", () => {
  const root = createReleaseSurfaceFixture();

  try {
    const reportPath = path.join(
      root,
      "build/reports/xhub_operator_channel_recovery_report.v1.json"
    );
    const channelRecovery = JSON.parse(fs.readFileSync(reportPath, "utf8"));
    channelRecovery.machine_decision.current_failure_code =
      "channel_live_test_heartbeat_visibility_missing";
    channelRecovery.machine_decision.current_failure_issue = "channel_live_test";
    channelRecovery.machine_decision.action_category =
      "restore_heartbeat_governance_visibility";
    channelRecovery.onboarding_truth.current_failure_code =
      "channel_live_test_heartbeat_visibility_missing";
    channelRecovery.onboarding_truth.current_failure_issue = "channel_live_test";
    channelRecovery.onboarding_truth.primary_check_kind = "channel_live_test";
    channelRecovery.recovery_classification.action_category =
      "restore_heartbeat_governance_visibility";
    channelRecovery.recommended_actions = [
      {
        rank: 1,
        action_id: "restore_heartbeat_governance_visibility",
        title: "Inspect operator channel diagnostics",
        command_or_ref: "hub://settings/diagnostics",
      },
    ];
    fs.writeFileSync(reportPath, `${JSON.stringify(channelRecovery, null, 2)}\n`, "utf8");

    const result = spawnSync(process.execPath, [path.join(__dirname, "generate_hub_r1_release_oss_boundary_report.js")], {
      cwd: root,
      env: {
        ...process.env,
        TZ: "Asia/Shanghai",
        XHUB_RELEASE_ROOT: root,
      },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);

    const readiness = JSON.parse(
      fs.readFileSync(path.join(root, "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json"), "utf8")
    );
    const delta = JSON.parse(
      fs.readFileSync(path.join(root, "build/reports/hub_l5_r1_release_oss_boundary_delta_3line.v1.json"), "utf8")
    );

    assert.equal(
      readiness.release_alignment.xhub_operator_channel_recovery.heartbeat_governance_visibility_gap,
      true
    );
    assert.equal(
      readiness.release_alignment.xhub_operator_channel_recovery.channel_focus_highlight,
      "First smoke proof still lacks heartbeat governance visibility."
    );
    assert.equal(
      delta.support_context.operator_channel_heartbeat_governance_visibility_gap,
      true
    );
    assert.equal(
      delta.support_context.operator_channel_focus_highlight,
      "First smoke proof still lacks heartbeat governance visibility."
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("boundary readiness prefers strict require-real connector evidence when current snapshot is absent", () => {
  const root = createReleaseSurfaceFixture();

  try {
    fs.writeFileSync(
      path.join(root, "build/xt_ready_gate_e2e_require_real_report.json"),
      JSON.stringify({
        ok: true,
        require_real_audit_source: true,
      }, null, 2) + "\n",
      "utf8"
    );
    fs.writeFileSync(
      path.join(root, "build/xt_ready_evidence_source.require_real.json"),
      JSON.stringify({
        selected_source: "audit_export",
        require_real_audit: true,
      }, null, 2) + "\n",
      "utf8"
    );
    fs.writeFileSync(
      path.join(root, "build/connector_ingress_gate_snapshot.require_real.json"),
      JSON.stringify({
        source_used: "audit",
        snapshot: { pass: true },
        summary: { blocked_event_miss_rate: 0 },
      }, null, 2) + "\n",
      "utf8"
    );
    fs.rmSync(path.join(root, "build/connector_ingress_gate_snapshot.json"));

    const result = spawnSync(process.execPath, [path.join(__dirname, "generate_hub_r1_release_oss_boundary_report.js")], {
      cwd: root,
      env: {
        ...process.env,
        TZ: "Asia/Shanghai",
        XHUB_RELEASE_ROOT: root,
      },
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);

    const readiness = JSON.parse(
      fs.readFileSync(path.join(root, "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json"), "utf8")
    );
    assert.equal(
      readiness.release_alignment.xt_ready.evidence_mode,
      "require_real_release_chain"
    );
    assert.equal(
      readiness.release_alignment.xt_ready.connector_gate_ref,
      "build/connector_ingress_gate_snapshot.require_real.json"
    );
    assert.equal(
      readiness.release_alignment.connector_gate.evidence_ref,
      "build/connector_ingress_gate_snapshot.require_real.json"
    );
    assert.equal(
      readiness.release_alignment.xt_ready_diagnostics.summary.connector_gate_ref,
      "build/connector_ingress_gate_snapshot.require_real.json"
    );
    assert(
      readiness.evidence_refs.includes(
        "build/reports/xhub_operator_channel_recovery_report.v1.json"
      )
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
