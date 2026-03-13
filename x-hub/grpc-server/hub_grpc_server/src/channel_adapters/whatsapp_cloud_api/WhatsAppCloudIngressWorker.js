import http from 'node:http';

import { normalizeWhatsAppCloudWebhookRequest } from './WhatsAppCloudIngress.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function jsonResponse(res, status, obj) {
  res.writeHead(Number(status || 200), {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  res.end(JSON.stringify(obj ?? {}));
}

function textResponse(res, status, text) {
  res.writeHead(Number(status || 200), {
    'content-type': 'text/plain; charset=utf-8',
    'cache-control': 'no-store',
  });
  res.end(String(text || ''));
}

async function readRawBody(req, { max_bytes = 256 * 1024 } = {}) {
  const limit = Math.max(1024, safeInt(max_bytes, 256 * 1024));
  const chunks = [];
  let total = 0;
  return await new Promise((resolve) => {
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      resolve(result);
    };
    req.on('data', (chunk) => {
      if (settled) return;
      const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      total += buf.length;
      if (total > limit) {
        finish({ ok: false, error: 'payload_too_large' });
        return;
      }
      chunks.push(buf);
    });
    req.on('end', () => {
      finish({
        ok: true,
        raw_body: Buffer.concat(chunks).toString('utf8'),
      });
    });
    req.on('error', () => {
      finish({ ok: false, error: 'read_failed' });
    });
  });
}

function statusForDenyCode(deny_code) {
  const code = safeString(deny_code);
  if (
    code === 'payload_invalid'
    || code === 'event_type_unsupported'
    || code === 'content_type_unsupported'
    || code === 'verify_mode_invalid'
    || code === 'verify_challenge_missing'
  ) return 400;
  if (code === 'payload_too_large') return 413;
  if (
    code === 'verify_token_invalid'
    || code === 'verify_token_missing'
    || code === 'signature_missing'
    || code === 'signature_invalid'
    || code === 'signature_secret_missing'
  ) return 401;
  return 403;
}

function parseQuery(reqUrl = '') {
  const url = new URL(String(reqUrl || '/'), 'http://127.0.0.1');
  return url.searchParams;
}

export function createWhatsAppCloudIngressHandler(options = {}) {
  const verify_token = safeString(options.verify_token);
  const app_secret = safeString(options.app_secret);
  const account_id = safeString(options.account_id);
  const event_path = safeString(options.event_path || '/whatsapp/events') || '/whatsapp/events';
  const health_path = safeString(options.health_path || '/health') || '/health';
  const body_max_bytes = Math.max(1024, safeInt(options.body_max_bytes, 256 * 1024));
  const onEnvelope = typeof options.onEnvelope === 'function' ? options.onEnvelope : (async () => ({ ok: true }));
  const now_fn = typeof options.now_fn === 'function' ? options.now_fn : Date.now;

  return async function handleWhatsAppCloudIngress(req, res) {
    const method = safeString(req?.method || 'GET').toUpperCase();
    const url = safeString(req?.url || '');
    const pathname = safeString(url.split('?')[0] || '/');

    if (method === 'GET' && pathname === health_path) {
      jsonResponse(res, 200, {
        ok: true,
        service: 'whatsapp_cloud_ingress_worker',
        provider: 'whatsapp_cloud_api',
        now_ms: safeInt(now_fn(), Date.now()),
      });
      return;
    }

    if (method === 'GET' && pathname === event_path) {
      const params = parseQuery(url);
      const mode = safeString(params.get('hub.mode'));
      const challenge = safeString(params.get('hub.challenge'));
      const token = safeString(params.get('hub.verify_token'));
      if (!verify_token) {
        jsonResponse(res, 401, {
          ok: false,
          error: {
            code: 'verify_token_missing',
            message: 'verify_token_missing',
            retryable: false,
          },
        });
        return;
      }
      if (mode !== 'subscribe') {
        jsonResponse(res, 400, {
          ok: false,
          error: {
            code: 'verify_mode_invalid',
            message: 'verify_mode_invalid',
            retryable: false,
          },
        });
        return;
      }
      if (!challenge) {
        jsonResponse(res, 400, {
          ok: false,
          error: {
            code: 'verify_challenge_missing',
            message: 'verify_challenge_missing',
            retryable: false,
          },
        });
        return;
      }
      if (token !== verify_token) {
        jsonResponse(res, 401, {
          ok: false,
          error: {
            code: 'verify_token_invalid',
            message: 'verify_token_invalid',
            retryable: false,
          },
        });
        return;
      }
      textResponse(res, 200, challenge);
      return;
    }

    if (method !== 'POST' || pathname !== event_path) {
      jsonResponse(res, 404, {
        ok: false,
        error: {
          code: 'not_found',
          message: 'not_found',
          retryable: false,
        },
      });
      return;
    }

    const raw = await readRawBody(req, { max_bytes: body_max_bytes });
    if (!raw.ok) {
      if (safeString(raw.error) === 'payload_too_large') {
        try { res.shouldKeepAlive = false; } catch { /* ignore */ }
      }
      jsonResponse(res, statusForDenyCode(raw.error), {
        ok: false,
        error: {
          code: safeString(raw.error || 'read_failed'),
          message: safeString(raw.error || 'read_failed'),
          retryable: false,
        },
      });
      return;
    }

    const normalized = normalizeWhatsAppCloudWebhookRequest({
      headers: req?.headers || {},
      raw_body: raw.raw_body,
      content_type: req?.headers?.['content-type'] || '',
      app_secret,
      account_id,
    });
    if (!normalized.ok) {
      jsonResponse(res, statusForDenyCode(normalized.deny_code), {
        ok: false,
        error: {
          code: safeString(normalized.deny_code || 'ingress_denied'),
          message: safeString(normalized.deny_code || 'ingress_denied'),
          retryable: false,
        },
      });
      return;
    }

    let accepted = null;
    try {
      accepted = await onEnvelope(normalized);
    } catch {
      accepted = { ok: false, deny_code: 'ingress_handler_failed' };
    }

    if (accepted && accepted.ok === false) {
      jsonResponse(res, 503, {
        ok: false,
        error: {
          code: safeString(accepted.deny_code || 'ingress_handler_failed'),
          message: safeString(accepted.deny_code || 'ingress_handler_failed'),
          retryable: true,
        },
      });
      return;
    }

    jsonResponse(res, 200, {
      ok: true,
      accepted: true,
      envelope_type: safeString(normalized.envelope_type),
      replay_key: safeString(normalized.replay_key),
    });
  };
}

export function createWhatsAppCloudIngressServer(options = {}) {
  const host = safeString(options.host || '127.0.0.1') || '127.0.0.1';
  const port = Math.max(0, safeInt(options.port, 0));
  const handler = createWhatsAppCloudIngressHandler(options);
  const server = http.createServer((req, res) => {
    Promise.resolve(handler(req, res)).catch(() => {
      jsonResponse(res, 503, {
        ok: false,
        error: {
          code: 'internal',
          message: 'internal',
          retryable: true,
        },
      });
    });
  });

  return {
    server,
    async listen() {
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(port, host, () => {
          server.off('error', reject);
          resolve();
        });
      });
      return server.address();
    },
    async close() {
      await new Promise((resolve) => {
        try {
          server.close(() => resolve());
        } catch {
          resolve();
        }
      });
    },
  };
}
