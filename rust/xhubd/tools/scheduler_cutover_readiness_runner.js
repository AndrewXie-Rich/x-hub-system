#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

async function main(argv) {
  const flags = parseFlags(argv);
  if (flags.has('help') || flags.has('h')) {
    process.stdout.write(helpText());
    return 0;
  }
  if (flags.has('self-test')) {
    runSelfTest();
    process.stdout.write('scheduler_cutover_readiness_runner self-test ok\n');
    return 0;
  }

  const config = resolveConfig(flags);
  if (flags.has('dry-run')) {
    process.stdout.write(JSON.stringify({
      schema_version: 'xhub.scheduler_cutover_readiness_runner.dry_run.v1',
      ok: true,
      config: publicConfig(config),
    }, null, 2) + '\n');
    return 0;
  }

  const previousEnv = captureEnv([
    'HUB_RUNTIME_BASE_DIR',
    'HUB_CLIENT_TOKEN',
    'XHUB_RUST_SCHEDULER_SHADOW_COMPARE',
    'XHUB_RUST_HUB_ROOT',
    'XHUB_RUST_HUB_RUNNER',
    'XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS',
    'XHUB_RUST_SCHEDULER_SHADOW_COMPARE_TIMEOUT_MS',
  ]);
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub_cutover_readiness_runtime_'));
  const nodeDbPath = path.join(
    os.tmpdir(),
    `xhub_cutover_readiness_${process.pid}_${Date.now()}_${Math.random().toString(16).slice(2)}.sqlite3`
  );

  try {
    process.env.HUB_RUNTIME_BASE_DIR = runtimeBaseDir;
    process.env.HUB_CLIENT_TOKEN = '';
    process.env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE = '1';
    process.env.XHUB_RUST_HUB_ROOT = config.rustHubRoot;
    process.env.XHUB_RUST_HUB_RUNNER = config.runner;
    process.env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS = String(config.shadowThrottleMs);
    process.env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_TIMEOUT_MS = String(config.timeoutMs);

    const src = path.join(config.xhubSystemRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src');
    const [{ HubDB }, { HubEventBus }, { makeServices }, { createSchedulerLeaseShadowBridge }] = await Promise.all([
      import(pathToFileURL(path.join(src, 'db.js')).href),
      import(pathToFileURL(path.join(src, 'event_bus.js')).href),
      import(pathToFileURL(path.join(src, 'services.js')).href),
      import(pathToFileURL(path.join(src, 'rust_scheduler_lease_shadow_bridge.js')).href),
    ]);

    const db = new HubDB({ dbPath: nodeDbPath });
    const leaseBridge = createSchedulerLeaseShadowBridge({
      env: {
        XHUB_RUST_SCHEDULER_LEASE_SHADOW: '1',
        XHUB_RUST_HUB_ROOT: config.rustHubRoot,
        XHUB_RUST_HUB_RUNNER: config.runner,
        XHUB_RUST_SCHEDULER_LEASE_SHADOW_TIMEOUT_MS: String(config.timeoutMs),
        XHUB_RUST_SCHEDULER_LEASE_SHADOW_OWNER: config.leaseOwner,
        XHUB_RUST_SCHEDULER_LEASE_SHADOW_DURATION_MS: String(config.leaseDurationMs),
      },
    });

    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const reportsBefore = readReports(config.runner, config.reportLimit);
      const leaseBefore = readLeaseShadowReport(config.runner, config.leaseReportLimit, config.staleAfterMs);
      let latestReports = reportsBefore;
      let latestLease = leaseBefore;
      let latestReadiness = readCutoverReadiness(config);
      const iterations = [];

      emitEvent('start', {
        config: publicConfig(config),
        reports_before: reportsBefore,
        lease_shadow_before: leaseBefore,
        readiness_before: latestReadiness,
      });

      for (let index = 0; index < config.runs; index += 1) {
        const previousTotal = safeInt(latestReports.total);
        const response = invokeUnary(impl.HubRuntime.GetSchedulerStatus, {
          include_queue_items: true,
          queue_items_limit: 20,
        });
        latestReports = await waitForReportIncrease({
          runner: config.runner,
          previousTotal,
          timeoutMs: config.timeoutMs,
          pollMs: config.pollMs,
          reportLimit: config.reportLimit,
        });

        const leaseIds = [];
        for (let leaseIndex = 0; leaseIndex < config.leaseRunsPerIteration; leaseIndex += 1) {
          const requestId = [
            'cutover_ready',
            process.pid,
            Date.now(),
            index + 1,
            leaseIndex + 1,
          ].join('_');
          leaseBridge.mirrorImmediateAcquire({
            requestId,
            scopeKey: `project:cutover-readiness-${index + 1}`,
            project_id: `cutover-readiness-${index + 1}`,
            device_id: 'cutover-readiness-runner',
          });
          leaseBridge.mirrorRelease({ requestId });
          leaseIds.push(requestId);
        }
        await leaseBridge.flush();

        latestLease = readLeaseShadowReport(config.runner, config.leaseReportLimit, config.staleAfterMs);
        latestReadiness = readCutoverReadiness(config);

        const item = {
          run_index: index + 1,
          node_snapshot: normalizePaidAI(response.paid_ai),
          report_total: safeInt(latestReports.total),
          report_mismatched: safeInt(latestReports.mismatched),
          lease_shadow_runs: safeInt(latestLease?.totals?.runs),
          readiness_ready: latestReadiness.ready === true,
          readiness_decision: String(latestReadiness.decision || ''),
          lease_request_ids: leaseIds,
        };
        iterations.push(item);
        emitEvent('iteration', item);

        if (latestReadiness.ready === true && !config.continueAfterReady) break;
        if (index + 1 < config.runs && config.intervalMs > 0) {
          await sleep(config.intervalMs);
        }
      }

      const reportsAdded = diffReports(reportsBefore, latestReports);
      const ok = (!config.expectZeroMismatch || reportsAdded.mismatched === 0)
        && (!config.expectReady || latestReadiness.ready === true);
      const finalPayload = {
        ok,
        reports_added: reportsAdded,
        reports_after: latestReports,
        lease_shadow_after: latestLease,
        readiness_after: latestReadiness,
        iterations,
      };
      emitEvent('stop', finalPayload);
      return ok ? 0 : 2;
    } finally {
      try {
        db.close();
      } catch {
        // ignore
      }
    }
  } finally {
    restoreEnv(previousEnv);
    cleanupDbArtifacts(nodeDbPath);
    try {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
}

function invokeUnary(fn, request) {
  let response = null;
  let error = null;
  fn(makeDirectCall(request), (err, out) => {
    error = err || null;
    response = out || null;
  });
  if (error) throw error;
  return response || {};
}

function makeDirectCall(request) {
  return {
    request,
    metadata: { get: () => [] },
    getPeer() {
      return 'ipv4:127.0.0.1:55331';
    },
  };
}

async function waitForReportIncrease({ runner, previousTotal, timeoutMs, pollMs, reportLimit }) {
  const started = Date.now();
  let latest = readReports(runner, reportLimit);
  while (Date.now() - started <= timeoutMs) {
    if (safeInt(latest.total) > safeInt(previousTotal)) return latest;
    await sleep(pollMs);
    latest = readReports(runner, reportLimit);
  }
  throw new Error(`scheduler report total did not increase within ${timeoutMs}ms`);
}

function readReports(runner, limit) {
  return readRunnerJson(runner, ['scheduler', 'reports', '--limit', String(limit)]);
}

function readLeaseShadowReport(runner, limit, staleAfterMs) {
  return readRunnerJson(runner, [
    'scheduler',
    'lease-shadow-report',
    '--limit',
    String(limit),
    '--stale-after-ms',
    String(staleAfterMs),
  ]);
}

function readCutoverReadiness(config) {
  return readRunnerJson(config.runner, buildCutoverReadinessArgs(config));
}

function readRunnerJson(runner, args) {
  const stdout = execFileSync(runner, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return JSON.parse(stdout);
}

function buildCutoverReadinessArgs(config) {
  return [
    'scheduler',
    'cutover-readiness',
    '--compare-limit',
    String(config.reportLimit),
    '--lease-report-limit',
    String(config.leaseReportLimit),
    '--stale-after-ms',
    String(config.staleAfterMs),
    '--min-compare-reports',
    String(config.minCompareReports),
    '--max-mismatches',
    String(config.maxMismatches),
    '--min-lease-shadow-runs',
    String(config.minLeaseShadowRuns),
    '--max-stale-active',
    String(config.maxStaleActive),
    '--max-orphaned-leases',
    String(config.maxOrphanedLeases),
  ];
}

function resolveConfig(flags) {
  const rustHubRoot = path.resolve(flags.get('rust-hub-root') || path.join(__dirname, '..'));
  const xhubSystemRoot = path.resolve(flags.get('xhub-system-root') || findXHubSystemRoot(rustHubRoot));
  const runner = path.resolve(flags.get('runner') || path.join(rustHubRoot, 'tools', 'run_rust_hub.command'));
  const runs = parseIntFlag(flags, 'runs', 5, 1);
  const minCompareReports = parseIntFlag(flags, 'min-compare-reports', 10, 0);
  return {
    rustHubRoot,
    xhubSystemRoot,
    runner,
    runs,
    intervalMs: parseIntFlag(flags, 'interval-ms', 500, 0),
    timeoutMs: parseIntFlag(flags, 'timeout-ms', 15000, 1),
    pollMs: parseIntFlag(flags, 'poll-ms', 250, 1),
    reportLimit: parseIntFlag(flags, 'report-limit', Math.max(20, minCompareReports + runs + 5), 1),
    leaseReportLimit: parseIntFlag(flags, 'lease-report-limit', 50, 1),
    staleAfterMs: parseIntFlag(flags, 'stale-after-ms', 300000, 1),
    shadowThrottleMs: parseIntFlag(flags, 'shadow-throttle-ms', 250, 1),
    leaseRunsPerIteration: parseIntFlag(flags, 'lease-runs-per-iteration', 1, 0),
    leaseOwner: String(flags.get('lease-owner') || 'node-hub-paid-ai-shadow').trim(),
    leaseDurationMs: parseIntFlag(flags, 'lease-duration-ms', 300000, 1000),
    minCompareReports,
    maxMismatches: parseIntFlag(flags, 'max-mismatches', 0, 0),
    minLeaseShadowRuns: parseIntFlag(flags, 'min-lease-shadow-runs', 1, 0),
    maxStaleActive: parseIntFlag(flags, 'max-stale-active', 0, 0),
    maxOrphanedLeases: parseIntFlag(flags, 'max-orphaned-leases', 0, 0),
    expectReady: flagEnabled(flags, 'expect-ready'),
    expectZeroMismatch: flagEnabled(flags, 'expect-zero-mismatch'),
    continueAfterReady: flagEnabled(flags, 'continue-after-ready'),
  };
}

function publicConfig(config) {
  return {
    rust_hub_root: config.rustHubRoot,
    xhub_system_root: config.xhubSystemRoot,
    runner: config.runner,
    runs: config.runs,
    interval_ms: config.intervalMs,
    timeout_ms: config.timeoutMs,
    poll_ms: config.pollMs,
    report_limit: config.reportLimit,
    lease_report_limit: config.leaseReportLimit,
    stale_after_ms: config.staleAfterMs,
    shadow_throttle_ms: config.shadowThrottleMs,
    lease_runs_per_iteration: config.leaseRunsPerIteration,
    lease_owner: config.leaseOwner,
    lease_duration_ms: config.leaseDurationMs,
    min_compare_reports: config.minCompareReports,
    max_mismatches: config.maxMismatches,
    min_lease_shadow_runs: config.minLeaseShadowRuns,
    max_stale_active: config.maxStaleActive,
    max_orphaned_leases: config.maxOrphanedLeases,
    expect_ready: config.expectReady,
    expect_zero_mismatch: config.expectZeroMismatch,
    continue_after_ready: config.continueAfterReady,
  };
}

function parseFlags(argv) {
  const flags = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) throw new Error(`unexpected positional argument: ${token}`);
    const body = token.slice(2);
    if (!body) throw new Error('empty flag is not supported');
    const eq = body.indexOf('=');
    if (eq >= 0) {
      flags.set(body.slice(0, eq), body.slice(eq + 1));
      continue;
    }
    const next = argv[index + 1];
    if (next != null && !next.startsWith('--')) {
      flags.set(body, next);
      index += 1;
    } else {
      flags.set(body, 'true');
    }
  }
  return flags;
}

function parseIntFlag(flags, key, fallback, min = 1) {
  if (!flags.has(key)) return fallback;
  const value = Number.parseInt(flags.get(key), 10);
  if (!Number.isFinite(value)) throw new Error(`--${key} must be an integer`);
  return Math.max(min, value);
}

function flagEnabled(flags, key) {
  if (!flags.has(key)) return false;
  const value = String(flags.get(key) || '').trim().toLowerCase();
  return !['', '0', 'false', 'no', 'off'].includes(value);
}

function findXHubSystemRoot(startDir) {
  let current = path.resolve(startDir);
  for (;;) {
    const candidate = path.join(current, 'x-hub-system');
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'services.js'))) {
      return candidate;
    }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  throw new Error('Unable to locate x-hub-system. Pass --xhub-system-root <path>.');
}

function normalizePaidAI(value = {}) {
  return {
    in_flight_total: safeInt(value.in_flight_total),
    queue_depth: safeInt(value.queue_depth),
    oldest_queued_ms: safeInt(value.oldest_queued_ms),
  };
}

function diffReports(before, after) {
  return {
    total: Math.max(0, safeInt(after?.total) - safeInt(before?.total)),
    matched: Math.max(0, safeInt(after?.matched) - safeInt(before?.matched)),
    mismatched: Math.max(0, safeInt(after?.mismatched) - safeInt(before?.mismatched)),
  };
}

function emitEvent(event, payload = {}) {
  process.stdout.write(JSON.stringify({
    schema_version: 'xhub.scheduler_cutover_readiness_runner.v1',
    event,
    at_ms: Date.now(),
    ...payload,
  }) + '\n');
}

function captureEnv(keys) {
  return new Map(keys.map((key) => [key, process.env[key]]));
}

function restoreEnv(previous) {
  for (const [key, value] of previous.entries()) {
    if (value == null) delete process.env[key];
    else process.env[key] = value;
  }
}

function cleanupDbArtifacts(dbPath) {
  for (const suffix of ['', '-wal', '-shm']) {
    try {
      fs.rmSync(`${dbPath}${suffix}`, { force: true });
    } catch {
      // ignore
    }
  }
}

function safeInt(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.max(0, Math.floor(number));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function runSelfTest() {
  const flags = parseFlags([
    '--runs',
    '3',
    '--interval-ms=0',
    '--expect-ready',
    '--min-compare-reports',
    '10',
  ]);
  const config = resolveConfig(flags);
  assert.equal(config.runs, 3);
  assert.equal(config.intervalMs, 0);
  assert.equal(config.expectReady, true);
  assert.equal(config.minCompareReports, 10);
  assert.deepEqual(diffReports(
    { total: 7, matched: 7, mismatched: 0 },
    { total: 10, matched: 10, mismatched: 0 }
  ), { total: 3, matched: 3, mismatched: 0 });
  assert.deepEqual(normalizePaidAI({
    in_flight_total: '1',
    queue_depth: '2',
    oldest_queued_ms: '3',
  }), {
    in_flight_total: 1,
    queue_depth: 2,
    oldest_queued_ms: 3,
  });
  assert.deepEqual(buildCutoverReadinessArgs(config).slice(0, 4), [
    'scheduler',
    'cutover-readiness',
    '--compare-limit',
    String(config.reportLimit),
  ]);
}

function helpText() {
  return `Usage:
  node tools/scheduler_cutover_readiness_runner.js [options]

Options:
  --rust-hub-root <path>           Rust Hub root, default parent of this tools dir
  --xhub-system-root <path>        x-hub-system root, auto-detected
  --runner <path>                  Rust Hub runner command
  --runs <n>                       Max evidence iterations, default 5
  --interval-ms <n>                Delay between iterations, default 500
  --timeout-ms <n>                 Wait timeout for compare/lease commands, default 15000
  --poll-ms <n>                    Compare report polling interval, default 250
  --lease-runs-per-iteration <n>   Lease shadow runs per iteration, default 1
  --min-compare-reports <n>        Readiness threshold, default 10
  --max-mismatches <n>             Readiness threshold, default 0
  --min-lease-shadow-runs <n>      Readiness threshold, default 1
  --max-stale-active <n>           Readiness threshold, default 0
  --max-orphaned-leases <n>        Readiness threshold, default 0
  --expect-ready                   Exit 2 unless final readiness is ready=true
  --expect-zero-mismatch           Exit 2 if newly added reports include mismatch
  --continue-after-ready           Keep collecting until --runs even after ready=true
  --dry-run                        Print resolved config
  --self-test                      Run local parser tests
`;
}

if (require.main === module) {
  main(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      process.stderr.write(`${error.stack || error.message}\n`);
      process.exitCode = 1;
    });
}
