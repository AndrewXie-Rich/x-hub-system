#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const NODE_PROCESS_MARKERS = ['hub_grpc_server/src/server.js', 'relflowhub_node'];

function isXHubShellProcessLine(line) {
  const text = String(line || '');
  return text.includes('/X-Hub.app/Contents/MacOS/XHub')
    && !text.includes('route_authority_prep_runtime_guard.js');
}

function isExternalRelFlowHubProcessLine(line) {
  const text = String(line || '');
  return !text.includes('/X-Hub.app/')
    && (text.includes('/RELFlowHub.app/') || text.includes('/Volumes/RELFlowHub'));
}

function isXHubNodeBridgeProcessLine(line) {
  const text = String(line || '');
  return NODE_PROCESS_MARKERS.every((marker) => text.includes(marker))
    && !isExternalRelFlowHubProcessLine(text)
    && (text.includes('/X-Hub.app/')
      || /\/x-hub-system(?:-github-clean)?\/x-hub\//.test(text));
}

function parsePidCommand(line) {
  const match = String(line || '').trim().match(/^(\d+)\s+([\s\S]*)$/);
  if (!match) return null;
  return { pid: Number(match[1]), command: match[2] };
}

function readProcessCommandRows() {
  return execFileSync('ps', ['ax', '-o', 'pid=,command='], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 8 * 1024 * 1024,
  }).split('\n');
}

function readProcessEnvCommand(pid) {
  try {
    return execFileSync('ps', ['eww', '-p', String(pid), '-o', 'command='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 8 * 1024 * 1024,
    }).trim();
  } catch {
  }
  try {
    const rows = execFileSync('ps', ['axeww', '-o', 'pid=,command='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 8 * 1024 * 1024,
    }).split('\n');
    const found = rows.map(parsePidCommand).find((row) => row?.pid === pid);
    return found?.command || '';
  } catch {
    return '';
  }
}

const SAFE_KEYS = [
  'XHUB_RUST_HUB_ROOT',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
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

const READ_KEYS = [...SAFE_KEYS, ...FORBIDDEN_PRODUCTION_KEYS];

function parseArgs(argv) {
  const out = {
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
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
    'route_authority_prep_runtime_guard.js',
    '',
    'Options:',
    '  --rust-hub-root <p>   Expected active Rust Hub root',
    '  --http-base-url <u>   Expected xhubd HTTP base URL',
    '  --no-report           Print only; do not write reports/',
    '  --self-test           Validate reducer logic',
  ].join('\n');
}

function expected(config) {
  return {
    XHUB_RUST_HUB_ROOT: config.rustHubRoot,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL: config.httpBaseUrl,
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH: '1',
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
  const rows = readProcessCommandRows();
  const candidates = rows
    .map((line) => line.trim())
    .filter((line) => isXHubNodeBridgeProcessLine(line))
    .filter((line) => !line.includes('route_authority_prep_runtime_guard.js'))
    .map(parsePidCommand)
    .filter(Boolean);
  if (candidates.length === 0) return { pid: 0, command: '', envCommand: '' };
  const parsed = candidates
    .sort((a, b) => b.pid - a.pid)[0];
  if (!parsed) return { pid: 0, command: '', envCommand: '' };
  return { ...parsed, envCommand: readProcessEnvCommand(parsed.pid) || parsed.command };
}

function findXHubShellProcess() {
  const rows = readProcessCommandRows();
  const candidates = rows
    .map((line) => line.trim())
    .filter((line) => isXHubShellProcessLine(line))
    .map(parsePidCommand)
    .filter(Boolean);
  if (candidates.length === 0) return { pid: 0, command: '' };
  return candidates.sort((a, b) => b.pid - a.pid)[0] || { pid: 0, command: '' };
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

function presentKeys(values, keys) {
  return keys.filter((key) => String(values?.[key] || '') !== '');
}

function collect(config) {
  const expectedValues = expected(config);
  const launchctlValues = readLaunchctlSession();
  const launchctl = compare(launchctlValues, expectedValues);
  const node = findNodeProcess();
  const shell = findXHubShellProcess();
  const nodeValues = node.pid ? parseProcessEnv(node.envCommand || '') : {};
  const nodeEnv = node.pid ? compare(nodeValues, expectedValues) : { present: [], missing: SAFE_KEYS, mismatched: [] };
  return {
    launchctl,
    node,
    shell,
    nodeEnv,
    launchctlForbiddenProductionKeys: presentKeys(launchctlValues, FORBIDDEN_PRODUCTION_KEYS),
    nodeForbiddenProductionKeys: presentKeys(nodeValues, FORBIDDEN_PRODUCTION_KEYS),
  };
}

function reduce(collected) {
  const issues = [];
  const nodeBridgeRunning = Number(collected.node?.pid || 0) > 0;
  const swiftShellRunning = Number(collected.shell?.pid || 0) > 0;
  const productShellRunning = swiftShellRunning || nodeBridgeRunning;
  if (collected.launchctl.missing.length || collected.launchctl.mismatched.length) issues.push('launchctl_prep_session_env_not_applied');
  if (!productShellRunning) issues.push('xhub_product_shell_not_running');
  if (nodeBridgeRunning && (collected.nodeEnv.missing.length || collected.nodeEnv.mismatched.length)) {
    issues.push('xhub_node_process_needs_relaunch_for_prep_env');
  }
  if (collected.launchctlForbiddenProductionKeys.length) issues.push('launchctl_provider_model_production_env_present');
  if (nodeBridgeRunning && collected.nodeForbiddenProductionKeys.length) issues.push('xhub_node_provider_model_production_env_present');
  return {
    ok: issues.length === 0,
    schema_version: 'xhub.route_authority_prep_runtime_guard.v1',
    generated_at: new Date().toISOString(),
    swift_product_shell_pid: Number(collected.shell?.pid || 0),
    swift_product_shell_running: swiftShellRunning,
    node_compatibility_layer_required: false,
    node_compatibility_layer_running: nodeBridgeRunning,
    launchctl_prep_session_applied: collected.launchctl.missing.length === 0 && collected.launchctl.mismatched.length === 0,
    running_node_process_pid: Number(collected.node?.pid || 0),
    running_node_prep_env_applied: nodeBridgeRunning
      ? collected.nodeEnv.missing.length === 0 && collected.nodeEnv.mismatched.length === 0
      : null,
    running_node_env_present: collected.nodeEnv.present,
    running_node_env_missing: collected.nodeEnv.missing,
    running_node_env_mismatched: collected.nodeEnv.mismatched,
    forbidden_provider_model_production_keys: FORBIDDEN_PRODUCTION_KEYS,
    launchctl_forbidden_production_keys_present: collected.launchctlForbiddenProductionKeys,
    running_node_forbidden_production_keys_present: collected.nodeForbiddenProductionKeys,
    production_authority_change: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
    issues,
  };
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `route_authority_prep_runtime_guard_${stamp}.json`);
}

function runSelfTest() {
  const external = '999 /Volumes/RELFlowHub v1.2.22/RELFlowHub.app/Contents/Resources/relflowhub_node /Volumes/RELFlowHub v1.2.22/RELFlowHub.app/Contents/Resources/hub_grpc_server/src/server.js';
  if (isXHubNodeBridgeProcessLine(external)) throw new Error('standalone RELFlowHub must not classify as X-Hub node bridge');
  const shellOnly = reduce({
    launchctl: { present: SAFE_KEYS, missing: [], mismatched: [] },
    node: { pid: 0 },
    shell: { pid: 456 },
    nodeEnv: { present: [], missing: SAFE_KEYS, mismatched: [] },
    launchctlForbiddenProductionKeys: [],
    nodeForbiddenProductionKeys: [],
  });
  if (!shellOnly.ok || shellOnly.node_compatibility_layer_required !== false) {
    throw new Error(`expected Swift shell + Rust prep authority to pass: ${shellOnly.issues.join(',')}`);
  }
  const result = reduce({
    launchctl: { present: SAFE_KEYS, missing: [], mismatched: [] },
    node: { pid: 123 },
    shell: { pid: 456 },
    nodeEnv: { present: SAFE_KEYS, missing: [], mismatched: [] },
    launchctlForbiddenProductionKeys: [],
    nodeForbiddenProductionKeys: [],
  });
  if (!result.ok) throw new Error(`expected self-test ok: ${result.issues.join(',')}`);
  const forbidden = reduce({
    launchctl: { present: SAFE_KEYS, missing: [], mismatched: [] },
    node: { pid: 123 },
    shell: { pid: 456 },
    nodeEnv: { present: SAFE_KEYS, missing: [], mismatched: [] },
    launchctlForbiddenProductionKeys: [],
    nodeForbiddenProductionKeys: ['XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION'],
  });
  if (forbidden.ok || !forbidden.issues.includes('xhub_node_provider_model_production_env_present')) {
    throw new Error('expected forbidden production env to fail closed');
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
    process.stdout.write('route_authority_prep_runtime_guard self-test ok\n');
    return;
  }
  const result = reduce(collect(config));
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
  process.stderr.write(`[route_authority_prep_runtime_guard] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
