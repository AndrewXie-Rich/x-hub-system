#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const SESSION_DIR = path.join(ROOT_DIR, 'reports', 'production_live_stability');
const STATE_FILE = path.join(SESSION_DIR, 'session_state.json');
const CHECKPOINT_LOOP_STATE_FILE = path.join(SESSION_DIR, 'checkpoint_loop_state.json');
const DEFAULT_HTTP_BASE_URL = 'http://127.0.0.1:50151';
const DEFAULT_LIVE_BASE_DIR = path.join(process.env.HOME || '', 'Library', 'Group Containers', 'group.rel.flowhub');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function utcStamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function parseArgs(argv) {
  const out = {
    mode: 'status',
    httpBaseUrl: DEFAULT_HTTP_BASE_URL,
    liveBaseDir: DEFAULT_LIVE_BASE_DIR,
    durationMs: 8 * 60 * 60 * 1000,
    intervalMs: 5000,
    maxStatusAgeMs: 7000,
    statusReadTimeoutMs: 3000,
    maxSlowRequests: 0,
    checkpointDurationMs: 10000,
    checkpointLoopIntervalMs: 15 * 60 * 1000,
    maxCheckpoints: 0,
    reportPath: '',
    logPath: '',
    replace: false,
    durationProvided: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--start':
        out.mode = 'start';
        break;
      case '--status':
        out.mode = 'status';
        break;
      case '--stop':
        out.mode = 'stop';
        break;
      case '--checkpoint':
        out.mode = 'checkpoint';
        break;
      case '--start-checkpoint-loop':
        out.mode = 'startCheckpointLoop';
        break;
      case '--checkpoint-loop-worker':
        out.mode = 'checkpointLoopWorker';
        break;
      case '--checkpoint-loop-status':
        out.mode = 'checkpointLoopStatus';
        break;
      case '--stop-checkpoint-loop':
        out.mode = 'stopCheckpointLoop';
        break;
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--live-base-dir':
        out.liveBaseDir = path.resolve(String(next || '').trim() || out.liveBaseDir);
        i += 1;
        break;
      case '--duration-ms':
        out.durationMs = parseIntInRange(next, out.durationMs, 1, 24 * 60 * 60 * 1000);
        out.durationProvided = true;
        i += 1;
        break;
      case '--interval-ms':
        out.intervalMs = parseIntInRange(next, out.intervalMs, 100, 60000);
        i += 1;
        break;
      case '--max-status-age-ms':
        out.maxStatusAgeMs = parseIntInRange(next, out.maxStatusAgeMs, 500, 60000);
        i += 1;
        break;
      case '--status-read-timeout-ms':
        out.statusReadTimeoutMs = parseIntInRange(next, out.statusReadTimeoutMs, 100, 30000);
        i += 1;
        break;
      case '--max-slow-requests':
        out.maxSlowRequests = parseIntInRange(next, out.maxSlowRequests, 0, 100000);
        i += 1;
        break;
      case '--checkpoint-duration-ms':
        out.checkpointDurationMs = parseIntInRange(next, out.checkpointDurationMs, 1, 60 * 60 * 1000);
        i += 1;
        break;
      case '--checkpoint-interval-ms':
        out.checkpointLoopIntervalMs = parseIntInRange(next, out.checkpointLoopIntervalMs, 1000, 24 * 60 * 60 * 1000);
        i += 1;
        break;
      case '--max-checkpoints':
        out.maxCheckpoints = parseIntInRange(next, out.maxCheckpoints, 0, 100000);
        i += 1;
        break;
      case '--report-path':
        out.reportPath = path.resolve(String(next || '').trim());
        i += 1;
        break;
      case '--log-path':
        out.logPath = path.resolve(String(next || '').trim());
        i += 1;
        break;
      case '--replace':
        out.replace = true;
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
    'production_live_stability_session.js',
    '',
    'Options:',
    '  --start                       Start a detached live stability gate session',
    '  --status                      Inspect the last/active stability session (default)',
    '  --stop                        Send SIGTERM to the active stability session',
    '  --checkpoint                  Run an immediate short stability checkpoint while a long session runs',
    '  --start-checkpoint-loop        Start a detached rolling checkpoint sidecar',
    '  --checkpoint-loop-status       Inspect the rolling checkpoint sidecar',
    '  --stop-checkpoint-loop         Send SIGTERM to the rolling checkpoint sidecar',
    '  --duration-ms <ms>             Default 28800000 (8h), max 86400000 (24h)',
    '  --interval-ms <ms>             Default 5000',
    '  --max-status-age-ms <ms>       Default 7000',
    '  --status-read-timeout-ms <ms>  Default 3000',
    '  --max-slow-requests <n>        Default 0',
    '  --checkpoint-duration-ms <ms>  Rolling sidecar checkpoint duration, default 10000',
    '  --checkpoint-interval-ms <ms>  Rolling sidecar interval, default 900000',
    '  --max-checkpoints <n>          Optional sidecar checkpoint count cap, default 0',
    '  --http-base-url <u>            Default http://127.0.0.1:50151',
    '  --live-base-dir <p>            Default ~/Library/Group Containers/group.rel.flowhub',
    '  --report-path <p>              Override top-level gate report path',
    '  --log-path <p>                 Override session stdout/stderr log path',
    '  --replace                      Stop an existing active session before start',
  ].join('\n');
}

function parseJsonObject(stdout) {
  const text = String(stdout || '').trim();
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end <= start) throw new Error('no JSON object found in command output');
  return JSON.parse(text.slice(start, end + 1));
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJsonFile(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function writeState(state) {
  ensureDir(path.dirname(STATE_FILE));
  fs.writeFileSync(STATE_FILE, `${JSON.stringify(state, null, 2)}\n`);
}

function writeCheckpointLoopState(state) {
  ensureDir(path.dirname(CHECKPOINT_LOOP_STATE_FILE));
  fs.writeFileSync(CHECKPOINT_LOOP_STATE_FILE, `${JSON.stringify(state, null, 2)}\n`);
}

function isPidRunning(pid) {
  const value = Number(pid || 0);
  if (!Number.isInteger(value) || value <= 1) return false;
  try {
    process.kill(value, 0);
    return true;
  } catch {
    return false;
  }
}

function extractFlagValue(command, flag) {
  const marker = ` ${flag} `;
  let start = String(command || '').indexOf(marker);
  if (start === -1 && String(command || '').startsWith(`${flag} `)) start = 0 - 1;
  if (start === -1) return '';
  const valueStart = start + marker.length;
  const rest = String(command || '').slice(valueStart);
  const nextFlag = rest.search(/ --[A-Za-z0-9-]+(?:\s|$)/);
  return (nextFlag >= 0 ? rest.slice(0, nextFlag) : rest).trim();
}

function discoverRunningGateProcess() {
  let rows = [];
  try {
    rows = execFileSync('ps', ['ax', '-o', 'pid=,command='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 8 * 1024 * 1024,
    }).split('\n').map((line) => line.trim()).filter(Boolean);
  } catch {
    return null;
  }
  const candidates = rows
    .map((line) => {
      const match = line.match(/^(\d+)\s+([\s\S]*)$/);
      if (!match) return null;
      return { pid: Number(match[1]), command: match[2] };
    })
    .filter(Boolean)
    .filter((item) => item.pid !== process.pid)
    .filter((item) => item.command.includes('production_live_stability_gate.js'))
    .filter((item) => !item.command.includes('production_live_stability_session.js'))
    .filter((item) => isPidRunning(item.pid));
  if (candidates.length === 0) return null;
  candidates.sort((a, b) => b.pid - a.pid);
  const chosen = candidates[0];
  const startedAtIso = processStartIso(chosen.pid);
  const durationMs = Number(extractFlagValue(chosen.command, '--duration-ms') || 0);
  const startedAtMs = Date.parse(startedAtIso) || 0;
  const expectedEndAtIso = startedAtMs > 0 && durationMs > 0
    ? new Date(startedAtMs + durationMs).toISOString()
    : '';
  return {
    pid: chosen.pid,
    command: chosen.command,
    started_at_iso: startedAtIso,
    expected_end_at_iso: expectedEndAtIso,
    report_path: extractFlagValue(chosen.command, '--report-path'),
    http_base_url: extractFlagValue(chosen.command, '--http-base-url'),
    live_base_dir: extractFlagValue(chosen.command, '--live-base-dir'),
    duration_ms: durationMs,
    interval_ms: Number(extractFlagValue(chosen.command, '--interval-ms') || 0),
    max_status_age_ms: Number(extractFlagValue(chosen.command, '--max-status-age-ms') || 0),
  };
}

function processStartIso(pid) {
  try {
    const raw = execFileSync('ps', ['-p', String(pid), '-o', 'lstart='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 3000,
    }).trim();
    const parsed = Date.parse(raw);
    return Number.isFinite(parsed) ? new Date(parsed).toISOString() : '';
  } catch {
    return '';
  }
}

function summarizeReport(report) {
  if (!report || typeof report !== 'object') return null;
  return {
    ok: report.ok === true,
    generated_at_iso: String(report.generated_at_iso || ''),
    duration_ms: Number(report.duration_ms || 0),
    provider_model_production_authority_effective_now: report.provider_model_production_authority_effective_now === true,
    scheduler_authority_effective_now: report.scheduler_authority_effective_now === true,
    xt_file_ipc_production_surface_ready: report.xt_file_ipc_production_surface_ready === true,
    memory_writer_authority_in_rust: report.memory_writer_authority_in_rust === true,
    skills_execution_authority_in_rust: report.skills_execution_authority_in_rust === true,
    ui_product_change: report.ui_product_change === true,
    secret_leak: report.secret_leak === true,
    issue_count: Array.isArray(report.issues) ? report.issues.length : 0,
    warning_count: Array.isArray(report.warnings) ? report.warnings.length : 0,
    slow_request_delta_budget_ok: report.slow_request_delta_budget_ok === true,
    baseline_slow_request_carryover_ok: report.baseline_slow_request_carryover_ok === true,
    slow_request_delta: report.slow_request_delta || null,
    heartbeat: report.checks?.live_heartbeat_soak?.summary || null,
    daemon_ops_gate: report.checks?.daemon_ops_gate?.summary || null,
    production_runtime_guard: report.checks?.production_runtime_guard?.summary || null,
    process_sanity: report.checks?.process_sanity ? {
      ok: report.checks.process_sanity.ok === true,
      xhubd_process_count: Array.isArray(report.checks.process_sanity.xhubd_processes) ? report.checks.process_sanity.xhubd_processes.length : 0,
      target_xhubd_process_count: Array.isArray(report.checks.process_sanity.target_xhubd_processes) ? report.checks.process_sanity.target_xhubd_processes.length : 0,
      relflowhub_process_count: Array.isArray(report.checks.process_sanity.relflowhub_processes) ? report.checks.process_sanity.relflowhub_processes.length : 0,
      python_runtime_process_count: Array.isArray(report.checks.process_sanity.python_runtime_processes) ? report.checks.process_sanity.python_runtime_processes.length : 0,
    } : null,
  };
}

function summarizeLoopReport(report) {
  if (!report || typeof report !== 'object') return null;
  const checkpoints = Array.isArray(report.checkpoints) ? report.checkpoints : [];
  const latest = checkpoints.length > 0 ? checkpoints[checkpoints.length - 1] : null;
  return {
    ok: report.ok === true,
    generated_at_iso: String(report.generated_at_iso || ''),
    completed: report.completed === true,
    stop_requested: report.stop_requested === true,
    stop_signal: String(report.stop_signal || ''),
    next_checkpoint_at_iso: String(report.next_checkpoint_at_iso || ''),
    next_checkpoint_remaining_ms: Number(report.next_checkpoint_remaining_ms || 0),
    checkpoint_count: checkpoints.length,
    failed_checkpoint_count: checkpoints.filter((item) => item?.ok !== true).length,
    latest_checkpoint: latest,
    memory_writer_authority_in_rust: report.memory_writer_authority_in_rust === true,
    skills_execution_authority_in_rust: report.skills_execution_authority_in_rust === true,
    ui_product_change: report.ui_product_change === true,
    secret_leak: report.secret_leak === true,
    issue_count: Array.isArray(report.issues) ? report.issues.length : 0,
  };
}

function statusPayload(extra = {}) {
  const state = readJsonFile(STATE_FILE);
  const stateRunning = isPidRunning(state?.pid);
  const discovered = stateRunning ? null : discoverRunningGateProcess();
  const running = stateRunning || Boolean(discovered);
  const effectivePid = stateRunning ? Number(state?.pid || 0) : Number(discovered?.pid || state?.pid || 0);
  const stateMatchesEffectiveProcess = Boolean(state?.pid) && Number(state.pid) === effectivePid;
  const effectiveReportPath = stateRunning
    ? String(state?.report_path || '')
    : String(discovered?.report_path || state?.report_path || '');
  const report = readJsonFile(effectiveReportPath);
  const completed = Boolean(state?.pid) && !running && Boolean(report);
  const reportSummary = summarizeReport(report);
  const now = Date.now();
  const startedAtIso = stateMatchesEffectiveProcess ? String(state?.started_at_iso || '') : String(discovered?.started_at_iso || '');
  const expectedEndAtIso = stateMatchesEffectiveProcess ? String(state?.expected_end_at_iso || '') : String(discovered?.expected_end_at_iso || '');
  const startedAtMs = Date.parse(startedAtIso) || 0;
  const expectedEndAtMs = Date.parse(expectedEndAtIso) || 0;
  const elapsedMs = startedAtMs > 0 ? Math.max(0, now - startedAtMs) : 0;
  const remainingMs = running && expectedEndAtMs > 0 ? Math.max(0, expectedEndAtMs - now) : 0;
  return {
    ok: true,
    schema_version: 'xhub.rust_hub.production_live_stability_session.v1',
    command: 'status',
    generated_at_iso: new Date().toISOString(),
    state_file: STATE_FILE,
    state_exists: Boolean(state),
    running,
    running_discovered_by_process_scan: !stateRunning && Boolean(discovered),
    completed,
    completed_ok: completed ? report?.ok === true : false,
    pid: effectivePid,
    started_at_iso: startedAtIso,
    expected_end_at_iso: expectedEndAtIso,
    elapsed_ms: elapsedMs,
    remaining_ms: remainingMs,
    duration_ms: Number((stateRunning ? state?.duration_ms : discovered?.duration_ms) || state?.duration_ms || 0),
    interval_ms: Number((stateRunning ? state?.interval_ms : discovered?.interval_ms) || state?.interval_ms || 0),
    max_status_age_ms: Number((stateRunning ? state?.max_status_age_ms : discovered?.max_status_age_ms) || state?.max_status_age_ms || 0),
    report_path: effectiveReportPath,
    report_exists: Boolean(report),
    report_summary: reportSummary,
    log_path: stateMatchesEffectiveProcess ? String(state?.log_path || '') : '',
    log_exists: stateMatchesEffectiveProcess && state?.log_path ? fs.existsSync(state.log_path) : false,
    production_authority_change: false,
    memory_writer_authority_in_rust: reportSummary?.memory_writer_authority_in_rust === true,
    skills_execution_authority_in_rust: reportSummary?.skills_execution_authority_in_rust === true,
    ui_product_change: reportSummary?.ui_product_change === true,
    secret_leak: reportSummary?.secret_leak === true,
    ...extra,
  };
}

function stopActive(reason = 'stop_requested') {
  const state = readJsonFile(STATE_FILE);
  if (!state?.pid || !isPidRunning(state.pid)) {
    return { stopped: false, reason: 'no_active_session' };
  }
  process.kill(Number(state.pid), 'SIGTERM');
  writeState({ ...state, stop_requested_at_iso: new Date().toISOString(), stop_reason: reason });
  return { stopped: true, pid: Number(state.pid), reason };
}

function startSession(config) {
  const existing = readJsonFile(STATE_FILE);
  if (existing?.pid && isPidRunning(existing.pid)) {
    if (!config.replace) {
      return {
        ...statusPayload(),
        ok: false,
        command: 'start',
        started: false,
        issues: ['production_live_stability_session_already_running'],
      };
    }
    stopActive('replace_requested');
  }
  ensureDir(SESSION_DIR);
  ensureDir(path.join(ROOT_DIR, 'logs'));
  const stamp = utcStamp();
  const reportPath = config.reportPath || path.join(SESSION_DIR, `production_live_stability_gate_session_${stamp}.json`);
  const logPath = config.logPath || path.join(ROOT_DIR, 'logs', `production_live_stability_session_${stamp}.log`);
  ensureDir(path.dirname(reportPath));
  ensureDir(path.dirname(logPath));

  const args = [
    path.join(SCRIPT_DIR, 'production_live_stability_gate.js'),
    '--http-base-url', config.httpBaseUrl,
    '--live-base-dir', config.liveBaseDir,
    '--duration-ms', String(config.durationMs),
    '--interval-ms', String(config.intervalMs),
    '--max-status-age-ms', String(config.maxStatusAgeMs),
    '--status-read-timeout-ms', String(config.statusReadTimeoutMs),
    '--max-slow-requests', String(config.maxSlowRequests),
    '--report-path', reportPath,
  ];
  const fd = fs.openSync(logPath, 'a');
  const child = spawn(process.execPath, args, {
    cwd: ROOT_DIR,
    detached: true,
    stdio: ['ignore', fd, fd],
    env: process.env,
  });
  child.unref();
  fs.closeSync(fd);

  const startedAt = Date.now();
  const state = {
    schema_version: 'xhub.rust_hub.production_live_stability_session_state.v1',
    pid: child.pid,
    started_at_iso: new Date(startedAt).toISOString(),
    expected_end_at_iso: new Date(startedAt + config.durationMs).toISOString(),
    root_dir: ROOT_DIR,
    report_path: reportPath,
    log_path: logPath,
    http_base_url: config.httpBaseUrl,
    live_base_dir: config.liveBaseDir,
    duration_ms: config.durationMs,
    interval_ms: config.intervalMs,
    max_status_age_ms: config.maxStatusAgeMs,
    status_read_timeout_ms: config.statusReadTimeoutMs,
    max_slow_requests: config.maxSlowRequests,
    command: process.execPath,
    args,
    production_authority_change: false,
  };
  writeState(state);
  return {
    ...statusPayload({ command: 'start' }),
    started: true,
  };
}

function runCheckpoint(config) {
  ensureDir(SESSION_DIR);
  const status = statusPayload();
  const checkpointDurationMs = config.durationProvided ? config.durationMs : 10000;
  const stamp = utcStamp();
  const reportPath = config.reportPath || path.join(SESSION_DIR, `production_live_stability_checkpoint_${stamp}.json`);
  const args = [
    path.join(SCRIPT_DIR, 'production_live_stability_gate.js'),
    '--http-base-url', config.httpBaseUrl,
    '--live-base-dir', config.liveBaseDir,
    '--duration-ms', String(checkpointDurationMs),
    '--interval-ms', String(config.intervalMs),
    '--max-status-age-ms', String(config.maxStatusAgeMs),
    '--status-read-timeout-ms', String(config.statusReadTimeoutMs),
    '--max-slow-requests', String(config.maxSlowRequests),
    '--report-path', reportPath,
  ];
  const startedAtMs = Date.now();
  const result = spawnSync(process.execPath, args, {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    timeout: checkpointDurationMs + Math.max(30000, config.intervalMs * 4),
    maxBuffer: 128 * 1024 * 1024,
    env: process.env,
  });
  let checkpointReport = null;
  let parseError = '';
  checkpointReport = readJsonFile(reportPath);
  if (!checkpointReport) {
    try {
      checkpointReport = parseJsonObject(result.stdout);
    } catch (error) {
      parseError = String(error.message || error);
    }
  }
  const summary = summarizeReport(checkpointReport);
  const ok = result.status === 0 && checkpointReport?.ok === true;
  return {
    ok,
    schema_version: 'xhub.rust_hub.production_live_stability_session_checkpoint.v1',
    command: 'checkpoint',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAtMs,
    running_session: status.running,
    running_session_pid: status.pid,
    running_session_elapsed_ms: status.elapsed_ms,
    running_session_remaining_ms: status.remaining_ms,
    checkpoint_duration_ms: checkpointDurationMs,
    checkpoint_interval_ms: config.intervalMs,
    report_path: reportPath,
    report_exists: fs.existsSync(reportPath),
    report_summary: summary,
    exit_code: typeof result.status === 'number' ? result.status : null,
    signal: result.signal || '',
    timed_out: result.error?.code === 'ETIMEDOUT' || Boolean(result.signal),
    error: result.error ? String(result.error.message || result.error) : String(result.stderr || '').trim(),
    parse_error: parseError,
    production_authority_change: false,
    memory_writer_authority_in_rust: summary?.memory_writer_authority_in_rust === true,
    skills_execution_authority_in_rust: summary?.skills_execution_authority_in_rust === true,
    ui_product_change: summary?.ui_product_change === true,
    secret_leak: summary?.secret_leak === true,
  };
}

function sleepMs(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, ms)));
}

async function sleepUntil(targetMs, shouldStop) {
  while (Date.now() < targetMs && !shouldStop()) {
    await sleepMs(Math.min(1000, Math.max(0, targetMs - Date.now())));
  }
}

function checkpointLoopStatusPayload(extra = {}) {
  const state = readJsonFile(CHECKPOINT_LOOP_STATE_FILE);
  const running = isPidRunning(state?.pid);
  const reportPath = String(state?.report_path || '');
  const report = readJsonFile(reportPath);
  const reportSummary = summarizeLoopReport(report);
  const now = Date.now();
  const startedAtIso = String(state?.started_at_iso || '');
  const expectedEndAtIso = String(state?.expected_end_at_iso || '');
  const startedAtMs = Date.parse(startedAtIso) || 0;
  const expectedEndAtMs = Date.parse(expectedEndAtIso) || 0;
  const elapsedMs = startedAtMs > 0 ? Math.max(0, now - startedAtMs) : 0;
  const remainingMs = running && expectedEndAtMs > 0 ? Math.max(0, expectedEndAtMs - now) : 0;
  const nextCheckpointAtIso = String(report?.next_checkpoint_at_iso || state?.next_checkpoint_at_iso || '');
  const nextCheckpointAtMs = Date.parse(nextCheckpointAtIso) || 0;
  const completed = Boolean(state?.pid) && !running && report?.completed === true;
  const stopped = Boolean(state?.stop_requested_at_iso) || report?.stop_requested === true;
  const incomplete = Boolean(state?.pid) && !running && Boolean(report) && report?.completed !== true;
  return {
    ok: true,
    schema_version: 'xhub.rust_hub.production_live_stability_checkpoint_loop_status.v1',
    command: 'checkpoint-loop-status',
    generated_at_iso: new Date().toISOString(),
    state_file: CHECKPOINT_LOOP_STATE_FILE,
    state_exists: Boolean(state),
    running,
    completed,
    completed_ok: completed ? report?.ok === true : false,
    incomplete,
    stopped,
    pid: Number(state?.pid || 0),
    started_at_iso: startedAtIso,
    expected_end_at_iso: expectedEndAtIso,
    elapsed_ms: elapsedMs,
    remaining_ms: remainingMs,
    duration_ms: Number(state?.duration_ms || 0),
    checkpoint_duration_ms: Number(state?.checkpoint_duration_ms || 0),
    checkpoint_interval_ms: Number(state?.checkpoint_interval_ms || 0),
    max_checkpoints: Number(state?.max_checkpoints || 0),
    next_checkpoint_at_iso: nextCheckpointAtIso,
    next_checkpoint_remaining_ms: running && nextCheckpointAtMs > 0 ? Math.max(0, nextCheckpointAtMs - now) : 0,
    report_path: reportPath,
    report_exists: Boolean(report),
    report_summary: reportSummary,
    log_path: String(state?.log_path || ''),
    log_exists: state?.log_path ? fs.existsSync(state.log_path) : false,
    production_authority_change: false,
    memory_writer_authority_in_rust: reportSummary?.memory_writer_authority_in_rust === true,
    skills_execution_authority_in_rust: reportSummary?.skills_execution_authority_in_rust === true,
    ui_product_change: reportSummary?.ui_product_change === true,
    secret_leak: reportSummary?.secret_leak === true,
    ...extra,
  };
}

function stopCheckpointLoop(reason = 'stop_requested') {
  const state = readJsonFile(CHECKPOINT_LOOP_STATE_FILE);
  if (!state?.pid || !isPidRunning(state.pid)) {
    return { stopped: false, reason: 'no_active_checkpoint_loop' };
  }
  process.kill(Number(state.pid), 'SIGTERM');
  writeCheckpointLoopState({ ...state, stop_requested_at_iso: new Date().toISOString(), stop_reason: reason });
  return { stopped: true, pid: Number(state.pid), reason };
}

function startCheckpointLoop(config) {
  const existing = readJsonFile(CHECKPOINT_LOOP_STATE_FILE);
  if (existing?.pid && isPidRunning(existing.pid)) {
    if (!config.replace) {
      return {
        ...checkpointLoopStatusPayload(),
        ok: false,
        command: 'start-checkpoint-loop',
        started: false,
        issues: ['production_live_stability_checkpoint_loop_already_running'],
      };
    }
    stopCheckpointLoop('replace_requested');
  }
  ensureDir(SESSION_DIR);
  ensureDir(path.join(ROOT_DIR, 'logs'));
  const stamp = utcStamp();
  const reportPath = config.reportPath || path.join(SESSION_DIR, `production_live_stability_checkpoint_loop_${stamp}.json`);
  const logPath = config.logPath || path.join(ROOT_DIR, 'logs', `production_live_stability_checkpoint_loop_${stamp}.log`);
  ensureDir(path.dirname(reportPath));
  ensureDir(path.dirname(logPath));

  const args = [
    path.join(SCRIPT_DIR, 'production_live_stability_session.js'),
    '--checkpoint-loop-worker',
    '--http-base-url', config.httpBaseUrl,
    '--live-base-dir', config.liveBaseDir,
    '--duration-ms', String(config.durationMs),
    '--interval-ms', String(config.intervalMs),
    '--max-status-age-ms', String(config.maxStatusAgeMs),
    '--status-read-timeout-ms', String(config.statusReadTimeoutMs),
    '--max-slow-requests', String(config.maxSlowRequests),
    '--checkpoint-duration-ms', String(config.checkpointDurationMs),
    '--checkpoint-interval-ms', String(config.checkpointLoopIntervalMs),
    '--max-checkpoints', String(config.maxCheckpoints),
    '--report-path', reportPath,
    '--log-path', logPath,
  ];
  const fd = fs.openSync(logPath, 'a');
  const child = spawn(process.execPath, args, {
    cwd: ROOT_DIR,
    detached: true,
    stdio: ['ignore', fd, fd],
    env: process.env,
  });
  child.unref();
  fs.closeSync(fd);

  const startedAt = Date.now();
  const state = {
    schema_version: 'xhub.rust_hub.production_live_stability_checkpoint_loop_state.v1',
    pid: child.pid,
    started_at_iso: new Date(startedAt).toISOString(),
    expected_end_at_iso: new Date(startedAt + config.durationMs).toISOString(),
    root_dir: ROOT_DIR,
    report_path: reportPath,
    log_path: logPath,
    http_base_url: config.httpBaseUrl,
    live_base_dir: config.liveBaseDir,
    duration_ms: config.durationMs,
    interval_ms: config.intervalMs,
    max_status_age_ms: config.maxStatusAgeMs,
    status_read_timeout_ms: config.statusReadTimeoutMs,
    max_slow_requests: config.maxSlowRequests,
    checkpoint_duration_ms: config.checkpointDurationMs,
    checkpoint_interval_ms: config.checkpointLoopIntervalMs,
    max_checkpoints: config.maxCheckpoints,
    command: process.execPath,
    args,
    production_authority_change: false,
  };
  writeCheckpointLoopState(state);
  return {
    ...checkpointLoopStatusPayload({ command: 'start-checkpoint-loop' }),
    started: true,
  };
}

function checkpointLoopReportBase(config, startedAtMs, checkpoints, issues, completed, extra = {}) {
  const latest = checkpoints.length > 0 ? checkpoints[checkpoints.length - 1] : null;
  const nextCheckpointAtMs = Number(extra.next_checkpoint_at_ms || 0);
  const stopRequested = extra.stop_requested === true;
  return {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.production_live_stability_checkpoint_loop.v1',
    generated_at_iso: new Date().toISOString(),
    completed,
    stop_requested: stopRequested,
    stop_signal: String(extra.stop_signal || ''),
    duration_ms: Date.now() - startedAtMs,
    http_base_url: config.httpBaseUrl,
    live_base_dir: config.liveBaseDir,
    loop_duration_ms: config.durationMs,
    checkpoint_duration_ms: config.checkpointDurationMs,
    checkpoint_interval_ms: config.checkpointLoopIntervalMs,
    max_status_age_ms: config.maxStatusAgeMs,
    status_read_timeout_ms: config.statusReadTimeoutMs,
    max_slow_requests: config.maxSlowRequests,
    max_checkpoints: config.maxCheckpoints,
    started_at_iso: new Date(startedAtMs).toISOString(),
    expected_end_at_iso: String(extra.expected_end_at_iso || ''),
    next_checkpoint_at_iso: !completed && !stopRequested && nextCheckpointAtMs > 0 ? new Date(nextCheckpointAtMs).toISOString() : '',
    next_checkpoint_remaining_ms: !completed && !stopRequested && nextCheckpointAtMs > 0 ? Math.max(0, nextCheckpointAtMs - Date.now()) : 0,
    checkpoint_count: checkpoints.length,
    latest_checkpoint: latest,
    checkpoints,
    production_authority_change: false,
    memory_writer_authority_in_rust: checkpoints.some((item) => item.memory_writer_authority_in_rust === true),
    skills_execution_authority_in_rust: checkpoints.some((item) => item.skills_execution_authority_in_rust === true),
    ui_product_change: checkpoints.some((item) => item.ui_product_change === true),
    secret_leak: checkpoints.some((item) => item.secret_leak === true),
    issues,
    report_path: config.reportPath,
  };
}

function writeCheckpointLoopReport(config, startedAtMs, checkpoints, issues, completed, extra = {}) {
  const report = checkpointLoopReportBase(config, startedAtMs, checkpoints, issues, completed, extra);
  ensureDir(path.dirname(config.reportPath));
  fs.writeFileSync(config.reportPath, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

async function runCheckpointLoop(config) {
  ensureDir(SESSION_DIR);
  if (!config.reportPath) {
    config.reportPath = path.join(SESSION_DIR, `production_live_stability_checkpoint_loop_${utcStamp()}.json`);
  }
  const startedAtMs = Date.now();
  const expectedEndAtMs = startedAtMs + config.durationMs;
  const expectedEndAtIso = new Date(expectedEndAtMs).toISOString();
  let stopRequested = false;
  let stopSignal = '';
  const requestStop = (signal) => {
    stopRequested = true;
    stopSignal = signal;
  };
  process.once('SIGTERM', () => requestStop('SIGTERM'));
  process.once('SIGINT', () => requestStop('SIGINT'));
  const state = {
    schema_version: 'xhub.rust_hub.production_live_stability_checkpoint_loop_state.v1',
    pid: process.pid,
    started_at_iso: new Date(startedAtMs).toISOString(),
    expected_end_at_iso: expectedEndAtIso,
    root_dir: ROOT_DIR,
    report_path: config.reportPath,
    log_path: config.logPath,
    http_base_url: config.httpBaseUrl,
    live_base_dir: config.liveBaseDir,
    duration_ms: config.durationMs,
    interval_ms: config.intervalMs,
    max_status_age_ms: config.maxStatusAgeMs,
    status_read_timeout_ms: config.statusReadTimeoutMs,
    max_slow_requests: config.maxSlowRequests,
    checkpoint_duration_ms: config.checkpointDurationMs,
    checkpoint_interval_ms: config.checkpointLoopIntervalMs,
    max_checkpoints: config.maxCheckpoints,
    production_authority_change: false,
  };
  writeCheckpointLoopState(state);

  const checkpoints = [];
  const issues = [];
  let nextCheckpointAtMs = startedAtMs;
  writeCheckpointLoopState({ ...state, next_checkpoint_at_iso: new Date(nextCheckpointAtMs).toISOString() });
  writeCheckpointLoopReport(config, startedAtMs, checkpoints, issues, false, {
    expected_end_at_iso: expectedEndAtIso,
    next_checkpoint_at_ms: nextCheckpointAtMs,
  });
  let checkpointFailed = false;
  while (Date.now() < expectedEndAtMs && !stopRequested) {
    if (config.maxCheckpoints > 0 && checkpoints.length >= config.maxCheckpoints) break;
    await sleepUntil(Math.min(nextCheckpointAtMs, expectedEndAtMs), () => stopRequested);
    if (stopRequested || Date.now() >= expectedEndAtMs) break;

    const cycle = checkpoints.length + 1;
    const checkpointStartedAtMs = Date.now();
    const checkpointReportPath = path.join(SESSION_DIR, `production_live_stability_checkpoint_loop_${utcStamp()}_cycle_${String(cycle).padStart(4, '0')}.json`);
    const checkpointPayload = runCheckpoint({
      ...config,
      durationMs: config.checkpointDurationMs,
      durationProvided: true,
      reportPath: checkpointReportPath,
    });
    const checkpoint = {
      cycle,
      ok: checkpointPayload.ok === true,
      started_at_iso: new Date(checkpointStartedAtMs).toISOString(),
      generated_at_iso: String(checkpointPayload.generated_at_iso || ''),
      duration_ms: Number(checkpointPayload.duration_ms || 0),
      report_path: checkpointReportPath,
      running_session: checkpointPayload.running_session === true,
      running_session_pid: Number(checkpointPayload.running_session_pid || 0),
      slow_request_delta_budget_ok: checkpointPayload.report_summary?.slow_request_delta_budget_ok === true,
      baseline_slow_request_carryover_ok: checkpointPayload.report_summary?.baseline_slow_request_carryover_ok === true,
      slow_request_delta: checkpointPayload.report_summary?.slow_request_delta || null,
      memory_writer_authority_in_rust: checkpointPayload.memory_writer_authority_in_rust === true,
      skills_execution_authority_in_rust: checkpointPayload.skills_execution_authority_in_rust === true,
      ui_product_change: checkpointPayload.ui_product_change === true,
      secret_leak: checkpointPayload.secret_leak === true,
      issue_count: Number(checkpointPayload.report_summary?.issue_count || 0),
      warning_count: Number(checkpointPayload.report_summary?.warning_count || 0),
      error: String(checkpointPayload.error || checkpointPayload.parse_error || ''),
    };
    checkpoints.push(checkpoint);
    if (!checkpoint.ok) {
      checkpointFailed = true;
      issues.push({
        code: 'rolling_checkpoint_failed',
        cycle,
        report_path: checkpointReportPath,
        error: checkpoint.error,
      });
      writeCheckpointLoopReport(config, startedAtMs, checkpoints, issues, false, {
        expected_end_at_iso: expectedEndAtIso,
        stop_requested: stopRequested,
        stop_signal: stopSignal,
      });
      break;
    }
    nextCheckpointAtMs = checkpointStartedAtMs + config.checkpointLoopIntervalMs;
    writeCheckpointLoopState({ ...state, next_checkpoint_at_iso: new Date(nextCheckpointAtMs).toISOString() });
    writeCheckpointLoopReport(config, startedAtMs, checkpoints, issues, false, {
      expected_end_at_iso: expectedEndAtIso,
      next_checkpoint_at_ms: nextCheckpointAtMs,
      stop_requested: stopRequested,
      stop_signal: stopSignal,
    });
  }

  if (stopRequested) {
    issues.push({ code: 'checkpoint_loop_stopped', signal: stopSignal });
  }
  if (checkpoints.length === 0) {
    issues.push({ code: 'no_rolling_checkpoints_completed' });
  }
  const completed = !stopRequested && !checkpointFailed && checkpoints.length > 0;
  const finalReport = writeCheckpointLoopReport(config, startedAtMs, checkpoints, issues, completed, {
    expected_end_at_iso: expectedEndAtIso,
    stop_requested: stopRequested,
    stop_signal: stopSignal,
  });
  writeCheckpointLoopState({
    ...state,
    completed_at_iso: new Date().toISOString(),
    checkpoint_count: checkpoints.length,
    completed: finalReport.completed === true,
    completed_ok: finalReport.completed === true && finalReport.ok === true,
    stop_requested: stopRequested,
    stop_signal: stopSignal,
  });
  return finalReport;
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.mode === 'start') {
    const payload = startSession(config);
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    if (!payload.ok) process.exit(2);
    return;
  }
  if (config.mode === 'stop') {
    const stopped = stopActive();
    const payload = statusPayload({ command: 'stop', ...stopped });
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    return;
  }
  if (config.mode === 'checkpoint') {
    const payload = runCheckpoint(config);
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    if (!payload.ok) process.exit(2);
    return;
  }
  if (config.mode === 'startCheckpointLoop') {
    const payload = startCheckpointLoop(config);
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    if (!payload.ok) process.exit(2);
    return;
  }
  if (config.mode === 'stopCheckpointLoop') {
    const stopped = stopCheckpointLoop();
    const payload = checkpointLoopStatusPayload({ command: 'stop-checkpoint-loop', ...stopped });
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    return;
  }
  if (config.mode === 'checkpointLoopStatus') {
    process.stdout.write(`${JSON.stringify(checkpointLoopStatusPayload(), null, 2)}\n`);
    return;
  }
  if (config.mode === 'checkpointLoopWorker') {
    const payload = await runCheckpointLoop(config);
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    if (!payload.ok) process.exit(2);
    return;
  }
  process.stdout.write(`${JSON.stringify(statusPayload(), null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[production_live_stability_session] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
