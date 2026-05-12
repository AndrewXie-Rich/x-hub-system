#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const config = {
    httpBaseUrl: 'http://127.0.0.1:50151',
    httpTimeoutMs: 750,
    authorityTimeoutMs: 45000,
    queuedTimeoutMs: 70000,
    leaseDurationMs: 300000,
    readinessCacheMs: 1000,
    pollMs: 100,
    minCompareReports: 10,
    maxMismatches: 0,
    minLeaseShadowRuns: 1,
    maxStaleActive: 0,
    maxOrphanedLeases: 0,
    allowActiveRuns: true,
    fallbackOnError: true,
    runGates: false,
    expectReady: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--http-base-url':
        config.httpBaseUrl = String(next || '').trim() || config.httpBaseUrl;
        i += 1;
        break;
      case '--http-timeout-ms':
        config.httpTimeoutMs = parseIntInRange(next, config.httpTimeoutMs, 100, 300000);
        i += 1;
        break;
      case '--authority-timeout-ms':
        config.authorityTimeoutMs = parseIntInRange(next, config.authorityTimeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--queued-timeout-ms':
        config.queuedTimeoutMs = parseIntInRange(next, config.queuedTimeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--min-compare-reports':
        config.minCompareReports = parseIntInRange(next, config.minCompareReports, 0, 1000000);
        i += 1;
        break;
      case '--min-lease-shadow-runs':
        config.minLeaseShadowRuns = parseIntInRange(next, config.minLeaseShadowRuns, 0, 1000000);
        i += 1;
        break;
      case '--max-mismatches':
        config.maxMismatches = parseIntInRange(next, config.maxMismatches, 0, 1000000);
        i += 1;
        break;
      case '--max-stale-active':
        config.maxStaleActive = parseIntInRange(next, config.maxStaleActive, 0, 1000000);
        i += 1;
        break;
      case '--max-orphaned-leases':
        config.maxOrphanedLeases = parseIntInRange(next, config.maxOrphanedLeases, 0, 1000000);
        i += 1;
        break;
      case '--no-active-runs':
        config.allowActiveRuns = false;
        break;
      case '--no-fallback-on-error':
        config.fallbackOnError = false;
        break;
      case '--run-gates':
        config.runGates = true;
        break;
      case '--expect-ready':
        config.expectReady = true;
        break;
      case '--self-test':
        config.selfTest = true;
        break;
      case '--dry-run':
        config.dryRun = true;
        break;
      case '--help':
      case '-h':
        config.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return config;
}

function usage() {
  return [
    'scheduler_production_authority_plan.js',
    '',
    'Options:',
    '  --http-base-url <url>          Rust xhubd HTTP base URL, default http://127.0.0.1:50151',
    '  --http-timeout-ms <n>          Node authority HTTP timeout, default 750',
    '  --authority-timeout-ms <n>     Single authority runner timeout, default 45000',
    '  --queued-timeout-ms <n>        Queued authority runner timeout, default 70000',
    '  --min-compare-reports <n>      Scheduler readiness minimum compare reports, default 10',
    '  --min-lease-shadow-runs <n>    Scheduler readiness minimum lease shadow runs, default 1',
    '  --max-mismatches <n>           Scheduler readiness mismatch threshold, default 0',
    '  --max-stale-active <n>         Scheduler stale active run threshold, default 0',
    '  --max-orphaned-leases <n>      Scheduler orphaned lease threshold, default 0',
    '  --no-active-runs               Do not allow active runs during authority claims',
    '  --no-fallback-on-error         Make production env fail closed instead of Node fallback',
    '  --run-gates                    Execute scheduler authority validation gates',
    '  --expect-ready                 Exit non-zero unless run gates pass',
    '  --dry-run                      Print resolved config only',
    '  --self-test                    Run parser and plan self-test',
  ].join('\n');
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function commandLine(file, args = []) {
  return ['bash', shellQuote(file), ...args.map((arg) => shellQuote(arg))].join(' ');
}

function envToSet(config) {
  return {
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
    XHUB_RUST_SCHEDULER_STATUS_READ: '1',
    XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_STATUS_HTTP: '1',
    XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS: String(config.httpTimeoutMs),
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP: '1',
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_AUTHORITY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_TIMEOUT_MS: String(config.httpTimeoutMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_TO_CLI: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_OWNER: 'node-hub-paid-ai-authority',
    XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS: String(config.leaseDurationMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS: String(config.authorityTimeoutMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS: String(config.pollMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS: String(config.readinessCacheMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR: config.fallbackOnError ? '1' : '0',
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS: String(config.minCompareReports),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_MISMATCHES: String(config.maxMismatches),
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS: String(config.minLeaseShadowRuns),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_STALE_ACTIVE: String(config.maxStaleActive),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_ORPHANED_LEASES: String(config.maxOrphanedLeases),
    XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS: config.allowActiveRuns ? '1' : '0',
  };
}

function validationCommands(config) {
  const readinessArgs = [
    '--min-compare-reports', String(config.minCompareReports),
    '--min-lease-shadow-runs', String(config.minLeaseShadowRuns),
    '--max-mismatches', String(config.maxMismatches),
    '--max-stale-active', String(config.maxStaleActive),
    '--max-orphaned-leases', String(config.maxOrphanedLeases),
  ];
  return [
    {
      name: 'cutover_readiness_sustained',
      file: path.join(SCRIPT_DIR, 'scheduler_cutover_readiness_runner.command'),
      args: [
        '--runs', '3',
        '--expect-ready',
        '--expect-zero-mismatch',
        ...readinessArgs,
      ],
      timeout_ms: config.queuedTimeoutMs + 60000,
    },
    {
      name: 'http_bridge_smoke',
      file: path.join(SCRIPT_DIR, 'scheduler_authority_http_bridge_smoke.command'),
      args: [],
      timeout_ms: config.authorityTimeoutMs + 30000,
    },
    {
      name: 'single_paid_path_authority',
      file: path.join(SCRIPT_DIR, 'scheduler_authority_runner.command'),
      args: [
        '--runs', '1',
        '--timeout-ms', String(config.authorityTimeoutMs),
        '--use-existing-rust-db',
        ...readinessArgs,
      ],
      timeout_ms: config.authorityTimeoutMs + 60000,
    },
    {
      name: 'queued_backpressure_authority',
      file: path.join(SCRIPT_DIR, 'scheduler_authority_runner.command'),
      args: [
        '--runs', '1',
        '--concurrency', '3',
        '--bridge-response-delay-ms', '3000',
        '--timeout-ms', String(config.queuedTimeoutMs),
        '--expect-queued',
        '--use-existing-rust-db',
        ...readinessArgs,
      ],
      timeout_ms: config.queuedTimeoutMs + 60000,
    },
    {
      name: 'queued_cancel_terminal_authority',
      file: path.join(SCRIPT_DIR, 'scheduler_authority_runner.command'),
      args: [
        '--scenario', 'queued-cancel',
        '--bridge-response-delay-ms', '3000',
        '--timeout-ms', String(config.queuedTimeoutMs),
        '--use-existing-rust-db',
        ...readinessArgs,
      ],
      timeout_ms: config.queuedTimeoutMs + 60000,
    },
    {
      name: 'queued_timeout_terminal_authority',
      file: path.join(SCRIPT_DIR, 'scheduler_authority_runner.command'),
      args: [
        '--scenario', 'queued-timeout',
        '--timeout-ms', String(config.queuedTimeoutMs),
        '--use-existing-rust-db',
        ...readinessArgs,
      ],
      timeout_ms: config.queuedTimeoutMs + 60000,
    },
    {
      name: 'node_hub_live_authority',
      file: path.join(SCRIPT_DIR, 'node_hub_authority_live_runner.command'),
      args: [
        '--runs', '1',
        '--timeout-ms', String(config.authorityTimeoutMs),
        '--use-existing-rust-db',
        ...readinessArgs,
      ],
      timeout_ms: config.authorityTimeoutMs + 90000,
    },
  ];
}

function runCommand(spec) {
  const startedAt = new Date().toISOString();
  let stdout = '';
  let stderr = '';
  let exitCode = 0;
  try {
    stdout = execFileSync(spec.file, spec.args, {
      encoding: 'utf8',
      timeout: spec.timeout_ms,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 16 * 1024 * 1024,
    });
  } catch (error) {
    exitCode = Number(error.status || 1);
    stdout = String(error.stdout || '');
    stderr = String(error.stderr || error.message || '');
  }
  return {
    name: spec.name,
    ok: exitCode === 0,
    exit_code: exitCode,
    command: commandLine(spec.file, spec.args),
    started_at: startedAt,
    finished_at: new Date().toISOString(),
    stdout_tail: stdout.slice(-4000),
    stderr_tail: stderr.slice(-4000),
  };
}

function buildPlan(config, gateResults = []) {
  const env = envToSet(config);
  const validations = validationCommands(config);
  const gatesWereRun = gateResults.length > 0;
  const gatesOk = gatesWereRun && gateResults.every((result) => result.ok);
  const ready = gatesOk;
  return {
    ok: true,
    schema_version: 'xhub.scheduler_production_authority_plan.v1',
    generated_at: new Date().toISOString(),
    rust_hub_root: ROOT_DIR,
    production_authority_change_planned: true,
    apply_performed: false,
    ready_for_scheduler_authority_apply: ready,
    gates_were_run: gatesWereRun,
    gates_ok: gatesOk,
    scheduler_authority_target: true,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    xt_file_ipc_authority_target: false,
    ui_product_change: false,
    node_process_restart_required: true,
    secret_leak: false,
    key_printed: false,
    env_to_set: env,
    env_export_commands: Object.entries(env).map(([key, value]) => `export ${key}=${shellQuote(value)}`),
    rollback_unset_commands: Object.keys(env).map((key) => `unset ${key}`),
    validation_commands: validations.map((spec) => commandLine(spec.file, spec.args)),
    gate_results: gateResults,
    release_gate_policy: {
      scheduler_only: true,
      requires_cutover_readiness_sustained: true,
      requires_http_bridge_smoke: true,
      requires_single_paid_path_authority: true,
      requires_queued_backpressure_authority: true,
      requires_queued_cancel_terminal_authority: true,
      requires_queued_timeout_terminal_authority: true,
      requires_node_hub_live_authority: true,
      provider_model_memory_skills_xt_authority_blocked: true,
    },
    blocked_authorities: [
      {
        name: 'provider_route',
        reason: 'authority bridge remains prep/observe; no production Bridge payload cutover is implemented',
      },
      {
        name: 'model_route',
        reason: 'selected-model authority remains candidate-only until explicit production cutover is implemented',
      },
      {
        name: 'memory_writer',
        reason: 'canonical memory writer in Rust is not implemented as production truth',
      },
      {
        name: 'skills_execution',
        reason: 'Rust skill vetting exists, but production skill execution authority is not implemented',
      },
      {
        name: 'xt_file_ipc',
        reason: 'XT file IPC remains shadow/readiness-gated and must not change the SwiftUI product UI',
      },
    ],
  };
}

function runSelfTest() {
  const defaultConfig = parseArgs([]);
  const defaultPlan = buildPlan(defaultConfig, []);
  const validationNames = validationCommands(defaultConfig).map((spec) => spec.name);
  const validationArgs = validationCommands(defaultConfig)
    .map((spec) => spec.args.join(' '))
    .join('\n');
  const expectedValidationNames = [
    'cutover_readiness_sustained',
    'http_bridge_smoke',
    'single_paid_path_authority',
    'queued_backpressure_authority',
    'queued_cancel_terminal_authority',
    'queued_timeout_terminal_authority',
    'node_hub_live_authority',
  ];
  if (
    defaultConfig.minCompareReports !== 10
    || defaultConfig.minLeaseShadowRuns !== 1
    || JSON.stringify(validationNames) !== JSON.stringify(expectedValidationNames)
    || !validationArgs.includes('--min-compare-reports 10')
    || !validationArgs.includes('--min-lease-shadow-runs 1')
    || !validationArgs.includes('--max-mismatches 0')
    || defaultPlan.release_gate_policy?.requires_cutover_readiness_sustained !== true
    || defaultPlan.release_gate_policy?.requires_queued_cancel_terminal_authority !== true
    || defaultPlan.release_gate_policy?.requires_queued_timeout_terminal_authority !== true
  ) {
    throw new Error('self-test failed: release gate defaults drifted');
  }

  const config = parseArgs([
    '--http-base-url', 'http://127.0.0.1:59999',
    '--authority-timeout-ms', '30000',
    '--queued-timeout-ms', '50000',
    '--min-compare-reports', '2',
    '--min-lease-shadow-runs', '2',
    '--no-active-runs',
    '--no-fallback-on-error',
  ]);
  const plan = buildPlan(config, [
    {
      name: 'fake',
      ok: true,
      exit_code: 0,
      command: 'fake',
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
      stdout_tail: '',
      stderr_tail: '',
    },
  ]);
  if (
    plan.ready_for_scheduler_authority_apply !== true
    || plan.scheduler_authority_target !== true
    || plan.memory_writer_authority_target !== false
    || plan.env_to_set.XHUB_RUST_SCHEDULER_AUTHORITY !== '1'
    || plan.env_to_set.XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS !== '0'
    || plan.env_to_set.XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR !== '0'
  ) {
    throw new Error('self-test failed');
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
    process.stdout.write('scheduler_production_authority_plan self-test ok\n');
    return;
  }
  if (config.dryRun) {
    process.stdout.write(`${JSON.stringify({ ok: true, dry_run: true, config }, null, 2)}\n`);
    return;
  }
  const results = config.runGates
    ? validationCommands(config).map((spec) => runCommand(spec))
    : [];
  const plan = buildPlan(config, results);
  process.stdout.write(`${JSON.stringify(plan, null, 2)}\n`);
  if (config.expectReady && !plan.ready_for_scheduler_authority_apply) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  process.stderr.write(`[scheduler_production_authority_plan] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
