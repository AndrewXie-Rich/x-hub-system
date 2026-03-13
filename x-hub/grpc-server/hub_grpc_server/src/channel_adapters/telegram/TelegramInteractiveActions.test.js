import assert from 'node:assert/strict';

import {
  buildTelegramApprovalCallbackData,
  compileTelegramCallbackAction,
  mapTelegramActionCodeToChannelAction,
} from './TelegramInteractiveActions.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('TelegramInteractiveActions maps compact action codes', () => {
  assert.equal(mapTelegramActionCodeToChannelAction('ga'), 'grant.approve');
  assert.equal(mapTelegramActionCodeToChannelAction('gr'), 'grant.reject');
  assert.equal(mapTelegramActionCodeToChannelAction('unknown'), '');
});

run('TelegramInteractiveActions builds callback payload within Telegram size limits', () => {
  const out = buildTelegramApprovalCallbackData({
    action_name: 'grant.approve',
    grant_request_id: 'grant_req_1',
    project_id: 'project_alpha',
  });
  assert.equal(out, 'xt|ga|grant_req_1|project_alpha');
});

run('TelegramInteractiveActions compiles callback query into governed action envelope', () => {
  const out = compileTelegramCallbackAction({
    update_id: 1001,
    callback_query: {
      id: 'cbq_1',
      data: 'xt|ga|grant_req_1|project_alpha',
      from: {
        id: 123456,
      },
      message: {
        message_id: 88,
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
  assert.equal(String(out.actor?.external_user_id || ''), '123456');
  assert.equal(String(out.channel?.conversation_id || ''), '-1001234567890');
  assert.equal(String(out.channel?.thread_key || ''), 'topic:42');
  assert.equal(String(out.action?.action_name || ''), 'grant.approve');
  assert.equal(String(out.action?.pending_grant?.grant_request_id || ''), 'grant_req_1');
  assert.equal(String(out.action?.pending_grant?.project_id || ''), 'project_alpha');
});
