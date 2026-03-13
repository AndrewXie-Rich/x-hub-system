import assert from 'node:assert/strict';

import {
  createWhatsAppCloudHubConnectorClient,
  whatsappCloudConnectorMetadataFromEnv,
} from './WhatsAppCloudHubConnectorClient.js';

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

run('WhatsAppCloudHubConnectorClient sends dedicated connector bearer token in metadata', () => {
  const md = whatsappCloudConnectorMetadataFromEnv({
    HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
  });
  assert.deepEqual(md.get('authorization'), ['Bearer connector-token-1']);
});

await runAsync('WhatsAppCloudHubConnectorClient wraps HubRuntime governance RPCs with connector principal', async () => {
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

  const client = createWhatsAppCloudHubConnectorClient({
    runtimeClient,
    eventsClient,
    env: {
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-2',
      HUB_HOST: '127.0.0.1',
      HUB_PORT: '50051',
    },
  });

  const gate = await client.evaluateChannelCommandGate({
    request_id: 'gate-1',
    actor: { provider: 'whatsapp_cloud_api', external_user_id: '15551234567', external_tenant_id: 'ops_whatsapp_cloud' },
    channel: { provider: 'whatsapp_cloud_api', account_id: 'ops_whatsapp_cloud', conversation_id: '15551234567', thread_key: 'wamid.1', channel_scope: 'dm' },
    action_name: 'deploy.plan',
    scope_type: 'project',
    scope_id: 'project_alpha',
  });
  assert.equal(!!gate.decision?.allowed, true);

  const route = await client.resolveSupervisorChannelRoute({
    request_id: 'route-1',
    channel: { provider: 'whatsapp_cloud_api', account_id: 'ops_whatsapp_cloud', conversation_id: '15551234567', thread_key: 'wamid.1', channel_scope: 'dm' },
    action_name: 'deploy.plan',
    project_id: 'project_alpha',
  });
  assert.equal(!!route.ok, true);

  const execution = await client.executeOperatorChannelHubCommand({
    request_id: 'exec-1',
    actor: { provider: 'whatsapp_cloud_api', external_user_id: '15551234567', external_tenant_id: 'ops_whatsapp_cloud' },
    channel: { provider: 'whatsapp_cloud_api', account_id: 'ops_whatsapp_cloud', conversation_id: '15551234567', thread_key: 'wamid.1', channel_scope: 'dm' },
    action_name: 'supervisor.status.get',
    scope_type: 'project',
    scope_id: 'project_alpha',
  });
  assert.equal(String(execution.query?.project_id || ''), 'project_alpha');

  const ingested = await client.ingestSupervisorSurface({
    request_id: 'ingest-1',
    ingress: {
      surface_type: 'whatsapp_cloud_api',
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

  assert.equal(String(calls[0].req.admin?.device_id || ''), 'hub_operator_channel_connector');
  assert.equal(String(calls[3].req.client?.app_id || ''), 'whatsapp_cloud_operator_adapter');
  assert.equal(String(calls[4].req.client?.device_id || ''), 'hub_operator_channel_connector');
  assert.equal(String(calls[5].req.client?.app_id || ''), 'whatsapp_cloud_operator_adapter');
});
