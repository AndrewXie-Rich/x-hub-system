#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'route_authority_prep');
const STATE_FILE = path.join(STATE_DIR, 'launchctl_session_env_state.json');

const KEYS = [
  'XHUB_RUST_HUB_ROOT',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_THROTTLE_MS',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_MAX_MISMATCHES',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES',
];

const FORBIDDEN_PRODUCTION_KEYS = [
  'XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY',
  'XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY',
];

function parseArgs(argv) {
  const out = {
    mode: 'status',
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
    providerMinCompareReports: 3,
    providerMaxMismatches: 0,
    modelMinCompareReports: 0,
    modelMaxMismatches: 0,
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
      case '--clear-production-env':
        out.mode = 'clear-production-env';
        break;
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
        i += 1;
        break;
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--provider-min-compare-reports':
        out.providerMinCompareReports = parseIntInRange(next, out.providerMinCompareReports, 0, 1000000);
        i += 1;
        break;
      case '--model-min-compare-reports':
        out.modelMinCompareReports = parseIntInRange(next, out.modelMinCompareReports, 0, 1000000);
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

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function usage() {
  return [
    'route_authority_prep_session.js',
    '',
    'Options:',
    '  --status                         Inspect provider/model route prep env',
    '  --apply                          Set provider/model route prep env in user launchd session',
    '  --rollback                       Restore/unset env from previous apply',
    '  --clear-production-env           Unset provider/model production route env only',
    '  --rust-hub-root <p>              Rust Hub root exported to X-Hub/Node',
    '  --http-base-url <u>              Rust xhubd HTTP base URL',
    '  --provider-min-compare-reports <n>',
    '  --model-min-compare-reports <n>',
    '  --self-test                      Run in-memory self-test',
  ].join('\n');
}

function desiredEnv(config) {
  return {
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS: '1000',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT: '2',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS: '750',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_FALLBACK_ON_ERROR: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS: String(config.providerMinCompareReports),
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES: String(config.providerMaxMismatches),
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS: '250',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES: '128',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_THROTTLE_MS: '1000',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT: '2',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS: '750',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS: String(config.modelMinCompareReports),
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_MAX_MISMATCHES: String(config.modelMaxMismatches),
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS: '250',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES: '128',
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
  for (const key of [...KEYS, ...FORBIDDEN_PRODUCTION_KEYS]) out[key] = getEnv(key);
  return out;
}

function inspect(config) {
  const current = snapshot();
  const desired = desiredEnv(config);
  const mismatchKeys = [];
  for (const [key, value] of Object.entries(desired)) {
    if (String(current[key] || '') !== String(value)) mismatchKeys.push(key);
  }
  return {
    applied: mismatchKeys.length === 0,
    managed_key_count_present: Object.values(current).filter((value) => value !== '').length,
    mismatch_keys: mismatchKeys,
    forbidden_production_keys_present: FORBIDDEN_PRODUCTION_KEYS.filter((key) => String(current[key] || '') !== ''),
    provider_prep_enabled: current.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP === '1',
    provider_candidate_enabled: current.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE === '1',
    model_prep_enabled: current.XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP === '1',
    model_candidate_enabled: current.XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE === '1',
    rust_hub_root: current.XHUB_RUST_HUB_ROOT || '',
    http_base_url: current.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL || current.XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL || '',
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
  const config = parseArgs(['--apply', '--rust-hub-root', '/tmp/rust-hub', '--provider-min-compare-reports', '7']);
  const env = desiredEnv(config);
  if (env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP !== '1') throw new Error('provider prep env missing');
  if (env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP !== '1') throw new Error('model prep env missing');
  if (env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS !== '7') throw new Error('threshold override failed');
  if (parseArgs(['--clear-production-env']).mode !== 'clear-production-env') throw new Error('clear production mode failed');
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('route_authority_prep_session self-test ok\n');
    return;
  }

  if (config.mode === 'apply') {
    const previous = snapshot();
    const env = desiredEnv(config);
    for (const [key, value] of Object.entries(env)) setEnv(key, value);
    writeState({
      schema_version: 'xhub.route_authority_prep_session_state.v1',
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
  } else if (config.mode === 'clear-production-env') {
    for (const key of FORBIDDEN_PRODUCTION_KEYS) unsetEnv(key);
  }

  process.stdout.write(`${JSON.stringify({
    ok: true,
    schema_version: 'xhub.route_authority_prep_session.v1',
    mode: config.mode,
    state_file: STATE_FILE,
    apply_performed: config.mode === 'apply',
    rollback_performed: config.mode === 'rollback',
    clear_production_env_performed: config.mode === 'clear-production-env',
    ...inspect(config),
    production_authority_change: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[route_authority_prep_session] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
