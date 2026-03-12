import assert from 'node:assert/strict';

import {
  resolveSlackOperatorWorkerConfig,
  startSlackOperatorWorker,
  validateSlackOperatorWorkerConfig,
} from './SlackOperatorWorkerRuntime.js';

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

run('SlackOperatorWorkerRuntime resolves disabled local-only defaults', () => {
  const cfg = resolveSlackOperatorWorkerConfig({});
  assert.equal(!!cfg.enabled, false);
  assert.equal(!!cfg.allow_remote, false);
  assert.equal(String(cfg.host || ''), '127.0.0.1');
  assert.equal(Number(cfg.port || 0), 50161);
  assert.equal(String(cfg.event_path || ''), '/slack/events');
  assert.equal(String(cfg.health_path || ''), '/health');
  assert.equal(Number(cfg.body_max_bytes || 0), 256 * 1024);
  assert.equal(!!cfg.reply_delivery_enabled, true);
  assert.equal(String(cfg.app_id || ''), 'slack_operator_adapter');
  assert.equal(!!cfg.bot_token_present, false);
  assert.equal(!!cfg.connector_token_present, false);
});

run('SlackOperatorWorkerRuntime validates connector token, signing secret, and remote host gate', () => {
  const missingSecret = validateSlackOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    signing_secret: '',
    connector_token_present: true,
  });
  assert.equal(!!missingSecret.ok, false);
  assert.equal(String(missingSecret.code || ''), 'signing_secret_missing');

  const missingConnector = validateSlackOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    signing_secret: 'secret',
    connector_token_present: false,
  });
  assert.equal(!!missingConnector.ok, false);
  assert.equal(String(missingConnector.code || ''), 'connector_token_missing');

  const remoteDenied = validateSlackOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '0.0.0.0',
    signing_secret: 'secret',
    connector_token_present: true,
  });
  assert.equal(!!remoteDenied.ok, false);
  assert.equal(String(remoteDenied.code || ''), 'remote_host_not_allowed');
});

await runAsync('SlackOperatorWorkerRuntime skips dependency creation when disabled', async () => {
  let clientCreated = false;
  let bridgeCreated = false;
  let serverCreated = false;
  const logs = [];

  const runtime = await startSlackOperatorWorker({
    env: {},
    log: (line) => logs.push(String(line || '')),
    createHubClient: () => {
      clientCreated = true;
      return {};
    },
    createIngressBridge: () => {
      bridgeCreated = true;
      return {};
    },
    createIngressServerFactory: () => {
      serverCreated = true;
      return {};
    },
  });

  assert.equal(!!runtime.started, false);
  assert.equal(clientCreated, false);
  assert.equal(bridgeCreated, false);
  assert.equal(serverCreated, false);
  assert.ok(logs.some((line) => line.includes('disabled')));
  await runtime.close();
});

await runAsync('SlackOperatorWorkerRuntime boots local worker and wires bridge handleEnvelope', async () => {
  const logs = [];
  const serverCalls = [];
  const bridgeCalls = [];
  const clientCalls = [];
  const publisherCalls = [];
  let closeCount = 0;
  let capturedOnEnvelope = null;
  let publishedResult = null;

  const runtime = await startSlackOperatorWorker({
    env: {
      HUB_SLACK_OPERATOR_ENABLE: '1',
      HUB_SLACK_OPERATOR_SIGNING_SECRET: 'slack-secret-1',
      HUB_SLACK_OPERATOR_BOT_TOKEN: 'xoxb-slack-1',
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
    },
    log: (line) => logs.push(String(line || '')),
    createHubClient: (opts) => {
      clientCalls.push(opts);
      return {
        close() {
          closeCount += 1;
        },
      };
    },
    createSlackApiClientFactory: (opts) => {
      publisherCalls.push({ kind: 'api_client', opts });
      return {
        async postMessage(payload) {
          publisherCalls.push({ kind: 'post_message', payload });
          return {
            ok: true,
            message_ts: '1710000000.9999',
          };
        },
      };
    },
    createResultPublisherFactory: () => {
      publisherCalls.push({ kind: 'publisher_factory' });
      return {
        async publish(result) {
          publishedResult = result;
          return {
            ok: true,
          };
        },
      };
    },
    createIngressBridge: (opts) => {
      bridgeCalls.push(opts);
      return {
        async handleEnvelope(envelope) {
          capturedOnEnvelope = envelope;
          await opts.on_result?.({
            request_id: 'slack:event_callback:Ev-test-1',
            command: {
              action_name: 'deploy.plan',
              audit_ref: 'audit-1',
              channel: {
                provider: 'slack',
                account_id: 'ops_bot',
                conversation_id: 'C123',
                thread_key: '1710000000.0001',
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
            dispatch_kind: 'xt_command',
            route_mode: 'hub_to_xt',
          };
        },
      };
    },
    createIngressServerFactory: (opts) => {
      serverCalls.push(opts);
      return {
        async listen() {
          return { address: '127.0.0.1', port: 50161 };
        },
        async close() {},
      };
    },
  });

  assert.equal(!!runtime.started, true);
  assert.equal(clientCalls.length, 1);
  assert.equal(String(clientCalls[0]?.app_id || ''), 'slack_operator_adapter');
  assert.equal(serverCalls.length, 1);
  assert.equal(String(serverCalls[0]?.host || ''), '127.0.0.1');
  assert.equal(Number(serverCalls[0]?.port || 0), 50161);
  assert.equal(String(serverCalls[0]?.event_path || ''), '/slack/events');
  assert.equal(String(serverCalls[0]?.health_path || ''), '/health');
  assert.equal(bridgeCalls.length, 1);
  assert.ok(bridgeCalls[0]?.hub_client, 'expected hub_client injected into bridge');
  assert.equal(publisherCalls.length >= 2, true);

  const onEnvelopeOut = await serverCalls[0].onEnvelope({
    structured_action: { action_name: 'deploy.plan' },
  });
  assert.equal(!!onEnvelopeOut.ok, true);
  assert.equal(String(capturedOnEnvelope?.structured_action?.action_name || ''), 'deploy.plan');
  assert.ok(logs.some((line) => line.includes('listening on 127.0.0.1:50161')));
  assert.ok(logs.some((line) => line.includes('reply_delivery_ready=1')));
  const snap = runtime.snapshot();
  assert.equal(String(snap?.config?.bot_token || ''), '');
  assert.equal(String(snap?.config?.signing_secret || ''), '');

  await runtime.close();
  assert.equal(closeCount, 1);
  assert.ok(publishedResult, 'expected publisher to receive bridge result');
});

await runAsync('SlackOperatorWorkerRuntime fails closed when enabled config is unsafe', async () => {
  await assert.rejects(
    async () => {
      await startSlackOperatorWorker({
        env: {
          HUB_SLACK_OPERATOR_ENABLE: '1',
          HUB_SLACK_OPERATOR_HOST: '0.0.0.0',
          HUB_SLACK_OPERATOR_SIGNING_SECRET: 'slack-secret-1',
          HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
        },
      });
    },
    /HUB_SLACK_OPERATOR_HOST must stay loopback/i
  );
});
