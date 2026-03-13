import assert from 'node:assert/strict';

import { normalizeFeishuWebhookRequest } from './FeishuIngress.js';
import { createFeishuCommandIngressBridge } from './FeishuCommandIngressBridge.js';

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

function envelopeForText(text) {
  const payload = {
    schema: '2.0',
    header: {
      event_id: `feishu-${text.replace(/\s+/g, '-')}`,
      event_type: 'im.message.receive_v1',
      create_time: '1710000000123',
      tenant_key: 'tenant-ops',
      token: 'verify-token-1',
    },
    event: {
      sender: {
        sender_id: {
          open_id: 'ou_user_1',
        },
      },
      message: {
        message_id: 'om_1',
        thread_id: 'omt_1',
        chat_id: 'oc_room_1',
        chat_type: 'group',
        message_type: 'text',
        content: JSON.stringify({
          text,
        }),
      },
    },
  };
  return normalizeFeishuWebhookRequest({
    headers: {
      'content-type': 'application/json; charset=utf-8',
    },
    raw_body: JSON.stringify(payload),
    verification_token: 'verify-token-1',
  });
}

await runAsync('FeishuCommandIngressBridge forwards valid commands into orchestrator and result sink', async () => {
  const seen = [];
  const bridge = createFeishuCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate(req) {
        return {
          decision: {
            allowed: true,
            action_name: req.action_name,
            binding_id: 'binding-deploy-1',
            scope_type: 'project',
            scope_id: 'project_alpha',
            route_mode: 'hub_to_xt',
          },
          audit_logged: true,
        };
      },
      async resolveSupervisorChannelRoute() {
        return {
          ok: true,
          audit_logged: true,
          created: true,
          updated: false,
          route: {
            route_mode: 'hub_to_xt',
            resolved_device_id: 'xt-alpha-1',
          },
        };
      },
    },
    on_result: async (result) => {
      seen.push(result);
    },
  });

  const out = await bridge.handleEnvelope(envelopeForText('deploy plan'));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(String(out.dispatch_kind || ''), 'xt_command');
  assert.equal(String(out.route_mode || ''), 'hub_to_xt');
  assert.equal(seen.length, 1);
  assert.equal(String(seen[0]?.route?.resolved_device_id || ''), 'xt-alpha-1');
});

await runAsync('FeishuCommandIngressBridge ignores valid Feishu events that are not supported commands', async () => {
  let result_called = false;
  const bridge = createFeishuCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate() {
        throw new Error('should_not_be_called');
      },
      async resolveSupervisorChannelRoute() {
        throw new Error('should_not_be_called');
      },
    },
    on_result: async () => {
      result_called = true;
    },
  });

  const out = await bridge.handleEnvelope(envelopeForText('hello team'));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, false);
  assert.equal(String(out.reason || ''), 'structured_action_missing');
  assert.equal(result_called, false);
});

await runAsync('FeishuCommandIngressBridge fails closed on retryable Hub RPC errors', async () => {
  const bridge = createFeishuCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate() {
        throw new Error('hub_unavailable');
      },
      async resolveSupervisorChannelRoute() {
        throw new Error('should_not_be_called');
      },
    },
  });

  const out = await bridge.handleEnvelope(envelopeForText('deploy plan'));

  assert.equal(!!out.ok, false);
  assert.equal(!!out.handled, false);
  assert.equal(String(out.deny_code || ''), 'gate_rpc_failed');
  assert.equal(!!out.retryable, true);
});

await runAsync('FeishuCommandIngressBridge keeps ingress ack success when reply delivery fails', async () => {
  const bridge = createFeishuCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate(req) {
        return {
          decision: {
            allowed: true,
            action_name: req.action_name,
            binding_id: 'binding-deploy-1',
            scope_type: 'project',
            scope_id: 'project_alpha',
            route_mode: 'hub_to_xt',
          },
          audit_logged: true,
        };
      },
      async resolveSupervisorChannelRoute() {
        return {
          ok: true,
          audit_logged: true,
          created: true,
          updated: false,
          route: {
            route_mode: 'hub_to_xt',
            resolved_device_id: 'xt-alpha-1',
          },
        };
      },
    },
    on_result: async () => {
      throw new Error('feishu_post_failed');
    },
  });

  const out = await bridge.handleEnvelope(envelopeForText('deploy plan'));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(!!out.reply_delivery_ok, false);
  assert.equal(String(out.reply_delivery_error || ''), 'feishu_post_failed');
});

run('FeishuCommandIngressBridge exposes local normalize helper', () => {
  const bridge = createFeishuCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate() {
        return { decision: { allowed: true } };
      },
      async resolveSupervisorChannelRoute() {
        return { ok: true, route: { route_mode: 'hub_only_status' } };
      },
    },
  });

  const normalized = bridge.normalize(envelopeForText('status'));
  assert.equal(!!normalized.ok, true);
  assert.equal(String(normalized.action_name || ''), 'supervisor.status.get');
});
