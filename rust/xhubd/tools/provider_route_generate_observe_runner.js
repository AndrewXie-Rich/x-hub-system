#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const CANDIDATE_AUDIT_EVENT_TYPE = 'ai.generate.provider_route_candidate';
const CANDIDATE_AUDIT_EXT_SCHEMA = 'xhub.rust_provider_route_candidate.audit.v1';
const PROVIDER_SECRET_SENTINEL = 'sk-provider-observe-runner';

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
    runs: 5,
    concurrency: 1,
    provider: 'openai',
    modelId: 'gpt-4o',
    timeoutMs: 30000,
    bridgePollMs: 10,
    observeThrottleMs: 0,
    observeMaxInFlight: 2,
    maxGenerateMs: 2000,
    enableCandidateAudit: false,
    expectCandidateReady: false,
    minCandidateAudits: 0,
    maxCandidateMismatches: 0,
    maxCandidateFallbacks: 0,
    expectSuccess: true,
    expectObserved: true,
    expectZeroWarnings: true,
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
      case '--bridge-poll-ms':
        out.bridgePollMs = parseIntInRange(next, out.bridgePollMs, 5, 5000);
        i += 1;
        break;
      case '--observe-throttle-ms':
        out.observeThrottleMs = parseIntInRange(next, out.observeThrottleMs, 0, 60000);
        i += 1;
        break;
      case '--observe-max-in-flight':
        out.observeMaxInFlight = parseIntInRange(next, out.observeMaxInFlight, 1, 16);
        i += 1;
        break;
      case '--max-generate-ms':
        out.maxGenerateMs = parseIntInRange(next, out.maxGenerateMs, 100, 300000);
        i += 1;
        break;
      case '--enable-candidate-audit':
        out.enableCandidateAudit = true;
        break;
      case '--expect-candidate-ready':
        out.expectCandidateReady = true;
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
      case '--allow-generate-failure':
        out.expectSuccess = false;
        break;
      case '--allow-no-observe':
        out.expectObserved = false;
        break;
      case '--allow-warnings':
        out.expectZeroWarnings = false;
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
  return out;
}

function usage() {
  return [
    'provider_route_generate_observe_runner.js',
    '',
    'Options:',
    '  --runs <n>                    Generate batches, default 5',
    '  --concurrency <n>             Parallel Generate calls per batch, default 1',
    '  --model-id <id>               Model ID, default gpt-4o',
    '  --provider <id>               Provider, default openai',
    '  --observe-throttle-ms <n>     Authority observe throttle, default 0',
    '  --observe-max-in-flight <n>   Authority observe max in-flight, default 2',
    '  --max-generate-ms <n>         Per-call latency gate, default 2000',
    '  --enable-candidate-audit      Enable Rust candidate audit evidence',
    '  --expect-candidate-ready      Fail unless candidate audit readiness is ready',
    '  --min-candidate-audits <n>    Readiness minimum candidate audit events',
    '  --max-candidate-mismatches <n> Readiness account mismatch threshold, default 0',
    '  --max-candidate-fallbacks <n> Readiness fallback threshold, default 0',
    '  --allow-generate-failure      Do not fail when Generate returns an error',
    '  --allow-no-observe            Do not fail when no observe call starts',
    '  --allow-warnings              Do not fail on observe warnings',
    '  --dry-run                     Print resolved config',
    '  --self-test                   Run parser self-test',
  ].join('\n');
}

function runSelfTest() {
  const parsed = parseArgs([
    '--runs', '3',
    '--concurrency', '2',
    '--observe-throttle-ms', '100',
    '--enable-candidate-audit',
    '--expect-candidate-ready',
    '--min-candidate-audits', '3',
    '--allow-warnings',
  ]);
  if (
    parsed.runs !== 3
    || parsed.concurrency !== 2
    || parsed.observeThrottleMs !== 100
    || parsed.enableCandidateAudit !== true
    || parsed.expectCandidateReady !== true
    || parsed.minCandidateAudits !== 3
    || parsed.expectZeroWarnings !== false
  ) {
    throw new Error('self-test parser failed');
  }
}

function publicConfig(config) {
  const observeRequired = config.expectObserved && !config.enableCandidateAudit;
  return {
    runs: config.runs,
    concurrency: config.concurrency,
    provider: config.provider,
    model_id: config.modelId,
    timeout_ms: config.timeoutMs,
    observe_throttle_ms: config.observeThrottleMs,
    observe_max_in_flight: config.observeMaxInFlight,
    max_generate_ms: config.maxGenerateMs,
    enable_candidate_audit: config.enableCandidateAudit,
    expect_candidate_ready: config.expectCandidateReady,
    min_candidate_audits: config.minCandidateAudits,
    max_candidate_mismatches: config.maxCandidateMismatches,
    max_candidate_fallbacks: config.maxCandidateFallbacks,
    expect_success: config.expectSuccess,
    expect_observed: config.expectObserved,
    observe_required: observeRequired,
    expect_zero_warnings: config.expectZeroWarnings,
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
    account_mismatch: 0,
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
      selected_account_match: false,
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
    secret_leak: serializedExt.includes(PROVIDER_SECRET_SENTINEL),
    schema_ok: ext?.schema_version === CANDIDATE_AUDIT_EXT_SCHEMA,
    selected_account_match: ext?.match?.selected_account_match === true,
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
    account_mismatch: Number(stats?.account_mismatch || 0),
    match_unknown: Number(stats?.match_unknown || 0),
    fallback: Number(stats?.fallback || 0),
    secret_leak: Number(stats?.secret_leak || 0),
  };
}

function buildCandidateAuditReadiness({ config, stats, maxGenerateMs }) {
  const summary = summarizeCandidateAuditStats(stats);
  const minAudits = config.enableCandidateAudit
    ? Math.max(Number(config.minCandidateAudits || 0), summary.expected)
    : Number(config.minCandidateAudits || 0);
  const checks = [
    {
      name: 'candidate_audit_enabled',
      ok: config.enableCandidateAudit === true,
      actual: config.enableCandidateAudit === true ? 1 : 0,
      threshold: 1,
      detail: 'candidate audit collection must be explicitly enabled',
    },
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
      detail: 'each Generate request must have one candidate audit event',
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
      name: 'candidate_audit_account_mismatch',
      ok: summary.account_mismatch <= config.maxCandidateMismatches,
      actual: summary.account_mismatch,
      threshold: config.maxCandidateMismatches,
      detail: 'Rust selected account must match the Node-selected account',
    },
    {
      name: 'candidate_audit_match_unknown',
      ok: summary.match_unknown === 0,
      actual: summary.match_unknown,
      threshold: 0,
      detail: 'Node/Rust selected account match must be known',
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
    schema_version: 'xhub.provider_route_candidate_audit_readiness.v1',
    component: 'provider_route',
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
    'Rust Provider Observe Runner Paid Model',
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
    device_id: 'dev-rust-provider-observe-runner',
    user_id: 'user-rust-provider-observe-runner',
    name: 'Rust Provider Observe Runner',
    token: `tok_rust_provider_observe_${process.pid}_${Date.now()}`,
    enabled: true,
    capabilities,
    policy_mode: 'new_profile',
    approved_trust_profile: {
      schema_version: 'hub.paired_terminal_trust_profile.v1',
      device_id: 'dev-rust-provider-observe-runner',
      device_name: 'Rust Provider Observe Runner',
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
      audit_ref: 'audit-rust-provider-observe-runner',
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
    error_code: safeString(error?.error?.code || error?.code),
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

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    console.log(usage());
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    console.log('provider_route_generate_observe_runner self-test ok');
    return;
  }
  if (config.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.provider_route_generate_observe_runner.dry_run.v1',
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
    { createProviderRouteAuthorityBridge },
  ] = await Promise.all([
    importFromSource(srcDir, 'db.js'),
    importFromSource(srcDir, 'event_bus.js'),
    importFromSource(srcDir, 'services.js'),
    importFromSource(srcDir, 'provider_key_store.js'),
    importFromSource(srcDir, 'rust_provider_route_authority_bridge.js'),
  ]);

  const tempRoot = makeTempDir('xhub-provider-observe-runner-');
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const bridgeBaseDir = path.join(tempRoot, 'bridge');
  const nodeDbPath = path.join(tempRoot, 'node_hub.sqlite3');
  const rustDbPath = path.join(tempRoot, 'rust_hub.sqlite3');
  const runnerPath = path.join(ROOT_DIR, 'tools', 'run_rust_hub.command');
  let db = null;
  let fakeBridge = null;

  const logs = [];
  const warnings = [];
  const observeCalls = [];
  const execStats = {
    started: 0,
    completed: 0,
    failed: 0,
    route_started: 0,
  };
  const execFileTracked = (file, args, options, callback) => {
    execStats.started += 1;
    if (Array.isArray(args) && args[0] === 'provider' && args[1] === 'route') {
      execStats.route_started += 1;
    }
    execFile(file, args, options, (error, stdout, stderr) => {
      execStats.completed += 1;
      if (error) execStats.failed += 1;
      callback(error, stdout, stderr);
    });
  };

  invalidateProviderKeyCache();

  try {
    await withEnv({
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_BRIDGE_BASE_DIR: bridgeBaseDir,
      HUB_CLIENT_TOKEN: '',
      HUB_AUDIT_LEVEL: config.enableCandidateAudit ? 'full_content' : 'metadata_only',
      HUB_MEMORY_AT_REST_ENABLED: 'false',
      HUB_MEMORY_RETENTION_ENABLED: 'false',
      HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '50',
      HUB_BRIDGE_AI_TIMEOUT_SEC: '2',
      HUB_PAID_AI_QUEUE_TIMEOUT_MS: '500',
      HUB_DB_PATH: rustDbPath,
      XHUB_RUST_HUB_ROOT: ROOT_DIR,
      XHUB_RUST_HUB_RUNNER: runnerPath,
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: config.enableCandidateAudit ? '1' : null,
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: null,
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_THROTTLE_MS: String(config.observeThrottleMs),
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_MAX_IN_FLIGHT: String(config.observeMaxInFlight),
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_VERBOSE: '1',
      XHUB_RUST_SCHEDULER_AUTHORITY: null,
      XHUB_RUST_SCHEDULER_STATUS_READ: null,
    }, async () => {
      fs.mkdirSync(runtimeBaseDir, { recursive: true });
      fs.mkdirSync(bridgeBaseDir, { recursive: true });
      db = new HubDB({ dbPath: nodeDbPath });
      insertPaidModel(db, config.modelId);
      const clientEntry = makeClientEntry(config.modelId);
      writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
      const addResult = addProviderKey(runtimeBaseDir, {
        provider: config.provider,
        api_key: 'sk-provider-observe-runner',
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
        responseText: 'provider observe runner ok',
        pollMs: config.bridgePollMs,
      });

      const realBridge = createProviderRouteAuthorityBridge({
        env: process.env,
        execFileImpl: execFileTracked,
        logger: {
          log: (line) => logs.push(safeString(line)),
          warn: (line) => warnings.push(safeString(line)),
        },
      });
      const providerRouteAuthorityBridge = {
        config: realBridge.config,
        observeRoute(input) {
          const started = realBridge.observeRoute(input);
          observeCalls.push({
            started,
            at_ms: Date.now(),
            model_id: safeString(input?.modelId),
            provider: safeString(input?.provider),
            node_account_key: safeString(input?.nodeAccountKey),
          });
          return started;
        },
        candidateRoute(input) {
          return realBridge.candidateRoute(input);
        },
      };
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        providerRouteAuthorityBridge,
      });

      const iterations = [];
      const candidateAuditAggregate = emptyCandidateAuditStats(0);
      console.log(JSON.stringify({
        event: 'start',
        schema_version: 'xhub.provider_route_generate_observe_runner.event.v1',
        config: publicConfig(config),
        runtime_base_dir: runtimeBaseDir,
        rust_db_path: rustDbPath,
      }));

      for (let runIndex = 0; runIndex < config.runs; runIndex += 1) {
        const batchStartedAt = Date.now();
        const batch = await Promise.all(
          Array.from({ length: config.concurrency }, async (_, requestIndex) => {
            const requestId = `gen_provider_observe_${runIndex + 1}_${requestIndex + 1}`;
            const call = makeGenerateCall({
              token: clientEntry.token,
              request: {
                request_id: requestId,
                model_id: config.modelId,
                max_tokens: 32,
                temperature: 0.1,
                top_p: 0.95,
                messages: [{ role: 'user', content: `hello provider observe ${runIndex + 1}/${requestIndex + 1}` }],
                client: {
                  device_id: clientEntry.device_id,
                  user_id: clientEntry.user_id,
                  app_id: 'xt-provider-observe-runner',
                  project_id: 'project-provider-observe-runner',
                },
              },
            });
            const started = Date.now();
            await impl.HubAI.Generate(call);
            const durationMs = Date.now() - started;
            return {
              request_id: requestId,
              generate: summarizeGenerateCall(call, durationMs),
            };
          })
        );

        await waitForCondition({
          timeoutMs: config.timeoutMs,
          label: 'observe route work',
          predicate: () => execStats.completed >= execStats.started,
        });
        const candidateStats = emptyCandidateAuditStats(
          config.enableCandidateAudit ? batch.length : 0
        );
        let candidateAuditOk = true;
        let candidateAuditWaitCompleted = true;
        if (config.enableCandidateAudit) {
          candidateAuditWaitCompleted = await waitForCondition({
            timeoutMs: config.timeoutMs,
            label: 'candidate audit events',
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
            if (!evaluation.selected_account_match) candidateStats.account_mismatch += 1;
            if (!evaluation.match_known) candidateStats.match_unknown += 1;
            if (evaluation.fallback) candidateStats.fallback += 1;
            if (evaluation.secret_leak) candidateStats.secret_leak += 1;
          }
          candidateAuditOk = (
            candidateStats.total === candidateStats.expected
            && candidateStats.missing === 0
            && candidateStats.not_ok_events === 0
            && candidateStats.schema_mismatch === 0
            && candidateStats.account_mismatch === 0
            && candidateStats.match_unknown === 0
            && candidateStats.fallback === 0
            && candidateStats.secret_leak === 0
          );
          addCandidateAuditStats(candidateAuditAggregate, candidateStats);
        }

        const bridgeRequests = fakeBridge.requests.slice(-config.concurrency);
        const bridgePayloadsOk = bridgeRequests.every((request) => (
          safeString(request?.provider_key?.account_key) === addResult.account_key
          && safeString(request?.provider_key?.provider) === config.provider
        ));
        const item = {
          run_index: runIndex + 1,
          request_count: batch.length,
          duration_ms: Date.now() - batchStartedAt,
          generate_ok: batch.every((result) => result.generate.done_ok === true),
          max_generate_ms: Math.max(...batch.map((result) => result.generate.duration_ms)),
          bridge_payloads_ok: bridgePayloadsOk,
          observe_calls: observeCalls.length,
          observe_started: observeCalls.filter((call) => call.started === true).length,
          observe_skipped: observeCalls.filter((call) => call.started !== true).length,
          observe_exec_started: execStats.route_started,
          observe_exec_completed: execStats.completed,
          candidate_audit_count: candidateStats.total,
          candidate_audit_ok: candidateAuditOk,
          candidate_audit_wait_completed: candidateAuditWaitCompleted,
          candidate_audit_stats: summarizeCandidateAuditStats(candidateStats),
          warnings: warnings.length,
          requests: batch,
        };
        iterations.push(item);
        console.log(JSON.stringify({ event: 'iteration', ...item }));
      }

      const observeStarted = observeCalls.filter((call) => call.started === true).length;
      const observeRequired = config.expectObserved && !config.enableCandidateAudit;
      const allGenerateOk = iterations.every((item) => item.generate_ok && item.bridge_payloads_ok);
      const allCandidateAuditOk = !config.enableCandidateAudit
        || iterations.every((item) => item.candidate_audit_ok && item.candidate_audit_count === item.request_count);
      const maxGenerateMs = Math.max(...iterations.map((item) => item.max_generate_ms));
      const candidateAuditReadiness = buildCandidateAuditReadiness({
        config,
        stats: candidateAuditAggregate,
        maxGenerateMs,
      });
      const ok = (!config.expectSuccess || allGenerateOk)
        && (!observeRequired || observeStarted > 0)
        && allCandidateAuditOk
        && (!config.expectCandidateReady || candidateAuditReadiness.ready === true)
        && (!config.expectZeroWarnings || warnings.length === 0)
        && maxGenerateMs <= config.maxGenerateMs;

      const finalPayload = {
        event: 'stop',
        ok,
        schema_version: 'xhub.provider_route_generate_observe_runner.result.v1',
        generate_ok: allGenerateOk,
        max_generate_ms: maxGenerateMs,
        observe_calls: observeCalls.length,
        observe_started: observeStarted,
        observe_required: observeRequired,
        observe_skipped: observeCalls.length - observeStarted,
        observe_exec_started: execStats.route_started,
        observe_exec_completed: execStats.completed,
        observe_exec_failed: execStats.failed,
        candidate_audit_enabled: config.enableCandidateAudit,
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
      };
      console.log(JSON.stringify(finalPayload, null, 2));
      if (!ok) process.exitCode = 2;
    });
  } finally {
    if (fakeBridge) fakeBridge.stop();
    if (db) db.close();
    cleanupPath(tempRoot);
    invalidateProviderKeyCache();
  }
}

main().catch((error) => {
  console.error(`[provider_route_generate_observe_runner] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
