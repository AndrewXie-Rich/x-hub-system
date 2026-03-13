function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function normalizeApiBaseUrl(input) {
  const value = safeString(input || 'https://api.telegram.org') || 'https://api.telegram.org';
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function parseJson(text) {
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    return null;
  }
}

export function telegramBotTokenFromEnv(env = process.env) {
  return safeString(env.HUB_TELEGRAM_OPERATOR_BOT_TOKEN || '');
}

function normalizeAllowedUpdates(input) {
  return safeArray(input).map((item) => safeString(item)).filter(Boolean);
}

export function createTelegramApiClient({
  token = '',
  fetch_impl = globalThis.fetch,
  api_base_url = 'https://api.telegram.org',
  timeout_ms = 15_000,
} = {}) {
  const botToken = safeString(token);
  const fetchFn = typeof fetch_impl === 'function' ? fetch_impl : null;
  const baseUrl = normalizeApiBaseUrl(api_base_url);
  const timeoutMs = Math.max(1000, safeInt(timeout_ms, 15_000) || 15_000);

  async function callApi(method, payload = {}) {
    if (!botToken) throw new Error('telegram_bot_token_missing');
    if (!fetchFn) throw new Error('fetch_impl_missing');
    const controller = typeof AbortController === 'function' ? new AbortController() : null;
    const timer = controller
      ? setTimeout(() => {
          try {
            controller.abort();
          } catch {
            // ignore
          }
        }, timeoutMs)
      : null;

    let response;
    try {
      response = await fetchFn(`${baseUrl}/bot${botToken}/${method}`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json; charset=utf-8',
        },
        body: JSON.stringify(safeObject(payload)),
        ...(controller ? { signal: controller.signal } : {}),
      });
    } catch (error) {
      if (timer) clearTimeout(timer);
      throw new Error(`telegram_fetch_failed:${safeString(error?.message || 'unknown')}`);
    }
    if (timer) clearTimeout(timer);

    const raw = await response.text();
    const parsed = parseJson(raw);
    if (!response.ok) {
      throw new Error(`telegram_http_${safeInt(response.status, 0)}:${safeString(parsed?.description || raw || 'request_failed')}`);
    }
    if (!parsed || parsed.ok !== true) {
      throw new Error(`telegram_api_error:${safeString(parsed?.description || 'unknown')}`);
    }
    return parsed;
  }

  async function getUpdates({
    offset = 0,
    timeout_sec = 15,
    allowed_updates = ['message', 'callback_query'],
  } = {}) {
    const parsed = await callApi('getUpdates', {
      offset: safeInt(offset, 0) || 0,
      timeout: Math.max(0, Math.min(50, safeInt(timeout_sec, 15))),
      allowed_updates: normalizeAllowedUpdates(allowed_updates),
    });
    return {
      ok: true,
      updates: safeArray(parsed.result),
      response: parsed,
    };
  }

  async function deleteWebhook({
    drop_pending_updates = false,
  } = {}) {
    const parsed = await callApi('deleteWebhook', {
      drop_pending_updates: safeBool(drop_pending_updates, false),
    });
    return {
      ok: true,
      result: parsed.result === true,
      response: parsed,
    };
  }

  async function postMessage({
    chat_id = '',
    text = '',
    message_thread_id = 0,
    parse_mode = '',
    reply_markup = null,
    reply_to_message_id = 0,
    disable_notification = false,
    disable_web_page_preview = true,
  } = {}) {
    const chatId = safeString(chat_id);
    const bodyText = safeString(text);
    if (!chatId) throw new Error('telegram_chat_id_missing');
    if (!bodyText) throw new Error('telegram_text_missing');

    const parsed = await callApi('sendMessage', {
      chat_id: chatId,
      text: bodyText,
      ...(safeInt(message_thread_id, 0) > 0 ? { message_thread_id: safeInt(message_thread_id, 0) } : {}),
      ...(safeString(parse_mode) ? { parse_mode: safeString(parse_mode) } : {}),
      ...(safeObject(reply_markup) && Object.keys(safeObject(reply_markup)).length ? { reply_markup: safeObject(reply_markup) } : {}),
      ...(safeInt(reply_to_message_id, 0) > 0 ? { reply_to_message_id: safeInt(reply_to_message_id, 0) } : {}),
      disable_notification: safeBool(disable_notification, false),
      disable_web_page_preview: safeBool(disable_web_page_preview, true),
    });
    const message = safeObject(parsed.result);
    return {
      ok: true,
      chat_id: safeString(message.chat?.id || chatId),
      message_id: safeInt(message.message_id, 0),
      response: parsed,
    };
  }

  async function answerCallbackQuery({
    callback_query_id = '',
    text = '',
    show_alert = false,
  } = {}) {
    const callbackQueryId = safeString(callback_query_id);
    if (!callbackQueryId) throw new Error('telegram_callback_query_id_missing');
    const parsed = await callApi('answerCallbackQuery', {
      callback_query_id: callbackQueryId,
      ...(safeString(text) ? { text: safeString(text).slice(0, 180) } : {}),
      show_alert: safeBool(show_alert, false),
    });
    return {
      ok: true,
      answered: parsed.result === true,
      response: parsed,
    };
  }

  return {
    async getUpdates(options) {
      return await getUpdates(options);
    },
    async deleteWebhook(options) {
      return await deleteWebhook(options);
    },
    async postMessage(payload) {
      return await postMessage(payload);
    },
    async answerCallbackQuery(payload) {
      return await answerCallbackQuery(payload);
    },
  };
}
