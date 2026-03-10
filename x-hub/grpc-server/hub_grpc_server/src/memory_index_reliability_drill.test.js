import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { consumeMemoryIndexChangelogBatch } from './memory_index_consumer.js';
import { listActiveMemorySearchIndexDocs, rebuildMemorySearchIndexAtomic } from './memory_index_rebuild.js';

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
    `hub_memory_index_reliability_${label}_${Date.now()}_${Math.random().toString(16).slice(2)}.db`
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
    HUB_MEMORY_RETENTION_ENABLED: 'false',
  };
}

function getOrCreateTestThread(db, threadKey = 'w3-05-reliability-thread') {
  return db.getOrCreateThread({
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    thread_key: threadKey,
  });
}

function appendTurnsRange(db, { thread_id, request_id, count, content_prefix, start_at_ms }) {
  const n = Math.max(0, Number(count || 0));
  if (n <= 0) return;
  const start = Math.max(0, Number(start_at_ms || Date.now()));
  const turns = [];
  for (let i = 0; i < n; i += 1) {
    const role = (i % 2 === 0) ? 'user' : 'assistant';
    turns.push({
      role,
      content: `${String(content_prefix || 'turn')} #${i + 1}`,
      is_private: 0,
      created_at_ms: start + i,
    });
  }
  db.appendTurns({
    thread_id,
    request_id: String(request_id || `req_${Date.now()}`),
    turns,
  });
}

function seedMemory(db, opts = {}) {
  const thread = getOrCreateTestThread(db, opts.thread_key);
  const now = Date.now();
  appendTurnsRange(db, {
    thread_id: thread.thread_id,
    request_id: String(opts.request_id || 'req_seed'),
    count: Math.max(1, Number(opts.turn_count || 6)),
    content_prefix: String(opts.content_prefix || 'seed'),
    start_at_ms: now - 1000,
  });
  db.upsertCanonicalItem({
    scope: 'thread',
    thread_id: thread.thread_id,
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    key: String(opts.canonical_key || 'water.price'),
    value: String(opts.canonical_value || '3'),
    pinned: Number(opts.canonical_pinned || 0) ? 1 : 0,
  });
  return thread;
}

run('W3-05/restart drill: checkpoint resume + rebuild remains swappable after restart', () => {
  const dbPath = makeTmpDbPath('restart');
  withEnv(baseEnv(), () => {
    let activeGenerationBeforeRestart = '';
    const consumerId = 'retrieval_hot_index';

    const db1 = new HubDB({ dbPath });
    try {
      seedMemory(db1, { thread_key: 'w3-05-restart', turn_count: 8, content_prefix: 'restart.seed' });
      const rInit = rebuildMemorySearchIndexAtomic({
        db: db1,
        source: 'w3_05_restart_init',
        batch_size: 64,
      });
      assert.equal(rInit.ok, true);
      activeGenerationBeforeRestart = String(rInit.active_generation_id || '');
      assert.ok(activeGenerationBeforeRestart.length > 0);

      const partial = consumeMemoryIndexChangelogBatch({
        db: db1,
        consumer_id: consumerId,
        batch_limit: 2,
        max_retries: 2,
        on_event: () => {},
      });
      assert.equal(partial.ok, true);
      assert.equal(partial.applied, 2);
      const cp1 = db1.getMemoryIndexConsumerCheckpoint({ consumer_id: consumerId });
      const maxSeq1 = db1.getMemoryIndexChangelogMaxSeq();
      assert.ok(Number(cp1?.checkpoint_seq || 0) > 0);
      assert.ok(Number(cp1?.checkpoint_seq || 0) < maxSeq1);
    } finally {
      db1.close();
    }

    const db2 = new HubDB({ dbPath });
    try {
      const thread = getOrCreateTestThread(db2, 'w3-05-restart');
      appendTurnsRange(db2, {
        thread_id: thread.thread_id,
        request_id: 'req_restart_after',
        count: 3,
        content_prefix: 'restart.after',
        start_at_ms: Date.now() + 10,
      });
      db2.upsertCanonicalItem({
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

      const maxSeqAfterRestartWrites = db2.getMemoryIndexChangelogMaxSeq();
      const resumed = consumeMemoryIndexChangelogBatch({
        db: db2,
        consumer_id: consumerId,
        batch_limit: 200,
        max_retries: 2,
        on_event: () => {},
      });
      assert.equal(resumed.ok, true);
      const cp2 = db2.getMemoryIndexConsumerCheckpoint({ consumer_id: consumerId });
      assert.equal(Number(cp2?.checkpoint_seq || 0), maxSeqAfterRestartWrites);

      const activeStill = db2.getActiveMemorySearchIndexGeneration();
      assert.equal(String(activeStill?.generation_id || ''), activeGenerationBeforeRestart);

      const rAfter = rebuildMemorySearchIndexAtomic({
        db: db2,
        source: 'w3_05_restart_after',
        batch_size: 64,
      });
      assert.equal(rAfter.ok, true);
      assert.notEqual(String(rAfter.active_generation_id || ''), activeGenerationBeforeRestart);
      assert.ok(Number(rAfter.docs_total || 0) >= 12);
    } finally {
      db2.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('W3-05/corruption drill: active pointer corruption can self-heal via rebuild', () => {
  const dbPath = makeTmpDbPath('corruption');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      seedMemory(db, { thread_key: 'w3-05-corrupt', turn_count: 6, content_prefix: 'corrupt.seed' });
      const r1 = rebuildMemorySearchIndexAtomic({
        db,
        source: 'w3_05_corrupt_before',
        batch_size: 64,
      });
      assert.equal(r1.ok, true);
      const oldActiveId = String(r1.active_generation_id || '');
      assert.ok(oldActiveId.length > 0);
      db.clearMemorySearchIndexGenerationDocs({ generation_id: oldActiveId });

      db.db
        .prepare(
          `UPDATE memory_search_index_state
           SET active_generation_id = ?, last_error = ?
           WHERE state_id = 1`
        )
        .run('midxg_missing_corrupted_pointer', 'simulated_corruption');
      assert.equal(db.getActiveMemorySearchIndexGeneration(), null);

      const recovered = rebuildMemorySearchIndexAtomic({
        db,
        source: 'w3_05_corrupt_recover',
        batch_size: 64,
      });
      assert.equal(recovered.ok, true);
      assert.ok(String(recovered.active_generation_id || '').length > 0);
      assert.notEqual(String(recovered.active_generation_id || ''), 'midxg_missing_corrupted_pointer');
      assert.ok(Number(recovered.docs_total || 0) >= 7);

      const state = db.getMemorySearchIndexState();
      assert.equal(String(state?.last_rebuild_status || ''), 'active');
      assert.equal(state?.last_error, null);
      const docs = listActiveMemorySearchIndexDocs({ db, limit: 200 });
      assert.equal(String(docs?.generation?.generation_id || ''), String(recovered.active_generation_id || ''));
      assert.ok(docs.docs.length >= 7);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('W3-05/concurrency drill: rebuild snapshot stays consistent and delta catches concurrent writes', () => {
  const dbPath = makeTmpDbPath('concurrency');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      const thread = seedMemory(db, {
        thread_key: 'w3-05-concurrent',
        turn_count: 120,
        content_prefix: 'concurrent.seed',
      });

      let injected = false;
      const origAppendDocs = db.appendMemorySearchIndexGenerationDocs.bind(db);
      db.appendMemorySearchIndexGenerationDocs = (args = {}) => {
        const inserted = origAppendDocs(args);
        const docs = Array.isArray(args?.docs) ? args.docs : [];
        if (!injected && docs.some((d) => String(d?.source_table || '') === 'turns')) {
          injected = true;
          appendTurnsRange(db, {
            thread_id: thread.thread_id,
            request_id: 'req_concurrent_during_rebuild',
            count: 2,
            content_prefix: 'concurrent.inflight',
            start_at_ms: Date.now() + 5,
          });
        }
        return inserted;
      };

      const rebuilt = rebuildMemorySearchIndexAtomic({
        db,
        source: 'w3_05_concurrency',
        batch_size: 20,
      });
      db.appendMemorySearchIndexGenerationDocs = origAppendDocs;

      assert.equal(rebuilt.ok, true);
      assert.equal(injected, true);
      assert.ok(Number(rebuilt.docs_total || 0) >= 121);

      const maxSeqAfter = db.getMemoryIndexChangelogMaxSeq();
      assert.ok(maxSeqAfter > Number(rebuilt.snapshot_to_seq || 0));

      const consumerId = 'retrieval_hot_index';
      db.upsertMemoryIndexConsumerCheckpoint({
        consumer_id: consumerId,
        checkpoint_seq: Number(rebuilt.snapshot_to_seq || 0),
        status: 'idle',
      });

      const consumedIds = [];
      const delta = consumeMemoryIndexChangelogBatch({
        db,
        consumer_id: consumerId,
        batch_limit: 200,
        on_event: (evt) => {
          consumedIds.push(String(evt?.event_id || ''));
        },
      });
      assert.equal(delta.ok, true);
      assert.ok(delta.applied >= 1);
      assert.equal(delta.next_seq, maxSeqAfter);
      assert.ok(consumedIds.length >= 1);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});
