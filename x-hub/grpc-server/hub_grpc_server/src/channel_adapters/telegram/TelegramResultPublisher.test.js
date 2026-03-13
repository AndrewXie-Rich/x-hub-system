import assert from 'node:assert/strict';

import {
  buildTelegramGrantDecisionSummary,
  buildTelegramGrantPendingMessage,
  buildTelegramResultSummary,
  createTelegramResultPublisher,
  publishTelegramCommandResult,
  publishTelegramGrantDecision,
  publishTelegramGrantPending,
} from './TelegramResultPublisher.js';

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

function makeResult(overrides = {}) {
  return {
    request_id: 'telegram:message:1001',
    command: {
      action_name: 'deploy.plan',
      audit_ref: 'audit-1',
      route_project_id: 'project_alpha',
      channel: {
        provider: 'telegram',
        account_id: 'telegram_ops_bot',
        conversation_id: '-1001234567890',
        thread_key: 'topic:42',
      },
    },
    gate: {
      action_name: 'deploy.plan',
      scope_type: 'project',
      scope_id: 'project_alpha',
      route_mode: 'hub_to_xt',
      deny_code: '',
    },
    route: {
      route_mode: 'hub_to_xt',
      resolved_device_id: 'xt-alpha-1',
      deny_code: '',
    },
    dispatch: {
      kind: 'xt_command',
    },
    ...overrides,
  };
}

run('TelegramResultPublisher builds routed summary payload', () => {
  const out = buildTelegramResultSummary(makeResult());
  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.chat_id || ''), '-1001234567890');
  assert.equal(Number(out.payload?.message_thread_id || 0), 42);
  assert.match(String(out.payload?.text || ''), /project_alpha/);
});

run('TelegramResultPublisher builds proactive grant decision summaries', () => {
  const out = buildTelegramGrantDecisionSummary({
    event: {
      event_id: 'evt_grant_1',
      grant_request_id: 'gr-evt-1',
      decision: 'GRANT_DECISION_APPROVED',
      project_id: 'project_alpha',
      grant: {
        grant_id: 'grant-1',
        capability: 'CAPABILITY_WEB_FETCH',
        expires_at_ms: 1710009999000,
        client: {
          device_id: 'xt-alpha-1',
          project_id: 'project_alpha',
        },
      },
      client: {
        device_id: 'xt-alpha-1',
        project_id: 'project_alpha',
      },
    },
    binding: {
      provider: 'telegram',
      conversation_id: '-1001234567890',
      thread_key: 'topic:42',
    },
  });
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Grant Approved/);
  assert.match(String(out.payload?.text || ''), /web.fetch/);
});

run('TelegramResultPublisher builds proactive pending approval messages', () => {
  const out = buildTelegramGrantPendingMessage({
    event: {
      event_id: 'evt_grant_pending_1',
      grant_request_id: 'gr-pending-1',
      decision: 'GRANT_DECISION_QUEUED',
      project_id: 'project_alpha',
      grant: {
        capability: 'CAPABILITY_WEB_FETCH',
        token_cap: 5000,
        client: {
          device_id: 'xt-alpha-1',
          project_id: 'project_alpha',
        },
      },
      client: {
        device_id: 'xt-alpha-1',
        project_id: 'project_alpha',
      },
    },
    binding: {
      binding_id: 'binding-telegram-approval',
      provider: 'telegram',
      conversation_id: '-1001234567890',
      thread_key: 'topic:42',
      scope_type: 'project',
      scope_id: 'project_alpha',
    },
  });
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Approval Required/);
});

await runAsync('TelegramResultPublisher posts messages through Telegram API client shape', async () => {
  const calls = [];
  const out = await publishTelegramCommandResult({
    result: makeResult(),
    telegram_client: {
      async postMessage(payload) {
        calls.push(payload);
        return {
          ok: true,
          message_id: 88,
        };
      },
    },
  });
  assert.equal(!!out.ok, true);
  assert.equal(calls.length, 1);
});

await runAsync('TelegramResultPublisher posts proactive grant decision and pending messages', async () => {
  const calls = [];
  const client = {
    async postMessage(payload) {
      calls.push(payload);
      return {
        ok: true,
        message_id: 89,
      };
    },
  };
  const decision = await publishTelegramGrantDecision({
    event: {
      event_id: 'evt_grant_2',
      grant_request_id: 'gr-evt-2',
      decision: 'GRANT_DECISION_DENIED',
      project_id: 'project_alpha',
      deny_reason: 'policy_denied',
      client: {
        device_id: 'xt-alpha-1',
        project_id: 'project_alpha',
      },
    },
    binding: {
      provider: 'telegram',
      conversation_id: '-1001234567890',
      thread_key: 'topic:42',
    },
    telegram_client: client,
  });
  const pending = await publishTelegramGrantPending({
    event: {
      event_id: 'evt_grant_pending_2',
      grant_request_id: 'gr-pending-2',
      decision: 'GRANT_DECISION_QUEUED',
      project_id: 'project_alpha',
      grant: {
        capability: 'CAPABILITY_WEB_FETCH',
        token_cap: 2048,
        client: {
          device_id: 'xt-alpha-1',
          project_id: 'project_alpha',
        },
      },
      client: {
        device_id: 'xt-alpha-1',
        project_id: 'project_alpha',
      },
    },
    binding: {
      binding_id: 'binding-telegram-approval',
      provider: 'telegram',
      conversation_id: '-1001234567890',
      thread_key: 'topic:42',
      scope_type: 'project',
      scope_id: 'project_alpha',
    },
    telegram_client: client,
  });

  assert.equal(!!decision.ok, true);
  assert.equal(!!pending.ok, true);
  assert.equal(calls.length, 2);
});

await runAsync('TelegramResultPublisher factory fails closed when client is invalid', async () => {
  const publisher = createTelegramResultPublisher({
    telegram_client: null,
  });
  const out = await publisher.publish(makeResult());
  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'telegram_client_invalid');
});
