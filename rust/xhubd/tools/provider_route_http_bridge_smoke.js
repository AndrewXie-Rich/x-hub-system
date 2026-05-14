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
    '/Users/andrew.xie/Documents/AX/x-hub-system',
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'rust_provider_route_authority_bridge.js'))) {
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
          account_key: 'openai:http-bridge-smoke',
          provider: 'openai',
          api_key: 'sk-http-bridge-smoke-redacted',
          models: ['gpt-4o'],
          priority: 1,
        }],
      },
    },
  }, null, 2), 'utf8');
}

function httpGet(url) {
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
        resolve(body);
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
      throw new Error(`xhubd serve exited before health was ready: ${child.exitCode}`);
    }
    try {
      await httpGet(`${baseUrl}/health`);
      return;
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health not ready: ${lastError?.message || lastError || 'timeout'}`);
}

function startServer({ port, runtimeBaseDir }) {
  const runner = path.join(ROOT_DIR, 'tools', 'run_rust_hub.command');
  const child = spawn(runner, ['serve'], {
    cwd: ROOT_DIR,
    env: {
      ...process.env,
      XHUB_RUST_HUB_ROOT: ROOT_DIR,
      XHUB_RUST_HUB_HTTP_PORT: String(port),
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
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
  const tempRoot = makeTempDir('xhub-provider-route-http-bridge-smoke-');
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const port = 52000 + (process.pid % 1000);
  const baseUrl = `http://127.0.0.1:${port}`;
  let child = null;
  try {
    writeProviderStore(runtimeBaseDir);
    child = startServer({ port, runtimeBaseDir });
    await waitForHealth(baseUrl, child);

    const srcDir = path.join(resolveXHubSystemRoot(), 'x-hub', 'grpc-server', 'hub_grpc_server', 'src');
    const { createProviderRouteAuthorityBridge } = await import(pathToFileURL(path.join(srcDir, 'rust_provider_route_authority_bridge.js')).href);
    const warnings = [];
    const bridge = createProviderRouteAuthorityBridge({
      env: {
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: '1',
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '1',
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL: baseUrl,
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS: '1000',
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '0',
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS: '0',
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES: '0',
        XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS: '0',
      },
      existsSync: () => false,
      logger: { warn: (line) => warnings.push(safeString(line)) },
    });
    const out = await bridge.candidateRoute({
      runtimeBaseDir,
      modelId: 'gpt-4o',
      provider: 'openai',
      nodeAccountKey: 'openai:http-bridge-smoke',
    });
    const ok = out?.used === true
      && out?.fallback !== true
      && out?.selected === true
      && out?.selectedAccountKey === 'openai:http-bridge-smoke'
      && warnings.length === 0;
    console.log(JSON.stringify({
      ok,
      schema_version: 'xhub.provider_route_http_bridge_smoke.v1',
      mode: 'node_bridge_http_first',
      cli_fallback_enabled: false,
      selected_account_key: safeString(out?.selectedAccountKey),
      error_code: safeString(out?.error_code),
      warnings,
      runtime_base_dir: runtimeBaseDir,
      rust_hub_root: ROOT_DIR,
      http_base_url: baseUrl,
    }, null, 2));
    if (!ok) process.exitCode = 2;
  } finally {
    if (child) {
      child.kill();
      await new Promise((resolve) => child.once('close', resolve));
    }
    try { fs.rmSync(tempRoot, { recursive: true, force: true }); } catch {}
  }
}

main().catch((error) => {
  console.error(`[provider_route_http_bridge_smoke] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
