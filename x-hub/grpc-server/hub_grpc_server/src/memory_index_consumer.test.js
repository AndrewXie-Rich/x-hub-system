import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { computeRetryBackoffMs, consumeMemoryIndexChangelogBatch } from './memory_index_consumer.js';

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
    `hub_memory_index_consumer_${label}_${Date.now()}_${Math.random().toString(16).slice(2)}.db`
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

function seedEvents(db) {
  const thread = db.getOrCreateThread({
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    thread_key: 'index-consumer-thread',
  });
  const now = Date.now();

  db.appendTurns({
    thread_id: thread.thread_id,
    request_id: 'req-consumer',
    turns: [
      { role: 'user', content: 'buy water', is_private: 0, created_at_ms: now - 2 },
      { role: 'assistant', content: 'price is 3', is_private: 0, created_at_ms: now - 1 },
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

  return db.listMemoryIndexChangelog({ since_seq: 0, limit: 100 });
}

run('W3-02/backoff formula grows exponentially and caps', () => {
  assert.equal(computeRetryBackoffMs(1, 50, 1000), 50);
  assert.equal(computeRetryBackoffMs(2, 50, 1000), 100);
  assert.equal(computeRetryBackoffMs(5, 50, 600), 600);
});

run('W3-02/consumer checkpoints progress across batches and supports resume', () => {
  const dbPath = makeTmpDbPath('batch_resume');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      const events = seedEvents(db);
      assert.equal(events.length, 4);
      const maxSeq = Number(events[events.length - 1].seq || 0);
      const handled = [];

      const r1 = consumeMemoryIndexChangelogBatch({
        db,
        consumer_id: 'retrieval_hot_index',
        batch_limit: 2,
        max_retries: 2,
        on_event: (evt) => {
          handled.push(String(evt.event_id || ''));
        },
      });
      assert.equal(r1.ok, true);
      assert.equal(r1.applied, 2);
      assert.equal(r1.failed, 0);
      assert.equal(r1.drained, false);

      const cp1 = db.getMemoryIndexConsumerCheckpoint({ consumer_id: 'retrieval_hot_index' });
      assert.equal(Number(cp1.checkpoint_seq || 0), Number(r1.next_seq || 0));
      assert.equal(String(cp1.status || ''), 'idle');

      const r2 = consumeMemoryIndexChangelogBatch({
        db,
        consumer_id: 'retrieval_hot_index',
        batch_limit: 5,
        max_retries: 2,
        on_event: (evt) => {
          handled.push(String(evt.event_id || ''));
        },
      });
      assert.equal(r2.ok, true);
      assert.equal(r2.applied, 2);
      assert.equal(r2.next_seq, maxSeq);

      const r3 = consumeMemoryIndexChangelogBatch({
        db,
        consumer_id: 'retrieval_hot_index',
        batch_limit: 5,
        on_event: () => {
          throw new Error('should not run when drained');
        },
      });
      assert.equal(r3.ok, true);
      assert.equal(r3.fetched, 0);
      assert.equal(r3.applied, 0);
      assert.equal(r3.drained, true);
      assert.equal(handled.length, 4);

      const processed = db.listMemoryIndexConsumerProcessedEvents({
        consumer_id: 'retrieval_hot_index',
        since_seq: 0,
        limit: 100,
      });
      assert.equal(processed.length, 4);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('W3-02/consumer failure writes error checkpoint and restart resumes from last seq', () => {
  const dbPath = makeTmpDbPath('fail_resume');
  withEnv(baseEnv(), () => {
    const db1 = new HubDB({ dbPath });
    try {
      const events = seedEvents(db1);
      assert.equal(events.length, 4);
      const failEventId = String(events[1].event_id || '');
      const maxSeq = Number(events[events.length - 1].seq || 0);
      const attempts = new Map();

      const rFail = consumeMemoryIndexChangelogBatch({
        db: db1,
        consumer_id: 'retrieval_hot_index',
        batch_limit: 10,
        max_retries: 1,
        retry_backoff_base_ms: 20,
        retry_backoff_cap_ms: 200,
        on_event: (evt) => {
          const id = String(evt.event_id || '');
          const n = Number(attempts.get(id) || 0);
          attempts.set(id, n + 1);
          if (id === failEventId) throw new Error('transient_index_error');
        },
      });
      assert.equal(rFail.ok, false);
      assert.equal(rFail.failed, 1);
      assert.ok(rFail.suggested_backoff_ms >= 20);

      const cpErr = db1.getMemoryIndexConsumerCheckpoint({ consumer_id: 'retrieval_hot_index' });
      assert.equal(String(cpErr.status || ''), 'error');
      assert.ok(String(cpErr.last_error || '').includes('transient_index_error'));
      assert.ok(Number(cpErr.checkpoint_seq || 0) < maxSeq);
    } finally {
      db1.close();
    }

    const db2 = new HubDB({ dbPath });
    try {
      const handledAfterRestart = [];
      const rResume = consumeMemoryIndexChangelogBatch({
        db: db2,
        consumer_id: 'retrieval_hot_index',
        batch_limit: 10,
        max_retries: 2,
        on_event: (evt) => {
          handledAfterRestart.push(String(evt.event_id || ''));
        },
      });
      assert.equal(rResume.ok, true);
      assert.ok(rResume.applied >= 1);

      const cpDone = db2.getMemoryIndexConsumerCheckpoint({ consumer_id: 'retrieval_hot_index' });
      assert.equal(String(cpDone.status || ''), 'idle');
      const allEvents = db2.listMemoryIndexChangelog({ since_seq: 0, limit: 100 });
      const maxSeq = Number(allEvents[allEvents.length - 1].seq || 0);
      assert.equal(Number(cpDone.checkpoint_seq || 0), maxSeq);

      db2.upsertMemoryIndexConsumerCheckpoint({
        consumer_id: 'retrieval_hot_index',
        checkpoint_seq: 0,
        status: 'idle',
      });

      let called = 0;
      const rIdempotent = consumeMemoryIndexChangelogBatch({
        db: db2,
        consumer_id: 'retrieval_hot_index',
        batch_limit: 100,
        on_event: () => {
          called += 1;
        },
      });
      assert.equal(rIdempotent.ok, true);
      assert.equal(rIdempotent.applied, 0);
      assert.equal(rIdempotent.skipped, allEvents.length);
      assert.equal(called, 0);
    } finally {
      db2.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});
