import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

import { makeClientCredentials } from '../../client_credentials.js';
import { resolveHubProtoPath } from '../../proto_path.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

export function telegramConnectorMetadataFromEnv(env = process.env) {
  const md = new grpc.Metadata();
  const tok = safeString(env.HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN || '');
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

export function telegramConnectorPrincipal({ app_id = 'telegram_operator_adapter' } = {}) {
  return {
    device_id: 'hub_operator_channel_connector',
    user_id: '',
    app_id: safeString(app_id) || 'telegram_operator_adapter',
    project_id: '',
    session_id: '',
  };
}

function unary(rpcClient, method, request, metadataFactory) {
  return new Promise((resolve, reject) => {
    rpcClient[method](request, metadataFactory(), (err, out) => {
      if (err) reject(err);
      else resolve(out);
    });
  });
}

export function createTelegramHubConnectorClient(options = {}) {
  const env = options.env && typeof options.env === 'object' ? options.env : process.env;
  const address = safeString(options.address || `${env.HUB_HOST || '127.0.0.1'}:${env.HUB_PORT || 50051}`);
  const metadataFactory = typeof options.metadataFactory === 'function'
    ? options.metadataFactory
    : (() => telegramConnectorMetadataFromEnv(env));
  const principal = options.principal && typeof options.principal === 'object'
    ? options.principal
    : telegramConnectorPrincipal({ app_id: safeString(options.app_id || 'telegram_operator_adapter') });
  const proto = (!options.runtimeClient || !options.eventsClient || !options.supervisorClient)
    ? loadProto(resolveHubProtoPath(env))
    : null;

  const runtimeClient = (() => {
    if (options.runtimeClient) return options.runtimeClient;
    const { creds, options: clientOptions } = makeClientCredentials(env);
    return new proto.HubRuntime(address, creds, clientOptions);
  })();
  const eventsClient = (() => {
    if (options.eventsClient) return options.eventsClient;
    const { creds, options: clientOptions } = makeClientCredentials(env);
    return new proto.HubEvents(address, creds, clientOptions);
  })();
  const supervisorClient = (() => {
    if (options.supervisorClient) return options.supervisorClient;
    if (
      runtimeClient
      && (
        typeof runtimeClient.IngestSupervisorSurface === 'function'
        || typeof runtimeClient.ResolveSupervisorRoute === 'function'
        || typeof runtimeClient.GetSupervisorBriefProjection === 'function'
        || typeof runtimeClient.ResolveSupervisorGuidance === 'function'
        || typeof runtimeClient.IssueSupervisorCheckpointChallenge === 'function'
      )
    ) {
      return runtimeClient;
    }
    const { creds, options: clientOptions } = makeClientCredentials(env);
    return new proto.HubSupervisor(address, creds, clientOptions);
  })();

  return {
    address,
    principal,
    close() {
      try {
        runtimeClient.close?.();
      } catch {
        // ignore
      }
      if (eventsClient !== runtimeClient) {
        try {
          eventsClient.close?.();
        } catch {
          // ignore
        }
      }
      if (supervisorClient !== runtimeClient && supervisorClient !== eventsClient) {
        try {
          supervisorClient.close?.();
        } catch {
          // ignore
        }
      }
    },
    async getChannelRuntimeStatusSnapshot() {
      return await unary(
        runtimeClient,
        'GetChannelRuntimeStatusSnapshot',
        { admin: principal },
        metadataFactory
      );
    },
    async listChannelIdentityBindings(filters = {}) {
      return await unary(
        runtimeClient,
        'ListChannelIdentityBindings',
        { admin: principal, ...filters },
        metadataFactory
      );
    },
    async upsertChannelIdentityBinding(binding, request_id = '') {
      return await unary(
        runtimeClient,
        'UpsertChannelIdentityBinding',
        { request_id: safeString(request_id), admin: principal, binding: binding || {} },
        metadataFactory
      );
    },
    async listSupervisorOperatorChannelBindings(filters = {}) {
      return await unary(
        runtimeClient,
        'ListSupervisorOperatorChannelBindings',
        { admin: principal, ...filters },
        metadataFactory
      );
    },
    async upsertSupervisorOperatorChannelBinding(binding, request_id = '') {
      return await unary(
        runtimeClient,
        'UpsertSupervisorOperatorChannelBinding',
        { request_id: safeString(request_id), admin: principal, binding: binding || {} },
        metadataFactory
      );
    },
    async listChannelOnboardingDiscoveryTickets(filters = {}) {
      return await unary(
        runtimeClient,
        'ListChannelOnboardingDiscoveryTickets',
        { admin: principal, ...filters },
        metadataFactory
      );
    },
    async createOrTouchChannelOnboardingDiscoveryTicket(ticket, request_id = '') {
      return await unary(
        runtimeClient,
        'CreateOrTouchChannelOnboardingDiscoveryTicket',
        { request_id: safeString(request_id), admin: principal, ticket: ticket || {} },
        metadataFactory
      );
    },
    async evaluateChannelCommandGate({
      request_id = '',
      actor = {},
      channel = {},
      binding_id = '',
      action_name = '',
      scope_type = '',
      scope_id = '',
      pending_grant = null,
    } = {}) {
      return await unary(
        runtimeClient,
        'EvaluateChannelCommandGate',
        {
          request_id: safeString(request_id),
          admin: principal,
          client: principal,
          actor,
          channel,
          binding_id: safeString(binding_id),
          action_name: safeString(action_name),
          scope_type: safeString(scope_type),
          scope_id: safeString(scope_id),
          pending_grant,
        },
        metadataFactory
      );
    },
    async resolveSupervisorChannelRoute({
      request_id = '',
      binding_id = '',
      channel = {},
      action_name = '',
      project_id = '',
      root_project_id = '',
    } = {}) {
      return await unary(
        runtimeClient,
        'ResolveSupervisorChannelRoute',
        {
          request_id: safeString(request_id),
          admin: principal,
          binding_id: safeString(binding_id),
          channel,
          action_name: safeString(action_name),
          project_id: safeString(project_id),
          root_project_id: safeString(root_project_id),
        },
        metadataFactory
      );
    },
    async executeOperatorChannelHubCommand({
      request_id = '',
      actor = {},
      channel = {},
      binding_id = '',
      action_name = '',
      scope_type = '',
      scope_id = '',
      pending_grant = null,
      note = '',
    } = {}) {
      return await unary(
        runtimeClient,
        'ExecuteOperatorChannelHubCommand',
        {
          request_id: safeString(request_id),
          admin: principal,
          actor,
          channel,
          binding_id: safeString(binding_id),
          action_name: safeString(action_name),
          scope_type: safeString(scope_type),
          scope_id: safeString(scope_id),
          pending_grant,
          note: safeString(note),
        },
        metadataFactory
      );
    },
    async ingestSupervisorSurface({
      request_id = '',
      ingress = {},
      allow_hub_only_without_project = false,
    } = {}) {
      return await unary(
        supervisorClient,
        'IngestSupervisorSurface',
        {
          request_id: safeString(request_id),
          client: principal,
          ingress: ingress || {},
          allow_hub_only_without_project: !!allow_hub_only_without_project,
        },
        metadataFactory
      );
    },
    async resolveSupervisorRoute({
      request_id = '',
      ingress = {},
      require_xt = false,
      require_runner = false,
      preferred_device_id_override = '',
    } = {}) {
      return await unary(
        supervisorClient,
        'ResolveSupervisorRoute',
        {
          request_id: safeString(request_id),
          client: principal,
          ingress: ingress || {},
          require_xt: !!require_xt,
          require_runner: !!require_runner,
          preferred_device_id_override: safeString(preferred_device_id_override),
        },
        metadataFactory
      );
    },
    async getSupervisorBriefProjection({
      request_id = '',
      project_id = '',
      run_id = '',
      mission_id = '',
      projection_kind = '',
      trigger = '',
      include_tts_script = true,
      include_card_summary = true,
      max_evidence_refs = 0,
    } = {}) {
      return await unary(
        supervisorClient,
        'GetSupervisorBriefProjection',
        {
          request_id: safeString(request_id),
          client: principal,
          project_id: safeString(project_id),
          run_id: safeString(run_id),
          mission_id: safeString(mission_id),
          projection_kind: safeString(projection_kind),
          trigger: safeString(trigger),
          include_tts_script: include_tts_script !== false,
          include_card_summary: include_card_summary !== false,
          max_evidence_refs: Number(max_evidence_refs || 0),
        },
        metadataFactory
      );
    },
    async resolveSupervisorGuidance({
      request_id = '',
      ingress = {},
      guidance_type = '',
      normalized_instruction = '',
      target_scope = null,
      requires_confirmation = false,
      requires_authorization = false,
    } = {}) {
      return await unary(
        supervisorClient,
        'ResolveSupervisorGuidance',
        {
          request_id: safeString(request_id),
          client: principal,
          ingress: ingress || {},
          guidance_type: safeString(guidance_type),
          normalized_instruction: safeString(normalized_instruction),
          target_scope: target_scope && typeof target_scope === 'object' ? target_scope : null,
          requires_confirmation: !!requires_confirmation,
          requires_authorization: !!requires_authorization,
        },
        metadataFactory
      );
    },
    async issueSupervisorCheckpointChallenge({
      request_id = '',
      project_id = '',
      mission_id = '',
      checkpoint_type = '',
      risk_tier = '',
      decision_path = '',
      scope_digest = '',
      amount_digest = '',
      requires_mobile_confirm = false,
      bound_device_id = '',
      ttl_ms = 0,
      evidence_refs = [],
    } = {}) {
      return await unary(
        supervisorClient,
        'IssueSupervisorCheckpointChallenge',
        {
          request_id: safeString(request_id),
          client: principal,
          project_id: safeString(project_id),
          mission_id: safeString(mission_id),
          checkpoint_type: safeString(checkpoint_type),
          risk_tier: safeString(risk_tier),
          decision_path: safeString(decision_path),
          scope_digest: safeString(scope_digest),
          amount_digest: safeString(amount_digest),
          requires_mobile_confirm: !!requires_mobile_confirm,
          bound_device_id: safeString(bound_device_id),
          ttl_ms: Number(ttl_ms || 0),
          evidence_refs: Array.isArray(evidence_refs) ? evidence_refs.map((item) => safeString(item)).filter(Boolean) : [],
        },
        metadataFactory
      );
    },
    subscribeHubEvents({
      scopes = ['grants'],
      last_event_id = '',
      on_data = null,
      on_error = null,
      on_end = null,
    } = {}) {
      if (!eventsClient || typeof eventsClient.Subscribe !== 'function') {
        throw new Error('hub_events_client_invalid');
      }
      const stream = eventsClient.Subscribe(
        {
          client: principal,
          scopes: Array.isArray(scopes) ? scopes.map((scope) => safeString(scope)).filter(Boolean) : [],
          last_event_id: safeString(last_event_id),
        },
        metadataFactory()
      );
      if (typeof on_data === 'function') stream.on('data', on_data);
      if (typeof on_error === 'function') stream.on('error', on_error);
      if (typeof on_end === 'function') stream.on('end', on_end);
      return stream;
    },
  };
}
