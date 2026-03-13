import assert from 'node:assert/strict';

import {
  buildSlackHubActionExecutionRequest,
  buildSlackSupervisorBriefProjectionRequest,
  createSlackHubActionExecutor,
  executeSlackHubAction,
} from './SlackHubActionExecutor.js';

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
      actor: {
        provider: 'slack',
        external_user_id: 'U123',
        external_tenant_id: 'T001',
      },
      channel: {
        provider: 'slack',
        account_id: 'ops-slack',
        conversation_id: 'C123',
        thread_key: '1710000000.0001',
        channel_scope: 'group',
      },
      binding_id: 'binding-1',
      action_name: 'supervisor.status.get',
      scope_type: 'project',
      scope_id: 'project_alpha',
      pending_grant: null,
    },
    dispatch: {
      kind: 'hub_query',
    },
    ...overrides,
  };
}

run('SlackHubActionExecutor builds Hub execution request from orchestrated Slack result', () => {
  const request = buildSlackHubActionExecutionRequest(makeResult({
    command: {
      ...makeResult().command,
      note: 'approved after review',
    },
  }));
  assert.equal(String(request.request_id || ''), 'slack:event_callback:Ev-1');
  assert.equal(String(request.actor?.external_user_id || ''), 'U123');
  assert.equal(String(request.channel?.conversation_id || ''), 'C123');
  assert.equal(String(request.action_name || ''), 'supervisor.status.get');
  assert.equal(String(request.scope_id || ''), 'project_alpha');
  assert.equal(String(request.note || ''), 'approved after review');
});

run('SlackHubActionExecutor builds supervisor brief projection requests for project-scoped status actions', () => {
  const request = buildSlackSupervisorBriefProjectionRequest(makeResult());
  assert.equal(String(request.request_id || ''), 'slack:event_callback:Ev-1');
  assert.equal(String(request.project_id || ''), 'project_alpha');
  assert.equal(String(request.projection_kind || ''), 'progress_brief');
  assert.equal(String(request.trigger || ''), 'user_query');
  assert.equal(request.include_card_summary, true);
  assert.equal(request.include_tts_script, false);
  assert.equal(Number(request.max_evidence_refs || 0), 4);
});

await runAsync('SlackHubActionExecutor executes governed XT command dispatches through the same Hub RPC', async () => {
  let captured = null;
  const out = await executeSlackHubAction({
    result: makeResult({
      command: {
        ...makeResult().command,
        action_name: 'deploy.plan',
      },
      dispatch: {
        kind: 'xt_command',
      },
    }),
    hub_client: {
      async executeOperatorChannelHubCommand(request) {
        captured = request;
        return {
          ok: true,
          detail: 'xt command queued',
          xt_command: {
            action_name: 'deploy.plan',
            command_id: 'xtcmd-1',
            project_id: 'project_alpha',
            resolved_device_id: 'xt-alpha-1',
            status: 'queued',
          },
        };
      },
    },
  });
  assert.equal(String(captured?.action_name || ''), 'deploy.plan');
  assert.equal(String(out.execution?.xt_command?.status || ''), 'queued');
});

await runAsync('SlackHubActionExecutor executes project-scoped supervisor status via supervisor brief projection RPC', async () => {
  let capturedProjection = null;
  let oldHubRpcCalls = 0;
  const executor = createSlackHubActionExecutor({
    hub_client: {
      async getSupervisorBriefProjection(request) {
        capturedProjection = request;
        return {
          ok: true,
          projection: {
            projection_kind: request.projection_kind,
            project_id: 'project_alpha',
            status: 'awaiting_authorization',
            topline: 'Release train paused on one approval',
            pending_grant_count: 1,
          },
        };
      },
      async executeOperatorChannelHubCommand() {
        oldHubRpcCalls += 1;
        throw new Error('unexpected_old_hub_query_rpc');
      },
    },
  });

  const out = await executor.execute(makeResult());
  assert.equal(String(capturedProjection?.project_id || ''), 'project_alpha');
  assert.equal(String(capturedProjection?.projection_kind || ''), 'progress_brief');
  assert.equal(String(capturedProjection?.trigger || ''), 'user_query');
  assert.equal(capturedProjection?.include_card_summary, true);
  assert.equal(capturedProjection?.include_tts_script, false);
  assert.equal(oldHubRpcCalls, 0);
  assert.equal(!!out.execution?.ok, true);
  assert.equal(String(out.execution?.projection?.project_id || ''), 'project_alpha');
  assert.equal(String(out.execution?.projection?.status || ''), 'awaiting_authorization');
  assert.equal(Number(out.execution?.projection?.pending_grant_count || 0), 1);
});

await runAsync('SlackHubActionExecutor keeps non-status Hub queries on the existing Hub command RPC', async () => {
  let captured = null;
  const out = await executeSlackHubAction({
    result: makeResult({
      command: {
        ...makeResult().command,
        action_name: 'supervisor.queue.get',
      },
    }),
    hub_client: {
      async executeOperatorChannelHubCommand(request) {
        captured = request;
        return {
          ok: true,
          detail: 'query_executed',
          query: {
            action_name: request.action_name,
            project_id: 'project_alpha',
            queue: {
              planned: true,
              items: [],
            },
          },
        };
      },
    },
  });
  assert.equal(String(captured?.action_name || ''), 'supervisor.queue.get');
  assert.equal(!!out.execution?.ok, true);
  assert.equal(String(out.execution?.query?.project_id || ''), 'project_alpha');
  assert.equal(String(out.execution?.query?.action_name || ''), 'supervisor.queue.get');
});

await runAsync('SlackHubActionExecutor converts execution RPC failures into non-throwing execution errors', async () => {
  const out = await executeSlackHubAction({
    result: makeResult({
      dispatch: {
        kind: 'hub_grant_action',
      },
      command: {
        ...makeResult().command,
        action_name: 'grant.approve',
        pending_grant: {
          grant_request_id: 'gr-1',
          project_id: 'project_alpha',
          status: 'pending',
        },
      },
    }),
    hub_client: {
      async executeOperatorChannelHubCommand() {
        throw new Error('hub_unavailable');
      },
    },
  });
  assert.equal(!!out.execution?.ok, false);
  assert.equal(String(out.execution?.deny_code || ''), 'hub_execution_rpc_failed');
  assert.equal(String(out.execution?.detail || ''), 'hub_unavailable');
});
