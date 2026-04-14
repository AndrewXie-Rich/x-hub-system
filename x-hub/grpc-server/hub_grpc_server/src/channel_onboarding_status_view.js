import { getChannelOnboardingDiscoveryTicketById } from './channel_onboarding_discovery_store.js';
import { getChannelOnboardingDeliveryReadiness } from './channel_onboarding_delivery_readiness.js';
import { getChannelOnboardingFirstSmokeReceiptByTicketId } from './channel_onboarding_first_smoke.js';
import { listChannelOutboxItems } from './channel_outbox.js';

export const CHANNEL_ONBOARDING_AUTOMATION_STATE_SCHEMA = 'xhub.channel_onboarding_automation_state.v1';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function parseJsonObject(input) {
  if (input && typeof input === 'object' && !Array.isArray(input)) return input;
  const text = safeString(input);
  if (!text) return null;
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function heartbeatGovernanceSnapshotFromReceipt(row) {
  const result = safeObject(row?.result);
  const execution = safeObject(result.execution);
  const query = safeObject(execution.query);
  return parseJsonObject(query.heartbeat_governance_snapshot_json);
}

function normalizeFirstSmokeReceipt(row) {
  if (!row || typeof row !== 'object') return null;
  const heartbeatGovernanceSnapshot = heartbeatGovernanceSnapshotFromReceipt(row);
  return {
    schema_version: safeString(row.schema_version),
    receipt_id: safeString(row.receipt_id),
    ticket_id: safeString(row.ticket_id),
    decision_id: safeString(row.decision_id),
    provider: safeString(row.provider),
    action_name: safeString(row.action_name),
    status: safeString(row.status),
    route_mode: safeString(row.route_mode),
    deny_code: safeString(row.deny_code),
    detail: safeString(row.detail),
    remediation_hint: safeString(row.remediation_hint),
    project_id: safeString(row.project_id),
    binding_id: safeString(row.binding_id),
    ack_outbox_item_id: safeString(row.ack_outbox_item_id),
    smoke_outbox_item_id: safeString(row.smoke_outbox_item_id),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
    heartbeat_governance_snapshot_json: heartbeatGovernanceSnapshot
      ? JSON.stringify(heartbeatGovernanceSnapshot)
      : '',
    heartbeat_governance_snapshot: heartbeatGovernanceSnapshot,
  };
}

function normalizeOutboxItem(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    schema_version: safeString(row.schema_version),
    item_id: safeString(row.item_id),
    provider: safeString(row.provider),
    item_kind: safeString(row.item_kind),
    status: safeString(row.status),
    ticket_id: safeString(row.ticket_id),
    decision_id: safeString(row.decision_id),
    receipt_id: safeString(row.receipt_id),
    attempt_count: safeInt(row.attempt_count, 0),
    last_error_code: safeString(row.last_error_code),
    last_error_message: safeString(row.last_error_message),
    provider_message_ref: safeString(row.provider_message_ref),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    delivered_at_ms: safeInt(row.delivered_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

function normalizeDeliveryReadiness(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    provider: safeString(row.provider),
    ready: !!row.ready,
    reply_enabled: !!row.reply_enabled,
    credentials_configured: !!row.credentials_configured,
    deny_code: safeString(row.deny_code),
    remediation_hint: safeString(row.remediation_hint),
  };
}

export function getChannelOnboardingAutomationState(db, {
  ticket_id = '',
  outbox_limit = 10,
  env = process.env,
} = {}) {
  const ticketId = safeString(ticket_id);
  if (!ticketId) return null;

  const ticket = getChannelOnboardingDiscoveryTicketById(db, {
    ticket_id: ticketId,
  });
  const first_smoke = normalizeFirstSmokeReceipt(
    getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
      ticket_id: ticketId,
    })
  );
  const outbox_items = listChannelOutboxItems(db, {
    ticket_id: ticketId,
    limit: Math.max(1, Math.min(50, safeInt(outbox_limit, 10) || 10)),
  }).map((row) => normalizeOutboxItem(row)).filter(Boolean);
  const provider = safeString(
    ticket?.provider
    || first_smoke?.provider
    || outbox_items[0]?.provider
  ).toLowerCase();

  if (!first_smoke && !outbox_items.length) return null;

  return {
    schema_version: CHANNEL_ONBOARDING_AUTOMATION_STATE_SCHEMA,
    ticket_id: ticketId,
    first_smoke,
    outbox_items,
    outbox_pending_count: outbox_items.filter((item) => safeString(item.status) === 'pending').length,
    outbox_delivered_count: outbox_items.filter((item) => safeString(item.status) === 'delivered').length,
    delivery_readiness: provider
      ? normalizeDeliveryReadiness(getChannelOnboardingDeliveryReadiness({
          provider,
          env,
        }))
      : null,
  };
}
