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
    port: 52400 + (process.pid % 1000),
    tokenPort: 53400 + (process.pid % 1000),
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
      case '--token-port':
        out.tokenPort = parseIntInRange(next, out.tokenPort, 1024, 65535);
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
    'provider_codex_oauth_refresh_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
    '  --token-port <port>  Local mock token endpoint port',
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
  fs.writeFileSync(path.join(runtimeBaseDir, 'hub_provider_keys.json'), JSON.stringify({
    schema_version: 'hub_provider_keys.v1',
    providers: {
      openai: {
        routing_strategy: 'priority',
        accounts: [
          {
            account_key: 'codex:oauth-smoke',
            provider: 'openai',
            api_key: 'old-access-smoke-secret',
            refresh_token: 'old-refresh-smoke-secret',
            auth_type: 'oauth',
            oauth_source_key: 'chatgpt',
            expires_at_ms: 1,
            models: ['gpt-5.4'],
            provider_host: 'api.openai.com',
            pool_id: 'free',
          },
        ],
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

function startTokenServer(port) {
  let requestCount = 0;
  const server = http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/oauth/token') {
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'not_found' }));
      return;
    }
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      requestCount += 1;
      if (!body.includes('grant_type=refresh_token') || !body.includes('refresh_token=old-refresh-smoke-secret')) {
        res.writeHead(400, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'invalid_request' }));
        return;
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({
        access_token: 'new-access-smoke-secret',
        refresh_token: 'new-refresh-smoke-secret',
        expires_in: 3600,
      }));
    });
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => {
      server.off('error', reject);
      resolve({
        url: `http://127.0.0.1:${port}/oauth/token`,
        close: () => new Promise((done) => server.close(done)),
        requestCount: () => requestCount,
      });
    });
  });
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
  for (const secret of [
    'old-access-smoke-secret',
    'old-refresh-smoke-secret',
    'new-access-smoke-secret',
    'new-refresh-smoke-secret',
  ]) {
    if (raw.includes(secret)) {
      throw new Error(`${label} leaked provider secret`);
    }
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-codex-oauth-refresh-smoke-'));
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const dbPath = path.join(tempRoot, 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;
  let tokenServer;
  let result;

  try {
    writeFixture(runtimeBaseDir);
    tokenServer = await startTokenServer(args.tokenPort);
    const started = startXhubd({ runtimeBaseDir, dbPath, port: args.port });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);

    const ready = await httpJson('GET', `${baseUrl}/ready`, undefined, 2000);
    if (ready?.capabilities?.provider_oauth_refresh_codex_plan_http !== true) {
      throw new Error(`missing codex oauth plan capability: ${JSON.stringify(ready?.capabilities || {})}`);
    }

    const planBefore = await httpJson('POST', `${baseUrl}/provider/oauth-refresh/codex/plan`, {
      runtime_base_dir: runtimeBaseDir,
      now_ms: 1000,
      include_skipped: true,
    }, 2000);
    assertNoSecret(planBefore, 'codex oauth plan before');
    if (planBefore?.result?.due_accounts !== 1 || planBefore?.result?.accounts?.[0]?.reason_code !== 'token_expired') {
      throw new Error(`unexpected plan before refresh: ${JSON.stringify(planBefore)}`);
    }

    const refreshed = await httpJson('POST', `${baseUrl}/provider/oauth-refresh/codex`, {
      runtime_base_dir: runtimeBaseDir,
      account_key: 'codex:oauth-smoke',
      refreshed_at_ms: 1000,
      token_url: tokenServer.url,
      timeout_ms: 5000,
      base_failure_backoff_ms: 100,
      max_failure_backoff_ms: 1000,
    }, 7000);
    assertNoSecret(refreshed, 'codex oauth refresh');
    if (refreshed?.ok !== true || refreshed?.refreshed !== true || refreshed?.result?.ok !== true) {
      throw new Error(`unexpected refresh response: ${JSON.stringify(refreshed)}`);
    }

    const planAfter = await httpJson('POST', `${baseUrl}/provider/oauth-refresh/codex/plan`, {
      runtime_base_dir: runtimeBaseDir,
      now_ms: 1000,
      include_skipped: true,
    }, 2000);
    assertNoSecret(planAfter, 'codex oauth plan after');
    if (planAfter?.result?.due_accounts !== 0) {
      throw new Error(`refresh plan should be empty after fresh token: ${JSON.stringify(planAfter)}`);
    }

    const store = JSON.parse(fs.readFileSync(path.join(runtimeBaseDir, 'hub_provider_keys.json'), 'utf8'));
    const account = store.providers.openai.accounts[0];
    if (account.api_key !== 'new-access-smoke-secret' || account.refresh_token !== 'new-refresh-smoke-secret') {
      throw new Error('provider store did not receive refreshed token material');
    }

    result = {
      ok: true,
      schema_version: 'xhub.provider_codex_oauth_refresh_smoke.v1',
      http_base_url: baseUrl,
      plan_endpoint: '/provider/oauth-refresh/codex/plan',
      refresh_endpoint: '/provider/oauth-refresh/codex',
      due_before: planBefore.result.due_accounts,
      due_after: planAfter.result.due_accounts,
      refreshed: refreshed.refreshed === true,
      token_endpoint_requests: tokenServer.requestCount(),
      capability_ready: true,
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
    if (tokenServer) {
      await tokenServer.close();
    }
    cleanupPath(tempRoot);
  }

  if (result) {
    console.log(JSON.stringify(result, null, 2));
  }
}

main().catch((error) => {
  console.error(`[provider_codex_oauth_refresh_smoke] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
