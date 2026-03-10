import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { MEMORY_METRICS_SCHEMA_VERSION } from './memory_metrics_schema.js';
import { responsePathForRequest } from './mlx_runtime_ipc.js';
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

async function runAsync(name, fn) {
  try {
    await fn();
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

async function withEnvAsync(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv)) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_metrics_${token}${suffix}`);
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
    HUB_AUDIT_LEVEL: 'full_content',
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
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '200',
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

function parseLatestAuditExtByType(db, eventType, deviceId = 'dev1') {
  const rows = db.listAuditEvents({ device_id: deviceId }) || [];
  const row = rows.find((r) => String(r.event_type || '') === String(eventType || ''));
  if (!row) return null;
  try {
    return JSON.parse(String(row.ext_json || '{}'));
  } catch {
    return null;
  }
}

function seedPaidGrant(db, {
  device_id = 'dev1',
  user_id = 'user1',
  app_id = 'app1',
  project_id = 'proj1',
  model_id = 'openai/gpt-4.1',
} = {}) {
  return db.createGrant({
    grant_request_id: '',
    device_id,
    user_id,
    app_id,
    project_id,
    capability: 'ai.generate.paid',
    model_id,
    token_cap: 1000000,
    expires_at_ms: Date.now() + (10 * 60 * 1000),
  });
}

run('W5-01/export audit carries unified metrics schema', () => {
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
        value: 'Ask user for payment confirmation.',
        pinned: 1,
      });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const out = invokeHubMemoryUnary(impl, 'LongtermMarkdownExport', {
        client: { device_id: 'dev1', user_id: 'user1', app_id: 'app1', project_id: 'proj1' },
        scope: 'project',
      });
      assert.equal(out.err, null);

      const ext = parseLatestAuditExtByType(db, 'memory.longterm_markdown.exported');
      assert.ok(ext && typeof ext === 'object');
      assert.ok(ext.metrics && typeof ext.metrics === 'object');
      assert.equal(ext.metrics.schema_version, MEMORY_METRICS_SCHEMA_VERSION);
      assert.equal(ext.metrics.event_kind, 'memory.longterm_markdown.exported');
      assert.equal(ext.metrics.job_type, 'markdown_export');
      assert.equal(ext.metrics.scope.kind, 'project');
      assert.equal(ext.metrics.op, 'markdown_export');
      assert.equal(ext.metrics.quality.total_items >= 1, true);
      assert.equal(ext.metrics.security.blocked, false);
      assert.equal(ext.metrics.latency.duration_ms >= 0, true);
      assert.equal(typeof ext.metrics.markdown, 'undefined');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run('W5-01/review deny path writes blocked security metrics without raw content', () => {
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
        key: 'workflow.note',
        value: 'normal note',
        pinned: 0,
      });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = { device_id: 'dev1', user_id: 'user1', app_id: 'app1', project_id: 'proj1' };

      const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
      assert.equal(begin.err, null);
      const patch = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
        client,
        edit_session_id: String(begin.res.edit_session_id || ''),
        base_version: String(begin.res.base_version || ''),
        session_revision: Number(begin.res.session_revision || 0),
        patch_mode: 'replace',
        patch_markdown: '# note\n\napi_key: sk-live-danger-token',
      });
      assert.equal(patch.err, null);

      const reviewed = invokeHubMemoryUnary(impl, 'LongtermMarkdownReview', {
        client,
        pending_change_id: String(patch.res.pending_change_id || ''),
        review_decision: 'approve',
        on_secret: 'deny',
      });
      assert.equal(reviewed.err, null);
      assert.equal(String(reviewed.res.status || ''), 'rejected');

      const ext = parseLatestAuditExtByType(db, 'memory.longterm_markdown.reviewed');
      assert.ok(ext && typeof ext === 'object');
      assert.ok(ext.metrics && typeof ext.metrics === 'object');
      assert.equal(ext.metrics.schema_version, MEMORY_METRICS_SCHEMA_VERSION);
      assert.equal(ext.metrics.event_kind, 'memory.longterm_markdown.reviewed');
      assert.equal(ext.metrics.job_type, 'markdown_review');
      assert.equal(ext.metrics.scope.kind, 'project');
      assert.equal(ext.metrics.security.blocked, true);
      assert.ok(['deny', 'deny_after_sanitize', 'blocked', 'unknown'].includes(String(ext.metrics.security.deny_code || '')));
      assert.equal(typeof ext.metrics.security.deny_reason, 'string');
      assert.equal(ext.metrics.quality.auto_rejected, true);
      assert.equal(typeof ext.metrics.markdown, 'undefined');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run('W5-02/review sanitize path marks downgraded metrics', () => {
  const runtimeBaseDir = makeTmp('runtime_sanitize');
  const dbPath = makeTmp('db_sanitize', '.db');
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
        key: 'workflow.note',
        value: 'normal note',
        pinned: 0,
      });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = { device_id: 'dev1', user_id: 'user1', app_id: 'app1', project_id: 'proj1' };

      const begin = invokeHubMemoryUnary(impl, 'LongtermMarkdownBeginEdit', { client, scope: 'project' });
      assert.equal(begin.err, null);
      const patch = invokeHubMemoryUnary(impl, 'LongtermMarkdownApplyPatch', {
        client,
        edit_session_id: String(begin.res.edit_session_id || ''),
        base_version: String(begin.res.base_version || ''),
        session_revision: Number(begin.res.session_revision || 0),
        patch_mode: 'replace',
        patch_markdown: '# note\n\nAuthorization: Bearer abcdefghijklmnopqrstuvwxyzz',
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

      const ext = parseLatestAuditExtByType(db, 'memory.longterm_markdown.reviewed');
      assert.ok(ext && typeof ext === 'object');
      assert.ok(ext.metrics && typeof ext.metrics === 'object');
      assert.equal(ext.metrics.security.blocked, false);
      assert.equal(ext.metrics.security.downgraded, true);
      assert.equal(String(ext.metrics.security.deny_code || ''), '');
      assert.equal(Number(ext.metrics.quality.redacted_count || 0) > 0, true);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

await runAsync('W5-02/ai.generate denied metrics align with audit error_code and scope aggregation', async () => {
  const runtimeBaseDir = makeTmp('runtime3');
  const dbPath = makeTmp('db3', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const request_id = `rid_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      const call = {
        request: {
          request_id,
          model_id: 'nonexistent/model',
          messages: [{ role: 'user', content: 'hello' }],
          client: {
            device_id: 'dev1',
            user_id: 'user1',
            app_id: 'app1',
            project_id: 'proj1',
          },
        },
        metadata: {
          get() {
            return [];
          },
        },
        write() {
          // ignored
        },
        end() {
          // ignored
        },
        on() {
          // ignored
        },
      };
      await impl.HubAI.Generate(call);

      const rows = db.listAuditEvents({ device_id: 'dev1' }) || [];
      const denied = rows.find((r) =>
        String(r.event_type || '') === 'ai.generate.denied'
        && String(r.request_id || '') === request_id
      );
      assert.ok(denied);
      const ext = JSON.parse(String(denied.ext_json || '{}'));
      assert.ok(ext.metrics && typeof ext.metrics === 'object');
      assert.equal(ext.metrics.schema_version, MEMORY_METRICS_SCHEMA_VERSION);
      assert.equal(ext.metrics.event_kind, 'ai.generate.denied');
      assert.equal(ext.metrics.job_type, 'ai_generate');
      assert.equal(ext.metrics.scope.kind, 'project');
      assert.equal(ext.metrics.scope.project_id, 'proj1');
      assert.equal(ext.metrics.security.blocked, true);
      assert.equal(ext.metrics.security.deny_code, String(denied.error_code || ''));
      assert.equal(ext.metrics.security.deny_reason, String(denied.error_code || ''));
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

await runAsync('W5-03/remote export gate error path blocks paid generate with consistent audit fields', async () => {
  const runtimeBaseDir = makeTmp('runtime_w5_03_error');
  const dbPath = makeTmp('db_w5_03_error', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(
    {
      ...baseEnv(runtimeBaseDir),
      HUB_REMOTE_EXPORT_ON_BLOCK: 'error',
      HUB_REMOTE_EXPORT_SECRET_MODE: 'deny',
    },
    async () => {
      const db = new HubDB({ dbPath });
      try {
        seedPaidGrant(db, {
          device_id: 'dev1',
          user_id: 'user1',
          app_id: 'app1',
          project_id: 'proj1',
          model_id: 'openai/gpt-4.1',
        });

        const impl = makeServices({ db, bus: new HubEventBus() });
        const request_id = `rid_w5_03_err_${Date.now()}_${Math.random().toString(16).slice(2)}`;
        const call = {
          request: {
            request_id,
            model_id: 'openai/gpt-4.1',
            messages: [{ role: 'user', content: 'api_key: sk-live-abcdef1234567890' }],
            client: {
              device_id: 'dev1',
              user_id: 'user1',
              app_id: 'app1',
              project_id: 'proj1',
            },
          },
          metadata: {
            get() {
              return [];
            },
          },
          write() {
            // ignored
          },
          end() {
            // ignored
          },
          on() {
            // ignored
          },
        };

        await impl.HubAI.Generate(call);

        const rows = db.listAuditEvents({ device_id: 'dev1' }) || [];
        const denied = rows.find((r) =>
          String(r.event_type || '') === 'ai.generate.denied'
          && String(r.request_id || '') === request_id
        );
        assert.ok(denied);
        const ext = JSON.parse(String(denied.ext_json || '{}'));
        assert.equal(ext.export_class, 'prompt_bundle');
        assert.equal(ext.job_sensitivity, 'secret');
        assert.equal(ext.gate_reason, 'credential_finding');
        assert.equal(ext.blocked, true);
        assert.equal(ext.downgraded, false);
        assert.ok(ext.metrics && typeof ext.metrics === 'object');
        assert.equal(ext.metrics.security.blocked, true);
        assert.equal(ext.metrics.security.deny_code, String(denied.error_code || ''));

        const downgraded = rows.find((r) =>
          String(r.event_type || '') === 'ai.generate.downgraded_to_local'
          && String(r.request_id || '') === request_id
        );
        assert.equal(!!downgraded, false);
      } finally {
        db.close();
        cleanupDbArtifacts(dbPath);
        try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
      }
    }
  );
});

await runAsync('W5-03/remote export gate downgrade path keeps final failed audit local-consistent', async () => {
  const runtimeBaseDir = makeTmp('runtime_w5_03_downgrade');
  const dbPath = makeTmp('db_w5_03_downgrade', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(
    {
      ...baseEnv(runtimeBaseDir),
      HUB_REMOTE_EXPORT_ON_BLOCK: 'downgrade_to_local',
      HUB_REMOTE_EXPORT_SECRET_MODE: 'deny',
      HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '120',
    },
    async () => {
      const db = new HubDB({ dbPath });
      try {
        seedPaidGrant(db, {
          device_id: 'dev1',
          user_id: 'user1',
          app_id: 'app1',
          project_id: 'proj1',
          model_id: 'openai/gpt-4.1',
        });

        const impl = makeServices({ db, bus: new HubEventBus() });
        const request_id = `rid_w5_03_down_${Date.now()}_${Math.random().toString(16).slice(2)}`;
        const call = {
          request: {
            request_id,
            model_id: 'openai/gpt-4.1',
            messages: [{ role: 'user', content: 'Please export [private]payment pin 7788[/private]' }],
            client: {
              device_id: 'dev1',
              user_id: 'user1',
              app_id: 'app1',
              project_id: 'proj1',
            },
          },
          metadata: {
            get() {
              return [];
            },
          },
          write() {
            // ignored
          },
          end() {
            // ignored
          },
          on() {
            // ignored
          },
        };

        await impl.HubAI.Generate(call);

        const rows = db.listAuditEvents({ device_id: 'dev1' }) || [];
        const downgraded = rows.find((r) =>
          String(r.event_type || '') === 'ai.generate.downgraded_to_local'
          && String(r.request_id || '') === request_id
        );
        assert.ok(downgraded);
        const ext = JSON.parse(String(downgraded.ext_json || '{}'));
        assert.equal(ext.export_class, 'prompt_bundle');
        assert.equal(ext.job_sensitivity, 'secret');
        assert.equal(ext.blocked, true);
        assert.equal(ext.downgraded, true);
        assert.equal(typeof ext.downgraded_model_id, 'string');
        assert.equal(ext.downgraded_model_id.length > 0, true);
        assert.ok(ext.metrics && typeof ext.metrics === 'object');
        assert.equal(ext.metrics.event_kind, 'ai.generate.downgraded_to_local');
        assert.equal(ext.metrics.security.blocked, true);
        assert.equal(ext.metrics.security.downgraded, true);
        assert.equal(ext.metrics.security.deny_code, String(downgraded.error_code || ''));

        const failed = rows.find((r) =>
          String(r.event_type || '') === 'ai.generate.failed'
          && String(r.request_id || '') === request_id
        );
        assert.ok(failed);
        assert.equal(String(failed.model_id || ''), String(ext.downgraded_model_id || ''));
        assert.equal(Number(failed.network_allowed || 0), 0);
        const failedExt = JSON.parse(String(failed.ext_json || '{}'));
        assert.ok(failedExt.metrics && typeof failedExt.metrics === 'object');
        assert.equal(failedExt.metrics.event_kind, 'ai.generate.failed');
        assert.equal(failedExt.metrics.channel, 'local');
        assert.equal(failedExt.metrics.remote_mode, false);
        assert.equal(failedExt.metrics.scope.project_id, 'proj1');
        assert.equal(failedExt.metrics.security.blocked, false);
        assert.equal(failedExt.metrics.security.deny_code, 'runtime_failed');
      } finally {
        db.close();
        cleanupDbArtifacts(dbPath);
        try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
      }
    }
  );
});

await runAsync('W5-03/remote export gate downgrade path keeps final completed audit local-consistent', async () => {
  const runtimeBaseDir = makeTmp('runtime_w5_03_down_completed');
  const dbPath = makeTmp('db_w5_03_down_completed', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(
    {
      ...baseEnv(runtimeBaseDir),
      HUB_REMOTE_EXPORT_ON_BLOCK: 'downgrade_to_local',
      HUB_REMOTE_EXPORT_SECRET_MODE: 'deny',
      HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '1500',
    },
    async () => {
      const db = new HubDB({ dbPath });
      try {
        seedPaidGrant(db, {
          device_id: 'dev1',
          user_id: 'user1',
          app_id: 'app1',
          project_id: 'proj1',
          model_id: 'openai/gpt-4.1',
        });

        const impl = makeServices({ db, bus: new HubEventBus() });
        const request_id = `rid_w5_03_down_ok_${Date.now()}_${Math.random().toString(16).slice(2)}`;

        // Inject a synthetic local-runtime success response so we can assert final completed audit semantics.
        setTimeout(() => {
          try {
            const respPath = responsePathForRequest(runtimeBaseDir, request_id);
            fs.mkdirSync(path.dirname(respPath), { recursive: true });
            const startedAtSec = Date.now() / 1000.0;
            const lines = [
              JSON.stringify({ type: 'start', model_id: 'mlx/qwen2.5-7b-instruct', started_at: startedAtSec }),
              JSON.stringify({ type: 'delta', seq: 1, text: 'ok' }),
              JSON.stringify({ type: 'done', ok: true, reason: 'eos', elapsed_ms: 20, promptTokens: 12, generationTokens: 4 }),
            ];
            fs.appendFileSync(respPath, `${lines.join('\n')}\n`, 'utf8');
          } catch {
            // ignore
          }
        }, 80);

        const call = {
          request: {
            request_id,
            model_id: 'openai/gpt-4.1',
            messages: [{ role: 'user', content: 'Please export [private]secret note[/private]' }],
            client: {
              device_id: 'dev1',
              user_id: 'user1',
              app_id: 'app1',
              project_id: 'proj1',
            },
          },
          metadata: {
            get() {
              return [];
            },
          },
          write() {
            // ignored
          },
          end() {
            // ignored
          },
          on() {
            // ignored
          },
        };

        await impl.HubAI.Generate(call);

        const rows = db.listAuditEvents({ device_id: 'dev1' }) || [];
        const downgraded = rows.find((r) =>
          String(r.event_type || '') === 'ai.generate.downgraded_to_local'
          && String(r.request_id || '') === request_id
        );
        assert.ok(downgraded);
        const downgradedExt = JSON.parse(String(downgraded.ext_json || '{}'));

        const completed = rows.find((r) =>
          String(r.event_type || '') === 'ai.generate.completed'
          && String(r.request_id || '') === request_id
        );
        assert.ok(completed);
        assert.equal(String(completed.model_id || ''), String(downgradedExt.downgraded_model_id || ''));
        assert.equal(Number(completed.network_allowed || 0), 0);
        const completedExt = JSON.parse(String(completed.ext_json || '{}'));
        assert.ok(completedExt.metrics && typeof completedExt.metrics === 'object');
        assert.equal(completedExt.metrics.event_kind, 'ai.generate.completed');
        assert.equal(completedExt.metrics.channel, 'local');
        assert.equal(completedExt.metrics.remote_mode, false);
        assert.equal(completedExt.metrics.scope.project_id, 'proj1');
        assert.equal(completedExt.metrics.security.blocked, false);
        assert.equal(String(completedExt.metrics.security.deny_code || ''), '');
        assert.equal(Number(completedExt.metrics.cost.total_tokens || 0) > 0, true);

        const failed = rows.find((r) =>
          String(r.event_type || '') === 'ai.generate.failed'
          && String(r.request_id || '') === request_id
        );
        assert.equal(!!failed, false);
      } finally {
        db.close();
        cleanupDbArtifacts(dbPath);
        try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
      }
    }
  );
});
