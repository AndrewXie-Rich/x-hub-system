import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import {
  createPreauthSurfaceGuard,
  createUnauthorizedFloodBreaker,
  createWebhookReplayGuard,
} from './pairing_http.js';
import { createConnectorTargetOrderingGuard } from './connector_target_ordering_guard.js';
import { createConnectorDeliveryReceiptCompensator } from './connector_delivery_receipt_compensator.js';

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

function withEnv(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
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

function makeTmp(prefix, suffix = '') {
  return path.join(
    os.tmpdir(),
    `${prefix}_${Date.now()}_${Math.random().toString(16).slice(2)}${suffix}`
  );
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x31).toString('base64')}`;

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_AUDIT_LEVEL: 'full_content',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'true',
    HUB_MEMORY_RETENTION_AUTO_JOB_ENABLED: 'false',
    HUB_MEMORY_RETENTION_BATCH_LIMIT: '100',
    HUB_MEMORY_RETENTION_TURNS_TTL_MS: '86400000',
    HUB_MEMORY_RETENTION_CANONICAL_TTL_MS: '86400000',
    HUB_MEMORY_RETENTION_CANONICAL_INCLUDE_PINNED: 'false',
    HUB_MEMORY_RETENTION_TOMBSTONE_TTL_MS: String(60 * 1000),
    HUB_MEMORY_RETENTION_AUDIT_ENABLED: 'true',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '200',
  };
}

function seedPaidGrant(db, {
  device_id = 'dev1',
  user_id = 'user1',
  app_id = 'app1',
  project_id = 'proj1',
  model_id = 'openai/gpt-4.1',
  expires_at_ms = Date.now() + (10 * 60 * 1000),
} = {}) {
  return db.createGrant({
    grant_request_id: '',
    device_id,
    user_id,
    app_id,
    project_id,
    capability: 'ai.generate.paid',
    model_id,
    token_cap: 1000000,
    expires_at_ms,
  });
}

function makeGenerateCall({ request_id, model_id, message, project_id = 'proj1' }) {
  return {
    request: {
      request_id,
      model_id,
      messages: [{ role: 'user', content: message }],
      client: {
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id,
      },
    },
    metadata: {
      get() {
        return [];
      },
    },
    write() {
      // Stream content is not needed for invariant assertions.
    },
    end() {
      // Stream end callback is not needed for invariant assertions.
    },
    on() {
      // Event handlers are not needed in this test harness.
    },
  };
}

function listAuditByRequestId(db, request_id) {
  const rows = db.listAuditEvents({ device_id: 'dev1' }) || [];
  return rows.filter((r) => String(r.request_id || '') === String(request_id || ''));
}

await runAsync('KQ-W1-03/CP-Grant-001 denies paid generate without active grant', async () => {
  const runtimeBaseDir = makeTmp('kq_cp_grant_runtime');
  const dbPath = makeTmp('kq_cp_grant_db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const request_id = `rid_cp_grant_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      await impl.HubAI.Generate(
        makeGenerateCall({
          request_id,
          model_id: 'openai/gpt-4.1',
          message: 'hello, paid generate without grant should fail',
        })
      );

      const rows = listAuditByRequestId(db, request_id);
      const denied = rows.find((r) => String(r.event_type || '') === 'ai.generate.denied');
      assert.ok(denied, 'expected ai.generate.denied audit event');
      assert.equal(String(denied.error_code || ''), 'legacy_grant_flow_required');

      const deniedExt = JSON.parse(String(denied.ext_json || '{}'));
      assert.equal(deniedExt.metrics?.security?.blocked, true);
      assert.equal(String(deniedExt.metrics?.security?.deny_code || ''), 'legacy_grant_flow_required');

      const policyRows = rows.filter((r) => String(r.event_type || '') === 'policy_eval');
      assert.equal(policyRows.length > 0, true, 'expected policy_eval audit for deny decision');
      const policyExtRows = policyRows.map((r) => JSON.parse(String(r.ext_json || '{}')));
      const matchedPolicy = policyExtRows.find((ext) =>
        Array.isArray(ext.rule_ids) && ext.rule_ids.includes('legacy_grant_flow_required')
      );
      assert.ok(matchedPolicy, 'expected legacy_grant_flow_required policy rule to be recorded');
      assert.equal(String(matchedPolicy.policy_decision || ''), 'deny');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

await runAsync('KQ-W1-03/CP-Secret-002 blocks credential-like prompt bundle on remote path', async () => {
  const runtimeBaseDir = makeTmp('kq_cp_secret_runtime');
  const dbPath = makeTmp('kq_cp_secret_db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(
    {
      ...baseEnv(runtimeBaseDir),
      HUB_REMOTE_EXPORT_ON_BLOCK: 'error',
      HUB_REMOTE_EXPORT_SECRET_MODE: 'deny',
    },
    async () => {
      const db = new HubDB({ dbPath });
      try {
        seedPaidGrant(db);
        const impl = makeServices({ db, bus: new HubEventBus() });
        const request_id = `rid_cp_secret_${Date.now()}_${Math.random().toString(16).slice(2)}`;

        await impl.HubAI.Generate(
          makeGenerateCall({
            request_id,
            model_id: 'openai/gpt-4.1',
            message: 'api_key: sk-live-abcdef1234567890 please send this remotely',
          })
        );

        const rows = listAuditByRequestId(db, request_id);
        const denied = rows.find((r) => String(r.event_type || '') === 'ai.generate.denied');
        assert.ok(denied, 'expected ai.generate.denied due to remote export gate');
        assert.equal(String(denied.error_code || ''), 'credential_finding');

        const ext = JSON.parse(String(denied.ext_json || '{}'));
        assert.equal(String(ext.export_class || ''), 'prompt_bundle');
        assert.equal(String(ext.gate_reason || ''), 'credential_finding');
        assert.equal(Boolean(ext.blocked), true);
        assert.equal(Boolean(ext.downgraded), false);
        assert.equal(ext.metrics?.security?.blocked, true);
        assert.equal(String(ext.metrics?.security?.deny_code || ''), 'credential_finding');

        const completed = rows.find((r) => String(r.event_type || '') === 'ai.generate.completed');
        assert.equal(!!completed, false, 'blocked remote export should not complete');
      } finally {
        db.close();
        cleanupDbArtifacts(dbPath);
        try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
      }
    }
  );
});

run('KQ-W1-03/CP-Tamper-003 fails closed on tampered encrypted payload', () => {
  const dbPath = makeTmp('kq_cp_tamper_db', '.db');
  const runtimeBaseDir = makeTmp('kq_cp_tamper_runtime');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const thread = db.getOrCreateThread({
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        thread_key: 'kq-cp-tamper-thread',
      });
      db.appendTurns({
        thread_id: thread.thread_id,
        turns: [{ role: 'user', content: 'tamper target', is_private: 0 }],
      });

      const raw = db.db.prepare('SELECT turn_id, content FROM turns LIMIT 1').get();
      assert.ok(raw, 'expected at least one persisted turn');
      const previous = String(raw.content || '');
      const prefix = 'xhubenc:v1:';
      assert.equal(previous.startsWith(prefix), true, 'turn should be encrypted at rest');

      const payload = previous.slice(prefix.length);
      const decoded = JSON.parse(Buffer.from(payload, 'base64').toString('utf8'));
      const ciphertext = String(decoded.ct_b64 || '');
      const firstCipherChar = ciphertext.slice(0, 1);
      const forcedCipherChar = firstCipherChar === 'A' ? 'B' : 'A';
      decoded.ct_b64 = `${forcedCipherChar}${ciphertext.slice(1)}`;
      const tampered = `${prefix}${Buffer.from(JSON.stringify(decoded), 'utf8').toString('base64')}`;

      db.db.prepare('UPDATE turns SET content = ? WHERE turn_id = ?').run(tampered, String(raw.turn_id || ''));
      assert.throws(() => {
        db.listTurns({ thread_id: thread.thread_id, limit: 10 });
      });
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

await runAsync('KQ-W1-03/CP-Tamper-003 replay guard rejects expired paid grant', async () => {
  const runtimeBaseDir = makeTmp('kq_cp_replay_runtime');
  const dbPath = makeTmp('kq_cp_replay_db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const grant = seedPaidGrant(db, { expires_at_ms: Date.now() + 5_000 });
      assert.ok(grant && grant.grant_id, 'expected seeded paid grant');
      db.db.prepare('UPDATE grants SET expires_at_ms = ? WHERE grant_id = ?').run(Date.now() - 1_000, String(grant.grant_id || ''));

      const impl = makeServices({ db, bus: new HubEventBus() });
      const request_id = `rid_cp_replay_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      await impl.HubAI.Generate(
        makeGenerateCall({
          request_id,
          model_id: 'openai/gpt-4.1',
          message: 'replay expired grant should be denied',
        })
      );

      const rows = listAuditByRequestId(db, request_id);
      const denied = rows.find((r) => String(r.event_type || '') === 'ai.generate.denied');
      assert.ok(denied, 'expected deny event for expired grant replay');
      assert.equal(String(denied.error_code || ''), 'legacy_grant_flow_required');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run('CM-W3-18/preauth guard keeps rotating source keys bounded', () => {
  const guard = createPreauthSurfaceGuard({
    window_ms: 60_000,
    max_per_window: 20,
    max_state_keys: 32,
    stale_window_ms: 120_000,
  });
  let now = 10_000;
  for (let i = 0; i < 320; i += 1) {
    const out = guard.check({ source_key: `rotating_${i}`, now_ms: now });
    assert.ok(out && typeof out === 'object');
    now += 2;
  }
  const snap = guard.snapshot();
  assert.ok(Number(snap.state_keys || 0) <= 32, `state_keys=${snap.state_keys}`);
  assert.ok(Number(snap.preauth_reject_rate || 0) > 0, `preauth_reject_rate=${snap.preauth_reject_rate}`);
});

run('CRK-W1-08/unauthorized flood breaker penalizes repeated unauthorized connection', () => {
  const breaker = createUnauthorizedFloodBreaker({
    window_ms: 10_000,
    max_unauthorized_per_window: 2,
    penalty_ms: 5_000,
    max_state_keys: 64,
    stale_window_ms: 30_000,
    audit_sample_every: 1,
  });
  const key = '127.0.0.1:50000->50052';

  const firstCheck = breaker.check({ connection_key: key, now_ms: 1_000 });
  assert.equal(!!firstCheck.ok, true);
  breaker.recordUnauthorized({ connection_key: key, deny_code: 'sender_not_allowlisted', now_ms: 1_010 });

  const secondCheck = breaker.check({ connection_key: key, now_ms: 1_100 });
  assert.equal(!!secondCheck.ok, true);
  breaker.recordUnauthorized({ connection_key: key, deny_code: 'sender_not_allowlisted', now_ms: 1_110 });

  const dropped = breaker.check({ connection_key: key, now_ms: 1_200 });
  assert.equal(!!dropped.ok, false);
  assert.equal(String(dropped.deny_code || ''), 'unauthorized_flood_dropped');
  assert.ok(Number(dropped.retry_after_ms || 0) > 0);

  const otherConnection = breaker.check({ connection_key: '127.0.0.1:50001->50052', now_ms: 1_200 });
  assert.equal(!!otherConnection.ok, true);

  const snap = breaker.snapshot();
  assert.ok(Number(snap.unauthorized_flood_drop_count || 0) > 0);
});

run('CRK-W2-02/ordering guard blocks target lock conflict and out-of-order event', () => {
  const guard = createConnectorTargetOrderingGuard({
    lock_ttl_ms: 5_000,
    seen_ttl_ms: 30_000,
    max_targets: 64,
  });
  const target = {
    connector: 'slack',
    target_id: 'channel_ordering',
  };

  const first = guard.begin({
    ...target,
    event_id: 'event-1',
    event_sequence: 10,
    now_ms: 2_000,
  });
  assert.equal(!!first.ok, true);

  const conflict = guard.begin({
    ...target,
    event_id: 'event-2',
    event_sequence: 11,
    now_ms: 2_050,
  });
  assert.equal(!!conflict.ok, false);
  assert.equal(String(conflict.deny_code || ''), 'target_locked');

  const firstDone = guard.complete({
    ...target,
    lock_token: first.lock_token,
    success: true,
    event_id: 'event-1',
    event_sequence: 10,
    now_ms: 2_080,
  });
  assert.equal(!!firstDone.ok, true);

  const outOfOrder = guard.begin({
    ...target,
    event_id: 'event-3',
    event_sequence: 9,
    now_ms: 2_120,
  });
  assert.equal(!!outOfOrder.ok, false);
  assert.equal(String(outOfOrder.deny_code || ''), 'out_of_order_event');
});

run('CRK-W2-03/delivery receipt compensator enforces prepare-commit-undo-compensate invariants', () => {
  const compensator = createConnectorDeliveryReceiptCompensator({
    default_commit_timeout_ms: 10_000,
    max_entries: 256,
  });
  const base = {
    connector: 'slack',
    target_id: 'channel_receipt',
    idempotency_key: 'idem-kq-1',
    event_id: 'event-kq-1',
    event_sequence: 7,
  };

  const prepared = compensator.prepare({
    ...base,
    now_ms: 2_000,
  });
  assert.equal(!!prepared.ok, true);
  assert.equal(String(prepared.delivery_state || ''), 'prepared');

  const committed = compensator.commit({
    ...base,
    provider_receipt: 'provider:kq-ack',
    now_ms: 2_010,
  });
  assert.equal(!!committed.ok, true);
  assert.equal(String(committed.delivery_state || ''), 'committed');

  const undo = compensator.undo({
    ...base,
    reason: 'runtime_error',
    compensate_after_ms: 0,
    now_ms: 2_020,
  });
  assert.equal(!!undo.ok, true);
  assert.equal(String(undo.delivery_state || ''), 'undo_pending');

  const compensated = compensator.runCompensation({
    now_ms: 2_021,
    max_jobs: 5,
  });
  assert.equal(!!compensated.ok, true);
  assert.equal(Number(compensated.compensated || 0), 1);

  const duplicatePrepare = compensator.prepare({
    ...base,
    now_ms: 2_030,
  });
  assert.equal(!!duplicatePrepare.ok, false);
  assert.equal(String(duplicatePrepare.deny_code || ''), 'terminal_not_allowed');
});

run('CRK-W1-07/webhook replay guard rejects duplicate signed event', () => {
  const guard = createWebhookReplayGuard({
    ttl_ms: 10_000,
    max_keys: 128,
    stale_window_ms: 30_000,
  });
  const first = guard.claim({
    connector: 'slack',
    target_id: 'channel_1',
    replay_key: 'event-1',
    signature: 'sig-v1',
    now_ms: 20_000,
  });
  assert.equal(!!first.ok, true);
  const second = guard.claim({
    connector: 'slack',
    target_id: 'channel_1',
    replay_key: 'event-1',
    signature: 'sig-v1',
    now_ms: 20_001,
  });
  assert.equal(!!second.ok, false);
  assert.equal(String(second.deny_code || ''), 'replay_detected');
  const snap = guard.snapshot();
  assert.ok(Number(snap.webhook_replay_block_rate || 0) > 0);
});

await runAsync('CRK-W1-07/replay guard keeps dedupe state across HubDB reopen', async () => {
  const runtimeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'kq_replay_guard_persist_'));
  const dbPath = path.join(runtimeDir, 'hub.db');
  try {
    await withEnvAsync({ HUB_MEMORY_AT_REST_ENABLED: 'false' }, async () => {
      const db1 = new HubDB({ dbPath });
      try {
        const guard1 = createWebhookReplayGuard({
          db: db1,
          ttl_ms: 30_000,
          max_keys: 128,
          stale_window_ms: 90_000,
        });
        const first = guard1.claim({
          connector: 'slack',
          target_id: 'channel_persist',
          replay_key: 'event-persist-1',
          signature: 'sig-persist',
          now_ms: 10_000,
        });
        assert.equal(!!first.ok, true);
      } finally {
        db1.close();
      }

      const db2 = new HubDB({ dbPath });
      try {
        const guard2 = createWebhookReplayGuard({
          db: db2,
          ttl_ms: 30_000,
          max_keys: 128,
          stale_window_ms: 90_000,
        });
        const replayed = guard2.claim({
          connector: 'slack',
          target_id: 'channel_persist',
          replay_key: 'event-persist-1',
          signature: 'sig-persist',
          now_ms: 10_001,
        });
        assert.equal(!!replayed.ok, false);
        assert.equal(String(replayed.deny_code || ''), 'replay_detected');

        const fresh = guard2.claim({
          connector: 'slack',
          target_id: 'channel_persist',
          replay_key: 'event-persist-2',
          signature: 'sig-persist',
          now_ms: 10_002,
        });
        assert.equal(!!fresh.ok, true);
      } finally {
        db2.close();
      }
    });
  } finally {
    cleanupDbArtifacts(dbPath);
    try { fs.rmSync(runtimeDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

run('CRK-W1-07/replay guard does not false-block when signature is same but replay key differs', () => {
  const guard = createWebhookReplayGuard({
    ttl_ms: 10_000,
    max_keys: 128,
    stale_window_ms: 30_000,
  });
  const first = guard.claim({
    connector: 'slack',
    target_id: 'channel_1',
    replay_key: 'event-a',
    signature: 'sig-same',
    now_ms: 30_000,
  });
  assert.equal(!!first.ok, true);

  const second = guard.claim({
    connector: 'slack',
    target_id: 'channel_1',
    replay_key: 'event-b',
    signature: 'sig-same',
    now_ms: 30_100,
  });
  assert.equal(!!second.ok, true);
});

run('CRK-W1-07/preauth + replay + ordering + receipt guards fail closed on internal clock error', () => {
  const failingClock = () => {
    throw new Error('simulated_clock_failure');
  };
  const preauth = createPreauthSurfaceGuard({
    nowFn: failingClock,
    window_ms: 1_000,
    max_per_window: 3,
    max_state_keys: 10,
    stale_window_ms: 5_000,
  });
  const preauthOut = preauth.check({ source_key: 's1' });
  assert.equal(!!preauthOut.ok, false);
  assert.equal(String(preauthOut.deny_code || ''), 'preauth_fail_closed');
  assert.ok(Number(preauth.snapshot().preauth_reject_rate || 0) >= 1);

  const replay = createWebhookReplayGuard({
    nowFn: failingClock,
    ttl_ms: 3_000,
    max_keys: 32,
    stale_window_ms: 10_000,
  });
  const replayOut = replay.claim({
    connector: 'slack',
    target_id: 'channel_2',
    replay_key: 'event-2',
    signature: 'sig-v2',
  });
  assert.equal(!!replayOut.ok, false);
  assert.equal(String(replayOut.deny_code || ''), 'replay_guard_error');

  const floodBreaker = createUnauthorizedFloodBreaker({
    nowFn: failingClock,
    window_ms: 10_000,
    max_unauthorized_per_window: 2,
    penalty_ms: 3_000,
  });
  const floodOut = floodBreaker.check({ connection_key: 'conn-fail' });
  assert.equal(!!floodOut.ok, false);
  assert.equal(String(floodOut.deny_code || ''), 'unauthorized_flood_fail_closed');

  const ordering = createConnectorTargetOrderingGuard({
    nowFn: failingClock,
  });
  const orderingOut = ordering.begin({
    connector: 'slack',
    target_id: 'channel-order-fail',
    event_id: 'event-order-fail',
    event_sequence: 1,
  });
  assert.equal(!!orderingOut.ok, false);
  assert.equal(String(orderingOut.deny_code || ''), 'ordering_guard_error');

  const receipt = createConnectorDeliveryReceiptCompensator({
    nowFn: failingClock,
  });
  const receiptPrepare = receipt.prepare({
    connector: 'slack',
    target_id: 'channel-receipt-fail',
    idempotency_key: 'idem-receipt-fail',
  });
  assert.equal(!!receiptPrepare.ok, false);
  assert.equal(String(receiptPrepare.deny_code || ''), 'receipt_guard_error');

  const receiptCompensate = receipt.runCompensation({
    max_jobs: 5,
  });
  assert.equal(!!receiptCompensate.ok, false);
  assert.equal(String(receiptCompensate.deny_code || ''), 'compensation_worker_error');
});

run('CM-W3-18/preauth guard emits preauth_state_overflow when source-key table is full', () => {
  const preauth = createPreauthSurfaceGuard({
    window_ms: 60_000,
    max_per_window: 10,
    max_state_keys: 16,
    stale_window_ms: 120_000,
  });
  const accepted = [];
  for (let i = 0; i < 16; i += 1) {
    const out = preauth.check({
      source_key: `key-${i}`,
      now_ms: 100 + i,
    });
    accepted.push(out);
  }
  assert.equal(accepted.every((x) => x.ok), true);
  const overflow = preauth.check({
    source_key: 'key-overflow',
    now_ms: 200,
  });
  assert.equal(!!overflow.ok, false);
  assert.equal(String(overflow.deny_code || ''), 'preauth_state_overflow');
});

run('CRK-W1-07/replay guard allows same replay key again after ttl expiry window', () => {
  const replay = createWebhookReplayGuard({
    ttl_ms: 1_000,
    max_keys: 32,
    stale_window_ms: 3_000,
  });
  const first = replay.claim({
    connector: 'slack',
    target_id: 'channel-ttl',
    replay_key: 'event-ttl',
    signature: 'sig-ttl',
    now_ms: 10_000,
  });
  assert.equal(!!first.ok, true);

  const blocked = replay.claim({
    connector: 'slack',
    target_id: 'channel-ttl',
    replay_key: 'event-ttl',
    signature: 'sig-ttl',
    now_ms: 10_050,
  });
  assert.equal(!!blocked.ok, false);
  assert.equal(String(blocked.deny_code || ''), 'replay_detected');

  const acceptedAfterTtl = replay.claim({
    connector: 'slack',
    target_id: 'channel-ttl',
    replay_key: 'event-ttl',
    signature: 'sig-ttl',
    now_ms: 11_200,
  });
  assert.equal(!!acceptedAfterTtl.ok, true);
});
