#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const SCHEMA = 'xhub.rust_hub.memory_gateway_model_call_live_canary_session.v1';
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'memory_gateway_model_call_live_canary');
const DEFAULT_HTTP_BASE_URL = 'http://127.0.0.1:50151';
const DEFAULT_LIVE_BASE_DIR = path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub', 'local');
const DEFAULT_ACCESS_KEY_FILE = path.join(
  os.homedir(),
  'Library',
  'Application Support',
  'AX',
  'rust-hub',
  'domain',
  'secrets',
  'xhubd_domain_access_key',
);
const DEFAULT_REPORT_MAX_AGE_MS = 2 * 60 * 60 * 1000;
const EXECUTE_SMOKE_STATUS_FILE = 'memory_gateway_model_call_execute_smoke_status.json';
const LOCAL_EXECUTOR_PREFIX = 'memory_gateway_model_call_local_executor_smoke_';

const LIVE_CANARY_ENV = {
  XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_ADMISSION: '1',
  XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION: '1',
  XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR: '1',
  XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY: '1',
  XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_ONLY: '1',
  XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_PROJECT_ID: 'xt-memory-gateway-live-canary',
  XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_REQUEST_PREFIX: 'memory_gateway_live_canary_',
  XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_AUDIT_PREFIX: 'memory_gateway_live_canary:',
};

const ROLLBACK_ENV_KEYS = Object.keys(LIVE_CANARY_ENV);

function safeString(value) {
  return String(value ?? '').trim();
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function utcStamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function parseArgs(argv) {
  const out = {
    mode: 'status',
    httpBaseUrl: safeString(process.env.XHUB_RUST_HTTP_BASE_URL || process.env.XHUBD_HTTP_BASE_URL) || DEFAULT_HTTP_BASE_URL,
    accessKeyFile: safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || process.env.XHUB_RUST_HUB_ACCESS_KEY_FILE) || DEFAULT_ACCESS_KEY_FILE,
    liveBaseDir: safeString(process.env.XHUB_RUST_LIVE_BASE_DIR || process.env.REL_FLOW_HUB_BASE_DIR) || DEFAULT_LIVE_BASE_DIR,
    opsGateReport: safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LIVE_CANARY_OPS_GATE_REPORT),
    cutoverReadinessPath: safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_CUTOVER_READINESS_PATH),
    executeSmokeStatusPath: safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SMOKE_STATUS_PATH),
    localExecutorSmokeReportPath: safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR_SMOKE_REPORT_PATH),
    reportPath: '',
    timeoutMs: 20000,
    reportMaxAgeMs: DEFAULT_REPORT_MAX_AGE_MS,
    maxSlowRequests: 0,
    requireCrossNetworkReady: false,
    help: false,
    selfTest: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--status':
        out.mode = 'status';
        break;
      case '--plan':
        out.mode = 'plan';
        break;
      case '--http-base-url':
        out.httpBaseUrl = safeString(next) || out.httpBaseUrl;
        i += 1;
        break;
      case '--access-key-file':
        out.accessKeyFile = safeString(next);
        i += 1;
        break;
      case '--live-base-dir':
      case '--hub-base-dir':
        out.liveBaseDir = safeString(next) || out.liveBaseDir;
        i += 1;
        break;
      case '--ops-gate-report':
        out.opsGateReport = safeString(next);
        i += 1;
        break;
      case '--cutover-readiness-path':
        out.cutoverReadinessPath = safeString(next);
        i += 1;
        break;
      case '--execute-smoke-status-path':
        out.executeSmokeStatusPath = safeString(next);
        i += 1;
        break;
      case '--local-executor-smoke-report-path':
        out.localExecutorSmokeReportPath = safeString(next);
        i += 1;
        break;
      case '--report-path':
        out.reportPath = safeString(next);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 250, 60000);
        i += 1;
        break;
      case '--report-max-age-ms':
        out.reportMaxAgeMs = parseIntInRange(next, out.reportMaxAgeMs, 0, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--max-slow-requests':
        out.maxSlowRequests = parseIntInRange(next, out.maxSlowRequests, 0, 1000000);
        i += 1;
        break;
      case '--require-cross-network-ready':
        out.requireCrossNetworkReady = true;
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
  out.liveBaseDir = path.resolve(out.liveBaseDir);
  if (!out.reportPath) {
    out.reportPath = path.join(STATE_DIR, `memory_gateway_model_call_live_canary_plan_${utcStamp()}.json`);
  }
  if (!path.isAbsolute(out.reportPath)) out.reportPath = path.resolve(ROOT_DIR, out.reportPath);
  return out;
}

function usage() {
  return [
    'memory_gateway_model_call_live_canary_session.js',
    '',
    'Builds a content-free, non-mutating live canary plan for Memory Gateway model-call execute.',
    'This first session tool does not set launchctl env or relaunch xhubd.',
    '',
    'Options:',
    '  --status                              Inspect current env and recent evidence paths',
    '  --plan                                Validate live canary preflight and write a plan report',
    '  --http-base-url <u>                   Live xhubd HTTP base URL, default 127.0.0.1:50151',
    '  --access-key-file <p>                 HTTP access key file',
    '  --live-base-dir <p>                   Live Rust Hub base dir',
    '  --ops-gate-report <p>                 Fresh ops-gate report from the live daemon',
    '  --cutover-readiness-path <p>           memory_gateway_cutover_readiness.json',
    '  --execute-smoke-status-path <p>        Live guarded execute smoke status JSON',
    '  --local-executor-smoke-report-path <p> Isolated local-executor smoke report JSON',
    '  --report-path <p>                     Output JSON report path',
    '  --timeout-ms <n>                      Live HTTP request timeout, default 20000',
    '  --report-max-age-ms <n>               Evidence freshness window, default 7200000',
    '  --max-slow-requests <n>               Allowed live recent slow requests, default 0',
    '  --require-cross-network-ready         Also require cross-network/domain readiness',
    '  --self-test                           Run in-memory validator self-test',
  ].join('\n');
}

function getLaunchctlEnv(key) {
  if (process.platform !== 'darwin') return '';
  const result = spawnSync('launchctl', ['getenv', key], { encoding: 'utf8' });
  if (result.status !== 0) return '';
  return safeString(result.stdout);
}

function envSnapshot() {
  const out = {};
  for (const key of ROLLBACK_ENV_KEYS) {
    out[key] = safeString(process.env[key]) || getLaunchctlEnv(key);
  }
  return out;
}

function envInspection() {
  const current = envSnapshot();
  const mismatchKeys = [];
  for (const [key, value] of Object.entries(LIVE_CANARY_ENV)) {
    if (String(current[key] || '') !== value) mismatchKeys.push(key);
  }
  return {
    desired_env: LIVE_CANARY_ENV,
    current_env: current,
    applied: mismatchKeys.length === 0,
    managed_key_count_present: Object.values(current).filter(Boolean).length,
    mismatch_keys: mismatchKeys,
    admission_enabled: current.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION === '1'
      || current.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_ADMISSION === '1',
    local_executor_enabled: current.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR === '1',
    execute_apply_enabled: current.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY === '1',
  };
}

function rollbackPlanFromEnv(current) {
  const actions = ROLLBACK_ENV_KEYS.map((key) => {
    const previous = safeString(current[key]);
    return previous
      ? { key, action: 'setenv', value: previous, command: `launchctl setenv ${key} ${previous}` }
      : { key, action: 'unsetenv', value: '', command: `launchctl unsetenv ${key}` };
  });
  return {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_live_canary_rollback_plan.v1',
    production_authority_change: false,
    restores_previous_launchctl_env: true,
    actions,
  };
}

function readJSON(filePath) {
  const resolved = safeString(filePath);
  if (!resolved || !fs.existsSync(resolved)) return null;
  try {
    return JSON.parse(fs.readFileSync(resolved, 'utf8'));
  } catch {
    return null;
  }
}

function latestReportPathInDir(dir, prefix) {
  const resolved = safeString(dir);
  if (!resolved || !fs.existsSync(resolved)) return '';
  try {
    const entries = fs.readdirSync(resolved)
      .filter((name) => name.startsWith(prefix) && name.endsWith('.json'))
      .map((name) => {
        const filePath = path.join(resolved, name);
        let mtimeMs = 0;
        try {
          mtimeMs = fs.statSync(filePath).mtimeMs;
        } catch {}
        return { filePath, mtimeMs };
      })
      .filter((entry) => entry.mtimeMs > 0)
      .sort((a, b) => b.mtimeMs - a.mtimeMs);
    return entries[0]?.filePath || '';
  } catch {
    return '';
  }
}

function uniquePaths(paths) {
  return Array.from(new Set(paths.map(safeString).filter(Boolean).map((item) => path.resolve(item))));
}

function candidatePaths(config, kind) {
  if (kind === 'ops_gate') {
    return uniquePaths([
      config.opsGateReport,
      '/private/tmp/xhub_ops_gate_after_local_executor_canary.json',
      latestReportPathInDir(path.join(config.liveBaseDir, 'reports'), 'daemon_ops_gate_'),
      latestReportPathInDir(path.join(ROOT_DIR, 'reports'), 'daemon_ops_gate_'),
    ]);
  }
  if (kind === 'cutover_readiness') {
    return uniquePaths([
      config.cutoverReadinessPath,
      path.join(config.liveBaseDir, 'memory_gateway_cutover_readiness.json'),
      path.join(ROOT_DIR, 'memory_gateway_cutover_readiness.json'),
    ]);
  }
  if (kind === 'execute_smoke') {
    return uniquePaths([
      config.executeSmokeStatusPath,
      path.join(config.liveBaseDir, EXECUTE_SMOKE_STATUS_FILE),
      path.join(ROOT_DIR, EXECUTE_SMOKE_STATUS_FILE),
    ]);
  }
  if (kind === 'local_executor_smoke') {
    return uniquePaths([
      config.localExecutorSmokeReportPath,
      '/private/tmp/memory_gateway_model_call_local_executor_smoke_latest.json',
      latestReportPathInDir(path.join(ROOT_DIR, 'reports'), LOCAL_EXECUTOR_PREFIX),
    ]);
  }
  return [];
}

function firstExistingPayload(config, kind) {
  const candidates = candidatePaths(config, kind);
  const found = candidates.find((item) => fs.existsSync(item));
  return {
    path: found || '',
    candidate_paths: candidates,
    payload: found ? readJSON(found) : null,
  };
}

function generatedAtMs(value) {
  const direct = Number(value?.generated_at_ms || 0);
  if (Number.isFinite(direct) && direct > 0) return direct;
  const iso = safeString(value?.generated_at_iso || value?.generated_at);
  const parsed = Date.parse(iso);
  return Number.isFinite(parsed) ? parsed : 0;
}

function freshnessSummary(payload, config, issueCodes) {
  const generated = generatedAtMs(payload);
  const ageMs = generated > 0 ? Math.max(0, Date.now() - generated) : null;
  if (!generated) issueCodes.push('evidence_missing_generated_at');
  if (ageMs !== null && config.reportMaxAgeMs > 0 && ageMs > config.reportMaxAgeMs) {
    issueCodes.push('evidence_stale');
  }
  return { generated_at_ms: generated || null, age_ms: ageMs };
}

function validateOpsGate(payload, pathValue, config) {
  const issueCodes = [];
  if (!payload) issueCodes.push('ops_gate_report_missing');
  else {
    if (payload.schema_version !== 'xhub.rust_hub.daemon_ops_gate.v1') issueCodes.push('ops_gate_schema_mismatch');
    if (payload.ok !== true) issueCodes.push('ops_gate_not_ok');
    if (payload.healthy !== true) issueCodes.push('ops_gate_health_not_ok');
    if (payload.ready !== true) issueCodes.push('ops_gate_readiness_not_ok');
    if (Array.isArray(payload.issues) && payload.issues.length > 0) issueCodes.push('ops_gate_has_issues');
    if (Number(payload.slow_requests || 0) > config.maxSlowRequests) issueCodes.push('ops_gate_slow_request_budget_exceeded');
    if (payload.ui_product_change === true || payload.swift_ui_files_touched === true || payload.rust_browser_product_ui === true) {
      issueCodes.push('ops_gate_ui_boundary_changed');
    }
    if (payload.production_authority_change === true || payload.daemon_restarted === true || payload.daemon_stopped === true) {
      issueCodes.push('ops_gate_unexpected_authority_or_daemon_change');
    }
    if (payload.node_remains_authority === true) issueCodes.push('node_still_marked_authority');
    if (payload.memory_writer_authority_in_rust !== true) issueCodes.push('memory_writer_not_rust_authority');
    if (payload.skills_execution_authority_in_rust !== true) issueCodes.push('skills_execution_not_rust_authority');
    if (payload.memory_gateway_cutover_readiness_ok !== true) issueCodes.push('memory_gateway_cutover_readiness_not_ok');
    if (payload.memory_gateway_model_call_execute_smoke_ok !== true) issueCodes.push('model_call_execute_guard_smoke_not_ok');
    if (payload.memory_gateway_model_call_execute_smoke_execution_blocked !== true) issueCodes.push('model_call_execute_guard_not_blocked');
    if (payload.memory_gateway_model_call_execute_smoke_content_free !== true) issueCodes.push('model_call_execute_guard_not_content_free');
    if (payload.memory_gateway_model_call_local_executor_smoke_ok !== true) issueCodes.push('local_executor_smoke_not_ok');
    if (payload.memory_gateway_model_call_local_executor_smoke_live_daemon_touched === true) issueCodes.push('local_executor_smoke_touched_live_daemon');
    if (payload.memory_gateway_model_call_local_executor_smoke_content_free !== true) issueCodes.push('local_executor_smoke_not_content_free');
    if (Number(payload.memory_gateway_model_call_local_executor_smoke_recent_slow_requests || 0) > 0) {
      issueCodes.push('local_executor_smoke_slow_requests_present');
    }
    if (payload.xt_file_ipc_run_once_smoke_ok !== true) issueCodes.push('xt_file_ipc_run_once_smoke_not_ok');
    if (payload.xt_file_ipc_background_watcher_smoke_ok !== true) issueCodes.push('xt_file_ipc_background_watcher_smoke_not_ok');
    if (payload.memory_writeback_candidate_queue_ready !== true) issueCodes.push('writeback_candidate_queue_not_ready');
    if (safeString(payload.memory_writeback_candidate_queue_pressure) && payload.memory_writeback_candidate_queue_pressure !== 'low') {
      issueCodes.push('writeback_candidate_queue_pressure_not_low');
    }
    if (Number(payload.memory_writeback_candidate_noise_score || 0) > 0) issueCodes.push('writeback_candidate_noise_present');
    if (Number(payload.memory_writeback_candidate_conflict_count || 0) > 0) issueCodes.push('writeback_candidate_conflict_present');
    if (Number(payload.memory_writeback_candidate_stale_review_required_count || 0) > 0) {
      issueCodes.push('writeback_candidate_stale_review_required_present');
    }
    if (payload.memory_writeback_candidate_production_authority_change === true) {
      issueCodes.push('writeback_candidate_authority_change');
    }
    freshnessSummary(payload, config, issueCodes);
  }
  return {
    ok: issueCodes.length === 0,
    path: pathValue,
    schema_version: safeString(payload?.schema_version),
    generated_at_iso: safeString(payload?.generated_at_iso),
    healthy: payload?.healthy === true,
    ready: payload?.ready === true,
    slow_requests: Number(payload?.slow_requests || 0),
    recent_slow_requests: payload?.recent_slow_requests ?? null,
    max_observed_http_elapsed_ms: Number(payload?.max_observed_http_elapsed_ms || 0),
    memory_writer_authority_in_rust: payload?.memory_writer_authority_in_rust === true,
    skills_execution_authority_in_rust: payload?.skills_execution_authority_in_rust === true,
    node_remains_authority: payload?.node_remains_authority === true,
    memory_gateway_model_call_execute_smoke_ok: payload?.memory_gateway_model_call_execute_smoke_ok === true,
    memory_gateway_model_call_local_executor_smoke_ok: payload?.memory_gateway_model_call_local_executor_smoke_ok === true,
    xt_file_ipc_run_once_smoke_ok: payload?.xt_file_ipc_run_once_smoke_ok === true,
    xt_file_ipc_background_watcher_smoke_ok: payload?.xt_file_ipc_background_watcher_smoke_ok === true,
    writeback_candidate_queue_pressure: safeString(payload?.memory_writeback_candidate_queue_pressure),
    writeback_candidate_noise_score: Number(payload?.memory_writeback_candidate_noise_score || 0),
    issue_codes: Array.from(new Set(issueCodes)),
  };
}

function validateCutoverReadiness(payload, pathValue, config) {
  const issueCodes = [];
  if (!payload) issueCodes.push('cutover_readiness_missing');
  else {
    if (payload.schema_version !== 'xt.rust_memory_gateway_cutover_readiness.v1') issueCodes.push('cutover_readiness_schema_mismatch');
    if (payload.ok !== true || payload.ready_for_require !== true) issueCodes.push('cutover_readiness_not_ready');
    if (Number(payload.authority_violation_count || 0) > 0) issueCodes.push('cutover_readiness_authority_violation');
    if (Number(payload.parity_failure_count || 0) > 0) issueCodes.push('cutover_readiness_parity_failure');
    if (Number(payload.rust_source_mismatch_count || 0) > 0) issueCodes.push('cutover_readiness_source_mismatch');
    const requiredSamples = Number(payload.required_sample_count || 0);
    const passingSamples = Number(payload.passing_sample_count || 0);
    if (requiredSamples < 1 || passingSamples < requiredSamples) issueCodes.push('cutover_readiness_insufficient_samples');
    if (Array.isArray(payload.issues) && payload.issues.some((issue) => issue?.blocking !== false)) {
      issueCodes.push('cutover_readiness_has_blocking_issues');
    }
    freshnessSummary(payload, config, issueCodes);
  }
  return {
    ok: issueCodes.length === 0,
    path: pathValue,
    schema_version: safeString(payload?.schema_version),
    ready_for_require: payload?.ready_for_require === true,
    required_sample_count: Number(payload?.required_sample_count || 0),
    passing_sample_count: Number(payload?.passing_sample_count || 0),
    issue_codes: Array.from(new Set(issueCodes)),
  };
}

function validateExecuteSmoke(payload, pathValue, config) {
  const issueCodes = [];
  if (!payload) issueCodes.push('execute_smoke_missing');
  else {
    if (payload.schema_version !== 'xhub.rust_hub.memory_gateway_model_call_execute_smoke.v1') issueCodes.push('execute_smoke_schema_mismatch');
    if (payload.ok !== true) issueCodes.push('execute_smoke_not_ok');
    if (payload.execution_blocked !== true) issueCodes.push('execute_smoke_not_blocked');
    if (payload.content_free === false) issueCodes.push('execute_smoke_not_content_free');
    if (payload.production_authority_change === true) issueCodes.push('execute_smoke_authority_change');
    if (payload.execute?.status !== 'blocked') issueCodes.push('execute_smoke_status_not_blocked');
    if (payload.execute?.would_call_model === true
      || payload.execute?.model_call_invoked === true
      || payload.execute?.model_call_executed === true
      || payload.execute?.local_ml_execute_http_invoked === true) {
      issueCodes.push('execute_smoke_invoked_model');
    }
    freshnessSummary(payload, config, issueCodes);
  }
  return {
    ok: issueCodes.length === 0,
    path: pathValue,
    schema_version: safeString(payload?.schema_version),
    execution_blocked: payload?.execution_blocked === true,
    content_free: payload?.content_free !== false,
    admission_ready: payload?.admission_ready === true,
    execute_status: safeString(payload?.execute?.status),
    execute_mode: safeString(payload?.execute?.mode),
    execute_authority: safeString(payload?.execute?.authority),
    issue_codes: Array.from(new Set(issueCodes)),
  };
}

function validateLocalExecutorSmoke(payload, pathValue, config) {
  const issueCodes = [];
  if (!payload) issueCodes.push('local_executor_smoke_missing');
  else {
    if (payload.schema_version !== 'xhub.rust_hub.memory_gateway_model_call_local_executor_smoke.v1') {
      issueCodes.push('local_executor_smoke_schema_mismatch');
    }
    if (payload.ok !== true) issueCodes.push('local_executor_smoke_not_ok');
    if (payload.isolated_daemon !== true) issueCodes.push('local_executor_smoke_not_isolated');
    if (payload.live_daemon_touched === true) issueCodes.push('local_executor_smoke_touched_live_daemon');
    if (payload.production_authority_change === true) issueCodes.push('local_executor_smoke_authority_change');
    if (payload.content_free === false) issueCodes.push('local_executor_smoke_not_content_free');
    if (payload.execute?.status !== 'executed') issueCodes.push('local_executor_smoke_not_executed');
    if (payload.execute?.mode !== 'local_ml_execute') issueCodes.push('local_executor_smoke_mode_mismatch');
    if (payload.execute?.model_call_invoked !== true || payload.execute?.model_call_executed !== true) {
      issueCodes.push('local_executor_smoke_model_call_not_observed');
    }
    if (payload.execute?.local_ml_execute_http_invoked !== true) issueCodes.push('local_executor_smoke_local_ml_not_invoked');
    if (Number(payload.http_metrics?.recent_slow_requests || 0) > 0) issueCodes.push('local_executor_smoke_recent_slow_request');
    freshnessSummary(payload, config, issueCodes);
  }
  return {
    ok: issueCodes.length === 0,
    path: pathValue,
    schema_version: safeString(payload?.schema_version),
    isolated_daemon: payload?.isolated_daemon === true,
    live_daemon_touched: payload?.live_daemon_touched === true,
    content_free: payload?.content_free !== false,
    execute_status: safeString(payload?.execute?.status),
    execute_mode: safeString(payload?.execute?.mode),
    local_ml_execute_http_invoked: payload?.execute?.local_ml_execute_http_invoked === true,
    recent_slow_requests: Number(payload?.http_metrics?.recent_slow_requests || 0),
    issue_codes: Array.from(new Set(issueCodes)),
  };
}

function readAccessKey(config) {
  const candidates = [
    config.accessKeyFile,
    process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE,
    process.env.XHUB_RUST_HUB_ACCESS_KEY_FILE,
  ].map(safeString).filter(Boolean);
  for (const candidate of candidates) {
    try {
      const value = fs.readFileSync(candidate, 'utf8').trim();
      if (value) return value;
    } catch {}
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
    if (accessKey) {
      headers.authorization = `Bearer ${accessKey}`;
      headers['x-hub-access-key'] = accessKey;
    }
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
          reject(new Error(`HTTP ${statusCode} from ${url}: ${raw.slice(0, 300)}`));
          return;
        }
        try {
          resolve(raw.trim() ? JSON.parse(raw) : {});
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

async function collectLiveHttp(config) {
  const accessKey = readAccessKey(config);
  const issueCodes = [];
  let health = null;
  let ready = null;
  let metrics = null;
  let memoryReadiness = null;
  try {
    health = await httpJson('GET', `${config.httpBaseUrl}/health`, undefined, config.timeoutMs, accessKey);
  } catch (error) {
    issueCodes.push('live_health_unavailable');
    health = { error: safeString(error?.message || error).slice(0, 300) };
  }
  try {
    ready = await httpJson('GET', `${config.httpBaseUrl}/ready`, undefined, config.timeoutMs, accessKey);
  } catch (error) {
    issueCodes.push('live_ready_unavailable');
    ready = { error: safeString(error?.message || error).slice(0, 300) };
  }
  try {
    metrics = await httpJson('GET', `${config.httpBaseUrl}/runtime/http-metrics`, undefined, config.timeoutMs, accessKey);
  } catch (error) {
    issueCodes.push('live_http_metrics_unavailable');
    metrics = { error: safeString(error?.message || error).slice(0, 300) };
  }
  try {
    memoryReadiness = await httpJson('GET', `${config.httpBaseUrl}/memory/readiness`, undefined, config.timeoutMs, accessKey);
  } catch (error) {
    issueCodes.push('live_memory_readiness_unavailable');
    memoryReadiness = { error: safeString(error?.message || error).slice(0, 300) };
  }

  const capabilities = ready?.capabilities || {};
  const runtime = ready?.runtime || {};
  const memory = ready?.memory || {};
  const skills = ready?.skills || {};
  const executeState = memory?.gateway_model_call_execute || {};
  const writeback = memoryReadiness?.object_store?.writeback_candidates || {};
  const diagnostics = writeback?.diagnostics || {};

  if (health?.ok !== true) issueCodes.push('live_health_not_ok');
  if (ready?.ok !== true || ready?.ready !== true) issueCodes.push('live_ready_not_ok');
  if (runtime?.provider_route_authority_in_rust !== true && capabilities.provider_route_authority_in_rust !== true) {
    issueCodes.push('provider_route_not_rust_authority');
  }
  if (runtime?.model_route_authority_in_rust !== true && capabilities.model_route_authority_in_rust !== true) {
    issueCodes.push('model_route_not_rust_authority');
  }
  if (memory?.canonical_writer_in_rust !== true && capabilities.memory_writer_authority_in_rust !== true) {
    issueCodes.push('memory_writer_not_rust_authority_live');
  }
  if (capabilities.skills_execution_authority_in_rust !== true && skills?.authority !== 'RustExecutionAuthority') {
    issueCodes.push('skills_execution_not_rust_authority_live');
  }
  if (capabilities.xt_file_ipc_production_authority_in_rust !== true) {
    issueCodes.push('xt_file_ipc_not_rust_production_authority_live');
  }
  if (runtime?.ml_execution_in_rust !== true && capabilities.ml_execution_authority_in_rust !== true) {
    issueCodes.push('ml_execution_not_rust_authority_live');
  }
  if (capabilities.memory_gateway_model_call_execution_admission_ready !== true
    && memory?.gateway_model_call_execution_admission_ready !== true
    && executeState.execution_admission_ready !== true) {
    issueCodes.push('model_call_execution_admission_not_ready_live');
  }
  if (executeState.model_call_execution_in_rust === true || capabilities.memory_gateway_model_call_execution_in_rust === true) {
    issueCodes.push('model_call_execution_already_enabled_live');
  }
  if (config.requireCrossNetworkReady) {
    if (capabilities.cross_network_ready !== true) issueCodes.push('cross_network_not_ready_live');
    if (capabilities.domain_public_endpoint_ready !== true) issueCodes.push('domain_public_endpoint_not_ready_live');
  }
  if (Number(metrics?.recent_slow_requests ?? metrics?.slow_requests ?? 0) > config.maxSlowRequests) {
    issueCodes.push('live_slow_request_budget_exceeded');
  }
  if (writeback?.ready !== true || diagnostics?.ready !== true) issueCodes.push('writeback_candidates_not_ready_live');
  if (safeString(diagnostics?.queue_pressure) && diagnostics.queue_pressure !== 'low') {
    issueCodes.push('writeback_candidate_queue_pressure_not_low_live');
  }
  if (Number(diagnostics?.noise_score || 0) > 0) issueCodes.push('writeback_candidate_noise_present_live');
  if (Number(diagnostics?.stale_candidate_count || 0) > 0) issueCodes.push('writeback_candidate_stale_present_live');
  if (Number(diagnostics?.conflict_candidate_count || 0) > 0) issueCodes.push('writeback_candidate_conflict_present_live');

  return {
    ok: issueCodes.length === 0,
    http_base_url: config.httpBaseUrl,
    access_key_configured: Boolean(accessKey),
    health: {
      ok: health?.ok === true,
      schema_version: safeString(health?.schema_version),
      mode: safeString(health?.mode),
      http_addr: safeString(health?.http_addr),
    },
    readiness: {
      ok: ready?.ok === true,
      ready: ready?.ready === true,
      provider_route_authority_in_rust: runtime?.provider_route_authority_in_rust === true || capabilities.provider_route_authority_in_rust === true,
      model_route_authority_in_rust: runtime?.model_route_authority_in_rust === true || capabilities.model_route_authority_in_rust === true,
      memory_writer_authority_in_rust: memory?.canonical_writer_in_rust === true || capabilities.memory_writer_authority_in_rust === true,
      skills_execution_authority_in_rust: capabilities.skills_execution_authority_in_rust === true || skills?.authority === 'RustExecutionAuthority',
      xt_file_ipc_production_authority_in_rust: capabilities.xt_file_ipc_production_authority_in_rust === true,
      ml_execution_in_rust: runtime?.ml_execution_in_rust === true || capabilities.ml_execution_authority_in_rust === true,
      cross_network_ready: capabilities.cross_network_ready === true,
      domain_public_endpoint_ready: capabilities.domain_public_endpoint_ready === true,
      model_call_execution_admission_ready: capabilities.memory_gateway_model_call_execution_admission_ready === true
        || memory?.gateway_model_call_execution_admission_ready === true
        || executeState.execution_admission_ready === true,
      model_call_execution_in_rust: executeState.model_call_execution_in_rust === true
        || capabilities.memory_gateway_model_call_execution_in_rust === true,
      model_call_execute_mode: safeString(executeState.mode),
      model_call_execute_authority: safeString(executeState.authority),
      local_executor_enabled: executeState.local_executor_enabled === true,
      local_executor_apply_enabled: executeState.local_executor_apply_enabled === true,
      canary_only_supported: executeState.canary_only_supported === true,
      canary_only: executeState.canary_only === true,
      canary_project_id: safeString(executeState.canary_scope?.project_id),
      canary_request_id_prefix: safeString(executeState.canary_scope?.request_id_prefix),
      canary_audit_ref_prefix: safeString(executeState.canary_scope?.audit_ref_prefix),
    },
    http_metrics: {
      ok: metrics?.ok === true,
      total_requests: Number(metrics?.total_requests || 0),
      slow_requests: Number(metrics?.slow_requests || 0),
      recent_slow_requests: Number(metrics?.recent_slow_requests ?? metrics?.slow_requests ?? 0),
      recent_max_elapsed_ms: Number(metrics?.recent_max_elapsed_ms ?? metrics?.max_elapsed_ms ?? 0),
    },
    writeback_candidates: {
      ready: writeback?.ready === true && diagnostics?.ready === true,
      candidate_count: Number(diagnostics?.candidate_count || writeback?.candidate_object_count || 0),
      stale_candidate_count: Number(diagnostics?.stale_candidate_count || 0),
      conflict_candidate_count: Number(diagnostics?.conflict_candidate_count || 0),
      queue_pressure: safeString(diagnostics?.queue_pressure),
      noise_score: Number(diagnostics?.noise_score || 0),
    },
    issue_codes: Array.from(new Set(issueCodes)),
  };
}

function nextCommands(config) {
  return {
    refresh_memory_gateway_profile_suite:
      `node ${path.join(ROOT_DIR, 'tools', 'memory_gateway_cutover_smoke.js')} --profile-suite --hub-base-dir ${config.liveBaseDir} --access-key-file ${config.accessKeyFile}`,
    refresh_live_guarded_execute_smoke:
      `node ${path.join(ROOT_DIR, 'tools', 'memory_gateway_model_call_execute_smoke.js')} --hub-base-dir ${config.liveBaseDir} --access-key-file ${config.accessKeyFile} --require-admission-ready`,
    refresh_isolated_local_executor_smoke:
      `node ${path.join(ROOT_DIR, 'tools', 'memory_gateway_model_call_local_executor_smoke.js')} --report-path /private/tmp/memory_gateway_model_call_local_executor_smoke_latest.json`,
    refresh_ops_gate:
      `node ${path.join(ROOT_DIR, 'tools', 'xhubd_daemon.js')} ops-gate --report-path /private/tmp/xhub_ops_gate_after_local_executor_canary.json --max-slow-requests ${config.maxSlowRequests} --memory-gateway-cutover-readiness-path ${path.join(config.liveBaseDir, 'memory_gateway_cutover_readiness.json')} --require-memory-gateway-cutover-ready --require-memory-gateway-model-call-execute-smoke --memory-gateway-model-call-local-executor-smoke-report-path /private/tmp/memory_gateway_model_call_local_executor_smoke_latest.json --require-memory-gateway-model-call-local-executor-smoke --xt-file-ipc-run-once-smoke --xt-file-ipc-background-watcher-smoke`,
  };
}

function liveSupportsScopedCanary(live) {
  return live?.readiness?.canary_only_supported === true;
}

function applyPlan(config, env, live, evidence) {
  const uid = (() => {
    try {
      return os.userInfo().uid;
    } catch {
      return '<uid>';
    }
  })();
  return {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_live_canary_apply_plan.v1',
    plan_only: true,
    apply_supported: liveSupportsScopedCanary(live),
    apply_blocker: liveSupportsScopedCanary(live)
      ? ''
      : 'memory_gateway_model_call_execute_has_global_env_gate_no_production_request_allowlist',
    reason: liveSupportsScopedCanary(live)
      ? 'Live readiness exposes scoped canary support; apply may be enabled after explicit operator confirmation.'
      : 'Current live daemon does not expose scoped canary support. Install the updated Rust Hub first so one canary route can execute without opening every local provider request.',
    desired_env: LIVE_CANARY_ENV,
    pre_apply_state_file: path.join(STATE_DIR, 'launchctl_session_env_state.json'),
    relaunch_plan: {
      label: 'com.ax.xhubd.local',
      service: `gui/${uid}/com.ax.xhubd.local`,
      commands: [
        ...Object.entries(LIVE_CANARY_ENV).map(([key, value]) => `launchctl setenv ${key} ${value}`),
        `launchctl kickstart -k gui/${uid}/com.ax.xhubd.local`,
      ],
      expected_live_state_after_relaunch: {
        memory_gateway_model_call_execution_in_rust: true,
        model_call_execute_mode: 'local_ml_execute_available_after_admission',
      },
    },
    post_apply_smoke_plan: {
      single_canary_route_required: true,
      provider_id: 'local',
      task_kind: 'text_generate',
      content_free_evidence_required: true,
      max_slow_requests: config.maxSlowRequests,
    },
    rollback_plan: rollbackPlanFromEnv(env.current_env),
    prerequisites_summary: {
      live_ok: live.ok === true,
      ops_gate_ok: evidence.ops_gate.ok === true,
      cutover_readiness_ok: evidence.cutover_readiness.ok === true,
      execute_guard_smoke_ok: evidence.execute_smoke.ok === true,
      isolated_local_executor_smoke_ok: evidence.local_executor_smoke.ok === true,
    },
  };
}

function flattenIssueCodes(sections) {
  const out = [];
  for (const section of sections) {
    for (const code of section?.issue_codes || []) {
      const normalized = safeString(code);
      if (normalized) out.push(normalized);
    }
  }
  return Array.from(new Set(out));
}

async function buildReport(config) {
  const env = envInspection();
  const opsGateFound = firstExistingPayload(config, 'ops_gate');
  const cutoverFound = firstExistingPayload(config, 'cutover_readiness');
  const executeFound = firstExistingPayload(config, 'execute_smoke');
  const localExecutorFound = firstExistingPayload(config, 'local_executor_smoke');

  const evidence = {
    ops_gate: validateOpsGate(opsGateFound.payload, opsGateFound.path, config),
    cutover_readiness: validateCutoverReadiness(cutoverFound.payload, cutoverFound.path, config),
    execute_smoke: validateExecuteSmoke(executeFound.payload, executeFound.path, config),
    local_executor_smoke: validateLocalExecutorSmoke(localExecutorFound.payload, localExecutorFound.path, config),
  };
  evidence.candidate_paths = {
    ops_gate: opsGateFound.candidate_paths,
    cutover_readiness: cutoverFound.candidate_paths,
    execute_smoke: executeFound.candidate_paths,
    local_executor_smoke: localExecutorFound.candidate_paths,
  };

  const live = config.mode === 'plan'
    ? await collectLiveHttp(config)
    : { ok: true, skipped: true, issue_codes: [] };

  const evidenceIssues = flattenIssueCodes([
    evidence.ops_gate,
    evidence.cutover_readiness,
    evidence.execute_smoke,
    evidence.local_executor_smoke,
    live,
  ]);
  const scopedCanaryIssues = liveSupportsScopedCanary(live)
    ? []
    : ['memory_gateway_model_call_execute_has_global_env_gate_no_production_request_allowlist'];
  const readyForOperatorReview = evidenceIssues.length === 0;
  const readyForApply = readyForOperatorReview && scopedCanaryIssues.length === 0;
  const report = {
    ok: readyForOperatorReview,
    schema_version: SCHEMA,
    command: 'memory-gateway-model-call-live-canary-session',
    mode: config.mode,
    generated_at_iso: new Date().toISOString(),
    http_base_url: config.httpBaseUrl,
    live_base_dir: config.liveBaseDir,
    report_max_age_ms: config.reportMaxAgeMs,
    max_slow_requests: config.maxSlowRequests,
    require_cross_network_ready: config.requireCrossNetworkReady,
    plan_only: true,
    apply_performed: false,
    rollback_performed: false,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    content_free: true,
    secret_leak: false,
    env,
    live,
    evidence,
    ready_for_operator_review: readyForOperatorReview,
    ready_for_apply: readyForApply,
    apply_supported: scopedCanaryIssues.length === 0,
    apply_blockers: scopedCanaryIssues,
    issues: [...evidenceIssues, ...scopedCanaryIssues],
    apply_plan: applyPlan(config, env, live, evidence),
    next_commands: nextCommands(config),
    report_path: config.reportPath,
  };
  const serialized = JSON.stringify(report);
  report.secret_leak = /sk-[A-Za-z0-9]|api_key|access_key"\s*:\s*"(?!\[REDACTED\])|Bearer\s+(?!\[REDACTED\])\S+/i.test(serialized);
  report.ok = report.ok === true && report.secret_leak === false;
  return report;
}

function atomicWriteJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmp = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, filePath);
}

function runSelfTest() {
  const config = parseArgs(['--plan', '--report-max-age-ms', String(60 * 60 * 1000)]);
  const now = Date.now();
  const ops = validateOpsGate({
    schema_version: 'xhub.rust_hub.daemon_ops_gate.v1',
    ok: true,
    generated_at_iso: new Date(now).toISOString(),
    healthy: true,
    ready: true,
    issues: [],
    slow_requests: 0,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    node_remains_authority: false,
    memory_writer_authority_in_rust: true,
    skills_execution_authority_in_rust: true,
    memory_gateway_cutover_readiness_ok: true,
    memory_gateway_model_call_execute_smoke_ok: true,
    memory_gateway_model_call_execute_smoke_execution_blocked: true,
    memory_gateway_model_call_execute_smoke_content_free: true,
    memory_gateway_model_call_local_executor_smoke_ok: true,
    memory_gateway_model_call_local_executor_smoke_live_daemon_touched: false,
    memory_gateway_model_call_local_executor_smoke_content_free: true,
    memory_gateway_model_call_local_executor_smoke_recent_slow_requests: 0,
    xt_file_ipc_run_once_smoke_ok: true,
    xt_file_ipc_background_watcher_smoke_ok: true,
    memory_writeback_candidate_queue_ready: true,
    memory_writeback_candidate_queue_pressure: 'low',
    memory_writeback_candidate_noise_score: 0,
    memory_writeback_candidate_conflict_count: 0,
    memory_writeback_candidate_stale_review_required_count: 0,
    memory_writeback_candidate_production_authority_change: false,
  }, '/tmp/ops.json', config);
  if (!ops.ok) throw new Error(`valid ops rejected: ${ops.issue_codes.join(',')}`);
  const stale = validateExecuteSmoke({
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_execute_smoke.v1',
    ok: true,
    generated_at_ms: now - (2 * 60 * 60 * 1000),
    execution_blocked: true,
    content_free: true,
    production_authority_change: false,
    execute: {
      status: 'blocked',
      would_call_model: false,
      model_call_invoked: false,
      model_call_executed: false,
      local_ml_execute_http_invoked: false,
    },
  }, '/tmp/execute.json', { ...config, reportMaxAgeMs: 1000 });
  if (stale.ok || !stale.issue_codes.includes('evidence_stale')) {
    throw new Error('stale execute smoke must be rejected');
  }
  const rollback = rollbackPlanFromEnv({
    XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_ADMISSION: '1',
    XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION: '',
    XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR: '',
    XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY: '',
  });
  if (!rollback.actions.some((item) => item.key === 'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_ADMISSION' && item.action === 'setenv')) {
    throw new Error('rollback must preserve existing admission env');
  }
  if (!rollback.actions.some((item) => item.key === 'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY' && item.action === 'unsetenv')) {
    throw new Error('rollback must unset newly planned apply env');
  }
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('memory_gateway_model_call_live_canary_session self-test ok\n');
    return;
  }
  const report = await buildReport(config);
  if (config.mode === 'plan') atomicWriteJSON(config.reportPath, report);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (config.mode === 'plan' && !report.ok) process.exit(2);
}

main().catch((error) => {
  process.stderr.write(`[memory_gateway_model_call_live_canary_session] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
