#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const DEFAULT_HTTP_BASE_URL = 'http://127.0.0.1:50151';
const DEFAULT_LIVE_BASE_DIR = path.join(process.env.HOME || '', 'Library', 'Group Containers', 'group.rel.flowhub');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    rustHubRoot: defaultRustHubRoot(),
    httpBaseUrl: DEFAULT_HTTP_BASE_URL,
    liveBaseDir: DEFAULT_LIVE_BASE_DIR,
    durationMs: 120000,
    intervalMs: 2000,
    maxStatusAgeMs: 5000,
    statusReadTimeoutMs: 3000,
    maxSlowRequests: 0,
    requireUiCompatibility: true,
    requireRelFlowHubProcess: true,
    requireNoTargetXhubd: true,
    includeChildOutput: false,
    reportPath: '',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--rust-hub-root':
        out.rustHubRoot = path.resolve(String(next || '').trim() || out.rustHubRoot);
        i += 1;
        break;
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--live-base-dir':
        out.liveBaseDir = path.resolve(String(next || '').trim() || out.liveBaseDir);
        i += 1;
        break;
      case '--duration-ms':
        out.durationMs = parseIntInRange(next, out.durationMs, 1, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--interval-ms':
        out.intervalMs = parseIntInRange(next, out.intervalMs, 100, 60000);
        i += 1;
        break;
      case '--max-status-age-ms':
        out.maxStatusAgeMs = parseIntInRange(next, out.maxStatusAgeMs, 500, 60000);
        i += 1;
        break;
      case '--status-read-timeout-ms':
        out.statusReadTimeoutMs = parseIntInRange(next, out.statusReadTimeoutMs, 100, 30000);
        i += 1;
        break;
      case '--max-slow-requests':
        out.maxSlowRequests = parseIntInRange(next, out.maxSlowRequests, 0, 100000);
        i += 1;
        break;
      case '--skip-ui-compatibility':
        out.requireUiCompatibility = false;
        break;
      case '--allow-missing-relflowhub':
        out.requireRelFlowHubProcess = false;
        break;
      case '--allow-target-xhubd':
        out.requireNoTargetXhubd = false;
        break;
      case '--include-child-output':
        out.includeChildOutput = true;
        break;
      case '--report-path':
        out.reportPath = String(next || '').trim();
        i += 1;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  if (!out.reportPath) {
    out.reportPath = path.join(REPORT_DIR, `production_live_stability_gate_${utcStamp()}.json`);
  } else if (!path.isAbsolute(out.reportPath)) {
    out.reportPath = path.resolve(out.rustHubRoot, out.reportPath);
  }
  return out;
}

function defaultRustHubRoot() {
  try {
    const activeRoot = execFileSync('launchctl', ['getenv', 'XHUB_RUST_HUB_ROOT'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 3000,
    }).trim();
    if (activeRoot) return path.resolve(activeRoot);
  } catch {
    // Fall back to the package/source root when no live production root is set.
  }
  return ROOT_DIR;
}

function usage() {
  return [
    'production_live_stability_gate.js',
    '',
    'Composes the live XT heartbeat soak, daemon ops gate, production runtime guard, UI compatibility gate, and process sanity checks.',
    '',
    'Options:',
    '  --rust-hub-root <p>             Active/final Rust Hub root, default launchctl XHUB_RUST_HUB_ROOT or current package root',
    '  --http-base-url <u>             Rust xhubd HTTP base URL, default http://127.0.0.1:50151',
    '  --live-base-dir <p>             Live XT file IPC base dir',
    '  --duration-ms <ms>              Heartbeat soak duration, default 120000, max 86400000',
    '  --interval-ms <ms>              Heartbeat interval, default 2000',
    '  --max-status-age-ms <ms>        Heartbeat freshness budget, default 5000',
    '  --status-read-timeout-ms <ms>   Child status read timeout, default 3000',
    '  --max-slow-requests <n>         Recent slow request budget for daemon ops gate, default 0',
    '  --skip-ui-compatibility         Skip no-product-UI-change gate',
    '  --allow-missing-relflowhub      Do not fail if RELFlowHub process is absent',
    '  --allow-target-xhubd            Do not fail if target/debug or target/release xhubd is present',
    '  --include-child-output          Embed full child JSON outputs in the top-level report',
    '  --report-path <p>               JSON report path',
  ].join('\n');
}

function utcStamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function parseJsonObject(stdout) {
  const text = String(stdout || '').trim();
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end <= start) throw new Error('no JSON object found in command output');
  return JSON.parse(text.slice(start, end + 1));
}

function getJson(url, timeoutMs = 5000) {
  return new Promise((resolve) => {
    const req = http.get(url, { timeout: timeoutMs }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          resolve({ ok: res.statusCode >= 200 && res.statusCode < 300, status_code: res.statusCode, body: JSON.parse(data), error: '' });
        } catch (error) {
          resolve({ ok: false, status_code: res.statusCode, body: null, error: String(error.message || error) });
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => resolve({ ok: false, status_code: 0, body: null, error: String(error.message || error) }));
  });
}

async function getHttpMetrics(config, label) {
  const startedAtMs = Date.now();
  const result = await getJson(`${config.httpBaseUrl}/runtime/http-metrics`, 5000);
  return {
    name: label,
    ok: result.ok && result.body?.ok === true,
    status_code: result.status_code,
    error: result.error,
    duration_ms: Date.now() - startedAtMs,
    summary: summarizeHttpMetrics(result.body),
    body: result.body,
  };
}

function summarizeHttpMetrics(metrics) {
  if (!metrics || typeof metrics !== 'object') {
    return {
      ok: false,
      total_requests: 0,
      slow_requests: 0,
      recent_slow_requests: null,
      max_elapsed_ms: 0,
      recent_max_elapsed_ms: 0,
      route_slow_counts: {},
    };
  }
  const routeSlowCounts = {};
  for (const route of metrics.routes || []) {
    routeSlowCounts[String(route.route || '')] = Number(route.slow_count || 0);
  }
  return {
    ok: metrics.ok === true,
    total_requests: Number(metrics.total_requests || 0),
    slow_requests: Number(metrics.slow_requests || 0),
    recent_slow_requests: metrics.recent_slow_requests ?? null,
    max_elapsed_ms: Number(metrics.max_elapsed_ms || 0),
    recent_max_elapsed_ms: Number(metrics.recent_max_elapsed_ms || 0),
    route_slow_counts: routeSlowCounts,
  };
}

function slowRequestDelta(beforeSummary, afterSummary) {
  const before = beforeSummary || summarizeHttpMetrics(null);
  const after = afterSummary || summarizeHttpMetrics(null);
  const routes = {};
  for (const route of new Set([
    ...Object.keys(before.route_slow_counts || {}),
    ...Object.keys(after.route_slow_counts || {}),
  ])) {
    routes[route] = Math.max(0, Number(after.route_slow_counts?.[route] || 0) - Number(before.route_slow_counts?.[route] || 0));
  }
  return {
    known: before.ok === true && after.ok === true,
    total_requests_delta: Math.max(0, Number(after.total_requests || 0) - Number(before.total_requests || 0)),
    slow_requests_delta: Math.max(0, Number(after.slow_requests || 0) - Number(before.slow_requests || 0)),
    max_elapsed_ms_delta_window: Math.max(0, Number(after.max_elapsed_ms || 0) - Number(before.max_elapsed_ms || 0)),
    route_slow_request_deltas: routes,
  };
}

function runJsonStep(name, command, args, options = {}) {
  const startedAtMs = Date.now();
  const result = spawnSync(command, args, {
    cwd: options.cwd || ROOT_DIR,
    encoding: 'utf8',
    timeout: options.timeoutMs || 60000,
    maxBuffer: options.maxBuffer || 64 * 1024 * 1024,
    env: { ...process.env, ...(options.env || {}) },
  });
  const step = {
    name,
    ok: false,
    command,
    args,
    exit_code: typeof result.status === 'number' ? result.status : null,
    signal: result.signal || '',
    duration_ms: Date.now() - startedAtMs,
    timed_out: result.error?.code === 'ETIMEDOUT' || Boolean(result.signal),
    parse_error: '',
    error: result.error ? String(result.error.message || result.error) : '',
    report_path: '',
    summary: {},
  };
  try {
    step.output = parseJsonObject(result.stdout);
    step.ok = result.status === 0 && step.output?.ok === true;
    step.report_path = String(step.output?.report_path || '');
  } catch (error) {
    step.parse_error = String(error.message || error);
  }
  if (result.status !== 0 && !step.error) step.error = String(result.stderr || '').trim();
  return step;
}

function trimChildOutput(step, includeChildOutput) {
  if (!includeChildOutput && step && Object.prototype.hasOwnProperty.call(step, 'output')) {
    delete step.output;
  }
  return step;
}

function summarizeHeartbeat(output) {
  return {
    ok: output?.ok === true,
    cycle_count: Number(output?.cycle_count || 0),
    duration_ms: Number(output?.duration_ms || 0),
    status_unique_updated_at_count: Number(output?.status_unique_updated_at_count || 0),
    max_observed_status_age_ms: Number(output?.max_observed_status_age_ms || 0),
    memory_writer_authority_in_rust: output?.memory_writer_authority_in_rust === true,
    skills_execution_authority_in_rust: output?.skills_execution_authority_in_rust === true,
    issue_count: Array.isArray(output?.issues) ? output.issues.length : 0,
  };
}

function summarizeOpsGate(output) {
  return {
    ok: output?.ok === true,
    healthy: output?.healthy === true,
    ready: output?.ready === true,
    http_metrics_ready: output?.http_metrics_ready === true,
    slow_request_budget_scope: String(output?.slow_request_budget_scope || ''),
    recent_slow_requests: output?.recent_slow_requests ?? null,
    slow_requests: Number(output?.slow_requests || 0),
    max_observed_http_elapsed_ms: Number(output?.max_observed_http_elapsed_ms || 0),
    xt_file_ipc_production_surface_ready: output?.status?.readiness?.capabilities?.xt_file_ipc_production_surface_ready === true,
    memory_writer_authority_in_rust: output?.memory_writer_authority_in_rust === true,
    skills_execution_authority_in_rust: output?.skills_execution_authority_in_rust === true,
    ui_product_change: output?.ui_product_change === true,
    secret_leak: output?.secret_leak === true,
    issue_count: Array.isArray(output?.issues) ? output.issues.length : 0,
  };
}

function summarizeRuntimeGuard(output) {
  return {
    ok: output?.ok === true,
    provider_model_production_authority_effective_now: output?.provider_model_production_authority_effective_now === true,
    scheduler_authority_effective_now: output?.scheduler_authority_effective_now === true,
    running_node_process_pid: Number(output?.running_node_process_pid || 0),
    memory_writer_authority_target: output?.memory_writer_authority_target === true,
    skills_execution_authority_target: output?.skills_execution_authority_target === true,
    ui_product_change: output?.ui_product_change === true,
    secret_leak: output?.secret_leak === true,
    issue_count: Array.isArray(output?.issues) ? output.issues.length : 0,
  };
}

function summarizeUiGate(output) {
  return {
    ok: output?.ok === true,
    product_ui_change: output?.product_ui_change === true,
    swift_ui_files_touched: output?.swift_ui_files_touched === true,
    rust_browser_product_ui: output?.rust_browser_product_ui === true,
    memory_writer_authority_in_rust: output?.memory_writer_authority_in_rust === true,
  };
}

function collectProcesses() {
  try {
    const rows = execFileSync('ps', ['ax', '-o', 'pid=,ppid=,stat=,command='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 8 * 1024 * 1024,
    }).split('\n').map((line) => line.trim()).filter(Boolean);
    return { ok: true, error: '', rows };
  } catch (error) {
    return { ok: false, error: String(error.message || error), rows: [] };
  }
}

function processSanity(config) {
  const snapshot = collectProcesses();
  const xhubd = snapshot.rows
    .filter((line) => /\bxhubd\b/.test(line))
    .filter((line) => !line.includes('production_live_stability_gate.js'));
  const targetXhubd = xhubd.filter((line) => /target\/(?:debug|release)\/xhubd\b/.test(line));
  const relflowhub = snapshot.rows
    .filter((line) => /Contents\/MacOS\/RELFlowHub(?:\s|$)/.test(line) || /\/RELFlowHub(?:\s|$)/.test(line))
    .filter((line) => !line.includes('production_live_stability_gate.js'));
  const pythonRuntime = snapshot.rows.filter((line) => /relflowhub_local_runtime\.py/.test(line));
  const issues = [];
  if (!snapshot.ok) issues.push('process_snapshot_unavailable');
  if (xhubd.length === 0) issues.push('xhubd_process_not_found');
  if (config.requireNoTargetXhubd && targetXhubd.length > 0) issues.push('target_xhubd_process_present');
  if (config.requireRelFlowHubProcess && relflowhub.length === 0) issues.push('relflowhub_process_not_found');
  return {
    ok: issues.length === 0,
    process_snapshot_ok: snapshot.ok,
    process_snapshot_error: snapshot.error,
    xhubd_processes: xhubd,
    target_xhubd_processes: targetXhubd,
    relflowhub_processes: relflowhub,
    python_runtime_processes: pythonRuntime,
    require_no_target_xhubd: config.requireNoTargetXhubd,
    require_relflowhub_process: config.requireRelFlowHubProcess,
    issues,
  };
}

function appendStepIssues(issues, step, code, summary) {
  if (!step.ok) {
    issues.push({
      code,
      exit_code: step.exit_code,
      signal: step.signal,
      timed_out: step.timed_out,
      error: step.error,
      parse_error: step.parse_error,
      report_path: step.report_path,
      summary,
    });
  }
}

function isBaselineSlowRequestCarryover(opsGate, metricsDelta, config) {
  const opIssues = Array.isArray(opsGate.output?.issues)
    ? opsGate.output.issues.map((issue) => String(issue))
    : [];
  return opsGate.ok === false
    && opIssues.length === 1
    && opIssues[0] === 'slow_request_budget_exceeded'
    && opsGate.summary.healthy === true
    && opsGate.summary.ready === true
    && opsGate.summary.http_metrics_ready === true
    && opsGate.summary.memory_writer_authority_in_rust === false
    && opsGate.summary.skills_execution_authority_in_rust === false
    && opsGate.summary.ui_product_change === false
    && opsGate.summary.secret_leak === false
    && metricsDelta.known === true
    && metricsDelta.slow_requests_delta <= config.maxSlowRequests;
}

async function run(config) {
  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const startedAtMs = Date.now();
  const metricsBefore = await getHttpMetrics(config, 'http_metrics_baseline');
  const heartbeatReportPath = path.join(REPORT_DIR, `xt_file_ipc_live_heartbeat_soak_for_stability_${utcStamp()}.json`);
  const heartbeat = runJsonStep('xt_file_ipc_live_heartbeat_soak', 'node', [
    path.join(SCRIPT_DIR, 'xt_file_ipc_live_heartbeat_soak.js'),
    '--http-base-url', config.httpBaseUrl,
    '--live-base-dir', config.liveBaseDir,
    '--duration-ms', String(config.durationMs),
    '--interval-ms', String(config.intervalMs),
    '--max-status-age-ms', String(config.maxStatusAgeMs),
    '--status-read-timeout-ms', String(config.statusReadTimeoutMs),
    '--report-path', heartbeatReportPath,
  ], {
    cwd: config.rustHubRoot,
    timeoutMs: config.durationMs + Math.max(30000, config.intervalMs * 4),
    maxBuffer: 128 * 1024 * 1024,
  });
  heartbeat.summary = summarizeHeartbeat(heartbeat.output);
  trimChildOutput(heartbeat, config.includeChildOutput);

  const opsGate = runJsonStep('daemon_ops_gate', 'bash', [
    path.join(SCRIPT_DIR, 'daemon_ops_gate.command'),
    '--max-slow-requests', String(config.maxSlowRequests),
  ], {
    cwd: config.rustHubRoot,
    timeoutMs: 120000,
    maxBuffer: 128 * 1024 * 1024,
  });
  opsGate.summary = summarizeOpsGate(opsGate.output);
  const metricsAfterSummary = summarizeHttpMetrics(opsGate.output?.http_metrics);
  const metricsDelta = slowRequestDelta(metricsBefore.summary, metricsAfterSummary);
  const baselineSlowRequestCarryoverOk = isBaselineSlowRequestCarryover(opsGate, metricsDelta, config);
  if (baselineSlowRequestCarryoverOk) {
    opsGate.accepted_by_stability_gate = true;
    opsGate.accepted_reason = 'baseline_slow_request_carryover_delta_ok';
  }
  trimChildOutput(opsGate, config.includeChildOutput);

  const runtimeGuard = runJsonStep('route_authority_production_runtime_guard', 'node', [
    path.join(SCRIPT_DIR, 'route_authority_production_runtime_guard.js'),
    '--rust-hub-root', config.rustHubRoot,
    '--http-base-url', config.httpBaseUrl,
    '--allow-xt-file-ipc-production',
  ], {
    cwd: config.rustHubRoot,
    timeoutMs: 60000,
    maxBuffer: 32 * 1024 * 1024,
  });
  runtimeGuard.summary = summarizeRuntimeGuard(runtimeGuard.output);
  trimChildOutput(runtimeGuard, config.includeChildOutput);

  let uiGate = null;
  if (config.requireUiCompatibility) {
    uiGate = runJsonStep('ui_compatibility_no_product_ui_change_gate', 'bash', [
      path.join(SCRIPT_DIR, 'ui_compatibility_no_product_ui_change_gate.command'),
    ], {
      cwd: config.rustHubRoot,
      timeoutMs: 60000,
      maxBuffer: 32 * 1024 * 1024,
    });
    uiGate.summary = summarizeUiGate(uiGate.output);
    trimChildOutput(uiGate, config.includeChildOutput);
  }

  const processes = processSanity(config);
  const issues = [];
  const warnings = [];
  if (!metricsBefore.ok) {
    issues.push({
      code: 'http_metrics_baseline_unavailable',
      status_code: metricsBefore.status_code,
      error: metricsBefore.error,
    });
  }
  if (!metricsDelta.known) {
    issues.push({
      code: 'http_metrics_slow_delta_unavailable',
      baseline_ok: metricsBefore.summary.ok,
      final_ok: metricsAfterSummary.ok,
    });
  } else if (metricsDelta.slow_requests_delta > config.maxSlowRequests) {
    issues.push({
      code: 'slow_request_delta_budget_exceeded',
      slow_requests_delta: metricsDelta.slow_requests_delta,
      max_slow_requests: config.maxSlowRequests,
      route_slow_request_deltas: metricsDelta.route_slow_request_deltas,
    });
  }
  if (baselineSlowRequestCarryoverOk) {
    warnings.push({
      code: 'baseline_slow_request_carryover_delta_ok',
      baseline_recent_slow_requests: metricsBefore.summary.recent_slow_requests,
      final_recent_slow_requests: metricsAfterSummary.recent_slow_requests,
      slow_requests_delta: metricsDelta.slow_requests_delta,
      max_slow_requests: config.maxSlowRequests,
      route_slow_request_deltas: metricsDelta.route_slow_request_deltas,
    });
  }
  appendStepIssues(issues, heartbeat, 'live_heartbeat_soak_failed', heartbeat.summary);
  if (!baselineSlowRequestCarryoverOk) {
    appendStepIssues(issues, opsGate, 'daemon_ops_gate_failed', opsGate.summary);
  }
  appendStepIssues(issues, runtimeGuard, 'production_runtime_guard_failed', runtimeGuard.summary);
  if (uiGate) appendStepIssues(issues, uiGate, 'ui_compatibility_gate_failed', uiGate.summary);
  for (const issue of processes.issues) issues.push({ code: issue, summary: processes });

  const memoryWriterAuthority = heartbeat.summary.memory_writer_authority_in_rust
    || opsGate.summary.memory_writer_authority_in_rust
    || runtimeGuard.summary.memory_writer_authority_target
    || Boolean(uiGate?.summary?.memory_writer_authority_in_rust);
  const skillsExecutionAuthority = heartbeat.summary.skills_execution_authority_in_rust
    || opsGate.summary.skills_execution_authority_in_rust
    || runtimeGuard.summary.skills_execution_authority_target;
  const uiProductChange = opsGate.summary.ui_product_change
    || runtimeGuard.summary.ui_product_change
    || Boolean(uiGate?.summary?.product_ui_change)
    || Boolean(uiGate?.summary?.swift_ui_files_touched)
    || Boolean(uiGate?.summary?.rust_browser_product_ui);
  const secretLeak = opsGate.summary.secret_leak || runtimeGuard.summary.secret_leak;
  if (memoryWriterAuthority) issues.push({ code: 'memory_writer_authority_changed' });
  if (skillsExecutionAuthority) issues.push({ code: 'skills_execution_authority_changed' });
  if (uiProductChange) issues.push({ code: 'ui_product_change_detected' });
  if (secretLeak) issues.push({ code: 'secret_leak_detected' });

  const report = {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.production_live_stability_gate.v1',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAtMs,
    rust_hub_root: config.rustHubRoot,
    http_base_url: config.httpBaseUrl,
    live_base_dir: config.liveBaseDir,
    heartbeat_duration_ms: config.durationMs,
    heartbeat_interval_ms: config.intervalMs,
    max_status_age_ms: config.maxStatusAgeMs,
    status_read_timeout_ms: config.statusReadTimeoutMs,
    max_slow_requests: config.maxSlowRequests,
    http_metrics_baseline: {
      ok: metricsBefore.ok,
      status_code: metricsBefore.status_code,
      error: metricsBefore.error,
      duration_ms: metricsBefore.duration_ms,
      summary: metricsBefore.summary,
    },
    http_metrics_final_summary: metricsAfterSummary,
    slow_request_delta: metricsDelta,
    slow_request_delta_budget_ok: metricsDelta.known && metricsDelta.slow_requests_delta <= config.maxSlowRequests,
    baseline_slow_request_carryover_ok: baselineSlowRequestCarryoverOk,
    include_child_output: config.includeChildOutput,
    production_authority_change: false,
    provider_model_production_authority_effective_now: runtimeGuard.summary.provider_model_production_authority_effective_now === true,
    scheduler_authority_effective_now: runtimeGuard.summary.scheduler_authority_effective_now === true,
    xt_file_ipc_production_surface_ready: opsGate.summary.xt_file_ipc_production_surface_ready === true,
    memory_writer_authority_in_rust: memoryWriterAuthority,
    skills_execution_authority_in_rust: skillsExecutionAuthority,
    ui_product_change: uiProductChange,
    secret_leak: secretLeak,
    checks: {
      live_heartbeat_soak: heartbeat,
      daemon_ops_gate: opsGate,
      production_runtime_guard: runtimeGuard,
      ui_compatibility: uiGate,
      process_sanity: processes,
    },
    warnings,
    issues,
    report_path: config.reportPath,
  };
  fs.mkdirSync(path.dirname(config.reportPath), { recursive: true });
  fs.writeFileSync(config.reportPath, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  const report = await run(config);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (!report.ok) process.exit(2);
}

main().catch((error) => {
  process.stderr.write(`[production_live_stability_gate] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
