import assert from 'node:assert/strict';

import { createWhatsAppCloudCommandIngressBridge } from './WhatsAppCloudCommandIngressBridge.js';

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

function makeEnvelope(overrides = {}) {
  return {
    envelope_type: 'messages',
    event_id: 'wamid.1',
    replay_key: 'wamid.1',
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
      channel_scope: 'dm',
    },
    structured_action: {
      action_name: 'deploy.plan',
      scope_type: 'project',
      scope_id: 'project_alpha',
    },
    ...overrides,
  };
}

await runAsync('WhatsAppCloudCommandIngressBridge forwards valid commands into orchestrator and result sink', async () => {
  const seen = [];
  const bridge = createWhatsAppCloudCommandIngressBridge({
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
          route: {
            route_mode: 'hub_to_xt',
            resolved_device_id: 'xt-alpha-1',
          },
          audit_logged: true,
        };
      },
    },
    on_result: async (result) => {
      seen.push(result);
    },
  });

  const out = await bridge.handleEnvelope(makeEnvelope());

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(String(out.dispatch_kind || ''), 'xt_command');
  assert.equal(String(out.route_mode || ''), 'hub_to_xt');
  assert.equal(seen.length, 1);
  assert.equal(String(seen[0]?.route?.resolved_device_id || ''), 'xt-alpha-1');
});

await runAsync('WhatsAppCloudCommandIngressBridge ignores inbound envelopes without structured actions', async () => {
  const bridge = createWhatsAppCloudCommandIngressBridge({
    hub_client: {
      async evaluateChannelCommandGate() {
        throw new Error('should_not_be_called');
      },
      async resolveSupervisorChannelRoute() {
        throw new Error('should_not_be_called');
      },
    },
  });

  const out = await bridge.handleEnvelope(makeEnvelope({ structured_action: {} }));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, false);
  assert.equal(String(out.reason || ''), 'structured_action_missing');
});

await runAsync('WhatsAppCloudCommandIngressBridge acknowledges unknown unbound ingress by creating a discovery ticket', async () => {
  const seen = [];
  let routeCalled = false;
  const bridge = createWhatsAppCloudCommandIngressBridge({
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
            ticket_id: 'disc-whatsapp-1',
            provider: ticket.provider,
            status: 'pending',
            recommended_binding_mode: ticket.recommended_binding_mode,
            audit_ref: 'audit-disc-whatsapp-1',
          },
        };
      },
      async resolveSupervisorChannelRoute() {
        routeCalled = true;
        throw new Error('should_not_route');
      },
    },
    on_result: async (result) => {
      seen.push(result);
    },
  });

  const out = await bridge.handleEnvelope(makeEnvelope({
    structured_action: {
      action_name: 'supervisor.status.get',
    },
  }));

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(String(out.dispatch_kind || ''), 'discovery_ticket');
  assert.equal(routeCalled, false);
  assert.equal(seen.length, 1);
  assert.equal(String(seen[0]?.discovery_ticket?.ticket_id || ''), 'disc-whatsapp-1');
});

await runAsync('WhatsAppCloudCommandIngressBridge keeps ingress ack success when reply delivery fails', async () => {
  const bridge = createWhatsAppCloudCommandIngressBridge({
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
          route: {
            route_mode: 'hub_to_xt',
            resolved_device_id: 'xt-alpha-1',
          },
          audit_logged: true,
        };
      },
    },
    on_result: async () => {
      throw new Error('whatsapp_reply_failed');
    },
  });

  const out = await bridge.handleEnvelope(makeEnvelope());

  assert.equal(!!out.ok, true);
  assert.equal(!!out.handled, true);
  assert.equal(!!out.reply_delivery_ok, false);
  assert.equal(String(out.reply_delivery_error || ''), 'whatsapp_reply_failed');
});
