import assert from 'node:assert/strict';

import {
  createChannelIngressPrimitiveSet,
  createConnectorDeliveryReceiptCompensator,
  createConnectorTargetOrderingGuard,
  createPreauthSurfaceGuard,
  createWebhookReplayGuard,
  describeChannelIngressPrimitiveSet,
  listChannelIngressPrimitiveExports,
} from './channel_ingress_primitives.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('XT-W3-24-G/channel ingress primitives expose one shared import surface', () => {
  assert.deepEqual(listChannelIngressPrimitiveExports(), [
    'createPreauthSurfaceGuard',
    'createUnauthorizedFloodBreaker',
    'createWebhookReplayGuard',
    'createConnectorTargetOrderingGuard',
    'createConnectorDeliveryReceiptCompensator',
  ]);

  const described = describeChannelIngressPrimitiveSet(createChannelIngressPrimitiveSet({
    env: {},
  }));
  assert.deepEqual(described, {
    preauth_guard: true,
    unauthorized_flood_breaker: true,
    webhook_replay_guard: true,
    target_ordering_guard: true,
    delivery_receipt_compensator: true,
  });
});

run('XT-W3-24-G/channel ingress primitives keep preauth/replay/order/receipt smoke semantics', () => {
  let now = 1_710_000_000_000;
  const now_fn = () => now;
  const preauth = createPreauthSurfaceGuard({
    nowFn: now_fn,
    window_ms: 10_000,
    max_per_window: 1,
  });
  assert.equal(!!preauth.check({ source_key: 'slack:1' }).ok, true);
  assert.equal(String(preauth.check({ source_key: 'slack:1' }).deny_code || ''), 'rate_limited');

  const replay = createWebhookReplayGuard({
    nowFn: now_fn,
    ttl_ms: 60_000,
  });
  assert.equal(!!replay.claim({
    connector: 'slack',
    target_id: 'C123',
    replay_key: 'evt-1',
    signature: 'sig-1',
  }).ok, true);
  assert.equal(String(replay.claim({
    connector: 'slack',
    target_id: 'C123',
    replay_key: 'evt-1',
    signature: 'sig-1',
  }).deny_code || ''), 'replay_detected');

  const ordering = createConnectorTargetOrderingGuard({
    now_fn,
  });
  const begin = ordering.begin({
    connector: 'slack',
    target_id: 'C123',
    event_id: 'evt-1',
    event_sequence: 1,
    now_ms: now,
  });
  assert.equal(!!begin.ok, true);
  assert.equal(!!ordering.complete({
    connector: 'slack',
    target_id: 'C123',
    lock_token: begin.lock_token,
    success: true,
    event_id: 'evt-1',
    event_sequence: 1,
    now_ms: now,
  }).ok, true);

  const receipt = createConnectorDeliveryReceiptCompensator({
    now_fn,
  });
  const prepare = receipt.prepare({
    connector: 'slack',
    target_id: 'C123',
    idempotency_key: 'idem-1',
    event_id: 'evt-1',
    event_sequence: 1,
    now_ms: now,
  });
  assert.equal(!!prepare.ok, true);
  assert.equal(!!receipt.commit({
    connector: 'slack',
    target_id: 'C123',
    idempotency_key: 'idem-1',
    provider_receipt: 'provider:1',
    event_id: 'evt-1',
    event_sequence: 1,
    now_ms: now,
  }).ok, true);

  now += 61_000;
  assert.equal(!!replay.claim({
    connector: 'slack',
    target_id: 'C123',
    replay_key: 'evt-1',
    signature: 'sig-1',
  }).ok, true);
});
