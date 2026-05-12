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
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'rust_provider_route_shadow_compare.js'))) {
      return candidate;
    }
  }
  return candidates[0];
}

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function writeProviderStore(runtimeBaseDir) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  fs.writeFileSync(path.join(runtimeBaseDir, 'hub_provider_keys.json'), JSON.stringify({
    schema_version: 'hub_provider_keys.v1',
    providers: {
      openai: {
        routing_strategy: 'fill-first',
        accounts: [{
          account_key: 'openai:http-shadow-compare-smoke',
          provider: 'openai',
          api_key: 'sk-http-shadow-compare-smoke-redacted',
          models: ['gpt-4o'],
          priority: 1,
        }],
      },
    },
  }, null, 2), 'utf8');
}

function sampleDecision() {
  return {
    requested_provider: 'openai',
    requested_model_id: 'gpt-4o',
    resolved_provider: 'openai',
    strategy: 'fill-first',
    selection_scope: 'openai::gpt-4o',
    selected_account_key: 'openai:http-shadow-compare-smoke',
    fallback_reason_code: '',
    available_count: 1,
    total_count: 1,
    candidates: [{
      account_key: 'openai:http-shadow-compare-smoke',
      provider: 'openai',
      provider_group: 'openai',
      state: 'ready',
      reason_code: 'selected_by_scheduler',
      selected: true,
      model_state_key: '',
    }],
    updated_at_ms: 1000,
  };
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

async function waitForReady(baseUrl, child) {
  const deadline = Date.now() + 10_000;
  let last = null;
  while (Date.now() < deadline) {
    if (child.exitCode != null) {
      const output = child.collectedOutput?.() || {};
      throw new Error(`xhubd serve exited before readiness was ready: ${child.exitCode} stdout=${safeString(output.stdout)} stderr=${safeString(output.stderr)}`);
    }
    last = await httpGetJson(`${baseUrl}/provider/readiness?min_compare_reports=1&max_mismatches=0&limit=3`);
    if (last?.ready === true) return last;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`provider readiness did not become ready: ${JSON.stringify(last || {})}`);
}

function startServer({ port, runtimeBaseDir, dbPath }) {
  const runner = path.join(ROOT_DIR, 'tools', 'run_rust_hub.command');
  const child = spawn(runner, ['serve'], {
    cwd: ROOT_DIR,
    env: {
      ...process.env,
      XHUB_RUST_HUB_ROOT: ROOT_DIR,
      XHUB_RUST_HUB_HTTP_PORT: String(port),
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
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
  const tempRoot = makeTempDir('xhub-provider-route-http-shadow-compare-smoke-');
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const dbPath = path.join(tempRoot, 'hub.sqlite3');
  const port = 53000 + (process.pid % 1000);
  const baseUrl = `http://127.0.0.1:${port}`;
  let child = null;
  try {
    writeProviderStore(runtimeBaseDir);
    child = startServer({ port, runtimeBaseDir, dbPath });
    await waitForHealth(baseUrl, child);
    await httpGetJson(`${baseUrl}/provider/readiness?min_compare_reports=0&max_mismatches=0&limit=3`);

    const srcDir = path.join(resolveXHubSystemRoot(), 'x-hub', 'grpc-server', 'hub_grpc_server', 'src');
    const { createProviderRouteShadowComparer } = await import(pathToFileURL(path.join(srcDir, 'rust_provider_route_shadow_compare.js')).href);
    const warnings = [];
    const logs = [];
    const comparer = createProviderRouteShadowComparer({
      env: {
        XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE: '1',
        XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP: '1',
        XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_BASE_URL: baseUrl,
        XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_TIMEOUT_MS: '1000',
        XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_FALLBACK_TO_CLI: '0',
        XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_THROTTLE_MS: '0',
        XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_VERBOSE: '1',
      },
      existsSync: () => false,
      logger: {
        log: (line) => logs.push(safeString(line)),
        warn: (line) => warnings.push(safeString(line)),
      },
    });
    const started = comparer.maybeCompare({
      runtimeBaseDir,
      modelId: 'gpt-4o',
      provider: 'openai',
      nodeDecision: sampleDecision(),
    });
    let readiness = null;
    let readinessError = '';
    try {
      readiness = await waitForReady(baseUrl, child);
    } catch (error) {
      readinessError = safeString(error?.message || error);
      readiness = await httpGetJson(`${baseUrl}/provider/readiness?min_compare_reports=1&max_mismatches=0&limit=3`)
        .catch((readError) => ({ ok: false, error: safeString(readError?.message || readError) }));
    }
    const ok = started === true && readiness?.ready === true && warnings.length === 0;
    fs.writeSync(1, `${JSON.stringify({
      ok,
      schema_version: 'xhub.provider_route_http_shadow_compare_smoke.v1',
      mode: 'node_shadow_compare_http_first',
      cli_fallback_enabled: false,
      started,
      readiness,
      readiness_error: readinessError,
      warnings,
      logs,
      runtime_base_dir: runtimeBaseDir,
      rust_hub_root: ROOT_DIR,
      http_base_url: baseUrl,
      db_path: dbPath,
      }, null, 2)}\n`);
    if (!ok) process.exitCode = 2;
  } finally {
    if (child) {
      if (child.exitCode == null && child.signalCode == null) {
        await new Promise((resolve) => {
          const timer = setTimeout(resolve, 1000);
          child.once('close', () => {
            clearTimeout(timer);
            resolve();
          });
          child.kill();
        });
      }
    }
    try { fs.rmSync(tempRoot, { recursive: true, force: true }); } catch {}
  }
}

try {
  await main();
} catch (error) {
  console.error(`[provider_route_http_shadow_compare_smoke] ${error?.stack || error?.message || error}`);
  process.exit(1);
}
