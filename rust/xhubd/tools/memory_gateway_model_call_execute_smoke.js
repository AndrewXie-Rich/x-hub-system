#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

const SCHEMA = 'xhub.rust_hub.memory_gateway_model_call_execute_smoke.v1';
const STATUS_FILE = 'memory_gateway_model_call_execute_smoke_status.json';
const HISTORY_FILE = 'memory_gateway_model_call_execute_smoke_history.json';
const ROLLBACK_ENV_KEYS = [
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_ADMISSION',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY',
];

function safeString(value) {
  return String(value ?? '').trim();
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    httpBaseUrl: safeString(process.env.XHUB_RUST_HTTP_BASE_URL || process.env.XHUBD_HTTP_BASE_URL) || 'http://127.0.0.1:50151',
    accessKeyFile: safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || process.env.XHUB_RUST_HUB_ACCESS_KEY_FILE),
    hubBaseDir: safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SMOKE_BASE_DIR || process.env.REL_FLOW_HUB_BASE_DIR),
    projectId: 'xt-memory-gateway-model-call-execute-smoke',
    timeoutMs: 5000,
    maxAgeMs: 10 * 60 * 1000,
    requireAdmissionReady: false,
    selfTest: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--http-base-url':
        out.httpBaseUrl = safeString(next) || out.httpBaseUrl;
        i += 1;
        break;
      case '--access-key-file':
        out.accessKeyFile = safeString(next);
        i += 1;
        break;
      case '--hub-base-dir':
        out.hubBaseDir = safeString(next);
        i += 1;
        break;
      case '--project-id':
        out.projectId = sanitizeToken(next) || out.projectId;
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 250, 60000);
        i += 1;
        break;
      case '--max-age-ms':
        out.maxAgeMs = parseIntInRange(next, out.maxAgeMs, 0, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--require-admission-ready':
        out.requireAdmissionReady = true;
        break;
      case '--self-test':
        out.selfTest = true;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  out.httpBaseUrl = out.httpBaseUrl.replace(/\/$/, '');
  return out;
}

function usage() {
  return [
    'memory_gateway_model_call_execute_smoke.js',
    '',
    'Options:',
    '  --http-base-url <u>          Live xhubd HTTP base URL, default 127.0.0.1:50151',
    '  --access-key-file <p>        HTTP access key file',
    '  --hub-base-dir <p>           Base dir for execute smoke status/history evidence',
    '  --project-id <id>            Smoke project id',
    '  --timeout-ms <n>             Request timeout, default 5000',
    '  --max-age-ms <n>             Freshness metadata for status, default 600000',
    '  --require-admission-ready    Fail if execution admission is not ready',
    '  --self-test                  Run in-memory self-test',
  ].join('\n');
}

function sanitizeToken(value) {
  return safeString(value)
    .replace(/[^A-Za-z0-9_.:-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function uniqueStrings(values) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const normalized = safeString(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function boundedCount(value) {
  const count = Number(value || 0);
  if (!Number.isFinite(count)) return 0;
  return Math.max(0, Math.min(1_000_000, Math.trunc(count)));
}

function safeErrorSummary(error) {
  return safeString(error?.message || error).slice(0, 500);
}

function readAccessKey(args) {
  const candidates = [
    args.accessKeyFile,
    process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE,
    process.env.XHUB_RUST_HUB_ACCESS_KEY_FILE,
  ].map(safeString).filter(Boolean);
  for (const candidate of candidates) {
    try {
      const value = fs.readFileSync(candidate, 'utf8').trim();
      if (value) return value;
    } catch {
      // Keep probing.
    }
  }
  return '';
}

function httpJson(method, url, body, timeoutMs, accessKey, okStatuses = [200]) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const payload = body === undefined ? '' : JSON.stringify(body);
    const headers = {};
    if (payload) {
      headers['content-type'] = 'application/json';
      headers['content-length'] = Buffer.byteLength(payload);
    }
    if (accessKey) headers['x-hub-access-key'] = accessKey;
    const req = http.request({
      method,
      hostname: target.hostname,
      port: target.port,
      path: `${target.pathname}${target.search}`,
      headers,
      timeout: timeoutMs,
    }, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        raw += chunk;
      });
      res.on('end', () => {
        const statusCode = Number(res.statusCode || 0);
        if (!okStatuses.includes(statusCode)) {
          reject(new Error(`HTTP ${statusCode} from ${url}: ${raw.slice(0, 500)}`));
          return;
        }
        try {
          resolve({ statusCode, raw, value: raw.trim() ? JSON.parse(raw) : {} });
        } catch (error) {
          reject(new Error(`invalid JSON from ${url}: ${error?.message || error}`));
        }
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error(`timeout after ${timeoutMs}ms: ${url}`));
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function defaultHubBaseDir(ready, explicit) {
  if (safeString(explicit)) return path.resolve(explicit);
  const memoryDir = safeString(ready?.memory?.memory_dir);
  if (memoryDir) return path.dirname(path.dirname(memoryDir));
  const runtimeDir = safeString(ready?.runtime?.runtime_base_dir);
  if (runtimeDir) return path.dirname(runtimeDir);
  return path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub', 'local');
}

function gateSummary(value) {
  const blockers = Array.isArray(value?.blockers)
    ? value.blockers.map((item) => safeString(item)).filter(Boolean).slice(0, 16)
    : [];
  return {
    schema_version: safeString(value?.schema_version),
    ok: value?.ok === true,
    status: safeString(value?.status),
    source: safeString(value?.source),
    mode: safeString(value?.mode),
    authority: safeString(value?.authority),
    ready_for_execution: value?.ready_for_execution === true,
    execution_admission_authority_in_rust: value?.execution_admission_authority_in_rust === true,
    execution_admission_ready: value?.execution_admission_ready === true,
    execution_authority_in_rust: value?.execution_authority_in_rust === true,
    would_call_model: value?.would_call_model === true,
    model_call_executed: value?.model_call_executed === true,
    production_authority_change: value?.production_authority_change === true,
    context_text_included: value?.plan?.context_text_included === true,
    prompt_text_included: value?.plan?.prompt_text_included === true,
    blocker_count: blockers.length,
    blockers,
  };
}

function executeSummary(value) {
  const blockers = Array.isArray(value?.blockers)
    ? value.blockers.map((item) => safeString(item)).filter(Boolean).slice(0, 16)
    : [];
  return {
    schema_version: safeString(value?.schema_version),
    ok: value?.ok === true,
    status: safeString(value?.status),
    source: safeString(value?.source),
    mode: safeString(value?.mode),
    authority: safeString(value?.authority),
    ready_for_execution: value?.ready_for_execution === true,
    execution_authority_in_rust: value?.execution_authority_in_rust === true,
    execution_enabled: value?.execution_enabled === true,
    would_call_model: value?.would_call_model === true,
    model_call_invoked: value?.model_call_invoked === true,
    model_call_executed: value?.model_call_executed === true,
    production_authority_change: value?.production_authority_change === true,
    local_ml_execute_http_invoked: value?.guards?.local_ml_execute_http_invoked === true,
    context_text_redacted_from_execute: value?.guards?.context_text_redacted_from_execute === true,
    prompt_text_redacted_from_execute: value?.guards?.prompt_text_redacted_from_execute === true,
    provider_route_not_mutated: value?.guards?.provider_route_not_mutated === true,
    node_not_authority: value?.guards?.node_not_authority === true,
    executor: safeString(value?.executor?.executor),
    local_executor_enabled: value?.executor?.local_executor_enabled === true,
    local_executor_apply_enabled: value?.executor?.local_executor_apply_enabled === true,
    local_route_allowed: value?.executor?.local_route_allowed === true,
    blocker_count: blockers.length,
    blockers,
  };
}

function rollbackPlan() {
  return {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_execute_rollback_plan.v1',
    authority_change: false,
    env_to_unset: ROLLBACK_ENV_KEYS,
    launchctl_commands: ROLLBACK_ENV_KEYS.map((key) => `launchctl unsetenv ${key}`),
    note: 'This smoke never applies env. These commands roll back a future explicit local-executor cutover.',
  };
}

function buildReport({
  ready,
  gate,
  execute,
  rawGate = '',
  rawExecute = '',
  promptNeedle = '',
  projectId,
  httpBaseUrl,
  hubBaseDir,
  requireAdmissionReady,
  maxAgeMs,
  error = '',
}) {
  const gateOut = gateSummary(gate);
  const executeOut = executeSummary(execute);
  const issueCodes = [];
  if (error) issueCodes.push('memory_gateway_model_call_execute_smoke_request_failed');
  if (gateOut.schema_version !== 'xhub.memory.gateway_model_call_execution_gate.v1') {
    issueCodes.push('memory_gateway_model_call_execution_gate_schema_mismatch');
  }
  if (gateOut.source !== 'rust_memory_gateway_model_call_execution_gate') {
    issueCodes.push('memory_gateway_model_call_execution_gate_source_mismatch');
  }
  if (requireAdmissionReady && gateOut.ready_for_execution !== true) {
    issueCodes.push('memory_gateway_model_call_execution_admission_not_ready');
  }
  if (gateOut.would_call_model || gateOut.model_call_executed) {
    issueCodes.push('memory_gateway_model_call_execution_gate_executed_unexpectedly');
  }
  if (gateOut.context_text_included || gateOut.prompt_text_included) {
    issueCodes.push('memory_gateway_model_call_execution_gate_text_leak');
  }
  if (gateOut.production_authority_change) {
    issueCodes.push('memory_gateway_model_call_execution_gate_authority_violation');
  }
  if (executeOut.schema_version !== 'xhub.memory.gateway_model_call_execute.v1') {
    issueCodes.push('memory_gateway_model_call_execute_schema_mismatch');
  }
  if (executeOut.source !== 'rust_memory_gateway_model_call_execute') {
    issueCodes.push('memory_gateway_model_call_execute_source_mismatch');
  }
  if (executeOut.status !== 'blocked') {
    issueCodes.push('memory_gateway_model_call_execute_not_blocked');
  }
  if (executeOut.would_call_model
    || executeOut.model_call_invoked
    || executeOut.model_call_executed
    || executeOut.local_ml_execute_http_invoked) {
    issueCodes.push('memory_gateway_model_call_execute_invoked_unexpectedly');
  }
  if (!executeOut.context_text_redacted_from_execute || !executeOut.prompt_text_redacted_from_execute) {
    issueCodes.push('memory_gateway_model_call_execute_text_leak');
  }
  if (!executeOut.provider_route_not_mutated || !executeOut.node_not_authority) {
    issueCodes.push('memory_gateway_model_call_execute_guard_missing');
  }
  if (executeOut.production_authority_change) {
    issueCodes.push('memory_gateway_model_call_execute_authority_violation');
  }
  if (safeString(promptNeedle) && (rawGate.includes(promptNeedle) || rawExecute.includes(promptNeedle))) {
    issueCodes.push('memory_gateway_model_call_execute_prompt_leak');
  }
  if (rawExecute.includes('memory://rust/object/') || rawExecute.includes('#object-')) {
    issueCodes.push('memory_gateway_model_call_execute_ref_leak');
  }
  const generatedAtMs = Date.now();
  const report = {
    ok: issueCodes.length === 0,
    schema_version: SCHEMA,
    command: 'memory-gateway-model-call-execute-smoke',
    generated_at_ms: generatedAtMs,
    max_age_ms: maxAgeMs,
    http_base_url: httpBaseUrl,
    project_id: projectId,
    hub_base_dir: hubBaseDir,
    readiness_ready: ready?.ready === true,
    memory_execute_http: ready?.memory?.gateway_model_call_execute_http === true
      || ready?.capabilities?.memory_gateway_model_call_execute_http === true,
    memory_execute_readiness: ready?.memory?.gateway_model_call_execute || null,
    require_admission_ready: requireAdmissionReady === true,
    admission_ready: gateOut.ready_for_execution === true,
    gate: gateOut,
    execute: executeOut,
    execution_blocked: executeOut.status === 'blocked'
      && executeOut.would_call_model === false
      && executeOut.model_call_invoked === false
      && executeOut.model_call_executed === false
      && executeOut.local_ml_execute_http_invoked === false,
    content_free: !issueCodes.some((code) => code.includes('text_leak') || code.includes('prompt_leak') || code.includes('ref_leak')),
    production_authority_change: false,
    rollback_plan: rollbackPlan(),
    issue_codes: uniqueStrings(issueCodes),
    error: safeString(error),
  };
  return report;
}

function atomicWriteJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmp = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, filePath);
}

function readJSON(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeEvidence(baseDir, report) {
  const statusPath = path.join(baseDir, STATUS_FILE);
  const historyPath = path.join(baseDir, HISTORY_FILE);
  const existing = readJSON(historyPath, null);
  const items = [report, ...(Array.isArray(existing?.items) ? existing.items : [])].slice(0, 64);
  const history = {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_execute_smoke_history.v1',
    generated_at_ms: Date.now(),
    item_limit: 64,
    items,
  };
  atomicWriteJSON(statusPath, report);
  atomicWriteJSON(historyPath, history);
  return { statusPath, historyPath };
}

function runSelfTest() {
  const promptNeedle = 'self-test prompt should not leak';
  const safe = buildReport({
    ready: { ready: true, memory: { gateway_model_call_execute_http: true } },
    gate: {
      schema_version: 'xhub.memory.gateway_model_call_execution_gate.v1',
      ok: true,
      status: 'blocked',
      source: 'rust_memory_gateway_model_call_execution_gate',
      ready_for_execution: false,
      would_call_model: false,
      model_call_executed: false,
      production_authority_change: false,
      plan: { context_text_included: false, prompt_text_included: false },
      blockers: ['memory_gateway_model_call_execution_not_enabled'],
    },
    execute: {
      schema_version: 'xhub.memory.gateway_model_call_execute.v1',
      ok: true,
      status: 'blocked',
      source: 'rust_memory_gateway_model_call_execute',
      would_call_model: false,
      model_call_invoked: false,
      model_call_executed: false,
      production_authority_change: false,
      guards: {
        local_ml_execute_http_invoked: false,
        context_text_redacted_from_execute: true,
        prompt_text_redacted_from_execute: true,
        provider_route_not_mutated: true,
        node_not_authority: true,
      },
      executor: { executor: 'local_ml', local_route_allowed: false },
      blockers: ['memory_gateway_model_call_non_local_executor_not_supported'],
    },
    rawGate: '{}',
    rawExecute: '{}',
    promptNeedle,
    projectId: 'self-test',
    httpBaseUrl: 'http://127.0.0.1:1',
    hubBaseDir: '/tmp',
    requireAdmissionReady: false,
    maxAgeMs: 600000,
  });
  if (safe.ok !== true || safe.execution_blocked !== true || safe.content_free !== true) {
    throw new Error(`safe self-test failed: ${JSON.stringify(safe.issue_codes)}`);
  }
  const unsafe = buildReport({
    ...safe,
    gate: safe.gate,
    execute: {
      ...safe.execute,
      status: 'executed',
      would_call_model: true,
      model_call_invoked: true,
      model_call_executed: true,
    },
    rawExecute: promptNeedle,
    promptNeedle,
  });
  if (unsafe.ok === true
    || !unsafe.issue_codes.includes('memory_gateway_model_call_execute_invoked_unexpectedly')
    || !unsafe.issue_codes.includes('memory_gateway_model_call_execute_prompt_leak')) {
    throw new Error('unsafe self-test failed');
  }
  const text = JSON.stringify(safe);
  if (text.includes('memory://rust/object/') || text.includes(promptNeedle)) {
    throw new Error('safe self-test leaked content');
  }
  console.log(JSON.stringify({
    ok: true,
    schema_version: `${SCHEMA}.self_test`,
    safe_issue_count: safe.issue_codes.length,
    unsafe_issue_codes: unsafe.issue_codes,
  }, null, 2));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  if (args.selfTest) {
    runSelfTest();
    return;
  }
  const accessKey = readAccessKey(args);
  const readyResp = await httpJson('GET', `${args.httpBaseUrl}/ready`, undefined, args.timeoutMs, accessKey);
  const ready = readyResp.value;
  const hubBaseDir = defaultHubBaseDir(ready, args.hubBaseDir);
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  const promptNeedle = `Memory gateway execute live smoke prompt ${stamp}`;
  const gateBody = {
    request_id: `memory_gateway_model_call_execute_gate_live_smoke_${stamp}`,
    audit_ref: `memory_gateway_model_call_execute_gate_live_smoke:${stamp}`,
    requester_role: 'chat',
    use_mode: 'project_chat',
    scope: 'project',
    project_id: args.projectId,
    serving_profile_id: 'M1_Execute',
    provider_id: 'local',
    model_id: 'memory-gateway-execute-smoke-local',
    task_kind: 'text_generate',
    prompt: promptNeedle,
    execute: true,
  };
  const executeBody = {
    request_id: `memory_gateway_model_call_execute_live_smoke_${stamp}`,
    audit_ref: `memory_gateway_model_call_execute_live_smoke:${stamp}`,
    requester_role: 'chat',
    use_mode: 'project_chat',
    scope: 'project',
    project_id: args.projectId,
    serving_profile_id: 'M1_Execute',
    provider_id: 'openai',
    model_id: 'memory-gateway-execute-smoke-remote',
    task_kind: 'text_generate',
    prompt: promptNeedle,
    execute: true,
  };
  let report;
  try {
    const gateResp = await httpJson(
      'POST',
      `${args.httpBaseUrl}/memory/gateway/model-call-execution-gate`,
      gateBody,
      args.timeoutMs,
      accessKey,
    );
    const executeResp = await httpJson(
      'POST',
      `${args.httpBaseUrl}/memory/gateway/model-call-execute`,
      executeBody,
      args.timeoutMs,
      accessKey,
    );
    report = buildReport({
      ready,
      gate: gateResp.value,
      execute: executeResp.value,
      rawGate: gateResp.raw,
      rawExecute: executeResp.raw,
      promptNeedle,
      projectId: args.projectId,
      httpBaseUrl: args.httpBaseUrl,
      hubBaseDir,
      requireAdmissionReady: args.requireAdmissionReady,
      maxAgeMs: args.maxAgeMs,
    });
  } catch (error) {
    report = buildReport({
      ready,
      gate: {},
      execute: {},
      rawGate: '',
      rawExecute: '',
      promptNeedle,
      projectId: args.projectId,
      httpBaseUrl: args.httpBaseUrl,
      hubBaseDir,
      requireAdmissionReady: args.requireAdmissionReady,
      maxAgeMs: args.maxAgeMs,
      error: safeErrorSummary(error),
    });
  }
  const evidence = writeEvidence(hubBaseDir, report);
  const output = {
    ...report,
    status_path: evidence.statusPath,
    history_path: evidence.historyPath,
  };
  console.log(JSON.stringify(output, null, 2));
  if (!output.ok) process.exit(1);
}

main().catch((error) => {
  process.stderr.write(`[memory_gateway_model_call_execute_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
