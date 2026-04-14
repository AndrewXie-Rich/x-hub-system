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
      cb(null, { ok: true, ingress: { ingress_id: 'ing-1', project_id: req.ingress?.project_id || '' } });
    },
    ResolveSupervisorRoute(req, md, cb) {
      calls.push({ method: 'ResolveSupervisorRoute', req, md });
      cb(null, {
        ok: true,
        route: {
          decision: 'hub_only',
          project_id: req.ingress?.project_id || '',
          governance_runtime_readiness: {
            runtime_ready: false,
            blocked_component_keys: ['route_ready'],
          },
        },
      });
    },
    GetSupervisorBriefProjection(req, md, cb) {
      calls.push({ method: 'GetSupervisorBriefProjection', req, md });
      cb(null, { ok: true, projection: { project_id: req.project_id, status: 'active' } });
    },
    ResolveSupervisorGuidance(req, md, cb) {
      calls.push({ method: 'ResolveSupervisorGuidance', req, md });
      cb(null, { ok: true, resolution: { guidance_type: req.guidance_type, resolution: 'pending' } });
    },
    IssueSupervisorCheckpointChallenge(req, md, cb) {
      calls.push({ method: 'IssueSupervisorCheckpointChallenge', req, md });
      cb(null, { ok: true, challenge: { project_id: req.project_id, checkpoint_type: req.checkpoint_type } });
    },
    ResolveSupervisorChannelRoute(req, md, cb) {
      calls.push({ method: 'ResolveSupervisorChannelRoute', req, md });
      cb(null, {
        ok: true,
        route: {
          route_mode: 'hub_to_xt',
          resolved_device_id: 'xt-1',
          governance_runtime_readiness: {
            runtime_ready: true,
            components_by_xt_key: {
              route_ready: { state: 'ready' },
            },
          },
        },
      });
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
      const listed = await client.listChannelOnboardingDiscoveryTickets({
        provider: 'slack',
        status: 'pending',
      });
      assert.equal(Array.isArray(listed.tickets), true);

      const discovery = await client.createOrTouchChannelOnboardingDiscoveryTicket({
        provider: 'slack',
        account_id: 'T001',
        external_user_id: 'U123',
        external_tenant_id: 'T001',
        conversation_id: 'C001',
        thread_key: '171.1',
        ingress_surface: 'group',
        first_message_preview: 'deploy.plan',
      }, 'disc-1');
      assert.equal(!!discovery.ok, true);
      assert.equal(String(discovery.ticket?.ticket_id || ''), 'disc-1');

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
      assert.equal(typeof route.route?.governance_runtime_readiness, 'object');
      assert.equal(Boolean(route.route?.governance_runtime_readiness?.runtime_ready), true);

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

      const ingested = await client.ingestSupervisorSurface({
        request_id: 'ingest-1',
        ingress: {
          surface_type: 'slack',
          normalized_intent_type: 'progress_query',
          project_id: 'project_alpha',
        },
      });
      assert.equal(!!ingested.ok, true);
      assert.equal(String(ingested.ingress?.project_id || ''), 'project_alpha');

      const supervisorRoute = await client.resolveSupervisorRoute({
        request_id: 'sup-route-1',
        ingress: {
          surface_type: 'slack',
          normalized_intent_type: 'directive',
          project_id: 'project_alpha',
        },
      });
      assert.equal(!!supervisorRoute.ok, true);
      assert.equal(typeof supervisorRoute.route?.governance_runtime_readiness, 'object');
      assert.equal(Boolean(supervisorRoute.route?.governance_runtime_readiness?.runtime_ready), false);

      const projection = await client.getSupervisorBriefProjection({
        request_id: 'brief-1',
        project_id: 'project_alpha',
        projection_kind: 'progress_brief',
      });
      assert.equal(String(projection.projection?.project_id || ''), 'project_alpha');

      const guidance = await client.resolveSupervisorGuidance({
        request_id: 'guidance-1',
        ingress: {
          surface_type: 'slack',
          normalized_intent_type: 'directive',
          project_id: 'project_alpha',
        },
        guidance_type: 'scope_hold',
        normalized_instruction: 'hold current scope',
      });
      assert.equal(String(guidance.resolution?.resolution || ''), 'pending');

      const checkpoint = await client.issueSupervisorCheckpointChallenge({
        request_id: 'checkpoint-1',
        project_id: 'project_alpha',
        checkpoint_type: 'substitution',
        risk_tier: 'medium',
        decision_path: 'voice_plus_mobile',
        scope_digest: 'substitute:item-1',
      });
      assert.equal(String(checkpoint.challenge?.project_id || ''), 'project_alpha');

      const subscribed = client.subscribeHubEvents({
        scopes: ['grants'],
      });
      assert.equal(subscribed, stream);
    }
  );

  assert.equal(calls.length, 11);
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
  assert.equal(String(calls[5].req.client?.app_id || ''), 'slack_operator_adapter');
  assert.deepEqual(calls[5].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[6].method || ''), 'ResolveSupervisorRoute');
  assert.deepEqual(calls[6].md.get('authorization'), ['Bearer connector-token-2']);
  assert.equal(String(calls[7].method || ''), 'GetSupervisorBriefProjection');
  assert.equal(String(calls[7].req.client?.device_id || ''), 'hub_operator_channel_connector');
  assert.equal(String(calls[8].method || ''), 'ResolveSupervisorGuidance');
  assert.equal(String(calls[9].method || ''), 'IssueSupervisorCheckpointChallenge');
  assert.equal(String(calls[10].method || ''), 'Subscribe');
  assert.equal(String(calls[10].req.client?.app_id || ''), 'slack_operator_adapter');
  assert.deepEqual(calls[10].req.scopes, ['grants']);
  assert.deepEqual(calls[10].md.get('authorization'), ['Bearer connector-token-2']);
});
