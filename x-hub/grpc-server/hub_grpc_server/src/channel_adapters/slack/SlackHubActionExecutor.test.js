import assert from 'node:assert/strict';

import {
  buildSlackHubActionExecutionRequest,
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

await runAsync('SlackHubActionExecutor executes Hub query and attaches normalized response', async () => {
  let captured = null;
  const executor = createSlackHubActionExecutor({
    hub_client: {
      async executeOperatorChannelHubCommand(request) {
        captured = request;
        return {
          ok: true,
          detail: 'query_executed',
          query: {
            action_name: request.action_name,
            project_id: 'project_alpha',
            heartbeat: {
              project_id: 'project_alpha',
              queue_depth: 3,
            },
          },
        };
      },
    },
  });

  const out = await executor.execute(makeResult());
  assert.equal(String(captured?.action_name || ''), 'supervisor.status.get');
  assert.equal(!!out.execution?.ok, true);
  assert.equal(String(out.execution?.query?.project_id || ''), 'project_alpha');
  assert.equal(Number(out.execution?.query?.heartbeat?.queue_depth || 0), 3);
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
