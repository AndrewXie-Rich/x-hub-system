#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function safeString(value) {
  return String(value ?? '').trim();
}

function resolveXHubSystemRoot() {
  const explicit = safeString(process.env.XHUB_SYSTEM_ROOT);
  if (explicit) return explicit;
  const candidates = [
    path.resolve(ROOT_DIR, '..', '..', 'x-hub-system'),
    path.resolve(ROOT_DIR, '..', '..', '..', '..', 'x-hub-system'),
    '.',
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'rust_scheduler_bridge.js'))) {
      return candidate;
    }
  }
  return candidates[0];
}

function httpGetJson(url) {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        if (Number(res.statusCode || 0) < 200 || Number(res.statusCode || 0) >= 300) {
          reject(new Error(`http_status:${res.statusCode}:${body.slice(0, 240)}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${body.slice(0, 240)}`));
        }
      });
    });
    req.setTimeout(500, () => req.destroy(new Error('http_timeout')));
    req.on('error', reject);
  });
}

async function waitForHealth(baseUrl, child) {
  const deadline = Date.now() + 10_000;
  let lastError = null;
  while (Date.now() < deadline) {
    if (child.exitCode != null) {
      const output = child.collectedOutput?.() || {};
      throw new Error(`xhubd serve exited before health was ready: ${child.exitCode} stdout=${safeString(output.stdout)} stderr=${safeString(output.stderr)}`);
    }
    try {
      await httpGetJson(`${baseUrl}/health`);
      return;
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health not ready: ${lastError?.message || lastError || 'timeout'}`);
}

function startServer({ port, dbPath }) {
  const runner = path.join(ROOT_DIR, 'tools', 'run_rust_hub.command');
  const child = spawn(runner, ['serve'], {
    cwd: ROOT_DIR,
    env: {
      ...process.env,
      XHUB_RUST_HUB_ROOT: ROOT_DIR,
      XHUB_RUST_HUB_HTTP_PORT: String(port),
      HUB_DB_PATH: dbPath,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += String(chunk); });
  child.stderr.on('data', (chunk) => { stderr += String(chunk); });
  child.collectedOutput = () => ({ stdout, stderr });
  return child;
}

async function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-scheduler-status-http-bridge-smoke-'));
  const dbPath = path.join(tempRoot, 'hub.sqlite3');
  const port = 54000 + (process.pid % 1000);
  const baseUrl = `http://127.0.0.1:${port}`;
  let child = null;
  try {
    child = startServer({ port, dbPath });
    await waitForHealth(baseUrl, child);

    const srcDir = path.join(resolveXHubSystemRoot(), 'x-hub', 'grpc-server', 'hub_grpc_server', 'src');
    const { createSchedulerStatusBridge } = await import(pathToFileURL(path.join(srcDir, 'rust_scheduler_bridge.js')).href);
    const warnings = [];
    const logs = [];
    const bridge = createSchedulerStatusBridge({
      env: {
        XHUB_RUST_SCHEDULER_STATUS_READ: '1',
        XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: '1',
        XHUB_RUST_SCHEDULER_STATUS_HTTP: '1',
        XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL: baseUrl,
        XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS: '1000',
        XHUB_RUST_SCHEDULER_STATUS_HTTP_FALLBACK_TO_CLI: '0',
        XHUB_RUST_SCHEDULER_STATUS_MIN_COMPARE_REPORTS: '0',
        XHUB_RUST_SCHEDULER_STATUS_MAX_MISMATCHES: '0',
        XHUB_RUST_SCHEDULER_STATUS_MIN_LEASE_SHADOW_RUNS: '0',
        XHUB_RUST_SCHEDULER_STATUS_MAX_STALE_ACTIVE: '0',
        XHUB_RUST_SCHEDULER_STATUS_MAX_ORPHANED_LEASES: '0',
        XHUB_RUST_SCHEDULER_STATUS_VERBOSE: '1',
      },
      existsSync: () => false,
      logger: {
        log: (line) => logs.push(safeString(line)),
        warn: (line) => warnings.push(safeString(line)),
      },
    });

    const out = await bridge.maybeReadStatus({
      includeQueueItems: true,
      queueItemsLimit: 5,
      fallback: {
        global_concurrency: 2,
        per_project_concurrency: 2,
        queue_limit: 100,
        queue_timeout_ms: 30000,
      },
    });
    const ok = out?.used === true
      && out?.readiness?.ready === true
      && Number(out?.paid_ai?.queue_depth || 0) === 0
      && Number(out?.paid_ai?.in_flight_total || 0) === 0
      && warnings.length === 0;

    fs.writeSync(1, `${JSON.stringify({
      ok,
      schema_version: 'xhub.scheduler_status_http_bridge_smoke.v1',
      mode: 'node_scheduler_status_http_first',
      cli_fallback_enabled: false,
      used: out?.used === true,
      readiness_ready: out?.readiness?.ready === true,
      paid_ai: out?.paid_ai || null,
      warnings,
      logs,
      rust_hub_root: ROOT_DIR,
      http_base_url: baseUrl,
      db_path: dbPath,
    }, null, 2)}\n`);
    if (!ok) process.exitCode = 2;
  } finally {
    if (child && child.exitCode == null && child.signalCode == null) {
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1000);
        child.once('close', () => {
          clearTimeout(timer);
          resolve();
        });
        child.kill();
      });
    }
    try { fs.rmSync(tempRoot, { recursive: true, force: true }); } catch {}
  }
}

try {
  await main();
} catch (error) {
  console.error(`[scheduler_status_http_bridge_smoke] ${error?.stack || error?.message || error}`);
  process.exit(1);
}
