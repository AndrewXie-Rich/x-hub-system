import assert from 'node:assert/strict';

import {
  buildWhatsAppCloudHubActionExecutionRequest,
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

await runAsync('WhatsAppCloudHubActionExecutor executes Hub query and attaches normalized response', async () => {
  let captured = null;
  const executor = createWhatsAppCloudHubActionExecutor({
    hub_client: {
      async executeOperatorChannelHubCommand(request) {
        captured = request;
        return {
          ok: true,
          detail: 'query_executed',
          query: {
            action_name: request.action_name,
            project_id: 'project_alpha',
          },
        };
      },
    },
  });

  const out = await executor.execute(makeResult());
  assert.equal(String(captured?.action_name || ''), 'supervisor.status.get');
  assert.equal(String(out.execution?.query?.project_id || ''), 'project_alpha');
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
