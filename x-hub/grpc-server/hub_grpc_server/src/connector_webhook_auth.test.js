import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import { verifyConnectorWebhook } from './connector_webhook_auth.js';
import { createPreauthSurfaceGuard, createWebhookReplayGuard, effectivePeerIpForPairingSourcePolicy } from './pairing_http.js';

const secret = 'test-only-webhook-signing-secret-at-least-32';
const nowMs = 1_800_000_000_000;
function signedRequest(overrides = {}) {
  const rawBody = Buffer.from('{"message":"你好"}');
  const timestamp = String(nowMs / 1000);
  const pathname = '/webhook/connectors/slack/channel';
  const replayKey = 'event-1';
  const signature = crypto.createHmac('sha256', secret)
    .update(`v1\n${timestamp}\nPOST\n${pathname}\n${replayKey}\n`).update(rawBody).digest('hex');
  return {
    connector: 'slack', targetId: 'channel', pathname, rawBody, body: JSON.parse(rawBody), nowMs,
    headers: { 'x-hub-timestamp': timestamp, 'x-replay-key': replayKey, 'x-hub-signature': `v1=${signature}` },
    env: { HUB_CONNECTOR_WEBHOOK_KEYS_JSON: JSON.stringify({ 'slack:channel': secret, 'slack:other': secret }) },
    ...overrides,
  };
}

test('webhook authentication binds the raw bytes, route, timestamp and replay id', () => {
  const request = signedRequest();
  assert.equal(verifyConnectorWebhook(request).ok, true);
  for (const change of [
    { rawBody: Buffer.from('{"message": "你好"}') },
    { pathname: '/webhook/connectors/slack/other', targetId: 'other' },
    { headers: { ...request.headers, 'x-replay-key': 'event-2' } },
    { headers: { ...request.headers, 'x-hub-signature': `v1=${'0'.repeat(64)}` } },
    { headers: { ...request.headers, 'x-hub-timestamp': String(nowMs / 1000 + 1) } },
    { nowMs: nowMs + 300_001 },
    { nowMs: nowMs - 300_001 },
    { headers: {}, body: { signature_valid: true } },
    { env: {} },
    { env: { HUB_CONNECTOR_WEBHOOK_KEYS_JSON: 'invalid-json' } },
    { env: { HUB_CONNECTOR_WEBHOOK_KEYS_JSON: '{"slack:channel":"short"}' } },
    { body: { source_id: 'slack:other' } },
    { body: { payload: { source_id: 'slack:other' } } },
    { body: { signature_valid: false } },
  ]) assert.equal(verifyConnectorWebhook({ ...request, ...change }).ok, false, JSON.stringify(Object.keys(change)));
});

test('untrusted forwarding headers do not control source identity', () => {
  assert.equal(effectivePeerIpForPairingSourcePolicy({ peer_ip: '127.0.0.1', forwarded_for: '192.0.2.10', env: {} }), '127.0.0.1');
  const env = { HUB_PAIRING_TRUSTED_PROXY_CIDRS: '127.0.0.1/32,10.0.0.1/32' };
  assert.equal(effectivePeerIpForPairingSourcePolicy({ peer_ip: '127.0.0.1', forwarded_for: 'spoof,192.0.2.10', env }), '');
  assert.equal(effectivePeerIpForPairingSourcePolicy({ peer_ip: '127.0.0.1', forwarded_for: '192.0.2.99,192.0.2.10,10.0.0.1', env }), '192.0.2.10');
  assert.equal(effectivePeerIpForPairingSourcePolicy({ peer_ip: '127.0.0.1', forwarded_for: 'spoof,192.0.2.10', env: { ...env, HUB_PAIRING_TRUSTED_PROXY_CIDRS: '127.0.0.1/32' } }), '');
  assert.equal(effectivePeerIpForPairingSourcePolicy({ peer_ip: '192.0.2.10', forwarded_for: '127.0.0.1', env }), '192.0.2.10');
  assert.equal(effectivePeerIpForPairingSourcePolicy({ peer_ip: '::ffff:127.0.0.1', env }), '127.0.0.1');
  assert.equal(effectivePeerIpForPairingSourcePolicy({ peer_ip: '0:0:0:0:0:0:0:1', env }), '::1');
});

test('preauth global budget applies across different peers and resets', () => {
  const guard = createPreauthSurfaceGuard({ max_total_per_window: 2, window_ms: 1000, nowFn: () => nowMs });
  assert.equal(guard.check({ source_key: '192.0.2.1' }).ok, true);
  assert.equal(guard.check({ source_key: '192.0.2.2' }).ok, true);
  assert.equal(guard.check({ source_key: '192.0.2.3' }).deny_code, 'preauth_global_rate_limited');
  assert.equal(guard.check({ source_key: '192.0.2.3', now_ms: nowMs + 1001 }).ok, true);
});

test('resigning an event cannot reset its replay claim', () => {
  const guard = createWebhookReplayGuard({ nowFn: () => nowMs });
  const event = { connector: 'slack', target_id: 'channel', replay_key: 'event-1' };
  assert.equal(guard.claim({ ...event, signature: 'original' }).ok, true);
  assert.equal(guard.claim({ ...event, signature: 'new-timestamp-signature' }).deny_code, 'replay_detected');
});
