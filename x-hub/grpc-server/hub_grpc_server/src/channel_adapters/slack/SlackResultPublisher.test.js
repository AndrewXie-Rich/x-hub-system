import assert from 'node:assert/strict';

import {
  buildSlackGrantDecisionSummary,
  buildSlackGrantPendingCard,
  buildSlackResultSummary,
  createSlackResultPublisher,
  publishSlackCommandResult,
  publishSlackGrantDecision,
  publishSlackGrantPending,
} from './SlackResultPublisher.js';

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
    request_id: 'slack:event_callback:Ev-1',
    command: {
      action_name: 'deploy.plan',
      audit_ref: 'audit-1',
      route_project_id: 'project_alpha',
      channel: {
        provider: 'slack',
        account_id: 'ops_bot',
        conversation_id: 'C123',
        thread_key: '1710000000.0001',
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

run('SlackResultPublisher builds routed summary payload from orchestration result', () => {
  const out = buildSlackResultSummary(makeResult());
  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.channel || ''), 'C123');
  assert.equal(String(out.payload?.thread_ts || ''), '1710000000.0001');
  assert.equal(String(out.payload?.metadata?.event_payload?.status || ''), 'routed_to_xt');
  assert.match(String(out.payload?.text || ''), /project=project_alpha/);
  assert.match(String(out.payload?.text || ''), /Action: deploy.plan/);
});

run('SlackResultPublisher reflects deny and route blocked outcomes in summary copy', () => {
  const denied = buildSlackResultSummary(makeResult({
    gate: {
      action_name: 'deploy.plan',
      deny_code: 'role_not_allowed',
      route_mode: 'hub_to_xt',
    },
    route: null,
    dispatch: { kind: 'deny' },
  }));
  assert.equal(!!denied.ok, true);
  assert.match(String(denied.payload?.text || ''), /status=denied/);
  assert.match(String(denied.payload?.text || ''), /Reason: role_not_allowed/);

  const blocked = buildSlackResultSummary(makeResult({
    route: {
      route_mode: 'xt_offline',
      resolved_device_id: 'xt-alpha-1',
      deny_code: 'preferred_device_offline',
    },
    dispatch: { kind: 'route_blocked' },
  }));
  assert.equal(!!blocked.ok, true);
  assert.match(String(blocked.payload?.text || ''), /status=route_blocked/);
  assert.match(String(blocked.payload?.text || ''), /Device: xt-alpha-1/);
});

run('SlackResultPublisher renders supervisor brief projection summaries when projection data is present', () => {
  const out = buildSlackResultSummary(makeResult({
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
        trigger: 'awaiting_authorization',
        status: 'awaiting_authorization',
        topline: 'Release train paused on one approval',
        critical_blocker: 'awaiting security review',
        next_best_action: 'Review 1 pending grant request',
        pending_grant_count: 1,
        card_summary: 'One pending grant is blocking the release train.',
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
  assert.match(String(out.payload?.text || ''), /status=supervisor_status/);
  assert.match(String(out.payload?.text || ''), /Topline: Release train paused on one approval/);
  assert.match(String(out.payload?.text || ''), /Blocker: awaiting security review/);
  assert.match(String(out.payload?.text || ''), /Next: Review 1 pending grant request/);
  assert.match(String(out.payload?.text || ''), /Pending grants: 1/);
  assert.match(String(out.payload?.text || ''), /Device: xt-alpha-1/);
  assert.equal(String(out.payload?.metadata?.event_payload?.audit_ref || ''), 'audit-projection-1');
});

run('SlackResultPublisher renders legacy Hub blocker query summaries when execution query data is present', () => {
  const out = buildSlackResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'supervisor.blockers.get',
    },
    dispatch: {
      kind: 'hub_query',
    },
    execution: {
      ok: true,
      route: {
        route_mode: 'hub_only_status',
        resolved_device_id: 'xt-alpha-1',
        xt_online: true,
      },
      query: {
        action_name: 'supervisor.blockers.get',
        project_id: 'project_alpha',
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
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /status=supervisor_blockers/);
  assert.match(String(out.payload?.text || ''), /Blockers: awaiting security review/);
  assert.match(String(out.payload?.text || ''), /Next actions: approve release grant/);
});

run('SlackResultPublisher renders governed XT command execution summaries when execution data is present', () => {
  const out = buildSlackResultSummary(makeResult({
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
  assert.match(String(out.payload?.text || ''), /XT Command Prepared/);
  assert.match(String(out.payload?.text || ''), /status=xt_command_prepared/);
  assert.match(String(out.payload?.text || ''), /Run: run-1/);
});

run('SlackResultPublisher renders actual grant decision summaries when execution data is present', () => {
  const out = buildSlackResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'grant.approve',
      pending_grant: {
        grant_request_id: 'gr-1',
        project_id: 'project_alpha',
        status: 'pending',
      },
    },
    dispatch: {
      kind: 'hub_grant_action',
    },
    execution: {
      ok: true,
      grant_action: {
        action_name: 'grant.approve',
        grant_request_id: 'gr-1',
        decision: 'approved',
        note: 'approved after release review',
        grant: {
          grant_id: 'grant-1',
          client: {
            project_id: 'project_alpha',
          },
          status: 'active',
          expires_at_ms: 1710009999000,
        },
      },
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Grant Approved/);
  assert.match(String(out.payload?.text || ''), /status=grant_approved/);
  assert.match(String(out.payload?.text || ''), /Grant request: gr-1/);
  assert.match(String(out.payload?.text || ''), /Note: approved after release review/);
});

run('SlackResultPublisher renders execution failures without dropping the Slack reply', () => {
  const out = buildSlackResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'supervisor.queue.get',
    },
    dispatch: {
      kind: 'hub_query',
    },
    execution: {
      ok: false,
      deny_code: 'project_scope_missing',
      detail: 'queue view requires project scope',
      route: {
        route_mode: 'hub_only_status',
      },
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Hub Command Failed/);
  assert.match(String(out.payload?.text || ''), /status=hub_execution_failed/);
  assert.match(String(out.payload?.text || ''), /Reason: project_scope_missing/);
});

run('SlackResultPublisher builds proactive grant decision summaries from Hub events', () => {
  const out = buildSlackGrantDecisionSummary({
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
      provider: 'slack',
      account_id: 'ops_bot',
      conversation_id: 'C123',
      thread_key: '1710000000.0001',
    },
  });

  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Grant Approved/);
  assert.match(String(out.payload?.text || ''), /Capability: web.fetch/);
  assert.match(String(out.payload?.text || ''), /Grant request: gr-evt-1/);
});

run('SlackResultPublisher builds proactive pending approval cards from queued Hub events', () => {
  const out = buildSlackGrantPendingCard({
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
      binding_id: 'binding-slack-approval',
      provider: 'slack',
      account_id: 'ops_bot',
      conversation_id: 'C123',
      thread_key: '1710000000.0001',
      scope_type: 'project',
      scope_id: 'project_alpha',
    },
  });

  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Approval Required/);
  assert.match(JSON.stringify(out.payload?.blocks || []), /xt\.grant\.approve/);
  assert.match(JSON.stringify(out.payload?.blocks || []), /web\.fetch/);
});

await runAsync('SlackResultPublisher posts summary payload through SlackApiClient shape', async () => {
  const calls = [];
  const out = await publishSlackCommandResult({
    result: makeResult(),
    slack_client: {
      async postMessage(payload) {
        calls.push(payload);
        return {
          ok: true,
          message_ts: '1710000000.0002',
        };
      },
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(calls.length, 1);
  assert.equal(String(calls[0]?.channel || ''), 'C123');
  assert.equal(String(out.delivered?.message_ts || ''), '1710000000.0002');
});

await runAsync('SlackResultPublisher posts proactive grant decision summaries through SlackApiClient shape', async () => {
  const calls = [];
  const out = await publishSlackGrantDecision({
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
      provider: 'slack',
      account_id: 'ops_bot',
      conversation_id: 'C123',
      thread_key: '1710000000.0001',
    },
    slack_client: {
      async postMessage(payload) {
        calls.push(payload);
        return {
          ok: true,
          message_ts: '1710000000.0003',
        };
      },
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(calls.length, 1);
  assert.match(String(calls[0]?.text || ''), /Reason: policy_denied/);
});

await runAsync('SlackResultPublisher posts proactive pending approval cards through SlackApiClient shape', async () => {
  const calls = [];
  const out = await publishSlackGrantPending({
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
      binding_id: 'binding-slack-approval',
      provider: 'slack',
      account_id: 'ops_bot',
      conversation_id: 'C123',
      thread_key: '1710000000.0001',
      scope_type: 'project',
      scope_id: 'project_alpha',
    },
    slack_client: {
      async postMessage(payload) {
        calls.push(payload);
        return {
          ok: true,
          message_ts: '1710000000.0004',
        };
      },
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(calls.length, 1);
  assert.match(JSON.stringify(calls[0]?.blocks || []), /xt\.grant\.approve/);
});

await runAsync('SlackResultPublisher factory fails closed when Slack client is invalid', async () => {
  const publisher = createSlackResultPublisher({
    slack_client: null,
  });
  const out = await publisher.publish(makeResult());
  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'slack_client_invalid');
});
