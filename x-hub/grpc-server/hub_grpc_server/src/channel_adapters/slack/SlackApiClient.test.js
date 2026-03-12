import assert from 'node:assert/strict';

import {
  createSlackApiClient,
  slackBotTokenFromEnv,
} from './SlackApiClient.js';

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

run('SlackApiClient reads dedicated bot token from env', () => {
  const token = slackBotTokenFromEnv({
    HUB_SLACK_OPERATOR_BOT_TOKEN: 'xoxb-test-1',
  });
  assert.equal(String(token || ''), 'xoxb-test-1');
});

await runAsync('SlackApiClient posts chat.postMessage with bearer auth and returns ts', async () => {
  const calls = [];
  const client = createSlackApiClient({
    token: 'xoxb-test-2',
    fetch_impl: async (url, init) => {
      calls.push({ url, init });
      return {
        ok: true,
        status: 200,
        async text() {
          return JSON.stringify({
            ok: true,
            channel: 'C123',
            ts: '1710000000.0001',
          });
        },
      };
    },
  });

  const out = await client.postMessage({
    channel: 'C123',
    text: 'Supervisor update',
    thread_ts: '1710000000.0001',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.channel || ''), 'C123');
  assert.equal(String(out.message_ts || ''), '1710000000.0001');
  assert.equal(calls.length, 1);
  assert.equal(String(calls[0].url || ''), 'https://slack.com/api/chat.postMessage');
  assert.equal(String(calls[0].init?.headers?.authorization || ''), 'Bearer xoxb-test-2');
  assert.match(String(calls[0].init?.body || ''), /"channel":"C123"/);
});

await runAsync('SlackApiClient fails closed on Slack API and transport errors', async () => {
  const apiErrorClient = createSlackApiClient({
    token: 'xoxb-test-3',
    fetch_impl: async () => ({
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({
          ok: false,
          error: 'channel_not_found',
        });
      },
    }),
  });

  await assert.rejects(
    async () => {
      await apiErrorClient.postMessage({
        channel: 'C404',
        text: 'Supervisor update',
      });
    },
    /slack_api_error:channel_not_found/
  );

  const fetchErrorClient = createSlackApiClient({
    token: 'xoxb-test-4',
    fetch_impl: async () => {
      throw new Error('network_down');
    },
  });
  await assert.rejects(
    async () => {
      await fetchErrorClient.postMessage({
        channel: 'C123',
        text: 'Supervisor update',
      });
    },
    /slack_fetch_failed:network_down/
  );
});

await runAsync('SlackApiClient validates token, channel, and text before sending', async () => {
  const client = createSlackApiClient({
    token: '',
    fetch_impl: async () => ({
      ok: true,
      status: 200,
      async text() {
        return '{}';
      },
    }),
  });
  await assert.rejects(
    async () => {
      await client.postMessage({
        channel: 'C123',
        text: 'Supervisor update',
      });
    },
    /slack_bot_token_missing/
  );
});
