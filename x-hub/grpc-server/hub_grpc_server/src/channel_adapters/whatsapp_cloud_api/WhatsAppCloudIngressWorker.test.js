import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import http from 'node:http';

import { createWhatsAppCloudIngressServer } from './WhatsAppCloudIngressWorker.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function request({
  method = 'GET',
  url,
  headers = {},
  body,
  timeout_ms = 2_000,
} = {}) {
  const target = new URL(String(url || ''));
  const payload = body == null ? '' : (typeof body === 'string' ? body : JSON.stringify(body));
  const reqHeaders = { ...headers };
  if (payload) {
    if (!reqHeaders['content-type']) reqHeaders['content-type'] = 'application/json; charset=utf-8';
    reqHeaders['content-length'] = String(Buffer.byteLength(payload, 'utf8'));
  }

  return new Promise((resolve, reject) => {
    const req = http.request({
      method: String(method || 'GET').toUpperCase(),
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers: reqHeaders,
      timeout: Math.max(100, Number(timeout_ms || 0)),
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try {
          json = text ? JSON.parse(text) : null;
        } catch {
          json = null;
        }
        resolve({
          status: Number(res.statusCode || 0),
          headers: res.headers || {},
          text,
          json,
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    if (payload) req.write(payload);
    req.end();
  });
}

function sign(body, secret) {
  return `sha256=${crypto.createHmac('sha256', secret).update(String(body), 'utf8').digest('hex')}`;
}

async function withWhatsAppCloudIngressServer(options = {}, fn) {
  const worker = createWhatsAppCloudIngressServer({
    host: '127.0.0.1',
    port: 0,
    verify_token: 'verify-token-1',
    app_secret: 'app-secret-1',
    account_id: 'ops_whatsapp_cloud',
    ...options,
  });
  const address = await worker.listen();
  const port = Number(address?.port || 0);
  assert.ok(port > 0, 'expected ephemeral worker port');
  const base_url = `http://127.0.0.1:${port}`;
  try {
    await fn({ base_url });
  } finally {
    await worker.close();
  }
}

await runAsync('WhatsAppCloudIngressWorker GET /health returns local readiness snapshot', async () => {
  await withWhatsAppCloudIngressServer({
    now_fn: () => 1710000005000,
  }, async ({ base_url }) => {
    const out = await request({
      method: 'GET',
      url: `${base_url}/health`,
    });

    assert.equal(out.status, 200);
    assert.equal(!!out.json?.ok, true);
    assert.equal(String(out.json?.service || ''), 'whatsapp_cloud_ingress_worker');
    assert.equal(String(out.json?.provider || ''), 'whatsapp_cloud_api');
    assert.equal(Number(out.json?.now_ms || 0), 1710000005000);
  });
});

await runAsync('WhatsAppCloudIngressWorker accepts verified GET challenge', async () => {
  await withWhatsAppCloudIngressServer({}, async ({ base_url }) => {
    const out = await request({
      method: 'GET',
      url: `${base_url}/whatsapp/events?hub.mode=subscribe&hub.verify_token=verify-token-1&hub.challenge=challenge-xyz`,
    });

    assert.equal(out.status, 200);
    assert.equal(String(out.text || ''), 'challenge-xyz');
  });
});

await runAsync('WhatsAppCloudIngressWorker forwards verified message callbacks into onEnvelope', async () => {
  const seen = [];
  const payload = {
    object: 'whatsapp_business_account',
    entry: [{
      id: 'waba-1',
      changes: [{
        field: 'messages',
        value: {
          metadata: {
            phone_number_id: 'phone-number-id-1',
          },
          messages: [{
            from: '15551234567',
            id: 'wamid.1',
            type: 'text',
            text: {
              body: 'status',
            },
          }],
        },
      }],
    }],
  };

  await withWhatsAppCloudIngressServer({
    onEnvelope: async (envelope) => {
      seen.push(envelope);
      return { ok: true };
    },
  }, async ({ base_url }) => {
    const rawBody = JSON.stringify(payload);
    const out = await request({
      method: 'POST',
      url: `${base_url}/whatsapp/events`,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'x-hub-signature-256': sign(rawBody, 'app-secret-1'),
      },
      body: rawBody,
    });

    assert.equal(out.status, 200);
    assert.equal(!!out.json?.ok, true);
    assert.equal(!!out.json?.accepted, true);
    assert.equal(String(out.json?.envelope_type || ''), 'messages');
  });

  assert.equal(seen.length, 1);
  assert.equal(String(seen[0]?.actor?.external_user_id || ''), '15551234567');
  assert.equal(String(seen[0]?.channel?.conversation_id || ''), '15551234567');
  assert.equal(String(seen[0]?.structured_action?.action_name || ''), 'supervisor.status.get');
});

await runAsync('WhatsAppCloudIngressWorker rejects invalid verify token fail-closed', async () => {
  await withWhatsAppCloudIngressServer({}, async ({ base_url }) => {
    const out = await request({
      method: 'GET',
      url: `${base_url}/whatsapp/events?hub.mode=subscribe&hub.verify_token=wrong-token&hub.challenge=challenge-xyz`,
    });

    assert.equal(out.status, 401);
    assert.equal(!!out.json?.ok, false);
    assert.equal(String(out.json?.error?.code || ''), 'verify_token_invalid');
  });
});

run('WhatsAppCloudIngressWorker exports a server factory', () => {
  assert.equal(typeof createWhatsAppCloudIngressServer, 'function');
});
