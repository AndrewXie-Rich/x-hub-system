import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';

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

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_markdown_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x41).toString('base64')}`;

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
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
    HUB_MEMORY_MARKDOWN_EXPORT_MAX_CHARS: '49152',
  };
}

function invokeLongtermExport(impl, request) {
  let outErr = null;
  let outRes = null;
  impl.HubMemory.LongtermMarkdownExport(
    {
      request,
      metadata: {
        get() {
          return [];
        },
      },
    },
    (err, res) => {
      outErr = err || null;
      outRes = res || null;
    }
  );
  return { err: outErr, res: outRes };
}

run('W4-06/LongtermMarkdownExport returns stable doc/version/markdown and provenance refs', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      db.upsertCanonicalItem({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'workflow.next_step',
        value: 'Ask user to confirm payment on phone.',
        pinned: 1,
      });
      db.upsertCanonicalItem({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'water.price',
        value: '3 USD',
        pinned: 0,
      });
      // Different project should not leak.
      db.upsertCanonicalItem({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj2',
        key: 'hidden.other_project',
        value: 'must_not_export',
        pinned: 0,
      });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const request = {
        client: {
          device_id: 'dev1',
          user_id: 'user1',
          app_id: 'app1',
          project_id: 'proj1',
        },
        scope: 'project',
        limit: 100,
      };
      const first = invokeLongtermExport(impl, request);
      assert.equal(first.err, null);
      assert.ok(first.res);
      assert.ok(String(first.res.doc_id || '').length > 0);
      assert.ok(String(first.res.version || '').startsWith('lmv1_'));
      assert.ok(String(first.res.markdown || '').includes('workflow.next_step'));
      assert.equal(String(first.res.markdown || '').includes('hidden.other_project'), false);
      assert.ok(Array.isArray(first.res.provenance_refs));
      assert.ok(first.res.provenance_refs.length >= 2);

      const replay = invokeLongtermExport(impl, {
        ...request,
        expected_version: String(first.res.version || ''),
      });
      assert.equal(replay.err, null);
      assert.equal(String(replay.res.version || ''), String(first.res.version || ''));
      assert.equal(String(replay.res.markdown || ''), String(first.res.markdown || ''));
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run('W4-06/LongtermMarkdownExport remote mode denies secret shard and supports version_conflict', () => {
  const runtimeBaseDir = makeTmp('runtime2');
  const dbPath = makeTmp('db2', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      db.upsertCanonicalItem({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'payment.api_key',
        value: 'sk-live-secret-12345',
        pinned: 0,
      });
      db.upsertCanonicalItem({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'payment.note',
        value: 'Need user authorization before pay.',
        pinned: 0,
      });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const request = {
        client: {
          device_id: 'dev1',
          user_id: 'user1',
          app_id: 'app1',
          project_id: 'proj1',
        },
        scope: 'project',
        remote_mode: true,
        allowed_sensitivity: ['public', 'internal', 'secret'],
      };

      const out = invokeLongtermExport(impl, request);
      assert.equal(out.err, null);
      assert.ok(out.res);
      assert.equal(String(out.res.markdown || '').includes('payment.api_key'), false);
      assert.equal(Array.isArray(out.res.applied_sensitivity), true);
      assert.equal(out.res.applied_sensitivity.includes('secret'), false);

      const conflict = invokeLongtermExport(impl, {
        ...request,
        expected_version: 'lmv1_conflict',
      });
      assert.ok(conflict.err);
      assert.equal(String(conflict.err.message || ''), 'version_conflict');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

