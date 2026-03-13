import assert from 'node:assert/strict';

import {
  buildTelegramHubActionExecutionRequest,
  createTelegramHubActionExecutor,
  executeTelegramHubAction,
} from './TelegramHubActionExecutor.js';

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
      actor: {
        provider: 'telegram',
        external_user_id: '123456',
        external_tenant_id: 'telegram_ops_bot',
      },
      channel: {
        provider: 'telegram',
        account_id: 'telegram_ops_bot',
        conversation_id: '-1001234567890',
        thread_key: 'topic:42',
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

run('TelegramHubActionExecutor builds Hub execution request from orchestrated result', () => {
  const request = buildTelegramHubActionExecutionRequest(makeResult({
    command: {
      ...makeResult().command,
      note: 'approved after review',
    },
  }));
  assert.equal(String(request.request_id || ''), 'telegram:message:1001');
  assert.equal(String(request.action_name || ''), 'supervisor.status.get');
  assert.equal(String(request.scope_id || ''), 'project_alpha');
});

await runAsync('TelegramHubActionExecutor executes Hub query and attaches normalized response', async () => {
  let captured = null;
  const executor = createTelegramHubActionExecutor({
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

await runAsync('TelegramHubActionExecutor converts execution RPC failures into non-throwing execution errors', async () => {
  const out = await executeTelegramHubAction({
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
