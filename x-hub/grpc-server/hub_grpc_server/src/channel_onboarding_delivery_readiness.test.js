import assert from 'node:assert/strict';

import {
  createChannelOnboardingDeliveryTarget,
  getChannelOnboardingDeliveryReadiness,
  listChannelOnboardingDeliveryReadiness,
} from './channel_onboarding_delivery_readiness.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('XT-W3-24/delivery readiness reports missing Slack credentials with remediation hint', () => {
  const readiness = getChannelOnboardingDeliveryReadiness({
    provider: 'slack',
    env: {},
  });
  assert.equal(readiness.provider, 'slack');
  assert.equal(readiness.ready, false);
  assert.equal(readiness.reply_enabled, true);
  assert.equal(readiness.credentials_configured, false);
  assert.equal(readiness.deny_code, 'provider_delivery_not_configured');
  assert.equal(readiness.remediation_hint.includes('HUB_SLACK_OPERATOR_BOT_TOKEN'), true);
  assert.equal(
    (readiness.repair_hints || []).some((item) => String(item || '').includes('HUB_SLACK_OPERATOR_BOT_TOKEN')),
    true
  );
});

run('XT-W3-24/delivery readiness treats Telegram as ready when bot token is configured', () => {
  const readiness = getChannelOnboardingDeliveryReadiness({
    provider: 'telegram',
    env: {
      HUB_TELEGRAM_OPERATOR_BOT_TOKEN: 'telegram-token',
    },
  });
  assert.equal(readiness.provider, 'telegram');
  assert.equal(readiness.ready, true);
  assert.equal(readiness.reply_enabled, true);
  assert.equal(readiness.credentials_configured, true);
  assert.equal(readiness.deny_code, '');
  assert.equal(readiness.remediation_hint, '');
});

run('XT-W3-24/delivery readiness keeps Feishu blocked until reply is explicitly enabled', () => {
  const readiness = getChannelOnboardingDeliveryReadiness({
    provider: 'feishu',
    env: {
      HUB_FEISHU_OPERATOR_BOT_APP_ID: 'cli_x',
      HUB_FEISHU_OPERATOR_BOT_APP_SECRET: 'secret_x',
    },
  });
  assert.equal(readiness.provider, 'feishu');
  assert.equal(readiness.ready, false);
  assert.equal(readiness.reply_enabled, false);
  assert.equal(readiness.credentials_configured, true);
  assert.equal(readiness.deny_code, 'provider_delivery_not_configured');
  assert.equal(readiness.remediation_hint.includes('HUB_FEISHU_OPERATOR_REPLY_ENABLE=1'), true);
  assert.equal(
    (readiness.repair_hints || []).some((item) => String(item || '').includes('HUB_FEISHU_OPERATOR_REPLY_ENABLE=1')),
    true
  );
});

run('XT-W3-24/delivery target shares the same readiness semantics for WhatsApp Cloud', () => {
  const target = createChannelOnboardingDeliveryTarget({
    provider: 'whatsapp_cloud_api',
    env: {
      HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE: '1',
      HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN: 'wa-token',
      HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID: '123456',
    },
  });
  assert.equal(target.ok, true);
  assert.equal(target.readiness?.provider, 'whatsapp_cloud_api');
  assert.equal(target.readiness?.ready, true);
  assert.equal(typeof target.target?.postMessage, 'function');
});

run('XT-W3-24/delivery readiness snapshot lists all supported operator channel providers', () => {
  const readiness = listChannelOnboardingDeliveryReadiness({
    env: {
      HUB_SLACK_OPERATOR_REPLY_ENABLE: '1',
      HUB_SLACK_OPERATOR_BOT_TOKEN: 'xoxb-ready',
      HUB_TELEGRAM_OPERATOR_REPLY_ENABLE: '1',
      HUB_TELEGRAM_OPERATOR_BOT_TOKEN: 'telegram-ready',
    },
  });
  assert.deepEqual(
    readiness.map((item) => String(item.provider || '')),
    ['slack', 'telegram', 'feishu', 'whatsapp_cloud_api']
  );
  assert.equal(readiness.find((item) => item.provider === 'slack')?.ready, true);
  assert.equal(readiness.find((item) => item.provider === 'telegram')?.ready, true);
  assert.equal(readiness.find((item) => item.provider === 'feishu')?.ready, false);
  assert.equal(readiness.find((item) => item.provider === 'whatsapp_cloud_api')?.ready, false);
});
