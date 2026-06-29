import Foundation

extension HubPairingCoordinator {
    func remoteGenerateScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const asText = (v) => (v == null ? '' : String(v));
const safe = (v) => asText(v).trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  const projectOverride = safe(process.env.XTERMINAL_GEN_PROJECT_ID || '');
  const sessionOverride = safe(process.env.XTERMINAL_GEN_SESSION_ID || '');
  const appOverride = safe(process.env.XTERMINAL_GEN_APP_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: appOverride || safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectOverride || safe(process.env.HUB_PROJECT_ID || ''),
    session_id: sessionOverride || safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function listModels(modelsClient, md, client) {
  return await new Promise((resolve, reject) => {
    modelsClient.ListModels({ client }, md, (err, out) => {
      if (err) reject(err);
      else resolve(Array.isArray(out?.models) ? out.models : []);
    });
  });
}

function normalizeWantedModelId(models, wantedModelId) {
  const wanted = safe(wantedModelId);
  if (!wanted) return '';

  const all = Array.isArray(models) ? models : [];
  const exact = all.find((m) => safe(m?.model_id || '').toLowerCase() === wanted.toLowerCase());
  if (exact) {
    return safe(exact?.model_id || '');
  }

  if (wanted.includes('/')) {
    return wanted;
  }

  const needle = wanted.toLowerCase();
  const suffixMatches = all.filter((m) => {
    const id = safe(m?.model_id || '').toLowerCase();
    if (!id) return false;
    return id === needle || id.endsWith(`/${needle}`);
  });
  if (suffixMatches.length === 1) {
    return safe(suffixMatches[0]?.model_id || '');
  }

  return wanted;
}

function selectModelId(models, wantedModelId) {
  const wanted = normalizeWantedModelId(models, wantedModelId);
  if (wanted) return wanted;
  const available = models.filter((m) => safe(m?.visibility) === 'MODEL_VISIBILITY_AVAILABLE');
  if (available.length > 0) {
    const id = safe(available[0]?.model_id || '');
    if (id) return id;
  }
  for (const m of models) {
    const id = safe(m?.model_id || '');
    if (id) return id;
  }
  return '';
}

function modelById(models, modelId) {
  const wanted = safe(modelId);
  if (!wanted) return null;
  const all = Array.isArray(models) ? models : [];
  const exact = all.find((m) => safe(m?.model_id || '').toLowerCase() === wanted.toLowerCase());
  if (exact) return exact;

  const normalized = normalizeWantedModelId(all, wanted);
  if (!normalized) return null;
  return all.find((m) => safe(m?.model_id || '').toLowerCase() === normalized.toLowerCase()) || null;
}

function modelIdsEquivalent(lhs, rhs) {
  const left = safe(lhs).toLowerCase();
  const right = safe(rhs).toLowerCase();
  if (!left || !right) return false;
  if (left === right) return true;

  const leftBase = left.includes('/') ? left.split('/').pop() : left;
  const rightBase = right.includes('/') ? right.split('/').pop() : right;
  return !!leftBase && leftBase === rightBase;
}

function isPaidModel(model) {
  const kind = safe(model?.kind || '');
  return kind === 'MODEL_KIND_PAID_ONLINE' || kind === '2';
}

function isLocalModel(model) {
  const kind = safe(model?.kind || '');
  if (kind === 'MODEL_KIND_LOCAL_OFFLINE' || kind === '1') return true;
  const backend = safe(model?.backend || '').toLowerCase();
  return backend === 'mlx';
}

function buildExecutionDescriptor(models, requestedModelId, actualModelId) {
  const requested = safe(requestedModelId);
  const actual = safe(actualModelId || requestedModelId);
  const requestedMeta = modelById(models, requested);
  const actualMeta = modelById(models, actual);
  const requestedPaid = isPaidModel(requestedMeta);
  const actualPaid = isPaidModel(actualMeta);
  const actualLocal = isLocalModel(actualMeta);

  if (!requestedPaid) {
    return {
      requested_model_id: requested,
      actual_model_id: actual,
      runtime_provider: 'Hub (Local)',
      execution_path: 'local_runtime',
      fallback_reason_code: '',
    };
  }

  if (requested && actual && !modelIdsEquivalent(requested, actual) && (actualLocal || !actualPaid)) {
    return {
      requested_model_id: requested,
      actual_model_id: actual,
      runtime_provider: 'Hub (Local)',
      execution_path: 'hub_downgraded_to_local',
      fallback_reason_code: 'downgrade_to_local',
    };
  }

  return {
    requested_model_id: requested,
    actual_model_id: actual,
    runtime_provider: 'Hub (Remote)',
    execution_path: 'remote_model',
    fallback_reason_code: '',
  };
}

async function generateOnce(aiClient, md, req, timeoutMs) {
  const stream = aiClient.Generate(req, md);
  return await new Promise((resolve, reject) => {
    let assistantText = '';
    let doneObj = null;
    let errObj = null;

    const timer = setTimeout(() => {
      try { stream.cancel(); } catch {}
      reject(new Error('remote_generate_timeout'));
    }, Math.max(4000, timeoutMs));

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      const start = ev?.start || (which === 'start' ? ev?.start : null);
      const delta = ev?.delta || (which === 'delta' ? ev?.delta : null);
      const done = ev?.done || (which === 'done' ? ev?.done : null);
      const err = ev?.error || (which === 'error' ? ev?.error : null);

      if (start && safe(start.model_id || '')) {
        req.model_id = safe(start.model_id || req.model_id || '');
      }
      if (delta && typeof delta.text === 'string' && delta.text) {
        assistantText += delta.text;
      }
      if (done) doneObj = done;
      if (err) errObj = err;
    });

    stream.on('end', () => {
      clearTimeout(timer);
      resolve({ assistantText, done: doneObj, error: errObj, model_id: safe(req.model_id || '') });
    });
    stream.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubAI) {
    throw new Error('hub_ai_missing');
  }

  const { creds, options } = await makeClientCreds();
  const aiClient = new proto.HubAI(addr, creds, options);
  const modelsClient = proto?.HubModels ? new proto.HubModels(addr, creds, options) : null;
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const reqId = safe(process.env.XTERMINAL_GEN_REQUEST_ID || `gen_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`);
  const wantedModelId = safe(process.env.XTERMINAL_GEN_MODEL_ID || '');
  const promptB64 = asText(process.env.XTERMINAL_GEN_PROMPT_B64 || '');
  const promptText = promptB64 ? Buffer.from(promptB64, 'base64').toString('utf8') : '';
  if (!safe(promptText)) {
    throw new Error('prompt_empty');
  }

  let models = [];
  let modelId = wantedModelId;
  if (modelsClient) {
    try {
      models = await listModels(modelsClient, md, client);
      modelId = selectModelId(models, wantedModelId);
    } catch {
      models = [];
      modelId = wantedModelId;
    }
  }
  if (!modelId) {
    throw new Error('no_model_routed');
  }

  const maxTokensRaw = Number.parseInt(safe(process.env.XTERMINAL_GEN_MAX_TOKENS || '768'), 10);
  const temperatureRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TEMPERATURE || '0.2'));
  const topPRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TOP_P || '0.95'));
  const timeoutSecRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TIMEOUT_SEC || '120'));
  const failClosedOnDowngrade = safe(process.env.XTERMINAL_GEN_FAIL_CLOSED_ON_DOWNGRADE || '') === '1';

  const req = {
    request_id: reqId,
    client,
    model_id: modelId,
    messages: [{ role: 'user', content: promptText }],
    max_tokens: Math.max(1, Math.min(8192, Number.isFinite(maxTokensRaw) ? maxTokensRaw : 768)),
    temperature: Math.max(0, Math.min(2, Number.isFinite(temperatureRaw) ? temperatureRaw : 0.2)),
    top_p: Math.max(0.01, Math.min(1, Number.isFinite(topPRaw) ? topPRaw : 0.95)),
    stream: true,
    created_at_ms: Date.now(),
    fail_closed_on_downgrade: failClosedOnDowngrade,
  };

  const streamResult = await generateOnce(
    aiClient,
    md,
    req,
    Math.max(8, Math.min(600, Number.isFinite(timeoutSecRaw) ? timeoutSecRaw : 240)) * 1000
  );

  const errPayload = streamResult?.error?.error || streamResult?.error || null;
  if (errPayload) {
    const code = safe(errPayload.code || '');
    const message = safe(errPayload.message || '');
    const routeError = streamResult?.error || {};
    const denyCode = safe(routeError.deny_code || errPayload.deny_code || code || '');
    const auditRef = safe(routeError.audit_ref || errPayload.audit_ref || '');
    const runtimeProvider = safe(routeError.runtime_provider || '');
    const executionPath = safe(routeError.execution_path || 'remote_error');
    const fallbackReasonCode = safe(routeError.fallback_reason_code || denyCode || code || '');
    const actualModelId = safe(routeError.model_id || streamResult?.model_id || modelId);
    out({
      ok: false,
      text: '',
      model_id: actualModelId || modelId,
      requested_model_id: modelId,
      actual_model_id: actualModelId || modelId,
      runtime_provider: runtimeProvider,
      execution_path: executionPath,
      fallback_reason_code: fallbackReasonCode,
      audit_ref: auditRef,
      deny_code: denyCode,
      reason: code || message || 'remote_chat_failed',
      error_code: code || message || 'remote_chat_failed',
      error_message: message || code || 'remote_chat_failed',
    });
    return;
  }

  const done = streamResult?.done || null;
  if (done && done.ok === false) {
    const reason = safe(done.reason || 'remote_chat_failed') || 'remote_chat_failed';
    const denyCode = safe(done.deny_code || reason || '');
    const auditRef = safe(done.audit_ref || '');
    const runtimeProvider = safe(done.runtime_provider || '');
    const executionPath = safe(done.execution_path || 'remote_error');
    const fallbackReasonCode = safe(done.fallback_reason_code || denyCode || reason || '');
    const actualModelId = safe(done.actual_model_id || streamResult?.model_id || modelId);
    out({
      ok: false,
      text: '',
      model_id: actualModelId || modelId,
      requested_model_id: modelId,
      actual_model_id: actualModelId || modelId,
      runtime_provider: runtimeProvider,
      execution_path: executionPath,
      fallback_reason_code: fallbackReasonCode,
      audit_ref: auditRef,
      deny_code: denyCode,
      reason,
      error_code: reason,
      error_message: reason,
    });
    return;
  }

  const usage = done?.usage && typeof done.usage === 'object' ? done.usage : {};
  const promptTokens = Number(usage.prompt_tokens || 0) || 0;
  const completionTokens = Number(usage.completion_tokens || 0) || 0;
  const totalTokens = Number(usage.total_tokens || 0) || (promptTokens + completionTokens);
  const actualModelId = safe(done?.actual_model_id || streamResult?.model_id || modelId);
  const execution = buildExecutionDescriptor(models, modelId, actualModelId);
  const runtimeProvider = safe(done?.runtime_provider || execution.runtime_provider);
  const executionPath = safe(done?.execution_path || execution.execution_path);
  const fallbackReasonCode = safe(done?.fallback_reason_code || execution.fallback_reason_code || '');
  const auditRef = safe(done?.audit_ref || '');
  const denyCode = safe(done?.deny_code || '');
  const memoryPromptProjection = done?.memory_prompt_projection && typeof done.memory_prompt_projection === 'object'
    ? done.memory_prompt_projection
    : null;

  out({
    ok: done ? done.ok !== false : true,
    text: asText(streamResult?.assistantText || ''),
    model_id: actualModelId || modelId,
    requested_model_id: execution.requested_model_id,
    actual_model_id: actualModelId || execution.actual_model_id,
    runtime_provider: runtimeProvider,
    execution_path: executionPath,
    fallback_reason_code: fallbackReasonCode,
    audit_ref: auditRef,
    deny_code: denyCode,
    reason: safe(done?.reason || 'eos') || 'eos',
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: totalTokens,
    ...(memoryPromptProjection ? { memory_prompt_projection: memoryPromptProjection } : {}),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    text: '',
    reason: msg || 'remote_chat_failed',
    error_code: msg || 'remote_chat_failed',
    error_message: msg || 'remote_chat_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteNetworkGrantScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function requestGrant(grantsClient, md, req) {
  return await new Promise((resolve, reject) => {
    grantsClient.RequestGrant(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function waitGrantDecision(eventsClient, md, client, grantId, waitMs) {
  return await new Promise((resolve) => {
    let done = false;
    const finish = (payload) => {
      if (done) return;
      done = true;
      try { stream.cancel(); } catch {}
      clearTimeout(timer);
      resolve(payload || null);
    };

    const stream = eventsClient.Subscribe(
      {
        client,
        scopes: ['grants', 'requests'],
        last_event_id: '',
      },
      md
    );

    const timer = setTimeout(() => finish(null), Math.max(1000, waitMs));

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      if (which !== 'grant_decision') return;
      const gd = ev?.grant_decision || null;
      const gid = safe(gd?.grant_request_id || '');
      if (!gid || gid !== grantId) return;
      finish({
        decision: safe(gd?.decision || ''),
        deny_reason: safe(gd?.deny_reason || ''),
      });
    });
    stream.on('error', () => finish(null));
    stream.on('end', () => finish(null));
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubGrants) {
    throw new Error('hub_grants_missing');
  }

  const { creds, options } = await makeClientCreds();
  const grantsClient = new proto.HubGrants(addr, creds, options);
  const eventsClient = proto?.HubEvents ? new proto.HubEvents(addr, creds, options) : null;
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const capability = safe(process.env.XTERMINAL_GRANT_CAPABILITY || 'CAPABILITY_WEB_FETCH');
  const reqId = `grant_${capability.toLowerCase()}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const reqSecondsRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_SECONDS || '900'), 10);
  const reqSeconds = Math.max(30, Math.min(86400, Number.isFinite(reqSecondsRaw) ? reqSecondsRaw : 900));
  const waitSecRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_WAIT_SEC || '10'), 10);
  const waitSec = Math.max(0, Math.min(60, Number.isFinite(waitSecRaw) ? waitSecRaw : 10));
  const requestedTokenCapRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_TOKEN_CAP || '0'), 10);
  const requestedTokenCap = Math.max(0, Math.min(5000, Number.isFinite(requestedTokenCapRaw) ? requestedTokenCapRaw : 0));
  const modelId = safe(process.env.XTERMINAL_GRANT_MODEL_ID || '');
  const reason = safe(process.env.XTERMINAL_GRANT_REASON || 'x_terminal need_network');

  if (capability === 'CAPABILITY_AI_GENERATE_PAID' && !modelId) {
    throw new Error('grant_model_id_missing');
  }

  const resp = await requestGrant(grantsClient, md, {
    request_id: reqId,
    client,
    capability,
    model_id: modelId,
    reason,
    requested_ttl_sec: reqSeconds,
    requested_token_cap: requestedTokenCap,
    created_at_ms: Date.now(),
  });

  const decisionRaw = safe(resp?.decision || '');
  const grantRequestId = safe(resp?.grant_request_id || reqId);
  const expiresAtMs = Number(resp?.expires_at_ms || 0) || 0;
  const denyReason = safe(resp?.deny_reason || '');

  if (decisionRaw === 'GRANT_DECISION_APPROVED') {
    out({
      ok: true,
      decision: 'approved',
      grant_request_id: grantRequestId,
      expires_at_ms: expiresAtMs,
      queued: false,
      auto_approved: true,
    });
    return;
  }

  if (decisionRaw === 'GRANT_DECISION_DENIED' || decisionRaw === 'GRANT_DECISION_REJECTED') {
    out({
      ok: false,
      decision: 'denied',
      grant_request_id: grantRequestId,
      expires_at_ms: expiresAtMs,
      reason: denyReason || 'grant_denied',
      queued: false,
      auto_approved: false,
      error_code: denyReason || 'grant_denied',
    });
    return;
  }

  if (decisionRaw === 'GRANT_DECISION_QUEUED' && waitSec > 0 && eventsClient) {
    const decided = await waitGrantDecision(eventsClient, md, client, grantRequestId, waitSec * 1000);
    const d = safe(decided?.decision || '');
    if (d === 'GRANT_DECISION_APPROVED') {
      out({
        ok: true,
        decision: 'approved',
        grant_request_id: grantRequestId,
        expires_at_ms: expiresAtMs,
        queued: false,
        auto_approved: false,
      });
      return;
    }
    if (d === 'GRANT_DECISION_DENIED' || d === 'GRANT_DECISION_REJECTED') {
      const deny = safe(decided?.deny_reason || 'grant_denied');
      out({
        ok: false,
        decision: 'denied',
        grant_request_id: grantRequestId,
        expires_at_ms: expiresAtMs,
        reason: deny,
        queued: false,
        auto_approved: false,
        error_code: deny,
      });
      return;
    }
  }

  out({
    ok: true,
    decision: 'queued',
    grant_request_id: grantRequestId,
    expires_at_ms: expiresAtMs,
    queued: true,
    auto_approved: false,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    decision: 'failed',
    error_code: msg || 'remote_grant_failed',
    error_message: msg || 'remote_grant_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteWebFetchScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function fetchOnce(webClient, md, req) {
  return await new Promise((resolve, reject) => {
    const stream = webClient.Fetch(req, md);
    let doneObj = null;
    const chunks = [];

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      const chunk = ev?.chunk || (which === 'chunk' ? ev?.chunk : null);
      const done = ev?.done || (which === 'done' ? ev?.done : null);
      if (chunk?.data) {
        chunks.push(Buffer.from(chunk.data));
      }
      if (done) {
        doneObj = done;
      }
    });

    stream.on('end', () => resolve({ done: doneObj, chunks }));
    stream.on('error', (e) => reject(e));
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const fetchURL = safe(process.env.XTERMINAL_FETCH_URL || '');
  if (!fetchURL) {
    throw new Error('empty_url');
  }

  const timeoutRaw = Number.parseFloat(safe(process.env.XTERMINAL_FETCH_TIMEOUT_SEC || '12'));
  const timeoutSec = Math.max(2, Math.min(60, Number.isFinite(timeoutRaw) ? timeoutRaw : 12));
  const maxBytesRaw = Number.parseInt(safe(process.env.XTERMINAL_FETCH_MAX_BYTES || '1000000'), 10);
  const maxBytes = Math.max(1024, Math.min(5000000, Number.isFinite(maxBytesRaw) ? maxBytesRaw : 1000000));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubWeb) {
    throw new Error('hub_web_missing');
  }

  const { creds, options } = await makeClientCreds();
  const webClient = new proto.HubWeb(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const req = {
    request_id: `web_fetch_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    client,
    url: fetchURL,
    method: 'GET',
    headers: {},
    timeout_sec: Math.floor(timeoutSec),
    max_bytes: Math.floor(maxBytes),
    created_at_ms: Date.now(),
    stream: false,
  };

  const resp = await fetchOnce(webClient, md, req);
  const done = resp?.done || null;
  const chunks = Array.isArray(resp?.chunks) ? resp.chunks : [];
  if (!done) {
    throw new Error('web_fetch_no_done_event');
  }

  let text = safe(done?.text || '');
  if (!text && chunks.length > 0) {
    try {
      text = Buffer.concat(chunks).toString('utf8');
    } catch {
      text = '';
    }
  }

  const errCode = safe(done?.error?.code || '');
  const errMessage = safe(done?.error?.message || '');

  out({
    ok: !!done?.ok,
    status: Number(done?.status || 0),
    final_url: safe(done?.final_url || fetchURL),
    content_type: safe(done?.content_type || ''),
    truncated: !!done?.truncated,
    bytes: Number(done?.bytes || 0),
    text,
    reason: errCode || errMessage || '',
    error_code: errCode || '',
    error_message: errMessage || '',
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    status: 0,
    final_url: safe(process.env.XTERMINAL_FETCH_URL || ''),
    content_type: '',
    truncated: false,
    bytes: 0,
    text: '',
    reason: msg || 'remote_web_fetch_failed',
    error_code: msg || 'remote_web_fetch_failed',
    error_message: msg || 'remote_web_fetch_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteProjectSyncScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  const projectId = safe(process.env.XTERMINAL_SYNC_PROJECT_ID || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function upsert(memoryClient, md, client, key, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'project',
        thread_id: '',
        key,
        value,
        pinned: false,
        request_id: safe(process.env.XTERMINAL_PROJECT_MEMORY_REQUEST_ID || ''),
        audit_ref: safe(process.env.XTERMINAL_PROJECT_MEMORY_AUDIT_REF || ''),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const client = reqClientFromEnv();
  if (!safe(client.project_id)) throw new Error('project_id_empty');

  const payload = {
    project_id: safe(process.env.XTERMINAL_SYNC_PROJECT_ID || ''),
    root_path: safe(process.env.XTERMINAL_SYNC_ROOT_PATH || ''),
    display_name: safe(process.env.XTERMINAL_SYNC_DISPLAY_NAME || ''),
    status_digest: safe(process.env.XTERMINAL_SYNC_STATUS_DIGEST || ''),
    last_summary_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_LAST_SUMMARY_AT || '0')) || 0,
    last_event_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_LAST_EVENT_AT || '0')) || 0,
    updated_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_UPDATED_AT || `${Date.now() / 1000}`)) || (Date.now() / 1000),
  };

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const key = 'xterminal.project.snapshot';
  const value = JSON.stringify(payload);
  await upsert(memoryClient, md, client, key, value);

  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_project_sync_failed', error_message: msg || 'remote_project_sync_failed' });
  process.exit(1);
});
"""#
    }

    func remoteNotificationScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function appendTurns(memoryClient, md, client, threadId, content) {
  return await new Promise((resolve, reject) => {
    memoryClient.AppendTurns(
      {
        request_id: `xterminal_notify_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        client,
        thread_id: threadId,
        messages: [{ role: 'assistant', content }],
        created_at_ms: Date.now(),
        allow_private: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function upsertLast(memoryClient, md, client, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'device',
        thread_id: '',
        key: 'xterminal.notification.last',
        value,
        pinned: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();

  const source = safe(process.env.XTERMINAL_NOTIFY_SOURCE || 'X-Terminal');
  const title = safe(process.env.XTERMINAL_NOTIFY_TITLE || '');
  const body = safe(process.env.XTERMINAL_NOTIFY_BODY || '');
  if (!title) throw new Error('title_empty');
  const dedupe = safe(process.env.XTERMINAL_NOTIFY_DEDUPE || '');
  const action = safe(process.env.XTERMINAL_NOTIFY_ACTION_URL || '');
  const unread = ['1', 'true', 'yes'].includes(safe(process.env.XTERMINAL_NOTIFY_UNREAD || '').toLowerCase());

  const payload = {
    source,
    title,
    body,
    dedupe_key: dedupe || null,
    action_url: action || null,
    unread,
    created_at: Date.now(),
  };
  const line = `[Notification] ${title}\n${body || '(no body)'}\nsource=${source}${action ? `\naction=${action}` : ''}${dedupe ? `\ndedupe=${dedupe}` : ''}`;

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const th = await getOrCreateThread(memoryClient, md, client, 'xterminal_notifications');
  const threadId = safe(th?.thread_id || '');
  if (!threadId) throw new Error('thread_missing');

  await appendTurns(memoryClient, md, client, threadId, line);
  await upsertLast(memoryClient, md, client, JSON.stringify(payload));
  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_notification_failed', error_message: msg || 'remote_notification_failed' });
  process.exit(1);
});
"""#
    }

    func remoteProjectConversationAppendScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = safe(projectIdOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

function parseMessagesJSON(raw, userText, assistantText) {
  const messages = [];
  try {
    const parsed = JSON.parse(String(raw || '[]'));
    if (Array.isArray(parsed)) {
      for (const item of parsed) {
        const role = safe(item?.role || '');
        const content = safe(item?.content || '');
        if (!role || !content) continue;
        const message = { role, content };
        if (item?.turn_metadata && typeof item.turn_metadata === 'object') {
          message.turn_metadata = item.turn_metadata;
        }
        messages.push(message);
      }
    }
  } catch {}
  if (messages.length === 0) {
    if (userText) messages.push({ role: 'user', content: userText });
    if (assistantText) messages.push({ role: 'assistant', content: assistantText });
  }
  return messages;
}

async function appendTurns(memoryClient, md, client, threadId, requestId, createdAtMs, messages) {
  if (messages.length === 0) throw new Error('turn_empty');

  return await new Promise((resolve, reject) => {
    memoryClient.AppendTurns(
      {
        request_id: requestId,
        client,
        thread_id: threadId,
        messages,
        created_at_ms: createdAtMs,
        allow_private: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_CONV_PROJECT_ID || '');
  const threadKey = safe(process.env.XTERMINAL_CONV_THREAD_KEY || '');
  const requestId = safe(process.env.XTERMINAL_CONV_REQUEST_ID || '');
  const userText = safe(process.env.XTERMINAL_CONV_USER_TEXT || '');
  const assistantText = safe(process.env.XTERMINAL_CONV_ASSISTANT_TEXT || '');
  const messages = parseMessagesJSON(process.env.XTERMINAL_CONV_MESSAGES_JSON || '[]', userText, assistantText);
  const createdAtMsRaw = Number.parseInt(safe(process.env.XTERMINAL_CONV_CREATED_AT_MS || `${Date.now()}`), 10);
  const createdAtMs = Number.isFinite(createdAtMsRaw) ? createdAtMsRaw : Date.now();

  if (!projectId) throw new Error('project_id_empty');
  if (!threadKey) throw new Error('thread_key_empty');
  if (!requestId) throw new Error('request_id_empty');
  if (messages.length === 0) throw new Error('turn_empty');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const th = await getOrCreateThread(memoryClient, md, client, threadKey);
  const threadId = safe(th?.thread_id || '');
  if (!threadId) throw new Error('thread_missing');

  await appendTurns(memoryClient, md, client, threadId, requestId, createdAtMs, messages);
  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_project_conversation_append_failed', error_message: msg || 'remote_project_conversation_append_failed' });
  process.exit(1);
});
"""#
    }

    func remoteSupervisorConversationAppendScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: '',
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function appendTurns(memoryClient, md, client, threadId, requestId, createdAtMs, userText, assistantText) {
  const messages = [];
  if (userText) messages.push({ role: 'user', content: userText });
  if (assistantText) messages.push({ role: 'assistant', content: assistantText });
  if (messages.length === 0) throw new Error('turn_empty');

  return await new Promise((resolve, reject) => {
    memoryClient.AppendTurns(
      {
        request_id: requestId,
        client,
        thread_id: threadId,
        messages,
        created_at_ms: createdAtMs,
        allow_private: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const threadKey = safe(process.env.XTERMINAL_SUPERVISOR_CONV_THREAD_KEY || '');
  const requestId = safe(process.env.XTERMINAL_SUPERVISOR_CONV_REQUEST_ID || '');
  const userText = safe(process.env.XTERMINAL_SUPERVISOR_CONV_USER_TEXT || '');
  const assistantText = safe(process.env.XTERMINAL_SUPERVISOR_CONV_ASSISTANT_TEXT || '');
  const createdAtMsRaw = Number.parseInt(safe(process.env.XTERMINAL_SUPERVISOR_CONV_CREATED_AT_MS || `${Date.now()}`), 10);
  const createdAtMs = Number.isFinite(createdAtMsRaw) ? createdAtMsRaw : Date.now();

  if (!threadKey) throw new Error('thread_key_empty');
  if (!requestId) throw new Error('request_id_empty');
  if (!userText && !assistantText) throw new Error('turn_empty');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const th = await getOrCreateThread(memoryClient, md, client, threadKey);
  const threadId = safe(th?.thread_id || '');
  if (!threadId) throw new Error('thread_missing');

  await appendTurns(memoryClient, md, client, threadId, requestId, createdAtMs, userText, assistantText);
  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_supervisor_conversation_append_failed', error_message: msg || 'remote_supervisor_conversation_append_failed' });
  process.exit(1);
});
"""#
    }

    func remoteProjectCanonicalMemoryUpsertScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = safe(projectIdOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function upsert(memoryClient, md, client, key, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'project',
        thread_id: '',
        key,
        value,
        pinned: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_PROJECT_MEMORY_PROJECT_ID || process.env.HUB_PROJECT_ID || '');
  if (!projectId) throw new Error('project_id_empty');
  const requestId = safe(process.env.XTERMINAL_PROJECT_MEMORY_REQUEST_ID || `project_canonical_memory_${Date.now()}`);
  const batchAuditRef = safe(process.env.XTERMINAL_PROJECT_MEMORY_AUDIT_REF || `audit-memory-canonical-upsert-${requestId}`);

  const encoded = safe(process.env.XTERMINAL_PROJECT_MEMORY_ITEMS_B64 || '');
  if (!encoded) throw new Error('project_memory_items_missing');

  let items = [];
  try {
    items = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));
  } catch {
    throw new Error('project_memory_items_invalid');
  }
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error('project_memory_items_empty');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const client = reqClientFromEnv(projectId);
  if (!safe(client.project_id)) throw new Error('project_id_empty');

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const auditRefs = [];
  const evidenceRefs = [];
  const writebackRefs = [];
  let updatedAtMs = 0;

  for (const row of items) {
    const key = safe(row?.key || '');
    const value = safe(row?.value || '');
    if (!key || !value) continue;
    const response = await upsert(memoryClient, md, client, key, value);
    const auditRef = safe(response?.audit_ref || batchAuditRef);
    const evidenceRef = safe(response?.evidence_ref || '');
    const writebackRef = safe(response?.writeback_ref || '');
    const itemUpdatedAtMs = Number(response?.item?.updated_at_ms || 0);
    if (auditRef) auditRefs.push(auditRef);
    if (evidenceRef) evidenceRefs.push(evidenceRef);
    if (writebackRef) writebackRefs.push(writebackRef);
    if (Number.isFinite(itemUpdatedAtMs) && itemUpdatedAtMs > updatedAtMs) {
      updatedAtMs = itemUpdatedAtMs;
    }
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    audit_ref: batchAuditRef,
    audit_refs: Array.from(new Set(auditRefs)),
    evidence_refs: Array.from(new Set(evidenceRefs)),
    writeback_refs: Array.from(new Set(writebackRefs)),
    updated_at_ms: updatedAtMs,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    error_code: msg || 'remote_project_canonical_memory_upsert_failed',
    error_message: msg || 'remote_project_canonical_memory_upsert_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteDeviceCanonicalMemoryUpsertScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: '',
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function upsert(memoryClient, md, client, key, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'device',
        thread_id: '',
        key,
        value,
        pinned: false,
        request_id: safe(process.env.XTERMINAL_DEVICE_MEMORY_REQUEST_ID || ''),
        audit_ref: safe(process.env.XTERMINAL_DEVICE_MEMORY_AUDIT_REF || ''),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const requestId = safe(process.env.XTERMINAL_DEVICE_MEMORY_REQUEST_ID || `device_canonical_memory_${Date.now()}`);
  const batchAuditRef = safe(process.env.XTERMINAL_DEVICE_MEMORY_AUDIT_REF || `audit-memory-canonical-upsert-${requestId}`);
  const encoded = safe(process.env.XTERMINAL_DEVICE_MEMORY_ITEMS_B64 || '');
  if (!encoded) throw new Error('device_canonical_memory_items_missing');

  let items = [];
  try {
    items = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));
  } catch {
    throw new Error('device_canonical_memory_items_invalid');
  }
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error('device_canonical_memory_items_empty');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv();
  const auditRefs = [];
  const evidenceRefs = [];
  const writebackRefs = [];
  let updatedAtMs = 0;

  for (const row of items) {
    const key = safe(row?.key || '');
    const value = safe(row?.value || '');
    if (!key || !value) continue;
    const response = await upsert(memoryClient, md, client, key, value);
    const auditRef = safe(response?.audit_ref || batchAuditRef);
    const evidenceRef = safe(response?.evidence_ref || '');
    const writebackRef = safe(response?.writeback_ref || '');
    const itemUpdatedAtMs = Number(response?.item?.updated_at_ms || 0);
    if (auditRef) auditRefs.push(auditRef);
    if (evidenceRef) evidenceRefs.push(evidenceRef);
    if (writebackRef) writebackRefs.push(writebackRef);
    if (Number.isFinite(itemUpdatedAtMs) && itemUpdatedAtMs > updatedAtMs) {
      updatedAtMs = itemUpdatedAtMs;
    }
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    audit_ref: batchAuditRef,
    audit_refs: Array.from(new Set(auditRefs)),
    evidence_refs: Array.from(new Set(evidenceRefs)),
    writeback_refs: Array.from(new Set(writebackRefs)),
    updated_at_ms: updatedAtMs,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    error_code: msg || 'remote_device_canonical_memory_upsert_failed',
    error_message: msg || 'remote_device_canonical_memory_upsert_failed',
  });
  process.exit(1);
});
"""#
    }

}
