export const OPERATOR_CHANNEL_LIVE_TEST_EVIDENCE_SCHEMA = 'xt_w3_24_operator_channel_live_test_evidence.v1';

import {
  buildOperatorChannelDeliveryRepairHints,
  buildOperatorChannelRuntimeRepairHints,
} from './channel_operator_repair_hints.js';

const SUPPORTED_PROVIDER_IDS = Object.freeze([
  'slack',
  'telegram',
  'feishu',
  'whatsapp_cloud_api',
]);

function safeString(input) {
  return String(input ?? '').trim();
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

function safeInt(input, fallback = 0) {
  const value = Number(input);
  return Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : fallback;
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : null;
}

function normalizeProviderId(input) {
  const normalized = safeString(input).toLowerCase();
  return SUPPORTED_PROVIDER_IDS.includes(normalized) ? normalized : '';
}

function normalizeVerdict(input) {
  const normalized = safeString(input).toLowerCase();
  switch (normalized) {
  case 'pass':
  case 'passed':
  case 'success':
    return 'passed';
  case 'fail':
  case 'failed':
  case 'error':
    return 'failed';
  case 'partial':
  case 'warning':
    return 'partial';
  default:
    return 'pending';
  }
}

function isoTimestamp(input) {
  const text = safeString(input);
  if (!text) return new Date().toISOString();
  const ts = Date.parse(text);
  return Number.isFinite(ts) ? new Date(ts).toISOString() : new Date().toISOString();
}

function normalizeEvidenceRefs(values) {
  const seen = new Set();
  return safeArray(values)
    .map((value) => safeString(value))
    .filter((value) => {
      if (!value || seen.has(value)) return false;
      seen.add(value);
      return true;
    });
}

function normalizeStringList(values) {
  const seen = new Set();
  return safeArray(values)
    .map((value) => safeString(value))
    .filter((value) => {
      if (!value || seen.has(value)) return false;
      seen.add(value);
      return true;
    });
}

function collectRepairHints(...sources) {
  const values = [];
  for (const source of sources) {
    if (Array.isArray(source)) {
      values.push(...source);
      continue;
    }
    values.push(source);
  }
  return normalizeStringList(values);
}

function preferredRemediation(fallback, ...sources) {
  return collectRepairHints(...sources)[0] || safeString(fallback);
}

function pickProviderRow(rows, provider) {
  return safeArray(rows).find((row) => normalizeProviderId(row?.provider) === provider) || null;
}

function summarizeReadiness(readiness) {
  if (!readiness || typeof readiness !== 'object') return null;
  const provider = normalizeProviderId(readiness.provider);
  const replyEnabled = !!readiness.reply_enabled;
  const credentialsConfigured = !!readiness.credentials_configured;
  const denyCode = safeString(readiness.deny_code);
  const remediationHint = safeString(readiness.remediation_hint);
  const repairHints = normalizeStringList(readiness.repair_hints);
  return {
    provider,
    ready: !!readiness.ready,
    reply_enabled: replyEnabled,
    credentials_configured: credentialsConfigured,
    deny_code: denyCode,
    remediation_hint: remediationHint,
    repair_hints: repairHints.length > 0
      ? repairHints
      : buildOperatorChannelDeliveryRepairHints({
        provider,
        reply_enabled: replyEnabled,
        credentials_configured: credentialsConfigured,
        deny_code: denyCode,
        remediation_hint: remediationHint,
      }),
  };
}

function summarizeRuntime(runtimeStatus) {
  if (!runtimeStatus || typeof runtimeStatus !== 'object') return null;
  const provider = normalizeProviderId(runtimeStatus.provider);
  const deliveryReady = !!runtimeStatus.delivery_ready;
  const commandEntryReady = !!runtimeStatus.command_entry_ready;
  const runtimeState = safeString(runtimeStatus.runtime_state);
  const releaseBlocked = !!runtimeStatus.release_blocked;
  const lastErrorCode = safeString(runtimeStatus.last_error_code);
  const repairHints = normalizeStringList(runtimeStatus.repair_hints);
  return {
    provider,
    label: safeString(runtimeStatus.label),
    release_stage: safeString(runtimeStatus.release_stage),
    release_blocked: releaseBlocked,
    require_real_evidence: !!runtimeStatus.require_real_evidence,
    endpoint_visibility: safeString(runtimeStatus.endpoint_visibility),
    operator_surface: safeString(runtimeStatus.operator_surface),
    runtime_state: runtimeState,
    delivery_ready: deliveryReady,
    command_entry_ready: commandEntryReady,
    last_error_code: lastErrorCode,
    updated_at_ms: safeInt(runtimeStatus.updated_at_ms),
    repair_hints: repairHints.length > 0
      ? repairHints
      : buildOperatorChannelRuntimeRepairHints({
        provider,
        runtime_state: runtimeState,
        delivery_ready: deliveryReady,
        command_entry_ready: commandEntryReady,
        last_error_code: lastErrorCode,
        release_blocked: releaseBlocked,
      }),
  };
}

function summarizeTicket(ticket) {
  if (!ticket || typeof ticket !== 'object') return null;
  return {
    ticket_id: safeString(ticket.ticket_id),
    provider: normalizeProviderId(ticket.provider),
    conversation_id: safeString(ticket.conversation_id),
    thread_key: safeString(ticket.thread_key),
    ingress_surface: safeString(ticket.ingress_surface),
    status: safeString(ticket.status),
    first_message_preview: safeString(ticket.first_message_preview),
    updated_at_ms: safeInt(ticket.updated_at_ms),
  };
}

function summarizeDecision(decision) {
  if (!decision || typeof decision !== 'object') return null;
  return {
    decision_id: safeString(decision.decision_id),
    decision: safeString(decision.decision),
    approved_by_hub_user_id: safeString(decision.approved_by_hub_user_id),
    hub_user_id: safeString(decision.hub_user_id),
    scope_type: safeString(decision.scope_type),
    scope_id: safeString(decision.scope_id),
    binding_mode: safeString(decision.binding_mode),
    grant_profile: safeString(decision.grant_profile),
    created_at_ms: safeInt(decision.created_at_ms),
  };
}

function parseHeartbeatGovernanceSnapshot(input) {
  if (input && typeof input === 'object' && !Array.isArray(input)) return input;
  const raw = safeString(input);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function summarizeHeartbeatGovernanceSnapshot(snapshot) {
  const row = parseHeartbeatGovernanceSnapshot(snapshot);
  if (!row) return null;
  const nextReview = safeObject(row.next_review_due);
  return {
    project_id: safeString(row.project_id),
    project_name: safeString(row.project_name),
    status_digest: safeString(row.status_digest),
    latest_quality_band: safeString(row.latest_quality_band),
    latest_quality_score: safeInt(row.latest_quality_score),
    open_anomaly_types: normalizeStringList(row.open_anomaly_types),
    weak_reasons: normalizeStringList(row.weak_reasons),
    next_review_due: nextReview
      ? {
        kind: safeString(nextReview.kind),
        due: safeBool(nextReview.due),
        at_ms: safeInt(nextReview.at_ms),
        reason_codes: normalizeStringList(nextReview.reason_codes),
      }
      : null,
  };
}

function heartbeatGovernanceVisible(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return false;
  return !!safeString(snapshot.latest_quality_band) || !!safeString(snapshot.next_review_due?.kind);
}

function summarizeAutomationState(state) {
  if (!state || typeof state !== 'object') return null;
  const heartbeatGovernanceSnapshot = summarizeHeartbeatGovernanceSnapshot(
    state?.first_smoke?.heartbeat_governance_snapshot
      || state?.first_smoke?.heartbeat_governance_snapshot_json
  );
  const firstSmoke = state.first_smoke && typeof state.first_smoke === 'object'
    ? {
      receipt_id: safeString(state.first_smoke.receipt_id),
      action_name: safeString(state.first_smoke.action_name),
      status: safeString(state.first_smoke.status),
      route_mode: safeString(state.first_smoke.route_mode),
      deny_code: safeString(state.first_smoke.deny_code),
      detail: safeString(state.first_smoke.detail),
      remediation_hint: safeString(state.first_smoke.remediation_hint),
      updated_at_ms: safeInt(state.first_smoke.updated_at_ms),
      heartbeat_governance_snapshot: heartbeatGovernanceSnapshot,
    }
    : null;
  return {
    first_smoke: firstSmoke,
    outbox_pending_count: safeInt(state.outbox_pending_count),
    outbox_delivered_count: safeInt(state.outbox_delivered_count),
    delivery_readiness: summarizeReadiness(state.delivery_readiness),
    pending_outbox_items: safeArray(state.outbox_items)
      .filter((item) => safeString(item?.status).toLowerCase() === 'pending')
      .slice(0, 8)
      .map((item) => ({
        item_id: safeString(item.item_id),
        item_kind: safeString(item.item_kind),
        status: safeString(item.status),
        last_error_code: safeString(item.last_error_code),
      })),
  };
}

function makeCheck(name, ok, pending, detail, remediation) {
  return {
    name,
    status: pending ? 'pending' : (ok ? 'pass' : 'fail'),
    detail: safeString(detail),
    remediation: safeString(remediation),
  };
}

export function evaluateOperatorChannelLiveTestChecks({
  provider = '',
  readiness = null,
  runtimeStatus = null,
  ticketDetail = null,
} = {}) {
  const normalizedProvider = normalizeProviderId(provider);
  const summaryReadiness = summarizeReadiness(readiness);
  const summaryRuntime = summarizeRuntime(runtimeStatus);
  const summaryTicket = summarizeTicket(ticketDetail?.ticket);
  const summaryDecision = summarizeDecision(ticketDetail?.latest_decision);
  const summaryAutomation = summarizeAutomationState(ticketDetail?.automation_state);
  const firstSmoke = summaryAutomation?.first_smoke || null;
  const runtimeRepairHints = summaryRuntime?.repair_hints || [];
  const readinessRepairHints = collectRepairHints(
    summaryReadiness?.repair_hints,
    summaryAutomation?.delivery_readiness?.repair_hints
  );
  const deliveryRepairHints = collectRepairHints(
    summaryAutomation?.delivery_readiness?.repair_hints,
    summaryReadiness?.repair_hints,
    summaryRuntime?.repair_hints,
    summaryAutomation?.delivery_readiness?.remediation_hint,
    summaryReadiness?.remediation_hint
  );
  const outboxRepairHints = collectRepairHints(
    summaryAutomation?.delivery_readiness?.repair_hints,
    summaryReadiness?.repair_hints,
    summaryRuntime?.repair_hints,
    summaryAutomation?.delivery_readiness?.remediation_hint,
    summaryReadiness?.remediation_hint,
    firstSmoke?.remediation_hint
  );

  return [
    makeCheck(
      'runtime_command_entry_ready',
      !!summaryRuntime?.command_entry_ready,
      !summaryRuntime,
      summaryRuntime
        ? `runtime_state=${summaryRuntime.runtime_state || 'unknown'} command_entry_ready=${summaryRuntime.command_entry_ready ? '1' : '0'}`
        : 'No runtime status row was available for this provider.',
      preferredRemediation(
        normalizedProvider === 'telegram'
          ? 'Confirm the Telegram polling worker is running with HUB_TELEGRAM_OPERATOR_ENABLE=1, HUB_TELEGRAM_OPERATOR_BOT_TOKEN, and HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN.'
          : 'Confirm the local-only connector worker is running and reload operator channel runtime status.',
        runtimeRepairHints
      )
    ),
    makeCheck(
      'delivery_ready',
      !!(summaryReadiness?.ready || summaryRuntime?.delivery_ready),
      !summaryReadiness && !summaryRuntime,
      summaryReadiness
        ? `readiness=${summaryReadiness.ready ? 'ready' : 'blocked'} reply_enabled=${summaryReadiness.reply_enabled ? '1' : '0'} credentials_configured=${summaryReadiness.credentials_configured ? '1' : '0'}`
        : (summaryRuntime ? `delivery_ready=${summaryRuntime.delivery_ready ? '1' : '0'}` : 'No delivery readiness row was available for this provider.'),
      preferredRemediation(
        'Confirm dedicated reply credentials are loaded into the running Hub process, then refresh readiness.',
        deliveryRepairHints
      )
    ),
    makeCheck(
      'release_ready_boundary',
      !!summaryRuntime && !summaryRuntime.release_blocked && !summaryRuntime.require_real_evidence,
      !summaryRuntime,
      summaryRuntime
        ? `release_stage=${summaryRuntime.release_stage || 'unknown'} release_blocked=${summaryRuntime.release_blocked ? '1' : '0'} require_real_evidence=${summaryRuntime.require_real_evidence ? '1' : '0'}`
        : 'No runtime release context is attached to this report yet.',
      preferredRemediation(
        normalizedProvider === 'whatsapp_cloud_api'
          ? 'Keep WhatsApp Cloud API as designed/wired only until require-real evidence clears the release block; do not market it as wave1 safe onboarding yet.'
          : 'Confirm this provider is marked wave1 and not release-blocked before advertising safe onboarding.',
        runtimeRepairHints
      )
    ),
    makeCheck(
      'quarantine_ticket_recorded',
      !!summaryTicket,
      !summaryTicket,
      summaryTicket
        ? `ticket_id=${summaryTicket.ticket_id} status=${summaryTicket.status || 'unknown'} conversation=${summaryTicket.conversation_id || 'unknown'}`
        : 'No onboarding ticket is attached to this report yet.',
      'Send a real status message from the target conversation so Hub can create a quarantine ticket.'
    ),
    makeCheck(
      'approval_recorded',
      safeString(summaryDecision?.decision).toLowerCase() === 'approve',
      !summaryTicket || !summaryDecision,
      summaryDecision
        ? `decision=${summaryDecision.decision || 'unknown'} grant_profile=${summaryDecision.grant_profile || 'unknown'}`
        : 'No approval decision is attached to this report yet.',
      'Approve the quarantine ticket locally in Hub before treating the provider as usable.'
    ),
    makeCheck(
      'first_smoke_executed',
      safeString(firstSmoke?.status).toLowerCase() === 'query_executed',
      !summaryDecision || !summaryAutomation || !firstSmoke,
      firstSmoke
        ? [
          `first_smoke_status=${firstSmoke.status || 'unknown'}`,
          `action=${firstSmoke.action_name || 'unknown'}`,
          `route_mode=${firstSmoke.route_mode || 'unknown'}`,
        ].filter(Boolean).join(' ')
        : 'No first smoke receipt is attached to this report yet.',
      preferredRemediation(
        'Reload the onboarding ticket detail and verify the low-risk first smoke completed.',
        firstSmoke?.remediation_hint
      )
    ),
    makeCheck(
      'heartbeat_governance_visible',
      heartbeatGovernanceVisible(firstSmoke?.heartbeat_governance_snapshot),
      !summaryAutomation || !firstSmoke,
      firstSmoke
        ? [
          firstSmoke.heartbeat_governance_snapshot
            ? 'heartbeat_governance_snapshot=present'
            : 'heartbeat_governance_snapshot=missing',
          firstSmoke.heartbeat_governance_snapshot?.latest_quality_band
            ? `heartbeat_quality=${firstSmoke.heartbeat_governance_snapshot.latest_quality_band}`
            : 'heartbeat_quality=missing',
          firstSmoke.heartbeat_governance_snapshot?.next_review_due?.kind
            ? `next_review=${firstSmoke.heartbeat_governance_snapshot.next_review_due.kind}`
            : 'next_review=missing',
        ].join(' ')
        : 'No first smoke receipt is attached to this report yet.',
      'Re-run or reload first smoke and verify it exported heartbeat governance visibility (quality band / next review).'
    ),
    makeCheck(
      'outbox_drained',
      safeInt(summaryAutomation?.outbox_pending_count, 0) === 0 && safeInt(summaryAutomation?.outbox_delivered_count, 0) > 0,
      !summaryAutomation,
      summaryAutomation
        ? `outbox_pending=${summaryAutomation.outbox_pending_count} outbox_delivered=${summaryAutomation.outbox_delivered_count}`
        : 'No automation state is attached to this report yet.',
      preferredRemediation(
        'If replies are still pending, fix provider delivery config and run Retry Pending Replies from the local onboarding UI.',
        outboxRepairHints
      )
    ),
  ];
}

export function deriveOperatorChannelLiveTestStatus(checks = []) {
  const rows = safeArray(checks);
  if (rows.some((check) => safeString(check?.status) === 'fail')) return 'attention';
  if (rows.some((check) => safeString(check?.status) === 'pending')) return 'pending';
  return 'pass';
}

function defaultNextStep(checks = []) {
  const next = safeArray(checks).find((check) => safeString(check?.status) !== 'pass');
  return safeString(next?.remediation) || 'All key operator channel live-test checks passed.';
}

export function buildOperatorChannelLiveTestEvidenceReport({
  provider = '',
  verdict = '',
  summary = '',
  performedAt = '',
  evidenceRefs = [],
  readiness = null,
  runtimeStatus = null,
  ticketDetail = null,
  adminBaseUrl = '',
  outputPath = '',
  requiredNextStep = '',
} = {}) {
  const normalizedProvider = normalizeProviderId(provider);
  if (!normalizedProvider) {
    throw new Error('operator_channel_live_test_provider_required');
  }

  const checks = evaluateOperatorChannelLiveTestChecks({
    provider: normalizedProvider,
    readiness,
    runtimeStatus,
    ticketDetail,
  });
  const derivedStatus = deriveOperatorChannelLiveTestStatus(checks);
  const summaryRuntime = summarizeRuntime(runtimeStatus);
  const summaryReadiness = summarizeReadiness(readiness);
  const summaryTicket = summarizeTicket(ticketDetail?.ticket);
  const summaryAutomation = summarizeAutomationState(ticketDetail?.automation_state);
  const repairHints = collectRepairHints(
    summaryRuntime?.repair_hints,
    summaryReadiness?.repair_hints,
    summaryAutomation?.delivery_readiness?.repair_hints
  );

  return {
    schema_version: OPERATOR_CHANNEL_LIVE_TEST_EVIDENCE_SCHEMA,
    generated_at: new Date().toISOString(),
    performed_at: isoTimestamp(performedAt),
    provider: normalizedProvider,
    operator_verdict: normalizeVerdict(verdict),
    derived_status: derivedStatus,
    live_test_success: derivedStatus === 'pass',
    summary: safeString(summary),
    report_scope: ['XT-W3-24-S', 'operator-channel-live-test'],
    admin_base_url: safeString(adminBaseUrl),
    machine_readable_evidence_path: safeString(outputPath),
    evidence_refs: normalizeEvidenceRefs(evidenceRefs),
    runtime_snapshot: summaryRuntime,
    readiness_snapshot: summaryReadiness,
    repair_hints: repairHints,
    onboarding_snapshot: {
      ticket: summaryTicket,
      latest_decision: summarizeDecision(ticketDetail?.latest_decision),
      automation_state: summaryAutomation,
    },
    provider_release_context: summaryRuntime
      ? {
        release_stage: safeString(summaryRuntime.release_stage),
        release_blocked: !!summaryRuntime.release_blocked,
        require_real_evidence: !!summaryRuntime.require_real_evidence,
      }
      : null,
    checks,
    required_next_step: safeString(requiredNextStep) || defaultNextStep(checks),
  };
}

export function operatorChannelLiveTestProviderRow(snapshot = {}, provider = '') {
  return pickProviderRow(snapshot?.providers, normalizeProviderId(provider));
}
