import crypto from 'node:crypto';

import { compileFeishuCardAction } from './FeishuCards.js';

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

function sha256Hex(input) {
  return crypto.createHash('sha256').update(String(input || ''), 'utf8').digest('hex');
}

function normalizeFeishuText(input) {
  return safeString(input).replace(/\s+/g, ' ').trim();
}

function stripLeadingFeishuMentions(text) {
  return normalizeFeishuText(text)
    .replace(/<at\b[^>]*>[^<]*<\/at>/gi, ' ')
    .replace(/(^|\s)@_all(?=\s|$)/g, '$1')
    .replace(/(^|\s)@[^/\s]+(?=\s|$|\/)/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}

function command(action_name, extras = {}) {
  return {
    action_name,
    ...extras,
  };
}

function normalizeGrantOperatorNote(input) {
  const text = normalizeFeishuText(input);
  return text ? text.slice(0, 500) : '';
}

function parseFeishuMessageText(content, message_type) {
  const messageType = safeString(message_type).toLowerCase();
  if (!content) return '';
  if (messageType !== 'text') return safeString(content);
  try {
    const parsed = JSON.parse(String(content || '{}'));
    return safeString(parsed?.text);
  } catch {
    return safeString(content);
  }
}

function normalizeFeishuChannelScope(chatType, conversationId) {
  const type = safeString(chatType).toLowerCase();
  const conversation = safeString(conversationId);
  if (type === 'p2p' || type === 'private') return 'dm';
  if (!type && !conversation) return 'group';
  return 'group';
}

function extractFeishuEventType(body = {}) {
  const src = safeObject(body);
  const header = safeObject(src.header);
  const headerType = safeString(header.event_type || src.event_type);
  if (headerType) return headerType;

  const bodyType = safeString(src.type).toLowerCase();
  if (bodyType === 'url_verification') return 'url_verification';
  if (bodyType === 'event_callback') {
    const event = safeObject(src.event);
    if (event.message && event.sender) return 'im.message.receive_v1';
    if (event.action && event.operator) return 'card.action.trigger';
  }
  return bodyType;
}

function extractVerificationToken(body = {}) {
  const src = safeObject(body);
  return safeString(src.token || src.header?.token);
}

export function compileFeishuTextCommand(input) {
  const text = stripLeadingFeishuMentions(input);
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
  if (/^deploy\s+plan$/i.test(text)) {
    return command('deploy.plan');
  }

  const grantApprove = text.match(/^grant\s+approve\s+([A-Za-z0-9._:-]+)(?:\s+(.+))?$/i);
  if (grantApprove) {
    const noteRaw = safeString(grantApprove[2]).replace(/^(?:note|because)\s+/i, '');
    return command('grant.approve', {
      pending_grant: {
        grant_request_id: grantApprove[1],
        status: 'pending',
      },
      note: normalizeGrantOperatorNote(noteRaw),
    });
  }

  const grantReject = text.match(/^grant\s+(reject|deny)\s+([A-Za-z0-9._:-]+)(?:\s+(.+))?$/i);
  if (grantReject) {
    const noteRaw = safeString(grantReject[3]).replace(/^(?:reason|because|note)\s+/i, '');
    return command('grant.reject', {
      pending_grant: {
        grant_request_id: grantReject[2],
        status: 'pending',
      },
      note: normalizeGrantOperatorNote(noteRaw),
    });
  }

  return null;
}

export function normalizeFeishuWebhookRequest({
  headers = {},
  raw_body = '',
  content_type = '',
  verification_token = '',
} = {}) {
  const contentType = safeString(content_type || headers['content-type']).toLowerCase();
  if (!contentType.includes('application/json')) {
    return {
      ok: false,
      deny_code: 'content_type_unsupported',
      token_valid: false,
    };
  }

  const verificationToken = safeString(verification_token);
  if (!verificationToken) {
    return {
      ok: false,
      deny_code: 'verification_token_missing',
      token_valid: false,
    };
  }

  let body;
  try {
    body = JSON.parse(String(raw_body || '{}'));
  } catch {
    return {
      ok: false,
      deny_code: 'payload_invalid',
      token_valid: false,
    };
  }

  if (safeString(body.encrypt)) {
    return {
      ok: false,
      deny_code: 'payload_encrypted_unsupported',
      token_valid: false,
    };
  }

  const payloadToken = extractVerificationToken(body);
  if (!payloadToken) {
    return {
      ok: false,
      deny_code: 'verification_token_missing_in_payload',
      token_valid: false,
    };
  }
  if (payloadToken !== verificationToken) {
    return {
      ok: false,
      deny_code: 'verification_token_invalid',
      token_valid: false,
    };
  }

  const eventType = extractFeishuEventType(body);
  if (eventType === 'url_verification') {
    return {
      ok: true,
      envelope_type: 'url_verification',
      challenge: safeString(body.challenge),
      replay_key: safeString(body.challenge || body.uuid || sha256Hex(raw_body).slice(0, 24)),
      token_valid: true,
    };
  }

  const header = safeObject(body.header);
  const event = safeObject(body.event);
  if (eventType === 'card.action.trigger') {
    const interactive = compileFeishuCardAction(body);
    if (!interactive.ok) {
      return {
        ...interactive,
        token_valid: true,
      };
    }
    return {
      ...interactive,
      envelope_type: 'interactive',
      event_id: safeString(header.event_id || interactive.request_id),
      replay_key: safeString(header.event_id || interactive.request_id || sha256Hex(raw_body).slice(0, 24)),
      token_valid: true,
      signature_valid: true,
    };
  }

  if (eventType !== 'im.message.receive_v1') {
    return {
      ok: false,
      deny_code: 'event_type_unsupported',
      token_valid: true,
    };
  }

  const message = safeObject(event.message);
  const sender = safeObject(event.sender);
  const senderId = safeObject(sender.sender_id);
  const actorId = safeString(senderId.open_id || senderId.user_id || senderId.union_id);
  const tenantKey = safeString(sender.tenant_key || header.tenant_key || body.tenant_key);
  const conversationId = safeString(message.chat_id || actorId);
  const channel_scope = normalizeFeishuChannelScope(message.chat_type, conversationId);
  const messageId = safeString(message.message_id || header.event_id);
  const text = parseFeishuMessageText(message.content, message.message_type);
  const messageType = safeString(message.message_type).toLowerCase();

  return {
    ok: true,
    envelope_type: 'event_callback',
    event_id: safeString(header.event_id || messageId),
    replay_key: safeString(header.event_id || messageId || sha256Hex(raw_body).slice(0, 24)),
    token_valid: true,
    signature_valid: true,
    actor: {
      provider: 'feishu',
      external_user_id: actorId,
      external_tenant_id: tenantKey,
    },
    channel: {
      provider: 'feishu',
      account_id: tenantKey,
      conversation_id: conversationId,
      thread_key: messageId,
      channel_scope,
    },
    ingress_event: {
      ingress_type: 'message',
      channel_scope,
      sender_id: actorId,
      channel_id: conversationId,
      message_id: messageId,
      event_sequence: safeInt(header.create_time || body.ts, 0),
      source_id: safeString(`feishu:${conversationId}`),
      signature_valid: true,
      replay_detected: false,
    },
    text,
    structured_action: messageType === 'text'
      ? compileFeishuTextCommand(text)
      : null,
    raw_event_type: eventType,
  };
}
