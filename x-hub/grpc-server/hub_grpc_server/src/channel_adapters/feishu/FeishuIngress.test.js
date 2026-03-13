import assert from 'node:assert/strict';

import {
  compileFeishuTextCommand,
  normalizeFeishuWebhookRequest,
} from './FeishuIngress.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('FeishuIngress normalizes verified message callbacks into project-thread aware envelopes', () => {
  const payload = {
    schema: '2.0',
    header: {
      event_id: 'feishu-evt-1',
      event_type: 'im.message.receive_v1',
      create_time: '1710000000123',
      tenant_key: 'tenant-ops',
      token: 'verify-token-1',
    },
    event: {
      sender: {
        sender_id: {
          open_id: 'ou_user_1',
        },
      },
      message: {
        message_id: 'om_1',
        thread_id: 'omt_1',
        chat_id: 'oc_room_1',
        chat_type: 'group',
        message_type: 'text',
        content: JSON.stringify({
          text: '<at user_id="ou_bot">XHub</at> deploy plan',
        }),
      },
    },
  };

  const out = normalizeFeishuWebhookRequest({
    headers: {
      'content-type': 'application/json; charset=utf-8',
    },
    raw_body: JSON.stringify(payload),
    verification_token: 'verify-token-1',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.envelope_type || ''), 'event_callback');
  assert.equal(String(out.actor?.external_user_id || ''), 'ou_user_1');
  assert.equal(String(out.channel?.account_id || ''), 'tenant-ops');
  assert.equal(String(out.channel?.conversation_id || ''), 'oc_room_1');
  assert.equal(String(out.channel?.thread_key || ''), 'om_1');
  assert.equal(String(out.channel?.channel_scope || ''), 'group');
  assert.equal(String(out.ingress_event?.message_id || ''), 'om_1');
  assert.equal(String(out.structured_action?.action_name || ''), 'deploy.plan');
});

run('FeishuIngress normalizes card callbacks into structured interactive actions', () => {
  const payload = {
    schema: '2.0',
    header: {
      event_id: 'feishu-card-1',
      event_type: 'card.action.trigger',
      tenant_key: 'tenant-ops',
      token: 'verify-token-2',
    },
    event: {
      operator: {
        operator_id: {
          open_id: 'ou_approver_1',
        },
      },
      token: 'card-trigger-1',
      action: {
        value: {
          audit_ref: 'audit-feishu-grant-1',
          action_name: 'grant.approve',
          binding_id: 'binding-feishu-1',
          scope_type: 'project',
          scope_id: 'payments-prod',
          pending_grant_request_id: 'grant_req_1',
          pending_grant_project_id: 'payments-prod',
          note: 'approved via feishu card',
        },
      },
      context: {
        open_chat_id: 'oc_room_approve',
        open_message_id: 'om_card_1',
        chat_type: 'group',
      },
    },
  };

  const out = normalizeFeishuWebhookRequest({
    headers: {
      'content-type': 'application/json',
    },
    raw_body: JSON.stringify(payload),
    verification_token: 'verify-token-2',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.envelope_type || ''), 'interactive');
  assert.equal(String(out.audit_ref || ''), 'audit-feishu-grant-1');
  assert.equal(String(out.channel?.conversation_id || ''), 'oc_room_approve');
  assert.equal(String(out.action?.action_name || ''), 'grant.approve');
  assert.equal(String(out.action?.pending_grant?.grant_request_id || ''), 'grant_req_1');
});

run('FeishuIngress validates verification token and compiles only supported text commands', () => {
  const compiled = compileFeishuTextCommand('grant approve gr_123 note reviewed by alice');
  assert.equal(String(compiled?.action_name || ''), 'grant.approve');
  assert.equal(String(compiled?.pending_grant?.grant_request_id || ''), 'gr_123');
  assert.equal(String(compiled?.note || ''), 'reviewed by alice');
  assert.equal(compileFeishuTextCommand('deploy execute'), null);

  const payload = {
    type: 'url_verification',
    challenge: 'challenge-feishu',
    token: 'wrong-token',
  };
  const out = normalizeFeishuWebhookRequest({
    headers: {
      'content-type': 'application/json',
    },
    raw_body: JSON.stringify(payload),
    verification_token: 'verify-token-3',
  });
  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'verification_token_invalid');
});

run('FeishuIngress returns url verification challenge for verified setup probes', () => {
  const payload = {
    type: 'url_verification',
    challenge: 'challenge-feishu',
    token: 'verify-token-4',
  };
  const out = normalizeFeishuWebhookRequest({
    headers: {
      'content-type': 'application/json',
    },
    raw_body: JSON.stringify(payload),
    verification_token: 'verify-token-4',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.envelope_type || ''), 'url_verification');
  assert.equal(String(out.challenge || ''), 'challenge-feishu');
});
