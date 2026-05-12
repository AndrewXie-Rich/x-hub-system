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

function parseArgs(argv) {
  const out = {
    targetRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
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
    '  --no-report           Print only; do not write reports/',
    '  --self-test           Validate reducer logic',
  ].join('\n');
}

function readLaunchctlRoot() {
  try {
    return execFileSync('launchctl', ['getenv', ROOT_KEY], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch {
    return '';
  }
}

function findNodeProcess() {
  let rows = [];
  try {
    rows = execFileSync('ps', ['axeww', '-o', 'pid=,command='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 8 * 1024 * 1024,
    }).split('\n');
  } catch {
    return { pid: 0, command: '', envRoot: '' };
  }
  const candidates = rows
    .map((line) => line.trim())
    .filter((line) => NODE_PROCESS_MARKERS.every((marker) => line.includes(marker)))
    .filter((line) => !line.includes('active_root_upgrade_plan.js'));
  if (candidates.length === 0) return { pid: 0, command: '', envRoot: '' };
  const parsed = candidates
    .map((line) => {
      const match = line.match(/^(\d+)\s+([\s\S]*)$/);
      if (!match) return null;
      return { pid: Number(match[1]), command: match[2] };
    })
    .filter(Boolean)
    .sort((a, b) => b.pid - a.pid)[0];
  return { ...parsed, envRoot: extractEnvValue(parsed.command, ROOT_KEY) };
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

function collect(config) {
  return {
    launchctlRoot: readLaunchctlRoot(),
    node: findNodeProcess(),
    targetExists: fs.existsSync(config.targetRoot),
    targetHasBin: fs.existsSync(path.join(config.targetRoot, 'bin', 'xhubd'))
      || fs.existsSync(path.join(config.targetRoot, 'target', 'release', 'xhubd')),
    targetHasTools: fs.existsSync(path.join(config.targetRoot, 'tools')),
  };
}

function reduce(collected, config) {
  const activeRoot = collected.node.envRoot || collected.launchctlRoot || '';
  const targetRoot = path.resolve(config.targetRoot);
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
    apply_commands: [
      `bash ${quote(path.join(targetRoot, 'tools', 'scheduler_production_authority_session.command'))} --apply --rust-hub-root ${quote(targetRoot)} --http-base-url ${quote(config.httpBaseUrl)}`,
      `bash ${quote(path.join(targetRoot, 'tools', 'scheduler_production_authority_session_launchd.command'))} --install --rust-hub-root ${quote(targetRoot)} --http-base-url ${quote(config.httpBaseUrl)}`,
      `bash ${quote(path.join(targetRoot, 'tools', 'route_authority_prep_session.command'))} --apply --rust-hub-root ${quote(targetRoot)} --http-base-url ${quote(config.httpBaseUrl)}`,
      `bash ${quote(path.join(targetRoot, 'tools', 'route_authority_prep_session_launchd.command'))} --install --rust-hub-root ${quote(targetRoot)} --http-base-url ${quote(config.httpBaseUrl)}`,
    ],
    restart_note: 'After applying the session env, relaunch X-Hub so its Node process inherits the target root.',
    validation_commands: [
      `bash ${quote(path.join(targetRoot, 'tools', 'scheduler_production_authority_guard.command'))} --rust-hub-root ${quote(targetRoot)}`,
      `bash ${quote(path.join(targetRoot, 'tools', 'route_authority_prep_runtime_guard.command'))} --rust-hub-root ${quote(targetRoot)}`,
      `bash ${quote(path.join(targetRoot, 'tools', 'route_authority_production_cutover_blocker.command'))} --rust-hub-root ${quote(targetRoot)}`,
      `bash ${quote(path.join(targetRoot, 'tools', 'ui_compatibility_no_product_ui_change_gate.command'))}`,
    ],
    rollback_commands: activeRoot ? [
      `bash ${quote(path.join(activeRoot, 'tools', 'scheduler_production_authority_session.command'))} --apply --rust-hub-root ${quote(activeRoot)} --http-base-url ${quote(config.httpBaseUrl)}`,
      `bash ${quote(path.join(activeRoot, 'tools', 'scheduler_production_authority_session_launchd.command'))} --install --rust-hub-root ${quote(activeRoot)} --http-base-url ${quote(config.httpBaseUrl)}`,
      `bash ${quote(path.join(activeRoot, 'tools', 'route_authority_prep_session.command'))} --apply --rust-hub-root ${quote(activeRoot)} --http-base-url ${quote(config.httpBaseUrl)}`,
      `bash ${quote(path.join(activeRoot, 'tools', 'route_authority_prep_session_launchd.command'))} --install --rust-hub-root ${quote(activeRoot)} --http-base-url ${quote(config.httpBaseUrl)}`,
    ] : [],
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
  return path.join(REPORT_DIR, `active_root_upgrade_plan_${stamp}.json`);
}

function runSelfTest() {
  const result = reduce({
    launchctlRoot: '/tmp/current',
    node: { pid: 1, envRoot: '/tmp/current' },
    targetExists: true,
    targetHasBin: true,
    targetHasTools: true,
  }, { targetRoot: '/tmp/target', httpBaseUrl: 'http://127.0.0.1:50151' });
  if (!result.ok) throw new Error(`expected target to be valid: ${result.issues.join(',')}`);
  if (result.action_required !== true) throw new Error('expected upgrade action required');
  if (result.production_authority_change !== false) throw new Error('plan must not change production authority');
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
