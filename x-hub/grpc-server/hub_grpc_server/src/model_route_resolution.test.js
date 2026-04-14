import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  return Promise.resolve()
    .then(fn)
    .finally(() => {
      for (const [key, value] of previous.entries()) {
        if (value == null) delete process.env[key];
        else process.env[key] = value;
      }
    });
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `xhub_model_route_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_AUDIT_LEVEL: 'full_content',
    HUB_MEMORY_AT_REST_ENABLED: 'false',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '50',
  };
}

function writeClientsSnapshot(runtimeBaseDir, clients) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  fs.writeFileSync(
    path.join(runtimeBaseDir, 'hub_grpc_clients.json'),
    `${JSON.stringify({
      schema_version: 'hub_grpc_clients.v1',
      updated_at_ms: Date.now(),
      clients,
    }, null, 2)}\n`,
    'utf8'
  );
}

function insertModel(db, {
  model_id,
  name,
  kind = 'paid_online',
  backend = 'openai',
  context_length = 128000,
  requires_grant = 1,
  enabled = 1,
} = {}) {
  db.db.prepare(
    `INSERT OR REPLACE INTO models(model_id,name,kind,backend,context_length,requires_grant,enabled,updated_at_ms)
     VALUES(?,?,?,?,?,?,?,?)`
  ).run(
    String(model_id || '').trim(),
    String(name || model_id || '').trim(),
    String(kind || '').trim(),
    String(backend || '').trim(),
    Number(context_length || 0),
    Number(requires_grant || 0),
    Number(enabled || 0),
    Date.now()
  );
}

function makeClientCall({ request, token }) {
  const writes = [];
  let ended = false;
  return {
    request,
    writes,
    get ended() {
      return ended;
    },
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() === 'authorization') {
          return token ? [`Bearer ${token}`] : [];
        }
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

function lastErrorCode(call) {
  const last = [...(call?.writes || [])].reverse().find((item) => item?.error?.error?.code);
  return String(last?.error?.error?.code || '');
}

function lastGenerateError(call) {
  return [...(call?.writes || [])].reverse().find((item) => item?.error)?.error || null;
}

function makeApprovedTrustProfile({
  deviceId,
  deviceName,
  capabilities,
  paidModelPolicyMode = 'custom_selected_models',
  allowedModelIds = [],
  dailyTokenLimit = 500,
  singleRequestTokenLimit = 1,
}) {
  return {
    schema_version: 'hub.paired_terminal_trust_profile.v1',
    device_id: deviceId,
    device_name: deviceName,
    trust_mode: 'trusted_daily',
    mode: 'standard',
    state: 'off',
    capabilities,
    allowed_project_ids: [],
    allowed_workspace_roots: [],
    xt_binding_required: false,
    auto_grant_profile: '',
    device_permission_owner_ref: '',
    paid_model_policy: {
      schema_version: 'hub.paired_terminal_paid_model_policy.v1',
      mode: paidModelPolicyMode,
      allowed_model_ids: paidModelPolicyMode === 'custom_selected_models' ? allowedModelIds : [],
    },
    network_policy: {
      default_web_fetch_enabled: true,
    },
    budget_policy: {
      daily_token_limit: dailyTokenLimit,
      single_request_token_limit: singleRequestTokenLimit,
    },
    audit_ref: 'audit-model-route-resolution',
  };
}

async function invokeRequestGrant({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const call = makeClientCall({
    request: {
      request_id: `grant_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      capability: 'CAPABILITY_AI_GENERATE_PAID',
      model_id: 'gpt-5.4',
      reason: 'model route resolution test',
      requested_ttl_sec: 60,
      requested_token_cap: 1000,
      client: {
        device_id: clientEntry.device_id,
        user_id: clientEntry.user_id,
        app_id: 'xt-model-route-test',
      },
      ...requestOverrides,
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubGrants.RequestGrant(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeGenerate({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const call = makeClientCall({
    request: {
      request_id: `gen_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      model_id: 'gpt-5.4',
      max_tokens: 64,
      messages: [{ role: 'user', content: 'hello from model route resolution test' }],
      client: {
        device_id: clientEntry.device_id,
        user_id: clientEntry.user_id,
        app_id: 'xt-model-route-test',
        project_id: 'project-route-resolution',
      },
      ...requestOverrides,
    },
    token: clientEntry.token,
  });
  await impl.HubAI.Generate(call);
  return call;
}

await run('RequestGrant resolves suffix model id to canonical model id', async () => {
  const runtimeBaseDir = makeTmp('runtime_grant');
  const dbPath = makeTmp('db_grant', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      insertModel(db, { model_id: 'openai/gpt-5.4', name: 'GPT 5.4' });
      const clientEntry = {
        device_id: 'dev-grant',
        user_id: 'dev-grant',
        name: 'Grant Device',
        token: 'tok-grant',
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.paid'],
        policy_mode: 'legacy_grant',
      };
      const response = await invokeRequestGrant({ db, runtimeBaseDir, clientEntry });
      assert.equal(String(response?.decision || ''), 'GRANT_DECISION_APPROVED');
      assert.equal(String(response?.grant?.model_id || ''), 'openai/gpt-5.4');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await run('Generate resolves suffix model id before paid allowlist and budget checks', async () => {
  const runtimeBaseDir = makeTmp('runtime_generate');
  const dbPath = makeTmp('db_generate', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      insertModel(db, { model_id: 'openai/gpt-5.4', name: 'GPT 5.4' });
      const clientEntry = {
        device_id: 'dev-generate',
        user_id: 'dev-generate',
        name: 'Generate Device',
        token: 'tok-generate',
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId: 'dev-generate',
          deviceName: 'Generate Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          allowedModelIds: ['openai/gpt-5.4'],
          singleRequestTokenLimit: 1,
          dailyTokenLimit: 100,
        }),
      };

      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'device_single_request_token_exceeded');
      assert.equal(String(lastGenerateError(call)?.model_id || ''), 'openai/gpt-5.4');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
