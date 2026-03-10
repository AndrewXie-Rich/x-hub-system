import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices, resolvePaidModelRuntimeAccess } from './services.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

async function runAsync(name, fn) {
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
  for (const key of Object.keys(tempEnv)) {
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
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `xt_w328_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x55).toString('base64')}`;

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_AUDIT_LEVEL: 'full_content',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '100',
  };
}

function makeApprovedTrustProfile({
  deviceId,
  deviceName,
  capabilities,
  paidModelPolicyMode,
  allowedModelIds = [],
  defaultWebFetchEnabled = true,
  dailyTokenLimit = 500,
  singleRequestTokenLimit = 120,
  auditRef = 'audit-xt-w328',
}) {
  return {
    schema_version: 'hub.paired_terminal_trust_profile.v1',
    device_id: deviceId,
    device_name: deviceName,
    trust_mode: 'trusted_daily',
    capabilities,
    paid_model_policy: {
      schema_version: 'hub.paired_terminal_paid_model_policy.v1',
      mode: paidModelPolicyMode,
      allowed_model_ids: paidModelPolicyMode === 'custom_selected_models' ? allowedModelIds : [],
    },
    network_policy: {
      default_web_fetch_enabled: defaultWebFetchEnabled,
    },
    budget_policy: {
      daily_token_limit: dailyTokenLimit,
      single_request_token_limit: singleRequestTokenLimit,
    },
    audit_ref: auditRef,
  };
}

function writeClientsSnapshot(runtimeBaseDir, clients) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const snapshot = {
    schema_version: 'hub_grpc_clients.v1',
    updated_at_ms: Date.now(),
    clients,
  };
  fs.writeFileSync(
    path.join(runtimeBaseDir, 'hub_grpc_clients.json'),
    JSON.stringify(snapshot, null, 2) + '\n',
    'utf8'
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
      // no-op for targeted deny-path tests
    },
  };
}

function lastErrorCode(call) {
  const last = [...call.writes].reverse().find((item) => item?.error?.error?.code);
  return String(last?.error?.error?.code || '');
}

async function invokeGenerate({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const request = {
    request_id: `rid_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    model_id: 'openai/gpt-4.1',
    max_tokens: 32,
    messages: [{ role: 'user', content: 'hello from XT-W3-28' }],
    client: {
      device_id: clientEntry.device_id,
      user_id: clientEntry.user_id,
      app_id: 'xt-w328-test',
      project_id: 'proj-w328',
    },
    ...requestOverrides,
  };
  const call = makeClientCall({ request, token: clientEntry.token });
  await impl.HubAI.Generate(call);
  return call;
}

run('resolver emits all frozen deny codes', () => {
  const baseClient = {
    device_id: 'dev-resolver',
    name: 'Resolver Device',
    policy_mode: 'new_profile',
    trust_profile_present: true,
    paid_model_policy_mode: 'all_paid_models',
    paid_model_allowed_model_ids: [],
    daily_token_limit: 500,
    single_request_token_limit: 100,
    default_web_fetch_enabled: true,
  };

  const allowed = resolvePaidModelRuntimeAccess({
    runtimeClient: baseClient,
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
    requestedTotalTokensEstimate: 80,
    usedTokensToday: 120,
  });
  assert.equal(allowed.allow, true);

  const disabled = resolvePaidModelRuntimeAccess({
    runtimeClient: { ...baseClient, paid_model_policy_mode: 'off' },
    capabilityAllowed: false,
    modelId: 'openai/gpt-4.1',
  });
  assert.equal(disabled.deny_code, 'device_paid_model_disabled');

  const notAllowed = resolvePaidModelRuntimeAccess({
    runtimeClient: {
      ...baseClient,
      paid_model_policy_mode: 'custom_selected_models',
      paid_model_allowed_model_ids: ['anthropic/claude-3-7-sonnet'],
    },
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
  });
  assert.equal(notAllowed.deny_code, 'device_paid_model_not_allowed');

  const singleExceeded = resolvePaidModelRuntimeAccess({
    runtimeClient: baseClient,
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
    requestedTotalTokensEstimate: 140,
    usedTokensToday: 0,
  });
  assert.equal(singleExceeded.deny_code, 'device_single_request_token_exceeded');

  const dailyExceeded = resolvePaidModelRuntimeAccess({
    runtimeClient: baseClient,
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
    requestedTotalTokensEstimate: 30,
    usedTokensToday: 490,
  });
  assert.equal(dailyExceeded.deny_code, 'device_daily_token_budget_exceeded');

  const legacy = resolvePaidModelRuntimeAccess({
    runtimeClient: null,
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
  });
  assert.equal(legacy.deny_code, 'legacy_grant_flow_required');
});

run('db metering tracks device/model/day usage summary fields', () => {
  const runtimeBaseDir = makeTmp('runtime_db');
  const dbPath = makeTmp('db_usage', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const dayBucket = '2026-03-08';
      db.recordTerminalModelUsageDaily({
        device_id: 'dev-usage',
        device_name: 'Usage Device',
        model_id: 'openai/gpt-4.1',
        day_bucket: dayBucket,
        prompt_tokens: 11,
        completion_tokens: 7,
        total_tokens: 18,
        last_used_at_ms: 1000,
      });
      db.recordTerminalModelUsageDaily({
        device_id: 'dev-usage',
        device_name: 'Usage Device',
        model_id: 'openai/gpt-4.1',
        day_bucket: dayBucket,
        prompt_tokens: 9,
        completion_tokens: 3,
        total_tokens: 12,
        last_used_at_ms: 2000,
      });
      db.recordTerminalModelBlockedDaily({
        device_id: 'dev-usage',
        device_name: 'Usage Device',
        model_id: 'openai/gpt-4.1',
        day_bucket: dayBucket,
        last_blocked_at_ms: 2500,
        last_blocked_reason: 'device_paid_model_not_allowed',
        last_deny_code: 'device_paid_model_not_allowed',
      });

      const rows = db.listTerminalModelUsageDaily({ device_id: 'dev-usage', day_bucket: dayBucket, limit: 5 });
      assert.equal(rows.length, 1);
      assert.equal(rows[0].device_id, 'dev-usage');
      assert.equal(rows[0].device_name, 'Usage Device');
      assert.equal(rows[0].model_id, 'openai/gpt-4.1');
      assert.equal(rows[0].day_bucket, dayBucket);
      assert.equal(rows[0].total_tokens, 30);
      assert.equal(rows[0].request_count, 2);
      assert.equal(rows[0].blocked_count, 1);

      const summary = db.getTerminalUsageSummaryDaily({ device_id: 'dev-usage', day_bucket: dayBucket });
      assert.equal(summary.device_id, 'dev-usage');
      assert.equal(summary.day_bucket, dayBucket);
      assert.equal(summary.total_tokens, 30);
      assert.equal(summary.request_count, 2);
      assert.equal(summary.blocked_count, 1);
      assert.equal(summary.top_model, 'openai/gpt-4.1');
      assert.equal(summary.last_deny_code, 'device_paid_model_not_allowed');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_paid_model_disabled for new-profile off mode', async () => {
  const runtimeBaseDir = makeTmp('runtime_disabled');
  const dbPath = makeTmp('db_disabled', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-disabled';
      const token = 'tok-disabled';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Disabled Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Disabled Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local'],
          paidModelPolicyMode: 'off',
        }),
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'device_paid_model_disabled');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_paid_model_not_allowed and writes dashboard snapshot', async () => {
  const runtimeBaseDir = makeTmp('runtime_not_allowed');
  const dbPath = makeTmp('db_not_allowed', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-not-allowed';
      const token = 'tok-not-allowed';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Allowlist Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Allowlist Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          paidModelPolicyMode: 'custom_selected_models',
          allowedModelIds: ['anthropic/claude-3-7-sonnet'],
          dailyTokenLimit: 500,
          singleRequestTokenLimit: 128,
        }),
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'device_paid_model_not_allowed');

      const snapshot = JSON.parse(fs.readFileSync(path.join(runtimeBaseDir, 'grpc_devices_status.json'), 'utf8'));
      const device = (snapshot.devices || []).find((item) => item.device_id === deviceId);
      assert.ok(device);
      assert.equal(device.paid_model_policy_mode, 'custom_selected_models');
      assert.equal(device.daily_token_limit, 500);
      assert.equal(device.remaining_daily_token_budget, 500);
      assert.equal(device.last_deny_code, 'device_paid_model_not_allowed');
      assert.ok(Array.isArray(device.model_breakdown));
      assert.equal(device.model_breakdown[0].device_id, deviceId);
      assert.equal(device.model_breakdown[0].model_id, 'openai/gpt-4.1');
      assert.equal(device.model_breakdown[0].blocked_count, 1);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_single_request_token_exceeded for trusted profile budget gate', async () => {
  const runtimeBaseDir = makeTmp('runtime_single');
  const dbPath = makeTmp('db_single', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-single-budget';
      const token = 'tok-single-budget';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Single Budget Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Single Budget Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
          paidModelPolicyMode: 'all_paid_models',
          dailyTokenLimit: 500,
          singleRequestTokenLimit: 8,
        }),
      };
      const call = await invokeGenerate({
        db,
        runtimeBaseDir,
        clientEntry,
        requestOverrides: {
          max_tokens: 32,
          messages: [{ role: 'user', content: 'single request should exceed budget' }],
        },
      });
      assert.equal(lastErrorCode(call), 'device_single_request_token_exceeded');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_daily_token_budget_exceeded when usage summary is near cap', async () => {
  const runtimeBaseDir = makeTmp('runtime_daily');
  const dbPath = makeTmp('db_daily', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const dayBucket = '2026-03-08';
      db.recordTerminalModelUsageDaily({
        device_id: 'dev-daily-budget',
        device_name: 'Daily Budget Device',
        model_id: 'openai/gpt-4.1',
        day_bucket: dayBucket,
        prompt_tokens: 220,
        completion_tokens: 220,
        total_tokens: 440,
        last_used_at_ms: Date.now(),
      });
      const deviceId = 'dev-daily-budget';
      const token = 'tok-daily-budget';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Daily Budget Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Daily Budget Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
          paidModelPolicyMode: 'all_paid_models',
          dailyTokenLimit: 450,
          singleRequestTokenLimit: 64,
        }),
      };
      const call = await invokeGenerate({
        db,
        runtimeBaseDir,
        clientEntry,
        requestOverrides: {
          created_at_ms: Date.parse('2026-03-08T12:00:00Z'),
          max_tokens: 32,
          messages: [{ role: 'user', content: 'daily budget should be exceeded' }],
        },
      });
      assert.equal(lastErrorCode(call), 'device_daily_token_budget_exceeded');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns legacy_grant_flow_required for legacy paired device', async () => {
  const runtimeBaseDir = makeTmp('runtime_legacy');
  const dbPath = makeTmp('db_legacy', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-legacy';
      const token = 'tok-legacy';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Legacy Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
        policy_mode: 'legacy_grant',
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'legacy_grant_flow_required');
      assert.equal(lastErrorCode(call) === 'grant_required', false);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
