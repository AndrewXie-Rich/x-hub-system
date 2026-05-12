#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const DEFAULT_HTTP_BASE_URL = 'http://127.0.0.1:50151';
const DEFAULT_LIVE_BASE_DIR = path.join(process.env.HOME || '', 'Library', 'Group Containers', 'group.rel.flowhub');
const EXPECTED_BLOCKERS = [
  'manual_live_cutover_approval_required',
  'daemon_relaunch_required_after_apply_before_write_status',
  'post_apply_write_status_smoke_required',
];

function parseArgs(argv) {
  const out = {
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: DEFAULT_HTTP_BASE_URL,
    liveBaseDir: DEFAULT_LIVE_BASE_DIR,
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
      case '--live-base-dir':
        out.liveBaseDir = String(next || '').trim() || out.liveBaseDir;
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
    'xt_file_ipc_live_cutover_preflight.js',
    '',
    'Options:',
    '  --rust-hub-root <p>   Expected active Rust Hub root',
    '  --http-base-url <u>   Rust xhubd HTTP base URL',
    '  --live-base-dir <p>   Live XT file IPC base dir',
    '  --no-report           Print only; do not write reports/',
    '  --self-test           Validate reducer logic',
  ].join('\n');
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function getJson(url, timeoutMs = 5000) {
  return new Promise((resolve) => {
    const req = http.get(url, { timeout: timeoutMs }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          resolve({ ok: res.statusCode >= 200 && res.statusCode < 300, status_code: res.statusCode, body: JSON.parse(data), error: '' });
        } catch (error) {
          resolve({ ok: false, status_code: res.statusCode, body: null, error: String(error.message || error) });
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (error) => resolve({ ok: false, status_code: 0, body: null, error: String(error.message || error) }));
  });
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
      maxBuffer: 16 * 1024 * 1024,
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

function liveBaseSnapshot(liveBaseDir) {
  const baseDir = path.resolve(String(liveBaseDir || '').trim());
  const statusPath = path.join(baseDir, 'hub_status.json');
  const ipcPath = path.join(baseDir, 'ipc_events');
  const tempDir = baseDir === '/tmp' || baseDir === '/private/tmp' || baseDir.startsWith('/tmp/') || baseDir.startsWith('/private/tmp/');
  const baseExists = fs.existsSync(baseDir);
  const baseDirectory = baseExists && fs.statSync(baseDir).isDirectory();
  const statusExists = fs.existsSync(statusPath);
  const statusStat = statusExists ? fs.statSync(statusPath) : null;
  const statusText = statusExists ? fs.readFileSync(statusPath) : Buffer.from('');
  let statusJson = null;
  let statusJsonParseOk = false;
  if (statusExists) {
    try {
      statusJson = JSON.parse(statusText.toString('utf8'));
      statusJsonParseOk = true;
    } catch {
      statusJsonParseOk = false;
    }
  }
  return {
    base_dir: baseDir,
    base_exists: baseExists,
    base_directory: baseDirectory,
    base_temp_dir: tempDir,
    status_path: statusPath,
    status_exists: statusExists,
    status_size_bytes: statusStat?.size || 0,
    status_mtime_ms: statusStat ? Math.round(statusStat.mtimeMs) : 0,
    status_sha256: statusExists ? crypto.createHash('sha256').update(statusText).digest('hex') : '',
    status_json_parse_ok: statusJsonParseOk,
    status_summary: statusJsonParseOk ? {
      pid_present: Number(statusJson?.pid || 0) > 0,
      ipc_mode: String(statusJson?.ipcMode || ''),
      ipc_path_present: String(statusJson?.ipcPath || '') !== '',
      base_dir_present: String(statusJson?.baseDir || '') !== '',
      ai_ready: Boolean(statusJson?.aiReady),
      loaded_model_count: Number(statusJson?.loadedModelCount || 0),
    } : null,
    ipc_path: ipcPath,
    ipc_path_exists: fs.existsSync(ipcPath),
    ok: baseExists && baseDirectory && !tempDir,
  };
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `xt_file_ipc_live_cutover_preflight_${stamp}.json`);
}

async function collect(config) {
  const snapshot = liveBaseSnapshot(config.liveBaseDir);
  const blocker = runJson('bash', [
    path.join(SCRIPT_DIR, 'xt_file_ipc_production_cutover_blocker.command'),
    '--rust-hub-root', config.rustHubRoot,
    '--http-base-url', config.httpBaseUrl,
    '--live-base-dir', snapshot.base_dir,
    '--no-report',
  ], 30000);
  const rehearsal = runJson('bash', [
    path.join(SCRIPT_DIR, 'xt_file_ipc_production_rollback_rehearsal.command'),
    '--rust-hub-root', config.rustHubRoot,
    '--no-report',
  ], 60000);
  const health = await getJson(`${config.httpBaseUrl}/health`);
  const ready = await getJson(`${config.httpBaseUrl}/ready`);
  return { snapshot, blocker, rehearsal, health, ready };
}

function reduce(evidence) {
  const blockers = [];
  if (!evidence.snapshot.ok) blockers.push('live_base_snapshot_not_ok');
  if (evidence.blocker.exit_code !== 0 || evidence.blocker.payload?.ok !== true) blockers.push('cutover_blocker_failed');
  const actualBlockers = evidence.blocker.payload?.blockers || [];
  const unexpectedBlockers = actualBlockers.filter((item) => !EXPECTED_BLOCKERS.includes(item));
  const missingExpectedBlockers = EXPECTED_BLOCKERS.filter((item) => !actualBlockers.includes(item));
  if (unexpectedBlockers.length > 0) blockers.push('unexpected_cutover_blockers_present');
  if (missingExpectedBlockers.length > 0) blockers.push('expected_cutover_blockers_missing');
  if (evidence.rehearsal.exit_code !== 0 || evidence.rehearsal.payload?.ok !== true) blockers.push('rollback_rehearsal_not_clean');
  if (evidence.ready.body?.capabilities?.xt_file_ipc_production_surface_ready !== false) blockers.push('production_surface_unexpectedly_enabled');
  return { blockers, unexpectedBlockers, missingExpectedBlockers };
}

function buildPlan(config, snapshot) {
  const productionTool = path.join(SCRIPT_DIR, 'xt_file_ipc_production_session.command');
  const daemonTool = path.join(SCRIPT_DIR, 'xhubd_daemon.command');
  const liveBaseDir = snapshot.base_dir;
  return {
    apply_command: `bash ${shellQuote(productionTool)} --apply --rust-hub-root ${shellQuote(config.rustHubRoot)} --live-base-dir ${shellQuote(liveBaseDir)} --confirm-live-cutover`,
    daemon_relaunch_plan: [
      `bash ${shellQuote(daemonTool)} launchd-install --replace-running`,
      `curl -fsS ${shellQuote(`${config.httpBaseUrl}/health`)}`,
      `curl -fsS ${shellQuote(`${config.httpBaseUrl}/xt/classic-hub-compat`)}`,
    ],
    write_status_smoke_plan: [
      `curl -fsS -X POST ${shellQuote(`${config.httpBaseUrl}/xt/classic-hub-compat/write-status`)}`,
      `test -f ${shellQuote(snapshot.status_path)}`,
      `curl -fsS ${shellQuote(`${config.httpBaseUrl}/xt/classic-hub-compat`)}`,
      `bash ${shellQuote(path.join(SCRIPT_DIR, 'daemon_ops_gate.command'))} --max-slow-requests 0 --maintenance-max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30`,
    ],
    rollback_plan: [
      `bash ${shellQuote(productionTool)} --rollback`,
      `bash ${shellQuote(daemonTool)} launchd-install --replace-running`,
      `curl -fsS ${shellQuote(`${config.httpBaseUrl}/health`)}`,
    ],
  };
}

function runSelfTest() {
  const reduced = reduce({
    snapshot: { ok: true },
    blocker: { exit_code: 0, payload: { ok: true, blockers: EXPECTED_BLOCKERS } },
    rehearsal: { exit_code: 0, payload: { ok: true } },
    ready: { body: { capabilities: { xt_file_ipc_production_surface_ready: false } } },
  });
  if (reduced.blockers.length !== 0) throw new Error('clean final preflight reducer should pass');
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('xt_file_ipc_live_cutover_preflight self-test ok\n');
    return;
  }
  const evidence = await collect(config);
  const reduced = reduce(evidence);
  const result = {
    ok: reduced.blockers.length === 0,
    schema_version: 'xhub.xt_file_ipc_live_cutover_preflight.v1',
    generated_at: new Date().toISOString(),
    rust_hub_root: config.rustHubRoot,
    http_base_url: config.httpBaseUrl,
    write_before_snapshot: evidence.snapshot,
    cutover_blocker_ok: evidence.blocker.payload?.ok === true,
    cutover_blockers: evidence.blocker.payload?.blockers || [],
    unexpected_cutover_blockers: reduced.unexpectedBlockers,
    missing_expected_cutover_blockers: reduced.missingExpectedBlockers,
    rollback_rehearsal_ok: evidence.rehearsal.payload?.ok === true,
    health_ok: evidence.health.body?.ok === true,
    ready: evidence.ready.body?.ready === true,
    plan: buildPlan(config, evidence.snapshot),
    blockers: reduced.blockers,
    apply_performed: false,
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
  process.stderr.write(`[xt_file_ipc_live_cutover_preflight] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
