import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
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
    `hub_memory_index_rebuild_${label}_${Date.now()}_${Math.random().toString(16).slice(2)}.db`
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

function seedMemory(db) {
  const thread = db.getOrCreateThread({
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    thread_key: 'index-rebuild-thread',
  });
  const now = Date.now();
  db.appendTurns({
    thread_id: thread.thread_id,
    request_id: 'req-rb',
    turns: [
      { role: 'user', content: 'robot buy water', is_private: 0, created_at_ms: now - 2 },
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
}

run('W3-03/rebuild atomic swap keeps read side available and promotes new active generation', () => {
  const dbPath = makeTmpDbPath('success');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      seedMemory(db);
      const baseline = db.ensureMemorySearchIndexBaselineActive({ source: 'test_bootstrap' });
      assert.ok(String(baseline.generation_id || '').length > 0);
      assert.equal(String(baseline.status || ''), 'active');

      const before = listActiveMemorySearchIndexDocs({ db, limit: 20 });
      assert.equal(before.docs.length, 0);

      const out = rebuildMemorySearchIndexAtomic({
        db,
        source: 'unit_test_rebuild',
      });
      assert.equal(out.ok, true);
      assert.ok(Number(out.duration_ms || 0) >= 0);
      assert.ok(Number(out.docs_total || 0) >= 3);
      assert.ok(String(out.active_generation_id || '').length > 0);
      assert.notEqual(String(out.active_generation_id || ''), String(baseline.generation_id || ''));

      const after = listActiveMemorySearchIndexDocs({ db, limit: 50 });
      assert.equal(String(after.generation?.generation_id || ''), String(out.active_generation_id || ''));
      assert.equal(after.docs.length, Number(out.docs_total || 0));
      const sourceTables = new Set(after.docs.map((d) => String(d.source_table || '')));
      assert.ok(sourceTables.has('turns'));
      assert.ok(sourceTables.has('canonical_memory'));

      const baselineAfter = db.getMemorySearchIndexGeneration({ generation_id: String(baseline.generation_id || '') });
      assert.equal(String(baselineAfter.status || ''), 'retired');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('W3-03/swap failure auto-rolls back to previous active generation and records failure reason', () => {
  const dbPath = makeTmpDbPath('swap_failure');
  withEnv(baseEnv(), () => {
    const db = new HubDB({ dbPath });
    try {
      seedMemory(db);
      const r1 = rebuildMemorySearchIndexAtomic({
        db,
        source: 'unit_test_first',
      });
      assert.equal(r1.ok, true);
      const activeBefore = db.getActiveMemorySearchIndexGeneration();
      assert.ok(activeBefore);
      const beforeDocs = listActiveMemorySearchIndexDocs({ db, limit: 100 }).docs;

      const r2 = rebuildMemorySearchIndexAtomic({
        db,
        source: 'unit_test_swap_fail',
        fail_after_pointer_update: true,
      });
      assert.equal(r2.ok, false);
      assert.equal(String(r2.error_code || ''), 'swap_failed');
      assert.ok(String(r2.error_message || '').includes('simulated_swap_failure'));

      const activeAfter = db.getActiveMemorySearchIndexGeneration();
      assert.equal(
        String(activeAfter?.generation_id || ''),
        String(activeBefore.generation_id || '')
      );

      const failedGen = db.getMemorySearchIndexGeneration({
        generation_id: String(r2.generation_id || ''),
      });
      assert.equal(String(failedGen?.status || ''), 'failed');
      assert.equal(String(failedGen?.error_code || ''), 'swap_failed');
      assert.ok(Number(failedGen?.duration_ms || 0) >= 0);

      const afterDocs = listActiveMemorySearchIndexDocs({ db, limit: 100 }).docs;
      assert.equal(afterDocs.length, beforeDocs.length);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});
