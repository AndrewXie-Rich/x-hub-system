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
  return path.join(os.tmpdir(), `hub_memory_markdown_w4_08_${token}${suffix}`);
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
    HUB_MEMORY_MARKDOWN_EDIT_TTL_MS: String(20 * 60 * 1000),
    HUB_MEMORY_MARKDOWN_PATCH_MAX_CHARS: '50000',
    HUB_MEMORY_MARKDOWN_PATCH_MAX_LINES: '1200',
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

run('W4-08/review deny or sanitize, then approve and writeback queue only', () => {
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
        value: 'Ask user before payment',
        pinned: 1,
      });
      const canonicalBefore = db.listCanonicalItems({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        limit: 20,
      });
      assert.equal(canonicalBefore.length, 1);
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = {
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        session_id: 'sess1',
      };

      // Path A: deny on secret -> rejected.
      const beginA = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
      assert.equal(beginA.err, null);
      const patchA = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
        client,
        edit_session_id: String(beginA.res.edit_session_id || ''),
        base_version: String(beginA.res.base_version || ''),
        session_revision: Number(beginA.res.session_revision || 0),
        patch_mode: 'replace',
        patch_markdown: `${String(beginA.res.markdown || '')}\n\nsecret: sk-abcdef1234567890`,
      });
      assert.equal(patchA.err, null);
      const reviewDeny = invokeHubMemoryUnary(impl, 'LongtermMarkdownReview', {
        client,
        pending_change_id: String(patchA.res.pending_change_id || ''),
        review_decision: 'approve',
        on_secret: 'deny',
      });
      assert.equal(reviewDeny.err, null);
      assert.equal(String(reviewDeny.res.status || ''), 'rejected');
      assert.equal(Boolean(reviewDeny.res.auto_rejected), true);
      const writebackRejected = invokeHubMemoryUnary(impl, 'LongtermMarkdownWriteback', {
        client,
        pending_change_id: String(patchA.res.pending_change_id || ''),
      });
      assert.ok(writebackRejected.err);
      assert.equal(String(writebackRejected.err.message || ''), 'change_not_approved');

      // Path B: sanitize + approve -> written queue.
      const beginB = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
      assert.equal(beginB.err, null);
      const patchB = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
        client,
        edit_session_id: String(beginB.res.edit_session_id || ''),
        base_version: String(beginB.res.base_version || ''),
        session_revision: Number(beginB.res.session_revision || 0),
        patch_mode: 'replace',
        patch_markdown: `${String(beginB.res.markdown || '')}\n\nBearer abcdefghijklmnopqrstuvwxyzz`,
      });
      assert.equal(patchB.err, null);
      const reviewed = invokeHubMemoryUnary(impl, 'LongtermMarkdownReview', {
        client,
        pending_change_id: String(patchB.res.pending_change_id || ''),
        review_decision: 'approve',
        on_secret: 'sanitize',
      });
      assert.equal(reviewed.err, null);
      assert.equal(String(reviewed.res.status || ''), 'approved');
      assert.equal(String(reviewed.res.markdown || '').includes('Bearer abcdefghijklmnopqrstuvwxyzz'), false);

      const written = invokeHubMemoryUnary(impl, 'LongtermMarkdownWriteback', {
        client,
        pending_change_id: String(patchB.res.pending_change_id || ''),
        writeback_note: 'accept sanitized draft',
      });
      assert.equal(written.err, null);
      assert.equal(String(written.res.status || ''), 'written');
      assert.ok(String(written.res.candidate_id || '').startsWith('mlwb_'));
      assert.ok(String(written.res.change_log_id || '').startsWith('mlog_'));
      assert.ok(String(written.res.evidence_ref || '').length > 0);

      const queueRow = db.getMemoryLongtermWritebackCandidate({
        candidate_id: String(written.res.candidate_id || ''),
      });
      assert.ok(queueRow);
      assert.equal(String(queueRow.change_id || ''), String(patchB.res.pending_change_id || ''));
      assert.equal(String(queueRow.content_markdown || '').includes('Bearer abcdefghijklmnopqrstuvwxyzz'), false);
      assert.equal(String(queueRow.evidence_ref || ''), String(written.res.evidence_ref || ''));

      const logs = db.listMemoryLongtermWritebackChangeLogs({
        change_id: String(patchB.res.pending_change_id || ''),
        event_type: 'writeback',
        limit: 5,
      });
      assert.equal(logs.length, 1);
      assert.equal(String(logs[0].change_id || ''), String(patchB.res.pending_change_id || ''));
      assert.equal(String(logs[0].actor_device_id || ''), 'dev1');
      assert.equal(String(logs[0].actor_app_id || ''), 'app1');
      assert.equal(String(logs[0].evidence_ref || '').length > 0, true);
      assert.equal(typeof logs[0].policy_decision, 'object');

      const canonicalAfter = db.listCanonicalItems({
        scope: 'project',
        thread_id: '',
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        limit: 20,
      });
      assert.equal(canonicalAfter.length, 1);
      assert.equal(String(canonicalAfter[0].value || ''), 'Ask user before payment');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});
