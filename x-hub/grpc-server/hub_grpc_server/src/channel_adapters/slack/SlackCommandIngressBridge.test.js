import assert from 'node:assert/strict';

import { computeSlackSignature, normalizeSlackWebhookRequest } from './SlackIngress.js';
import { createSlackCommandIngressBridge } from './SlackCommandIngressBridge.js';

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

function signedEnvelopeForText(text) {
  const signing_secret = 'slack-signing-secret';
  const payload = {
    type: 'event_callback',
    team_id: 'T001',
    event_id: `Ev-${text.replace(/\s+/g, '-')}`,
    event_time: 1710000000,
    event: {
      type: 'message',
      user: 'U123',
      channel: 'C456',
      channel_type: 'channel',
      text,
      ts: '1710000000.1234',
      thread_ts: '1710000000.0001',
      client_msg_id: 'msg-1',
    },
  };
  const raw_body = JSON.stringify(payload);
  const timestamp_sec = 1710000005;
  return normalizeSlackWebhookRequest({
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'x-slack-request-timestamp': String(timestamp_sec),
      'x-slack-signature': computeSlackSignature({
        signing_secret,
        timestamp_sec,
        raw_body,
      }),
    },
    raw_body,
    signing_secret,
    now_ms: timestamp_sec * 1000,
  });
}

await runAsync('SlackCommandIngressBridge forwards valid commands into orchestrator and result sink', async () => {
  const seen = [];
  const bridge = createSlackCommandIngressBridge({
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

  const out = await bridge.handleEnvelope(signedEnvelopeForText('deploy plan'));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(String(out.dispatch_kind || ''), 'xt_command');
  assert.equal(String(out.route_mode || ''), 'hub_to_xt');
  assert.equal(seen.length, 1);
  assert.equal(String(seen[0]?.route?.resolved_device_id || ''), 'xt-alpha-1');
});

await runAsync('SlackCommandIngressBridge ignores signed Slack events that are not supported commands', async () => {
  let result_called = false;
  const bridge = createSlackCommandIngressBridge({
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

  const out = await bridge.handleEnvelope(signedEnvelopeForText('hello team'));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, false);
  assert.equal(String(out.reason || ''), 'structured_action_missing');
  assert.equal(result_called, false);
});

await runAsync('SlackCommandIngressBridge fails closed on retryable Hub RPC errors', async () => {
  const bridge = createSlackCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate() {
        throw new Error('hub_unavailable');
      },
      async resolveSupervisorChannelRoute() {
        throw new Error('should_not_be_called');
      },
    },
  });

  const out = await bridge.handleEnvelope(signedEnvelopeForText('deploy plan'));

  assert.equal(!!out.ok, false);
  assert.equal(!!out.handled, false);
  assert.equal(String(out.deny_code || ''), 'gate_rpc_failed');
  assert.equal(!!out.retryable, true);
});

await runAsync('SlackCommandIngressBridge keeps ingress ack success when reply delivery fails', async () => {
  const bridge = createSlackCommandIngressBridge({
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
      throw new Error('slack_post_failed');
    },
  });

  const out = await bridge.handleEnvelope(signedEnvelopeForText('deploy plan'));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(!!out.reply_delivery_ok, false);
  assert.equal(String(out.reply_delivery_error || ''), 'slack_post_failed');
});

run('SlackCommandIngressBridge exposes local normalize helper', () => {
  const bridge = createSlackCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate() {
        return { decision: { allowed: true } };
      },
      async resolveSupervisorChannelRoute() {
        return { ok: true, route: { route_mode: 'hub_only_status' } };
      },
    },
  });

  const normalized = bridge.normalize(signedEnvelopeForText('status'));
  assert.equal(!!normalized.ok, true);
  assert.equal(String(normalized.action_name || ''), 'supervisor.status.get');
});
