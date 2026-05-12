#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'route_authority_production');
const STATE_FILE = path.join(STATE_DIR, 'launchctl_session_env_state.json');
const DEFAULT_PREP_SOAK_REPORT_MAX_AGE_MS = 60 * 60 * 1000;

const KEYS = [
  'XHUB_RUST_HUB_ROOT',
  'XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY',
  'XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
];

function parseArgs(argv) {
  const out = {
    mode: 'status',
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
    prepSustainedReport: '',
    prepSustainedReportMaxAgeMs: DEFAULT_PREP_SOAK_REPORT_MAX_AGE_MS,
    minSoakCycles: 3,
    confirmProviderModelProductionAuthority: false,
    dryRun: false,
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
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--prep-sustained-report':
        out.prepSustainedReport = String(next || '').trim();
        i += 1;
        break;
      case '--prep-sustained-report-max-age-ms':
        out.prepSustainedReportMaxAgeMs = parseIntInRange(next, out.prepSustainedReportMaxAgeMs, 1000, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--min-soak-cycles':
        out.minSoakCycles = parseIntInRange(next, out.minSoakCycles, 1, 1000000);
        i += 1;
        break;
      case '--confirm-provider-model-production-authority':
        out.confirmProviderModelProductionAuthority = true;
        break;
      case '--dry-run':
        out.dryRun = true;
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
    'route_authority_production_session.js',
    '',
    'Options:',
    '  --status              Inspect provider/model production env',
    '  --apply               Set provider/model production env in user launchd session',
    '  --rollback            Restore/unset env from previous apply',
    '  --rust-hub-root <p>   Rust Hub root exported to X-Hub/Node',
    '  --http-base-url <u>   Rust xhubd HTTP base URL',
    '  --prep-sustained-report <p> Required fresh prep sustained report for apply',
    '  --prep-sustained-report-max-age-ms <n> Report freshness window, default 3600000',
    '  --min-soak-cycles <n>  Required successful sustained cycles, default 3',
    '  --confirm-provider-model-production-authority Required for apply',
    '  --dry-run              Validate apply preflight without writing env',
    '  --self-test           Run in-memory self-test',
  ].join('\n');
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function desiredEnv(config) {
  return {
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY: '1',
    XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_FALLBACK_ON_ERROR: '0',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR: '0',
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
  const mismatchKeys = [];
  for (const [key, value] of Object.entries(desired)) {
    if (String(current[key] || '') !== String(value)) mismatchKeys.push(key);
  }
  return {
    applied: mismatchKeys.length === 0,
    managed_key_count_present: Object.values(current).filter((value) => value !== '').length,
    mismatch_keys: mismatchKeys,
    provider_production_enabled: current.XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY === '1',
    model_production_enabled: current.XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY === '1',
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

function validatePrepSustainedReportPayload(payload, config, now = Date.now()) {
  const issues = [];
  if (payload?.schema_version !== 'xhub.route_authority_prep_sustained_guard.v1') issues.push('prep_sustained_report_schema_mismatch');
  if (payload?.ok !== true) issues.push('prep_sustained_report_not_ok');
  if (payload?.all_cycles_ok !== true) issues.push('prep_sustained_cycles_not_all_ok');
  if (Number(payload?.cycles_completed || 0) < Number(config.minSoakCycles || 3)) issues.push('prep_sustained_cycles_below_minimum');
  if (Number(payload?.daemon_recent_slow_requests || 0) !== 0) issues.push('prep_sustained_daemon_slow_requests_present');
  if (Array.isArray(payload?.daemon_recent_slow_routes) && payload.daemon_recent_slow_routes.length > 0) {
    issues.push('prep_sustained_daemon_slow_routes_present');
  }
  if (Array.isArray(payload?.issues) && payload.issues.length > 0) issues.push('prep_sustained_report_has_issues');
  if (payload?.production_authority_change !== false) issues.push('prep_sustained_report_changed_production_authority');
  if (payload?.provider_route_authority_target !== false) issues.push('prep_sustained_provider_authority_target_not_false');
  if (payload?.model_route_authority_target !== false) issues.push('prep_sustained_model_authority_target_not_false');
  if (payload?.memory_writer_authority_target !== false) issues.push('prep_sustained_memory_writer_target_not_false');
  if (payload?.skills_execution_authority_target !== false) issues.push('prep_sustained_skills_execution_target_not_false');
  if (payload?.ui_product_change !== false) issues.push('prep_sustained_ui_product_change');
  if (payload?.secret_leak !== false) issues.push('prep_sustained_secret_leak');
  const generatedAtMs = Date.parse(String(payload?.generated_at || payload?.generated_at_iso || ''));
  if (!Number.isFinite(generatedAtMs)) {
    issues.push('prep_sustained_report_missing_generated_at');
  } else if (Math.max(0, now - generatedAtMs) > Number(config.prepSustainedReportMaxAgeMs || DEFAULT_PREP_SOAK_REPORT_MAX_AGE_MS)) {
    issues.push('prep_sustained_report_stale');
  }
  return {
    ok: issues.length === 0,
    issues,
    cycles_completed: Number(payload?.cycles_completed || 0),
    daemon_recent_slow_requests: Number(payload?.daemon_recent_slow_requests || 0),
    generated_at: String(payload?.generated_at || payload?.generated_at_iso || ''),
  };
}

function validatePrepSustainedReport(config) {
  const reportPath = String(config.prepSustainedReport || '').trim();
  if (!reportPath) {
    return { ok: false, issues: ['prep_sustained_report_required'], path: '' };
  }
  if (!fs.existsSync(reportPath)) {
    return { ok: false, issues: ['prep_sustained_report_missing'], path: reportPath };
  }
  let payload = null;
  try {
    payload = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
  } catch {
    return { ok: false, issues: ['prep_sustained_report_not_parseable'], path: reportPath };
  }
  return {
    path: reportPath,
    ...validatePrepSustainedReportPayload(payload, config),
  };
}

function requireApplyPreflight(config) {
  const issues = [];
  if (config.confirmProviderModelProductionAuthority !== true) {
    issues.push('confirm_provider_model_production_authority_required');
  }
  const prep = validatePrepSustainedReport(config);
  if (!prep.ok) issues.push(...prep.issues);
  return { ok: issues.length === 0, issues, prep_sustained_report: prep };
}

function runSelfTest() {
  const config = parseArgs(['--apply', '--rust-hub-root', '/tmp/rust-hub']);
  const env = desiredEnv(config);
  if (env.XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY !== '1') throw new Error('provider production env missing');
  if (env.XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY !== '1') throw new Error('model production env missing');
  if (env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY !== '1') throw new Error('provider require-ready missing');
  if (env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR !== '0') throw new Error('model fallback must be disabled for production');
  if (parseArgs(['--apply', '--dry-run']).dryRun !== true) throw new Error('dry-run parser failed');
  const missingConfirm = requireApplyPreflight(config);
  if (missingConfirm.ok || !missingConfirm.issues.includes('confirm_provider_model_production_authority_required')) {
    throw new Error('apply preflight must require explicit confirmation');
  }
  const validReport = validatePrepSustainedReportPayload({
    schema_version: 'xhub.route_authority_prep_sustained_guard.v1',
    ok: true,
    generated_at: new Date().toISOString(),
    cycles_completed: 3,
    all_cycles_ok: true,
    daemon_recent_slow_requests: 0,
    daemon_recent_slow_routes: [],
    issues: [],
    production_authority_change: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  }, config);
  if (!validReport.ok) throw new Error(`valid prep report rejected: ${validReport.issues.join(',')}`);
  const slowReport = validatePrepSustainedReportPayload({
    schema_version: 'xhub.route_authority_prep_sustained_guard.v1',
    ok: true,
    generated_at: new Date().toISOString(),
    cycles_completed: 3,
    all_cycles_ok: true,
    daemon_recent_slow_requests: 1,
    daemon_recent_slow_routes: [{ route: '/xt/classic-hub-compat', slow_count: 1 }],
    issues: [],
    production_authority_change: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  }, config);
  if (slowReport.ok || !slowReport.issues.includes('prep_sustained_daemon_slow_requests_present')) {
    throw new Error('slow prep report must be rejected');
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
    process.stdout.write('route_authority_production_session self-test ok\n');
    return;
  }

  if (config.mode === 'apply') {
    const preflight = requireApplyPreflight(config);
    if (!preflight.ok) {
      process.stdout.write(`${JSON.stringify({
        ok: false,
        schema_version: 'xhub.route_authority_production_session.v1',
        mode: config.mode,
        apply_performed: false,
        rollback_performed: false,
        production_authority_change: false,
        provider_route_authority_target: false,
        model_route_authority_target: false,
        memory_writer_authority_target: false,
        skills_execution_authority_target: false,
        ui_product_change: false,
        secret_leak: false,
        prep_sustained_report: preflight.prep_sustained_report,
        issues: preflight.issues,
      }, null, 2)}\n`);
      process.exit(2);
    }
    if (config.dryRun) {
      process.stdout.write(`${JSON.stringify({
        ok: true,
        schema_version: 'xhub.route_authority_production_session.v1',
        mode: config.mode,
        dry_run: true,
        apply_performed: false,
        rollback_performed: false,
        production_authority_change_planned: true,
        production_authority_change: false,
        provider_route_authority_target: true,
        model_route_authority_target: true,
        memory_writer_authority_target: false,
        skills_execution_authority_target: false,
        ui_product_change: false,
        secret_leak: false,
        confirm_provider_model_production_authority: config.confirmProviderModelProductionAuthority,
        prep_sustained_report: preflight.prep_sustained_report,
        ...inspect(config),
        issues: [],
      }, null, 2)}\n`);
      return;
    }
    const previous = snapshot();
    const env = desiredEnv(config);
    for (const [key, value] of Object.entries(env)) setEnv(key, value);
    writeState({
      schema_version: 'xhub.route_authority_production_session_state.v1',
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

  process.stdout.write(`${JSON.stringify({
    ok: true,
    schema_version: 'xhub.route_authority_production_session.v1',
    mode: config.mode,
    state_file: STATE_FILE,
    dry_run: config.dryRun,
    apply_performed: config.mode === 'apply',
    rollback_performed: config.mode === 'rollback',
    confirm_provider_model_production_authority: config.confirmProviderModelProductionAuthority,
    prep_sustained_report: config.mode === 'apply' ? validatePrepSustainedReport(config) : null,
    ...inspect(config),
    production_authority_change: config.mode === 'apply',
    provider_route_authority_target: config.mode === 'apply',
    model_route_authority_target: config.mode === 'apply',
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[route_authority_production_session] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
