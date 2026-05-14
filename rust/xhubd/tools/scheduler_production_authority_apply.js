#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const DEFAULT_PLIST = path.join(os.homedir(), 'Library', 'LaunchAgents', 'com.rel.flowhub.dock-agent.plist');
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'scheduler_production_authority');
const STATE_FILE = path.join(STATE_DIR, 'dock_agent_env_state.json');
const MANAGED_KEYS = [
  'XHUB_ENABLE_RUST_AUTHORITY_CUTOVER',
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

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    mode: 'status',
    plistPath: DEFAULT_PLIST,
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
    httpTimeoutMs: 750,
    authorityTimeoutMs: 45000,
    leaseDurationMs: 300000,
    readinessCacheMs: 1000,
    pollMs: 100,
    minCompareReports: 10,
    maxMismatches: 0,
    minLeaseShadowRuns: 1,
    maxStaleActive: 0,
    maxOrphanedLeases: 0,
    allowActiveRuns: true,
    fallbackOnError: true,
    restartDockAgent: false,
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
      case '--plist':
        out.plistPath = String(next || '').trim() || out.plistPath;
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
      case '--http-timeout-ms':
        out.httpTimeoutMs = parseIntInRange(next, out.httpTimeoutMs, 100, 300000);
        i += 1;
        break;
      case '--authority-timeout-ms':
        out.authorityTimeoutMs = parseIntInRange(next, out.authorityTimeoutMs, 1000, 300000);
        i += 1;
        break;
      case '--min-compare-reports':
        out.minCompareReports = parseIntInRange(next, out.minCompareReports, 0, 1000000);
        i += 1;
        break;
      case '--min-lease-shadow-runs':
        out.minLeaseShadowRuns = parseIntInRange(next, out.minLeaseShadowRuns, 0, 1000000);
        i += 1;
        break;
      case '--no-active-runs':
        out.allowActiveRuns = false;
        break;
      case '--no-fallback-on-error':
        out.fallbackOnError = false;
        break;
      case '--restart-dock-agent':
        out.restartDockAgent = true;
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
    'scheduler_production_authority_apply.js',
    '',
    'Options:',
    '  --status                       Inspect Dock Agent LaunchAgent env, default',
    '  --apply                        Add scheduler production authority env to Dock Agent LaunchAgent',
    '  --rollback                     Restore keys changed by the last apply',
    '  --restart-dock-agent           Restart com.rel.flowhub.dock-agent after apply/rollback',
    '  --plist <path>                 Target plist, default ~/Library/LaunchAgents/com.rel.flowhub.dock-agent.plist',
    '  --rust-hub-root <path>         Rust Hub root exported to Node, default current package/source root',
    '  --http-base-url <url>          Rust xhubd HTTP URL, default http://127.0.0.1:50151',
    '  --min-compare-reports <n>      Production readiness minimum compare reports, default 10',
    '  --min-lease-shadow-runs <n>    Production readiness minimum lease shadow runs, default 1',
    '  --no-active-runs               Do not allow active scheduler runs at claim time',
    '  --no-fallback-on-error         Fail closed instead of falling back to Node queue',
    '  --self-test                    Run in-memory self-test',
  ].join('\n');
}

function authorityEnv(config) {
  return {
    XHUB_ENABLE_RUST_AUTHORITY_CUTOVER: '1',
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_SCHEDULER_STATUS_READ: '1',
    XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_STATUS_HTTP: '1',
    XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS: String(config.httpTimeoutMs),
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP: '1',
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_AUTHORITY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_TIMEOUT_MS: String(config.httpTimeoutMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_TO_CLI: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_OWNER: 'node-hub-paid-ai-authority',
    XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS: String(config.leaseDurationMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS: String(config.authorityTimeoutMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS: String(config.pollMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS: String(config.readinessCacheMs),
    XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR: config.fallbackOnError ? '1' : '0',
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS: String(config.minCompareReports),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_MISMATCHES: String(config.maxMismatches),
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS: String(config.minLeaseShadowRuns),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_STALE_ACTIVE: String(config.maxStaleActive),
    XHUB_RUST_SCHEDULER_AUTHORITY_MAX_ORPHANED_LEASES: String(config.maxOrphanedLeases),
    XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS: config.allowActiveRuns ? '1' : '0',
    XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_BY: 'rust-hub-rhm-070',
    XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_AT: new Date().toISOString(),
  };
}

function readPlist(plistPath) {
  const stdout = execFileSync('plutil', ['-convert', 'json', '-o', '-', plistPath], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 4 * 1024 * 1024,
  });
  return JSON.parse(stdout);
}

function writePlist(plistPath, plist) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  const tempPath = path.join(STATE_DIR, `.plist-${process.pid}-${Date.now()}.json`);
  fs.writeFileSync(tempPath, JSON.stringify(plist, null, 2));
  try {
    execFileSync('plutil', ['-convert', 'xml1', '-o', plistPath, tempPath], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } finally {
    try { fs.unlinkSync(tempPath); } catch {}
  }
}

function inspect(plist, config) {
  const env = plist.EnvironmentVariables || {};
  const desired = authorityEnv(config);
  const mismatches = [];
  for (const [key, value] of Object.entries(desired)) {
    if (key === 'XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_AT') continue;
    if (String(env[key] ?? '') !== String(value)) mismatches.push(key);
  }
  return {
    applied: mismatches.length === 0 && String(env.XHUB_RUST_SCHEDULER_AUTHORITY_APPLIED_BY || '') === 'rust-hub-rhm-070',
    authority_enabled: String(env.XHUB_RUST_SCHEDULER_AUTHORITY || '') === '1',
    rust_hub_root: String(env.XHUB_RUST_HUB_ROOT || ''),
    http_base_url: String(env.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL || ''),
    managed_key_count_present: MANAGED_KEYS.filter((key) => Object.hasOwn(env, key)).length,
    mismatch_keys: mismatches,
  };
}

function applyEnv(plist, config) {
  const currentEnv = plist.EnvironmentVariables && typeof plist.EnvironmentVariables === 'object'
    ? { ...plist.EnvironmentVariables }
    : {};
  const desired = authorityEnv(config);
  const previous = {};
  const absent = [];
  for (const key of MANAGED_KEYS) {
    if (Object.hasOwn(currentEnv, key)) previous[key] = String(currentEnv[key]);
    else absent.push(key);
  }
  return {
    plist: {
      ...plist,
      EnvironmentVariables: {
        ...currentEnv,
        ...desired,
      },
    },
    state: {
      schema_version: 'xhub.scheduler_production_authority_apply_state.v1',
      generated_at: new Date().toISOString(),
      plist_path: config.plistPath,
      rust_hub_root: config.rustHubRoot,
      previous_values: previous,
      absent_keys: absent,
      managed_keys: MANAGED_KEYS,
    },
  };
}

function rollbackEnv(plist, state) {
  const currentEnv = plist.EnvironmentVariables && typeof plist.EnvironmentVariables === 'object'
    ? { ...plist.EnvironmentVariables }
    : {};
  for (const key of state.managed_keys || MANAGED_KEYS) {
    if (Object.hasOwn(state.previous_values || {}, key)) currentEnv[key] = String(state.previous_values[key]);
    else delete currentEnv[key];
  }
  return {
    ...plist,
    EnvironmentVariables: currentEnv,
  };
}

function backupPlist(plistPath) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, 'Z');
  const backupPath = path.join(STATE_DIR, `dock-agent-${stamp}.plist.bak`);
  fs.copyFileSync(plistPath, backupPath);
  return backupPath;
}

function readState() {
  if (!fs.existsSync(STATE_FILE)) return null;
  return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
}

function writeState(state) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(STATE_FILE, `${JSON.stringify(state, null, 2)}\n`);
}

function restartDockAgent(plistPath) {
  const uid = String(process.getuid?.() ?? execFileSync('id', ['-u'], { encoding: 'utf8' }).trim());
  const label = 'com.rel.flowhub.dock-agent';
  const service = `gui/${uid}/${label}`;
  const domain = `gui/${uid}`;
  let bootout = { ok: true, stderr: '' };
  try {
    execFileSync('launchctl', ['bootout', service], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    const stderr = String(error.stderr || error.message || '');
    bootout = { ok: /No such process|Could not find service/.test(stderr), stderr };
  }
  execFileSync('launchctl', ['bootstrap', domain, plistPath], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return { bootout, bootstrap: { ok: true }, service };
}

function runSelfTest() {
  const config = parseArgs(['--apply', '--rust-hub-root', '/tmp/rust-hub', '--no-active-runs']);
  const original = { Label: 'com.rel.flowhub.dock-agent', EnvironmentVariables: { EXISTING: '1', XHUB_RUST_SCHEDULER_AUTHORITY: '0' } };
  const applied = applyEnv(original, config);
  if (applied.plist.EnvironmentVariables.XHUB_ENABLE_RUST_AUTHORITY_CUTOVER !== '1') throw new Error('apply did not enable rust authority cutover gate');
  if (applied.plist.EnvironmentVariables.XHUB_RUST_SCHEDULER_AUTHORITY !== '1') throw new Error('apply did not enable authority');
  if (applied.plist.EnvironmentVariables.XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS !== '0') throw new Error('allow active runs mismatch');
  const rolledBack = rollbackEnv(applied.plist, applied.state);
  if (rolledBack.EnvironmentVariables.XHUB_RUST_SCHEDULER_AUTHORITY !== '0') throw new Error('rollback did not restore previous authority');
  if (rolledBack.EnvironmentVariables.EXISTING !== '1') throw new Error('rollback removed unrelated env');
  if (Object.hasOwn(rolledBack.EnvironmentVariables, 'XHUB_RUST_HUB_ROOT')) throw new Error('rollback kept absent managed key');
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('scheduler_production_authority_apply self-test ok\n');
    return;
  }

  const plist = readPlist(config.plistPath);
  if (config.mode === 'status') {
    process.stdout.write(`${JSON.stringify({
      ok: true,
      schema_version: 'xhub.scheduler_production_authority_apply.v1',
      mode: 'status',
      plist_path: config.plistPath,
      apply_performed: false,
      rollback_performed: false,
      restart_performed: false,
      ...inspect(plist, config),
      memory_writer_authority_target: false,
      skills_execution_authority_target: false,
      provider_route_authority_target: false,
      model_route_authority_target: false,
      ui_product_change: false,
      secret_leak: false,
    }, null, 2)}\n`);
    return;
  }

  let backupPath = '';
  let restart = null;
  let updated = plist;
  if (config.mode === 'apply') {
    backupPath = backupPlist(config.plistPath);
    const next = applyEnv(plist, config);
    updated = next.plist;
    writePlist(config.plistPath, updated);
    writeState({ ...next.state, backup_path: backupPath });
  } else if (config.mode === 'rollback') {
    const state = readState();
    if (!state) throw new Error(`missing rollback state: ${STATE_FILE}`);
    backupPath = backupPlist(config.plistPath);
    updated = rollbackEnv(plist, state);
    writePlist(config.plistPath, updated);
  }

  if (config.restartDockAgent) {
    restart = restartDockAgent(config.plistPath);
  }

  process.stdout.write(`${JSON.stringify({
    ok: true,
    schema_version: 'xhub.scheduler_production_authority_apply.v1',
    mode: config.mode,
    plist_path: config.plistPath,
    state_file: STATE_FILE,
    backup_path: backupPath,
    apply_performed: config.mode === 'apply',
    rollback_performed: config.mode === 'rollback',
    restart_performed: !!config.restartDockAgent,
    restart,
    ...inspect(updated, config),
    scheduler_authority_target: config.mode === 'rollback' ? false : true,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[scheduler_production_authority_apply] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
