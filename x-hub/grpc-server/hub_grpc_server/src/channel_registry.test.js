import assert from 'node:assert/strict';

import {
  HUB_CHANNEL_OPENCLAW_REUSE_MAP,
  explainChannelProviderInput,
  getChannelProviderMeta,
  listChannelProviders,
  normalizeChannelProviderId,
} from './channel_registry.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('XT-W3-24-G/channel registry normalizes aliases to a single provider id', () => {
  assert.equal(normalizeChannelProviderId('Slack'), 'slack');
  assert.equal(normalizeChannelProviderId('telegram_bot'), 'telegram');
  assert.equal(normalizeChannelProviderId('tg'), 'telegram');
  assert.equal(normalizeChannelProviderId('lark'), 'feishu');
  assert.equal(normalizeChannelProviderId('whatsapp_cloud_api'), 'whatsapp_cloud_api');
  assert.equal(normalizeChannelProviderId('whatsapp cloud api'), 'whatsapp_cloud_api');
});

run('XT-W3-24-G/channel registry keeps whatsapp generic alias ambiguous and fail-closed', () => {
  assert.equal(normalizeChannelProviderId('whatsapp'), null);
  assert.equal(normalizeChannelProviderId('wa'), null);
  const explained = explainChannelProviderInput('whatsapp');
  assert.equal(!!explained.ok, false);
  assert.equal(!!explained.ambiguous, true);
  assert.equal(String(explained.reason || ''), 'provider_alias_ambiguous');
});

run('XT-W3-24-G/channel registry exposes frozen provider metadata and reuse map', () => {
  const providers = listChannelProviders();
  assert.equal(providers.length, 5);
  const feishu = getChannelProviderMeta('feishu');
  assert.equal(String(feishu?.approval_surface || ''), 'card');
  assert.equal(Array.isArray(feishu?.capabilities), true);
  assert.equal(String(HUB_CHANNEL_OPENCLAW_REUSE_MAP.registry.reuse_class || ''), 'direct_logic');
  assert.equal(String(HUB_CHANNEL_OPENCLAW_REUSE_MAP.xt_runtime_tokens.reuse_class || ''), 'forbidden');
});
