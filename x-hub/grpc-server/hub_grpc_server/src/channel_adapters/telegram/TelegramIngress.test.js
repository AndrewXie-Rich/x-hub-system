import assert from 'node:assert/strict';

import {
  compileTelegramTextCommand,
  normalizeTelegramUpdate,
} from './TelegramIngress.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('TelegramIngress compiles basic text commands', () => {
  assert.equal(String(compileTelegramTextCommand('status')?.action_name || ''), 'supervisor.status.get');
  assert.equal(String(compileTelegramTextCommand('deploy plan')?.action_name || ''), 'deploy.plan');
  assert.equal(String(compileTelegramTextCommand('grant approve grant_req_1 project project_alpha')?.pending_grant?.project_id || ''), 'project_alpha');
});

run('TelegramIngress normalizes text messages into operator envelopes', () => {
  const out = normalizeTelegramUpdate({
    update_id: 1001,
    message: {
      message_id: 88,
      text: 'deploy plan',
      chat: {
        id: -1001234567890,
        type: 'supergroup',
      },
      from: {
        id: 123456,
      },
      message_thread_id: 42,
    },
  }, {
    account_id: 'telegram_ops_bot',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.schema_version || ''), 'xhub.channel_ingress_envelope.v1');
  assert.equal(String(out.listener || ''), 'provider_polling');
  assert.equal(String(out.process || ''), 'telegram_polling_worker');
  assert.equal(String(out.channel?.conversation_id || ''), '-1001234567890');
  assert.equal(String(out.channel?.thread_key || ''), 'topic:42');
  assert.equal(String(out.delivery_context?.thread_key || ''), 'topic:42');
  assert.equal(String(out.structured_action?.action_name || ''), 'deploy.plan');
});

run('TelegramIngress ignores bot-authored messages fail-closed', () => {
  const out = normalizeTelegramUpdate({
    update_id: 1002,
    message: {
      message_id: 89,
      text: 'status',
      chat: {
        id: 12345,
        type: 'private',
      },
      from: {
        id: 999,
        is_bot: true,
      },
    },
  }, {
    account_id: 'telegram_ops_bot',
  });

  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'structured_action_missing');
});

run('TelegramIngress keeps callback query id for interactive ack flow', () => {
  const out = normalizeTelegramUpdate({
    update_id: 1003,
    callback_query: {
      id: 'cbq_1',
      data: 'xt|ga|grant_req_1|project_alpha',
      from: {
        id: 123456,
      },
      message: {
        message_id: 90,
        message_thread_id: 42,
        chat: {
          id: -1001234567890,
          type: 'supergroup',
        },
      },
    },
  }, {
    account_id: 'telegram_ops_bot',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.callback_query_id || ''), 'cbq_1');
  assert.equal(String(out.audit_ref || ''), 'telegram_callback:cbq_1');
  assert.equal(String(out.action?.action_name || ''), 'grant.approve');
  assert.equal(String(out.channel?.thread_key || ''), 'topic:42');
});
