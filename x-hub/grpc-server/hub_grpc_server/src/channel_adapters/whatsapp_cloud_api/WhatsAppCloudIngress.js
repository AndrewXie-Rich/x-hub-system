import crypto from 'node:crypto';

import { normalizeHubChannelIngressEnvelope } from '../../channel_ingress_envelope.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

function normalizeWhatsAppText(input) {
  return safeString(input).replace(/\s+/g, ' ').trim();
}

function normalizeGrantOperatorNote(input) {
  const text = normalizeWhatsAppText(input);
  return text ? text.slice(0, 500) : '';
}

function command(action_name, extras = {}) {
  return {
    action_name,
    ...extras,
  };
}

function sha256Hex(input) {
  return crypto.createHash('sha256').update(String(input || ''), 'utf8').digest('hex');
}

function verifyMetaSignature(rawBody, signatureHeader, appSecret) {
  const provided = safeString(signatureHeader);
  const secret = safeString(appSecret);
  if (!secret) {
    return {
      ok: false,
      deny_code: 'signature_secret_missing',
    };
  }
  if (!provided) {
    return {
      ok: false,
      deny_code: 'signature_missing',
    };
  }
  const expected = `sha256=${crypto.createHmac('sha256', secret).update(String(rawBody || ''), 'utf8').digest('hex')}`;
  const left = Buffer.from(provided, 'utf8');
  const right = Buffer.from(expected, 'utf8');
  if (left.length !== right.length) {
    return {
      ok: false,
      deny_code: 'signature_invalid',
    };
  }
  const valid = crypto.timingSafeEqual(left, right);
  return valid
    ? { ok: true }
    : {
        ok: false,
        deny_code: 'signature_invalid',
      };
}

function normalizeChannelAccountId(explicitAccountId, phoneNumberId) {
  return safeString(explicitAccountId || phoneNumberId);
}

function extractWhatsAppText(message = {}) {
  const msg = safeObject(message);
  const type = safeString(msg.type).toLowerCase();
  if (type === 'text') return normalizeWhatsAppText(msg.text?.body);
  if (type === 'button') return normalizeWhatsAppText(msg.button?.text);
  if (type === 'interactive') {
    return normalizeWhatsAppText(
      msg.interactive?.button_reply?.title
      || msg.interactive?.list_reply?.title
      || msg.interactive?.list_reply?.description
    );
  }
  return '';
}

export function compileWhatsAppCloudTextCommand(input) {
  const text = normalizeWhatsAppText(input);
  if (!text) return null;

  if (/^(xt|supervisor)\s+status$/i.test(text) || /^status$/i.test(text)) {
    return command('supervisor.status.get');
  }
  if (/^(xt|supervisor)\s+queue$/i.test(text) || /^queue$/i.test(text)) {
    return command('supervisor.queue.get');
  }
  if (/^deploy\s+plan$/i.test(text)) {
    return command('deploy.plan');
  }
  if (/^deploy\s+(execute|run)$/i.test(text)) {
    return command('deploy.execute');
  }
  if (/^(xt|supervisor)\s+pause$/i.test(text) || /^pause$/i.test(text)) {
    return command('supervisor.pause');
  }
  if (/^(xt|supervisor)\s+resume$/i.test(text) || /^resume$/i.test(text)) {
    return command('supervisor.resume');
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

export function normalizeWhatsAppCloudWebhookRequest({
  headers = {},
  raw_body = '',
  content_type = '',
  app_secret = '',
  account_id = '',
} = {}) {
  const contentType = safeString(content_type || headers['content-type']).toLowerCase();
  if (!contentType.includes('application/json')) {
    return {
      ok: false,
      deny_code: 'content_type_unsupported',
      token_valid: false,
      signature_valid: false,
    };
  }

  const signature = verifyMetaSignature(
    raw_body,
    headers['x-hub-signature-256'] || headers['X-Hub-Signature-256'],
    app_secret
  );
  if (!signature.ok) {
    return {
      ok: false,
      deny_code: signature.deny_code,
      token_valid: false,
      signature_valid: false,
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
      signature_valid: true,
    };
  }

  if (safeString(body.object) !== 'whatsapp_business_account') {
    return {
      ok: false,
      deny_code: 'event_type_unsupported',
      token_valid: true,
      signature_valid: true,
    };
  }

  for (const entry of safeArray(body.entry)) {
    for (const change of safeArray(entry.changes)) {
      const field = safeString(change.field);
      const value = safeObject(change.value);
      const metadata = safeObject(value.metadata);
      const phoneNumberId = safeString(metadata.phone_number_id);
      const resolvedAccountId = normalizeChannelAccountId(account_id, phoneNumberId);

      for (const message of safeArray(value.messages)) {
        const text = extractWhatsAppText(message);
        const senderId = safeString(message.from);
        const messageId = safeString(message.id);
        return normalizeHubChannelIngressEnvelope({
          ok: true,
          envelope_type: field || 'messages',
          event_id: messageId || sha256Hex(raw_body).slice(0, 24),
          replay_key: messageId || sha256Hex(raw_body).slice(0, 24),
          token_valid: true,
          signature_valid: true,
          actor: {
            provider: 'whatsapp_cloud_api',
            external_user_id: senderId,
            external_tenant_id: resolvedAccountId,
          },
          channel: {
            provider: 'whatsapp_cloud_api',
            account_id: resolvedAccountId,
            conversation_id: senderId,
            thread_key: messageId,
            channel_scope: 'dm',
          },
          ingress_event: {
            field,
            message_id: messageId,
            phone_number_id: phoneNumberId,
            message_type: safeString(message.type),
          },
          structured_action: compileWhatsAppCloudTextCommand(text),
        }, {
          provider: 'whatsapp_cloud_api',
        });
      }

      const firstStatus = safeArray(value.statuses)[0];
      if (firstStatus) {
        return normalizeHubChannelIngressEnvelope({
          ok: true,
          envelope_type: field || 'statuses',
          event_id: safeString(firstStatus.id || firstStatus.meta_msg_id || sha256Hex(raw_body).slice(0, 24)),
          replay_key: safeString(firstStatus.id || firstStatus.meta_msg_id || sha256Hex(raw_body).slice(0, 24)),
          token_valid: true,
          signature_valid: true,
          actor: {
            provider: 'whatsapp_cloud_api',
            external_user_id: safeString(firstStatus.recipient_id),
            external_tenant_id: resolvedAccountId,
          },
          channel: {
            provider: 'whatsapp_cloud_api',
            account_id: resolvedAccountId,
            conversation_id: safeString(firstStatus.recipient_id),
            thread_key: safeString(firstStatus.id || firstStatus.meta_msg_id),
            channel_scope: 'dm',
          },
          ingress_event: {
            field,
            status: safeString(firstStatus.status),
            message_id: safeString(firstStatus.id || firstStatus.meta_msg_id),
            phone_number_id: phoneNumberId,
          },
          structured_action: null,
        }, {
          provider: 'whatsapp_cloud_api',
        });
      }
    }
  }

  return {
    ok: false,
    deny_code: 'event_type_unsupported',
    token_valid: true,
    signature_valid: true,
  };
}
