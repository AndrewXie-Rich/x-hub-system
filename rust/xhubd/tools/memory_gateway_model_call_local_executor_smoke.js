#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const SCHEMA = 'xhub.rust_hub.memory_gateway_model_call_local_executor_smoke.v1';

function safeString(value) {
  return String(value ?? '').trim();
}

function utcStamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const stamp = utcStamp();
  const out = {
    xhubdBin: safeString(process.env.XHUBD_BIN),
    port: 0,
    timeoutMs: 10000,
    startupTimeoutMs: 15000,
    keepTemp: false,
    reportPath: path.join(REPORT_DIR, `memory_gateway_model_call_local_executor_smoke_${stamp}.json`),
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--xhubd-bin':
        out.xhubdBin = safeString(next);
        i += 1;
        break;
      case '--port':
        out.port = parseIntInRange(next, out.port, 0, 65535);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 60000);
        i += 1;
        break;
      case '--startup-timeout-ms':
        out.startupTimeoutMs = parseIntInRange(next, out.startupTimeoutMs, 1000, 60000);
        i += 1;
        break;
      case '--report-path':
        out.reportPath = safeString(next) || out.reportPath;
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
  if (!path.isAbsolute(out.reportPath)) out.reportPath = path.resolve(ROOT_DIR, out.reportPath);
  if (out.xhubdBin && !path.isAbsolute(out.xhubdBin)) out.xhubdBin = path.resolve(ROOT_DIR, out.xhubdBin);
  return out;
}

function usage() {
  return [
    'memory_gateway_model_call_local_executor_smoke.js',
    '',
    'Starts an isolated temporary xhubd with Memory Gateway local executor env enabled and a synthetic Python runtime.',
    'The live daemon, launchd env, and production authority are not modified.',
    '',
    'Options:',
    '  --xhubd-bin <p>          Optional xhubd binary; defaults to package bin or cargo build',
    '  --port <n>              Optional local test port; default random free port',
    '  --timeout-ms <n>        HTTP/runtime timeout, default 10000',
    '  --startup-timeout-ms <n> Isolated daemon startup timeout, default 15000',
    '  --report-path <p>       JSON report path',
    '  --keep-temp             Keep temporary runtime root for inspection',
  ].join('\n');
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

async function freePort() {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : 0;
      server.close(() => resolve(port));
    });
  });
}

function resolveXhubdBin(explicit) {
  if (explicit) {
    if (!fs.existsSync(explicit)) throw new Error(`xhubd binary not found: ${explicit}`);
    return explicit;
  }
  const packaged = path.join(ROOT_DIR, 'bin', 'xhubd');
  if (fs.existsSync(packaged)) return packaged;
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  if (fs.existsSync(debugBin)) return debugBin;
  const built = spawnSyncChecked('cargo', ['build', '--bin', 'xhubd'], { cwd: ROOT_DIR });
  if (built.status !== 0) throw new Error(`cargo build failed: ${built.stderr || built.stdout}`);
  if (!fs.existsSync(debugBin)) throw new Error(`cargo build did not produce ${debugBin}`);
  return debugBin;
}

function pythonCandidate() {
  const candidates = [
    process.env.PYTHON3,
    process.env.PYTHON,
    '/usr/bin/python3',
    '/Library/Frameworks/Python.framework/Versions/3.11/bin/python3',
    '/opt/homebrew/bin/python3',
  ].map(safeString).filter(Boolean);
  for (const candidate of candidates) {
    if (path.isAbsolute(candidate) && fs.existsSync(candidate)) return candidate;
  }
  return '';
}

function writeFakeRuntime(scriptPath) {
  fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
  fs.writeFileSync(scriptPath, `#!/usr/bin/env python3
import json
import sys

def main():
    try:
        request = json.load(sys.stdin)
    except Exception as exc:
        print(json.dumps({"ok": False, "reasonCode": "invalid_json", "error": str(exc)}))
        return 0
    print(json.dumps({
        "ok": True,
        "reasonCode": "",
        "engine": "xhub_memory_gateway_fake_local_runtime",
        "result": {
            "ok": True,
            "text": "Synthetic bounded memory gateway local execution output.",
            "request_id": request.get("request_id", "")
        }
    }))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
`, 'utf8');
  fs.chmodSync(scriptPath, 0o755);
}

function safeTail(value, limit = 3000) {
  const text = String(value || '');
  return text.length <= limit ? text : text.slice(-limit);
}

function startXhubd({ bin, port, tempRoot, runtimeDir, memoryDir, skillsDir, dbPath, fakeRuntimePath, pythonPath }) {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.mkdirSync(memoryDir, { recursive: true });
  fs.mkdirSync(skillsDir, { recursive: true });
  const env = {
    ...process.env,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
    XHUB_RUST_HUB_HOST: '127.0.0.1',
    XHUB_RUST_HUB_HTTP_PORT: String(port),
    XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY: '0',
    XHUB_RUST_HTTP_ACCESS_KEY: '',
    XHUB_RUST_HTTP_ACCESS_KEY_FILE: '',
    XHUB_RUST_HUB_ACCESS_KEY: '',
    XHUB_RUST_HUB_ACCESS_KEY_FILE: '',
    XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT: '0',
    XHUB_RUST_HUB_PUBLIC_BASE_URL: '',
    XHUB_RUST_HUB_PUBLIC_HOST: '',
    HUB_DB_PATH: dbPath,
    HUB_RUNTIME_BASE_DIR: runtimeDir,
    XHUB_RUST_MEMORY_DIR: memoryDir,
    XHUB_RUST_SKILLS_DIR: skillsDir,
    XHUB_RUST_LOCAL_RUNTIME_SCRIPT: fakeRuntimePath,
    PYTHON3: pythonPath,
    XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION: '1',
    XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION: '1',
    XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_ADMISSION: '1',
    XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION: '1',
    XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR: '1',
    XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY: '1',
    XHUB_RUST_ML_EXECUTION_AUTHORITY: '1',
    XHUB_RUST_LOCAL_ML_EXECUTION_AUTHORITY: '1',
    XHUB_ENABLE_RUST_ML_EXECUTION: '1',
    REL_FLOW_HUB_BASE_DIR: tempRoot,
  };
  const child = spawn(bin, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });
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
          reject(new Error(`http_status:${res.statusCode}:${raw.slice(0, 500)}`));
          return;
        }
        try {
          resolve({ statusCode: Number(res.statusCode || 0), raw, value: JSON.parse(raw) });
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${raw.slice(0, 500)}`));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error(`http_timeout:${url}`)));
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

function executeSummary(value) {
  return {
    schema_version: safeString(value?.schema_version),
    ok: value?.ok === true,
    status: safeString(value?.status),
    source: safeString(value?.source),
    mode: safeString(value?.mode),
    authority: safeString(value?.authority),
    execution_authority_in_rust: value?.execution_authority_in_rust === true,
    execution_enabled: value?.execution_enabled === true,
    ready_for_execution: value?.ready_for_execution === true,
    would_call_model: value?.would_call_model === true,
    model_call_invoked: value?.model_call_invoked === true,
    model_call_executed: value?.model_call_executed === true,
    local_ml_execute_http_invoked: value?.guards?.local_ml_execute_http_invoked === true,
    context_text_redacted_from_execute: value?.guards?.context_text_redacted_from_execute === true,
    prompt_text_redacted_from_execute: value?.guards?.prompt_text_redacted_from_execute === true,
    provider_route_not_mutated: value?.guards?.provider_route_not_mutated === true,
    node_not_authority: value?.guards?.node_not_authority === true,
    local_executor_enabled: value?.executor?.local_executor_enabled === true,
    local_executor_apply_enabled: value?.executor?.local_executor_apply_enabled === true,
    local_route_allowed: value?.executor?.local_route_allowed === true,
    local_ml_result_text_included: value?.local_ml?.result_text_included === true,
    production_authority_change: value?.production_authority_change === true,
    blocker_count: Array.isArray(value?.blockers) ? value.blockers.length : 0,
  };
}

async function run(args) {
  const startedAtMs = Date.now();
  const port = args.port || await freePort();
  const baseUrl = `http://127.0.0.1:${port}`;
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-memory-gateway-local-executor-smoke-'));
  const runtimeDir = path.join(tempRoot, 'runtime');
  const memoryDir = path.join(tempRoot, 'data', 'memory');
  const skillsDir = path.join(tempRoot, 'skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const fakeRuntimePath = path.join(runtimeDir, 'fake_relflowhub_local_runtime.py');
  const pythonPath = pythonCandidate();
  const issueCodes = [];
  let child = null;
  let output = { stdout: '', stderr: '' };
  let ready = {};
  let metrics = {};
  let executeResp = { raw: '', value: {} };
  let error = '';

  try {
    if (!pythonPath) throw new Error('python3_not_found');
    writeFakeRuntime(fakeRuntimePath);
    const bin = resolveXhubdBin(args.xhubdBin);
    ({ child, output } = startXhubd({
      bin,
      port,
      tempRoot,
      runtimeDir,
      memoryDir,
      skillsDir,
      dbPath,
      fakeRuntimePath,
      pythonPath,
    }));
    await waitForHealth(baseUrl, child, output, args.startupTimeoutMs);
    ready = (await httpJson('GET', `${baseUrl}/ready`, undefined, args.timeoutMs)).value;
    const promptNeedle = `Memory gateway local executor bounded smoke prompt ${utcStamp()} should not leak`;
    const body = {
      request_id: `memory_gateway_local_executor_smoke_${utcStamp()}`,
      audit_ref: `memory_gateway_local_executor_smoke:${utcStamp()}`,
      requester_role: 'chat',
      use_mode: 'project_chat',
      scope: 'project',
      project_id: 'xt-memory-gateway-local-executor-smoke',
      serving_profile_id: 'M1_Execute',
      provider_id: 'local',
      model_id: 'memory-gateway-local-executor-smoke-local',
      task_kind: 'text_generate',
      prompt: promptNeedle,
      execute: true,
      timeout_ms: args.timeoutMs,
    };
    executeResp = await httpJson(
      'POST',
      `${baseUrl}/memory/gateway/model-call-execute`,
      body,
      args.timeoutMs + 2000,
    );
    metrics = (await httpJson('GET', `${baseUrl}/runtime/http-metrics`, undefined, args.timeoutMs)).value;
    const execute = executeSummary(executeResp.value);
    if (ready?.ready !== true) issueCodes.push('isolated_xhubd_not_ready');
    if (ready?.memory?.gateway_model_call_execute?.local_executor_ready_for_attempt !== true) {
      issueCodes.push('local_executor_not_ready_for_attempt');
    }
    if (execute.schema_version !== 'xhub.memory.gateway_model_call_execute.v1') {
      issueCodes.push('execute_schema_mismatch');
    }
    if (execute.status !== 'executed' || execute.mode !== 'local_ml_execute') {
      issueCodes.push('local_executor_execute_not_observed');
    }
    if (!execute.execution_authority_in_rust || !execute.execution_enabled || !execute.ready_for_execution) {
      issueCodes.push('local_executor_authority_not_active');
    }
    if (!execute.model_call_invoked || !execute.model_call_executed || !execute.local_ml_execute_http_invoked) {
      issueCodes.push('local_executor_model_call_not_invoked');
    }
    if (!execute.context_text_redacted_from_execute || !execute.prompt_text_redacted_from_execute) {
      issueCodes.push('local_executor_redaction_guard_missing');
    }
    if (!execute.provider_route_not_mutated || !execute.node_not_authority) {
      issueCodes.push('local_executor_authority_guard_missing');
    }
    if (!execute.local_executor_enabled || !execute.local_executor_apply_enabled || !execute.local_route_allowed) {
      issueCodes.push('local_executor_flags_missing');
    }
    if (execute.production_authority_change) issueCodes.push('production_authority_changed');
    if (executeResp.raw.includes(promptNeedle)) issueCodes.push('prompt_leak');
    if (Number(metrics?.recent_slow_requests || 0) > 0 || Number(metrics?.slow_requests || 0) > 0) {
      issueCodes.push('isolated_slow_request_observed');
    }
  } catch (err) {
    error = safeString(err?.stack || err?.message || err);
    issueCodes.push('memory_gateway_local_executor_smoke_failed');
  } finally {
    if (child && child.exitCode === null) {
      child.kill('SIGTERM');
      await new Promise((resolve) => setTimeout(resolve, 100));
      if (child.exitCode === null) child.kill('SIGKILL');
    }
  }

  const execute = executeSummary(executeResp.value);
  const report = {
    ok: issueCodes.length === 0,
    schema_version: SCHEMA,
    command: 'memory-gateway-model-call-local-executor-smoke',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAtMs,
    http_base_url: baseUrl,
    temp_root: args.keepTemp ? tempRoot : '',
    isolated_daemon: true,
    production_authority_change: false,
    live_daemon_touched: false,
    memory_execute_readiness: ready?.memory?.gateway_model_call_execute || null,
    execute,
    http_metrics: {
      ok: metrics?.ok === true,
      total_requests: Number(metrics?.total_requests || 0),
      slow_requests: Number(metrics?.slow_requests || 0),
      recent_slow_requests: Number(metrics?.recent_slow_requests || 0),
      recent_max_elapsed_ms: Number(metrics?.recent_max_elapsed_ms || 0),
      max_elapsed_ms: Number(metrics?.max_elapsed_ms || 0),
      route_count: Number(metrics?.route_count || 0),
    },
    content_free: !issueCodes.includes('prompt_leak'),
    stdout_tail: safeTail(output.stdout, 1200),
    stderr_tail: safeTail(output.stderr, 1200),
    issue_codes: [...new Set(issueCodes)],
    error,
    report_path: args.reportPath,
  };
  fs.mkdirSync(path.dirname(args.reportPath), { recursive: true });
  fs.writeFileSync(args.reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  if (!args.keepTemp) fs.rmSync(tempRoot, { recursive: true, force: true });
  return report;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  const report = await run(args);
  console.log(JSON.stringify(report, null, 2));
  if (!report.ok) process.exit(1);
}

main().catch((error) => {
  process.stderr.write(`[memory_gateway_model_call_local_executor_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
