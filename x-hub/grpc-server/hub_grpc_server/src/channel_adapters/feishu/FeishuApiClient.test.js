import assert from 'node:assert/strict';

import {
  createFeishuApiClient,
  feishuBotCredentialsFromEnv,
} from './FeishuApiClient.js';

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

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

run('FeishuApiClient reads bot credentials from environment', () => {
  withEnv({
    HUB_FEISHU_OPERATOR_BOT_APP_ID: 'cli_xxx',
    HUB_FEISHU_OPERATOR_BOT_APP_SECRET: 'sec_xxx',
  }, () => {
    const creds = feishuBotCredentialsFromEnv(process.env);
    assert.equal(String(creds.app_id || ''), 'cli_xxx');
    assert.equal(String(creds.app_secret || ''), 'sec_xxx');
  });
});

await runAsync('FeishuApiClient fetches tenant token once and posts direct messages with cached auth', async () => {
  const calls = [];
  const fetch_impl = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    if (String(url).includes('/auth/v3/tenant_access_token/internal')) {
      return {
        ok: true,
        status: 200,
        async text() {
          return JSON.stringify({
            code: 0,
            expire: 7200,
            tenant_access_token: 'tenant-token-1',
          });
        },
      };
    }
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({
          code: 0,
          data: {
            message_id: 'om_msg_1',
          },
        });
      },
    };
  };

  const client = createFeishuApiClient({
    app_id: 'cli_xxx',
    app_secret: 'sec_xxx',
    fetch_impl,
    now_fn: () => 1_710_000_000_000,
  });

  const first = await client.postMessage({
    receive_id: 'oc_room_1',
    receive_id_type: 'chat_id',
    msg_type: 'interactive',
    content: '{"schema":"2.0"}',
  });
  const second = await client.postMessage({
    receive_id: 'oc_room_1',
    receive_id_type: 'chat_id',
    msg_type: 'interactive',
    content: '{"schema":"2.0"}',
  });

  assert.equal(!!first.ok, true);
  assert.equal(String(first.message_id || ''), 'om_msg_1');
  assert.equal(!!second.ok, true);
  assert.equal(calls.length, 3);
  assert.match(String(calls[1].url || ''), /\/im\/v1\/messages\?receive_id_type=chat_id$/);
  assert.match(String(calls[2].url || ''), /\/im\/v1\/messages\?receive_id_type=chat_id$/);
  assert.equal(String(calls[1].options?.headers?.authorization || ''), 'Bearer tenant-token-1');
});

await runAsync('FeishuApiClient posts reply-thread messages against message reply endpoint', async () => {
  const calls = [];
  const client = createFeishuApiClient({
    app_id: 'cli_xxx',
    app_secret: 'sec_xxx',
    fetch_impl: async (url, options = {}) => {
      calls.push({ url: String(url), options });
      if (String(url).includes('/auth/v3/tenant_access_token/internal')) {
        return {
          ok: true,
          status: 200,
          async text() {
            return JSON.stringify({
              code: 0,
              expire: 7200,
              tenant_access_token: 'tenant-token-1',
            });
          },
        };
      }
      return {
        ok: true,
        status: 200,
        async text() {
          return JSON.stringify({
            code: 0,
            data: {
              message_id: 'om_reply_1',
            },
          });
        },
      };
    },
  });

  const out = await client.postMessage({
    receive_id: 'oc_room_1',
    receive_id_type: 'chat_id',
    reply_to_message_id: 'om_anchor_1',
    reply_in_thread: true,
    msg_type: 'interactive',
    content: '{"schema":"2.0"}',
  });

  assert.equal(!!out.ok, true);
  assert.match(String(calls[1].url || ''), /\/im\/v1\/messages\/om_anchor_1\/reply$/);
  assert.match(String(calls[1].options?.body || ''), /"reply_in_thread":true/);
});

await runAsync('FeishuApiClient fails closed on provider API errors', async () => {
  const client = createFeishuApiClient({
    app_id: 'cli_xxx',
    app_secret: 'sec_xxx',
    fetch_impl: async (url) => {
      if (String(url).includes('/auth/v3/tenant_access_token/internal')) {
        return {
          ok: true,
          status: 200,
          async text() {
            return JSON.stringify({
              code: 0,
              expire: 7200,
              tenant_access_token: 'tenant-token-1',
            });
          },
        };
      }
      return {
        ok: true,
        status: 200,
        async text() {
          return JSON.stringify({
            code: 999,
            msg: 'permission denied',
          });
        },
      };
    },
  });

  await assert.rejects(
    async () => {
      await client.postMessage({
        receive_id: 'oc_room_1',
        receive_id_type: 'chat_id',
        msg_type: 'interactive',
        content: '{"schema":"2.0"}',
      });
    },
    /feishu_api_error:permission denied/
  );
});
