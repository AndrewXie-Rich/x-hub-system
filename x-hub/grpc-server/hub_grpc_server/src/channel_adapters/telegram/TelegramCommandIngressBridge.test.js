import assert from 'node:assert/strict';

import { normalizeTelegramUpdate } from './TelegramIngress.js';
import { createTelegramCommandIngressBridge } from './TelegramCommandIngressBridge.js';

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
  return normalizeTelegramUpdate({
    update_id: 1001,
    message: {
      message_id: 88,
      text,
      chat: {
        id: -1001234567890,
        type: 'supergroup',
      },
      from: {
        id: 123456,
      },
      message_thread_id: 42,
    },
  }, {
    account_id: 'telegram_ops_bot',
  });
}

await runAsync('TelegramCommandIngressBridge forwards valid commands into orchestrator and result sink', async () => {
  const seen = [];
  const bridge = createTelegramCommandIngressBridge({
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

await runAsync('TelegramCommandIngressBridge ignores supported Telegram events that are not commands', async () => {
  let result_called = false;
  const bridge = createTelegramCommandIngressBridge({
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

await runAsync('TelegramCommandIngressBridge fails closed on retryable Hub RPC errors', async () => {
  const bridge = createTelegramCommandIngressBridge({
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

await runAsync('TelegramCommandIngressBridge acknowledges unknown unbound ingress by creating a discovery ticket', async () => {
  const seen = [];
  let route_called = false;
  const bridge = createTelegramCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate(req) {
        return {
          decision: {
            allowed: false,
            deny_code: 'identity_binding_missing',
            action_name: req.action_name,
            route_mode: 'hub_only_status',
          },
          audit_logged: true,
        };
      },
      async createOrTouchChannelOnboardingDiscoveryTicket(ticket) {
        return {
          ok: true,
          created: true,
          updated: false,
          audit_logged: true,
          ticket: {
            ticket_id: 'disc-telegram-bridge-1',
            provider: ticket.provider,
            status: 'pending',
            recommended_binding_mode: ticket.recommended_binding_mode,
            audit_ref: 'audit-disc-telegram-bridge-1',
          },
        };
      },
      async resolveSupervisorChannelRoute() {
        route_called = true;
        throw new Error('should_not_route');
      },
    },
    on_result: async (result) => {
      seen.push(result);
    },
  });

  const out = await bridge.handleEnvelope(envelopeForText('status'));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(String(out.dispatch_kind || ''), 'discovery_ticket');
  assert.equal(route_called, false);
  assert.equal(seen.length, 1);
  assert.equal(String(seen[0]?.discovery_ticket?.ticket_id || ''), 'disc-telegram-bridge-1');
});

await runAsync('TelegramCommandIngressBridge keeps ingress ack success when reply delivery fails', async () => {
  const bridge = createTelegramCommandIngressBridge({
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
      throw new Error('telegram_post_failed');
    },
  });

  const out = await bridge.handleEnvelope(envelopeForText('deploy plan'));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(!!out.reply_delivery_ok, false);
  assert.equal(String(out.reply_delivery_error || ''), 'telegram_post_failed');
});

run('TelegramCommandIngressBridge exposes local normalize helper', () => {
  const bridge = createTelegramCommandIngressBridge({
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
