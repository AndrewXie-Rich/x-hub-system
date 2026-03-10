import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { HubDB } from './db.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CLI_PATH = path.join(HERE, 'memory_rebuild_client.js');

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
    `hub_memory_rebuild_cli_${label}_${Date.now()}_${Math.random().toString(16).slice(2)}.db`
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

function seedMemory(dbPath) {
  const db = new HubDB({ dbPath });
  try {
    const thread = db.getOrCreateThread({
      device_id: 'dev1',
      user_id: 'user1',
      app_id: 'app1',
      project_id: 'proj1',
      thread_key: 'rebuild-cli-thread',
    });
    const now = Date.now();
    db.appendTurns({
      thread_id: thread.thread_id,
      request_id: 'req-cli',
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
  } finally {
    db.close();
  }
}

function runCli(args, extraEnv = {}) {
  const env = { ...process.env, ...baseEnv(), ...extraEnv };
  return spawnSync('node', [CLI_PATH, ...args], {
    env,
    encoding: 'utf8',
  });
}

run('W3-04/rebuild-index supports dry-run without writing active generation', () => {
  const dbPath = makeTmpDbPath('dry_run');
  withEnv(baseEnv(), () => {
    seedMemory(dbPath);
    const p = runCli(['--db-path', dbPath, '--dry-run', '--json']);
    assert.equal(p.status, 0);
    const out = JSON.parse(String(p.stdout || '{}'));
    assert.equal(out.ok, true);
    assert.equal(out.dry_run, true);
    assert.equal(out.stage, 'plan');
    assert.ok(Number(out.docs_total || 0) >= 3);

    const db = new HubDB({ dbPath });
    try {
      const active = db.getActiveMemorySearchIndexGeneration();
      assert.equal(active, null);
      const gens = db.listMemorySearchIndexGenerations({ limit: 10 });
      assert.equal(gens.length, 0);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});

run('W3-04/rebuild-index executes full rebuild and supports swap-failure rollback', () => {
  const dbPath = makeTmpDbPath('full_and_fail');
  withEnv(baseEnv(), () => {
    seedMemory(dbPath);

    const okRun = runCli(['--db-path', dbPath, '--json', '--batch-size', '64']);
    assert.equal(okRun.status, 0);
    const okOut = JSON.parse(String(okRun.stdout || '{}'));
    assert.equal(okOut.ok, true);
    assert.equal(okOut.stage, 'swap');
    assert.ok(String(okOut.active_generation_id || '').length > 0);
    const activeGen = String(okOut.active_generation_id || '');

    const failRun = runCli(['--db-path', dbPath, '--json', '--fail-after-pointer-update']);
    assert.equal(failRun.status, 2);
    const failOut = JSON.parse(String(failRun.stdout || '{}'));
    assert.equal(failOut.ok, false);
    assert.equal(String(failOut.error_code || ''), 'swap_failed');
    assert.equal(String(failOut.active_generation_id || ''), activeGen);

    const db = new HubDB({ dbPath });
    try {
      const active = db.getActiveMemorySearchIndexGeneration();
      assert.equal(String(active?.generation_id || ''), activeGen);
      const docs = db.listMemorySearchIndexGenerationDocs({
        generation_id: activeGen,
        limit: 100,
        offset: 0,
      });
      assert.ok(docs.length >= 3);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
    }
  });
});
