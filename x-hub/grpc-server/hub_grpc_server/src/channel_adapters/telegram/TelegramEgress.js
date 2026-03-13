import { buildTelegramApprovalCallbackData } from './TelegramInteractiveActions.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

function buildLines(lines = []) {
  return safeArray(lines)
    .map((line) => safeString(line))
    .filter(Boolean)
    .join('\n');
}

function parseTelegramThreadKey(thread_key = '') {
  const match = /^topic:(\d+)$/.exec(safeString(thread_key));
  return match ? safeInt(match[1], 0) : 0;
}

function normalizeDeliveryContext(input = {}) {
  const src = safeObject(input);
  const conversationId = safeString(src.conversation_id || src.chat_id);
  if (!conversationId) {
    return {
      ok: false,
      deny_code: 'conversation_id_missing',
    };
  }
  return {
    ok: true,
    context: {
      provider: 'telegram',
      account_id: safeString(src.account_id),
      conversation_id: conversationId,
      thread_key: safeString(src.thread_key),
    },
  };
}

export function buildTelegramSendMessagePayload({
  delivery_context = {},
  text = '',
  reply_markup = null,
} = {}) {
  const normalized = normalizeDeliveryContext(delivery_context);
  if (!normalized.ok) return normalized;
  const bodyText = safeString(text);
  if (!bodyText) {
    return {
      ok: false,
      deny_code: 'text_missing',
    };
  }
  const payload = {
    chat_id: normalized.context.conversation_id,
    text: bodyText,
  };
  const messageThreadId = parseTelegramThreadKey(normalized.context.thread_key);
  if (messageThreadId > 0) payload.message_thread_id = messageThreadId;
  if (safeObject(reply_markup) && Object.keys(safeObject(reply_markup)).length) {
    payload.reply_markup = safeObject(reply_markup);
  }
  return {
    ok: true,
    delivery_context: normalized.context,
    payload,
  };
}

export function buildTelegramApprovalMessage({
  delivery_context = {},
  title = 'Approval Required',
  summary_lines = [],
  audit_ref = '',
  binding_id = '',
  scope_type = '',
  scope_id = '',
  project_id = '',
  grant_request_id = '',
  pending_grant_status = 'pending',
} = {}) {
  const auditRef = safeString(audit_ref);
  if (!auditRef) {
    return {
      ok: false,
      deny_code: 'audit_ref_missing',
    };
  }
  const bindingId = safeString(binding_id);
  if (!bindingId) {
    return {
      ok: false,
      deny_code: 'binding_id_missing',
    };
  }
  const scopeType = safeString(scope_type);
  const scopeId = safeString(scope_id);
  const grantRequestId = safeString(grant_request_id);
  if (!scopeType || !scopeId) {
    return {
      ok: false,
      deny_code: 'scope_missing',
    };
  }
  if (!grantRequestId) {
    return {
      ok: false,
      deny_code: 'grant_request_id_missing',
    };
  }
  const projectId = safeString(project_id || (scopeType === 'project' ? scopeId : ''));
  const approveData = buildTelegramApprovalCallbackData({
    action_name: 'grant.approve',
    grant_request_id: grantRequestId,
    project_id: projectId,
  });
  const rejectData = buildTelegramApprovalCallbackData({
    action_name: 'grant.reject',
    grant_request_id: grantRequestId,
    project_id: projectId,
  });
  const keyboard = approveData && rejectData
    ? {
        inline_keyboard: [[
          { text: 'Approve', callback_data: approveData },
          { text: 'Reject', callback_data: rejectData },
        ]],
      }
    : null;
  const fallbackCommands = keyboard
    ? []
    : [
        `Approve manually: grant approve ${grantRequestId} project ${projectId}`,
        `Reject manually: grant reject ${grantRequestId} project ${projectId} reason <why>`,
      ];

  return buildTelegramSendMessagePayload({
    delivery_context,
    text: buildLines([
      safeString(title) || 'Approval Required',
      projectId ? `Project: ${projectId}` : '',
      `Grant: ${grantRequestId}`,
      `Audit: ${auditRef}`,
      `Binding: ${bindingId}`,
      `Status: ${safeString(pending_grant_status || 'pending') || 'pending'}`,
      ...safeArray(summary_lines),
      ...fallbackCommands,
    ]),
    reply_markup: keyboard,
  });
}

export function buildTelegramSummaryMessage({
  delivery_context = {},
  title = 'Supervisor Summary',
  status = '',
  project_id = '',
  lines = [],
  audit_ref = '',
} = {}) {
  const auditRef = safeString(audit_ref);
  if (!auditRef) {
    return {
      ok: false,
      deny_code: 'audit_ref_missing',
    };
  }
  return buildTelegramSendMessagePayload({
    delivery_context,
    text: buildLines([
      safeString(title) || 'Supervisor Summary',
      safeString(status) ? `Status: ${safeString(status)}` : '',
      safeString(project_id) ? `Project: ${safeString(project_id)}` : '',
      ...safeArray(lines),
      `Audit: ${auditRef}`,
    ]),
  });
}
