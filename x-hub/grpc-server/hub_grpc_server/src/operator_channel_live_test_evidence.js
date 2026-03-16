export const OPERATOR_CHANNEL_LIVE_TEST_EVIDENCE_SCHEMA = 'xt_w3_24_operator_channel_live_test_evidence.v1';

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

function pickProviderRow(rows, provider) {
  return safeArray(rows).find((row) => normalizeProviderId(row?.provider) === provider) || null;
}

function summarizeReadiness(readiness) {
  if (!readiness || typeof readiness !== 'object') return null;
  return {
    provider: normalizeProviderId(readiness.provider),
    ready: !!readiness.ready,
    reply_enabled: !!readiness.reply_enabled,
    credentials_configured: !!readiness.credentials_configured,
    deny_code: safeString(readiness.deny_code),
    remediation_hint: safeString(readiness.remediation_hint),
  };
}

function summarizeRuntime(runtimeStatus) {
  if (!runtimeStatus || typeof runtimeStatus !== 'object') return null;
  return {
    provider: normalizeProviderId(runtimeStatus.provider),
    label: safeString(runtimeStatus.label),
    release_stage: safeString(runtimeStatus.release_stage),
    release_blocked: !!runtimeStatus.release_blocked,
    require_real_evidence: !!runtimeStatus.require_real_evidence,
    endpoint_visibility: safeString(runtimeStatus.endpoint_visibility),
    operator_surface: safeString(runtimeStatus.operator_surface),
    runtime_state: safeString(runtimeStatus.runtime_state),
    delivery_ready: !!runtimeStatus.delivery_ready,
    command_entry_ready: !!runtimeStatus.command_entry_ready,
    last_error_code: safeString(runtimeStatus.last_error_code),
    updated_at_ms: safeInt(runtimeStatus.updated_at_ms),
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

function summarizeAutomationState(state) {
  if (!state || typeof state !== 'object') return null;
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
    }
    : null;
  return {
    first_smoke: firstSmoke,
    outbox_pending_count: safeInt(state.outbox_pending_count),
    outbox_delivered_count: safeInt(state.outbox_delivered_count),
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

  return [
    makeCheck(
      'runtime_command_entry_ready',
      !!summaryRuntime?.command_entry_ready,
      !summaryRuntime,
      summaryRuntime
        ? `runtime_state=${summaryRuntime.runtime_state || 'unknown'} command_entry_ready=${summaryRuntime.command_entry_ready ? '1' : '0'}`
        : 'No runtime status row was available for this provider.',
      normalizedProvider === 'telegram'
        ? 'Confirm the Telegram polling worker is running with HUB_TELEGRAM_OPERATOR_ENABLE=1, HUB_TELEGRAM_OPERATOR_BOT_TOKEN, and HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN.'
        : 'Confirm the local-only connector worker is running and reload operator channel runtime status.'
    ),
    makeCheck(
      'delivery_ready',
      !!(summaryReadiness?.ready || summaryRuntime?.delivery_ready),
      !summaryReadiness && !summaryRuntime,
      summaryReadiness
        ? `readiness=${summaryReadiness.ready ? 'ready' : 'blocked'} reply_enabled=${summaryReadiness.reply_enabled ? '1' : '0'} credentials_configured=${summaryReadiness.credentials_configured ? '1' : '0'}`
        : (summaryRuntime ? `delivery_ready=${summaryRuntime.delivery_ready ? '1' : '0'}` : 'No delivery readiness row was available for this provider.'),
      'Confirm dedicated reply credentials are loaded into the running Hub process, then refresh readiness.'
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
        ? `first_smoke_status=${firstSmoke.status || 'unknown'} action=${firstSmoke.action_name || 'unknown'} route_mode=${firstSmoke.route_mode || 'unknown'}`
        : 'No first smoke receipt is attached to this report yet.',
      'Reload the onboarding ticket detail and verify the low-risk first smoke completed.'
    ),
    makeCheck(
      'outbox_drained',
      safeInt(summaryAutomation?.outbox_pending_count, 0) === 0 && safeInt(summaryAutomation?.outbox_delivered_count, 0) > 0,
      !summaryAutomation,
      summaryAutomation
        ? `outbox_pending=${summaryAutomation.outbox_pending_count} outbox_delivered=${summaryAutomation.outbox_delivered_count}`
        : 'No automation state is attached to this report yet.',
      'If replies are still pending, fix provider delivery config and run Retry Pending Replies from the local onboarding UI.'
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
    onboarding_snapshot: {
      ticket: summaryTicket,
      latest_decision: summarizeDecision(ticketDetail?.latest_decision),
      automation_state: summarizeAutomationState(ticketDetail?.automation_state),
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
