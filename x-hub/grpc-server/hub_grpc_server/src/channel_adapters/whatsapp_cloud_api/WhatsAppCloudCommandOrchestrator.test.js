import assert from 'node:assert/strict';

import {
  createWhatsAppCloudCommandOrchestrator,
} from './WhatsAppCloudCommandOrchestrator.js';

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

run('WhatsAppCloudCommandOrchestrator normalizes webhook text envelopes', () => {
  const orchestrator = createWhatsAppCloudCommandOrchestrator();
  const out = orchestrator.normalize(makeEnvelope());
  assert.equal(!!out.ok, true);
  assert.match(String(out.request_id || ''), /^whatsapp_cloud_api:messages:/);
  assert.equal(String(out.action_name || ''), 'deploy.plan');
  assert.equal(String(out.channel?.provider || ''), 'whatsapp_cloud_api');
});

await runAsync('WhatsAppCloudCommandOrchestrator resolves deploy plan to XT dispatch via Hub gate and route', async () => {
  const calls = [];
  const orchestrator = createWhatsAppCloudCommandOrchestrator({
    hub_client: {
      async evaluateChannelCommandGate(req) {
        calls.push({ method: 'gate', req });
        return {
          decision: {
            allowed: true,
            action_name: req.action_name,
            binding_id: 'binding-wa-1',
            scope_type: 'project',
            scope_id: 'project_alpha',
            route_mode: 'hub_to_xt',
          },
          audit_logged: true,
        };
      },
      async resolveSupervisorChannelRoute(req) {
        calls.push({ method: 'route', req });
        return {
          route: {
            route_mode: 'hub_to_xt',
            resolved_device_id: 'xt-alpha-1',
          },
          audit_logged: true,
        };
      },
    },
  });

  const out = await orchestrator.handle(makeEnvelope());
  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'xt_command');
  assert.equal(String(out.route?.resolved_device_id || ''), 'xt-alpha-1');
  assert.equal(String(calls[0]?.req.channel?.provider || ''), 'whatsapp_cloud_api');
});

await runAsync('WhatsAppCloudCommandOrchestrator keeps approval actions hub-side and forwards pending grant scope', async () => {
  const orchestrator = createWhatsAppCloudCommandOrchestrator({
    hub_client: {
      async evaluateChannelCommandGate(req) {
        return {
          decision: {
            allowed: true,
            action_name: req.action_name,
            binding_id: 'binding-wa-approval',
            scope_type: 'project',
            scope_id: 'project_alpha',
            route_mode: 'hub_only_status',
          },
          audit_logged: true,
        };
      },
      async resolveSupervisorChannelRoute() {
        return {
          route: {
            route_mode: 'hub_only_status',
          },
          audit_logged: true,
        };
      },
    },
  });

  const out = await orchestrator.handle(makeEnvelope({
    structured_action: {
      action_name: 'grant.approve',
      pending_grant: {
        grant_request_id: 'grant-req-1',
        project_id: 'project_alpha',
        status: 'pending',
      },
    },
  }));

  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'hub_grant_action');
  assert.equal(String(out.command?.pending_grant?.grant_request_id || ''), 'grant-req-1');
});
