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

run('TelegramResultPublisher renders onboarding discovery summaries for unknown ingress', () => {
  const out = buildTelegramResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'supervisor.status.get',
    },
    gate: {
      action_name: 'supervisor.status.get',
      deny_code: 'channel_binding_missing',
      route_mode: 'hub_only_status',
    },
    route: {
      route_mode: 'discovery_ticket',
    },
    dispatch: {
      kind: 'discovery_ticket',
    },
    discovery_ticket: {
      ticket_id: 'disc-telegram-1',
      status: 'pending',
      ingress_surface: 'group',
      proposed_scope_type: 'project',
      proposed_scope_id: 'project_alpha',
      recommended_binding_mode: 'thread_binding',
      audit_ref: 'audit-disc-telegram-1',
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Access Pending Approval/);
  assert.match(String(out.payload?.text || ''), /Status: access_pending_approval/);
  assert.match(String(out.payload?.text || ''), /Requested action: supervisor.status.get/);
  assert.match(String(out.payload?.text || ''), /Ticket: disc-telegram-1/);
  assert.match(String(out.payload?.text || ''), /Scope hint: project\/project_alpha/);
  assert.match(String(out.payload?.text || ''), /Audit: audit-disc-telegram-1/);
});

run('TelegramResultPublisher renders supervisor brief projection summaries when projection data is present', () => {
  const out = buildTelegramResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'supervisor.status.get',
    },
    dispatch: {
      kind: 'hub_query',
    },
    execution: {
      ok: true,
      projection: {
        projection_kind: 'progress_brief',
        project_id: 'project_alpha',
        trigger: 'route_repair',
        status: 'attention_required',
        topline: 'Model route diagnosis needed',
        critical_blocker: 'Hub export gate or remote policy is blocking the preferred model route',
        next_best_action: 'Run route diagnose and verify Hub export gate',
        pending_grant_count: 0,
        card_summary: 'MODEL ROUTE: Hub-side downgrade or export gate is overriding the preferred route.',
        audit_ref: 'audit-projection-1',
      },
      route: {
        route_mode: 'hub_only_status',
        resolved_device_id: 'xt-alpha-1',
        xt_online: true,
      },
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Status: supervisor_status/);
  assert.match(String(out.payload?.text || ''), /Project state: attention required/);
  assert.match(String(out.payload?.text || ''), /Topline: Model route diagnosis needed/);
  assert.match(String(out.payload?.text || ''), /Pending grants: 0/);
  assert.match(String(out.payload?.text || ''), /Audit: audit-projection-1/);
});

run('TelegramResultPublisher renders governed heartbeat query summaries when execution query data is present', () => {
  const out = buildTelegramResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'supervisor.blockers.get',
    },
    dispatch: {
      kind: 'hub_query',
    },
    execution: {
      ok: true,
      query: {
        action_name: 'supervisor.blockers.get',
        project_id: 'project_alpha',
        heartbeat_governance_snapshot_json: JSON.stringify({
          status_digest: 'Core loop advancing',
          latest_quality_band: 'usable',
          open_anomaly_types: ['stale_repeat'],
          next_review_due: {
            kind: 'review_pulse',
            due: true,
            due_at_ms: 1710000600000,
          },
        }),
        heartbeat: {
          queue_depth: 3,
          oldest_wait_ms: 9000,
          risk_tier: 'medium',
          blocked_reason: ['awaiting security review'],
          next_actions: ['approve release grant'],
        },
        provider_status: {
          runtime_state: 'ready',
        },
      },
      route: {
        route_mode: 'hub_only_status',
        resolved_device_id: 'xt-alpha-1',
        xt_online: true,
      },
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Status: supervisor_blockers/);
  assert.match(String(out.payload?.text || ''), /Review pressure: quality=usable anomalies=stale_repeat/);
  assert.match(String(out.payload?.text || ''), /Next review: review_pulse due=yes at_ms=1710000600000/);
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
