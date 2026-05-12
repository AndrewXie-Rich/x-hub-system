#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'scheduler_production_authority');
const STATE_FILE = path.join(STATE_DIR, 'launchctl_session_env_state.json');
const DEFAULT_APP = 'build/X-Hub.app';
const NODE_PROCESS_MARKERS = [
  'hub_grpc_server/src/server.js',
  'relflowhub_node',
];

const KEYS = [
  'XHUB_RUST_HUB_ROOT',
  'XHUB_RUST_SCHEDULER_STATUS_READ',
  'XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY',
  'XHUB_RUST_SCHEDULER_STATUS_HTTP',
  'XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL',
  'XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS',
  'XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP',
  'XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL',
  'XHUB_RUST_SCHEDULER_AUTHORITY',
  'XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_SCHEDULER_AUTHORITY_HTTP',
  'XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_TIMEOUT_MS',
  'XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_TO_CLI',
  'XHUB_RUST_SCHEDULER_AUTHORITY_OWNER',
  'XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS',
  'XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS',
  'XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS',
  'XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS',
  'XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR',
  'XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS',
  'XHUB_RUST_SCHEDULER_AUTHORITY_MAX_MISMATCHES',
  'XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS',
  'XHUB_RUST_SCHEDULER_AUTHORITY_MAX_STALE_ACTIVE',
  'XHUB_RUST_SCHEDULER_AUTHORITY_MAX_ORPHANED_LEASES',
  'XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS',
  'XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_BY',
  'XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_AT',
];

function parseArgs(argv) {
  const out = {
    mode: 'status',
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
    appPath: DEFAULT_APP,
    openApp: false,
    minCompareReports: 10,
    minLeaseShadowRuns: 1,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--status':
        out.mode = 'status';
        break;
      case '--apply':
        out.mode = 'apply';
        break;
      case '--rollback':
        out.mode = 'rollback';
        break;
      case '--open-xhub':
        out.openApp = true;
        break;
      case '--app':
        out.appPath = String(next || '').trim() || out.appPath;
        i += 1;
        break;
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
        i += 1;
        break;
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--self-test':
        out.selfTest = true;
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
    'scheduler_production_authority_session.js',
    '',
    'Options:',
    '  --status              Inspect current user launchctl scheduler authority env',
    '  --apply               Set scheduler production authority env in user launchd session',
    '  --rollback            Restore/unset env from previous apply',
    '  --open-xhub           Open X-Hub.app after apply',
    '  --app <path>          X-Hub.app path',
    '  --rust-hub-root <p>   Rust Hub root exported to X-Hub/Node',
    '  --http-base-url <u>   Rust xhubd HTTP base URL',
    '  --self-test           Run in-memory self-test',
  ].join('\n');
}

function desiredEnv(config) {
  return {
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_SCHEDULER_STATUS_READ: '1',
    XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_STATUS_HTTP: '1',
    XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS: '750',
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP: '1',
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_AUTHORITY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_TIMEOUT_MS: '750',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_TO_CLI: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_OWNER: 'node-hub-paid-ai-authority',
    XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS: '300000',
    XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS: '45000',
    XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS: '100',
    XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS: '1000',
    XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS: String(config.minCompareReports),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_MISMATCHES: '0',
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS: String(config.minLeaseShadowRuns),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_STALE_ACTIVE: '0',
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_ORPHANED_LEASES: '0',
    XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_BY: 'rust-hub-rhm-071-session',
    XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_AT: new Date().toISOString(),
  };
}

function getEnv(key) {
  try {
    return execFileSync('launchctl', ['getenv', key], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch {
    return '';
  }
}

function setEnv(key, value) {
  execFileSync('launchctl', ['setenv', key, value], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function unsetEnv(key) {
  execFileSync('launchctl', ['unsetenv', key], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function snapshot() {
  const out = {};
  for (const key of KEYS) out[key] = getEnv(key);
  return out;
}

function inspect(config) {
  const current = snapshot();
  const desired = desiredEnv(config);
  const mismatches = [];
  for (const [key, value] of Object.entries(desired)) {
    if (key === 'XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_AT') continue;
    if (String(current[key] || '') !== String(value)) mismatches.push(key);
  }
  const launchctlApplied = mismatches.length === 0;
  const nodeProcess = inspectRunningNodeProcess(config, desired);
  return {
    applied: launchctlApplied,
    launchctl_session_applied: launchctlApplied,
    authority_enabled: launchctlApplied || nodeProcess.authority_enabled,
    production_authority_effective_now: nodeProcess.authority_enabled,
    session_env_persistent_for_future_launches: launchctlApplied,
    rust_hub_root: current.XHUB_RUST_HUB_ROOT || '',
    http_base_url: current.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL || '',
    managed_key_count_present: Object.values(current).filter((value) => value !== '').length,
    mismatch_keys: mismatches,
    running_node_process_pid: nodeProcess.pid,
    running_node_process_authority_enabled: nodeProcess.authority_enabled,
    running_node_process_env_present: nodeProcess.present_keys,
    running_node_process_env_missing: nodeProcess.missing_keys,
    running_node_process_env_mismatched: nodeProcess.mismatched_keys,
    running_node_process_checked: nodeProcess.checked,
    running_node_process_check_error: nodeProcess.error,
  };
}

function inspectRunningNodeProcess(config, desired) {
  const safeDesired = {
    XHUB_RUST_HUB_ROOT: desired.XHUB_RUST_HUB_ROOT,
    XHUB_RUST_SCHEDULER_AUTHORITY: desired.XHUB_RUST_SCHEDULER_AUTHORITY,
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP: desired.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP,
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL: desired.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL,
    XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: desired.XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY,
    XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR: desired.XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR,
    XHUB_RUST_SCHEDULER_STATUS_HTTP: desired.XHUB_RUST_SCHEDULER_STATUS_HTTP,
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP: desired.XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP,
  };
  try {
    const rows = execFileSync('ps', ['axeww', '-o', 'pid=,command='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 8 * 1024 * 1024,
    }).split('\n');
    const candidates = rows
      .map((line) => line.trim())
      .filter((line) => NODE_PROCESS_MARKERS.every((marker) => line.includes(marker)))
      .filter((line) => !line.includes('scheduler_production_authority_session.js'));
    if (candidates.length === 0) {
      return emptyNodeProcess('not_found', true);
    }
    const parsed = candidates
      .map((line) => {
        const match = line.match(/^(\d+)\s+([\s\S]*)$/);
        if (!match) return null;
        return { pid: Number(match[1]), command: match[2] };
      })
      .filter(Boolean)
      .sort((a, b) => b.pid - a.pid)[0];
    const values = parseManagedEnvFromProcessLine(parsed.command);
    const present = [];
    const missing = [];
    const mismatched = [];
    for (const [key, value] of Object.entries(safeDesired)) {
      if (!Object.prototype.hasOwnProperty.call(values, key)) {
        missing.push(key);
      } else {
        present.push(key);
        if (String(values[key]) !== String(value)) mismatched.push(key);
      }
    }
    return {
      checked: true,
      pid: parsed.pid,
      authority_enabled: values.XHUB_RUST_SCHEDULER_AUTHORITY === '1'
        && values.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP === '1'
        && values.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL === config.httpBaseUrl,
      present_keys: present,
      missing_keys: missing,
      mismatched_keys: mismatched,
      error: '',
    };
  } catch (error) {
    return emptyNodeProcess(error?.message || String(error), true);
  }
}

function parseManagedEnvFromProcessLine(line) {
  const values = {};
  for (const key of KEYS) {
    const prefix = `${key}=`;
    let idx = line.indexOf(prefix);
    if (idx > 0 && line[idx - 1] !== ' ') idx = line.indexOf(` ${prefix}`);
    if (idx === -1) continue;
    if (line[idx] === ' ') idx += 1;
    const start = idx + prefix.length;
    const rest = line.slice(start);
    const nextEnv = rest.match(/ [A-Za-z_][A-Za-z0-9_]*=/);
    let end = nextEnv ? start + nextEnv.index : line.length;
    while (end > start && line[end - 1] === ' ') end -= 1;
    values[key] = line.slice(start, end);
  }
  return values;
}

function emptyNodeProcess(error, checked = false) {
  return {
    checked,
    pid: 0,
    authority_enabled: false,
    present_keys: [],
    missing_keys: [],
    mismatched_keys: [],
    error,
  };
}

function writeState(state) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(STATE_FILE, `${JSON.stringify(state, null, 2)}\n`);
}

function readState() {
  if (!fs.existsSync(STATE_FILE)) return null;
  return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
}

function openApp(appPath) {
  execFileSync('open', [appPath], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function runSelfTest() {
  const config = parseArgs(['--apply', '--rust-hub-root', '/tmp/rust-hub']);
  const env = desiredEnv(config);
  if (env.XHUB_RUST_SCHEDULER_AUTHORITY !== '1') throw new Error('authority env missing');
  if (env.XHUB_RUST_HUB_ROOT !== '/tmp/rust-hub') throw new Error('root override failed');
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('scheduler_production_authority_session self-test ok\n');
    return;
  }
  if (config.mode === 'apply' && !fs.existsSync(config.appPath)) {
    throw new Error(`X-Hub.app not found: ${config.appPath}`);
  }

  if (config.mode === 'apply') {
    const previous = snapshot();
    const env = desiredEnv(config);
    for (const [key, value] of Object.entries(env)) setEnv(key, value);
    writeState({
      schema_version: 'xhub.scheduler_production_authority_session_state.v1',
      generated_at: new Date().toISOString(),
      previous_values: previous,
      managed_keys: KEYS,
    });
    if (config.openApp) openApp(config.appPath);
  } else if (config.mode === 'rollback') {
    const state = readState();
    if (!state) throw new Error(`missing rollback state: ${STATE_FILE}`);
    for (const key of state.managed_keys || KEYS) {
      const previous = String(state.previous_values?.[key] || '');
      if (previous) setEnv(key, previous);
      else unsetEnv(key);
    }
  }

  process.stdout.write(`${JSON.stringify({
    ok: true,
    schema_version: 'xhub.scheduler_production_authority_session.v1',
    mode: config.mode,
    state_file: STATE_FILE,
    app_path: config.appPath,
    app_exists: fs.existsSync(config.appPath),
    apply_performed: config.mode === 'apply',
    rollback_performed: config.mode === 'rollback',
    open_performed: config.mode === 'apply' && config.openApp,
    ...inspect(config),
    scheduler_authority_target: config.mode !== 'rollback',
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[scheduler_production_authority_session] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
