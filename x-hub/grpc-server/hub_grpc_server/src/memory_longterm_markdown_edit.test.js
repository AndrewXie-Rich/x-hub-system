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
  return path.join(os.tmpdir(), `hub_memory_markdown_edit_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x41).toString('base64')}`;

function baseEnv(runtimeBaseDir, extra = {}) {
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
    HUB_MEMORY_MARKDOWN_EDIT_TTL_MS: String(20 * 60 * 1000),
    HUB_MEMORY_MARKDOWN_PATCH_MAX_CHARS: '20000',
    HUB_MEMORY_MARKDOWN_PATCH_MAX_LINES: '1200',
    ...extra,
  };
}

function invokeHubMemoryUnary(impl, methodName, request) {
  let outErr = null;
  let outRes = null;
  impl.HubMemory[methodName](
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

run('W4-07/begin_edit + apply_patch optimistic lock and pending draft without canonical write', () => {
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
        value: 'Ask user to confirm payment.',
        pinned: 1,
      });
      const beforeCanonical = db.listCanonicalItems({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        limit: 20,
      });
      assert.equal(beforeCanonical.length, 1);

      const impl = makeServices({ db, bus: new HubEventBus() });
      const baseRequest = {
        client: {
          device_id: 'dev1',
          user_id: 'user1',
          app_id: 'app1',
          project_id: 'proj1',
          session_id: 'sess1',
        },
        scope: 'project',
      };
      const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', baseRequest);
      assert.equal(begin.err, null);
      assert.ok(begin.res);
      assert.ok(String(begin.res.edit_session_id || '').length > 0);
      assert.equal(Number(begin.res.session_revision || 0), 0);
      assert.ok(String(begin.res.markdown || '').includes('workflow.next_step'));

      const apply = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
        client: baseRequest.client,
        edit_session_id: String(begin.res.edit_session_id || ''),
        base_version: String(begin.res.base_version || ''),
        session_revision: Number(begin.res.session_revision || 0),
        patch_mode: 'replace',
        patch_markdown: String(begin.res.markdown || '').replace(
          'Ask user to confirm payment.',
          'Ask user on phone, then wait for explicit authorization.'
        ),
        patch_note: 'tighten authorization wording',
      });
      assert.equal(apply.err, null);
      assert.ok(apply.res);
      assert.equal(Number(apply.res.session_revision || 0), 1);
      assert.ok(String(apply.res.pending_change_id || '').length > 0);
      assert.equal(String(apply.res.status || ''), 'draft');
      assert.ok(String(apply.res.markdown || '').includes('explicit authorization'));

      const stale = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
        client: baseRequest.client,
        edit_session_id: String(begin.res.edit_session_id || ''),
        base_version: String(begin.res.base_version || ''),
        session_revision: Number(begin.res.session_revision || 0), // stale revision
        patch_mode: 'replace',
        patch_markdown: String(begin.res.markdown || ''),
      });
      assert.ok(stale.err);
      assert.equal(String(stale.err.message || ''), 'version_conflict');

      const pendingRows = db.listMemoryMarkdownPendingChanges({
        edit_session_id: String(begin.res.edit_session_id || ''),
        status: 'draft',
        limit: 10,
      });
      assert.equal(pendingRows.length, 1);
      assert.ok(String(pendingRows[0].patched_markdown || '').includes('explicit authorization'));

      const afterCanonical = db.listCanonicalItems({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        limit: 20,
      });
      assert.equal(afterCanonical.length, 1);
      assert.equal(String(afterCanonical[0].value || ''), 'Ask user to confirm payment.');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run('W4-07/apply_patch over limit fails closed', () => {
  const runtimeBaseDir = makeTmp('runtime2');
  const dbPath = makeTmp('db2', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir, { HUB_MEMORY_MARKDOWN_PATCH_MAX_CHARS: '80' }), () => {
    const db = new HubDB({ dbPath });
    try {
      db.upsertCanonicalItem({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        key: 'k1',
        value: 'v1',
        pinned: 0,
      });
      const impl = makeServices({ db, bus: new HubEventBus() });
      const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', {
        client: {
          device_id: 'dev1',
          user_id: 'user1',
          app_id: 'app1',
          project_id: 'proj1',
        },
        scope: 'project',
      });
      assert.equal(begin.err, null);
      const tooLong = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
        client: {
          device_id: 'dev1',
          user_id: 'user1',
          app_id: 'app1',
          project_id: 'proj1',
        },
        edit_session_id: String(begin.res.edit_session_id || ''),
        base_version: String(begin.res.base_version || ''),
        session_revision: Number(begin.res.session_revision || 0),
        patch_mode: 'replace',
        patch_markdown: '# x\n' + 'a'.repeat(900),
      });
      assert.ok(tooLong.err);
      assert.equal(String(tooLong.err.message || ''), 'patch_limit_exceeded:chars');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});
