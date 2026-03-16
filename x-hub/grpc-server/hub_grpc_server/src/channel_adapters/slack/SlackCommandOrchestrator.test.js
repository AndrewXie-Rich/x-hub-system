import assert from 'node:assert/strict';

import {
  compileSlackInteractiveAction,
} from './SlackInteractiveActions.js';
import {
  computeSlackSignature,
  normalizeSlackWebhookRequest,
} from './SlackIngress.js';
import {
  classifySlackCommandDispatch,
  createSlackCommandOrchestrator,
  normalizeSlackCommandInput,
  orchestrateSlackCommand,
} from './SlackCommandOrchestrator.js';

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

function makeSignedHeaders({ signing_secret, raw_body, timestamp_sec }) {
  return {
    'content-type': 'application/json; charset=utf-8',
    'x-slack-request-timestamp': String(timestamp_sec),
    'x-slack-signature': computeSlackSignature({
      signing_secret,
      timestamp_sec,
      raw_body,
    }),
  };
}

function makeSlackDeployEnvelope() {
  const signing_secret = 'slack-signing-secret';
  const payload = {
    type: 'event_callback',
    team_id: 'T001',
    event_id: 'Ev-deploy-1',
    event_time: 1710000000,
    event: {
      type: 'message',
      user: 'U123',
      channel: 'C456',
      channel_type: 'channel',
      text: 'deploy plan',
      ts: '1710000000.1234',
      thread_ts: '1710000000.0001',
      client_msg_id: 'msg-1',
    },
  };
  const raw_body = JSON.stringify(payload);
  return normalizeSlackWebhookRequest({
    headers: makeSignedHeaders({
      signing_secret,
      raw_body,
      timestamp_sec: 1710000005,
    }),
    raw_body,
    signing_secret,
    now_ms: 1710000005000,
  });
}

function makeSlackGrantAction() {
  return compileSlackInteractiveAction({
    type: 'block_actions',
    trigger_id: '1337.42.abcd',
    team: { id: 'T001' },
    user: { id: 'U123' },
    channel: { id: 'C456' },
    container: { channel_id: 'C456', thread_ts: '1710000000.0002' },
    actions: [{
      action_id: 'xt.grant.approve',
      value: JSON.stringify({
        audit_ref: 'audit-slack-grant-1',
        binding_id: 'binding-slack-1',
        scope_type: 'project',
        scope_id: 'payments-prod',
        pending_grant_request_id: 'grant_req_1',
        pending_grant_project_id: 'payments-prod',
        note: 'approved after change review',
      }),
    }],
  });
}

await runAsync('SlackCommandOrchestrator resolves deploy plan to XT dispatch via Hub gate and route', async () => {
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

  const out = await orchestrateSlackCommand({
    input: makeSlackDeployEnvelope(),
    hub_client,
    now_fn: () => 1710000007000,
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.command?.action_name || ''), 'deploy.plan');
  assert.equal(String(out.dispatch?.kind || ''), 'xt_command');
  assert.equal(String(out.route?.route_mode || ''), 'hub_to_xt');
  assert.equal(String(out.route?.resolved_device_id || ''), 'xt-alpha-1');
  assert.equal(calls.length, 2);
  assert.equal(String(calls[0].req.channel?.conversation_id || ''), 'C456');
  assert.equal(String(calls[1].req.binding_id || ''), 'binding-deploy-1');
  assert.equal(String(calls[1].req.project_id || ''), 'project_alpha');
});

await runAsync('SlackCommandOrchestrator keeps approval actions hub-side and forwards pending grant scope', async () => {
  const calls = [];
  const input = makeSlackGrantAction();
  const orchestrator = createSlackCommandOrchestrator({
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

  const out = await orchestrator.handle(input);

  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'hub_grant_action');
  assert.equal(String(out.command?.binding_id || ''), 'binding-slack-1');
  assert.equal(String(out.command?.pending_grant?.grant_request_id || ''), 'grant_req_1');
  assert.equal(String(out.command?.note || ''), 'approved after change review');
  assert.equal(String(calls[0].req.scope_id || ''), 'payments-prod');
  assert.equal(String(calls[1].req.binding_id || ''), 'binding-slack-1');
  assert.equal(String(calls[1].req.project_id || ''), 'payments-prod');
});

await runAsync('SlackCommandOrchestrator short-circuits route on gate deny', async () => {
  let route_called = false;
  const out = await orchestrateSlackCommand({
    input: makeSlackDeployEnvelope(),
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

await runAsync('SlackCommandOrchestrator creates discovery ticket when governed bindings are missing', async () => {
  let route_called = false;
  const discovery_calls = [];
  const out = await orchestrateSlackCommand({
    input: makeSlackDeployEnvelope(),
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
            ticket_id: 'disc-slack-1',
            provider: ticket.provider,
            conversation_id: ticket.conversation_id,
            thread_key: ticket.thread_key,
            recommended_binding_mode: ticket.recommended_binding_mode,
            status: 'pending',
            audit_ref: 'audit-disc-slack-1',
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
  assert.equal(String(out.discovery_ticket?.ticket_id || ''), 'disc-slack-1');
  assert.equal(route_called, false);
  assert.equal(discovery_calls.length, 1);
  assert.equal(String(discovery_calls[0].ticket.provider || ''), 'slack');
  assert.equal(String(discovery_calls[0].ticket.conversation_id || ''), 'C456');
  assert.equal(String(discovery_calls[0].ticket.recommended_binding_mode || ''), 'thread_binding');
});

await runAsync('SlackCommandOrchestrator preserves route-blocked outcomes for offline XT paths', async () => {
  const out = await orchestrateSlackCommand({
    input: makeSlackDeployEnvelope(),
    hub_client: {
      async evaluateChannelCommandGate(req) {
        return {
          decision: {
            allowed: true,
            action_name: req.action_name,
            binding_id: 'binding-deploy-2',
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
            route_mode: 'xt_offline',
            deny_code: 'preferred_device_offline',
            resolved_device_id: 'xt-alpha-1',
            xt_online: false,
          },
        };
      },
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'route_blocked');
  assert.equal(String(out.route?.route_mode || ''), 'xt_offline');
  assert.equal(String(out.route?.deny_code || ''), 'preferred_device_offline');
});

run('SlackCommandOrchestrator fails closed on unsupported local input and exposes normalization helpers', () => {
  const unsupported = normalizeSlackCommandInput({
    envelope_type: 'event_callback',
    actor: { external_user_id: 'U123' },
    channel: { provider: 'slack', conversation_id: 'C1' },
    structured_action: null,
  });
  assert.equal(!!unsupported.ok, false);
  assert.equal(String(unsupported.deny_code || ''), 'structured_action_missing');

  const classify = classifySlackCommandDispatch({
    gate: { allowed: true, action_name: 'grant.approve', route_mode: 'hub_only_status' },
    route: { route_mode: 'hub_only_status' },
  });
  assert.equal(String(classify.kind || ''), 'hub_grant_action');
});
