import assert from 'node:assert/strict';

import {
  createSlackHubConnectorClient,
  slackConnectorMetadataFromEnv,
} from './SlackHubConnectorClient.js';

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

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

run('SlackHubConnectorClient sends dedicated connector bearer token in metadata', () => {
  withEnv(
    {
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
    },
    () => {
      const md = slackConnectorMetadataFromEnv(process.env);
      assert.deepEqual(md.get('authorization'), ['Bearer connector-token-1']);
    }
  );
});

async function withEnvAsync(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

await runAsync('SlackHubConnectorClient wraps HubRuntime governance RPCs with connector principal', async () => {
  const calls = [];
  const stream = {
    on() {
      return this;
    },
    cancel() {},
  };
  const runtimeClient = {
    EvaluateChannelCommandGate(req, md, cb) {
      calls.push({ method: 'EvaluateChannelCommandGate', req, md });
      cb(null, { decision: { allowed: true, action_name: req.action_name }, audit_logged: true });
    },
    ResolveSupervisorChannelRoute(req, md, cb) {
      calls.push({ method: 'ResolveSupervisorChannelRoute', req, md });
      cb(null, { ok: true, route: { route_mode: 'hub_to_xt', resolved_device_id: 'xt-1' } });
    },
    ExecuteOperatorChannelHubCommand(req, md, cb) {
      calls.push({ method: 'ExecuteOperatorChannelHubCommand', req, md });
      cb(null, {
        ok: true,
        detail: 'query_executed',
        query: {
          action_name: req.action_name,
          project_id: 'project_alpha',
        },
      });
    },
    close() {},
  };
  const eventsClient = {
    Subscribe(req, md) {
      calls.push({ method: 'Subscribe', req, md });
      return stream;
    },
    close() {},
  };

  await withEnvAsync(
    {
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-2',
      HUB_HOST: '127.0.0.1',
      HUB_PORT: '50051',
    },
    async () => {
      const client = createSlackHubConnectorClient({
        runtimeClient,
        eventsClient,
        env: process.env,
      });
      const gate = await client.evaluateChannelCommandGate({
        request_id: 'gate-1',
        actor: { provider: 'slack', external_user_id: 'U123', external_tenant_id: 'T001' },
        channel: { provider: 'slack', account_id: 'T001', conversation_id: 'C001', thread_key: '171.1', channel_scope: 'group' },
        action_name: 'deploy.plan',
        scope_type: 'project',
        scope_id: 'project_alpha',
      });
      assert.equal(!!gate.decision?.allowed, true);

      const route = await client.resolveSupervisorChannelRoute({
        request_id: 'route-1',
        channel: { provider: 'slack', account_id: 'T001', conversation_id: 'C001', thread_key: '171.1', channel_scope: 'group' },
        action_name: 'deploy.plan',
        project_id: 'project_alpha',
      });
      assert.equal(!!route.ok, true);
      assert.equal(String(route.route?.resolved_device_id || ''), 'xt-1');

      const execution = await client.executeOperatorChannelHubCommand({
        request_id: 'exec-1',
        actor: { provider: 'slack', external_user_id: 'U123', external_tenant_id: 'T001' },
        channel: { provider: 'slack', account_id: 'T001', conversation_id: 'C001', thread_key: '171.1', channel_scope: 'group' },
        action_name: 'supervisor.status.get',
        scope_type: 'project',
        scope_id: 'project_alpha',
      });
      assert.equal(!!execution.ok, true);
      assert.equal(String(execution.query?.project_id || ''), 'project_alpha');

      const subscribed = client.subscribeHubEvents({
        scopes: ['grants'],
      });
      assert.equal(subscribed, stream);
    }
  );

  assert.equal(calls.length, 4);
  assert.equal(String(calls[0].method || ''), 'EvaluateChannelCommandGate');
  assert.equal(String(calls[0].req.admin?.device_id || ''), 'hub_operator_channel_connector');
  assert.deepEqual(calls[0].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[1].method || ''), 'ResolveSupervisorChannelRoute');
  assert.deepEqual(calls[1].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[2].method || ''), 'ExecuteOperatorChannelHubCommand');
  assert.equal(String(calls[2].req.admin?.device_id || ''), 'hub_operator_channel_connector');
  assert.deepEqual(calls[2].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[3].method || ''), 'Subscribe');
  assert.equal(String(calls[3].req.client?.app_id || ''), 'slack_operator_adapter');
  assert.deepEqual(calls[3].req.scopes, ['grants']);
  assert.deepEqual(calls[3].md.get('authorization'), ['Bearer connector-token-2']);
});
