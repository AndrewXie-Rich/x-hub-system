import assert from 'node:assert/strict';
import http from 'node:http';

import { computeSlackSignature } from './SlackIngress.js';
import { createSlackIngressServer } from './SlackIngressWorker.js';

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

function makeSignedHeaders({
  signing_secret,
  raw_body,
  timestamp_sec,
  content_type = 'application/json; charset=utf-8',
  signature,
} = {}) {
  return {
    'content-type': String(content_type || 'application/json; charset=utf-8'),
    'x-slack-request-timestamp': String(timestamp_sec),
    'x-slack-signature': String(signature || computeSlackSignature({
      signing_secret,
      timestamp_sec,
      raw_body,
    })),
  };
}

async function withSlackIngressServer(options = {}, fn) {
  const worker = createSlackIngressServer({
    host: '127.0.0.1',
    port: 0,
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

await runAsync('SlackIngressWorker GET /health returns local readiness snapshot', async () => {
  await withSlackIngressServer({
    now_fn: () => 1710000005000,
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'GET',
      url: `${base_url}/health`,
    });

    assert.equal(out.status, 200);
    assert.equal(!!out.json?.ok, true);
    assert.equal(String(out.json?.service || ''), 'slack_ingress_worker');
    assert.equal(String(out.json?.provider || ''), 'slack');
    assert.equal(Number(out.json?.now_ms || 0), 1710000005000);
  });
});

await runAsync('SlackIngressWorker accepts signed url_verification challenge', async () => {
  const signing_secret = 'slack-signing-secret';
  const payload = {
    type: 'url_verification',
    challenge: 'challenge-xyz',
  };
  const raw_body = JSON.stringify(payload);
  const timestamp_sec = 1710000005;

  await withSlackIngressServer({
    signing_secret,
    now_fn: () => timestamp_sec * 1000,
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${base_url}/slack/events`,
      headers: makeSignedHeaders({
        signing_secret,
        raw_body,
        timestamp_sec,
      }),
      body: raw_body,
    });

    assert.equal(out.status, 200);
    assert.equal(String(out.json?.challenge || ''), 'challenge-xyz');
  });
});

await runAsync('SlackIngressWorker forwards signed event callbacks into onEnvelope', async () => {
  const signing_secret = 'slack-signing-secret';
  const seen = [];
  const payload = {
    type: 'event_callback',
    team_id: 'T001',
    event_id: 'Ev001',
    event_time: 1710000000,
    event: {
      type: 'message',
      user: 'U123',
      channel: 'C456',
      channel_type: 'channel',
      text: 'status',
      ts: '1710000000.1234',
      thread_ts: '1710000000.0001',
      client_msg_id: 'msg-1',
    },
  };
  const raw_body = JSON.stringify(payload);
  const timestamp_sec = 1710000005;

  await withSlackIngressServer({
    signing_secret,
    now_fn: () => timestamp_sec * 1000,
    onEnvelope: async (envelope) => {
      seen.push(envelope);
      return { ok: true };
    },
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${base_url}/slack/events`,
      headers: makeSignedHeaders({
        signing_secret,
        raw_body,
        timestamp_sec,
      }),
      body: raw_body,
    });

    assert.equal(out.status, 202);
    assert.equal(!!out.json?.ok, true);
    assert.equal(!!out.json?.accepted, true);
    assert.equal(String(out.json?.envelope_type || ''), 'event_callback');
  });

  assert.equal(seen.length, 1);
  assert.equal(String(seen[0]?.actor?.external_user_id || ''), 'U123');
  assert.equal(String(seen[0]?.channel?.conversation_id || ''), 'C456');
  assert.equal(String(seen[0]?.channel?.thread_key || ''), '1710000000.0001');
  assert.equal(String(seen[0]?.structured_action?.action_name || ''), 'supervisor.status.get');
});

await runAsync('SlackIngressWorker rejects invalid signatures fail-closed', async () => {
  const signing_secret = 'slack-signing-secret';
  let call_count = 0;
  const payload = {
    type: 'url_verification',
    challenge: 'challenge-xyz',
  };
  const raw_body = JSON.stringify(payload);
  const timestamp_sec = 1710000005;

  await withSlackIngressServer({
    signing_secret,
    now_fn: () => timestamp_sec * 1000,
    onEnvelope: async () => {
      call_count += 1;
      return { ok: true };
    },
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${base_url}/slack/events`,
      headers: makeSignedHeaders({
        signing_secret,
        raw_body,
        timestamp_sec,
        signature: 'v0=invalid',
      }),
      body: raw_body,
    });

    assert.equal(out.status, 401);
    assert.equal(!!out.json?.ok, false);
    assert.equal(String(out.json?.error?.code || ''), 'signature_invalid');
  });

  assert.equal(call_count, 0);
});

await runAsync('SlackIngressWorker rejects oversized bodies fail-closed', async () => {
  const signing_secret = 'slack-signing-secret';
  let call_count = 0;
  const payload = {
    type: 'url_verification',
    challenge: 'x'.repeat(2048),
  };
  const raw_body = JSON.stringify(payload);
  const timestamp_sec = 1710000005;

  await withSlackIngressServer({
    signing_secret,
    body_max_bytes: 1024,
    now_fn: () => timestamp_sec * 1000,
    onEnvelope: async () => {
      call_count += 1;
      return { ok: true };
    },
  }, async ({ base_url }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${base_url}/slack/events`,
      headers: makeSignedHeaders({
        signing_secret,
        raw_body,
        timestamp_sec,
      }),
      body: raw_body,
      timeout_ms: 3_000,
    });

    assert.equal(out.status, 413);
    assert.equal(!!out.json?.ok, false);
    assert.equal(String(out.json?.error?.code || ''), 'payload_too_large');
  });

  assert.equal(call_count, 0);
});

run('SlackIngressWorker exports a server factory', () => {
  assert.equal(typeof createSlackIngressServer, 'function');
});
