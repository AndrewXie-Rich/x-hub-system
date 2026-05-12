#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function safeString(value) {
  return String(value ?? '').trim();
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    modelId: 'gpt-4o',
    provider: 'openai',
    timeoutMs: 30000,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--model-id':
        out.modelId = safeString(next);
        i += 1;
        break;
      case '--provider':
        out.provider = safeString(next);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 120000);
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
  return out;
}

function usage() {
  return [
    'provider_route_shadow_compare_smoke.js',
    '',
    'Options:',
    '  --model-id <id>      Model ID to route, default gpt-4o',
    '  --provider <id>      Provider override, default openai',
    '  --timeout-ms <ms>    Wait timeout, default 30000',
  ].join('\n');
}

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  };
  for (const [key, value] of Object.entries(tempEnv)) {
    previous.set(key, process.env[key]);
    if (value == null) delete process.env[key];
    else process.env[key] = String(value);
  }
  try {
    const result = fn();
    if (result && typeof result.then === 'function') {
      return result.finally(restore);
    }
    restore();
    return result;
  } catch (error) {
    restore();
    throw error;
  }
}

function makeTransportCall(request = {}, token = '') {
  return {
    request,
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() !== 'authorization') return [];
        return token ? [`Bearer ${token}`] : [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:54321';
    },
  };
}

async function invokeUnary(method, call) {
  return await new Promise((resolve) => {
    method(call, (err, res) => resolve({ err, res }));
  });
}

async function waitFor(predicate, {
  timeoutMs = 30000,
  intervalMs = 50,
} = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await predicate();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return null;
}

function cleanupPath(target) {
  try {
    fs.rmSync(target, { recursive: true, force: true });
  } catch {
    // ignore
  }
}

async function importFromSource(srcDir, fileName) {
  return await import(pathToFileURL(path.join(srcDir, fileName)).href);
}

function parseJsonLine(stdout) {
  const line = String(stdout || '')
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean)
    .reverse()
    .find((item) => item.startsWith('{'));
  if (!line) throw new Error('missing JSON output');
  return JSON.parse(line);
}

function resolveXHubSystemRoot() {
  const explicit = safeString(process.env.XHUB_SYSTEM_ROOT);
  if (explicit) return explicit;
  const candidates = [
    path.resolve(ROOT_DIR, '..', '..', 'x-hub-system'),
    path.resolve(ROOT_DIR, '..', '..', '..', '..', 'x-hub-system'),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src', 'services.js'))) {
      return candidate;
    }
  }
  return candidates[0];
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const sourceRoot = resolveXHubSystemRoot();
  const srcDir = path.join(sourceRoot, 'x-hub', 'grpc-server', 'hub_grpc_server', 'src');
  if (!fs.existsSync(path.join(srcDir, 'services.js'))) {
    throw new Error(`Node Hub source not found: ${srcDir}`);
  }

  const [
    { HubDB },
    { HubEventBus },
    { makeServices },
    { addProviderKey, invalidateProviderKeyCache },
    { createProviderRouteShadowComparer },
  ] = await Promise.all([
    importFromSource(srcDir, 'db.js'),
    importFromSource(srcDir, 'event_bus.js'),
    importFromSource(srcDir, 'services.js'),
    importFromSource(srcDir, 'provider_key_store.js'),
    importFromSource(srcDir, 'rust_provider_route_shadow_compare.js'),
  ]);

  const runtimeBaseDir = makeTempDir('xhub-provider-route-shadow-smoke-runtime-');
  const dbDir = makeTempDir('xhub-provider-route-shadow-smoke-db-');
  const dbPath = path.join(dbDir, 'hub.sqlite3');
  const rustDbPath = path.join(dbDir, 'rust_hub.sqlite3');
  const logs = [];
  const warnings = [];

  invalidateProviderKeyCache();

  try {
    await withEnv({
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_CLIENT_TOKEN: 'client-secret',
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE: '1',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_VERBOSE: '1',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_THROTTLE_MS: '0',
      XHUB_RUST_HUB_ROOT: ROOT_DIR,
      HUB_DB_PATH: rustDbPath,
    }, async () => {
      const db = new HubDB({ dbPath });
      try {
        const addResult = addProviderKey(runtimeBaseDir, {
          provider: args.provider,
          api_key: 'sk-provider-route-shadow-smoke',
          auth_type: 'api_key',
          models: [args.modelId],
          priority: 7,
        });
        if (!addResult.ok) {
          throw new Error(`addProviderKey failed: ${addResult.error || 'unknown_error'}`);
        }

        const comparer = createProviderRouteShadowComparer({
          logger: {
            log: (line) => logs.push(String(line || '')),
            warn: (line) => warnings.push(String(line || '')),
          },
        });
        const impl = makeServices({
          db,
          bus: new HubEventBus(),
          providerRouteShadowComparer: comparer,
        });

        const response = await invokeUnary(
          impl.HubProviderKeys.GetProviderKeyRouteDecision,
          makeTransportCall({
            model_id: args.modelId,
            provider: args.provider,
          }, 'client-secret')
        );
        if (response.err) {
          throw response.err;
        }
        const selectedAccountKey = safeString(response.res?.decision?.selected_account_key);
        if (selectedAccountKey !== addResult.account_key) {
          throw new Error(`unexpected selected account: ${selectedAccountKey}`);
        }

        const matched = await waitFor(
          () => logs.find((line) => line.includes('rust provider route shadow match')),
          { timeoutMs: args.timeoutMs }
        );
        if (!matched) {
          throw new Error(`provider route shadow compare did not report match; warnings=${warnings.join(' | ')}`);
        }
        if (warnings.length > 0) {
          throw new Error(`provider route shadow warnings: ${warnings.join(' | ')}`);
        }

        const runnerPath = path.join(ROOT_DIR, 'tools', 'run_rust_hub.command');
        const runnerEnv = {
          ...process.env,
          HUB_DB_PATH: rustDbPath,
          XHUB_RUST_HUB_ROOT: ROOT_DIR,
        };
        const reports = parseJsonLine(execFileSync(
          runnerPath,
          ['provider', 'reports', '--limit', '5'],
          { encoding: 'utf8', env: runnerEnv, timeout: args.timeoutMs }
        ));
        if (Number(reports?.total || 0) < 1 || Number(reports?.mismatched || 0) !== 0) {
          throw new Error(`unexpected provider reports summary: ${JSON.stringify(reports)}`);
        }
        const readiness = parseJsonLine(execFileSync(
          runnerPath,
          ['provider', 'readiness', '--min-compare-reports', '1', '--max-mismatches', '0'],
          { encoding: 'utf8', env: runnerEnv, timeout: args.timeoutMs }
        ));
        if (readiness?.ready !== true) {
          throw new Error(`provider readiness not ready: ${JSON.stringify(readiness)}`);
        }

        console.log(JSON.stringify({
          ok: true,
          schema_version: 'xhub.provider_route_shadow_compare_smoke.v1',
          model_id: args.modelId,
          provider: args.provider,
          selected_account_key: selectedAccountKey,
          shadow_match: true,
          reports_total: reports.total,
          readiness_ready: readiness.ready,
          runtime_base_dir: runtimeBaseDir,
          rust_db_path: rustDbPath,
        }, null, 2));
      } finally {
        db.close();
      }
    });
  } finally {
    cleanupPath(runtimeBaseDir);
    cleanupPath(dbDir);
  }
}

main().catch((error) => {
  console.error(`[provider_route_shadow_compare_smoke] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
