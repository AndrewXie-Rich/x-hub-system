import assert from 'node:assert/strict';

import {
  buildFeishuHubActionExecutionRequest,
  buildFeishuSupervisorBriefProjectionRequest,
  createFeishuHubActionExecutor,
  executeFeishuHubAction,
} from './FeishuHubActionExecutor.js';

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
      actor: {
        provider: 'feishu',
        external_user_id: 'ou_user_1',
        external_tenant_id: 'tenant-ops',
      },
      channel: {
        provider: 'feishu',
        account_id: 'tenant-ops',
        conversation_id: 'oc_room_1',
        thread_key: 'om_anchor_1',
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

run('FeishuHubActionExecutor builds Hub execution request from orchestrated result', () => {
  const request = buildFeishuHubActionExecutionRequest(makeResult({
    command: {
      ...makeResult().command,
      note: 'approved after review',
    },
  }));
  assert.equal(String(request.request_id || ''), 'feishu:event_callback:Ev-1');
  assert.equal(String(request.action_name || ''), 'supervisor.status.get');
  assert.equal(String(request.scope_id || ''), 'project_alpha');
});

run('FeishuHubActionExecutor builds supervisor brief projection requests for project-scoped status actions', () => {
  const request = buildFeishuSupervisorBriefProjectionRequest(makeResult());
  assert.equal(String(request.request_id || ''), 'feishu:event_callback:Ev-1');
  assert.equal(String(request.project_id || ''), 'project_alpha');
  assert.equal(String(request.projection_kind || ''), 'progress_brief');
  assert.equal(String(request.trigger || ''), 'user_query');
  assert.equal(request.include_card_summary, true);
  assert.equal(request.include_tts_script, false);
  assert.equal(Number(request.max_evidence_refs || 0), 4);
});

await runAsync('FeishuHubActionExecutor executes project-scoped supervisor status via supervisor brief projection RPC', async () => {
  let capturedProjection = null;
  let oldHubRpcCalls = 0;
  const executor = createFeishuHubActionExecutor({
    hub_client: {
      async getSupervisorBriefProjection(request) {
        capturedProjection = request;
        return {
          ok: true,
          projection: {
            projection_kind: request.projection_kind,
            project_id: 'project_alpha',
            status: 'awaiting_authorization',
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
  assert.equal(oldHubRpcCalls, 0);
  assert.equal(String(out.execution?.projection?.project_id || ''), 'project_alpha');
});

await runAsync('FeishuHubActionExecutor keeps non-status Hub queries on the existing Hub command RPC', async () => {
  let captured = null;
  const out = await executeFeishuHubAction({
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
          query: {
            action_name: request.action_name,
            project_id: 'project_alpha',
          },
        };
      },
    },
  });
  assert.equal(String(captured?.action_name || ''), 'supervisor.queue.get');
  assert.equal(String(out.execution?.query?.action_name || ''), 'supervisor.queue.get');
});

await runAsync('FeishuHubActionExecutor converts execution RPC failures into non-throwing execution errors', async () => {
  const out = await executeFeishuHubAction({
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
});
