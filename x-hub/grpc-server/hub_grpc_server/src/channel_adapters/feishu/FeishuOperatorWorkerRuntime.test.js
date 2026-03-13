import assert from 'node:assert/strict';

import {
  resolveFeishuOperatorWorkerConfig,
  startFeishuOperatorWorker,
  validateFeishuOperatorWorkerConfig,
} from './FeishuOperatorWorkerRuntime.js';

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

run('FeishuOperatorWorkerRuntime resolves disabled local-only defaults', () => {
  const cfg = resolveFeishuOperatorWorkerConfig({});
  assert.equal(!!cfg.enabled, false);
  assert.equal(!!cfg.allow_remote, false);
  assert.equal(String(cfg.host || ''), '127.0.0.1');
  assert.equal(Number(cfg.port || 0), 50162);
  assert.equal(String(cfg.event_path || ''), '/feishu/events');
  assert.equal(String(cfg.health_path || ''), '/health');
  assert.equal(Number(cfg.body_max_bytes || 0), 256 * 1024);
  assert.equal(!!cfg.reply_delivery_enabled, false);
  assert.equal(String(cfg.app_id || ''), 'feishu_operator_adapter');
  assert.equal(!!cfg.verification_token_present, false);
  assert.equal(!!cfg.bot_credentials_present, false);
  assert.equal(!!cfg.connector_token_present, false);
});

run('FeishuOperatorWorkerRuntime validates connector token, verification token, and remote host gate', () => {
  const missingToken = validateFeishuOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    verification_token: '',
    connector_token_present: true,
  });
  assert.equal(!!missingToken.ok, false);
  assert.equal(String(missingToken.code || ''), 'verification_token_missing');

  const missingConnector = validateFeishuOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    verification_token: 'verify-token',
    connector_token_present: false,
  });
  assert.equal(!!missingConnector.ok, false);
  assert.equal(String(missingConnector.code || ''), 'connector_token_missing');

  const missingReplyCreds = validateFeishuOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    verification_token: 'verify-token',
    connector_token_present: true,
    reply_delivery_enabled: true,
    bot_credentials_present: false,
  });
  assert.equal(!!missingReplyCreds.ok, false);
  assert.equal(String(missingReplyCreds.code || ''), 'reply_credentials_missing');

  const remoteDenied = validateFeishuOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '0.0.0.0',
    verification_token: 'verify-token',
    connector_token_present: true,
  });
  assert.equal(!!remoteDenied.ok, false);
  assert.equal(String(remoteDenied.code || ''), 'remote_host_not_allowed');
});

await runAsync('FeishuOperatorWorkerRuntime skips dependency creation when disabled', async () => {
  let clientCreated = false;
  let bridgeCreated = false;
  let serverCreated = false;
  const logs = [];

  const runtime = await startFeishuOperatorWorker({
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

await runAsync('FeishuOperatorWorkerRuntime boots local worker and wires bridge handleEnvelope', async () => {
  const logs = [];
  const serverCalls = [];
  const bridgeCalls = [];
  const clientCalls = [];
  const executorCalls = [];
  const apiClientCalls = [];
  const publisherCalls = [];
  const forwarderCalls = [];
  let closeCount = 0;
  let capturedOnEnvelope = null;
  let receivedResult = null;

  const runtime = await startFeishuOperatorWorker({
    env: {
      HUB_FEISHU_OPERATOR_ENABLE: '1',
      HUB_FEISHU_OPERATOR_REPLY_ENABLE: '1',
      HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN: 'verify-token-1',
      HUB_FEISHU_OPERATOR_BOT_APP_ID: 'cli_xxx',
      HUB_FEISHU_OPERATOR_BOT_APP_SECRET: 'sec_xxx',
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
    createHubActionExecutorFactory: () => {
      executorCalls.push({ kind: 'executor_factory' });
      return {
        async execute(result) {
          executorCalls.push({ kind: 'execute', result });
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
      };
    },
    createFeishuApiClientFactory: (opts) => {
      apiClientCalls.push(opts);
      return {
        async postMessage(payload) {
          publisherCalls.push({ kind: 'post_message', payload });
          return {
            ok: true,
            message_id: 'om_sent_1',
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
            provider: 'feishu',
            subscribed: true,
          };
        },
        suppressGrantDecision() {},
        async close() {},
      };
    },
    createIngressBridge: (opts) => {
      bridgeCalls.push(opts);
      return {
        async handleEnvelope(envelope) {
          capturedOnEnvelope = envelope;
          await opts.on_result?.({
            request_id: 'feishu:event_callback:Ev-test-1',
            command: {
              action_name: 'deploy.plan',
              audit_ref: 'audit-1',
              channel: {
                provider: 'feishu',
                account_id: 'tenant-ops',
                conversation_id: 'oc_1',
                thread_key: 'om_1',
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
          return { address: '127.0.0.1', port: 50162 };
        },
        async close() {},
      };
    },
    on_result: async (result) => {
      receivedResult = result;
    },
  });

  assert.equal(!!runtime.started, true);
  assert.equal(clientCalls.length, 1);
  assert.equal(String(clientCalls[0]?.app_id || ''), 'feishu_operator_adapter');
  assert.equal(serverCalls.length, 1);
  assert.equal(String(serverCalls[0]?.host || ''), '127.0.0.1');
  assert.equal(Number(serverCalls[0]?.port || 0), 50162);
  assert.equal(String(serverCalls[0]?.event_path || ''), '/feishu/events');
  assert.equal(String(serverCalls[0]?.health_path || ''), '/health');
  assert.equal(bridgeCalls.length, 1);
  assert.ok(bridgeCalls[0]?.hub_client, 'expected hub_client injected into bridge');
  assert.equal(executorCalls.length >= 1, true);
  assert.equal(apiClientCalls.length, 1);
  assert.equal(String(apiClientCalls[0]?.app_id || ''), 'cli_xxx');
  assert.equal(forwarderCalls.length, 1);
  assert.equal(String(forwarderCalls[0]?.provider || ''), 'feishu');
  assert.equal(typeof forwarderCalls[0]?.publish_grant_pending, 'function');
  assert.equal(typeof forwarderCalls[0]?.publish_grant_decision, 'function');

  const onEnvelopeOut = await serverCalls[0].onEnvelope({
    structured_action: { action_name: 'deploy.plan' },
  });
  assert.equal(!!onEnvelopeOut.ok, true);
  assert.equal(publisherCalls.length >= 2, true);
  assert.equal(String(capturedOnEnvelope?.structured_action?.action_name || ''), 'deploy.plan');
  assert.ok(logs.some((line) => line.includes('listening on 127.0.0.1:50162')));
  assert.ok(logs.some((line) => line.includes('reply_delivery_ready=1')));
  assert.ok(logs.some((line) => line.includes('proactive_grant_forwarding_ready=1')));
  const snap = runtime.snapshot();
  assert.equal(String(snap?.config?.verification_token || ''), '');
  assert.equal(String(snap?.event_forwarder?.provider || ''), 'feishu');

  await runtime.close();
  assert.equal(closeCount, 1);
  assert.equal(String(receivedResult?.execution?.xt_command?.status || ''), 'queued');
});

await runAsync('FeishuOperatorWorkerRuntime fails closed when enabled config is unsafe', async () => {
  await assert.rejects(
    async () => {
      await startFeishuOperatorWorker({
        env: {
          HUB_FEISHU_OPERATOR_ENABLE: '1',
          HUB_FEISHU_OPERATOR_HOST: '0.0.0.0',
          HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN: 'verify-token-1',
          HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
        },
      });
    },
    /HUB_FEISHU_OPERATOR_HOST must stay loopback/i
  );
});
