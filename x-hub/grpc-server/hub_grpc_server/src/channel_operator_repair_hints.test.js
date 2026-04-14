import assert from 'node:assert/strict';

import {
  buildOperatorChannelDeliveryRepairHints,
  buildOperatorChannelRuntimeRepairHints,
} from './channel_operator_repair_hints.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('XT-W3-24/repair hints map Feishu verification_token_invalid to an actionable token fix', () => {
  const hints = buildOperatorChannelRuntimeRepairHints({
    provider: 'feishu',
    runtime_state: 'ingress_ready',
    delivery_ready: false,
    command_entry_ready: false,
    last_error_code: 'verification_token_invalid',
  });

  assert.equal(
    hints.some((item) => String(item || '').includes('HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN')),
    true
  );
  assert.equal(
    hints.some((item) => String(item || '').includes('/feishu/events')),
    true
  );
});

run('XT-W3-24/repair hints map WhatsApp verify_token_invalid to a re-verify path', () => {
  const hints = buildOperatorChannelRuntimeRepairHints({
    provider: 'whatsapp_cloud_api',
    runtime_state: 'ingress_ready',
    delivery_ready: false,
    command_entry_ready: false,
    last_error_code: 'verify_token_invalid',
  });

  assert.equal(
    hints.some((item) => String(item || '').includes('HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN')),
    true
  );
  assert.equal(
    hints.some((item) => String(item || '').includes('GET verify challenge')),
    true
  );
});

run('XT-W3-24/repair hints explain Slack signature failures without falling back to generic wording', () => {
  const hints = buildOperatorChannelRuntimeRepairHints({
    provider: 'slack',
    runtime_state: 'degraded',
    delivery_ready: false,
    command_entry_ready: false,
    last_error_code: 'signature_invalid',
  });

  assert.equal(
    hints.some((item) => String(item || '').includes('HUB_SLACK_OPERATOR_SIGNING_SECRET')),
    true
  );
  assert.equal(
    hints.some((item) => String(item || '').includes('/slack/events')),
    true
  );
});

run('XT-W3-24/repair hints explain replay suspicion as new-message-only recovery', () => {
  const hints = buildOperatorChannelDeliveryRepairHints({
    provider: 'telegram',
    reply_enabled: true,
    credentials_configured: true,
    deny_code: 'replay_detected',
  });

  assert.equal(
    hints.some((item) => String(item || '').includes('重新发送一条新消息')),
    true
  );
  assert.equal(
    hints.some((item) => String(item || '').includes('不要直接复用旧 payload')),
    true
  );
});
