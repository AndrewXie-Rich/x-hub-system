#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const INNER_FAILURE_SCHEMA = 'xhub.route_authority.inner_failure.v1';

function safeString(value) {
  return String(value ?? '').trim();
}

function redactDiagnosticText(value) {
  const original = String(value ?? '');
  const redacted = original
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [REDACTED]')
    .replace(/(X-XHub-Access-Key\s*[:=]\s*)[A-Za-z0-9._~+/=-]+/gi, '$1[REDACTED]')
    .replace(/(XHUB_[A-Z0-9_]*ACCESS_KEY\s*=\s*)[^\s]+/gi, '$1[REDACTED]')
    .replace(/("?(?:api_key|access_key|token|secret)"?\s*[:=]\s*")([^"\n]+)(")/gi, '$1[REDACTED]$3')
    .replace(/([?&](?:api_key|access_key|access_token|token|key)=)[^&\s]+/gi, '$1[REDACTED]')
    .replace(/\bsk-[A-Za-z0-9][A-Za-z0-9_-]{12,}\b/g, 'sk-[REDACTED]')
    .replace(/\b[a-f0-9]{48,128}\b/gi, '[REDACTED_HEX]');
  return { text: redacted, redaction_applied: redacted !== original };
}

function boundedDiagnostic(value, maxChars = 2000, maxLines = 20) {
  const redacted = redactDiagnosticText(value);
  const lines = redacted.text.split(/\r?\n/).slice(-maxLines).join('\n');
  return { text: lines.slice(-maxChars), redaction_applied: redacted.redaction_applied };
}

function innerFailureKind(exitCode, parsed, decision) {
  if (exitCode !== 0 && exitCode !== 2) return 'execution_failed';
  if (!parsed) return 'output_not_parseable';
  if (exitCode === 2 || decision === 'not_ready') return 'not_ready';
  return 'contract_failed';
}

function normalizeInnerFailure(value, defaults = {}) {
  const parseDiagnostic = boundedDiagnostic(value?.parse_error, 500, 5);
  const stderrDiagnostic = boundedDiagnostic(value?.stderr_tail || value?.stderr, 2000, 20);
  const exitCode = Number(value?.exit_code ?? defaults.exit_code ?? -1);
  const parsed = value?.parsed === true;
  const decision = safeString(value?.decision || defaults.decision).slice(0, 128);
  return {
    schema_version: INNER_FAILURE_SCHEMA,
    cycle: Number(defaults.cycle || value?.cycle || 0),
    component: safeString(value?.component || defaults.component).slice(0, 64),
    stage: safeString(value?.stage || defaults.stage).slice(0, 128),
    parent_stage: safeString(value?.parent_stage || defaults.parent_stage).slice(0, 128),
    kind: ['execution_failed', 'output_not_parseable', 'not_ready', 'contract_failed']
      .includes(safeString(value?.kind))
      ? safeString(value.kind)
      : innerFailureKind(exitCode, parsed, decision),
    exit_code: exitCode,
    parsed,
    decision,
    parse_error: parseDiagnostic.text,
    stderr_tail: stderrDiagnostic.text,
    failed_checks: Array.isArray(value?.failed_checks)
      ? value.failed_checks.map((item) => safeString(item).slice(0, 128)).filter(Boolean).slice(0, 32)
      : [],
    diagnostic_redaction_applied: value?.diagnostic_redaction_applied === true
      || parseDiagnostic.redaction_applied
      || stderrDiagnostic.redaction_applied,
  };
}

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
    allowMemorySkillsProduction: false,
    requireMemorySkillsProduction: false,
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
      case '--allow-memory-skills-production':
        out.allowMemorySkillsProduction = true;
        break;
      case '--require-memory-skills-production':
        out.allowMemorySkillsProduction = true;
        out.requireMemorySkillsProduction = true;
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
    '  --allow-memory-skills-production Permit explicit Rust memory writer and skills execution authority',
    '  --require-memory-skills-production Require both Rust memory writer and skills execution authority',
    '  --no-report              Print only; do not write reports/',
    '  --self-test              Validate reducer logic',
  ].join('\n');
}

function memorySkillsArgs(config) {
  if (config.requireMemorySkillsProduction) return ['--require-memory-skills-production'];
  if (config.allowMemorySkillsProduction) return ['--allow-memory-skills-production'];
  return [];
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
    stderr = String(error.stderr || error.message || '');
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

function buildCycleSummary(config, cycleIndex, elapsedMs, runtime, route, scheduler) {
  const issues = [];
  if (!runtime.payload?.ok) issues.push('prep_runtime_guard_failed');
  if (!route.payload?.ok) issues.push('route_cutover_guard_failed');
  if (config.schedulerGateMode === 'applied' && !scheduler.payload?.ok) issues.push('scheduler_guard_failed');
  if (elapsedMs > config.maxCycleMs) issues.push('cycle_latency_budget_exceeded');
  const innerFailures = [];
  const routeInnerFailures = Array.isArray(route.payload?.inner_failures)
    ? route.payload.inner_failures
    : [];
  for (const failure of routeInnerFailures) {
    innerFailures.push(normalizeInnerFailure(failure, {
      cycle: cycleIndex,
      parent_stage: 'route_authority_cutover_guard',
    }));
  }
  if (!runtime.payload?.ok || runtime.exit_code !== 0 || runtime.parsed !== true) {
    innerFailures.push(normalizeInnerFailure({
      component: 'route_authority',
      stage: 'route_authority_prep_runtime_guard',
      parent_stage: 'route_authority_prep_sustained_guard',
      exit_code: Number(runtime.exit_code ?? -1),
      parsed: runtime.parsed === true,
      decision: 'not_ready',
      parse_error: runtime.parse_error,
      stderr_tail: runtime.stderr,
      failed_checks: ['prep_runtime_guard_failed'],
    }, { cycle: cycleIndex }));
  }
  if (!route.payload?.ok || route.exit_code !== 0 || route.parsed !== true) {
    innerFailures.push(normalizeInnerFailure({
      component: 'route_authority',
      stage: 'route_authority_cutover_guard',
      parent_stage: 'route_authority_prep_sustained_guard',
      exit_code: Number(route.exit_code ?? -1),
      parsed: route.parsed === true,
      decision: 'not_ready',
      parse_error: route.parse_error,
      stderr_tail: route.stderr,
      failed_checks: Array.isArray(route.payload?.issues)
        ? route.payload.issues
        : ['route_cutover_guard_failed'],
    }, { cycle: cycleIndex }));
  }
  if (config.schedulerGateMode === 'applied'
    && (!scheduler.payload?.ok || scheduler.exit_code !== 0 || scheduler.parsed !== true)) {
    innerFailures.push(normalizeInnerFailure({
      component: 'scheduler',
      stage: 'scheduler_production_authority_guard',
      parent_stage: 'route_authority_prep_sustained_guard',
      exit_code: Number(scheduler.exit_code ?? -1),
      parsed: scheduler.parsed === true,
      decision: 'not_ready',
      parse_error: scheduler.parse_error,
      stderr_tail: scheduler.stderr,
      failed_checks: ['scheduler_guard_failed'],
    }, { cycle: cycleIndex }));
  }
  const routeParseError = boundedDiagnostic(route.parse_error, 500, 5);
  const routeStderr = boundedDiagnostic(route.stderr, 2000, 20);
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
    route_guard_exit_code: Number(route.exit_code ?? -1),
    route_guard_parsed: route.parsed === true,
    route_guard_parse_error: routeParseError.text,
    route_guard_stderr_tail: routeStderr.text,
    inner_failure_count: innerFailures.length,
    inner_failures: innerFailures,
    production_authority_change: false,
    issues,
  };
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
    ...memorySkillsArgs(config),
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
      ...memorySkillsArgs(config),
    ], 60000);
  }
  const elapsedMs = Date.now() - started;
  return buildCycleSummary(config, cycleIndex, elapsedMs, runtime, route, scheduler);
}

function reduce(cycles, config, daemonOps) {
  const issues = [];
  const failed = cycles.filter((cycle) => !cycle.ok);
  const innerFailures = cycles.flatMap((cycle) => (
    Array.isArray(cycle?.inner_failures) ? cycle.inner_failures : []
  ));
  const innerFailureStages = Array.from(new Set(
    innerFailures.map((failure) => safeString(failure?.stage)).filter(Boolean),
  ));
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
    inner_failure_count: innerFailures.length,
    inner_failure_stages: innerFailureStages,
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
    ...memorySkillsArgs(config),
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
  const secret = 'sk-sustained-inner-failure-secret-1234567890';
  const failedCycle = buildCycleSummary(
    parseArgs([]),
    7,
    25,
    { exit_code: 0, parsed: true, payload: { ok: true } },
    {
      exit_code: 2,
      parsed: true,
      parse_error: '',
      stderr: '',
      payload: {
        ok: false,
        issues: ['provider_route_authority_plan_not_ready'],
        inner_failures: [{
          component: 'provider_route',
          stage: 'provider_shadow_runner',
          parent_stage: 'provider_cutover_readiness_runner',
          kind: 'execution_failed',
          exit_code: 1,
          parsed: false,
          decision: 'not_ready',
          parse_error: 'runner output did not contain JSON',
          stderr_tail: `Error [ERR_MODULE_NOT_FOUND] X-XHub-Access-Key: ${secret}`,
          failed_checks: ['provider_shadow_runner_ok'],
          stdout: secret,
        }],
      },
    },
    { exit_code: 0, parsed: true, payload: { ok: true } },
  );
  const failedResult = reduce([failedCycle], parseArgs([]), {
    payload: {
      ok: true,
      recent_slow_requests: 0,
      max_observed_http_elapsed_ms: 1,
      http_metrics: { recent_routes: [] },
    },
  });
  const failureJson = JSON.stringify(failedCycle.inner_failures);
  if (
    failedCycle.ok !== false
    || failedCycle.route_guard_exit_code !== 2
    || failedCycle.inner_failure_count !== 2
    || failedCycle.inner_failures[0]?.cycle !== 7
    || !failureJson.includes('ERR_MODULE_NOT_FOUND')
    || failureJson.includes(secret)
    || failedResult.inner_failure_count !== 2
    || !failedResult.inner_failure_stages.includes('provider_shadow_runner')
  ) {
    throw new Error('expected sustained inner failure propagation and redaction');
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
