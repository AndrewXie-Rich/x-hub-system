import assert from 'node:assert/strict';

import {
  resolveTelegramOperatorWorkerConfig,
  startTelegramOperatorWorker,
  validateTelegramOperatorWorkerConfig,
} from './TelegramOperatorWorkerRuntime.js';

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

run('TelegramOperatorWorkerRuntime resolves polling local-only defaults', () => {
  const config = resolveTelegramOperatorWorkerConfig({
    HUB_PORT: '50051',
  });
  assert.equal(!!config.enabled, false);
  assert.equal(!!config.reply_delivery_enabled, true);
  assert.equal(!!config.poll_updates_enabled, true);
  assert.equal(Number(config.poll_timeout_sec || 0), 15);
});

run('TelegramOperatorWorkerRuntime validates dedicated connector token and bot token', () => {
  const missingConnector = validateTelegramOperatorWorkerConfig({
    enabled: true,
    bot_token: 'telegram-token-1',
    connector_token_present: false,
  });
  assert.equal(!!missingConnector.ok, false);
  assert.match(String(missingConnector.message || ''), /CONNECTOR_TOKEN/i);

  const missingBot = validateTelegramOperatorWorkerConfig({
    enabled: true,
    bot_token: '',
    connector_token_present: true,
  });
  assert.equal(!!missingBot.ok, false);
  assert.match(String(missingBot.message || ''), /BOT_TOKEN/i);
});

await runAsync('TelegramOperatorWorkerRuntime skips dependency creation when disabled', async () => {
  let created = false;
  const runtime = await startTelegramOperatorWorker({
    env: {},
    createHubClient: () => {
      created = true;
      return {};
    },
  });
  assert.equal(!!runtime.started, false);
  assert.equal(created, false);
});

await runAsync('TelegramOperatorWorkerRuntime boots polling worker and wires bridge + proactive grant forwarder', async () => {
  const logs = [];
  const clientCalls = [];
  const publisherCalls = [];
  const forwarderCalls = [];
  let pollerOpts = null;
  let closeCount = 0;
  let capturedEnvelope = null;

  const runtime = await startTelegramOperatorWorker({
    env: {
      HUB_TELEGRAM_OPERATOR_ENABLE: '1',
      HUB_TELEGRAM_OPERATOR_BOT_TOKEN: 'telegram-token-1',
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
      HUB_TELEGRAM_OPERATOR_ACCOUNT_ID: 'telegram_ops_bot',
    },
    log: (line) => {
      logs.push(String(line || ''));
    },
    createHubClient: (opts) => {
      clientCalls.push(opts);
      return {
        close() {
          closeCount += 1;
        },
      };
    },
    createHubActionExecutorFactory: () => ({
      async execute(result) {
        return {
          ...result,
          execution: {
            ok: true,
            xt_command: {
              action_name: 'deploy.plan',
              status: 'queued',
            },
          },
        };
      },
    }),
    createTelegramApiClientFactory: () => {
      publisherCalls.push({ kind: 'api_client_factory' });
      return {
        async deleteWebhook() {
          return {
            ok: true,
          };
        },
        async postMessage(payload) {
          publisherCalls.push({ kind: 'post_message', payload });
          return {
            ok: true,
            message_id: 88,
          };
        },
        async answerCallbackQuery() {
          return {
            ok: true,
            answered: true,
          };
        },
      };
    },
    createResultPublisherFactory: () => {
      publisherCalls.push({ kind: 'publisher_factory' });
      return {
        async publish(result) {
          publisherCalls.push({ kind: 'publish', result });
          return {
            ok: true,
          };
        },
        async publishGrantPending() {
          return {
            ok: true,
          };
        },
        async publishGrantDecision() {
          return {
            ok: true,
          };
        },
      };
    },
    createEventForwarderFactory: (opts) => {
      forwarderCalls.push(opts);
      return {
        snapshot() {
          return {
            provider: 'telegram',
            subscribed: true,
          };
        },
        suppressGrantDecision() {},
        async close() {},
      };
    },
    createIngressBridge: (opts) => ({
      async handleEnvelope(envelope) {
        capturedEnvelope = envelope;
        await opts.on_result?.({
          request_id: 'telegram:message:1001',
          command: {
            action_name: 'deploy.plan',
            audit_ref: 'audit-1',
            channel: {
              provider: 'telegram',
              account_id: 'telegram_ops_bot',
              conversation_id: '-1001234567890',
              thread_key: 'topic:42',
            },
          },
          gate: {
            action_name: 'deploy.plan',
            scope_type: 'project',
            scope_id: 'project_alpha',
            route_mode: 'hub_to_xt',
          },
          route: {
            route_mode: 'hub_to_xt',
            resolved_device_id: 'xt-alpha-1',
          },
          dispatch: {
            kind: 'xt_command',
          },
        });
        return {
          ok: true,
          handled: true,
        };
      },
    }),
    createPollingWorkerFactory: (opts) => {
      pollerOpts = opts;
      return {
        async listen() {
          return { started: true };
        },
        snapshot() {
          return {
            started: true,
            update_count: 0,
          };
        },
        async close() {},
      };
    },
  });

  assert.equal(!!runtime.started, true);
  assert.equal(clientCalls.length, 1);
  assert.equal(String(clientCalls[0]?.app_id || ''), 'telegram_operator_adapter');
  assert.equal(String(forwarderCalls[0]?.provider || ''), 'telegram');
  assert.equal(typeof forwarderCalls[0]?.publish_grant_pending, 'function');
  assert.equal(typeof pollerOpts?.on_update, 'function');

  await pollerOpts.on_update({
    update_id: 1001,
    message: {
      message_id: 88,
      text: 'deploy plan',
      message_thread_id: 42,
      chat: {
        id: -1001234567890,
        type: 'supergroup',
      },
      from: {
        id: 123456,
      },
    },
  });

  assert.equal(String(capturedEnvelope?.structured_action?.action_name || ''), 'deploy.plan');
  assert.equal(publisherCalls.length >= 2, true);
  assert.ok(logs.some((line) => line.includes('polling_ready=1')));

  const snap = runtime.snapshot();
  assert.equal(String(snap?.config?.bot_token || ''), '');
  assert.equal(String(snap?.event_forwarder?.provider || ''), 'telegram');

  await runtime.close();
  assert.equal(closeCount, 1);
});

await runAsync('TelegramOperatorWorkerRuntime pre-suppresses local grant actions before Hub execution and acks callback queries', async () => {
  const suppressed = [];
  const acked = [];
  let pollerOpts = null;

  const runtime = await startTelegramOperatorWorker({
    env: {
      HUB_TELEGRAM_OPERATOR_ENABLE: '1',
      HUB_TELEGRAM_OPERATOR_BOT_TOKEN: 'telegram-token-1',
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
      HUB_TELEGRAM_OPERATOR_ACCOUNT_ID: 'telegram_ops_bot',
    },
    createHubClient: () => ({
      close() {},
    }),
    createHubActionExecutorFactory: () => ({
      async execute(result) {
        return {
          ...result,
          execution: {
            ok: true,
            grant_action: {
              action_name: 'grant.approve',
              grant_request_id: 'grant-req-1',
              decision: 'approved',
              grant: {
                grant_id: 'grant-1',
                client: {
                  project_id: 'project_alpha',
                },
              },
            },
          },
        };
      },
    }),
    createTelegramApiClientFactory: () => ({
      async deleteWebhook() {
        return {
          ok: true,
        };
      },
      async postMessage() {
        return {
          ok: true,
          message_id: 90,
        };
      },
      async answerCallbackQuery(payload) {
        acked.push(payload);
        return {
          ok: true,
          answered: true,
        };
      },
    }),
    createResultPublisherFactory: () => ({
      async publish() {
        return {
          ok: true,
        };
      },
      async publishGrantPending() {
        return {
          ok: true,
        };
      },
      async publishGrantDecision() {
        return {
          ok: true,
        };
      },
    }),
    createEventForwarderFactory: () => ({
      snapshot() {
        return {
          provider: 'telegram',
          subscribed: true,
        };
      },
      suppressGrantDecision(payload) {
        suppressed.push(payload);
      },
      async close() {},
    }),
    createIngressBridge: (opts) => ({
      async handleEnvelope() {
        await opts.on_result?.({
          request_id: 'telegram:interactive:cbq_1',
          command: {
            action_name: 'grant.approve',
            pending_grant: {
              grant_request_id: 'grant-req-1',
              project_id: 'project_alpha',
              status: 'pending',
            },
            channel: {
              provider: 'telegram',
              account_id: 'telegram_ops_bot',
              conversation_id: '-1001234567890',
              thread_key: 'topic:42',
            },
          },
          gate: {
            action_name: 'grant.approve',
            scope_type: 'project',
            scope_id: 'project_alpha',
            route_mode: 'hub_only_status',
          },
          route: {
            route_mode: 'hub_only_status',
          },
          dispatch: {
            kind: 'hub_grant_action',
          },
        });
        return {
          ok: true,
          handled: true,
        };
      },
    }),
    createPollingWorkerFactory: (opts) => {
      pollerOpts = opts;
      return {
        async listen() {
          return { started: true };
        },
        snapshot() {
          return {
            started: true,
          };
        },
        async close() {},
      };
    },
  });

  await pollerOpts.on_update({
    update_id: 1002,
    callback_query: {
      id: 'cbq_1',
      data: 'xt|ga|grant-req-1|project_alpha',
      from: {
        id: 123456,
      },
      message: {
        message_id: 89,
        message_thread_id: 42,
        chat: {
          id: -1001234567890,
          type: 'supergroup',
        },
      },
    },
  });

  assert.deepEqual(suppressed, [
    {
      grant_request_id: 'grant-req-1',
    },
  ]);
  assert.equal(String(acked[0]?.callback_query_id || ''), 'cbq_1');
  await runtime.close();
});
