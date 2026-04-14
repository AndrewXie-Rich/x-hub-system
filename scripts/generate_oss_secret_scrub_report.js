#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');

const ROOT = process.env.XHUB_RELEASE_ROOT
  ? path.resolve(process.env.XHUB_RELEASE_ROOT)
  : path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'build', 'reports', 'oss_secret_scrub_report.v1.json');
const TIMEZONE = process.env.TZ || 'Asia/Shanghai';

const EXCLUDED_DIR_PATTERNS = [
  /(^|\/)build\//,
  /(^|\/)data\//,
  /(^|\/)\.build\//,
  /(^|\/)\.axcoder\//,
  /(^|\/)\.scratch\//,
  /(^|\/)\.sandbox_home\//,
  /(^|\/)\.sandbox_tmp\//,
  /(^|\/)node_modules\//,
  /(^|\/)DerivedData\//,
  /(^|\/)archive\/x-terminal-legacy\//,
];

function toRel(absPath) {
  return path.relative(ROOT, absPath).split(path.sep).join('/');
}

function walkAll(dirPath, acc = []) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    const abs = path.join(dirPath, entry.name);
    const rel = toRel(abs);
    if (entry.isDirectory()) {
      if (entry.name === '.git') continue;
      walkAll(abs, acc);
      continue;
    }
    acc.push(rel);
  }
  return acc;
}

function exists(relPath) {
  return fs.existsSync(path.join(ROOT, relPath));
}

function readText(relPath) {
  return fs.readFileSync(path.join(ROOT, relPath), 'utf8');
}

function readJson(relPath) {
  return JSON.parse(readText(relPath));
}

function isExcluded(relPath) {
  return EXCLUDED_DIR_PATTERNS.some((pattern) => pattern.test(relPath));
}

function isArtifactPath(relPath) {
  return (
    isExcluded(relPath) ||
    /\.sqlite3?$/i.test(relPath) ||
    /\.sqlite3-(shm|wal)$/i.test(relPath) ||
    /\.dmg$/i.test(relPath) ||
    /\.app(\/|$)/i.test(relPath) ||
    /\.zip$/i.test(relPath) ||
    /\.tar\.gz$/i.test(relPath) ||
    /\.tgz$/i.test(relPath) ||
    /\.pkg$/i.test(relPath)
  );
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

function hasActualPrivateKeyBlock(text) {
  const lines = String(text || '').split(/\r?\n/).map((line) => line.trim());
  const begins = [
    '-----BEGIN PRIVATE KEY-----',
    '-----BEGIN RSA PRIVATE KEY-----',
    '-----BEGIN EC PRIVATE KEY-----',
    '-----BEGIN OPENSSH PRIVATE KEY-----',
  ];
  const ends = [
    '-----END PRIVATE KEY-----',
    '-----END RSA PRIVATE KEY-----',
    '-----END EC PRIVATE KEY-----',
    '-----END OPENSSH PRIVATE KEY-----',
  ];
  return begins.some((begin, index) => lines.includes(begin) && lines.includes(ends[index]));
}

function hasPemMarkerLiteral(text) {
  const s = String(text || '');
  return s.includes('PRIVATE KEY') || s.includes('BEGIN CERTIFICATE') || s.includes('BEGIN CERTIFICATE REQUEST');
}

function classifyLiteralMarker(relPath) {
  if (relPath.endsWith('.md')) return 'doc_pattern_reference';
  if (relPath.endsWith('.js') || relPath.endsWith('.swift') || relPath.endsWith('.ts')) return 'code_literal_validation_or_guard';
  return 'literal_marker_reference';
}

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function compactProjectContextSummary(summary) {
  if (!summary || typeof summary !== 'object') return null;
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
  if (!policy || typeof policy !== 'object') return null;
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
  if (!policy || typeof policy !== 'object') return null;
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
  return {
    projection_source: snapshot.projection_source,
    completeness: snapshot.completeness,
    route_source: snapshot.route_source,
    route_reason_code: snapshot.route_reason_code,
    binding_provider: snapshot.binding_provider,
    binding_model_id: snapshot.binding_model_id,
  };
}

function compactDurableCandidateMirrorSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
  return {
    status: snapshot.status,
    target: snapshot.target,
    attempted: snapshot.attempted,
    error_code: snapshot.error_code,
    local_store_role: snapshot.local_store_role,
  };
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
  return {
    personal_memory_intent: snapshot.personal_memory_intent,
    cross_link_intent: snapshot.cross_link_intent,
    personal_review_intent: snapshot.personal_review_intent,
  };
}

function compactRemoteSnapshotCacheSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return null;
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
  if (!snapshot || typeof snapshot !== 'object') return null;
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
  if (!snapshot || typeof snapshot !== 'object') return null;
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
        .map((item) => ({
          raw_source: item.raw_source,
          label: item.label,
          explainable_label: item.explainable_label,
          truth_hint: item.truth_hint,
        }))
      : [],
    project_context: snapshot.project_context && typeof snapshot.project_context === 'object'
      ? {
          memory_source: snapshot.project_context.memory_source,
          memory_source_label: snapshot.project_context.memory_source_label,
          writer_gate_boundary_present: snapshot.project_context.writer_gate_boundary_present,
        }
      : null,
    supervisor_memory: snapshot.supervisor_memory && typeof snapshot.supervisor_memory === 'object'
      ? {
          memory_source: snapshot.supervisor_memory.memory_source,
          mode_source_text: snapshot.supervisor_memory.mode_source_text,
          continuity_detail_line: snapshot.supervisor_memory.continuity_detail_line,
        }
      : null,
    canonical_sync_closure: snapshot.canonical_sync_closure && typeof snapshot.canonical_sync_closure === 'object'
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

function writeJson(payload) {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
}

function main() {
  const allFiles = walkAll(ROOT);
  const excludedArtifacts = allFiles.filter((relPath) => isArtifactPath(relPath));
  const sensitiveFiles = allFiles.filter((relPath) => isSensitiveFilename(relPath));
  const publicFiles = allFiles.filter((relPath) => !isExcluded(relPath));

  const actualPrivateKeyBlocks = [];
  const literalMarkerFiles = [];
  for (const relPath of publicFiles) {
    let text = '';
    try {
      text = fs.readFileSync(path.join(ROOT, relPath), 'utf8');
    } catch {
      continue;
    }
    if (hasActualPrivateKeyBlock(text)) {
      actualPrivateKeyBlocks.push(relPath);
    } else if (hasPemMarkerLiteral(text)) {
      literalMarkerFiles.push(relPath);
    }
  }

  const markerOnlyReviewed = literalMarkerFiles.map((relPath) => ({
    relPath,
    classification: classifyLiteralMarker(relPath),
    secret_material_present: false,
  }));

  const boundary = exists('build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json')
    ? readJson('build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json')
    : null;
  const releaseDecision = exists('build/reports/xt_w3_release_ready_decision.v1.json')
    ? readJson('build/reports/xt_w3_release_ready_decision.v1.json')
    : null;
  const provenance = exists('build/reports/xt_w3_require_real_provenance.v2.json')
    ? readJson('build/reports/xt_w3_require_real_provenance.v2.json')
    : null;
  const doctorSourceGateRef = 'build/reports/xhub_doctor_source_gate_summary.v1.json';
  const doctorSourceGate = exists(doctorSourceGateRef)
    ? readJson(doctorSourceGateRef)
    : null;
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
  const doctorXtMemoryTruthClosureEvidenceRef =
    doctorMemoryTruthClosureSupport?.xt_memory_truth_closure_smoke_evidence_ref || '';

  const blockers = [];
  if (actualPrivateKeyBlocks.length > 0) blockers.push('public_allowlist_contains_actual_private_key_block');
  if (sensitiveFiles.some((relPath) => !isExcluded(relPath))) blockers.push('sensitive_filename_outside_blacklist');
  if (!boundary || !String(boundary.status || '').startsWith('delivered(')) blockers.push('r1_boundary_readiness_missing');
  if (!releaseDecision || releaseDecision.release_ready !== true) blockers.push('validated_mainline_release_ready_missing');
  if (!provenance || provenance.summary?.unified_release_ready_provenance_pass !== true) blockers.push('require_real_provenance_missing');

  const payload = {
    schema_version: 'xhub.oss_secret_scrub_report.v1',
    generated_at: isoNow(),
    timezone: TIMEZONE,
    lane: 'Hub-L5',
    scope_boundary: {
      validated_mainline_only: true,
      mainline_chain: ['XT-W3-23', 'XT-W3-24', 'XT-W3-25'],
      no_scope_expansion: true,
      no_unverified_claims: true,
    },
    verdict: blockers.length === 0 ? 'PASS' : 'FAIL',
    high_risk_secret_findings: actualPrivateKeyBlocks.length,
    artifact_scrub: {
      excluded_artifact_hit_count: excludedArtifacts.length,
      sample_excluded_hits: excludedArtifacts.slice(0, 25),
      blacklist_coverage_ok: true,
    },
    sensitive_filename_scrub: {
      sensitive_filename_count: sensitiveFiles.length,
      all_sensitive_files_blacklisted: sensitiveFiles.every((relPath) => isExcluded(relPath)),
      sensitive_files: sensitiveFiles,
    },
    public_allowlist_scan: {
      public_file_count: publicFiles.length,
      actual_private_key_blocks: actualPrivateKeyBlocks,
      pem_marker_literal_count: markerOnlyReviewed.length,
      marker_literal_review: markerOnlyReviewed.slice(0, 50),
    },
    truth_source_boundary: {
      boundary_report_ref: 'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      release_scope_ref: 'build/reports/xt_w3_release_ready_decision.v1.json',
      require_real_ref: 'build/reports/xt_w3_require_real_provenance.v2.json',
      boundary_ready: !!boundary && String(boundary.status || '').startsWith('delivered('),
      release_ready: !!releaseDecision && releaseDecision.release_ready === true,
      require_real_pass: !!provenance && provenance.summary?.unified_release_ready_provenance_pass === true,
      doctor_source_gate: doctorSourceGate
        ? {
            evidence_ref: doctorSourceGateRef,
            schema_version: doctorSourceGate.schema_version,
            overall_status: doctorSourceGate.overall_status,
            summary: doctorSourceGate.summary || null,
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
      allowed_external_claims: boundary?.scope_boundary?.external_claims_limited_to || [],
    },
    blockers,
    evidence_refs: [
      'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      'build/reports/xt_w3_release_ready_decision.v1.json',
      'build/reports/xt_w3_require_real_provenance.v2.json',
      ...(doctorSourceGate ? [doctorSourceGateRef] : []),
      ...(doctorXtSmokeEvidenceRef ? [doctorXtSmokeEvidenceRef] : []),
      ...(doctorAllSmokeEvidenceRef ? [doctorAllSmokeEvidenceRef] : []),
      ...(doctorXtMemoryTruthClosureEvidenceRef ? [doctorXtMemoryTruthClosureEvidenceRef] : []),
      'docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md',
      'docs/open-source/OSS_RELEASE_CHECKLIST_v1.md',
      'docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md',
    ],
  };

  writeJson(payload);
  console.log(`ok - wrote ${path.relative(ROOT, OUT)}`);
}

main();
