import assert from 'node:assert/strict';

import { normalizeFeishuWebhookRequest } from './FeishuIngress.js';
import {
  classifyFeishuCommandDispatch,
  createFeishuCommandOrchestrator,
  normalizeFeishuCommandInput,
  orchestrateFeishuCommand,
} from './FeishuCommandOrchestrator.js';

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

function makeFeishuDeployEnvelope() {
  const payload = {
    schema: '2.0',
    header: {
      event_id: 'feishu-evt-deploy-1',
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
          text: '<at user_id="ou_bot">XHub</at> deploy plan',
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

function makeFeishuGrantAction() {
  const payload = {
    schema: '2.0',
    header: {
      event_id: 'feishu-card-grant-1',
      event_type: 'card.action.trigger',
      tenant_key: 'tenant-ops',
      token: 'verify-token-2',
    },
    event: {
      operator: {
        operator_id: {
          open_id: 'ou_approver_1',
        },
      },
      token: 'card-trigger-1',
      action: {
        value: {
          audit_ref: 'audit-feishu-grant-1',
          action_name: 'grant.approve',
          binding_id: 'binding-feishu-1',
          scope_type: 'project',
          scope_id: 'payments-prod',
          pending_grant_request_id: 'grant_req_1',
          pending_grant_project_id: 'payments-prod',
          note: 'approved via feishu card',
        },
      },
      context: {
        open_chat_id: 'oc_room_approve',
        open_message_id: 'om_card_1',
        chat_type: 'group',
      },
    },
  };
  return normalizeFeishuWebhookRequest({
    headers: {
      'content-type': 'application/json',
    },
    raw_body: JSON.stringify(payload),
    verification_token: 'verify-token-2',
  });
}

await runAsync('FeishuCommandOrchestrator resolves deploy plan to XT dispatch via Hub gate and route', async () => {
  const calls = [];
  const hub_client = {
    async evaluateChannelCommandGate(req) {
      calls.push({ method: 'gate', req });
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
    async resolveSupervisorChannelRoute(req) {
      calls.push({ method: 'route', req });
      return {
        ok: true,
        audit_logged: true,
        created: true,
        updated: false,
        route: {
          route_mode: 'hub_to_xt',
          resolved_device_id: 'xt-alpha-1',
          scope_type: 'project',
          scope_id: 'project_alpha',
          xt_online: true,
        },
      };
    },
  };

  const out = await orchestrateFeishuCommand({
    input: makeFeishuDeployEnvelope(),
    hub_client,
    now_fn: () => 1710000007000,
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.command?.action_name || ''), 'deploy.plan');
  assert.equal(String(out.dispatch?.kind || ''), 'xt_command');
  assert.equal(String(out.route?.route_mode || ''), 'hub_to_xt');
  assert.equal(String(out.route?.resolved_device_id || ''), 'xt-alpha-1');
  assert.equal(calls.length, 2);
  assert.equal(String(calls[0].req.channel?.conversation_id || ''), 'oc_room_1');
  assert.equal(String(calls[1].req.binding_id || ''), 'binding-deploy-1');
  assert.equal(String(calls[1].req.project_id || ''), 'project_alpha');
});

await runAsync('FeishuCommandOrchestrator keeps approval actions hub-side and forwards pending grant scope', async () => {
  const calls = [];
  const orchestrator = createFeishuCommandOrchestrator({
    hub_client: {
      async evaluateChannelCommandGate(req) {
        calls.push({ method: 'gate', req });
        return {
          decision: {
            allowed: true,
            action_name: 'grant.approve',
            binding_id: req.binding_id,
            scope_type: 'project',
            scope_id: 'payments-prod',
            route_mode: 'hub_only_status',
          },
          audit_logged: true,
        };
      },
      async resolveSupervisorChannelRoute(req) {
        calls.push({ method: 'route', req });
        return {
          ok: true,
          audit_logged: true,
          created: false,
          updated: true,
          route: {
            route_mode: 'hub_only_status',
            scope_type: 'project',
            scope_id: 'payments-prod',
          },
        };
      },
    },
    now_fn: () => 1710000010000,
  });

  const out = await orchestrator.handle(makeFeishuGrantAction());

  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'hub_grant_action');
  assert.equal(String(out.command?.binding_id || ''), 'binding-feishu-1');
  assert.equal(String(out.command?.pending_grant?.grant_request_id || ''), 'grant_req_1');
  assert.equal(String(out.command?.note || ''), 'approved via feishu card');
  assert.equal(String(calls[0].req.scope_id || ''), 'payments-prod');
  assert.equal(String(calls[1].req.binding_id || ''), 'binding-feishu-1');
  assert.equal(String(calls[1].req.project_id || ''), 'payments-prod');
});

await runAsync('FeishuCommandOrchestrator short-circuits route on gate deny', async () => {
  let route_called = false;
  const out = await orchestrateFeishuCommand({
    input: makeFeishuDeployEnvelope(),
    hub_client: {
      async evaluateChannelCommandGate() {
        return {
          decision: {
            allowed: false,
            deny_code: 'role_not_allowed',
            action_name: 'deploy.plan',
            route_mode: 'hub_to_xt',
          },
          audit_logged: true,
        };
      },
      async resolveSupervisorChannelRoute() {
        route_called = true;
        throw new Error('should_not_route');
      },
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'deny');
  assert.equal(String(out.gate?.deny_code || ''), 'role_not_allowed');
  assert.equal(route_called, false);
});

await runAsync('FeishuCommandOrchestrator creates discovery ticket when governed bindings are missing', async () => {
  let route_called = false;
  const discovery_calls = [];
  const out = await orchestrateFeishuCommand({
    input: makeFeishuDeployEnvelope(),
    hub_client: {
      async evaluateChannelCommandGate(req) {
        return {
          decision: {
            allowed: false,
            deny_code: 'channel_binding_missing',
            action_name: req.action_name,
            route_mode: 'hub_only_status',
          },
          audit_logged: true,
        };
      },
      async createOrTouchChannelOnboardingDiscoveryTicket(ticket, request_id) {
        discovery_calls.push({ ticket, request_id });
        return {
          ok: true,
          created: true,
          updated: false,
          audit_logged: true,
          ticket: {
            ticket_id: 'disc-feishu-1',
            provider: ticket.provider,
            conversation_id: ticket.conversation_id,
            thread_key: ticket.thread_key,
            recommended_binding_mode: ticket.recommended_binding_mode,
            status: 'pending',
            audit_ref: 'audit-disc-feishu-1',
          },
        };
      },
      async resolveSupervisorChannelRoute() {
        route_called = true;
        throw new Error('should_not_route');
      },
    },
    now_fn: () => 1710000007000,
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'discovery_ticket');
  assert.equal(String(out.discovery_ticket?.ticket_id || ''), 'disc-feishu-1');
  assert.equal(route_called, false);
  assert.equal(discovery_calls.length, 1);
  assert.equal(String(discovery_calls[0].ticket.provider || ''), 'feishu');
  assert.equal(String(discovery_calls[0].ticket.conversation_id || ''), 'oc_room_1');
  assert.equal(String(discovery_calls[0].ticket.recommended_binding_mode || ''), 'thread_binding');
});

run('FeishuCommandOrchestrator fails closed on unsupported input and exposes normalization helpers', () => {
  const unsupported = normalizeFeishuCommandInput({
    envelope_type: 'event_callback',
    actor: { external_user_id: 'ou_user_1' },
    channel: { provider: 'feishu', conversation_id: 'oc_room_1' },
    structured_action: null,
  });
  assert.equal(!!unsupported.ok, false);
  assert.equal(String(unsupported.deny_code || ''), 'structured_action_missing');

  const classify = classifyFeishuCommandDispatch({
    gate: { allowed: true, action_name: 'grant.approve', route_mode: 'hub_only_status' },
    route: { route_mode: 'hub_only_status' },
  });
  assert.equal(String(classify.kind || ''), 'hub_grant_action');
});
