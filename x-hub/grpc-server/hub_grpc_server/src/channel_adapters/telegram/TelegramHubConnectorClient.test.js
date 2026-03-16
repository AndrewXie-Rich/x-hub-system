import assert from 'node:assert/strict';

import {
  createTelegramHubConnectorClient,
  telegramConnectorMetadataFromEnv,
} from './TelegramHubConnectorClient.js';

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

run('TelegramHubConnectorClient sends dedicated connector bearer token in metadata', () => {
  const md = telegramConnectorMetadataFromEnv({
    HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
  });
  assert.deepEqual(md.get('authorization'), ['Bearer connector-token-1']);
});

await runAsync('TelegramHubConnectorClient wraps HubRuntime governance RPCs with connector principal', async () => {
  const calls = [];
  const stream = {
    on() {
      return this;
    },
    cancel() {},
  };
  const runtimeClient = {
    ListChannelOnboardingDiscoveryTickets(req, md, cb) {
      calls.push({ method: 'ListChannelOnboardingDiscoveryTickets', req, md });
      cb(null, { updated_at_ms: 1710000000000, tickets: [] });
    },
    CreateOrTouchChannelOnboardingDiscoveryTicket(req, md, cb) {
      calls.push({ method: 'CreateOrTouchChannelOnboardingDiscoveryTicket', req, md });
      cb(null, {
        ok: true,
        created: true,
        updated: false,
        audit_logged: true,
        ticket: {
          ticket_id: 'disc-1',
          provider: req.ticket?.provider || '',
          conversation_id: req.ticket?.conversation_id || '',
          status: 'pending',
        },
      });
    },
    EvaluateChannelCommandGate(req, md, cb) {
      calls.push({ method: 'EvaluateChannelCommandGate', req, md });
      cb(null, { decision: { allowed: true, action_name: req.action_name }, audit_logged: true });
    },
    IngestSupervisorSurface(req, md, cb) {
      calls.push({ method: 'IngestSupervisorSurface', req, md });
      cb(null, { ok: true, ingress: { project_id: req.ingress?.project_id || '' } });
    },
    GetSupervisorBriefProjection(req, md, cb) {
      calls.push({ method: 'GetSupervisorBriefProjection', req, md });
      cb(null, { ok: true, projection: { project_id: req.project_id, status: 'active' } });
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

  const client = createTelegramHubConnectorClient({
    runtimeClient,
    eventsClient,
    env: {
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-2',
      HUB_HOST: '127.0.0.1',
      HUB_PORT: '50051',
    },
  });

  const listed = await client.listChannelOnboardingDiscoveryTickets({
    provider: 'telegram',
    status: 'pending',
  });
  assert.equal(Array.isArray(listed.tickets), true);

  const discovery = await client.createOrTouchChannelOnboardingDiscoveryTicket({
    provider: 'telegram',
    account_id: 'telegram_ops_bot',
    external_user_id: '123456',
    external_tenant_id: 'telegram_ops_bot',
    conversation_id: '-1001',
    thread_key: 'topic:42',
    ingress_surface: 'group',
    first_message_preview: 'deploy.plan',
  }, 'disc-1');
  assert.equal(!!discovery.ok, true);
  assert.equal(String(discovery.ticket?.ticket_id || ''), 'disc-1');

  const gate = await client.evaluateChannelCommandGate({
    request_id: 'gate-1',
    actor: { provider: 'telegram', external_user_id: '123456', external_tenant_id: 'telegram_ops_bot' },
    channel: { provider: 'telegram', account_id: 'telegram_ops_bot', conversation_id: '-1001', thread_key: 'topic:42', channel_scope: 'group' },
    action_name: 'deploy.plan',
    scope_type: 'project',
    scope_id: 'project_alpha',
  });
  assert.equal(!!gate.decision?.allowed, true);

  const route = await client.resolveSupervisorChannelRoute({
    request_id: 'route-1',
    channel: { provider: 'telegram', account_id: 'telegram_ops_bot', conversation_id: '-1001', thread_key: 'topic:42', channel_scope: 'group' },
    action_name: 'deploy.plan',
    project_id: 'project_alpha',
  });
  assert.equal(!!route.ok, true);

  const execution = await client.executeOperatorChannelHubCommand({
    request_id: 'exec-1',
    actor: { provider: 'telegram', external_user_id: '123456', external_tenant_id: 'telegram_ops_bot' },
    channel: { provider: 'telegram', account_id: 'telegram_ops_bot', conversation_id: '-1001', thread_key: 'topic:42', channel_scope: 'group' },
    action_name: 'supervisor.status.get',
    scope_type: 'project',
    scope_id: 'project_alpha',
  });
  assert.equal(String(execution.query?.project_id || ''), 'project_alpha');

  const ingested = await client.ingestSupervisorSurface({
    request_id: 'ingest-1',
    ingress: {
      surface_type: 'telegram',
      normalized_intent_type: 'progress_query',
      project_id: 'project_alpha',
    },
  });
  assert.equal(String(ingested.ingress?.project_id || ''), 'project_alpha');

  const projection = await client.getSupervisorBriefProjection({
    request_id: 'brief-1',
    project_id: 'project_alpha',
    projection_kind: 'progress_brief',
  });
  assert.equal(String(projection.projection?.project_id || ''), 'project_alpha');

  const subscribed = client.subscribeHubEvents({
    scopes: ['grants'],
  });
  assert.equal(subscribed, stream);

  assert.equal(calls.length, 8);
  assert.equal(String(calls[0].method || ''), 'ListChannelOnboardingDiscoveryTickets');
  assert.equal(String(calls[0].req.admin?.device_id || ''), 'hub_operator_channel_connector');
  assert.deepEqual(calls[0].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[1].method || ''), 'CreateOrTouchChannelOnboardingDiscoveryTicket');
  assert.deepEqual(calls[1].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[2].method || ''), 'EvaluateChannelCommandGate');
  assert.equal(String(calls[2].req.admin?.device_id || ''), 'hub_operator_channel_connector');
  assert.deepEqual(calls[2].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[3].method || ''), 'ResolveSupervisorChannelRoute');
  assert.deepEqual(calls[3].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[4].method || ''), 'ExecuteOperatorChannelHubCommand');
  assert.equal(String(calls[4].req.admin?.device_id || ''), 'hub_operator_channel_connector');
  assert.deepEqual(calls[4].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[5].method || ''), 'IngestSupervisorSurface');
  assert.equal(String(calls[5].req.client?.app_id || ''), 'telegram_operator_adapter');
  assert.deepEqual(calls[5].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[6].method || ''), 'GetSupervisorBriefProjection');
  assert.equal(String(calls[6].req.client?.device_id || ''), 'hub_operator_channel_connector');
  assert.deepEqual(calls[6].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[7].method || ''), 'Subscribe');
  assert.equal(String(calls[7].req.client?.app_id || ''), 'telegram_operator_adapter');
  assert.deepEqual(calls[7].req.scopes, ['grants']);
  assert.deepEqual(calls[7].md.get('authorization'), ['Bearer connector-token-2']);
});
