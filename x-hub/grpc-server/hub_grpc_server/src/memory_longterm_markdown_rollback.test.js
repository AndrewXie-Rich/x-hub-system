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
  return path.join(os.tmpdir(), `hub_memory_markdown_w4_09_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x51).toString('base64')}`;

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

function createWrittenCandidate(impl, client, suffix) {
  const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
  assert.equal(begin.err, null);

  const patch = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
    client,
    edit_session_id: String(begin.res.edit_session_id || ''),
    base_version: String(begin.res.base_version || ''),
    session_revision: Number(begin.res.session_revision || 0),
    patch_mode: 'replace',
    patch_markdown: `${String(begin.res.markdown || '')}\n\nnext_step: ${suffix}`,
  });
  assert.equal(patch.err, null);

  const review = invokeHubMemoryUnary(impl, 'LongtermMarkdownReview', {
    client,
    pending_change_id: String(patch.res.pending_change_id || ''),
    review_decision: 'approve',
    on_secret: 'deny',
  });
  assert.equal(review.err, null);
  assert.equal(String(review.res.status || ''), 'approved');

  const writeback = invokeHubMemoryUnary(impl, 'LongtermMarkdownWriteback', {
    client,
    pending_change_id: String(patch.res.pending_change_id || ''),
    writeback_note: `write ${suffix}`,
  });
  assert.equal(writeback.err, null);
  assert.equal(String(writeback.res.status || ''), 'written');
  assert.ok(String(writeback.res.candidate_id || '').startsWith('mlwb_'));

  return {
    pending_change_id: String(patch.res.pending_change_id || ''),
    candidate_id: String(writeback.res.candidate_id || ''),
    change_log_id: String(writeback.res.change_log_id || ''),
  };
}

run('W4-09/rollback restores previous stable candidate and is idempotent', () => {
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
        value: 'ask user before payment',
        pinned: 1,
      });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = {
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        session_id: 'sess1',
      };

      const first = createWrittenCandidate(impl, client, 'v1');
      const second = createWrittenCandidate(impl, client, 'v2');

      const rollback = invokeHubMemoryUnary(impl, 'LongtermMarkdownRollback', {
        client,
        pending_change_id: second.pending_change_id,
        rollback_note: 'rollback to previous stable',
      });
      assert.equal(rollback.err, null);
      assert.equal(String(rollback.res.status || ''), 'rolled_back');
      assert.equal(String(rollback.res.rolled_back_candidate_id || ''), second.candidate_id);
      assert.equal(String(rollback.res.restored_candidate_id || ''), first.candidate_id);
      assert.ok(String(rollback.res.change_log_id || '').startsWith('mlog_'));
      assert.ok(String(rollback.res.evidence_ref || '').length > 0);

      const changeAfterRollback = db.getMemoryMarkdownPendingChange({
        change_id: second.pending_change_id,
      });
      assert.equal(String(changeAfterRollback.status || ''), 'rolled_back');
      assert.equal(String(changeAfterRollback.rollback_ref || ''), first.candidate_id);

      const rolledCandidate = db.getMemoryLongtermWritebackCandidate({
        candidate_id: second.candidate_id,
      });
      assert.equal(String(rolledCandidate.status || ''), 'rolled_back');
      assert.equal(Math.max(0, Number(rolledCandidate.rolled_back_at_ms || 0)) > 0, true);

      const rollbackLogs = db.listMemoryLongtermWritebackChangeLogs({
        change_id: second.pending_change_id,
        event_type: 'rollback',
        limit: 10,
      });
      assert.equal(rollbackLogs.length, 1);
      assert.equal(String(rollbackLogs[0].candidate_id || ''), second.candidate_id);
      assert.equal(String(rollbackLogs[0].restored_candidate_id || ''), first.candidate_id);
      assert.equal(String(rollbackLogs[0].actor_device_id || ''), 'dev1');
      assert.equal(String(rollbackLogs[0].actor_app_id || ''), 'app1');

      const rollbackAgain = invokeHubMemoryUnary(impl, 'LongtermMarkdownRollback', {
        client,
        pending_change_id: second.pending_change_id,
        rollback_note: 'idempotent replay',
      });
      assert.equal(rollbackAgain.err, null);
      assert.equal(String(rollbackAgain.res.status || ''), 'rolled_back');
      assert.equal(String(rollbackAgain.res.restored_candidate_id || ''), first.candidate_id);
      assert.equal(String(rollbackAgain.res.change_log_id || ''), String(rollback.res.change_log_id || ''));

      const rollbackLogsAfterReplay = db.listMemoryLongtermWritebackChangeLogs({
        change_id: second.pending_change_id,
        event_type: 'rollback',
        limit: 10,
      });
      assert.equal(rollbackLogsAfterReplay.length, 1);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run('W4-09/rollback scope mismatch fails closed', () => {
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
        value: 'ask user before payment',
        pinned: 1,
      });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = {
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
        session_id: 'sess1',
      };

      const first = createWrittenCandidate(impl, client, 'scope-v1');
      const second = createWrittenCandidate(impl, client, 'scope-v2');
      assert.ok(first);

      db.db
        .prepare(
          `UPDATE memory_longterm_writeback_queue
           SET scope_ref_json = ?
           WHERE candidate_id = ?`
        )
        .run(
          JSON.stringify({
            device_id: 'dev1',
            user_id: 'user1',
            app_id: 'app1',
            project_id: 'other_project',
            thread_id: '',
          }),
          second.candidate_id
        );

      const rollback = invokeHubMemoryUnary(impl, 'LongtermMarkdownRollback', {
        client,
        pending_change_id: second.pending_change_id,
        rollback_note: 'should fail closed',
      });
      assert.ok(rollback.err);
      assert.equal(String(rollback.err.message || ''), 'rollback_scope_mismatch');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});
