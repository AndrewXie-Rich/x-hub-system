import { buildSlackResultSummary } from './channel_adapters/slack/SlackResultPublisher.js';
import { buildTelegramResultSummary } from './channel_adapters/telegram/TelegramResultPublisher.js';
import { buildFeishuResultSummary } from './channel_adapters/feishu/FeishuResultPublisher.js';
import { buildWhatsAppCloudResultSummary } from './channel_adapters/whatsapp_cloud_api/WhatsAppCloudResultPublisher.js';
import { createChannelOnboardingDeliveryTarget } from './channel_onboarding_delivery_readiness.js';
import {
  attachChannelOnboardingFirstSmokeOutboxRefs,
  runChannelOnboardingFirstSmoke,
} from './channel_onboarding_first_smoke.js';
import {
  buildChannelOnboardingAcceptedReply,
  buildChannelOnboardingSummaryReply,
} from './channel_onboarding_reply_builder.js';
import {
  enqueueChannelOutboxItem,
  listChannelOutboxItems,
  recordChannelOutboxDeliveryResult,
} from './channel_outbox.js';
import { getChannelOnboardingAutomationState } from './channel_onboarding_status_view.js';
import { nowMs, uuid } from './util.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function resultSummaryBuilderForProvider(provider = '') {
  const normalized = safeString(provider).toLowerCase();
  if (normalized === 'slack') return buildSlackResultSummary;
  if (normalized === 'telegram') return buildTelegramResultSummary;
  if (normalized === 'feishu') return buildFeishuResultSummary;
  if (normalized === 'whatsapp_cloud_api') return buildWhatsAppCloudResultSummary;
  return null;
}

function outboxAuditActor(audit = {}, app_id = 'channel_onboarding_automation') {
  return {
    device_id: safeString(audit.device_id || 'channel_onboarding_automation'),
    user_id: safeString(audit.user_id),
    app_id: safeString(audit.app_id || app_id) || app_id,
    project_id: safeString(audit.project_id),
    session_id: safeString(audit.session_id),
  };
}

function appendOutboxRetryAudit(db, {
  ticket_id = '',
  request_id = '',
  audit = {},
  ok = true,
  deny_code = '',
  detail = '',
  delivered_count = 0,
  pending_count = 0,
} = {}) {
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type: ok
      ? 'channel.onboarding.outbox.retry.completed'
      : 'channel.onboarding.outbox.retry.rejected',
    created_at_ms: nowMs(),
    severity: ok ? 'info' : 'warn',
    device_id: safeString(audit.device_id || 'channel_onboarding_outbox_retry'),
    user_id: safeString(audit.user_id) || null,
    app_id: safeString(audit.app_id || 'channel_onboarding_outbox_retry'),
    project_id: safeString(audit.project_id) || null,
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: 'channel.outbox.write',
    model_id: null,
    ok: !!ok,
    error_code: ok ? null : (safeString(deny_code) || 'channel_onboarding_outbox_retry_rejected'),
    error_message: ok ? null : (safeString(detail || deny_code || 'channel_onboarding_outbox_retry_rejected')),
    ext_json: JSON.stringify({
      ticket_id: safeString(ticket_id),
      delivered_count: Math.max(0, Number(delivered_count || 0)),
      pending_count: Math.max(0, Number(pending_count || 0)),
    }),
  });
}

function buildFallbackFirstSmokeReply({
  ticket = {},
  decision = {},
  receipt = {},
} = {}) {
  const projectId = safeString(
    (safeString(decision.scope_type) === 'project' ? decision.scope_id : '')
    || receipt.project_id
  );
  return buildChannelOnboardingSummaryReply({
    ticket,
    decision,
    title: 'First Smoke Result',
    status: safeString(receipt.status || receipt.deny_code || 'first_smoke_failed'),
    project_id: projectId,
    lines: [
      safeString(receipt.action_name) ? `Action: ${safeString(receipt.action_name)}` : '',
      safeString(receipt.route_mode) ? `Route: ${safeString(receipt.route_mode)}` : '',
      safeString(receipt.deny_code) ? `Reason: ${safeString(receipt.deny_code)}` : '',
      safeString(receipt.detail) ? `Detail: ${safeString(receipt.detail)}` : '',
      safeString(receipt.remediation_hint) ? `Next: ${safeString(receipt.remediation_hint)}` : '',
    ].filter(Boolean),
    audit_ref: `channel_onboarding_first_smoke:${safeString(receipt.receipt_id || receipt.ticket_id || 'unknown') || 'unknown'}`,
  });
}

function makeOutboxItem({
  provider = '',
  item_kind = '',
  ticket = {},
  decision = {},
  receipt_id = '',
  payload = {},
  delivery_context = {},
} = {}) {
  const ticketId = safeString(ticket.ticket_id);
  const decisionId = safeString(decision.decision_id);
  return {
    provider: safeString(provider),
    item_kind: safeString(item_kind),
    ticket_id: ticketId,
    decision_id: decisionId,
    receipt_id: safeString(receipt_id),
    dedupe_key: `${safeString(provider).toLowerCase()}:${safeString(item_kind)}:${ticketId}:${decisionId || 'na'}`,
    payload: safeObject(payload),
    delivery_context: safeObject(delivery_context),
  };
}

export function runApprovedChannelOnboardingAutomation(db, {
  ticket = {},
  decision = {},
  auto_bind_receipt = null,
  request_id = '',
  runtimeBaseDir = '',
  audit = {},
} = {}) {
  if (safeString(decision.decision).toLowerCase() !== 'approve') {
    return {
      ok: false,
      deny_code: 'decision_not_approved',
      ack_item: null,
      smoke_item: null,
      receipt: null,
    };
  }

  const ackSummary = buildChannelOnboardingAcceptedReply({
    ticket,
    decision,
    auto_bind_receipt,
  });
  const ackItem = ackSummary.ok
    ? enqueueChannelOutboxItem(db, {
        item: makeOutboxItem({
          provider: safeString(ticket.provider),
          item_kind: 'onboarding_ack',
          ticket,
          decision,
          receipt_id: '',
          payload: ackSummary.payload,
          delivery_context: ackSummary.delivery_context,
        }),
        request_id,
        audit: outboxAuditActor(audit, 'channel_onboarding_ack'),
      }).item
    : null;

  const smoke = runChannelOnboardingFirstSmoke(db, {
    ticket,
    decision,
    auto_bind_receipt,
    request_id: `${safeString(request_id) || safeString(ticket.ticket_id) || 'channel_onboarding'}:first_smoke`,
    runtimeBaseDir,
    audit: outboxAuditActor(audit, 'channel_onboarding_first_smoke'),
  });
  const buildResultSummary = resultSummaryBuilderForProvider(ticket.provider);
  const smokeSummary = typeof buildResultSummary === 'function' && smoke.result
    ? buildResultSummary(smoke.result)
    : buildFallbackFirstSmokeReply({
        ticket,
        decision,
        receipt: smoke.receipt,
      });
  const smokeItem = smokeSummary.ok
    ? enqueueChannelOutboxItem(db, {
        item: makeOutboxItem({
          provider: safeString(ticket.provider),
          item_kind: 'onboarding_first_smoke',
          ticket,
          decision,
          receipt_id: safeString(smoke.receipt?.receipt_id),
          payload: smokeSummary.payload,
          delivery_context: smokeSummary.delivery_context,
        }),
        request_id,
        audit: outboxAuditActor(audit, 'channel_onboarding_first_smoke_reply'),
      }).item
    : null;

  const receipt = smoke.receipt
    ? attachChannelOnboardingFirstSmokeOutboxRefs(db, {
        ticket_id: safeString(ticket.ticket_id),
        ack_outbox_item_id: safeString(ackItem?.item_id),
        smoke_outbox_item_id: safeString(smokeItem?.item_id),
        request_id,
        audit: outboxAuditActor(audit, 'channel_onboarding_first_smoke_receipt'),
      })
    : null;

  return {
    ok: true,
    deny_code: '',
    ack_item: ackItem,
    smoke_item: smokeItem,
    receipt,
  };
}

export async function flushChannelOutboxForTicket(db, {
  ticket_id = '',
  request_id = '',
  env = process.env,
  fetch_impl = globalThis.fetch,
  audit = {},
} = {}) {
  const items = listChannelOutboxItems(db, {
    ticket_id,
    status: 'pending',
    limit: 20,
  });
  const deliveryTargetCache = new Map();
  const delivered = [];
  const pending = [];

  for (const item of items) {
    const provider = safeString(item.provider).toLowerCase();
    if (!deliveryTargetCache.has(provider)) {
      deliveryTargetCache.set(provider, createChannelOnboardingDeliveryTarget({
        provider,
        env,
        fetch_impl,
      }));
    }
    const resolved = deliveryTargetCache.get(provider);
    if (!resolved?.ok || !resolved.target || typeof resolved.target.postMessage !== 'function') {
      const updated = recordChannelOutboxDeliveryResult(db, {
        item_id: item.item_id,
        delivered: false,
        deny_code: safeString(resolved?.deny_code || 'provider_delivery_not_configured'),
        error_message: safeString(resolved?.deny_code || 'provider_delivery_not_configured'),
        request_id,
        audit: outboxAuditActor(audit, 'channel_outbox_flush'),
      });
      pending.push(updated.item);
      continue;
    }

    try {
      const response = await resolved.target.postMessage(item.payload);
      const updated = recordChannelOutboxDeliveryResult(db, {
        item_id: item.item_id,
        delivered: true,
        deny_code: '',
        error_message: '',
        provider_message_ref: safeString(
          response?.message_ts
          || response?.message_id
          || response?.channel
          || response?.to
        ),
        request_id,
        audit: outboxAuditActor(audit, 'channel_outbox_flush'),
      });
      delivered.push(updated.item);
    } catch (error) {
      const deny_code = safeString(error?.message || 'provider_delivery_failed') || 'provider_delivery_failed';
      const updated = recordChannelOutboxDeliveryResult(db, {
        item_id: item.item_id,
        delivered: false,
        deny_code,
        error_message: deny_code,
        request_id,
        audit: outboxAuditActor(audit, 'channel_outbox_flush'),
      });
      pending.push(updated.item);
    }
  }

  return {
    ok: true,
    delivered,
    pending,
  };
}

export async function retryChannelOnboardingOutbox(db, {
  ticket = null,
  ticket_id = '',
  request_id = '',
  env = process.env,
  fetch_impl = globalThis.fetch,
  audit = {},
} = {}) {
  const ticketId = safeString(ticket?.ticket_id || ticket_id);
  if (!ticketId) {
    appendOutboxRetryAudit(db, {
      ticket_id: '',
      request_id,
      audit: outboxAuditActor(audit, 'channel_onboarding_outbox_retry'),
      ok: false,
      deny_code: 'ticket_id_missing',
      detail: 'ticket_id_missing',
      delivered_count: 0,
      pending_count: 0,
    });
    return {
      ok: false,
      deny_code: 'ticket_id_missing',
      delivered: [],
      pending: [],
      delivered_count: 0,
      pending_count: 0,
      automation_state: null,
    };
  }
  const ticketStatus = safeString(ticket?.status);
  if (ticket && ticketStatus && ticketStatus !== 'approved') {
    const automationState = getChannelOnboardingAutomationState(db, {
      ticket_id: ticketId,
      env,
    });
    appendOutboxRetryAudit(db, {
      ticket_id: ticketId,
      request_id,
      audit: outboxAuditActor(audit, 'channel_onboarding_outbox_retry'),
      ok: false,
      deny_code: 'ticket_not_approved',
      detail: `ticket status ${ticketStatus || 'unknown'} is not approved`,
      delivered_count: 0,
      pending_count: 0,
    });
    return {
      ok: false,
      deny_code: 'ticket_not_approved',
      delivered: [],
      pending: [],
      delivered_count: 0,
      pending_count: 0,
      automation_state: automationState,
    };
  }

  const flushed = await flushChannelOutboxForTicket(db, {
    ticket_id: ticketId,
    request_id,
    env,
    fetch_impl,
    audit: outboxAuditActor(audit, 'channel_onboarding_outbox_retry_flush'),
  });
  const automationState = getChannelOnboardingAutomationState(db, {
    ticket_id: ticketId,
    env,
  });
  appendOutboxRetryAudit(db, {
    ticket_id: ticketId,
    request_id,
    audit: outboxAuditActor(audit, 'channel_onboarding_outbox_retry'),
    ok: true,
    delivered_count: Array.isArray(flushed.delivered) ? flushed.delivered.length : 0,
    pending_count: Array.isArray(flushed.pending) ? flushed.pending.length : 0,
  });
  return {
    ok: true,
    deny_code: '',
    delivered: Array.isArray(flushed.delivered) ? flushed.delivered : [],
    pending: Array.isArray(flushed.pending) ? flushed.pending : [],
    delivered_count: Array.isArray(flushed.delivered) ? flushed.delivered.length : 0,
    pending_count: Array.isArray(flushed.pending) ? flushed.pending.length : 0,
    automation_state: automationState,
  };
}
