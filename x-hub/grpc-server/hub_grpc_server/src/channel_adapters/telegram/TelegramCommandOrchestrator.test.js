import assert from 'node:assert/strict';

import { compileTelegramCallbackAction } from './TelegramInteractiveActions.js';
import {
  classifyTelegramCommandDispatch,
  createTelegramCommandOrchestrator,
  normalizeTelegramCommandInput,
  orchestrateTelegramCommand,
} from './TelegramCommandOrchestrator.js';
import { normalizeTelegramUpdate } from './TelegramIngress.js';

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

function makeTelegramDeployEnvelope() {
  return normalizeTelegramUpdate({
    update_id: 1001,
    message: {
      message_id: 88,
      text: 'deploy plan',
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

function makeTelegramGrantAction() {
  return compileTelegramCallbackAction({
    update_id: 1002,
    callback_query: {
      id: 'cbq_1',
      data: 'xt|ga|grant_req_1|payments-prod',
      from: {
        id: 123456,
      },
      message: {
        message_id: 89,
        message_thread_id: 42,
        chat: {
          id: -1001234567890,
          type: 'supergroup',
        },
      },
    },
  }, {
    account_id: 'telegram_ops_bot',
  });
}

run('TelegramCommandOrchestrator classifies route blocked and XT routes', () => {
  assert.equal(String(classifyTelegramCommandDispatch({
    gate: { allowed: true, action_name: 'deploy.plan', route_mode: 'hub_to_xt' },
    route: { route_mode: 'hub_to_xt' },
  }).kind || ''), 'xt_command');
  assert.equal(String(classifyTelegramCommandDispatch({
    gate: { allowed: false, action_name: 'deploy.plan' },
  }).kind || ''), 'deny');
});

run('TelegramCommandOrchestrator normalizes callback actions with pending grant scope', () => {
  const out = normalizeTelegramCommandInput(makeTelegramGrantAction(), {
    now_ms: 1710000010000,
  });
  assert.equal(!!out.ok, true);
  assert.equal(String(out.action_name || ''), 'grant.approve');
  assert.equal(String(out.scope_id || ''), 'payments-prod');
  assert.equal(String(out.pending_grant?.project_id || ''), 'payments-prod');
});

await runAsync('TelegramCommandOrchestrator resolves deploy plan to XT dispatch via Hub gate and route', async () => {
  const calls = [];
  const out = await orchestrateTelegramCommand({
    input: makeTelegramDeployEnvelope(),
    hub_client: {
      async evaluateChannelCommandGate(req) {
        calls.push({ method: 'gate', req });
        return {
          decision: {
            allowed: true,
            action_name: req.action_name,
            binding_id: 'binding-telegram-1',
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
          route: {
            route_mode: 'hub_to_xt',
            resolved_device_id: 'xt-alpha-1',
          },
        };
      },
    },
    now_fn: () => 1710000007000,
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'xt_command');
  assert.equal(String(out.route?.resolved_device_id || ''), 'xt-alpha-1');
  assert.equal(String(calls[0].req.channel?.conversation_id || ''), '-1001234567890');
});

await runAsync('TelegramCommandOrchestrator keeps approval actions hub-side and forwards pending grant scope', async () => {
  const calls = [];
  const orchestrator = createTelegramCommandOrchestrator({
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

  const out = await orchestrator.handle(makeTelegramGrantAction());

  assert.equal(!!out.ok, true);
  assert.equal(String(out.dispatch?.kind || ''), 'hub_grant_action');
  assert.equal(String(out.command?.pending_grant?.grant_request_id || ''), 'grant_req_1');
  assert.equal(String(calls[0].req.scope_id || ''), 'payments-prod');
});

await runAsync('TelegramCommandOrchestrator creates discovery ticket when governed bindings are missing', async () => {
  let route_called = false;
  const discovery_calls = [];
  const out = await orchestrateTelegramCommand({
    input: makeTelegramDeployEnvelope(),
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
      async createOrTouchChannelOnboardingDiscoveryTicket(ticket, request_id) {
        discovery_calls.push({ ticket, request_id });
        return {
          ok: true,
          created: true,
          updated: false,
          audit_logged: true,
          ticket: {
            ticket_id: 'disc-telegram-1',
            provider: ticket.provider,
            conversation_id: ticket.conversation_id,
            thread_key: ticket.thread_key,
            recommended_binding_mode: ticket.recommended_binding_mode,
            status: 'pending',
            audit_ref: 'audit-disc-telegram-1',
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
  assert.equal(String(out.discovery_ticket?.ticket_id || ''), 'disc-telegram-1');
  assert.equal(route_called, false);
  assert.equal(discovery_calls.length, 1);
  assert.equal(String(discovery_calls[0].ticket.provider || ''), 'telegram');
  assert.equal(String(discovery_calls[0].ticket.conversation_id || ''), '-1001234567890');
  assert.equal(String(discovery_calls[0].ticket.recommended_binding_mode || ''), 'thread_binding');
});

run('TelegramCommandOrchestrator derives actor identity from stable Telegram ids, not display text', () => {
  const normalized = normalizeTelegramCommandInput({
    envelope_type: 'message',
    actor: {
      external_user_id: '123456',
      external_tenant_id: 'telegram_ops_bot',
      username: 'alice_ops',
      display_name: 'Alice Visible',
    },
    channel: {
      provider: 'telegram',
      account_id: 'telegram_ops_bot',
      conversation_id: '-1001234567890',
      thread_key: 'topic:42',
      channel_scope: 'group',
    },
    structured_action: {
      action_name: 'deploy.plan',
    },
  }, {
    now_ms: 1710000012000,
  });

  assert.equal(!!normalized.ok, true);
  assert.equal(String(normalized.actor?.external_user_id || ''), '123456');
  assert.equal(String(normalized.actor?.external_tenant_id || ''), 'telegram_ops_bot');
  assert.equal(String(normalized.actor?.stable_external_id || ''), 'telegram/telegram_ops_bot/123456');
});
