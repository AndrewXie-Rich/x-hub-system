import assert from 'node:assert/strict';
import http from 'node:http';

import { createFeishuIngressServer } from './FeishuIngressWorker.js';

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

function requestJson({
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

async function withFeishuIngressServer(options = {}, fn) {
  const worker = createFeishuIngressServer({
    host: '127.0.0.1',
    port: 0,
    verification_token: 'verify-token-1',
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

await runAsync('FeishuIngressWorker GET /health returns local readiness snapshot', async () => {
  await withFeishuIngressServer({
    now_fn: () => 1710000005000,
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'GET',
      url: `${base_url}/health`,
    });

    assert.equal(out.status, 200);
    assert.equal(!!out.json?.ok, true);
    assert.equal(String(out.json?.service || ''), 'feishu_ingress_worker');
    assert.equal(String(out.json?.provider || ''), 'feishu');
    assert.equal(Number(out.json?.now_ms || 0), 1710000005000);
  });
});

await runAsync('FeishuIngressWorker accepts verified url_verification challenge', async () => {
  const payload = {
    type: 'url_verification',
    challenge: 'challenge-xyz',
    token: 'verify-token-1',
  };

  await withFeishuIngressServer({}, async ({ base_url }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${base_url}/feishu/events`,
      body: payload,
    });

    assert.equal(out.status, 200);
    assert.equal(String(out.json?.challenge || ''), 'challenge-xyz');
  });
});

await runAsync('FeishuIngressWorker forwards verified event callbacks into onEnvelope', async () => {
  const seen = [];
  const payload = {
    schema: '2.0',
    header: {
      event_id: 'feishu-evt-1',
      event_type: 'im.message.receive_v1',
      create_time: '1710000000123',
      tenant_key: 'tenant-ops',
      token: 'verify-token-1',
    },
    event: {
      sender: {
        sender_id: {
          open_id: 'ou_user_1',
        },
      },
      message: {
        message_id: 'om_1',
        thread_id: 'omt_1',
        chat_id: 'oc_room_1',
        chat_type: 'group',
        message_type: 'text',
        content: JSON.stringify({
          text: 'status',
        }),
      },
    },
  };

  await withFeishuIngressServer({
    onEnvelope: async (envelope) => {
      seen.push(envelope);
      return { ok: true };
    },
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${base_url}/feishu/events`,
      body: payload,
    });

    assert.equal(out.status, 202);
    assert.equal(!!out.json?.ok, true);
    assert.equal(!!out.json?.accepted, true);
    assert.equal(String(out.json?.envelope_type || ''), 'event_callback');
  });

  assert.equal(seen.length, 1);
  assert.equal(String(seen[0]?.actor?.external_user_id || ''), 'ou_user_1');
  assert.equal(String(seen[0]?.channel?.conversation_id || ''), 'oc_room_1');
  assert.equal(String(seen[0]?.channel?.thread_key || ''), 'om_1');
  assert.equal(String(seen[0]?.structured_action?.action_name || ''), 'supervisor.status.get');
});

await runAsync('FeishuIngressWorker rejects invalid verification token fail-closed', async () => {
  let call_count = 0;
  const payload = {
    type: 'url_verification',
    challenge: 'challenge-xyz',
    token: 'wrong-token',
  };

  await withFeishuIngressServer({
    onEnvelope: async () => {
      call_count += 1;
      return { ok: true };
    },
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${base_url}/feishu/events`,
      body: payload,
    });

    assert.equal(out.status, 401);
    assert.equal(!!out.json?.ok, false);
    assert.equal(String(out.json?.error?.code || ''), 'verification_token_invalid');
  });

  assert.equal(call_count, 0);
});

await runAsync('FeishuIngressWorker rejects oversized bodies fail-closed', async () => {
  let call_count = 0;
  const payload = {
    type: 'url_verification',
    challenge: 'x'.repeat(2048),
    token: 'verify-token-1',
  };

  await withFeishuIngressServer({
    body_max_bytes: 1024,
    onEnvelope: async () => {
      call_count += 1;
      return { ok: true };
    },
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${base_url}/feishu/events`,
      body: payload,
      timeout_ms: 3_000,
    });

    assert.equal(out.status, 413);
    assert.equal(!!out.json?.ok, false);
    assert.equal(String(out.json?.error?.code || ''), 'payload_too_large');
  });

  assert.equal(call_count, 0);
});

run('FeishuIngressWorker exports a server factory', () => {
  assert.equal(typeof createFeishuIngressServer, 'function');
});
