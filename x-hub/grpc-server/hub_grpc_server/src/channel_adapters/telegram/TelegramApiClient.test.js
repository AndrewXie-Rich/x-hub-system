import assert from 'node:assert/strict';

import {
  createTelegramApiClient,
  telegramBotTokenFromEnv,
} from './TelegramApiClient.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('TelegramApiClient reads bot token from env', () => {
  assert.equal(telegramBotTokenFromEnv({
    HUB_TELEGRAM_OPERATOR_BOT_TOKEN: 'telegram-token-1',
  }), 'telegram-token-1');
});

await runAsync('TelegramApiClient sends messages and normalizes Telegram response', async () => {
  const calls = [];
  const client = createTelegramApiClient({
    token: 'telegram-token-2',
    fetch_impl: async (url, options) => {
      calls.push({ url, options });
      return {
        ok: true,
        async text() {
          return JSON.stringify({
            ok: true,
            result: {
              message_id: 42,
              chat: {
                id: -100123,
              },
            },
          });
        },
      };
    },
  });

  const out = await client.postMessage({
    chat_id: '-100123',
    text: 'hello telegram',
    message_thread_id: 9,
    reply_markup: {
      inline_keyboard: [[{ text: 'Approve', callback_data: 'xt|ga|gr|proj' }]],
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(out.message_id, 42);
  assert.match(String(calls[0]?.url || ''), /sendMessage$/);
  const body = JSON.parse(String(calls[0]?.options?.body || '{}'));
  assert.equal(String(body.chat_id || ''), '-100123');
  assert.equal(Number(body.message_thread_id || 0), 9);
});

await runAsync('TelegramApiClient polls updates and answers callback queries', async () => {
  const calls = [];
  const client = createTelegramApiClient({
    token: 'telegram-token-3',
    fetch_impl: async (url, options) => {
      calls.push({ url, options });
      if (String(url).endsWith('/getUpdates')) {
        return {
          ok: true,
          async text() {
            return JSON.stringify({
              ok: true,
              result: [
                { update_id: 1001, message: { message_id: 1 } },
              ],
            });
          },
        };
      }
      return {
        ok: true,
        async text() {
          return JSON.stringify({
            ok: true,
            result: true,
          });
        },
      };
    },
  });

  const updates = await client.getUpdates({
    offset: 1000,
    timeout_sec: 12,
    allowed_updates: ['message', 'callback_query'],
  });
  assert.equal(updates.updates.length, 1);
  const answer = await client.answerCallbackQuery({
    callback_query_id: 'cbq-1',
    text: 'Accepted',
  });
  assert.equal(!!answer.ok, true);
  assert.match(String(calls[0]?.url || ''), /getUpdates$/);
  assert.match(String(calls[1]?.url || ''), /answerCallbackQuery$/);
});
