#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'xt_file_ipc_prep');
const STATE_FILE = path.join(STATE_DIR, 'launchctl_session_env_state.json');

const KEYS = [
  'XHUB_RUST_HUB_ROOT',
  'XHUB_RUST_XT_FILE_IPC_SHADOW',
  'XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY',
  'XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE',
  'XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN',
  'XHUB_RUST_XT_FILE_IPC_RUNTIME_ADAPTER_CANDIDATE',
  'XHUB_RUST_XT_FILE_IPC_RUNTIME_READY',
  'XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY',
  'XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY',
  'XHUB_RUST_XT_FILE_IPC_WATCHER_RUN_ONCE_APPLY',
  'XHUB_RUST_XT_FILE_IPC_WATCHER_SESSION_APPLY',
  'XHUB_RUST_XT_FILE_IPC_WATCHER_BACKGROUND_APPLY',
  'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER',
  'XHUB_RUST_XT_FILE_IPC_BASE_DIR',
];

function parseArgs(argv) {
  const out = {
    mode: 'status',
    rustHubRoot: ROOT_DIR,
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
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
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
    'xt_file_ipc_prep_session.js',
    '',
    'Options:',
    '  --status              Inspect XT file IPC prep env',
    '  --apply               Set default-off XT file IPC prep env in user launchd session',
    '  --rollback            Restore/unset env from previous apply',
    '  --rust-hub-root <p>   Rust Hub root exported to X-Hub/Node',
    '  --self-test           Run in-memory self-test',
  ].join('\n');
}

function desiredEnv(config) {
  return {
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_XT_FILE_IPC_SHADOW: '1',
    XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY: '1',
    XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE: '1',
    XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN: '1',
    XHUB_RUST_XT_FILE_IPC_RUNTIME_ADAPTER_CANDIDATE: '1',
    XHUB_RUST_XT_FILE_IPC_RUNTIME_READY: '1',
    XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY: '1',
    XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY: '1',
    XHUB_RUST_XT_FILE_IPC_WATCHER_RUN_ONCE_APPLY: '1',
    XHUB_RUST_XT_FILE_IPC_WATCHER_SESSION_APPLY: '1',
    XHUB_RUST_XT_FILE_IPC_WATCHER_BACKGROUND_APPLY: '1',
  };
}

function getEnv(key) {
  try {
    return execFileSync('launchctl', ['getenv', key], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch {
    return '';
  }
}

function setEnv(key, value) {
  execFileSync('launchctl', ['setenv', key, value], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function unsetEnv(key) {
  execFileSync('launchctl', ['unsetenv', key], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function snapshot() {
  const out = {};
  for (const key of KEYS) out[key] = getEnv(key);
  return out;
}

function inspect(config) {
  const current = snapshot();
  const desired = desiredEnv(config);
  const mismatchKeys = [];
  for (const [key, value] of Object.entries(desired)) {
    if (String(current[key] || '') !== String(value)) mismatchKeys.push(key);
  }
  const forbiddenEnabled = [
    'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER',
    'XHUB_RUST_XT_FILE_IPC_BASE_DIR',
  ].filter((key) => String(current[key] || '') !== '');
  return {
    applied: mismatchKeys.length === 0 && forbiddenEnabled.length === 0,
    managed_key_count_present: Object.values(current).filter((value) => value !== '').length,
    mismatch_keys: mismatchKeys,
    forbidden_enabled_keys: forbiddenEnabled,
    shadow_enabled: current.XHUB_RUST_XT_FILE_IPC_SHADOW === '1',
    shadow_apply_enabled: current.XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY === '1',
    watcher_enabled: current.XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE === '1',
    runtime_plan_enabled: current.XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN === '1',
    runtime_adapter_candidate_enabled: current.XHUB_RUST_XT_FILE_IPC_RUNTIME_ADAPTER_CANDIDATE === '1',
    runtime_ready_enabled: current.XHUB_RUST_XT_FILE_IPC_RUNTIME_READY === '1',
    rollback_apply_enabled: current.XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY === '1',
    watcher_start_apply_enabled: current.XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY === '1',
    watcher_run_once_apply_enabled: current.XHUB_RUST_XT_FILE_IPC_WATCHER_RUN_ONCE_APPLY === '1',
    watcher_session_apply_enabled: current.XHUB_RUST_XT_FILE_IPC_WATCHER_SESSION_APPLY === '1',
    watcher_background_apply_enabled: current.XHUB_RUST_XT_FILE_IPC_WATCHER_BACKGROUND_APPLY === '1',
    production_cutover_enabled: current.XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER === '1',
    live_base_dir_configured: String(current.XHUB_RUST_XT_FILE_IPC_BASE_DIR || '') !== '',
    rust_hub_root: current.XHUB_RUST_HUB_ROOT || '',
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

function runSelfTest() {
  const config = parseArgs(['--apply', '--rust-hub-root', '/tmp/rust-hub']);
  const env = desiredEnv(config);
  if (env.XHUB_RUST_XT_FILE_IPC_SHADOW !== '1') throw new Error('shadow env missing');
  if (env.XHUB_RUST_XT_FILE_IPC_RUNTIME_ADAPTER_CANDIDATE !== '1') {
    throw new Error('runtime adapter candidate env missing');
  }
  if (Object.prototype.hasOwnProperty.call(env, 'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER')) {
    throw new Error('prep session must not set production cutover');
  }
  if (Object.prototype.hasOwnProperty.call(env, 'XHUB_RUST_XT_FILE_IPC_BASE_DIR')) {
    throw new Error('prep session must not set a live base dir');
  }
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('xt_file_ipc_prep_session self-test ok\n');
    return;
  }

  if (config.mode === 'apply') {
    const previous = snapshot();
    const env = desiredEnv(config);
    for (const [key, value] of Object.entries(env)) setEnv(key, value);
    unsetEnv('XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER');
    unsetEnv('XHUB_RUST_XT_FILE_IPC_BASE_DIR');
    writeState({
      schema_version: 'xhub.xt_file_ipc_prep_session_state.v1',
      generated_at: new Date().toISOString(),
      previous_values: previous,
      managed_keys: KEYS,
    });
  } else if (config.mode === 'rollback') {
    const state = readState();
    if (!state) throw new Error(`missing rollback state: ${STATE_FILE}`);
    for (const key of state.managed_keys || KEYS) {
      const previous = String(state.previous_values?.[key] || '');
      if (previous) setEnv(key, previous);
      else unsetEnv(key);
    }
  }

  const inspected = inspect(config);
  process.stdout.write(`${JSON.stringify({
    ok: inspected.forbidden_enabled_keys.length === 0,
    schema_version: 'xhub.xt_file_ipc_prep_session.v1',
    mode: config.mode,
    state_file: STATE_FILE,
    apply_performed: config.mode === 'apply',
    rollback_performed: config.mode === 'rollback',
    ...inspected,
    production_authority_change: false,
    xt_file_ipc_production_surface_ready: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[xt_file_ipc_prep_session] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
