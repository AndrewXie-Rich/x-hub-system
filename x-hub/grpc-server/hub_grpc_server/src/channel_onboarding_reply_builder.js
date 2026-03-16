import { buildSlackSummaryMessage } from './channel_adapters/slack/SlackEgress.js';
import { buildTelegramSummaryMessage } from './channel_adapters/telegram/TelegramEgress.js';
import { buildFeishuSummaryMessage } from './channel_adapters/feishu/FeishuEgress.js';
import { buildWhatsAppCloudSummaryMessage } from './channel_adapters/whatsapp_cloud_api/WhatsAppCloudEgress.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function deliveryContextFromTicket(ticket = {}, decision = {}) {
  return {
    provider: safeString(ticket.provider),
    account_id: safeString(ticket.account_id),
    conversation_id: safeString(ticket.conversation_id),
    thread_key: safeString(ticket.thread_key),
    binding_mode: safeString(decision.binding_mode || ticket.recommended_binding_mode),
  };
}

function summaryBuilderForProvider(provider = '') {
  const normalized = safeString(provider).toLowerCase();
  if (normalized === 'slack') return buildSlackSummaryMessage;
  if (normalized === 'telegram') return buildTelegramSummaryMessage;
  if (normalized === 'feishu') return buildFeishuSummaryMessage;
  if (normalized === 'whatsapp_cloud_api') return buildWhatsAppCloudSummaryMessage;
  return null;
}

export function buildChannelOnboardingSummaryReply({
  ticket = {},
  decision = {},
  title = 'Operator Channel Update',
  status = '',
  project_id = '',
  lines = [],
  audit_ref = '',
} = {}) {
  const provider = safeString(ticket.provider);
  const buildSummary = summaryBuilderForProvider(provider);
  if (typeof buildSummary !== 'function') {
    return {
      ok: false,
      deny_code: 'provider_unsupported',
    };
  }
  return buildSummary({
    delivery_context: deliveryContextFromTicket(ticket, decision),
    title: safeString(title) || 'Operator Channel Update',
    status: safeString(status),
    project_id: safeString(project_id || (safeString(decision.scope_type) === 'project' ? decision.scope_id : '')),
    lines: Array.isArray(lines) ? lines : [],
    audit_ref: safeString(audit_ref),
  });
}

export function buildChannelOnboardingAcceptedReply({
  ticket = {},
  decision = {},
  auto_bind_receipt = null,
  first_smoke_action = 'supervisor.status.get',
} = {}) {
  const receipt = safeObject(auto_bind_receipt);
  const projectId = safeString(
    (safeString(decision.scope_type) === 'project' ? decision.scope_id : '')
    || ticket.proposed_scope_id
  );
  return buildChannelOnboardingSummaryReply({
    ticket,
    decision,
    title: 'Operator Channel Connected',
    status: 'connected_pending_smoke',
    project_id: projectId,
    lines: [
      'This conversation is now bound to the governed Hub operator channel.',
      safeString(decision.scope_type) && safeString(decision.scope_id)
        ? `Scope: ${safeString(decision.scope_type)}/${safeString(decision.scope_id)}`
        : '',
      safeString(decision.binding_mode || ticket.recommended_binding_mode)
        ? `Binding mode: ${safeString(decision.binding_mode || ticket.recommended_binding_mode)}`
        : '',
      safeString(receipt.preferred_device_id)
        ? `Preferred device: ${safeString(receipt.preferred_device_id)}`
        : '',
      safeString(first_smoke_action)
        ? `Running first smoke: ${safeString(first_smoke_action)}`
        : '',
    ].filter(Boolean),
    audit_ref: `channel_onboarding_ack:${safeString(decision.decision_id || ticket.ticket_id || 'unknown') || 'unknown'}`,
  });
}
