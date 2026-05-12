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
    port: 60600 + (process.pid % 1000),
    reportFile: '',
    keepTemp: false,
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
      case '--report-file':
        out.reportFile = String(next || '').trim();
        if (!out.reportFile) throw new Error('--report-file requires a path');
        i += 1;
        break;
      case '--keep-temp':
        out.keepTemp = true;
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
    'xt_file_ipc_runtime_execution_plan_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
    '  --report-file <path> Write the JSON report to a file',
    '  --keep-temp          Keep the temporary smoke directory',
  ].join('\n');
}

function resolveXhubdBinary() {
  const packagedBin = path.join(ROOT_DIR, 'bin', 'xhubd');
  const releaseBin = path.join(ROOT_DIR, 'target', 'release', 'xhubd');
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  if (fs.existsSync(packagedBin)) return packagedBin;
  if (fs.existsSync(releaseBin)) return releaseBin;
  if (fs.existsSync(debugBin)) return debugBin;
  const built = spawnSync('cargo', ['build', '--bin', 'xhubd'], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  if (built.status !== 0) {
    throw new Error(`cargo build failed before runtime execution plan smoke: ${built.stderr}`);
  }
  return debugBin;
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
          resolve({ statusCode: res.statusCode || 0, body: JSON.parse(raw) });
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

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 800)}` : '';
    throw new Error(`${message}${suffix}`);
  }
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

async function waitForHealth(baseUrl, child, output, timeoutMs) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (child.exitCode !== null) {
      throw new Error(`xhubd exited before health: ${child.exitCode}\n${output.stderr.slice(-1000)}`);
    }
    try {
      const response = await httpJson('GET', `${baseUrl}/health`, undefined, 750);
      if (response.statusCode >= 200 && response.statusCode < 300) return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\n${output.stderr.slice(-1000)}`);
}

async function stopChild(child) {
  if (!child || !child.pid || child.exitCode !== null) return;
  child.kill('SIGTERM');
  spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || !pidAlive(child.pid)) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (child.exitCode === null && pidAlive(child.pid)) {
    child.kill('SIGKILL');
    spawnSync('kill', ['-KILL', String(child.pid)], { encoding: 'utf8' });
  }
}

function writeRequestAndRuntime(baseDir, reqId, modelId) {
  fs.mkdirSync(path.join(baseDir, 'ai_requests'), { recursive: true });
  fs.mkdirSync(path.join(baseDir, 'ai_responses'), { recursive: true });
  fs.mkdirSync(path.join(baseDir, 'ai_cancels'), { recursive: true });
  fs.writeFileSync(path.join(baseDir, 'ai_requests', `req_${reqId}.json`), `${JSON.stringify({
    type: 'generate',
    req_id: reqId,
    app_id: 'x-terminal',
    task_type: 'text_generate',
    preferred_model_id: modelId,
    prompt: 'runtime execution plan smoke',
    max_tokens: 8,
    temperature: 0.2,
    top_p: 0.95,
    created_at: 100.5,
    auto_load: true,
  })}\n`, 'utf8');
  const artifact = path.join(baseDir, 'model.gguf');
  fs.writeFileSync(artifact, 'fixture', 'utf8');
  fs.writeFileSync(path.join(baseDir, 'models_state.json'), `${JSON.stringify({
    models: [{ id: modelId, backend: 'mlx', modelPath: artifact, capabilities: ['text_generate'] }],
  }, null, 2)}\n`, 'utf8');
  fs.writeFileSync(path.join(baseDir, 'ai_runtime_status.json'), `${JSON.stringify({
    providers: {
      mlx: {
        provider: 'mlx',
        ok: true,
        availableTaskKinds: ['text_generate'],
        runtimeSource: 'fixture',
        runtimeSourcePath: '/tmp/fixture-runtime',
        runtimeResolutionState: 'resolved',
        updatedAtMs: 1000,
      },
    },
  }, null, 2)}\n`, 'utf8');
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

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-xt-file-ipc-runtime-plan-smoke-'));
  const hubRoot = path.join(tempRoot, 'hub-root');
  const ipcDir = path.join(tempRoot, 'xt-ipc');
  const modelId = 'local.plan-smoke';
  const reqId = 'runtime_plan_smoke';
  let child = null;
  let output = { stdout: '', stderr: '' };

  try {
    writeRequestAndRuntime(ipcDir, reqId, modelId);
    fs.mkdirSync(path.join(tempRoot, 'data'), { recursive: true });
    const env = {
      ...process.env,
      XHUB_RUST_HUB_ROOT: hubRoot,
      XHUB_RUST_HUB_HOST: '127.0.0.1',
      XHUB_RUST_HUB_HTTP_PORT: String(args.port),
      HUB_DB_PATH: path.join(tempRoot, 'data', 'hub.sqlite3'),
      HUB_RUNTIME_BASE_DIR: ipcDir,
      XHUB_RUST_MEMORY_DIR: path.join(tempRoot, 'memory'),
      XHUB_RUST_SKILLS_DIR: path.join(tempRoot, 'skills'),
      XHUB_RUST_XT_FILE_IPC_SHADOW: '1',
      XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN: '1',
    };
    child = spawn(resolveXhubdBinary(), ['serve'], {
      cwd: ROOT_DIR,
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });

    const baseUrl = `http://127.0.0.1:${args.port}`;
    await waitForHealth(baseUrl, child, output, args.timeoutMs);
    const ready = await httpJson('GET', `${baseUrl}/ready`, undefined, 2000);
    assertOk(ready.body?.capabilities?.xt_file_ipc_shadow_runtime_execution_plan_http === true, 'runtime plan capability missing');
    assertOk(ready.body?.capabilities?.xt_file_ipc_production_surface_ready !== undefined, 'production file IPC readiness missing');

    const plan = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-execution-plan`, {
      base_dir: ipcDir,
      runtime_base_dir: ipcDir,
      req_id: reqId,
    }, args.timeoutMs);
    assertOk(plan.statusCode === 200, 'runtime execution plan HTTP status failed', plan);
    assertOk(plan.body?.ok === true, 'runtime execution plan failed', plan.body);
    assertOk(plan.body?.ready === false, 'runtime execution plan marked ready');
    assertOk(plan.body?.wrote === false, 'runtime execution plan wrote files');
    assertOk(plan.body?.model_route?.selected_model_id === modelId, 'model route did not select local model', plan.body?.model_route);
    assertOk(plan.body?.execution_adapter_plan?.adapter_kind === 'local_runtime_file_ipc', 'adapter kind mismatch', plan.body?.execution_adapter_plan);
    assertOk(plan.body?.execution_adapter_plan?.dry_run_candidate === true, 'dry run candidate was false', plan.body?.execution_adapter_plan);
    assertOk(plan.body?.execution_adapter_plan?.production_candidate === false, 'production candidate unexpectedly true', plan.body?.execution_adapter_plan);
    assertOk(plan.body?.authority?.production_authority_change === false, 'production authority changed');
    assertOk(!fs.existsSync(path.join(ipcDir, 'ai_responses', `resp_${reqId}.jsonl`)), 'response file was written');
    assertOk(!fs.existsSync(path.join(ipcDir, 'hub_status.json')), 'hub_status.json was written');

    const report = {
      schema_version: 'xhub.rust_hub.xt_file_ipc_runtime_execution_plan_smoke.v1',
      ok: true,
      production_authority_change: false,
      temp_root: tempRoot,
      base_url: baseUrl,
      request_id: reqId,
      model_id: modelId,
      report_file: '',
      checks: {
        ready_capability: true,
        plan_ok: true,
        model_route_selected: true,
        dry_run_candidate: true,
        production_candidate: false,
        response_written: false,
        hub_status_written: false,
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
    schema_version: 'xhub.rust_hub.xt_file_ipc_runtime_execution_plan_smoke.v1',
    ok: false,
    error_message: error?.stack || error?.message || String(error),
  }, null, 2));
  process.exit(1);
});
