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
    `hub_memory_index_changelog_${label}_${Date.now()}_${Math.random().toString(16).slice(2)}.db`
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
    thread_key: 'index-changelog-thread',
  });
}

run('W3-01/index changelog records insert/update in order and supports incremental cursor', () => {
  const dbPath = makeTmpDbPath('insert_update');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      const thread = createThread(db);
      const now = Date.now();

      db.appendTurns({
        thread_id: thread.thread_id,
        request_id: 'req-1',
        turns: [
          { role: 'user', content: 'buy water now', is_private: 0, created_at_ms: now - 2 },
          { role: 'assistant', content: 'price is 3 dollars', is_private: 0, created_at_ms: now - 1 },
        ],
      });

      db.upsertCanonicalItem({
        scope: 'thread',
        thread_id: thread.thread_id,
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'water.price',
        value: '3',
        pinned: 0,
      });

      db.upsertCanonicalItem({
        scope: 'thread',
        thread_id: thread.thread_id,
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'water.price',
        value: '4',
        pinned: 1,
      });

      const rows = db.listMemoryIndexChangelog({ since_seq: 0, limit: 50 });
      assert.equal(rows.length, 4);
      for (let i = 1; i < rows.length; i += 1) {
        assert.ok(Number(rows[i].seq || 0) > Number(rows[i - 1].seq || 0));
      }

      const turnEvents = rows.filter((r) => String(r.table_name || '') === 'turns');
      assert.equal(turnEvents.length, 2);
      assert.ok(turnEvents.every((r) => String(r.event_type || '') === 'insert'));
      const turnPayload = JSON.parse(String(turnEvents[0].payload_json || '{}'));
      assert.equal(Object.prototype.hasOwnProperty.call(turnPayload, 'content'), false);
      assert.ok(Number(turnPayload.content_bytes || 0) > 0);

      const canonicalEvents = rows.filter((r) => String(r.table_name || '') === 'canonical_memory');
      assert.equal(canonicalEvents.length, 2);
      assert.equal(String(canonicalEvents[0].event_type || ''), 'insert');
      assert.equal(String(canonicalEvents[1].event_type || ''), 'update');
      const canonicalPayload = JSON.parse(String(canonicalEvents[1].payload_json || '{}'));
      assert.equal(Object.prototype.hasOwnProperty.call(canonicalPayload, 'value'), false);
      assert.ok(Number(canonicalPayload.value_bytes || 0) > 0);

      const canonicalScope = JSON.parse(String(canonicalEvents[0].scope_json || '{}'));
      assert.equal(String(canonicalScope.device_id || ''), 'dev1');
      assert.equal(String(canonicalScope.app_id || ''), 'app1');

      const cursor = Number(rows[1].seq || 0);
      const incremental = db.listMemoryIndexChangelog({ since_seq: cursor, limit: 50 });
      assert.equal(incremental.length, 2);
      assert.equal(String(incremental[0].event_type || ''), 'insert');
      assert.equal(String(incremental[1].event_type || ''), 'update');

      const onlyCanonicalDelete = db.listMemoryIndexChangelog({
        since_seq: 0,
        limit: 50,
        table_name: 'canonical_memory',
        event_type: 'delete',
      });
      assert.equal(onlyCanonicalDelete.length, 0);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('W3-01/index changelog captures retention delete + restore events (turn/canonical)', () => {
  const dbPath = makeTmpDbPath('delete_restore');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      const now = Date.now();
      const thread = createThread(db);

      db.appendTurns({
        thread_id: thread.thread_id,
        request_id: 'req-ret',
        turns: [{ role: 'user', content: 'old turn delete me', is_private: 0, created_at_ms: now - 10_000 }],
      });

      const canonical = db.upsertCanonicalItem({
        scope: 'thread',
        thread_id: thread.thread_id,
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'old.key',
        value: 'old.value',
        pinned: 0,
      });

      db.db
        .prepare(`UPDATE canonical_memory SET updated_at_ms = ? WHERE item_id = ?`)
        .run(now - 10_000, String(canonical.item_id || ''));

      const before = db.listMemoryIndexChangelog({ since_seq: 0, limit: 100 });
      const cursor = Number(before[before.length - 1]?.seq || 0);

      const retention = db.runMemoryRetentionJob({ trigger: 'manual:w3_changelog', now_ms: now });
      assert.equal(retention.ok, true);
      assert.equal(retention.turns_deleted, 1);
      assert.equal(retention.canonical_deleted, 1);

      const delta = db.listMemoryIndexChangelog({ since_seq: cursor, limit: 100 });
      const deleteEvents = delta.filter((r) => String(r.event_type || '') === 'delete');
      assert.equal(deleteEvents.length, 2);
      assert.ok(deleteEvents.some((r) => String(r.table_name || '') === 'turns'));
      assert.ok(deleteEvents.some((r) => String(r.table_name || '') === 'canonical_memory'));
      assert.ok(deleteEvents.every((r) => String(r.source || '') === 'memory_retention'));

      const turnDeletePayload = JSON.parse(
        String(deleteEvents.find((r) => String(r.table_name || '') === 'turns')?.payload_json || '{}')
      );
      assert.equal(Object.prototype.hasOwnProperty.call(turnDeletePayload, 'content'), false);

      const tombstones = db.listMemoryDeleteTombstones({ limit: 10, include_payload: true });
      const turnTs = tombstones.find((t) => String(t.table_name || '') === 'turns');
      const canonTs = tombstones.find((t) => String(t.table_name || '') === 'canonical_memory');
      assert.ok(turnTs);
      assert.ok(canonTs);

      const deleteCursor = Number(delta[delta.length - 1]?.seq || cursor);
      const restoreTurn = db.restoreMemoryDeleteTombstone({ tombstone_id: String(turnTs.tombstone_id || '') });
      const restoreCanon = db.restoreMemoryDeleteTombstone({ tombstone_id: String(canonTs.tombstone_id || '') });
      assert.equal(restoreTurn.ok, true);
      assert.equal(restoreCanon.ok, true);

      const restoreEvents = db.listMemoryIndexChangelog({ since_seq: deleteCursor, limit: 100 });
      const restores = restoreEvents.filter((r) => String(r.event_type || '') === 'restore');
      assert.equal(restores.length, 2);
      assert.ok(restores.every((r) => String(r.source || '') === 'memory_retention_restore'));
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});
