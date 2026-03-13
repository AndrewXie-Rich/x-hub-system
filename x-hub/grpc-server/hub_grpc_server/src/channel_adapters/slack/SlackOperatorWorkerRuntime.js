import { createSlackCommandIngressBridge } from './SlackCommandIngressBridge.js';
import { createSlackApiClient, slackBotTokenFromEnv } from './SlackApiClient.js';
import { createSlackHubActionExecutor } from './SlackHubActionExecutor.js';
import { createSlackHubConnectorClient } from './SlackHubConnectorClient.js';
import { createSlackIngressServer } from './SlackIngressWorker.js';
import { createSlackResultPublisher } from './SlackResultPublisher.js';
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

export function resolveSlackOperatorWorkerConfig(env = process.env) {
  const hubPort = boundedInt(env.HUB_PORT, { fallback: 50051, min: 1, max: 65535 });
  const enabled = safeBool(env.HUB_SLACK_OPERATOR_ENABLE, false);
  const allow_remote = safeBool(env.HUB_SLACK_OPERATOR_ALLOW_REMOTE, false);
  const reply_delivery_enabled = safeBool(env.HUB_SLACK_OPERATOR_REPLY_ENABLE, true);
  const host = safeString(env.HUB_SLACK_OPERATOR_HOST || '127.0.0.1') || '127.0.0.1';
  const port = boundedInt(env.HUB_SLACK_OPERATOR_PORT, {
    fallback: 50161,
    min: 1,
    max: 65535,
  });
  const event_path = normalizePath(env.HUB_SLACK_OPERATOR_EVENT_PATH, '/slack/events');
  const health_path = normalizePath(env.HUB_SLACK_OPERATOR_HEALTH_PATH, '/health');
  const body_max_bytes = boundedInt(env.HUB_SLACK_OPERATOR_BODY_MAX_BYTES, {
    fallback: 256 * 1024,
    min: 1024,
    max: 1024 * 1024,
  });
  const signing_secret = safeString(env.HUB_SLACK_OPERATOR_SIGNING_SECRET);
  const bot_token = slackBotTokenFromEnv(env);
  const app_id = safeString(env.HUB_SLACK_OPERATOR_APP_ID || 'slack_operator_adapter') || 'slack_operator_adapter';
  const connector_token_present = !!safeString(env.HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN);

  return {
    enabled,
    allow_remote,
    reply_delivery_enabled,
    host,
    port,
    event_path,
    health_path,
    body_max_bytes,
    signing_secret,
    signing_secret_present: !!signing_secret,
    bot_token,
    bot_token_present: !!bot_token,
    app_id,
    connector_token_present,
    hub_address: `${safeString(env.HUB_HOST || '127.0.0.1') || '127.0.0.1'}:${hubPort}`,
  };
}

export function validateSlackOperatorWorkerConfig(config = {}) {
  const cfg = config && typeof config === 'object' ? config : {};
  if (!cfg.enabled) {
    return {
      ok: true,
      code: '',
      message: '',
    };
  }
  if (!safeString(cfg.signing_secret)) {
    return {
      ok: false,
      code: 'signing_secret_missing',
      message: 'HUB_SLACK_OPERATOR_SIGNING_SECRET is required when HUB_SLACK_OPERATOR_ENABLE=1',
    };
  }
  if (!cfg.connector_token_present) {
    return {
      ok: false,
      code: 'connector_token_missing',
      message: 'HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN is required for Slack operator worker',
    };
  }
  if (!cfg.allow_remote && !isLoopbackHost(cfg.host)) {
    return {
      ok: false,
      code: 'remote_host_not_allowed',
      message: 'HUB_SLACK_OPERATOR_HOST must stay loopback unless HUB_SLACK_OPERATOR_ALLOW_REMOTE=1',
    };
  }
  return {
    ok: true,
    code: '',
    message: '',
  };
}

export async function startSlackOperatorWorker({
  env = process.env,
  log = console.log,
  createHubClient = createSlackHubConnectorClient,
  createHubActionExecutorFactory = createSlackHubActionExecutor,
  createSlackApiClientFactory = createSlackApiClient,
  createResultPublisherFactory = createSlackResultPublisher,
  createEventForwarderFactory = startOperatorChannelEventForwarder,
  createIngressBridge = createSlackCommandIngressBridge,
  createIngressServerFactory = createSlackIngressServer,
  now_fn = Date.now,
  on_result = null,
} = {}) {
  const config = resolveSlackOperatorWorkerConfig(env);
  const validation = validateSlackOperatorWorkerConfig(config);
  if (!validation.ok) {
    throw new Error(validation.message);
  }

  if (!config.enabled) {
    log?.('[hub_slack_operator] disabled (HUB_SLACK_OPERATOR_ENABLE=0)');
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
            signing_secret: '',
            bot_token: '',
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
  const slack_client = config.reply_delivery_enabled && config.bot_token_present
    ? createSlackApiClientFactory({
        token: config.bot_token,
      })
    : null;
  const result_publisher = slack_client
    ? createResultPublisherFactory({
        slack_client,
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
      provider: 'slack',
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
    signing_secret: config.signing_secret,
    event_path: config.event_path,
    health_path: config.health_path,
    body_max_bytes: config.body_max_bytes,
    now_fn,
    onEnvelope: async (envelope) => {
      return await bridge.handleEnvelope(envelope);
    },
  });

  let address = null;
  try {
    address = await server.listen();
  } catch (error) {
    try {
      hub_client?.close?.();
    } catch {
      // ignore
    }
    throw error;
  }

  const boundHost = safeString(address?.address || config.host) || config.host;
  const boundPort = boundedInt(address?.port, { fallback: config.port, min: 1, max: 65535 });
  log?.(
    `[hub_slack_operator] listening on ${boundHost}:${boundPort} event_path=${config.event_path} health_path=${config.health_path} local_only=${config.allow_remote ? '0' : '1'}`
  );
  log?.(
    `[hub_slack_operator] hub=${config.hub_address} app_id=${config.app_id} connector_token_present=${config.connector_token_present ? '1' : '0'} reply_delivery_ready=${slack_client ? '1' : '0'}`
  );
  log?.(
    `[hub_slack_operator] proactive_grant_forwarding_ready=${event_forwarder?.snapshot?.().subscribed ? '1' : '0'}`
  );

  return {
    enabled: true,
    started: true,
    config,
    address,
    bridge,
    hub_client,
    hub_action_executor,
    slack_client,
    result_publisher,
    event_forwarder,
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
          signing_secret: '',
          bot_token: '',
        },
        address,
        event_forwarder: event_forwarder?.snapshot?.() || null,
      };
    },
  };
}
