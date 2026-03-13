import { startOperatorChannelEventForwarder } from '../../operator_channel_event_forwarder.js';
import { createTelegramApiClient, telegramBotTokenFromEnv } from './TelegramApiClient.js';
import { createTelegramCommandIngressBridge } from './TelegramCommandIngressBridge.js';
import { normalizeTelegramUpdate } from './TelegramIngress.js';
import { createTelegramHubActionExecutor } from './TelegramHubActionExecutor.js';
import { createTelegramHubConnectorClient } from './TelegramHubConnectorClient.js';
import { createTelegramPollingWorker } from './TelegramPollingWorker.js';
import { createTelegramResultPublisher } from './TelegramResultPublisher.js';

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

export function resolveTelegramOperatorWorkerConfig(env = process.env) {
  const hubPort = boundedInt(env.HUB_PORT, { fallback: 50051, min: 1, max: 65535 });
  const enabled = safeBool(env.HUB_TELEGRAM_OPERATOR_ENABLE, false);
  const reply_delivery_enabled = safeBool(env.HUB_TELEGRAM_OPERATOR_REPLY_ENABLE, true);
  const poll_updates_enabled = safeBool(env.HUB_TELEGRAM_OPERATOR_POLL_ENABLE, true);
  const poll_timeout_sec = boundedInt(env.HUB_TELEGRAM_OPERATOR_POLL_TIMEOUT_SEC, {
    fallback: 15,
    min: 0,
    max: 50,
  });
  const poll_idle_ms = boundedInt(env.HUB_TELEGRAM_OPERATOR_POLL_IDLE_MS, {
    fallback: 400,
    min: 100,
    max: 30_000,
  });
  const bot_token = telegramBotTokenFromEnv(env);
  const account_id = safeString(env.HUB_TELEGRAM_OPERATOR_ACCOUNT_ID || 'telegram_operator') || 'telegram_operator';
  const app_id = safeString(env.HUB_TELEGRAM_OPERATOR_APP_ID || 'telegram_operator_adapter') || 'telegram_operator_adapter';
  const connector_token_present = !!safeString(env.HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN);
  const api_base_url = safeString(env.HUB_TELEGRAM_OPERATOR_API_BASE_URL || 'https://api.telegram.org') || 'https://api.telegram.org';

  return {
    enabled,
    reply_delivery_enabled,
    poll_updates_enabled,
    poll_timeout_sec,
    poll_idle_ms,
    bot_token,
    bot_token_present: !!bot_token,
    account_id,
    app_id,
    connector_token_present,
    api_base_url,
    hub_address: `${safeString(env.HUB_HOST || '127.0.0.1') || '127.0.0.1'}:${hubPort}`,
  };
}

export function validateTelegramOperatorWorkerConfig(config = {}) {
  const cfg = config && typeof config === 'object' ? config : {};
  if (!cfg.enabled) {
    return {
      ok: true,
      code: '',
      message: '',
    };
  }
  if (!cfg.connector_token_present) {
    return {
      ok: false,
      code: 'connector_token_missing',
      message: 'HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN is required for Telegram operator worker',
    };
  }
  if (!safeString(cfg.bot_token)) {
    return {
      ok: false,
      code: 'bot_token_missing',
      message: 'HUB_TELEGRAM_OPERATOR_BOT_TOKEN is required when HUB_TELEGRAM_OPERATOR_ENABLE=1',
    };
  }
  return {
    ok: true,
    code: '',
    message: '',
  };
}

export async function startTelegramOperatorWorker({
  env = process.env,
  log = console.log,
  createHubClient = createTelegramHubConnectorClient,
  createHubActionExecutorFactory = createTelegramHubActionExecutor,
  createTelegramApiClientFactory = createTelegramApiClient,
  createResultPublisherFactory = createTelegramResultPublisher,
  createEventForwarderFactory = startOperatorChannelEventForwarder,
  createIngressBridge = createTelegramCommandIngressBridge,
  createPollingWorkerFactory = createTelegramPollingWorker,
  normalizeUpdate = normalizeTelegramUpdate,
  now_fn = Date.now,
  on_result = null,
} = {}) {
  const config = resolveTelegramOperatorWorkerConfig(env);
  const validation = validateTelegramOperatorWorkerConfig(config);
  if (!validation.ok) {
    throw new Error(validation.message);
  }

  if (!config.enabled) {
    log?.('[hub_telegram_operator] disabled (HUB_TELEGRAM_OPERATOR_ENABLE=0)');
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
            bot_token: '',
          },
          polling_worker: null,
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
  const telegram_client = createTelegramApiClientFactory({
    token: config.bot_token,
    api_base_url: config.api_base_url,
  });
  const result_publisher = config.reply_delivery_enabled
    ? createResultPublisherFactory({
        telegram_client,
      })
    : null;
  let event_forwarder = null;
  let polling_worker = null;

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
      provider: 'telegram',
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

  const acknowledgeCallback = async (envelope, handled) => {
    const callbackQueryId = safeString(envelope?.callback_query_id);
    if (!callbackQueryId) return;
    if (!telegram_client || typeof telegram_client.answerCallbackQuery !== 'function') return;
    const text = handled?.ok === true
      ? (handled.handled === true ? 'Accepted' : 'Ignored')
      : (safeString(handled?.deny_code || 'request_denied') || 'request_denied');
    try {
      await telegram_client.answerCallbackQuery({
        callback_query_id: callbackQueryId,
        text,
        show_alert: handled?.ok !== true,
      });
    } catch (error) {
      log?.(
        `[hub_telegram_operator] callback ack failed error=${safeString(error?.message || 'callback_ack_failed') || 'callback_ack_failed'}`
      );
    }
  };

  const handleUpdate = async (update) => {
    const envelope = normalizeUpdate(update, {
      account_id: config.account_id,
    });
    if (!envelope.ok) {
      if (safeString(envelope.deny_code) !== 'structured_action_missing' && safeString(envelope.deny_code) !== 'event_type_unsupported') {
        log?.(
          `[hub_telegram_operator] dropped update deny_code=${safeString(envelope.deny_code || 'update_denied') || 'update_denied'}`
        );
      }
      await acknowledgeCallback(envelope, envelope);
      return envelope;
    }
    const handled = await bridge.handleEnvelope(envelope);
    await acknowledgeCallback(envelope, handled);
    return handled;
  };

  if (config.poll_updates_enabled && createPollingWorkerFactory) {
    try {
      await telegram_client.deleteWebhook?.({
        drop_pending_updates: false,
      });
    } catch (error) {
      log?.(
        `[hub_telegram_operator] deleteWebhook failed error=${safeString(error?.message || 'delete_webhook_failed') || 'delete_webhook_failed'}`
      );
    }
    polling_worker = createPollingWorkerFactory({
      telegram_client,
      on_update: handleUpdate,
      log,
      poll_timeout_sec: config.poll_timeout_sec,
      poll_idle_ms: config.poll_idle_ms,
    });
    await polling_worker.listen();
  }

  log?.(
    `[hub_telegram_operator] hub=${config.hub_address} app_id=${config.app_id} account_id=${config.account_id} connector_token_present=${config.connector_token_present ? '1' : '0'}`
  );
  log?.(
    `[hub_telegram_operator] reply_delivery_ready=${result_publisher ? '1' : '0'} polling_ready=${polling_worker ? '1' : '0'} proactive_grant_forwarding_ready=${event_forwarder?.snapshot?.().subscribed ? '1' : '0'}`
  );

  return {
    enabled: true,
    started: true,
    config,
    bridge,
    hub_client,
    hub_action_executor,
    telegram_client,
    result_publisher,
    event_forwarder,
    polling_worker,
    async close() {
      try {
        await polling_worker?.close?.();
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
          bot_token: '',
        },
        event_forwarder: event_forwarder?.snapshot?.() || null,
        polling_worker: polling_worker?.snapshot?.() || null,
      };
    },
  };
}
