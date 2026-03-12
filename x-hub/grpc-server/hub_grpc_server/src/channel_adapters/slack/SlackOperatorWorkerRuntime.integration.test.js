import assert from 'node:assert/strict';
import http from 'node:http';

import { computeSlackSignature } from './SlackIngress.js';
import { startSlackOperatorWorker } from './SlackOperatorWorkerRuntime.js';

function runAsync(name, fn) {
  return (async () => {
    try {
      await fn();
      process.stdout.write(`ok - ${name}\n`);
    } catch (error) {
      process.stderr.write(`not ok - ${name}\n`);
      throw error;
    }
  })();
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

function makeSignedEvent({
  signing_secret,
  text = 'deploy plan',
  timestamp_sec = 1710000005,
} = {}) {
  const payload = {
    type: 'event_callback',
    team_id: 'T001',
    event_id: `Ev-${text.replace(/\s+/g, '-')}`,
    event_time: 1710000000,
    event: {
      type: 'message',
      user: 'U123',
      channel: 'C456',
      channel_type: 'channel',
      text,
      ts: '1710000000.1234',
      thread_ts: '1710000000.0001',
      client_msg_id: 'msg-1',
    },
  };
  const raw_body = JSON.stringify(payload);
  return {
    raw_body,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'x-slack-request-timestamp': String(timestamp_sec),
      'x-slack-signature': computeSlackSignature({
        signing_secret,
        timestamp_sec,
        raw_body,
      }),
    },
  };
}

await runAsync('SlackOperatorWorkerRuntime keeps webhook ack 202 when Slack reply delivery fails', async () => {
  const port = 56100 + Math.floor(Math.random() * 2000);
  const signing_secret = 'slack-secret-1';
  const runtime = await startSlackOperatorWorker({
    env: {
      HUB_HOST: '127.0.0.1',
      HUB_PORT: '50051',
      HUB_SLACK_OPERATOR_ENABLE: '1',
      HUB_SLACK_OPERATOR_HOST: '127.0.0.1',
      HUB_SLACK_OPERATOR_PORT: String(port),
      HUB_SLACK_OPERATOR_SIGNING_SECRET: signing_secret,
      HUB_SLACK_OPERATOR_BOT_TOKEN: 'xoxb-slack-1',
      HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'connector-token-1',
    },
    log: () => {},
    now_fn: () => 1710000005000,
    createHubClient: () => ({
      async evaluateChannelCommandGate(req) {
        return {
          decision: {
            allowed: true,
            action_name: req.action_name,
            binding_id: 'binding-deploy-1',
            scope_type: 'project',
            scope_id: 'project_alpha',
            route_mode: 'hub_to_xt',
          },
          audit_logged: true,
        };
      },
      async resolveSupervisorChannelRoute() {
        return {
          ok: true,
          audit_logged: true,
          created: true,
          updated: false,
          route: {
            route_mode: 'hub_to_xt',
            resolved_device_id: 'xt-alpha-1',
            scope_type: 'project',
            scope_id: 'project_alpha',
            xt_online: true,
          },
        };
      },
      close() {},
    }),
    createSlackApiClientFactory: () => ({
      async postMessage() {
        throw new Error('slack_post_failed');
      },
    }),
  });

  try {
    const signed = makeSignedEvent({
      signing_secret,
      text: 'deploy plan',
    });
    const out = await requestJson({
      method: 'POST',
      url: `http://127.0.0.1:${port}/slack/events`,
      headers: signed.headers,
      body: signed.raw_body,
      timeout_ms: 3_000,
    });

    assert.equal(out.status, 202);
    assert.equal(!!out.json?.ok, true);
    assert.equal(!!out.json?.accepted, true);
  } finally {
    await runtime.close();
  }
});
