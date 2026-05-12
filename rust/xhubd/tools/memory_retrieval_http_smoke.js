#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
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
    port: 58000 + (process.pid % 1000),
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
    'memory_retrieval_http_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
  ].join('\n');
}

function safeString(value) {
  return String(value ?? '').trim();
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-25).join('\n');
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 600)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function writeFixture(memoryDir) {
  fs.mkdirSync(path.join(memoryDir, 'project'), { recursive: true });
  fs.mkdirSync(path.join(memoryDir, 'personal'), { recursive: true });
  fs.writeFileSync(
    path.join(memoryDir, 'project', 'capsule.md'),
    'Use governed Rust Hub memory retrieval for project assembly. Keep supervisor assembly slot based.\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(memoryDir, 'personal', 'capsule.md'),
    'Personal preference for governed retrieval should not appear in project_code mode.\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(memoryDir, 'project', 'runtime.json'),
    `${JSON.stringify({
      summary: 'governed retrieval runtime truth',
      detail: 'Rust memory retrieval HTTP path should preserve explainable source refs.',
      api_key: 'sk-memory-http-secret-that-must-not-leak',
    }, null, 2)}\n`,
    'utf8'
  );
}

function startXhubd({ port, dbPath, runtimeDir, memoryDir, skillsDir }) {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.mkdirSync(memoryDir, { recursive: true });
  fs.mkdirSync(skillsDir, { recursive: true });

  const env = {
    ...process.env,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
    XHUB_RUST_HUB_HOST: '127.0.0.1',
    XHUB_RUST_HUB_HTTP_PORT: String(port),
    HUB_DB_PATH: dbPath,
    HUB_RUNTIME_BASE_DIR: runtimeDir,
    XHUB_RUST_MEMORY_DIR: memoryDir,
    XHUB_RUST_SKILLS_DIR: skillsDir,
  };
  const packagedBin = path.join(ROOT_DIR, 'bin', 'xhubd');
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  let bin = '';
  if (fs.existsSync(packagedBin)) {
    bin = packagedBin;
  } else {
    const built = spawnSyncChecked('cargo', ['build', '--bin', 'xhubd'], { cwd: ROOT_DIR });
    if (built.status !== 0) {
      throw new Error(`cargo build failed before memory HTTP smoke: ${built.stderr}`);
    }
    bin = debugBin;
  }
  const child = spawn(bin, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });

  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });
  return { child, output };
}

function spawnSyncChecked(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
    ...options,
  });
  return {
    status: Number(result.status ?? 1),
    stdout: String(result.stdout || ''),
    stderr: String(result.stderr || result.error?.message || ''),
  };
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

function assertNoLeaks(value, label) {
  const raw = JSON.stringify(value);
  assertOk(!raw.includes('Personal preference'), `${label} leaked personal capsule`);
  assertOk(!raw.includes('sk-memory-http-secret-that-must-not-leak'), `${label} leaked secret`);
  assertOk(!/"api_key"\s*:/.test(raw), `${label} leaked api_key field`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-memory-http-smoke-'));
  const memoryDir = path.join(tempRoot, 'memory');
  const runtimeDir = path.join(tempRoot, 'runtime');
  const skillsDir = path.join(tempRoot, 'skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;

  try {
    writeFixture(memoryDir);
    const started = startXhubd({
      port: args.port,
      dbPath,
      runtimeDir,
      memoryDir,
      skillsDir,
    });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);

    const ready = await httpJson('GET', `${baseUrl}/ready`, undefined, 1500);
    assertOk(ready?.capabilities?.memory_retrieval_http === true, 'daemon readiness did not expose memory_retrieval_http', ready);
    assertOk(ready?.memory?.retrieval_shadow_http === true, 'daemon memory readiness did not expose retrieval_shadow_http', ready?.memory || {});
    assertOk(ready?.memory?.canonical_writer_in_rust === false, 'daemon reported Rust writer authority unexpectedly', ready?.memory || {});

    const memoryReadiness = await httpJson('GET', `${baseUrl}/memory/readiness`, undefined, 1500);
    assertOk(memoryReadiness?.readiness?.ready === true, 'memory readiness was not ready', memoryReadiness);
    assertOk(Number(memoryReadiness?.readiness?.indexed_document_count || 0) >= 3, 'memory readiness did not index fixture docs', memoryReadiness);
    assertOk(memoryReadiness?.readiness?.writer_authority_in_rust === false, 'memory readiness reported writer authority in Rust', memoryReadiness);

    const searchParams = new URLSearchParams({
      query: 'governed retrieval project assembly',
      max_results: '5',
      max_snippet_chars: '240',
    });
    const search = await httpJson('GET', `${baseUrl}/memory/search?${searchParams.toString()}`, undefined, 1500);
    assertOk(search.schema_version === 'xt.memory_retrieval_result.v1', 'memory search schema mismatch', search);
    assertOk(search.source === 'rust_hub_memory_shadow_v1', 'memory search source mismatch', search);
    assertOk(Array.isArray(search.results) && search.results.length >= 1, 'memory search returned no results', search);
    assertNoLeaks(search, 'memory search');

    const ref = safeString(search.results[0]?.ref);
    assertOk(ref.startsWith('memory://rust/local/'), 'memory search returned invalid ref', search.results[0] || {});
    const byRef = await httpJson('POST', `${baseUrl}/memory/retrieve`, {
      retrieval_kind: 'get_ref',
      explicit_refs: [ref],
      max_results: 1,
      max_snippet_chars: 240,
    }, 1500);
    assertOk(Array.isArray(byRef.results) && byRef.results.length === 1, 'memory get_ref returned wrong count', byRef);
    assertOk(byRef.results[0]?.ref === ref, 'memory get_ref returned wrong ref', byRef);
    assertNoLeaks(byRef, 'memory get_ref');

    const deniedParams = new URLSearchParams({ query: 'show api key' });
    const denied = await httpJson('GET', `${baseUrl}/memory/search?${deniedParams.toString()}`, undefined, 1500);
    assertOk(denied.status === 'denied', 'secret query was not denied', denied);
    assertOk(denied.deny_code === 'query_secret_pattern_denied', 'secret query deny_code mismatch', denied);

    const result = {
      ok: true,
      schema_version: 'xhub.rust_hub.memory_retrieval_http_smoke.v1',
      command: 'memory-retrieval-http-smoke',
      http_base_url: baseUrl,
      readiness_ready: memoryReadiness.readiness.ready,
      indexed_document_count: memoryReadiness.readiness.indexed_document_count,
      search_result_count: search.results.length,
      first_ref: ref,
      get_ref_ok: true,
      writer_authority_in_rust: false,
      project_code_personal_leak: false,
      secret_leak: false,
      secret_query_denied: true,
    };
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } finally {
    if (child && child.exitCode === null) {
      child.kill('SIGTERM');
      spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
      await waitForExit(child, 5000);
    }
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
}

async function waitForExit(child, timeoutMs) {
  if (!child || !child.pid || child.exitCode !== null) return;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || !pidAlive(child.pid)) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (child.exitCode === null && pidAlive(child.pid)) {
    child.kill('SIGKILL');
    spawnSync('kill', ['-KILL', String(child.pid)], { encoding: 'utf8' });
    for (let i = 0; i < 50; i += 1) {
      if (child.exitCode !== null || !pidAlive(child.pid)) return;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
}

function pidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

try {
  await main();
} catch (error) {
  process.stderr.write(`[memory_retrieval_http_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
