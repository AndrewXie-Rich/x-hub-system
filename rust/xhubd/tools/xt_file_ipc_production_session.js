#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'xt_file_ipc_production');
const STATE_FILE = path.join(STATE_DIR, 'launchctl_session_env_state.json');
const DEFAULT_LIVE_BASE_DIR = path.join(
  process.env.HOME || '',
  'Library',
  'Group Containers',
  'group.rel.flowhub',
);

const KEYS = [
  'XHUB_RUST_HUB_ROOT',
  'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER',
  'XHUB_RUST_XT_FILE_IPC_BASE_DIR',
  'XHUB_RUST_XT_CLASSIC_COMPAT',
  'XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT_MS',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_LEASE_MS',
  'XHUB_RUST_XT_CLASSIC_GRPC_PROBE',
  'XHUB_RUST_XT_CLASSIC_GRPC_HOST',
  'XHUB_RUST_XT_CLASSIC_GRPC_PORT',
  'XHUB_RUST_XT_CLASSIC_GRPC_PROBE_TIMEOUT_MS',
  'XHUB_RUST_XT_CLASSIC_GRPC_MTLS_TRANSPORT_FALLBACK',
  'XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR',
  'XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH',
  'XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT',
  'XHUB_RUST_XT_CLASSIC_FILE_IPC_READY',
  'XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER',
];

function parseArgs(argv) {
  const out = {
    mode: 'status',
    rustHubRoot: ROOT_DIR,
    liveBaseDir: '',
    grpcHost: '127.0.0.1',
    grpcPort: '50152',
    grpcProbeTimeoutMs: '250',
    confirmLiveCutover: false,
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
      case '--live-base-dir':
        out.liveBaseDir = String(next || '').trim();
        i += 1;
        break;
      case '--grpc-host':
        out.grpcHost = String(next || '').trim() || out.grpcHost;
        i += 1;
        break;
      case '--grpc-port':
        out.grpcPort = String(next || '').trim() || out.grpcPort;
        i += 1;
        break;
      case '--grpc-probe-timeout-ms':
        out.grpcProbeTimeoutMs = String(next || '').trim() || out.grpcProbeTimeoutMs;
        i += 1;
        break;
      case '--confirm-live-cutover':
        out.confirmLiveCutover = true;
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
    'xt_file_ipc_production_session.js',
    '',
    'Options:',
    '  --status                    Inspect XT file IPC production env',
    '  --apply                     Set explicit XT file IPC production env in user launchd session',
    '  --rollback                  Restore/unset env from previous apply',
    '  --rust-hub-root <p>         Rust Hub root exported to X-Hub/Node',
    '  --live-base-dir <p>         Existing non-temp XT file IPC base dir',
    '  --grpc-host <h>             Classic compat gRPC probe host',
    '  --grpc-port <p>             Classic compat gRPC probe port',
    '  --grpc-probe-timeout-ms <n> Classic compat gRPC probe timeout',
    '  --confirm-live-cutover      Required with --apply',
    '  --self-test                 Run in-memory self-test',
    '',
    `Default live base dir candidate: ${DEFAULT_LIVE_BASE_DIR}`,
  ].join('\n');
}

function normalizeLiveBaseDir(value) {
  const trimmed = String(value || '').trim();
  if (!trimmed) return '';
  return path.resolve(trimmed);
}

function validateLiveBaseDir(value) {
  const liveBaseDir = normalizeLiveBaseDir(value);
  if (!liveBaseDir) throw new Error('missing --live-base-dir');
  if (!path.isAbsolute(liveBaseDir)) throw new Error('live base dir must be absolute');
  if (liveBaseDir === '/tmp' || liveBaseDir === '/private/tmp' || liveBaseDir.startsWith('/tmp/') || liveBaseDir.startsWith('/private/tmp/')) {
    throw new Error('live base dir must not be a temporary directory');
  }
  if (!fs.existsSync(liveBaseDir)) throw new Error(`live base dir does not exist: ${liveBaseDir}`);
  if (!fs.statSync(liveBaseDir).isDirectory()) throw new Error(`live base dir is not a directory: ${liveBaseDir}`);
  return liveBaseDir;
}

function validateNumericRange(name, raw, min, max) {
  const parsed = Number.parseInt(String(raw), 10);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer in range ${min}..${max}`);
  }
  return String(parsed);
}

function desiredEnv(config) {
  const liveBaseDir = validateLiveBaseDir(config.liveBaseDir);
  const grpcPort = validateNumericRange('grpc port', config.grpcPort, 1, 65535);
  const grpcProbeTimeoutMs = validateNumericRange('grpc probe timeout ms', config.grpcProbeTimeoutMs, 50, 5000);
  return {
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER: '1',
    XHUB_RUST_XT_FILE_IPC_BASE_DIR: liveBaseDir,
    XHUB_RUST_XT_CLASSIC_COMPAT: '1',
    XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES: '1',
    XHUB_RUST_XT_CLASSIC_STATUS_WRITER: '1',
    XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY: '1',
    XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT: '1',
    XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT_MS: '1000',
    XHUB_RUST_XT_CLASSIC_STATUS_WRITER_LEASE_MS: '2000',
    XHUB_RUST_XT_CLASSIC_GRPC_PROBE: '1',
    XHUB_RUST_XT_CLASSIC_GRPC_HOST: config.grpcHost,
    XHUB_RUST_XT_CLASSIC_GRPC_PORT: grpcPort,
    XHUB_RUST_XT_CLASSIC_GRPC_PROBE_TIMEOUT_MS: grpcProbeTimeoutMs,
    XHUB_RUST_XT_CLASSIC_GRPC_MTLS_TRANSPORT_FALLBACK: '1',
    XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR: liveBaseDir,
    XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH: path.join(liveBaseDir, 'hub_status.json'),
    XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT: '1',
    XHUB_RUST_XT_CLASSIC_FILE_IPC_READY: '1',
    XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER: '1',
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
  const desired = config.liveBaseDir ? desiredEnv(config) : null;
  const mismatchKeys = [];
  if (desired) {
    for (const [key, value] of Object.entries(desired)) {
      if (String(current[key] || '') !== String(value)) mismatchKeys.push(key);
    }
  }
  const liveBaseDir = current.XHUB_RUST_XT_FILE_IPC_BASE_DIR || current.XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR || '';
  return {
    applied: desired ? mismatchKeys.length === 0 : false,
    managed_key_count_present: Object.values(current).filter((value) => value !== '').length,
    mismatch_keys: mismatchKeys,
    desired_live_base_dir: desired ? desired.XHUB_RUST_XT_FILE_IPC_BASE_DIR : '',
    configured_live_base_dir: liveBaseDir,
    live_base_dir_configured: liveBaseDir !== '',
    file_ipc_production_cutover_enabled: current.XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER === '1',
    classic_compat_enabled: current.XHUB_RUST_XT_CLASSIC_COMPAT === '1',
    classic_scan_enabled: current.XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES === '1',
    classic_status_writer_enabled: current.XHUB_RUST_XT_CLASSIC_STATUS_WRITER === '1',
    classic_status_writer_apply_enabled: current.XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY === '1',
    classic_grpc_probe_enabled: current.XHUB_RUST_XT_CLASSIC_GRPC_PROBE === '1',
    classic_rollback_contract_enabled: current.XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT === '1',
    classic_file_ipc_ready_enabled: current.XHUB_RUST_XT_CLASSIC_FILE_IPC_READY === '1',
    classic_production_cutover_enabled: current.XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER === '1',
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
  const temp = '/tmp/rust-hub-live-base';
  let rejectedTemp = false;
  try {
    validateLiveBaseDir(temp);
  } catch {
    rejectedTemp = true;
  }
  if (!rejectedTemp) throw new Error('temporary live base dir must be rejected');

  const config = parseArgs([
    '--apply',
    '--rust-hub-root',
    '/tmp/rust-hub',
    '--live-base-dir',
    DEFAULT_LIVE_BASE_DIR,
    '--confirm-live-cutover',
  ]);
  const env = desiredEnv({
    ...config,
    liveBaseDir: process.env.HOME || '/',
  });
  if (env.XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER !== '1') throw new Error('file IPC production cutover env missing');
  if (env.XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY !== '1') throw new Error('classic status writer apply env missing');
  if (Object.keys(env).some((key) => key.includes('MEMORY') || key.includes('SKILLS'))) {
    throw new Error('production file IPC session must not manage memory or skills keys');
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
    process.stdout.write('xt_file_ipc_production_session self-test ok\n');
    return;
  }

  if (config.mode === 'apply') {
    if (!config.confirmLiveCutover) throw new Error('missing --confirm-live-cutover');
    const previous = snapshot();
    const env = desiredEnv(config);
    for (const [key, value] of Object.entries(env)) setEnv(key, value);
    writeState({
      schema_version: 'xhub.xt_file_ipc_production_session_state.v1',
      generated_at: new Date().toISOString(),
      previous_values: previous,
      managed_keys: KEYS,
      live_base_dir: env.XHUB_RUST_XT_FILE_IPC_BASE_DIR,
      status_path: env.XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH,
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
    ok: true,
    schema_version: 'xhub.xt_file_ipc_production_session.v1',
    mode: config.mode,
    state_file: STATE_FILE,
    apply_performed: config.mode === 'apply',
    rollback_performed: config.mode === 'rollback',
    ...inspected,
    production_authority_change: config.mode === 'apply',
    xt_file_ipc_production_surface_ready_target: config.mode === 'apply',
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[xt_file_ipc_production_session] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
