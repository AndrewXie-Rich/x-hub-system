import crypto from 'node:crypto';

import { normalizeHubChannelIngressEnvelope } from '../../channel_ingress_envelope.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function getHeader(headers, key) {
  const wanted = safeString(key).toLowerCase();
  if (!wanted || !headers || typeof headers !== 'object') return '';
  for (const [rawKey, rawValue] of Object.entries(headers)) {
    if (safeString(rawKey).toLowerCase() !== wanted) continue;
    if (Array.isArray(rawValue)) return safeString(rawValue[0]);
    return safeString(rawValue);
  }
  return '';
}

function safeEqualText(a, b) {
  const left = Buffer.from(String(a || ''), 'utf8');
  const right = Buffer.from(String(b || ''), 'utf8');
  if (left.length !== right.length || left.length <= 0) return false;
  try {
    return crypto.timingSafeEqual(left, right);
  } catch {
    return false;
  }
}

function sha256Hex(input) {
  return crypto.createHash('sha256').update(String(input || ''), 'utf8').digest('hex');
}

function normalizeSlackChannelScope(channelType, channelId) {
  const type = safeString(channelType).toLowerCase();
  const channel = safeString(channelId);
  if (type === 'im' || channel.startsWith('D')) return 'dm';
  return 'group';
}

function normalizeSlackThreadKey(threadTs, messageTs) {
  return safeString(threadTs || messageTs);
}

function normalizeSlackText(input) {
  return safeString(input).replace(/\s+/g, ' ').trim();
}

function stripLeadingSlackMentions(text) {
  return normalizeSlackText(text).replace(/^(<@[^>]+>\s*)+/g, '').trim();
}

function command(action_name, extras = {}) {
  return {
    action_name,
    ...extras,
  };
}

function normalizeGrantOperatorNote(input) {
  const text = normalizeSlackText(input);
  return text ? text.slice(0, 500) : '';
}

export function compileSlackTextCommand(input) {
  const text = stripLeadingSlackMentions(input);
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
  if (/^(xt|device)\s+permissions?$/i.test(text) || /^permissions?$/i.test(text)) {
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
    const reasonRaw = safeString(grantReject[3]).replace(/^(?:reason|because|note)\s+/i, '');
    return command('grant.reject', {
      pending_grant: {
        grant_request_id: grantReject[2],
        status: 'pending',
      },
      note: normalizeGrantOperatorNote(reasonRaw),
    });
  }

  return null;
}

export function computeSlackSignature({
  signing_secret = '',
  timestamp_sec = 0,
  raw_body = '',
} = {}) {
  const secret = safeString(signing_secret);
  const ts = safeInt(timestamp_sec, 0);
  const base = `v0:${ts}:${String(raw_body || '')}`;
  const digest = crypto.createHmac('sha256', secret).update(base, 'utf8').digest('hex');
  return `v0=${digest}`;
}

export function verifySlackRequestSignature({
  signing_secret = '',
  headers = {},
  raw_body = '',
  now_ms = Date.now(),
  tolerance_sec = 300,
} = {}) {
  const secret = safeString(signing_secret);
  if (!secret) {
    return {
      ok: false,
      deny_code: 'signing_secret_missing',
      signature_valid: false,
    };
  }

  const timestampRaw = getHeader(headers, 'x-slack-request-timestamp');
  const signature = getHeader(headers, 'x-slack-signature');
  const timestamp_sec = safeInt(timestampRaw, 0);
  if (!timestamp_sec) {
    return {
      ok: false,
      deny_code: 'signature_timestamp_missing',
      signature_valid: false,
    };
  }
  if (!signature) {
    return {
      ok: false,
      deny_code: 'signature_missing',
      signature_valid: false,
    };
  }

  const nowSec = Math.max(0, Math.trunc(Number(now_ms || Date.now()) / 1000));
  const tolerance = Math.max(30, safeInt(tolerance_sec, 300));
  if (Math.abs(nowSec - timestamp_sec) > tolerance) {
    return {
      ok: false,
      deny_code: 'request_timestamp_out_of_range',
      signature_valid: false,
      timestamp_sec,
    };
  }

  const expected = computeSlackSignature({
    signing_secret: secret,
    timestamp_sec,
    raw_body,
  });
  const valid = safeEqualText(signature, expected);
  return {
    ok: valid,
    deny_code: valid ? '' : 'signature_invalid',
    signature_valid: valid,
    timestamp_sec,
  };
}

export function parseSlackWebhookBody({
  raw_body = '',
  content_type = '',
  headers = {},
} = {}) {
  const bodyText = String(raw_body || '');
  const contentType = safeString(content_type || getHeader(headers, 'content-type')).toLowerCase();

  if (contentType.includes('application/x-www-form-urlencoded')) {
    const params = new URLSearchParams(bodyText);
    const payloadText = safeString(params.get('payload'));
    if (payloadText) {
      return {
        ok: true,
        body_kind: 'form_payload_json',
        body: JSON.parse(payloadText),
      };
    }
    const body = {};
    for (const [key, value] of params.entries()) {
      body[key] = value;
    }
    return {
      ok: true,
      body_kind: 'form_fields',
      body,
    };
  }

  return {
    ok: true,
    body_kind: 'json',
    body: JSON.parse(bodyText || '{}'),
  };
}

function eventToIngressType(event = {}) {
  const type = safeString(event.type).toLowerCase();
  if (type === 'reaction_added' || type === 'reaction_removed') return 'reaction';
  if (type === 'pin_added' || type === 'pin_removed') return 'pin';
  if (type === 'member_joined_channel' || type === 'member_left_channel') return 'member';
  return 'message';
}

function allowSlackMessageEvent(event = {}) {
  const subtype = safeString(event.subtype).toLowerCase();
  if (!subtype) return true;
  return false;
}

function normalizeSlackInteractiveRequest(body = {}, base = {}) {
  const action = Array.isArray(body.actions) ? body.actions[0] : null;
  const teamId = safeString(body.team?.id || body.team?.enterprise_id || base.team_id);
  const channelId = safeString(body.channel?.id || body.container?.channel_id);
  const threadKey = normalizeSlackThreadKey(
    body.container?.thread_ts || body.message?.thread_ts,
    body.message?.ts
  );
  return normalizeHubChannelIngressEnvelope({
    ok: true,
    envelope_type: 'interactive',
    event_id: safeString(body.trigger_id || action?.action_ts || body.container?.message_ts),
    replay_key: safeString(body.trigger_id || action?.action_ts || body.container?.message_ts || sha256Hex(JSON.stringify(body)).slice(0, 24)),
    signature_valid: base.signature_valid === true,
    actor: {
      provider: 'slack',
      external_user_id: safeString(body.user?.id),
      external_tenant_id: teamId,
    },
    channel: {
      provider: 'slack',
      account_id: teamId,
      conversation_id: channelId,
      thread_key: threadKey,
      channel_scope: normalizeSlackChannelScope(body.channel?.name || '', channelId),
    },
    source_id: safeString(`slack:${channelId}`),
  }, {
    provider: 'slack',
  });
}

function normalizeSlackEventEnvelope(body = {}, base = {}) {
  if (safeString(body.type).toLowerCase() === 'url_verification') {
    return normalizeHubChannelIngressEnvelope({
      ok: true,
      envelope_type: 'url_verification',
      challenge: safeString(body.challenge),
      replay_key: safeString(body.challenge || sha256Hex(JSON.stringify(body)).slice(0, 24)),
      signature_valid: base.signature_valid === true,
    }, {
      provider: 'slack',
    });
  }

  if (safeString(body.type).toLowerCase() !== 'event_callback') {
    return {
      ok: false,
      deny_code: 'event_type_unsupported',
    };
  }

  const event = body.event && typeof body.event === 'object' ? body.event : {};
  if (!safeString(event.type)) {
    return {
      ok: false,
      deny_code: 'event_missing',
    };
  }
  if (safeString(event.type).toLowerCase() === 'message' && !allowSlackMessageEvent(event)) {
    return {
      ok: false,
      deny_code: 'message_subtype_unsupported',
    };
  }

  const teamId = safeString(body.team_id || body.authorizations?.[0]?.team_id);
  const channelId = safeString(event.channel || event.item?.channel);
  const actorId = safeString(event.user || event.item_user || event.user_id);
  const messageId = safeString(event.client_msg_id || event.event_ts || event.ts || body.event_id);
  const threadKey = normalizeSlackThreadKey(event.thread_ts, event.ts);
  const channel_scope = normalizeSlackChannelScope(event.channel_type, channelId);
  const text = safeString(event.text);
  const structured_action = eventToIngressType(event) === 'message'
    ? compileSlackTextCommand(text)
    : null;

  return normalizeHubChannelIngressEnvelope({
    ok: true,
    envelope_type: 'event_callback',
    event_id: safeString(body.event_id || messageId),
    replay_key: safeString(body.event_id || messageId || sha256Hex(JSON.stringify(body)).slice(0, 24)),
    signature_valid: base.signature_valid === true,
    actor: {
      provider: 'slack',
      external_user_id: actorId,
      external_tenant_id: teamId,
    },
    channel: {
      provider: 'slack',
      account_id: teamId,
      conversation_id: channelId,
      thread_key: threadKey,
      channel_scope,
    },
    ingress_event: {
      ingress_type: eventToIngressType(event),
      channel_scope,
      sender_id: actorId,
      channel_id: channelId,
      message_id: messageId,
      event_sequence: safeInt(body.event_time, 0),
      source_id: safeString(`slack:${channelId}`),
      signature_valid: base.signature_valid === true,
      replay_detected: false,
    },
    text,
    structured_action,
  }, {
    provider: 'slack',
  });
}

export function normalizeSlackWebhookRequest({
  headers = {},
  raw_body = '',
  content_type = '',
  signing_secret = '',
  now_ms = Date.now(),
} = {}) {
  const signature = verifySlackRequestSignature({
    signing_secret,
    headers,
    raw_body,
    now_ms,
  });
  if (!signature.ok) {
    return {
      ok: false,
      deny_code: signature.deny_code,
      signature_valid: false,
    };
  }

  let parsed;
  try {
    parsed = parseSlackWebhookBody({
      raw_body,
      content_type,
      headers,
    });
  } catch {
    return {
      ok: false,
      deny_code: 'payload_invalid',
      signature_valid: true,
    };
  }

  const body = parsed?.body && typeof parsed.body === 'object' ? parsed.body : {};
  const bodyType = safeString(body.type).toLowerCase();
  const base = {
    signature_valid: true,
    timestamp_sec: signature.timestamp_sec,
  };

  if (bodyType === 'url_verification' || bodyType === 'event_callback') {
    return normalizeSlackEventEnvelope(body, base);
  }
  if (bodyType === 'block_actions' || bodyType === 'view_submission' || bodyType === 'shortcut') {
    return normalizeSlackInteractiveRequest(body, base);
  }

  return {
    ok: false,
    deny_code: 'payload_type_unsupported',
    signature_valid: true,
  };
}
