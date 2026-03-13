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

export function whatsappCloudConnectorMetadataFromEnv(env = process.env) {
  const md = new grpc.Metadata();
  const tok = safeString(env.HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN || '');
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

export function whatsappCloudConnectorPrincipal({ app_id = 'whatsapp_cloud_operator_adapter' } = {}) {
  return {
    device_id: 'hub_operator_channel_connector',
    user_id: '',
    app_id: safeString(app_id) || 'whatsapp_cloud_operator_adapter',
    project_id: '',
    session_id: '',
  };
}

function unary(runtimeClient, method, request, metadataFactory) {
  return new Promise((resolve, reject) => {
    runtimeClient[method](request, metadataFactory(), (err, out) => {
      if (err) reject(err);
      else resolve(out);
    });
  });
}

export function createWhatsAppCloudHubConnectorClient(options = {}) {
  const env = options.env && typeof options.env === 'object' ? options.env : process.env;
  const address = safeString(options.address || `${env.HUB_HOST || '127.0.0.1'}:${env.HUB_PORT || 50051}`);
  const metadataFactory = typeof options.metadataFactory === 'function'
    ? options.metadataFactory
    : (() => whatsappCloudConnectorMetadataFromEnv(env));
  const principal = options.principal && typeof options.principal === 'object'
    ? options.principal
    : whatsappCloudConnectorPrincipal({ app_id: safeString(options.app_id || 'whatsapp_cloud_operator_adapter') });
  const proto = (!options.runtimeClient || !options.eventsClient)
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
