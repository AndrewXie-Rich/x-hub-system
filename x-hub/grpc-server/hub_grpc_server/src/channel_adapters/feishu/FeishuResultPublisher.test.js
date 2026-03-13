import assert from 'node:assert/strict';

import {
  buildFeishuGrantDecisionSummary,
  buildFeishuGrantPendingCard,
  buildFeishuResultSummary,
  createFeishuResultPublisher,
  publishFeishuCommandResult,
  publishFeishuGrantDecision,
  publishFeishuGrantPending,
} from './FeishuResultPublisher.js';

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
    request_id: 'feishu:event_callback:Ev-1',
    command: {
      action_name: 'deploy.plan',
      audit_ref: 'audit-1',
      route_project_id: 'project_alpha',
      channel: {
        provider: 'feishu',
        account_id: 'tenant-ops',
        conversation_id: 'oc_room_1',
        thread_key: 'om_anchor_1',
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

run('FeishuResultPublisher builds routed summary payload from orchestration result', () => {
  const out = buildFeishuResultSummary(makeResult());
  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.receive_id || ''), 'oc_room_1');
  assert.equal(String(out.payload?.reply_to_message_id || ''), 'om_anchor_1');
  const card = JSON.parse(String(out.payload?.content || '{}'));
  const markdown = String(card.body?.elements?.[0]?.content || '');
  assert.match(markdown, /project_alpha/);
  assert.match(markdown, /Action: deploy.plan/);
});

run('FeishuResultPublisher reflects deny and route blocked outcomes in summary copy', () => {
  const denied = buildFeishuResultSummary(makeResult({
    gate: {
      action_name: 'deploy.plan',
      deny_code: 'role_not_allowed',
      route_mode: 'hub_to_xt',
    },
    route: null,
    dispatch: { kind: 'deny' },
  }));
  assert.equal(!!denied.ok, true);
  assert.match(String(denied.payload?.content || ''), /denied/);
  assert.match(String(denied.payload?.content || ''), /role_not_allowed/);

  const blocked = buildFeishuResultSummary(makeResult({
    route: {
      route_mode: 'xt_offline',
      resolved_device_id: 'xt-alpha-1',
      deny_code: 'preferred_device_offline',
    },
    dispatch: { kind: 'route_blocked' },
  }));
  assert.equal(!!blocked.ok, true);
  assert.match(String(blocked.payload?.content || ''), /route_blocked/);
  assert.match(String(blocked.payload?.content || ''), /xt-alpha-1/);
});

run('FeishuResultPublisher renders actual governed XT command summaries when execution data is present', () => {
  const out = buildFeishuResultSummary(makeResult({
    execution: {
      ok: true,
      xt_command: {
        action_name: 'deploy.plan',
        command_id: 'xtcmd-1',
        project_id: 'project_alpha',
        resolved_device_id: 'xt-alpha-1',
        status: 'prepared',
        detail: 'automation prepared',
        run_id: 'run-1',
        audit_ref: 'audit-xt-1',
      },
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.content || ''), /XT Command Prepared/);
  assert.match(String(out.payload?.content || ''), /run-1/);
});

run('FeishuResultPublisher builds proactive grant decision summaries from Hub events', () => {
  const out = buildFeishuGrantDecisionSummary({
    event: {
      event_id: 'evt_grant_1',
      grant_request_id: 'gr-evt-1',
      decision: 'GRANT_DECISION_APPROVED',
      project_id: 'project_alpha',
      grant: {
        grant_id: 'grant-evt-1',
        capability: 'CAPABILITY_WEB_FETCH',
        expires_at_ms: 1710009999000,
        status: 'active',
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
      provider: 'feishu',
      account_id: 'tenant-ops',
      conversation_id: 'oc_room_1',
      thread_key: 'om_anchor_1',
    },
  });

  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.content || ''), /Grant Approved/);
  assert.match(String(out.payload?.content || ''), /web.fetch/);
  assert.match(String(out.payload?.content || ''), /gr-evt-1/);
});

run('FeishuResultPublisher builds proactive pending approval cards from queued Hub events', () => {
  const out = buildFeishuGrantPendingCard({
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
      binding_id: 'binding-feishu-approval',
      provider: 'feishu',
      account_id: 'tenant-ops',
      conversation_id: 'oc_room_1',
      thread_key: 'om_anchor_1',
      scope_type: 'project',
      scope_id: 'project_alpha',
    },
  });

  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.content || ''), /Approval Required/);
  assert.match(String(out.payload?.content || ''), /web.fetch/);
  assert.match(String(out.payload?.content || ''), /gr-pending-1/);
});

await runAsync('FeishuResultPublisher sends summary payload through Feishu API client', async () => {
  let posted = null;
  const out = await publishFeishuCommandResult({
    result: makeResult(),
    feishu_client: {
      async postMessage(payload) {
        posted = payload;
        return {
          ok: true,
          message_id: 'om_sent_1',
        };
      },
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(posted?.receive_id || ''), 'oc_room_1');
  assert.equal(String(out.delivered?.message_id || ''), 'om_sent_1');
});

await runAsync('FeishuResultPublisher sends proactive grant decision payload through Feishu API client', async () => {
  let posted = null;
  const out = await publishFeishuGrantDecision({
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
      provider: 'feishu',
      account_id: 'tenant-ops',
      conversation_id: 'oc_room_1',
      thread_key: 'om_anchor_1',
    },
    feishu_client: {
      async postMessage(payload) {
        posted = payload;
        return {
          ok: true,
          message_id: 'om_sent_2',
        };
      },
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(posted?.reply_to_message_id || ''), 'om_anchor_1');
  assert.match(String(posted?.content || ''), /policy_denied/);
});

await runAsync('FeishuResultPublisher sends proactive pending approval payload through Feishu API client', async () => {
  let posted = null;
  const out = await publishFeishuGrantPending({
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
      binding_id: 'binding-feishu-approval',
      provider: 'feishu',
      account_id: 'tenant-ops',
      conversation_id: 'oc_room_1',
      thread_key: 'om_anchor_1',
      scope_type: 'project',
      scope_id: 'project_alpha',
    },
    feishu_client: {
      async postMessage(payload) {
        posted = payload;
        return {
          ok: true,
          message_id: 'om_sent_pending_1',
        };
      },
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(posted?.reply_to_message_id || ''), 'om_anchor_1');
  assert.match(String(posted?.content || ''), /web.fetch/);
});

await runAsync('FeishuResultPublisher exposes publisher wrapper', async () => {
  const publisher = createFeishuResultPublisher({
    feishu_client: {
      async postMessage(payload) {
        return {
          ok: true,
          message_id: payload.reply_to_message_id || 'om_sent_2',
        };
      },
    },
  });

  const built = publisher.build(makeResult());
  assert.equal(!!built.ok, true);
  const sent = await publisher.publish(makeResult());
  assert.equal(!!sent.ok, true);
  assert.equal(String(sent.delivered?.message_id || ''), 'om_anchor_1');
});
