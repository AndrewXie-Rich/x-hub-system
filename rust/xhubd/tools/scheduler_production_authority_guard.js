#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');

function parseArgs(argv) {
  const out = {
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
    maxSlowRequests: 0,
    allowMemorySkillsProduction: false,
    requireMemorySkillsProduction: false,
    writeReport: true,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
        i += 1;
        break;
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--max-slow-requests':
        out.maxSlowRequests = Number(next || out.maxSlowRequests);
        i += 1;
        break;
      case '--allow-memory-skills-production':
        out.allowMemorySkillsProduction = true;
        break;
      case '--require-memory-skills-production':
        out.allowMemorySkillsProduction = true;
        out.requireMemorySkillsProduction = true;
        break;
      case '--no-report':
        out.writeReport = false;
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
    'scheduler_production_authority_guard.js',
    '',
    'Options:',
    '  --rust-hub-root <p>       Expected Rust Hub root exported to X-Hub/Node',
    '  --http-base-url <u>       Expected Rust xhubd HTTP base URL',
    '  --max-slow-requests <n>   Recent slow request budget, default 0',
    '  --allow-memory-skills-production Permit explicit Rust memory writer and skills execution authority',
    '  --require-memory-skills-production Require both Rust memory writer and skills execution authority',
    '  --no-report               Print only; do not write reports/',
    '  --self-test               Validate guard reducer logic',
  ].join('\n');
}

function runJson(command, args, options = {}) {
  const output = execFileSync(command, args, {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
  return JSON.parse(output);
}

function runText(command, args) {
  return execFileSync(command, args, {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
}

function collect(config) {
  const session = runJson('bash', [
    path.join(SCRIPT_DIR, 'scheduler_production_authority_session.command'),
    '--status',
    '--rust-hub-root',
    config.rustHubRoot,
    '--http-base-url',
    config.httpBaseUrl,
  ]);
  const sessionLaunchd = runJson('bash', [
    path.join(SCRIPT_DIR, 'scheduler_production_authority_session_launchd.command'),
    '--status',
    '--rust-hub-root',
    config.rustHubRoot,
    '--http-base-url',
    config.httpBaseUrl,
  ]);
  const daemonOpsArgs = [
    path.join(SCRIPT_DIR, 'daemon_ops_gate.command'),
    '--max-slow-requests',
    String(config.maxSlowRequests),
    '--maintenance-max-log-bytes',
    '10485760',
    '--keep-report-files',
    '100',
    '--max-report-age-days',
    '30',
  ];
  if (config.requireMemorySkillsProduction) {
    daemonOpsArgs.push('--require-memory-skills-production');
  } else if (config.allowMemorySkillsProduction) {
    daemonOpsArgs.push('--allow-memory-skills-production');
  }
  const daemonOps = runJson('bash', daemonOpsArgs);
  const ui = runJson('bash', [
    path.join(SCRIPT_DIR, 'ui_compatibility_no_product_ui_change_gate.command'),
  ]);
  const doctorText = runText(resolveXhubd(), ['doctor']);
  return { session, sessionLaunchd, daemonOps, ui, doctor_ok: doctorText.includes('mirrored_proto=ok') };
}

function resolveXhubd() {
  const packaged = path.join(ROOT_DIR, 'bin', 'xhubd');
  if (fs.existsSync(packaged)) return packaged;
  return path.join(ROOT_DIR, 'target', 'release', 'xhubd');
}

function reduce(collected, config) {
  const issues = [];
  const schedulerAuthorityInRust = collected.daemonOps?.status?.readiness?.capabilities?.scheduler_authority_in_rust === true
    || collected.daemonOps?.launchd_status?.readiness?.capabilities?.scheduler_authority_in_rust === true;
  const sessionEffective = Boolean(collected.session?.production_authority_effective_now);
  const nodeCompatibilityRequired = Boolean(collected.session?.node_compatibility_layer_required);
  const runningNodeProcessPid = Number(collected.session?.running_node_process_pid || 0);
  const runningNodeProcessAuthorityEnabled = Boolean(collected.session?.running_node_process_authority_enabled);
  if (!schedulerAuthorityInRust && !sessionEffective) {
    issues.push('scheduler_authority_not_effective_in_running_node_process');
  }
  if (
    !schedulerAuthorityInRust
    && !sessionEffective
    && (nodeCompatibilityRequired || runningNodeProcessPid > 0)
    && !runningNodeProcessAuthorityEnabled
  ) {
    issues.push('running_node_process_scheduler_authority_missing');
  }
  if (!collected.session?.launchctl_session_applied) issues.push('launchctl_scheduler_session_env_not_applied');
  if (!collected.session?.session_env_persistent_for_future_launches) issues.push('session_env_not_persistent_for_future_launches');
  if (!collected.sessionLaunchd?.production_authority_persistence_installed) issues.push('scheduler_authority_session_launchd_not_installed');
  if (!collected.sessionLaunchd?.loaded) issues.push('scheduler_authority_session_launchd_not_loaded');
  if (!collected.daemonOps?.healthy || !collected.daemonOps?.ready) issues.push('rust_daemon_not_ready');
  if (!collected.daemonOps?.slow_request_budget_ok) issues.push('rust_daemon_slow_request_budget_exceeded');
  if (!collected.daemonOps?.http_metrics_ready) issues.push('rust_daemon_http_metrics_not_ready');
  if (collected.ui?.product_ui_change) issues.push('product_ui_changed');
  if (collected.ui?.swift_ui_files_touched) issues.push('swift_ui_files_touched');
  if (!collected.doctor_ok) issues.push('xhubd_doctor_failed');
  return {
    ok: issues.length === 0,
    schema_version: 'xhub.scheduler_production_authority_guard.v1',
    generated_at: new Date().toISOString(),
    rust_hub_root: config.rustHubRoot,
    http_base_url: config.httpBaseUrl,
    scheduler_authority_effective_now: schedulerAuthorityInRust
      || Boolean(collected.session?.production_authority_effective_now),
    scheduler_authority_in_rust: schedulerAuthorityInRust,
    scheduler_authority_persistent_for_future_launches: Boolean(collected.session?.session_env_persistent_for_future_launches),
    scheduler_authority_launchd_installed: Boolean(collected.sessionLaunchd?.production_authority_persistence_installed),
    scheduler_authority_launchd_loaded: Boolean(collected.sessionLaunchd?.loaded),
    running_node_process_pid: Number(collected.session?.running_node_process_pid || 0),
    swift_product_shell_pid: Number(collected.session?.swift_product_shell_pid || 0),
    swift_product_shell_running: Boolean(collected.session?.swift_product_shell_running),
    node_compatibility_layer_required: false,
    launchctl_managed_key_count_present: Number(collected.session?.managed_key_count_present || 0),
    daemon_healthy: Boolean(collected.daemonOps?.healthy),
    daemon_ready: Boolean(collected.daemonOps?.ready),
    daemon_recent_slow_requests: Number(collected.daemonOps?.recent_slow_requests || collected.daemonOps?.slow_requests || 0),
    daemon_max_observed_http_elapsed_ms: Number(collected.daemonOps?.max_observed_http_elapsed_ms || 0),
    memory_skills_production_allowed: Boolean(config.allowMemorySkillsProduction),
    memory_skills_production_required: Boolean(config.requireMemorySkillsProduction),
    memory_writer_authority_in_rust: Boolean(collected.daemonOps?.memory_writer_authority_in_rust),
    skills_execution_authority_in_rust: Boolean(collected.daemonOps?.skills_execution_authority_in_rust),
    ui_product_change: Boolean(collected.ui?.product_ui_change),
    swift_ui_files_touched: Boolean(collected.ui?.swift_ui_files_touched),
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    secret_leak: false,
    issues,
  };
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `scheduler_production_authority_guard_${stamp}.json`);
}

function runSelfTest() {
  const result = reduce({
    session: {
      production_authority_effective_now: true,
      running_node_process_authority_enabled: true,
      launchctl_session_applied: true,
      session_env_persistent_for_future_launches: true,
      running_node_process_pid: 1,
      swift_product_shell_pid: 2,
      swift_product_shell_running: true,
      managed_key_count_present: 28,
    },
    sessionLaunchd: { production_authority_persistence_installed: true, loaded: true },
    daemonOps: { healthy: true, ready: true, slow_request_budget_ok: true, http_metrics_ready: true },
    ui: { product_ui_change: false, swift_ui_files_touched: false },
    doctor_ok: true,
  }, {
    rustHubRoot: '/tmp/rust-hub',
    httpBaseUrl: 'http://127.0.0.1:50151',
    allowMemorySkillsProduction: true,
    requireMemorySkillsProduction: true,
  });
  if (!result.ok) throw new Error(`expected self-test ok: ${result.issues.join(',')}`);
  if (!result.memory_skills_production_required) throw new Error('expected memory/skills requirement to round-trip');
  const swiftShellOnly = reduce({
    session: {
      production_authority_effective_now: true,
      running_node_process_authority_enabled: false,
      node_compatibility_layer_required: false,
      launchctl_session_applied: true,
      session_env_persistent_for_future_launches: true,
      running_node_process_pid: 0,
      swift_product_shell_pid: 2,
      swift_product_shell_running: true,
      managed_key_count_present: 28,
    },
    sessionLaunchd: { production_authority_persistence_installed: true, loaded: true },
    daemonOps: { healthy: true, ready: true, slow_request_budget_ok: true, http_metrics_ready: true },
    ui: { product_ui_change: false, swift_ui_files_touched: false },
    doctor_ok: true,
  }, {
    rustHubRoot: '/tmp/rust-hub',
    httpBaseUrl: 'http://127.0.0.1:50151',
    allowMemorySkillsProduction: true,
    requireMemorySkillsProduction: true,
  });
  if (!swiftShellOnly.ok) {
    throw new Error(`expected Swift-shell-only scheduler authority to pass: ${swiftShellOnly.issues.join(',')}`);
  }
  const rustOnly = reduce({
    session: {
      production_authority_effective_now: false,
      running_node_process_authority_enabled: false,
      launchctl_session_applied: true,
      session_env_persistent_for_future_launches: true,
      running_node_process_pid: 0,
      swift_product_shell_pid: 2,
      swift_product_shell_running: true,
      managed_key_count_present: 28,
    },
    sessionLaunchd: { production_authority_persistence_installed: true, loaded: true },
    daemonOps: {
      healthy: true,
      ready: true,
      slow_request_budget_ok: true,
      http_metrics_ready: true,
      status: { readiness: { capabilities: { scheduler_authority_in_rust: true } } },
    },
    ui: { product_ui_change: false, swift_ui_files_touched: false },
    doctor_ok: true,
  }, {
    rustHubRoot: '/tmp/rust-hub',
    httpBaseUrl: 'http://127.0.0.1:50151',
    allowMemorySkillsProduction: true,
    requireMemorySkillsProduction: true,
  });
  if (!rustOnly.ok || rustOnly.scheduler_authority_in_rust !== true) {
    throw new Error(`expected Rust-only scheduler authority to pass: ${rustOnly.issues.join(',')}`);
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
    process.stdout.write('scheduler_production_authority_guard self-test ok\n');
    return;
  }
  const result = reduce(collect(config), config);
  if (config.writeReport) {
    fs.mkdirSync(REPORT_DIR, { recursive: true });
    const pathOut = reportPath();
    fs.writeFileSync(pathOut, `${JSON.stringify(result, null, 2)}\n`);
    result.report_path = pathOut;
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.ok) process.exit(2);
}

main().catch((error) => {
  process.stderr.write(`[scheduler_production_authority_guard] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
