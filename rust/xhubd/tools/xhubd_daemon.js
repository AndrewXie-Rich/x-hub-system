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

function allowMemorySkillsProduction(args = {}) {
  return parseBool(args['allow-memory-skills-production'], false)
    || parseBool(process.env.XHUB_ALLOW_RUST_MEMORY_SKILLS_PRODUCTION, false)
    || requireMemorySkillsProduction(args);
}

function requireMemorySkillsProduction(args = {}) {
  return parseBool(args['no-require-memory-skills-production'], false)
    ? false
    : parseBool(
      args['require-memory-skills-production'],
      parseBool(process.env.XHUB_REQUIRE_RUST_MEMORY_SKILLS_PRODUCTION, true),
    );
}

function memorySkillsAuthorityState(readiness) {
  return {
    memory_writer_authority_in_rust: readiness?.memory?.canonical_writer_in_rust === true,
    skills_execution_authority_in_rust: readiness?.skills?.execution_authority_in_rust === true,
  };
}

const EXPECTED_LONG_RUNNING_HTTP_ROUTES = new Set([
  '/local-ml/execute',
  '/local-ml/run-local-task',
  '/runtime/local-ml/execute',
]);

function httpSlowBudgetSummary(httpMetrics) {
  const recentSlowRaw = httpMetrics?.recent_slow_requests;
  const recentSlowAvailable = recentSlowRaw !== undefined && recentSlowRaw !== null;
  const cumulativeSlowRequests = Number(httpMetrics?.slow_requests || 0);
  const recentSlowRequests = recentSlowAvailable ? Number(recentSlowRaw || 0) : null;
  const rawBudgetSlowRequests = recentSlowAvailable ? Number(recentSlowRequests || 0) : cumulativeSlowRequests;
  const routeRows = Array.isArray(recentSlowAvailable ? httpMetrics?.recent_routes : httpMetrics?.routes)
    ? (recentSlowAvailable ? httpMetrics.recent_routes : httpMetrics.routes)
    : [];
  const excludedLongRunningSlowRoutes = routeRows
    .map((row) => ({
      route: safeString(row?.route),
      slow_count: Number(row?.slow_count || 0),
      max_elapsed_ms: Number(row?.max_elapsed_ms || 0),
      avg_elapsed_ms: Number(row?.avg_elapsed_ms || 0),
    }))
    .filter((row) => EXPECTED_LONG_RUNNING_HTTP_ROUTES.has(row.route) && row.slow_count > 0);
  const excludedLongRunningSlowRequests = excludedLongRunningSlowRoutes
    .reduce((sum, row) => sum + Number(row.slow_count || 0), 0);
  const budgetSlowRequests = Math.max(0, rawBudgetSlowRequests - excludedLongRunningSlowRequests);
  return {
    recentSlowAvailable,
    cumulativeSlowRequests,
    recentSlowRequests,
    rawBudgetSlowRequests,
    budgetSlowRequests,
    excludedLongRunningSlowRequests,
    excludedLongRunningSlowRoutes,
  };
}

function appendMemorySkillsAuthorityIssues(issues, readiness, args = {}) {
  const require = requireMemorySkillsProduction(args);
  const allow = allowMemorySkillsProduction(args) || require;
  const state = memorySkillsAuthorityState(readiness);
  if (!allow && state.memory_writer_authority_in_rust) issues.push('memory_writer_authority_in_rust');
  if (!allow && state.skills_execution_authority_in_rust) issues.push('skills_execution_authority_in_rust');
  if (require && !state.memory_writer_authority_in_rust) issues.push('memory_writer_authority_not_active');
  if (require && !state.skills_execution_authority_in_rust) issues.push('skills_execution_authority_not_active');
  return { allow, require, ...state };
}

function enableCrossNetworkRemoteRouteSmoke(args = {}) {
  return parseBool(args['cross-network-remote-route-smoke'], false)
    || parseBool(process.env.XHUB_RUST_CROSS_NETWORK_REMOTE_ROUTE_SMOKE, false)
    || requireCrossNetworkRemoteRouteSmoke(args);
}

function requireCrossNetworkRemoteRouteSmoke(args = {}) {
  return parseBool(args['require-cross-network-remote-route-smoke'], false)
    || parseBool(process.env.XHUB_RUST_REQUIRE_CROSS_NETWORK_REMOTE_ROUTE_SMOKE, false);
}

function requireMemoryGatewayCutoverReady(args = {}) {
  return parseBool(args['require-memory-gateway-cutover-ready'], false)
    || parseBool(process.env.XHUB_RUST_MEMORY_GATEWAY_CUTOVER_REQUIRE_READY, false)
    || parseBool(process.env.XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE, false);
}

function requireMemoryGatewayModelCallPlanShadow(args = {}) {
  return parseBool(args['require-memory-gateway-model-call-plan-shadow'], false)
    || parseBool(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_SHADOW_REQUIRE, false);
}

function requireMemoryGatewayModelCallExecuteSmoke(args = {}) {
  return parseBool(args['require-memory-gateway-model-call-execute-smoke'], false)
    || parseBool(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SMOKE_REQUIRE, false);
}

function requireMemoryGatewayModelCallLocalExecutorSmoke(args = {}) {
  return parseBool(args['require-memory-gateway-model-call-local-executor-smoke'], false)
    || parseBool(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR_SMOKE_REQUIRE, false);
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

function urlHostname(raw) {
  try {
    return safeString(new URL(safeString(raw)).hostname);
  } catch {
    return '';
  }
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

function readLaunchdEnvironmentVariables(plistPath) {
  const resolved = safeString(plistPath) ? path.resolve(plistPath) : '';
  if (process.platform !== 'darwin' || !resolved || !fs.existsSync(resolved)) return {};
  try {
    const result = spawnSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', resolved], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (result.status !== 0) return {};
    const parsed = JSON.parse(result.stdout || '{}');
    const env = parsed?.EnvironmentVariables;
    return env && typeof env === 'object' && !Array.isArray(env) ? env : {};
  } catch {
    return {};
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

function firstValueWithSource(entries) {
  for (const [source, value] of entries) {
    if (value !== undefined && value !== null && safeString(value) !== '') {
      return { source, value };
    }
  }
  return { source: '', value: undefined };
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
  const publicBaseUrlRaw = safeString(firstValue([
    args['public-base-url'],
    env.XHUB_RUST_HUB_PUBLIC_BASE_URL,
    profileConfig.public_base_url,
    profileConfig.publicBaseUrl,
  ]));
  const publicBaseUrlHost = urlHostname(publicBaseUrlRaw);
  const publicHost = safeString(firstValue([args['public-host'], publicBaseUrlHost, env.XHUB_RUST_HUB_PUBLIC_HOST, profileConfig.public_host, profileConfig.publicHost]))
    || discoveredPublicHost
    || connectHost;
  const publicEndpoint = profile === 'domain'
    || parseBool(firstValue([
      args['public-endpoint'],
      args.domain,
      env.XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT,
      env.XHUB_RUST_HUB_PUBLIC_ENDPOINT,
      profileConfig.public_endpoint,
      profileConfig.publicEndpoint,
      profileConfig.domain,
    ]), false);
  const publicBaseUrl = publicBaseUrlRaw || `http://${publicHost}:${port}`;
  const runDir = path.resolve(pathFromRoot(firstValue([args['run-dir'], env.XHUB_RUST_DAEMON_RUN_DIR, profileConfig.run_dir, profileConfig.runDir])) || path.join(ROOT_DIR, 'run'));
  const logDir = path.resolve(pathFromRoot(firstValue([args['log-dir'], env.XHUB_RUST_DAEMON_LOG_DIR, profileConfig.log_dir, profileConfig.logDir])) || path.join(ROOT_DIR, 'logs'));
  const pidFile = path.resolve(pathFromRoot(firstValue([args['pid-file'], env.XHUB_RUST_DAEMON_PID_FILE, profileConfig.pid_file, profileConfig.pidFile])) || path.join(runDir, 'xhubd.pid'));
  const dbPath = path.resolve(pathFromRoot(firstValue([args['db-path'], env.HUB_DB_PATH, profileConfig.db_path, profileConfig.dbPath])) || path.join(ROOT_DIR, 'data', 'hub.sqlite3'));
  const runtimeBaseDir = path.resolve(pathFromRoot(firstValue([args['runtime-base-dir'], env.HUB_RUNTIME_BASE_DIR, profileConfig.runtime_base_dir, profileConfig.runtimeBaseDir])) || path.join(ROOT_DIR, 'runtime'));
  const memoryDir = path.resolve(pathFromRoot(firstValue([args['memory-dir'], env.XHUB_RUST_MEMORY_DIR, profileConfig.memory_dir, profileConfig.memoryDir])) || path.join(ROOT_DIR, 'data', 'memory'));
  const skillsDir = path.resolve(pathFromRoot(firstValue([args['skills-dir'], env.XHUB_RUST_SKILLS_DIR, profileConfig.skills_dir, profileConfig.skillsDir])) || path.join(ROOT_DIR, 'skills'));
  const launchdLabelForEnv = safeString(firstValue([
    args['launchd-label'],
    env.XHUB_RUST_LAUNCHD_LABEL,
    profileConfig.launchd_label,
    profileConfig.launchdLabel,
  ])) || `com.ax.xhubd.${profile}`;
  const launchdInstallPlistPathForEnv = path.resolve(
    pathFromRoot(firstValue([
      args['install-plist-path'],
      env.XHUB_RUST_LAUNCHD_INSTALL_PLIST_PATH,
      profileConfig.launchd_install_plist_path,
      profileConfig.launchdInstallPlistPath,
    ])) || path.join(os.homedir(), 'Library', 'LaunchAgents', `${launchdLabelForEnv}.plist`)
  );
  const launchdEnv = readLaunchdEnvironmentVariables(launchdInstallPlistPathForEnv);
  const defaultLaunchdRuntimeRoot = path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub', profile);
  const launchdRuntimeRoot = path.resolve(pathFromRoot(firstValue([
    args['launchd-runtime-root'],
    env.XHUB_RUST_LAUNCHD_RUNTIME_ROOT,
    profileConfig.launchd_runtime_root,
    profileConfig.launchdRuntimeRoot,
  ])) || defaultLaunchdRuntimeRoot);
  const accessKeyCandidate = firstValueWithSource([
    ['args', args['access-key-file']],
    ['env:XHUB_RUST_HTTP_ACCESS_KEY_FILE', env.XHUB_RUST_HTTP_ACCESS_KEY_FILE],
    ['env:XHUB_RUST_HUB_ACCESS_KEY_FILE', env.XHUB_RUST_HUB_ACCESS_KEY_FILE],
    ['launchd:XHUB_RUST_HTTP_ACCESS_KEY_FILE', launchdEnv.XHUB_RUST_HTTP_ACCESS_KEY_FILE],
    ['launchd:XHUB_RUST_HUB_ACCESS_KEY_FILE', launchdEnv.XHUB_RUST_HUB_ACCESS_KEY_FILE],
    ['profile:access_key_file', profileConfig.access_key_file],
    ['profile:accessKeyFile', profileConfig.accessKeyFile],
  ]);
  const accessKeyFileRaw = accessKeyCandidate.value;
  const accessKeyFile = safeString(accessKeyFileRaw)
    ? path.resolve(pathFromRoot(accessKeyFileRaw))
    : '';
  const accessKeyFileSource = accessKeyCandidate.source;
  const httpRequireAccessKey = publicEndpoint || parseBool(firstValue([
    args['require-access-key'],
    env.XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY,
    launchdEnv.XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY,
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
    publicBaseUrl,
    publicEndpoint,
    runDir,
    logDir,
    pidFile,
    dbPath,
    runtimeBaseDir,
    memoryDir,
    skillsDir,
    accessKeyFile,
    accessKeyFileSource,
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

function pathEqualOrInside(child, parent) {
  const childPath = safeString(child) ? path.resolve(child) : '';
  const parentPath = safeString(parent) ? path.resolve(parent) : '';
  if (!childPath || !parentPath) return false;
  const relative = path.relative(parentPath, childPath);
  return relative === '' || (!!relative && !relative.startsWith('..') && !path.isAbsolute(relative));
}

function defaultAccessKeyFileName(profile) {
  const normalized = safeString(profile) || 'local';
  if (normalized === 'domain') return 'xhubd_domain_access_key';
  if (normalized === 'lan') return 'xhubd_lan_access_key';
  return 'xhubd_http_access_key';
}

function launchdRuntimeAccessKeyFile(config, runtimeRoot) {
  const current = safeString(config.accessKeyFile);
  const basename = current ? path.basename(current) : defaultAccessKeyFileName(config.profile);
  return path.join(runtimeRoot, 'config', basename || defaultAccessKeyFileName(config.profile));
}

function shouldUseLaunchdRuntimeAccessKeyFile(config, runtimeRoot) {
  const current = safeString(config.accessKeyFile);
  if (!current) return config.httpRequireAccessKey === true;
  if (pathEqualOrInside(current, runtimeRoot)) return false;
  if (safeString(config.accessKeyFileSource) === 'args') return false;
  if (safeString(config.accessKeyFileSource).startsWith('profile:')) return true;
  return pathEqualOrInside(current, path.join(config.rootDir, 'secrets'));
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

function redactHttpDiagnostic(value) {
  return String(value || '')
    .replace(/Bearer\s+(?!\[REDACTED\])\S+/gi, 'Bearer [REDACTED]')
    .replace(/access_key"\s*:\s*"(?!\[REDACTED\])[^"]*"/gi, 'access_key":"[REDACTED]"');
}

function readAccessKeyForProbe(config) {
  const raw = safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY || process.env.XHUB_RUST_HUB_ACCESS_KEY);
  if (raw) return raw;
  if (!safeString(config.accessKeyFile)) return '';
  try {
    return safeString(fs.readFileSync(config.accessKeyFile, 'utf8'));
  } catch {
    return '';
  }
}

function httpGetJson(url, timeoutMs = 750, accessKey = '') {
  return new Promise((resolve, reject) => {
    const headers = { accept: 'application/json' };
    const token = safeString(accessKey);
    if (token) headers.Authorization = `Bearer ${token}`;
    const req = http.get(url, { timeout: timeoutMs, headers }, (res) => {
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
          reject(new Error(`http_status:${statusCode}:${redactHttpDiagnostic(body.slice(0, 240))}`));
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
  const readiness = await httpGetJson(`${config.baseUrl}/ready`, 5000, readAccessKeyForProbe(config));
  return { ok: readiness?.ready === true, readiness };
}

async function collectMemoryReadiness(config) {
  try {
    const readiness = await httpGetJson(
      `${config.baseUrl}/memory/readiness`,
      1500,
      readAccessKeyForProbe(config),
    );
    return { ok: true, readiness, error_code: "", error_message: "" };
  } catch (error) {
    return {
      ok: false,
      readiness: null,
      error_code: "memory_readiness_fetch_failed",
      error_message: redactHttpDiagnostic(String(error.message || error)).slice(0, 300),
    };
  }
}

function compactMemoryWritebackCandidateDiagnostics(memoryReadiness) {
  const writebackCandidates = memoryReadiness?.object_store?.writeback_candidates;
  const diagnostics = writebackCandidates?.diagnostics;
  const maintenance = writebackCandidates?.maintenance;
  const out = {
    schema_version: "xhub.rust_hub.memory_writeback_candidate_ops_rollup.v1",
    ok: true,
    ready: writebackCandidates?.ready === true && diagnostics?.ready === true,
    authority: safeString(writebackCandidates?.authority),
    candidate_count: Number(diagnostics?.candidate_count || writebackCandidates?.candidate_object_count || 0),
    conflict_candidate_count: Number(diagnostics?.conflict_candidate_count || 0),
    stale_review_required_count: Number(diagnostics?.stale_review_required_count || 0),
    stale_candidate_count: Number(diagnostics?.stale_candidate_count || maintenance?.stale_candidate_count || 0),
    superseding_candidate_count: Number(diagnostics?.superseding_candidate_count || 0),
    superseded_candidate_count: Number(diagnostics?.superseded_candidate_count || diagnostics?.archived_superseded_count || 0),
    archived_superseded_count: Number(diagnostics?.archived_superseded_count || diagnostics?.superseded_candidate_count || 0),
    planned_archive_count: Number(diagnostics?.planned_archive_count || maintenance?.planned_archive_count || 0),
    planned_stale_review_required_count: Number(diagnostics?.planned_stale_review_required_count || maintenance?.planned_stale_review_required_count || 0),
    active_review_lock_count: Number(diagnostics?.active_review_lock_count || 0),
    queue_pressure: safeString(diagnostics?.queue_pressure || "unknown"),
    noise_score: Number(diagnostics?.noise_score || 0),
    maintenance_ready: maintenance?.maintenance_ready === true,
    candidate_maintenance_http: writebackCandidates?.candidate_maintenance_http === true || maintenance?.candidate_maintenance_http === true,
    production_authority_change: writebackCandidates?.production_authority_change === true
      || diagnostics?.production_authority_change === true
      || maintenance?.production_authority_change === true,
    blocking_issues: [],
  };
  const schemaOk = diagnostics?.schema_version === "xhub.memory.writeback_candidate_diagnostics.v1";
  if (!writebackCandidates || !diagnostics) {
    out.ok = false;
    out.ready = false;
    out.error_code = "memory_writeback_candidate_diagnostics_unavailable";
  } else if (!schemaOk) {
    out.ok = false;
    out.blocking_issues.push("memory_writeback_candidate_diagnostics_schema_mismatch");
  }
  if (out.production_authority_change) {
    out.ok = false;
    out.blocking_issues.push("memory_writeback_candidate_production_authority_change");
  }
  out.blocking_issues = Array.from(new Set(out.blocking_issues));
  return out;
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
      XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT: config.publicEndpoint ? '1' : '0',
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
    public_endpoint: config.publicEndpoint,
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
  'XHUB_SYSTEM_ROOT',
  'XHUB_ENABLE_RUST_AUTHORITY_CUTOVER',
  'XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
  'XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
  'XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH',
  'XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR',
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
  'XHUB_ALLOW_RUST_MEMORY_SKILLS_PRODUCTION',
  'XHUB_RUST_MEMORY_WRITER_AUTHORITY',
  'XHUB_RUST_MEMORY_WRITE_AUTHORITY',
  'XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY',
  'XHUB_RUST_MEMORY_CONTEXT_GATEWAY',
  'XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE',
  'XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_SHADOW',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_SHADOW_REQUIRE',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_BASE_DIR',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_STATUS_PATH',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_HISTORY_PATH',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_ADMISSION',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_ONLY',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_PROJECT_ID',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_REQUEST_PREFIX',
  'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_AUDIT_PREFIX',
  'XHUB_RUST_SKILLS_EXECUTION_AUTHORITY',
  'XHUB_RUST_SKILLS_PRODUCTION_EXECUTION',
  'XHUB_RUST_SKILLS_EXECUTION_PRODUCTION',
  'XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY',
  'XHUB_RUST_SKILLS_ALLOWED_RUNNERS',
  'XHUB_ENABLE_RUST_PROVIDER_KEY_SNAPSHOT',
  'XHUB_RUST_PROVIDER_KEY_SNAPSHOT',
  'XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP',
  'XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP_BASE_URL',
  'XHUB_RUST_PROVIDER_KEY_SNAPSHOT_FALLBACK_ON_ERROR',
  'XHUB_ENABLE_RUST_PROVIDER_QUOTA_APPLY',
  'XHUB_RUST_PROVIDER_QUOTA_APPLY',
  'XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP',
  'XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP_BASE_URL',
  'XHUB_RUST_PROVIDER_QUOTA_APPLY_FALLBACK_ON_ERROR',
  'XHUB_ENABLE_RUST_PROVIDER_QUOTA_SCHEDULER',
  'XHUB_ENABLE_RUST_PROVIDER_QUOTA_PLAN',
  'XHUB_ENABLE_RUST_PROVIDER_QUOTA_FAILURE',
  'XHUB_RUST_PROVIDER_QUOTA_PLAN',
  'XHUB_RUST_PROVIDER_QUOTA_FAILURE',
  'XHUB_RUST_ML_EXECUTION_AUTHORITY',
  'XHUB_RUST_LOCAL_ML_EXECUTION_AUTHORITY',
  'XHUB_ENABLE_RUST_ML_EXECUTION',
  'XHUB_RUST_LOCAL_RUNTIME_SCRIPT',
  'XHUB_LOCAL_RUNTIME_SCRIPT',
  'RELFLOWHUB_LOCAL_RUNTIME_SCRIPT',
  'RELFLOWHUB_AI_RUNTIME_PYTHON',
  'REL_FLOW_HUB_RUNTIME_PYTHON',
  'X_HUB_LOCAL_RUNTIME_PYTHON',
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
    ...launchdPassthroughEnvironment(),
    XHUB_RUST_HUB_ROOT: config.rootDir,
    XHUB_RUST_HUB_HOST: config.host,
    XHUB_RUST_HUB_HTTP_PORT: String(config.port),
    XHUB_RUST_HUB_ALLOW_LAN: config.allowLan ? '1' : '0',
    XHUB_RUST_HUB_PUBLIC_HOST: config.publicHost,
    XHUB_RUST_HUB_PUBLIC_BASE_URL: config.publicBaseUrl,
    XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT: config.publicEndpoint ? '1' : '0',
    HUB_DB_PATH: config.dbPath,
    HUB_RUNTIME_BASE_DIR: config.runtimeBaseDir,
    XHUB_RUST_MEMORY_DIR: config.memoryDir,
    XHUB_RUST_SKILLS_DIR: config.skillsDir,
    XHUB_RUST_HTTP_ACCESS_KEY_FILE: config.accessKeyFile || '',
    XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY: config.httpRequireAccessKey ? '1' : '0',
  };
}

function assertLaunchdExplicitConfigWins() {
  const previousPublicBaseUrl = process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL;
  const previousPublicHost = process.env.XHUB_RUST_HUB_PUBLIC_HOST;
  process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL = 'http://stale.example.invalid';
  process.env.XHUB_RUST_HUB_PUBLIC_HOST = 'stale.example.invalid';
  try {
    const env = launchdEnvironment({
      rootDir: '/tmp/xhubd-self-test',
      host: '127.0.0.1',
      port: 50151,
      allowLan: false,
      publicHost: 'andrew.tailbe79cd.ts.net',
      publicBaseUrl: 'https://andrew.tailbe79cd.ts.net',
      dbPath: '/tmp/xhubd-self-test/data/hub.sqlite3',
      runtimeBaseDir: '/tmp/xhubd-self-test/runtime',
      memoryDir: '/tmp/xhubd-self-test/data/memory',
      skillsDir: '/tmp/xhubd-self-test/skills',
      accessKeyFile: '/tmp/xhubd-self-test/secrets/access_key',
      httpRequireAccessKey: true,
      publicEndpoint: true,
    });
    if (env.XHUB_RUST_HUB_PUBLIC_BASE_URL !== 'https://andrew.tailbe79cd.ts.net') {
      throw new Error('launchd_explicit_public_base_url_overridden_by_passthrough_env');
    }
    if (env.XHUB_RUST_HUB_PUBLIC_HOST !== 'andrew.tailbe79cd.ts.net') {
      throw new Error('launchd_explicit_public_host_overridden_by_passthrough_env');
    }
  } finally {
    if (previousPublicBaseUrl === undefined) delete process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL;
    else process.env.XHUB_RUST_HUB_PUBLIC_BASE_URL = previousPublicBaseUrl;
    if (previousPublicHost === undefined) delete process.env.XHUB_RUST_HUB_PUBLIC_HOST;
    else process.env.XHUB_RUST_HUB_PUBLIC_HOST = previousPublicHost;
  }
}

function assertLaunchdPassthroughIncludesProviderModelProduction() {
  const required = [
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
  const missing = required.filter((key) => !LAUNCHD_PASSTHROUGH_ENV_KEYS.includes(key));
  if (missing.length > 0) {
    throw new Error(`launchd_passthrough_missing_provider_model_production_keys:${missing.join(',')}`);
  }
}

function assertMemoryGatewayModelCallExecuteSmokeCollector() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhubd-execute-smoke-collector-'));
  try {
    const statusPath = path.join(tempRoot, 'memory_gateway_model_call_execute_smoke_status.json');
    fs.writeFileSync(statusPath, `${JSON.stringify({
      ok: true,
      schema_version: 'xhub.rust_hub.memory_gateway_model_call_execute_smoke.v1',
      generated_at_ms: Date.now(),
      execution_blocked: true,
      content_free: true,
      admission_ready: false,
      production_authority_change: false,
      gate: {
        status: 'blocked',
        mode: 'execution_admission_no_model_call',
        authority: 'rust_memory_gateway',
        ready_for_execution: false,
      },
      execute: {
        status: 'blocked',
        mode: 'execute_guard_no_model_call',
        authority: 'rust_memory_gateway',
        executor: 'none',
        blocker_count: 1,
        would_call_model: false,
        model_call_invoked: false,
        model_call_executed: false,
        local_ml_execute_http_invoked: false,
      },
      issue_codes: [],
      rollback_plan: {
        env_to_unset: [
          'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION',
          'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR',
          'XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY',
        ],
      },
    }, null, 2)}\n`, 'utf8');
    const baseConfig = { rootDir: tempRoot, profile: 'local' };
    const requiredArgs = {
      'memory-gateway-model-call-execute-smoke-status-path': statusPath,
      'require-memory-gateway-model-call-execute-smoke': true,
    };
    const valid = collectMemoryGatewayModelCallExecuteSmoke(baseConfig, requiredArgs, {}, {});
    if (valid.ok !== true || valid.status_found !== true || valid.execution_blocked !== true) {
      throw new Error('memory_gateway_model_call_execute_smoke_collector_valid_required_failed');
    }
    fs.unlinkSync(statusPath);
    const missing = collectMemoryGatewayModelCallExecuteSmoke(baseConfig, {
      'memory-gateway-model-call-execute-smoke-status-path': path.join(tempRoot, 'missing.json'),
      'require-memory-gateway-model-call-execute-smoke': true,
    }, {}, {});
    if (missing.ok === true || !missing.blocking_issues.includes('memory_gateway_model_call_execute_smoke_missing')) {
      throw new Error('memory_gateway_model_call_execute_smoke_collector_required_missing_not_blocked');
    }
  } finally {
    try { fs.rmSync(tempRoot, { recursive: true, force: true }); } catch {}
  }
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
  const root = safeString(config.launchdRuntimeRoot || config.rootDir);
  const useRuntimeAccessKey = shouldUseLaunchdRuntimeAccessKeyFile(config, root);
  const accessKeyFile = useRuntimeAccessKey
    ? launchdRuntimeAccessKeyFile(config, root)
    : config.accessKeyFile;
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
    accessKeyFile,
    accessKeyFileSource: useRuntimeAccessKey ? 'launchd_runtime' : config.accessKeyFileSource,
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

function seedLaunchdRuntimeAccessKey(config, serviceConfig, deployment) {
  const target = safeString(serviceConfig.accessKeyFile);
  const source = safeString(config.accessKeyFile);
  deployment.access_key_file_source = source;
  deployment.access_key_file_runtime = target;
  deployment.access_key_file_relocated = !!target && !!source && path.resolve(target) !== path.resolve(source);
  deployment.access_key_file_seeded = false;
  deployment.access_key_file_mode = target ? fileModeOctal(target) : '';
  deployment.access_key_file_seed_skipped_reason = target ? '' : 'not_configured';
  if (!target) return;

  ensureDir(path.dirname(target));
  if (source && path.resolve(source) !== path.resolve(target) && fs.existsSync(source) && !fs.existsSync(target)) {
    fs.copyFileSync(source, target);
    fs.chmodSync(target, 0o600);
    deployment.access_key_file_seeded = true;
    deployment.access_key_file_mode = fileModeOctal(target);
    deployment.access_key_file_seed_skipped_reason = '';
    return;
  }
  if (fs.existsSync(target)) {
    try {
      fs.chmodSync(target, 0o600);
    } catch {}
    deployment.access_key_file_mode = fileModeOctal(target);
    deployment.access_key_file_seed_skipped_reason = deployment.access_key_file_relocated ? 'runtime_already_exists' : 'already_exists';
    return;
  }
  deployment.access_key_file_seed_skipped_reason = source ? 'source_missing' : 'source_not_configured';
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
    skills_synced: false,
    access_key_file_source: config.accessKeyFile || '',
    access_key_file_runtime: serviceConfig.accessKeyFile || '',
    access_key_file_relocated: false,
    access_key_file_seeded: false,
    access_key_file_mode: '',
    access_key_file_seed_skipped_reason: options.dryRun ? 'dry_run' : '',
  };
  if (options.dryRun) {
    deployment.access_key_file_relocated = !!serviceConfig.accessKeyFile
      && !!config.accessKeyFile
      && path.resolve(serviceConfig.accessKeyFile) !== path.resolve(config.accessKeyFile);
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
  deployment.skills_synced = copyDirectoryIfPresent(path.join(config.rootDir, 'skills'), path.join(serviceConfig.rootDir, 'skills'));
  seedLaunchdRuntimeAccessKey(config, serviceConfig, deployment);
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
  const stdout = safeString(result.stdout);
  const output = {
    args,
    ok: status === 0,
    status,
    stdout: stdout.slice(0, 2000),
    stderr: safeString(result.stderr).slice(0, 2000),
  };
  Object.defineProperty(output, 'stdoutFull', {
    value: stdout,
    enumerable: false,
  });
  if (!output.ok && !options.allowFailure) {
    throw new Error(`launchctl_failed:${args.join(' ')}:${output.stderr || output.stdout || status}`);
  }
  return output;
}

function launchctlPid(output) {
  const text = safeString(output?.stdoutFull || output?.stdout);
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
  const launchctlPrintPid = launchctlPid(launchdPrint);
  const pid = launchctlPrintPid || pidFilePid;
  const pidSource = launchctlPrintPid ? 'launchctl_print' : (pidFilePid ? 'pid_file' : 'none');
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
    pid_source: pidSource,
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
    '--public-host',
    config.publicHost,
    '--public-base-url',
    config.publicBaseUrl,
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
    '--allow-memory-skills-production',
  ];
  if (config.publicEndpoint) args.push('--public-endpoint');
  if (safeString(config.accessKeyFile)) args.push('--access-key-file', config.accessKeyFile);
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

function publicBaseUrlReady(config, args = {}) {
  const allowLoopback = parseBool(args['allow-loopback-public-host'], false);
  const raw = safeString(config.publicBaseUrl);
  if (!raw || raw.toLowerCase().includes('replace_with')) return false;
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    return false;
  }
  if (!['http:', 'https:'].includes(parsed.protocol)) return false;
  if (!parsed.hostname || isWildcardHost(parsed.hostname)) return false;
  if (!allowLoopback && isLoopbackHost(parsed.hostname)) return false;
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
  const memorySkills = {
    allow: allowMemorySkillsProduction(args) || requireMemorySkillsProduction(args),
    require: requireMemorySkillsProduction(args),
    ...memorySkillsAuthorityState(readiness),
  };
  const launchdXml = launchdPlistXml(config);
  const watchdogXml = watchdogLaunchdPlistXml(config);
  const launchdPlistSafe = safeString(config.accessKeyFile)
    && launchdXml.includes(config.accessKeyFile)
    && !/"XHUB_RUST_HTTP_ACCESS_KEY"\s*=/.test(launchdXml);
  const watchdogInstallable = watchdogXml.includes('StartInterval')
    && watchdogXml.includes('watchdog')
    && !watchdogXml.includes('<key>RunAtLoad</key>');
  const livePublicEndpointOk = !config.publicEndpoint
    || !readiness
    || (readiness?.capabilities?.cross_network_public_endpoint === true
      && readiness?.network?.cross_network_public_endpoint === true);
  const liveCrossNetworkReadyOk = !config.publicEndpoint
    || !readiness
    || readiness?.capabilities?.cross_network_ready === true;
  const liveDomainEndpointReadyOk = !config.publicEndpoint
    || !readiness
    || (readiness?.capabilities?.domain_public_endpoint_ready === true
      && readiness?.network?.public_endpoint_ready === true);
  const livePublicBaseUrlMatches = !config.publicEndpoint
    || !readiness
    || safeString(readiness?.network?.public_base_url) === config.publicBaseUrl;
  const remoteRouteSmoke = collectCrossNetworkRemoteRouteSmoke(config, args, readiness);

  const checks = [
    { name: 'lan_profile_or_allow_lan_or_public_endpoint', ok: config.allowLan === true || config.publicEndpoint === true, blocking: true },
    { name: 'non_loopback_bind_or_public_endpoint', ok: !isLoopbackHost(config.host) || config.publicEndpoint === true, blocking: true },
    { name: 'public_host_ready', ok: config.publicEndpoint ? true : publicHostReady(config, args), blocking: true },
    { name: 'public_base_url_ready', ok: publicBaseUrlReady(config, args), blocking: true },
    { name: 'public_endpoint_requires_access_key', ok: !config.publicEndpoint || config.httpRequireAccessKey === true, blocking: true },
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
      name: 'live_cross_network_public_endpoint',
      ok: livePublicEndpointOk,
      blocking: config.publicEndpoint && readiness !== null,
    },
    {
      name: 'live_cross_network_ready',
      ok: liveCrossNetworkReadyOk,
      blocking: config.publicEndpoint && readiness !== null,
    },
    {
      name: 'live_domain_public_endpoint_ready',
      ok: liveDomainEndpointReadyOk,
      blocking: config.publicEndpoint && readiness !== null,
    },
    {
      name: 'live_public_base_url_matches',
      ok: livePublicBaseUrlMatches,
      blocking: config.publicEndpoint && readiness !== null,
    },
    {
      name: 'remote_route_smoke',
      ok: remoteRouteSmoke.ok === true,
      blocking: remoteRouteSmoke.required === true,
    },
    {
      name: 'memory_writer_authority_disabled',
      ok: readiness ? (memorySkills.allow || !memorySkills.memory_writer_authority_in_rust) : true,
      blocking: true,
    },
    {
      name: 'skills_execution_authority_disabled',
      ok: readiness ? (memorySkills.allow || !memorySkills.skills_execution_authority_in_rust) : true,
      blocking: true,
    },
    {
      name: 'memory_writer_authority_active',
      ok: !memorySkills.require || memorySkills.memory_writer_authority_in_rust,
      blocking: memorySkills.require,
    },
    {
      name: 'skills_execution_authority_active',
      ok: !memorySkills.require || memorySkills.skills_execution_authority_in_rust,
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
  issues.push(...remoteRouteSmoke.blocking_issues);

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
    public_endpoint: config.publicEndpoint,
    require_live_ready: requireLiveReady,
    require_launchd_loaded: requireLaunchdLoaded,
    require_watchdog_timer: requireWatchdogTimer,
    require_cross_network_remote_route_smoke: remoteRouteSmoke.required === true,
    access_key_file: accessKey,
    launchd_plist_installable: launchdPlistSafe,
    watchdog_timer_installable: watchdogInstallable,
    status: statusOut,
    launchd_status: launchdOut,
    watchdog_timer_status: watchdogTimer,
    cross_network_remote_route_smoke: remoteRouteSmoke,
    cross_network_remote_route_smoke_enabled: remoteRouteSmoke.enabled === true,
    cross_network_remote_route_smoke_required: remoteRouteSmoke.required === true,
    cross_network_remote_route_smoke_ok: remoteRouteSmoke.ok === true,
    ui_compatibility: uiGate,
    rust_product_kernel: true,
    swift_product_shell: true,
    node_compatibility_layer: true,
    node_remains_authority: false,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    memory_skills_production_allowed: memorySkills.allow,
    memory_skills_production_required: memorySkills.require,
    memory_writer_authority_in_rust: memorySkills.memory_writer_authority_in_rust,
    skills_execution_authority_in_rust: memorySkills.skills_execution_authority_in_rust,
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

function parseJsonToolOutput(stdout) {
  const text = safeString(stdout);
  if (!text) return { json: null, error: 'stdout_empty' };
  try {
    return { json: JSON.parse(text), error: '' };
  } catch {}
  const first = text.indexOf('{');
  const last = text.lastIndexOf('}');
  if (first >= 0 && last > first) {
    try {
      return { json: JSON.parse(text.slice(first, last + 1)), error: '' };
    } catch (error) {
      return { json: null, error: safeString(error.message || error) };
    }
  }
  return { json: null, error: 'json_object_not_found' };
}

function hasSecretLikeText(value) {
  return /sk-[A-Za-z0-9]|api_key|access_key"\s*:\s*"(?!\[REDACTED\])|Bearer\s+(?!\[REDACTED\])\S+|[a-f0-9]{64}/i.test(String(value || ''));
}

function hasSecretLikeValue(value) {
  return hasSecretLikeText(JSON.stringify(value || null));
}

function compactRemoteRouteSmokeIssues(report) {
  const issues = [];
  const seen = new Set();
  const add = (code) => {
    const normalized = safeString(code);
    if (!normalized || seen.has(normalized)) return;
    seen.add(normalized);
    issues.push(normalized);
  };
  if (!report || report.ok !== true) add('cross_network_remote_route_smoke_failed');
  for (const issue of Array.isArray(report?.issues) ? report.issues : []) {
    if (typeof issue === 'string') {
      add(`cross_network_remote_route_smoke_${issue}`);
    } else if ((issue?.severity || 'blocker') === 'blocker') {
      add(`cross_network_remote_route_smoke_${issue?.code || 'issue'}`);
    }
  }
  return issues;
}

function collectCrossNetworkRemoteRouteSmoke(config, args = {}, readiness = null) {
  const required = requireCrossNetworkRemoteRouteSmoke(args);
  const enabled = enableCrossNetworkRemoteRouteSmoke(args);
  const timeoutMs = parseIntInRange(args['cross-network-remote-route-smoke-timeout-ms'], 12000, 250, 120000);
  const launchdEnv = readLaunchdEnvironmentVariables(config.launchdInstallPlistPath);
  const publicBaseUrl = safeString(firstValue([
    args['cross-network-remote-route-smoke-public-base-url'],
    readiness?.network?.public_base_url,
    readiness?.public_base_url,
    launchdEnv.XHUB_RUST_HUB_PUBLIC_BASE_URL,
    config.publicBaseUrl,
  ]));
  const accessKeyFile = safeString(firstValue([
    args['cross-network-remote-route-smoke-access-key-file'],
    launchdEnv.XHUB_RUST_HTTP_ACCESS_KEY_FILE,
    config.accessKeyFile,
  ]));
  const commandPath = path.join(config.rootDir, 'tools', 'cross_network_remote_route_doctor.command');
  const base = {
    ok: true,
    enabled,
    required,
    skipped: !enabled,
    reason: enabled ? '' : 'cross_network_remote_route_smoke_not_requested',
    public_base_url: publicBaseUrl,
    access_key_file_configured: safeString(accessKeyFile) !== '',
    access_key_file: accessKeyFile,
    timeout_ms: timeoutMs,
    command_path: commandPath,
    exit_status: null,
    parsed: false,
    parse_error: '',
    report: null,
    report_redacted_due_to_secret_leak: false,
    stdout_tail: '',
    stderr_tail: '',
    secret_leak: false,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    blocking_issues: [],
  };
  const fail = (reason, issue, extra = {}) => ({
    ...base,
    ...extra,
    ok: false,
    enabled: true,
    skipped: false,
    reason,
    blocking_issues: required ? [issue] : [],
  });
  if (!enabled) return base;
  if (!safeString(publicBaseUrl)) {
    return fail(
      'cross_network_remote_route_smoke_public_base_url_missing',
      'cross_network_remote_route_smoke_public_base_url_missing',
    );
  }
  if (!fs.existsSync(commandPath)) {
    return fail(
      'cross_network_remote_route_doctor_missing',
      'cross_network_remote_route_doctor_missing',
    );
  }
  const commandArgs = [
    commandPath,
    '--public-base-url',
    publicBaseUrl,
    '--timeout-ms',
    String(timeoutMs),
    '--require-live-http',
    '--require-auth-ready',
  ];
  if (safeString(accessKeyFile)) {
    commandArgs.push('--access-key-file', accessKeyFile);
  }
  if (parseBool(args['allow-loopback-public-host'], false)) {
    commandArgs.push('--allow-loopback-public-host');
  }
  if (parseBool(args['allow-vpn-raw-host'], false)) {
    commandArgs.push('--allow-vpn-raw-host');
  }
  if (parseBool(args['allow-public-raw-ip'], false)) {
    commandArgs.push('--allow-public-raw-ip');
  }
  const result = spawnSync('bash', commandArgs, {
    cwd: config.rootDir,
    encoding: 'utf8',
    timeout: Math.max(timeoutMs + 5000, 1000),
    maxBuffer: 8 * 1024 * 1024,
  });
  const parsed = parseJsonToolOutput(result.stdout || '');
  const rawSecretLeak = hasSecretLikeText(result.stdout) || hasSecretLikeText(result.stderr);
  const parsedSecretLeak = parsed.json ? hasSecretLikeValue(parsed.json) : false;
  const report = parsed.json && !parsedSecretLeak ? parsed.json : null;
  const blockingIssues = [];
  if (rawSecretLeak || parsedSecretLeak) blockingIssues.push('cross_network_remote_route_smoke_secret_leak');
  if (!parsed.json) blockingIssues.push('cross_network_remote_route_smoke_json_parse_failed');
  if (result.status !== 0 && !parsed.json) blockingIssues.push('cross_network_remote_route_smoke_exit_nonzero');
  if (parsed.json?.ok !== true) blockingIssues.push(...compactRemoteRouteSmokeIssues(parsed.json));
  return {
    ...base,
    ok: blockingIssues.length === 0,
    enabled: true,
    skipped: false,
    reason: blockingIssues.length === 0 ? '' : 'cross_network_remote_route_smoke_failed',
    command: commandLine(['bash', ...commandArgs]),
    exit_status: Number.isFinite(result.status) ? result.status : null,
    parsed: parsed.json !== null,
    parse_error: parsed.error,
    report,
    report_redacted_due_to_secret_leak: parsedSecretLeak,
    stdout_tail: redactEvidenceText(safeString(result.stdout).split(/\r?\n/).slice(-20).join('\n')),
    stderr_tail: redactEvidenceText(safeString(result.stderr).split(/\r?\n/).slice(-20).join('\n')),
    secret_leak: rawSecretLeak || parsedSecretLeak,
    production_authority_change: parsed.json?.production_authority_change === true,
    daemon_restarted: parsed.json?.daemon_restarted === true,
    daemon_stopped: parsed.json?.daemon_stopped === true,
    blocking_issues: required ? [...new Set(blockingIssues)] : [],
  };
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
    '--public-base-url',
    config.publicBaseUrl,
  ];
  if (config.publicEndpoint) args.push('--public-endpoint');
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
    public_endpoint: config.publicEndpoint,
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

function runProductProcessSanity(config, args = {}, reportPath = '', caller = 'ops_gate') {
  const enabled = !parseBool(args['skip-product-process-sanity'], false);
  const commandPath = path.join(config.rootDir, 'tools', 'product_process_sanity.command');
  const sanityReportPath = path.join(
    path.dirname(reportPath || resolveReportPath(config, '', caller === 'watchdog' ? 'daemon_watchdog' : 'daemon_ops_gate')),
    `product_process_sanity_${caller}_${utcStamp()}.json`
  );
  const maxProductCpuPercent = parseIntInRange(args['max-product-cpu-percent'], 0, 0, 1000);
  if (!enabled) {
    return {
      ok: true,
      enabled: false,
      skipped: true,
      reason: 'product_process_sanity_not_requested',
      production_authority_change: false,
      ui_product_change: false,
    };
  }
  if (!fs.existsSync(commandPath)) {
    return {
      ok: false,
      enabled: true,
      skipped: true,
      reason: 'product_process_sanity_missing',
      command_path: commandPath,
      production_authority_change: false,
      ui_product_change: false,
    };
  }
  const commandArgs = [
    commandPath,
    '--report-path',
    sanityReportPath,
  ];
  if (maxProductCpuPercent > 0) {
    commandArgs.push('--max-product-cpu-percent', String(maxProductCpuPercent));
  }
  if (parseBool(args['allow-missing-xhubd'], false)) {
    commandArgs.push('--allow-missing-xhubd');
  }
  if (parseBool(args['require-product-shell'], false)) {
    commandArgs.push('--require-product-shell');
  }
  if (parseBool(args['allow-target-xhubd'], false)) {
    commandArgs.push('--allow-target-xhubd');
  }
  const result = spawnSync('bash', commandArgs, {
    cwd: config.rootDir,
    encoding: 'utf8',
    timeout: 5000,
    maxBuffer: 4 * 1024 * 1024,
  });
  let parsed = null;
  try {
    if (fs.existsSync(sanityReportPath)) {
      parsed = JSON.parse(fs.readFileSync(sanityReportPath, 'utf8'));
    } else if (safeString(result.stdout)) {
      parsed = JSON.parse(result.stdout);
    }
  } catch (error) {
    return {
      ok: false,
      enabled: true,
      skipped: false,
      report_path: sanityReportPath,
      error_code: `product_process_sanity_invalid_json:${error.message}`,
      exit_status: result.status,
      stdout_tail: redactEvidenceText(safeString(result.stdout).split(/\r?\n/).slice(-20).join('\n')),
      stderr_tail: redactEvidenceText(safeString(result.stderr).split(/\r?\n/).slice(-20).join('\n')),
      production_authority_change: false,
      ui_product_change: false,
    };
  }
  if (!parsed) {
    return {
      ok: false,
      enabled: true,
      skipped: false,
      report_path: sanityReportPath,
      error_code: result.error ? `product_process_sanity_spawn_failed:${result.error.message}` : 'product_process_sanity_no_output',
      exit_status: result.status,
      stdout_tail: redactEvidenceText(safeString(result.stdout).split(/\r?\n/).slice(-20).join('\n')),
      stderr_tail: redactEvidenceText(safeString(result.stderr).split(/\r?\n/).slice(-20).join('\n')),
      production_authority_change: false,
      ui_product_change: false,
    };
  }
  return {
    ...parsed,
    ok: parsed?.ok === true && parsed?.production_authority_change !== true && parsed?.ui_product_change !== true,
    enabled: true,
    skipped: false,
    report_path: parsed?.report_path || sanityReportPath,
    exit_status: result.status,
  };
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
    httpMetrics = await httpGetJson(
      `${config.baseUrl}/runtime/http-metrics`,
      1000,
      readAccessKeyForProbe(config),
    );
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
  const memoryGatewayCutoverReadiness = collectMemoryGatewayCutoverReadiness(
    config,
    args,
    statusOut,
    launchdOut,
  );
  const memoryGatewayModelCallPlanShadow = collectMemoryGatewayModelCallPlanShadow(
    config,
    args,
    statusOut,
    launchdOut,
  );
  const memoryGatewayModelCallExecuteSmoke = collectMemoryGatewayModelCallExecuteSmoke(
    config,
    args,
    statusOut,
    launchdOut,
  );
  const memoryGatewayModelCallLocalExecutorSmoke = collectMemoryGatewayModelCallLocalExecutorSmoke(
    config,
    args,
  );
  const remoteRouteSmoke = collectCrossNetworkRemoteRouteSmoke(config, args, readiness);
  const memoryReadinessProbe = await collectMemoryReadiness(config);
  const memoryWritebackCandidateOpsRollup = compactMemoryWritebackCandidateDiagnostics(
    memoryReadinessProbe.readiness,
  );
  if (!memoryReadinessProbe.ok) {
    memoryWritebackCandidateOpsRollup.ok = false;
    memoryWritebackCandidateOpsRollup.ready = false;
    memoryWritebackCandidateOpsRollup.error_code = memoryReadinessProbe.error_code;
    memoryWritebackCandidateOpsRollup.error_message = memoryReadinessProbe.error_message;
  }
  const memorySkills = {
    allow: allowMemorySkillsProduction(args) || requireMemorySkillsProduction(args),
    require: requireMemorySkillsProduction(args),
    ...memorySkillsAuthorityState(readiness),
  };
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
    memory_gateway_cutover_readiness: memoryGatewayCutoverReadiness,
    memory_gateway_cutover_readiness_required: memoryGatewayCutoverReadiness.required === true,
    memory_gateway_cutover_ready: memoryGatewayCutoverReadiness.ready_for_require === true,
    memory_gateway_cutover_readiness_ok: memoryGatewayCutoverReadiness.ok === true,
    memory_gateway_model_call_plan_smoke_enabled: memoryGatewayCutoverReadiness.model_call_plan_smoke_enabled === true,
    memory_gateway_model_call_plan_ready: memoryGatewayCutoverReadiness.model_call_plan_ready === true,
    memory_gateway_model_call_plan_execution_blocked: memoryGatewayCutoverReadiness.model_call_plan_execution_blocked === true,
    memory_gateway_model_call_execution_gate_ready_for_execution: memoryGatewayCutoverReadiness.model_call_execution_gate_ready_for_execution === true,
    memory_gateway_model_call_execution_admission_authority_in_rust: memoryGatewayCutoverReadiness.model_call_execution_admission_authority_in_rust === true,
    memory_gateway_model_call_execution_gate_status: memoryGatewayCutoverReadiness.model_call_execution_gate_status || '',
    memory_gateway_model_call_execution_gate_mode: memoryGatewayCutoverReadiness.model_call_execution_gate_mode || '',
    memory_gateway_model_call_execution_gate_authority: memoryGatewayCutoverReadiness.model_call_execution_gate_authority || '',
    memory_gateway_model_call_execution_gate_blocker_count: Number(memoryGatewayCutoverReadiness.model_call_execution_gate_blocker_count || 0),
    memory_gateway_model_call_execute_blocked: memoryGatewayCutoverReadiness.model_call_execute_blocked === true,
    memory_gateway_model_call_execute_status: memoryGatewayCutoverReadiness.model_call_execute_status || '',
    memory_gateway_model_call_execute_mode: memoryGatewayCutoverReadiness.model_call_execute_mode || '',
    memory_gateway_model_call_execute_authority: memoryGatewayCutoverReadiness.model_call_execute_authority || '',
    memory_gateway_model_call_execute_executor: memoryGatewayCutoverReadiness.model_call_execute_executor || '',
    memory_gateway_model_call_execute_blocker_count: Number(memoryGatewayCutoverReadiness.model_call_execute_blocker_count || 0),
    memory_gateway_model_call_plan_omitted_reason_counts: memoryGatewayCutoverReadiness.model_call_plan_omitted_reason_counts || {},
    memory_gateway_model_call_plan_selected_chunk_count: memoryGatewayCutoverReadiness.model_call_plan_selected_chunk_count || 0,
    memory_gateway_model_call_plan_selected_chunk_ref_count: memoryGatewayCutoverReadiness.model_call_plan_selected_chunk_ref_count || 0,
    memory_gateway_model_call_plan_omitted_ref_count: memoryGatewayCutoverReadiness.model_call_plan_omitted_ref_count || 0,
    memory_gateway_model_call_plan_omitted_chunk_ref_count: memoryGatewayCutoverReadiness.model_call_plan_omitted_chunk_ref_count || 0,
    memory_gateway_model_call_plan_index_granularity: memoryGatewayCutoverReadiness.model_call_plan_index_granularity || '',
    memory_gateway_model_call_plan_index_source: memoryGatewayCutoverReadiness.model_call_plan_index_source || '',
    memory_gateway_model_call_plan_chunk_identity_schema: memoryGatewayCutoverReadiness.model_call_plan_chunk_identity_schema || '',
    memory_gateway_model_call_plan_chunk_expand_via_get_ref: memoryGatewayCutoverReadiness.model_call_plan_chunk_expand_via_get_ref === true,
    memory_gateway_model_call_plan_shadow: memoryGatewayModelCallPlanShadow,
    memory_gateway_model_call_plan_shadow_required: memoryGatewayModelCallPlanShadow.required === true,
    memory_gateway_model_call_plan_shadow_found: memoryGatewayModelCallPlanShadow.status_found === true,
    memory_gateway_model_call_plan_shadow_ok: memoryGatewayModelCallPlanShadow.ok === true,
    memory_gateway_model_call_plan_shadow_evidence_ok: memoryGatewayModelCallPlanShadow.evidence_ok === true,
    memory_gateway_model_call_plan_shadow_execution_safe: memoryGatewayModelCallPlanShadow.execution_safe === true,
    memory_gateway_model_call_plan_shadow_text_safe: memoryGatewayModelCallPlanShadow.text_safe === true,
    memory_gateway_model_call_plan_shadow_omitted_reason_counts: memoryGatewayModelCallPlanShadow.omitted_reason_counts || {},
    memory_gateway_model_call_plan_shadow_selected_chunk_count: memoryGatewayModelCallPlanShadow.selected_chunk_count || 0,
    memory_gateway_model_call_plan_shadow_selected_chunk_ref_count: memoryGatewayModelCallPlanShadow.selected_chunk_ref_count || 0,
    memory_gateway_model_call_plan_shadow_omitted_ref_count: memoryGatewayModelCallPlanShadow.omitted_ref_count || 0,
    memory_gateway_model_call_plan_shadow_omitted_chunk_ref_count: memoryGatewayModelCallPlanShadow.omitted_chunk_ref_count || 0,
    memory_gateway_model_call_plan_shadow_index_granularity: memoryGatewayModelCallPlanShadow.index_granularity || '',
    memory_gateway_model_call_plan_shadow_index_source: memoryGatewayModelCallPlanShadow.index_source || '',
    memory_gateway_model_call_plan_shadow_chunk_identity_schema: memoryGatewayModelCallPlanShadow.chunk_identity_schema || '',
    memory_gateway_model_call_plan_shadow_chunk_expand_via_get_ref: memoryGatewayModelCallPlanShadow.chunk_expand_via_get_ref === true,
    memory_gateway_model_call_execute_smoke: memoryGatewayModelCallExecuteSmoke,
    memory_gateway_model_call_execute_smoke_required: memoryGatewayModelCallExecuteSmoke.required === true,
    memory_gateway_model_call_execute_smoke_found: memoryGatewayModelCallExecuteSmoke.status_found === true,
    memory_gateway_model_call_execute_smoke_ok: memoryGatewayModelCallExecuteSmoke.ok === true,
    memory_gateway_model_call_execute_smoke_execution_blocked: memoryGatewayModelCallExecuteSmoke.execution_blocked === true,
    memory_gateway_model_call_execute_smoke_content_free: memoryGatewayModelCallExecuteSmoke.content_free !== false,
    memory_gateway_model_call_execute_smoke_admission_ready: memoryGatewayModelCallExecuteSmoke.admission_ready === true,
    memory_gateway_model_call_execute_smoke_status: memoryGatewayModelCallExecuteSmoke.execute_status || '',
    memory_gateway_model_call_execute_smoke_mode: memoryGatewayModelCallExecuteSmoke.execute_mode || '',
    memory_gateway_model_call_execute_smoke_authority: memoryGatewayModelCallExecuteSmoke.execute_authority || '',
    memory_gateway_model_call_execute_smoke_blocker_count: Number(memoryGatewayModelCallExecuteSmoke.execute_blocker_count || 0),
    memory_gateway_model_call_local_executor_smoke: memoryGatewayModelCallLocalExecutorSmoke,
    memory_gateway_model_call_local_executor_smoke_required: memoryGatewayModelCallLocalExecutorSmoke.required === true,
    memory_gateway_model_call_local_executor_smoke_found: memoryGatewayModelCallLocalExecutorSmoke.report_found === true,
    memory_gateway_model_call_local_executor_smoke_ok: memoryGatewayModelCallLocalExecutorSmoke.ok === true,
    memory_gateway_model_call_local_executor_smoke_isolated_daemon: memoryGatewayModelCallLocalExecutorSmoke.isolated_daemon === true,
    memory_gateway_model_call_local_executor_smoke_live_daemon_touched: memoryGatewayModelCallLocalExecutorSmoke.live_daemon_touched === true,
    memory_gateway_model_call_local_executor_smoke_content_free: memoryGatewayModelCallLocalExecutorSmoke.content_free !== false,
    memory_gateway_model_call_local_executor_smoke_status: memoryGatewayModelCallLocalExecutorSmoke.execute_status || '',
    memory_gateway_model_call_local_executor_smoke_mode: memoryGatewayModelCallLocalExecutorSmoke.execute_mode || '',
    memory_gateway_model_call_local_executor_smoke_authority: memoryGatewayModelCallLocalExecutorSmoke.execute_authority || '',
    memory_gateway_model_call_local_executor_smoke_local_ml_execute_http_invoked: memoryGatewayModelCallLocalExecutorSmoke.local_ml_execute_http_invoked === true,
    memory_gateway_model_call_local_executor_smoke_recent_slow_requests: Number(memoryGatewayModelCallLocalExecutorSmoke.http_recent_slow_requests || 0),
    memory_gateway_model_call_local_executor_smoke_recent_max_elapsed_ms: Number(memoryGatewayModelCallLocalExecutorSmoke.http_recent_max_elapsed_ms || 0),
    cross_network_remote_route_smoke: remoteRouteSmoke,
    cross_network_remote_route_smoke_enabled: remoteRouteSmoke.enabled === true,
    cross_network_remote_route_smoke_required: remoteRouteSmoke.required === true,
    cross_network_remote_route_smoke_ok: remoteRouteSmoke.ok === true,
    memory_readiness_ready: memoryReadinessProbe.ok === true,
    memory_readiness_error_code: memoryReadinessProbe.error_code || "",
    memory_readiness_error_message: memoryReadinessProbe.error_message || "",
    memory_writeback_candidate_ops_rollup: memoryWritebackCandidateOpsRollup,
    memory_writeback_candidate_queue_ready: memoryWritebackCandidateOpsRollup.ready === true,
    memory_writeback_candidate_queue_pressure: memoryWritebackCandidateOpsRollup.queue_pressure,
    memory_writeback_candidate_noise_score: memoryWritebackCandidateOpsRollup.noise_score,
    memory_writeback_candidate_conflict_count: memoryWritebackCandidateOpsRollup.conflict_candidate_count,
    memory_writeback_candidate_stale_review_required_count: memoryWritebackCandidateOpsRollup.stale_review_required_count,
    memory_writeback_candidate_production_authority_change: memoryWritebackCandidateOpsRollup.production_authority_change === true,
    ui_product_change: uiGate.product_ui_change === true,
    swift_ui_files_touched: uiGate.swift_ui_files_touched === true,
    rust_browser_product_ui: uiGate.rust_browser_product_ui === true,
    rust_product_kernel: true,
    swift_product_shell: true,
    node_compatibility_layer: true,
    node_remains_authority: false,
    production_authority_change: false,
    memory_skills_production_allowed: memorySkills.allow,
    memory_skills_production_required: memorySkills.require,
    memory_writer_authority_in_rust: memorySkills.memory_writer_authority_in_rust,
    skills_execution_authority_in_rust: memorySkills.skills_execution_authority_in_rust,
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
    && report.memory_writeback_candidate_production_authority_change === false
    && report.ui_product_change === false
    && report.swift_ui_files_touched === false
    && report.rust_browser_product_ui === false
    && (memorySkills.allow || report.memory_writer_authority_in_rust === false)
    && (memorySkills.allow || report.skills_execution_authority_in_rust === false)
    && (!memorySkills.require || report.memory_writer_authority_in_rust === true)
    && (!memorySkills.require || report.skills_execution_authority_in_rust === true)
    && report.memory_gateway_cutover_readiness_ok === true
    && report.memory_gateway_model_call_plan_shadow_ok === true
    && report.memory_gateway_model_call_execute_smoke_ok === true
    && report.memory_gateway_model_call_local_executor_smoke_ok === true
    && report.xt_file_ipc_run_once_smoke_ok === true
    && report.xt_file_ipc_background_watcher_smoke_ok === true;
  ensureDir(path.dirname(reportPath));
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  printJson(report, (requireReady && (!healthy || !readyState)) || !report.ok ? 2 : 0);
}

function uniquePaths(values) {
  return Array.from(new Set(values.filter((value) => safeString(value)).map((value) => path.resolve(value))));
}

function parentOfDataDbPath(dbPath) {
  const resolved = safeString(dbPath);
  if (!resolved) return '';
  const dataDir = path.dirname(resolved);
  if (path.basename(dataDir) !== 'data') return '';
  return path.dirname(dataDir);
}

function liveBaseDirCandidates(config, statusOut = {}, launchdOut = {}) {
  const serviceConfig = launchdRuntimeConfig(config);
  const groupBaseDir = path.join(os.homedir(), 'Library', 'Group Containers', 'group.rel.flowhub');
  const appSupportBaseDir = path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub', config.profile);
  const liveStatusBaseDir = safeString(statusOut?.health?.db_path)
    ? parentOfDataDbPath(statusOut.health.db_path)
    : '';
  const liveLaunchdBaseDir = safeString(launchdOut?.health?.db_path)
    ? parentOfDataDbPath(launchdOut.health.db_path)
    : '';
  return uniquePaths([
    config.rootDir,
    serviceConfig.rootDir,
    liveStatusBaseDir,
    liveLaunchdBaseDir,
    appSupportBaseDir,
    groupBaseDir,
  ]);
}

function memoryGatewayModelCallPlanShadowCandidatePaths(config, args = {}, statusOut = {}, launchdOut = {}) {
  const explicitStatusPath = pathFromRoot(firstValue([
    args['memory-gateway-model-call-plan-status-path'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_STATUS_PATH,
  ]));
  const explicitBaseDir = pathFromRoot(firstValue([
    args['memory-gateway-model-call-plan-base-dir'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_BASE_DIR,
    process.env.XHUB_RUST_MEMORY_GATEWAY_CUTOVER_BASE_DIR,
    process.env.REL_FLOW_HUB_BASE_DIR,
  ]));
  const fileName = 'memory_gateway_model_call_plan_status.json';
  return uniquePaths([
    explicitStatusPath,
    explicitBaseDir ? path.join(explicitBaseDir, fileName) : '',
    ...liveBaseDirCandidates(config, statusOut, launchdOut).map((baseDir) => path.join(baseDir, fileName)),
  ]);
}

function memoryGatewayModelCallPlanShadowHistoryCandidatePaths(statusPath, args = {}) {
  const explicitHistoryPath = pathFromRoot(firstValue([
    args['memory-gateway-model-call-plan-history-path'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_HISTORY_PATH,
  ]));
  const statusDir = safeString(statusPath) ? path.dirname(statusPath) : '';
  return uniquePaths([
    explicitHistoryPath,
    statusDir ? path.join(statusDir, 'memory_gateway_model_call_plan_history.json') : '',
  ]);
}

function readMemoryGatewayModelCallPlanShadowStatus(filePath) {
  const parsed = readMemoryGatewayJsonObject(filePath);
  if (!parsed) return { ok: false, error: 'status_not_parseable', status: null };
  return { ok: true, error: '', status: parsed };
}

function collectMemoryGatewayModelCallPlanShadow(config, args = {}, statusOut = {}, launchdOut = {}) {
  const required = requireMemoryGatewayModelCallPlanShadow(args);
  const candidates = memoryGatewayModelCallPlanShadowCandidatePaths(config, args, statusOut, launchdOut);
  const explicitPath = safeString(args['memory-gateway-model-call-plan-status-path'])
    || safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_STATUS_PATH);
  const out = {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_plan_shadow_gate.v1',
    ok: true,
    required,
    enabled: false,
    status_found: false,
    status_path: '',
    history_found: false,
    history_path: '',
    candidate_paths: candidates,
    schema_ok: false,
    evidence_ok: false,
    source: '',
    mode: '',
    request_id: '',
    audit_ref: '',
    requester_role: '',
    use_mode: '',
    scope: '',
    serving_profile_id: '',
    project_id: '',
    session_id: '',
    app_id: '',
    provider_id: '',
    model_id: '',
    task_kind: '',
    plan_schema_version: '',
    plan_status: '',
    plan_source: '',
    plan_mode: '',
    plan_authority: '',
    context_char_count: 0,
    selected_ref_count: 0,
    selected_chunk_count: 0,
    selected_chunk_ref_count: 0,
    omitted_ref_count: 0,
    omitted_chunk_ref_count: 0,
    omitted_reason_counts: {},
    index_source: '',
    index_granularity: '',
    chunk_identity_schema: '',
    chunk_expand_via_get_ref: false,
    prompt_char_count: 0,
    message_count: 0,
    would_call_model: false,
    model_call_executed: false,
    production_authority_change: false,
    context_text_included: false,
    prompt_text_included: false,
    execution_safe: true,
    text_safe: true,
    issue_codes: [],
    reason_code: '',
    detail: '',
    recorded_at_ms: null,
    age_ms: null,
    history_sample_count: 0,
    latest_history_recorded_at_ms: null,
    blocking_issues: [],
    error: '',
  };

  const statusPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!statusPath) {
    if (required) out.blocking_issues.push('memory_gateway_model_call_plan_shadow_missing');
    out.ok = out.blocking_issues.length === 0;
    return out;
  }

  out.enabled = true;
  out.status_found = true;
  out.status_path = statusPath;
  const loaded = readMemoryGatewayModelCallPlanShadowStatus(statusPath);
  if (!loaded.ok) {
    out.error = loaded.error;
    if (required || explicitPath) out.blocking_issues.push('memory_gateway_model_call_plan_shadow_invalid');
    out.ok = out.blocking_issues.length === 0;
    return out;
  }

  const status = loaded.status;
  out.schema_ok = status.schema_version === 'xt.rust_memory_gateway_model_call_plan_shadow.v1';
  out.evidence_ok = status.ok === true;
  out.source = safeString(status.source);
  out.mode = safeString(status.mode);
  out.request_id = safeString(status.request_id);
  out.audit_ref = safeString(status.audit_ref);
  out.requester_role = safeString(status.requester_role);
  out.use_mode = safeString(status.use_mode);
  out.scope = safeString(status.scope);
  out.serving_profile_id = normalizedMemoryGatewayProfileId(status.serving_profile_id);
  out.project_id = safeString(status.project_id);
  out.session_id = safeString(status.session_id);
  out.app_id = safeString(status.app_id);
  out.provider_id = safeString(status.provider_id);
  out.model_id = safeString(status.model_id);
  out.task_kind = safeString(status.task_kind);
  out.plan_schema_version = safeString(status.plan_schema_version);
  out.plan_status = safeString(status.plan_status);
  out.plan_source = safeString(status.plan_source);
  out.plan_mode = safeString(status.plan_mode);
  out.plan_authority = safeString(status.plan_authority);
  out.context_char_count = Number(status.context_char_count || 0);
  out.selected_ref_count = Number(status.selected_ref_count || 0);
  const chunkEvidence = summarizeMemoryGatewayChunkEvidence(status);
  out.selected_chunk_count = chunkEvidence.selected_chunk_count;
  out.selected_chunk_ref_count = chunkEvidence.selected_chunk_ref_count;
  out.omitted_ref_count = chunkEvidence.omitted_ref_count;
  out.omitted_chunk_ref_count = chunkEvidence.omitted_chunk_ref_count;
  out.index_source = chunkEvidence.index_source;
  out.index_granularity = chunkEvidence.index_granularity;
  out.chunk_identity_schema = chunkEvidence.chunk_identity_schema;
  out.chunk_expand_via_get_ref = chunkEvidence.chunk_expand_via_get_ref;
  out.omitted_reason_counts = normalizedObjectCounts(status.omitted_reason_counts);
  out.prompt_char_count = Number(status.prompt_char_count || 0);
  out.message_count = Number(status.message_count || 0);
  out.would_call_model = status.would_call_model === true;
  out.model_call_executed = status.model_call_executed === true;
  out.production_authority_change = status.production_authority_change === true;
  out.context_text_included = status.context_text_included === true;
  out.prompt_text_included = status.prompt_text_included === true;
  out.execution_safe = !out.would_call_model && !out.model_call_executed;
  out.text_safe = !out.context_text_included && !out.prompt_text_included;
  out.issue_codes = Array.from(new Set(
    (Array.isArray(status.issue_codes) ? status.issue_codes : [])
      .map((value) => safeString(value))
      .filter(Boolean)
  )).slice(0, 16);
  out.reason_code = safeString(status.reason_code || out.issue_codes[0]);
  out.detail = safeString(status.detail).slice(0, 300);
  out.recorded_at_ms = Number.isFinite(Number(status.recorded_at_ms)) ? Number(status.recorded_at_ms) : null;
  out.age_ms = out.recorded_at_ms !== null ? Math.max(0, Date.now() - out.recorded_at_ms) : null;

  for (const historyPath of memoryGatewayModelCallPlanShadowHistoryCandidatePaths(statusPath, args)) {
    const parsed = readMemoryGatewayJsonObject(historyPath);
    if (Array.isArray(parsed?.items)) {
      out.history_found = true;
      out.history_path = historyPath;
      out.history_sample_count = parsed.items.length;
      out.latest_history_recorded_at_ms = parsed.items.reduce((latest, item) => {
        const value = Number(item?.recorded_at_ms || 0);
        return value > latest ? value : latest;
      }, 0) || null;
      break;
    }
  }

  if (!out.schema_ok && (required || explicitPath)) {
    out.blocking_issues.push('memory_gateway_model_call_plan_shadow_schema_mismatch');
  }
  if (required && !out.evidence_ok) {
    out.blocking_issues.push('memory_gateway_model_call_plan_shadow_not_ok');
  }
  if (out.production_authority_change) {
    out.blocking_issues.push('memory_gateway_model_call_plan_shadow_authority_violation');
  }
  if (!out.execution_safe) {
    out.blocking_issues.push('memory_gateway_model_call_plan_shadow_executed_unexpectedly');
  }
  if (!out.text_safe) {
    out.blocking_issues.push('memory_gateway_model_call_plan_shadow_text_leak');
  }
  out.blocking_issues = Array.from(new Set(out.blocking_issues));
  out.ok = out.blocking_issues.length === 0;
  return out;
}

function memoryGatewayModelCallExecuteSmokeCandidatePaths(config, args = {}, statusOut = {}, launchdOut = {}) {
  const explicitStatusPath = pathFromRoot(firstValue([
    args['memory-gateway-model-call-execute-smoke-status-path'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SMOKE_STATUS_PATH,
  ]));
  const explicitBaseDir = pathFromRoot(firstValue([
    args['memory-gateway-model-call-execute-smoke-base-dir'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SMOKE_BASE_DIR,
    process.env.XHUB_RUST_MEMORY_GATEWAY_CUTOVER_BASE_DIR,
    process.env.REL_FLOW_HUB_BASE_DIR,
  ]));
  const fileName = 'memory_gateway_model_call_execute_smoke_status.json';
  return uniquePaths([
    explicitStatusPath,
    explicitBaseDir ? path.join(explicitBaseDir, fileName) : '',
    ...liveBaseDirCandidates(config, statusOut, launchdOut).map((baseDir) => path.join(baseDir, fileName)),
  ]);
}

function memoryGatewayModelCallExecuteSmokeHistoryCandidatePaths(statusPath, args = {}) {
  const explicitHistoryPath = pathFromRoot(firstValue([
    args['memory-gateway-model-call-execute-smoke-history-path'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SMOKE_HISTORY_PATH,
  ]));
  const statusDir = safeString(statusPath) ? path.dirname(statusPath) : '';
  return uniquePaths([
    explicitHistoryPath,
    statusDir ? path.join(statusDir, 'memory_gateway_model_call_execute_smoke_history.json') : '',
  ]);
}

function collectMemoryGatewayModelCallExecuteSmoke(config, args = {}, statusOut = {}, launchdOut = {}) {
  const required = requireMemoryGatewayModelCallExecuteSmoke(args);
  const candidates = memoryGatewayModelCallExecuteSmokeCandidatePaths(config, args, statusOut, launchdOut);
  const explicitPath = safeString(args['memory-gateway-model-call-execute-smoke-status-path'])
    || safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SMOKE_STATUS_PATH);
  const out = {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_execute_smoke_gate.v1',
    ok: true,
    required,
    enabled: false,
    status_found: false,
    status_path: '',
    history_found: false,
    history_path: '',
    candidate_paths: candidates,
    schema_ok: false,
    evidence_ok: false,
    execution_blocked: false,
    content_free: true,
    admission_ready: false,
    require_admission_ready: false,
    memory_execute_http: false,
    gate_status: '',
    gate_mode: '',
    gate_authority: '',
    gate_ready_for_execution: false,
    execute_status: '',
    execute_mode: '',
    execute_authority: '',
    execute_executor: '',
    execute_blocker_count: 0,
    execute_would_call_model: false,
    execute_model_call_invoked: false,
    execute_model_call_executed: false,
    execute_local_ml_invoked: false,
    production_authority_change: false,
    issue_codes: [],
    generated_at_ms: null,
    age_ms: null,
    history_sample_count: 0,
    latest_history_generated_at_ms: null,
    rollback_env_to_unset: [],
    blocking_issues: [],
    error: '',
  };

  const statusPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!statusPath) {
    if (required) out.blocking_issues.push('memory_gateway_model_call_execute_smoke_missing');
    out.ok = out.blocking_issues.length === 0;
    return out;
  }

  out.enabled = true;
  out.status_found = true;
  out.status_path = statusPath;
  const status = readMemoryGatewayJsonObject(statusPath);
  if (!status) {
    if (required || explicitPath) out.blocking_issues.push('memory_gateway_model_call_execute_smoke_invalid');
    out.error = 'status_not_parseable';
    out.ok = out.blocking_issues.length === 0;
    return out;
  }

  out.schema_ok = status.schema_version === 'xhub.rust_hub.memory_gateway_model_call_execute_smoke.v1';
  out.evidence_ok = status.ok === true;
  out.execution_blocked = status.execution_blocked === true;
  out.content_free = status.content_free !== false;
  out.admission_ready = status.admission_ready === true;
  out.require_admission_ready = status.require_admission_ready === true;
  out.memory_execute_http = status.memory_execute_http === true;
  out.gate_status = safeString(status.gate?.status);
  out.gate_mode = safeString(status.gate?.mode);
  out.gate_authority = safeString(status.gate?.authority);
  out.gate_ready_for_execution = status.gate?.ready_for_execution === true;
  out.execute_status = safeString(status.execute?.status);
  out.execute_mode = safeString(status.execute?.mode);
  out.execute_authority = safeString(status.execute?.authority);
  out.execute_executor = safeString(status.execute?.executor);
  out.execute_blocker_count = Number(status.execute?.blocker_count || 0);
  out.execute_would_call_model = status.execute?.would_call_model === true;
  out.execute_model_call_invoked = status.execute?.model_call_invoked === true;
  out.execute_model_call_executed = status.execute?.model_call_executed === true;
  out.execute_local_ml_invoked = status.execute?.local_ml_execute_http_invoked === true;
  out.production_authority_change = status.production_authority_change === true;
  out.issue_codes = Array.from(new Set(
    (Array.isArray(status.issue_codes) ? status.issue_codes : [])
      .map((value) => safeString(value))
      .filter(Boolean)
  )).slice(0, 16);
  out.generated_at_ms = Number.isFinite(Number(status.generated_at_ms)) ? Number(status.generated_at_ms) : null;
  out.age_ms = out.generated_at_ms !== null ? Math.max(0, Date.now() - out.generated_at_ms) : null;
  out.rollback_env_to_unset = Array.isArray(status.rollback_plan?.env_to_unset)
    ? status.rollback_plan.env_to_unset.map((value) => safeString(value)).filter(Boolean).slice(0, 16)
    : [];

  for (const historyPath of memoryGatewayModelCallExecuteSmokeHistoryCandidatePaths(statusPath, args)) {
    const parsed = readMemoryGatewayJsonObject(historyPath);
    if (Array.isArray(parsed?.items)) {
      out.history_found = true;
      out.history_path = historyPath;
      out.history_sample_count = parsed.items.length;
      out.latest_history_generated_at_ms = parsed.items.reduce((latest, item) => {
        const value = Number(item?.generated_at_ms || 0);
        return value > latest ? value : latest;
      }, 0) || null;
      break;
    }
  }

  if (!out.schema_ok && (required || explicitPath)) {
    out.blocking_issues.push('memory_gateway_model_call_execute_smoke_schema_mismatch');
  }
  if (required && !out.evidence_ok) {
    out.blocking_issues.push('memory_gateway_model_call_execute_smoke_not_ok');
  }
  if (out.production_authority_change) {
    out.blocking_issues.push('memory_gateway_model_call_execute_smoke_authority_violation');
  }
  if (!out.execution_blocked) {
    out.blocking_issues.push('memory_gateway_model_call_execute_smoke_not_blocked');
  }
  if (out.execute_would_call_model || out.execute_model_call_invoked || out.execute_model_call_executed || out.execute_local_ml_invoked) {
    out.blocking_issues.push('memory_gateway_model_call_execute_smoke_invoked_unexpectedly');
  }
  if (!out.content_free) {
    out.blocking_issues.push('memory_gateway_model_call_execute_smoke_text_leak');
  }
  out.blocking_issues = Array.from(new Set(out.blocking_issues));
  out.ok = out.blocking_issues.length === 0;
  return out;
}

function latestReportPathInDir(dir, prefix) {
  const resolvedDir = safeString(dir);
  if (!resolvedDir || !fs.existsSync(resolvedDir)) return '';
  try {
    const matches = fs.readdirSync(resolvedDir)
      .filter((name) => name.startsWith(prefix) && name.endsWith('.json'))
      .map((name) => {
        const filePath = path.join(resolvedDir, name);
        let mtimeMs = 0;
        try {
          mtimeMs = fs.statSync(filePath).mtimeMs;
        } catch {}
        return { filePath, mtimeMs };
      })
      .filter((entry) => entry.mtimeMs > 0)
      .sort((a, b) => b.mtimeMs - a.mtimeMs);
    return matches[0]?.filePath || '';
  } catch {
    return '';
  }
}

function memoryGatewayModelCallLocalExecutorSmokeCandidatePaths(config, args = {}) {
  const explicitReportPath = pathFromRoot(firstValue([
    args['memory-gateway-model-call-local-executor-smoke-report-path'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR_SMOKE_REPORT_PATH,
  ]));
  const explicitBaseDir = pathFromRoot(firstValue([
    args['memory-gateway-model-call-local-executor-smoke-base-dir'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR_SMOKE_BASE_DIR,
  ]));
  const prefix = 'memory_gateway_model_call_local_executor_smoke_';
  const reportDirs = uniquePaths([
    explicitBaseDir ? path.join(explicitBaseDir, 'reports') : '',
    explicitBaseDir,
    path.join(config.rootDir, 'reports'),
  ]);
  return uniquePaths([
    explicitReportPath,
    ...reportDirs.map((dir) => latestReportPathInDir(dir, prefix)),
  ]);
}

function collectMemoryGatewayModelCallLocalExecutorSmoke(config, args = {}) {
  const required = requireMemoryGatewayModelCallLocalExecutorSmoke(args);
  const candidates = memoryGatewayModelCallLocalExecutorSmokeCandidatePaths(config, args);
  const explicitPath = safeString(args['memory-gateway-model-call-local-executor-smoke-report-path'])
    || safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR_SMOKE_REPORT_PATH);
  const out = {
    schema_version: 'xhub.rust_hub.memory_gateway_model_call_local_executor_smoke_gate.v1',
    ok: true,
    required,
    enabled: false,
    report_found: false,
    report_path: '',
    candidate_paths: candidates,
    schema_ok: false,
    evidence_ok: false,
    isolated_daemon: false,
    live_daemon_touched: false,
    production_authority_change: false,
    content_free: true,
    execute_status: '',
    execute_mode: '',
    execute_authority: '',
    execution_authority_in_rust: false,
    execution_enabled: false,
    ready_for_execution: false,
    model_call_invoked: false,
    model_call_executed: false,
    local_ml_execute_http_invoked: false,
    context_text_redacted_from_execute: false,
    prompt_text_redacted_from_execute: false,
    provider_route_not_mutated: false,
    node_not_authority: false,
    local_executor_enabled: false,
    local_executor_apply_enabled: false,
    local_route_allowed: false,
    http_slow_requests: 0,
    http_recent_slow_requests: 0,
    http_recent_max_elapsed_ms: 0,
    duration_ms: 0,
    generated_at_iso: '',
    age_ms: null,
    issue_codes: [],
    blocking_issues: [],
    error: '',
  };

  const reportPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!reportPath) {
    if (required) out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_missing');
    out.ok = out.blocking_issues.length === 0;
    return out;
  }

  out.enabled = true;
  out.report_found = true;
  out.report_path = reportPath;
  const report = readMemoryGatewayJsonObject(reportPath);
  if (!report) {
    if (required || explicitPath) out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_invalid');
    out.error = 'report_not_parseable';
    out.ok = out.blocking_issues.length === 0;
    return out;
  }

  const execute = report.execute || {};
  out.schema_ok = report.schema_version === 'xhub.rust_hub.memory_gateway_model_call_local_executor_smoke.v1';
  out.evidence_ok = report.ok === true;
  out.isolated_daemon = report.isolated_daemon === true;
  out.live_daemon_touched = report.live_daemon_touched === true;
  out.production_authority_change = report.production_authority_change === true;
  out.content_free = report.content_free !== false;
  out.execute_status = safeString(execute.status);
  out.execute_mode = safeString(execute.mode);
  out.execute_authority = safeString(execute.authority);
  out.execution_authority_in_rust = execute.execution_authority_in_rust === true;
  out.execution_enabled = execute.execution_enabled === true;
  out.ready_for_execution = execute.ready_for_execution === true;
  out.model_call_invoked = execute.model_call_invoked === true;
  out.model_call_executed = execute.model_call_executed === true;
  out.local_ml_execute_http_invoked = execute.local_ml_execute_http_invoked === true;
  out.context_text_redacted_from_execute = execute.context_text_redacted_from_execute === true;
  out.prompt_text_redacted_from_execute = execute.prompt_text_redacted_from_execute === true;
  out.provider_route_not_mutated = execute.provider_route_not_mutated === true;
  out.node_not_authority = execute.node_not_authority === true;
  out.local_executor_enabled = execute.local_executor_enabled === true;
  out.local_executor_apply_enabled = execute.local_executor_apply_enabled === true;
  out.local_route_allowed = execute.local_route_allowed === true;
  out.http_slow_requests = Number(report.http_metrics?.slow_requests || 0);
  out.http_recent_slow_requests = Number(report.http_metrics?.recent_slow_requests || 0);
  out.http_recent_max_elapsed_ms = Number(report.http_metrics?.recent_max_elapsed_ms || 0);
  out.duration_ms = Number(report.duration_ms || 0);
  out.generated_at_iso = safeString(report.generated_at_iso);
  const generatedAtMs = Date.parse(out.generated_at_iso);
  out.age_ms = Number.isFinite(generatedAtMs) ? Math.max(0, Date.now() - generatedAtMs) : null;
  out.issue_codes = Array.from(new Set(
    (Array.isArray(report.issue_codes) ? report.issue_codes : [])
      .map((value) => safeString(value))
      .filter(Boolean)
  )).slice(0, 16);
  out.error = safeString(report.error).slice(0, 300);

  if (!out.schema_ok && (required || explicitPath)) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_schema_mismatch');
  }
  if (required && !out.evidence_ok) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_not_ok');
  }
  if (!out.isolated_daemon) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_not_isolated');
  }
  if (out.live_daemon_touched) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_live_daemon_touched');
  }
  if (out.production_authority_change) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_authority_violation');
  }
  if (!out.content_free) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_text_leak');
  }
  if (out.http_slow_requests > 0 || out.http_recent_slow_requests > 0) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_slow_request_observed');
  }
  if (out.execute_status !== 'executed' || out.execute_mode !== 'local_ml_execute') {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_execute_not_observed');
  }
  if (!out.execution_authority_in_rust || !out.execution_enabled || !out.ready_for_execution) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_authority_not_active');
  }
  if (!out.model_call_invoked || !out.model_call_executed || !out.local_ml_execute_http_invoked) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_model_call_not_invoked');
  }
  if (!out.context_text_redacted_from_execute || !out.prompt_text_redacted_from_execute) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_redaction_guard_missing');
  }
  if (!out.provider_route_not_mutated || !out.node_not_authority) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_authority_guard_missing');
  }
  if (!out.local_executor_enabled || !out.local_executor_apply_enabled || !out.local_route_allowed) {
    out.blocking_issues.push('memory_gateway_model_call_local_executor_smoke_executor_flags_missing');
  }
  out.blocking_issues = Array.from(new Set(out.blocking_issues));
  out.ok = out.blocking_issues.length === 0;
  return out;
}

function memoryGatewayCutoverReadinessCandidatePaths(config, args = {}, statusOut = {}, launchdOut = {}) {
  const explicitPath = pathFromRoot(firstValue([
    args['memory-gateway-cutover-readiness-path'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_CUTOVER_READINESS_PATH,
  ]));
  const explicitBaseDir = pathFromRoot(firstValue([
    args['memory-gateway-cutover-base-dir'],
    process.env.XHUB_RUST_MEMORY_GATEWAY_CUTOVER_BASE_DIR,
    process.env.REL_FLOW_HUB_BASE_DIR,
  ]));
  const serviceConfig = launchdRuntimeConfig(config);
  const groupBaseDir = path.join(os.homedir(), 'Library', 'Group Containers', 'group.rel.flowhub');
  const appSupportBaseDir = path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub', config.profile);
  const liveStatusBaseDir = safeString(statusOut?.health?.db_path)
    ? parentOfDataDbPath(statusOut.health.db_path)
    : '';
  const liveLaunchdBaseDir = safeString(launchdOut?.health?.db_path)
    ? parentOfDataDbPath(launchdOut.health.db_path)
    : '';
  const fileName = 'memory_gateway_cutover_readiness.json';

  return uniquePaths([
    explicitPath,
    explicitBaseDir ? path.join(explicitBaseDir, fileName) : '',
    path.join(config.rootDir, fileName),
    path.join(serviceConfig.rootDir, fileName),
    liveStatusBaseDir ? path.join(liveStatusBaseDir, fileName) : '',
    liveLaunchdBaseDir ? path.join(liveLaunchdBaseDir, fileName) : '',
    path.join(appSupportBaseDir, fileName),
    path.join(groupBaseDir, fileName),
  ]);
}

function readMemoryGatewayCutoverReadinessReport(filePath) {
  try {
    const data = fs.readFileSync(filePath, 'utf8');
    const parsed = JSON.parse(data);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return { ok: false, error: 'json_not_object', report: null };
    }
    return { ok: true, error: '', report: parsed };
  } catch (error) {
    return { ok: false, error: String(error?.message || error), report: null };
  }
}

function compactMemoryGatewayCutoverIssue(issue) {
  const code = safeString(issue?.code);
  const detail = safeString(issue?.detail);
  return {
    code,
    blocking: issue?.blocking === true,
    detail: detail.slice(0, 300),
  };
}

function normalizedMemoryGatewayProfileId(value) {
  const raw = safeString(value);
  if (!raw) return '';
  const key = raw.toLowerCase().replace(/[\s-]+/g, '_');
  const profiles = {
    m0_heartbeat: 'M0_Heartbeat',
    m1_execute: 'M1_Execute',
    m2_plan_review: 'M2_PlanReview',
    m3_deep_dive: 'M3_DeepDive',
    m4_full_scan: 'M4_FullScan',
  };
  return profiles[key] || raw;
}

function normalizedEvidenceKey(value) {
  return safeString(value)
    .replace(/[^A-Za-z0-9_.:-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80);
}

function normalizedObjectCounts(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  const out = {};
  const entries = Object.entries(value)
    .map(([key, count]) => [normalizedEvidenceKey(key), Number(count)])
    .filter(([key, count]) => key && Number.isFinite(count) && count > 0)
    .sort(([left], [right]) => left.localeCompare(right))
    .slice(0, 32);
  for (const [key, count] of entries) {
    out[key] = Math.max(0, Math.min(1_000_000, Math.trunc(count)));
  }
  return out;
}

function boundedOpsCount(value) {
  const count = Number(value || 0);
  if (!Number.isFinite(count)) return 0;
  return Math.max(0, Math.min(1_000_000, Math.trunc(count)));
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function countChunkIdentityRefs(value) {
  return arrayValue(value).filter((item) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return false;
    return Boolean(safeString(item.chunk_ref) || safeString(item.chunk_id));
  }).length;
}

function summarizeMemoryGatewayChunkEvidence(source = {}, fallback = {}) {
  const selectedRefs = arrayValue(source.selected_refs).length > 0
    ? arrayValue(source.selected_refs)
    : arrayValue(fallback.selected_refs);
  const omittedRefs = arrayValue(source.omitted_refs).length > 0
    ? arrayValue(source.omitted_refs)
    : arrayValue(fallback.omitted_refs);
  return {
    selected_chunk_count: boundedOpsCount(
      source.selected_chunk_count
        || fallback.selected_chunk_count
        || selectedRefs.length
    ),
    selected_chunk_ref_count: boundedOpsCount(countChunkIdentityRefs(selectedRefs)),
    omitted_ref_count: boundedOpsCount(
      source.omitted_ref_count
        || fallback.omitted_ref_count
        || omittedRefs.length
    ),
    omitted_chunk_ref_count: boundedOpsCount(countChunkIdentityRefs(omittedRefs)),
    index_source: safeString(source.index_source || fallback.index_source),
    index_granularity: safeString(source.index_granularity || fallback.index_granularity),
    chunk_identity_schema: safeString(source.chunk_identity_schema || fallback.chunk_identity_schema),
    chunk_expand_via_get_ref: source.chunk_expand_via_get_ref === true
      || fallback.chunk_expand_via_get_ref === true,
  };
}

function summarizeMemoryGatewayChunkEvidenceFromPlan(plan = {}, report = {}) {
  const prepare = plan?.prepare && typeof plan.prepare === 'object' && !Array.isArray(plan.prepare)
    ? plan.prepare
    : {};
  const memoryContext = plan?.memory_context && typeof plan.memory_context === 'object' && !Array.isArray(plan.memory_context)
    ? plan.memory_context
    : {};
  const source = {
    selected_chunk_count: report.model_call_plan_selected_chunk_count || prepare.selected_chunk_count,
    selected_refs: arrayValue(memoryContext.selected_refs).length > 0
      ? memoryContext.selected_refs
      : prepare.selected_refs,
    omitted_ref_count: report.model_call_plan_omitted_ref_count
      || memoryContext.omitted_ref_count
      || prepare.omitted_ref_count,
    omitted_refs: arrayValue(memoryContext.omitted_refs).length > 0
      ? memoryContext.omitted_refs
      : prepare.omitted_refs,
    index_source: report.model_call_plan_index_source || prepare.index_source,
    index_granularity: report.model_call_plan_index_granularity
      || memoryContext.index_granularity
      || prepare.index_granularity,
    chunk_identity_schema: report.model_call_plan_chunk_identity_schema
      || memoryContext.chunk_identity_schema
      || prepare.chunk_identity_schema,
    chunk_expand_via_get_ref: report.model_call_plan_chunk_expand_via_get_ref === true
      || memoryContext.chunk_expand_via_get_ref === true
      || prepare.chunk_expand_via_get_ref === true,
  };
  const summary = summarizeMemoryGatewayChunkEvidence(source);
  if (Number.isFinite(Number(report.model_call_plan_selected_chunk_ref_count))) {
    summary.selected_chunk_ref_count = boundedOpsCount(report.model_call_plan_selected_chunk_ref_count);
  }
  if (Number.isFinite(Number(report.model_call_plan_omitted_chunk_ref_count))) {
    summary.omitted_chunk_ref_count = boundedOpsCount(report.model_call_plan_omitted_chunk_ref_count);
  }
  return summary;
}

function memoryGatewaySampleProfile(sample) {
  return normalizedMemoryGatewayProfileId(
    firstValue([
      sample?.serving_profile_id,
      sample?.servingProfileId,
      sample?.selected_profile,
      sample?.selectedProfile,
      sample?.effective_profile,
      sample?.effectiveProfile,
    ])
  ) || 'unknown';
}

function memoryGatewayShadowSamplePasses(sample) {
  return sample?.ok === true
    && sample?.parity_ok === true
    && sample?.production_authority_change !== true
    && safeString(sample?.rust_source) === 'rust_memory_gateway_prepare';
}

function memoryGatewayShadowSampleMatchesReadinessScope(sample, report) {
  const requesterRole = safeString(report?.requester_role);
  const useMode = safeString(report?.use_mode);
  const projectId = safeString(report?.project_id);
  if (requesterRole && safeString(sample?.requester_role) !== requesterRole) return false;
  if (useMode && safeString(sample?.use_mode) !== useMode) return false;
  if (projectId && safeString(sample?.project_id) !== projectId) return false;
  return true;
}

function readMemoryGatewayJsonObject(filePath) {
  const resolved = safeString(filePath);
  if (!resolved || !fs.existsSync(resolved)) return null;
  try {
    const parsed = JSON.parse(fs.readFileSync(resolved, 'utf8'));
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function collectMemoryGatewayShadowSamples(report, reportPath) {
  const reportDir = safeString(reportPath) ? path.dirname(reportPath) : '';
  const historyCandidates = uniquePaths([
    report?.history_path,
    reportDir ? path.join(reportDir, 'memory_gateway_shadow_compare_history.json') : '',
  ]);
  for (const candidate of historyCandidates) {
    const parsed = readMemoryGatewayJsonObject(candidate);
    if (Array.isArray(parsed?.items)) {
      return {
        source: candidate,
        samples: parsed.items.filter((item) => item && typeof item === 'object' && !Array.isArray(item)),
      };
    }
  }

  const statusCandidates = uniquePaths([
    report?.status_path,
    reportDir ? path.join(reportDir, 'memory_gateway_shadow_compare_status.json') : '',
  ]);
  for (const candidate of statusCandidates) {
    const parsed = readMemoryGatewayJsonObject(candidate);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return { source: candidate, samples: [parsed] };
    }
  }
  return { source: '', samples: [] };
}

function summarizeMemoryGatewayProfileReadiness(report, reportPath) {
  const requiredSamples = Math.max(1, Number(report?.required_sample_count || 1));
  const maxAgeMs = Math.max(0, Number(report?.max_age_ms || 0));
  const nowMs = Date.now();
  const loaded = collectMemoryGatewayShadowSamples(report, reportPath);
  const samples = loaded.samples
    .filter((sample) => memoryGatewayShadowSampleMatchesReadinessScope(sample, report));
  const byProfile = new Map();
  for (const sample of samples) {
    const profile = memoryGatewaySampleProfile(sample);
    if (!byProfile.has(profile)) {
      byProfile.set(profile, {
        serving_profile_id: profile,
        total_sample_count: 0,
        fresh_sample_count: 0,
        passing_sample_count: 0,
        authority_violation_count: 0,
        fresh_authority_violation_count: 0,
        parity_failure_count: 0,
        fresh_parity_failure_count: 0,
        rust_source_mismatch_count: 0,
        fresh_rust_source_mismatch_count: 0,
        downgrade_count: 0,
        deny_count: 0,
        latest_recorded_at_ms: null,
        ready_for_require: false,
      });
    }
    const bucket = byProfile.get(profile);
    const recordedAtMs = Number(sample?.recorded_at_ms || 0);
    const selectedProfile = normalizedMemoryGatewayProfileId(sample?.selected_profile);
    const effectiveProfile = normalizedMemoryGatewayProfileId(sample?.effective_profile);
    const fresh = maxAgeMs <= 0 || (recordedAtMs > 0 && nowMs - recordedAtMs >= 0 && nowMs - recordedAtMs <= maxAgeMs);
    bucket.total_sample_count += 1;
    if (fresh) bucket.fresh_sample_count += 1;
    if (fresh && memoryGatewayShadowSamplePasses(sample)) bucket.passing_sample_count += 1;
    if (sample?.production_authority_change === true) bucket.authority_violation_count += 1;
    if (fresh && sample?.production_authority_change === true) bucket.fresh_authority_violation_count += 1;
    if (sample?.ok !== true || sample?.parity_ok !== true) bucket.parity_failure_count += 1;
    if (fresh && (sample?.ok !== true || sample?.parity_ok !== true)) bucket.fresh_parity_failure_count += 1;
    if (safeString(sample?.rust_source) && safeString(sample?.rust_source) !== 'rust_memory_gateway_prepare') {
      bucket.rust_source_mismatch_count += 1;
      if (fresh) bucket.fresh_rust_source_mismatch_count += 1;
    }
    if (selectedProfile && effectiveProfile && selectedProfile !== effectiveProfile) bucket.downgrade_count += 1;
    if (safeString(sample?.rust_deny_code)) bucket.deny_count += 1;
    if (recordedAtMs > 0 && (bucket.latest_recorded_at_ms === null || recordedAtMs > bucket.latest_recorded_at_ms)) {
      bucket.latest_recorded_at_ms = recordedAtMs;
    }
  }

  const profileReadiness = Array.from(byProfile.values()).map((bucket) => ({
    ...bucket,
    ready_for_require: bucket.passing_sample_count >= requiredSamples
      && bucket.fresh_authority_violation_count === 0
      && bucket.fresh_parity_failure_count === 0
      && bucket.fresh_rust_source_mismatch_count === 0,
  })).sort((a, b) => a.serving_profile_id.localeCompare(b.serving_profile_id));
  return {
    source: loaded.source,
    sample_count: samples.length,
    profile_downgrade_count: profileReadiness.reduce((sum, item) => sum + item.downgrade_count, 0),
    rust_deny_count: profileReadiness.reduce((sum, item) => sum + item.deny_count, 0),
    profile_readiness: profileReadiness,
  };
}

function collectMemoryGatewayCutoverReadiness(config, args = {}, statusOut = {}, launchdOut = {}) {
  const required = requireMemoryGatewayCutoverReady(args);
  const candidates = memoryGatewayCutoverReadinessCandidatePaths(config, args, statusOut, launchdOut);
  const explicitPath = safeString(args['memory-gateway-cutover-readiness-path'])
    || safeString(process.env.XHUB_RUST_MEMORY_GATEWAY_CUTOVER_READINESS_PATH);
  const out = {
    schema_version: 'xhub.rust_hub.memory_gateway_cutover_readiness_gate.v1',
    ok: true,
    required,
    enabled: false,
    report_found: false,
    report_path: '',
    candidate_paths: candidates,
    schema_ok: false,
    ready_for_require: false,
    report_ok: false,
    source: '',
    generated_at_ms: null,
    age_ms: null,
    requester_role: '',
    use_mode: '',
    serving_profile_id: '',
    selected_profile: '',
    effective_profile: '',
    project_id: '',
    required_sample_count: 0,
    max_age_ms: 0,
    total_sample_count: 0,
    matching_sample_count: 0,
    fresh_matching_sample_count: 0,
    considered_sample_count: 0,
    passing_sample_count: 0,
    stale_matching_sample_count: 0,
    authority_violation_count: 0,
    parity_failure_count: 0,
    rust_source_mismatch_count: 0,
    latest_recorded_at_ms: null,
    oldest_considered_at_ms: null,
    profile_readiness_source: '',
    profile_readiness_sample_count: 0,
    profile_downgrade_count: 0,
    rust_deny_count: 0,
    profile_readiness: [],
    model_call_plan_smoke_enabled: false,
    model_call_plan_required: false,
    model_call_plan_ready: false,
    model_call_plan_schema: '',
    model_call_plan_authority: '',
    model_call_plan_mode: '',
    model_call_plan_execution_blocked: false,
    model_call_plan_would_call_model: false,
    model_call_plan_model_call_executed: false,
    model_call_plan_context_text_included: false,
    model_call_plan_prompt_text_included: false,
    model_call_plan_omitted_reason_counts: {},
    model_call_plan_selected_chunk_count: 0,
    model_call_plan_selected_chunk_ref_count: 0,
    model_call_plan_omitted_ref_count: 0,
    model_call_plan_omitted_chunk_ref_count: 0,
    model_call_plan_index_granularity: '',
    model_call_plan_index_source: '',
    model_call_plan_chunk_identity_schema: '',
    model_call_plan_chunk_expand_via_get_ref: false,
    model_call_plan_issue_codes: [],
    model_call_plan_smoke: null,
    report_issue_codes: [],
    report_issues: [],
    blocking_issues: [],
    error: '',
  };

  const reportPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!reportPath) {
    if (required) out.blocking_issues.push('memory_gateway_cutover_readiness_missing');
    out.ok = out.blocking_issues.length === 0;
    return out;
  }

  out.enabled = true;
  out.report_found = true;
  out.report_path = reportPath;
  const loaded = readMemoryGatewayCutoverReadinessReport(reportPath);
  if (!loaded.ok) {
    out.error = loaded.error;
    if (required || explicitPath) out.blocking_issues.push('memory_gateway_cutover_readiness_invalid');
    out.ok = out.blocking_issues.length === 0;
    return out;
  }

  const report = loaded.report;
  out.schema_ok = report.schema_version === 'xt.rust_memory_gateway_cutover_readiness.v1';
  out.ready_for_require = report.ready_for_require === true;
  out.report_ok = report.ok === true;
  out.source = safeString(report.source);
  out.generated_at_ms = Number.isFinite(Number(report.generated_at_ms)) ? Number(report.generated_at_ms) : null;
  out.age_ms = out.generated_at_ms !== null ? Math.max(0, Date.now() - out.generated_at_ms) : null;
  out.requester_role = safeString(report.requester_role);
  out.use_mode = safeString(report.use_mode);
  out.serving_profile_id = normalizedMemoryGatewayProfileId(report.serving_profile_id);
  out.selected_profile = normalizedMemoryGatewayProfileId(report.selected_profile);
  out.effective_profile = normalizedMemoryGatewayProfileId(report.effective_profile);
  out.project_id = safeString(report.project_id);
  out.required_sample_count = Number(report.required_sample_count || 0);
  out.max_age_ms = Number(report.max_age_ms || 0);
  out.total_sample_count = Number(report.total_sample_count || 0);
  out.matching_sample_count = Number(report.matching_sample_count || 0);
  out.fresh_matching_sample_count = Number(report.fresh_matching_sample_count || 0);
  out.considered_sample_count = Number(report.considered_sample_count || 0);
  out.passing_sample_count = Number(report.passing_sample_count || 0);
  out.stale_matching_sample_count = Number(report.stale_matching_sample_count || 0);
  out.authority_violation_count = Number(report.authority_violation_count || 0);
  out.parity_failure_count = Number(report.parity_failure_count || 0);
  out.rust_source_mismatch_count = Number(report.rust_source_mismatch_count || 0);
  out.latest_recorded_at_ms = Number.isFinite(Number(report.latest_recorded_at_ms)) ? Number(report.latest_recorded_at_ms) : null;
  out.oldest_considered_at_ms = Number.isFinite(Number(report.oldest_considered_at_ms)) ? Number(report.oldest_considered_at_ms) : null;
  const profileSummary = summarizeMemoryGatewayProfileReadiness(report, reportPath);
  out.profile_readiness_source = profileSummary.source;
  out.profile_readiness_sample_count = profileSummary.sample_count;
  out.profile_downgrade_count = profileSummary.profile_downgrade_count;
  out.rust_deny_count = profileSummary.rust_deny_count;
  out.profile_readiness = profileSummary.profile_readiness;
  const modelCallPlanSmoke = report?.model_call_plan_smoke && typeof report.model_call_plan_smoke === 'object' && !Array.isArray(report.model_call_plan_smoke)
    ? report.model_call_plan_smoke
    : {};
  const modelCallPlan = modelCallPlanSmoke?.plan && typeof modelCallPlanSmoke.plan === 'object' && !Array.isArray(modelCallPlanSmoke.plan)
    ? modelCallPlanSmoke.plan
    : {};
  const modelCallExecuteDenial = modelCallPlanSmoke?.execute_denial && typeof modelCallPlanSmoke.execute_denial === 'object' && !Array.isArray(modelCallPlanSmoke.execute_denial)
    ? modelCallPlanSmoke.execute_denial
    : {};
  const modelCallExecutionGate = modelCallPlanSmoke?.execution_gate && typeof modelCallPlanSmoke.execution_gate === 'object' && !Array.isArray(modelCallPlanSmoke.execution_gate)
    ? modelCallPlanSmoke.execution_gate
    : {};
  const modelCallExecute = modelCallPlanSmoke?.execute && typeof modelCallPlanSmoke.execute === 'object' && !Array.isArray(modelCallPlanSmoke.execute)
    ? modelCallPlanSmoke.execute
    : {};
  const modelCallPlanIssueCodes = [
    ...(Array.isArray(report?.model_call_plan_issue_codes) ? report.model_call_plan_issue_codes : []),
    ...(Array.isArray(modelCallPlanSmoke?.issue_codes) ? modelCallPlanSmoke.issue_codes : []),
  ].map((value) => safeString(value)).filter(Boolean);
  out.model_call_plan_smoke_enabled = report.model_call_plan_smoke_enabled === true || modelCallPlanSmoke.enabled === true;
  out.model_call_plan_required = report.model_call_plan_required === true || (out.model_call_plan_smoke_enabled && modelCallPlanSmoke.skipped !== true);
  out.model_call_plan_ready = report.model_call_plan_ready === true || (out.model_call_plan_smoke_enabled && modelCallPlanSmoke.ok === true);
  out.model_call_plan_schema = safeString(report.model_call_plan_schema || modelCallPlan.schema_version);
  out.model_call_plan_authority = safeString(report.model_call_plan_authority || modelCallPlan.authority);
  out.model_call_plan_mode = safeString(report.model_call_plan_mode || modelCallPlan.mode);
  out.model_call_plan_execution_blocked = report.model_call_plan_execution_blocked === true || modelCallPlanSmoke.execution_blocked === true;
  out.model_call_plan_would_call_model = report.model_call_plan_would_call_model === true || modelCallPlan.would_call_model === true;
  out.model_call_plan_model_call_executed = report.model_call_plan_model_call_executed === true || modelCallPlan.model_call_executed === true;
  out.model_call_plan_context_text_included = report.model_call_plan_context_text_included === true || modelCallPlan.context_text_included === true;
  out.model_call_plan_prompt_text_included = report.model_call_plan_prompt_text_included === true || modelCallPlan.prompt_text_included === true;
  out.model_call_plan_omitted_reason_counts = normalizedObjectCounts(
    report.model_call_plan_omitted_reason_counts || modelCallPlan.omitted_reason_counts
  );
  const modelCallPlanChunkEvidence = summarizeMemoryGatewayChunkEvidenceFromPlan(modelCallPlan, report);
  out.model_call_plan_selected_chunk_count = modelCallPlanChunkEvidence.selected_chunk_count;
  out.model_call_plan_selected_chunk_ref_count = modelCallPlanChunkEvidence.selected_chunk_ref_count;
  out.model_call_plan_omitted_ref_count = modelCallPlanChunkEvidence.omitted_ref_count;
  out.model_call_plan_omitted_chunk_ref_count = modelCallPlanChunkEvidence.omitted_chunk_ref_count;
  out.model_call_plan_index_granularity = modelCallPlanChunkEvidence.index_granularity;
  out.model_call_plan_index_source = modelCallPlanChunkEvidence.index_source;
  out.model_call_plan_chunk_identity_schema = modelCallPlanChunkEvidence.chunk_identity_schema;
  out.model_call_plan_chunk_expand_via_get_ref = modelCallPlanChunkEvidence.chunk_expand_via_get_ref;
  out.model_call_execution_gate_ready_for_execution = report.model_call_execution_gate_ready_for_execution === true
    || modelCallPlanSmoke.execution_gate_ready_for_execution === true
    || modelCallExecutionGate.ready_for_execution === true;
  out.model_call_execution_admission_authority_in_rust = report.model_call_execution_admission_authority_in_rust === true
    || modelCallPlanSmoke.execution_admission_authority_in_rust === true
    || modelCallExecutionGate.execution_admission_authority_in_rust === true;
  out.model_call_execution_gate_status = safeString(report.model_call_execution_gate_status || modelCallExecutionGate.status);
  out.model_call_execution_gate_mode = safeString(report.model_call_execution_gate_mode || modelCallExecutionGate.mode);
  out.model_call_execution_gate_authority = safeString(report.model_call_execution_gate_authority || modelCallExecutionGate.authority);
  out.model_call_execution_gate_blocker_count = Number(report.model_call_execution_gate_blocker_count ?? (
    Array.isArray(modelCallExecutionGate.blockers) ? modelCallExecutionGate.blockers.length : 0
  ));
  out.model_call_execution_gate_would_call_model = report.model_call_execution_gate_would_call_model === true
    || modelCallExecutionGate.would_call_model === true;
  out.model_call_execution_gate_model_call_executed = report.model_call_execution_gate_model_call_executed === true
    || modelCallExecutionGate.model_call_executed === true;
  out.model_call_execution_gate_context_text_included = report.model_call_execution_gate_context_text_included === true
    || modelCallExecutionGate.context_text_included === true;
  out.model_call_execution_gate_prompt_text_included = report.model_call_execution_gate_prompt_text_included === true
    || modelCallExecutionGate.prompt_text_included === true;
  out.model_call_execution_gate_production_authority_change = modelCallExecutionGate.production_authority_change === true;
  out.model_call_execute_blocked = report.model_call_execute_blocked === true
    || modelCallPlanSmoke.execute_blocked === true
    || modelCallExecute.status === 'blocked';
  out.model_call_execute_status = safeString(report.model_call_execute_status || modelCallExecute.status);
  out.model_call_execute_mode = safeString(report.model_call_execute_mode || modelCallExecute.mode);
  out.model_call_execute_authority = safeString(report.model_call_execute_authority || modelCallExecute.authority);
  out.model_call_execute_executor = safeString(report.model_call_execute_executor || modelCallExecute.executor);
  out.model_call_execute_blocker_count = Number(report.model_call_execute_blocker_count ?? modelCallExecute.blocker_count ?? (
    Array.isArray(modelCallExecute.blockers) ? modelCallExecute.blockers.length : 0
  ));
  out.model_call_execute_would_call_model = report.model_call_execute_would_call_model === true
    || modelCallExecute.would_call_model === true;
  out.model_call_execute_model_call_invoked = report.model_call_execute_model_call_invoked === true
    || modelCallExecute.model_call_invoked === true;
  out.model_call_execute_model_call_executed = report.model_call_execute_model_call_executed === true
    || modelCallExecute.model_call_executed === true;
  out.model_call_execute_local_ml_invoked = report.model_call_execute_local_ml_invoked === true
    || modelCallExecute.local_ml_execute_http_invoked === true;
  out.model_call_execute_context_text_included = report.model_call_execute_context_text_included === true
    || modelCallExecute.context_text_included === true;
  out.model_call_execute_prompt_text_included = report.model_call_execute_prompt_text_included === true
    || modelCallExecute.prompt_text_included === true;
  out.model_call_execute_production_authority_change = modelCallExecute.production_authority_change === true;
  out.model_call_plan_issue_codes = Array.from(new Set(modelCallPlanIssueCodes)).slice(0, 12);
  out.model_call_plan_smoke = out.model_call_plan_smoke_enabled ? {
    schema_version: safeString(modelCallPlanSmoke.schema_version),
    enabled: true,
    ok: modelCallPlanSmoke.ok === true,
    endpoint: safeString(modelCallPlanSmoke.endpoint || 'POST /memory/gateway/model-call-plan'),
    execution_blocked: out.model_call_plan_execution_blocked,
    issue_codes: out.model_call_plan_issue_codes,
    plan: {
      schema_version: out.model_call_plan_schema,
      ok: modelCallPlan.ok === true,
      status: safeString(modelCallPlan.status),
      source: safeString(modelCallPlan.source),
      mode: out.model_call_plan_mode,
      authority: out.model_call_plan_authority,
      would_call_model: out.model_call_plan_would_call_model,
      model_call_executed: out.model_call_plan_model_call_executed,
      context_text_included: out.model_call_plan_context_text_included,
      prompt_text_included: out.model_call_plan_prompt_text_included,
      omitted_reason_counts: out.model_call_plan_omitted_reason_counts,
      selected_chunk_count: out.model_call_plan_selected_chunk_count,
      selected_chunk_ref_count: out.model_call_plan_selected_chunk_ref_count,
      omitted_ref_count: out.model_call_plan_omitted_ref_count,
      omitted_chunk_ref_count: out.model_call_plan_omitted_chunk_ref_count,
      index_granularity: out.model_call_plan_index_granularity,
      index_source: out.model_call_plan_index_source,
      chunk_identity_schema: out.model_call_plan_chunk_identity_schema,
      chunk_expand_via_get_ref: out.model_call_plan_chunk_expand_via_get_ref,
      local_ml_execute_http_not_invoked: modelCallPlan.local_ml_execute_http_not_invoked === true,
      provider_route_not_mutated: modelCallPlan.provider_route_not_mutated === true,
      node_not_authority: modelCallPlan.node_not_authority === true,
    },
    execute_denial: {
      schema_version: safeString(modelCallExecuteDenial.schema_version),
      error_code: safeString(modelCallExecuteDenial.error_code),
      would_call_model: modelCallExecuteDenial.would_call_model === true,
      model_call_executed: modelCallExecuteDenial.model_call_executed === true,
      production_authority_change: modelCallExecuteDenial.production_authority_change === true,
    },
    execution_gate: {
      schema_version: safeString(modelCallExecutionGate.schema_version),
      status: out.model_call_execution_gate_status,
      mode: out.model_call_execution_gate_mode,
      authority: out.model_call_execution_gate_authority,
      ready_for_execution: out.model_call_execution_gate_ready_for_execution,
      execution_admission_authority_in_rust: out.model_call_execution_admission_authority_in_rust,
      execution_admission_ready: modelCallExecutionGate.execution_admission_ready === true,
      execution_authority_in_rust: modelCallExecutionGate.execution_authority_in_rust === true,
      execution_enabled: modelCallExecutionGate.execution_enabled === true,
      would_call_model: out.model_call_execution_gate_would_call_model,
      model_call_executed: out.model_call_execution_gate_model_call_executed,
      context_text_included: out.model_call_execution_gate_context_text_included,
      prompt_text_included: out.model_call_execution_gate_prompt_text_included,
      route_specified: modelCallExecutionGate.route_specified === true,
      provider_route_authority_in_rust: modelCallExecutionGate.provider_route_authority_in_rust === true,
      model_route_authority_in_rust: modelCallExecutionGate.model_route_authority_in_rust === true,
      blocker_count: out.model_call_execution_gate_blocker_count,
    },
    execute: {
      schema_version: safeString(modelCallExecute.schema_version),
      status: out.model_call_execute_status,
      mode: out.model_call_execute_mode,
      authority: out.model_call_execute_authority,
      executor: out.model_call_execute_executor,
      blocked: out.model_call_execute_blocked,
      would_call_model: out.model_call_execute_would_call_model,
      model_call_invoked: out.model_call_execute_model_call_invoked,
      model_call_executed: out.model_call_execute_model_call_executed,
      local_ml_execute_http_invoked: out.model_call_execute_local_ml_invoked,
      context_text_included: out.model_call_execute_context_text_included,
      prompt_text_included: out.model_call_execute_prompt_text_included,
      blocker_count: out.model_call_execute_blocker_count,
    },
  } : null;
  out.report_issues = Array.isArray(report.issues)
    ? report.issues.slice(0, 12).map(compactMemoryGatewayCutoverIssue)
    : [];
  out.report_issue_codes = out.report_issues.map((issue) => issue.code).filter(Boolean);

  if (!out.schema_ok && (required || explicitPath)) {
    out.blocking_issues.push('memory_gateway_cutover_readiness_schema_mismatch');
  }
  if (out.authority_violation_count > 0 || out.report_issue_codes.includes('memory_gateway_cutover_authority_violation')) {
    out.blocking_issues.push('memory_gateway_cutover_authority_violation');
  }
  if (required && (!out.report_ok || !out.ready_for_require)) {
    out.blocking_issues.push('memory_gateway_cutover_readiness_not_ready');
  }
  if (out.model_call_plan_required && out.model_call_plan_ready !== true) {
    out.blocking_issues.push('memory_gateway_model_call_plan_smoke_failed');
  }
  if (out.model_call_plan_smoke_enabled && out.model_call_plan_execution_blocked !== true) {
    out.blocking_issues.push('memory_gateway_model_call_execute_denial_missing');
  }
  if (out.model_call_plan_would_call_model || out.model_call_plan_model_call_executed) {
    out.blocking_issues.push('memory_gateway_model_call_plan_executed_unexpectedly');
  }
  if (out.model_call_plan_context_text_included || out.model_call_plan_prompt_text_included) {
    out.blocking_issues.push('memory_gateway_model_call_plan_text_leak');
  }
  if (out.model_call_execution_gate_would_call_model || out.model_call_execution_gate_model_call_executed) {
    out.blocking_issues.push('memory_gateway_model_call_execution_gate_executed_unexpectedly');
  }
  if (out.model_call_execution_gate_context_text_included || out.model_call_execution_gate_prompt_text_included) {
    out.blocking_issues.push('memory_gateway_model_call_execution_gate_text_leak');
  }
  if (out.model_call_execution_gate_production_authority_change) {
    out.blocking_issues.push('memory_gateway_model_call_execution_gate_authority_violation');
  }
  const modelCallExecuteEvidencePresent = Boolean(
    out.model_call_execute_status
      || out.model_call_execute_mode
      || out.model_call_execute_authority
      || out.model_call_execute_executor
      || out.model_call_execute_blocker_count > 0
      || out.model_call_execute_would_call_model
      || out.model_call_execute_model_call_invoked
      || out.model_call_execute_model_call_executed
      || out.model_call_execute_local_ml_invoked
  );
  if (modelCallExecuteEvidencePresent && out.model_call_execute_blocked !== true) {
    out.blocking_issues.push('memory_gateway_model_call_execute_block_missing');
  }
  if (out.model_call_execute_would_call_model
    || out.model_call_execute_model_call_invoked
    || out.model_call_execute_model_call_executed
    || out.model_call_execute_local_ml_invoked) {
    out.blocking_issues.push('memory_gateway_model_call_execute_invoked_unexpectedly');
  }
  if (out.model_call_execute_context_text_included || out.model_call_execute_prompt_text_included) {
    out.blocking_issues.push('memory_gateway_model_call_execute_text_leak');
  }
  if (out.model_call_execute_production_authority_change) {
    out.blocking_issues.push('memory_gateway_model_call_execute_authority_violation');
  }
  out.blocking_issues = Array.from(new Set(out.blocking_issues));
  out.ok = out.blocking_issues.length === 0;
  return out;
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
    rust_product_kernel: true,
    swift_product_shell: true,
    node_compatibility_layer: true,
    node_remains_authority: false,
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
    httpMetrics = await httpGetJson(
      `${config.baseUrl}/runtime/http-metrics`,
      1000,
      readAccessKeyForProbe(config),
    );
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
  const productProcessSanity = runProductProcessSanity(config, args, reportPath, 'watchdog');
  const readiness = statusOut.readiness || launchdOut.readiness || null;
  const healthy = statusOut.running === true || launchdOut.running === true;
  const readyState = readiness?.ready === true;
  const slowBudget = httpSlowBudgetSummary(httpMetrics);
  const launchdExpected = process.platform === 'darwin' && !allowManual;

  const issues = [];
  if (requireReady && !healthy) issues.push('daemon_health_unavailable');
  if (requireReady && !readyState) issues.push('daemon_readiness_unavailable');
  if (launchdExpected && launchdOut.loaded !== true) issues.push('launchd_not_loaded');
  if (httpMetrics?.schema_version !== 'xhub.rust_hub.http_metrics.v1') issues.push('http_metrics_unavailable');
  if (slowBudget.budgetSlowRequests > maxSlowRequests) issues.push('slow_request_budget_exceeded');
  if (readiness?.capabilities?.http_io_timeouts !== true) issues.push('http_io_timeout_capability_missing');
  if (readiness?.capabilities?.http_backpressure !== true) issues.push('http_backpressure_capability_missing');
  if (uiGate.product_ui_change === true) issues.push('ui_product_change');
  if (uiGate.swift_ui_files_touched === true) issues.push('swift_ui_files_touched');
  if (uiGate.rust_browser_product_ui === true) issues.push('rust_browser_product_ui');
  if (productProcessSanity.ok !== true) issues.push('product_process_sanity_failed');
  const memorySkills = appendMemorySkillsAuthorityIssues(issues, readiness, args);
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
  if (Number(productProcessSanity.mounted_app_process_count || 0) > 0) {
    recommendedActions.push('Close or terminate stale /Volumes X-Hub processes after confirming they are not the current /Applications app.');
  }
  if (productProcessSanity.product_cpu_over_budget === true) {
    recommendedActions.push('Defer heavy gates or checkpoints until product CPU returns under budget.');
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
    slow_request_budget_scope: slowBudget.recentSlowAvailable ? 'recent_window' : 'cumulative',
    slow_requests: slowBudget.budgetSlowRequests,
    raw_slow_requests_for_budget_scope: slowBudget.rawBudgetSlowRequests,
    cumulative_slow_requests: slowBudget.cumulativeSlowRequests,
    recent_slow_requests: slowBudget.recentSlowAvailable ? slowBudget.recentSlowRequests : null,
    excluded_long_running_slow_requests: slowBudget.excludedLongRunningSlowRequests,
    excluded_long_running_slow_routes: slowBudget.excludedLongRunningSlowRoutes,
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
    product_process_sanity: productProcessSanity,
    product_process_sanity_ok: productProcessSanity.ok === true,
    stale_mounted_app_process_count: Number(productProcessSanity.mounted_app_process_count || 0),
    product_total_cpu_percent: Number(productProcessSanity.product_total_cpu_percent || 0),
    product_max_cpu_percent: Number(productProcessSanity.product_max_cpu_percent || 0),
    product_process_cpu_over_budget: productProcessSanity.product_cpu_over_budget === true,
    ui_product_change: uiGate.product_ui_change === true,
    swift_ui_files_touched: uiGate.swift_ui_files_touched === true,
    rust_browser_product_ui: uiGate.rust_browser_product_ui === true,
    rust_product_kernel: true,
    swift_product_shell: true,
    node_compatibility_layer: true,
    node_remains_authority: false,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    memory_skills_production_allowed: memorySkills.allow,
    memory_skills_production_required: memorySkills.require,
    memory_writer_authority_in_rust: memorySkills.memory_writer_authority_in_rust,
    skills_execution_authority_in_rust: memorySkills.skills_execution_authority_in_rust,
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
    httpMetrics = await httpGetJson(
      `${config.baseUrl}/runtime/http-metrics`,
      1000,
      readAccessKeyForProbe(config),
    );
  } catch (error) {
    httpMetricsError = String(error.message || error);
  }
  const logs = collectLogEvidence(config, maxLogBytes);
  const logMaintenance = collectLogMaintenance(config, maintenanceArgs, false);
  const reportMaintenance = collectReportMaintenance(config, maintenanceArgs, false, reportPath);
  const uiGate = runUiCompatibilityGate(config);
  const productProcessSanity = runProductProcessSanity(config, args, reportPath, 'ops_gate');
  const xtFileIpcRunOnceSmoke = runXtFileIpcWatcherRunOnceSmoke(config, args, reportPath);
  const xtFileIpcBackgroundWatcherSmoke = runXtFileIpcBackgroundWatcherSmoke(config, args, reportPath);
  const readiness = statusOut.readiness || launchdOut.readiness || null;
  const healthy = statusOut.running === true || launchdOut.running === true;
  const readyState = readiness?.ready === true;
  const slowBudget = httpSlowBudgetSummary(httpMetrics);
  const maintenanceNeeded = Number(logMaintenance.files_over_limit || 0) > 0
    || Number(reportMaintenance.files_planned_delete || 0) > 0;
  const memoryGatewayCutoverReadiness = collectMemoryGatewayCutoverReadiness(
    config,
    args,
    statusOut,
    launchdOut,
  );
  const memoryGatewayModelCallPlanShadow = collectMemoryGatewayModelCallPlanShadow(
    config,
    args,
    statusOut,
    launchdOut,
  );
  const memoryGatewayModelCallExecuteSmoke = collectMemoryGatewayModelCallExecuteSmoke(
    config,
    args,
    statusOut,
    launchdOut,
  );
  const memoryGatewayModelCallLocalExecutorSmoke = collectMemoryGatewayModelCallLocalExecutorSmoke(
    config,
    args,
  );
  const remoteRouteSmoke = collectCrossNetworkRemoteRouteSmoke(config, args, readiness);
  const memoryReadinessProbe = await collectMemoryReadiness(config);
  const memoryWritebackCandidateOpsRollup = compactMemoryWritebackCandidateDiagnostics(
    memoryReadinessProbe.readiness,
  );
  if (!memoryReadinessProbe.ok) {
    memoryWritebackCandidateOpsRollup.ok = false;
    memoryWritebackCandidateOpsRollup.ready = false;
    memoryWritebackCandidateOpsRollup.error_code = memoryReadinessProbe.error_code;
    memoryWritebackCandidateOpsRollup.error_message = memoryReadinessProbe.error_message;
  }
  const issues = [];
  if (requireReady && !healthy) issues.push('daemon_health_unavailable');
  if (requireReady && !readyState) issues.push('daemon_readiness_unavailable');
  if (httpMetrics?.schema_version !== 'xhub.rust_hub.http_metrics.v1') issues.push('http_metrics_unavailable');
  if (slowBudget.budgetSlowRequests > maxSlowRequests) issues.push('slow_request_budget_exceeded');
  if (uiGate.product_ui_change === true) issues.push('ui_product_change');
  if (uiGate.swift_ui_files_touched === true) issues.push('swift_ui_files_touched');
  if (uiGate.rust_browser_product_ui === true) issues.push('rust_browser_product_ui');
  if (productProcessSanity.ok !== true) issues.push('product_process_sanity_failed');
  if (xtFileIpcRunOnceSmoke.ok !== true) issues.push('xt_file_ipc_run_once_smoke_failed');
  if (xtFileIpcBackgroundWatcherSmoke.ok !== true) issues.push('xt_file_ipc_background_watcher_smoke_failed');
  issues.push(...memoryGatewayCutoverReadiness.blocking_issues);
  issues.push(...memoryGatewayModelCallPlanShadow.blocking_issues);
  issues.push(...memoryGatewayModelCallExecuteSmoke.blocking_issues);
  issues.push(...memoryGatewayModelCallLocalExecutorSmoke.blocking_issues);
  issues.push(...remoteRouteSmoke.blocking_issues);
  if (requireReady && memoryReadinessProbe.ok !== true) issues.push("memory_readiness_unavailable");
  if (memoryWritebackCandidateOpsRollup.production_authority_change === true) {
    issues.push("memory_writeback_candidate_production_authority_change");
  }
  if (memoryWritebackCandidateOpsRollup.blocking_issues.includes("memory_writeback_candidate_diagnostics_schema_mismatch")) {
    issues.push("memory_writeback_candidate_diagnostics_schema_mismatch");
  }
  const memorySkills = appendMemorySkillsAuthorityIssues(issues, readiness, args);

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
    slow_request_budget_scope: slowBudget.recentSlowAvailable ? 'recent_window' : 'cumulative',
    slow_requests: slowBudget.budgetSlowRequests,
    raw_slow_requests_for_budget_scope: slowBudget.rawBudgetSlowRequests,
    cumulative_slow_requests: slowBudget.cumulativeSlowRequests,
    recent_slow_requests: slowBudget.recentSlowAvailable ? slowBudget.recentSlowRequests : null,
    recent_sample_count: Number(httpMetrics?.recent_sample_count || 0),
    recent_sample_capacity: Number(httpMetrics?.recent_sample_capacity || 0),
    excluded_long_running_slow_requests: slowBudget.excludedLongRunningSlowRequests,
    excluded_long_running_slow_routes: slowBudget.excludedLongRunningSlowRoutes,
    slow_request_budget_ok: slowBudget.budgetSlowRequests <= maxSlowRequests,
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
    product_process_sanity: productProcessSanity,
    product_process_sanity_ok: productProcessSanity.ok === true,
    stale_mounted_app_process_count: Number(productProcessSanity.mounted_app_process_count || 0),
    product_total_cpu_percent: Number(productProcessSanity.product_total_cpu_percent || 0),
    product_max_cpu_percent: Number(productProcessSanity.product_max_cpu_percent || 0),
    product_process_cpu_over_budget: productProcessSanity.product_cpu_over_budget === true,
    xt_file_ipc_run_once_smoke: xtFileIpcRunOnceSmoke,
    xt_file_ipc_background_watcher_smoke: xtFileIpcBackgroundWatcherSmoke,
    memory_gateway_cutover_readiness: memoryGatewayCutoverReadiness,
    memory_gateway_cutover_readiness_required: memoryGatewayCutoverReadiness.required === true,
    memory_gateway_cutover_ready: memoryGatewayCutoverReadiness.ready_for_require === true,
    memory_gateway_cutover_readiness_ok: memoryGatewayCutoverReadiness.ok === true,
    memory_gateway_model_call_plan_smoke_enabled: memoryGatewayCutoverReadiness.model_call_plan_smoke_enabled === true,
    memory_gateway_model_call_plan_ready: memoryGatewayCutoverReadiness.model_call_plan_ready === true,
    memory_gateway_model_call_plan_execution_blocked: memoryGatewayCutoverReadiness.model_call_plan_execution_blocked === true,
    memory_gateway_model_call_plan_omitted_reason_counts: memoryGatewayCutoverReadiness.model_call_plan_omitted_reason_counts || {},
    memory_gateway_model_call_plan_selected_chunk_count: memoryGatewayCutoverReadiness.model_call_plan_selected_chunk_count || 0,
    memory_gateway_model_call_plan_selected_chunk_ref_count: memoryGatewayCutoverReadiness.model_call_plan_selected_chunk_ref_count || 0,
    memory_gateway_model_call_plan_omitted_ref_count: memoryGatewayCutoverReadiness.model_call_plan_omitted_ref_count || 0,
    memory_gateway_model_call_plan_omitted_chunk_ref_count: memoryGatewayCutoverReadiness.model_call_plan_omitted_chunk_ref_count || 0,
    memory_gateway_model_call_plan_index_granularity: memoryGatewayCutoverReadiness.model_call_plan_index_granularity || '',
    memory_gateway_model_call_plan_index_source: memoryGatewayCutoverReadiness.model_call_plan_index_source || '',
    memory_gateway_model_call_plan_chunk_identity_schema: memoryGatewayCutoverReadiness.model_call_plan_chunk_identity_schema || '',
    memory_gateway_model_call_plan_chunk_expand_via_get_ref: memoryGatewayCutoverReadiness.model_call_plan_chunk_expand_via_get_ref === true,
    memory_gateway_model_call_plan_shadow: memoryGatewayModelCallPlanShadow,
    memory_gateway_model_call_plan_shadow_required: memoryGatewayModelCallPlanShadow.required === true,
    memory_gateway_model_call_plan_shadow_found: memoryGatewayModelCallPlanShadow.status_found === true,
    memory_gateway_model_call_plan_shadow_ok: memoryGatewayModelCallPlanShadow.ok === true,
    memory_gateway_model_call_plan_shadow_evidence_ok: memoryGatewayModelCallPlanShadow.evidence_ok === true,
    memory_gateway_model_call_plan_shadow_execution_safe: memoryGatewayModelCallPlanShadow.execution_safe === true,
    memory_gateway_model_call_plan_shadow_text_safe: memoryGatewayModelCallPlanShadow.text_safe === true,
    memory_gateway_model_call_plan_shadow_omitted_reason_counts: memoryGatewayModelCallPlanShadow.omitted_reason_counts || {},
    memory_gateway_model_call_plan_shadow_selected_chunk_count: memoryGatewayModelCallPlanShadow.selected_chunk_count || 0,
    memory_gateway_model_call_plan_shadow_selected_chunk_ref_count: memoryGatewayModelCallPlanShadow.selected_chunk_ref_count || 0,
    memory_gateway_model_call_plan_shadow_omitted_ref_count: memoryGatewayModelCallPlanShadow.omitted_ref_count || 0,
    memory_gateway_model_call_plan_shadow_omitted_chunk_ref_count: memoryGatewayModelCallPlanShadow.omitted_chunk_ref_count || 0,
    memory_gateway_model_call_plan_shadow_index_granularity: memoryGatewayModelCallPlanShadow.index_granularity || '',
    memory_gateway_model_call_plan_shadow_index_source: memoryGatewayModelCallPlanShadow.index_source || '',
    memory_gateway_model_call_plan_shadow_chunk_identity_schema: memoryGatewayModelCallPlanShadow.chunk_identity_schema || '',
    memory_gateway_model_call_plan_shadow_chunk_expand_via_get_ref: memoryGatewayModelCallPlanShadow.chunk_expand_via_get_ref === true,
    memory_gateway_model_call_execute_smoke: memoryGatewayModelCallExecuteSmoke,
    memory_gateway_model_call_execute_smoke_required: memoryGatewayModelCallExecuteSmoke.required === true,
    memory_gateway_model_call_execute_smoke_found: memoryGatewayModelCallExecuteSmoke.status_found === true,
    memory_gateway_model_call_execute_smoke_ok: memoryGatewayModelCallExecuteSmoke.ok === true,
    memory_gateway_model_call_execute_smoke_execution_blocked: memoryGatewayModelCallExecuteSmoke.execution_blocked === true,
    memory_gateway_model_call_execute_smoke_content_free: memoryGatewayModelCallExecuteSmoke.content_free !== false,
    memory_gateway_model_call_execute_smoke_admission_ready: memoryGatewayModelCallExecuteSmoke.admission_ready === true,
    memory_gateway_model_call_execute_smoke_status: memoryGatewayModelCallExecuteSmoke.execute_status || '',
    memory_gateway_model_call_execute_smoke_mode: memoryGatewayModelCallExecuteSmoke.execute_mode || '',
    memory_gateway_model_call_execute_smoke_authority: memoryGatewayModelCallExecuteSmoke.execute_authority || '',
    memory_gateway_model_call_execute_smoke_blocker_count: Number(memoryGatewayModelCallExecuteSmoke.execute_blocker_count || 0),
    memory_gateway_model_call_local_executor_smoke: memoryGatewayModelCallLocalExecutorSmoke,
    memory_gateway_model_call_local_executor_smoke_required: memoryGatewayModelCallLocalExecutorSmoke.required === true,
    memory_gateway_model_call_local_executor_smoke_found: memoryGatewayModelCallLocalExecutorSmoke.report_found === true,
    memory_gateway_model_call_local_executor_smoke_ok: memoryGatewayModelCallLocalExecutorSmoke.ok === true,
    memory_gateway_model_call_local_executor_smoke_isolated_daemon: memoryGatewayModelCallLocalExecutorSmoke.isolated_daemon === true,
    memory_gateway_model_call_local_executor_smoke_live_daemon_touched: memoryGatewayModelCallLocalExecutorSmoke.live_daemon_touched === true,
    memory_gateway_model_call_local_executor_smoke_content_free: memoryGatewayModelCallLocalExecutorSmoke.content_free !== false,
    memory_gateway_model_call_local_executor_smoke_status: memoryGatewayModelCallLocalExecutorSmoke.execute_status || '',
    memory_gateway_model_call_local_executor_smoke_mode: memoryGatewayModelCallLocalExecutorSmoke.execute_mode || '',
    memory_gateway_model_call_local_executor_smoke_authority: memoryGatewayModelCallLocalExecutorSmoke.execute_authority || '',
    memory_gateway_model_call_local_executor_smoke_local_ml_execute_http_invoked: memoryGatewayModelCallLocalExecutorSmoke.local_ml_execute_http_invoked === true,
    memory_gateway_model_call_local_executor_smoke_recent_slow_requests: Number(memoryGatewayModelCallLocalExecutorSmoke.http_recent_slow_requests || 0),
    memory_gateway_model_call_local_executor_smoke_recent_max_elapsed_ms: Number(memoryGatewayModelCallLocalExecutorSmoke.http_recent_max_elapsed_ms || 0),
    cross_network_remote_route_smoke: remoteRouteSmoke,
    cross_network_remote_route_smoke_enabled: remoteRouteSmoke.enabled === true,
    cross_network_remote_route_smoke_required: remoteRouteSmoke.required === true,
    cross_network_remote_route_smoke_ok: remoteRouteSmoke.ok === true,
    memory_readiness_ready: memoryReadinessProbe.ok === true,
    memory_readiness_error_code: memoryReadinessProbe.error_code || "",
    memory_readiness_error_message: memoryReadinessProbe.error_message || "",
    memory_writeback_candidate_ops_rollup: memoryWritebackCandidateOpsRollup,
    memory_writeback_candidate_queue_ready: memoryWritebackCandidateOpsRollup.ready === true,
    memory_writeback_candidate_queue_pressure: memoryWritebackCandidateOpsRollup.queue_pressure,
    memory_writeback_candidate_noise_score: memoryWritebackCandidateOpsRollup.noise_score,
    memory_writeback_candidate_conflict_count: memoryWritebackCandidateOpsRollup.conflict_candidate_count,
    memory_writeback_candidate_stale_review_required_count: memoryWritebackCandidateOpsRollup.stale_review_required_count,
    memory_writeback_candidate_production_authority_change: memoryWritebackCandidateOpsRollup.production_authority_change === true,
    ui_product_change: uiGate.product_ui_change === true,
    swift_ui_files_touched: uiGate.swift_ui_files_touched === true,
    rust_browser_product_ui: uiGate.rust_browser_product_ui === true,
    rust_product_kernel: true,
    swift_product_shell: true,
    node_compatibility_layer: true,
    node_remains_authority: false,
    production_authority_change: false,
    daemon_restarted: false,
    daemon_stopped: false,
    memory_skills_production_allowed: memorySkills.allow,
    memory_skills_production_required: memorySkills.require,
    memory_writer_authority_in_rust: memorySkills.memory_writer_authority_in_rust,
    skills_execution_authority_in_rust: memorySkills.skills_execution_authority_in_rust,
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

function readAccessKeyForPairing(config) {
  if (!safeString(config.accessKeyFile)) {
    throw new Error('access_key_file_required_for_pairing');
  }
  const secret = fs.readFileSync(config.accessKeyFile, 'utf8').trim();
  if (!secret) throw new Error('access_key_file_empty_for_pairing');
  return secret;
}

function crossNetworkPairingExport(config, args = {}) {
  if (!publicBaseUrlReady(config, args)) {
    printJson({
      ok: false,
      schema_version: 'xhub.rust_hub.cross_network_pairing_export.v1',
      command: 'cross-network-pairing-export',
      error_code: 'public_base_url_not_ready',
      public_base_url: config.publicBaseUrl,
      key_printed: false,
      secret_leak: false,
    }, 2);
    return;
  }
  const accessKey = readAccessKeyForPairing(config);
  const outputDir = path.resolve(pathFromRoot(args['output-dir']) || path.join(config.rootDir, 'pairing'));
  const outputFile = path.resolve(pathFromRoot(args['output-file']) || path.join(outputDir, `xt_hub_pairing_${utcStamp()}.json`));
  const hubId = crypto
    .createHash('sha256')
    .update(`${config.publicBaseUrl}\n${config.launchdLabel}\n`)
    .digest('hex')
    .slice(0, 24);
  const endpoints = [
    {
      kind: config.publicEndpoint ? 'domain' : 'lan',
      base_url: config.publicBaseUrl,
      priority: 10,
      requires_access_key: true,
    },
  ];
  if (!isLoopbackHost(config.host) && config.baseUrl !== config.publicBaseUrl) {
    endpoints.push({
      kind: 'lan-bind',
      base_url: config.baseUrl,
      priority: 20,
      requires_access_key: true,
    });
  }
  const pairing = {
    schema_version: 'xhub.xt_hub_pairing.v1',
    generated_at_iso: new Date().toISOString(),
    hub_id: hubId,
    hub_label: safeString(args['hub-label']) || 'AX Rust Hub',
    public_base_url: config.publicBaseUrl,
    endpoints,
    auth: {
      scheme: 'bearer',
      access_key: accessKey,
    },
    reconnect_policy: {
      health_path: '/health',
      readiness_path: '/ready',
      connect_timeout_ms: 5000,
      read_timeout_ms: 30000,
      backoff_initial_ms: 500,
      backoff_max_ms: 15000,
    },
  };
  ensureDir(path.dirname(outputFile));
  fs.writeFileSync(outputFile, `${JSON.stringify(pairing, null, 2)}\n`, { mode: 0o600, flag: 'w' });
  try {
    fs.chmodSync(outputFile, 0o600);
  } catch {}
  printJson({
    ok: true,
    schema_version: 'xhub.rust_hub.cross_network_pairing_export.v1',
    command: 'cross-network-pairing-export',
    generated_at_iso: new Date().toISOString(),
    pairing_file: outputFile,
    pairing_file_mode: '0600',
    pairing_file_contains_secret: true,
    key_printed: false,
    hub_id: hubId,
    public_base_url: config.publicBaseUrl,
    endpoint_count: endpoints.length,
    production_authority_change: false,
    ui_product_change: false,
    secret_leak: false,
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
    `export XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT=${config.publicEndpoint ? '1' : '0'}`,
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
    `export XHUB_ENABLE_RUST_PROVIDER_KEY_SNAPSHOT=1`,
    `export XHUB_RUST_PROVIDER_KEY_SNAPSHOT=1`,
    `export XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP=1`,
    `export XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
    `export XHUB_RUST_PROVIDER_KEY_SNAPSHOT_FALLBACK_ON_ERROR=1`,
    `export XHUB_ENABLE_RUST_PROVIDER_QUOTA_APPLY=1`,
    `export XHUB_RUST_PROVIDER_QUOTA_APPLY=1`,
    `export XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP=1`,
    `export XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
    `export XHUB_RUST_PROVIDER_QUOTA_APPLY_FALLBACK_ON_ERROR=1`,
    `export XHUB_ENABLE_RUST_PROVIDER_QUOTA_SCHEDULER=1`,
    `export XHUB_ENABLE_RUST_PROVIDER_QUOTA_PLAN=1`,
    `export XHUB_ENABLE_RUST_PROVIDER_QUOTA_FAILURE=1`,
    `export XHUB_RUST_PROVIDER_QUOTA_PLAN=1`,
    `export XHUB_RUST_PROVIDER_QUOTA_FAILURE=1`,
    `export XHUB_RUST_MODEL_INVENTORY_BRIDGE=1`,
    `export XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL=${shellQuote(config.baseUrl)}`,
  ];
  fs.writeSync(1, `${lines.join('\n')}\n`);
}

function assertHttpSlowBudgetExcludesExpectedLongRunningRoutes() {
  const summary = httpSlowBudgetSummary({
    slow_requests: 4,
    recent_slow_requests: 3,
    recent_routes: [
      { route: '/local-ml/execute', slow_count: 2, max_elapsed_ms: 11163 },
      { route: '/ready', slow_count: 1, max_elapsed_ms: 2500 },
    ],
    routes: [
      { route: '/local-ml/execute', slow_count: 2, max_elapsed_ms: 11163 },
      { route: '/provider/openai-quota-refresh/plan', slow_count: 2, max_elapsed_ms: 2466 },
    ],
  });
  if (summary.rawBudgetSlowRequests !== 3) throw new Error('expected raw recent slow budget to remain visible');
  if (summary.excludedLongRunningSlowRequests !== 2) throw new Error('expected local ml slow requests to be excluded');
  if (summary.budgetSlowRequests !== 1) throw new Error('expected non-local-ml slow request to remain budgeted');

  const cumulativeSummary = httpSlowBudgetSummary({
    slow_requests: 5,
    routes: [
      { route: '/local-ml/run-local-task', slow_count: 2, max_elapsed_ms: 9876 },
      { route: '/runtime/local-ml/execute', slow_count: 1, max_elapsed_ms: 6789 },
      { route: '/ready', slow_count: 2, max_elapsed_ms: 2400 },
    ],
  });
  if (cumulativeSummary.recentSlowAvailable !== false) {
    throw new Error('expected cumulative budget path when recent window is unavailable');
  }
  if (cumulativeSummary.rawBudgetSlowRequests !== 5) {
    throw new Error('expected cumulative slow request count to remain visible');
  }
  if (cumulativeSummary.excludedLongRunningSlowRequests !== 3) {
    throw new Error('expected expected long-running local executor routes to be excluded');
  }
  if (cumulativeSummary.budgetSlowRequests !== 2) {
    throw new Error('expected non-local-executor cumulative slow requests to remain budgeted');
  }
}

function httpSlowBudgetSelfTest() {
  assertHttpSlowBudgetExcludesExpectedLongRunningRoutes();
  printJson({
    ok: true,
    command: 'http-slow-budget-self-test',
    schema_version: 'xhub.rust_hub.http_slow_budget_self_test.v1',
    expected_long_running_routes: Array.from(EXPECTED_LONG_RUNNING_HTTP_ROUTES).sort(),
  });
}

async function selfTest(config) {
  assertLaunchdExplicitConfigWins();
  assertLaunchdPassthroughIncludesProviderModelProduction();
  assertMemoryGatewayModelCallExecuteSmokeCollector();
  assertHttpSlowBudgetExcludesExpectedLongRunningRoutes();
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
  cross-network-pairing-export Write a 0600 XT pairing JSON bundle without printing the key
  ops-report Collect non-mutating health/readiness/launchd/http-metrics/log evidence
  maintenance Preview/apply bounded log and report retention
  ops-gate  Run daily/manual health, metrics, maintenance dry-run, and UI boundary gate
  watchdog  Run long-running daemon guard checks and optional stale-pid repair
  access-key-init Create or rotate a 0600 HTTP access key file without printing the key
  stop      Stop the pid recorded by this daemon manager
  restart   Stop then start
  env       Print Node Hub HTTP-first environment variables
  self-test Start a temporary daemon, check health, and stop it
  http-slow-budget-self-test Validate slow-budget exclusion for expected long-running local model routes

Options:
  --profile <p>    local, lan, or domain. lan binds 0.0.0.0; domain models a tunnel/public URL.
  --profile-file <p> Profile JSON path, default config/daemon_profile.<profile>.json
  --port <n>       HTTP port, default XHUB_RUST_HUB_HTTP_PORT or 50151
  --host <host>    HTTP host, default XHUB_RUST_HUB_HOST or 127.0.0.1
  --allow-lan      Permit non-loopback bind without using --profile lan
  --public-host <h> Public LAN host/IP used in public_base_url output
  --public-base-url <u> Exact public URL, e.g. https://hub.example.com
  --public-endpoint Mark the public/domain endpoint as intentionally exposed through auth gate
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
  --cross-network-remote-route-smoke For cross-network-readiness/ops-gate, run non-mutating public URL /health + auth /ready smoke as evidence
  --require-cross-network-remote-route-smoke For cross-network-readiness/ops-gate, fail unless public URL /health and authenticated /ready pass
  --cross-network-remote-route-smoke-timeout-ms <n> Timeout for public URL smoke, default 12000
  --cross-network-remote-route-smoke-public-base-url <u> Override public URL used by the smoke
  --cross-network-remote-route-smoke-access-key-file <p> Override access key file used by the smoke
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
  --max-product-cpu-percent <n> For ops-gate/watchdog, fail product process sanity when product CPU exceeds n
  --skip-product-process-sanity For ops-gate/watchdog, skip stale mounted app and product CPU process check
  --require-product-shell For ops-gate/watchdog, require X-Hub shell or X-Hub Node bridge process
  --allow-target-xhubd For ops-gate/watchdog, allow ad-hoc target/debug or target/release xhubd
  --maintenance-max-log-bytes <n> For ops-gate maintenance dry-run log budget
  --xt-file-ipc-run-once-smoke For ops-report/ops-gate, run isolated XT file IPC run-once smoke
  --xt-file-ipc-run-once-smoke-timeout-ms <n> Timeout for that isolated smoke
  --xt-file-ipc-background-watcher-smoke For ops-report/ops-gate, run isolated XT file IPC background watcher smoke
  --xt-file-ipc-background-watcher-smoke-timeout-ms <n> Timeout for that isolated smoke
  --memory-gateway-cutover-readiness-path <p> For ops-report/ops-gate, explicit memory_gateway_cutover_readiness.json
  --require-memory-gateway-cutover-ready For ops-gate, require ready_for_require=true before live require cutover
  --memory-gateway-model-call-plan-status-path <p> For ops-report/ops-gate, explicit memory_gateway_model_call_plan_status.json
  --memory-gateway-model-call-plan-history-path <p> For ops-report/ops-gate, explicit memory_gateway_model_call_plan_history.json
  --memory-gateway-model-call-plan-base-dir <p> For ops-report/ops-gate, base dir containing model-call plan shadow evidence
  --require-memory-gateway-model-call-plan-shadow For ops-gate, require XT model-call shadow preflight evidence to be present and ok
  --memory-gateway-model-call-execute-smoke-status-path <p> For ops-report/ops-gate, explicit memory_gateway_model_call_execute_smoke_status.json
  --memory-gateway-model-call-execute-smoke-history-path <p> For ops-report/ops-gate, explicit memory_gateway_model_call_execute_smoke_history.json
  --memory-gateway-model-call-execute-smoke-base-dir <p> For ops-report/ops-gate, base dir containing model-call execute smoke evidence
  --require-memory-gateway-model-call-execute-smoke For ops-gate, require model-call execute smoke evidence to be present, blocked, and content-free
  --memory-gateway-model-call-local-executor-smoke-report-path <p> For ops-report/ops-gate, explicit isolated local-executor smoke report JSON
  --memory-gateway-model-call-local-executor-smoke-base-dir <p> For ops-report/ops-gate, base dir or package root containing isolated local-executor smoke reports
  --require-memory-gateway-model-call-local-executor-smoke For ops-gate, require isolated local-executor smoke evidence to be present, executed, content-free, and zero-slow
  --allow-memory-skills-production For ops/report/watchdog gates, permit explicit Rust memory writer and skills execution authority
  --require-memory-skills-production For ops/report/watchdog gates, require both Rust memory writer and skills execution authority, default post-cutover
  --no-require-memory-skills-production For ops/report/watchdog gates, use pre-cutover boundary mode
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
    case 'cross-network-pairing-export':
      crossNetworkPairingExport(config, args);
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
    case 'http-slow-budget-self-test':
      httpSlowBudgetSelfTest();
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
