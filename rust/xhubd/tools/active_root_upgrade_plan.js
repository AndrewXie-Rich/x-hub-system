#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const NODE_PROCESS_MARKERS = ['hub_grpc_server/src/server.js', 'relflowhub_node'];
const ROOT_KEY = 'XHUB_RUST_HUB_ROOT';
const PROVIDER_MODEL_PRODUCTION_KEYS = [
  'XHUB_ENABLE_RUST_AUTHORITY_CUTOVER',
  'XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY',
  'XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY',
];
const MEMORY_SKILLS_PRODUCTION_KEYS = [
  'XHUB_RUST_MEMORY_WRITER_AUTHORITY',
  'XHUB_RUST_MEMORY_WRITE_AUTHORITY',
  'XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY',
  'XHUB_RUST_SKILLS_EXECUTION_AUTHORITY',
  'XHUB_RUST_SKILLS_PRODUCTION_EXECUTION',
  'XHUB_RUST_SKILLS_EXECUTION_PRODUCTION',
  'XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY',
];
const ROUTE_PREP_KEYS = [
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
];
const AUTHORITY_READ_KEYS = [
  ROOT_KEY,
  ...PROVIDER_MODEL_PRODUCTION_KEYS,
  ...MEMORY_SKILLS_PRODUCTION_KEYS,
  ...ROUTE_PREP_KEYS,
];

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

function parseArgs(argv) {
  const out = {
    targetRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
    forceRoutePrep: false,
    writeReport: true,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--target-root':
      case '--rust-hub-root':
        out.targetRoot = String(next || '').trim() || out.targetRoot;
        i += 1;
        break;
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--no-report':
        out.writeReport = false;
        break;
      case '--force-route-prep':
        out.forceRoutePrep = true;
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
    'active_root_upgrade_plan.js',
    '',
    'Options:',
    '  --target-root <p>     Rust Hub root to make active, default current package/source root',
    '  --http-base-url <u>   Rust xhubd HTTP base URL, default http://127.0.0.1:50151',
    '  --force-route-prep    Force legacy route prep apply/install commands even if production is detected',
    '  --no-report           Print only; do not write reports/',
    '  --self-test           Validate reducer logic',
  ].join('\n');
}

function readLaunchctlValue(key) {
  try {
    return execFileSync('launchctl', ['getenv', key], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch {
    return '';
  }
}

function readLaunchctlValues(keys) {
  return Object.fromEntries(keys.map((key) => [key, readLaunchctlValue(key)]));
}

function readLaunchctlRoot() {
  return readLaunchctlValue(ROOT_KEY);
}

function findNodeProcess() {
  let rows = [];
  try {
    rows = readProcessCommandRows();
  } catch {
    return { pid: 0, command: '', envCommand: '', envRoot: '' };
  }
  const candidates = rows
    .map((line) => line.trim())
    .filter((line) => isXHubNodeBridgeProcessLine(line))
    .filter((line) => !line.includes('active_root_upgrade_plan.js'))
    .map(parsePidCommand)
    .filter(Boolean);
  if (candidates.length === 0) return { pid: 0, command: '', envCommand: '', envRoot: '' };
  const parsed = candidates
    .sort((a, b) => b.pid - a.pid)[0];
  const envCommand = readProcessEnvCommand(parsed.pid) || parsed.command;
  return { ...parsed, envCommand, envRoot: extractEnvValue(envCommand, ROOT_KEY) };
}

function extractEnvValue(text, key) {
  const prefix = `${key}=`;
  let idx = text.indexOf(prefix);
  if (idx > 0 && text[idx - 1] !== ' ') idx = text.indexOf(` ${prefix}`);
  if (idx === -1) return '';
  if (text[idx] === ' ') idx += 1;
  const start = idx + prefix.length;
  const rest = text.slice(start);
  const nextEnv = rest.match(/ [A-Za-z_][A-Za-z0-9_]*=/);
  let end = nextEnv ? start + nextEnv.index : text.length;
  while (end > start && text[end - 1] === ' ') end -= 1;
  return text.slice(start, end);
}

function quote(value) {
  return `"${String(value).replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;
}

function valueEnabled(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value || '').trim().toLowerCase());
}

function enabledLaunchctlKeys(values, keys) {
  return keys.filter((key) => valueEnabled(values[key]));
}

function enabledNodeKeys(command, keys) {
  return keys.filter((key) => valueEnabled(extractEnvValue(command || '', key)));
}

function collectAuthority(node) {
  const launchctlValues = readLaunchctlValues(AUTHORITY_READ_KEYS);
  const providerLaunchctlKeys = enabledLaunchctlKeys(launchctlValues, PROVIDER_MODEL_PRODUCTION_KEYS);
  const providerNodeKeys = enabledNodeKeys(node?.envCommand || '', PROVIDER_MODEL_PRODUCTION_KEYS);
  const memoryLaunchctlKeys = enabledLaunchctlKeys(launchctlValues, MEMORY_SKILLS_PRODUCTION_KEYS);
  const memoryNodeKeys = enabledNodeKeys(node?.envCommand || '', MEMORY_SKILLS_PRODUCTION_KEYS);
  const prepLaunchctlKeys = enabledLaunchctlKeys(launchctlValues, ROUTE_PREP_KEYS);
  const prepNodeKeys = enabledNodeKeys(node?.envCommand || '', ROUTE_PREP_KEYS);
  return {
    providerModelProductionActive: providerLaunchctlKeys.length > 0 || providerNodeKeys.length > 0,
    memorySkillsProductionActive: memoryLaunchctlKeys.length > 0 || memoryNodeKeys.length > 0,
    routePrepActive: prepLaunchctlKeys.length > 0 || prepNodeKeys.length > 0,
    provider_model_production_launchctl_keys: providerLaunchctlKeys,
    provider_model_production_node_keys: providerNodeKeys,
    memory_skills_production_launchctl_keys: memoryLaunchctlKeys,
    memory_skills_production_node_keys: memoryNodeKeys,
    route_prep_launchctl_keys: prepLaunchctlKeys,
    route_prep_node_keys: prepNodeKeys,
  };
}

function selectRouteAuthorityMode(config, authority) {
  if (config.forceRoutePrep) return 'prep_forced';
  if (authority?.providerModelProductionActive) return 'production';
  return 'prep';
}

function memorySkillsGuardArg(authority) {
  return authority?.memorySkillsProductionActive
    ? '--require-memory-skills-production'
    : '--allow-memory-skills-production';
}

function schedulerApplyCommands(root, config) {
  return [
    `bash ${quote(path.join(root, 'tools', 'scheduler_production_authority_session.command'))} --apply --rust-hub-root ${quote(root)} --http-base-url ${quote(config.httpBaseUrl)}`,
    `bash ${quote(path.join(root, 'tools', 'scheduler_production_authority_session_launchd.command'))} --install --rust-hub-root ${quote(root)} --http-base-url ${quote(config.httpBaseUrl)}`,
  ];
}

function routePrepApplyCommands(root, config) {
  return [
    `bash ${quote(path.join(root, 'tools', 'route_authority_prep_session.command'))} --apply --rust-hub-root ${quote(root)} --http-base-url ${quote(config.httpBaseUrl)}`,
    `bash ${quote(path.join(root, 'tools', 'route_authority_prep_session_launchd.command'))} --install --rust-hub-root ${quote(root)} --http-base-url ${quote(config.httpBaseUrl)}`,
  ];
}

function validationCommands(root, config, authority, routeAuthorityMode) {
  const commands = [
    `bash ${quote(path.join(root, 'tools', 'scheduler_production_authority_guard.command'))} --rust-hub-root ${quote(root)} --http-base-url ${quote(config.httpBaseUrl)} ${memorySkillsGuardArg(authority)}`,
  ];
  if (routeAuthorityMode === 'production') {
    commands.push(
      `bash ${quote(path.join(root, 'tools', 'route_authority_production_runtime_guard.command'))} --rust-hub-root ${quote(root)} --http-base-url ${quote(config.httpBaseUrl)} ${memorySkillsGuardArg(authority)}`,
    );
  } else {
    commands.push(
      `bash ${quote(path.join(root, 'tools', 'route_authority_prep_runtime_guard.command'))} --rust-hub-root ${quote(root)}`,
      `bash ${quote(path.join(root, 'tools', 'route_authority_production_cutover_blocker.command'))} --rust-hub-root ${quote(root)}`,
    );
  }
  commands.push(`bash ${quote(path.join(root, 'tools', 'ui_compatibility_no_product_ui_change_gate.command'))}`);
  return commands;
}

function collect(config) {
  const node = findNodeProcess();
  return {
    launchctlRoot: readLaunchctlRoot(),
    node,
    authority: collectAuthority(node),
    targetExists: fs.existsSync(config.targetRoot),
    targetHasBin: fs.existsSync(path.join(config.targetRoot, 'bin', 'xhubd'))
      || fs.existsSync(path.join(config.targetRoot, 'target', 'release', 'xhubd')),
    targetHasTools: fs.existsSync(path.join(config.targetRoot, 'tools')),
  };
}

function reduce(collected, config) {
  const activeRoot = collected.node.envRoot || collected.launchctlRoot || '';
  const targetRoot = path.resolve(config.targetRoot);
  const authority = collected.authority || collectAuthority(collected.node || {});
  const routeAuthorityMode = selectRouteAuthorityMode(config, authority);
  const applyCommands = [
    ...schedulerApplyCommands(targetRoot, config),
    ...(routeAuthorityMode === 'production' ? [] : routePrepApplyCommands(targetRoot, config)),
  ];
  const rollbackCommands = activeRoot ? [
    ...schedulerApplyCommands(activeRoot, config),
    ...(routeAuthorityMode === 'production' ? [] : routePrepApplyCommands(activeRoot, config)),
  ] : [];
  const issues = [];
  if (!collected.targetExists) issues.push('target_root_missing');
  if (!collected.targetHasBin) issues.push('target_xhubd_binary_missing');
  if (!collected.targetHasTools) issues.push('target_tools_missing');
  if (!collected.launchctlRoot) issues.push('launchctl_root_not_set');
  if (!collected.node.pid) issues.push('xhub_node_process_not_running');
  const aligned = activeRoot === targetRoot
    && collected.launchctlRoot === targetRoot
    && collected.node.envRoot === targetRoot;
  return {
    ok: issues.length === 0,
    schema_version: 'xhub.active_root_upgrade_plan.v1',
    generated_at: new Date().toISOString(),
    target_root: targetRoot,
    active_root: activeRoot,
    launchctl_root: collected.launchctlRoot,
    running_node_process_pid: collected.node.pid,
    running_node_root: collected.node.envRoot,
    target_root_exists: collected.targetExists,
    target_has_xhubd_binary: collected.targetHasBin,
    target_has_tools: collected.targetHasTools,
    active_root_aligned_with_target: aligned,
    action_required: !aligned,
    route_authority_mode: routeAuthorityMode,
    provider_model_production_authority_detected: authority.providerModelProductionActive,
    memory_skills_production_authority_detected: authority.memorySkillsProductionActive,
    route_prep_authority_detected: authority.routePrepActive,
    route_prep_apply_skipped: routeAuthorityMode === 'production',
    route_prep_apply_skip_reason: routeAuthorityMode === 'production'
      ? 'provider_model_production_authority_detected'
      : '',
    authority_detection: authority,
    apply_commands: applyCommands,
    restart_note: 'After applying the session env, relaunch X-Hub so its Node process inherits the target root.',
    validation_commands: validationCommands(targetRoot, config, authority, routeAuthorityMode),
    rollback_commands: rollbackCommands,
    production_authority_change: false,
    provider_route_authority_target: authority.providerModelProductionActive,
    model_route_authority_target: authority.providerModelProductionActive,
    memory_writer_authority_target: authority.memorySkillsProductionActive,
    skills_execution_authority_target: authority.memorySkillsProductionActive,
    ui_product_change: false,
    secret_leak: false,
    issues,
  };
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `active_root_upgrade_plan_${stamp}.json`);
}

function runSelfTest() {
  const external = '999 /Volumes/RELFlowHub v1.2.22/RELFlowHub.app/Contents/Resources/relflowhub_node /Volumes/RELFlowHub v1.2.22/RELFlowHub.app/Contents/Resources/hub_grpc_server/src/server.js';
  if (isXHubNodeBridgeProcessLine(external)) throw new Error('standalone RELFlowHub must not classify as X-Hub node bridge');
  const result = reduce({
    launchctlRoot: '/tmp/current',
    node: { pid: 1, envRoot: '/tmp/current' },
    authority: {
      providerModelProductionActive: false,
      memorySkillsProductionActive: false,
      routePrepActive: true,
    },
    targetExists: true,
    targetHasBin: true,
    targetHasTools: true,
  }, { targetRoot: '/tmp/target', httpBaseUrl: 'http://127.0.0.1:50151' });
  if (!result.ok) throw new Error(`expected target to be valid: ${result.issues.join(',')}`);
  if (result.action_required !== true) throw new Error('expected upgrade action required');
  if (result.production_authority_change !== false) throw new Error('plan must not change production authority');
  const productionResult = reduce({
    launchctlRoot: '/tmp/current',
    node: { pid: 1, envRoot: '/tmp/current' },
    authority: {
      providerModelProductionActive: true,
      memorySkillsProductionActive: true,
      routePrepActive: false,
    },
    targetExists: true,
    targetHasBin: true,
    targetHasTools: true,
  }, { targetRoot: '/tmp/target', httpBaseUrl: 'http://127.0.0.1:50151', forceRoutePrep: false });
  if (productionResult.route_authority_mode !== 'production') throw new Error('expected production route authority mode');
  if (productionResult.apply_commands.some((cmd) => cmd.includes('route_authority_prep_session'))) {
    throw new Error('production active-root plan must not apply route prep env');
  }
  if (!productionResult.validation_commands.some((cmd) => cmd.includes('route_authority_production_runtime_guard.command'))) {
    throw new Error('production active-root plan must validate production runtime authority');
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
    process.stdout.write('active_root_upgrade_plan self-test ok\n');
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
  process.stderr.write(`[active_root_upgrade_plan] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
