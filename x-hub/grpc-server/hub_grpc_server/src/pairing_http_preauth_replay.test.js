import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import {
  createPreauthSurfaceGuard,
  createWebhookReplayGuard,
  startPairingHTTPServer,
} from './pairing_http.js';
import { createConnectorDeliveryReceiptCompensator } from './connector_delivery_receipt_compensator.js';
import { HubDB } from './db.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

async function withEnvAsync(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms || 0))));
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

function requestJson({
  method = 'GET',
  url,
  headers = {},
  body,
  agent,
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
      ...(agent ? { agent } : {}),
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

async function waitForHealth(baseUrl, timeoutMs = 2_000) {
  const deadline = Date.now() + Math.max(200, Number(timeoutMs || 0));
  let lastErr = null;
  while (Date.now() < deadline) {
    try {
      const out = await requestJson({ url: `${baseUrl}/health`, timeout_ms: 300 });
      if (out.status === 200) return;
    } catch (err) {
      lastErr = err;
    }
    await sleep(25);
  }
  if (lastErr) throw lastErr;
  throw new Error('pairing_server_not_ready');
}

function makeAuditDb() {
  const rows = [];
  return {
    rows,
    appendAudit(event) {
      rows.push(event);
    },
  };
}

async function withPairingServer({
  env = {},
  db = makeAuditDb(),
  preauthGuard = null,
  unauthorizedFloodBreaker = null,
  connectorRuntimeOrchestrator = null,
  connectorTargetOrderingGuard = null,
  connectorDeliveryReceiptCompensator = null,
  webhookReplayGuard = null,
} = {}, fn) {
  const port = 56000 + Math.floor(Math.random() * 6000);
  const baseUrl = `http://127.0.0.1:${port}`;
  await withEnvAsync({
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_HOST: '127.0.0.1',
    HUB_PORT: '50051',
    HUB_PAIRING_ALLOWED_CIDRS: 'any',
    HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_1,slack:channel_2,slack:channel_3,slack:channel_4',
    HUB_CONNECTOR_INGRESS_POLICY_JSON: '',
    ...env,
  }, async () => {
    const stop = startPairingHTTPServer({
      db,
      preauthGuard,
      unauthorizedFloodBreaker,
      connectorRuntimeOrchestrator,
      connectorTargetOrderingGuard,
      connectorDeliveryReceiptCompensator,
      webhookReplayGuard,
    });
    try {
      await waitForHealth(baseUrl, 3_000);
      await fn({ baseUrl, db });
    } finally {
      try {
        stop?.();
      } catch {
        // ignore
      }
      await sleep(40);
    }
  });
}

run('CM-W3-18/preauth rotating source key stays bounded with stale prune', () => {
  const guard = createPreauthSurfaceGuard({
    window_ms: 60_000,
    max_per_window: 20,
    max_state_keys: 32,
    stale_window_ms: 120_000,
  });

  let now = 1_000_000;
  for (let i = 0; i < 400; i += 1) {
    const out = guard.check({
      source_key: `rotating_source_${i}`,
      now_ms: now,
    });
    assert.ok(out && typeof out === 'object');
    now += 3;
  }

  const snap = guard.snapshot();
  assert.ok(Number(snap.state_keys || 0) <= 32, `state_keys=${snap.state_keys}`);
  assert.ok(Number(snap.preauth_reject_rate || 0) > 0, `reject_rate=${snap.preauth_reject_rate}`);

  guard.prune(now + (10 * 60 * 1000));
  const afterPrune = guard.snapshot();
  assert.equal(Number(afterPrune.state_keys || 0), 0);
});

await runAsync('CRK-W1-07/webhook replay duplicate signature second send is rejected', async () => {
  await withPairingServer({}, async ({ baseUrl, db }) => {
    const headers = {
      'x-source-key': 'src-main',
      'x-replay-key': 'evt-1001',
      'x-signature': 'sig-fixed-v1',
    };
    const body = {
      event_id: 'evt-1001',
      ingress_type: 'webhook',
      ts: 1700000,
      payload: { action: 'webhook.received' },
    };

    const first = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_1`,
      headers,
      body,
    });
    assert.equal(first.status, 202);
    assert.equal(!!first.json?.accepted, true);

    const second = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_1`,
      headers,
      body,
    });
    assert.equal(second.status, 409);
    assert.equal(String(second.json?.error?.code || ''), 'replay_detected');

    const rejected = db.rows.find((row) => String(row?.event_type || '') === 'connector.webhook.rejected');
    assert.ok(rejected, 'expected connector.webhook.rejected audit');
    let ext = {};
    try {
      ext = JSON.parse(String(rejected.ext_json || '{}'));
    } catch {
      ext = {};
    }
    assert.ok(Number(ext.webhook_replay_block_rate || 0) > 0, 'webhook_replay_block_rate should be > 0');
  });
});

await runAsync('CRK-W1-07/webhook replay dedupe persists across server restart with HubDB', async () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pairing_replay_persist_'));
  const dbPath = path.join(tmpDir, 'hub.db');
  const sharedEnv = {
    HUB_MEMORY_KEK_FILE: path.join(tmpDir, 'hub_memory_kek.json'),
    HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:persist_channel',
    HUB_WEBHOOK_REPLAY_TTL_MS: '60000',
    HUB_WEBHOOK_REPLAY_STALE_WINDOW_MS: '120000',
  };

  const postEvent = ({ baseUrl, replayKey = 'evt-persist-1' }) => requestJson({
    method: 'POST',
    url: `${baseUrl}/webhook/connectors/slack/persist_channel`,
    headers: {
      'x-source-key': 'src-persist',
      'x-replay-key': replayKey,
      'x-signature': 'sig-persist',
    },
    body: {
      event_id: replayKey,
      ingress_type: 'webhook',
    },
  });

  try {
    await withEnvAsync({
      HUB_MEMORY_KEK_FILE: sharedEnv.HUB_MEMORY_KEK_FILE,
    }, async () => {
      const db1 = new HubDB({ dbPath });
      try {
        await withPairingServer({
          db: db1,
          env: sharedEnv,
        }, async ({ baseUrl }) => {
          const first = await postEvent({ baseUrl, replayKey: 'evt-persist-1' });
          assert.equal(first.status, 202);
        });
      } finally {
        db1.close();
      }

      const db2 = new HubDB({ dbPath });
      try {
        await withPairingServer({
          db: db2,
          env: sharedEnv,
        }, async ({ baseUrl }) => {
          const second = await postEvent({ baseUrl, replayKey: 'evt-persist-1' });
          assert.equal(second.status, 409);
          assert.equal(String(second.json?.error?.code || ''), 'replay_detected');

          const fresh = await postEvent({ baseUrl, replayKey: 'evt-persist-2' });
          assert.equal(fresh.status, 202);
        });
      } finally {
        db2.close();
      }
    });
  } finally {
    cleanupDbArtifacts(dbPath);
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

await runAsync('CRK-W1-07/same signature with different replay keys is accepted (no false replay)', async () => {
  await withPairingServer({}, async ({ baseUrl, db }) => {
    const first = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_1`,
      headers: {
        'x-source-key': 'src-same-sig',
        'x-replay-key': 'evt-same-sig-1',
        'x-signature': 'sig-same-value',
      },
      body: {
        event_id: 'evt-same-sig-1',
        ingress_type: 'webhook',
      },
    });
    assert.equal(first.status, 202);

    const second = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_1`,
      headers: {
        'x-source-key': 'src-same-sig',
        'x-replay-key': 'evt-same-sig-2',
        'x-signature': 'sig-same-value',
      },
      body: {
        event_id: 'evt-same-sig-2',
        ingress_type: 'webhook',
      },
    });
    assert.equal(second.status, 202);

    const replayRejected = db.rows.find((row) =>
      String(row?.event_type || '') === 'connector.webhook.rejected'
      && String(row?.error_code || '') === 'replay_detected'
    );
    assert.equal(!!replayRejected, false, 'different replay keys should not be flagged as replay_detected');
  });
});

await runAsync('CM-W3-18/pre-auth body size cap rejects oversized webhook payload', async () => {
  await withPairingServer({
    env: {
      HUB_PREAUTH_BODY_MAX_BYTES: '128',
    },
  }, async ({ baseUrl }) => {
    const oversized = JSON.stringify({
      replay_key: 'evt-big-body',
      payload: 'x'.repeat(800),
    });
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_2`,
      headers: {
        'x-source-key': 'src-body-cap',
        'x-signature': 'sig-body-cap',
      },
      body: oversized,
    });
    assert.equal(out.status, 400);
    assert.equal(String(out.json?.error?.code || ''), 'body_too_large');
  });
});

await runAsync('CRK-W1-07/fail-closed when replay component throws', async () => {
  const failingReplayGuard = {
    claim() {
      throw new Error('simulated replay component failure');
    },
    snapshot() {
      return {
        total: 0,
        blocked: 0,
        webhook_replay_block_rate: 0,
      };
    },
  };

  await withPairingServer({
    webhookReplayGuard: failingReplayGuard,
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_3`,
      headers: {
        'x-source-key': 'src-fail-closed',
        'x-replay-key': 'evt-fail-closed',
        'x-signature': 'sig-fail-closed',
      },
      body: { hello: 'world' },
    });
    assert.equal(out.status, 503);
    assert.equal(String(out.json?.error?.code || ''), 'replay_guard_error');

    const rejected = db.rows.find((row) => String(row?.error_code || '') === 'replay_guard_error');
    assert.ok(rejected, 'expected replay_guard_error audit row');
  });
});

await runAsync('CRK-W1-08/unauthorized webhook flood on same connection is throttled with drop metric', async () => {
  await withPairingServer({
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:flood_channel',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-group-ok',
      HUB_UNAUTHORIZED_FLOOD_WINDOW_MS: '60000',
      HUB_UNAUTHORIZED_FLOOD_MAX_PER_WINDOW: '2',
      HUB_UNAUTHORIZED_FLOOD_PENALTY_MS: '20000',
      HUB_UNAUTHORIZED_FLOOD_AUDIT_SAMPLE_EVERY: '1',
    },
  }, async ({ baseUrl, db }) => {
    const keepAliveAgent = new http.Agent({
      keepAlive: true,
      maxSockets: 1,
      maxFreeSockets: 1,
    });
    const requestUnauthorized = (idx) => requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/flood_channel`,
      agent: keepAliveAgent,
      headers: {
        'x-source-key': 'src-flood-guard',
        'x-replay-key': `evt-flood-${idx}`,
        'x-signature': `sig-flood-${idx}`,
      },
      body: {
        event_id: `evt-flood-${idx}`,
        ingress_type: 'member',
        channel_scope: 'group',
        sender_id: `u-not-allowlisted-${idx}`,
      },
    });

    try {
      const first = await requestUnauthorized(1);
      assert.equal(first.status, 403);
      assert.equal(String(first.json?.error?.code || ''), 'sender_not_allowlisted');

      const second = await requestUnauthorized(2);
      assert.equal(second.status, 403);
      assert.equal(String(second.json?.error?.code || ''), 'sender_not_allowlisted');

      const dropped = await requestUnauthorized(3);
      assert.equal(dropped.status, 429);
      assert.equal(String(dropped.json?.error?.code || ''), 'unauthorized_flood_dropped');
      assert.ok(Number(dropped.headers?.['retry-after'] || 0) >= 1, 'retry-after should be set for flood drop');
    } finally {
      keepAliveAgent.destroy();
    }

    const droppedAudit = db.rows.find((row) =>
      String(row?.event_type || '') === 'connector.webhook.rejected'
      && String(row?.error_code || '') === 'unauthorized_flood_dropped'
    );
    assert.ok(droppedAudit, 'expected unauthorized_flood_dropped audit row');
    let ext = {};
    try {
      ext = JSON.parse(String(droppedAudit?.ext_json || '{}'));
    } catch {
      ext = {};
    }
    assert.ok(Number(ext.unauthorized_flood_drop_count || 0) > 0, 'unauthorized_flood_drop_count should be > 0');
  });
});

await runAsync('CRK-W1-08/fail-closed when unauthorized flood breaker throws', async () => {
  const failingUnauthorizedFloodBreaker = {
    check() {
      throw new Error('simulated unauthorized flood breaker failure');
    },
    recordUnauthorized() {
      // no-op
    },
    snapshot() {
      return {
        unauthorized_flood_drop_count: 0,
        checks: 0,
        unauthorized: 0,
        penalties: 0,
      };
    },
  };

  await withPairingServer({
    unauthorizedFloodBreaker: failingUnauthorizedFloodBreaker,
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:flood_fail_closed_channel',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/flood_fail_closed_channel`,
      headers: {
        'x-source-key': 'src-flood-breaker-fail',
        'x-replay-key': 'evt-flood-breaker-fail',
        'x-signature': 'sig-flood-breaker-fail',
      },
      body: {
        event_id: 'evt-flood-breaker-fail',
      },
    });
    assert.equal(out.status, 503);
    assert.equal(String(out.json?.error?.code || ''), 'unauthorized_flood_fail_closed');

    const rejected = db.rows.find((row) => String(row?.error_code || '') === 'unauthorized_flood_fail_closed');
    assert.ok(rejected, 'expected unauthorized_flood_fail_closed audit row');
  });
});

await runAsync('CRK-W1-06/non-message reaction ingress unauthorized sender is denied with machine-readable deny_code', async () => {
  await withPairingServer({
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_ingress',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-group-ok',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_ingress`,
      headers: {
        'x-source-key': 'src-non-message',
        'x-replay-key': 'evt-reaction-deny',
        'x-signature': 'sig-reaction-deny',
      },
      body: {
        event_id: 'evt-reaction-deny',
        ingress_type: 'reaction',
        channel_scope: 'group',
        sender_id: 'u-unauthorized',
      },
    });

    assert.equal(out.status, 403);
    assert.equal(String(out.json?.error?.code || ''), 'sender_not_allowlisted');

    const ingressDenied = db.rows.find((row) => String(row?.event_type || '') === 'connector.ingress.denied');
    assert.ok(ingressDenied, 'expected connector.ingress.denied audit row');
    assert.equal(String(ingressDenied?.error_code || ''), 'sender_not_allowlisted');

    const webhookRejected = db.rows.find((row) => String(row?.event_type || '') === 'connector.webhook.rejected');
    assert.ok(webhookRejected, 'expected connector.webhook.rejected audit row');
    let ext = {};
    try {
      ext = JSON.parse(String(webhookRejected?.ext_json || '{}'));
    } catch {
      ext = {};
    }
    assert.equal(Number(ext.non_message_ingress_policy_coverage || 0), 1);
    assert.equal(Number(ext.blocked_event_miss_rate || 0), 0);
    assert.equal(String(ext.non_message_ingress_gate_schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
    assert.ok(Number(ext.non_message_ingress_gate_measured_at_ms || 0) > 0);
    assert.equal(!!ext.non_message_ingress_gate_pass, true);
    assert.deepEqual(ext.non_message_ingress_gate_incident_codes || [], []);
    assert.equal(Number(ext.non_message_ingress_gate_thresholds?.non_message_ingress_policy_coverage_min || 0), 1);
    assert.ok(Number(ext.non_message_ingress_gate_thresholds?.blocked_event_miss_rate_max_exclusive || 0) > 0);
    assert.ok(Array.isArray(ext.non_message_ingress_gate_checks), 'expected machine-readable gate checks');
    assert.equal(ext.non_message_ingress_gate_checks.length >= 2, true);
    assert.equal(typeof ext.non_message_ingress_gate_metrics, 'object');
    assert.equal(Number(ext.non_message_ingress_gate_metrics?.non_message_ingress_policy_coverage || 0), 1);
    assert.equal(Number(ext.non_message_ingress_gate_metrics?.blocked_event_miss_rate || 0), 0);
    const coverageCheck = ext.non_message_ingress_gate_checks.find((x) => String(x?.key || '') === 'non_message_ingress_policy_coverage');
    assert.ok(coverageCheck, 'expected coverage check');
    assert.equal(coverageCheck.pass, true);
  });
});

await runAsync('CRK-W1-06/non-message pin ingress unauthorized sender is denied', async () => {
  await withPairingServer({
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_pin',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-pin-allowed',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_pin`,
      headers: {
        'x-source-key': 'src-pin-deny',
        'x-replay-key': 'evt-pin-deny',
        'x-signature': 'sig-pin-deny',
      },
      body: {
        event_id: 'evt-pin-deny',
        ingress_type: 'pin',
        channel_scope: 'group',
        sender_id: 'u-pin-unauthorized',
      },
    });

    assert.equal(out.status, 403);
    assert.equal(String(out.json?.error?.code || ''), 'sender_not_allowlisted');

    const ingressDenied = db.rows.find(
      (row) => String(row?.event_type || '') === 'connector.ingress.denied'
        && String(row?.error_code || '') === 'sender_not_allowlisted'
    );
    assert.ok(ingressDenied, 'expected connector.ingress.denied(sender_not_allowlisted) audit row for pin ingress');
  });
});

await runAsync('CRK-W1-06/non-message member ingress unauthorized sender is denied', async () => {
  await withPairingServer({
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_member',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-member-allowed',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_member`,
      headers: {
        'x-source-key': 'src-member-deny',
        'x-replay-key': 'evt-member-deny',
        'x-signature': 'sig-member-deny',
      },
      body: {
        event_id: 'evt-member-deny',
        ingress_type: 'member',
        channel_scope: 'group',
        sender_id: 'u-member-unauthorized',
      },
    });

    assert.equal(out.status, 403);
    assert.equal(String(out.json?.error?.code || ''), 'sender_not_allowlisted');

    const ingressDenied = db.rows.find(
      (row) => String(row?.event_type || '') === 'connector.ingress.denied'
        && String(row?.error_code || '') === 'sender_not_allowlisted'
    );
    assert.ok(ingressDenied, 'expected connector.ingress.denied(sender_not_allowlisted) audit row for member ingress');
  });
});

await runAsync('CRK-W1-06/webhook source not allowlisted is denied with webhook_not_allowlisted', async () => {
  await withPairingServer({
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_allowed_only',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-group-ok',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_denied`,
      headers: {
        'x-source-key': 'src-webhook-deny',
        'x-replay-key': 'evt-webhook-deny',
        'x-signature': 'sig-webhook-deny',
      },
      body: {
        event_id: 'evt-webhook-deny',
        ingress_type: 'webhook',
        source_id: 'slack:channel_denied',
      },
    });
    assert.equal(out.status, 403);
    assert.equal(String(out.json?.error?.code || ''), 'webhook_not_allowlisted');

    const ingressDenied = db.rows.find(
      (row) => String(row?.event_type || '') === 'connector.ingress.denied'
        && String(row?.error_code || '') === 'webhook_not_allowlisted'
    );
    assert.ok(ingressDenied, 'expected connector.ingress.denied(webhook_not_allowlisted) audit row');
  });
});

await runAsync('CRK-W1-06/fail-closed when connector ingress audit write fails', async () => {
  const rows = [];
  const failingIngressAuditDb = {
    appendAudit(event) {
      const eventType = String(event?.event_type || '');
      if (eventType === 'connector.ingress.allowed' || eventType === 'connector.ingress.denied') {
        throw new Error('simulated connector ingress audit failure');
      }
      rows.push(event);
    },
  };

  await withPairingServer({
    db: failingIngressAuditDb,
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_audit_fail_closed',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-audit-ok',
    },
  }, async ({ baseUrl }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_audit_fail_closed`,
      headers: {
        'x-source-key': 'src-audit-fail-closed',
        'x-replay-key': 'evt-audit-fail-closed',
        'x-signature': 'sig-audit-fail-closed',
      },
      body: {
        event_id: 'evt-audit-fail-closed',
        ingress_type: 'message',
        channel_scope: 'group',
        sender_id: 'u-audit-ok',
      },
    });

    assert.equal(out.status, 503);
    assert.equal(String(out.json?.error?.code || ''), 'audit_write_failed');

    const rejected = rows.find((row) => String(row?.event_type || '') === 'connector.webhook.rejected');
    assert.ok(rejected, 'expected connector.webhook.rejected audit row');
    let ext = {};
    try {
      ext = JSON.parse(String(rejected?.ext_json || '{}'));
    } catch {
      ext = {};
    }
    assert.equal(String(ext.non_message_ingress_gate_schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
    assert.ok(Number(ext.non_message_ingress_gate_measured_at_ms || 0) > 0);
    assert.equal(!!ext.non_message_ingress_gate_pass, true);
    assert.deepEqual(ext.non_message_ingress_gate_incident_codes || [], []);
    assert.equal(typeof ext.non_message_ingress_gate_metrics, 'object');
    assert.equal(Number(ext.non_message_ingress_gate_metrics?.non_message_ingress_policy_coverage || 0), 1);
  });
});

await runAsync('CRK-W1-06/dm pairing allowlist does not auto-expand into group allowlist', async () => {
  await withPairingServer({
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_scope',
      HUB_CONNECTOR_DM_PAIRING_ALLOW_FROM: 'u-dm-paired',
    },
  }, async ({ baseUrl }) => {
    const dmAllowed = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_scope`,
      headers: {
        'x-source-key': 'src-scope-dm',
        'x-replay-key': 'evt-dm-allow',
        'x-signature': 'sig-dm-allow',
      },
      body: {
        event_id: 'evt-dm-allow',
        ingress_type: 'message',
        channel_scope: 'dm',
        sender_id: 'u-dm-paired',
      },
    });
    assert.equal(dmAllowed.status, 202);

    const groupDenied = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_scope`,
      headers: {
        'x-source-key': 'src-scope-group',
        'x-replay-key': 'evt-group-deny',
        'x-signature': 'sig-group-deny',
      },
      body: {
        event_id: 'evt-group-deny',
        ingress_type: 'member',
        channel_scope: 'group',
        sender_id: 'u-dm-paired',
      },
    });
    assert.equal(groupDenied.status, 403);
    assert.equal(String(groupDenied.json?.error?.code || ''), 'dm_pairing_scope_violation');
  });
});

await runAsync('CRK-W1-06/admin ingress gate snapshot endpoint returns canonical audit evidence', async () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pairing_gate_snapshot_'));
  const dbPath = path.join(tmpDir, 'hub.db');
  const kekFile = path.join(tmpDir, 'hub_memory_kek.json');
  try {
    await withEnvAsync({
      HUB_MEMORY_KEK_FILE: kekFile,
    }, async () => {
      const db = new HubDB({ dbPath });
      try {
        await withPairingServer({
          db,
          env: {
            HUB_MEMORY_KEK_FILE: kekFile,
            HUB_ADMIN_TOKEN: 'admin-token-snapshot',
            HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_snapshot',
            HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-snapshot-allowed',
          },
        }, async ({ baseUrl }) => {
          const noToken = await requestJson({
            method: 'GET',
            url: `${baseUrl}/admin/pairing/connector-ingress/gate-snapshot?source=audit`,
          });
          assert.equal(noToken.status, 401);
          assert.equal(String(noToken.json?.error?.code || ''), 'unauthenticated');

          const allow = await requestJson({
            method: 'POST',
            url: `${baseUrl}/webhook/connectors/slack/channel_snapshot`,
            headers: {
              'x-source-key': 'src-snapshot-allow',
              'x-replay-key': 'evt-snapshot-allow',
              'x-signature': 'sig-snapshot-allow',
            },
            body: {
              event_id: 'evt-snapshot-allow',
              ingress_type: 'message',
              channel_scope: 'group',
              sender_id: 'u-snapshot-allowed',
            },
          });
          assert.equal(allow.status, 202);

          const deny = await requestJson({
            method: 'POST',
            url: `${baseUrl}/webhook/connectors/slack/channel_snapshot`,
            headers: {
              'x-source-key': 'src-snapshot-deny',
              'x-replay-key': 'evt-snapshot-deny',
              'x-signature': 'sig-snapshot-deny',
            },
            body: {
              event_id: 'evt-snapshot-deny',
              ingress_type: 'reaction',
              channel_scope: 'group',
              sender_id: 'u-snapshot-denied',
            },
          });
          assert.equal(deny.status, 403);
          assert.equal(String(deny.json?.error?.code || ''), 'sender_not_allowlisted');

          const out = await requestJson({
            method: 'GET',
            url: `${baseUrl}/admin/pairing/connector-ingress/gate-snapshot?source=audit&device_id=pairing-http`,
            headers: {
              authorization: 'Bearer admin-token-snapshot',
            },
          });
          assert.equal(out.status, 200);
          assert.equal(!!out.json?.ok, true);
          assert.equal(String(out.json?.source_used || ''), 'audit');
          assert.equal(Number(out.json?.audit_row_count || 0) >= 2, true);
          assert.equal(typeof out.json?.snapshot, 'object');
          assert.equal(typeof out.json?.snapshot_audit, 'object');
          assert.equal(typeof out.json?.snapshot_scan, 'object');

          const snapshot = out.json?.snapshot || {};
          assert.equal(String(snapshot.schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
          assert.equal(typeof snapshot.pass, 'boolean');
          assert.ok(Array.isArray(snapshot.incident_codes), 'expected incident_codes[]');
          assert.equal(typeof snapshot.metrics, 'object');
          assert.equal(typeof snapshot.metrics?.non_message_ingress_policy_coverage, 'number');
          assert.equal(typeof snapshot.metrics?.blocked_event_miss_rate, 'number');
        });
      } finally {
        db.close();
      }
    });
  } finally {
    cleanupDbArtifacts(dbPath);
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

await runAsync('CRK-W1-06/admin ingress gate snapshot supports source=auto|scan and rejects invalid source', async () => {
  await withPairingServer({
    env: {
      HUB_ADMIN_TOKEN: 'admin-token-snapshot-scan',
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:channel_snapshot_scan',
    },
  }, async ({ baseUrl }) => {
    const invalidSource = await requestJson({
      method: 'GET',
      url: `${baseUrl}/admin/pairing/connector-ingress/gate-snapshot?source=broken_mode`,
      headers: {
        authorization: 'Bearer admin-token-snapshot-scan',
      },
    });
    assert.equal(invalidSource.status, 400);
    assert.equal(String(invalidSource.json?.error?.code || ''), 'invalid_request');

    const denied = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_snapshot_scan`,
      headers: {
        'x-source-key': 'src-snapshot-scan',
        'x-replay-key': 'evt-snapshot-scan',
        'x-signature': 'sig-snapshot-scan',
      },
      body: {
        event_id: 'evt-snapshot-scan',
        ingress_type: 'member',
        channel_scope: 'group',
        sender_id: 'u-snapshot-scan-denied',
      },
    });
    assert.equal(denied.status, 403);
    assert.equal(String(denied.json?.error?.code || ''), 'sender_not_allowlisted');

    const scanSource = await requestJson({
      method: 'GET',
      url: `${baseUrl}/admin/pairing/connector-ingress/gate-snapshot?source=scan`,
      headers: {
        authorization: 'Bearer admin-token-snapshot-scan',
      },
    });
    assert.equal(scanSource.status, 200);
    assert.equal(String(scanSource.json?.source_used || ''), 'scan');
    assert.equal(Number(scanSource.json?.audit_row_count || 0), 0);
    assert.equal(Number(scanSource.json?.scan_entry_count || 0) >= 1, true);
    assert.equal(typeof scanSource.json?.snapshot, 'object');

    const autoSource = await requestJson({
      method: 'GET',
      url: `${baseUrl}/admin/pairing/connector-ingress/gate-snapshot?source=auto`,
      headers: {
        authorization: 'Bearer admin-token-snapshot-scan',
      },
    });
    assert.equal(autoSource.status, 200);
    assert.equal(String(autoSource.json?.source_used || ''), 'scan');
    assert.equal(!!autoSource.json?.data_ready, true);
    assert.equal(typeof autoSource.json?.snapshot, 'object');
    const snapshot = autoSource.json?.snapshot || {};
    assert.equal(String(snapshot.schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
    assert.equal(typeof snapshot.metrics?.non_message_ingress_policy_coverage, 'number');
  });
});

await runAsync('CRK-W2-01/admin connector runtime signal endpoints drive state transitions + snapshot', async () => {
  await withPairingServer({
    env: {
      HUB_ADMIN_TOKEN: 'admin-runtime-token',
      HUB_CONNECTOR_RECONNECT_BACKOFF_BASE_MS: '1000',
      HUB_CONNECTOR_RECONNECT_BACKOFF_MAX_MS: '5000',
    },
  }, async ({ baseUrl, db }) => {
    const noToken = await requestJson({
      method: 'GET',
      url: `${baseUrl}/admin/pairing/connector-runtime/snapshot`,
    });
    assert.equal(noToken.status, 401);
    assert.equal(String(noToken.json?.error?.code || ''), 'unauthenticated');

    const sendSignal = async ({ signal, now_ms, error_code = '' }) => requestJson({
      method: 'POST',
      url: `${baseUrl}/admin/pairing/connector-runtime/signal`,
      headers: {
        authorization: 'Bearer admin-runtime-token',
      },
      body: {
        connector: 'slack',
        target_id: 'room_runtime',
        signal,
        now_ms,
        error_code,
      },
    });

    const boot = await sendSignal({ signal: 'boot', now_ms: 1_000 });
    assert.equal(boot.status, 200);
    assert.equal(String(boot.json?.state || ''), 'idle');

    const connecting = await sendSignal({ signal: 'ws_connecting', now_ms: 1_100 });
    assert.equal(connecting.status, 200);
    assert.equal(String(connecting.json?.state || ''), 'connecting');

    const failed = await sendSignal({
      signal: 'ws_failed',
      now_ms: 1_200,
      error_code: 'transport_unavailable',
    });
    assert.equal(failed.status, 200);
    assert.equal(String(failed.json?.state || ''), 'degraded_polling');
    assert.ok(Number(failed.json?.retry_after_ms || 0) > 0);

    const reconnectTick = await sendSignal({ signal: 'reconnect_tick', now_ms: 2_300 });
    assert.equal(reconnectTick.status, 200);
    assert.equal(String(reconnectTick.json?.state || ''), 'recovering');
    assert.equal(String(reconnectTick.json?.action || ''), 'attempt_ws_reconnect');

    const ready = await sendSignal({ signal: 'ws_ready', now_ms: 2_600 });
    assert.equal(ready.status, 200);
    assert.equal(String(ready.json?.state || ''), 'ready');

    const targetState = await requestJson({
      method: 'GET',
      url: `${baseUrl}/admin/pairing/connector-runtime/target?connector=slack&target_id=room_runtime`,
      headers: {
        authorization: 'Bearer admin-runtime-token',
      },
    });
    assert.equal(targetState.status, 200);
    assert.equal(String(targetState.json?.target?.state || ''), 'ready');

    const snapshot = await requestJson({
      method: 'GET',
      url: `${baseUrl}/admin/pairing/connector-runtime/snapshot`,
      headers: {
        authorization: 'Bearer admin-runtime-token',
      },
    });
    assert.equal(snapshot.status, 200);
    assert.equal(!!snapshot.json?.ok, true);
    assert.ok(Number(snapshot.json?.snapshot?.reconnect_attempts || 0) >= 1);
    assert.ok(Number(snapshot.json?.snapshot?.connector_reconnect_ms_p95 || 0) > 0);

    const acceptedAudit = db.rows.find((row) => String(row?.event_type || '') === 'connector.runtime.signal.accepted');
    assert.ok(acceptedAudit, 'expected connector.runtime.signal.accepted audit');
  });
});

await runAsync('CRK-W2-01/webhook ingress fail-closed when runtime orchestrator throws', async () => {
  const failingRuntimeOrchestrator = {
    applySignal() {
      throw new Error('simulated_runtime_orchestrator_failure');
    },
    snapshot() {
      return {
        targets: 0,
        denied: 0,
        state_corrupt_incidents: 0,
        connector_reconnect_ms_p95: 0,
      };
    },
    getTarget() {
      return null;
    },
  };

  await withPairingServer({
    connectorRuntimeOrchestrator: failingRuntimeOrchestrator,
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:runtime_fail_closed_channel',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-runtime-ok',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/runtime_fail_closed_channel`,
      headers: {
        'x-source-key': 'src-runtime-fail-closed',
        'x-replay-key': 'evt-runtime-fail-closed',
        'x-signature': 'sig-runtime-fail-closed',
      },
      body: {
        event_id: 'evt-runtime-fail-closed',
        ingress_type: 'message',
        channel_scope: 'group',
        sender_id: 'u-runtime-ok',
      },
    });
    assert.equal(out.status, 503);
    assert.equal(String(out.json?.error?.code || ''), 'connector_runtime_orchestrator_error');

    const rejected = db.rows.find((row) => String(row?.error_code || '') === 'connector_runtime_orchestrator_error');
    assert.ok(rejected, 'expected connector_runtime_orchestrator_error audit row');
  });
});

await runAsync('CRK-W2-02/out-of-order webhook sequence is rejected with stable deny_code', async () => {
  await withPairingServer({
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:ordering_channel',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-ordering-ok',
    },
  }, async ({ baseUrl, db }) => {
    const first = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/ordering_channel`,
      headers: {
        'x-source-key': 'src-ordering',
        'x-replay-key': 'evt-ordering-10',
        'x-signature': 'sig-ordering-10',
      },
      body: {
        event_id: 'evt-ordering-10',
        ingress_type: 'message',
        channel_scope: 'group',
        sender_id: 'u-ordering-ok',
        sequence: 10,
      },
    });
    assert.equal(first.status, 202);

    const outOfOrder = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/ordering_channel`,
      headers: {
        'x-source-key': 'src-ordering',
        'x-replay-key': 'evt-ordering-9',
        'x-signature': 'sig-ordering-9',
      },
      body: {
        event_id: 'evt-ordering-9',
        ingress_type: 'message',
        channel_scope: 'group',
        sender_id: 'u-ordering-ok',
        sequence: 9,
      },
    });
    assert.equal(outOfOrder.status, 409);
    assert.equal(String(outOfOrder.json?.error?.code || ''), 'out_of_order_event');

    const rejected = db.rows.find((row) => String(row?.error_code || '') === 'out_of_order_event');
    assert.ok(rejected, 'expected out_of_order_event audit row');
    let ext = {};
    try {
      ext = JSON.parse(String(rejected?.ext_json || '{}'));
    } catch {
      ext = {};
    }
    assert.ok(Number(ext.connector_out_of_order_reject_count || 0) > 0, 'out-of-order counter should be > 0');
  });
});

await runAsync('CRK-W2-02/fail-closed when target ordering guard throws', async () => {
  const failingTargetOrderingGuard = {
    begin() {
      throw new Error('simulated_target_ordering_guard_failure');
    },
    complete() {
      return { ok: true };
    },
    snapshot() {
      return {
        targets: 0,
        lock_conflict_count: 0,
        out_of_order_reject_count: 0,
        duplicate_reject_count: 0,
      };
    },
    getTarget() {
      return null;
    },
  };

  await withPairingServer({
    connectorTargetOrderingGuard: failingTargetOrderingGuard,
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:ordering_fail_closed_channel',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-ordering-fail-ok',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/ordering_fail_closed_channel`,
      headers: {
        'x-source-key': 'src-ordering-fail-closed',
        'x-replay-key': 'evt-ordering-fail-closed',
        'x-signature': 'sig-ordering-fail-closed',
      },
      body: {
        event_id: 'evt-ordering-fail-closed',
        ingress_type: 'message',
        channel_scope: 'group',
        sender_id: 'u-ordering-fail-ok',
      },
    });
    assert.equal(out.status, 503);
    assert.equal(String(out.json?.error?.code || ''), 'ordering_guard_error');

    const rejected = db.rows.find((row) => String(row?.error_code || '') === 'ordering_guard_error');
    assert.ok(rejected, 'expected ordering_guard_error audit row');
  });
});

await runAsync('CRK-W2-03/admin connector receipt compensate endpoint drives committed -> undo_pending -> compensated', async () => {
  const receiptCompensator = createConnectorDeliveryReceiptCompensator({
    default_commit_timeout_ms: 60_000,
    max_entries: 256,
  });
  await withPairingServer({
    connectorDeliveryReceiptCompensator: receiptCompensator,
    env: {
      HUB_ADMIN_TOKEN: 'admin-receipt-token',
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:receipt_channel',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-receipt-ok',
    },
  }, async ({ baseUrl }) => {
    const accepted = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/receipt_channel`,
      headers: {
        'x-source-key': 'src-receipt',
        'x-replay-key': 'evt-receipt-1',
        'x-idempotency-key': 'idem-receipt-1',
        'x-signature': 'sig-receipt-1',
      },
      body: {
        event_id: 'evt-receipt-1',
        ingress_type: 'message',
        channel_scope: 'group',
        sender_id: 'u-receipt-ok',
      },
    });
    assert.equal(accepted.status, 202);
    assert.equal(String(accepted.json?.delivery_state || ''), 'committed');

    const undo = receiptCompensator.undo({
      connector: 'slack',
      target_id: 'receipt_channel',
      idempotency_key: 'idem-receipt-1',
      reason: 'test_compensation',
      compensate_after_ms: 0,
      now_ms: 2_000,
    });
    assert.equal(!!undo.ok, true);
    assert.equal(String(undo.delivery_state || ''), 'undo_pending');

    const compensate = await requestJson({
      method: 'POST',
      url: `${baseUrl}/admin/pairing/connector-receipt/compensate`,
      headers: {
        authorization: 'Bearer admin-receipt-token',
      },
      body: {
        now_ms: 2_100,
        max_jobs: 10,
      },
    });
    assert.equal(compensate.status, 200);
    assert.ok(Number(compensate.json?.compensated || 0) >= 1);
    assert.equal(Number(compensate.json?.pending_compensation || 0), 0);

    const snapshot = await requestJson({
      method: 'GET',
      url: `${baseUrl}/admin/pairing/connector-receipt/snapshot`,
      headers: {
        authorization: 'Bearer admin-receipt-token',
      },
    });
    assert.equal(snapshot.status, 200);
    assert.ok(Number(snapshot.json?.snapshot?.entries || 0) >= 1);
    assert.equal(Number(snapshot.json?.snapshot?.compensation_pending_count || 0), 0);
    assert.ok(Number(snapshot.json?.snapshot?.compensated_total || 0) >= 1);

    const item = await requestJson({
      method: 'GET',
      url: `${baseUrl}/admin/pairing/connector-receipt/item?connector=slack&target_id=receipt_channel&idempotency_key=idem-receipt-1`,
      headers: {
        authorization: 'Bearer admin-receipt-token',
      },
    });
    assert.equal(item.status, 200);
    assert.equal(String(item.json?.receipt?.delivery_state || ''), 'compensated');
  });
});

await runAsync('CRK-W2-03/webhook ingress fail-closed when delivery receipt component throws', async () => {
  const failingDeliveryReceiptCompensator = {
    prepare() {
      throw new Error('simulated_delivery_receipt_prepare_failure');
    },
    commit() {
      return { ok: true, delivery_state: 'committed' };
    },
    undo() {
      return { ok: true, delivery_state: 'undo_pending' };
    },
    runCompensation() {
      return { ok: true, processed: 0, compensated: 0, failed: 0, pending_compensation: 0 };
    },
    snapshot() {
      return {
        entries: 0,
        prepare_total: 0,
        commit_total: 0,
        undo_total: 0,
        compensation_pending_count: 0,
      };
    },
    getTarget() {
      return null;
    },
    getReceipt() {
      return null;
    },
  };
  await withPairingServer({
    connectorDeliveryReceiptCompensator: failingDeliveryReceiptCompensator,
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:receipt_fail_channel',
      HUB_CONNECTOR_GROUP_ALLOW_FROM: 'u-receipt-fail-ok',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/receipt_fail_channel`,
      headers: {
        'x-source-key': 'src-receipt-fail',
        'x-replay-key': 'evt-receipt-fail',
        'x-idempotency-key': 'idem-receipt-fail',
        'x-signature': 'sig-receipt-fail',
      },
      body: {
        event_id: 'evt-receipt-fail',
        ingress_type: 'message',
        channel_scope: 'group',
        sender_id: 'u-receipt-fail-ok',
      },
    });
    assert.equal(out.status, 503);
    assert.equal(String(out.json?.error?.code || ''), 'connector_delivery_receipt_error');

    const rejected = db.rows.find((row) => String(row?.error_code || '') === 'connector_delivery_receipt_error');
    assert.ok(rejected, 'expected connector_delivery_receipt_error audit row');
  });
});

await runAsync('CRK-W2-03/admin compensation endpoint fail-closed when worker throws', async () => {
  const failingCompensationWorker = {
    prepare() {
      return { ok: true, delivery_state: 'prepared' };
    },
    commit() {
      return { ok: true, delivery_state: 'committed' };
    },
    undo() {
      return { ok: true, delivery_state: 'undo_pending' };
    },
    runCompensation() {
      throw new Error('simulated_compensation_worker_failure');
    },
    snapshot() {
      return {
        entries: 0,
        prepare_total: 0,
        commit_total: 0,
        undo_total: 0,
        compensation_pending_count: 0,
      };
    },
    getTarget() {
      return null;
    },
    getReceipt() {
      return null;
    },
  };
  await withPairingServer({
    connectorDeliveryReceiptCompensator: failingCompensationWorker,
    env: {
      HUB_ADMIN_TOKEN: 'admin-receipt-fail-token',
    },
  }, async ({ baseUrl, db }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/admin/pairing/connector-receipt/compensate`,
      headers: {
        authorization: 'Bearer admin-receipt-fail-token',
      },
      body: {
        now_ms: 3_000,
        max_jobs: 5,
      },
    });
    assert.equal(out.status, 503);
    assert.equal(String(out.json?.error?.code || ''), 'compensation_worker_error');

    const rejected = db.rows.find((row) => String(row?.event_type || '') === 'connector.receipt.compensation.rejected');
    assert.ok(rejected, 'expected connector.receipt.compensation.rejected audit row');
  });
});

run('CRK-W1-07/replay guard direct claim exposes block-rate metric', () => {
  const guard = createWebhookReplayGuard({
    ttl_ms: 10_000,
    max_keys: 128,
    stale_window_ms: 30_000,
  });
  const first = guard.claim({
    connector: 'slack',
    target_id: 'targetA',
    replay_key: 'evt-1',
    signature: 'sig-1',
    now_ms: 10_000,
  });
  assert.equal(!!first.ok, true);
  const second = guard.claim({
    connector: 'slack',
    target_id: 'targetA',
    replay_key: 'evt-1',
    signature: 'sig-1',
    now_ms: 10_100,
  });
  assert.equal(!!second.ok, false);
  assert.equal(String(second.deny_code || ''), 'replay_detected');
  const snap = guard.snapshot();
  assert.ok(Number(snap.webhook_replay_block_rate || 0) > 0);
});

await runAsync('CM-W3-18/pre-auth state cap rejects rotating source-key flood', async () => {
  const guarded = createPreauthSurfaceGuard({
    window_ms: 60_000,
    max_per_window: 100,
    max_state_keys: 16,
    stale_window_ms: 60_000,
  });
  await withPairingServer({ preauthGuard: guarded }, async ({ baseUrl }) => {
    let overflowSeen = false;
    for (let i = 0; i < 64; i += 1) {
      const out = await requestJson({
        method: 'POST',
        url: `${baseUrl}/webhook/connectors/slack/channel_4`,
        headers: {
          'x-source-key': `source-rotate-${i}`,
          'x-replay-key': `event-${i}`,
          'x-signature': `sig-${i}`,
        },
        body: { event_id: `event-${i}` },
      });
      if (out.status === 429 && String(out.json?.error?.code || '') === 'preauth_state_overflow') {
        overflowSeen = true;
        break;
      }
    }
    assert.equal(overflowSeen, true, 'expected preauth_state_overflow under rotating source-key flood');
  });
});

await runAsync('CRK-W1-07/fail-closed when preauth component throws', async () => {
  const failingPreauthGuard = {
    check() {
      throw new Error('simulated preauth component failure');
    },
    snapshot() {
      return {
        total: 0,
        rejected: 0,
        preauth_reject_rate: 0,
      };
    },
  };
  await withPairingServer({
    preauthGuard: failingPreauthGuard,
  }, async ({ baseUrl }) => {
    const out = await requestJson({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/channel_4`,
      headers: {
        'x-source-key': 'src-preauth-fail-closed',
        'x-replay-key': 'evt-preauth-fail-closed',
        'x-signature': 'sig-preauth-fail-closed',
      },
      body: { hello: 'world' },
    });
    assert.equal(out.status, 503);
    assert.equal(String(out.json?.error?.code || ''), 'preauth_fail_closed');
  });
});

await runAsync('CM-W3-18/ingress audit always includes preauth_reject_rate + webhook_replay_block_rate', async () => {
  await withPairingServer({
    env: {
      HUB_PAIRING_RL_PER_MIN: '3',
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:metrics_channel',
    },
  }, async ({ baseUrl, db }) => {
    for (let i = 0; i < 5; i += 1) {
      const out = await requestJson({
        method: 'POST',
        url: `${baseUrl}/webhook/connectors/slack/metrics_channel`,
        headers: {
          'x-source-key': 'src-metrics',
          'x-replay-key': `evt-metrics-${i}`,
          'x-signature': `sig-metrics-${i}`,
        },
        body: { event_id: `evt-metrics-${i}` },
      });
      if (i < 3) assert.equal(out.status, 202);
      if (i >= 3) assert.equal(out.status, 429);
    }

    const accepted = db.rows.find((row) => String(row?.event_type || '') === 'connector.webhook.received');
    assert.ok(accepted, 'expected connector.webhook.received audit');
    let acceptedExt = {};
    try {
      acceptedExt = JSON.parse(String(accepted.ext_json || '{}'));
    } catch {
      acceptedExt = {};
    }
    assert.equal(typeof acceptedExt.preauth_reject_rate, 'number');
    assert.equal(typeof acceptedExt.webhook_replay_block_rate, 'number');
    assert.equal(String(acceptedExt.non_message_ingress_gate_schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
    assert.equal(typeof acceptedExt.non_message_ingress_gate_pass, 'boolean');
    assert.ok(Array.isArray(acceptedExt.non_message_ingress_gate_incident_codes));
    assert.equal(typeof acceptedExt.non_message_ingress_gate_metrics, 'object');
    assert.equal(typeof acceptedExt.non_message_ingress_gate_metrics?.blocked_event_miss_rate, 'number');

    const rejected = db.rows.find((row) =>
      String(row?.event_type || '') === 'connector.webhook.rejected'
      && String(row?.error_code || '') === 'rate_limited'
    );
    assert.ok(rejected, 'expected connector.webhook.rejected rate_limited audit');
    let rejectedExt = {};
    try {
      rejectedExt = JSON.parse(String(rejected.ext_json || '{}'));
    } catch {
      rejectedExt = {};
    }
    assert.equal(typeof rejectedExt.preauth_reject_rate, 'number');
    assert.equal(typeof rejectedExt.webhook_replay_block_rate, 'number');
    assert.ok(Number(rejectedExt.preauth_reject_rate || 0) > 0, 'preauth_reject_rate should be > 0 after throttling');
  });
});

await runAsync('CRK-W1-07/webhook replay key is accepted again after replay TTL expires', async () => {
  let nowMs = 1_000_000;
  const baseReplayGuard = createWebhookReplayGuard({
    ttl_ms: 1_000,
    max_keys: 256,
    stale_window_ms: 2_000,
  });
  const deterministicReplayGuard = {
    claim(args = {}) {
      return baseReplayGuard.claim({
        ...(args && typeof args === 'object' ? args : {}),
        now_ms: nowMs,
      });
    },
    snapshot() {
      return baseReplayGuard.snapshot();
    },
  };

  await withPairingServer({
    webhookReplayGuard: deterministicReplayGuard,
    env: {
      HUB_CONNECTOR_WEBHOOK_ALLOW_FROM: 'slack:ttl_channel',
    },
  }, async ({ baseUrl, db }) => {
    const makeReq = (eventId) => ({
      method: 'POST',
      url: `${baseUrl}/webhook/connectors/slack/ttl_channel`,
      headers: {
        'x-source-key': 'src-ttl',
        'x-replay-key': 'evt-ttl-replay',
        'x-signature': 'sig-ttl-replay',
      },
      body: {
        event_id: String(eventId || ''),
        ingress_type: 'webhook',
      },
    });

    const first = await requestJson(makeReq('evt-ttl-replay-1'));
    assert.equal(first.status, 202);

    const second = await requestJson(makeReq('evt-ttl-replay-2'));
    assert.equal(second.status, 409);
    assert.equal(String(second.json?.error?.code || ''), 'replay_detected');

    nowMs += 1_251;
    const third = await requestJson(makeReq('evt-ttl-replay-3'));
    assert.equal(third.status, 202);

    const acceptedRows = db.rows.filter((row) => String(row?.event_type || '') === 'connector.webhook.received');
    assert.ok(acceptedRows.length >= 2, `expected replay acceptance after ttl; acceptedRows=${acceptedRows.length}`);
    const replayDenied = db.rows.find((row) =>
      String(row?.event_type || '') === 'connector.webhook.rejected'
      && String(row?.error_code || '') === 'replay_detected'
    );
    assert.ok(replayDenied, 'expected replay_detected rejection before ttl expiry');
  });
});
