import assert from 'node:assert/strict';

import {
  buildWhatsAppCloudHubActionExecutionRequest,
  buildWhatsAppCloudSupervisorBriefProjectionRequest,
  createWhatsAppCloudHubActionExecutor,
  executeWhatsAppCloudHubAction,
} from './WhatsAppCloudHubActionExecutor.js';

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
    request_id: 'whatsapp_cloud_api:messages:wamid.1',
    command: {
      actor: {
        provider: 'whatsapp_cloud_api',
        external_user_id: '15551234567',
        external_tenant_id: 'ops_whatsapp_cloud',
      },
      channel: {
        provider: 'whatsapp_cloud_api',
        account_id: 'ops_whatsapp_cloud',
        conversation_id: '15551234567',
        thread_key: 'wamid.1',
        channel_scope: 'dm',
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

run('WhatsAppCloudHubActionExecutor builds Hub execution request from orchestrated result', () => {
  const request = buildWhatsAppCloudHubActionExecutionRequest(makeResult({
    command: {
      ...makeResult().command,
      note: 'approved after review',
    },
  }));
  assert.equal(String(request.request_id || ''), 'whatsapp_cloud_api:messages:wamid.1');
  assert.equal(String(request.action_name || ''), 'supervisor.status.get');
  assert.equal(String(request.scope_id || ''), 'project_alpha');
});

run('WhatsAppCloudHubActionExecutor builds supervisor brief projection requests for project-scoped status actions', () => {
  const request = buildWhatsAppCloudSupervisorBriefProjectionRequest(makeResult());
  assert.equal(String(request.request_id || ''), 'whatsapp_cloud_api:messages:wamid.1');
  assert.equal(String(request.project_id || ''), 'project_alpha');
  assert.equal(String(request.projection_kind || ''), 'progress_brief');
  assert.equal(String(request.trigger || ''), 'user_query');
});

await runAsync('WhatsAppCloudHubActionExecutor executes project-scoped supervisor status via supervisor brief projection RPC', async () => {
  let capturedProjection = null;
  let oldHubRpcCalls = 0;
  const executor = createWhatsAppCloudHubActionExecutor({
    hub_client: {
      async getSupervisorBriefProjection(request) {
        capturedProjection = request;
        return {
          ok: true,
          projection: {
            projection_kind: request.projection_kind,
            project_id: 'project_alpha',
            status: 'awaiting_authorization',
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
  assert.equal(oldHubRpcCalls, 0);
  assert.equal(String(out.execution?.projection?.project_id || ''), 'project_alpha');
});

await runAsync('WhatsAppCloudHubActionExecutor keeps non-status Hub queries on the existing Hub command RPC', async () => {
  let captured = null;
  const out = await executeWhatsAppCloudHubAction({
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

await runAsync('WhatsAppCloudHubActionExecutor converts execution RPC failures into non-throwing execution errors', async () => {
  const out = await executeWhatsAppCloudHubAction({
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
