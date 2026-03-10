import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

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
    `hub_memory_retention_${label}_${Date.now()}_${Math.random().toString(16).slice(2)}.db`
  );
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x41).toString('base64')}`;

function baseEnv() {
  return {
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'true',
    HUB_MEMORY_RETENTION_AUTO_JOB_ENABLED: 'false',
    HUB_MEMORY_RETENTION_BATCH_LIMIT: '100',
    HUB_MEMORY_RETENTION_TURNS_TTL_MS: '1000',
    HUB_MEMORY_RETENTION_CANONICAL_TTL_MS: '1000',
    HUB_MEMORY_RETENTION_CANONICAL_INCLUDE_PINNED: 'false',
    HUB_MEMORY_RETENTION_TOMBSTONE_TTL_MS: String(60 * 1000),
    HUB_MEMORY_RETENTION_AUDIT_ENABLED: 'true',
  };
}

function createThread(db) {
  return db.getOrCreateThread({
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    thread_key: 'retention-thread',
  });
}

function seedCanonicalItems(db, threadId, now) {
  const oldDelete = db.upsertCanonicalItem({
    scope: 'thread',
    thread_id: threadId,
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    key: 'old.delete',
    value: 'delete me',
    pinned: 0,
  });
  const oldPinned = db.upsertCanonicalItem({
    scope: 'thread',
    thread_id: threadId,
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    key: 'old.pinned',
    value: 'keep me',
    pinned: 1,
  });
  const fresh = db.upsertCanonicalItem({
    scope: 'thread',
    thread_id: threadId,
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    key: 'fresh.keep',
    value: 'fresh',
    pinned: 0,
  });

  db.db.prepare(`UPDATE canonical_memory SET updated_at_ms = ? WHERE item_id = ?`).run(now - 10_000, String(oldDelete.item_id || ''));
  db.db.prepare(`UPDATE canonical_memory SET updated_at_ms = ? WHERE item_id = ?`).run(now - 10_000, String(oldPinned.item_id || ''));
  db.db.prepare(`UPDATE canonical_memory SET updated_at_ms = ? WHERE item_id = ?`).run(now - 100, String(fresh.item_id || ''));
}

run('retention job deletes expired turns/unpinned canonical and writes audit+tombstones', () => {
  const dbPath = makeTmpDbPath('delete');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      const now = Date.now();
      const thread = createThread(db);
      db.appendTurns({
        thread_id: thread.thread_id,
        turns: [
          { role: 'user', content: 'old-turn', is_private: 0, created_at_ms: now - 10_000 },
          { role: 'assistant', content: 'fresh-turn', is_private: 0, created_at_ms: now - 100 },
        ],
      });
      seedCanonicalItems(db, thread.thread_id, now);

      const summary = db.runMemoryRetentionJob({ trigger: 'manual:test', now_ms: now });
      assert.equal(summary.ok, true);
      assert.equal(summary.turns_deleted, 1);
      assert.equal(summary.canonical_deleted, 1);
      assert.equal(summary.tombstones_written, 2);

      const turns = db.listTurns({ thread_id: thread.thread_id, limit: 10 });
      assert.deepEqual(turns.map((t) => t.content), ['fresh-turn']);

      const canonical = db.listCanonicalItems({
        scope: 'thread',
        thread_id: thread.thread_id,
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        limit: 10,
      });
      const keys = canonical.map((it) => String(it.key || '')).sort();
      assert.deepEqual(keys, ['fresh.keep', 'old.pinned']);

      const tombstones = db.listMemoryDeleteTombstones({ limit: 10 });
      assert.equal(tombstones.length, 2);

      const runs = db.listMemoryRetentionRuns({ limit: 5 });
      assert.ok(runs.length >= 1);
      assert.equal(String(runs[0].run_id || ''), String(summary.run_id || ''));

      const auditRows = db.listAuditEvents({ device_id: 'hub' });
      assert.ok(auditRows.some((r) => String(r.event_type || '') === 'memory.retention.completed'));
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('dry-run keeps rows unchanged and reports candidates', () => {
  const dbPath = makeTmpDbPath('dryrun');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      const now = Date.now();
      const thread = createThread(db);
      db.appendTurns({
        thread_id: thread.thread_id,
        turns: [{ role: 'user', content: 'old-turn', is_private: 0, created_at_ms: now - 10_000 }],
      });
      seedCanonicalItems(db, thread.thread_id, now);

      const summary = db.runMemoryRetentionJob({ trigger: 'manual:dryrun', now_ms: now, dry_run: true });
      assert.equal(summary.ok, true);
      assert.equal(summary.dry_run, true);
      assert.ok(summary.turns_candidates >= 1);
      assert.ok(summary.canonical_candidates >= 1);
      assert.equal(summary.turns_deleted, 0);
      assert.equal(summary.canonical_deleted, 0);

      const turns = db.listTurns({ thread_id: thread.thread_id, limit: 10 });
      assert.equal(turns.length, 1);
      assert.equal(turns[0].content, 'old-turn');
      const canonical = db.listCanonicalItems({
        scope: 'thread',
        thread_id: thread.thread_id,
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        limit: 10,
      });
      assert.equal(canonical.length, 3);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('restore from tombstone recovers deleted records', () => {
  const dbPath = makeTmpDbPath('restore');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      const now = Date.now();
      const thread = createThread(db);
      db.appendTurns({
        thread_id: thread.thread_id,
        turns: [{ role: 'user', content: 'old-turn', is_private: 0, created_at_ms: now - 10_000 }],
      });
      seedCanonicalItems(db, thread.thread_id, now);

      const summary = db.runMemoryRetentionJob({ trigger: 'manual:restore_seed', now_ms: now });
      assert.equal(summary.turns_deleted, 1);
      assert.equal(summary.canonical_deleted, 1);

      const tombstones = db.listMemoryDeleteTombstones({ limit: 10, include_payload: true });
      const turnTs = tombstones.find((t) => String(t.table_name || '') === 'turns');
      const canonTs = tombstones.find((t) => String(t.table_name || '') === 'canonical_memory');
      assert.ok(turnTs);
      assert.ok(canonTs);

      const r1 = db.restoreMemoryDeleteTombstone({ tombstone_id: String(turnTs.tombstone_id || '') });
      const r2 = db.restoreMemoryDeleteTombstone({ tombstone_id: String(canonTs.tombstone_id || '') });
      assert.equal(r1.ok, true);
      assert.equal(r2.ok, true);

      const turns = db.listTurns({ thread_id: thread.thread_id, limit: 10 });
      assert.equal(turns.length, 1);
      assert.equal(turns[0].content, 'old-turn');

      const canonical = db.listCanonicalItems({
        scope: 'thread',
        thread_id: thread.thread_id,
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        limit: 10,
      });
      assert.equal(canonical.length, 3);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});
