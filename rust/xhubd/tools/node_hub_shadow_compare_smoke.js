#!/usr/bin/env node
'use strict';

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

  const root = path.resolve(flags.get('rust-hub-root') || path.join(__dirname, '..'));
  const runner = path.resolve(flags.get('runner') || path.join(root, 'tools', 'run_rust_hub.command'));
  const xhubSystemRoot = path.resolve(flags.get('xhub-system-root') || findXHubSystemRoot(root));
  const timeoutMs = parseIntFlag(flags, 'timeout-ms', 10000);
  const pollMs = parseIntFlag(flags, 'poll-ms', 250);
  const runs = parseIntFlag(flags, 'runs', 1);
  const intervalMs = parseIntFlag(flags, 'interval-ms', 1000);
  const reportLimit = parseIntFlag(flags, 'report-limit', Math.max(5, Math.min(100, runs + 5)));
  const expectZeroMismatch = flagEnabled(flags, 'expect-zero-mismatch');

  const before = readReports(runner, reportLimit);
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub_node_shadow_runtime_'));
  const nodeDbPath = path.join(
    os.tmpdir(),
    `xhub_node_shadow_compare_${process.pid}_${Date.now()}_${Math.random().toString(16).slice(2)}.sqlite3`
  );

  const previousEnv = captureEnv([
    'HUB_RUNTIME_BASE_DIR',
    'HUB_CLIENT_TOKEN',
    'XHUB_RUST_SCHEDULER_SHADOW_COMPARE',
    'XHUB_RUST_HUB_ROOT',
    'XHUB_RUST_HUB_RUNNER',
    'XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS',
    'XHUB_RUST_SCHEDULER_SHADOW_COMPARE_TIMEOUT_MS',
  ]);

  try {
    process.env.HUB_RUNTIME_BASE_DIR = runtimeBaseDir;
    process.env.HUB_CLIENT_TOKEN = '';
    process.env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE = '1';
    process.env.XHUB_RUST_HUB_ROOT = root;
    process.env.XHUB_RUST_HUB_RUNNER = runner;
    process.env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS = String(
      parseIntFlag(flags, 'shadow-throttle-ms', 250)
    );
    process.env.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_TIMEOUT_MS = String(timeoutMs);

    const src = path.join(xhubSystemRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src');
    const [{ HubDB }, { HubEventBus }, { makeServices }] = await Promise.all([
      import(pathToFileURL(path.join(src, 'db.js')).href),
      import(pathToFileURL(path.join(src, 'event_bus.js')).href),
      import(pathToFileURL(path.join(src, 'services.js')).href),
    ]);

    const db = new HubDB({ dbPath: nodeDbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const nodeSnapshots = [];
      let latest = before;
      for (let index = 0; index < runs; index += 1) {
        const response = invokeUnary(impl.HubRuntime.GetSchedulerStatus, {
          include_queue_items: true,
          queue_items_limit: 20,
        });
        const paidAi = response.paid_ai || {};
        nodeSnapshots.push({
          run_index: index + 1,
          in_flight_total: safeInt(paidAi.in_flight_total),
          queue_depth: safeInt(paidAi.queue_depth),
          oldest_queued_ms: safeInt(paidAi.oldest_queued_ms),
        });
        latest = await waitForReportIncrease({
          runner,
          previousTotal: latest.total,
          timeoutMs,
          pollMs,
          reportLimit,
        });
        if (index + 1 < runs && intervalMs > 0) {
          await sleep(intervalMs);
        }
      }
      const after = latest;
      const added = {
        total: Math.max(0, safeInt(after.total) - safeInt(before.total)),
        matched: Math.max(0, safeInt(after.matched) - safeInt(before.matched)),
        mismatched: Math.max(0, safeInt(after.mismatched) - safeInt(before.mismatched)),
      };
      const ok = !expectZeroMismatch || added.mismatched === 0;
      process.stdout.write(
        JSON.stringify(
          {
            schema_version: 'xhub.node_hub_shadow_compare_smoke.v1',
            ok,
            rust_hub_root: root,
            xhub_system_root: xhubSystemRoot,
            runs_requested: runs,
            runs_completed: nodeSnapshots.length,
            interval_ms: intervalMs,
            report_limit: reportLimit,
            expect_zero_mismatch: expectZeroMismatch,
            node_snapshots: nodeSnapshots,
            reports_added: added,
            latest_match_result: String(after.rows?.[0]?.match_result || ''),
            latest_mismatches: Array.isArray(after.rows?.[0]?.mismatches)
              ? after.rows[0].mismatches
              : [],
            node_snapshot: {
              in_flight_total: nodeSnapshots[nodeSnapshots.length - 1]?.in_flight_total || 0,
              queue_depth: nodeSnapshots[nodeSnapshots.length - 1]?.queue_depth || 0,
              oldest_queued_ms: nodeSnapshots[nodeSnapshots.length - 1]?.oldest_queued_ms || 0,
            },
            reports_before: before,
            reports_after: after,
          },
          null,
          2
        ) + '\n'
      );
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
    metadata: {
      get() {
        return [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:55221';
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

function readReports(runner, limit = 5) {
  const stdout = execFileSync(runner, ['scheduler', 'reports', '--limit', String(limit)], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return JSON.parse(stdout);
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

function parseFlags(argv) {
  const flags = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      throw new Error(`unexpected positional argument: ${token}`);
    }
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

function parseIntFlag(flags, key, fallback) {
  if (!flags.has(key)) return fallback;
  const value = Number.parseInt(flags.get(key), 10);
  if (!Number.isFinite(value)) throw new Error(`--${key} must be an integer`);
  return Math.max(1, value);
}

function flagEnabled(flags, key) {
  if (!flags.has(key)) return false;
  const value = String(flags.get(key) || '').trim().toLowerCase();
  return !['', '0', 'false', 'no', 'off'].includes(value);
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

function helpText() {
  return `Usage:
  node tools/node_hub_shadow_compare_smoke.js

Options:
  --rust-hub-root <path>      Rust Hub root, default: parent of this tools dir
  --xhub-system-root <path>   x-hub-system root, auto-detected from ancestors
  --runner <path>             Rust Hub runner command
  --runs <n>                  Number of Node GetSchedulerStatus calls, default 1
  --interval-ms <n>           Delay between successful report writes, default 1000
  --report-limit <n>          Recent report rows to include, default runs+5
  --timeout-ms <n>            Wait for report increase, default 10000
  --poll-ms <n>               Report polling interval, default 250
  --shadow-throttle-ms <n>    Node hook throttle, default 250
  --expect-zero-mismatch      Exit 2 if newly collected reports include mismatches
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
