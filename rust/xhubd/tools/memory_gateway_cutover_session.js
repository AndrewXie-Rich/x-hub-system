#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'memory_gateway_cutover');
const STATE_FILE = path.join(STATE_DIR, 'launchctl_session_env_state.json');
const DEFAULT_PARITY_MAX_AGE_MS = 10 * 60 * 1000;
const DEFAULT_REPORT_MAX_AGE_MS = 10 * 60 * 1000;

const KEYS = [
  'XHUB_RUST_HUB_ROOT',
  'XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW',
  'XHUB_RUST_MEMORY_CONTEXT_GATEWAY',
  'XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE',
  'XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS',
];

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    mode: 'status',
    cutoverMode: 'primary',
    rustHubRoot: ROOT_DIR,
    readinessReport: '',
    reportMaxAgeMs: DEFAULT_REPORT_MAX_AGE_MS,
    parityMaxAgeMs: DEFAULT_PARITY_MAX_AGE_MS,
    confirmMemoryGatewayCutover: false,
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
      case '--shadow':
        out.cutoverMode = 'shadow';
        break;
      case '--primary':
        out.cutoverMode = 'primary';
        break;
      case '--require':
        out.cutoverMode = 'require';
        break;
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
        i += 1;
        break;
      case '--readiness-report':
        out.readinessReport = String(next || '').trim();
        i += 1;
        break;
      case '--report-max-age-ms':
        out.reportMaxAgeMs = parseIntInRange(next, out.reportMaxAgeMs, 0, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--parity-max-age-ms':
        out.parityMaxAgeMs = parseIntInRange(next, out.parityMaxAgeMs, 0, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--confirm-memory-gateway-cutover':
        out.confirmMemoryGatewayCutover = true;
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
    'memory_gateway_cutover_session.js',
    '',
    'Options:',
    '  --status                         Inspect Memory Gateway cutover env (default)',
    '  --apply                          Set Memory Gateway cutover env in user launchd session',
    '  --rollback                       Restore/unset env from previous apply',
    '  --shadow                         Enable shadow compare only',
    '  --primary                        Enable Rust gateway as primary with compatibility fallback (default)',
    '  --require                        Enable fail-closed required Rust gateway after evidence preflight',
    '  --rust-hub-root <p>              Rust Hub root exported to X-Hub/XT',
    '  --readiness-report <p>           Explicit memory_gateway_cutover_readiness.json',
    '  --report-max-age-ms <n>          Required report freshness for --require, default 600000',
    '  --parity-max-age-ms <n>          XT same-scope parity max age, default 600000',
    '  --confirm-memory-gateway-cutover Required with --apply',
    '  --dry-run                        Validate apply preflight without writing env',
    '  --self-test                      Run in-memory self-test',
  ].join('\n');
}

function desiredEnv(config) {
  const base = {
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS: String(config.parityMaxAgeMs),
  };
  if (config.cutoverMode === 'shadow') {
    return {
      ...base,
      XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW: '1',
    };
  }
  if (config.cutoverMode === 'require') {
    return {
      ...base,
      XHUB_RUST_MEMORY_CONTEXT_GATEWAY: '1',
      XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE: '1',
    };
  }
  return {
    ...base,
    XHUB_RUST_MEMORY_CONTEXT_GATEWAY: '1',
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

function activeMode(current) {
  if (current.XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE === '1') return 'require';
  if (current.XHUB_RUST_MEMORY_CONTEXT_GATEWAY === '1') return 'primary';
  if (current.XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW === '1') return 'shadow';
  return 'off';
}

function inspect(config) {
  const current = snapshot();
  const desired = desiredEnv(config);
  const mismatchKeys = [];
  for (const key of KEYS) {
    const expected = Object.prototype.hasOwnProperty.call(desired, key) ? String(desired[key]) : '';
    if (String(current[key] || '') !== expected) mismatchKeys.push(key);
  }
  return {
    applied: mismatchKeys.length === 0,
    managed_key_count_present: Object.values(current).filter((value) => value !== '').length,
    mismatch_keys: mismatchKeys,
    desired_mode: config.cutoverMode,
    active_mode: activeMode(current),
    rust_hub_root: current.XHUB_RUST_HUB_ROOT || '',
    shadow_enabled: current.XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW === '1',
    primary_enabled: current.XHUB_RUST_MEMORY_CONTEXT_GATEWAY === '1',
    require_enabled: current.XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE === '1',
    parity_max_age_ms: Number(current.XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS || 0),
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

function candidateReadinessPaths(config) {
  const home = os.homedir();
  const fileName = 'memory_gateway_cutover_readiness.json';
  const paths = [];
  if (config.readinessReport) paths.push(path.resolve(config.readinessReport));
  paths.push(path.join(ROOT_DIR, fileName));
  paths.push(path.join(home, 'Library', 'Application Support', 'AX', 'rust-hub', 'domain', fileName));
  paths.push(path.join(home, 'Library', 'Application Support', 'AX', 'rust-hub', 'local', fileName));
  paths.push(path.join(home, 'Library', 'Group Containers', 'group.rel.flowhub', fileName));
  return [...new Set(paths)];
}

function blockingIssueCodes(report) {
  if (!Array.isArray(report?.issues)) return [];
  return report.issues
    .filter((issue) => issue?.blocking !== false)
    .map((issue) => String(issue?.code || '').trim())
    .filter(Boolean);
}

function validateReadinessReportPayload(report, config, now = Date.now()) {
  const issues = [];
  if (report?.schema_version !== 'xt.rust_memory_gateway_cutover_readiness.v1') {
    issues.push('memory_gateway_cutover_readiness_schema_mismatch');
  }
  if (report?.ok !== true || report?.ready_for_require !== true) {
    issues.push('memory_gateway_cutover_readiness_not_ready');
  }
  const generatedAtMs = Number(report?.generated_at_ms || 0);
  if (!Number.isFinite(generatedAtMs) || generatedAtMs <= 0) {
    issues.push('memory_gateway_cutover_readiness_missing_generated_at_ms');
  } else if (config.reportMaxAgeMs > 0 && Math.max(0, now - generatedAtMs) > config.reportMaxAgeMs) {
    issues.push('memory_gateway_cutover_readiness_stale');
  }
  const requiredSamples = Number(report?.required_sample_count || 0);
  const passingSamples = Number(report?.passing_sample_count || 0);
  if (requiredSamples < 1 || passingSamples < requiredSamples) {
    issues.push('memory_gateway_cutover_readiness_insufficient_passing_samples');
  }
  if (Number(report?.authority_violation_count || 0) > 0) {
    issues.push('memory_gateway_cutover_authority_violation');
  }
  if (Number(report?.parity_failure_count || 0) > 0) {
    issues.push('memory_gateway_cutover_parity_failure');
  }
  if (Number(report?.rust_source_mismatch_count || 0) > 0) {
    issues.push('memory_gateway_cutover_source_mismatch');
  }
  issues.push(...blockingIssueCodes(report));
  return {
    ok: issues.length === 0,
    issues: [...new Set(issues)],
    schema_version: String(report?.schema_version || ''),
    ready_for_require: report?.ready_for_require === true,
    generated_at_ms: generatedAtMs,
    age_ms: generatedAtMs > 0 ? Math.max(0, now - generatedAtMs) : 0,
    required_sample_count: requiredSamples,
    passing_sample_count: passingSamples,
    requester_role: String(report?.requester_role || ''),
    use_mode: String(report?.use_mode || ''),
    project_id: String(report?.project_id || ''),
  };
}

function validateReadinessReport(config) {
  const candidates = candidateReadinessPaths(config);
  const found = candidates.find((item) => fs.existsSync(item));
  if (!found) {
    return {
      ok: false,
      path: '',
      candidate_paths: candidates,
      issues: ['memory_gateway_cutover_readiness_missing'],
    };
  }
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(found, 'utf8'));
  } catch {
    return {
      ok: false,
      path: found,
      candidate_paths: candidates,
      issues: ['memory_gateway_cutover_readiness_not_parseable'],
    };
  }
  return {
    path: found,
    candidate_paths: candidates,
    ...validateReadinessReportPayload(payload, config),
  };
}

function requireApplyPreflight(config) {
  const issues = [];
  if (config.confirmMemoryGatewayCutover !== true) {
    issues.push('confirm_memory_gateway_cutover_required');
  }
  const readiness = validateReadinessReport(config);
  if (config.cutoverMode === 'require' && !readiness.ok) {
    issues.push(...readiness.issues);
  }
  return {
    ok: issues.length === 0,
    issues: [...new Set(issues)],
    memory_gateway_cutover_readiness: readiness,
  };
}

function applyDesiredEnv(config) {
  const env = desiredEnv(config);
  for (const key of KEYS) {
    if (Object.prototype.hasOwnProperty.call(env, key)) setEnv(key, String(env[key]));
    else unsetEnv(key);
  }
}

function runSelfTest() {
  const primary = parseArgs(['--apply', '--primary', '--rust-hub-root', '/tmp/rust-hub']);
  const primaryEnv = desiredEnv(primary);
  if (primaryEnv.XHUB_RUST_MEMORY_CONTEXT_GATEWAY !== '1') throw new Error('primary env missing');
  if (primaryEnv.XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE) throw new Error('primary must not enable require');
  const require = parseArgs(['--apply', '--require', '--rust-hub-root', '/tmp/rust-hub']);
  const requireEnv = desiredEnv(require);
  if (requireEnv.XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE !== '1') throw new Error('require env missing');
  if (parseArgs(['--apply', '--dry-run']).dryRun !== true) throw new Error('dry-run parser failed');
  const valid = validateReadinessReportPayload({
    schema_version: 'xt.rust_memory_gateway_cutover_readiness.v1',
    ok: true,
    ready_for_require: true,
    generated_at_ms: Date.now(),
    required_sample_count: 3,
    passing_sample_count: 3,
    authority_violation_count: 0,
    parity_failure_count: 0,
    rust_source_mismatch_count: 0,
    issues: [],
  }, require);
  if (!valid.ok) throw new Error(`valid readiness rejected: ${valid.issues.join(',')}`);
  const stale = validateReadinessReportPayload({
    schema_version: 'xt.rust_memory_gateway_cutover_readiness.v1',
    ok: true,
    ready_for_require: true,
    generated_at_ms: Date.now() - 60 * 60 * 1000,
    required_sample_count: 3,
    passing_sample_count: 3,
    authority_violation_count: 0,
    parity_failure_count: 0,
    rust_source_mismatch_count: 0,
    issues: [],
  }, require);
  if (stale.ok || !stale.issues.includes('memory_gateway_cutover_readiness_stale')) {
    throw new Error('stale readiness must be rejected');
  }
  const missingConfirm = requireApplyPreflight(primary);
  if (missingConfirm.ok || !missingConfirm.issues.includes('confirm_memory_gateway_cutover_required')) {
    throw new Error('apply preflight must require explicit confirmation');
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
    process.stdout.write('memory_gateway_cutover_session self-test ok\n');
    return;
  }

  let preflight = null;
  if (config.mode === 'apply') {
    preflight = requireApplyPreflight(config);
    if (!preflight.ok) {
      process.stdout.write(`${JSON.stringify({
        ok: false,
        schema_version: 'xhub.memory_gateway_cutover_session.v1',
        mode: config.mode,
        cutover_mode: config.cutoverMode,
        dry_run: config.dryRun,
        apply_performed: false,
        rollback_performed: false,
        production_authority_change: false,
        memory_gateway_primary_target: config.cutoverMode === 'primary' || config.cutoverMode === 'require',
        memory_gateway_require_target: config.cutoverMode === 'require',
        memory_gateway_cutover_readiness: preflight.memory_gateway_cutover_readiness,
        issues: preflight.issues,
      }, null, 2)}\n`);
      process.exit(2);
    }
    if (config.dryRun) {
      process.stdout.write(`${JSON.stringify({
        ok: true,
        schema_version: 'xhub.memory_gateway_cutover_session.v1',
        mode: config.mode,
        cutover_mode: config.cutoverMode,
        dry_run: true,
        apply_performed: false,
        rollback_performed: false,
        production_authority_change_planned: config.cutoverMode !== 'shadow',
        production_authority_change: false,
        memory_gateway_primary_target: config.cutoverMode === 'primary' || config.cutoverMode === 'require',
        memory_gateway_require_target: config.cutoverMode === 'require',
        memory_gateway_cutover_readiness: preflight.memory_gateway_cutover_readiness,
        ...inspect(config),
        issues: [],
      }, null, 2)}\n`);
      return;
    }
    const previous = snapshot();
    applyDesiredEnv(config);
    writeState({
      schema_version: 'xhub.memory_gateway_cutover_session_state.v1',
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
    schema_version: 'xhub.memory_gateway_cutover_session.v1',
    mode: config.mode,
    cutover_mode: config.cutoverMode,
    state_file: STATE_FILE,
    dry_run: config.dryRun,
    apply_performed: config.mode === 'apply',
    rollback_performed: config.mode === 'rollback',
    confirm_memory_gateway_cutover: config.confirmMemoryGatewayCutover,
    memory_gateway_cutover_readiness: config.mode === 'apply' ? (preflight?.memory_gateway_cutover_readiness || validateReadinessReport(config)) : validateReadinessReport(config),
    ...inspect(config),
    production_authority_change: config.mode === 'apply' && config.cutoverMode !== 'shadow',
    memory_gateway_primary_target: config.mode === 'apply' && (config.cutoverMode === 'primary' || config.cutoverMode === 'require'),
    memory_gateway_require_target: config.mode === 'apply' && config.cutoverMode === 'require',
    ui_product_change: false,
    secret_leak: false,
    issues: [],
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[memory_gateway_cutover_session] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
