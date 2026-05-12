#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    cycles: 3,
    intervalMs: 500,
    timeoutMs: 45000,
    rustHubRoot: ROOT_DIR,
    maxSlowRequests: 0,
    maxCycleMs: 120000,
    modelRemoteRuns: 1,
    modelLocalRuns: 1,
    schedulerGateMode: 'skip',
    writeReport: true,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--cycles':
        out.cycles = parseIntInRange(next, out.cycles, 1, 10000);
        i += 1;
        break;
      case '--interval-ms':
        out.intervalMs = parseIntInRange(next, out.intervalMs, 0, 60000);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
        i += 1;
        break;
      case '--max-slow-requests':
        out.maxSlowRequests = parseIntInRange(next, out.maxSlowRequests, 0, 1000000);
        i += 1;
        break;
      case '--max-cycle-ms':
        out.maxCycleMs = parseIntInRange(next, out.maxCycleMs, 1, 300000);
        i += 1;
        break;
      case '--model-remote-runs':
        out.modelRemoteRuns = parseIntInRange(next, out.modelRemoteRuns, 1, 10000);
        i += 1;
        break;
      case '--model-local-runs':
        out.modelLocalRuns = parseIntInRange(next, out.modelLocalRuns, 1, 10000);
        i += 1;
        break;
      case '--scheduler-gate-mode':
        out.schedulerGateMode = String(next || '').trim() || out.schedulerGateMode;
        if (!['ready', 'applied', 'skip'].includes(out.schedulerGateMode)) {
          throw new Error(`invalid --scheduler-gate-mode: ${out.schedulerGateMode}`);
        }
        i += 1;
        break;
      case '--no-report':
        out.writeReport = false;
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
    'route_authority_prep_sustained_guard.js',
    '',
    'Options:',
    '  --cycles <n>             Sustained guard cycles, default 3',
    '  --interval-ms <n>        Delay between cycles, default 500',
    '  --timeout-ms <n>         Route guard timeout, default 45000',
    '  --rust-hub-root <p>      Expected active Rust Hub root',
    '  --max-slow-requests <n>  Recent daemon slow request budget, default 0',
    '  --max-cycle-ms <n>       Per-cycle elapsed budget, default 120000',
    '  --model-remote-runs <n>  Model route remote runs per cycle, default 1',
    '  --model-local-runs <n>   Model route local runs per cycle, default 1',
    '  --scheduler-gate-mode <mode> ready|applied|skip, default skip',
    '  --no-report              Print only; do not write reports/',
    '  --self-test              Validate reducer logic',
  ].join('\n');
}

function runJson(command, args, timeoutMs) {
  const started = Date.now();
  let stdout = '';
  let stderr = '';
  let exitCode = 0;
  try {
    stdout = execFileSync(command, args, {
      cwd: ROOT_DIR,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: timeoutMs,
      maxBuffer: 32 * 1024 * 1024,
    });
  } catch (error) {
    stdout = String(error.stdout || '');
    stderr = String(error.stderr || error.message || '').slice(0, 4000);
    exitCode = Number(error.status || 1);
  }
  let payload = null;
  let parseError = '';
  try {
    payload = JSON.parse(stdout);
  } catch {
    try {
      payload = parseLastJsonObject(stdout);
    } catch (error) {
      parseError = String(error.message || error);
    }
  }
  return {
    ok: exitCode === 0 && !!payload,
    exit_code: exitCode,
    parsed: !!payload,
    parse_error: parseError,
    stderr,
    elapsed_ms: Date.now() - started,
    payload,
  };
}

function parseLastJsonObject(stdout) {
  const text = String(stdout || '').trim();
  const starts = [];
  for (let i = 0; i < text.length; i += 1) {
    if (text[i] === '{') starts.push(i);
  }
  for (let i = starts.length - 1; i >= 0; i -= 1) {
    try {
      return JSON.parse(text.slice(starts[i]));
    } catch {
      // Continue scanning.
    }
  }
  throw new Error('no parseable JSON object in command output');
}

function sleep(ms) {
  if (ms <= 0) return;
  execFileSync('sleep', [String(Math.max(0, ms / 1000))], { stdio: ['ignore', 'ignore', 'ignore'] });
}

function runCycle(config, cycleIndex) {
  const started = Date.now();
  const runtime = runJson('bash', [
    path.join(SCRIPT_DIR, 'route_authority_prep_runtime_guard.command'),
    '--no-report',
    '--rust-hub-root',
    config.rustHubRoot,
  ], 30000);
  const route = runJson('bash', [
    path.join(SCRIPT_DIR, 'route_authority_cutover_guard.command'),
    '--no-report',
    '--scheduler-gate-mode',
    config.schedulerGateMode,
    '--model-remote-runs',
    String(config.modelRemoteRuns),
    '--model-local-runs',
    String(config.modelLocalRuns),
    '--timeout-ms',
    String(config.timeoutMs),
    '--rust-hub-root',
    config.rustHubRoot,
  ], config.timeoutMs + 140000);
  let scheduler = { payload: { ok: true, skipped: true }, exit_code: 0, parsed: true };
  if (config.schedulerGateMode === 'applied') {
    scheduler = runJson('bash', [
      path.join(SCRIPT_DIR, 'scheduler_production_authority_guard.command'),
      '--no-report',
      '--rust-hub-root',
      config.rustHubRoot,
      '--max-slow-requests',
      String(config.maxSlowRequests),
    ], 60000);
  }
  const elapsedMs = Date.now() - started;
  const issues = [];
  if (!runtime.payload?.ok) issues.push('prep_runtime_guard_failed');
  if (!route.payload?.ok) issues.push('route_cutover_guard_failed');
  if (config.schedulerGateMode === 'applied' && !scheduler.payload?.ok) issues.push('scheduler_guard_failed');
  if (elapsedMs > config.maxCycleMs) issues.push('cycle_latency_budget_exceeded');
  return {
    cycle: cycleIndex,
    ok: issues.length === 0,
    elapsed_ms: elapsedMs,
    runtime_ok: Boolean(runtime.payload?.ok),
    route_ok: Boolean(route.payload?.ok),
    scheduler_ok: Boolean(scheduler.payload?.ok),
    scheduler_gate_mode: config.schedulerGateMode,
    running_node_process_pid: Number(runtime.payload?.running_node_process_pid || scheduler.payload?.running_node_process_pid || 0),
    daemon_recent_slow_requests: Number(scheduler.payload?.daemon_recent_slow_requests || 0),
    daemon_max_observed_http_elapsed_ms: Number(scheduler.payload?.daemon_max_observed_http_elapsed_ms || 0),
    provider_route_ready_for_manual_prep_trial: Boolean(route.payload?.provider_route_ready_for_manual_prep_trial),
    model_route_ready_for_manual_prep_trial: Boolean(route.payload?.model_route_ready_for_manual_prep_trial),
    production_authority_change: false,
    issues,
  };
}

function reduce(cycles, config, daemonOps) {
  const issues = [];
  const failed = cycles.filter((cycle) => !cycle.ok);
  const daemonRecentSlowRoutes = Array.isArray(daemonOps.payload?.http_metrics?.recent_routes)
    ? daemonOps.payload.http_metrics.recent_routes
      .filter((route) => Number(route?.slow_count || 0) > 0)
      .map((route) => ({
        route: String(route?.route || ''),
        slow_count: Number(route?.slow_count || 0),
        max_elapsed_ms: Number(route?.max_elapsed_ms || 0),
        last_elapsed_ms: Number(route?.last_elapsed_ms || 0),
      }))
    : [];
  if (failed.length) issues.push('one_or_more_sustained_cycles_failed');
  if (!daemonOps.payload?.ok) issues.push('daemon_ops_gate_failed');
  if (Number(daemonOps.payload?.recent_slow_requests || daemonOps.payload?.slow_requests || 0) > config.maxSlowRequests) {
    issues.push('daemon_slow_request_budget_exceeded');
  }
  if (daemonRecentSlowRoutes.length) issues.push('daemon_recent_slow_routes_present');
  return {
    ok: issues.length === 0,
    schema_version: 'xhub.route_authority_prep_sustained_guard.v1',
    generated_at: new Date().toISOString(),
    cycles_requested: config.cycles,
    cycles_completed: cycles.length,
    all_cycles_ok: failed.length === 0,
    max_cycle_elapsed_ms: cycles.reduce((max, cycle) => Math.max(max, cycle.elapsed_ms), 0),
    daemon_ops_gate_ok: Boolean(daemonOps.payload?.ok),
    daemon_recent_slow_requests: Number(daemonOps.payload?.recent_slow_requests || daemonOps.payload?.slow_requests || 0),
    daemon_max_observed_http_elapsed_ms: Number(daemonOps.payload?.max_observed_http_elapsed_ms || 0),
    daemon_recent_slow_routes: daemonRecentSlowRoutes,
    production_authority_change: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
    issues,
    cycle_summaries: cycles,
  };
}

function runDaemonOpsGate(config) {
  return runJson('bash', [
    path.join(SCRIPT_DIR, 'daemon_ops_gate.command'),
    '--max-slow-requests',
    String(config.maxSlowRequests),
    '--maintenance-max-log-bytes',
    '10485760',
    '--keep-report-files',
    '100',
    '--max-report-age-days',
    '30',
  ], 60000);
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `route_authority_prep_sustained_guard_${stamp}.json`);
}

function runSelfTest() {
  const result = reduce([
    { ok: true, elapsed_ms: 1, scheduler_gate_mode: 'ready', daemon_recent_slow_requests: 0, issues: [] },
  ], parseArgs([]), { payload: { ok: true, recent_slow_requests: 0, max_observed_http_elapsed_ms: 1, http_metrics: { recent_routes: [] } } });
  if (!result.ok) throw new Error(`expected self-test ok: ${result.issues.join(',')}`);
  const slow = reduce([
    { ok: true, elapsed_ms: 1, scheduler_gate_mode: 'skip', daemon_recent_slow_requests: 0, issues: [] },
  ], parseArgs([]), {
    payload: {
      ok: false,
      recent_slow_requests: 1,
      max_observed_http_elapsed_ms: 2200,
      http_metrics: {
        recent_routes: [{ route: '/xt/classic-hub-compat', slow_count: 1, max_elapsed_ms: 2200, last_elapsed_ms: 2200 }],
      },
    },
  });
  if (!slow.issues.includes('daemon_recent_slow_routes_present') || slow.daemon_recent_slow_routes.length !== 1) {
    throw new Error('expected slow route diagnostics');
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
    process.stdout.write('route_authority_prep_sustained_guard self-test ok\n');
    return;
  }
  const cycles = [];
  for (let i = 0; i < config.cycles; i += 1) {
    cycles.push(runCycle(config, i + 1));
    if (i + 1 < config.cycles) sleep(config.intervalMs);
  }
  const result = reduce(cycles, config, runDaemonOpsGate(config));
  if (config.writeReport) {
    fs.mkdirSync(REPORT_DIR, { recursive: true });
    const pathOut = reportPath();
    fs.writeFileSync(pathOut, `${JSON.stringify(result, null, 2)}\n`);
    result.report_path = pathOut;
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.ok) process.exit(2);
}

main().catch((error) => {
  process.stderr.write(`[route_authority_prep_sustained_guard] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
