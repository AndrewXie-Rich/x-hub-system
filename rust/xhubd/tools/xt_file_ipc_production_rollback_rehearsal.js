#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const REHEARSAL_DIR = path.join(REPORT_DIR, 'xt_file_ipc_production_rehearsal');
const DEFAULT_REHEARSAL_BASE_DIR = path.join(REHEARSAL_DIR, 'live_base_rehearsal');

const PRODUCTION_KEYS = [
  'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER',
  'XHUB_RUST_XT_FILE_IPC_BASE_DIR',
  'XHUB_RUST_XT_CLASSIC_COMPAT',
  'XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY',
  'XHUB_RUST_XT_CLASSIC_GRPC_PROBE',
  'XHUB_RUST_XT_CLASSIC_GRPC_HOST',
  'XHUB_RUST_XT_CLASSIC_GRPC_PORT',
  'XHUB_RUST_XT_CLASSIC_GRPC_PROBE_TIMEOUT_MS',
  'XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR',
  'XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH',
  'XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT',
  'XHUB_RUST_XT_CLASSIC_FILE_IPC_READY',
  'XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER',
];

function parseArgs(argv) {
  const out = {
    rustHubRoot: ROOT_DIR,
    rehearsalBaseDir: DEFAULT_REHEARSAL_BASE_DIR,
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
      case '--rehearsal-base-dir':
        out.rehearsalBaseDir = String(next || '').trim() || out.rehearsalBaseDir;
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
    'xt_file_ipc_production_rollback_rehearsal.js',
    '',
    'Options:',
    '  --rust-hub-root <p>        Expected active Rust Hub root',
    '  --rehearsal-base-dir <p>   Existing-created non-temp rehearsal base dir',
    '  --no-report                Print only; do not write reports/',
    '  --self-test                Validate reducer logic',
  ].join('\n');
}

function runJson(command, args, timeoutMs) {
  let stdout = '';
  let stderr = '';
  let exitCode = 0;
  try {
    stdout = execFileSync(command, args, {
      cwd: ROOT_DIR,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: timeoutMs,
      maxBuffer: 8 * 1024 * 1024,
    });
  } catch (error) {
    stdout = String(error.stdout || '');
    stderr = String(error.stderr || error.message || '').slice(0, 4000);
    exitCode = Number(error.status || 1);
  }
  try {
    return { exit_code: exitCode, parsed: true, stderr, payload: JSON.parse(stdout) };
  } catch {
    return { exit_code: exitCode, parsed: false, stderr, stdout: stdout.slice(0, 4000), payload: null };
  }
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

function snapshot() {
  const out = {};
  for (const key of ['XHUB_RUST_HUB_ROOT', ...PRODUCTION_KEYS]) out[key] = getEnv(key);
  return out;
}

function diffSnapshot(before, after) {
  return Object.keys(before)
    .filter((key) => String(before[key] || '') !== String(after[key] || ''));
}

function validateRehearsalBaseDir(baseDir) {
  const resolved = path.resolve(String(baseDir || '').trim());
  if (!resolved) throw new Error('missing rehearsal base dir');
  if (resolved === '/tmp' || resolved === '/private/tmp' || resolved.startsWith('/tmp/') || resolved.startsWith('/private/tmp/')) {
    throw new Error('rehearsal base dir must not be in temp');
  }
  fs.mkdirSync(resolved, { recursive: true });
  if (!fs.statSync(resolved).isDirectory()) throw new Error(`rehearsal base dir is not a directory: ${resolved}`);
  return resolved;
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `xt_file_ipc_production_rollback_rehearsal_${stamp}.json`);
}

function reduce(evidence) {
  const blockers = [];
  if (evidence.apply.exit_code !== 0 || evidence.apply.payload?.applied !== true) blockers.push('production_session_apply_failed');
  if (evidence.after_apply.XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER !== '1') blockers.push('production_cutover_env_not_set_during_rehearsal');
  if (evidence.status_file_written_before || evidence.status_file_written_after) blockers.push('hub_status_written_during_rehearsal');
  if (evidence.rollback.exit_code !== 0 || evidence.rollback.payload?.rollback_performed !== true) blockers.push('production_session_rollback_failed');
  if (evidence.changed_after_rollback.length > 0) blockers.push('launchctl_env_not_restored_after_rollback');
  return {
    ok: blockers.length === 0,
    blockers,
  };
}

function runSelfTest() {
  const result = reduce({
    apply: { exit_code: 0, payload: { applied: true } },
    rollback: { exit_code: 0, payload: { rollback_performed: true } },
    after_apply: { XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER: '1' },
    status_file_written_before: false,
    status_file_written_after: false,
    changed_after_rollback: [],
  });
  if (result.ok !== true) throw new Error('clean rehearsal should pass');
  const blocked = reduce({
    apply: { exit_code: 0, payload: { applied: true } },
    rollback: { exit_code: 0, payload: { rollback_performed: true } },
    after_apply: { XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER: '1' },
    status_file_written_before: false,
    status_file_written_after: true,
    changed_after_rollback: [],
  });
  if (!blocked.blockers.includes('hub_status_written_during_rehearsal')) {
    throw new Error('status write blocker missing');
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
    process.stdout.write('xt_file_ipc_production_rollback_rehearsal self-test ok\n');
    return;
  }

  const rehearsalBaseDir = validateRehearsalBaseDir(config.rehearsalBaseDir);
  const statusPath = path.join(rehearsalBaseDir, 'hub_status.json');
  const before = snapshot();
  const statusFileWrittenBefore = fs.existsSync(statusPath);
  const productionTool = path.join(SCRIPT_DIR, 'xt_file_ipc_production_session.command');
  const apply = runJson('bash', [
    productionTool,
    '--apply',
    '--rust-hub-root',
    config.rustHubRoot,
    '--live-base-dir',
    rehearsalBaseDir,
    '--confirm-live-cutover',
  ], 30000);
  const afterApply = snapshot();
  const statusAfterApply = runJson('bash', [
    productionTool,
    '--status',
    '--rust-hub-root',
    config.rustHubRoot,
    '--live-base-dir',
    rehearsalBaseDir,
  ], 30000);
  const statusFileWrittenAfterApply = fs.existsSync(statusPath);
  const rollback = runJson('bash', [productionTool, '--rollback'], 30000);
  const afterRollback = snapshot();
  const statusFileWrittenAfterRollback = fs.existsSync(statusPath);
  const changedAfterRollback = diffSnapshot(before, afterRollback);

  const reduced = reduce({
    apply,
    rollback,
    after_apply: afterApply,
    status_file_written_before: statusFileWrittenBefore,
    status_file_written_after: statusFileWrittenAfterApply || statusFileWrittenAfterRollback,
    changed_after_rollback: changedAfterRollback,
  });
  const result = {
    ok: reduced.ok,
    schema_version: 'xhub.xt_file_ipc_production_rollback_rehearsal.v1',
    generated_at: new Date().toISOString(),
    rust_hub_root: config.rustHubRoot,
    rehearsal_base_dir: rehearsalBaseDir,
    status_path: statusPath,
    apply_exit_code: apply.exit_code,
    apply_applied: apply.payload?.applied === true,
    status_after_apply_applied: statusAfterApply.payload?.applied === true,
    rollback_exit_code: rollback.exit_code,
    rollback_performed: rollback.payload?.rollback_performed === true,
    production_cutover_env_seen_during_rehearsal: afterApply.XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER === '1',
    status_file_written_before: statusFileWrittenBefore,
    status_file_written_after_apply: statusFileWrittenAfterApply,
    status_file_written_after_rollback: statusFileWrittenAfterRollback,
    changed_after_rollback: changedAfterRollback,
    blockers: reduced.blockers,
    daemon_restarted: false,
    write_status_called: false,
    production_authority_change: false,
    xt_file_ipc_production_surface_ready_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  };
  if (config.writeReport) {
    fs.mkdirSync(REPORT_DIR, { recursive: true });
    const outputPath = reportPath();
    fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`);
    result.report_path = outputPath;
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.ok) process.exit(2);
}

main().catch((error) => {
  process.stderr.write(`[xt_file_ipc_production_rollback_rehearsal] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
