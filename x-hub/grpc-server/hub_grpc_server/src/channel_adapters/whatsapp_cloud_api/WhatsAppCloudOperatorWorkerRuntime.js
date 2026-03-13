import { createWhatsAppCloudApiClient, whatsappCloudReplyCredentialsFromEnv } from './WhatsAppCloudApiClient.js';
import { createWhatsAppCloudCommandIngressBridge } from './WhatsAppCloudCommandIngressBridge.js';
import { createWhatsAppCloudHubActionExecutor } from './WhatsAppCloudHubActionExecutor.js';
import { createWhatsAppCloudHubConnectorClient } from './WhatsAppCloudHubConnectorClient.js';
import { createWhatsAppCloudIngressServer } from './WhatsAppCloudIngressWorker.js';
import { createWhatsAppCloudResultPublisher } from './WhatsAppCloudResultPublisher.js';
import { startOperatorChannelEventForwarder } from '../../operator_channel_event_forwarder.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

function boundedInt(input, { fallback = 0, min = 0, max = Number.MAX_SAFE_INTEGER } = {}) {
  const n = Number(input);
  if (!Number.isFinite(n)) return fallback;
  const value = Math.trunc(n);
  if (value < min || value > max) return fallback;
  return value;
}

function normalizePath(input, fallback) {
  const text = safeString(input || fallback || '/');
  if (!text) return '/';
  return text.startsWith('/') ? text : `/${text}`;
}

function isLoopbackHost(host) {
  const value = safeString(host).toLowerCase();
  return value === '127.0.0.1' || value === 'localhost' || value === '::1' || value === '[::1]';
}

export function resolveWhatsAppCloudOperatorWorkerConfig(env = process.env) {
  const hubPort = boundedInt(env.HUB_PORT, { fallback: 50051, min: 1, max: 65535 });
  const enabled = safeBool(env.HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE, false);
  const allow_remote = safeBool(env.HUB_WHATSAPP_CLOUD_OPERATOR_ALLOW_REMOTE, false);
  const reply_delivery_enabled = safeBool(env.HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE, false);
  const host = safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_HOST || '127.0.0.1') || '127.0.0.1';
  const port = boundedInt(env.HUB_WHATSAPP_CLOUD_OPERATOR_PORT, {
    fallback: 50163,
    min: 1,
    max: 65535,
  });
  const event_path = normalizePath(env.HUB_WHATSAPP_CLOUD_OPERATOR_EVENT_PATH, '/whatsapp/events');
  const health_path = normalizePath(env.HUB_WHATSAPP_CLOUD_OPERATOR_HEALTH_PATH, '/health');
  const body_max_bytes = boundedInt(env.HUB_WHATSAPP_CLOUD_OPERATOR_BODY_MAX_BYTES, {
    fallback: 256 * 1024,
    min: 1024,
    max: 1024 * 1024,
  });
  const verify_token = safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN);
  const app_secret = safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET);
  const reply_credentials = whatsappCloudReplyCredentialsFromEnv(env);
  const account_id = safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_ACCOUNT_ID || reply_credentials.phone_number_id || 'whatsapp_cloud_operator') || 'whatsapp_cloud_operator';
  const app_id = safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_APP_ID || 'whatsapp_cloud_operator_adapter') || 'whatsapp_cloud_operator_adapter';
  const connector_token_present = !!safeString(env.HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN);
  const api_base_url = safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_API_BASE_URL || 'https://graph.facebook.com') || 'https://graph.facebook.com';
  const api_version = safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_API_VERSION || 'v23.0') || 'v23.0';

  return {
    enabled,
    allow_remote,
    reply_delivery_enabled,
    host,
    port,
    event_path,
    health_path,
    body_max_bytes,
    verify_token,
    verify_token_present: !!verify_token,
    app_secret,
    app_secret_present: !!app_secret,
    account_id,
    access_token: reply_credentials.access_token,
    phone_number_id: reply_credentials.phone_number_id,
    reply_credentials_present: !!reply_credentials.access_token && !!reply_credentials.phone_number_id,
    api_base_url,
    api_version,
    app_id,
    connector_token_present,
    hub_address: `${safeString(env.HUB_HOST || '127.0.0.1') || '127.0.0.1'}:${hubPort}`,
  };
}

export function validateWhatsAppCloudOperatorWorkerConfig(config = {}) {
  const cfg = config && typeof config === 'object' ? config : {};
  if (!cfg.enabled) {
    return {
      ok: true,
      code: '',
      message: '',
    };
  }
  if (!safeString(cfg.verify_token)) {
    return {
      ok: false,
      code: 'verify_token_missing',
      message: 'HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN is required when HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE=1',
    };
  }
  if (!safeString(cfg.app_secret)) {
    return {
      ok: false,
      code: 'app_secret_missing',
      message: 'HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET is required when HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE=1',
    };
  }
  if (!cfg.connector_token_present) {
    return {
      ok: false,
      code: 'connector_token_missing',
      message: 'HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN is required for WhatsApp Cloud operator worker',
    };
  }
  if (cfg.reply_delivery_enabled && !cfg.reply_credentials_present) {
    return {
      ok: false,
      code: 'reply_credentials_missing',
      message: 'HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN and HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID are required when HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE=1',
    };
  }
  if (!cfg.allow_remote && !isLoopbackHost(cfg.host)) {
    return {
      ok: false,
      code: 'remote_host_not_allowed',
      message: 'HUB_WHATSAPP_CLOUD_OPERATOR_HOST must stay loopback unless HUB_WHATSAPP_CLOUD_OPERATOR_ALLOW_REMOTE=1',
    };
  }
  return {
    ok: true,
    code: '',
    message: '',
  };
}

export async function startWhatsAppCloudOperatorWorker({
  env = process.env,
  log = console.log,
  createHubClient = createWhatsAppCloudHubConnectorClient,
  createWhatsAppCloudApiClientFactory = createWhatsAppCloudApiClient,
  createResultPublisherFactory = createWhatsAppCloudResultPublisher,
  createHubActionExecutorFactory = createWhatsAppCloudHubActionExecutor,
  createEventForwarderFactory = startOperatorChannelEventForwarder,
  createIngressBridge = createWhatsAppCloudCommandIngressBridge,
  createIngressServerFactory = createWhatsAppCloudIngressServer,
  now_fn = Date.now,
  on_result = null,
} = {}) {
  const config = resolveWhatsAppCloudOperatorWorkerConfig(env);
  const validation = validateWhatsAppCloudOperatorWorkerConfig(config);
  if (!validation.ok) {
    throw new Error(validation.message);
  }

  if (!config.enabled) {
    log?.('[hub_whatsapp_cloud_operator] disabled (HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE=0)');
    return {
      enabled: false,
      started: false,
      config,
      async close() {},
      snapshot() {
        return {
          enabled: false,
          started: false,
          config: {
            ...config,
            verify_token: '',
            app_secret: '',
            access_token: '',
          },
          address: null,
        };
      },
    };
  }

  const hub_client = createHubClient({
    env,
    app_id: config.app_id,
  });
  const hub_action_executor = createHubActionExecutorFactory({
    hub_client,
  });
  const whatsapp_client = config.reply_delivery_enabled && config.reply_credentials_present
    ? createWhatsAppCloudApiClientFactory({
        access_token: config.access_token,
        phone_number_id: config.phone_number_id,
        api_base_url: config.api_base_url,
        api_version: config.api_version,
      })
    : null;
  const result_publisher = whatsapp_client
    ? createResultPublisherFactory({
        whatsapp_client,
      })
    : null;
  let event_forwarder = null;
  const maybeSuppressGrantDecision = (result) => {
    const actionName = safeString(result?.command?.action_name).toLowerCase();
    const grantRequestId = safeString(result?.command?.pending_grant?.grant_request_id);
    if (!grantRequestId) return;
    if (actionName !== 'grant.approve' && actionName !== 'grant.reject') return;
    event_forwarder?.suppressGrantDecision?.({
      grant_request_id: grantRequestId,
    });
  };
  const executeResult = async (result) => {
    maybeSuppressGrantDecision(result);
    if (!hub_action_executor || typeof hub_action_executor.execute !== 'function') {
      return result;
    }
    return await hub_action_executor.execute(result);
  };
  const result_handler = typeof on_result === 'function' && result_publisher
    ? (async (result) => {
        const executed = await executeResult(result);
        await result_publisher.publish(executed);
        await on_result(executed);
      })
    : (typeof on_result === 'function'
      ? (async (result) => await on_result(await executeResult(result)))
      : (result_publisher ? (async (result) => await result_publisher.publish(await executeResult(result))) : null));
  if (
    result_publisher
    && (
      typeof result_publisher.publishGrantDecision === 'function'
      || typeof result_publisher.publishGrantPending === 'function'
    )
    && createEventForwarderFactory
  ) {
    event_forwarder = createEventForwarderFactory({
      provider: 'whatsapp_cloud_api',
      hub_client,
      log,
      publish_grant_pending: typeof result_publisher.publishGrantPending === 'function'
        ? (async ({ event, binding }) => {
            return await result_publisher.publishGrantPending({
              event,
              binding,
            });
          })
        : null,
      publish_grant_decision: typeof result_publisher.publishGrantDecision === 'function'
        ? (async ({ event, binding }) => {
            return await result_publisher.publishGrantDecision({
              event,
              binding,
            });
          })
        : null,
    });
  }
  const bridge = createIngressBridge({
    hub_client,
    now_fn,
    on_result: result_handler,
  });
  const server = createIngressServerFactory({
    host: config.host,
    port: config.port,
    verify_token: config.verify_token,
    app_secret: config.app_secret,
    account_id: config.account_id,
    event_path: config.event_path,
    health_path: config.health_path,
    body_max_bytes: config.body_max_bytes,
    now_fn,
    onEnvelope: async (envelope) => {
      return await bridge.handleEnvelope(envelope);
    },
  });
  const address = await server.listen();
  const boundHost = safeString(address?.address || config.host);
  const boundPort = boundedInt(address?.port, { fallback: config.port, min: 1, max: 65535 });
  log?.(
    `[hub_whatsapp_cloud_operator] listening on ${boundHost}:${boundPort} event_path=${config.event_path} health_path=${config.health_path} local_only=${config.allow_remote ? '0' : '1'}`
  );
  log?.(
    `[hub_whatsapp_cloud_operator] hub=${config.hub_address} app_id=${config.app_id} account_id=${config.account_id} connector_token_present=${config.connector_token_present ? '1' : '0'} reply_delivery_ready=${whatsapp_client ? '1' : '0'}`
  );
  log?.(
    `[hub_whatsapp_cloud_operator] proactive_grant_forwarding_ready=${event_forwarder?.snapshot?.().subscribed ? '1' : '0'} release_stage=p1 release_blocked=1`
  );

  return {
    enabled: true,
    started: true,
    config,
    address: {
      host: boundHost,
      port: boundPort,
    },
    bridge,
    hub_client,
    hub_action_executor,
    whatsapp_client,
    result_publisher,
    event_forwarder,
    server,
    async close() {
      try {
        await server.close();
      } finally {
        try {
          await event_forwarder?.close?.();
        } catch {
          // ignore
        }
        try {
          hub_client?.close?.();
        } catch {
          // ignore
        }
      }
    },
    snapshot() {
      return {
        enabled: true,
        started: true,
        config: {
          ...config,
          verify_token: '',
          app_secret: '',
          access_token: '',
        },
        address: {
          host: boundHost,
          port: boundPort,
        },
        event_forwarder: event_forwarder?.snapshot?.() || null,
      };
    },
  };
}
