import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { parseEncryptedEnvelopeMeta } from './at_rest_crypto.js';
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

function withEnv(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv)) {
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

function makeTmpDbPath(label) {
  return path.join(
    os.tmpdir(),
    `hub_memory_at_rest_${label}_${Date.now()}_${Math.random().toString(16).slice(2)}.db`
  );
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x11).toString('base64')}`;
const KEK_V2 = `base64:${Buffer.alloc(32, 0x22).toString('base64')}`;

function baseEnv(activeVersion = 'kek_v1', includeV1 = true, includeV2 = true) {
  const ring = {};
  if (includeV1) ring.kek_v1 = KEK_V1;
  if (includeV2) ring.kek_v2 = KEK_V2;
  return {
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: activeVersion,
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify(ring),
    HUB_MEMORY_KEK_FILE: '',
  };
}

function createThreadForTest(db) {
  return db.getOrCreateThread({
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    thread_key: 'thread-key',
  });
}

run('turns/canonical are encrypted at rest and decrypted on read', () => {
  const dbPath = makeTmpDbPath('roundtrip');
  withEnv(baseEnv('kek_v1'), () => {
    const db = new HubDB({ dbPath });
    try {
      const thread = createThreadForTest(db);
      db.appendTurns({
        thread_id: thread.thread_id,
        request_id: 'req-1',
        turns: [{ role: 'user', content: 'water price is 2.5', is_private: 0 }],
      });
      const rawTurn = db.db.prepare(`SELECT * FROM turns LIMIT 1`).get();
      assert.ok(rawTurn);
      assert.notEqual(String(rawTurn.content || ''), 'water price is 2.5');
      assert.ok(parseEncryptedEnvelopeMeta(String(rawTurn.content || '')));

      const turns = db.listTurns({ thread_id: thread.thread_id, limit: 10 });
      assert.equal(turns.length, 1);
      assert.equal(turns[0].content, 'water price is 2.5');

      db.upsertCanonicalItem({
        scope: 'thread',
        thread_id: thread.thread_id,
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'water.latest.price',
        value: '2.5 CNY',
        pinned: 1,
      });
      const rawCanon = db.db.prepare(`SELECT * FROM canonical_memory LIMIT 1`).get();
      assert.ok(rawCanon);
      assert.notEqual(String(rawCanon.value || ''), '2.5 CNY');
      assert.ok(parseEncryptedEnvelopeMeta(String(rawCanon.value || '')));

      const canon = db.getCanonicalItem({
        scope: 'thread',
        thread_id: thread.thread_id,
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'water.latest.price',
      });
      assert.ok(canon);
      assert.equal(canon.value, '2.5 CNY');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('DEK rotation keeps old rows readable and new rows use new DEK', () => {
  const dbPath = makeTmpDbPath('dek_rotate');
  withEnv(baseEnv('kek_v1'), () => {
    const db = new HubDB({ dbPath });
    try {
      const thread = createThreadForTest(db);
      db.appendTurns({
        thread_id: thread.thread_id,
        turns: [{ role: 'user', content: 'first', is_private: 0 }],
      });
      const firstRaw = db.db.prepare(`SELECT content FROM turns ORDER BY created_at_ms ASC LIMIT 1`).get();
      const firstMeta = parseEncryptedEnvelopeMeta(String(firstRaw?.content || ''));
      assert.ok(firstMeta?.dek_id);

      const rotated = db.rotateMemoryDek();
      assert.equal(rotated.ok, true);
      assert.notEqual(rotated.dek_id, firstMeta.dek_id);

      db.appendTurns({
        thread_id: thread.thread_id,
        turns: [{ role: 'assistant', content: 'second', is_private: 0 }],
      });

      const rawRows = db.db.prepare(`SELECT content FROM turns ORDER BY created_at_ms ASC`).all();
      const ids = rawRows.map((r) => parseEncryptedEnvelopeMeta(String(r.content || ''))?.dek_id || '');
      assert.equal(ids.length, 2);
      assert.notEqual(ids[0], ids[1]);
      assert.equal(ids[1], rotated.dek_id);

      const turns = db.listTurns({ thread_id: thread.thread_id, limit: 10 }).reverse();
      assert.deepEqual(turns.map((t) => t.content), ['first', 'second']);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('KEK rewrap supports rotation and old KEK retirement', () => {
  const dbPath = makeTmpDbPath('kek_rewrap');
  withEnv(baseEnv('kek_v1'), () => {
    const db = new HubDB({ dbPath });
    try {
      const thread = createThreadForTest(db);
      db.appendTurns({
        thread_id: thread.thread_id,
        turns: [{ role: 'user', content: 'rotate me', is_private: 0 }],
      });
      const row = db.db.prepare(`SELECT kek_version FROM memory_encryption_keys WHERE status='active' LIMIT 1`).get();
      assert.equal(String(row?.kek_version || ''), 'kek_v1');
    } finally {
      db.close();
    }
  });

  withEnv(baseEnv('kek_v2'), () => {
    const db = new HubDB({ dbPath });
    try {
      const before = db.db.prepare(`SELECT COUNT(*) AS n FROM memory_encryption_keys WHERE kek_version='kek_v1'`).get();
      assert.ok(Number(before?.n || 0) >= 1);
      const rewrap = db.rewrapMemoryDeksToActiveKek();
      assert.equal(rewrap.ok, true);
      assert.ok(Number(rewrap.rewrapped || 0) >= 1);
      const after = db.db.prepare(`SELECT COUNT(*) AS n FROM memory_encryption_keys WHERE kek_version='kek_v1'`).get();
      assert.equal(Number(after?.n || 0), 0);
    } finally {
      db.close();
    }
  });

  withEnv(baseEnv('kek_v2', false, true), () => {
    const db = new HubDB({ dbPath });
    try {
      const thread = createThreadForTest(db);
      const turns = db.listTurns({ thread_id: thread.thread_id, limit: 10 });
      assert.equal(turns.length, 1);
      assert.equal(turns[0].content, 'rotate me');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('tampered encrypted payload fails closed', () => {
  const dbPath = makeTmpDbPath('tamper');
  withEnv(baseEnv('kek_v1'), () => {
    const db = new HubDB({ dbPath });
    try {
      const thread = createThreadForTest(db);
      db.appendTurns({
        thread_id: thread.thread_id,
        turns: [{ role: 'user', content: 'tamper target', is_private: 0 }],
      });
      const raw = db.db.prepare(`SELECT turn_id, content FROM turns LIMIT 1`).get();
      assert.ok(raw);
      const oldContent = String(raw.content || '');
      const prefix = 'xhubenc:v1:';
      const payload = oldContent.startsWith(prefix) ? oldContent.slice(prefix.length) : '';
      const decoded = JSON.parse(Buffer.from(payload, 'base64').toString('utf8'));
      decoded.ct_b64 = `A${String(decoded.ct_b64 || '').slice(1)}`;
      const tampered = `${prefix}${Buffer.from(JSON.stringify(decoded), 'utf8').toString('base64')}`;
      db.db.prepare(`UPDATE turns SET content = ? WHERE turn_id = ?`).run(tampered, String(raw.turn_id || ''));
      assert.throws(() => {
        db.listTurns({ thread_id: thread.thread_id, limit: 10 });
      });
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});
