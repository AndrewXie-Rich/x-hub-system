#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const NODE_PROCESS_MARKERS = ['hub_grpc_server/src/server.js', 'relflowhub_node'];

const PROVIDER_MODEL_PRODUCTION_KEYS = [
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

const SCHEDULER_AUTHORITY_KEYS = [
  'XHUB_RUST_SCHEDULER_STATUS_READ',
  'XHUB_RUST_SCHEDULER_STATUS_HTTP',
  'XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL',
  'XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP',
  'XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL',
  'XHUB_RUST_SCHEDULER_AUTHORITY',
  'XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_SCHEDULER_AUTHORITY_HTTP',
  'XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL',
];

const UNRELATED_PRODUCTION_KEYS = [
  'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER',
  'XHUB_RUST_MEMORY_WRITER_AUTHORITY',
  'XHUB_RUST_MEMORY_WRITE_AUTHORITY',
  'XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY',
  'XHUB_RUST_SKILLS_EXECUTION_AUTHORITY',
  'XHUB_RUST_SKILLS_PRODUCTION_EXECUTION',
  'XHUB_RUST_SKILLS_EXECUTION_PRODUCTION',
  'XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY',
];

const READ_KEYS = [
  ...PROVIDER_MODEL_PRODUCTION_KEYS,
  ...SCHEDULER_AUTHORITY_KEYS,
  ...UNRELATED_PRODUCTION_KEYS,
];

function parseArgs(argv) {
  const out = {
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
    writeReport: true,
    requireSchedulerAuthority: true,
    allowXtFileIpcProduction: true,
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
      case '--skip-scheduler-check':
        out.requireSchedulerAuthority = false;
        break;
      case '--allow-xt-file-ipc-production':
        out.allowXtFileIpcProduction = true;
        break;
      case '--fail-on-xt-file-ipc-production':
        out.allowXtFileIpcProduction = false;
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
    'route_authority_production_runtime_guard.js',
    '',
    'Options:',
    '  --rust-hub-root <p>              Expected active Rust Hub root',
    '  --http-base-url <u>              Expected xhubd HTTP base URL',
    '  --skip-scheduler-check           Do not require scheduler authority env',
    '  --allow-xt-file-ipc-production   Do not fail when XT file IPC live key is present (default)',
    '  --fail-on-xt-file-ipc-production Fail when XT file IPC live key is present',
    '  --no-report                      Print only; do not write reports/',
    '  --self-test                      Validate reducer logic',
  ].join('\n');
}

function providerModelExpected(config) {
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

function schedulerExpected(config) {
  return {
    XHUB_RUST_SCHEDULER_STATUS_READ: '1',
    XHUB_RUST_SCHEDULER_STATUS_HTTP: '1',
    XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP: '1',
    XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_SCHEDULER_AUTHORITY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
  };
}

function readLaunchctlSession() {
  const values = {};
  for (const key of READ_KEYS) {
    try {
      values[key] = execFileSync('launchctl', ['getenv', key], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      }).trim();
    } catch {
      values[key] = '';
    }
  }
  return values;
}

function findNodeProcess() {
  const rows = execFileSync('ps', ['axeww', '-o', 'pid=,command='], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 8 * 1024 * 1024,
  }).split('\n');
  const candidates = rows
    .map((line) => line.trim())
    .filter((line) => NODE_PROCESS_MARKERS.every((marker) => line.includes(marker)))
    .filter((line) => !line.includes('route_authority_production_runtime_guard.js'));
  if (candidates.length === 0) return { pid: 0, command: '' };
  const parsed = candidates
    .map((line) => {
      const match = line.match(/^(\d+)\s+([\s\S]*)$/);
      if (!match) return null;
      return { pid: Number(match[1]), command: match[2] };
    })
    .filter(Boolean)
    .sort((a, b) => b.pid - a.pid)[0];
  return parsed || { pid: 0, command: '' };
}

function parseProcessEnv(line) {
  const values = {};
  for (const key of READ_KEYS) {
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

function processXhubRustKeys(line) {
  const keys = new Set();
  const regex = /(?:^| )((?:XHUB_RUST|HUB_RUST)_[A-Z0-9_]+)=/g;
  let match = regex.exec(String(line || ''));
  while (match) {
    keys.add(match[1]);
    match = regex.exec(String(line || ''));
  }
  return [...keys].sort();
}

function inferredUnrelatedProductionKeys(keys, config) {
  return keys.filter((key) => {
    if (!/^XHUB_RUST_/.test(key)) return false;
    if (PROVIDER_MODEL_PRODUCTION_KEYS.includes(key)) return false;
    if (SCHEDULER_AUTHORITY_KEYS.includes(key)) return false;
    if (config.allowXtFileIpcProduction && key === 'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER') return false;
    if (UNRELATED_PRODUCTION_KEYS.includes(key)) return true;
    if (/XT_FILE_IPC/.test(key)) return /(PRODUCTION|CUTOVER)/.test(key);
    return /(MEMORY|SKILL).*(AUTHOR|PRODUCTION|EXEC|WRITE|CUTOVER)/.test(key);
  });
}

function compare(values, expectedValues) {
  const present = [];
  const missing = [];
  const mismatched = [];
  for (const [key, value] of Object.entries(expectedValues)) {
    if (!Object.prototype.hasOwnProperty.call(values, key) || values[key] === '') {
      missing.push(key);
    } else {
      present.push(key);
      if (String(values[key]) !== String(value)) mismatched.push(key);
    }
  }
  return { present, missing, mismatched };
}

function presentKeys(values, keys, config) {
  return keys.filter((key) => {
    if (config.allowXtFileIpcProduction && key === 'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER') return false;
    return String(values?.[key] || '') !== '';
  });
}

function collect(config) {
  const providerModel = providerModelExpected(config);
  const scheduler = schedulerExpected(config);
  const launchctlValues = readLaunchctlSession();
  const node = findNodeProcess();
  const nodeValues = node.pid ? parseProcessEnv(node.command) : {};
  const nodeXhubRustKeys = node.pid ? processXhubRustKeys(node.command) : [];
  return {
    launchctlProviderModel: compare(launchctlValues, providerModel),
    node,
    nodeProviderModel: node.pid ? compare(nodeValues, providerModel) : { present: [], missing: Object.keys(providerModel), mismatched: [] },
    launchctlScheduler: compare(launchctlValues, scheduler),
    nodeScheduler: node.pid ? compare(nodeValues, scheduler) : { present: [], missing: Object.keys(scheduler), mismatched: [] },
    launchctlUnrelatedProductionKeys: presentKeys(launchctlValues, UNRELATED_PRODUCTION_KEYS, config),
    nodeUnrelatedProductionKeys: [
      ...new Set([
        ...presentKeys(nodeValues, UNRELATED_PRODUCTION_KEYS, config),
        ...inferredUnrelatedProductionKeys(nodeXhubRustKeys, config),
      ]),
    ].sort(),
    nodeXhubRustKeys,
  };
}

function compareOk(compared) {
  return compared.missing.length === 0 && compared.mismatched.length === 0;
}

function reduce(collected, config) {
  const issues = [];
  if (!compareOk(collected.launchctlProviderModel)) issues.push('launchctl_provider_model_production_env_not_applied');
  if (!collected.node.pid) issues.push('xhub_node_process_not_running');
  if (!compareOk(collected.nodeProviderModel)) issues.push('xhub_node_process_needs_relaunch_for_provider_model_production_env');
  if (config.requireSchedulerAuthority && !compareOk(collected.launchctlScheduler)) issues.push('launchctl_scheduler_authority_env_not_applied');
  if (config.requireSchedulerAuthority && !compareOk(collected.nodeScheduler)) issues.push('xhub_node_scheduler_authority_env_missing');
  if (collected.launchctlUnrelatedProductionKeys.length) issues.push('launchctl_unrelated_production_env_present');
  if (collected.nodeUnrelatedProductionKeys.length) issues.push('xhub_node_unrelated_production_env_present');
  return {
    ok: issues.length === 0,
    schema_version: 'xhub.route_authority_production_runtime_guard.v1',
    generated_at: new Date().toISOString(),
    rust_hub_root: config.rustHubRoot,
    http_base_url: config.httpBaseUrl,
    require_scheduler_authority: config.requireSchedulerAuthority,
    provider_model_production_authority_effective_now: compareOk(collected.nodeProviderModel),
    launchctl_provider_model_production_session_applied: compareOk(collected.launchctlProviderModel),
    running_node_process_pid: collected.node.pid,
    running_node_provider_model_production_env_applied: compareOk(collected.nodeProviderModel),
    running_node_provider_model_env_present: collected.nodeProviderModel.present,
    running_node_provider_model_env_missing: collected.nodeProviderModel.missing,
    running_node_provider_model_env_mismatched: collected.nodeProviderModel.mismatched,
    scheduler_authority_effective_now: compareOk(collected.nodeScheduler),
    launchctl_scheduler_authority_session_applied: compareOk(collected.launchctlScheduler),
    running_node_scheduler_env_present: collected.nodeScheduler.present,
    running_node_scheduler_env_missing: collected.nodeScheduler.missing,
    running_node_scheduler_env_mismatched: collected.nodeScheduler.mismatched,
    unrelated_production_keys_checked: UNRELATED_PRODUCTION_KEYS,
    launchctl_unrelated_production_keys_present: collected.launchctlUnrelatedProductionKeys,
    running_node_unrelated_production_keys_present: collected.nodeUnrelatedProductionKeys,
    production_authority_change: false,
    provider_route_authority_target: true,
    model_route_authority_target: true,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
    issues,
  };
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `route_authority_production_runtime_guard_${stamp}.json`);
}

function runSelfTest() {
  const config = {
    rustHubRoot: '/tmp/rust-hub',
    httpBaseUrl: 'http://127.0.0.1:50151',
    requireSchedulerAuthority: true,
    allowXtFileIpcProduction: true,
  };
  const providerModel = Object.keys(providerModelExpected(config));
  const scheduler = Object.keys(schedulerExpected(config));
  const ok = reduce({
    launchctlProviderModel: { present: providerModel, missing: [], mismatched: [] },
    node: { pid: 123 },
    nodeProviderModel: { present: providerModel, missing: [], mismatched: [] },
    launchctlScheduler: { present: scheduler, missing: [], mismatched: [] },
    nodeScheduler: { present: scheduler, missing: [], mismatched: [] },
    launchctlUnrelatedProductionKeys: [],
    nodeUnrelatedProductionKeys: [],
  }, config);
  if (!ok.ok) throw new Error(`expected production runtime guard ok: ${ok.issues.join(',')}`);
  const fallbackMismatch = reduce({
    launchctlProviderModel: { present: providerModel, missing: [], mismatched: ['XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR'] },
    node: { pid: 123 },
    nodeProviderModel: { present: providerModel, missing: [], mismatched: ['XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR'] },
    launchctlScheduler: { present: scheduler, missing: [], mismatched: [] },
    nodeScheduler: { present: scheduler, missing: [], mismatched: [] },
    launchctlUnrelatedProductionKeys: [],
    nodeUnrelatedProductionKeys: [],
  }, config);
  if (fallbackMismatch.ok || !fallbackMismatch.issues.includes('xhub_node_process_needs_relaunch_for_provider_model_production_env')) {
    throw new Error('expected fallback mismatch to fail closed');
  }
  const unrelated = reduce({
    launchctlProviderModel: { present: providerModel, missing: [], mismatched: [] },
    node: { pid: 123 },
    nodeProviderModel: { present: providerModel, missing: [], mismatched: [] },
    launchctlScheduler: { present: scheduler, missing: [], mismatched: [] },
    nodeScheduler: { present: scheduler, missing: [], mismatched: [] },
    launchctlUnrelatedProductionKeys: [],
    nodeUnrelatedProductionKeys: ['XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER'],
  }, { ...config, allowXtFileIpcProduction: false });
  if (unrelated.ok || !unrelated.issues.includes('xhub_node_unrelated_production_env_present')) {
    throw new Error('expected unrelated production env to fail closed');
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
    process.stdout.write('route_authority_production_runtime_guard self-test ok\n');
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
  process.stderr.write(`[route_authority_production_runtime_guard] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
