function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function normalizeApiBaseUrl(input) {
  const value = safeString(input || 'https://slack.com/api') || 'https://slack.com/api';
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function parseJson(text) {
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    return null;
  }
}

export function slackBotTokenFromEnv(env = process.env) {
  return safeString(env.HUB_SLACK_OPERATOR_BOT_TOKEN || '');
}

export function createSlackApiClient({
  token = '',
  fetch_impl = globalThis.fetch,
  api_base_url = 'https://slack.com/api',
  timeout_ms = 10_000,
} = {}) {
  const bearer = safeString(token);
  const fetchFn = typeof fetch_impl === 'function' ? fetch_impl : null;
  const baseUrl = normalizeApiBaseUrl(api_base_url);
  const timeoutMs = safeInt(timeout_ms, 10_000) || 10_000;

  async function postMessage(payload = {}) {
    const body = safeObject(payload);
    if (!bearer) {
      throw new Error('slack_bot_token_missing');
    }
    if (!fetchFn) {
      throw new Error('fetch_impl_missing');
    }
    if (!safeString(body.channel)) {
      throw new Error('slack_channel_missing');
    }
    if (!safeString(body.text)) {
      throw new Error('slack_text_missing');
    }

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
      response = await fetchFn(`${baseUrl}/chat.postMessage`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${bearer}`,
          'content-type': 'application/json; charset=utf-8',
        },
        body: JSON.stringify(body),
        ...(controller ? { signal: controller.signal } : {}),
      });
    } catch (error) {
      if (timer) clearTimeout(timer);
      throw new Error(`slack_fetch_failed:${safeString(error?.message || 'unknown')}`);
    }
    if (timer) clearTimeout(timer);

    const raw = await response.text();
    const parsed = parseJson(raw);
    if (!response.ok) {
      throw new Error(`slack_http_${safeInt(response.status, 0)}:${safeString(parsed?.error || raw || 'request_failed')}`);
    }
    if (!parsed || parsed.ok !== true) {
      throw new Error(`slack_api_error:${safeString(parsed?.error || 'unknown')}`);
    }

    return {
      ok: true,
      channel: safeString(parsed.channel || body.channel),
      message_ts: safeString(parsed.ts),
      warning: safeString(parsed.warning),
      response: parsed,
    };
  }

  return {
    async postMessage(payload) {
      return await postMessage(payload);
    },
  };
}
