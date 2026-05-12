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
    keepTemp: false,
    reportFile: '',
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
      case '--keep-temp':
        out.keepTemp = true;
        break;
      case '--report-file':
        out.reportFile = String(next || '').trim();
        if (!out.reportFile) throw new Error('--report-file requires a path');
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
    'xt_file_ipc_watcher_run_once_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
    '  --keep-temp          Keep the temporary smoke directory',
    '  --report-file <path> Write the JSON report to a file',
  ].join('\n');
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-25).join('\n');
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 800)}` : '';
    throw new Error(`${message}${suffix}`);
  }
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

function pidAlive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function resolveXhubdBinary() {
  const packagedBin = path.join(ROOT_DIR, 'bin', 'xhubd');
  const releaseBin = path.join(ROOT_DIR, 'target', 'release', 'xhubd');
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  if (fs.existsSync(packagedBin)) return packagedBin;
  if (fs.existsSync(releaseBin)) return releaseBin;
  if (fs.existsSync(debugBin)) return debugBin;
  const built = spawnSyncChecked('cargo', ['build', '--bin', 'xhubd'], { cwd: ROOT_DIR });
  if (built.status !== 0) {
    throw new Error(`cargo build failed before XT file IPC smoke: ${built.stderr}`);
  }
  return debugBin;
}

function startXhubd({ port, rootDir, dbPath, runtimeDir, memoryDir, skillsDir }) {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.mkdirSync(memoryDir, { recursive: true });
  fs.mkdirSync(skillsDir, { recursive: true });
  const env = {
    ...process.env,
    XHUB_RUST_HUB_ROOT: rootDir,
    XHUB_RUST_HUB_HOST: '127.0.0.1',
    XHUB_RUST_HUB_HTTP_PORT: String(port),
    HUB_DB_PATH: dbPath,
    HUB_RUNTIME_BASE_DIR: runtimeDir,
    XHUB_RUST_MEMORY_DIR: memoryDir,
    XHUB_RUST_SKILLS_DIR: skillsDir,
    XHUB_RUST_XT_FILE_IPC_SHADOW: '1',
    XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY: '1',
    XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE: '1',
    XHUB_RUST_XT_FILE_IPC_RUNTIME_READY: '1',
    XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY: '1',
    XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY: '1',
    XHUB_RUST_XT_FILE_IPC_WATCHER_RUN_ONCE_APPLY: '1',
  };
  const child = spawn(resolveXhubdBinary(), ['serve'], {
    cwd: ROOT_DIR,
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
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
        try {
          resolve({
            statusCode: res.statusCode || 0,
            body: JSON.parse(raw),
          });
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
      const response = await httpJson('GET', `${baseUrl}/health`, undefined, 750);
      if (response.statusCode >= 200 && response.statusCode < 300) return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
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
  }
}

async function stopChild(child) {
  if (!child || !child.pid || child.exitCode !== null) return;
  child.kill('SIGTERM');
  spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
  await waitForExit(child, 5000);
}

function writeRequest(baseDir, reqId) {
  fs.mkdirSync(path.join(baseDir, 'ai_requests'), { recursive: true });
  fs.mkdirSync(path.join(baseDir, 'ai_responses'), { recursive: true });
  fs.mkdirSync(path.join(baseDir, 'ai_cancels'), { recursive: true });
  fs.writeFileSync(path.join(baseDir, 'ai_requests', `req_${reqId}.json`), `${JSON.stringify({
    type: 'generate',
    req_id: reqId,
    model_id: 'mlx/smoke',
    task_type: 'text_generate',
    prompt: 'hello from xt file ipc watcher run once smoke',
    max_tokens: 8,
  })}\n`, 'utf8');
}

function readJson(pathname) {
  return JSON.parse(fs.readFileSync(pathname, 'utf8'));
}

function resolveReportFile(reportFile) {
  if (!reportFile) return '';
  const resolved = path.resolve(process.cwd(), reportFile);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  return resolved;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-xt-file-ipc-run-once-smoke-'));
  const rootDir = path.join(tempRoot, 'hub-root');
  const ipcDir = path.join(tempRoot, 'xt-ipc');
  const reqId = 'run_once_smoke';
  let child = null;
  let output = null;

  try {
    writeRequest(ipcDir, reqId);
    const started = startXhubd({
      port: args.port,
      rootDir,
      dbPath: path.join(tempRoot, 'data', 'hub.sqlite3'),
      runtimeDir: path.join(tempRoot, 'runtime'),
      memoryDir: path.join(tempRoot, 'memory'),
      skillsDir: path.join(tempRoot, 'skills'),
    });
    child = started.child;
    output = started.output;
    const baseUrl = `http://127.0.0.1:${args.port}`;
    await waitForHealth(baseUrl, child, output, args.timeoutMs);

    const ready = await httpJson('GET', `${baseUrl}/ready`, undefined, 2000);
    assertOk(ready.statusCode === 200, 'ready request failed', ready);
    assertOk(ready.body?.capabilities?.xt_file_ipc_shadow_watcher_run_once_http === true, 'run-once capability missing');
    assertOk(ready.body?.capabilities?.xt_file_ipc_production_surface_ready !== undefined, 'production file IPC readiness missing');
    const productionSurfaceReadyObserved = ready.body?.capabilities?.xt_file_ipc_production_surface_ready === true;

    const response = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/watcher-run-once`, {
      base_dir: ipcDir,
      apply: true,
      max_requests: 16,
      max_cycles: 1,
      cycle_interval_ms: 0,
    }, args.timeoutMs);
    assertOk(response.statusCode === 200, 'run-once HTTP status failed', response);
    const body = response.body;
    assertOk(body.ok === true, 'run-once did not succeed', body);
    assertOk(body.ready === false, 'run-once marked ready');
    assertOk(body.wrote === true, 'run-once did not write shadow artifacts');
    assertOk(body?.watcher_run_once?.lock_acquired === true, 'lock was not acquired');
    assertOk(body?.watcher_run_once?.lock_released === true, 'lock was not released');
    assertOk(body?.watcher_run_once?.background_watcher_started === false, 'background watcher unexpectedly started');
    assertOk(typeof body?.watcher_run_once?.production_file_ipc_ready === 'boolean', 'production file IPC readiness field missing');
    assertOk(body?.watcher_run_once?.ml_execution_in_rust === false, 'ML execution unexpectedly enabled');

    const lockPath = path.join(ipcDir, 'rust_file_ipc_shadow_watcher.lock');
    const watcherStatusPath = path.join(ipcDir, 'rust_file_ipc_shadow_watcher_status.json');
    const processorStatusPath = path.join(ipcDir, 'rust_file_ipc_shadow_processor_status.json');
    const responsePath = path.join(ipcDir, 'ai_responses', `resp_${reqId}.jsonl`);
    const hubStatusPath = path.join(ipcDir, 'hub_status.json');
    assertOk(!fs.existsSync(lockPath), 'watcher lock was not released');
    assertOk(fs.existsSync(watcherStatusPath), 'watcher status missing');
    assertOk(fs.existsSync(processorStatusPath), 'processor status missing');
    assertOk(fs.existsSync(responsePath), 'XT response JSONL missing');
    assertOk(!fs.existsSync(hubStatusPath), 'hub_status.json was written unexpectedly');

    const watcherStatus = readJson(watcherStatusPath);
    const processorStatus = readJson(processorStatusPath);
    const responseLines = fs.readFileSync(responsePath, 'utf8').trim().split(/\r?\n/).map((line) => JSON.parse(line));
    assertOk(watcherStatus.state === 'stopped', 'watcher status did not stop', watcherStatus);
    assertOk(watcherStatus.ready === false, 'watcher status marked ready', watcherStatus);
    assertOk(watcherStatus.hub_status_written === false, 'watcher status claims hub_status write', watcherStatus);
    assertOk(processorStatus.ready === false, 'processor status marked ready', processorStatus);
    assertOk(processorStatus.production_file_ipc_ready === false, 'processor status marked production ready', processorStatus);
    assertOk(responseLines.length === 2, 'unexpected response line count', { responseLines });
    assertOk(responseLines[0].type === 'start', 'first response event is not start', responseLines[0]);
    assertOk(responseLines[1].type === 'done', 'second response event is not done', responseLines[1]);
    assertOk(responseLines[1].ok === false, 'done event unexpectedly succeeded', responseLines[1]);
    assertOk(responseLines[1].reason === 'rust_file_ipc_not_authoritative', 'done event reason changed', responseLines[1]);

    const report = {
      schema_version: 'xhub.rust_hub.xt_file_ipc_watcher_run_once_smoke.v1',
      ok: true,
      production_authority_change: false,
      temp_root: tempRoot,
      base_url: baseUrl,
      request_id: reqId,
      report_file: '',
      checks: {
        ready_capability: true,
        run_once_ok: true,
        lock_released: true,
        watcher_status_stopped: true,
        processor_status_shadow_only: true,
        response_fail_closed: true,
        hub_status_written: false,
        background_watcher_started: false,
        production_surface_ready_observed: productionSurfaceReadyObserved,
        production_surface_ready_accepted: true,
        shadow_processor_production_file_ipc_ready: processorStatus.production_file_ipc_ready === false,
        production_file_ipc_ready: false,
        ml_execution_in_rust: false,
      },
    };
    report.report_file = resolveReportFile(args.reportFile);
    if (report.report_file) {
      fs.writeFileSync(report.report_file, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    }
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await stopChild(child);
    if (!args.keepTemp) {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(JSON.stringify({
    schema_version: 'xhub.rust_hub.xt_file_ipc_watcher_run_once_smoke.v1',
    ok: false,
    error_message: error?.stack || error?.message || String(error),
  }, null, 2));
  process.exit(1);
});
