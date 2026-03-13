import assert from 'node:assert/strict';
import crypto from 'node:crypto';

import {
  compileWhatsAppCloudTextCommand,
  normalizeWhatsAppCloudWebhookRequest,
} from './WhatsAppCloudIngress.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function sign(body, secret) {
  return `sha256=${crypto.createHmac('sha256', secret).update(String(body), 'utf8').digest('hex')}`;
}

run('WhatsAppCloudIngress compiles governed text commands', () => {
  const status = compileWhatsAppCloudTextCommand('status');
  const deploy = compileWhatsAppCloudTextCommand('deploy plan');
  const grant = compileWhatsAppCloudTextCommand('grant approve gr-1 project project_alpha note release ready');

  assert.equal(String(status?.action_name || ''), 'supervisor.status.get');
  assert.equal(String(deploy?.action_name || ''), 'deploy.plan');
  assert.equal(String(grant?.action_name || ''), 'grant.approve');
  assert.equal(String(grant?.pending_grant?.grant_request_id || ''), 'gr-1');
  assert.equal(String(grant?.pending_grant?.project_id || ''), 'project_alpha');
});

run('WhatsAppCloudIngress normalizes verified text messages into operator envelopes', () => {
  const rawBody = JSON.stringify({
    object: 'whatsapp_business_account',
    entry: [{
      id: 'waba-1',
      changes: [{
        field: 'messages',
        value: {
          metadata: {
            phone_number_id: 'phone-number-id-1',
          },
          messages: [{
            from: '15551234567',
            id: 'wamid.1',
            type: 'text',
            text: {
              body: 'status',
            },
          }],
        },
      }],
    }],
  });

  const out = normalizeWhatsAppCloudWebhookRequest({
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'x-hub-signature-256': sign(rawBody, 'app-secret-1'),
    },
    raw_body: rawBody,
    content_type: 'application/json; charset=utf-8',
    app_secret: 'app-secret-1',
    account_id: 'ops_whatsapp_cloud',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.actor?.external_user_id || ''), '15551234567');
  assert.equal(String(out.channel?.account_id || ''), 'ops_whatsapp_cloud');
  assert.equal(String(out.channel?.conversation_id || ''), '15551234567');
  assert.equal(String(out.channel?.thread_key || ''), 'wamid.1');
  assert.equal(String(out.structured_action?.action_name || ''), 'supervisor.status.get');
});

run('WhatsAppCloudIngress accepts status-only webhooks and keeps them non-command', () => {
  const rawBody = JSON.stringify({
    object: 'whatsapp_business_account',
    entry: [{
      id: 'waba-1',
      changes: [{
        field: 'messages',
        value: {
          metadata: {
            phone_number_id: 'phone-number-id-1',
          },
          statuses: [{
            id: 'wamid.outbound.1',
            recipient_id: '15551234567',
            status: 'delivered',
          }],
        },
      }],
    }],
  });

  const out = normalizeWhatsAppCloudWebhookRequest({
    headers: {
      'content-type': 'application/json',
      'x-hub-signature-256': sign(rawBody, 'app-secret-1'),
    },
    raw_body: rawBody,
    content_type: 'application/json',
    app_secret: 'app-secret-1',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.envelope_type || ''), 'messages');
  assert.equal(out.structured_action, null);
});

run('WhatsAppCloudIngress rejects invalid signatures fail-closed', () => {
  const rawBody = JSON.stringify({
    object: 'whatsapp_business_account',
    entry: [],
  });

  const out = normalizeWhatsAppCloudWebhookRequest({
    headers: {
      'content-type': 'application/json',
      'x-hub-signature-256': 'sha256=wrong',
    },
    raw_body: rawBody,
    content_type: 'application/json',
    app_secret: 'app-secret-1',
  });

  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'signature_invalid');
});
