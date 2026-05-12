#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    timeoutMs: 30000,
    port: 52000 + (process.pid % 1000),
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 120000);
        i += 1;
        break;
      case '--port':
        out.port = parseIntInRange(next, out.port, 1024, 65535);
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
    'model_inventory_http_bridge_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
  ].join('\n');
}

function cleanupPath(target) {
  try {
    fs.rmSync(target, { recursive: true, force: true });
  } catch {
    // ignore cleanup failures
  }
}

function writeFixture(runtimeBaseDir) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const artifactPath = path.join(runtimeBaseDir, 'local.summary.gguf');
  fs.writeFileSync(artifactPath, 'fixture');
  fs.writeFileSync(path.join(runtimeBaseDir, 'hub_provider_keys.json'), JSON.stringify({
    schema_version: 'hub_provider_keys.v1',
    providers: {
      openai: {
        routing_strategy: 'priority',
        accounts: [
          {
            account_key: 'acct-model-inventory-http',
            provider: 'openai',
            api_key: 'sk-model-inventory-http-smoke',
            models: ['gpt-5.5'],
            provider_host: 'api.openai.com',
            pool_id: 'free',
          },
        ],
      },
    },
  }, null, 2));
  fs.writeFileSync(path.join(runtimeBaseDir, 'models_state.json'), JSON.stringify({
    models: [
      {
        id: 'local.summary',
        name: 'Local Summary',
        backend: 'mlx',
        modelPath: artifactPath,
        capabilities: ['text_generate'],
      },
    ],
  }, null, 2));
  fs.writeFileSync(path.join(runtimeBaseDir, 'ai_runtime_status.json'), JSON.stringify({
    providers: {
      mlx: {
        provider: 'mlx',
        ok: true,
        availableTaskKinds: ['text.generate'],
        runtimeSource: 'fixture',
        runtimeSourcePath: '/tmp/fixture-runtime',
        runtimeResolutionState: 'resolved',
        updatedAtMs: 1000,
      },
    },
  }, null, 2));
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-20).join('\n');
}

function startXhubd({ runtimeBaseDir, dbPath, port }) {
  const env = {
    ...process.env,
    XHUB_RUST_HUB_HTTP_PORT: String(port),
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_DB_PATH: dbPath,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
  };
  const packagedRunner = path.join(ROOT_DIR, 'bin', 'xhubd');
  const child = fs.existsSync(packagedRunner)
    ? spawn(packagedRunner, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] })
    : spawn('cargo', ['run', '--bin', 'xhubd', '--', 'serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });

  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });
  return { child, output };
}

function httpJson(method, url, body = undefined, timeoutMs = 1000) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
    const req = http.request(url, {
      method,
      timeout: timeoutMs,
      headers: {
        accept: 'application/json',
        ...(data ? { 'content-type': 'application/json', 'content-length': String(data.length) } : {}),
      },
    }, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { raw += chunk; });
      res.on('end', () => {
        if ((res.statusCode || 0) < 200 || (res.statusCode || 0) >= 300) {
          reject(new Error(`http_status:${res.statusCode}:${raw.slice(0, 400)}`));
          return;
        }
        try {
          resolve(JSON.parse(raw));
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${raw.slice(0, 400)}`));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('http_timeout')));
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function waitForHealth(baseUrl, child, output, timeoutMs) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (child.exitCode !== null) {
      throw new Error(`xhubd exited before health was ready: ${child.exitCode}\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
    }
    try {
      await httpJson('GET', `${baseUrl}/health`, undefined, 750);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
}

function assertNoSecret(value, label) {
  const raw = JSON.stringify(value);
  if (raw.includes('sk-model-inventory-http-smoke')) {
    throw new Error(`${label} leaked provider secret`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-model-inventory-http-'));
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const dbPath = path.join(tempRoot, 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;
  let result;

  try {
    writeFixture(runtimeBaseDir);
    const started = startXhubd({ runtimeBaseDir, dbPath, port: args.port });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);

    const inventoryUrl = `${baseUrl}/model/inventory?runtime_base_dir=${encodeURIComponent(runtimeBaseDir)}&now_ms=1000`;
    const inventory = await httpJson('GET', inventoryUrl, undefined, 2000);
    assertNoSecret(inventory, 'model inventory HTTP');
    if (inventory?.schema_version !== 'xhub.model_inventory.v1') {
      throw new Error(`unexpected inventory schema: ${JSON.stringify(inventory)}`);
    }

    const readinessBefore = await httpJson('GET', `${baseUrl}/model/readiness?min_compare_reports=0&max_mismatches=0&limit=3`, undefined, 2000);
    if (readinessBefore?.ready !== true) {
      throw new Error(`zero-threshold readiness should be ready: ${JSON.stringify(readinessBefore)}`);
    }

    const compare = await httpJson('POST', `${baseUrl}/model/compare`, {
      runtime_base_dir: runtimeBaseDir,
      now_ms: 1000,
      node_inventory: inventory,
    }, 4000);
    assertNoSecret(compare, 'model inventory compare HTTP');
    if (compare?.match !== true) {
      throw new Error(`model compare mismatch: ${JSON.stringify(compare?.mismatches || [])}`);
    }

    const reports = await httpJson('GET', `${baseUrl}/model/reports?limit=3`, undefined, 2000);
    if (Number(reports?.total || 0) < 1 || Number(reports?.mismatched || 0) !== 0) {
      throw new Error(`unexpected model reports: ${JSON.stringify(reports)}`);
    }

    const readinessAfter = await httpJson('GET', `${baseUrl}/model/readiness?min_compare_reports=1&max_mismatches=0&limit=3`, undefined, 2000);
    if (readinessAfter?.ready !== true) {
      throw new Error(`readiness after compare should be ready: ${JSON.stringify(readinessAfter)}`);
    }

    result = {
      ok: true,
      schema_version: 'xhub.model_inventory_http_bridge_smoke.v1',
      http_base_url: baseUrl,
      inventory_schema_version: inventory.schema_version,
      remote_models: inventory.remote_models?.length || 0,
      local_models: inventory.local_models?.length || 0,
      compare_match: compare.match === true,
      reports_total: reports.total,
      readiness_ready: readinessAfter.ready === true,
    };
  } finally {
    if (child) {
      if (child.exitCode === null) {
        const exited = new Promise((resolve) => child.once('exit', resolve));
        child.kill('SIGTERM');
        await Promise.race([
          exited,
          new Promise((resolve) => setTimeout(resolve, 1000)),
        ]);
      }
    }
    cleanupPath(tempRoot);
  }

  if (result) {
    console.log(JSON.stringify(result, null, 2));
  }
}

main().catch((error) => {
  console.error(`[model_inventory_http_bridge_smoke] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
