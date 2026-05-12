#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function safeString(value) {
  return String(value ?? '').trim();
}

function utcStamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseBool(value, fallback = false) {
  if (value == null) return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (!normalized) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  return fallback;
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith('--')) {
      args._.push(item);
      continue;
    }
    const eq = item.indexOf('=');
    if (eq > 2) {
      args[item.slice(2, eq)] = item.slice(eq + 1);
      continue;
    }
    const key = item.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith('--')) {
      args[key] = next;
      i += 1;
    } else {
      args[key] = true;
    }
  }
  return args;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function pathFromRoot(value) {
  const raw = safeString(value);
  if (!raw) return '';
  return path.isAbsolute(raw) ? raw : path.join(ROOT_DIR, raw);
}

function isLoopbackHost(host) {
  const normalized = safeString(host).replace(/^\[/, '').replace(/\]$/, '').toLowerCase();
  return normalized === 'localhost' || normalized === '::1' || normalized.startsWith('127.');
}

function isWildcardHost(host) {
  const normalized = safeString(host).replace(/^\[/, '').replace(/\]$/, '').toLowerCase();
  return normalized === '0.0.0.0' || normalized === '::' || normalized === '';
}

function discoverLanHost() {
  const interfaces = os.networkInterfaces();
  for (const records of Object.values(interfaces)) {
    for (const item of records || []) {
      if (item?.family === 'IPv4' && !item.internal && safeString(item.address)) {
        return item.address;
      }
    }
  }
  return '';
}

function readJsonFile(filePath) {
  if (!safeString(filePath) || !fs.existsSync(filePath)) return {};
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch (error) {
    throw new Error(`invalid_profile_file:${filePath}:${error.message}`);
  }
}

function resolveProfileFile(args = {}, env = process.env) {
  const explicit = safeString(args['profile-file'] || env.XHUB_RUST_DAEMON_PROFILE_FILE);
  if (explicit) return path.resolve(explicit);
  const profileName = safeString(args.profile || env.XHUB_RUST_DAEMON_PROFILE) || 'local';
  const candidate = path.join(ROOT_DIR, 'config', `daemon_profile.${profileName}.json`);
  if (fs.existsSync(candidate)) return candidate;
  if (profileName === 'local') return path.join(ROOT_DIR, 'config', 'daemon_profile.local.json');
  return '';
}

function firstValue(values) {
  for (const value of values) {
    if (value !== undefined && value !== null && safeString(value) !== '') return value;
  }
  return undefined;
}

function resolveConfig(args = {}, env = process.env) {
  const profileFile = resolveProfileFile(args, env);
  const profileConfig = readJsonFile(profileFile);
  const profile = safeString(firstValue([args.profile, env.XHUB_RUST_DAEMON_PROFILE, profileConfig.profile])) || 'local';
  const allowLan = profile === 'lan'
    || parseBool(firstValue([args['allow-lan'], env.XHUB_RUST_HUB_ALLOW_LAN, profileConfig.allow_lan, profileConfig.allowLan]), false);
  const defaultHost = profile === 'lan' ? '0.0.0.0' : '127.0.0.1';
  const host = safeString(firstValue([args.host, env.XHUB_RUST_HUB_HOST, profileConfig.host])) || defaultHost;
  const port = parseIntInRange(firstValue([args.port, env.XHUB_RUST_HUB_HTTP_PORT, profileConfig.port]), 50151, 1, 65535);
  const connectHost = isWildcardHost(host) ? '127.0.0.1' : host;
  const discoveredPublicHost = profile === 'lan' ? discoverLanHost() : '';
  const publicHost = safeString(firstValue([args['public-host'], env.XHUB_RUST_HUB_PUBLIC_HOST, profileConfig.public_host, profileConfig.publicHost]))
    || discoveredPublicHost
    || connectHost;
  const runDir = path.resolve(pathFromRoot(firstValue([args['run-dir'], env.XHUB_RUST_DAEMON_RUN_DIR, profileConfig.run_dir, profileConfig.runDir])) || path.join(ROOT_DIR, 'run'));
  const logDir = path.resolve(pathFromRoot(firstValue([args['log-dir'], env.XHUB_RUST_DAEMON_LOG_DIR, profileConfig.log_dir, profileConfig.logDir])) || path.join(ROOT_DIR, 'logs'));
  const pidFile = path.resolve(pathFromRoot(firstValue([args['pid-file'], env.XHUB_RUST_DAEMON_PID_FILE, profileConfig.pid_file, profileConfig.pidFile])) || path.join(runDir, 'xhubd.pid'));
  const dbPath = path.resolve(pathFromRoot(firstValue([args['db-path'], env.HUB_DB_PATH, profileConfig.db_path, profileConfig.dbPath])) || path.join(ROOT_DIR, 'data', 'hub.sqlite3'));
  const runtimeBaseDir = path.resolve(pathFromRoot(firstValue([args['runtime-base-dir'], env.HUB_RUNTIME_BASE_DIR, profileConfig.runtime_base_dir, profileConfig.runtimeBaseDir])) || path.join(ROOT_DIR, 'runtime'));
  const memoryDir = path.resolve(pathFromRoot(firstValue([args['memory-dir'], env.XHUB_RUST_MEMORY_DIR, profileConfig.memory_dir, profileConfig.memoryDir])) || path.join(ROOT_DIR, 'data', 'memory'));
  const skillsDir = path.resolve(pathFromRoot(firstValue([args['skills-dir'], env.XHUB_RUST_SKILLS_DIR, profileConfig.skills_dir, profileConfig.skillsDir])) || path.join(ROOT_DIR, 'skills'));
  const accessKeyFileRaw = firstValue([
    args['access-key-file'],
    env.XHUB_RUST_HTTP_ACCESS_KEY_FILE,
    env.XHUB_RUST_HUB_ACCESS_KEY_FILE,
    profileConfig.access_key_file,
    profileConfig.accessKeyFile,
  ]);
  const accessKeyFile = safeString(accessKeyFileRaw)
    ? path.resolve(pathFromRoot(accessKeyFileRaw))
    : '';
  const httpRequireAccessKey = parseBool(firstValue([
    args['require-access-key'],
    env.XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY,
    profileConfig.http_require_access_key,
    profileConfig.httpRequireAccessKey,
  ]), false);
  const runner = path.resolve(pathFromRoot(firstValue([args.runner, env.XHUB_RUST_HUB_RUNNER, profileConfig.runner])) || path.join(ROOT_DIR, 'tools', 'run_rust_hub.command'));
  const waitMs = parseIntInRange(firstValue([args['wait-ms'], env.XHUB_RUST_DAEMON_WAIT_MS, profileConfig.wait_ms, profileConfig.waitMs]), 10000, 250, 120000);
  const launchdLabel = safeString(firstValue([args['launchd-label'], env.XHUB_RUST_LAUNCHD_LABEL, profileConfig.launchd_label, profileConfig.launchdLabel]))
    || `com.ax.xhubd.${profile}`;
  const launchdPlistPathRaw = firstValue([
    args['plist-path'],
    env.XHUB_RUST_LAUNCHD_PLIST_PATH,
    profileConfig.launchd_plist_path,
    profileConfig.launchdPlistPath,
  ]);
  const launchdPlistPathExplicit = safeString(launchdPlistPathRaw) !== '';
  const launchdPlistPath = path.resolve(pathFromRoot(launchdPlistPathRaw) || path.join(runDir, `${launchdLabel}.plist`));
  const launchdInstallPlistPathRaw = firstValue([
    args['install-plist-path'],
    env.XHUB_RUST_LAUNCHD_INSTALL_PLIST_PATH,
    profileConfig.launchd_install_plist_path,
    profileConfig.launchdInstallPlistPath,
  ]);
  const launchdInstallPlistPath = path.resolve(
    pathFromRoot(launchdInstallPlistPathRaw)
      || path.join(os.homedir(), 'Library', 'LaunchAgents', `${launchdLabel}.plist`)
  );
  const defaultLaunchdRuntimeRoot = path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub', profile);
  const launchdRuntimeRoot = path.resolve(pathFromRoot(firstValue([
    args['launchd-runtime-root'],
    env.XHUB_RUST_LAUNCHD_RUNTIME_ROOT,
    profileConfig.launchd_runtime_root,
    profileConfig.launchdRuntimeRoot,
  ])) || defaultLaunchdRuntimeRoot);
  const defaultBinarySource = fs.existsSync(path.join(ROOT_DIR, 'target', 'release', 'xhubd'))
    ? path.join(ROOT_DIR, 'target', 'release', 'xhubd')
    : path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  const launchdBinarySource = path.resolve(pathFromRoot(firstValue([
    args['launchd-binary-source'],
    env.XHUB_RUST_LAUNCHD_BINARY_SOURCE,
    profileConfig.launchd_binary_source,
    profileConfig.launchdBinarySource,
  ])) || defaultBinarySource);
  const watchdogLaunchdLabel = safeString(firstValue([
    args['watchdog-launchd-label'],
    env.XHUB_RUST_WATCHDOG_LAUNCHD_LABEL,
    profileConfig.watchdog_launchd_label,
    profileConfig.watchdogLaunchdLabel,
  ])) || `${launchdLabel}.watchdog`;
  const watchdogLaunchdPlistPathRaw = firstValue([
    args['watchdog-plist-path'],
    env.XHUB_RUST_WATCHDOG_LAUNCHD_PLIST_PATH,
    profileConfig.watchdog_launchd_plist_path,
    profileConfig.watchdogLaunchdPlistPath,
  ]);
  const watchdogLaunchdPlistPath = path.resolve(
    pathFromRoot(watchdogLaunchdPlistPathRaw)
      || path.join(runDir, `${watchdogLaunchdLabel}.plist`)
  );
  const watchdogLaunchdInstallPlistPathRaw = firstValue([
    args['watchdog-install-plist-path'],
    env.XHUB_RUST_WATCHDOG_LAUNCHD_INSTALL_PLIST_PATH,
    profileConfig.watchdog_launchd_install_plist_path,
    profileConfig.watchdogLaunchdInstallPlistPath,
  ]);
  const watchdogLaunchdInstallPlistPath = path.resolve(
    pathFromRoot(watchdogLaunchdInstallPlistPathRaw)
      || path.join(os.homedir(), 'Library', 'LaunchAgents', `${watchdogLaunchdLabel}.plist`)
  );
  const watchdogIntervalSec = parseIntInRange(firstValue([
    args['watchdog-interval-sec'],
    env.XHUB_RUST_WATCHDOG_INTERVAL_SEC,
    profileConfig.watchdog_interval_sec,
    profileConfig.watchdogIntervalSec,
  ]), 900, 60, 86400);
  const watchdogMaxSlowRequests = parseIntInRange(firstValue([
    args['watchdog-max-slow-requests'],
    args['max-slow-requests'],
    env.XHUB_RUST_WATCHDOG_MAX_SLOW_REQUESTS,
    profileConfig.watchdog_max_slow_requests,
    profileConfig.watchdogMaxSlowRequests,
  ]), 0, 0, 1000000);
  const watchdogMaintenanceMaxLogBytes = parseIntInRange(firstValue([
    args['watchdog-maintenance-max-log-bytes'],
    args['maintenance-max-log-bytes'],
    env.XHUB_RUST_WATCHDOG_MAINTENANCE_MAX_LOG_BYTES,
    profileConfig.watchdog_maintenance_max_log_bytes,
    profileConfig.watchdogMaintenanceMaxLogBytes,
  ]), 10 * 1024 * 1024, 0, 1024 * 1024 * 1024);
  const watchdogKeepReportFiles = parseIntInRange(firstValue([
    args['watchdog-keep-report-files'],
    args['keep-report-files'],
    env.XHUB_RUST_WATCHDOG_KEEP_REPORT_FILES,
    profileConfig.watchdog_keep_report_files,
    profileConfig.watchdogKeepReportFiles,
  ]), 100, 1, 100000);
  const watchdogMaxReportAgeDays = parseIntInRange(firstValue([
    args['watchdog-max-report-age-days'],
    args['max-report-age-days'],
    env.XHUB_RUST_WATCHDOG_MAX_REPORT_AGE_DAYS,
    profileConfig.watchdog_max_report_age_days,
    profileConfig.watchdogMaxReportAgeDays,
  ]), 30, 0, 3650);
  return {
    rootDir: ROOT_DIR,
    profileFile,
    profile,
    allowLan,
    host,
    connectHost,
    publicHost,
    port,
    bindUrl: `http://${host}:${port}`,
    baseUrl: `http://${connectHost}:${port}`,
    publicBaseUrl: `http://${publicHost}:${port}`,
    runDir,
    logDir,
    pidFile,
    dbPath,
    runtimeBaseDir,
    memoryDir,
    skillsDir,
    accessKeyFile,
    httpRequireAccessKey,
    runner,
    waitMs,
    launchdLabel,
    launchdPlistPath,
    launchdInstallPlistPath,
    launchdPlistPathExplicit,
    launchdRuntimeRoot,
    launchdBinarySource,
    watchdogLaunchdLabel,
    watchdogLaunchdPlistPath,
    watchdogLaunchdInstallPlistPath,
    watchdogIntervalSec,
    watchdogMaxSlowRequests,
    watchdogMaintenanceMaxLogBytes,
    watchdogKeepReportFiles,
    watchdogMaxReportAgeDays,
  };
}

function accessKeyConfigured(config, env = process.env) {
  const raw = safeString(env.XHUB_RUST_HTTP_ACCESS_KEY || env.XHUB_RUST_HUB_ACCESS_KEY);
  if (raw) return true;
  if (!safeString(config.accessKeyFile) || !fs.existsSync(config.accessKeyFile)) return false;
  try {
    return safeString(fs.readFileSync(config.accessKeyFile, 'utf8')) !== '';
  } catch {
    return false;
  }
}

function fileModeOctal(filePath) {
  try {
    return (fs.statSync(filePath).mode & 0o777).toString(8).padStart(4, '0');
  } catch {
    return '';
  }
}

function collectAccessKeyFileState(config) {
  const filePath = config.accessKeyFile || '';
  const out = {
    path: filePath,
    configured: safeString(filePath) !== '',
    exists: false,
    non_empty: false,
    mode: '',
    mode_ok: false,
    readable: false,
    source: safeString(filePath) ? 'file' : 'none',
  };
  if (!out.configured) return out;
  try {
    const stat = fs.statSync(filePath);
    out.exists = stat.isFile();
    out.mode = fileModeOctal(filePath);
    out.mode_ok = out.mode === '0600';
    if (out.exists) {
      out.non_empty = stat.size > 0;
      fs.accessSync(filePath, fs.constants.R_OK);
      out.readable = true;
    }
  } catch {}
  return out;
}

function readPid(pidFile) {
  try {
    const value = Number.parseInt(String(fs.readFileSync(pidFile, 'utf8')).trim(), 10);
    return Number.isFinite(value) && value > 0 ? value : 0;
  } catch {
    return 0;
  }
}

function isProcessAlive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function removePidFile(pidFile) {
  try {
    fs.unlinkSync(pidFile);
  } catch {}
}

function collectPidFileState(pidFile) {
  const out = {
    path: pidFile,
    exists: false,
    pid: null,
    pid_alive: false,
    stale: false,
    invalid: false,
    repairable: false,
    error: '',
  };
  try {
    const raw = fs.readFileSync(pidFile, 'utf8');
    out.exists = true;
    const pid = Number.parseInt(String(raw).trim(), 10);
    if (!Number.isFinite(pid) || pid <= 0) {
      out.invalid = true;
      out.repairable = true;
      return out;
    }
    out.pid = pid;
    out.pid_alive = isProcessAlive(pid);
    out.stale = !out.pid_alive;
    out.repairable = out.stale;
    return out;
  } catch (error) {
    if (error?.code !== 'ENOENT') out.error = String(error.message || error);
    return out;
  }
}

function httpGetJson(url, timeoutMs = 750) {
  return new Promise((resolve, reject) => {
    const req = http.get(url, { timeout: timeoutMs, headers: { accept: 'application/json' } }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
        if (body.length > 1024 * 1024) {
          req.destroy(new Error('response_too_large'));
        }
      });
      res.on('end', () => {
        const statusCode = Number(res.statusCode || 0);
        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`http_status:${statusCode}:${body.slice(0, 240)}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${body.slice(0, 240)}`));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('http_timeout')));
    req.on('error', reject);
  });
}

async function readHealth(config) {
  const health = await httpGetJson(`${config.baseUrl}/health`, 750);
  return { ok: health?.ok === true, health };
}

async function readReady(config) {
  const readiness = await httpGetJson(`${config.baseUrl}/ready`, 1000);
  return { ok: readiness?.ready === true, readiness };
}

async function waitForHealth(config, child = null) {
  const deadline = Date.now() + config.waitMs;
  let lastError = null;
  while (Date.now() < deadline) {
    if (child && child.exitCode != null) {
      throw new Error(`xhubd_exited_before_healthy:${child.exitCode}`);
    }
    try {
      const health = await readHealth(config);
      if (health.ok) return health;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`health_timeout:${lastError?.message || lastError || 'unknown'}`);
}

function printJson(value, exitCode = 0) {
  fs.writeSync(1, `${JSON.stringify(value, null, 2)}\n`);
  process.exitCode = exitCode;
}

async function start(config) {
  if (!isLoopbackHost(config.host) && !config.allowLan) {
    printJson({
      ok: false,
      command: 'start',
      error_code: 'lan_bind_requires_explicit_allow',
      host: config.host,
      profile: config.profile,
      hint: 'Use --profile lan or --allow-lan to bind beyond localhost.',
    }, 64);
    return;
  }

  const existingPid = readPid(config.pidFile);
  if (existingPid && !isProcessAlive(existingPid)) {
    removePidFile(config.pidFile);
  }
  try {
    const health = await readHealth(config);
    if (health.ok) {
      printJson({
        ok: true,
        command: 'start',
        already_running: true,
        pid: existingPid || null,
        http_base_url: config.baseUrl,
        bind_url: config.bindUrl,
        public_base_url: config.publicBaseUrl,
        profile_file: config.profileFile || '',
        profile: config.profile,
        cross_network_bind: !isLoopbackHost(config.host),
        pid_file: config.pidFile,
        runtime_base_dir: config.runtimeBaseDir,
        memory_dir: config.memoryDir,
        skills_dir: config.skillsDir,
        http_access_key_configured: accessKeyConfigured(config),
        http_access_key_file: config.accessKeyFile || '',
        http_require_access_key: config.httpRequireAccessKey,
        health: health.health,
      });
      return;
    }
  } catch {}

  if (existingPid && isProcessAlive(existingPid)) {
    printJson({
      ok: false,
      command: 'start',
      error_code: 'pid_alive_but_health_not_ready',
      pid: existingPid,
      http_base_url: config.baseUrl,
      bind_url: config.bindUrl,
      pid_file: config.pidFile,
    }, 2);
    return;
  }

  if (!fs.existsSync(config.runner)) {
    printJson({
      ok: false,
      command: 'start',
      error_code: 'runner_missing',
      runner: config.runner,
    }, 127);
    return;
  }

  ensureDir(config.runDir);
  ensureDir(config.logDir);
  ensureDir(path.dirname(config.dbPath));
  ensureDir(config.runtimeBaseDir);
  ensureDir(config.memoryDir);
  ensureDir(config.skillsDir);
  const outFd = fs.openSync(path.join(config.logDir, 'xhubd.out.log'), 'a');
  const errFd = fs.openSync(path.join(config.logDir, 'xhubd.err.log'), 'a');
  const child = spawn(config.runner, ['serve'], {
    cwd: config.rootDir,
    detached: true,
    env: {
      ...process.env,
      XHUB_RUST_HUB_ROOT: config.rootDir,
      XHUB_RUST_HUB_HOST: config.host,
      XHUB_RUST_HUB_HTTP_PORT: String(config.port),
      XHUB_RUST_HUB_ALLOW_LAN: config.allowLan ? '1' : '0',
      XHUB_RUST_HUB_PUBLIC_HOST: config.publicHost,
      XHUB_RUST_HUB_PUBLIC_BASE_URL: config.publicBaseUrl,
      HUB_DB_PATH: config.dbPath,
      HUB_RUNTIME_BASE_DIR: config.runtimeBaseDir,
      XHUB_RUST_MEMORY_DIR: config.memoryDir,
      XHUB_RUST_SKILLS_DIR: config.skillsDir,
      XHUB_RUST_HTTP_ACCESS_KEY_FILE: config.accessKeyFile || '',
      XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY: config.httpRequireAccessKey ? '1' : '0',
    },
    stdio: ['ignore', outFd, errFd],
  });
  fs.closeSync(outFd);
  fs.closeSync(errFd);
  fs.writeFileSync(config.pidFile, `${child.pid}\n`);
  child.unref();

  try {
    const health = await waitForHealth(config, child);
    let readiness = null;
    try {
      readiness = (await readReady(config)).readiness;
    } catch {}
    printJson({
      ok: true,
      command: 'start',
      already_running: false,
      pid: child.pid,
      http_base_url: config.baseUrl,
      bind_url: config.bindUrl,
      public_base_url: config.publicBaseUrl,
      profile_file: config.profileFile || '',
      profile: config.profile,
      cross_network_bind: !isLoopbackHost(config.host),
      pid_file: config.pidFile,
      db_path: config.dbPath,
      runtime_base_dir: config.runtimeBaseDir,
      memory_dir: config.memoryDir,
      skills_dir: config.skillsDir,
      http_access_key_configured: accessKeyConfigured(config),
      http_access_key_file: config.accessKeyFile || '',
      http_require_access_key: config.httpRequireAccessKey,
      log_dir: config.logDir,
      health: health.health,
      readiness,
    });
  } catch (error) {
    printJson({
      ok: false,
      command: 'start',
      error_code: 'health_not_ready',
      error_message: String(error.message || error),
      pid: child.pid,
      http_base_url: config.baseUrl,
      bind_url: config.bindUrl,
      pid_file: config.pidFile,
      db_path: config.dbPath,
      log_dir: config.logDir,
    }, 2);
  }
}

async function health(config) {
  try {
    const out = await readHealth(config);
    printJson({
      ok: out.ok,
      command: 'health',
      running: out.ok,
      pid: readPid(config.pidFile) || null,
      http_base_url: config.baseUrl,
      bind_url: config.bindUrl,
      public_base_url: config.publicBaseUrl,
      profile_file: config.profileFile || '',
      profile: config.profile,
      cross_network_bind: !isLoopbackHost(config.host),
      http_access_key_configured: accessKeyConfigured(config),
      http_access_key_file: config.accessKeyFile || '',
      http_require_access_key: config.httpRequireAccessKey,
      pid_file: config.pidFile,
      health: out.health,
    }, out.ok ? 0 : 2);
  } catch (error) {
    printJson({
      ok: false,
      command: 'health',
      running: false,
      pid: readPid(config.pidFile) || null,
      http_base_url: config.baseUrl,
      bind_url: config.bindUrl,
      pid_file: config.pidFile,
      error_code: 'health_failed',
      error_message: String(error.message || error),
    }, 2);
  }
}

async function ready(config) {
  try {
    const out = await readReady(config);
    printJson({
      ok: out.ok,
      command: 'ready',
      ready: out.ok,
      pid: readPid(config.pidFile) || null,
      http_base_url: config.baseUrl,
      bind_url: config.bindUrl,
      public_base_url: config.publicBaseUrl,
      profile_file: config.profileFile || '',
      profile: config.profile,
      cross_network_bind: !isLoopbackHost(config.host),
      http_access_key_configured: accessKeyConfigured(config),
      http_access_key_file: config.accessKeyFile || '',
      http_require_access_key: config.httpRequireAccessKey,
      pid_file: config.pidFile,
      readiness: out.readiness,
    }, out.ok ? 0 : 2);
  } catch (error) {
    printJson({
      ok: false,
      command: 'ready',
      ready: false,
      pid: readPid(config.pidFile) || null,
      http_base_url: config.baseUrl,
      bind_url: config.bindUrl,
      pid_file: config.pidFile,
      error_code: 'ready_failed',
      error_message: String(error.message || error),
    }, 2);
  }
}

async function status(config) {
  printJson(await collectStatus(config));
}

async function collectStatus(config) {
  const pid = readPid(config.pidFile);
  let healthOut = null;
  let readinessOut = null;
  let healthError = '';
  let readinessError = '';
  try {
    healthOut = await readHealth(config);
  } catch (error) {
    healthError = String(error.message || error);
  }
  try {
    readinessOut = await readReady(config);
  } catch (error) {
    readinessError = String(error.message || error);
  }
  return {
    ok: true,
    command: 'status',
    running: healthOut?.ok === true,
    pid: pid || null,
    pid_alive: isProcessAlive(pid),
    http_base_url: config.baseUrl,
    bind_url: config.bindUrl,
    public_base_url: config.publicBaseUrl,
    profile_file: config.profileFile || '',
    profile: config.profile,
    cross_network_bind: !isLoopbackHost(config.host),
    lan_allowed: config.allowLan,
    http_access_key_configured: accessKeyConfigured(config),
    http_access_key_file: config.accessKeyFile || '',
    http_require_access_key: config.httpRequireAccessKey,
    pid_file: config.pidFile,
    db_path: config.dbPath,
    runtime_base_dir: config.runtimeBaseDir,
    memory_dir: config.memoryDir,
    skills_dir: config.skillsDir,
    log_dir: config.logDir,
    health: healthOut?.health || null,
    health_error: healthError,
    readiness: readinessOut?.readiness || null,
    readiness_error: readinessError,
  };
}

async function stop(config) {
  const result = await stopProcess(config);
  printJson(result, result.ok ? 0 : 2);
}

async function stopProcess(config) {
  const pid = readPid(config.pidFile);
  if (!pid) {
    return {
      ok: true,
      command: 'stop',
      stopped: false,
      reason: 'pid_file_missing',
      pid_file: config.pidFile,
    };
  }
  if (!isProcessAlive(pid)) {
    removePidFile(config.pidFile);
    return {
      ok: true,
      command: 'stop',
      stopped: false,
      reason: 'stale_pid',
      pid,
      pid_file: config.pidFile,
    };
  }

  process.kill(pid, 'SIGTERM');
  const deadline = Date.now() + config.waitMs;
  while (Date.now() < deadline && isProcessAlive(pid)) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const stillAlive = isProcessAlive(pid);
  if (!stillAlive) removePidFile(config.pidFile);
  return {
    ok: !stillAlive,
    command: 'stop',
    stopped: !stillAlive,
    pid,
    pid_file: config.pidFile,
    error_code: stillAlive ? 'process_still_alive_after_sigterm' : '',
  };
}

function profile(config) {
  printJson({
    ok: true,
    command: 'profile',
    schema_version: 'xhub.rust_hub.daemon_profile.resolved.v1',
    profile_file: config.profileFile || '',
    profile: config.profile,
    host: config.host,
    port: config.port,
    allow_lan: config.allowLan,
    http_base_url: config.baseUrl,
    bind_url: config.bindUrl,
    public_base_url: config.publicBaseUrl,
    db_path: config.dbPath,
    runtime_base_dir: config.runtimeBaseDir,
    memory_dir: config.memoryDir,
    skills_dir: config.skillsDir,
    http_access_key_configured: accessKeyConfigured(config),
    http_access_key_file: config.accessKeyFile || '',
    http_require_access_key: config.httpRequireAccessKey,
    run_dir: config.runDir,
    log_dir: config.logDir,
    pid_file: config.pidFile,
    runner: config.runner,
    wait_ms: config.waitMs,
    launchd_label: config.launchdLabel,
    launchd_plist_path: config.launchdPlistPath,
    launchd_install_plist_path: config.launchdInstallPlistPath,
    launchd_plist_path_explicit: config.launchdPlistPathExplicit,
    launchd_runtime_root: config.launchdRuntimeRoot,
    launchd_binary_source: config.launchdBinarySource,
    watchdog_launchd_label: config.watchdogLaunchdLabel,
    watchdog_launchd_plist_path: config.watchdogLaunchdPlistPath,
    watchdog_launchd_install_plist_path: config.watchdogLaunchdInstallPlistPath,
    watchdog_interval_sec: config.watchdogIntervalSec,
    watchdog_max_slow_requests: config.watchdogMaxSlowRequests,
    watchdog_maintenance_max_log_bytes: config.watchdogMaintenanceMaxLogBytes,
    watchdog_keep_report_files: config.watchdogKeepReportFiles,
    watchdog_max_report_age_days: config.watchdogMaxReportAgeDays,
  });
}

function xmlEscape(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function plistKeyString(key, value) {
  return `    <key>${xmlEscape(key)}</key>\n    <string>${xmlEscape(value)}</string>`;
}

const LAUNCHD_PASSTHROUGH_ENV_KEYS = [
  'XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER',
  'XHUB_RUST_XT_FILE_IPC_BASE_DIR',
  'XHUB_RUST_XT_CLASSIC_COMPAT',
  'XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT_MS',
  'XHUB_RUST_XT_CLASSIC_STATUS_WRITER_LEASE_MS',
  'XHUB_RUST_XT_CLASSIC_GRPC_PROBE',
  'XHUB_RUST_XT_CLASSIC_GRPC_HOST',
  'XHUB_RUST_XT_CLASSIC_GRPC_PORT',
  'XHUB_RUST_XT_CLASSIC_GRPC_PROBE_TIMEOUT_MS',
  'XHUB_RUST_XT_CLASSIC_GRPC_MTLS_TRANSPORT_FALLBACK',
  'XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR',
  'XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH',
  'XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT',
  'XHUB_RUST_XT_CLASSIC_FILE_IPC_READY',
  'XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER',
];

function launchctlGetenv(key) {
  if (process.platform !== 'darwin') return '';
  const result = spawnSync('launchctl', ['getenv', key], { encoding: 'utf8' });
  if (result.status !== 0) return '';
  return safeString(result.stdout);
}

function launchdPassthroughEnvironment() {
  const values = {};
  for (const key of LAUNCHD_PASSTHROUGH_ENV_KEYS) {
    const value = safeString(process.env[key]) || launchctlGetenv(key);
    if (value) values[key] = value;
  }
  return values;
}

function launchdEnvironment(config) {
  return {
    XHUB_RUST_HUB_ROOT: config.rootDir,
    XHUB_RUST_HUB_HOST: config.host,
    XHUB_RUST_HUB_HTTP_PORT: String(config.port),
    XHUB_RUST_HUB_ALLOW_LAN: config.allowLan ? '1' : '0',
    XHUB_RUST_HUB_PUBLIC_HOST: config.publicHost,
    XHUB_RUST_HUB_PUBLIC_BASE_URL: config.publicBaseUrl,
    HUB_DB_PATH: config.dbPath,
    HUB_RUNTIME_BASE_DIR: config.runtimeBaseDir,
    XHUB_RUST_MEMORY_DIR: config.memoryDir,
    XHUB_RUST_SKILLS_DIR: config.skillsDir,
    XHUB_RUST_HTTP_ACCESS_KEY_FILE: config.accessKeyFile || '',
    XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY: config.httpRequireAccessKey ? '1' : '0',
    ...launchdPassthroughEnvironment(),
  };
}

function launchdPlistXml(config) {
  const stdoutPath = path.join(config.logDir, 'xhubd.launchd.out.log');
  const stderrPath = path.join(config.logDir, 'xhubd.launchd.err.log');
  const envLines = Object.entries(launchdEnvironment(config))
    .map(([key, value]) => plistKeyString(key, value))
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${xmlEscape(config.launchdLabel)}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${xmlEscape(config.runner)}</string>
    <string>serve</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${xmlEscape(config.rootDir)}</string>
  <key>EnvironmentVariables</key>
  <dict>
${envLines}
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>${xmlEscape(stdoutPath)}</string>
  <key>StandardErrorPath</key>
  <string>${xmlEscape(stderrPath)}</string>
</dict>
</plist>
`;
}

function launchdRuntimeConfig(config) {
  const root = config.launchdRuntimeRoot;
  return {
    ...config,
    rootDir: root,
    runner: path.join(root, 'bin', 'xhubd'),
    runDir: path.join(root, 'run'),
    logDir: path.join(root, 'logs'),
    pidFile: path.join(root, 'run', 'xhubd.pid'),
    dbPath: path.join(root, 'data', 'hub.sqlite3'),
    runtimeBaseDir: path.join(root, 'runtime'),
    memoryDir: path.join(root, 'data', 'memory'),
    skillsDir: path.join(root, 'skills'),
  };
}

function copyDirectoryIfPresent(source, target, options = {}) {
  if (!fs.existsSync(source)) return false;
  if (options.onlyIfMissing && fs.existsSync(target)) return false;
  ensureDir(path.dirname(target));
  fs.cpSync(source, target, { recursive: true, force: true, preserveTimestamps: true });
  return true;
}

function signLaunchdRunner(runnerPath) {
  const result = {
    tool: '/usr/bin/codesign',
    identity: '-',
    attempted: false,
    signed: false,
    skipped_reason: '',
  };
  if (process.platform !== 'darwin') {
    result.skipped_reason = 'non_darwin';
    return result;
  }
  result.attempted = true;
  const output = spawnSync(result.tool, ['--force', '--sign', result.identity, runnerPath], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const status = Number.isInteger(output.status) ? output.status : 1;
  if (status !== 0) {
    const detail = safeString(output.stderr) || safeString(output.stdout) || `status=${status}`;
    throw new Error(`launchd_runtime_codesign_failed:${detail.slice(0, 2000)}`);
  }
  result.signed = true;
  return result;
}

function prepareLaunchdRuntime(config, options = {}) {
  const serviceConfig = launchdRuntimeConfig(config);
  const deployment = {
    runtime_root: serviceConfig.rootDir,
    runner: serviceConfig.runner,
    binary_source: config.launchdBinarySource,
    binary_sign_planned: process.platform === 'darwin',
    binary_sign_attempted: false,
    binary_signed: false,
    binary_sign_skipped_reason: options.dryRun ? 'dry_run' : '',
    assets_copied: false,
    config_copied: false,
    migrations_copied: false,
    reports_copied: false,
    data_seeded: false,
    skills_seeded: false,
  };
  if (options.dryRun) {
    return { serviceConfig, deployment };
  }
  if (!fs.existsSync(config.launchdBinarySource)) {
    throw new Error(`launchd_binary_source_missing:${config.launchdBinarySource}`);
  }
  ensureDir(path.join(serviceConfig.rootDir, 'bin'));
  ensureDir(serviceConfig.runDir);
  ensureDir(serviceConfig.logDir);
  ensureDir(serviceConfig.runtimeBaseDir);
  ensureDir(serviceConfig.memoryDir);
  ensureDir(serviceConfig.skillsDir);
  ensureDir(path.dirname(serviceConfig.dbPath));
  fs.copyFileSync(config.launchdBinarySource, serviceConfig.runner);
  fs.chmodSync(serviceConfig.runner, 0o755);
  const signResult = signLaunchdRunner(serviceConfig.runner);
  deployment.binary_sign_attempted = signResult.attempted;
  deployment.binary_signed = signResult.signed;
  deployment.binary_sign_skipped_reason = signResult.skipped_reason;
  deployment.binary_sign_tool = signResult.tool;
  deployment.binary_sign_identity = signResult.identity;
  deployment.assets_copied = copyDirectoryIfPresent(path.join(config.rootDir, 'assets'), path.join(serviceConfig.rootDir, 'assets'));
  deployment.config_copied = copyDirectoryIfPresent(path.join(config.rootDir, 'config'), path.join(serviceConfig.rootDir, 'config'));
  deployment.migrations_copied = copyDirectoryIfPresent(path.join(config.rootDir, 'migrations'), path.join(serviceConfig.rootDir, 'migrations'));
  deployment.reports_copied = copyDirectoryIfPresent(path.join(config.rootDir, 'reports'), path.join(serviceConfig.rootDir, 'reports'));
  deployment.data_seeded = copyDirectoryIfPresent(path.join(config.rootDir, 'data'), path.join(serviceConfig.rootDir, 'data'), { onlyIfMissing: true });
  deployment.skills_seeded = copyDirectoryIfPresent(path.join(config.rootDir, 'skills'), path.join(serviceConfig.rootDir, 'skills'), { onlyIfMissing: true });
  return { serviceConfig, deployment };
}

function writeLaunchdPlist(config, plistPath = config.launchdPlistPath) {
  ensureDir(config.runDir);
  ensureDir(config.logDir);
  ensureDir(path.dirname(plistPath));
  ensureDir(path.dirname(config.dbPath));
  ensureDir(config.runtimeBaseDir);
  ensureDir(config.memoryDir);
  ensureDir(config.skillsDir);
  const xml = launchdPlistXml(config);
  fs.writeFileSync(plistPath, xml, { mode: 0o644 });
  try {
    fs.chmodSync(plistPath, 0o644);
  } catch {}
  return { plistPath, xml };
}

function launchdUserDomain() {
  const uid = typeof process.getuid === 'function'
    ? process.getuid()
    : Number.parseInt(safeString(process.env.UID), 10);
  if (!Number.isFinite(uid) || uid < 0) {
    throw new Error('launchd_user_uid_unavailable');
  }
  return `gui/${uid}`;
}

function launchdServiceTarget(config) {
  return `${launchdUserDomain()}/${config.launchdLabel}`;
}

function watchdogLaunchdServiceTarget(config) {
  return `${launchdUserDomain()}/${config.watchdogLaunchdLabel}`;
}

function launchctl(args, options = {}) {
  const result = spawnSync('/bin/launchctl', args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const status = Number.isInteger(result.status) ? result.status : 1;
  const output = {
    args,
    ok: status === 0,
    status,
    stdout: safeString(result.stdout).slice(0, 2000),
    stderr: safeString(result.stderr).slice(0, 2000),
  };
  if (!output.ok && !options.allowFailure) {
    throw new Error(`launchctl_failed:${args.join(' ')}:${output.stderr || output.stdout || status}`);
  }
  return output;
}

function launchctlPid(output) {
  const text = safeString(output?.stdout);
  const match = text.match(/(?:^|\n)\s*pid\s*=\s*(\d+)\s*(?:\n|$)/);
  if (!match) return 0;
  const pid = Number.parseInt(match[1], 10);
  return Number.isFinite(pid) && pid > 0 ? pid : 0;
}

function launchdPlist(config) {
  const { plistPath } = writeLaunchdPlist(config, config.launchdPlistPath);
  printJson({
    ok: true,
    command: 'launchd-plist',
    schema_version: 'xhub.rust_hub.launchd_plist.v1',
    label: config.launchdLabel,
    plist_path: plistPath,
    launchd_install_plist_path: config.launchdInstallPlistPath,
    profile: config.profile,
    profile_file: config.profileFile || '',
    runner: config.runner,
    http_base_url: config.baseUrl,
    bind_url: config.bindUrl,
    public_base_url: config.publicBaseUrl,
    log_dir: config.logDir,
    db_path: config.dbPath,
    http_access_key_configured: accessKeyConfigured(config),
    http_access_key_file: config.accessKeyFile || '',
    http_require_access_key: config.httpRequireAccessKey,
    install_hint: `bash ${shellQuote(path.join(config.rootDir, 'tools', 'xhubd_daemon.command'))} launchd-install`,
    uninstall_hint: `bash ${shellQuote(path.join(config.rootDir, 'tools', 'xhubd_daemon.command'))} launchd-uninstall`,
    bootstrap_hint: `launchctl bootstrap ${launchdUserDomain()} ${shellQuote(plistPath)}`,
  });
}

async function launchdInstall(config, args = {}) {
  const dryRun = parseBool(args['dry-run'], false);
  const replaceRunning = parseBool(args['replace-running'], false);
  const plistPath = config.launchdInstallPlistPath;
  if (!isLoopbackHost(config.host) && !config.allowLan) {
    printJson({
      ok: false,
      command: 'launchd-install',
      error_code: 'lan_bind_requires_explicit_allow',
      host: config.host,
      profile: config.profile,
    }, 64);
    return;
  }

  let serviceConfig;
  let deployment;
  try {
    ({ serviceConfig, deployment } = prepareLaunchdRuntime(config, { dryRun }));
  } catch (error) {
    printJson({
      ok: false,
      command: 'launchd-install',
      error_code: 'launchd_runtime_prepare_failed',
      error_message: String(error.message || error),
      production_authority_change: false,
    }, 2);
    return;
  }

  const { plistPath: writtenPlistPath } = writeLaunchdPlist(serviceConfig, plistPath);
  const domain = launchdUserDomain();
  const service = launchdServiceTarget(config);
  const planned = [
    ['bootout', service],
    ['bootstrap', domain, writtenPlistPath],
    ['enable', service],
    ['kickstart', '-k', service],
  ];
  if (dryRun) {
    printJson({
      ok: true,
      command: 'launchd-install',
      dry_run: true,
      schema_version: 'xhub.rust_hub.launchd_activation.v1',
      label: config.launchdLabel,
      domain,
      service,
      plist_path: writtenPlistPath,
      runtime_root: serviceConfig.rootDir,
      runner: serviceConfig.runner,
      deployment,
      http_base_url: config.baseUrl,
      replace_running: replaceRunning,
      planned_launchctl: planned,
      production_authority_change: false,
    });
    return;
  }

  const pid = readPid(config.pidFile);
  let stop_result = null;
  const bootout = launchctl(['bootout', service], { allowFailure: true });
  if (pid && isProcessAlive(pid)) {
    if (!replaceRunning) {
      printJson({
        ok: false,
        command: 'launchd-install',
        error_code: 'manual_daemon_running',
        pid,
        pid_file: config.pidFile,
        hint: 'Retry with --replace-running to stop the manual daemon before bootstrap.',
      }, 2);
      return;
    }
    stop_result = await stopProcess(config);
    if (!stop_result.ok) {
      printJson({
        ok: false,
        command: 'launchd-install',
        error_code: 'manual_daemon_stop_failed',
        stop_result,
      }, 2);
      return;
    }
  }

  const bootstrap = launchctl(['bootstrap', domain, writtenPlistPath]);
  const enable = launchctl(['enable', service], { allowFailure: true });
  const kickstart = launchctl(['kickstart', '-k', service], { allowFailure: true });
  let healthOut = null;
  let readinessOut = null;
  try {
    healthOut = await waitForHealth(serviceConfig);
    readinessOut = (await readReady(serviceConfig)).readiness;
  } catch (error) {
    printJson({
      ok: false,
      command: 'launchd-install',
      error_code: 'launchd_started_but_health_not_ready',
      error_message: String(error.message || error),
      label: config.launchdLabel,
      domain,
      service,
      plist_path: writtenPlistPath,
      bootout,
      bootstrap,
      enable,
      kickstart,
      stop_result,
      deployment,
    }, 2);
    return;
  }

  printJson({
    ok: true,
    command: 'launchd-install',
    schema_version: 'xhub.rust_hub.launchd_activation.v1',
    label: config.launchdLabel,
    domain,
    service,
    plist_path: writtenPlistPath,
    runtime_root: serviceConfig.rootDir,
    runner: serviceConfig.runner,
    http_base_url: config.baseUrl,
    bootout,
    bootstrap,
    enable,
    kickstart,
    deployment,
    stop_result,
    health: healthOut.health,
    readiness: readinessOut,
    production_authority_change: false,
  });
}

async function launchdUninstall(config, args = {}) {
  const dryRun = parseBool(args['dry-run'], false);
  const keepPlist = parseBool(args['keep-plist'], false);
  const plistPath = config.launchdInstallPlistPath;
  const domain = launchdUserDomain();
  const service = launchdServiceTarget(config);
  const planned = [
    ['bootout', service],
    ['bootout', domain, plistPath],
  ];
  if (dryRun) {
    printJson({
      ok: true,
      command: 'launchd-uninstall',
      dry_run: true,
      schema_version: 'xhub.rust_hub.launchd_activation.v1',
      label: config.launchdLabel,
      domain,
      service,
      plist_path: plistPath,
      keep_plist: keepPlist,
      planned_launchctl: planned,
      production_authority_change: false,
    });
    return;
  }

  const bootoutService = launchctl(['bootout', service], { allowFailure: true });
  const bootoutPlist = launchctl(['bootout', domain, plistPath], { allowFailure: true });
  let plistRemoved = false;
  if (!keepPlist) {
    try {
      fs.unlinkSync(plistPath);
      plistRemoved = true;
    } catch {}
  }
  printJson({
    ok: true,
    command: 'launchd-uninstall',
    schema_version: 'xhub.rust_hub.launchd_activation.v1',
    label: config.launchdLabel,
    domain,
    service,
    plist_path: plistPath,
    bootout_service: bootoutService,
    bootout_plist: bootoutPlist,
    plist_removed: plistRemoved,
    production_authority_change: false,
  });
}

async function launchdStatus(config) {
  const out = await collectLaunchdStatus(config);
  printJson(out, out.ok ? 0 : 2);
}

async function collectLaunchdStatus(config) {
  const service = launchdServiceTarget(config);
  const serviceConfig = launchdRuntimeConfig(config);
  const launchdPrint = launchctl(['print', service], { allowFailure: true });
  const pidFilePid = readPid(serviceConfig.pidFile);
  const pid = pidFilePid || launchctlPid(launchdPrint);
  let healthOut = null;
  let readinessOut = null;
  let healthError = '';
  let readinessError = '';
  try {
    healthOut = await readHealth(config);
  } catch (error) {
    healthError = String(error.message || error);
  }
  try {
    readinessOut = await readReady(config);
  } catch (error) {
    readinessError = String(error.message || error);
  }
  return {
    ok: launchdPrint.ok || healthOut?.ok === true,
    command: 'launchd-status',
    schema_version: 'xhub.rust_hub.launchd_activation_status.v1',
    label: config.launchdLabel,
    domain: launchdUserDomain(),
    service,
    plist_path: config.launchdInstallPlistPath,
    runtime_root: serviceConfig.rootDir,
    runner: serviceConfig.runner,
    loaded: launchdPrint.ok,
    launchctl_status: launchdPrint.status,
    launchctl_error: launchdPrint.ok ? '' : launchdPrint.stderr || launchdPrint.stdout,
    running: healthOut?.ok === true,
    pid: pid || null,
    pid_source: pidFilePid ? 'pid_file' : (pid ? 'launchctl_print' : 'none'),
    pid_alive: isProcessAlive(pid),
    pid_file: serviceConfig.pidFile,
    http_base_url: config.baseUrl,
    health: healthOut?.health || null,
    health_error: healthError,
    readiness: readinessOut?.readiness || null,
    readiness_error: readinessError,
    production_authority_change: false,
  };
}

function plistArrayStrings(values) {
  return values
    .map((value) => `    <string>${xmlEscape(value)}</string>`)
    .join('\n');
}

function watchdogLaunchdProgramArgs(config) {
  const args = [
    process.execPath,
    path.join(config.rootDir, 'tools', 'xhubd_daemon.js'),
    'watchdog',
    '--profile',
    config.profile,
    '--host',
    config.host,
    '--port',
    String(config.port),
    '--launchd-label',
    config.launchdLabel,
    '--launchd-runtime-root',
    config.launchdRuntimeRoot,
    '--max-slow-requests',
    String(config.watchdogMaxSlowRequests),
    '--maintenance-max-log-bytes',
    String(config.watchdogMaintenanceMaxLogBytes),
    '--keep-report-files',
    String(config.watchdogKeepReportFiles),
    '--max-report-age-days',
    String(config.watchdogMaxReportAgeDays),
  ];
  if (safeString(config.profileFile)) {
    args.push('--profile-file', config.profileFile);
  }
  return args;
}

function watchdogLaunchdPlistXml(config) {
  const stdoutPath = path.join(config.logDir, 'xhubd.watchdog.out.log');
  const stderrPath = path.join(config.logDir, 'xhubd.watchdog.err.log');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${xmlEscape(config.watchdogLaunchdLabel)}</string>
  <key>ProgramArguments</key>
  <array>
${plistArrayStrings(watchdogLaunchdProgramArgs(config))}
  </array>
  <key>WorkingDirectory</key>
  <string>${xmlEscape(config.rootDir)}</string>
  <key>StartInterval</key>
  <integer>${config.watchdogIntervalSec}</integer>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>${xmlEscape(stdoutPath)}</string>
  <key>StandardErrorPath</key>
  <string>${xmlEscape(stderrPath)}</string>
</dict>
</plist>
`;
}

function writeWatchdogLaunchdPlist(config, plistPath = config.watchdogLaunchdPlistPath) {
  ensureDir(config.runDir);
  ensureDir(config.logDir);
  ensureDir(path.dirname(plistPath));
  const xml = watchdogLaunchdPlistXml(config);
  fs.writeFileSync(plistPath, xml, { mode: 0o644 });
  try {
    fs.chmodSync(plistPath, 0o644);
  } catch {}
  return { plistPath, xml };
}

function watchdogLaunchdPlist(config) {
  const { plistPath } = writeWatchdogLaunchdPlist(config, config.watchdogLaunchdPlistPath);
  printJson({
    ok: true,
    command: 'watchdog-plist',
    schema_version: 'xhub.rust_hub.watchdog_launchd_plist.v1',
    label: config.watchdogLaunchdLabel,
    daemon_label: config.launchdLabel,
    plist_path: plistPath,
    install_plist_path: config.watchdogLaunchdInstallPlistPath,
    interval_sec: config.watchdogIntervalSec,
    node_path: process.execPath,
    root_dir: config.rootDir,
    profile: config.profile,
    profile_file: config.profileFile || '',
    http_base_url: config.baseUrl,
    program_arguments: watchdogLaunchdProgramArgs(config),
    stdout_path: path.join(config.logDir, 'xhubd.watchdog.out.log'),
    stderr_path: path.join(config.logDir, 'xhubd.watchdog.err.log'),
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
  });
}

async function watchdogLaunchdInstall(config, args = {}) {
  const dryRun = parseBool(args['dry-run'], false);
  const plistPath = config.watchdogLaunchdInstallPlistPath;
  const domain = launchdUserDomain();
  const service = watchdogLaunchdServiceTarget(config);
  const planned = [
    ['bootout', service],
    ['bootstrap', domain, plistPath],
    ['enable', service],
  ];
  if (dryRun) {
    const preview = writeWatchdogLaunchdPlist(config, config.watchdogLaunchdPlistPath);
    printJson({
      ok: true,
      command: 'watchdog-install',
      dry_run: true,
      schema_version: 'xhub.rust_hub.watchdog_launchd_activation.v1',
      label: config.watchdogLaunchdLabel,
      daemon_label: config.launchdLabel,
      domain,
      service,
      preview_plist_path: preview.plistPath,
      install_plist_path: plistPath,
      interval_sec: config.watchdogIntervalSec,
      planned_launchctl: planned,
      production_authority_change: false,
      daemon_restarted: false,
      daemon_stopped: false,
    });
    return;
  }

  const { plistPath: writtenPlistPath } = writeWatchdogLaunchdPlist(config, plistPath);
  const bootout = launchctl(['bootout', service], { allowFailure: true });
  const bootstrap = launchctl(['bootstrap', domain, writtenPlistPath]);
  const enable = launchctl(['enable', service], { allowFailure: true });
  printJson({
    ok: true,
    command: 'watchdog-install',
    schema_version: 'xhub.rust_hub.watchdog_launchd_activation.v1',
    label: config.watchdogLaunchdLabel,
    daemon_label: config.launchdLabel,
    domain,
    service,
    plist_path: writtenPlistPath,
    interval_sec: config.watchdogIntervalSec,
    bootout,
    bootstrap,
    enable,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
  });
}

function collectWatchdogLaunchdStatus(config) {
  const service = watchdogLaunchdServiceTarget(config);
  const launchdPrint = launchctl(['print', service], { allowFailure: true });
  return {
    ok: true,
    command: 'watchdog-status',
    schema_version: 'xhub.rust_hub.watchdog_launchd_status.v1',
    label: config.watchdogLaunchdLabel,
    daemon_label: config.launchdLabel,
    domain: launchdUserDomain(),
    service,
    plist_path: config.watchdogLaunchdInstallPlistPath,
    preview_plist_path: config.watchdogLaunchdPlistPath,
    interval_sec: config.watchdogIntervalSec,
    loaded: launchdPrint.ok,
    launchctl_status: launchdPrint.status,
    launchctl_error: launchdPrint.ok ? '' : launchdPrint.stderr || launchdPrint.stdout,
    install_plist_exists: fs.existsSync(config.watchdogLaunchdInstallPlistPath),
    preview_plist_exists: fs.existsSync(config.watchdogLaunchdPlistPath),
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
  };
}

function watchdogLaunchdStatus(config) {
  const out = collectWatchdogLaunchdStatus(config);
  printJson(out);
}

function publicHostReady(config, args = {}) {
  const allowLoopback = parseBool(args['allow-loopback-public-host'], false);
  const host = safeString(config.publicHost);
  const normalized = host.toLowerCase();
  if (!host) return false;
  if (normalized === 'replace_with_lan_ip' || normalized.includes('replace_with')) return false;
  if (isWildcardHost(host)) return false;
  if (!allowLoopback && isLoopbackHost(host)) return false;
  return true;
}

async function crossNetworkReadiness(config, args = {}) {
  const startedAt = Date.now();
  const reportPath = resolveReportPath(config, args['report-path'], 'cross_network_readiness');
  const requireLiveReady = parseBool(args['require-live-ready'], false);
  const requireLaunchdLoaded = parseBool(args['require-launchd-loaded'], false);
  const requireWatchdogTimer = parseBool(args['require-watchdog-timer'], false);
  const accessKey = collectAccessKeyFileState(config);
  const uiGate = runUiCompatibilityGate(config);
  const launchdOut = await collectLaunchdStatus(config);
  const watchdogTimer = collectWatchdogLaunchdStatus(config);
  let statusOut = null;
  try {
    statusOut = await collectStatus(config);
  } catch (error) {
    statusOut = {
      ok: false,
      error_code: 'status_collect_failed',
      error_message: String(error.message || error),
    };
  }

  const readiness = statusOut?.readiness || launchdOut.readiness || null;
  const launchdXml = launchdPlistXml(config);
  const watchdogXml = watchdogLaunchdPlistXml(config);
  const launchdPlistSafe = safeString(config.accessKeyFile)
    && launchdXml.includes(config.accessKeyFile)
    && !/"XHUB_RUST_HTTP_ACCESS_KEY"\s*=/.test(launchdXml);
  const watchdogInstallable = watchdogXml.includes('StartInterval')
    && watchdogXml.includes('watchdog')
    && !watchdogXml.includes('<key>RunAtLoad</key>');

  const checks = [
    { name: 'lan_profile_or_allow_lan', ok: config.allowLan === true, blocking: true },
    { name: 'non_loopback_bind', ok: !isLoopbackHost(config.host), blocking: true },
    { name: 'public_host_ready', ok: publicHostReady(config, args), blocking: true },
    { name: 'access_key_file_configured', ok: accessKey.configured, blocking: true },
    { name: 'access_key_file_exists', ok: accessKey.exists, blocking: true },
    { name: 'access_key_file_non_empty', ok: accessKey.non_empty, blocking: true },
    { name: 'access_key_file_mode_0600', ok: accessKey.mode_ok, blocking: true },
    { name: 'launchd_plist_carries_key_file_path_only', ok: launchdPlistSafe, blocking: true },
    { name: 'watchdog_timer_installable', ok: watchdogInstallable, blocking: true },
    { name: 'ui_compatibility', ok: uiGate.ok === true, blocking: true },
    {
      name: 'cross_network_auth_gate',
      ok: readiness ? readiness?.capabilities?.cross_network_auth_gate === true : true,
      blocking: readiness !== null,
    },
    {
      name: 'memory_writer_authority_disabled',
      ok: readiness ? readiness?.memory?.canonical_writer_in_rust !== true : true,
      blocking: true,
    },
    {
      name: 'skills_execution_authority_disabled',
      ok: readiness ? readiness?.skills?.execution_authority_in_rust !== true : true,
      blocking: true,
    },
    {
      name: 'live_readiness',
      ok: !requireLiveReady || readiness?.ready === true,
      blocking: requireLiveReady,
    },
    {
      name: 'launchd_loaded',
      ok: !requireLaunchdLoaded || launchdOut.loaded === true,
      blocking: requireLaunchdLoaded,
    },
    {
      name: 'watchdog_timer_loaded',
      ok: !requireWatchdogTimer || watchdogTimer.loaded === true,
      blocking: requireWatchdogTimer,
    },
  ];
  const issues = checks
    .filter((item) => item.blocking && item.ok !== true)
    .map((item) => item.name);

  const report = {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.cross_network_readiness.v1',
    command: 'cross-network-readiness',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    profile: config.profile,
    profile_file: config.profileFile || '',
    host: config.host,
    port: config.port,
    bind_url: config.bindUrl,
    http_base_url: config.baseUrl,
    public_base_url: config.publicBaseUrl,
    require_live_ready: requireLiveReady,
    require_launchd_loaded: requireLaunchdLoaded,
    require_watchdog_timer: requireWatchdogTimer,
    access_key_file: accessKey,
    launchd_plist_installable: launchdPlistSafe,
    watchdog_timer_installable: watchdogInstallable,
    status: statusOut,
    launchd_status: launchdOut,
    watchdog_timer_status: watchdogTimer,
    ui_compatibility: uiGate,
    node_remains_authority: true,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    memory_writer_authority_in_rust: readiness?.memory?.canonical_writer_in_rust === true,
    skills_execution_authority_in_rust: readiness?.skills?.execution_authority_in_rust === true,
    key_printed: false,
    secret_leak: false,
    checks,
    issues,
    report_path: reportPath,
  };
  const serialized = JSON.stringify(report);
  report.secret_leak = /sk-[A-Za-z0-9]|api_key|access_key"\s*:\s*"(?!\[REDACTED\])|Bearer\s+(?!\[REDACTED\])\S+|[a-f0-9]{64}/i.test(serialized);
  if (report.secret_leak) {
    report.ok = false;
    report.issues.push('secret_leak');
  }
  ensureDir(path.dirname(reportPath));
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  printJson(report, report.ok ? 0 : 2);
}

function commandLine(parts) {
  return parts.map((part) => shellQuote(part)).join(' ');
}

function daemonCommand(config, command, extraArgs = []) {
  return commandLine([
    'bash',
    path.join(config.rootDir, 'tools', 'xhubd_daemon.command'),
    command,
    ...extraArgs,
  ]);
}

function crossNetworkCommonArgs(config) {
  const args = [
    '--profile',
    config.profile,
    '--host',
    config.host,
    '--port',
    String(config.port),
    '--public-host',
    config.publicHost,
  ];
  if (safeString(config.profileFile)) args.push('--profile-file', config.profileFile);
  if (safeString(config.accessKeyFile)) args.push('--access-key-file', config.accessKeyFile);
  if (safeString(config.launchdLabel)) args.push('--launchd-label', config.launchdLabel);
  if (safeString(config.launchdRuntimeRoot)) args.push('--launchd-runtime-root', config.launchdRuntimeRoot);
  if (safeString(config.watchdogLaunchdLabel)) args.push('--watchdog-launchd-label', config.watchdogLaunchdLabel);
  return args;
}

function crossNetworkInstallPlan(config) {
  const commonArgs = crossNetworkCommonArgs(config);
  const readinessCommand = commandLine([
    'bash',
    path.join(config.rootDir, 'tools', 'cross_network_readiness_gate.command'),
    ...commonArgs,
  ]);
  const installedGateCommand = commandLine([
    'bash',
    path.join(config.rootDir, 'tools', 'cross_network_installed_gate.command'),
    ...commonArgs,
  ]);
  const plan = {
    ok: true,
    schema_version: 'xhub.rust_hub.cross_network_install_plan.v1',
    command: 'cross-network-install-plan',
    generated_at_iso: new Date().toISOString(),
    profile: config.profile,
    profile_file: config.profileFile || '',
    bind_url: config.bindUrl,
    public_base_url: config.publicBaseUrl,
    access_key_file: config.accessKeyFile || '',
    access_key_configured: accessKeyConfigured(config),
    launchd_label: config.launchdLabel,
    launchd_install_plist_path: config.launchdInstallPlistPath,
    launchd_runtime_root: config.launchdRuntimeRoot,
    watchdog_launchd_label: config.watchdogLaunchdLabel,
    watchdog_install_plist_path: config.watchdogLaunchdInstallPlistPath,
    watchdog_interval_sec: config.watchdogIntervalSec,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    key_printed: false,
    secret_leak: false,
    steps: [
      {
        name: 'preflight_readiness',
        mutates: false,
        command: readinessCommand,
      },
      {
        name: 'initialize_or_repair_access_key_file',
        mutates: true,
        command: daemonCommand(config, 'access-key-init', commonArgs),
        notes: 'Creates or chmods the access-key file without printing the key.',
      },
      {
        name: 'daemon_launchd_dry_run',
        mutates: false,
        command: daemonCommand(config, 'launchd-install', [...commonArgs, '--dry-run']),
      },
      {
        name: 'watchdog_timer_dry_run',
        mutates: false,
        command: daemonCommand(config, 'watchdog-install', [...commonArgs, '--dry-run']),
      },
      {
        name: 'install_daemon_launchagent',
        mutates: true,
        command: daemonCommand(config, 'launchd-install', commonArgs),
      },
      {
        name: 'install_watchdog_timer',
        mutates: true,
        command: daemonCommand(config, 'watchdog-install', commonArgs),
      },
      {
        name: 'strict_installed_gate',
        mutates: false,
        command: installedGateCommand,
      },
    ],
    rollback_steps: [
      {
        name: 'uninstall_watchdog_timer',
        mutates: true,
        command: daemonCommand(config, 'watchdog-uninstall', commonArgs),
      },
      {
        name: 'uninstall_daemon_launchagent',
        mutates: true,
        command: daemonCommand(config, 'launchd-uninstall', commonArgs),
      },
      {
        name: 'verify_local_or_fallback_daemon',
        mutates: false,
        command: daemonCommand({ ...config, profile: 'local' }, 'launchd-status', ['--profile', 'local']),
      },
    ],
  };
  const serialized = JSON.stringify(plan);
  plan.secret_leak = /sk-[A-Za-z0-9]|api_key|access_key"\s*:\s*"(?!\[REDACTED\])|Bearer\s+(?!\[REDACTED\])\S+|[a-f0-9]{64}/i.test(serialized);
  if (plan.secret_leak) plan.ok = false;
  printJson(plan, plan.ok ? 0 : 2);
}

async function watchdogLaunchdUninstall(config, args = {}) {
  const dryRun = parseBool(args['dry-run'], false);
  const keepPlist = parseBool(args['keep-plist'], false);
  const domain = launchdUserDomain();
  const service = watchdogLaunchdServiceTarget(config);
  const plistPath = config.watchdogLaunchdInstallPlistPath;
  const planned = [
    ['bootout', service],
    ['bootout', domain, plistPath],
  ];
  if (dryRun) {
    printJson({
      ok: true,
      command: 'watchdog-uninstall',
      dry_run: true,
      schema_version: 'xhub.rust_hub.watchdog_launchd_activation.v1',
      label: config.watchdogLaunchdLabel,
      daemon_label: config.launchdLabel,
      domain,
      service,
      plist_path: plistPath,
      keep_plist: keepPlist,
      planned_launchctl: planned,
      production_authority_change: false,
      daemon_restarted: false,
      daemon_stopped: false,
    });
    return;
  }

  const bootoutService = launchctl(['bootout', service], { allowFailure: true });
  const bootoutPlist = launchctl(['bootout', domain, plistPath], { allowFailure: true });
  let plistRemoved = false;
  if (!keepPlist) {
    try {
      fs.unlinkSync(plistPath);
      plistRemoved = true;
    } catch {}
  }
  printJson({
    ok: true,
    command: 'watchdog-uninstall',
    schema_version: 'xhub.rust_hub.watchdog_launchd_activation.v1',
    label: config.watchdogLaunchdLabel,
    daemon_label: config.launchdLabel,
    domain,
    service,
    plist_path: plistPath,
    bootout_service: bootoutService,
    bootout_plist: bootoutPlist,
    plist_removed: plistRemoved,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
  });
}

function redactEvidenceText(value) {
  return String(value ?? '')
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [REDACTED]')
    .replace(/(X-XHub-Access-Key\s*[:=]\s*)[A-Za-z0-9._~+/=-]+/gi, '$1[REDACTED]')
    .replace(/(XHUB_RUST_(?:HTTP|HUB)_ACCESS_KEY\s*=\s*)[^\s]+/gi, '$1[REDACTED]')
    .replace(/("?(?:api_key|access_key|token|secret)"?\s*[:=]\s*")([^"\n]+)(")/gi, '$1[REDACTED]$3')
    .replace(/\bsk-[A-Za-z0-9][A-Za-z0-9_-]{12,}\b/g, 'sk-[REDACTED]')
    .replace(/\b[a-f0-9]{48,128}\b/gi, '[REDACTED_HEX]');
}

function tailFileEvidence(filePath, maxBytes) {
  const out = {
    path: filePath,
    exists: false,
    size_bytes: 0,
    modified_at_iso: '',
    tail_bytes: 0,
    tail_redacted: '',
    read_error: '',
  };
  try {
    const stat = fs.statSync(filePath);
    if (!stat.isFile()) {
      out.exists = true;
      out.read_error = 'not_a_file';
      return out;
    }
    out.exists = true;
    out.size_bytes = stat.size;
    out.modified_at_iso = stat.mtime.toISOString();
    const bytesToRead = Math.min(stat.size, maxBytes);
    out.tail_bytes = bytesToRead;
    if (bytesToRead <= 0) return out;
    const fd = fs.openSync(filePath, 'r');
    try {
      const buffer = Buffer.alloc(bytesToRead);
      fs.readSync(fd, buffer, 0, bytesToRead, stat.size - bytesToRead);
      out.tail_redacted = redactEvidenceText(buffer.toString('utf8'));
    } finally {
      fs.closeSync(fd);
    }
  } catch (error) {
    out.read_error = String(error.message || error);
  }
  return out;
}

function collectLogEvidence(config, maxLogBytes) {
  const serviceConfig = launchdRuntimeConfig(config);
  const dirs = Array.from(new Set([config.logDir, serviceConfig.logDir].filter(Boolean)));
  const names = [
    'xhubd.out.log',
    'xhubd.err.log',
    'xhubd.launchd.out.log',
    'xhubd.launchd.err.log',
  ];
  const files = [];
  for (const dir of dirs) {
    for (const name of names) {
      files.push(tailFileEvidence(path.join(dir, name), maxLogBytes));
    }
  }
  const totalBytes = files.reduce((sum, item) => sum + Number(item.size_bytes || 0), 0);
  return {
    max_tail_bytes_per_file: maxLogBytes,
    log_dirs: dirs,
    total_log_bytes: totalBytes,
    rotation_recommended: files.some((item) => Number(item.size_bytes || 0) > maxLogBytes * 8),
    files,
  };
}

function runUiCompatibilityGate(config) {
  const commandPath = path.join(config.rootDir, 'tools', 'ui_compatibility_no_product_ui_change_gate.command');
  if (!fs.existsSync(commandPath)) {
    return {
      ok: false,
      skipped: true,
      reason: 'ui_compatibility_gate_missing',
    };
  }
  const result = spawnSync('bash', [commandPath], {
    cwd: config.rootDir,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) {
    return {
      ok: false,
      skipped: false,
      error_code: 'ui_compatibility_gate_failed',
      stderr_tail: redactEvidenceText(safeString(result.stderr).split(/\r?\n/).slice(-20).join('\n')),
    };
  }
  try {
    const parsed = JSON.parse(result.stdout);
    return {
      ok: parsed?.ok === true
        && parsed?.product_ui_change === false
        && parsed?.swift_ui_files_touched === false
        && parsed?.rust_browser_product_ui === false,
      product_ui_change: parsed?.product_ui_change === true,
      swift_ui_files_touched: parsed?.swift_ui_files_touched === true,
      rust_browser_product_ui: parsed?.rust_browser_product_ui === true,
      rust_browser_diagnostic_only: parsed?.rust_browser_diagnostic_only === true,
    };
  } catch (error) {
    return {
      ok: false,
      skipped: false,
      error_code: `ui_compatibility_gate_invalid_json:${error.message}`,
    };
  }
}

function runXtFileIpcWatcherRunOnceSmoke(config, args = {}, reportPath = '') {
  const enabled = parseBool(args['xt-file-ipc-run-once-smoke'], false);
  const commandPath = path.join(config.rootDir, 'tools', 'xt_file_ipc_watcher_run_once_smoke.command');
  const smokeReportPath = path.join(
    path.dirname(reportPath || resolveReportPath(config, '', 'daemon_ops_gate')),
    `xt_file_ipc_watcher_run_once_smoke_${utcStamp()}.json`
  );
  if (!enabled) {
    return {
      ok: true,
      enabled: false,
      skipped: true,
      reason: 'xt_file_ipc_run_once_smoke_not_requested',
      production_authority_change: false,
    };
  }
  if (!fs.existsSync(commandPath)) {
    return {
      ok: false,
      enabled: true,
      skipped: true,
      reason: 'xt_file_ipc_run_once_smoke_missing',
      production_authority_change: false,
    };
  }
  const timeoutMs = parseIntInRange(args['xt-file-ipc-run-once-smoke-timeout-ms'], 30000, 1000, 120000);
  const result = spawnSync('bash', [
    commandPath,
    '--timeout-ms',
    String(timeoutMs),
    '--report-file',
    smokeReportPath,
  ], {
    cwd: config.rootDir,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) {
    return {
      ok: false,
      enabled: true,
      skipped: false,
      report_path: smokeReportPath,
      error_code: 'xt_file_ipc_run_once_smoke_failed',
      stdout_tail: redactEvidenceText(safeString(result.stdout).split(/\r?\n/).slice(-20).join('\n')),
      stderr_tail: redactEvidenceText(safeString(result.stderr).split(/\r?\n/).slice(-20).join('\n')),
      production_authority_change: false,
    };
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(smokeReportPath, 'utf8'));
    const checks = parsed?.checks || {};
    return {
      ok: parsed?.ok === true
        && parsed?.production_authority_change === false
        && checks?.hub_status_written === false
        && checks?.background_watcher_started === false
        && xtFileIpcShadowSmokeProductionSafe(checks)
        && checks?.ml_execution_in_rust === false,
      enabled: true,
      skipped: false,
      report_path: smokeReportPath,
      schema_version: parsed?.schema_version || '',
      checks,
      production_authority_change: parsed?.production_authority_change === true,
    };
  } catch (error) {
    return {
      ok: false,
      enabled: true,
      skipped: false,
      report_path: smokeReportPath,
      error_code: `xt_file_ipc_run_once_smoke_invalid_json:${error.message}`,
      production_authority_change: false,
    };
  }
}

function runXtFileIpcBackgroundWatcherSmoke(config, args = {}, reportPath = '') {
  const enabled = parseBool(args['xt-file-ipc-background-watcher-smoke'], false);
  const commandPath = path.join(config.rootDir, 'tools', 'xt_file_ipc_background_watcher_smoke.command');
  const smokeReportPath = path.join(
    path.dirname(reportPath || resolveReportPath(config, '', 'daemon_ops_gate')),
    `xt_file_ipc_background_watcher_smoke_${utcStamp()}.json`
  );
  if (!enabled) {
    return {
      ok: true,
      enabled: false,
      skipped: true,
      reason: 'xt_file_ipc_background_watcher_smoke_not_requested',
      production_authority_change: false,
    };
  }
  if (!fs.existsSync(commandPath)) {
    return {
      ok: false,
      enabled: true,
      skipped: true,
      reason: 'xt_file_ipc_background_watcher_smoke_missing',
      production_authority_change: false,
    };
  }
  const timeoutMs = parseIntInRange(args['xt-file-ipc-background-watcher-smoke-timeout-ms'], 30000, 1000, 120000);
  const result = spawnSync('bash', [
    commandPath,
    '--timeout-ms',
    String(timeoutMs),
    '--report-file',
    smokeReportPath,
  ], {
    cwd: config.rootDir,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) {
    return {
      ok: false,
      enabled: true,
      skipped: false,
      report_path: smokeReportPath,
      error_code: 'xt_file_ipc_background_watcher_smoke_failed',
      stdout_tail: redactEvidenceText(safeString(result.stdout).split(/\r?\n/).slice(-20).join('\n')),
      stderr_tail: redactEvidenceText(safeString(result.stderr).split(/\r?\n/).slice(-20).join('\n')),
      production_authority_change: false,
    };
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(smokeReportPath, 'utf8'));
    const checks = parsed?.checks || {};
    return {
      ok: parsed?.ok === true
        && parsed?.production_authority_change === false
        && checks?.background_start_ok === true
        && checks?.background_status_ok === true
        && checks?.background_stop_ok === true
        && checks?.lock_released === true
        && checks?.watcher_status_stopped === true
        && checks?.processor_status_shadow_only === true
        && checks?.response_fail_closed === true
        && checks?.hub_status_written === false
        && xtFileIpcShadowSmokeProductionSafe(checks)
        && checks?.ml_execution_in_rust === false,
      enabled: true,
      skipped: false,
      report_path: smokeReportPath,
      schema_version: parsed?.schema_version || '',
      checks,
      production_authority_change: parsed?.production_authority_change === true,
    };
  } catch (error) {
    return {
      ok: false,
      enabled: true,
      skipped: false,
      report_path: smokeReportPath,
      error_code: `xt_file_ipc_background_watcher_smoke_invalid_json:${error.message}`,
      production_authority_change: false,
    };
  }
}

function xtFileIpcShadowSmokeProductionSafe(checks = {}) {
  const legacyShadowReadyFalse = checks?.production_file_ipc_ready === false;
  const explicitShadowReadyFalse = checks?.shadow_processor_production_file_ipc_ready === true;
  const productionSurfaceObservationOk = checks?.production_surface_ready_observed === undefined
    || typeof checks?.production_surface_ready_observed === 'boolean';
  const productionSurfaceAccepted = checks?.production_surface_ready_accepted === undefined
    || checks?.production_surface_ready_accepted === true;
  return (legacyShadowReadyFalse || explicitShadowReadyFalse)
    && productionSurfaceObservationOk
    && productionSurfaceAccepted;
}

function resolveReportPath(config, value, prefix) {
  const raw = safeString(value);
  if (raw) return path.resolve(pathFromRoot(raw));
  return path.join(config.rootDir, 'reports', `${prefix}_${utcStamp()}.json`);
}

async function opsReport(config, args = {}) {
  const maxLogBytes = parseIntInRange(args['max-log-bytes'], 8192, 0, 1024 * 1024);
  const reportPath = resolveReportPath(config, args['report-path'], 'daemon_ops');
  const requireReady = parseBool(args['require-ready'], false);
  const startedAt = new Date();
  const statusOut = await collectStatus(config);
  const launchdOut = await collectLaunchdStatus(config);
  let httpMetrics = null;
  let httpMetricsError = '';
  try {
    httpMetrics = await httpGetJson(`${config.baseUrl}/runtime/http-metrics`, 1000);
  } catch (error) {
    httpMetricsError = String(error.message || error);
  }
  const logs = collectLogEvidence(config, maxLogBytes);
  const uiGate = runUiCompatibilityGate(config);
  const xtFileIpcRunOnceSmoke = runXtFileIpcWatcherRunOnceSmoke(config, args, reportPath);
  const xtFileIpcBackgroundWatcherSmoke = runXtFileIpcBackgroundWatcherSmoke(config, args, reportPath);
  const readiness = statusOut.readiness || launchdOut.readiness || null;
  const healthy = statusOut.running === true || launchdOut.running === true;
  const readyState = readiness?.ready === true;
  const report = {
    ok: true,
    schema_version: 'xhub.rust_hub.daemon_ops_report.v1',
    command: 'ops-report',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt.getTime(),
    profile: config.profile,
    profile_file: config.profileFile || '',
    http_base_url: config.baseUrl,
    bind_url: config.bindUrl,
    public_base_url: config.publicBaseUrl,
    healthy,
    ready: readyState,
    status: statusOut,
    launchd_status: launchdOut,
    http_metrics_ready: httpMetrics?.schema_version === 'xhub.rust_hub.http_metrics.v1',
    http_metrics_error: httpMetricsError,
    http_metrics: httpMetrics,
    slow_requests: Number(httpMetrics?.slow_requests || 0),
    total_requests: Number(httpMetrics?.total_requests || 0),
    log_evidence: logs,
    ui_compatibility: uiGate,
    xt_file_ipc_run_once_smoke: xtFileIpcRunOnceSmoke,
    xt_file_ipc_background_watcher_smoke: xtFileIpcBackgroundWatcherSmoke,
    ui_product_change: uiGate.product_ui_change === true,
    swift_ui_files_touched: uiGate.swift_ui_files_touched === true,
    rust_browser_product_ui: uiGate.rust_browser_product_ui === true,
    node_remains_authority: true,
    production_authority_change: false,
    memory_writer_authority_in_rust: readiness?.memory?.canonical_writer_in_rust === true,
    skills_execution_authority_in_rust: readiness?.skills?.execution_authority_in_rust === true,
    cross_network_auth_gate: readiness?.capabilities?.cross_network_auth_gate === true,
    xt_file_ipc_run_once_smoke_enabled: xtFileIpcRunOnceSmoke.enabled === true,
    xt_file_ipc_run_once_smoke_ok: xtFileIpcRunOnceSmoke.ok === true,
    xt_file_ipc_background_watcher_smoke_enabled: xtFileIpcBackgroundWatcherSmoke.enabled === true,
    xt_file_ipc_background_watcher_smoke_ok: xtFileIpcBackgroundWatcherSmoke.ok === true,
    secret_leak: false,
    report_path: reportPath,
  };
  const serialized = JSON.stringify(report);
  report.secret_leak = /sk-[A-Za-z0-9]|api_key|access_key"\s*:\s*"(?!\[REDACTED\])|Bearer\s+(?!\[REDACTED\])\S+/i.test(serialized);
  report.ok = report.secret_leak === false
    && report.production_authority_change === false
    && report.ui_product_change === false
    && report.swift_ui_files_touched === false
    && report.rust_browser_product_ui === false
    && report.memory_writer_authority_in_rust === false
    && report.skills_execution_authority_in_rust === false
    && report.xt_file_ipc_run_once_smoke_ok === true
    && report.xt_file_ipc_background_watcher_smoke_ok === true;
  ensureDir(path.dirname(reportPath));
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  printJson(report, (requireReady && (!healthy || !readyState)) || !report.ok ? 2 : 0);
}

function uniquePaths(values) {
  return Array.from(new Set(values.filter((value) => safeString(value)).map((value) => path.resolve(value))));
}

function maintenanceLogFiles(config) {
  const serviceConfig = launchdRuntimeConfig(config);
  const dirs = uniquePaths([config.logDir, serviceConfig.logDir]);
  const names = [
    'xhubd.out.log',
    'xhubd.err.log',
    'xhubd.launchd.out.log',
    'xhubd.launchd.err.log',
  ];
  const files = [];
  for (const dir of dirs) {
    for (const name of names) {
      files.push(path.join(dir, name));
    }
  }
  return { dirs, files };
}

function maintenanceReportDirs(config, args = {}) {
  const explicit = safeString(args['reports-dir'] || args['report-dir']);
  if (explicit) return uniquePaths([pathFromRoot(explicit)]);
  const serviceConfig = launchdRuntimeConfig(config);
  return uniquePaths([
    path.join(config.rootDir, 'reports'),
    path.join(serviceConfig.rootDir, 'reports'),
  ]);
}

function statFileOrNull(filePath) {
  try {
    const stat = fs.statSync(filePath);
    return stat.isFile() ? stat : null;
  } catch {
    return null;
  }
}

function truncateFileToTail(filePath, keepBytes) {
  const stat = statFileOrNull(filePath);
  if (!stat) return { ok: false, error: 'missing_or_not_file' };
  const bytesToKeep = Math.min(stat.size, keepBytes);
  let tail = Buffer.alloc(0);
  if (bytesToKeep > 0) {
    const fd = fs.openSync(filePath, 'r');
    try {
      tail = Buffer.alloc(bytesToKeep);
      fs.readSync(fd, tail, 0, bytesToKeep, stat.size - bytesToKeep);
    } finally {
      fs.closeSync(fd);
    }
  }
  fs.writeFileSync(filePath, tail);
  return {
    ok: true,
    old_size_bytes: stat.size,
    new_size_bytes: bytesToKeep,
    reclaimed_bytes: Math.max(0, stat.size - bytesToKeep),
  };
}

function collectLogMaintenance(config, args = {}, apply = false) {
  const maxLogBytes = parseIntInRange(args['max-log-bytes'], 10 * 1024 * 1024, 0, 1024 * 1024 * 1024);
  const { dirs, files } = maintenanceLogFiles(config);
  const actions = files.map((filePath) => {
    const stat = statFileOrNull(filePath);
    const base = {
      path: filePath,
      exists: Boolean(stat),
      size_bytes: stat?.size || 0,
      modified_at_iso: stat ? stat.mtime.toISOString() : '',
      max_log_bytes: maxLogBytes,
      action: 'none',
      applied: false,
      reclaimed_bytes: 0,
      error: '',
    };
    if (!stat) return base;
    if (stat.size <= maxLogBytes) return base;
    base.action = 'truncate_to_tail';
    base.target_size_bytes = maxLogBytes;
    base.reclaimed_bytes = Math.max(0, stat.size - maxLogBytes);
    if (!apply) return base;
    try {
      const applied = truncateFileToTail(filePath, maxLogBytes);
      return {
        ...base,
        applied: applied.ok === true,
        size_bytes_before: applied.old_size_bytes,
        size_bytes_after: applied.new_size_bytes,
        reclaimed_bytes: applied.reclaimed_bytes,
        error: applied.ok ? '' : applied.error,
      };
    } catch (error) {
      return {
        ...base,
        applied: false,
        error: String(error.message || error),
      };
    }
  });
  return {
    log_dirs: dirs,
    max_log_bytes: maxLogBytes,
    files_seen: actions.length,
    files_over_limit: actions.filter((item) => item.action !== 'none').length,
    files_changed: actions.filter((item) => item.applied).length,
    reclaimed_bytes: actions.reduce((sum, item) => sum + (item.applied ? Number(item.reclaimed_bytes || 0) : 0), 0),
    planned_reclaim_bytes: actions.reduce((sum, item) => sum + Number(item.reclaimed_bytes || 0), 0),
    actions,
  };
}

function listReportFiles(reportDir) {
  try {
    if (!fs.existsSync(reportDir)) return [];
    return fs.readdirSync(reportDir)
      .filter((name) => name.endsWith('.json'))
      .map((name) => {
        const filePath = path.join(reportDir, name);
        const stat = statFileOrNull(filePath);
        if (!stat) return null;
        return {
          path: filePath,
          name,
          size_bytes: stat.size,
          modified_ms: stat.mtimeMs,
          modified_at_iso: stat.mtime.toISOString(),
        };
      })
      .filter(Boolean);
  } catch {
    return [];
  }
}

function collectReportMaintenance(config, args = {}, apply = false, keepPath = '') {
  const keepReportFiles = parseIntInRange(args['keep-report-files'], 100, 1, 100000);
  const maxReportAgeDays = parseIntInRange(args['max-report-age-days'], 30, 0, 3650);
  const now = Date.now();
  const maxAgeMs = maxReportAgeDays > 0 ? maxReportAgeDays * 24 * 60 * 60 * 1000 : 0;
  const dirs = maintenanceReportDirs(config, args);
  const perDir = [];
  for (const dir of dirs) {
    const files = listReportFiles(dir).sort((a, b) => b.modified_ms - a.modified_ms);
    const actions = files.map((file, index) => {
      const ageMs = Math.max(0, now - file.modified_ms);
      const overCount = index >= keepReportFiles;
      const overAge = maxAgeMs > 0 && ageMs > maxAgeMs;
      const protectedCurrent = keepPath && path.resolve(file.path) === path.resolve(keepPath);
      const shouldDelete = !protectedCurrent && (overCount || overAge);
      const action = {
        path: file.path,
        size_bytes: file.size_bytes,
        modified_at_iso: file.modified_at_iso,
        age_days: Math.round((ageMs / (24 * 60 * 60 * 1000)) * 100) / 100,
        rank_newest_first: index + 1,
        over_keep_count: overCount,
        over_age: overAge,
        protected_current_report: protectedCurrent,
        action: shouldDelete ? 'delete' : 'keep',
        applied: false,
        error: '',
      };
      if (shouldDelete && apply) {
        try {
          fs.unlinkSync(file.path);
          action.applied = true;
        } catch (error) {
          action.error = String(error.message || error);
        }
      }
      return action;
    });
    perDir.push({
      report_dir: dir,
      exists: fs.existsSync(dir),
      keep_report_files: keepReportFiles,
      max_report_age_days: maxReportAgeDays,
      files_seen: files.length,
      files_planned_delete: actions.filter((item) => item.action === 'delete').length,
      files_deleted: actions.filter((item) => item.applied).length,
      planned_reclaim_bytes: actions
        .filter((item) => item.action === 'delete')
        .reduce((sum, item) => sum + Number(item.size_bytes || 0), 0),
      reclaimed_bytes: actions
        .filter((item) => item.applied)
        .reduce((sum, item) => sum + Number(item.size_bytes || 0), 0),
      actions,
    });
  }
  return {
    report_dirs: dirs,
    keep_report_files: keepReportFiles,
    max_report_age_days: maxReportAgeDays,
    dirs_seen: perDir.length,
    files_seen: perDir.reduce((sum, item) => sum + item.files_seen, 0),
    files_planned_delete: perDir.reduce((sum, item) => sum + item.files_planned_delete, 0),
    files_deleted: perDir.reduce((sum, item) => sum + item.files_deleted, 0),
    planned_reclaim_bytes: perDir.reduce((sum, item) => sum + item.planned_reclaim_bytes, 0),
    reclaimed_bytes: perDir.reduce((sum, item) => sum + item.reclaimed_bytes, 0),
    per_dir: perDir,
  };
}

function maintenance(config, args = {}) {
  const apply = parseBool(args.apply, false);
  const reportPath = resolveReportPath(config, args['report-path'], 'daemon_maintenance');
  const startedAt = Date.now();
  const logMaintenance = collectLogMaintenance(config, args, apply);
  const reportMaintenance = collectReportMaintenance(config, args, apply, reportPath);
  const uiGate = runUiCompatibilityGate(config);
  const report = {
    ok: true,
    schema_version: 'xhub.rust_hub.daemon_maintenance_report.v1',
    command: 'maintenance',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    dry_run: !apply,
    applied: apply,
    profile: config.profile,
    profile_file: config.profileFile || '',
    http_base_url: config.baseUrl,
    log_maintenance: logMaintenance,
    report_maintenance: reportMaintenance,
    ui_compatibility: uiGate,
    ui_product_change: uiGate.product_ui_change === true,
    swift_ui_files_touched: uiGate.swift_ui_files_touched === true,
    rust_browser_product_ui: uiGate.rust_browser_product_ui === true,
    node_remains_authority: true,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    memory_writer_authority_in_rust: false,
    skills_execution_authority_in_rust: false,
    secret_leak: false,
    report_path: reportPath,
  };
  report.ok = report.ui_product_change === false
    && report.swift_ui_files_touched === false
    && report.rust_browser_product_ui === false
    && report.production_authority_change === false
    && report.daemon_restarted === false
    && report.daemon_stopped === false
    && report.memory_writer_authority_in_rust === false
    && report.skills_execution_authority_in_rust === false;
  ensureDir(path.dirname(reportPath));
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  printJson(report, report.ok ? 0 : 2);
}

function compactMaintenanceSummary(logMaintenance, reportMaintenance) {
  return {
    maintenance_dry_run: true,
    log_files_over_limit: Number(logMaintenance.files_over_limit || 0),
    report_files_planned_delete: Number(reportMaintenance.files_planned_delete || 0),
    planned_reclaim_bytes: Number(logMaintenance.planned_reclaim_bytes || 0)
      + Number(reportMaintenance.planned_reclaim_bytes || 0),
    maintenance_needed: Number(logMaintenance.files_over_limit || 0) > 0
      || Number(reportMaintenance.files_planned_delete || 0) > 0,
    log_dirs: logMaintenance.log_dirs || [],
    report_dirs: reportMaintenance.report_dirs || [],
  };
}

function maybeRepairPidFile(state, { apply, repairStalePid, label }) {
  const needed = state.exists === true && state.repairable === true;
  const action = {
    id: `repair_${label}_pid_file`,
    action: 'remove_pid_file',
    target: state.path,
    needed,
    allowed: repairStalePid === true,
    applied: false,
    reason: state.invalid ? 'invalid_pid_file' : (state.stale ? 'stale_pid_file' : ''),
    skipped_reason: '',
    error: '',
  };
  if (!needed) {
    action.skipped_reason = 'not_needed';
    return action;
  }
  if (!apply) {
    action.skipped_reason = 'dry_run';
    return action;
  }
  if (!repairStalePid) {
    action.skipped_reason = 'repair_stale_pid_not_enabled';
    return action;
  }
  try {
    fs.unlinkSync(state.path);
    action.applied = true;
    return action;
  } catch (error) {
    action.error = String(error.message || error);
    return action;
  }
}

function watchdogPidIssues(sourcePid, launchdPid) {
  const issues = [];
  if (sourcePid.invalid) issues.push('source_pid_file_invalid');
  if (sourcePid.stale) issues.push('source_pid_file_stale');
  if (launchdPid.invalid) issues.push('launchd_runtime_pid_file_invalid');
  if (launchdPid.stale) issues.push('launchd_runtime_pid_file_stale');
  return issues;
}

async function watchdog(config, args = {}) {
  const startedAt = Date.now();
  const reportPath = resolveReportPath(config, args['report-path'], 'daemon_watchdog');
  const apply = parseBool(args.apply, false);
  const repairStalePid = parseBool(args['repair-stale-pid'], false);
  const allowManual = parseBool(args['allow-manual'], false);
  const requireReady = !parseBool(args['no-require-ready'], false)
    && parseBool(args['require-ready'], true);
  const maxSlowRequests = parseIntInRange(args['max-slow-requests'], 0, 0, 1000000);
  const maintenanceArgs = {
    ...args,
    'max-log-bytes': firstValue([args['maintenance-max-log-bytes'], args['max-maintenance-log-bytes'], 10 * 1024 * 1024]),
  };

  const statusOut = await collectStatus(config);
  const launchdOut = await collectLaunchdStatus(config);
  let httpMetrics = null;
  let httpMetricsError = '';
  try {
    httpMetrics = await httpGetJson(`${config.baseUrl}/runtime/http-metrics`, 1000);
  } catch (error) {
    httpMetricsError = String(error.message || error);
  }

  const serviceConfig = launchdRuntimeConfig(config);
  const sourcePidBefore = collectPidFileState(config.pidFile);
  const launchdPidBefore = collectPidFileState(serviceConfig.pidFile);
  const actions = [
    maybeRepairPidFile(sourcePidBefore, { apply, repairStalePid, label: 'source' }),
    maybeRepairPidFile(launchdPidBefore, { apply, repairStalePid, label: 'launchd_runtime' }),
  ];
  const sourcePidAfter = collectPidFileState(config.pidFile);
  const launchdPidAfter = collectPidFileState(serviceConfig.pidFile);

  const logMaintenance = collectLogMaintenance(config, maintenanceArgs, false);
  const reportMaintenance = collectReportMaintenance(config, maintenanceArgs, false, reportPath);
  const maintenanceSummary = compactMaintenanceSummary(logMaintenance, reportMaintenance);
  const uiGate = runUiCompatibilityGate(config);
  const readiness = statusOut.readiness || launchdOut.readiness || null;
  const healthy = statusOut.running === true || launchdOut.running === true;
  const readyState = readiness?.ready === true;
  const recentSlowRaw = httpMetrics?.recent_slow_requests;
  const recentSlowAvailable = recentSlowRaw !== undefined && recentSlowRaw !== null;
  const cumulativeSlowRequests = Number(httpMetrics?.slow_requests || 0);
  const recentSlowRequests = recentSlowAvailable ? Number(recentSlowRaw || 0) : null;
  const budgetSlowRequests = recentSlowAvailable ? Number(recentSlowRequests || 0) : cumulativeSlowRequests;
  const launchdExpected = process.platform === 'darwin' && !allowManual;

  const issues = [];
  if (requireReady && !healthy) issues.push('daemon_health_unavailable');
  if (requireReady && !readyState) issues.push('daemon_readiness_unavailable');
  if (launchdExpected && launchdOut.loaded !== true) issues.push('launchd_not_loaded');
  if (httpMetrics?.schema_version !== 'xhub.rust_hub.http_metrics.v1') issues.push('http_metrics_unavailable');
  if (budgetSlowRequests > maxSlowRequests) issues.push('slow_request_budget_exceeded');
  if (readiness?.capabilities?.http_io_timeouts !== true) issues.push('http_io_timeout_capability_missing');
  if (readiness?.capabilities?.http_backpressure !== true) issues.push('http_backpressure_capability_missing');
  if (uiGate.product_ui_change === true) issues.push('ui_product_change');
  if (uiGate.swift_ui_files_touched === true) issues.push('swift_ui_files_touched');
  if (uiGate.rust_browser_product_ui === true) issues.push('rust_browser_product_ui');
  if (readiness?.memory?.canonical_writer_in_rust === true) issues.push('memory_writer_authority_in_rust');
  if (readiness?.skills?.execution_authority_in_rust === true) issues.push('skills_execution_authority_in_rust');
  issues.push(...watchdogPidIssues(sourcePidAfter, launchdPidAfter));
  for (const action of actions) {
    if (action.needed && apply && action.allowed && !action.applied) {
      issues.push(`${action.id}_failed`);
    }
  }

  const recommendedActions = [];
  if (sourcePidAfter.repairable || launchdPidAfter.repairable) {
    recommendedActions.push('Run watchdog with --apply --repair-stale-pid to remove stale or invalid pid files.');
  }
  if (launchdExpected && launchdOut.loaded !== true) {
    recommendedActions.push('Run xhubd_daemon.command launchd-install --replace-running after reviewing the profile.');
  }
  if (!healthy || !readyState) {
    recommendedActions.push('Run daemon_ops_report.command for redacted logs and readiness detail.');
  }
  if (maintenanceSummary.maintenance_needed) {
    recommendedActions.push('Run daemon_maintenance.command --apply after reviewing the dry-run plan.');
  }

  const report = {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.daemon_watchdog_report.v1',
    command: 'watchdog',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    dry_run: !apply,
    applied: apply,
    repair_stale_pid_enabled: repairStalePid,
    allow_manual: allowManual,
    profile: config.profile,
    profile_file: config.profileFile || '',
    http_base_url: config.baseUrl,
    bind_url: config.bindUrl,
    public_base_url: config.publicBaseUrl,
    require_ready: requireReady,
    healthy,
    ready: readyState,
    launchd_expected: launchdExpected,
    launchd_loaded: launchdOut.loaded === true,
    launchd_running: launchdOut.running === true,
    status: statusOut,
    launchd_status: launchdOut,
    pid_files: {
      source_before: sourcePidBefore,
      source_after: sourcePidAfter,
      launchd_runtime_before: launchdPidBefore,
      launchd_runtime_after: launchdPidAfter,
    },
    http_metrics_ready: httpMetrics?.schema_version === 'xhub.rust_hub.http_metrics.v1',
    http_metrics_error: httpMetricsError,
    total_requests: Number(httpMetrics?.total_requests || 0),
    slow_request_budget_scope: recentSlowAvailable ? 'recent_window' : 'cumulative',
    slow_requests: budgetSlowRequests,
    cumulative_slow_requests: cumulativeSlowRequests,
    recent_slow_requests: recentSlowAvailable ? recentSlowRequests : null,
    recent_sample_count: Number(httpMetrics?.recent_sample_count || 0),
    recent_sample_capacity: Number(httpMetrics?.recent_sample_capacity || 0),
    max_observed_http_elapsed_ms: Number(httpMetrics?.max_elapsed_ms || 0),
    route_count: Number(httpMetrics?.route_count || 0),
    readiness_guards: {
      http_io_timeouts: readiness?.capabilities?.http_io_timeouts === true,
      http_read_timeout_ms: Number(readiness?.performance?.http_read_timeout_ms || 0),
      http_write_timeout_ms: Number(readiness?.performance?.http_write_timeout_ms || 0),
      http_backpressure: readiness?.capabilities?.http_backpressure === true,
      http_metrics_recent_window: readiness?.capabilities?.http_metrics_recent_window === true,
      cross_network_auth_gate: readiness?.capabilities?.cross_network_auth_gate === true,
    },
    maintenance: maintenanceSummary,
    actions,
    recommended_actions: recommendedActions,
    ui_compatibility: uiGate,
    ui_product_change: uiGate.product_ui_change === true,
    swift_ui_files_touched: uiGate.swift_ui_files_touched === true,
    rust_browser_product_ui: uiGate.rust_browser_product_ui === true,
    node_remains_authority: true,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    memory_writer_authority_in_rust: readiness?.memory?.canonical_writer_in_rust === true,
    skills_execution_authority_in_rust: readiness?.skills?.execution_authority_in_rust === true,
    cross_network_auth_gate: readiness?.capabilities?.cross_network_auth_gate === true,
    secret_leak: false,
    issues,
    report_path: reportPath,
  };
  const serialized = JSON.stringify(report);
  report.secret_leak = /sk-[A-Za-z0-9]|api_key|access_key"\s*:\s*"(?!\[REDACTED\])|Bearer\s+(?!\[REDACTED\])\S+/i.test(serialized);
  if (report.secret_leak) {
    report.ok = false;
    report.issues.push('secret_leak');
  }
  ensureDir(path.dirname(reportPath));
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  printJson(report, report.ok ? 0 : 2);
}

async function opsGate(config, args = {}) {
  const startedAt = Date.now();
  const reportPath = resolveReportPath(config, args['report-path'], 'daemon_ops_gate');
  const requireReady = !parseBool(args['no-require-ready'], false)
    && parseBool(args['require-ready'], true);
  const maxSlowRequests = parseIntInRange(args['max-slow-requests'], 0, 0, 1000000);
  const maxLogBytes = parseIntInRange(args['max-log-bytes'], 4096, 0, 1024 * 1024);
  const maintenanceArgs = {
    ...args,
    'max-log-bytes': firstValue([args['maintenance-max-log-bytes'], args['max-maintenance-log-bytes'], 10 * 1024 * 1024]),
  };
  const statusOut = await collectStatus(config);
  const launchdOut = await collectLaunchdStatus(config);
  let httpMetrics = null;
  let httpMetricsError = '';
  try {
    httpMetrics = await httpGetJson(`${config.baseUrl}/runtime/http-metrics`, 1000);
  } catch (error) {
    httpMetricsError = String(error.message || error);
  }
  const logs = collectLogEvidence(config, maxLogBytes);
  const logMaintenance = collectLogMaintenance(config, maintenanceArgs, false);
  const reportMaintenance = collectReportMaintenance(config, maintenanceArgs, false, reportPath);
  const uiGate = runUiCompatibilityGate(config);
  const xtFileIpcRunOnceSmoke = runXtFileIpcWatcherRunOnceSmoke(config, args, reportPath);
  const xtFileIpcBackgroundWatcherSmoke = runXtFileIpcBackgroundWatcherSmoke(config, args, reportPath);
  const readiness = statusOut.readiness || launchdOut.readiness || null;
  const healthy = statusOut.running === true || launchdOut.running === true;
  const readyState = readiness?.ready === true;
  const cumulativeSlowRequests = Number(httpMetrics?.slow_requests || 0);
  const recentSlowRaw = httpMetrics?.recent_slow_requests;
  const recentSlowAvailable = recentSlowRaw !== undefined && recentSlowRaw !== null;
  const recentSlowRequests = recentSlowAvailable ? Number(recentSlowRaw || 0) : null;
  const budgetSlowRequests = recentSlowAvailable ? Number(recentSlowRequests || 0) : cumulativeSlowRequests;
  const maintenanceNeeded = Number(logMaintenance.files_over_limit || 0) > 0
    || Number(reportMaintenance.files_planned_delete || 0) > 0;
  const issues = [];
  if (requireReady && !healthy) issues.push('daemon_health_unavailable');
  if (requireReady && !readyState) issues.push('daemon_readiness_unavailable');
  if (httpMetrics?.schema_version !== 'xhub.rust_hub.http_metrics.v1') issues.push('http_metrics_unavailable');
  if (budgetSlowRequests > maxSlowRequests) issues.push('slow_request_budget_exceeded');
  if (uiGate.product_ui_change === true) issues.push('ui_product_change');
  if (uiGate.swift_ui_files_touched === true) issues.push('swift_ui_files_touched');
  if (uiGate.rust_browser_product_ui === true) issues.push('rust_browser_product_ui');
  if (xtFileIpcRunOnceSmoke.ok !== true) issues.push('xt_file_ipc_run_once_smoke_failed');
  if (xtFileIpcBackgroundWatcherSmoke.ok !== true) issues.push('xt_file_ipc_background_watcher_smoke_failed');
  if (readiness?.memory?.canonical_writer_in_rust === true) issues.push('memory_writer_authority_in_rust');
  if (readiness?.skills?.execution_authority_in_rust === true) issues.push('skills_execution_authority_in_rust');

  const report = {
    ok: issues.length === 0,
    schema_version: 'xhub.rust_hub.daemon_ops_gate.v1',
    command: 'ops-gate',
    generated_at_iso: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    profile: config.profile,
    profile_file: config.profileFile || '',
    http_base_url: config.baseUrl,
    require_ready: requireReady,
    max_slow_requests: maxSlowRequests,
    healthy,
    ready: readyState,
    http_metrics_ready: httpMetrics?.schema_version === 'xhub.rust_hub.http_metrics.v1',
    http_metrics_error: httpMetricsError,
    total_requests: Number(httpMetrics?.total_requests || 0),
    slow_request_budget_scope: recentSlowAvailable ? 'recent_window' : 'cumulative',
    slow_requests: budgetSlowRequests,
    cumulative_slow_requests: cumulativeSlowRequests,
    recent_slow_requests: recentSlowAvailable ? recentSlowRequests : null,
    recent_sample_count: Number(httpMetrics?.recent_sample_count || 0),
    recent_sample_capacity: Number(httpMetrics?.recent_sample_capacity || 0),
    slow_request_budget_ok: budgetSlowRequests <= maxSlowRequests,
    max_observed_http_elapsed_ms: Number(httpMetrics?.max_elapsed_ms || 0),
    route_count: Number(httpMetrics?.route_count || 0),
    maintenance_dry_run: true,
    maintenance_needed: maintenanceNeeded,
    log_files_over_limit: Number(logMaintenance.files_over_limit || 0),
    report_files_planned_delete: Number(reportMaintenance.files_planned_delete || 0),
    planned_reclaim_bytes: Number(logMaintenance.planned_reclaim_bytes || 0)
      + Number(reportMaintenance.planned_reclaim_bytes || 0),
    status: statusOut,
    launchd_status: launchdOut,
    http_metrics: httpMetrics,
    log_evidence: logs,
    maintenance_preview: {
      log_maintenance: logMaintenance,
      report_maintenance: reportMaintenance,
    },
    ui_compatibility: uiGate,
    xt_file_ipc_run_once_smoke: xtFileIpcRunOnceSmoke,
    xt_file_ipc_background_watcher_smoke: xtFileIpcBackgroundWatcherSmoke,
    ui_product_change: uiGate.product_ui_change === true,
    swift_ui_files_touched: uiGate.swift_ui_files_touched === true,
    rust_browser_product_ui: uiGate.rust_browser_product_ui === true,
    node_remains_authority: true,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    memory_writer_authority_in_rust: readiness?.memory?.canonical_writer_in_rust === true,
    skills_execution_authority_in_rust: readiness?.skills?.execution_authority_in_rust === true,
    cross_network_auth_gate: readiness?.capabilities?.cross_network_auth_gate === true,
    xt_file_ipc_run_once_smoke_enabled: xtFileIpcRunOnceSmoke.enabled === true,
    xt_file_ipc_run_once_smoke_ok: xtFileIpcRunOnceSmoke.ok === true,
    xt_file_ipc_background_watcher_smoke_enabled: xtFileIpcBackgroundWatcherSmoke.enabled === true,
    xt_file_ipc_background_watcher_smoke_ok: xtFileIpcBackgroundWatcherSmoke.ok === true,
    secret_leak: false,
    issues,
    report_path: reportPath,
  };
  const serialized = JSON.stringify(report);
  report.secret_leak = /sk-[A-Za-z0-9]|api_key|access_key"\s*:\s*"(?!\[REDACTED\])|Bearer\s+(?!\[REDACTED\])\S+/i.test(serialized);
  if (report.secret_leak) {
    report.ok = false;
    report.issues.push('secret_leak');
  }
  ensureDir(path.dirname(reportPath));
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  printJson(report, report.ok ? 0 : 2);
}

function accessKeyInit(config, args = {}) {
  const accessKeyFile = config.accessKeyFile || path.join(config.rootDir, 'secrets', 'xhubd_http_access_key');
  const rotate = parseBool(args.rotate, false);
  if (fs.existsSync(accessKeyFile) && !rotate) {
    try {
      fs.chmodSync(accessKeyFile, 0o600);
    } catch {}
    printJson({
      ok: true,
      command: 'access-key-init',
      schema_version: 'xhub.rust_hub.access_key_file.v1',
      created: false,
      rotated: false,
      access_key_file: accessKeyFile,
      mode: '0600',
      key_printed: false,
    });
    return;
  }

  ensureDir(path.dirname(accessKeyFile));
  const secret = crypto.randomBytes(32).toString('hex');
  const flag = rotate ? 'w' : 'wx';
  try {
    fs.writeFileSync(accessKeyFile, `${secret}\n`, { mode: 0o600, flag });
  } catch (error) {
    if (error?.code === 'EEXIST') {
      printJson({
        ok: true,
        command: 'access-key-init',
        schema_version: 'xhub.rust_hub.access_key_file.v1',
        created: false,
        rotated: false,
        access_key_file: accessKeyFile,
        mode: '0600',
        key_printed: false,
      });
      return;
    }
    throw error;
  }
  try {
    fs.chmodSync(accessKeyFile, 0o600);
  } catch {}
  printJson({
    ok: true,
    command: 'access-key-init',
    schema_version: 'xhub.rust_hub.access_key_file.v1',
    created: !rotate,
    rotated: rotate,
    access_key_file: accessKeyFile,
    mode: '0600',
    key_printed: false,
    key_bytes: 32,
  });
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function printEnv(config) {
  const lines = [
    `export XHUB_RUST_HUB_ROOT=${shellQuote(config.rootDir)}`,
    `export XHUB_RUST_HUB_HOST=${shellQuote(config.host)}`,
    `export XHUB_RUST_HUB_HTTP_PORT=${shellQuote(String(config.port))}`,
    `export XHUB_RUST_HUB_ALLOW_LAN=${config.allowLan ? '1' : '0'}`,
    `export XHUB_RUST_HUB_PUBLIC_BASE_URL=${shellQuote(config.publicBaseUrl)}`,
    `export HUB_DB_PATH=${shellQuote(config.dbPath)}`,
    `export HUB_RUNTIME_BASE_DIR=${shellQuote(config.runtimeBaseDir)}`,
    `export XHUB_RUST_MEMORY_DIR=${shellQuote(config.memoryDir)}`,
    `export XHUB_RUST_SKILLS_DIR=${shellQuote(config.skillsDir)}`,
    `export XHUB_RUST_HTTP_ACCESS_KEY_FILE=${shellQuote(config.accessKeyFile || '')}`,
    `export XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY=${config.httpRequireAccessKey ? '1' : '0'}`,
    `export XHUB_RUST_SCHEDULER_STATUS_HTTP=1`,
    `export XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
    `export XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP=1`,
    `export XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
    `export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP=1`,
    `export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
    `export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP=1`,
    `export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
    `export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP=1`,
    `export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
    `export XHUB_RUST_MODEL_INVENTORY_BRIDGE=1`,
    `export XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
  ];
  fs.writeSync(1, `${lines.join('\n')}\n`);
}

async function selfTest(config) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhubd-daemon-self-test-'));
  const port = 57000 + (process.pid % 1000);
  const selfConfig = {
    ...config,
    profile: 'local',
    allowLan: false,
    host: '127.0.0.1',
    connectHost: '127.0.0.1',
    publicHost: '127.0.0.1',
    port,
    bindUrl: `http://127.0.0.1:${port}`,
    baseUrl: `http://127.0.0.1:${port}`,
    publicBaseUrl: `http://127.0.0.1:${port}`,
    runDir: path.join(tempRoot, 'run'),
    logDir: path.join(tempRoot, 'logs'),
    pidFile: path.join(tempRoot, 'run', 'xhubd.pid'),
    dbPath: path.join(tempRoot, 'data', 'hub.sqlite3'),
    runtimeBaseDir: path.join(tempRoot, 'runtime'),
    memoryDir: path.join(tempRoot, 'data', 'memory'),
    skillsDir: path.join(tempRoot, 'skills'),
    accessKeyFile: '',
    httpRequireAccessKey: false,
    waitMs: Math.max(config.waitMs, 15000),
  };
  try {
    await start(selfConfig);
    await health(selfConfig);
    await ready(selfConfig);
    await stop(selfConfig);
  } finally {
    try { fs.rmSync(tempRoot, { recursive: true, force: true }); } catch {}
  }
}

function printHelp() {
  fs.writeSync(1, `xhubd_daemon commands:
  start     Start xhubd serve in the background and wait for /health
  health    Check /health and return non-zero when unavailable
  ready     Check /ready operational readiness
  status    Print pid, log, db, and health status
  profile   Print the resolved persistent daemon profile
  launchd-plist Generate a macOS LaunchAgent plist under run/
  launchd-install Install and bootstrap a user LaunchAgent with KeepAlive
  launchd-status Check launchd load state plus HTTP health/readiness
  launchd-uninstall Boot out the user LaunchAgent and remove its plist
  watchdog-plist Generate a StartInterval LaunchAgent plist for watchdog reports
  watchdog-install Install the watchdog timer LaunchAgent
  watchdog-status Check watchdog timer LaunchAgent load state
  watchdog-uninstall Remove the watchdog timer LaunchAgent
  cross-network-readiness Check LAN/cross-device deployment readiness without mutation
  cross-network-install-plan Print LAN daemon/timer install, validation, and rollback plan
  ops-report Collect non-mutating health/readiness/launchd/http-metrics/log evidence
  maintenance Preview/apply bounded log and report retention
  ops-gate  Run daily/manual health, metrics, maintenance dry-run, and UI boundary gate
  watchdog  Run long-running daemon guard checks and optional stale-pid repair
  access-key-init Create or rotate a 0600 HTTP access key file without printing the key
  stop      Stop the pid recorded by this daemon manager
  restart   Stop then start
  env       Print Node Hub HTTP-first environment variables
  self-test Start a temporary daemon, check health, and stop it

Options:
  --profile <p>    local or lan. lan binds 0.0.0.0 and sets allow-lan.
  --profile-file <p> Profile JSON path, default config/daemon_profile.<profile>.json
  --port <n>       HTTP port, default XHUB_RUST_HUB_HTTP_PORT or 50151
  --host <host>    HTTP host, default XHUB_RUST_HUB_HOST or 127.0.0.1
  --allow-lan      Permit non-loopback bind without using --profile lan
  --public-host <h> Public LAN host/IP used in public_base_url output
  --db-path <path> SQLite DB path, default data/hub.sqlite3
  --runtime-base-dir <path> Runtime base dir, default runtime
  --memory-dir <path> Memory storage dir, default data/memory
  --skills-dir <path> Skills registry dir, default skills
  --access-key-file <path> HTTP access key file used for LAN/cross-device requests
  --require-access-key Require an HTTP access key even for loopback probes
  --launchd-label <label> LaunchAgent label, default com.ax.xhubd.<profile>
  --plist-path <path> LaunchAgent plist output path, default run/<label>.plist
  --install-plist-path <path> LaunchAgent install path, default ~/Library/LaunchAgents/<label>.plist
  --launchd-runtime-root <path> Runtime copy root, default ~/Library/Application Support/AX/rust-hub/<profile>
  --launchd-binary-source <path> xhubd binary copied into the runtime root
  --dry-run        For launchd-install/uninstall, write plist and print actions only
  --replace-running Stop a manually started daemon before launchd-install
  --keep-plist     For launchd-uninstall, keep the installed plist file
  --watchdog-launchd-label <label> Timer LaunchAgent label, default <launchd-label>.watchdog
  --watchdog-plist-path <p> Timer plist preview path, default run/<watchdog-label>.plist
  --watchdog-install-plist-path <p> Timer install path, default ~/Library/LaunchAgents/<watchdog-label>.plist
  --watchdog-interval-sec <n> Timer StartInterval seconds, default 900
  --require-live-ready For cross-network-readiness, require live /ready=true
  --require-launchd-loaded For cross-network-readiness, require daemon LaunchAgent loaded
  --require-watchdog-timer For cross-network-readiness, require watchdog timer loaded
  --allow-loopback-public-host For cross-network-readiness tests with 127.0.0.1
  --report-path <p> For ops-report, persisted JSON report path
  --max-log-bytes <n> For ops-report, redacted tail bytes per log file
  --require-ready For ops-report, exit non-zero when health/readiness is unavailable
  --apply          For maintenance, apply retention. Default is dry-run preview.
  --keep-report-files <n> For maintenance, keep newest report JSON files per report dir
  --max-report-age-days <n> For maintenance, delete report JSON older than this age
  --reports-dir <p> For maintenance, override report directory scope
  --no-require-ready For ops-gate, do not fail when health/readiness is unavailable
  --max-slow-requests <n> For ops-gate, slow-request budget, default 0
  --maintenance-max-log-bytes <n> For ops-gate maintenance dry-run log budget
  --xt-file-ipc-run-once-smoke For ops-report/ops-gate, run isolated XT file IPC run-once smoke
  --xt-file-ipc-run-once-smoke-timeout-ms <n> Timeout for that isolated smoke
  --xt-file-ipc-background-watcher-smoke For ops-report/ops-gate, run isolated XT file IPC background watcher smoke
  --xt-file-ipc-background-watcher-smoke-timeout-ms <n> Timeout for that isolated smoke
  --allow-manual   For watchdog, do not require launchd to be loaded
  --repair-stale-pid For watchdog --apply, remove stale/invalid pid files
  --pid-file <p>   PID file, default run/xhubd.pid
  --run-dir <dir>  Run state directory, default run
  --log-dir <dir>  Log directory, default logs
  --wait-ms <n>    Health wait timeout
`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const command = safeString(args._[0]) || 'status';
  const config = resolveConfig(args);
  switch (command) {
    case 'start':
      await start(config);
      break;
    case 'health':
      await health(config);
      break;
    case 'ready':
      await ready(config);
      break;
    case 'status':
      await status(config);
      break;
    case 'profile':
      profile(config);
      break;
    case 'launchd-plist':
      launchdPlist(config);
      break;
    case 'launchd-install':
      await launchdInstall(config, args);
      break;
    case 'launchd-status':
      await launchdStatus(config);
      break;
    case 'launchd-uninstall':
      await launchdUninstall(config, args);
      break;
    case 'watchdog-plist':
      watchdogLaunchdPlist(config);
      break;
    case 'watchdog-install':
      await watchdogLaunchdInstall(config, args);
      break;
    case 'watchdog-status':
      watchdogLaunchdStatus(config);
      break;
    case 'watchdog-uninstall':
      await watchdogLaunchdUninstall(config, args);
      break;
    case 'cross-network-readiness':
      await crossNetworkReadiness(config, args);
      break;
    case 'cross-network-install-plan':
      crossNetworkInstallPlan(config);
      break;
    case 'ops-report':
      await opsReport(config, args);
      break;
    case 'maintenance':
      maintenance(config, args);
      break;
    case 'ops-gate':
      await opsGate(config, args);
      break;
    case 'watchdog':
      await watchdog(config, args);
      break;
    case 'access-key-init':
      accessKeyInit(config, args);
      break;
    case 'stop':
      await stop(config);
      break;
    case 'restart':
      await stop(config);
      await start(config);
      break;
    case 'env':
      printEnv(config);
      break;
    case 'self-test':
      await selfTest(config);
      break;
    case 'help':
    case '-h':
    case '--help':
      printHelp();
      break;
    default:
      printJson({ ok: false, error_code: 'unknown_command', command }, 64);
  }
}

try {
  await main();
} catch (error) {
  printJson({
    ok: false,
    error_code: 'xhubd_daemon_failed',
    error_message: String(error?.stack || error?.message || error),
  }, 1);
}
