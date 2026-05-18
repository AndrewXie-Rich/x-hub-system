import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import {
  addProviderKey,
  invalidateProviderKeyCache,
} from './provider_key_store.js';

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
  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  };
  for (const [key, value] of Object.entries(tempEnv)) {
    previous.set(key, process.env[key]);
    if (value == null) delete process.env[key];
    else process.env[key] = String(value);
  }
  try {
    const result = fn();
    if (result && typeof result.then === 'function') {
      return result.finally(restore);
    }
    restore();
    return result;
  } catch (error) {
    restore();
    throw error;
  }
}

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function writeJsonAtomic(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmp = `${filePath}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  fs.writeFileSync(tmp, `${JSON.stringify(obj, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, filePath);
}

function readJsonSafe(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function bridgePaths(baseDir) {
  return {
    statusPath: path.join(baseDir, 'bridge_status.json'),
    reqDir: path.join(baseDir, 'bridge_requests'),
    respDir: path.join(baseDir, 'bridge_responses'),
    commandsDir: path.join(baseDir, 'bridge_commands'),
  };
}

function startFakeBridge({ bridgeBaseDir, responseText = 'ok', pollMs = 10 } = {}) {
  const paths = bridgePaths(bridgeBaseDir);
  fs.mkdirSync(paths.reqDir, { recursive: true });
  fs.mkdirSync(paths.respDir, { recursive: true });
  fs.mkdirSync(paths.commandsDir, { recursive: true });

  const seen = new Set();
  const requests = [];
  const writeStatus = () => {
    writeJsonAtomic(paths.statusPath, {
      schema_version: 'xhub.bridge.status.v1',
      pid: process.pid,
      updatedAt: Date.now() / 1000,
      enabledUntil: Date.now() / 1000 + 3600,
    });
  };
  const scan = () => {
    let files = [];
    try {
      files = fs.readdirSync(paths.reqDir);
    } catch {
      return;
    }
    for (const file of files) {
      if (!file.startsWith('req_') || !file.endsWith('.json')) continue;
      const filePath = path.join(paths.reqDir, file);
      const req = readJsonSafe(filePath);
      const reqId = String(req?.req_id || req?.request_id || '').trim();
      if (!reqId || seen.has(reqId)) continue;
      seen.add(reqId);
      requests.push(req);
      if (String(req?.type || '') !== 'ai_generate') continue;
      writeJsonAtomic(path.join(paths.respDir, `resp_${reqId}.json`), {
        ok: true,
        status: 200,
        text: responseText,
        usage: {
          prompt_tokens: 4,
          completion_tokens: 2,
          total_tokens: 6,
        },
      });
    }
  };

  writeStatus();
  const statusTimer = setInterval(writeStatus, 250);
  const scanTimer = setInterval(scan, Math.max(5, Number(pollMs || 10)));
  if (typeof statusTimer.unref === 'function') statusTimer.unref();
  if (typeof scanTimer.unref === 'function') scanTimer.unref();

  return {
    requests,
    stop() {
      clearInterval(statusTimer);
      clearInterval(scanTimer);
    },
  };
}

function writeClientsSnapshot(runtimeBaseDir, clients) {
  writeJsonAtomic(path.join(runtimeBaseDir, 'hub_grpc_clients.json'), {
    schema_version: 'hub_grpc_clients.v2',
    updated_at_ms: Date.now(),
    clients,
  });
}

function insertPaidModel(db, modelId) {
  db.db.prepare(
    `INSERT OR REPLACE INTO models(model_id,name,kind,backend,context_length,requires_grant,enabled,updated_at_ms)
     VALUES(?,?,?,?,?,?,?,?)`
  ).run(
    modelId,
    'Rust Provider Observe Generate Hook Test',
    'paid_online',
    'openai',
    128000,
    1,
    1,
    Date.now()
  );
}

function makeClientEntry(modelId, options = {}) {
  const capabilities = ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'];
  const allowedModelIds = Array.isArray(options.allowedModelIds) && options.allowedModelIds.length > 0
    ? options.allowedModelIds
    : [modelId];
  return {
    device_id: 'dev-rust-provider-observe',
    user_id: 'user-rust-provider-observe',
    name: 'Rust Provider Observe Test',
    token: 'tok-rust-provider-observe',
    enabled: true,
    capabilities,
    policy_mode: 'new_profile',
    approved_trust_profile: {
      schema_version: 'hub.paired_terminal_trust_profile.v1',
      device_id: 'dev-rust-provider-observe',
      device_name: 'Rust Provider Observe Test',
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
        mode: 'custom_selected_models',
        allowed_model_ids: allowedModelIds,
      },
      network_policy: {
        default_web_fetch_enabled: true,
      },
      budget_policy: {
        daily_token_limit: 100000,
        single_request_token_limit: 100000,
      },
      audit_ref: 'audit-rust-provider-observe-generate-hook-test',
    },
  };
}

function makeGenerateCall({ request, token }) {
  const writes = [];
  const handlers = new Map();
  let ended = false;
  return {
    request,
    writes,
    get ended() {
      return ended;
    },
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() !== 'authorization') return [];
        return token ? [`Bearer ${token}`] : [];
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
    on(event, handler) {
      const key = String(event || '');
      if (!key || typeof handler !== 'function') return this;
      const list = handlers.get(key) || [];
      list.push(handler);
      handlers.set(key, list);
      return this;
    },
  };
}

function summarizeGenerate(call) {
  const writes = Array.isArray(call?.writes) ? call.writes : [];
  const done = [...writes].reverse().find((item) => item?.done)?.done || null;
  const error = [...writes].reverse().find((item) => item?.error)?.error || null;
  const deltas = writes.filter((item) => item?.delta);
  return {
    ended: call?.ended === true,
    done_ok: done?.ok === true,
    done_reason: String(done?.reason || ''),
    error_code: String(error?.error?.code || error?.code || ''),
    delta_text: deltas.map((item) => String(item?.delta?.text || '')).join(''),
  };
}

async function withTimeout(promise, timeoutMs, label) {
  let timer = null;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function waitForAuditEvent(db, { requestId, eventType, timeoutMs = 1000 } = {}) {
  const started = Date.now();
  while (Date.now() - started <= timeoutMs) {
    const row = (db.listAuditEvents({ request_id: requestId }) || [])
      .find((item) => String(item?.event_type || '') === String(eventType || ''));
    if (row) return row;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(`audit event ${eventType} not found for ${requestId}`);
}

await run('HubAI.Generate candidate audits Rust provider/model routes without Bridge payload changes', async () => {
  const root = makeTempDir('xhub-rust-provider-observe-generate-');
  const runtimeBaseDir = path.join(root, 'runtime');
  const bridgeBaseDir = path.join(root, 'bridge');
  const dbPath = path.join(root, 'hub.sqlite3');
  const modelId = 'gpt-4o';
  let db = null;
  let fakeBridge = null;
  invalidateProviderKeyCache();

  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_BRIDGE_BASE_DIR: bridgeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_AUDIT_LEVEL: 'full_content',
    HUB_MEMORY_AT_REST_ENABLED: 'false',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '50',
    HUB_BRIDGE_AI_TIMEOUT_SEC: '2',
    HUB_PAID_AI_QUEUE_TIMEOUT_MS: '500',
    XHUB_RUST_SCHEDULER_AUTHORITY: null,
    XHUB_RUST_SCHEDULER_STATUS_READ: null,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE: null,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: null,
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: null,
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE: null,
  }, async () => {
    try {
      fs.mkdirSync(runtimeBaseDir, { recursive: true });
      fs.mkdirSync(bridgeBaseDir, { recursive: true });
      db = new HubDB({ dbPath });
      insertPaidModel(db, modelId);
      const clientEntry = makeClientEntry(modelId);
      writeClientsSnapshot(runtimeBaseDir, [clientEntry]);

      const addResult = addProviderKey(runtimeBaseDir, {
        provider: 'openai',
        api_key: 'sk-node-selected-provider-key',
        auth_type: 'api_key',
        models: [modelId],
        base_url: 'https://api.openai.com',
      });
      assert.equal(addResult.ok, true);
      fakeBridge = startFakeBridge({ bridgeBaseDir, responseText: 'bridge response ok' });

      const observeCalls = [];
      const candidateCalls = [];
      const modelRouteCandidateCalls = [];
      const providerRouteAuthorityBridge = {
        config: {
          candidateEnabled: true,
        },
        observeRoute(input) {
          observeCalls.push(input);
          return new Promise(() => {});
        },
        candidateRoute(input) {
          candidateCalls.push(input);
          return Promise.resolve({
            ok: true,
            used: true,
            fallback: false,
            selected: true,
            selectedAccountKey: addResult.account_key,
            decision: {
              requestedProvider: 'openai',
              requestedModelId: modelId,
              resolvedProvider: 'openai',
              strategy: 'fill-first',
              selectionScope: 'openai::gpt-4o',
              selectedAccountKey: addResult.account_key,
              fallbackReasonCode: '',
              availableCount: 1,
              totalCount: 1,
              candidates: [],
            },
          });
        },
      };
      const modelRouteAuthorityBridge = {
        config: {
          candidateEnabled: true,
        },
        candidateRoute(input) {
          modelRouteCandidateCalls.push(input);
          return Promise.resolve({
            ok: true,
            used: true,
            fallback: false,
            selected: true,
            selectedModelId: modelId,
            selectedRouteKind: 'remote',
            decision: {
              requestedTaskType: 'text.generate',
              requestedModelId: modelId,
              requiredCapabilities: ['text.generate'],
              privacyMode: 'remote-only',
              costPreference: 'balanced',
              selectedRouteKind: 'remote',
              selectedModelId: modelId,
              blockingReasonCode: '',
              remoteCandidateCount: 1,
              localCandidateCount: 0,
            },
          });
        },
      };
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        providerRouteAuthorityBridge,
        modelRouteAuthorityBridge,
      });
      const call = makeGenerateCall({
        token: clientEntry.token,
        request: {
          request_id: 'gen_provider_observe_hook',
          model_id: modelId,
          max_tokens: 32,
          temperature: 0.1,
          top_p: 0.95,
          messages: [{ role: 'user', content: 'hello from provider observe hook test' }],
          client: {
            device_id: clientEntry.device_id,
            user_id: clientEntry.user_id,
            app_id: 'xt-provider-observe-test',
            project_id: 'project-provider-observe-test',
          },
        },
      });

      await withTimeout(impl.HubAI.Generate(call), 1500, 'HubAI.Generate');
      const summary = summarizeGenerate(call);
      assert.equal(summary.ended, true);
      assert.equal(summary.done_ok, true);
      assert.equal(summary.done_reason, 'eos');
      assert.equal(summary.error_code, '');
      assert.match(summary.delta_text, /bridge response ok/);

      assert.equal(observeCalls.length, 0);
      assert.equal(candidateCalls.length, 1);
      assert.equal(candidateCalls[0].runtimeBaseDir, runtimeBaseDir);
      assert.equal(candidateCalls[0].modelId, modelId);
      assert.equal(candidateCalls[0].provider, 'openai');
      assert.equal(candidateCalls[0].nodeAccountKey, addResult.account_key);
      assert.equal(modelRouteCandidateCalls.length, 1);
      assert.equal(modelRouteCandidateCalls[0].runtimeBaseDir, runtimeBaseDir);
      assert.equal(modelRouteCandidateCalls[0].taskType, 'text_generate');
      assert.equal(modelRouteCandidateCalls[0].modelId, modelId);
      assert.deepEqual(modelRouteCandidateCalls[0].requiredCapabilities, ['text.generate']);
      assert.equal(modelRouteCandidateCalls[0].privacyMode, 'remote-only');
      assert.equal(modelRouteCandidateCalls[0].nodeModelId, modelId);
      assert.equal(modelRouteCandidateCalls[0].nodeRouteKind, 'remote');

      const candidateAudit = await waitForAuditEvent(db, {
        requestId: 'gen_provider_observe_hook',
        eventType: 'ai.generate.provider_route_candidate',
      });
      assert.equal(candidateAudit.ok, 1);
      assert.equal(candidateAudit.error_code, null);
      const ext = JSON.parse(candidateAudit.ext_json || '{}');
      assert.equal(ext.schema_version, 'xhub.rust_provider_route_candidate.audit.v1');
      assert.equal(ext.node.selected_account, addResult.account_key);
      assert.equal(ext.rust.selected_account, addResult.account_key);
      assert.equal(ext.match.selected_account_match, true);
      assert.equal(JSON.stringify(ext).includes('sk-node-selected-provider-key'), false);

      const modelRouteAudit = await waitForAuditEvent(db, {
        requestId: 'gen_provider_observe_hook',
        eventType: 'ai.generate.model_route_candidate',
      });
      assert.equal(modelRouteAudit.ok, 1);
      assert.equal(modelRouteAudit.error_code, null);
      const modelRouteExt = JSON.parse(modelRouteAudit.ext_json || '{}');
      assert.equal(modelRouteExt.schema_version, 'xhub.rust_model_route_candidate.audit.v1');
      assert.equal(modelRouteExt.node.selected_model_id, modelId);
      assert.equal(modelRouteExt.node.selected_route_kind, 'remote');
      assert.equal(modelRouteExt.rust.selected_model_id, modelId);
      assert.equal(modelRouteExt.rust.selected_route_kind, 'remote');
      assert.equal(modelRouteExt.match.selected_model_match, true);
      assert.equal(modelRouteExt.match.route_kind_match, true);
      assert.equal(JSON.stringify(modelRouteExt).includes('sk-node-selected-provider-key'), false);

      assert.equal(fakeBridge.requests.length, 1);
      const bridgeRequest = fakeBridge.requests[0];
      assert.equal(bridgeRequest.type, 'ai_generate');
      assert.equal(bridgeRequest.model_id, modelId);
      assert.equal(bridgeRequest.provider_key?.account_key, addResult.account_key);
      assert.equal(bridgeRequest.provider_key?.provider, 'openai');
      assert.equal(bridgeRequest.provider_key?.base_url, 'https://api.openai.com');
    } finally {
      if (fakeBridge) fakeBridge.stop();
      if (db) db.close();
  }
});

await run('HubAI.Generate production authority applies Rust selected model and provider account', async () => {
  const root = makeTempDir('xhub-rust-provider-production-generate-');
  const runtimeBaseDir = path.join(root, 'runtime');
  const bridgeBaseDir = path.join(root, 'bridge');
  const dbPath = path.join(root, 'hub.sqlite3');
  const requestedModelId = 'gpt-4o';
  const selectedModelId = 'gpt-4.1';
  let db = null;
  let fakeBridge = null;
  invalidateProviderKeyCache();

  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_BRIDGE_BASE_DIR: bridgeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_AUDIT_LEVEL: 'full_content',
    HUB_MEMORY_AT_REST_ENABLED: 'false',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '50',
    HUB_BRIDGE_AI_TIMEOUT_SEC: '2',
    HUB_PAID_AI_QUEUE_TIMEOUT_MS: '500',
    XHUB_RUST_SCHEDULER_AUTHORITY: null,
    XHUB_RUST_SCHEDULER_STATUS_READ: null,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE: null,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: null,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: null,
    XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY: null,
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: null,
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE: null,
    XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY: null,
  }, async () => {
    try {
      fs.mkdirSync(runtimeBaseDir, { recursive: true });
      fs.mkdirSync(bridgeBaseDir, { recursive: true });
      db = new HubDB({ dbPath });
      insertPaidModel(db, requestedModelId);
      insertPaidModel(db, selectedModelId);
      const clientEntry = makeClientEntry(requestedModelId, {
        allowedModelIds: [requestedModelId, selectedModelId],
      });
      writeClientsSnapshot(runtimeBaseDir, [clientEntry]);

      const nodeAccount = addProviderKey(runtimeBaseDir, {
        provider: 'openai',
        api_key: 'sk-node-production-provider-key',
        auth_type: 'api_key',
        models: [requestedModelId, selectedModelId],
        base_url: 'https://node-selected.example.test',
      });
      assert.equal(nodeAccount.ok, true);
      const rustAccount = addProviderKey(runtimeBaseDir, {
        provider: 'openai',
        api_key: 'sk-rust-production-provider-key',
        auth_type: 'api_key',
        models: [requestedModelId, selectedModelId],
        base_url: 'https://rust-selected.example.test',
      });
      assert.equal(rustAccount.ok, true);
      fakeBridge = startFakeBridge({ bridgeBaseDir, responseText: 'bridge production authority ok' });

      const providerRouteCalls = [];
      const modelRouteCalls = [];
      const providerRouteAuthorityBridge = {
        config: {
          productionAuthority: true,
          candidateEnabled: false,
          prepEnabled: false,
        },
        route(input) {
          providerRouteCalls.push(input);
          return Promise.resolve({
            ok: true,
            used: true,
            fallback: false,
            selected: true,
            selectedAccountKey: rustAccount.account_key,
            decision: {
              requestedProvider: 'openai',
              requestedModelId: selectedModelId,
              resolvedProvider: 'openai',
              strategy: 'quota-aware',
              selectionScope: `openai::${selectedModelId}`,
              selectedAccountKey: rustAccount.account_key,
              fallbackReasonCode: '',
              availableCount: 2,
              totalCount: 2,
              candidates: [],
            },
          });
        },
      };
      const modelRouteAuthorityBridge = {
        config: {
          productionAuthority: true,
          candidateEnabled: false,
          prepEnabled: false,
        },
        route(input) {
          modelRouteCalls.push(input);
          return Promise.resolve({
            ok: true,
            used: true,
            fallback: false,
            selected: true,
            selectedModelId,
            selectedRouteKind: 'remote',
            decision: {
              requestedTaskType: 'text_generate',
              requestedModelId,
              requiredCapabilities: ['text.generate'],
              privacyMode: 'remote-only',
              costPreference: 'balanced',
              selectedRouteKind: 'remote',
              selectedModelId,
              blockingReasonCode: '',
              remoteCandidateCount: 2,
              localCandidateCount: 0,
            },
          });
        },
      };
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        providerRouteAuthorityBridge,
        modelRouteAuthorityBridge,
      });
      const call = makeGenerateCall({
        token: clientEntry.token,
        request: {
          request_id: 'gen_provider_production_authority',
          model_id: requestedModelId,
          max_tokens: 32,
          temperature: 0.1,
          top_p: 0.95,
          messages: [{ role: 'user', content: 'hello from provider production authority test' }],
          client: {
            device_id: clientEntry.device_id,
            user_id: clientEntry.user_id,
            app_id: 'xt-provider-production-test',
            project_id: 'project-provider-production-test',
          },
        },
      });

      await withTimeout(impl.HubAI.Generate(call), 1500, 'HubAI.Generate production authority');
      const summary = summarizeGenerate(call);
      assert.equal(summary.ended, true);
      assert.equal(summary.done_ok, true);
      assert.equal(summary.done_reason, 'eos');
      assert.equal(summary.error_code, '');
      assert.match(summary.delta_text, /bridge production authority ok/);

      assert.equal(modelRouteCalls.length, 1);
      assert.equal(modelRouteCalls[0].modelId, requestedModelId);
      assert.equal(modelRouteCalls[0].nodeModelId, requestedModelId);
      assert.equal(modelRouteCalls[0].nodeRouteKind, 'remote');
      assert.equal(modelRouteCalls[0].requireNodeMatch, false);
      assert.equal(providerRouteCalls.length, 1);
      assert.equal(providerRouteCalls[0].modelId, selectedModelId);
      assert.equal(providerRouteCalls[0].nodeAccountKey, nodeAccount.account_key);
      assert.equal(providerRouteCalls[0].requireNodeMatch, false);

      assert.equal(fakeBridge.requests.length, 1);
      const bridgeRequest = fakeBridge.requests[0];
      assert.equal(bridgeRequest.type, 'ai_generate');
      assert.equal(bridgeRequest.model_id, selectedModelId);
      assert.equal(bridgeRequest.provider_key?.account_key, rustAccount.account_key);
      assert.equal(bridgeRequest.provider_key?.provider, 'openai');
      assert.equal(bridgeRequest.provider_key?.base_url, 'https://rust-selected.example.test');

      const modelAuthorityAudit = await waitForAuditEvent(db, {
        requestId: 'gen_provider_production_authority',
        eventType: 'ai.generate.model_route_authority',
      });
      assert.equal(modelAuthorityAudit.ok, 1);
      const modelExt = JSON.parse(modelAuthorityAudit.ext_json || '{}');
      assert.equal(modelExt.schema_version, 'xhub.rust_model_route_authority.audit.v1');
      assert.equal(modelExt.requested_model_id, requestedModelId);
      assert.equal(modelExt.selected_model_id, selectedModelId);

      const providerAuthorityAudit = await waitForAuditEvent(db, {
        requestId: 'gen_provider_production_authority',
        eventType: 'ai.generate.provider_route_authority',
      });
      assert.equal(providerAuthorityAudit.ok, 1);
      const providerExt = JSON.parse(providerAuthorityAudit.ext_json || '{}');
      assert.equal(providerExt.schema_version, 'xhub.rust_provider_route_authority.audit.v1');
      assert.equal(providerExt.selected_account_key, rustAccount.account_key);
      assert.equal(JSON.stringify(providerExt).includes('sk-rust-production-provider-key'), false);
    } finally {
      if (fakeBridge) fakeBridge.stop();
      if (db) db.close();
    }
  });
});

await run('HubAI.Generate production model authority rechecks trust policy for Rust selected model', async () => {
  const root = makeTempDir('xhub-rust-model-production-deny-');
  const runtimeBaseDir = path.join(root, 'runtime');
  const bridgeBaseDir = path.join(root, 'bridge');
  const dbPath = path.join(root, 'hub.sqlite3');
  const requestedModelId = 'gpt-4o';
  const blockedSelectedModelId = 'gpt-4.1';
  let db = null;
  let fakeBridge = null;
  invalidateProviderKeyCache();

  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_BRIDGE_BASE_DIR: bridgeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_AUDIT_LEVEL: 'full_content',
    HUB_MEMORY_AT_REST_ENABLED: 'false',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '50',
    HUB_BRIDGE_AI_TIMEOUT_SEC: '2',
    HUB_PAID_AI_QUEUE_TIMEOUT_MS: '500',
    XHUB_RUST_SCHEDULER_AUTHORITY: null,
    XHUB_RUST_SCHEDULER_STATUS_READ: null,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: null,
    XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY: null,
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE: null,
    XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY: null,
  }, async () => {
    try {
      fs.mkdirSync(runtimeBaseDir, { recursive: true });
      fs.mkdirSync(bridgeBaseDir, { recursive: true });
      db = new HubDB({ dbPath });
      insertPaidModel(db, requestedModelId);
      insertPaidModel(db, blockedSelectedModelId);
      const clientEntry = makeClientEntry(requestedModelId, {
        allowedModelIds: [requestedModelId],
      });
      writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
      const nodeAccount = addProviderKey(runtimeBaseDir, {
        provider: 'openai',
        api_key: 'sk-node-production-deny-provider-key',
        auth_type: 'api_key',
        models: [requestedModelId, blockedSelectedModelId],
        base_url: 'https://node-selected.example.test',
      });
      assert.equal(nodeAccount.ok, true);
      fakeBridge = startFakeBridge({ bridgeBaseDir, responseText: 'should not be used' });

      const providerRouteCalls = [];
      const modelRouteCalls = [];
      const providerRouteAuthorityBridge = {
        config: {
          productionAuthority: true,
          candidateEnabled: false,
          prepEnabled: false,
        },
        route(input) {
          providerRouteCalls.push(input);
          return Promise.resolve({
            ok: true,
            used: true,
            fallback: false,
            selected: true,
            selectedAccountKey: nodeAccount.account_key,
          });
        },
      };
      const modelRouteAuthorityBridge = {
        config: {
          productionAuthority: true,
          candidateEnabled: false,
          prepEnabled: false,
        },
        route(input) {
          modelRouteCalls.push(input);
          return Promise.resolve({
            ok: true,
            used: true,
            fallback: false,
            selected: true,
            selectedModelId: blockedSelectedModelId,
            selectedRouteKind: 'remote',
            decision: {
              selectedModelId: blockedSelectedModelId,
              selectedRouteKind: 'remote',
            },
          });
        },
      };
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        providerRouteAuthorityBridge,
        modelRouteAuthorityBridge,
      });
      const call = makeGenerateCall({
        token: clientEntry.token,
        request: {
          request_id: 'gen_model_production_authority_denied',
          model_id: requestedModelId,
          max_tokens: 32,
          temperature: 0.1,
          top_p: 0.95,
          messages: [{ role: 'user', content: 'hello from model production authority deny test' }],
          client: {
            device_id: clientEntry.device_id,
            user_id: clientEntry.user_id,
            app_id: 'xt-model-production-deny-test',
            project_id: 'project-model-production-deny-test',
          },
        },
      });

      await withTimeout(impl.HubAI.Generate(call), 1500, 'HubAI.Generate production authority deny');
      const summary = summarizeGenerate(call);
      assert.equal(summary.ended, true);
      assert.equal(summary.done_ok, false);
      assert.equal(summary.error_code, 'device_paid_model_not_allowed');
      assert.equal(modelRouteCalls.length, 1);
      assert.equal(providerRouteCalls.length, 0);
      assert.equal(fakeBridge.requests.length, 0);
    } finally {
      if (fakeBridge) fakeBridge.stop();
      if (db) db.close();
    }
  });
});

  try { fs.rmSync(root, { recursive: true, force: true }); } catch {}
  invalidateProviderKeyCache();
});
