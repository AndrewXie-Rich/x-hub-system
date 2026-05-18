#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const DEFAULT_HTTP_BASE_URL = 'http://127.0.0.1:50151';
const FALLBACK_LIVE_BASE_DIR = path.join(process.env.HOME || '', 'Library', 'Group Containers', 'group.rel.flowhub');
const STATUS_READER_SCRIPT = `
const fs = require('node:fs');
const [statusPath, ipcPath, baseDir, nowRaw] = process.argv.slice(1);
const nowMs = Number(nowRaw || Date.now());
let stat = null;
let body = null;
let parseOk = false;
let readError = '';
try {
  if (fs.existsSync(statusPath)) {
    stat = fs.statSync(statusPath);
    try {
      body = JSON.parse(fs.readFileSync(statusPath, 'utf8'));
      parseOk = true;
    } catch (error) {
      readError = String(error && error.message || error);
    }
  }
} catch (error) {
  readError = String(error && error.message || error);
}
const updatedAtMs = Number(body && body.updatedAt || 0) > 0 ? Math.round(Number(body.updatedAt) * 1000) : 0;
const ageMs = updatedAtMs > 0 ? Math.max(0, nowMs - updatedAtMs) : Number.MAX_SAFE_INTEGER;
const out = {
  base_dir: baseDir,
  status_path: statusPath,
  status_exists: Boolean(stat),
  status_size_bytes: stat ? stat.size : 0,
  status_mtime_ms: stat ? Math.round(stat.mtimeMs) : 0,
  status_json_parse_ok: parseOk,
  status_read_timeout: false,
  status_read_error: readError,
  updated_at_ms: updatedAtMs,
  age_ms: ageMs,
  pid: Number(body && body.pid || 0),
  ipc_mode: String(body && body.ipcMode || ''),
  ipc_path: String(body && body.ipcPath || ''),
  base_dir_from_status: String(body && body.baseDir || ''),
  ai_ready: Boolean(body && body.aiReady),
  loaded_model_count: Number(body && body.loadedModelCount || 0),
  rust_hub_authority: String(body && body.rustHub && body.rustHub.authority || ''),
  rust_hub_schema_version: String(body && body.rustHub && body.rustHub.schema_version || ''),
  expected_ipc_path: ipcPath,
  ipc_path_exists: fs.existsSync(ipcPath),
};
process.stdout.write(JSON.stringify(out));
`;

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function safeString(value) {
  return String(value ?? '').trim();
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

function defaultLaunchdEnv() {
  return readLaunchdEnvironmentVariables(path.join(process.env.HOME || '', 'Library', 'LaunchAgents', 'com.ax.xhubd.local.plist'));
}

function readAccessKeyForProbe(config = {}) {
  const raw = safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY || process.env.XHUB_RUST_HUB_ACCESS_KEY);
  if (raw) return raw;
  const launchdEnv = defaultLaunchdEnv();
  const accessKeyFile = safeString(config.accessKeyFile)
    || safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY_FILE)
    || safeString(process.env.XHUB_RUST_HUB_ACCESS_KEY_FILE)
    || safeString(launchdEnv.XHUB_RUST_HTTP_ACCESS_KEY_FILE)
    || safeString(launchdEnv.XHUB_RUST_HUB_ACCESS_KEY_FILE);
  if (!accessKeyFile) return '';
  try {
    return safeString(fs.readFileSync(path.resolve(accessKeyFile), 'utf8'));
  } catch {
    return '';
  }
}

function parseArgs(argv) {
  const out = {
    httpBaseUrl: DEFAULT_HTTP_BASE_URL,
    liveBaseDir: '',
    liveBaseDirSource: 'auto',
    durationMs: 30000,
    intervalMs: 2000,
    maxStatusAgeMs: 5000,
    statusReadTimeoutMs: 3000,
    allowMemorySkillsProduction: false,
    requireMemorySkillsProduction: false,
    accessKeyFile: '',
    reportPath: '',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--live-base-dir':
        out.liveBaseDir = String(next || '').trim() || out.liveBaseDir;
        out.liveBaseDirSource = 'argument';
        i += 1;
        break;
      case '--duration-ms':
        out.durationMs = parseIntInRange(next, out.durationMs, 1, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--interval-ms':
        out.intervalMs = parseIntInRange(next, out.intervalMs, 100, 60000);
        i += 1;
        break;
      case '--max-status-age-ms':
        out.maxStatusAgeMs = parseIntInRange(next, out.maxStatusAgeMs, 500, 60000);
        i += 1;
        break;
      case '--status-read-timeout-ms':
        out.statusReadTimeoutMs = parseIntInRange(next, out.statusReadTimeoutMs, 100, 30000);
        i += 1;
        break;
      case '--access-key-file':
        out.accessKeyFile = String(next || '').trim();
        i += 1;
        break;
      case '--allow-memory-skills-production':
        out.allowMemorySkillsProduction = true;
        break;
      case '--require-memory-skills-production':
        out.allowMemorySkillsProduction = true;
        out.requireMemorySkillsProduction = true;
        break;
      case '--report-path':
        out.reportPath = String(next || '').trim();
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
    out.reportPath = path.join(ROOT_DIR, 'reports', `xt_file_ipc_live_heartbeat_soak_${utcStamp()}.json`);
  } else if (!path.isAbsolute(out.reportPath)) {
    out.reportPath = path.resolve(ROOT_DIR, out.reportPath);
  }
  return out;
}

function usage() {
  return [
    'xt_file_ipc_live_heartbeat_soak.js',
    '',
    'Options:',
    '  --http-base-url <u>      Rust xhubd HTTP base URL',
    '  --live-base-dir <p>      Live XT file IPC base dir; defaults to /xt/classic-hub-compat discovery',
    '  --duration-ms <ms>       Soak duration, default 30000',
    '  --interval-ms <ms>       Delay between checks, default 2000',
    '  --max-status-age-ms <ms> Freshness budget, default 5000',
    '  --status-read-timeout-ms <ms> Child-process status read timeout, default 3000',
    '  --access-key-file <p>  HTTP access key file; defaults to env or com.ax.xhubd.local launchd plist',
    '  --allow-memory-skills-production Permit explicit Rust memory writer and skills execution authority',
    '  --require-memory-skills-production Require both Rust memory writer and skills execution authority',
    '  --report-path <p>       JSON report path',
  ].join('\n');
}

function utcStamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function nowMs() {
  return Date.now();
}

function getJson(url, timeoutMs = 5000, config = {}) {
  return new Promise((resolve) => {
    const headers = { accept: 'application/json' };
    const accessKey = readAccessKeyForProbe(config);
    if (accessKey) headers.Authorization = `Bearer ${accessKey}`;
    const req = http.get(url, { timeout: timeoutMs, headers }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          resolve({ ok: res.statusCode >= 200 && res.statusCode < 300, status_code: res.statusCode, body: JSON.parse(data), error: '' });
        } catch (error) {
          resolve({ ok: false, status_code: res.statusCode, body: null, error: String(error.message || error) });
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => resolve({ ok: false, status_code: 0, body: null, error: String(error.message || error) }));
  });
}

function firstUsableLiveBaseDir(compatBody) {
  const candidates = [
    compatBody?.status_writer?.planned_base_dir,
    compatBody?.xt_contract?.active_classic_hub?.base_dir,
    compatBody?.xt_contract?.active_classic_hub?.base_dir_from_status,
  ].map((item) => String(item || '').trim()).filter(Boolean);
  for (const candidate of candidates) {
    if (path.isAbsolute(candidate)) return path.resolve(candidate);
  }
  const statusPath = String(compatBody?.status_writer?.planned_status_path || compatBody?.xt_contract?.preferred_status_path || '').trim();
  if (path.isAbsolute(statusPath)) return path.dirname(path.resolve(statusPath));
  return '';
}

async function resolveLiveBaseDir(config) {
  if (String(config.liveBaseDir || '').trim()) {
    return { ...config, liveBaseDir: path.resolve(config.liveBaseDir), liveBaseDirSource: config.liveBaseDirSource || 'argument' };
  }
  const compat = await getJson(`${config.httpBaseUrl}/xt/classic-hub-compat`, 10000, config);
  const discovered = compat.ok ? firstUsableLiveBaseDir(compat.body) : '';
  if (discovered) {
    return { ...config, liveBaseDir: discovered, liveBaseDirSource: 'xt_classic_hub_compat' };
  }
  return { ...config, liveBaseDir: path.resolve(FALLBACK_LIVE_BASE_DIR), liveBaseDirSource: 'fallback_group_container' };
}

function emptyStatus(baseDir, statusPath, ipcPath, overrides = {}) {
  return {
    base_dir: baseDir,
    status_path: statusPath,
    status_exists: false,
    status_size_bytes: 0,
    status_mtime_ms: 0,
    status_json_parse_ok: false,
    status_read_timeout: false,
    status_read_error: '',
    updated_at_ms: 0,
    age_ms: Number.MAX_SAFE_INTEGER,
    pid: 0,
    ipc_mode: '',
    ipc_path: '',
    base_dir_from_status: '',
    ai_ready: false,
    loaded_model_count: 0,
    rust_hub_authority: '',
    rust_hub_schema_version: '',
    expected_ipc_path: ipcPath,
    ipc_path_exists: false,
    ...overrides,
  };
}

function readStatus(liveBaseDir, timeoutMs = 3000) {
  const baseDir = path.resolve(liveBaseDir);
  const statusPath = path.join(baseDir, 'hub_status.json');
  const ipcPath = path.join(baseDir, 'ipc_events');
  const result = spawnSync(process.execPath, ['-e', STATUS_READER_SCRIPT, statusPath, ipcPath, baseDir, String(nowMs())], {
    encoding: 'utf8',
    timeout: timeoutMs,
    maxBuffer: 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    return emptyStatus(baseDir, statusPath, ipcPath, {
      status_read_timeout: result.error?.code === 'ETIMEDOUT' || Boolean(result.signal),
      status_read_error: String(result.error?.message || result.stderr || `status=${result.status}`),
    });
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    return emptyStatus(baseDir, statusPath, ipcPath, {
      status_read_error: String(error.message || error),
    });
  }
}

function addIssue(issues, code, detail = {}) {
  issues.push({ code, detail });
}

function checkCycle(config, index, startedAtMs) {
  return Promise.all([
    getJson(`${config.httpBaseUrl}/health`, 5000, config),
    getJson(`${config.httpBaseUrl}/ready`, 5000, config),
    getJson(`${config.httpBaseUrl}/xt/classic-hub-compat`, 10000, config),
  ]).then(([health, ready, compat]) => {
    const status = readStatus(config.liveBaseDir, config.statusReadTimeoutMs);
    const issues = [];
    if (!health.ok || health.body?.ok !== true) addIssue(issues, 'health_not_ok', { error: health.error, status_code: health.status_code });
    if (!ready.ok || ready.body?.ready !== true) addIssue(issues, 'ready_not_ok', { error: ready.error, status_code: ready.status_code });
    if (ready.ok && ready.body?.capabilities?.xt_file_ipc_production_surface_ready !== true) {
      addIssue(issues, 'production_surface_not_ready', { value: ready.body?.capabilities?.xt_file_ipc_production_surface_ready });
    }
    const memoryAuthority = ready.ok && ready.body?.memory?.canonical_writer_in_rust === true;
    const skillsAuthority = ready.ok && ready.body?.skills?.execution_authority_in_rust === true;
    if (memoryAuthority && !config.allowMemorySkillsProduction) addIssue(issues, 'memory_writer_authority_changed');
    if (skillsAuthority && !config.allowMemorySkillsProduction) addIssue(issues, 'skills_execution_authority_changed');
    if (config.requireMemorySkillsProduction && !memoryAuthority) addIssue(issues, 'memory_writer_authority_not_active');
    if (config.requireMemorySkillsProduction && !skillsAuthority) addIssue(issues, 'skills_execution_authority_not_active');
    if (!compat.ok || compat.body?.ok !== true) addIssue(issues, 'compat_not_ok', { error: compat.error, status_code: compat.status_code });
    const active = compat.body?.xt_contract?.active_classic_hub;
    if (!active || active.xt_live !== true) addIssue(issues, 'compat_active_xt_live_missing', { active });
    if (compat.body?.grpc_compat?.probe_ok !== true) addIssue(issues, 'grpc_compat_not_ready', { grpc_compat: compat.body?.grpc_compat });
    if (status.status_read_timeout) addIssue(issues, 'status_read_timeout', { timeout_ms: config.statusReadTimeoutMs, error: status.status_read_error });
    if (status.status_read_error && !status.status_json_parse_ok) addIssue(issues, 'status_read_error', { error: status.status_read_error });
    if (!status.status_exists || !status.status_json_parse_ok) addIssue(issues, 'status_file_missing_or_invalid', status);
    if (status.age_ms > config.maxStatusAgeMs) addIssue(issues, 'status_stale', { age_ms: status.age_ms, max_status_age_ms: config.maxStatusAgeMs });
    if (status.pid <= 1) addIssue(issues, 'status_pid_missing', { pid: status.pid });
    if (status.ipc_mode !== 'file') addIssue(issues, 'status_ipc_mode_not_file', { ipc_mode: status.ipc_mode });
    if (status.ipc_path !== status.expected_ipc_path) addIssue(issues, 'status_ipc_path_mismatch', { ipc_path: status.ipc_path, expected: status.expected_ipc_path });
    if (status.base_dir_from_status !== path.resolve(config.liveBaseDir)) {
      addIssue(issues, 'status_base_dir_mismatch', { base_dir: status.base_dir_from_status, expected: path.resolve(config.liveBaseDir) });
    }
    if (status.ai_ready !== true) addIssue(issues, 'status_ai_ready_not_true', { ai_ready: status.ai_ready });
    if (status.rust_hub_authority !== 'explicit_cutover_only') {
      addIssue(issues, 'status_rust_hub_authority_mismatch', { authority: status.rust_hub_authority });
    }
    return {
      index,
      elapsed_since_start_ms: nowMs() - startedAtMs,
      ok: issues.length === 0,
      issues,
      status,
      memory_writer_authority_in_rust: memoryAuthority,
      skills_execution_authority_in_rust: skillsAuthority,
      ready_surface: ready.body?.capabilities?.xt_file_ipc_production_surface_ready === true,
      compat_xt_live: active?.xt_live === true,
      compat_deny_code: String(compat.body?.deny_code || ''),
    };
  });
}

async function run(config) {
  config = await resolveLiveBaseDir(config);
  const startedAtMs = nowMs();
  const cycles = [];
  let index = 0;
  do {
    index += 1;
    cycles.push(await checkCycle(config, index, startedAtMs));
    if (nowMs() - startedAtMs >= config.durationMs) break;
    await sleep(config.intervalMs);
  } while (true);

  const issues = cycles.flatMap((cycle) => cycle.issues.map((issue) => ({ cycle: cycle.index, ...issue })));
  const updatedAtValues = [...new Set(cycles.map((cycle) => cycle.status.updated_at_ms).filter(Boolean))];
  if (updatedAtValues.length < 2 && config.durationMs >= config.intervalMs * 2) {
    issues.push({ cycle: 0, code: 'status_heartbeat_not_observed', detail: { unique_updated_at_ms: updatedAtValues.length } });
  }
  const ages = cycles.map((cycle) => cycle.status.age_ms).filter((age) => Number.isFinite(age));
  const report = {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.xt_file_ipc_live_heartbeat_soak.v1',
    generated_at_iso: new Date().toISOString(),
    duration_ms: nowMs() - startedAtMs,
    http_base_url: config.httpBaseUrl,
    live_base_dir: path.resolve(config.liveBaseDir),
    live_base_dir_source: config.liveBaseDirSource,
    max_status_age_ms: config.maxStatusAgeMs,
    status_read_timeout_ms: config.statusReadTimeoutMs,
    cycle_count: cycles.length,
    status_unique_updated_at_count: updatedAtValues.length,
    max_observed_status_age_ms: ages.length ? Math.max(...ages) : 0,
    min_observed_status_age_ms: ages.length ? Math.min(...ages) : 0,
    memory_skills_production_allowed: config.allowMemorySkillsProduction,
    memory_skills_production_required: config.requireMemorySkillsProduction,
    memory_writer_authority_in_rust: cycles.some((cycle) => cycle.memory_writer_authority_in_rust === true),
    skills_execution_authority_in_rust: cycles.some((cycle) => cycle.skills_execution_authority_in_rust === true),
    issues,
    cycles,
    report_path: config.reportPath,
  };
  fs.mkdirSync(path.dirname(config.reportPath), { recursive: true });
  fs.writeFileSync(config.reportPath, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    console.log(usage());
    return;
  }
  const report = await run(config);
  console.log(JSON.stringify(report, null, 2));
  if (!report.ok) process.exitCode = 1;
}

main().catch((error) => {
  console.error(String(error.stack || error.message || error));
  process.exit(1);
});
