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
    port: 60100 + (process.pid % 1000),
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
    'memory_skills_production_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
  ].join('\n');
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 600)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-25).join('\n');
}

function assertNoLeak(value, label) {
  const raw = JSON.stringify(value);
  assertOk(!raw.includes('sk-memory-skills-prod-secret'), `${label} leaked secret value`);
  assertOk(!/"detail_json"\s*:/.test(raw), `${label} leaked detail_json field`);
  assertOk(!/"api_key"\s*:/.test(raw), `${label} leaked api_key field`);
}

function writeSkill(skillsDir) {
  const skill = path.join(skillsDir, 'health');
  fs.mkdirSync(skill, { recursive: true });
  fs.writeFileSync(
    path.join(skill, 'skill.json'),
    `${JSON.stringify({
      id: 'health',
      name: 'Health',
      capabilities: ['health'],
      execution: { kind: 'builtin', name: 'healthcheck' },
    }, null, 2)}\n`,
    'utf8'
  );
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
    XHUB_RUST_MEMORY_WRITER_AUTHORITY: '1',
    XHUB_RUST_MEMORY_WRITE_AUTHORITY: '1',
    XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY: '1',
    XHUB_RUST_SKILLS_EXECUTION_AUTHORITY: '1',
    XHUB_RUST_SKILLS_PRODUCTION_EXECUTION: '1',
    XHUB_RUST_SKILLS_EXECUTION_PRODUCTION: '1',
    XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY: '1',
  };
  const packagedBin = path.join(ROOT_DIR, 'bin', 'xhubd');
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  let bin = '';
  if (fs.existsSync(packagedBin)) {
    bin = packagedBin;
  } else {
    const built = spawnSyncChecked('cargo', ['build', '--bin', 'xhubd'], { cwd: ROOT_DIR });
    if (built.status !== 0) throw new Error(`cargo build failed: ${built.stderr}`);
    bin = debugBin;
  }
  const child = spawn(bin, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });
  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });
  return { child, output };
}

function httpJson(method, url, body = undefined, timeoutMs = 1000, allowedStatuses = [200]) {
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
        if (!allowedStatuses.includes(Number(res.statusCode || 0))) {
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

async function stopChild(child) {
  if (!child || !child.pid || child.exitCode !== null) return;
  child.kill('SIGTERM');
  spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
  for (let i = 0; i < 50; i += 1) {
    if (child.exitCode !== null) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (child.exitCode === null) {
    child.kill('SIGKILL');
    spawnSync('kill', ['-KILL', String(child.pid)], { encoding: 'utf8' });
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-memory-skills-prod-'));
  const runtimeDir = path.join(tempRoot, 'runtime');
  const memoryDir = path.join(tempRoot, 'memory');
  const skillsDir = path.join(tempRoot, 'skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;

  try {
    writeSkill(skillsDir);
    const started = startXhubd({ port: args.port, dbPath, runtimeDir, memoryDir, skillsDir });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);

    const ready = await httpJson('GET', `${baseUrl}/ready`, undefined, 1500);
    assertOk(ready?.memory?.canonical_writer_in_rust === true, 'memory writer authority not enabled', ready?.memory || {});
    assertOk(ready?.skills?.execution_authority_in_rust === true, 'skills execution authority not enabled', ready?.skills || {});
    assertOk(ready?.capabilities?.memory_write_http === true, 'memory write HTTP missing', ready?.capabilities || {});
    assertOk(ready?.capabilities?.skills_execute_http === true, 'skills execute HTTP missing', ready?.capabilities || {});

    const written = await httpJson('POST', `${baseUrl}/memory/write`, {
      request_id: 'memory-skills-prod-smoke',
      scope: 'project:memory-skills-prod',
      title: 'Rust memory production writer',
      text: 'Rust production memory writer stores governed memory for smooth long running Hub operation.',
      tags: ['memory.write', 'production'],
      actor: 'memory-skills-prod-smoke',
    }, 1500);
    assertOk(written?.ok === true && written?.writer_authority_in_rust === true, 'memory write failed', written);
    assertNoLeak(written, 'memory write');

    const secretDenied = await httpJson('POST', `${baseUrl}/memory/write`, {
      text: 'do not store sk-memory-skills-prod-secret',
    }, 1500, [403]);
    assertOk(secretDenied?.deny_code === 'memory_secret_pattern_denied', 'secret memory write was not denied', secretDenied);
    assertNoLeak(secretDenied, 'memory secret denied');

    const search = await httpJson('GET', `${baseUrl}/memory/search?${new URLSearchParams({
      query: 'production memory writer smooth operation',
      max_results: '3',
    }).toString()}`, undefined, 1500);
    assertOk(Array.isArray(search?.results) && search.results.length >= 1, 'written memory was not retrievable', search);
    assertNoLeak(search, 'memory search');

    await httpJson('POST', `${baseUrl}/skills/pin`, {
      scope_key: 'project:memory-skills-prod',
      skill_id: 'health',
      actor: 'memory-skills-prod-smoke',
    }, 1500);
    await httpJson('POST', `${baseUrl}/skills/grant`, {
      scope_key: 'project:memory-skills-prod',
      skill_id: 'health',
      capability: 'health',
      actor: 'memory-skills-prod-smoke',
    }, 1500);
    const executed = await httpJson('POST', `${baseUrl}/skills/execute`, {
      scope_key: 'project:memory-skills-prod',
      skill_id: 'health',
      requested_capabilities: ['health'],
      request_id: 'skills-execute-prod-smoke',
      audit_ref: 'memory-skills-prod-smoke',
      actor: 'memory-skills-prod-smoke',
      input: { ping: true },
    }, 1500);
    assertOk(executed?.ok === true && executed?.status === 'executed', 'skill execute failed', executed);
    assertOk(executed?.execution_authority_in_rust === true, 'skill execute authority not reported', executed);
    assertOk(executed?.output?.status === 'ok', 'skill execute output mismatch', executed);
    assertNoLeak(executed, 'skill execute');

    const deniedExecute = await httpJson('POST', `${baseUrl}/skills/execute`, {
      scope_key: 'project:memory-skills-prod',
      skill_id: 'health',
      requested_capabilities: ['health'],
      input: { token: 'sk-memory-skills-prod-secret' },
    }, 1500, [403]);
    assertOk(deniedExecute?.deny_code === 'skill_input_secret_pattern_denied', 'secret skill input was not denied', deniedExecute);
    assertNoLeak(deniedExecute, 'secret skill execute denied');

    process.stdout.write(`${JSON.stringify({
      ok: true,
      schema_version: 'xhub.rust_hub.memory_skills_production_smoke.v1',
      command: 'memory-skills-production-smoke',
      http_base_url: baseUrl,
      memory_writer_authority_in_rust: true,
      skills_execution_authority_in_rust: true,
      memory_write_ok: true,
      memory_secret_denied: true,
      written_memory_retrievable: true,
      skill_execute_ok: true,
      skill_secret_input_denied: true,
      detail_json_included: false,
      secret_leak: false,
    }, null, 2)}\n`);
  } finally {
    await stopChild(child);
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
}

try {
  await main();
} catch (error) {
  process.stderr.write(`[memory_skills_production_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
