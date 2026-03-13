import { compileTelegramCallbackAction } from './TelegramInteractiveActions.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function normalizeTelegramText(input) {
  return safeString(input).replace(/\s+/g, ' ').trim();
}

function stripLeadingTelegramMention(text) {
  return normalizeTelegramText(text).replace(/^@\S+\s+/g, '').trim();
}

function normalizeGrantOperatorNote(input) {
  const text = normalizeTelegramText(input);
  return text ? text.slice(0, 500) : '';
}

function normalizeTelegramChannelScope(chatType) {
  return safeString(chatType).toLowerCase() === 'private' ? 'dm' : 'group';
}

function normalizeTelegramThreadKey(messageThreadId) {
  const value = safeInt(messageThreadId, 0);
  return value > 0 ? `topic:${value}` : '';
}

function command(action_name, extras = {}) {
  return {
    action_name,
    ...extras,
  };
}

export function compileTelegramTextCommand(input) {
  const text = stripLeadingTelegramMention(input);
  if (!text) return null;

  if (/^(xt|supervisor)\s+status$/i.test(text) || /^status$/i.test(text)) {
    return command('supervisor.status.get');
  }
  if (/^(xt|supervisor)\s+blockers$/i.test(text) || /^blockers$/i.test(text)) {
    return command('supervisor.blockers.get');
  }
  if (/^(xt|supervisor)\s+queue$/i.test(text) || /^queue$/i.test(text)) {
    return command('supervisor.queue.get');
  }
  if (/^(xt|device)\s+doctor$/i.test(text) || /^doctor$/i.test(text)) {
    return command('device.doctor.get');
  }
  if (/^(xt|device)\s+permissions?$/i.test(text) || /^permissions$/i.test(text)) {
    return command('device.permission_status.get');
  }
  if (/^(xt|supervisor)\s+pause$/i.test(text) || /^pause$/i.test(text)) {
    return command('supervisor.pause');
  }
  if (/^(xt|supervisor)\s+resume$/i.test(text) || /^resume$/i.test(text)) {
    return command('supervisor.resume');
  }
  if (/^deploy\s+plan$/i.test(text)) {
    return command('deploy.plan');
  }
  if (/^deploy\s+(execute|run)$/i.test(text)) {
    return command('deploy.execute');
  }

  const grantApprove = text.match(/^grant\s+approve\s+([A-Za-z0-9._:-]+)(?:\s+(?:project|in)\s+([A-Za-z0-9._:/-]+))?(?:\s+(.+))?$/i);
  if (grantApprove) {
    const noteRaw = safeString(grantApprove[3]).replace(/^(?:note|because)\s+/i, '');
    return command('grant.approve', {
      scope_type: grantApprove[2] ? 'project' : '',
      scope_id: safeString(grantApprove[2]),
      pending_grant: {
        grant_request_id: grantApprove[1],
        project_id: safeString(grantApprove[2]),
        status: 'pending',
      },
      note: normalizeGrantOperatorNote(noteRaw),
    });
  }

  const grantReject = text.match(/^grant\s+(reject|deny)\s+([A-Za-z0-9._:-]+)(?:\s+(?:project|in)\s+([A-Za-z0-9._:/-]+))?(?:\s+(.+))?$/i);
  if (grantReject) {
    const noteRaw = safeString(grantReject[4]).replace(/^(?:reason|because|note)\s+/i, '');
    return command('grant.reject', {
      scope_type: grantReject[3] ? 'project' : '',
      scope_id: safeString(grantReject[3]),
      pending_grant: {
        grant_request_id: grantReject[2],
        project_id: safeString(grantReject[3]),
        status: 'pending',
      },
      note: normalizeGrantOperatorNote(noteRaw),
    });
  }

  return null;
}

export function normalizeTelegramUpdate(update = {}, { account_id = '' } = {}) {
  const src = safeObject(update);
  const callbackQuery = safeObject(src.callback_query);
  if (Object.keys(callbackQuery).length) {
    const interactive = compileTelegramCallbackAction(src, {
      account_id,
    });
    if (!interactive.ok) return interactive;
    return {
      ...interactive,
      envelope_type: 'callback_query',
      event_id: safeString(src.update_id || callbackQuery.id),
      replay_key: safeString(src.update_id || callbackQuery.id),
      signature_valid: true,
      token_valid: true,
    };
  }

  const message = safeObject(src.message);
  if (!Object.keys(message).length) {
    return {
      ok: false,
      deny_code: 'event_type_unsupported',
      retryable: false,
    };
  }
  if (message.from?.is_bot === true) {
    return {
      ok: false,
      deny_code: 'structured_action_missing',
      retryable: false,
    };
  }
  const structured_action = compileTelegramTextCommand(message.text || message.caption || '');
  const chat = safeObject(message.chat);
  const from = safeObject(message.from);
  return {
    ok: true,
    envelope_type: 'message',
    event_id: safeString(src.update_id || message.message_id),
    replay_key: safeString(src.update_id || message.message_id),
    signature_valid: true,
    token_valid: true,
    callback_query_id: '',
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
    structured_action,
  };
}
