function safeString(value) {
  return String(value ?? '').trim();
}

function safeStringArray(values) {
  if (!Array.isArray(values)) return [];
  const out = [];
  const seen = new Set();
  for (const raw of values) {
    const cleaned = safeString(raw);
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

function safeJsonParse(value, fallback = null) {
  try {
    return JSON.parse(String(value ?? ''));
  } catch {
    return fallback;
  }
}

function nonNegativeInt(value, fallback = 0) {
  if (value == null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

export const XT_PROJECT_HEARTBEAT_CANONICAL_PREFIX = 'xterminal.project.heartbeat.';
export const XT_PROJECT_HEARTBEAT_SUMMARY_JSON_KEY = `${XT_PROJECT_HEARTBEAT_CANONICAL_PREFIX}summary_json`;

function normalizeHeartbeatCadenceDimension(raw, fallbackDimension = '') {
  const dimension = safeString(raw?.dimension) || safeString(fallbackDimension);
  return {
    dimension,
    configured_seconds: raw?.configuredSeconds == null ? null : nonNegativeInt(raw.configuredSeconds),
    recommended_seconds: raw?.recommendedSeconds == null ? null : nonNegativeInt(raw.recommendedSeconds),
    effective_seconds: raw?.effectiveSeconds == null ? null : nonNegativeInt(raw.effectiveSeconds),
    effective_reason_codes: safeStringArray(raw?.effectiveReasonCodes),
    next_due_at_ms: raw?.nextDueAtMs == null ? null : Math.max(0, Number(raw.nextDueAtMs || 0)),
    next_due_reason_codes: safeStringArray(raw?.nextDueReasonCodes),
    due: raw?.isDue == null ? null : !!raw.isDue,
  };
}

function normalizeHeartbeatNextReviewDue(rawSummary, cadence = {}) {
  const kind = safeString(rawSummary?.next_review_kind);
  const due = rawSummary?.next_review_due == null ? null : !!rawSummary.next_review_due;
  const atMs = rawSummary?.next_review_due_at_ms == null ? null : Math.max(0, Number(rawSummary.next_review_due_at_ms || 0));
  let reasonCodes = [];
  const pulse = cadence.review_pulse && typeof cadence.review_pulse === 'object' ? cadence.review_pulse : null;
  const brainstorm = cadence.brainstorm_review && typeof cadence.brainstorm_review === 'object' ? cadence.brainstorm_review : null;
  if (kind && pulse?.dimension === kind) {
    reasonCodes = safeStringArray(pulse.next_due_reason_codes);
  } else if (kind && brainstorm?.dimension === kind) {
    reasonCodes = safeStringArray(brainstorm.next_due_reason_codes);
  }
  return {
    kind: kind || null,
    due,
    at_ms: atMs,
    reason_codes: reasonCodes,
  };
}

function normalizeHeartbeatRecoveryDecision(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const action = safeString(raw.action);
  const urgency = safeString(raw.urgency);
  const reasonCode = safeString(raw.reasonCode);
  const summary = safeString(raw.summary);
  const sourceSignals = safeStringArray(raw.sourceSignals);
  const anomalyTypes = safeStringArray(raw.anomalyTypes);
  const blockedLaneReasons = safeStringArray(raw.blockedLaneReasons);
  const blockedLaneCount = raw.blockedLaneCount == null ? null : nonNegativeInt(raw.blockedLaneCount);
  const stalledLaneCount = raw.stalledLaneCount == null ? null : nonNegativeInt(raw.stalledLaneCount);
  const failedLaneCount = raw.failedLaneCount == null ? null : nonNegativeInt(raw.failedLaneCount);
  const recoveringLaneCount = raw.recoveringLaneCount == null ? null : nonNegativeInt(raw.recoveringLaneCount);
  const requiresUserAction = raw.requiresUserAction == null ? null : !!raw.requiresUserAction;
  const queuedReviewTrigger = safeString(raw.queuedReviewTrigger);
  const queuedReviewLevel = safeString(raw.queuedReviewLevel);
  const queuedReviewRunKind = safeString(raw.queuedReviewRunKind);

  if (
    !action
    && !urgency
    && !reasonCode
    && !summary
    && sourceSignals.length === 0
    && anomalyTypes.length === 0
    && blockedLaneReasons.length === 0
    && blockedLaneCount == null
    && stalledLaneCount == null
    && failedLaneCount == null
    && recoveringLaneCount == null
    && requiresUserAction == null
    && !queuedReviewTrigger
    && !queuedReviewLevel
    && !queuedReviewRunKind
  ) {
    return null;
  }

  return {
    action: action || null,
    urgency: urgency || null,
    reason_code: reasonCode || null,
    summary,
    source_signals: sourceSignals,
    anomaly_types: anomalyTypes,
    blocked_lane_reasons: blockedLaneReasons,
    blocked_lane_count: blockedLaneCount,
    stalled_lane_count: stalledLaneCount,
    failed_lane_count: failedLaneCount,
    recovering_lane_count: recoveringLaneCount,
    requires_user_action: requiresUserAction,
    queued_review_trigger: queuedReviewTrigger || null,
    queued_review_level: queuedReviewLevel || null,
    queued_review_run_kind: queuedReviewRunKind || null,
  };
}

function heartbeatCadenceProjectionFromSummary(rawSummary) {
  const cadence = rawSummary?.cadence && typeof rawSummary.cadence === 'object'
    ? rawSummary.cadence
    : {};
  const progressHeartbeat = normalizeHeartbeatCadenceDimension(
    cadence.progressHeartbeat,
    'progress_heartbeat',
  );
  const reviewPulse = normalizeHeartbeatCadenceDimension(
    cadence.reviewPulse,
    'review_pulse',
  );
  const brainstormReview = normalizeHeartbeatCadenceDimension(
    cadence.brainstormReview,
    'brainstorm_review',
  );
  return {
    progress_heartbeat: progressHeartbeat,
    review_pulse: reviewPulse,
    brainstorm_review: brainstormReview,
    next_review_due: normalizeHeartbeatNextReviewDue(
      rawSummary,
      {
        review_pulse: reviewPulse,
        brainstorm_review: brainstormReview,
      },
    ),
  };
}

function buildHeartbeatGovernanceSnapshotFromSummary(rawSummary) {
  if (!rawSummary || typeof rawSummary !== 'object') return null;
  const projectId = safeString(rawSummary.project_id);
  if (!projectId) return null;

  const cadenceProjection = heartbeatCadenceProjectionFromSummary(rawSummary);
  const digest = rawSummary.digestExplainability && typeof rawSummary.digestExplainability === 'object'
    ? rawSummary.digestExplainability
    : {};

  return {
    project_id: projectId,
    project_name: safeString(rawSummary.project_name),
    status_digest: safeString(rawSummary.status_digest),
    current_state_summary: safeString(rawSummary.current_state_summary),
    next_step_summary: safeString(rawSummary.next_step_summary),
    blocker_summary: safeString(rawSummary.blocker_summary),
    last_heartbeat_at_ms: Math.max(0, Number(rawSummary.last_heartbeat_at_ms || 0)),
    latest_quality_band: safeString(rawSummary.latest_quality_band) || null,
    latest_quality_score: rawSummary.latest_quality_score == null ? null : nonNegativeInt(rawSummary.latest_quality_score),
    weak_reasons: safeStringArray(rawSummary.weak_reasons),
    open_anomaly_types: safeStringArray(rawSummary.open_anomaly_types),
    project_phase: safeString(rawSummary.project_phase) || null,
    execution_status: safeString(rawSummary.execution_status) || null,
    risk_tier: safeString(rawSummary.risk_tier) || null,
    digest_visibility: safeString(digest.visibility) || 'suppressed',
    digest_reason_codes: safeStringArray(digest.reasonCodes),
    digest_what_changed_text: safeString(digest.whatChangedText),
    digest_why_important_text: safeString(digest.whyImportantText),
    digest_system_next_step_text: safeString(digest.systemNextStepText),
    progress_heartbeat: cadenceProjection.progress_heartbeat,
    review_pulse: cadenceProjection.review_pulse,
    brainstorm_review: cadenceProjection.brainstorm_review,
    next_review_due: cadenceProjection.next_review_due,
    recovery_decision: normalizeHeartbeatRecoveryDecision(rawSummary.recoveryDecision),
  };
}

export function buildProjectHeartbeatGovernanceSnapshot({
  db,
  device_id,
  user_id,
  app_id,
  project_id,
} = {}) {
  const projectId = safeString(project_id);
  const deviceId = safeString(device_id);
  const userId = safeString(user_id);
  const appId = safeString(app_id);
  if (!db || typeof db.listCanonicalItems !== 'function' || !projectId || !deviceId || !appId) {
    return null;
  }

  const rows = db.listCanonicalItems({
    scope: 'project',
    device_id: deviceId,
    user_id: userId,
    app_id: appId,
    project_id: projectId,
    limit: 128,
  });
  const summaryItem = Array.isArray(rows)
    ? rows.find((row) => safeString(row?.key) === XT_PROJECT_HEARTBEAT_SUMMARY_JSON_KEY)
    : null;
  if (!summaryItem) return null;

  const rawSummary = safeJsonParse(summaryItem.value, null);
  return buildHeartbeatGovernanceSnapshotFromSummary(rawSummary);
}
