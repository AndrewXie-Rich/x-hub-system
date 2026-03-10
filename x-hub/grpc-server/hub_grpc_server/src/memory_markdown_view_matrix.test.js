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
  return path.join(os.tmpdir(), `hub_memory_markdown_w4_10_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x61).toString('base64')}`;

function baseEnv(runtimeBaseDir, overrides = {}) {
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
    ...overrides,
  };
}

function withHubCase(fn, envOverrides = {}) {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  return withEnv(baseEnv(runtimeBaseDir, envOverrides), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      return fn({ db, impl });
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
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

function makeClient(overrides = {}) {
  return {
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    session_id: 'sess1',
    ...overrides,
  };
}

function seedCanonicalProject(db, value = 'ask user before payment') {
  db.upsertCanonicalItem({
    scope: 'project',
    thread_id: '',
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    key: 'workflow.next_step',
    value,
    pinned: 1,
  });
}

function createApprovedChange(impl, client, patchMarkdown) {
  const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
  assert.equal(begin.err, null);

  const patch = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
    client,
    edit_session_id: String(begin.res.edit_session_id || ''),
    base_version: String(begin.res.base_version || ''),
    session_revision: Number(begin.res.session_revision || 0),
    patch_mode: 'replace',
    patch_markdown: String(patchMarkdown || begin.res.markdown || ''),
  });
  assert.equal(patch.err, null);

  const reviewed = invokeHubMemoryUnary(impl, 'LongtermMarkdownReview', {
    client,
    pending_change_id: String(patch.res.pending_change_id || ''),
    review_decision: 'approve',
    on_secret: 'sanitize',
  });
  assert.equal(reviewed.err, null);
  assert.equal(String(reviewed.res.status || ''), 'approved');

  return {
    begin,
    patch,
    reviewed,
    pending_change_id: String(patch.res.pending_change_id || ''),
  };
}

function createWrittenCandidate(impl, client, suffix) {
  const approved = createApprovedChange(
    impl,
    client,
    `# note\n\nnext_step: ${String(suffix || 'default')}`
  );
  const written = invokeHubMemoryUnary(impl, 'LongtermMarkdownWriteback', {
    client,
    pending_change_id: approved.pending_change_id,
    writeback_note: `write ${String(suffix || 'default')}`,
  });
  assert.equal(written.err, null);
  return {
    pending_change_id: approved.pending_change_id,
    candidate_id: String(written.res.candidate_id || ''),
    change_log_id: String(written.res.change_log_id || ''),
  };
}

run('W4-10/matrix empty export returns deterministic empty markdown', () => {
  withHubCase(({ impl }) => {
    const emptyClient = makeClient({ project_id: 'proj_empty' });
    const out = invokeHubMemoryUnary(impl, 'LongtermMarkdownExport', {
      client: emptyClient,
      scope: 'project',
    });
    assert.equal(out.err, null);
    assert.equal(Number(out.res.total_items ?? -1), 0);
    assert.equal(Number(out.res.included_items ?? -1), 0);
    assert.equal(Array.isArray(out.res.provenance_refs), true);
    assert.equal(out.res.provenance_refs.length, 0);
    assert.equal(String(out.res.markdown || '').includes('_No entries matched current filters/gates._'), true);
  });
});

run('W4-10/matrix malicious markdown requires sanitize before writeback', () => {
  withHubCase(({ db, impl }) => {
    seedCanonicalProject(db);
    const client = makeClient();
    const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
    assert.equal(begin.err, null);

    const patch = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
      client,
      edit_session_id: String(begin.res.edit_session_id || ''),
      base_version: String(begin.res.base_version || ''),
      session_revision: Number(begin.res.session_revision || 0),
      patch_mode: 'replace',
      patch_markdown: `${String(begin.res.markdown || '')}\n\n<script>alert(1)</script>\nBearer abcdefghijklmnopqrstuvwxyzz\n<private>card:4242</private>`,
    });
    assert.equal(patch.err, null);

    const reviewed = invokeHubMemoryUnary(impl, 'LongtermMarkdownReview', {
      client,
      pending_change_id: String(patch.res.pending_change_id || ''),
      review_decision: 'approve',
      on_secret: 'sanitize',
    });
    assert.equal(reviewed.err, null);
    assert.equal(String(reviewed.res.status || ''), 'approved');
    assert.equal(String(reviewed.res.markdown || '').includes('Bearer abcdefghijklmnopqrstuvwxyzz'), false);
    assert.equal(String(reviewed.res.markdown || '').includes('<private>'), false);

    const written = invokeHubMemoryUnary(impl, 'LongtermMarkdownWriteback', {
      client,
      pending_change_id: String(patch.res.pending_change_id || ''),
    });
    assert.equal(written.err, null);
    assert.equal(String(written.res.status || ''), 'written');
  });
});

run('W4-10/matrix overlong patch fails closed with explicit error', () => {
  withHubCase(({ db, impl }) => {
    seedCanonicalProject(db);
    const client = makeClient();
    const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
    assert.equal(begin.err, null);

    const tooLong = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
      client,
      edit_session_id: String(begin.res.edit_session_id || ''),
      base_version: String(begin.res.base_version || ''),
      session_revision: Number(begin.res.session_revision || 0),
      patch_mode: 'replace',
      patch_markdown: `# oversize\n\n${'x'.repeat(50001)}`,
    });
    assert.ok(tooLong.err);
    assert.equal(String(tooLong.err.message || ''), 'patch_limit_exceeded:chars');
  });
});

run('W4-10/matrix cross-scope write path is denied fail-closed', () => {
  withHubCase(({ db, impl }) => {
    seedCanonicalProject(db);
    const clientA = makeClient({ project_id: 'proj1' });
    const clientB = makeClient({ project_id: 'proj2' });

    const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client: clientA, scope: 'project' });
    assert.equal(begin.err, null);

    const denied = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
      client: clientB,
      edit_session_id: String(begin.res.edit_session_id || ''),
      base_version: String(begin.res.base_version || ''),
      session_revision: Number(begin.res.session_revision || 0),
      patch_mode: 'replace',
      patch_markdown: String(begin.res.markdown || ''),
    });
    assert.ok(denied.err);
    assert.equal(String(denied.err.message || ''), 'permission_denied');
  });
});

run('W4-10/matrix optimistic lock conflict returns version_conflict', () => {
  withHubCase(({ db, impl }) => {
    seedCanonicalProject(db);
    const client = makeClient();

    const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
    assert.equal(begin.err, null);

    const applied = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
      client,
      edit_session_id: String(begin.res.edit_session_id || ''),
      base_version: String(begin.res.base_version || ''),
      session_revision: Number(begin.res.session_revision || 0),
      patch_mode: 'replace',
      patch_markdown: `${String(begin.res.markdown || '')}\n\nnext_step: v1`,
    });
    assert.equal(applied.err, null);

    const stale = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
      client,
      edit_session_id: String(begin.res.edit_session_id || ''),
      base_version: String(begin.res.base_version || ''),
      session_revision: Number(begin.res.session_revision || 0),
      patch_mode: 'replace',
      patch_markdown: `${String(begin.res.markdown || '')}\n\nnext_step: stale`,
    });
    assert.ok(stale.err);
    assert.equal(String(stale.err.message || ''), 'version_conflict');
  });
});

run('W4-10/matrix corrupted change log fails closed with explicit error', () => {
  withHubCase(({ db, impl }) => {
    seedCanonicalProject(db);
    const client = makeClient();

    // Corrupt writeback changelog and ensure idempotent replay fails closed.
    const written = createWrittenCandidate(impl, client, 'corrupt-writeback');
    db.db
      .prepare(
        `DELETE FROM memory_longterm_writeback_changelog
         WHERE change_id = ? AND event_type = 'writeback'`
      )
      .run(written.pending_change_id);
    const writebackReplay = invokeHubMemoryUnary(impl, 'LongtermMarkdownWriteback', {
      client,
      pending_change_id: written.pending_change_id,
    });
    assert.ok(writebackReplay.err);
    assert.equal(String(writebackReplay.err.message || ''), 'writeback_state_corrupt');

    // Corrupt rollback changelog and ensure rollback replay fails closed.
    const first = createWrittenCandidate(impl, client, 'rollback-v1');
    const second = createWrittenCandidate(impl, client, 'rollback-v2');
    assert.ok(first.candidate_id.length > 0);

    const rollback = invokeHubMemoryUnary(impl, 'LongtermMarkdownRollback', {
      client,
      pending_change_id: second.pending_change_id,
      rollback_note: 'first rollback',
    });
    assert.equal(rollback.err, null);
    assert.equal(String(rollback.res.status || ''), 'rolled_back');

    db.db
      .prepare(
        `DELETE FROM memory_longterm_writeback_changelog
         WHERE change_id = ? AND event_type = 'rollback'`
      )
      .run(second.pending_change_id);

    const rollbackReplay = invokeHubMemoryUnary(impl, 'LongtermMarkdownRollback', {
      client,
      pending_change_id: second.pending_change_id,
      rollback_note: 'replay after log corruption',
    });
    assert.ok(rollbackReplay.err);
    assert.equal(String(rollbackReplay.err.message || ''), 'rollback_state_corrupt');
  });
});
