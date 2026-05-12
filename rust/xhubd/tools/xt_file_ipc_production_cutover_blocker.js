#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const REPORT_DIR = path.join(ROOT_DIR, 'reports');
const DEFAULT_HTTP_BASE_URL = 'http://127.0.0.1:50151';
const DEFAULT_LIVE_BASE_DIR = path.join(
  process.env.HOME || '',
  'Library',
  'Group Containers',
  'group.rel.flowhub',
);

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
    'xt_file_ipc_production_cutover_blocker.js',
    '',
    'Options:',
    '  --rust-hub-root <p>   Expected active Rust Hub root',
    '  --http-base-url <u>   Rust xhubd HTTP base URL',
    '  --live-base-dir <p>   Intended non-temp XT file IPC base dir',
    '  --no-report           Print only; do not write reports/',
    '  --self-test           Validate blocker reducer logic',
  ].join('\n');
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
          resolve({
            ok: res.statusCode >= 200 && res.statusCode < 300,
            status_code: res.statusCode,
            parsed: true,
            body: JSON.parse(data),
            error: '',
          });
        } catch (error) {
          resolve({
            ok: false,
            status_code: res.statusCode,
            parsed: false,
            body: null,
            error: String(error.message || error),
          });
        }
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('timeout'));
    });
    req.on('error', (error) => {
      resolve({ ok: false, status_code: 0, parsed: false, body: null, error: String(error.message || error) });
    });
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
    return { exit_code: exitCode, parsed: false, stderr, payload: null };
  }
}

function liveBaseDirStatus(liveBaseDir) {
  const normalized = path.resolve(String(liveBaseDir || '').trim() || DEFAULT_LIVE_BASE_DIR);
  const tempDir = normalized === '/tmp'
    || normalized === '/private/tmp'
    || normalized.startsWith('/tmp/')
    || normalized.startsWith('/private/tmp/');
  const exists = fs.existsSync(normalized);
  const directory = exists && fs.statSync(normalized).isDirectory();
  return {
    path: normalized,
    exists,
    directory,
    temp_dir: tempDir,
    status_path: path.join(normalized, 'hub_status.json'),
    ipc_path: path.join(normalized, 'ipc_events'),
    ok: exists && directory && !tempDir,
  };
}

async function collect(config) {
  const health = await getJson(`${config.httpBaseUrl}/health`);
  const ready = await getJson(`${config.httpBaseUrl}/ready`);
  const classicCompat = await getJson(`${config.httpBaseUrl}/xt/classic-hub-compat`);
  const productionSession = runJson('bash', [
    path.join(SCRIPT_DIR, 'xt_file_ipc_production_session.command'),
    '--status',
    '--rust-hub-root',
    config.rustHubRoot,
    '--live-base-dir',
    config.liveBaseDir,
  ], 30000);
  const prepSession = runJson('bash', [
    path.join(SCRIPT_DIR, 'xt_file_ipc_prep_session.command'),
    '--status',
    '--rust-hub-root',
    config.rustHubRoot,
  ], 30000);
  const uiGate = runJson('bash', [
    path.join(SCRIPT_DIR, 'ui_compatibility_no_product_ui_change_gate.command'),
  ], 30000);
  return {
    health,
    ready,
    classic_compat: classicCompat,
    production_session: productionSession,
    prep_session: prepSession,
    ui_gate: uiGate,
    live_base_dir: liveBaseDirStatus(config.liveBaseDir),
  };
}

function reduce(collected, config) {
  const readyBody = collected.ready.body || {};
  const compatBody = collected.classic_compat.body || {};
  const productionStatus = collected.production_session.payload || {};
  const prepStatus = collected.prep_session.payload || {};
  const uiStatus = collected.ui_gate.payload || {};
  const blockers = [];

  if (!collected.health.ok || collected.health.body?.ok !== true) blockers.push('rust_daemon_health_not_ok');
  if (!collected.ready.ok || readyBody.ready !== true) blockers.push('rust_daemon_readiness_not_ok');
  if (readyBody.capabilities?.xt_file_ipc_production_surface_ready !== false) {
    blockers.push('unexpected_xt_file_ipc_production_surface_ready');
  }
  if (readyBody.memory?.canonical_writer_in_rust !== false) blockers.push('memory_writer_authority_unexpected');
  if (readyBody.skills?.execution_authority_in_rust !== false) blockers.push('skills_execution_authority_unexpected');
  if (!collected.live_base_dir.ok) blockers.push('live_base_dir_not_ready_or_not_allowed');
  if (prepStatus.applied !== true) blockers.push('xt_file_ipc_prep_session_not_applied');
  if (prepStatus.production_cutover_enabled === true || prepStatus.live_base_dir_configured === true) {
    blockers.push('prep_session_contains_forbidden_live_cutover_env');
  }
  if (productionStatus.file_ipc_production_cutover_enabled === true) {
    blockers.push('production_cutover_already_enabled');
  }
  if (productionStatus.classic_status_writer_apply_enabled === true) {
    blockers.push('classic_status_writer_apply_already_enabled');
  }
  if (compatBody.ready === true || compatBody.status_writer?.can_write_now === true) {
    blockers.push('classic_compat_writer_ready_before_explicit_apply');
  }
  if (uiStatus.ok !== true || uiStatus.product_ui_change !== false || uiStatus.swift_ui_files_touched !== false) {
    blockers.push('ui_compatibility_gate_not_clean');
  }
  blockers.push('manual_live_cutover_approval_required');
  blockers.push('daemon_relaunch_required_after_apply_before_write_status');
  blockers.push('post_apply_write_status_smoke_required');

  return {
    ok: true,
    schema_version: 'xhub.xt_file_ipc_production_cutover_blocker.v1',
    generated_at: new Date().toISOString(),
    rust_hub_root: config.rustHubRoot,
    http_base_url: config.httpBaseUrl,
    production_apply_allowed: false,
    blockers,
    health_ok: collected.health.body?.ok === true,
    ready: readyBody.ready === true,
    live_base_dir: collected.live_base_dir,
    prep_session_applied: prepStatus.applied === true,
    prep_production_cutover_enabled: prepStatus.production_cutover_enabled === true,
    production_session_applied: productionStatus.applied === true,
    production_cutover_enabled: productionStatus.file_ipc_production_cutover_enabled === true,
    classic_compat_ready: compatBody.ready === true,
    classic_status_writer_can_write_now: compatBody.status_writer?.can_write_now === true,
    xt_file_ipc_production_surface_ready: readyBody.capabilities?.xt_file_ipc_production_surface_ready === true,
    required_before_apply: [
      'operator confirms XT can tolerate Rust-owned hub_status.json for the live base dir',
      'live base dir exists and is not under /tmp or /private/tmp',
      'provider/model production authority remains clean',
      'XT file IPC prep session is applied with production cutover still false',
      'daemon ops gate has 0 recent slow requests',
      'UI compatibility gate passes with no SwiftUI product files touched',
    ],
    apply_command: [
      'bash',
      path.join(SCRIPT_DIR, 'xt_file_ipc_production_session.command'),
      '--apply',
      '--rust-hub-root',
      config.rustHubRoot,
      '--live-base-dir',
      collected.live_base_dir.path,
      '--confirm-live-cutover',
    ].join(' '),
    rollback_command: [
      'bash',
      path.join(SCRIPT_DIR, 'xt_file_ipc_production_session.command'),
      '--rollback',
    ].join(' '),
    write_status_endpoint: `${config.httpBaseUrl}/xt/classic-hub-compat/write-status`,
    production_authority_change: false,
    xt_file_ipc_production_surface_ready_target: false,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
  };
}

function reportPath() {
  const stamp = new Date().toISOString().replaceAll('-', '').replaceAll(':', '').replace(/\.\d{3}Z$/, 'Z');
  return path.join(REPORT_DIR, `xt_file_ipc_production_cutover_blocker_${stamp}.json`);
}

function runSelfTest() {
  const result = reduce({
    health: { ok: true, body: { ok: true } },
    ready: {
      ok: true,
      body: {
        ready: true,
        capabilities: { xt_file_ipc_production_surface_ready: false },
        memory: { canonical_writer_in_rust: false },
        skills: { execution_authority_in_rust: false },
      },
    },
    classic_compat: { ok: true, body: { ready: false, status_writer: { can_write_now: false } } },
    production_session: { payload: { applied: false, file_ipc_production_cutover_enabled: false } },
    prep_session: { payload: { applied: true, production_cutover_enabled: false, live_base_dir_configured: false } },
    ui_gate: { payload: { ok: true, product_ui_change: false, swift_ui_files_touched: false } },
    live_base_dir: { ok: true, path: '/Users/example/Library/Group Containers/group.rel.flowhub' },
  }, parseArgs([]));
  if (result.production_apply_allowed !== false) throw new Error('production apply must remain blocked by default');
  if (!result.blockers.includes('manual_live_cutover_approval_required')) throw new Error('manual approval blocker missing');
  if (result.memory_writer_authority_target !== false) throw new Error('memory authority must stay false');
  if (result.skills_execution_authority_target !== false) throw new Error('skills authority must stay false');
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('xt_file_ipc_production_cutover_blocker self-test ok\n');
    return;
  }
  const result = reduce(await collect(config), config);
  if (config.writeReport) {
    fs.mkdirSync(REPORT_DIR, { recursive: true });
    const outputPath = reportPath();
    fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`);
    result.report_path = outputPath;
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[xt_file_ipc_production_cutover_blocker] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
