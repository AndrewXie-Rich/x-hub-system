#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');
const {
  buildXtReadyReleaseDiagnostics,
  compactXtReadyReleaseDiagnostics,
  DEFAULT_DB_CANDIDATE_REFS,
  writeXtReadyReleaseDiagnostics,
} = require('./xt_ready_release_diagnostics.js');

const ROOT = process.env.XHUB_RELEASE_ROOT
  ? path.resolve(process.env.XHUB_RELEASE_ROOT)
  : path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'build', 'reports');
const TIMEZONE = process.env.TZ || 'Asia/Shanghai';
const MAINLINE = ['XT-W3-23', 'XT-W3-24', 'XT-W3-25'];

function readText(relPath) {
  return fs.readFileSync(path.join(ROOT, relPath), 'utf8');
}

function readJson(relPath) {
  return JSON.parse(readText(relPath));
}

function exists(relPath) {
  return fs.existsSync(path.join(ROOT, relPath));
}

function readJsonIfExists(relPath) {
  return exists(relPath) ? readJson(relPath) : null;
}

function writeJson(relPath, payload) {
  const absPath = path.join(ROOT, relPath);
  fs.mkdirSync(path.dirname(absPath), { recursive: true });
  fs.writeFileSync(absPath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
}

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function includesAll(text, patterns) {
  return patterns.map((pattern) => ({ pattern, ok: String(text).includes(String(pattern)) }));
}

function walk(dirPath, acc = []) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    const abs = path.join(dirPath, entry.name);
    const rel = path.relative(ROOT, abs).split(path.sep).join('/');
    if (entry.isDirectory()) {
      if (
        entry.name === 'build' ||
        entry.name === 'node_modules' ||
        entry.name === '.build' ||
        entry.name === '.axcoder' ||
        entry.name === '.sandbox_home' ||
        entry.name === '.sandbox_tmp' ||
        rel === 'archive/x-terminal-legacy'
      ) {
        continue;
      }
      walk(abs, acc);
      continue;
    }
    acc.push(rel);
  }
  return acc;
}

function isSensitiveFilename(relPath) {
  const base = path.basename(relPath).toLowerCase();
  return (
    base === '.env' ||
    /kek.*\.json$/i.test(base) ||
    /dek.*\.json$/i.test(base) ||
    /\.sqlite3?$/i.test(base) ||
    /\.sqlite3-(shm|wal)$/i.test(base)
  );
}

function blacklistCovers(relPath) {
  return (
    /(^|\/)build\//.test(relPath) ||
    /(^|\/)data\//.test(relPath) ||
    /(^|\/)node_modules\//.test(relPath) ||
    /(^|\/)\.build\//.test(relPath) ||
    /(^|\/)\.axcoder\//.test(relPath) ||
    /(^|\/)\.sandbox_home\//.test(relPath) ||
    /(^|\/)\.sandbox_tmp\//.test(relPath) ||
    /(^|\/)DerivedData\//.test(relPath) ||
    /(^|\/)__pycache__\//.test(relPath) ||
    /\.sqlite3?$/i.test(relPath) ||
    /\.sqlite3-(shm|wal)$/i.test(relPath) ||
    /(^|\/)\.env$/i.test(relPath) ||
    /kek/i.test(relPath) ||
    /dek/i.test(relPath) ||
    /secret/i.test(relPath) ||
    /token/i.test(relPath) ||
    /password/i.test(relPath)
  );
}

function pick(obj, keys) {
  const out = {};
  for (const key of keys) out[key] = obj[key];
  return out;
}

function findStepById(report, stepId) {
  if (!report || !Array.isArray(report.steps)) return null;
  return report.steps.find((step) => step.step_id === stepId) || null;
}

function compactProjectContextSummary(summary) {
  if (!summary || typeof summary !== 'object') return null;
  return pick(summary, [
    'source_kind',
    'source_badge',
    'status_line',
    'project_label',
    'dialogue_metric',
    'depth_metric',
    'dialogue_line',
    'depth_line',
    'coverage_metric',
    'boundary_metric',
    'coverage_line',
    'boundary_line',
  ]);
}

function compactProjectMemoryPolicy(policy) {
  if (!policy || typeof policy !== 'object') return null;
  return pick(policy, [
    'configured_recent_project_dialogue_profile',
    'configured_project_context_depth',
    'recommended_recent_project_dialogue_profile',
    'recommended_project_context_depth',
    'effective_recent_project_dialogue_profile',
    'effective_project_context_depth',
    'a_tier_memory_ceiling',
    'audit_ref',
  ]);
}

function compactSupervisorMemoryPolicy(policy) {
  if (!policy || typeof policy !== 'object') return null;
  return pick(policy, [
    'configured_supervisor_recent_raw_context_profile',
    'configured_review_memory_depth',
    'recommended_supervisor_recent_raw_context_profile',
    'recommended_review_memory_depth',
    'effective_supervisor_recent_raw_context_profile',
    'effective_review_memory_depth',
    's_tier_review_memory_ceiling',
    'audit_ref',
  ]);
}

function compactMemoryAssemblyResolution(resolution) {
  if (!resolution || typeof resolution !== 'object') return null;
  return {
    role: resolution.role,
    dominant_mode: resolution.dominant_mode,
    trigger: resolution.trigger,
    configured_depth: resolution.configured_depth,
    recommended_depth: resolution.recommended_depth,
    effective_depth: resolution.effective_depth,
    ceiling_from_tier: resolution.ceiling_from_tier,
    ceiling_hit: resolution.ceiling_hit,
    selected_slots: Array.isArray(resolution.selected_slots) ? resolution.selected_slots : [],
    selected_planes: Array.isArray(resolution.selected_planes) ? resolution.selected_planes : [],
    selected_serving_objects: Array.isArray(resolution.selected_serving_objects)
      ? resolution.selected_serving_objects
      : [],
    excluded_blocks: Array.isArray(resolution.excluded_blocks) ? resolution.excluded_blocks : [],
    budget_summary: resolution.budget_summary,
    audit_ref: resolution.audit_ref,
  };
}

function compactMemoryRouteTruthSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return pick(snapshot, [
    'projection_source',
    'completeness',
    'route_source',
    'route_reason_code',
    'binding_provider',
    'binding_model_id',
  ]);
}

function compactDurableCandidateMirrorSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return pick(snapshot, [
    'status',
    'target',
    'attempted',
    'error_code',
    'local_store_role',
  ]);
}

function compactHeartbeatGovernanceSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
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
  if (!decision || typeof decision !== 'object') return null;

  const out = {};
  const scalarFields = [
    'action',
    'action_display_text',
    'urgency',
    'urgency_display_text',
    'reason_code',
    'reason_display_text',
    'system_next_step_display_text',
    'summary',
    'doctor_explainability_text',
    'queued_review_trigger',
    'queued_review_trigger_display_text',
    'queued_review_level',
    'queued_review_level_display_text',
    'queued_review_run_kind',
    'queued_review_run_kind_display_text',
  ];
  for (const key of scalarFields) {
    const value = decision[key];
    if (value !== undefined && value !== null && value !== '') {
      out[key] = value;
    }
  }

  const arrayFields = [
    'source_signals',
    'source_signal_display_texts',
    'anomaly_types',
    'anomaly_type_display_texts',
    'blocked_lane_reasons',
    'blocked_lane_reason_display_texts',
  ];
  for (const key of arrayFields) {
    if (Array.isArray(decision[key]) && decision[key].length > 0) {
      out[key] = decision[key];
    }
  }

  const countFields = [
    'blocked_lane_count',
    'stalled_lane_count',
    'failed_lane_count',
    'recovering_lane_count',
  ];
  for (const key of countFields) {
    if (typeof decision[key] === 'number') {
      out[key] = decision[key];
    }
  }

  if (typeof decision.requires_user_action === 'boolean') {
    out.requires_user_action = decision.requires_user_action;
  }

  return Object.keys(out).length > 0 ? out : null;
}

function compactLocalStoreWriteSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return pick(snapshot, [
    'personal_memory_intent',
    'cross_link_intent',
    'personal_review_intent',
  ]);
}

function compactRemoteSnapshotCacheSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return pick(snapshot, [
    'source',
    'freshness',
    'cache_hit',
    'scope',
    'cached_at_ms',
    'age_ms',
    'ttl_remaining_ms',
  ]);
}

function compactXtRouteTargetSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return pick(snapshot, [
    'route_kind',
    'host',
    'pairing_port',
    'grpc_port',
    'host_kind',
    'source',
  ]);
}

function compactXtFirstPairCompletionProofSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return pick(snapshot, [
    'readiness',
    'same_lan_verified',
    'owner_local_approval_verified',
    'pairing_material_issued',
    'cached_reconnect_smoke_passed',
    'stable_remote_route_present',
    'remote_shadow_smoke_passed',
    'remote_shadow_smoke_status',
    'remote_shadow_smoke_source',
    'remote_shadow_route',
    'remote_shadow_reason_code',
    'remote_shadow_summary',
    'summary_line',
  ]);
}

function compactXtPairedRouteSetSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
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
  if (!support || typeof support !== 'object') return null;
  return {
    xt_source_smoke_status: support.xt_source_smoke_status || '',
    all_source_smoke_status: support.all_source_smoke_status || '',
    xt_source_first_pair_completion_proof: compactXtFirstPairCompletionProofSnapshot(
      support.xt_source_first_pair_completion_proof,
    ),
    xt_source_paired_route_set: compactXtPairedRouteSetSnapshot(
      support.xt_source_paired_route_set,
    ),
    all_source_first_pair_completion_proof: compactXtFirstPairCompletionProofSnapshot(
      support.all_source_first_pair_completion_proof,
    ),
    all_source_paired_route_set: compactXtPairedRouteSetSnapshot(
      support.all_source_paired_route_set,
    ),
    xt_source_smoke_evidence_ref: support.xt_source_smoke_evidence_ref || '',
    all_source_smoke_evidence_ref: support.all_source_smoke_evidence_ref || '',
  };
}

function compactMemoryTruthClosureSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return {
    truth_examples: Array.isArray(snapshot.truth_examples)
      ? snapshot.truth_examples
        .filter((item) => item && typeof item === 'object')
        .map((item) => pick(item, [
          'raw_source',
          'label',
          'explainable_label',
          'truth_hint',
        ]))
      : [],
    project_context: snapshot.project_context && typeof snapshot.project_context === 'object'
      ? pick(snapshot.project_context, [
          'memory_source',
          'memory_source_label',
          'writer_gate_boundary_present',
        ])
      : null,
    supervisor_memory: snapshot.supervisor_memory && typeof snapshot.supervisor_memory === 'object'
      ? pick(snapshot.supervisor_memory, [
          'memory_source',
          'mode_source_text',
          'continuity_detail_line',
        ])
      : null,
    canonical_sync_closure: snapshot.canonical_sync_closure && typeof snapshot.canonical_sync_closure === 'object'
      ? pick(snapshot.canonical_sync_closure, [
          'doctor_summary_line',
          'audit_ref',
          'evidence_ref',
          'writeback_ref',
          'strict_issue_code',
        ])
      : null,
  };
}

function compactBuildSnapshotInventorySurface(surface) {
  if (!surface || typeof surface !== 'object') return null;
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
  if (!support || typeof support !== 'object') return null;
  const inventorySummary = support.inventory_summary && typeof support.inventory_summary === 'object'
    ? support.inventory_summary
    : {};
  return {
    report_ref: support.report_ref || '',
    build_snapshot_inventory_generation_status:
      support.build_snapshot_inventory_generation_status || '',
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

function compactHubPairingSmokeSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return {
    mode: snapshot.mode,
    ok: snapshot.ok,
    launch: snapshot.launch && typeof snapshot.launch === 'object'
      ? pick(snapshot.launch, [
          'action',
          'background_launch_evidence_found',
          'main_panel_shown_after_launch',
        ])
      : null,
    discovery: snapshot.discovery && typeof snapshot.discovery === 'object'
      ? pick(snapshot.discovery, [
          'ok',
          'status',
          'pairing_enabled',
          'hub_instance_id',
          'lan_discovery_name',
          'hub_host_hint',
          'grpc_port',
          'pairing_port',
          'tls_mode',
          'internet_host_hint',
        ])
      : null,
    admin_token: snapshot.admin_token && typeof snapshot.admin_token === 'object'
      ? pick(snapshot.admin_token, ['resolved', 'token_source'])
      : null,
    pairing: snapshot.pairing && typeof snapshot.pairing === 'object'
      ? pick(snapshot.pairing, [
          'request_id',
          'pairing_request_id',
          'device_name',
          'post_status',
          'pending_list_status',
          'pending_list_contains_request',
          'cleanup_status',
          'cleanup_verified',
        ])
      : null,
    error_count: snapshot.error_count,
  };
}

function compactHubPairingRoundtripSupport(support) {
  if (!support || typeof support !== 'object') return null;
  return {
    launch_only_smoke_status: support.launch_only_smoke_status || '',
    launch_only_smoke_evidence_ref: support.launch_only_smoke_evidence_ref || '',
    launch_only_snapshot: compactHubPairingSmokeSnapshot(
      support.launch_only_snapshot,
    ),
    verify_only_smoke_status: support.verify_only_smoke_status || '',
    verify_only_smoke_evidence_ref: support.verify_only_smoke_evidence_ref || '',
    verify_only_snapshot: compactHubPairingSmokeSnapshot(
      support.verify_only_snapshot,
    ),
  };
}

function compactTopRecommendedAction(action) {
  if (!action || typeof action !== 'object') return null;
  return pick(action, ['rank', 'action_id', 'title', 'command_or_ref']);
}

function compactScanRootSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return pick(snapshot, ['path', 'present']);
}

function compactHelperLocalServiceRecovery(report) {
  if (!report || typeof report !== 'object') return null;
  return {
    current_machine_state: report.current_machine_state
      ? pick(report.current_machine_state, [
          'helper_binary_found',
          'helper_binary_path',
          'helper_server_base_url',
          'server_models_endpoint_ok',
          'settings_found',
          'settings_path',
          'enable_local_service',
          'cli_installed',
          'app_first_load',
          'primary_blocker',
          'recommended_next_step',
        ])
      : null,
    helper_route_contract: report.helper_route_contract
      ? {
          ...pick(report.helper_route_contract, [
            'helper_route_role',
            'helper_route_ready_verdict',
            'required_ready_signals',
          ]),
          reject_signals: Array.isArray(report.helper_route_contract.reject_signals)
            ? report.helper_route_contract.reject_signals
              .map((signal) => (
                signal && typeof signal === 'object'
                  ? pick(signal, ['signal', 'reason'])
                  : null
              ))
              .filter(Boolean)
            : [],
        }
      : null,
    top_recommended_action: report.top_recommended_action
      ? pick(report.top_recommended_action, [
          'action_id',
          'action_summary',
          'next_step',
          'command_or_ref',
        ])
      : null,
    operator_workflow: Array.isArray(report.operator_workflow)
      ? report.operator_workflow
        .map((step) => (
          step && typeof step === 'object'
            ? pick(step, ['step_id', 'allowed_now', 'description', 'command', 'command_or_ref'])
            : null
        ))
        .filter(Boolean)
      : [],
    artifact_refs: report.artifact_refs
      ? pick(report.artifact_refs, ['helper_probe_report'])
      : null,
  };
}

function compactRequireRealSearchRecovery(report) {
  if (!report || typeof report !== 'object') return null;
  return pick(report, [
    'exact_path_known',
    'exact_path_exists',
    'exact_path_validation_command',
    'wide_shortlist_search_command',
    'preferred_next_step',
  ]);
}

function compactOperatorRecoverySupport(report) {
  if (!report || typeof report !== 'object') return null;
  const recommendedActions = Array.isArray(report.recommended_actions) ? report.recommended_actions : [];
  const requireRealFocus = report.require_real_focus && typeof report.require_real_focus === 'object'
    ? report.require_real_focus
    : null;
  return {
    schema_version: report.schema_version,
    gate_verdict: report.gate_verdict,
    release_stance: report.release_stance,
    machine_decision: report.machine_decision
      ? pick(report.machine_decision, [
          'support_ready',
          'release_ready',
          'source_gate_status',
          'snapshot_smoke_status',
          'require_real_release_stance',
          'require_real_focus_helper_local_service_recovery_present',
          'action_category',
        ])
      : null,
    local_service_truth: report.local_service_truth
      ? pick(report.local_service_truth, [
          'provider_id',
          'primary_issue_reason_code',
          'doctor_failure_code',
          'doctor_provider_check_status',
          'service_state',
          'runtime_reason_code',
          'managed_process_state',
          'managed_start_attempt_count',
          'managed_last_start_error',
          'repair_destination_ref',
        ])
      : null,
    recovery_classification: report.recovery_classification
      ? pick(report.recovery_classification, ['action_category', 'severity', 'install_hint'])
      : null,
    release_wording: report.release_wording
      ? pick(report.release_wording, ['external_status_line'])
      : null,
    top_recommended_action: compactTopRecommendedAction(recommendedActions[0]),
    require_real_focus: requireRealFocus
      ? {
          handoff_state: requireRealFocus.handoff_state,
          blocker_class: requireRealFocus.blocker_class,
          top_recommended_action: requireRealFocus.top_recommended_action
            ? pick(requireRealFocus.top_recommended_action, ['action_id', 'action_summary'])
            : null,
          helper_local_service_recovery: compactHelperLocalServiceRecovery(
            requireRealFocus.helper_local_service_recovery,
          ),
          checked_sources: requireRealFocus.checked_sources
            ? {
                scan_roots: Array.isArray(requireRealFocus.checked_sources.scan_roots)
                  ? requireRealFocus.checked_sources.scan_roots
                    .map((snapshot) => compactScanRootSnapshot(snapshot))
                    .filter(Boolean)
                  : [],
              }
            : null,
          search_recovery: compactRequireRealSearchRecovery(requireRealFocus.search_recovery),
          candidate_acceptance: requireRealFocus.candidate_acceptance
            ? {
                acceptance_contract: requireRealFocus.candidate_acceptance.acceptance_contract
                  ? pick(requireRealFocus.candidate_acceptance.acceptance_contract, [
                      'required_gate_verdict',
                      'required_loadability_verdict',
                    ])
                  : null,
                current_no_go_example: requireRealFocus.candidate_acceptance.current_no_go_example
                  ? pick(requireRealFocus.candidate_acceptance.current_no_go_example, [
                      'normalized_model_dir',
                      'loadability_blocker',
                    ])
                  : null,
              }
            : null,
          candidate_registration: requireRealFocus.candidate_registration
            ? {
                machine_decision: requireRealFocus.candidate_registration.machine_decision
                  ? {
                      catalog_write_allowed_now:
                        requireRealFocus.candidate_registration.machine_decision.catalog_write_allowed_now,
                      top_recommended_action: requireRealFocus.candidate_registration.machine_decision.top_recommended_action
                        ? pick(requireRealFocus.candidate_registration.machine_decision.top_recommended_action, [
                            'action_id',
                            'action_summary',
                          ])
                        : null,
                    }
                  : null,
                candidate_validation: requireRealFocus.candidate_registration.candidate_validation
                  ? pick(requireRealFocus.candidate_registration.candidate_validation, [
                      'gate_verdict',
                      'loadability_blocker',
                    ])
                  : null,
                proposed_catalog_entry: requireRealFocus.candidate_registration.proposed_catalog_entry
                  ? pick(requireRealFocus.candidate_registration.proposed_catalog_entry, [
                      'id',
                      'backend',
                      'model_path',
                    ])
                  : null,
                catalog_patch_plan_summary: requireRealFocus.candidate_registration.catalog_patch_plan_summary
                  ? pick(requireRealFocus.candidate_registration.catalog_patch_plan_summary, [
                      'artifact_ref',
                      'manual_patch_allowed_now',
                      'blocked_reason',
                      'eligible_target_base_count',
                      'blocked_target_base_count',
                    ])
                  : null,
              }
            : null,
        }
      : null,
  };
}

function compactOperatorChannelRecoverySupport(report) {
  if (!report || typeof report !== 'object') return null;
  const recommendedActions = Array.isArray(report.recommended_actions) ? report.recommended_actions : [];
  const topAction = recommendedActions[0] || null;
  const onboardingTruth = report.onboarding_truth && typeof report.onboarding_truth === 'object'
    ? report.onboarding_truth
    : null;
  const currentFailureCode = String(onboardingTruth?.current_failure_code || '').trim();
  const heartbeatGovernanceVisibilityGap =
    currentFailureCode === 'channel_live_test_heartbeat_visibility_missing';
  return {
    schema_version: report.schema_version,
    gate_verdict: report.gate_verdict,
    release_stance: report.release_stance,
    heartbeat_governance_visibility_gap: heartbeatGovernanceVisibilityGap,
    channel_focus_highlight: heartbeatGovernanceVisibilityGap
      ? 'First smoke proof still lacks heartbeat governance visibility.'
      : '',
    machine_decision: report.machine_decision
      ? pick(report.machine_decision, [
          'support_ready',
          'source',
          'source_gate_status',
          'all_source_smoke_status',
          'overall_state',
          'ready_for_first_task',
          'current_failure_code',
          'current_failure_issue',
          'action_category',
        ])
      : null,
    onboarding_truth: onboardingTruth
      ? pick(onboardingTruth, [
          'overall_state',
          'ready_for_first_task',
          'current_failure_code',
          'current_failure_issue',
          'primary_check_kind',
          'primary_check_status',
          'primary_check_blocking',
          'repair_destination_ref',
        ])
      : null,
    recovery_classification: report.recovery_classification
      ? pick(report.recovery_classification, [
          'action_category',
          'severity',
          'install_hint',
        ])
      : null,
    release_wording: report.release_wording
      ? pick(report.release_wording, ['external_status_line'])
      : null,
    top_recommended_action: compactTopRecommendedAction(topAction),
  };
}

function selectPreferredXtReadyArtifacts() {
  const candidates = [
    {
      mode: 'require_real_release_chain',
      reportRef: 'build/xt_ready_gate_e2e_require_real_report.json',
      sourceRefs: [
        'build/xt_ready_evidence_source.require_real.json',
        'build/xt_ready_evidence_source.json',
      ],
      connectorRefs: [
        'build/connector_ingress_gate_snapshot.require_real.json',
        'build/connector_ingress_gate_snapshot.json',
      ],
    },
    {
      mode: 'db_real_release_chain',
      reportRef: 'build/xt_ready_gate_e2e_db_real_report.json',
      sourceRefs: [
        'build/xt_ready_evidence_source.db_real.json',
        'build/xt_ready_evidence_source.require_real.json',
        'build/xt_ready_evidence_source.json',
      ],
      connectorRefs: [
        'build/connector_ingress_gate_snapshot.db_real.json',
        'build/connector_ingress_gate_snapshot.require_real.json',
        'build/connector_ingress_gate_snapshot.json',
      ],
    },
    {
      mode: 'current_gate',
      reportRef: 'build/xt_ready_gate_e2e_report.json',
      sourceRefs: ['build/xt_ready_evidence_source.json'],
      connectorRefs: ['build/connector_ingress_gate_snapshot.json'],
    },
  ];

  for (const candidate of candidates) {
    if (!exists(candidate.reportRef)) continue;
    const sourceRef = candidate.sourceRefs.find((relPath) => exists(relPath)) || candidate.sourceRefs[0];
    const connectorRef =
      candidate.connectorRefs.find((relPath) => exists(relPath)) || candidate.connectorRefs[0];
    return {
      mode: candidate.mode,
      reportRef: candidate.reportRef,
      sourceRef,
      connectorRef,
      report: readJson(candidate.reportRef),
      source: readJson(sourceRef),
      connector: readJson(connectorRef),
    };
  }

  throw new Error('missing XT-Ready gate evidence: no preferred report candidate exists');
}

function main() {
  const docs = {
    minimal: readText('docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md'),
    release: readText('docs/open-source/OSS_RELEASE_CHECKLIST_v1.md'),
    paths: readText('docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md'),
  };

  const governanceFiles = [
    'README.md',
    'LICENSE',
    'NOTICE.md',
    'SECURITY.md',
    'CONTRIBUTING.md',
    'CODE_OF_CONDUCT.md',
    'CODEOWNERS',
    'CHANGELOG.md',
    'RELEASE.md',
    '.gitignore',
  ];
  const governanceChecks = governanceFiles.map((relPath) => ({ relPath, ok: exists(relPath) }));

  const releaseDecision = readJson('build/reports/xt_w3_release_ready_decision.v1.json');
  const provenance = readJson('build/reports/xt_w3_require_real_provenance.v2.json');
  const xtReadyArtifacts = selectPreferredXtReadyArtifacts();
  const xtReady = xtReadyArtifacts.report;
  const xtReadySource = xtReadyArtifacts.source;
  const xtReadyReportRef = xtReadyArtifacts.reportRef;
  const xtReadySourceRef = xtReadyArtifacts.sourceRef;
  const connectorGateRef = xtReadyArtifacts.connectorRef;
  const connectorGate = xtReadyArtifacts.connector;
  const xtReadyDiagnostics = buildXtReadyReleaseDiagnostics({
    rootDir: ROOT,
    xtReadyGate: xtReady,
    xtReadySource,
    connectorGate,
    xtReadyArtifact: {
      mode: xtReadyArtifacts.mode,
      reportRef: xtReadyReportRef,
      sourceRef: xtReadySourceRef,
      connectorGateRef,
    },
    dbCandidateRefs: DEFAULT_DB_CANDIDATE_REFS,
  });
  const xtReadyDiagnosticsRef = 'build/reports/xt_ready_release_diagnostics.v1.json';
  const internalPassGlobal = readJson('build/hub_l5_release_internal_pass_lines_report.json');
  const internalPassW3 = readJson('build/reports/xt_w3_internal_pass_lines_release_ready.v1.json');
  const rollback = readJson('build/reports/xt_w3_25_competitive_rollback.v1.json');
  const doctorSourceGateRef = 'build/reports/xhub_doctor_source_gate_summary.v1.json';
  const doctorSourceGate = readJsonIfExists(doctorSourceGateRef);
  const operatorRecoveryRef = 'build/reports/xhub_local_service_operator_recovery_report.v1.json';
  const operatorRecoveryReport = readJsonIfExists(operatorRecoveryRef);
  const operatorChannelRecoveryRef = 'build/reports/xhub_operator_channel_recovery_report.v1.json';
  const operatorChannelRecoveryReport = readJsonIfExists(operatorChannelRecoveryRef);
  const doctorProjectContextSupport = doctorSourceGate?.project_context_summary_support || null;
  const doctorProjectMemoryPolicySupport = doctorSourceGate?.project_memory_policy_support || null;
  const doctorProjectMemoryAssemblyResolutionSupport =
    doctorSourceGate?.project_memory_assembly_resolution_support || null;
  const doctorProjectRemoteSnapshotCacheSupport =
    doctorSourceGate?.project_remote_snapshot_cache_support || null;
  const doctorHeartbeatGovernanceSupport = doctorSourceGate?.heartbeat_governance_support || null;
  const doctorSupervisorMemoryPolicySupport = doctorSourceGate?.supervisor_memory_policy_support || null;
  const doctorSupervisorMemoryAssemblyResolutionSupport =
    doctorSourceGate?.supervisor_memory_assembly_resolution_support || null;
  const doctorSupervisorRemoteSnapshotCacheSupport =
    doctorSourceGate?.supervisor_remote_snapshot_cache_support || null;
  const doctorDurableCandidateMirrorSupport = doctorSourceGate?.durable_candidate_mirror_support || null;
  const doctorLocalStoreWriteSupport = doctorSourceGate?.local_store_write_support || null;
  const doctorXtPairingReadinessSupport = doctorSourceGate?.xt_pairing_readiness_support || null;
  const doctorMemoryRouteSupport = doctorSourceGate?.memory_route_truth_support || null;
  const doctorHubPairingRoundtripSupport =
    doctorSourceGate?.hub_pairing_roundtrip_support || null;
  const doctorMemoryTruthClosureSupport = doctorSourceGate?.xt_memory_truth_closure_support || null;
  const doctorBuildSnapshotInventorySupport = doctorSourceGate?.build_snapshot_inventory_support || null;
  const doctorXtSmokeEvidenceRef =
    doctorProjectContextSupport?.xt_source_smoke_evidence_ref ||
    doctorProjectMemoryPolicySupport?.xt_source_smoke_evidence_ref ||
    doctorProjectMemoryAssemblyResolutionSupport?.xt_source_smoke_evidence_ref ||
    doctorProjectRemoteSnapshotCacheSupport?.xt_source_smoke_evidence_ref ||
    doctorHeartbeatGovernanceSupport?.xt_source_smoke_evidence_ref ||
    doctorSupervisorMemoryPolicySupport?.xt_source_smoke_evidence_ref ||
    doctorSupervisorMemoryAssemblyResolutionSupport?.xt_source_smoke_evidence_ref ||
    doctorSupervisorRemoteSnapshotCacheSupport?.xt_source_smoke_evidence_ref ||
    doctorXtPairingReadinessSupport?.xt_source_smoke_evidence_ref ||
    '';
  const doctorAllSmokeEvidenceRef =
    doctorProjectContextSupport?.all_source_smoke_evidence_ref ||
    doctorProjectMemoryPolicySupport?.all_source_smoke_evidence_ref ||
    doctorProjectMemoryAssemblyResolutionSupport?.all_source_smoke_evidence_ref ||
    doctorProjectRemoteSnapshotCacheSupport?.all_source_smoke_evidence_ref ||
    doctorHeartbeatGovernanceSupport?.all_source_smoke_evidence_ref ||
    doctorSupervisorMemoryPolicySupport?.all_source_smoke_evidence_ref ||
    doctorSupervisorMemoryAssemblyResolutionSupport?.all_source_smoke_evidence_ref ||
    doctorSupervisorRemoteSnapshotCacheSupport?.all_source_smoke_evidence_ref ||
    doctorXtPairingReadinessSupport?.all_source_smoke_evidence_ref ||
    '';
  const doctorHubPairingLaunchOnlyEvidenceRef =
    doctorHubPairingRoundtripSupport?.launch_only_smoke_evidence_ref || '';
  const doctorHubPairingVerifyOnlyEvidenceRef =
    doctorHubPairingRoundtripSupport?.verify_only_smoke_evidence_ref || '';
  const doctorXtMemoryTruthClosureEvidenceRef =
    doctorMemoryTruthClosureSupport?.xt_memory_truth_closure_smoke_evidence_ref || '';
  const doctorBuildSnapshotInventoryReportRef =
    doctorBuildSnapshotInventorySupport?.report_ref || '';

  const docChecks = {
    minimal: includesAll(docs.minimal, ['OSS-G0', 'OSS-G5', 'GO|NO-GO|INSUFFICIENT_EVIDENCE', 'build/reports/oss_secret_scrub_report.v1.json']),
    release: includesAll(docs.release, ['OSS-G0', 'OSS-G5', 'build/reports/oss_secret_scrub_report.v1.json', 'rollback']),
    paths: includesAll(docs.paths, ['allowlist-first + fail-closed', 'build/**', '**/*kek*.json', '**/*secret*', 'GO|NO-GO|INSUFFICIENT_EVIDENCE']),
  };

  const sensitiveFindings = walk(ROOT)
    .filter((relPath) => isSensitiveFilename(relPath))
    .map((relPath) => ({ relPath, blacklist_covered: blacklistCovers(relPath) }));

  const boundaryEvidence = [
    { relPath: 'build/reports/xt_w3_23_direct_require_real_provenance_binding.v1.json', required: true },
    { relPath: 'build/reports/xt_w3_24_direct_require_real_provenance_binding.v1.json', required: true },
    { relPath: 'build/reports/xt_w3_require_real_provenance.v2.json', required: true },
    { relPath: 'build/reports/xt_w3_release_ready_decision.v1.json', required: true },
    { relPath: xtReadyReportRef, required: true },
    { relPath: xtReadySourceRef, required: true },
    { relPath: connectorGateRef, required: true },
    { relPath: 'build/hub_l5_release_internal_pass_lines_report.json', required: true },
    { relPath: 'build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json', required: true },
    { relPath: 'build/reports/xt_w3_25_e_bootstrap_templates_evidence.v1.json', required: true },
    { relPath: 'build/reports/xt_w3_24_f_channel_hub_boundary_evidence.v1.json', required: true },
    { relPath: 'build/reports/xt_w3_25_competitive_rollback.v1.json', required: true },
    { relPath: doctorSourceGateRef, required: false },
    { relPath: operatorRecoveryRef, required: false },
    { relPath: operatorChannelRecoveryRef, required: false },
    ...(doctorXtSmokeEvidenceRef ? [{ relPath: doctorXtSmokeEvidenceRef, required: false }] : []),
    ...(doctorAllSmokeEvidenceRef ? [{ relPath: doctorAllSmokeEvidenceRef, required: false }] : []),
    ...(doctorHubPairingLaunchOnlyEvidenceRef ? [{ relPath: doctorHubPairingLaunchOnlyEvidenceRef, required: false }] : []),
    ...(doctorHubPairingVerifyOnlyEvidenceRef ? [{ relPath: doctorHubPairingVerifyOnlyEvidenceRef, required: false }] : []),
    ...(doctorXtMemoryTruthClosureEvidenceRef ? [{ relPath: doctorXtMemoryTruthClosureEvidenceRef, required: false }] : []),
    ...(doctorBuildSnapshotInventoryReportRef ? [{ relPath: doctorBuildSnapshotInventoryReportRef, required: false }] : []),
  ];
  const boundaryEvidenceChecks = boundaryEvidence.map(({ relPath, required }) => ({
    relPath,
    required,
    ok: exists(relPath),
  }));
  const requiredBoundaryEvidenceChecks = boundaryEvidenceChecks.filter((item) => item.required);

  const outOfScopeCoverageFalse = Object.entries((internalPassW3.checks || {}).coverage_checks || {})
    .filter(([key, value]) => !value && !MAINLINE.includes(key))
    .map(([key]) => key);
  const internalPassAlignment = {
    w3_report_release_decision: String(internalPassW3.release_decision || ''),
    global_report_release_decision: String(internalPassGlobal.release_decision || ''),
    out_of_scope_coverage_false: outOfScopeCoverageFalse,
    release_ready_non_scope_note_present: String(releaseDecision.non_scope_note || '').trim().length > 0,
    effective_source_ref: 'build/hub_l5_release_internal_pass_lines_report.json',
    superseded_ref: 'build/reports/xt_w3_internal_pass_lines_release_ready.v1.json',
    alignment_status:
      String(internalPassGlobal.release_decision || '') === 'GO' &&
      outOfScopeCoverageFalse.length > 0 &&
      String(releaseDecision.non_scope_note || '').trim().length > 0
        ? 'pass(scope_frozen_effective_source_selected)'
        : 'blocked(scope_frozen_internal_pass_lines_alignment_missing)',
  };

  const gateSummary = {
    'OSS-G0': governanceChecks.every((item) => item.ok) ? 'PASS' : 'FAIL',
    'OSS-G1': sensitiveFindings.every((item) => item.blacklist_covered) ? 'PASS' : 'FAIL',
    'OSS-G2': requiredBoundaryEvidenceChecks.filter((item) => /bootstrap|onboard/.test(item.relPath)).every((item) => item.ok) ? 'PASS' : 'FAIL',
    'OSS-G3': xtReady.ok === true && connectorGate.snapshot?.pass === true ? 'PASS' : 'FAIL',
    'OSS-G4': governanceChecks.every((item) => item.ok) && docChecks.minimal.every((item) => item.ok) && docChecks.release.every((item) => item.ok) ? 'PASS' : 'FAIL',
    'OSS-G5': rollback.rollback_ready === true && String(internalPassGlobal.release_decision || '') === 'GO' ? 'PASS' : 'FAIL',
  };

  const blockers = [];
  if (!(releaseDecision.release_ready === true && provenance.summary?.release_stance === 'release_ready')) {
    blockers.push('validated_mainline_release_ready_not_bound');
  }
  if (!(xtReady.ok === true && xtReady.require_real_audit_source === true && xtReadySource.selected_source !== 'sample_fixture')) {
    blockers.push('require_real_or_audit_source_not_strict');
  }
  if (!(connectorGate.source_used === 'audit' && connectorGate.snapshot?.pass === true)) {
    blockers.push('connector_gate_not_audit_green');
  }
  if (!(String(internalPassGlobal.release_decision || '') === 'GO' && internalPassAlignment.alignment_status.startsWith('pass'))) {
    blockers.push('internal_pass_lines_scope_alignment_missing');
  }
  if (!(rollback.rollback_ready === true)) {
    blockers.push('rollback_ready_missing');
  }
  if (!sensitiveFindings.every((item) => item.blacklist_covered)) {
    blockers.push('sensitive_path_outside_blacklist_coverage');
  }
  if (!governanceChecks.every((item) => item.ok)) {
    blockers.push('governance_file_missing');
  }
  if (!requiredBoundaryEvidenceChecks.every((item) => item.ok)) {
    blockers.push('boundary_evidence_missing');
  }

  const consumerEvidence = {
    xt_main: [
      'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      'build/reports/xt_w3_release_ready_decision.v1.json',
      'build/reports/xt_w3_require_real_provenance.v2.json',
      xtReadyReportRef,
      'build/reports/xt_w3_25_competitive_rollback.v1.json',
      operatorRecoveryRef,
      operatorChannelRecoveryRef,
    ],
    qa_main: [
      'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      'build/hub_l5_release_internal_pass_lines_report.json',
      xtReadySourceRef,
      connectorGateRef,
      operatorRecoveryRef,
      operatorChannelRecoveryRef,
      'docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md',
    ],
  };

  const readiness = {
    schema_version: 'xhub.hub_l5_r1_release_oss_boundary_readiness.v1',
    generated_at: isoNow(),
    timezone: TIMEZONE,
    lane: 'Hub-L5',
    slice_id: 'R1',
    status: blockers.length === 0
      ? 'delivered(validated_mainline_release_oss_boundary_ready)'
      : 'blocked(validated_mainline_release_oss_boundary_gap)',
    scope_boundary: {
      validated_mainline_only: true,
      mainline_chain: MAINLINE,
      no_scope_expansion: true,
      no_unverified_claims: true,
      effective_release_scope_ref: 'build/reports/xt_w3_release_ready_decision.v1.json',
      external_claims_limited_to: [
        'XT memory UX adapter backed by Hub truth-source',
        'Hub-governed multi-channel gateway',
        'Hub-first governed automations',
      ],
    },
    gates: gateSummary,
    release_alignment: {
      require_real: pick(provenance.summary, ['strict_xt_ready_require_real_pass', 'unified_release_ready_provenance_pass', 'release_stance']),
      xt_ready: {
        evidence_mode: xtReadyArtifacts.mode,
        report_ref: xtReadyReportRef,
        evidence_source_ref: xtReadySourceRef,
        connector_gate_ref: connectorGateRef,
        ok: xtReady.ok === true,
        require_real_audit_source: xtReady.require_real_audit_source === true,
        selected_audit_source: xtReadySource.selected_source,
      },
      xt_ready_diagnostics: compactXtReadyReleaseDiagnostics(xtReadyDiagnostics),
      connector_gate: {
        evidence_ref: connectorGateRef,
        source_used: connectorGate.source_used,
        pass: connectorGate.snapshot?.pass === true,
        blocked_event_miss_rate: connectorGate.summary?.blocked_event_miss_rate,
      },
      doctor_source_gate: doctorSourceGate
        ? {
            evidence_ref: doctorSourceGateRef,
            schema_version: doctorSourceGate.schema_version,
            overall_status: doctorSourceGate.overall_status,
            pass: doctorSourceGate.overall_status === 'pass',
            summary: pick(doctorSourceGate.summary || {}, ['passed', 'failed']),
            wrapper_dispatch_tests: findStepById(doctorSourceGate, 'wrapper_dispatch_tests'),
            xt_source_smoke: findStepById(doctorSourceGate, 'xt_source_smoke'),
            aggregate_source_smoke: findStepById(doctorSourceGate, 'all_source_smoke'),
            project_context_summary_support: doctorSourceGate.project_context_summary_support
              ? {
                  xt_source_smoke_status: doctorSourceGate.project_context_summary_support.xt_source_smoke_status,
                  all_source_smoke_status: doctorSourceGate.project_context_summary_support.all_source_smoke_status,
                  xt_source_project_context_summary: compactProjectContextSummary(
                    doctorSourceGate.project_context_summary_support.xt_source_project_context_summary,
                  ),
                  all_source_project_context_summary: compactProjectContextSummary(
                    doctorSourceGate.project_context_summary_support.all_source_project_context_summary,
                  ),
                  xt_source_smoke_evidence_ref: doctorSourceGate.project_context_summary_support.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref: doctorSourceGate.project_context_summary_support.all_source_smoke_evidence_ref || '',
                }
              : null,
            project_memory_policy_support: doctorProjectMemoryPolicySupport
              ? {
                  xt_source_smoke_status: doctorProjectMemoryPolicySupport.xt_source_smoke_status,
                  all_source_smoke_status: doctorProjectMemoryPolicySupport.all_source_smoke_status,
                  xt_source_project_memory_policy: compactProjectMemoryPolicy(
                    doctorProjectMemoryPolicySupport.xt_source_project_memory_policy,
                  ),
                  all_source_project_memory_policy: compactProjectMemoryPolicy(
                    doctorProjectMemoryPolicySupport.all_source_project_memory_policy,
                  ),
                  xt_source_smoke_evidence_ref:
                    doctorProjectMemoryPolicySupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref:
                    doctorProjectMemoryPolicySupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            project_memory_assembly_resolution_support: doctorProjectMemoryAssemblyResolutionSupport
              ? {
                  xt_source_smoke_status:
                    doctorProjectMemoryAssemblyResolutionSupport.xt_source_smoke_status,
                  all_source_smoke_status:
                    doctorProjectMemoryAssemblyResolutionSupport.all_source_smoke_status,
                  xt_source_project_memory_assembly_resolution: compactMemoryAssemblyResolution(
                    doctorProjectMemoryAssemblyResolutionSupport.xt_source_project_memory_assembly_resolution,
                  ),
                  all_source_project_memory_assembly_resolution: compactMemoryAssemblyResolution(
                    doctorProjectMemoryAssemblyResolutionSupport.all_source_project_memory_assembly_resolution,
                  ),
                  xt_source_smoke_evidence_ref:
                    doctorProjectMemoryAssemblyResolutionSupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref:
                    doctorProjectMemoryAssemblyResolutionSupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            project_remote_snapshot_cache_support: doctorProjectRemoteSnapshotCacheSupport
              ? {
                  xt_source_smoke_status: doctorProjectRemoteSnapshotCacheSupport.xt_source_smoke_status,
                  all_source_smoke_status: doctorProjectRemoteSnapshotCacheSupport.all_source_smoke_status,
                  xt_source_project_remote_snapshot_cache_snapshot: compactRemoteSnapshotCacheSnapshot(
                    doctorProjectRemoteSnapshotCacheSupport.xt_source_project_remote_snapshot_cache_snapshot,
                  ),
                  all_source_project_remote_snapshot_cache_snapshot: compactRemoteSnapshotCacheSnapshot(
                    doctorProjectRemoteSnapshotCacheSupport.all_source_project_remote_snapshot_cache_snapshot,
                  ),
                  xt_source_smoke_evidence_ref:
                    doctorProjectRemoteSnapshotCacheSupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref:
                    doctorProjectRemoteSnapshotCacheSupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            heartbeat_governance_support: doctorHeartbeatGovernanceSupport
              ? {
                  xt_source_smoke_status: doctorHeartbeatGovernanceSupport.xt_source_smoke_status,
                  all_source_smoke_status: doctorHeartbeatGovernanceSupport.all_source_smoke_status,
                  xt_source_heartbeat_governance_snapshot: compactHeartbeatGovernanceSnapshot(
                    doctorHeartbeatGovernanceSupport.xt_source_heartbeat_governance_snapshot,
                  ),
                  all_source_heartbeat_governance_snapshot: compactHeartbeatGovernanceSnapshot(
                    doctorHeartbeatGovernanceSupport.all_source_heartbeat_governance_snapshot,
                  ),
                  xt_source_smoke_evidence_ref:
                    doctorHeartbeatGovernanceSupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref:
                    doctorHeartbeatGovernanceSupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            supervisor_memory_policy_support: doctorSupervisorMemoryPolicySupport
              ? {
                  xt_source_smoke_status: doctorSupervisorMemoryPolicySupport.xt_source_smoke_status,
                  all_source_smoke_status: doctorSupervisorMemoryPolicySupport.all_source_smoke_status,
                  xt_source_supervisor_memory_policy: compactSupervisorMemoryPolicy(
                    doctorSupervisorMemoryPolicySupport.xt_source_supervisor_memory_policy,
                  ),
                  all_source_supervisor_memory_policy: compactSupervisorMemoryPolicy(
                    doctorSupervisorMemoryPolicySupport.all_source_supervisor_memory_policy,
                  ),
                  xt_source_smoke_evidence_ref:
                    doctorSupervisorMemoryPolicySupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref:
                    doctorSupervisorMemoryPolicySupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            supervisor_memory_assembly_resolution_support: doctorSupervisorMemoryAssemblyResolutionSupport
              ? {
                  xt_source_smoke_status:
                    doctorSupervisorMemoryAssemblyResolutionSupport.xt_source_smoke_status,
                  all_source_smoke_status:
                    doctorSupervisorMemoryAssemblyResolutionSupport.all_source_smoke_status,
                  xt_source_supervisor_memory_assembly_resolution: compactMemoryAssemblyResolution(
                    doctorSupervisorMemoryAssemblyResolutionSupport.xt_source_supervisor_memory_assembly_resolution,
                  ),
                  all_source_supervisor_memory_assembly_resolution: compactMemoryAssemblyResolution(
                    doctorSupervisorMemoryAssemblyResolutionSupport.all_source_supervisor_memory_assembly_resolution,
                  ),
                  xt_source_smoke_evidence_ref:
                    doctorSupervisorMemoryAssemblyResolutionSupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref:
                    doctorSupervisorMemoryAssemblyResolutionSupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            supervisor_remote_snapshot_cache_support: doctorSupervisorRemoteSnapshotCacheSupport
              ? {
                  xt_source_smoke_status:
                    doctorSupervisorRemoteSnapshotCacheSupport.xt_source_smoke_status,
                  all_source_smoke_status:
                    doctorSupervisorRemoteSnapshotCacheSupport.all_source_smoke_status,
                  xt_source_supervisor_remote_snapshot_cache_snapshot: compactRemoteSnapshotCacheSnapshot(
                    doctorSupervisorRemoteSnapshotCacheSupport.xt_source_supervisor_remote_snapshot_cache_snapshot,
                  ),
                  all_source_supervisor_remote_snapshot_cache_snapshot: compactRemoteSnapshotCacheSnapshot(
                    doctorSupervisorRemoteSnapshotCacheSupport.all_source_supervisor_remote_snapshot_cache_snapshot,
                  ),
                  xt_source_smoke_evidence_ref:
                    doctorSupervisorRemoteSnapshotCacheSupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref:
                    doctorSupervisorRemoteSnapshotCacheSupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            durable_candidate_mirror_support: doctorDurableCandidateMirrorSupport
              ? {
                  xt_source_smoke_status: doctorDurableCandidateMirrorSupport.xt_source_smoke_status,
                  all_source_smoke_status: doctorDurableCandidateMirrorSupport.all_source_smoke_status,
                  xt_source_durable_candidate_mirror_snapshot: compactDurableCandidateMirrorSnapshot(
                    doctorDurableCandidateMirrorSupport.xt_source_durable_candidate_mirror_snapshot,
                  ),
                  all_source_durable_candidate_mirror_snapshot: compactDurableCandidateMirrorSnapshot(
                    doctorDurableCandidateMirrorSupport.all_source_durable_candidate_mirror_snapshot,
                  ),
                  xt_source_smoke_evidence_ref: doctorDurableCandidateMirrorSupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref: doctorDurableCandidateMirrorSupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            local_store_write_support: doctorLocalStoreWriteSupport
              ? {
                  xt_source_smoke_status: doctorLocalStoreWriteSupport.xt_source_smoke_status,
                  all_source_smoke_status: doctorLocalStoreWriteSupport.all_source_smoke_status,
                  xt_source_local_store_write_snapshot: compactLocalStoreWriteSnapshot(
                    doctorLocalStoreWriteSupport.xt_source_local_store_write_snapshot,
                  ),
                  all_source_local_store_write_snapshot: compactLocalStoreWriteSnapshot(
                    doctorLocalStoreWriteSupport.all_source_local_store_write_snapshot,
                  ),
                  xt_source_smoke_evidence_ref: doctorLocalStoreWriteSupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref: doctorLocalStoreWriteSupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            xt_pairing_readiness_support: compactXtPairingReadinessSupport(
              doctorXtPairingReadinessSupport,
            ),
            memory_route_truth_support: doctorMemoryRouteSupport
              ? {
                  xt_source_smoke_status: doctorMemoryRouteSupport.xt_source_smoke_status,
                  all_source_smoke_status: doctorMemoryRouteSupport.all_source_smoke_status,
                  xt_source_memory_route_truth_snapshot: compactMemoryRouteTruthSnapshot(
                    doctorMemoryRouteSupport.xt_source_memory_route_truth_snapshot,
                  ),
                  all_source_memory_route_truth_snapshot: compactMemoryRouteTruthSnapshot(
                    doctorMemoryRouteSupport.all_source_memory_route_truth_snapshot,
                  ),
                  xt_source_smoke_evidence_ref: doctorMemoryRouteSupport.xt_source_smoke_evidence_ref || '',
                  all_source_smoke_evidence_ref: doctorMemoryRouteSupport.all_source_smoke_evidence_ref || '',
                }
              : null,
            hub_pairing_roundtrip_support: compactHubPairingRoundtripSupport(
              doctorHubPairingRoundtripSupport,
            ),
            xt_memory_truth_closure_support: doctorMemoryTruthClosureSupport
              ? {
                  xt_memory_truth_closure_smoke_status:
                    doctorMemoryTruthClosureSupport.xt_memory_truth_closure_smoke_status,
                  xt_memory_truth_closure_snapshot: compactMemoryTruthClosureSnapshot(
                    doctorMemoryTruthClosureSupport.xt_memory_truth_closure_snapshot,
                  ),
                  xt_memory_truth_closure_smoke_evidence_ref:
                    doctorMemoryTruthClosureSupport.xt_memory_truth_closure_smoke_evidence_ref || '',
                }
              : null,
            build_snapshot_inventory_support: compactBuildSnapshotInventorySupport(
              doctorBuildSnapshotInventorySupport,
            ),
            status:
              doctorSourceGate.overall_status === 'pass'
                ? 'pass(source_run_wrapper_xt_and_aggregate_smoke_green)'
                : 'warn(source_run_wrapper_xt_or_aggregate_smoke_failed)',
          }
        : {
            evidence_ref: doctorSourceGateRef,
            status: 'not_present(optional_supporting_evidence)',
          },
      xhub_local_service_operator_recovery: operatorRecoveryReport
        ? {
            evidence_ref: operatorRecoveryRef,
            present: true,
            ...compactOperatorRecoverySupport(operatorRecoveryReport),
            status: String(operatorRecoveryReport.gate_verdict || '').startsWith('PASS(')
              ? 'pass(structured_local_service_recovery_truth_available_for_release_decision)'
              : 'warn(structured_local_service_recovery_truth_fail_closed)',
          }
        : {
            evidence_ref: operatorRecoveryRef,
            present: false,
            status: 'not_present(optional_supporting_evidence)',
          },
      xhub_operator_channel_recovery: operatorChannelRecoveryReport
        ? {
            evidence_ref: operatorChannelRecoveryRef,
            present: true,
            ...compactOperatorChannelRecoverySupport(operatorChannelRecoveryReport),
            status: String(operatorChannelRecoveryReport.gate_verdict || '').startsWith('PASS(')
              ? 'pass(structured_operator_channel_recovery_truth_available_for_supporting_release_context)'
              : 'warn(structured_operator_channel_recovery_truth_fail_closed)',
          }
        : {
            evidence_ref: operatorChannelRecoveryRef,
            present: false,
            status: 'not_present(optional_supporting_evidence)',
          },
      internal_pass_lines: internalPassAlignment,
      rollback: {
        rollback_ready: rollback.rollback_ready === true,
        rollback_scope: rollback.rollback_scope,
        rollback_mode: rollback.rollback_mode,
      },
    },
    oss_boundary: {
      governance_files: governanceChecks,
      doc_checks: docChecks,
      boundary_evidence: boundaryEvidenceChecks,
      sensitive_findings: sensitiveFindings,
      public_path_policy: {
        allowlist_first: true,
        fail_closed_blacklist: true,
        must_exclude_paths: sensitiveFindings.map((item) => item.relPath),
      },
    },
    blockers,
    next_action: blockers.length === 0
      ? [
          'XT-Main consumes this report as the Hub-side R1 boundary packet and keeps release messaging frozen to XT-W3-23->24->25 mainline only',
          'QA-Main reuses this report for OSS/public-path review and does not broaden validation scope',
        ]
      : [
          'keep_release_scope_frozen',
          'fix_only_remaining_boundary_blockers',
        ],
    consumer_min_evidence: consumerEvidence,
    evidence_refs: [
      'build/reports/xt_w3_release_ready_decision.v1.json',
      'build/reports/xt_w3_require_real_provenance.v2.json',
      xtReadyReportRef,
      xtReadySourceRef,
      xtReadyDiagnosticsRef,
      connectorGateRef,
      'build/hub_l5_release_internal_pass_lines_report.json',
      'build/reports/xt_w3_internal_pass_lines_release_ready.v1.json',
      'build/reports/xt_w3_25_competitive_rollback.v1.json',
      ...(doctorSourceGate ? [doctorSourceGateRef] : []),
      ...(operatorRecoveryReport ? [operatorRecoveryRef] : []),
      ...(operatorChannelRecoveryReport ? [operatorChannelRecoveryRef] : []),
      ...(doctorXtSmokeEvidenceRef ? [doctorXtSmokeEvidenceRef] : []),
      ...(doctorAllSmokeEvidenceRef ? [doctorAllSmokeEvidenceRef] : []),
      ...(doctorHubPairingLaunchOnlyEvidenceRef ? [doctorHubPairingLaunchOnlyEvidenceRef] : []),
      ...(doctorHubPairingVerifyOnlyEvidenceRef ? [doctorHubPairingVerifyOnlyEvidenceRef] : []),
      ...(doctorXtMemoryTruthClosureEvidenceRef ? [doctorXtMemoryTruthClosureEvidenceRef] : []),
      'docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md',
      'docs/open-source/OSS_RELEASE_CHECKLIST_v1.md',
      'docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md',
    ],
  };

  const delta = {
    schema_version: 'xhub.hub_l5_r1_release_oss_boundary_delta_3line.v1',
    generated_at: readiness.generated_at,
    timezone: TIMEZONE,
    lane: 'Hub-L5',
    mode: 'delta_3line_only',
    status: readiness.status,
    scope_boundary: readiness.scope_boundary,
    blockers: readiness.blockers,
    support_context: {
      local_service_recovery_status:
        readiness.release_alignment.xhub_local_service_operator_recovery.status,
      operator_channel_recovery_status:
        readiness.release_alignment.xhub_operator_channel_recovery.status,
      operator_channel_release_stance:
        readiness.release_alignment.xhub_operator_channel_recovery.release_stance || 'missing',
      operator_channel_action_category:
        readiness.release_alignment.xhub_operator_channel_recovery.recovery_classification?.action_category || 'missing',
      operator_channel_heartbeat_governance_visibility_gap:
        readiness.release_alignment.xhub_operator_channel_recovery.heartbeat_governance_visibility_gap === true,
      operator_channel_focus_highlight:
        readiness.release_alignment.xhub_operator_channel_recovery.channel_focus_highlight || 'none',
      operator_channel_external_status_line:
        readiness.release_alignment.xhub_operator_channel_recovery.release_wording?.external_status_line
          || 'Structured operator-channel onboarding recovery wording is not available.',
    },
    next_action: readiness.next_action,
    evidence_refs: [
      'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      'build/reports/xt_w3_release_ready_decision.v1.json',
      'build/reports/xt_w3_require_real_provenance.v2.json',
    ],
  };

  writeXtReadyReleaseDiagnostics(ROOT, xtReadyDiagnostics);
  writeJson('build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json', readiness);
  writeJson('build/reports/hub_l5_r1_release_oss_boundary_delta_3line.v1.json', delta);
  console.log('ok - wrote build/reports/xt_ready_release_diagnostics.v1.json');
  console.log('ok - wrote build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json');
  console.log('ok - wrote build/reports/hub_l5_r1_release_oss_boundary_delta_3line.v1.json');
}

main();
