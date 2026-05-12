#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const DEFAULT_APP = 'build/X-Hub.app';
const NODE_PROCESS_MARKERS = ['hub_grpc_server/src/server.js', 'relflowhub_node'];
const ROOT_KEY = 'XHUB_RUST_HUB_ROOT';

function parseArgs(argv) {
  const out = {
    targetRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
    apply: false,
    relaunchXhub: false,
    validate: false,
    appPath: DEFAULT_APP,
    relaunchWaitMs: 30000,
    relaunchPollMs: 1000,
    relaunchRetryWaitMs: 15000,
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
      case '--apply':
        out.apply = true;
        break;
      case '--relaunch-xhub':
        out.relaunchXhub = true;
        break;
      case '--validate':
        out.validate = true;
        break;
      case '--app':
        out.appPath = String(next || '').trim() || out.appPath;
        i += 1;
        break;
      case '--relaunch-wait-ms':
        out.relaunchWaitMs = parseIntInRange(next, out.relaunchWaitMs, 0, 300000);
        i += 1;
        break;
      case '--relaunch-poll-ms':
        out.relaunchPollMs = parseIntInRange(next, out.relaunchPollMs, 100, 60000);
        i += 1;
        break;
      case '--relaunch-retry-wait-ms':
        out.relaunchRetryWaitMs = parseIntInRange(next, out.relaunchRetryWaitMs, 0, 300000);
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

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function usage() {
  return [
    'active_root_upgrade_apply.js',
    '',
    'Options:',
    '  --target-root <p>     Rust Hub root to make active, default current package/source root',
    '  --http-base-url <u>   Rust xhubd HTTP base URL, default http://127.0.0.1:50151',
    '  --apply               Apply launchctl/session and persistent LaunchAgent root changes',
    '  --relaunch-xhub       Relaunch X-Hub after --apply so Node inherits the target root',
    '  --validate            Run post-apply guards after optional relaunch',
    '  --app <path>          X-Hub.app path',
    '  --relaunch-wait-ms <n> Wait for X-Hub Node root after relaunch, default 30000',
    '  --relaunch-poll-ms <n> Poll interval while waiting for relaunch, default 1000',
    '  --relaunch-retry-wait-ms <n> Retry open wait if Node is not ready, default 15000',
    '  --no-report           Print only; do not write reports/',
    '  --self-test           Validate reducer logic',
  ].join('\n');
}

function quote(value) {
  return `"${String(value).replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;
}

function shellLine(step) {
  return ['bash', quote(step.command), ...step.args.map(quote)].join(' ');
}

function step(name, command, args, mutating) {
  return { name, command, args, mutating, shell: shellLine({ command, args }) };
}

function buildSteps(config) {
  const targetRoot = path.resolve(config.targetRoot);
  const tools = path.join(targetRoot, 'tools');
  const common = ['--rust-hub-root', targetRoot, '--http-base-url', config.httpBaseUrl];
  return {
    targetRoot,
    applySteps: [
      step('scheduler_session_apply', path.join(tools, 'scheduler_production_authority_session.command'), ['--apply', ...common], true),
      step('scheduler_session_launchd_install', path.join(tools, 'scheduler_production_authority_session_launchd.command'), ['--install', ...common], true),
      step('route_prep_session_apply', path.join(tools, 'route_authority_prep_session.command'), ['--apply', ...common], true),
      step('route_prep_session_launchd_install', path.join(tools, 'route_authority_prep_session_launchd.command'), ['--install', ...common], true),
    ],
    validationSteps: [
      step('scheduler_authority_guard', path.join(tools, 'scheduler_production_authority_guard.command'), ['--rust-hub-root', targetRoot], false),
      step('route_prep_runtime_guard', path.join(tools, 'route_authority_prep_runtime_guard.command'), ['--rust-hub-root', targetRoot], false),
      step('route_production_cutover_blocker', path.join(tools, 'route_authority_production_cutover_blocker.command'), ['--rust-hub-root', targetRoot], false),
      step('ui_compatibility_gate', path.join(tools, 'ui_compatibility_no_product_ui_change_gate.command'), [], false),
    ],
  };
}

function validateTarget(targetRoot) {
  const issues = [];
  if (!fs.existsSync(targetRoot)) issues.push('target_root_missing');
  if (!fs.existsSync(path.join(targetRoot, 'tools'))) issues.push('target_tools_missing');
  const binExists = fs.existsSync(path.join(targetRoot, 'bin', 'xhubd'))
    || fs.existsSync(path.join(targetRoot, 'target', 'release', 'xhubd'));
  if (!binExists) issues.push('target_xhubd_binary_missing');
  return issues;
}

function runStep(s) {
  const started = Date.now();
  let stdout = '';
  let stderr = '';
  let exitCode = 0;
  try {
    stdout = execFileSync('bash', [s.command, ...s.args], {
      cwd: ROOT_DIR,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 240000,
      maxBuffer: 32 * 1024 * 1024,
    });
  } catch (error) {
    stdout = String(error.stdout || '').slice(0, 12000);
    stderr = String(error.stderr || error.message || '').slice(0, 4000);
    exitCode = Number(error.status || 1);
  }
  return {
    name: s.name,
    mutating: s.mutating,
    exit_code: exitCode,
    ok: exitCode === 0,
    elapsed_ms: Date.now() - started,
    stdout_tail: stdout.slice(-2000),
    stderr,
  };
}

function relaunchXhub(config, targetRoot) {
  const out = {
    requested: true,
    app_path: config.appPath,
    app_exists: fs.existsSync(config.appPath),
    quit_exit_code: 0,
    open_exit_code: 0,
    wait_ms: config.relaunchWaitMs,
    poll_ms: config.relaunchPollMs,
    retry_wait_ms: config.relaunchRetryWaitMs,
    retry_open_attempted: false,
    retry_open_exit_code: 0,
    node_ready: false,
    node_pid: 0,
    node_root: '',
  };
  if (!out.app_exists) {
    out.quit_exit_code = 1;
    out.open_exit_code = 1;
    out.error = 'xhub_app_missing';
    return out;
  }
  try {
    execFileSync('osascript', ['-e', 'tell application "X-Hub" to quit'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 30000,
    });
  } catch (error) {
    out.quit_exit_code = Number(error.status || 1);
  }
  try {
    execFileSync('open', [config.appPath], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 30000,
    });
  } catch (error) {
    out.open_exit_code = Number(error.status || 1);
  }
  const wait = waitForNodeRoot(targetRoot, config.relaunchWaitMs, config.relaunchPollMs);
  out.node_ready = wait.ready;
  out.node_pid = wait.pid;
  out.node_root = wait.root;
  out.wait_elapsed_ms = wait.elapsed_ms;
  out.wait_attempts = wait.attempts;
  if (!out.node_ready && config.relaunchRetryWaitMs > 0 && out.open_exit_code === 0) {
    out.retry_open_attempted = true;
    try {
      execFileSync('open', [config.appPath], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: 30000,
      });
    } catch (error) {
      out.retry_open_exit_code = Number(error.status || 1);
    }
    const retryWait = waitForNodeRoot(targetRoot, config.relaunchRetryWaitMs, config.relaunchPollMs);
    out.node_ready = retryWait.ready;
    out.node_pid = retryWait.pid;
    out.node_root = retryWait.root;
    out.retry_wait_elapsed_ms = retryWait.elapsed_ms;
    out.retry_wait_attempts = retryWait.attempts;
  }
  return out;
}

function reduce(config, executed, targetIssues, relaunch) {
  const failed = executed.filter((item) => !item.ok);
  const issues = [...targetIssues];
  if (config.relaunchXhub && !config.apply) issues.push('relaunch_requires_apply');
  if (failed.length) issues.push('one_or_more_steps_failed');
  if (relaunch?.requested && relaunch.open_exit_code !== 0) issues.push('xhub_relaunch_failed');
  if (relaunch?.requested && !relaunch.node_ready) issues.push('xhub_node_root_not_ready_after_relaunch');
  const steps = buildSteps(config);
  return {
    ok: issues.length === 0,
    schema_version: 'xhub.active_root_upgrade_apply.v1',
    generated_at: new Date().toISOString(),
    target_root: steps.targetRoot,
    dry_run: !config.apply,
    apply_requested: config.apply,
    relaunch_xhub_requested: config.relaunchXhub,
    validation_requested: config.validate,
    apply_steps: steps.applySteps.map((s) => ({ name: s.name, shell: s.shell })),
    validation_steps: steps.validationSteps.map((s) => ({ name: s.name, shell: s.shell })),
    executed_steps: executed,
    relaunch_xhub: relaunch || { requested: false },
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

function waitForNodeRoot(targetRoot, waitMs, pollMs) {
  const started = Date.now();
  let attempts = 0;
  let last = { pid: 0, root: '' };
  while (Date.now() - started <= waitMs) {
    attempts += 1;
    last = findNodeProcess();
    if (last.pid && last.root === targetRoot) {
      return {
        ready: true,
        pid: last.pid,
        root: last.root,
        elapsed_ms: Date.now() - started,
        attempts,
      };
    }
    if (waitMs === 0) break;
    sleep(Math.min(pollMs, Math.max(0, waitMs - (Date.now() - started))));
  }
  return {
    ready: false,
    pid: last.pid,
    root: last.root,
    elapsed_ms: Date.now() - started,
    attempts,
  };
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
    return { pid: 0, root: '' };
  }
  const candidates = rows
    .map((line) => line.trim())
    .filter((line) => NODE_PROCESS_MARKERS.every((marker) => line.includes(marker)))
    .filter((line) => !line.includes('active_root_upgrade_apply.js'));
  if (candidates.length === 0) return { pid: 0, root: '' };
  const parsed = candidates
    .map((line) => {
      const match = line.match(/^(\d+)\s+([\s\S]*)$/);
      if (!match) return null;
      return { pid: Number(match[1]), command: match[2] };
    })
    .filter(Boolean)
    .sort((a, b) => b.pid - a.pid)[0];
  return { pid: parsed.pid, root: extractEnvValue(parsed.command, ROOT_KEY) };
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

function sleep(ms) {
  if (ms <= 0) return;
  const seconds = String(Math.max(0, ms / 1000));
  execFileSync('sleep', [seconds], { stdio: ['ignore', 'ignore', 'ignore'] });
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `active_root_upgrade_apply_${stamp}.json`);
}

function runSelfTest() {
  const config = parseArgs(['--target-root', '/tmp/rust-hub-target']);
  const steps = buildSteps(config);
  if (steps.applySteps.length !== 4) throw new Error('expected four apply steps');
  if (steps.validationSteps.length !== 4) throw new Error('expected four validation steps');
  const result = reduce(config, [], [], null);
  if (result.dry_run !== true) throw new Error('default must be dry-run');
  if (result.production_authority_change !== false) throw new Error('must not change provider/model production authority');
  const parsed = parseArgs(['--relaunch-wait-ms', '1', '--relaunch-poll-ms', '100', '--relaunch-retry-wait-ms', '2']);
  if (parsed.relaunchWaitMs !== 1) throw new Error('relaunch wait parser failed');
  if (parsed.relaunchPollMs !== 100) throw new Error('relaunch poll parser failed');
  if (parsed.relaunchRetryWaitMs !== 2) throw new Error('relaunch retry wait parser failed');
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('active_root_upgrade_apply self-test ok\n');
    return;
  }
  const steps = buildSteps(config);
  const targetIssues = validateTarget(steps.targetRoot);
  const executed = [];
  let relaunch = null;
  if (config.apply && targetIssues.length === 0) {
    for (const s of steps.applySteps) executed.push(runStep(s));
    if (config.relaunchXhub) relaunch = relaunchXhub(config, steps.targetRoot);
    if (config.validate) {
      for (const s of steps.validationSteps) executed.push(runStep(s));
    }
  }
  const result = reduce(config, executed, targetIssues, relaunch);
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
  process.stderr.write(`[active_root_upgrade_apply] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
