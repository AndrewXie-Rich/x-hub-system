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

function normalizeTelegramChannelScope(chatType) {
  return safeString(chatType).toLowerCase() === 'private' ? 'dm' : 'group';
}

function normalizeTelegramThreadKey(messageThreadId) {
  const value = safeInt(messageThreadId, 0);
  return value > 0 ? `topic:${value}` : '';
}

const TELEGRAM_ACTION_CODE_MAP = Object.freeze({
  ga: 'grant.approve',
  gr: 'grant.reject',
});

export function mapTelegramActionCodeToChannelAction(code) {
  return TELEGRAM_ACTION_CODE_MAP[safeString(code).toLowerCase()] || '';
}

export function buildTelegramApprovalCallbackData({
  action_name = '',
  grant_request_id = '',
  project_id = '',
} = {}) {
  const actionCode = action_name === 'grant.approve'
    ? 'ga'
    : action_name === 'grant.reject'
      ? 'gr'
      : '';
  const grantRequestId = safeString(grant_request_id);
  const projectId = safeString(project_id);
  if (!actionCode || !grantRequestId || !projectId) return '';
  const value = `xt|${actionCode}|${grantRequestId}|${projectId}`;
  return Buffer.byteLength(value, 'utf8') <= 64 ? value : '';
}

export function compileTelegramCallbackAction(update = {}, { account_id = '' } = {}) {
  const callbackQuery = safeObject(update.callback_query);
  const message = safeObject(callbackQuery.message);
  const chat = safeObject(message.chat);
  const from = safeObject(callbackQuery.from);
  const data = safeString(callbackQuery.data);
  const parts = data.split('|');
  if (parts.length < 4 || parts[0] !== 'xt') {
    return {
      ok: false,
      deny_code: 'action_unsupported',
    };
  }

  const action_name = mapTelegramActionCodeToChannelAction(parts[1]);
  const grant_request_id = safeString(parts[2]);
  const project_id = safeString(parts[3]);
  if (!action_name || !grant_request_id || !project_id) {
    return {
      ok: false,
      deny_code: 'action_unsupported',
    };
  }

  return {
    ok: true,
    deny_code: '',
    request_id: `telegram:callback:${safeString(callbackQuery.id || update.update_id) || 'unknown'}`,
    callback_query_id: safeString(callbackQuery.id),
    actor: {
      provider: 'telegram',
      external_user_id: safeString(from.id),
      external_tenant_id: safeString(account_id),
    },
    channel: {
      provider: 'telegram',
      account_id: safeString(account_id),
      conversation_id: safeString(chat.id),
      thread_key: normalizeTelegramThreadKey(message.message_thread_id),
      channel_scope: normalizeTelegramChannelScope(chat.type),
    },
    action: {
      binding_id: '',
      action_name,
      scope_type: 'project',
      scope_id: project_id,
      note: '',
      pending_grant: {
        grant_request_id,
        project_id,
        status: 'pending',
      },
    },
  };
}
