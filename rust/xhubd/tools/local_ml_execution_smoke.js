#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const DEFAULT_HTTP_BASE_URL = 'http://127.0.0.1:50151';

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

function readLaunchdEnvironmentVariables(plistPath) {
  const resolved = safeString(plistPath) ? path.resolve(plistPath) : '';
  if (process.platform !== 'darwin' || !resolved || !fs.existsSync(resolved)) return {};
  try {
    const result = spawnSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', resolved], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (result.status !== 0) return {};
    const parsed = JSON.parse(result.stdout || '{}');
    const env = parsed?.EnvironmentVariables;
    return env && typeof env === 'object' && !Array.isArray(env) ? env : {};
  } catch {
    return {};
  }
}

function readAccessKey(config) {
  const raw = safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY || process.env.XHUB_RUST_HUB_ACCESS_KEY);
  if (raw) return raw;
  const launchdEnv = readLaunchdEnvironmentVariables(path.join(process.env.HOME || '', 'Library', 'LaunchAgents', 'com.ax.xhubd.local.plist'));
  const filePath = safeString(config.accessKeyFile)
    || safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE)
    || safeString(process.env.XHUB_RUST_HUB_ACCESS_KEY_FILE)
    || safeString(launchdEnv.XHUB_RUST_HTTP_ACCESS_KEY_FILE)
    || safeString(launchdEnv.XHUB_RUST_HUB_ACCESS_KEY_FILE);
  if (!filePath) return '';
  try {
    return safeString(fs.readFileSync(path.resolve(filePath), 'utf8'));
  } catch {
    return '';
  }
}

function parseArgs(argv) {
  const out = {
    httpBaseUrl: DEFAULT_HTTP_BASE_URL,
    accessKeyFile: '',
    runtimeBaseDir: '',
    timeoutMs: 30000,
    reportPath: '',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--http-base-url':
        out.httpBaseUrl = safeString(next) || out.httpBaseUrl;
        i += 1;
        break;
      case '--access-key-file':
        out.accessKeyFile = safeString(next);
        i += 1;
        break;
      case '--runtime-base-dir':
        out.runtimeBaseDir = safeString(next);
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--report-path':
        out.reportPath = safeString(next);
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
  if (!out.reportPath) {
    out.reportPath = path.join(REPORT_DIR, `local_ml_execution_smoke_${utcStamp()}.json`);
  } else if (!path.isAbsolute(out.reportPath)) {
    out.reportPath = path.resolve(ROOT_DIR, out.reportPath);
  }
  return out;
}

function usage() {
  return [
    'local_ml_execution_smoke.js',
    '',
    'Validates that Rust local ML execution readiness is active and that the HTTP bridge dispatches into the Python local runtime without loading a model.',
    '',
    'Options:',
    '  --http-base-url <u>      Rust xhubd HTTP base URL, default http://127.0.0.1:50151',
    '  --access-key-file <p>    HTTP access key file; defaults to env or com.ax.xhubd.local launchd plist',
    '  --runtime-base-dir <p>   Optional runtime base dir override',
    '  --timeout-ms <ms>        Execute request timeout, default 30000',
    '  --report-path <p>        JSON report path',
  ].join('\n');
}

function requestJson(method, url, config, body = null, timeoutMs = 5000) {
  return new Promise((resolve) => {
    const accessKey = safeString(config.httpAccessKey);
    const payload = body == null ? '' : JSON.stringify(body);
    const headers = {
      ...(accessKey ? { Authorization: `Bearer ${accessKey}` } : {}),
      ...(payload ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(payload) } : {}),
    };
    const req = http.request(url, { method, headers, timeout: timeoutMs }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          resolve({
            ok: res.statusCode >= 200 && res.statusCode < 300,
            status_code: res.statusCode,
            body: JSON.parse(data || '{}'),
            error: '',
            parse_error: '',
          });
        } catch (error) {
          resolve({
            ok: false,
            status_code: res.statusCode,
            body: null,
            error: '',
            parse_error: String(error.message || error),
          });
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => resolve({ ok: false, status_code: 0, body: null, error: String(error.message || error), parse_error: '' }));
    if (payload) req.write(payload);
    req.end();
  });
}

function acceptedRuntimeError(value) {
  const error = safeString(value?.result?.error || value?.result?.reasonCode || value?.result?.reason_code || value?.error_code);
  return error === 'provider_not_resolved'
    || error.startsWith('unknown_provider:')
    || error.startsWith('unsupported_task_kind:')
    || error.startsWith('model_task_unsupported:');
}

async function run(config) {
  config.httpAccessKey = readAccessKey(config);
  const startedAtMs = Date.now();
  const readiness = await requestJson('GET', `${config.httpBaseUrl}/runtime/ml-execution/readiness`, config, null, 5000);
  const requestId = `local-ml-smoke-${utcStamp()}`;
  const executeBody = {
    command: 'run-local-task',
    request_id: requestId,
    timeout_ms: config.timeoutMs,
    ...(config.runtimeBaseDir ? { runtime_base_dir: config.runtimeBaseDir } : {}),
    request: {
      request_id: requestId,
      provider_id: '__xhub_smoke_missing_provider__',
      model_id: '__xhub_smoke_missing_model__',
      task_kind: 'xhub_smoke_unsupported_task',
      prompt: 'xhub local ml smoke',
      allow_daemon_proxy: false,
      allow_runtime_daemon_proxy: false,
    },
  };
  const execute = await requestJson('POST', `${config.httpBaseUrl}/runtime/ml-execution/execute`, config, executeBody, config.timeoutMs + 5000);
  const readinessOk = readiness.ok
    && readiness.body?.ready === true
    && readiness.body?.execution_authority_in_rust === true
    && readiness.body?.engine === 'python_local_runtime';
  const executeDispatched = execute.ok
    && execute.body?.schema_version === 'xhub.rust_hub.local_ml_execution_bridge.v1'
    && execute.body?.engine === 'python_local_runtime'
    && execute.body?.execution_authority_in_rust === true
    && execute.body?.request_id === requestId
    && acceptedRuntimeError(execute.body);
  const issues = [];
  if (!readinessOk) issues.push('local_ml_readiness_not_active');
  if (!executeDispatched) issues.push('local_ml_execute_bridge_not_observed');
  const report = {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.local_ml_execution_smoke.v1',
    command: 'local-ml-execution-smoke',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAtMs,
    http_base_url: config.httpBaseUrl,
    runtime_base_dir: safeString(readiness.body?.runtime_base_dir || execute.body?.runtime_base_dir || config.runtimeBaseDir),
    readiness: {
      ok: readinessOk,
      status_code: readiness.status_code,
      ready: readiness.body?.ready === true,
      enabled: readiness.body?.enabled === true,
      authority: safeString(readiness.body?.authority),
      engine: safeString(readiness.body?.engine),
      script_exists: readiness.body?.script_exists === true,
      python_available: readiness.body?.python_available === true,
      blocker: safeString(readiness.body?.blocker),
      error: readiness.error,
      parse_error: readiness.parse_error,
    },
    execute: {
      ok: executeDispatched,
      status_code: execute.status_code,
      bridge_ok: execute.body?.ok === true,
      expected_negative_result: true,
      error_code: safeString(execute.body?.error_code),
      result_error: safeString(execute.body?.result?.error || execute.body?.result?.reasonCode || execute.body?.result?.reason_code),
      engine: safeString(execute.body?.engine),
      execution_authority_in_rust: execute.body?.execution_authority_in_rust === true,
      audit_ref_present: safeString(execute.body?.audit_ref) !== '',
      error: execute.error,
      parse_error: execute.parse_error,
    },
    production_authority_change: false,
    ui_product_change: false,
    secret_leak: false,
    issues,
    report_path: config.reportPath,
  };
  fs.mkdirSync(path.dirname(config.reportPath), { recursive: true });
  fs.writeFileSync(config.reportPath, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  const report = await run(config);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (!report.ok) process.exit(2);
}

main().catch((error) => {
  process.stderr.write(`[local_ml_execution_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
