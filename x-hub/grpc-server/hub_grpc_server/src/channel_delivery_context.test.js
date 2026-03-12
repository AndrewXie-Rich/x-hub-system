import assert from 'node:assert/strict';

import {
  channelDeliveryContextFromSession,
  channelDeliveryContextKey,
  mergeChannelDeliveryContext,
  normalizeChannelDeliveryContext,
  normalizeChannelSessionDeliveryFields,
} from './channel_delivery_context.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('XT-W3-24-G/delivery context normalizes provider aliases and preserves provider-native thread keys', () => {
  const slack = normalizeChannelDeliveryContext({
    provider: 'Slack',
    conversation_id: 'C123',
    account_id: 'ops_bot',
    thread_key: '1741770000.12345',
  });
  const telegram = normalizeChannelDeliveryContext({
    provider: 'tg',
    conversation_id: '-1001234567890',
    thread_key: 'topic:42',
  });

  assert.deepEqual(slack, {
    provider: 'slack',
    conversation_id: 'C123',
    account_id: 'ops_bot',
    thread_key: '1741770000.12345',
  });
  assert.deepEqual(telegram, {
    provider: 'telegram',
    conversation_id: '-1001234567890',
    account_id: undefined,
    thread_key: 'topic:42',
  });
  assert.equal(channelDeliveryContextKey(slack), 'slack|C123|ops_bot|1741770000.12345');
  assert.equal(channelDeliveryContextKey(telegram), 'telegram|-1001234567890||topic:42');
});

run('XT-W3-24-G/delivery context never mixes route fields across providers', () => {
  const merged = mergeChannelDeliveryContext(
    {
      provider: 'feishu',
      conversation_id: 'oc_room_1',
    },
    {
      provider: 'slack',
      conversation_id: 'C123',
      thread_key: '1741770000.12345',
      account_id: 'ops_bot',
    }
  );
  assert.deepEqual(merged, {
    provider: 'feishu',
    conversation_id: 'oc_room_1',
    account_id: undefined,
    thread_key: undefined,
  });
});

run('XT-W3-24-G/delivery context session helpers keep last normalized route fields', () => {
  const fields = normalizeChannelSessionDeliveryFields({
    provider: 'lark',
    conversation_id: 'oc_room_9',
    delivery_context: {
      provider: 'feishu',
      conversation_id: 'oc_room_9',
      thread_key: 'thread-1',
    },
  });
  assert.deepEqual(fields.delivery_context, {
    provider: 'feishu',
    conversation_id: 'oc_room_9',
    account_id: undefined,
    thread_key: 'thread-1',
  });
  assert.equal(String(fields.last_provider || ''), 'feishu');
  assert.equal(String(fields.last_thread_key || ''), 'thread-1');

  const fromSession = channelDeliveryContextFromSession({
    provider: 'telegram',
    conversation_id: '-1001',
    origin: { thread_key: 'topic:99' },
  });
  assert.deepEqual(fromSession, {
    provider: 'telegram',
    conversation_id: '-1001',
    account_id: undefined,
    thread_key: 'topic:99',
  });
});

run('XT-W3-24-G/delivery context rejects unknown or ambiguous providers', () => {
  assert.equal(normalizeChannelDeliveryContext({ provider: 'discord', conversation_id: 'room' }), undefined);
  assert.equal(channelDeliveryContextKey({ provider: 'whatsapp', conversation_id: 'room' }), undefined);
});
