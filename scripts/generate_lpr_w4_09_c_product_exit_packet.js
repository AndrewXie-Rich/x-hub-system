#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const defaultOperatorRecoveryPath = path.join(
  repoRoot,
  "build/reports/xhub_local_service_operator_recovery_report.v1.json"
);
const defaultOperatorChannelRecoveryPath = path.join(
  repoRoot,
  "build/reports/xhub_operator_channel_recovery_report.v1.json"
);
const defaultRequireRealPath = path.join(
  repoRoot,
  "build/reports/lpr_w3_03_a_require_real_evidence.v1.json"
);
const defaultBoundaryPath = path.join(
  repoRoot,
  "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json"
);
const defaultOssReadinessPath = path.join(
  repoRoot,
  "build/reports/oss_release_readiness_v1.json"
);
const defaultDoctorSourceGatePath = path.join(
  repoRoot,
  "build/reports/xhub_doctor_source_gate_summary.v1.json"
);
const defaultOutputPath = path.join(
  repoRoot,
  "build/reports/lpr_w4_09_c_product_exit_packet.v1.json"
);
const refreshReleaseInputRefs = [
  "build/reports/lpr_w3_03_a_require_real_evidence.v1.json",
  "build/reports/xhub_doctor_source_gate_summary.v1.json",
  "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json",
  "x-terminal/.axcoder/reports/xt-report-index.json",
  "x-terminal/.axcoder/reports/xt-gate-report.md",
  "x-terminal/.axcoder/reports/xt-rollback-last.json",
  "x-terminal/.axcoder/reports/xt-rollback-verify.json",
  "x-terminal/.axcoder/reports/secrets-dry-run-report.json",
];
const preferredXtReadyArtifactCandidates = [
  {
    mode: "require_real_release_chain",
    reportRef: "build/xt_ready_gate_e2e_require_real_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.require_real.json",
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.require_real.json",
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
  {
    mode: "db_real_release_chain",
    reportRef: "build/xt_ready_gate_e2e_db_real_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.db_real.json",
      "build/xt_ready_evidence_source.require_real.json",
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.db_real.json",
      "build/connector_ingress_gate_snapshot.require_real.json",
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
  {
    mode: "current_gate",
    reportRef: "build/xt_ready_gate_e2e_report.json",
    sourceRefs: [
      "build/xt_ready_evidence_source.json",
    ],
    connectorRefs: [
      "build/connector_ingress_gate_snapshot.json",
    ],
  },
];

function isoNow() {
  return new Date().toISOString();
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return readJSON(filePath);
  } catch {
    return null;
  }
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function normalizeBoolean(value) {
  return value === true;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function buildAlternativeRefLabel(refs = []) {
  return normalizeArray(refs).map((ref) => normalizeString(ref)).filter(Boolean).join(" | ");
}

function compactProjectContextSummary(summary) {
  if (!summary || typeof summary !== "object") return null;
  return {
    source_kind: summary.source_kind,
    source_badge: summary.source_badge,
    status_line: summary.status_line,
    project_label: summary.project_label,
    dialogue_metric: summary.dialogue_metric,
    depth_metric: summary.depth_metric,
    dialogue_line: summary.dialogue_line,
    depth_line: summary.depth_line,
    coverage_metric: summary.coverage_metric,
    boundary_metric: summary.boundary_metric,
    coverage_line: summary.coverage_line,
    boundary_line: summary.boundary_line,
  };
}

function compactProjectMemoryPolicy(policy) {
  if (!policy || typeof policy !== "object") return null;
  return {
    configured_recent_project_dialogue_profile: policy.configured_recent_project_dialogue_profile,
    configured_project_context_depth: policy.configured_project_context_depth,
    recommended_recent_project_dialogue_profile: policy.recommended_recent_project_dialogue_profile,
    recommended_project_context_depth: policy.recommended_project_context_depth,
    effective_recent_project_dialogue_profile: policy.effective_recent_project_dialogue_profile,
    effective_project_context_depth: policy.effective_project_context_depth,
    a_tier_memory_ceiling: policy.a_tier_memory_ceiling,
    audit_ref: policy.audit_ref,
  };
}

function compactSupervisorMemoryPolicy(policy) {
  if (!policy || typeof policy !== "object") return null;
  return {
    configured_supervisor_recent_raw_context_profile:
      policy.configured_supervisor_recent_raw_context_profile,
    configured_review_memory_depth: policy.configured_review_memory_depth,
    recommended_supervisor_recent_raw_context_profile:
      policy.recommended_supervisor_recent_raw_context_profile,
    recommended_review_memory_depth: policy.recommended_review_memory_depth,
    effective_supervisor_recent_raw_context_profile:
      policy.effective_supervisor_recent_raw_context_profile,
    effective_review_memory_depth: policy.effective_review_memory_depth,
    s_tier_review_memory_ceiling: policy.s_tier_review_memory_ceiling,
    audit_ref: policy.audit_ref,
  };
}

function compactMemoryAssemblyResolution(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    role: snapshot.role,
    dominant_mode: snapshot.dominant_mode,
    trigger: snapshot.trigger,
    configured_depth: snapshot.configured_depth,
    recommended_depth: snapshot.recommended_depth,
    effective_depth: snapshot.effective_depth,
    ceiling_from_tier: snapshot.ceiling_from_tier,
    ceiling_hit: snapshot.ceiling_hit,
    selected_slots: Array.isArray(snapshot.selected_slots) ? snapshot.selected_slots : [],
    selected_planes: Array.isArray(snapshot.selected_planes) ? snapshot.selected_planes : [],
    selected_serving_objects: Array.isArray(snapshot.selected_serving_objects)
      ? snapshot.selected_serving_objects
      : [],
    excluded_blocks: Array.isArray(snapshot.excluded_blocks) ? snapshot.excluded_blocks : [],
    budget_summary: snapshot.budget_summary,
    audit_ref: snapshot.audit_ref,
  };
}

function compactDurableCandidateMirrorSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    status: snapshot.status,
    target: snapshot.target,
    attempted: snapshot.attempted,
    error_code: snapshot.error_code,
    local_store_role: snapshot.local_store_role,
  };
}

function compactHeartbeatGovernanceSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    project_id: snapshot.project_id,
    project_name: snapshot.project_name,
    status_digest: snapshot.status_digest,
    latest_quality_band: snapshot.latest_quality_band,
    latest_quality_score: snapshot.latest_quality_score,
    weak_reasons: Array.isArray(snapshot.weak_reasons) ? snapshot.weak_reasons : [],
    open_anomaly_types: Array.isArray(snapshot.open_anomaly_types) ? snapshot.open_anomaly_types : [],
    project_phase: snapshot.project_phase,
    execution_status: snapshot.execution_status,
    risk_tier: snapshot.risk_tier,
    progress_heartbeat_effective_seconds: snapshot.progress_heartbeat_effective_seconds,
    review_pulse_effective_seconds: snapshot.review_pulse_effective_seconds,
    brainstorm_review_effective_seconds: snapshot.brainstorm_review_effective_seconds,
    next_review_kind: snapshot.next_review_kind,
    next_review_due: snapshot.next_review_due,
    recovery_decision: compactHeartbeatRecoveryDecision(snapshot.recovery_decision),
  };
}

function compactHeartbeatRecoveryDecision(decision) {
  if (!decision || typeof decision !== "object") return null;

  const out = {};
  const scalarFields = [
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
  ];
  for (const key of scalarFields) {
    const value = decision[key];
    if (value !== undefined && value !== null && value !== "") {
      out[key] = value;
    }
  }

  const arrayFields = [
    "source_signals",
    "source_signal_display_texts",
    "anomaly_types",
    "anomaly_type_display_texts",
    "blocked_lane_reasons",
    "blocked_lane_reason_display_texts",
  ];
  for (const key of arrayFields) {
    if (Array.isArray(decision[key]) && decision[key].length > 0) {
      out[key] = decision[key];
    }
  }

  const countFields = [
    "blocked_lane_count",
    "stalled_lane_count",
    "failed_lane_count",
    "recovering_lane_count",
  ];
  for (const key of countFields) {
    if (typeof decision[key] === "number") {
      out[key] = decision[key];
    }
  }

  if (typeof decision.requires_user_action === "boolean") {
    out.requires_user_action = decision.requires_user_action;
  }

  return Object.keys(out).length > 0 ? out : null;
}

function compactLocalStoreWriteSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    personal_memory_intent: snapshot.personal_memory_intent,
    cross_link_intent: snapshot.cross_link_intent,
    personal_review_intent: snapshot.personal_review_intent,
  };
}

function compactRemoteSnapshotCacheSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    source: snapshot.source,
    freshness: snapshot.freshness,
    cache_hit: snapshot.cache_hit,
    scope: snapshot.scope,
    cached_at_ms: snapshot.cached_at_ms,
    age_ms: snapshot.age_ms,
    ttl_remaining_ms: snapshot.ttl_remaining_ms,
  };
}

function compactXtRouteTargetSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    route_kind: snapshot.route_kind,
    host: snapshot.host,
    pairing_port: snapshot.pairing_port,
    grpc_port: snapshot.grpc_port,
    host_kind: snapshot.host_kind,
    source: snapshot.source,
  };
}

function compactXtFirstPairCompletionProofSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    readiness: snapshot.readiness,
    same_lan_verified: snapshot.same_lan_verified,
    owner_local_approval_verified: snapshot.owner_local_approval_verified,
    pairing_material_issued: snapshot.pairing_material_issued,
    cached_reconnect_smoke_passed: snapshot.cached_reconnect_smoke_passed,
    stable_remote_route_present: snapshot.stable_remote_route_present,
    remote_shadow_smoke_passed: snapshot.remote_shadow_smoke_passed,
    remote_shadow_smoke_status: snapshot.remote_shadow_smoke_status,
    remote_shadow_smoke_source: snapshot.remote_shadow_smoke_source,
    remote_shadow_route: snapshot.remote_shadow_route,
    remote_shadow_reason_code: snapshot.remote_shadow_reason_code,
    remote_shadow_summary: snapshot.remote_shadow_summary,
    summary_line: snapshot.summary_line,
  };
}

function compactXtPairedRouteSetSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    readiness: snapshot.readiness,
    readiness_reason_code: snapshot.readiness_reason_code,
    summary_line: snapshot.summary_line,
    hub_instance_id: snapshot.hub_instance_id,
    pairing_profile_epoch: snapshot.pairing_profile_epoch,
    route_pack_version: snapshot.route_pack_version,
    active_route: compactXtRouteTargetSnapshot(snapshot.active_route),
    lan_route: compactXtRouteTargetSnapshot(snapshot.lan_route),
    stable_remote_route: compactXtRouteTargetSnapshot(snapshot.stable_remote_route),
    last_known_good_route: compactXtRouteTargetSnapshot(snapshot.last_known_good_route),
    cached_reconnect_smoke_status: snapshot.cached_reconnect_smoke_status,
    cached_reconnect_smoke_reason_code: snapshot.cached_reconnect_smoke_reason_code,
    cached_reconnect_smoke_summary: snapshot.cached_reconnect_smoke_summary,
  };
}

function compactXtPairingReadinessSupport(support) {
  if (!support || typeof support !== "object") return null;
  return {
    xt_source_smoke_status: normalizeString(
      support.xt_source_smoke_status,
      "missing"
    ),
    all_source_smoke_status: normalizeString(
      support.all_source_smoke_status,
      "missing"
    ),
    xt_source_first_pair_completion_proof: compactXtFirstPairCompletionProofSnapshot(
      support.xt_source_first_pair_completion_proof
    ),
    xt_source_paired_route_set: compactXtPairedRouteSetSnapshot(
      support.xt_source_paired_route_set
    ),
    all_source_first_pair_completion_proof: compactXtFirstPairCompletionProofSnapshot(
      support.all_source_first_pair_completion_proof
    ),
    all_source_paired_route_set: compactXtPairedRouteSetSnapshot(
      support.all_source_paired_route_set
    ),
  };
}

function compactMemoryRouteTruthSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    projection_source: snapshot.projection_source,
    completeness: snapshot.completeness,
    route_source: snapshot.route_source,
    route_reason_code: snapshot.route_reason_code,
    binding_provider: snapshot.binding_provider,
    binding_model_id: snapshot.binding_model_id,
  };
}

function compactMemoryTruthClosureSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") return null;
  return {
    truth_examples: Array.isArray(snapshot.truth_examples)
      ? snapshot.truth_examples
        .filter((item) => item && typeof item === "object")
        .map((item) => ({
          raw_source: item.raw_source,
          label: item.label,
          explainable_label: item.explainable_label,
          truth_hint: item.truth_hint,
        }))
      : [],
    project_context: snapshot.project_context && typeof snapshot.project_context === "object"
      ? {
          memory_source: snapshot.project_context.memory_source,
          memory_source_label: snapshot.project_context.memory_source_label,
          writer_gate_boundary_present: snapshot.project_context.writer_gate_boundary_present,
        }
      : null,
    supervisor_memory: snapshot.supervisor_memory && typeof snapshot.supervisor_memory === "object"
      ? {
          memory_source: snapshot.supervisor_memory.memory_source,
          mode_source_text: snapshot.supervisor_memory.mode_source_text,
          continuity_detail_line: snapshot.supervisor_memory.continuity_detail_line,
        }
      : null,
    canonical_sync_closure: snapshot.canonical_sync_closure && typeof snapshot.canonical_sync_closure === "object"
      ? {
          doctor_summary_line: snapshot.canonical_sync_closure.doctor_summary_line,
          audit_ref: snapshot.canonical_sync_closure.audit_ref,
          evidence_ref: snapshot.canonical_sync_closure.evidence_ref,
          writeback_ref: snapshot.canonical_sync_closure.writeback_ref,
          strict_issue_code: snapshot.canonical_sync_closure.strict_issue_code,
        }
      : null,
  };
}

function compactBuildSnapshotInventorySurface(surface) {
  if (!surface || typeof surface !== "object") return null;
  return {
    status: surface.status,
    snapshot_root_ref: surface.snapshot_root_ref,
    snapshot_root_exists: surface.snapshot_root_exists,
    retention_keep_count: surface.retention_keep_count,
    current_snapshot_ref: surface.current_snapshot_ref,
    current_snapshot_size_bytes: surface.current_snapshot_size_bytes,
    historical_snapshot_count: surface.historical_snapshot_count,
    historical_snapshot_total_bytes: surface.historical_snapshot_total_bytes,
    would_prune_history_count: surface.would_prune_history_count,
    would_prune_total_bytes: surface.would_prune_total_bytes,
    would_keep_history_refs: Array.isArray(surface.would_keep_history_refs)
      ? surface.would_keep_history_refs
      : [],
    would_prune_history_refs: Array.isArray(surface.would_prune_history_refs)
      ? surface.would_prune_history_refs
      : [],
  };
}

function compactBuildSnapshotInventorySupport(support) {
  if (!support || typeof support !== "object") return null;
  const inventorySummary = support.inventory_summary && typeof support.inventory_summary === "object"
    ? support.inventory_summary
    : {};
  return {
    report_ref: support.report_ref || "",
    build_snapshot_inventory_generation_status:
      support.build_snapshot_inventory_generation_status || "",
    summary_status: inventorySummary.summary_status,
    verdict_reason: inventorySummary.verdict_reason,
    stale_history_surface_ids: Array.isArray(inventorySummary.stale_history_surface_ids)
      ? inventorySummary.stale_history_surface_ids
      : [],
    largest_reclaim_candidate_surface_id:
      inventorySummary.largest_reclaim_candidate_surface_id,
    current_snapshot_total_bytes: inventorySummary.current_snapshot_total_bytes,
    historical_snapshot_total_bytes: inventorySummary.historical_snapshot_total_bytes,
    projected_prune_total_bytes: inventorySummary.projected_prune_total_bytes,
    projected_prune_history_count: inventorySummary.projected_prune_history_count,
    hub: compactBuildSnapshotInventorySurface(inventorySummary.hub),
    xterminal: compactBuildSnapshotInventorySurface(inventorySummary.xterminal),
  };
}

function parseArgs(argv) {
  const out = {
    operatorRecoveryPath: defaultOperatorRecoveryPath,
    operatorChannelRecoveryPath: defaultOperatorChannelRecoveryPath,
    requireRealPath: defaultRequireRealPath,
    boundaryPath: defaultBoundaryPath,
    ossReadinessPath: defaultOssReadinessPath,
    doctorSourceGatePath: defaultDoctorSourceGatePath,
    outputPath: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--operator-recovery":
        out.operatorRecoveryPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--operator-channel-recovery":
        out.operatorChannelRecoveryPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--require-real":
        out.requireRealPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--boundary":
        out.boundaryPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--oss-readiness":
        out.ossReadinessPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--doctor-source-gate":
        out.doctorSourceGatePath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--out":
        out.outputPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }

  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w4_09_c_product_exit_packet.js",
    "  node scripts/generate_lpr_w4_09_c_product_exit_packet.js \\",
    "    --operator-recovery build/reports/xhub_local_service_operator_recovery_report.v1.json \\",
    "    --operator-channel-recovery build/reports/xhub_operator_channel_recovery_report.v1.json \\",
    "    --require-real build/reports/lpr_w3_03_a_require_real_evidence.v1.json \\",
    "    --boundary build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json \\",
    "    --oss-readiness build/reports/oss_release_readiness_v1.json \\",
    "    --doctor-source-gate build/reports/xhub_doctor_source_gate_summary.v1.json \\",
    "    --out build/reports/lpr_w4_09_c_product_exit_packet.v1.json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function compactOperatorRecovery(report) {
  if (!report || typeof report !== "object") return null;
  const recommendedActions = normalizeArray(report.recommended_actions);
  const topAction = recommendedActions[0] || null;
  return {
    gate_verdict: normalizeString(report.gate_verdict, "missing"),
    release_stance: normalizeString(report.release_stance, "missing"),
    machine_decision: report.machine_decision || null,
    local_service_truth: report.local_service_truth || null,
    recovery_classification: report.recovery_classification || null,
    release_wording: report.release_wording || null,
    top_recommended_action: topAction
      ? {
          rank: topAction.rank,
          action_id: topAction.action_id,
          title: topAction.title,
          command_or_ref: topAction.command_or_ref,
        }
      : null,
    recommended_actions: recommendedActions,
    support_faq: normalizeArray(report.support_faq),
  };
}

function compactOperatorChannelRecovery(report) {
  if (!report || typeof report !== "object") return null;
  const recommendedActions = normalizeArray(report.recommended_actions);
  const topAction = recommendedActions[0] || null;
  const onboardingTruth = report.onboarding_truth && typeof report.onboarding_truth === "object"
    ? report.onboarding_truth
    : {};
  const currentFailureCode = normalizeString(onboardingTruth.current_failure_code, "");
  const heartbeatGovernanceVisibilityGap =
    currentFailureCode === "channel_live_test_heartbeat_visibility_missing";
  const channelFocusHighlight = heartbeatGovernanceVisibilityGap
    ? "First smoke proof still lacks heartbeat governance visibility."
    : "";
  return {
    gate_verdict: normalizeString(report.gate_verdict, "missing"),
    release_stance: normalizeString(report.release_stance, "missing"),
    verdict_reason: normalizeString(report.verdict_reason, ""),
    machine_decision: report.machine_decision || null,
    heartbeat_governance_visibility_gap: heartbeatGovernanceVisibilityGap,
    channel_focus_highlight: channelFocusHighlight,
    onboarding_truth: {
      overall_state: normalizeString(onboardingTruth.overall_state, "missing"),
      ready_for_first_task: normalizeBoolean(onboardingTruth.ready_for_first_task),
      current_failure_code: currentFailureCode,
      current_failure_issue: normalizeString(onboardingTruth.current_failure_issue, ""),
      primary_check_kind: normalizeString(onboardingTruth.primary_check_kind, ""),
      primary_check_status: normalizeString(onboardingTruth.primary_check_status, ""),
      primary_check_blocking: normalizeBoolean(onboardingTruth.primary_check_blocking),
      repair_destination_ref: normalizeString(onboardingTruth.repair_destination_ref, ""),
      provider_ids: normalizeArray(onboardingTruth.provider_ids),
      error_codes: normalizeArray(onboardingTruth.error_codes),
      fetch_errors: normalizeArray(onboardingTruth.fetch_errors),
      required_next_steps: normalizeArray(onboardingTruth.required_next_steps),
    },
    recovery_classification: report.recovery_classification || null,
    release_wording: report.release_wording || null,
    top_recommended_action: topAction
      ? {
          rank: topAction.rank,
          action_id: topAction.action_id,
          title: topAction.title,
          command_or_ref: topAction.command_or_ref,
        }
      : null,
    recommended_actions: recommendedActions,
    support_faq: normalizeArray(report.support_faq),
  };
}

function compactRequireReal(report) {
  if (!report || typeof report !== "object") return null;
  const machineDecision = report.machine_decision || {};
  const sample1OperatorHandoffFromMachine =
    machineDecision.sample1_operator_handoff && typeof machineDecision.sample1_operator_handoff === "object"
      ? machineDecision.sample1_operator_handoff
      : null;
  const sample1OperatorHandoffFromSupport =
    report.sample1_require_real_support && typeof report.sample1_require_real_support.operator_handoff === "object"
      ? report.sample1_require_real_support.operator_handoff
      : null;
  const sample1OperatorHandoff =
    sample1OperatorHandoffFromMachine || sample1OperatorHandoffFromSupport
      ? {
          ...(sample1OperatorHandoffFromSupport || {}),
          ...(sample1OperatorHandoffFromMachine || {}),
        }
      : null;
  const sample1CandidateAcceptanceFromMachine =
    machineDecision.sample1_candidate_acceptance && typeof machineDecision.sample1_candidate_acceptance === "object"
      ? machineDecision.sample1_candidate_acceptance
      : null;
  const sample1CandidateAcceptanceFromHandoff =
    sample1OperatorHandoff && typeof sample1OperatorHandoff.candidate_acceptance === "object"
      ? sample1OperatorHandoff.candidate_acceptance
      : null;
  const sample1CandidateAcceptanceFromSupport =
    report.sample1_require_real_support &&
    typeof report.sample1_require_real_support.candidate_acceptance_packet === "object"
      ? report.sample1_require_real_support.candidate_acceptance_packet
      : null;
  const sample1CandidateAcceptance =
    sample1CandidateAcceptanceFromMachine ||
    sample1CandidateAcceptanceFromHandoff ||
    sample1CandidateAcceptanceFromSupport
      ? {
          ...(sample1CandidateAcceptanceFromSupport || {}),
          ...(sample1CandidateAcceptanceFromHandoff || {}),
          ...(sample1CandidateAcceptanceFromMachine || {}),
        }
      : null;
  const sample1CandidateRegistrationFromMachine =
    machineDecision.sample1_candidate_registration && typeof machineDecision.sample1_candidate_registration === "object"
      ? machineDecision.sample1_candidate_registration
      : null;
  const sample1CandidateRegistrationFromHandoff =
    sample1OperatorHandoff && typeof sample1OperatorHandoff.candidate_registration === "object"
      ? sample1OperatorHandoff.candidate_registration
      : null;
  const sample1CandidateRegistrationFromSupport =
    report.sample1_require_real_support &&
    typeof report.sample1_require_real_support.candidate_registration_packet === "object"
      ? report.sample1_require_real_support.candidate_registration_packet
      : null;
  const sample1CandidateRegistration =
    sample1CandidateRegistrationFromMachine ||
    sample1CandidateRegistrationFromHandoff ||
    sample1CandidateRegistrationFromSupport
      ? {
          ...(sample1CandidateRegistrationFromSupport || {}),
          ...(sample1CandidateRegistrationFromHandoff || {}),
          ...(sample1CandidateRegistrationFromMachine || {}),
        }
      : null;
  return {
    gate_verdict: normalizeString(report.gate_verdict, "missing"),
    release_stance: normalizeString(report.release_stance, "missing"),
    verdict_reason: normalizeString(report.verdict_reason, ""),
    next_required_artifacts: normalizeArray(report.next_required_artifacts),
    gate_readiness: report.gate_readiness || null,
    machine_decision: {
      pending_samples: normalizeArray(machineDecision.pending_samples),
      failed_samples: normalizeArray(machineDecision.failed_samples),
      invalid_samples: normalizeArray(machineDecision.invalid_samples),
      synthetic_samples: normalizeArray(machineDecision.synthetic_samples),
      missing_evidence_samples: normalizeArray(machineDecision.missing_evidence_samples),
      all_samples_executed: normalizeBoolean(machineDecision.all_samples_executed),
      all_samples_passed: normalizeBoolean(machineDecision.all_samples_passed),
      sample1_probe_artifacts_present:
        machineDecision.sample1_probe_artifacts_present || null,
      sample1_current_blockers: normalizeArray(machineDecision.sample1_current_blockers),
      sample1_runtime_ready: normalizeBoolean(machineDecision.sample1_runtime_ready),
      sample1_execution_ready: normalizeBoolean(machineDecision.sample1_execution_ready),
      sample1_overall_recommended_action_id: normalizeString(
        machineDecision.sample1_overall_recommended_action_id
      ),
      sample1_overall_recommended_action_summary: normalizeString(
        machineDecision.sample1_overall_recommended_action_summary
      ),
      sample1_preferred_route: machineDecision.sample1_preferred_route || null,
      sample1_secondary_route: machineDecision.sample1_secondary_route || null,
      sample1_operator_handoff_state: normalizeString(machineDecision.sample1_operator_handoff_state),
      sample1_operator_handoff_blocker_class: normalizeString(
        machineDecision.sample1_operator_handoff_blocker_class
      ),
      sample1_candidate_acceptance_present: normalizeBoolean(
        machineDecision.sample1_candidate_acceptance_present
      ) || !!sample1CandidateAcceptance,
      sample1_candidate_registration_present: normalizeBoolean(
        machineDecision.sample1_candidate_registration_present
      ) || !!sample1CandidateRegistration,
    },
    sample1_operator_handoff: sample1OperatorHandoff,
    sample1_candidate_acceptance: sample1CandidateAcceptance,
    sample1_candidate_registration: sample1CandidateRegistration,
  };
}

function compactBoundary(report) {
  if (!report || typeof report !== "object") return null;
  return {
    status: normalizeString(report.status, "missing"),
    blockers: normalizeArray(report.blockers),
    release_alignment: report.release_alignment || null,
    scope_boundary: report.scope_boundary || null,
  };
}

function compactOssReadiness(report) {
  if (!report || typeof report !== "object") return null;
  return {
    status: normalizeString(report.status, "missing"),
    release_stance: normalizeString(report.release_stance, "missing"),
    missing_evidence: normalizeArray(report.missing_evidence),
    hard_lines: normalizeArray(report.hard_lines),
    checks: report.checks || null,
  };
}

function buildRefreshReleasePreflight(overrides = null) {
  if (overrides && typeof overrides === "object") {
    if (Array.isArray(overrides.required_inputs)) {
      const requiredInputs = normalizeArray(overrides.required_inputs);
      const normalizedInputs = requiredInputs.map((item) => ({
        ref: normalizeString(item?.ref, "missing"),
        present: normalizeBoolean(item?.present),
      }));
      const missingInputs = normalizedInputs
        .filter((item) => !item.present)
        .map((item) => item.ref);
      return {
        ready: missingInputs.length === 0,
        required_inputs: normalizedInputs,
        missing_inputs: missingInputs,
        xt_ready_preferred_input: overrides.xt_ready_preferred_input || null,
      };
    }
  }

  const repoRootForScan =
    overrides && typeof overrides === "object" && overrides.repoRoot
      ? path.resolve(overrides.repoRoot)
      : repoRoot;
  const existsFn =
    overrides && typeof overrides === "object" && typeof overrides.existsFn === "function"
      ? overrides.existsFn
      : (ref) => fs.existsSync(path.join(repoRootForScan, ref));

  const requiredInputs = refreshReleaseInputRefs.map((ref) => ({
    ref,
    present: existsFn(ref),
  }));
  const xtReadyPreferredInput = resolvePreferredXtReadyInput(existsFn);
  const normalizedInputs = [
    ...requiredInputs,
    ...xtReadyPreferredInput.required_inputs,
  ];
  const missingInputs = normalizedInputs
    .filter((item) => !item.present)
    .map((item) => item.ref);
  return {
    ready: missingInputs.length === 0,
    required_inputs: normalizedInputs,
    missing_inputs: missingInputs,
    xt_ready_preferred_input: xtReadyPreferredInput,
  };
}

function resolvePreferredXtReadyInput(existsFn) {
  const reportCandidates = preferredXtReadyArtifactCandidates.map((candidate) => ({
    mode: candidate.mode,
    ref: candidate.reportRef,
    present: existsFn(candidate.reportRef),
  }));
  const selectedCandidate = preferredXtReadyArtifactCandidates.find((candidate) =>
    existsFn(candidate.reportRef)
  );

  if (!selectedCandidate) {
    return {
      mode: "missing",
      ready: false,
      selected_report_ref: null,
      selected_source_ref: null,
      selected_connector_ref: null,
      report_candidates: reportCandidates,
      source_candidates: [],
      connector_candidates: [],
      required_inputs: [
        {
          ref: buildAlternativeRefLabel(
            preferredXtReadyArtifactCandidates.map((candidate) => candidate.reportRef)
          ),
          present: false,
        },
      ],
    };
  }

  const sourceCandidates = selectedCandidate.sourceRefs.map((ref) => ({
    ref,
    present: existsFn(ref),
  }));
  const connectorCandidates = selectedCandidate.connectorRefs.map((ref) => ({
    ref,
    present: existsFn(ref),
  }));
  const selectedSource = sourceCandidates.find((candidate) => candidate.present) || null;
  const selectedConnector =
    connectorCandidates.find((candidate) => candidate.present) || null;
  return {
    mode: selectedCandidate.mode,
    ready: selectedSource !== null && selectedConnector !== null,
    selected_report_ref: selectedCandidate.reportRef,
    selected_source_ref: selectedSource?.ref || null,
    selected_connector_ref: selectedConnector?.ref || null,
    report_candidates: reportCandidates,
    source_candidates: sourceCandidates,
    connector_candidates: connectorCandidates,
    required_inputs: [
      {
        ref: selectedCandidate.reportRef,
        present: true,
      },
      {
        ref:
          selectedSource?.ref ||
          buildAlternativeRefLabel(selectedCandidate.sourceRefs),
        present: selectedSource !== null,
      },
      {
        ref:
          selectedConnector?.ref ||
          buildAlternativeRefLabel(selectedCandidate.connectorRefs),
        present: selectedConnector !== null,
      },
    ],
  };
}

function buildProductExitPacket(inputs = {}) {
  const generatedAt = inputs.generatedAt || isoNow();
  const timezone = inputs.timezone || "Asia/Shanghai";
  const operatorRecovery = inputs.operatorRecovery || null;
  const operatorChannelRecovery = inputs.operatorChannelRecovery || null;
  const requireReal = inputs.requireReal || null;
  const boundary = inputs.boundary || null;
  const ossReadiness = inputs.ossReadiness || null;
  const doctorSourceGate = inputs.doctorSourceGate || null;
  const refreshReleasePreflight = buildRefreshReleasePreflight(
    inputs.releaseRefreshPreflight || null
  );

  const compactRecovery = compactOperatorRecovery(operatorRecovery);
  const compactChannelRecovery = compactOperatorChannelRecovery(operatorChannelRecovery);
  const compactRequireRealReport = compactRequireReal(requireReal);
  const compactBoundaryReport = compactBoundary(boundary);
  const compactOssReadinessReport = compactOssReadiness(ossReadiness);

  const operatorSupportReady = normalizeBoolean(
    compactRecovery?.machine_decision?.support_ready
  );
  const operatorChannelSupportReady = normalizeBoolean(
    compactChannelRecovery?.machine_decision?.support_ready
  );
  const doctorSourceGatePass =
    normalizeString(doctorSourceGate?.overall_status, "missing") === "pass";
  const requireRealStance = normalizeString(
    compactRequireRealReport?.release_stance,
    "missing"
  );
  const requireRealReady =
    requireRealStance === "candidate_go" || requireRealStance === "release_ready";
  const boundaryReady = normalizeString(
    compactBoundaryReport?.status,
    "missing"
  ).startsWith("delivered(");
  const ossReleaseReady =
    normalizeString(compactOssReadinessReport?.release_stance, "missing") === "GO";
  const topActionID = normalizeString(
    compactRecovery?.top_recommended_action?.action_id,
    "missing"
  );
  const channelTopActionID = normalizeString(
    compactChannelRecovery?.top_recommended_action?.action_id,
    "missing"
  );
  const currentActionCategory = normalizeString(
    compactRecovery?.recovery_classification?.action_category,
    normalizeString(compactRecovery?.machine_decision?.action_category, "unknown")
  );
  const currentChannelActionCategory = normalizeString(
    compactChannelRecovery?.recovery_classification?.action_category,
    normalizeString(compactChannelRecovery?.machine_decision?.action_category, "missing")
  );

  const blockers = [];
  if (!compactRecovery) blockers.push("operator_recovery_report_missing");
  else if (!normalizeString(compactRecovery.gate_verdict).startsWith("PASS(")) {
    blockers.push("operator_recovery_report_fail_closed");
  }
  if (!operatorSupportReady) blockers.push("operator_support_not_ready");
  if (!doctorSourceGatePass) blockers.push("doctor_source_gate_not_green");
  if (!compactRequireRealReport) blockers.push("require_real_report_missing");
  else if (!requireRealReady) blockers.push("require_real_not_ready");
  if (!compactBoundaryReport) blockers.push("release_boundary_report_missing");
  else if (!boundaryReady) blockers.push("release_boundary_not_ready");
  if (!compactOssReadinessReport) blockers.push("oss_release_readiness_missing");
  else if (!ossReleaseReady) blockers.push("oss_release_not_go");
  if (!refreshReleasePreflight.ready) blockers.push("release_refresh_inputs_missing");

  const exitReady = blockers.length === 0;
  const gateVerdict = exitReady
    ? "PASS(product_exit_packet_ready_for_operator_and_release_handoff)"
    : "NO_GO(product_exit_packet_fail_closed)";

  const verdictReason = exitReady
    ? "Operator recovery truth, require-real closure, release boundary, and OSS readiness are all present and green enough to hand off one product-exit packet."
    : `Product exit remains blocked because: ${blockers.join(", ")}.`;

  const missingArtifacts = [
    !compactRecovery
      ? "build/reports/xhub_local_service_operator_recovery_report.v1.json"
      : null,
    !compactRequireRealReport
      ? "build/reports/lpr_w3_03_a_require_real_evidence.v1.json"
      : null,
    !compactBoundaryReport
      ? "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json"
      : null,
    !compactOssReadinessReport
      ? "build/reports/oss_release_readiness_v1.json"
      : null,
    !doctorSourceGate
      ? "build/reports/xhub_doctor_source_gate_summary.v1.json"
      : null,
  ].filter(Boolean);

  return {
    schema_version: "xhub.lpr_w4_09_c_product_exit_packet.v1",
    generated_at: generatedAt,
    timezone,
    lane: "Hub-L5",
    work_order: "LPR-W4-09-C",
    scope: "xhub_local_service product exit / operator runbook / support faq / release closure",
    fail_closed: true,
    gate_verdict: gateVerdict,
    verdict_reason: verdictReason,
    machine_decision: {
      operator_support_ready: operatorSupportReady,
      doctor_source_gate_status: normalizeString(
        doctorSourceGate?.overall_status,
        "missing"
      ),
      require_real_release_stance: requireRealStance,
      boundary_ready: boundaryReady,
      oss_release_ready: ossReleaseReady,
      current_action_category: currentActionCategory,
      top_action_id: topActionID,
      operator_channel_support_ready: operatorChannelSupportReady,
      operator_channel_action_category: currentChannelActionCategory,
      operator_channel_top_action_id: channelTopActionID,
      exit_ready: exitReady,
    },
    blockers,
    missing_artifacts: missingArtifacts,
    artifact_status: {
      operator_recovery: {
        present: !!compactRecovery,
        gate_verdict: compactRecovery?.gate_verdict || "missing",
        release_stance: compactRecovery?.release_stance || "missing",
      },
      operator_channel_recovery: {
        present: !!compactChannelRecovery,
        gate_verdict: compactChannelRecovery?.gate_verdict || "missing",
        release_stance: compactChannelRecovery?.release_stance || "missing",
        support_ready: operatorChannelSupportReady,
        action_category: currentChannelActionCategory,
      },
      require_real: {
        present: !!compactRequireRealReport,
        gate_verdict: compactRequireRealReport?.gate_verdict || "missing",
        release_stance: compactRequireRealReport?.release_stance || "missing",
        pending_samples_count: compactRequireRealReport
          ? compactRequireRealReport.machine_decision.pending_samples.length
          : 0,
      },
      release_boundary: {
        present: !!compactBoundaryReport,
        status: compactBoundaryReport?.status || "missing",
        blocker_count: compactBoundaryReport
          ? normalizeArray(compactBoundaryReport.blockers).length
          : 0,
      },
      oss_release_readiness: {
        present: !!compactOssReadinessReport,
        status: compactOssReadinessReport?.status || "missing",
        release_stance: compactOssReadinessReport?.release_stance || "missing",
        missing_evidence_count: compactOssReadinessReport
          ? normalizeArray(compactOssReadinessReport.missing_evidence).length
          : 0,
      },
    },
    release_refresh_preflight: refreshReleasePreflight,
    operator_handoff: {
      primary_issue_reason_code:
        compactRecovery?.local_service_truth?.primary_issue_reason_code || "unknown",
      managed_process_state:
        compactRecovery?.local_service_truth?.managed_process_state || "unknown",
      managed_start_attempt_count:
        compactRecovery?.local_service_truth?.managed_start_attempt_count ?? 0,
      top_recommended_action: compactRecovery?.top_recommended_action || null,
      recommended_actions: compactRecovery?.recommended_actions || [],
      channel_onboarding_focus: compactChannelRecovery
        ? {
            verdict_reason: compactChannelRecovery.verdict_reason,
            gate_verdict: compactChannelRecovery.gate_verdict,
            release_stance: compactChannelRecovery.release_stance,
            support_ready: operatorChannelSupportReady,
            heartbeat_governance_visibility_gap:
              compactChannelRecovery.heartbeat_governance_visibility_gap === true,
            channel_focus_highlight: compactChannelRecovery.channel_focus_highlight || "",
            current_failure_code:
              compactChannelRecovery.onboarding_truth?.current_failure_code || "missing",
            current_failure_issue:
              compactChannelRecovery.onboarding_truth?.current_failure_issue || "missing",
            action_category: currentChannelActionCategory,
            top_recommended_action: compactChannelRecovery.top_recommended_action,
            recommended_actions: compactChannelRecovery.recommended_actions || [],
            support_faq: compactChannelRecovery.support_faq || [],
          }
        : null,
      support_faq: compactRecovery?.support_faq || [],
      require_real_focus: compactRequireRealReport
        ? {
            verdict_reason: compactRequireRealReport.verdict_reason,
            next_required_artifacts: compactRequireRealReport.next_required_artifacts || [],
            ...(compactRequireRealReport.sample1_operator_handoff || {}),
            current_machine_state:
              compactRequireRealReport.sample1_candidate_acceptance?.current_machine_state || null,
            filtered_out_examples:
              compactRequireRealReport.sample1_candidate_acceptance?.filtered_out_examples || [],
            candidate_acceptance: compactRequireRealReport.sample1_candidate_acceptance || null,
            candidate_registration: compactRequireRealReport.sample1_candidate_registration || null,
          }
        : null,
      runbook_refs: [
        "docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md",
        "docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md",
        "docs/WORKING_INDEX.md",
      ],
      next_commands: [
        "bash scripts/ci/xhub_doctor_source_gate.sh",
        "node scripts/generate_xhub_local_service_operator_recovery_report.js",
        "node scripts/generate_xhub_operator_channel_recovery_report.js",
        "bash scripts/refresh_oss_release_evidence.sh",
      ],
    },
    release_handoff: {
      external_status_line:
        compactRecovery?.release_wording?.external_status_line ||
        "Structured local-service recovery wording is not available.",
      allowed_external_claims:
        compactBoundaryReport?.scope_boundary?.external_claims_limited_to || [],
      boundary_status: compactBoundaryReport?.status || "missing",
      oss_release_stance: compactOssReadinessReport?.release_stance || "missing",
      remote_channel_status_line:
        compactChannelRecovery?.release_wording?.external_status_line ||
        "Structured operator-channel onboarding recovery wording is not available.",
      remote_channel_focus_highlight:
        compactChannelRecovery?.channel_focus_highlight || "",
      release_blockers: normalizeArray(compactOssReadinessReport?.missing_evidence),
      refresh_bundle_ready: refreshReleasePreflight.ready,
      refresh_bundle_missing_inputs: refreshReleasePreflight.missing_inputs,
    },
    support_truth: {
      operator_recovery: compactRecovery,
      operator_channel_recovery: compactChannelRecovery,
      require_real: compactRequireRealReport,
      boundary: compactBoundaryReport,
      oss_release_readiness: compactOssReadinessReport,
      doctor_source_gate: doctorSourceGate
        ? {
            overall_status: normalizeString(doctorSourceGate.overall_status, "missing"),
            summary: doctorSourceGate.summary || null,
            project_context_summary_support: doctorSourceGate.project_context_summary_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.project_context_summary_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.project_context_summary_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_project_context_summary: compactProjectContextSummary(
                    doctorSourceGate.project_context_summary_support.xt_source_project_context_summary
                  ),
                  all_source_project_context_summary: compactProjectContextSummary(
                    doctorSourceGate.project_context_summary_support.all_source_project_context_summary
                  ),
                }
              : null,
            project_memory_policy_support: doctorSourceGate.project_memory_policy_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.project_memory_policy_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.project_memory_policy_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_project_memory_policy: compactProjectMemoryPolicy(
                    doctorSourceGate.project_memory_policy_support.xt_source_project_memory_policy
                  ),
                  all_source_project_memory_policy: compactProjectMemoryPolicy(
                    doctorSourceGate.project_memory_policy_support.all_source_project_memory_policy
                  ),
                }
              : null,
            project_memory_assembly_resolution_support: doctorSourceGate.project_memory_assembly_resolution_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.project_memory_assembly_resolution_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.project_memory_assembly_resolution_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_project_memory_assembly_resolution: compactMemoryAssemblyResolution(
                    doctorSourceGate.project_memory_assembly_resolution_support.xt_source_project_memory_assembly_resolution
                  ),
                  all_source_project_memory_assembly_resolution: compactMemoryAssemblyResolution(
                    doctorSourceGate.project_memory_assembly_resolution_support.all_source_project_memory_assembly_resolution
                  ),
                }
              : null,
            project_remote_snapshot_cache_support: doctorSourceGate.project_remote_snapshot_cache_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.project_remote_snapshot_cache_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.project_remote_snapshot_cache_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_project_remote_snapshot_cache_snapshot: compactRemoteSnapshotCacheSnapshot(
                    doctorSourceGate.project_remote_snapshot_cache_support.xt_source_project_remote_snapshot_cache_snapshot
                  ),
                  all_source_project_remote_snapshot_cache_snapshot: compactRemoteSnapshotCacheSnapshot(
                    doctorSourceGate.project_remote_snapshot_cache_support.all_source_project_remote_snapshot_cache_snapshot
                  ),
                }
              : null,
            heartbeat_governance_support: doctorSourceGate.heartbeat_governance_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.heartbeat_governance_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.heartbeat_governance_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_heartbeat_governance_snapshot: compactHeartbeatGovernanceSnapshot(
                    doctorSourceGate.heartbeat_governance_support.xt_source_heartbeat_governance_snapshot
                  ),
                  all_source_heartbeat_governance_snapshot: compactHeartbeatGovernanceSnapshot(
                    doctorSourceGate.heartbeat_governance_support.all_source_heartbeat_governance_snapshot
                  ),
                }
              : null,
            supervisor_memory_policy_support: doctorSourceGate.supervisor_memory_policy_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.supervisor_memory_policy_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.supervisor_memory_policy_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_supervisor_memory_policy: compactSupervisorMemoryPolicy(
                    doctorSourceGate.supervisor_memory_policy_support.xt_source_supervisor_memory_policy
                  ),
                  all_source_supervisor_memory_policy: compactSupervisorMemoryPolicy(
                    doctorSourceGate.supervisor_memory_policy_support.all_source_supervisor_memory_policy
                  ),
                }
              : null,
            supervisor_memory_assembly_resolution_support: doctorSourceGate.supervisor_memory_assembly_resolution_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.supervisor_memory_assembly_resolution_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.supervisor_memory_assembly_resolution_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_supervisor_memory_assembly_resolution: compactMemoryAssemblyResolution(
                    doctorSourceGate.supervisor_memory_assembly_resolution_support.xt_source_supervisor_memory_assembly_resolution
                  ),
                  all_source_supervisor_memory_assembly_resolution: compactMemoryAssemblyResolution(
                    doctorSourceGate.supervisor_memory_assembly_resolution_support.all_source_supervisor_memory_assembly_resolution
                  ),
                }
              : null,
            supervisor_remote_snapshot_cache_support: doctorSourceGate.supervisor_remote_snapshot_cache_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.supervisor_remote_snapshot_cache_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.supervisor_remote_snapshot_cache_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_supervisor_remote_snapshot_cache_snapshot: compactRemoteSnapshotCacheSnapshot(
                    doctorSourceGate.supervisor_remote_snapshot_cache_support.xt_source_supervisor_remote_snapshot_cache_snapshot
                  ),
                  all_source_supervisor_remote_snapshot_cache_snapshot: compactRemoteSnapshotCacheSnapshot(
                    doctorSourceGate.supervisor_remote_snapshot_cache_support.all_source_supervisor_remote_snapshot_cache_snapshot
                  ),
                }
              : null,
            durable_candidate_mirror_support: doctorSourceGate.durable_candidate_mirror_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.durable_candidate_mirror_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.durable_candidate_mirror_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_durable_candidate_mirror_snapshot: compactDurableCandidateMirrorSnapshot(
                    doctorSourceGate.durable_candidate_mirror_support.xt_source_durable_candidate_mirror_snapshot
                  ),
                  all_source_durable_candidate_mirror_snapshot: compactDurableCandidateMirrorSnapshot(
                    doctorSourceGate.durable_candidate_mirror_support.all_source_durable_candidate_mirror_snapshot
                  ),
                }
              : null,
            local_store_write_support: doctorSourceGate.local_store_write_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.local_store_write_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.local_store_write_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_local_store_write_snapshot: compactLocalStoreWriteSnapshot(
                    doctorSourceGate.local_store_write_support.xt_source_local_store_write_snapshot
                  ),
                  all_source_local_store_write_snapshot: compactLocalStoreWriteSnapshot(
                    doctorSourceGate.local_store_write_support.all_source_local_store_write_snapshot
                  ),
                }
              : null,
            xt_pairing_readiness_support: doctorSourceGate.xt_pairing_readiness_support
              ? compactXtPairingReadinessSupport(
                  doctorSourceGate.xt_pairing_readiness_support
                )
              : null,
            memory_route_truth_support: doctorSourceGate.memory_route_truth_support
              ? {
                  xt_source_smoke_status: normalizeString(
                    doctorSourceGate.memory_route_truth_support.xt_source_smoke_status,
                    "missing"
                  ),
                  all_source_smoke_status: normalizeString(
                    doctorSourceGate.memory_route_truth_support.all_source_smoke_status,
                    "missing"
                  ),
                  xt_source_memory_route_truth_snapshot: compactMemoryRouteTruthSnapshot(
                    doctorSourceGate.memory_route_truth_support.xt_source_memory_route_truth_snapshot
                  ),
                  all_source_memory_route_truth_snapshot: compactMemoryRouteTruthSnapshot(
                    doctorSourceGate.memory_route_truth_support.all_source_memory_route_truth_snapshot
                  ),
                }
              : null,
            xt_memory_truth_closure_support: doctorSourceGate.xt_memory_truth_closure_support
              ? {
                  xt_memory_truth_closure_smoke_status: normalizeString(
                    doctorSourceGate.xt_memory_truth_closure_support.xt_memory_truth_closure_smoke_status,
                    "missing"
                  ),
                  xt_memory_truth_closure_snapshot: compactMemoryTruthClosureSnapshot(
                    doctorSourceGate.xt_memory_truth_closure_support.xt_memory_truth_closure_snapshot
                  ),
                }
              : null,
            build_snapshot_inventory_support: doctorSourceGate.build_snapshot_inventory_support
              ? compactBuildSnapshotInventorySupport(
                  doctorSourceGate.build_snapshot_inventory_support
                )
              : null,
          }
        : null,
    },
    evidence_refs: [
      ...(compactRecovery
        ? ["build/reports/xhub_local_service_operator_recovery_report.v1.json"]
        : []),
      ...(compactChannelRecovery
        ? ["build/reports/xhub_operator_channel_recovery_report.v1.json"]
        : []),
      ...(compactRequireRealReport
        ? ["build/reports/lpr_w3_03_a_require_real_evidence.v1.json"]
        : []),
      ...(compactBoundaryReport
        ? ["build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json"]
        : []),
      ...(compactOssReadinessReport
        ? ["build/reports/oss_release_readiness_v1.json"]
        : []),
      ...(doctorSourceGate
        ? ["build/reports/xhub_doctor_source_gate_summary.v1.json"]
        : []),
      "scripts/generate_lpr_w4_09_c_product_exit_packet.js",
    ],
    inputs: {
      operator_recovery_present: !!compactRecovery,
      operator_channel_recovery_present: !!compactChannelRecovery,
      require_real_present: !!compactRequireRealReport,
      boundary_present: !!compactBoundaryReport,
      oss_readiness_present: !!compactOssReadinessReport,
      doctor_source_gate_present: !!doctorSourceGate,
      operator_recovery_ref:
        "build/reports/xhub_local_service_operator_recovery_report.v1.json",
      operator_channel_recovery_ref:
        "build/reports/xhub_operator_channel_recovery_report.v1.json",
      require_real_ref: "build/reports/lpr_w3_03_a_require_real_evidence.v1.json",
      boundary_ref: "build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json",
      oss_readiness_ref: "build/reports/oss_release_readiness_v1.json",
      doctor_source_gate_ref: "build/reports/xhub_doctor_source_gate_summary.v1.json",
    },
  };
}

function main() {
  const args = parseArgs(process.argv);
  const packet = buildProductExitPacket({
    operatorRecovery: readJSONIfExists(args.operatorRecoveryPath),
    operatorChannelRecovery: readJSONIfExists(args.operatorChannelRecoveryPath),
    requireReal: readJSONIfExists(args.requireRealPath),
    boundary: readJSONIfExists(args.boundaryPath),
    ossReadiness: readJSONIfExists(args.ossReadinessPath),
    doctorSourceGate: readJSONIfExists(args.doctorSourceGatePath),
  });
  writeJSON(args.outputPath, packet);
  process.stdout.write(`${args.outputPath}\n`);
}

if (require.main === module) {
  main();
}

module.exports = {
  buildProductExitPacket,
  buildRefreshReleasePreflight,
  parseArgs,
};
