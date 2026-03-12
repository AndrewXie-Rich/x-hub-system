import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { responsePathForRequest } from './local_runtime_ipc.js';
import { makeServices } from './services.js';

function runAsync(name, fn) {
  return fn()
    .then(() => {
      process.stdout.write(`ok - ${name}\n`);
    })
    .catch((error) => {
      process.stderr.write(`not ok - ${name}\n`);
      throw error;
    });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

async function withEnvAsync(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function makeTmp(label, suffix = '') {
  return path.join(os.tmpdir(), `mlx_compat_${label}_${Date.now()}_${Math.random().toString(16).slice(2)}${suffix}`);
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
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '500',
    HUB_MLX_RESPONSE_TIMEOUT_MS: '2000',
  };
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

function writeModelsState(runtimeBaseDir, models) {
  writeJson(path.join(runtimeBaseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models,
  });
}

function writeLegacyMLXStatus(runtimeBaseDir, { mlxOk = true, importError = '' } = {}) {
  const payload = {
    pid: 12345,
    updatedAt: Date.now() / 1000.0,
    mlxOk,
    runtimeVersion: 'legacy-mlx-test',
  };
  if (importError) payload.importError = importError;
  writeJson(path.join(runtimeBaseDir, 'ai_runtime_status.json'), payload);
}

function writeProviderAwareMLXStatus(runtimeBaseDir, { ok, importError = '' }) {
  writeJson(path.join(runtimeBaseDir, 'ai_runtime_status.json'), {
    schema_version: 'xhub.local_runtime_status.v2',
    pid: 12345,
    updatedAt: Date.now() / 1000.0,
    mlxOk: !!ok,
    runtimeVersion: 'legacy-mlx-test',
    providers: {
      mlx: {
        provider: 'mlx',
        ok: !!ok,
        reasonCode: ok ? 'ready' : 'import_error',
        runtimeVersion: 'legacy-mlx-test',
        availableTaskKinds: ok ? ['text_generate'] : [],
        loadedModels: [],
        deviceBackend: 'mps',
        updatedAt: Date.now() / 1000.0,
        importError,
      },
    },
  });
}

function makeGenerateCall({ request_id, model_id, message }) {
  const writes = [];
  let ended = false;
  return {
    request: {
      request_id,
      model_id,
      max_tokens: 24,
      messages: [{ role: 'user', content: message }],
      client: {
        device_id: 'dev1',
        user_id: 'user1',
        app_id: 'app1',
        project_id: 'proj1',
      },
    },
    writes,
    get ended() {
      return ended;
    },
    metadata: {
      get() {
        return [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:54321';
    },
    write(payload) {
      writes.push(payload);
    },
    end() {
      ended = true;
    },
    on() {
      // no-op
    },
  };
}

async function satisfyLocalRuntimeRequest(runtimeBaseDir, requestId, onRequest) {
  const reqPath = path.join(runtimeBaseDir, 'ai_requests', `req_${requestId}.json`);
  const respPath = responsePathForRequest(runtimeBaseDir, requestId);

  const deadline = Date.now() + 2000;
  while (Date.now() < deadline) {
    if (fs.existsSync(reqPath)) break;
    await sleep(20);
  }
  assert.equal(fs.existsSync(reqPath), true, 'expected runtime request file to be written');
  const req = JSON.parse(fs.readFileSync(reqPath, 'utf8'));
  onRequest(req);

  fs.mkdirSync(path.dirname(respPath), { recursive: true });
  const startedAt = Date.now() / 1000.0;
  const lines = [
    JSON.stringify({ type: 'start', req_id: requestId, model_id: String(req.model_id || ''), started_at: startedAt }),
    JSON.stringify({ type: 'delta', req_id: requestId, seq: 1, text: 'compat-ok' }),
    JSON.stringify({ type: 'done', req_id: requestId, ok: true, reason: 'eos', promptTokens: 7, generationTokens: 3 }),
  ];
  fs.writeFileSync(respPath, `${lines.join('\n')}\n`, 'utf8');
}

function auditRowsByRequestId(db, requestId) {
  return (db.listAuditEvents({ device_id: 'dev1' }) || []).filter(
    (row) => String(row.request_id || '') === String(requestId || '')
  );
}

await runAsync('LPR-W1-05/legacy MLX generate path remains compatible after local runtime generalization', async () => {
  const runtimeBaseDir = makeTmp('runtime_generate');
  const dbPath = makeTmp('db_generate', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      writeModelsState(runtimeBaseDir, [
        {
          id: 'mlx/qwen2.5-7b-instruct',
          name: 'Qwen Local',
          backend: 'mlx',
          modelPath: '/models/qwen',
          state: 'available',
        },
      ]);
      writeLegacyMLXStatus(runtimeBaseDir, { mlxOk: true });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const request_id = `rid_lpr_w105_generate_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      const call = makeGenerateCall({
        request_id,
        model_id: 'mlx/qwen2.5-7b-instruct',
        message: 'say hello locally',
      });

      const completer = satisfyLocalRuntimeRequest(runtimeBaseDir, request_id, (req) => {
        assert.equal(String(req.model_id || ''), 'mlx/qwen2.5-7b-instruct');
        assert.equal(String(req.task_type || ''), 'text_generate');
        assert.equal(String(req.type || ''), 'generate');
      });

      await impl.HubAI.Generate(call);
      await completer;

      assert.equal(call.ended, true);
      assert.ok(call.writes.some((item) => item?.start?.request_id === request_id));
      assert.ok(call.writes.some((item) => item?.delta?.text === 'compat-ok'));
      const done = call.writes.find((item) => item?.done?.request_id === request_id);
      assert.ok(done, 'expected done event');
      assert.equal(done.done.ok, true);

      const rows = auditRowsByRequestId(db, request_id);
      assert.ok(rows.some((row) => String(row.event_type || '') === 'ai.generate.completed'));
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

await runAsync('LPR-W1-05/provider-aware bridge still surfaces MLX import error without enqueueing runtime work', async () => {
  const runtimeBaseDir = makeTmp('runtime_import_error');
  const dbPath = makeTmp('db_import_error', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      writeModelsState(runtimeBaseDir, [
        {
          id: 'mlx/qwen2.5-7b-instruct',
          name: 'Qwen Local',
          backend: 'mlx',
          modelPath: '/models/qwen',
          state: 'available',
        },
      ]);
      writeProviderAwareMLXStatus(runtimeBaseDir, {
        ok: false,
        importError: 'missing_module:mlx_lm',
      });

      const impl = makeServices({ db, bus: new HubEventBus() });
      const request_id = `rid_lpr_w105_import_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      const call = makeGenerateCall({
        request_id,
        model_id: 'mlx/qwen2.5-7b-instruct',
        message: 'this should fail fast',
      });

      await impl.HubAI.Generate(call);

      const firstError = call.writes.find((item) => item?.error?.error?.code);
      assert.ok(firstError, 'expected local_provider_unavailable error');
      assert.equal(String(firstError.error.error.code || ''), 'local_provider_unavailable');
      assert.match(String(firstError.error.error.message || ''), /missing_module:mlx_lm/);
      assert.equal(call.ended, true);

      const reqPath = path.join(runtimeBaseDir, 'ai_requests', `req_${request_id}.json`);
      assert.equal(fs.existsSync(reqPath), false, 'runtime request should not be written when MLX provider is unavailable');

      const rows = auditRowsByRequestId(db, request_id);
      const denied = rows.find((row) => String(row.event_type || '') === 'ai.generate.denied');
      assert.ok(denied);
      assert.equal(String(denied.error_code || ''), 'local_provider_unavailable');
      const ext = JSON.parse(String(denied.ext_json || '{}'));
      assert.equal(String(ext.local_provider || ''), 'mlx');
      assert.equal(String(ext.provider_import_error || ''), 'missing_module:mlx_lm');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});
