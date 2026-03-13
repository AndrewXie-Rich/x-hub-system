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

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function normalizeApiBaseUrl(input) {
  const value = safeString(input || 'https://graph.facebook.com') || 'https://graph.facebook.com';
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function normalizeApiVersion(input) {
  const value = safeString(input || 'v23.0') || 'v23.0';
  return value.replace(/^\/+|\/+$/g, '');
}

function parseJson(text) {
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    return null;
  }
}

function normalizeWhatsAppCloudRecipient(input) {
  const raw = safeString(input).replace(/^whatsapp:/i, '');
  if (!raw) return '';
  if (raw.includes('@')) return raw;
  return raw.replace(/[^\d]/g, '');
}

export function whatsappCloudReplyCredentialsFromEnv(env = process.env) {
  return {
    access_token: safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN || ''),
    phone_number_id: safeString(env.HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID || ''),
  };
}

export function createWhatsAppCloudApiClient({
  access_token = '',
  phone_number_id = '',
  fetch_impl = globalThis.fetch,
  api_base_url = 'https://graph.facebook.com',
  api_version = 'v23.0',
  timeout_ms = 15_000,
} = {}) {
  const accessToken = safeString(access_token);
  const phoneNumberId = safeString(phone_number_id);
  const fetchFn = typeof fetch_impl === 'function' ? fetch_impl : null;
  const baseUrl = normalizeApiBaseUrl(api_base_url);
  const apiVersion = normalizeApiVersion(api_version);
  const timeoutMs = Math.max(1000, safeInt(timeout_ms, 15_000));

  async function callApi(path, payload = {}) {
    if (!accessToken) throw new Error('whatsapp_cloud_access_token_missing');
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
      response = await fetchFn(`${baseUrl}/${apiVersion}/${path.replace(/^\/+/, '')}`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${accessToken}`,
          'content-type': 'application/json; charset=utf-8',
        },
        body: JSON.stringify(safeObject(payload)),
        ...(controller ? { signal: controller.signal } : {}),
      });
    } catch (error) {
      if (timer) clearTimeout(timer);
      throw new Error(`whatsapp_cloud_fetch_failed:${safeString(error?.message || 'unknown')}`);
    }
    if (timer) clearTimeout(timer);

    const raw = await response.text();
    const parsed = parseJson(raw);
    if (!response.ok) {
      throw new Error(`whatsapp_cloud_http_${safeInt(response.status, 0)}:${safeString(parsed?.error?.message || raw || 'request_failed')}`);
    }
    if (parsed && parsed.error) {
      throw new Error(`whatsapp_cloud_api_error:${safeString(parsed.error?.message || 'unknown')}`);
    }
    return parsed || {};
  }

  async function postMessage({
    to = '',
    text = '',
    reply_to_message_id = '',
    preview_url = false,
  } = {}) {
    if (!phoneNumberId) throw new Error('whatsapp_cloud_phone_number_id_missing');
    const recipient = normalizeWhatsAppCloudRecipient(to);
    const bodyText = safeString(text);
    if (!recipient) throw new Error('whatsapp_cloud_recipient_missing');
    if (!bodyText) throw new Error('whatsapp_cloud_text_missing');

    const parsed = await callApi(`${phoneNumberId}/messages`, {
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      to: recipient,
      type: 'text',
      text: {
        preview_url: safeBool(preview_url, false),
        body: bodyText,
      },
      ...(safeString(reply_to_message_id) ? {
        context: {
          message_id: safeString(reply_to_message_id),
        },
      } : {}),
    });
    const contacts = Array.isArray(parsed.contacts) ? parsed.contacts : [];
    const messages = Array.isArray(parsed.messages) ? parsed.messages : [];
    return {
      ok: true,
      message_id: safeString(messages[0]?.id),
      to: safeString(contacts[0]?.wa_id || recipient),
      response: parsed,
    };
  }

  return {
    async postMessage(payload) {
      return await postMessage(payload);
    },
  };
}
