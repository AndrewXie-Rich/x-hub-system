#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

function writeText(root, relPath, text) {
  const absPath = path.join(root, relPath);
  fs.mkdirSync(path.dirname(absPath), { recursive: true });
  fs.writeFileSync(absPath, text, "utf8");
}

function writeJson(root, relPath, payload) {
  writeText(root, relPath, `${JSON.stringify(payload, null, 2)}\n`);
}

function createReleaseSurfaceFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-release-surface-"));

  writeText(
    root,
    "README.md",
    [
      "# x-hub-system",
      "",
      "## Quick Start",
      "",
      "Run `bash x-terminal/scripts/ci/xt_release_gate.sh` to reproduce the XT release smoke.",
      "",
      "This fixture keeps the release surface frozen to the validated mainline only.",
      "",
    ].join("\n")
  );
  writeText(root, "LICENSE", "fixture license\n");
  writeText(root, "NOTICE.md", "fixture notice\n");
  writeText(root, "SECURITY.md", "fixture security\n");
  writeText(root, "CONTRIBUTING.md", "fixture contributing\n");
  writeText(root, "CODE_OF_CONDUCT.md", "fixture code of conduct\n");
  writeText(root, "CODEOWNERS", "* @fixture-owner\n");
  writeText(root, "CHANGELOG.md", "## 0.1.0\n\n- fixture\n");
  writeText(
    root,
    "RELEASE.md",
    [
      "# Release",
      "",
      "## 6) Rollback",
      "",
      "Rollback remains executable for the validated mainline.",
      "",
    ].join("\n")
  );
  writeText(root, ".gitignore", "build/\n");

  writeText(root, ".github/ISSUE_TEMPLATE/bug_report.yml", "name: Bug Report\n");
  writeText(root, ".github/ISSUE_TEMPLATE/feature_request.yml", "name: Feature Request\n");
  writeText(root, ".github/PULL_REQUEST_TEMPLATE.md", "## Summary\n");
  writeText(root, ".github/dependabot.yml", "version: 2\nupdates: []\n");

  writeText(
    root,
    "docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md",
    [
      "# OSS Minimal Runnable Package",
      "",
      "- OSS-G0",
      "- OSS-G5",
      "- GO|NO-GO|INSUFFICIENT_EVIDENCE",
      "- build/reports/oss_secret_scrub_report.v1.json",
      "",
    ].join("\n")
  );
  writeText(
    root,
    "docs/open-source/OSS_RELEASE_CHECKLIST_v1.md",
    [
      "# OSS Release Checklist",
      "",
      "- OSS-G0",
      "- OSS-G5",
      "- build/reports/oss_secret_scrub_report.v1.json",
      "- rollback",
      "",
    ].join("\n")
  );
  writeText(
    root,
    "docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md",
    [
      "# Public Paths",
      "",
      "- allowlist-first + fail-closed",
      "- build/**",
      "- **/*kek*.json",
      "- **/*secret*",
      "- GO|NO-GO|INSUFFICIENT_EVIDENCE",
      "",
    ].join("\n")
  );

  writeJson(root, "x-terminal/.axcoder/reports/xt-report-index.json", {
    release_decision: "GO",
    generated_at: "2026-03-22T12:00:00Z",
  });
  writeJson(root, "x-terminal/.axcoder/reports/xt-rollback-verify.json", {
    status: "pass",
  });
  writeJson(root, "x-terminal/.axcoder/reports/secrets-dry-run-report.json", {
    blocking_count: 0,
    missing_variables_count: 0,
    permission_boundary_error_count: 0,
  });

  writeJson(root, "build/xt_ready_gate_e2e_report.json", {
    ok: true,
    require_real_audit_source: true,
  });
  writeJson(root, "build/xt_ready_evidence_source.json", {
    selected_source: "audit_export",
  });
  writeJson(root, "build/connector_ingress_gate_snapshot.json", {
    source_used: "audit",
    snapshot: { pass: true },
    summary: { blocked_event_miss_rate: 0 },
  });
  writeJson(root, "build/hub_l5_release_internal_pass_lines_report.json", {
    release_decision: "GO",
  });

  writeJson(root, "build/reports/xt_w3_release_ready_decision.v1.json", {
    release_ready: true,
    non_scope_note: "Out-of-scope lanes remain frozen outside the validated mainline.",
  });
  writeJson(root, "build/reports/xt_w3_require_real_provenance.v2.json", {
    summary: {
      strict_xt_ready_require_real_pass: true,
      unified_release_ready_provenance_pass: true,
      release_stance: "release_ready",
    },
  });
  writeJson(root, "build/reports/xt_w3_internal_pass_lines_release_ready.v1.json", {
    release_decision: "GO",
    checks: {
      coverage_checks: {
        "XT-W3-23": true,
        "XT-W3-24": true,
        "XT-W3-25": true,
        "XT-W2-99": false,
      },
    },
  });
  writeJson(root, "build/reports/xt_w3_25_competitive_rollback.v1.json", {
    rollback_ready: true,
    rollback_scope: "validated_mainline_only",
    rollback_mode: "scripted",
  });

  writeJson(root, "build/reports/xt_w3_23_direct_require_real_provenance_binding.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xt_w3_24_direct_require_real_provenance_binding.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xt_w3_25_e_bootstrap_templates_evidence.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xt_w3_24_f_channel_hub_boundary_evidence.v1.json", {
    status: "pass",
  });

  writeJson(root, "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xhub_doctor_xt_pairing_repair_smoke_evidence.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xhub_doctor_xt_memory_truth_closure_smoke_evidence.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json", {
    status: "pass",
  });
  writeJson(root, "build/reports/xhub_background_launch_only_smoke_evidence.v1.json", {
    schemaVersion: "xhub.background_pairing_smoke.v1",
    mode: "launch_only",
    ok: true,
    launch: {
      action: "already_ready",
      backgroundLaunchEvidenceFound: false,
      mainPanelShownAfterLaunch: false,
    },
    discovery: {
      ok: true,
      status: 200,
      response: {
        pairing_enabled: true,
        hub_instance_id: "hub_fixture_1",
        lan_discovery_name: "axhub-fixture",
        hub_host_hint: "127.0.0.1",
        grpc_port: 50054,
        pairing_port: 50055,
        tls_mode: "mtls",
        internet_host_hint: "17.81.10.243",
      },
    },
    adminToken: {
      resolved: false,
      tokenSource: "",
    },
    pairing: {
      cleanupVerified: false,
    },
    errors: [],
  });
  writeJson(root, "build/reports/xhub_pairing_roundtrip_verify_only_smoke_evidence.v1.json", {
    schemaVersion: "xhub.background_pairing_smoke.v1",
    mode: "verify_only",
    ok: true,
    launch: {
      action: "verify_only_existing_hub",
      backgroundLaunchEvidenceFound: false,
      mainPanelShownAfterLaunch: false,
    },
    discovery: {
      ok: true,
      status: 200,
      response: {
        pairing_enabled: true,
        hub_instance_id: "hub_fixture_1",
        lan_discovery_name: "axhub-fixture",
        hub_host_hint: "127.0.0.1",
        grpc_port: 50054,
        pairing_port: 50055,
        tls_mode: "mtls",
        internet_host_hint: "17.81.10.243",
      },
    },
    adminToken: {
      resolved: true,
      tokenSource: "encrypted_tokens_file",
    },
    pairing: {
      postStatus: 201,
      pendingListStatus: 200,
      pendingListContainsRequest: true,
      cleanupStatus: "denied",
      cleanupVerified: true,
    },
    errors: [],
  });
  writeJson(root, "build/reports/build_snapshot_inventory.v1.json", {
    schema_version: "xhub.build_snapshot_inventory.v1",
    summary: {
      status: "within_retention_budget",
      verdict_reason: "Build snapshot roots exist, but timestamped historical siblings are already within the configured retention budget.",
      stale_history_surface_ids: [],
      largest_reclaim_candidate_surface_id: "hub",
    },
    totals: {
      current_snapshot_total_bytes: 880553886,
      historical_snapshot_total_bytes: 3556349728,
      historical_snapshot_count: 2,
      projected_prune_total_bytes: 0,
      projected_prune_history_count: 0,
    },
    surfaces: {
      hub: {
        status: "within_retention_budget",
        snapshot_root_ref: "build/.xhub-build-src",
        snapshot_root_exists: true,
        retention_keep_count: 2,
        current_snapshot: {
          snapshot_ref: "build/.xhub-build-src",
          size_bytes: 209339786,
        },
        historical_snapshot_count: 2,
        historical_snapshot_total_bytes: 3556349728,
        prune_preview: {
          would_prune_history_count: 0,
          would_prune_total_bytes: 0,
          would_keep_history_refs: [
            "build/.xhub-build-src-20260318-0751",
            "build/.xhub-build-src-20260318-0739",
          ],
          would_prune_history_refs: [],
        },
      },
      xterminal: {
        status: "within_retention_budget",
        snapshot_root_ref: "build/.xterminal-build-src",
        snapshot_root_exists: true,
        retention_keep_count: 2,
        current_snapshot: {
          snapshot_ref: "build/.xterminal-build-src",
          size_bytes: 671214100,
        },
        historical_snapshot_count: 0,
        historical_snapshot_total_bytes: 0,
        prune_preview: {
          would_prune_history_count: 0,
          would_prune_total_bytes: 0,
          would_keep_history_refs: [],
          would_prune_history_refs: [],
        },
      },
    },
  });
  writeJson(root, "build/reports/xhub_doctor_source_gate_summary.v1.json", {
    schema_version: "xhub.doctor_source_gate_summary.v1",
    overall_status: "pass",
    summary: {
      passed: 8,
      failed: 0,
    },
    steps: [
      { step_id: "wrapper_dispatch_tests", status: "pass" },
      { step_id: "build_snapshot_retention_smoke", status: "pass" },
      { step_id: "hub_local_service_snapshot_smoke", status: "pass" },
      { step_id: "xt_source_smoke", status: "pass" },
      { step_id: "xt_pairing_repair_smoke", status: "pass" },
      { step_id: "xt_memory_truth_closure_smoke", status: "pass" },
      { step_id: "all_source_smoke", status: "pass", smoke_tmp_root: "/tmp/fixture-smoke-root" },
      { step_id: "build_snapshot_inventory_report", status: "pass" },
    ],
    project_context_summary_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_project_context_summary: {
        source_kind: "xt_source",
        source_badge: "XT",
        status_line: "Project context snapshot is available.",
      },
      all_source_project_context_summary: {
        source_kind: "all_source",
        source_badge: "ALL",
        status_line: "Aggregate project context snapshot is available.",
      },
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
    },
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
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
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
    },
    memory_route_truth_support: {
      xt_source_smoke_status: "pass",
      all_source_smoke_status: "pass",
      xt_source_memory_route_truth_snapshot: {
        projection_source: "fixture",
        completeness: "full",
        route_source: "memory_router",
        route_reason_code: "fixture_route",
        binding_provider: "fixture_provider",
        binding_model_id: "fixture_model",
      },
      all_source_memory_route_truth_snapshot: {
        projection_source: "fixture",
        completeness: "full",
        route_source: "memory_router",
        route_reason_code: "fixture_route",
        binding_provider: "fixture_provider",
        binding_model_id: "fixture_model",
      },
      xt_source_smoke_evidence_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
    },
    hub_pairing_roundtrip_support: {
      launch_only_smoke_status: "pass",
      launch_only_smoke_evidence_ref: "build/reports/xhub_background_launch_only_smoke_evidence.v1.json",
      launch_only_snapshot: {
        mode: "launch_only",
        ok: true,
        launch: {
          action: "already_ready",
          background_launch_evidence_found: false,
          main_panel_shown_after_launch: false,
        },
        discovery: {
          ok: true,
          status: 200,
          pairing_enabled: true,
          hub_instance_id: "hub_fixture_1",
          lan_discovery_name: "axhub-fixture",
          hub_host_hint: "127.0.0.1",
          grpc_port: 50054,
          pairing_port: 50055,
          tls_mode: "mtls",
          internet_host_hint: "17.81.10.243",
        },
        admin_token: {
          resolved: false,
          token_source: "",
        },
        pairing: {
          cleanup_verified: false,
        },
        error_count: 0,
      },
      verify_only_smoke_status: "pass",
      verify_only_smoke_evidence_ref: "build/reports/xhub_pairing_roundtrip_verify_only_smoke_evidence.v1.json",
      verify_only_snapshot: {
        mode: "verify_only",
        ok: true,
        launch: {
          action: "verify_only_existing_hub",
          background_launch_evidence_found: false,
          main_panel_shown_after_launch: false,
        },
        discovery: {
          ok: true,
          status: 200,
          pairing_enabled: true,
          hub_instance_id: "hub_fixture_1",
          lan_discovery_name: "axhub-fixture",
          hub_host_hint: "127.0.0.1",
          grpc_port: 50054,
          pairing_port: 50055,
          tls_mode: "mtls",
          internet_host_hint: "17.81.10.243",
        },
        admin_token: {
          resolved: true,
          token_source: "encrypted_tokens_file",
        },
        pairing: {
          post_status: 201,
          pending_list_status: 200,
          pending_list_contains_request: true,
          cleanup_status: "denied",
          cleanup_verified: true,
        },
        error_count: 0,
      },
    },
    xt_pairing_repair_support: {
      xt_pairing_repair_smoke_status: "pass",
      xt_pairing_repair_smoke_evidence_ref: "build/reports/xhub_doctor_xt_pairing_repair_smoke_evidence.v1.json",
      xt_pairing_repair_snapshot: {
        scenario_count: 2,
        scenarios: [
          {
            failure_code: "pairing_health_failed",
            mapped_issue: "pairing_repair_required",
            guide_destinations: ["xt_pair_hub", "hub_pairing_device_trust", "hub_diagnostics_recovery"],
            wizard_primary_action_id: "repair_pairing",
            settings_primary_action_id: "repair_pairing",
            repair_entry_title: "打开配对修复入口",
            doctor_headline: "现有配对档案已失效，需要清理并重配",
            doctor_repair_entry: "xt_pair_hub",
          },
          {
            failure_code: "hub_port_conflict",
            mapped_issue: "hub_port_conflict",
            guide_destinations: ["xt_pair_hub", "hub_lan_grpc", "xt_diagnostics"],
            wizard_primary_action_id: "repair_hub_port_conflict",
            settings_primary_action_id: "repair_hub_port_conflict",
            repair_entry_title: "打开端口冲突修复入口",
            doctor_headline: "Hub 端口冲突，必须先修复 LAN 端口",
            doctor_repair_entry: "xt_pair_hub",
          },
        ],
      },
    },
    xt_memory_truth_closure_support: {
      xt_memory_truth_closure_smoke_status: "pass",
      xt_memory_truth_closure_smoke_evidence_ref: "build/reports/xhub_doctor_xt_memory_truth_closure_smoke_evidence.v1.json",
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
          {
            raw_source: "local_fallback",
            label: "本地 fallback",
            explainable_label: "本地 fallback（Hub 不可用时兜底）",
            truth_hint: "Hub 不可用时兜底",
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
  });

  writeJson(root, "build/reports/xhub_local_service_operator_recovery_report.v1.json", {
    schema_version: "xhub.local_service_operator_recovery_report.v1",
    gate_verdict: "PASS(operator_recovery_ready)",
    release_stance: "candidate_go",
    machine_decision: {
      support_ready: true,
      release_ready: true,
      source_gate_status: "pass",
      snapshot_smoke_status: "pass",
      require_real_release_stance: "candidate_go",
      require_real_focus_helper_local_service_recovery_present: true,
      action_category: "inspect_snapshot_before_retry",
    },
    local_service_truth: {
      provider_id: "fixture_provider",
      primary_issue_reason_code: "none",
      doctor_failure_code: null,
      doctor_provider_check_status: "pass",
      service_state: "running",
      runtime_reason_code: "healthy",
      managed_process_state: "running",
      managed_start_attempt_count: 1,
      managed_last_start_error: null,
      repair_destination_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
    },
    recovery_classification: {
      action_category: "inspect_snapshot_before_retry",
      severity: "low",
      install_hint: "Inspect the structured snapshot before retrying.",
    },
    release_wording: {
      external_status_line: "Structured local service recovery truth is available.",
    },
    require_real_focus: {
      handoff_state: "blocked",
      blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
      top_recommended_action: {
        action_id: "source_native_loadable_embedding_model_dir",
        action_summary:
          "Current embedding dirs look like fixture quantized layouts, not torch/transformers-native dirs. Source one native-loadable real embedding model dir first.",
      },
      helper_local_service_recovery: {
        current_machine_state: {
          helper_binary_found: true,
          helper_binary_path: "/Users/demo/.lmstudio/bin/lms",
          helper_server_base_url: "http://127.0.0.1:1234",
          server_models_endpoint_ok: false,
          settings_found: true,
          settings_path: "/Users/demo/.lmstudio/settings.json",
          enable_local_service: false,
          cli_installed: false,
          app_first_load: true,
          primary_blocker: "helper_local_service_disabled_before_probe",
          recommended_next_step:
            "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
        },
        helper_route_contract: {
          helper_route_role: "secondary_reference_only",
          helper_route_ready_verdict:
            "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)",
          required_ready_signals: [
            "helper_binary_found=true",
            "lmstudio_environment.enable_local_service=true",
            "server_models_endpoint_ok=true",
          ],
          reject_signals: [
            {
              signal: "lmstudio_environment.enable_local_service=false",
              reason: "LM Studio local service is disabled in settings.",
            },
          ],
        },
        top_recommended_action: {
          action_id: "enable_lm_studio_local_service",
          action_summary:
            "Turn on LM Studio local service before trusting the helper route.",
          next_step: "turn_on_local_service_then_rerun_helper_probe",
          command_or_ref:
            "LM Studio -> Settings -> Developer -> Local Service (/Users/demo/.lmstudio/settings.json)",
        },
        operator_workflow: [
          {
            step_id: "enable_lmstudio_local_service",
            allowed_now: true,
            description: "Enable LM Studio local service.",
            command: "",
            command_or_ref:
              "LM Studio -> Settings -> Developer -> Local Service (/Users/demo/.lmstudio/settings.json)",
          },
        ],
        artifact_refs: {
          helper_probe_report: "build/reports/lpr_w3_03_d_helper_bridge_probe.v1.json",
        },
      },
      checked_sources: {
        scan_roots: [
          { path: "/fixture/models", present: true },
          { path: "/Users/demo/Downloads", present: true },
        ],
      },
      search_recovery: {
        exact_path_known: true,
        exact_path_exists: true,
        exact_path_validation_command:
          "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js --model-path /fixture/models/quantized-embed --task-kind embedding",
        wide_shortlist_search_command:
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js --task-kind embedding --wide-common-user-roots",
        preferred_next_step:
          "refresh_or_widen_machine_readable_search_then_revalidate_exact_path",
      },
      candidate_acceptance: {
        acceptance_contract: {
          required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
          required_loadability_verdict: "native_loadable",
        },
        current_no_go_example: {
          normalized_model_dir: "/fixture/models/quantized-embed",
          loadability_blocker: "unsupported_quantization_config",
        },
      },
      candidate_registration: {
        machine_decision: {
          catalog_write_allowed_now: false,
          top_recommended_action: {
            action_id: "source_different_native_embedding_model_dir",
            action_summary:
              "This directory still looks like a provider-specific quantized layout. Do not register it as sample1-ready.",
          },
        },
        candidate_validation: {
          gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
          loadability_blocker: "unsupported_quantization_config",
        },
        proposed_catalog_entry: {
          id: "hf-embed-fixture",
          backend: "transformers",
          model_path: "/fixture/models/quantized-embed",
        },
        catalog_patch_plan_summary: {
          artifact_ref: "build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json",
          manual_patch_allowed_now: false,
          blocked_reason: "validator_not_pass",
          eligible_target_base_count: 0,
          blocked_target_base_count: 1,
        },
      },
    },
    recommended_actions: [
      {
        rank: 1,
        action_id: "inspect_managed_service_snapshot",
        title: "Inspect managed service snapshot before retry",
        command_or_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      },
    ],
  });

  writeJson(root, "build/reports/xhub_operator_channel_recovery_report.v1.json", {
    schema_version: "xhub.operator.channel_onboarding_recovery_report.v1",
    gate_verdict:
      "PASS(channel_onboarding_recovery_report_generated_from_structured_doctor_truth)",
    release_stance: "preview_working",
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
    recommended_actions: [
      {
        rank: 1,
        action_id: "restore_channel_admin_surface",
        title: "Restore operator channel admin surface",
        command_or_ref: "hub://settings/operator_channels",
      },
    ],
  });

  return root;
}

module.exports = {
  createReleaseSurfaceFixture,
};
