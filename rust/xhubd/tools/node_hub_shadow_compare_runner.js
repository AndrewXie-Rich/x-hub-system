#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');

async function main(argv) {
  const flags = parseFlags(argv);
  if (flags.has('help') || flags.has('h')) {
    process.stdout.write(helpText());
    return 0;
  }
  if (flags.has('self-test')) {
    runSelfTest();
    process.stdout.write('node_hub_shadow_compare_runner self-test ok\n');
    return 0;
  }

  const config = resolveConfig(flags);
  if (flags.has('dry-run')) {
    process.stdout.write(JSON.stringify({
      schema_version: 'xhub.node_hub_shadow_compare_runner.dry_run.v1',
      ok: true,
      config: publicConfig(config),
    }, null, 2) + '\n');
    return 0;
  }

  let child = null;
  let childExit = null;
  let stopRequested = false;
  const stop = () => {
    stopRequested = true;
    if (child && !child.killed) {
      try {
        child.kill('SIGTERM');
      } catch {
        // ignore
      }
    }
  };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);

  const before = readReports(config.runner, config.reportLimit);
  try {
    if (!config.noStart) {
      child = startNodeHub(config, (status) => {
        childExit = status;
      });
    }

    const startedAtMs = Date.now();
    let latest = before;
    emitEvent('start', {
      node_hub_started: !!child,
      node_pid: child?.pid || 0,
      reports_before: before,
      config: publicConfig(config),
    });

    for (;;) {
      if (stopRequested) break;
      latest = readReports(config.runner, config.reportLimit);
      emitEvent('reports', {
        elapsed_ms: Date.now() - startedAtMs,
        reports: latest,
        reports_added: diffReports(before, latest),
      });

      if (childExit) break;
      if (config.durationMs > 0 && Date.now() - startedAtMs >= config.durationMs) break;
      await sleep(config.reportIntervalMs);
    }

    const finalReports = readReports(config.runner, config.reportLimit);
    const added = diffReports(before, finalReports);
    const evaluation = evaluateStop(config, added, childExit, stopRequested);
    emitEvent('stop', {
      ok: evaluation.ok,
      mismatch_ok: evaluation.mismatchOk,
      node_hub_ok: evaluation.nodeHubOk,
      elapsed_ms: Date.now() - startedAtMs,
      reports_before: before,
      reports_after: finalReports,
      reports_added: added,
      node_hub_exit: childExit,
    });
    return evaluation.exitCode;
  } finally {
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
    if (child && !child.killed) {
      try {
        child.kill('SIGTERM');
      } catch {
        // ignore
      }
    }
  }
}

function startNodeHub(config, onExit = () => {}) {
  const serverPath = path.join(config.nodeHubDir, 'src', 'server.js');
  if (!fs.existsSync(serverPath)) {
    throw new Error(`Node Hub server not found: ${serverPath}`);
  }
  const child = spawn(config.nodeBin, ['src/server.js'], {
    cwd: config.nodeHubDir,
    env: config.nodeEnv,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  pipePrefixed(child.stdout, 'node_hub_stdout');
  pipePrefixed(child.stderr, 'node_hub_stderr');
  child.on('exit', (code, signal) => {
    const status = {
      code: code == null ? null : code,
      signal: signal || '',
    };
    onExit(status);
    emitEvent('node_hub_exit', status);
  });
  child.on('error', (error) => {
    onExit({
      code: null,
      signal: '',
      error: error.message,
    });
    emitEvent('node_hub_error', {
      message: error.message,
    });
  });
  return child;
}

function pipePrefixed(stream, event) {
  let buffer = '';
  stream?.on?.('data', (chunk) => {
    buffer += String(chunk || '');
    for (;;) {
      const index = buffer.indexOf('\n');
      if (index < 0) break;
      const line = buffer.slice(0, index).trimEnd();
      buffer = buffer.slice(index + 1);
      if (line) emitEvent(event, { line });
    }
  });
}

function resolveConfig(flags) {
  const rustHubRoot = path.resolve(flags.get('rust-hub-root') || path.join(__dirname, '..'));
  const xhubSystemRoot = path.resolve(flags.get('xhub-system-root') || findXHubSystemRoot(rustHubRoot));
  const nodeHubDir = path.resolve(
    flags.get('node-hub-dir')
      || path.join(xhubSystemRoot, 'x-hub', 'grpc-server', 'hub_grpc_server')
  );
  const runner = path.resolve(flags.get('runner') || path.join(rustHubRoot, 'tools', 'run_rust_hub.command'));
  const nodeBin = path.resolve(flags.get('node-bin') || process.execPath);
  const noStart = flagEnabled(flags, 'no-start');
  const durationMs = parseIntFlag(flags, 'duration-ms', 0, 0);
  const reportIntervalMs = parseIntFlag(flags, 'report-interval-ms', 5000, 1);
  const reportLimit = parseIntFlag(flags, 'report-limit', 20, 1);
  const expectZeroMismatch = flagEnabled(flags, 'expect-zero-mismatch');

  const nodeEnv = {
    ...process.env,
    XHUB_RUST_SCHEDULER_SHADOW_COMPARE: '1',
    XHUB_RUST_HUB_ROOT: rustHubRoot,
    XHUB_RUST_HUB_RUNNER: runner,
    XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS: String(
      parseIntFlag(flags, 'shadow-throttle-ms', 5000, 1)
    ),
    XHUB_RUST_SCHEDULER_SHADOW_COMPARE_TIMEOUT_MS: String(
      parseIntFlag(flags, 'shadow-timeout-ms', 5000, 1)
    ),
    HUB_HOST: flags.get('hub-host') || process.env.HUB_HOST || '127.0.0.1',
    HUB_PORT: flags.get('hub-port') || process.env.HUB_PORT || '50051',
    HUB_PAIRING_ENABLE: flags.get('pairing-enable') || process.env.HUB_PAIRING_ENABLE || '0',
  };

  if (flags.has('hub-db-path')) nodeEnv.HUB_DB_PATH = path.resolve(flags.get('hub-db-path'));
  if (flags.has('runtime-base-dir')) nodeEnv.HUB_RUNTIME_BASE_DIR = path.resolve(flags.get('runtime-base-dir'));

  return {
    rustHubRoot,
    xhubSystemRoot,
    nodeHubDir,
    runner,
    nodeBin,
    noStart,
    durationMs,
    reportIntervalMs,
    reportLimit,
    expectZeroMismatch,
    nodeEnv,
  };
}

function publicConfig(config) {
  return {
    rust_hub_root: config.rustHubRoot,
    xhub_system_root: config.xhubSystemRoot,
    node_hub_dir: config.nodeHubDir,
    runner: config.runner,
    node_bin: config.nodeBin,
    no_start: config.noStart,
    duration_ms: config.durationMs,
    report_interval_ms: config.reportIntervalMs,
    report_limit: config.reportLimit,
    expect_zero_mismatch: config.expectZeroMismatch,
    hub_host: config.nodeEnv.HUB_HOST,
    hub_port: config.nodeEnv.HUB_PORT,
    hub_db_path: config.nodeEnv.HUB_DB_PATH || '',
    runtime_base_dir: config.nodeEnv.HUB_RUNTIME_BASE_DIR || '',
    pairing_enable: config.nodeEnv.HUB_PAIRING_ENABLE,
    shadow_throttle_ms: config.nodeEnv.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS,
    shadow_timeout_ms: config.nodeEnv.XHUB_RUST_SCHEDULER_SHADOW_COMPARE_TIMEOUT_MS,
  };
}

function evaluateStop(config, added, childExit, stopRequested = false) {
  const mismatchOk = !config.expectZeroMismatch || safeInt(added?.mismatched) === 0;
  const nodeHubOk = config.noStart || stopRequested || childExit == null;
  return {
    ok: mismatchOk && nodeHubOk,
    mismatchOk,
    nodeHubOk,
    exitCode: nodeHubOk ? (mismatchOk ? 0 : 2) : 3,
  };
}

function readReports(runner, limit = 20) {
  const stdout = execFileSync(runner, ['scheduler', 'reports', '--limit', String(limit)], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return JSON.parse(stdout);
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
    schema_version: 'xhub.node_hub_shadow_compare_runner.v1',
    event,
    at_ms: Date.now(),
    ...payload,
  }) + '\n');
}

function findXHubSystemRoot(startDir) {
  let current = path.resolve(startDir);
  for (;;) {
    const candidate = path.join(current, 'x-hub-system');
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'server.js'))) {
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
    '--no-start',
    '--duration-ms',
    '1000',
    '--report-interval-ms=250',
    '--expect-zero-mismatch',
  ]);
  assert.equal(flagEnabled(flags, 'no-start'), true);
  assert.equal(parseIntFlag(flags, 'duration-ms', 0, 0), 1000);
  assert.equal(parseIntFlag(flags, 'report-interval-ms', 5000), 250);
  assert.equal(flagEnabled(flags, 'expect-zero-mismatch'), true);
  assert.deepEqual(diffReports(
    { total: 10, matched: 8, mismatched: 2 },
    { total: 13, matched: 11, mismatched: 2 }
  ), { total: 3, matched: 3, mismatched: 0 });
  assert.equal(evaluateStop(
    { noStart: false, expectZeroMismatch: true },
    { mismatched: 0 },
    { code: 1, signal: '' },
    false
  ).exitCode, 3);
  assert.equal(evaluateStop(
    { noStart: false, expectZeroMismatch: true },
    { mismatched: 1 },
    null,
    false
  ).exitCode, 2);
}

function helpText() {
  return `Usage:
  node tools/node_hub_shadow_compare_runner.js [options]

Modes:
  default       Start Node Hub with Rust scheduler shadow compare enabled
  --no-start   Do not start Node Hub; only print existing Rust reports

Options:
  --rust-hub-root <path>       Rust Hub root, default: parent of this tools dir
  --xhub-system-root <path>    x-hub-system root, auto-detected from ancestors
  --node-hub-dir <path>        Existing Node Hub grpc-server dir
  --runner <path>              Rust Hub runner command
  --node-bin <path>            Node binary, default current process.execPath
  --duration-ms <n>            Stop after duration, default 0 means until Ctrl-C
  --report-interval-ms <n>     Print report summary interval, default 5000
  --report-limit <n>           Recent report rows to include, default 20
  --expect-zero-mismatch       Exit 2 if newly collected reports include mismatch
  --hub-host <host>            Node Hub HUB_HOST, default 127.0.0.1
  --hub-port <port>            Node Hub HUB_PORT, default 50051
  --hub-db-path <path>         Node Hub DB path
  --runtime-base-dir <path>    Node Hub runtime base dir
  --pairing-enable <0|1>       HUB_PAIRING_ENABLE, default 0 for runner safety
  --shadow-throttle-ms <n>     Compare throttle, default 5000
  --shadow-timeout-ms <n>      Compare process timeout, default 5000
  --dry-run                    Print resolved config without starting
  --self-test                  Run local parser/config tests
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
