function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function normalizeApiBaseUrl(input) {
  const value = safeString(input || 'https://open.feishu.cn/open-apis') || 'https://open.feishu.cn/open-apis';
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function parseJson(text) {
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    return null;
  }
}

export function feishuBotCredentialsFromEnv(env = process.env) {
  return {
    app_id: safeString(env.HUB_FEISHU_OPERATOR_BOT_APP_ID || ''),
    app_secret: safeString(env.HUB_FEISHU_OPERATOR_BOT_APP_SECRET || ''),
  };
}

export function createFeishuApiClient({
  app_id = '',
  app_secret = '',
  fetch_impl = globalThis.fetch,
  api_base_url = 'https://open.feishu.cn/open-apis',
  timeout_ms = 10_000,
  now_fn = Date.now,
} = {}) {
  const appId = safeString(app_id);
  const appSecret = safeString(app_secret);
  const fetchFn = typeof fetch_impl === 'function' ? fetch_impl : null;
  const baseUrl = normalizeApiBaseUrl(api_base_url);
  const timeoutMs = safeInt(timeout_ms, 10_000) || 10_000;
  let cachedToken = '';
  let cachedExpireAtMs = 0;

  async function fetchJson(url, { method = 'GET', headers = {}, body = null } = {}) {
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
      response = await fetchFn(url, {
        method,
        headers,
        ...(body == null ? {} : { body }),
        ...(controller ? { signal: controller.signal } : {}),
      });
    } catch (error) {
      if (timer) clearTimeout(timer);
      throw new Error(`feishu_fetch_failed:${safeString(error?.message || 'unknown')}`);
    }
    if (timer) clearTimeout(timer);

    const raw = await response.text();
    const parsed = parseJson(raw);
    if (!response.ok) {
      throw new Error(`feishu_http_${safeInt(response.status, 0)}:${safeString(parsed?.msg || parsed?.error || raw || 'request_failed')}`);
    }
    if (!parsed || Number(parsed.code) !== 0) {
      throw new Error(`feishu_api_error:${safeString(parsed?.msg || 'unknown')}`);
    }
    return parsed;
  }

  async function getTenantAccessToken({ force_refresh = false } = {}) {
    if (!appId) throw new Error('feishu_app_id_missing');
    if (!appSecret) throw new Error('feishu_app_secret_missing');
    const nowMs = typeof now_fn === 'function' ? Number(now_fn()) : Date.now();
    if (!force_refresh && cachedToken && cachedExpireAtMs > nowMs + 5_000) {
      return {
        ok: true,
        tenant_access_token: cachedToken,
        expire_at_ms: cachedExpireAtMs,
      };
    }

    const parsed = await fetchJson(`${baseUrl}/auth/v3/tenant_access_token/internal`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json; charset=utf-8',
      },
      body: JSON.stringify({
        app_id: appId,
        app_secret: appSecret,
      }),
    });
    const token = safeString(parsed.tenant_access_token);
    const expireSeconds = Math.max(60, safeInt(parsed.expire, 7200));
    if (!token) {
      throw new Error('feishu_api_error:tenant_access_token_missing');
    }
    cachedToken = token;
    cachedExpireAtMs = nowMs + (expireSeconds * 1000);
    return {
      ok: true,
      tenant_access_token: token,
      expire_at_ms: cachedExpireAtMs,
    };
  }

  async function postMessage({
    receive_id = '',
    receive_id_type = 'chat_id',
    content = '',
    msg_type = 'interactive',
    reply_to_message_id = '',
    reply_in_thread = true,
  } = {}) {
    const receiveId = safeString(receive_id);
    const receiveIdType = safeString(receive_id_type || 'chat_id') || 'chat_id';
    const contentText = safeString(content);
    const msgType = safeString(msg_type || 'interactive') || 'interactive';
    const replyMessageId = safeString(reply_to_message_id);
    if (!contentText) throw new Error('feishu_content_missing');
    if (!replyMessageId && !receiveId) throw new Error('feishu_receive_id_missing');

    const token = await getTenantAccessToken();
    const headers = {
      authorization: `Bearer ${token.tenant_access_token}`,
      'content-type': 'application/json; charset=utf-8',
    };

    const parsed = replyMessageId
      ? await fetchJson(`${baseUrl}/im/v1/messages/${encodeURIComponent(replyMessageId)}/reply`, {
          method: 'POST',
          headers,
          body: JSON.stringify({
            content: contentText,
            msg_type: msgType,
            ...(reply_in_thread ? { reply_in_thread: true } : {}),
          }),
        })
      : await fetchJson(`${baseUrl}/im/v1/messages?receive_id_type=${encodeURIComponent(receiveIdType)}`, {
          method: 'POST',
          headers,
          body: JSON.stringify({
            receive_id: receiveId,
            content: contentText,
            msg_type: msgType,
          }),
        });

    const messageId = safeString(parsed?.data?.message_id);
    return {
      ok: true,
      message_id: messageId,
      receive_id: receiveId,
      receive_id_type: receiveIdType,
      response: parsed,
    };
  }

  return {
    async getTenantAccessToken(options) {
      return await getTenantAccessToken(options);
    },
    async postMessage(payload) {
      return await postMessage(payload);
    },
  };
}
