import assert from 'node:assert/strict';

import {
  resolveWhatsAppCloudOperatorWorkerConfig,
  startWhatsAppCloudOperatorWorker,
  validateWhatsAppCloudOperatorWorkerConfig,
} from './WhatsAppCloudOperatorWorkerRuntime.js';

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

run('WhatsAppCloudOperatorWorkerRuntime resolves disabled local-only defaults', () => {
  const cfg = resolveWhatsAppCloudOperatorWorkerConfig({});
  assert.equal(!!cfg.enabled, false);
  assert.equal(!!cfg.allow_remote, false);
  assert.equal(String(cfg.host || ''), '127.0.0.1');
  assert.equal(Number(cfg.port || 0), 50163);
  assert.equal(String(cfg.event_path || ''), '/whatsapp/events');
  assert.equal(String(cfg.health_path || ''), '/health');
  assert.equal(!!cfg.reply_delivery_enabled, false);
  assert.equal(String(cfg.app_id || ''), 'whatsapp_cloud_operator_adapter');
});

run('WhatsAppCloudOperatorWorkerRuntime validates connector token, verify token, app secret, and remote host gate', () => {
  const missingVerifyToken = validateWhatsAppCloudOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    verify_token: '',
    app_secret: 'app-secret-1',
    connector_token_present: true,
  });
  assert.equal(!!missingVerifyToken.ok, false);
  assert.equal(String(missingVerifyToken.code || ''), 'verify_token_missing');

  const missingSecret = validateWhatsAppCloudOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    verify_token: 'verify-token-1',
    app_secret: '',
    connector_token_present: true,
  });
  assert.equal(!!missingSecret.ok, false);
  assert.equal(String(missingSecret.code || ''), 'app_secret_missing');

  const missingConnector = validateWhatsAppCloudOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    verify_token: 'verify-token-1',
    app_secret: 'app-secret-1',
    connector_token_present: false,
  });
  assert.equal(!!missingConnector.ok, false);
  assert.equal(String(missingConnector.code || ''), 'connector_token_missing');

  const missingReplyCreds = validateWhatsAppCloudOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '127.0.0.1',
    verify_token: 'verify-token-1',
    app_secret: 'app-secret-1',
    connector_token_present: true,
    reply_delivery_enabled: true,
    reply_credentials_present: false,
  });
  assert.equal(!!missingReplyCreds.ok, false);
  assert.equal(String(missingReplyCreds.code || ''), 'reply_credentials_missing');

  const remoteDenied = validateWhatsAppCloudOperatorWorkerConfig({
    enabled: true,
    allow_remote: false,
    host: '0.0.0.0',
    verify_token: 'verify-token-1',
    app_secret: 'app-secret-1',
    connector_token_present: true,
  });
  assert.equal(!!remoteDenied.ok, false);
  assert.equal(String(remoteDenied.code || ''), 'remote_host_not_allowed');
});

await runAsync('WhatsAppCloudOperatorWorkerRuntime skips dependency creation when disabled', async () => {
  let clientCreated = false;
  let bridgeCreated = false;
  let serverCreated = false;
  const logs = [];

  const runtime = await startWhatsAppCloudOperatorWorker({
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

await runAsync('WhatsAppCloudOperatorWorkerRuntime boots local worker and wires bridge handleEnvelope', async () => {
  const logs = [];
  const serverCalls = [];
  const clientCalls = [];
  const publisherCalls = [];
  const forwarderCalls = [];
  let closeCount = 0;
  let capturedEnvelope = null;
  let receivedResult = null;

  const runtime = await startWhatsAppCloudOperatorWorker({
    env: {
      HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE: '1',
      HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE: '1',
      HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN: 'verify-token-1',
      HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET: 'app-secret-1',
      HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN: 'wa-access-token-1',
      HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID: 'phone-number-id-1',
      HUB_WHATSAPP_CLOUD_OPERATOR_ACCOUNT_ID: 'ops_whatsapp_cloud',
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
    createWhatsAppCloudApiClientFactory: () => ({
      async postMessage(payload) {
        publisherCalls.push({ kind: 'post_message', payload });
        return {
          ok: true,
          message_id: 'wamid.outbound.1',
        };
      },
    }),
    createResultPublisherFactory: () => ({
      async publish(result) {
        receivedResult = result;
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
    }),
    createEventForwarderFactory: (opts) => {
      forwarderCalls.push(opts);
      return {
        snapshot() {
          return {
            provider: 'whatsapp_cloud_api',
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
          request_id: 'whatsapp_cloud_api:messages:wamid.1',
          command: {
            action_name: 'deploy.plan',
            audit_ref: 'audit-1',
            channel: {
              provider: 'whatsapp_cloud_api',
              account_id: 'ops_whatsapp_cloud',
              conversation_id: '15551234567',
              thread_key: 'wamid.1',
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
    createIngressServerFactory: (opts) => {
      serverCalls.push(opts);
      return {
        async listen() {
          await opts.onEnvelope({
            envelope_type: 'messages',
            event_id: 'wamid.1',
            actor: {
              provider: 'whatsapp_cloud_api',
              external_user_id: '15551234567',
              external_tenant_id: 'ops_whatsapp_cloud',
            },
            channel: {
              provider: 'whatsapp_cloud_api',
              account_id: 'ops_whatsapp_cloud',
              conversation_id: '15551234567',
              thread_key: 'wamid.1',
            },
            structured_action: {
              action_name: 'deploy.plan',
              scope_type: 'project',
              scope_id: 'project_alpha',
            },
          });
          return {
            address: '127.0.0.1',
            port: 50163,
          };
        },
        async close() {},
      };
    },
  });

  assert.equal(!!runtime.started, true);
  assert.equal(clientCalls.length, 1);
  assert.equal(String(clientCalls[0]?.app_id || ''), 'whatsapp_cloud_operator_adapter');
  assert.equal(String(serverCalls[0]?.event_path || ''), '/whatsapp/events');
  assert.equal(String(forwarderCalls[0]?.provider || ''), 'whatsapp_cloud_api');
  assert.equal(typeof forwarderCalls[0]?.publish_grant_pending, 'function');
  assert.equal(String(capturedEnvelope?.structured_action?.action_name || ''), 'deploy.plan');
  assert.equal(String(receivedResult?.execution?.xt_command?.status || ''), 'queued');
  assert.ok(logs.some((line) => line.includes('release_blocked=1')));

  const snap = runtime.snapshot();
  assert.equal(String(snap?.config?.verify_token || ''), '');
  assert.equal(String(snap?.config?.app_secret || ''), '');
  assert.equal(String(snap?.config?.access_token || ''), '');
  assert.equal(String(snap?.event_forwarder?.provider || ''), 'whatsapp_cloud_api');

  await runtime.close();
  assert.equal(closeCount, 1);
});
