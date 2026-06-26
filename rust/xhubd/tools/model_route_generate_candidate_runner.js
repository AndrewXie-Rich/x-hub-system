#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const CANDIDATE_AUDIT_EVENT_TYPE = 'ai.generate.model_route_candidate';
const CANDIDATE_AUDIT_EXT_SCHEMA = 'xhub.rust_model_route_candidate.audit.v1';
const PROVIDER_SECRET_SENTINEL = 'sk-model-route-candidate-runner';

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
    runs: 3,
    concurrency: 1,
    provider: 'openai',
    modelId: 'gpt-5.5',
    timeoutMs: 30000,
    port: 55000 + (process.pid % 1000),
    bridgePollMs: 10,
    maxGenerateMs: 2000,
    minCandidateAudits: 0,
    maxCandidateMismatches: 0,
    maxCandidateFallbacks: 0,
    minPrepMatches: 0,
    prepTrial: false,
    expectReady: false,
    expectSuccess: true,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--runs':
        out.runs = parseIntInRange(next, out.runs, 1, 10000);
        i += 1;
        break;
      case '--concurrency':
        out.concurrency = parseIntInRange(next, out.concurrency, 1, 64);
        i += 1;
        break;
      case '--provider':
        out.provider = safeString(next) || out.provider;
        i += 1;
        break;
      case '--model-id':
        out.modelId = safeString(next) || out.modelId;
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--port':
        out.port = parseIntInRange(next, out.port, 1024, 65535);
        i += 1;
        break;
      case '--bridge-poll-ms':
        out.bridgePollMs = parseIntInRange(next, out.bridgePollMs, 5, 5000);
        i += 1;
        break;
      case '--max-generate-ms':
        out.maxGenerateMs = parseIntInRange(next, out.maxGenerateMs, 100, 300000);
        i += 1;
        break;
      case '--min-candidate-audits':
        out.minCandidateAudits = parseIntInRange(next, out.minCandidateAudits, 0, 1000000);
        i += 1;
        break;
      case '--max-candidate-mismatches':
        out.maxCandidateMismatches = parseIntInRange(next, out.maxCandidateMismatches, 0, 1000000);
        i += 1;
        break;
      case '--max-candidate-fallbacks':
        out.maxCandidateFallbacks = parseIntInRange(next, out.maxCandidateFallbacks, 0, 1000000);
        i += 1;
        break;
      case '--min-prep-matches':
        out.minPrepMatches = parseIntInRange(next, out.minPrepMatches, 0, 1000000);
        i += 1;
        break;
      case '--prep-trial':
        out.prepTrial = true;
        break;
      case '--expect-ready':
        out.expectReady = true;
        break;
      case '--allow-generate-failure':
        out.expectSuccess = false;
        break;
      case '--dry-run':
        out.dryRun = true;
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
  if (out.prepTrial && out.minPrepMatches <= 0) {
    out.minPrepMatches = out.runs;
  }
  return out;
}

function usage() {
  return [
    'model_route_generate_candidate_runner.js',
    '',
    'Options:',
    '  --runs <n>                     Generate batches, default 3',
    '  --concurrency <n>              Parallel Generate calls per batch, default 1',
    '  --model-id <id>                Paid model ID, default gpt-5.5',
    '  --provider <id>                Provider, default openai',
    '  --timeout-ms <n>               Runner wait timeout, default 30000',
    '  --port <n>                     Isolated Rust HTTP port',
    '  --bridge-poll-ms <n>           Fake Bridge poll interval, default 10',
    '  --max-generate-ms <n>          Per-call latency gate, default 2000',
    '  --min-candidate-audits <n>     Candidate audit minimum',
    '  --max-candidate-mismatches <n> Model/route-kind mismatch threshold, default 0',
    '  --max-candidate-fallbacks <n>  Rust candidate fallback threshold, default 0',
    '  --prep-trial                   Use prep route checks instead of candidate audit events',
    '  --min-prep-matches <n>         Prep match log minimum, default runs in prep mode',
    '  --expect-ready                 Fail unless candidate readiness is ready',
    '  --allow-generate-failure       Do not fail when Generate returns an error',
    '  --dry-run                      Print resolved config',
    '  --self-test                    Run parser self-test',
  ].join('\n');
}

function runSelfTest() {
  const parsed = parseArgs([
    '--runs', '4',
    '--concurrency', '2',
    '--model-id', 'gpt-5.5',
    '--expect-ready',
    '--min-candidate-audits', '8',
    '--prep-trial',
  ]);
  if (
    parsed.runs !== 4
    || parsed.concurrency !== 2
    || parsed.modelId !== 'gpt-5.5'
    || parsed.expectReady !== true
    || parsed.minCandidateAudits !== 8
    || parsed.prepTrial !== true
    || parsed.minPrepMatches !== 4
  ) {
    throw new Error('self-test parser failed');
  }
}

function publicConfig(config) {
  return {
    runs: config.runs,
    concurrency: config.concurrency,
    provider: config.provider,
    model_id: config.modelId,
    timeout_ms: config.timeoutMs,
    port: config.port,
    max_generate_ms: config.maxGenerateMs,
    min_candidate_audits: config.minCandidateAudits,
    max_candidate_mismatches: config.maxCandidateMismatches,
    max_candidate_fallbacks: config.maxCandidateFallbacks,
    min_prep_matches: config.minPrepMatches,
    prep_trial: config.prepTrial,
    expect_ready: config.expectReady,
    expect_success: config.expectSuccess,
    rust_hub_root: ROOT_DIR,
  };
}

function resolveXHubSystemRoot() {
  const explicit = safeString(process.env.XHUB_SYSTEM_ROOT);
  if (explicit) return explicit;
  const candidates = [
    path.resolve(ROOT_DIR, '..', '..', 'x-hub-system'),
    path.resolve(ROOT_DIR, '..', '..', '..', '..', 'x-hub-system'),
    '/Users/andrew.xie/Documents/AX/x-hub-system',
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'services.js'))) {
      return candidate;
    }
  }
  return candidates[0];
}

function resolveNodeHubSourceDir(sourceRoot = resolveXHubSystemRoot()) {
  const explicit = safeString(process.env.XHUB_NODE_HUB_SRC_DIR || process.env.XHUB_HUB_GRPC_SERVER_SRC_DIR);
  const candidates = [
    explicit,
    path.join(sourceRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src'),
    path.join(sourceRoot, 'hub_grpc_server', 'src'),
    path.resolve(ROOT_DIR, '..', 'hub_grpc_server', 'src'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'services.js'))) return candidate;
  }
  return candidates[0];
}

async function importFromSource(srcDir, fileName) {
  return await import(pathToFileURL(path.join(srcDir, fileName)).href);
}

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function cleanupPath(target) {
  try {
    fs.rmSync(target, { recursive: true, force: true });
  } catch {
    // ignore
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

function parseJsonObject(raw) {
  try {
    const parsed = JSON.parse(String(raw || '{}'));
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
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

function startFakeBridge({ bridgeBaseDir, responseText, pollMs }) {
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
      const reqId = safeString(req?.req_id || req?.request_id);
      if (!reqId || seen.has(reqId)) continue;
      seen.add(reqId);
      requests.push(req);
      if (safeString(req?.type) !== 'ai_generate') continue;
      writeJsonAtomic(path.join(paths.respDir, `resp_${reqId}.json`), {
        ok: true,
        status: 200,
        text: responseText,
        usage: {
          prompt_tokens: 8,
          completion_tokens: 6,
          total_tokens: 14,
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
    'Rust Model Route Candidate Runner Paid Model',
    'paid_online',
    'openai',
    128000,
    1,
    1,
    Date.now()
  );
}

function makeClientEntry(modelId) {
  const capabilities = ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'];
  return {
    device_id: 'dev-rust-model-route-candidate-runner',
    user_id: 'user-rust-model-route-candidate-runner',
    name: 'Rust Model Route Candidate Runner',
    token: `tok_rust_model_route_candidate_${process.pid}_${Date.now()}`,
    enabled: true,
    capabilities,
    policy_mode: 'new_profile',
    approved_trust_profile: {
      schema_version: 'hub.paired_terminal_trust_profile.v1',
      device_id: 'dev-rust-model-route-candidate-runner',
      device_name: 'Rust Model Route Candidate Runner',
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
        allowed_model_ids: [modelId],
      },
      network_policy: {
        default_web_fetch_enabled: true,
      },
      budget_policy: {
        daily_token_limit: 100000,
        single_request_token_limit: 100000,
      },
      audit_ref: 'audit-rust-model-route-candidate-runner',
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
      const key = safeString(event);
      if (!key || typeof handler !== 'function') return this;
      const list = handlers.get(key) || [];
      list.push(handler);
      handlers.set(key, list);
      return this;
    },
  };
}

function summarizeGenerateCall(call, durationMs) {
  const writes = Array.isArray(call?.writes) ? call.writes : [];
  const done = [...writes].reverse().find((item) => item?.done)?.done || null;
  const error = [...writes].reverse().find((item) => item?.error)?.error || null;
  const deltas = writes.filter((item) => item?.delta);
  return {
    ended: call?.ended === true,
    duration_ms: durationMs,
    write_count: writes.length,
    delta_count: deltas.length,
    delta_text: deltas.map((item) => safeString(item?.delta?.text)).join(''),
    done_ok: done?.ok === true,
    done_reason: safeString(done?.reason),
    actual_model_id: safeString(done?.actual_model_id),
    execution_path: safeString(done?.execution_path),
    runtime_provider: safeString(done?.runtime_provider),
    error_code: safeString(error?.error?.code || error?.code),
  };
}

function findAuditEvent(db, { requestId, eventType }) {
  return (db.listAuditEvents({ request_id: requestId }) || [])
    .find((item) => safeString(item?.event_type) === safeString(eventType)) || null;
}

function emptyCandidateAuditStats(expected = 0) {
  return {
    expected,
    total: 0,
    ok_events: 0,
    not_ok_events: 0,
    missing: 0,
    schema_mismatch: 0,
    model_mismatch: 0,
    route_kind_mismatch: 0,
    match_unknown: 0,
    fallback: 0,
    secret_leak: 0,
  };
}

function addCandidateAuditStats(target, next) {
  for (const key of Object.keys(emptyCandidateAuditStats())) {
    target[key] = Number(target[key] || 0) + Number(next?.[key] || 0);
  }
  return target;
}

function evaluateCandidateAuditRow(row) {
  if (!row) {
    return {
      present: false,
      ok: false,
      ext: {},
      secret_leak: false,
      schema_ok: false,
      selected_model_match: false,
      route_kind_match: false,
      match_known: false,
      fallback: false,
    };
  }
  const ext = parseJsonObject(row.ext_json);
  const serializedExt = JSON.stringify(ext);
  return {
    present: true,
    ok: row.ok === 1,
    ext,
    secret_leak: serializedExt.includes(PROVIDER_SECRET_SENTINEL) || /"api_key"\s*:/.test(serializedExt),
    schema_ok: ext?.schema_version === CANDIDATE_AUDIT_EXT_SCHEMA,
    selected_model_match: ext?.match?.selected_model_match === true,
    route_kind_match: ext?.match?.route_kind_match === true,
    match_known: ext?.match?.match_known === true,
    fallback: ext?.rust?.fallback === true,
  };
}

function summarizeCandidateAuditStats(stats) {
  return {
    expected: Number(stats?.expected || 0),
    total: Number(stats?.total || 0),
    ok_events: Number(stats?.ok_events || 0),
    not_ok_events: Number(stats?.not_ok_events || 0),
    missing: Number(stats?.missing || 0),
    schema_mismatch: Number(stats?.schema_mismatch || 0),
    model_mismatch: Number(stats?.model_mismatch || 0),
    route_kind_mismatch: Number(stats?.route_kind_mismatch || 0),
    match_unknown: Number(stats?.match_unknown || 0),
    fallback: Number(stats?.fallback || 0),
    secret_leak: Number(stats?.secret_leak || 0),
  };
}

function buildCandidateAuditReadiness({ config, stats, maxGenerateMs }) {
  const summary = summarizeCandidateAuditStats(stats);
  const minAudits = Math.max(Number(config.minCandidateAudits || 0), summary.expected);
  const checks = [
    {
      name: 'candidate_audit_min_events',
      ok: summary.total >= minAudits,
      actual: summary.total,
      threshold: minAudits,
      detail: 'candidate audit events must cover every Generate request in this run',
    },
    {
      name: 'candidate_audit_missing',
      ok: summary.missing === 0,
      actual: summary.missing,
      threshold: 0,
      detail: 'each Generate request must have one model route candidate audit event',
    },
    {
      name: 'candidate_audit_schema',
      ok: summary.schema_mismatch === 0,
      actual: summary.schema_mismatch,
      threshold: 0,
      detail: 'candidate audit ext schema must match the readiness contract',
    },
    {
      name: 'candidate_audit_not_ok',
      ok: summary.not_ok_events === 0,
      actual: summary.not_ok_events,
      threshold: 0,
      detail: 'candidate audit events must be stored as ok',
    },
    {
      name: 'candidate_audit_model_mismatch',
      ok: summary.model_mismatch <= config.maxCandidateMismatches,
      actual: summary.model_mismatch,
      threshold: config.maxCandidateMismatches,
      detail: 'Rust selected model must match Node selected model',
    },
    {
      name: 'candidate_audit_route_kind_mismatch',
      ok: summary.route_kind_mismatch <= config.maxCandidateMismatches,
      actual: summary.route_kind_mismatch,
      threshold: config.maxCandidateMismatches,
      detail: 'Rust selected route kind must match Node selected route kind',
    },
    {
      name: 'candidate_audit_match_unknown',
      ok: summary.match_unknown === 0,
      actual: summary.match_unknown,
      threshold: 0,
      detail: 'Node/Rust selected model and route-kind match must be known',
    },
    {
      name: 'candidate_audit_fallback',
      ok: summary.fallback <= config.maxCandidateFallbacks,
      actual: summary.fallback,
      threshold: config.maxCandidateFallbacks,
      detail: 'Rust candidate route should not fall back during readiness runs',
    },
    {
      name: 'candidate_audit_secret_leak',
      ok: summary.secret_leak === 0,
      actual: summary.secret_leak,
      threshold: 0,
      detail: 'candidate audit ext must not include provider API keys',
    },
    {
      name: 'generate_latency_max_ms',
      ok: maxGenerateMs <= config.maxGenerateMs,
      actual: maxGenerateMs,
      threshold: config.maxGenerateMs,
      detail: 'Generate hot path must stay within the configured latency gate',
    },
  ];
  const ready = checks.every((check) => check.ok === true);
  return {
    schema_version: 'xhub.model_route_candidate_audit_readiness.v1',
    component: 'model_route',
    decision: ready ? 'ready' : 'not_ready',
    ready,
    generated_at_ms: Date.now(),
    expected_request_count: summary.expected,
    thresholds: {
      min_candidate_audits: minAudits,
      max_candidate_mismatches: config.maxCandidateMismatches,
      max_candidate_fallbacks: config.maxCandidateFallbacks,
      max_generate_ms: config.maxGenerateMs,
    },
    audit: summary,
    checks,
  };
}

function countPrepMatches(logs) {
  return (Array.isArray(logs) ? logs : [])
    .filter((line) => safeString(line).includes('rust model route prep match'))
    .length;
}

function countPrepWarnings(warnings) {
  return (Array.isArray(warnings) ? warnings : [])
    .filter((line) => safeString(line).includes('rust model route prep'))
    .length;
}

function buildPrepTrialReadiness({ config, prepMatchCount, prepWarningCount, authorityPayloadsOk, maxGenerateMs }) {
  const checks = [
    {
      name: 'prep_match_min_events',
      ok: prepMatchCount >= config.minPrepMatches,
      actual: prepMatchCount,
      threshold: config.minPrepMatches,
      detail: 'prep trial must observe Rust/Node selected model matches',
    },
    {
      name: 'prep_warnings',
      ok: prepWarningCount === 0,
      actual: prepWarningCount,
      threshold: 0,
      detail: 'prep trial must not emit route mismatch, no-selection, or failure warnings',
    },
    {
      name: 'node_remote_payload_authority',
      ok: authorityPayloadsOk === true,
      actual: authorityPayloadsOk === true ? 1 : 0,
      threshold: 1,
      detail: 'remote Bridge payload model and provider account must remain Node-selected',
    },
    {
      name: 'generate_latency_max_ms',
      ok: maxGenerateMs <= config.maxGenerateMs,
      actual: maxGenerateMs,
      threshold: config.maxGenerateMs,
      detail: 'Generate hot path must stay within the configured latency gate',
    },
  ];
  const ready = checks.every((check) => check.ok === true);
  return {
    schema_version: 'xhub.model_route_remote_prep_trial_readiness.v1',
    component: 'model_route',
    route_kind: 'remote',
    decision: ready ? 'ready' : 'not_ready',
    ready,
    generated_at_ms: Date.now(),
    expected_request_count: config.runs * config.concurrency,
    thresholds: {
      min_prep_matches: config.minPrepMatches,
      max_generate_ms: config.maxGenerateMs,
    },
    prep_match_count: prepMatchCount,
    prep_warning_count: prepWarningCount,
    node_authority_preserved: authorityPayloadsOk === true,
    checks,
  };
}

async function waitForCondition({ timeoutMs, pollMs = 20, label, predicate }) {
  const started = Date.now();
  while (Date.now() - started <= timeoutMs) {
    if (predicate()) return true;
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  throw new Error(`${label} did not complete within ${timeoutMs}ms`);
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-20).join('\n');
}

function startXhubd({ runtimeBaseDir, dbPath, port }) {
  const env = {
    ...process.env,
    XHUB_RUST_HUB_HTTP_PORT: String(port),
    XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY: '0',
    XHUB_RUST_HTTP_ACCESS_KEY: '',
    XHUB_RUST_HTTP_ACCESS_KEY_FILE: '',
    XHUB_RUST_HUB_ACCESS_KEY: '',
    XHUB_RUST_HUB_ACCESS_KEY_FILE: '',
    XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT: '0',
    XHUB_RUST_HUB_PUBLIC_BASE_URL: '',
    XHUB_RUST_HUB_PUBLIC_HOST: '',
    XHUB_RUST_HUB_PUBLIC_ENDPOINT: '0',
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_DB_PATH: dbPath,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
  };
  const packagedRunner = path.join(ROOT_DIR, 'bin', 'xhubd');
  const child = fs.existsSync(packagedRunner)
    ? spawn(packagedRunner, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] })
    : spawn('cargo', ['run', '--bin', 'xhubd', '--', 'serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });

  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });
  return { child, output };
}

function httpJson(method, url, body = undefined, timeoutMs = 1000) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
    const req = http.request(url, {
      method,
      timeout: timeoutMs,
      headers: {
        accept: 'application/json',
        ...(data ? { 'content-type': 'application/json', 'content-length': String(data.length) } : {}),
      },
    }, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { raw += chunk; });
      res.on('end', () => {
        if ((res.statusCode || 0) < 200 || (res.statusCode || 0) >= 300) {
          reject(new Error(`http_status:${res.statusCode}:${raw.slice(0, 400)}`));
          return;
        }
        try {
          resolve(JSON.parse(raw));
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${raw.slice(0, 400)}`));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('http_timeout')));
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function waitForHealth(baseUrl, child, output, timeoutMs) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (child.exitCode !== null) {
      throw new Error(`xhubd exited before health was ready: ${child.exitCode}\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
    }
    try {
      await httpJson('GET', `${baseUrl}/health`, undefined, 750);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
}

async function stopChild(child) {
  if (!child || child.exitCode !== null) return;
  const exited = new Promise((resolve) => child.once('exit', resolve));
  child.kill('SIGTERM');
  await Promise.race([
    exited,
    new Promise((resolve) => setTimeout(resolve, 1000)),
  ]);
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    console.log(usage());
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    console.log('model_route_generate_candidate_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.model_route_generate_candidate_runner.dry_run.v1',
      config: publicConfig(config),
    }, null, 2));
    return;
  }

  const sourceRoot = resolveXHubSystemRoot();
  const srcDir = resolveNodeHubSourceDir(sourceRoot);
  if (!fs.existsSync(path.join(srcDir, 'services.js'))) {
    throw new Error(`Node Hub source not found: ${srcDir}`);
  }

  const [
    { HubDB },
    { HubEventBus },
    { makeServices },
    { addProviderKey, invalidateProviderKeyCache },
    { createModelRouteAuthorityBridge },
  ] = await Promise.all([
    importFromSource(srcDir, 'db.js'),
    importFromSource(srcDir, 'event_bus.js'),
    importFromSource(srcDir, 'services.js'),
    importFromSource(srcDir, 'provider_key_store.js'),
    importFromSource(srcDir, 'rust_model_route_authority_bridge.js'),
  ]);

  const tempRoot = makeTempDir('xhub-model-route-candidate-runner-');
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const bridgeBaseDir = path.join(tempRoot, 'bridge');
  const nodeDbPath = path.join(tempRoot, 'node_hub.sqlite3');
  const rustDbPath = path.join(tempRoot, 'rust_hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${config.port}`;
  let db = null;
  let fakeBridge = null;
  let child = null;

  const logs = [];
  const warnings = [];
  invalidateProviderKeyCache();

  try {
    fs.mkdirSync(runtimeBaseDir, { recursive: true });
    fs.mkdirSync(bridgeBaseDir, { recursive: true });
    const started = startXhubd({ runtimeBaseDir, dbPath: rustDbPath, port: config.port });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, config.timeoutMs);

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
      XHUB_RUST_HUB_ROOT: ROOT_DIR,
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE: config.prepTrial ? '0' : '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS: '0',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: config.prepTrial ? '1' : null,
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_THROTTLE_MS: config.prepTrial ? '0' : null,
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT: config.prepTrial ? String(Math.max(1, config.concurrency)) : null,
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL: baseUrl,
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS: '0',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_MAX_MISMATCHES: '0',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_VERBOSE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE: null,
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: null,
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: null,
      XHUB_RUST_SCHEDULER_AUTHORITY: null,
      XHUB_RUST_SCHEDULER_STATUS_READ: null,
    }, async () => {
      db = new HubDB({ dbPath: nodeDbPath });
      insertPaidModel(db, config.modelId);
      const clientEntry = makeClientEntry(config.modelId);
      writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
      const addResult = addProviderKey(runtimeBaseDir, {
        provider: config.provider,
        api_key: PROVIDER_SECRET_SENTINEL,
        auth_type: 'api_key',
        models: [config.modelId],
        base_url: 'https://api.openai.com',
        priority: 10,
      });
      if (!addResult.ok) {
        throw new Error(`addProviderKey failed: ${addResult.error || 'unknown_error'}`);
      }
      fakeBridge = startFakeBridge({
        bridgeBaseDir,
        responseText: 'model route candidate runner ok',
        pollMs: config.bridgePollMs,
      });

      const realModelBridge = createModelRouteAuthorityBridge({
        env: process.env,
        logger: {
          log: (line) => logs.push(safeString(line)),
          warn: (line) => warnings.push(safeString(line)),
        },
      });
      const modelRouteAuthorityBridge = {
        config: realModelBridge.config,
        candidateRoute(input) {
          return realModelBridge.candidateRoute(input);
        },
        prepRoute(input) {
          return realModelBridge.prepRoute(input);
        },
      };
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        modelRouteAuthorityBridge,
      });

      const iterations = [];
      const candidateAuditAggregate = emptyCandidateAuditStats(0);
      console.log(JSON.stringify({
        event: 'start',
        schema_version: 'xhub.model_route_generate_candidate_runner.event.v1',
        config: publicConfig(config),
        runtime_base_dir: runtimeBaseDir,
        rust_db_path: rustDbPath,
        http_base_url: baseUrl,
      }));

      for (let runIndex = 0; runIndex < config.runs; runIndex += 1) {
        const batchStartedAt = Date.now();
        const batch = await Promise.all(
          Array.from({ length: config.concurrency }, async (_, requestIndex) => {
            const requestId = `gen_model_route_candidate_${runIndex + 1}_${requestIndex + 1}`;
            const call = makeGenerateCall({
              token: clientEntry.token,
              request: {
                request_id: requestId,
                model_id: config.modelId,
                max_tokens: 32,
                temperature: 0.1,
                top_p: 0.95,
                messages: [{ role: 'user', content: `hello model route candidate ${runIndex + 1}/${requestIndex + 1}` }],
                client: {
                  device_id: clientEntry.device_id,
                  user_id: clientEntry.user_id,
                  app_id: 'xt-model-route-candidate-runner',
                  project_id: 'project-model-route-candidate-runner',
                },
              },
            });
            const startedAt = Date.now();
            await impl.HubAI.Generate(call);
            return {
              request_id: requestId,
              generate: summarizeGenerateCall(call, Date.now() - startedAt),
            };
          })
        );

        let candidateAuditWaitCompleted = false;
        const candidateStats = emptyCandidateAuditStats(config.prepTrial ? 0 : batch.length);
        if (!config.prepTrial) {
          candidateAuditWaitCompleted = await waitForCondition({
            timeoutMs: config.timeoutMs,
            label: 'model route candidate audit events',
            predicate: () => batch.every((result) => {
              const row = findAuditEvent(db, {
                requestId: result.request_id,
                eventType: CANDIDATE_AUDIT_EVENT_TYPE,
              });
              return !!row;
            }),
          }).catch(() => false);

          for (const result of batch) {
            const row = findAuditEvent(db, {
              requestId: result.request_id,
              eventType: CANDIDATE_AUDIT_EVENT_TYPE,
            });
            const evaluation = evaluateCandidateAuditRow(row);
            if (!evaluation.present) candidateStats.missing += 1;
            else candidateStats.total += 1;
            if (evaluation.ok) candidateStats.ok_events += 1;
            else candidateStats.not_ok_events += 1;
            if (!evaluation.schema_ok) candidateStats.schema_mismatch += 1;
            if (!evaluation.selected_model_match) candidateStats.model_mismatch += 1;
            if (!evaluation.route_kind_match) candidateStats.route_kind_mismatch += 1;
            if (!evaluation.match_known) candidateStats.match_unknown += 1;
            if (evaluation.fallback) candidateStats.fallback += 1;
            if (evaluation.secret_leak) candidateStats.secret_leak += 1;
          }
          addCandidateAuditStats(candidateAuditAggregate, candidateStats);
        }

        const bridgeRequests = fakeBridge.requests.slice(-config.concurrency);
        const bridgePayloadsOk = bridgeRequests.every((request) => (
          safeString(request?.model_id) === config.modelId
          && safeString(request?.provider_key?.account_key) === addResult.account_key
          && safeString(request?.provider_key?.provider) === config.provider
        ));
        const item = {
          run_index: runIndex + 1,
          request_count: batch.length,
          duration_ms: Date.now() - batchStartedAt,
          generate_ok: batch.every((result) => result.generate.done_ok === true),
          max_generate_ms: Math.max(...batch.map((result) => result.generate.duration_ms)),
          bridge_payloads_ok: bridgePayloadsOk,
          candidate_audit_count: candidateStats.total,
          candidate_audit_wait_completed: candidateAuditWaitCompleted,
          candidate_audit_ok: config.prepTrial || (
            candidateStats.total === candidateStats.expected
            && candidateStats.missing === 0
            && candidateStats.not_ok_events === 0
            && candidateStats.schema_mismatch === 0
            && candidateStats.model_mismatch === 0
            && candidateStats.route_kind_mismatch === 0
            && candidateStats.match_unknown === 0
            && candidateStats.fallback === 0
            && candidateStats.secret_leak === 0
          ),
          prep_match_count: countPrepMatches(logs),
          candidate_audit_stats: summarizeCandidateAuditStats(candidateStats),
          warnings: warnings.length,
          requests: batch,
        };
        iterations.push(item);
        console.log(JSON.stringify({ event: 'iteration', ...item }));
      }

      if (config.prepTrial) {
        await waitForCondition({
          timeoutMs: config.timeoutMs,
          label: 'model route prep match logs',
          predicate: () => countPrepMatches(logs) >= config.minPrepMatches,
        }).catch(() => false);
      }

      const allGenerateOk = iterations.every((item) => item.generate_ok && item.bridge_payloads_ok);
      const allCandidateAuditOk = config.prepTrial
        || iterations.every((item) => item.candidate_audit_ok && item.candidate_audit_count === item.request_count);
      const maxGenerateMs = Math.max(...iterations.map((item) => item.max_generate_ms));
      const candidateAuditReadiness = buildCandidateAuditReadiness({
        config,
        stats: candidateAuditAggregate,
        maxGenerateMs,
      });
      const prepMatchCount = countPrepMatches(logs);
      const prepWarningCount = countPrepWarnings(warnings);
      const prepTrialReadiness = buildPrepTrialReadiness({
        config,
        prepMatchCount,
        prepWarningCount,
        authorityPayloadsOk: allGenerateOk,
        maxGenerateMs,
      });
      const ok = (!config.expectSuccess || allGenerateOk)
        && allCandidateAuditOk
        && (!config.expectReady || (config.prepTrial ? prepTrialReadiness.ready === true : candidateAuditReadiness.ready === true))
        && (config.prepTrial ? prepWarningCount === 0 : warnings.length === 0)
        && maxGenerateMs <= config.maxGenerateMs;

      const finalPayload = {
        event: 'stop',
        ok,
        schema_version: 'xhub.model_route_generate_candidate_runner.result.v1',
        generate_ok: allGenerateOk,
        max_generate_ms: maxGenerateMs,
        prep_trial: config.prepTrial,
        prep_match_count: prepMatchCount,
        prep_warning_count: prepWarningCount,
        prep_readiness: config.prepTrial ? prepTrialReadiness : null,
        node_authority_preserved: allGenerateOk,
        candidate_audit_count: candidateAuditAggregate.total,
        candidate_audit_stats: summarizeCandidateAuditStats(candidateAuditAggregate),
        candidate_audit_ok: allCandidateAuditOk,
        candidate_readiness: candidateAuditReadiness,
        warnings,
        logs,
        bridge_requests: fakeBridge.requests.map((request) => ({
          req_id: safeString(request?.req_id),
          model_id: safeString(request?.model_id),
          provider_key_account_key: safeString(request?.provider_key?.account_key),
          provider_key_provider: safeString(request?.provider_key?.provider),
        })),
        iterations,
        runtime_base_dir: runtimeBaseDir,
        rust_db_path: rustDbPath,
        http_base_url: baseUrl,
      };
      console.log(JSON.stringify(finalPayload, null, 2));
      if (!ok) process.exitCode = 2;
    });
  } finally {
    if (fakeBridge) fakeBridge.stop();
    if (db) db.close();
    await stopChild(child);
    cleanupPath(tempRoot);
    invalidateProviderKeyCache();
  }
}

main().catch((error) => {
  console.error(`[model_route_generate_candidate_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
