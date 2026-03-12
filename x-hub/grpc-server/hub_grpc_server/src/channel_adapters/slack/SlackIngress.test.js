import assert from 'node:assert/strict';

import {
  compileSlackTextCommand,
  computeSlackSignature,
  normalizeSlackWebhookRequest,
} from './SlackIngress.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeSignedHeaders({ signing_secret, raw_body, timestamp_sec }) {
  return {
    'content-type': 'application/json; charset=utf-8',
    'x-slack-request-timestamp': String(timestamp_sec),
    'x-slack-signature': computeSlackSignature({
      signing_secret,
      timestamp_sec,
      raw_body,
    }),
  };
}

run('SlackIngress normalizes signed event callback into project-thread aware envelope', () => {
  const signing_secret = 'slack-signing-secret';
  const payload = {
    type: 'event_callback',
    team_id: 'T001',
    event_id: 'Ev001',
    event_time: 1710000000,
    event: {
      type: 'message',
      user: 'U123',
      channel: 'C456',
      channel_type: 'channel',
      text: 'status',
      ts: '1710000000.1234',
      thread_ts: '1710000000.0001',
      client_msg_id: 'msg-1',
    },
  };
  const raw_body = JSON.stringify(payload);
  const timestamp_sec = 1710000005;

  const out = normalizeSlackWebhookRequest({
    headers: makeSignedHeaders({ signing_secret, raw_body, timestamp_sec }),
    raw_body,
    signing_secret,
    now_ms: timestamp_sec * 1000,
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.envelope_type || ''), 'event_callback');
  assert.equal(String(out.actor?.external_user_id || ''), 'U123');
  assert.equal(String(out.channel?.account_id || ''), 'T001');
  assert.equal(String(out.channel?.conversation_id || ''), 'C456');
  assert.equal(String(out.channel?.thread_key || ''), '1710000000.0001');
  assert.equal(String(out.channel?.channel_scope || ''), 'group');
  assert.equal(String(out.ingress_event?.message_id || ''), 'msg-1');
  assert.equal(String(out.structured_action?.action_name || ''), 'supervisor.status.get');
});

run('SlackIngress validates interactive form payloads and DM thread fallback', () => {
  const signing_secret = 'slack-signing-secret';
  const payload = {
    type: 'block_actions',
    team: { id: 'T001' },
    user: { id: 'U123' },
    channel: { id: 'D456' },
    container: { channel_id: 'D456', message_ts: '1710000001.0002' },
    message: { ts: '1710000001.0002' },
    actions: [{ action_id: 'xt.supervisor.status', action_ts: '1710000002.0003' }],
    trigger_id: '1337.42.abcd',
  };
  const raw_body = `payload=${encodeURIComponent(JSON.stringify(payload))}`;
  const timestamp_sec = 1710000005;

  const out = normalizeSlackWebhookRequest({
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      'x-slack-request-timestamp': String(timestamp_sec),
      'x-slack-signature': computeSlackSignature({
        signing_secret,
        timestamp_sec,
        raw_body,
      }),
    },
    raw_body,
    content_type: 'application/x-www-form-urlencoded',
    signing_secret,
    now_ms: timestamp_sec * 1000,
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.envelope_type || ''), 'interactive');
  assert.equal(String(out.channel?.channel_scope || ''), 'dm');
  assert.equal(String(out.channel?.thread_key || ''), '1710000001.0002');
});

run('SlackIngress rejects invalid signatures and compiles supported text commands only', () => {
  const compiled = compileSlackTextCommand('grant approve gr_123');
  assert.equal(String(compiled?.action_name || ''), 'grant.approve');
  assert.equal(String(compiled?.pending_grant?.grant_request_id || ''), 'gr_123');
  assert.equal(String(compiled?.note || ''), '');
  const approveWithNote = compileSlackTextCommand('grant approve gr_123 note reviewed by alice');
  assert.equal(String(approveWithNote?.note || ''), 'reviewed by alice');
  const rejectWithReason = compileSlackTextCommand('grant reject gr_456 because outside change window');
  assert.equal(String(rejectWithReason?.action_name || ''), 'grant.reject');
  assert.equal(String(rejectWithReason?.note || ''), 'outside change window');
  assert.equal(compileSlackTextCommand('continue deploy'), null);

  const payload = { type: 'url_verification', challenge: 'xyz' };
  const raw_body = JSON.stringify(payload);
  const out = normalizeSlackWebhookRequest({
    headers: {
      'content-type': 'application/json',
      'x-slack-request-timestamp': '1710000005',
      'x-slack-signature': 'v0=invalid',
    },
    raw_body,
    signing_secret: 'slack-signing-secret',
    now_ms: 1710000005000,
  });
  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'signature_invalid');
});
