import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { URL, fileURLToPath } from 'node:url';

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));

function safeString(value) {
  return String(value ?? '').trim();
}

function parseBoolEnv(value, fallback = false) {
  if (value == null) return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (!normalized) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  return fallback;
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function nonNegativeInt(value, fallback = 0) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

function resolveRustHubRoot(env = process.env) {
  const explicit = safeString(env.XHUB_RUST_HUB_ROOT);
  if (explicit) return explicit;
  const sourceRoot = safeString(env.XHUB_SYSTEM_ROOT);
  if (sourceRoot) return path.resolve(sourceRoot, '..', 'rust', 'rust hub');
  return path.resolve(MODULE_DIR, '..', '..', '..', '..', '..', 'rust', 'rust hub');
}

export function resolveSchedulerAuthorityConfig(env = process.env) {
  const root = resolveRustHubRoot(env);
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled: parseBoolEnv(env.XHUB_RUST_SCHEDULER_AUTHORITY, false),
    requireReady: parseBoolEnv(env.XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY, true),
    fallbackOnError: parseBoolEnv(env.XHUB_RUST_SCHEDULER_AUTHORITY_FALLBACK_ON_ERROR, true),
    root,
    runnerPath: safeString(env.XHUB_RUST_HUB_RUNNER)
      || safeString(env.XHUB_RUST_SCHEDULER_BRIDGE_RUNNER)
      || path.join(root, 'tools', 'run_rust_hub.command'),
    dbPath: safeString(env.XHUB_RUST_SCHEDULER_AUTHORITY_DB_PATH),
    timeoutMs: parseIntInRange(env.XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS, 5000, 250, 300000),
    httpEnabled: parseBoolEnv(env.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP, false),
    httpBaseUrl: safeString(env.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    httpTimeoutMs: parseIntInRange(
      env.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_TIMEOUT_MS,
      750,
      100,
      60000
    ),
    httpFallbackToCli: parseBoolEnv(
      env.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_TO_CLI
        ?? env.XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_CLI,
      true
    ),
    pollIntervalMs: parseIntInRange(env.XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS, 100, 20, 5000),
    readinessCacheMs: parseIntInRange(env.XHUB_RUST_SCHEDULER_AUTHORITY_READINESS_CACHE_MS, 1000, 0, 30000),
    leaseOwner: safeString(env.XHUB_RUST_SCHEDULER_AUTHORITY_OWNER) || 'node-hub-paid-ai-authority',
    leaseDurationMs: parseIntInRange(
      env.XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS,
      300000,
      1000,
      3600000
    ),
    readiness: {
      minCompareReports: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS,
        10,
        0,
        1000000
      ),
      maxMismatches: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_AUTHORITY_MAX_MISMATCHES,
        0,
        0,
        1000000
      ),
      minLeaseShadowRuns: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS,
        1,
        0,
        1000000
      ),
      maxStaleActive: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_AUTHORITY_MAX_STALE_ACTIVE,
        0,
        0,
        1000000
      ),
      maxOrphanedLeases: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_AUTHORITY_MAX_ORPHANED_LEASES,
        0,
        0,
        1000000
      ),
      allowActiveRuns: parseBoolEnv(env.XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS, true),
    },
    verbose: parseBoolEnv(env.XHUB_RUST_SCHEDULER_AUTHORITY_VERBOSE, false),
  };
}

export function schedulerAuthorityRunId(requestId) {
  const raw = safeString(requestId);
  if (!raw) return '';
  const normalized = raw.replace(/[^a-zA-Z0-9_.:-]+/g, '_').slice(0, 170);
  return `node_paid_ai_authority_${normalized}`;
}

export function buildSchedulerAuthorityArgs(action, input = {}, config = resolveSchedulerAuthorityConfig({})) {
  const requestId = safeString(input.requestId || input.request_id);
  const runId = safeString(input.runId || input.run_id) || schedulerAuthorityRunId(requestId);
  const scopeKey = safeString(input.scopeKey || input.scope_key) || 'unknown';

  switch (action) {
    case 'cutover-readiness':
      return [
        'scheduler',
        'cutover-readiness',
        '--min-compare-reports',
        String(parseIntInRange(config.readiness?.minCompareReports, 10, 0, 1000000)),
        '--max-mismatches',
        String(parseIntInRange(config.readiness?.maxMismatches, 0, 0, 1000000)),
        '--min-lease-shadow-runs',
        String(parseIntInRange(config.readiness?.minLeaseShadowRuns, 1, 0, 1000000)),
        '--max-stale-active',
        String(parseIntInRange(config.readiness?.maxStaleActive, 0, 0, 1000000)),
        '--max-orphaned-leases',
        String(parseIntInRange(config.readiness?.maxOrphanedLeases, 0, 0, 1000000)),
        ...(config.readiness?.allowActiveRuns ? ['--allow-active-runs'] : []),
      ];
    case 'claim':
      return [
        'scheduler',
        'claim',
        '--run-id',
        runId,
        '--request-id',
        requestId,
        '--scope-key',
        scopeKey,
        '--idempotency-key',
        safeString(input.idempotencyKey || input.idempotency_key) || requestId || runId,
        '--task-type',
        safeString(input.taskType || input.task_type) || 'paid_ai',
        '--lease-owner',
        config.leaseOwner,
        '--lease-duration-ms',
        String(config.leaseDurationMs),
        '--payload-json',
        JSON.stringify(input.payload && typeof input.payload === 'object' ? input.payload : {}),
        ...optionalFlag('project-id', input.project_id),
        ...optionalFlag('device-id', input.device_id),
      ];
    case 'release':
      return [
        'scheduler',
        'release',
        '--run-id',
        runId,
        '--lease-token',
        safeString(input.leaseToken || input.lease_token),
        '--outcome',
        safeString(input.outcome) || 'completed',
      ];
    case 'cancel':
      return [
        'scheduler',
        'cancel',
        '--run-id',
        runId,
        '--reason',
        safeString(input.reason) || 'canceled',
      ];
    default:
      throw new Error(`unknown scheduler authority action: ${action}`);
  }
}

export function buildSchedulerAuthorityHttpPayload(action, input = {}, config = resolveSchedulerAuthorityConfig({})) {
  const requestId = safeString(input.requestId || input.request_id);
  const runId = safeString(input.runId || input.run_id) || schedulerAuthorityRunId(requestId);
  const scopeKey = safeString(input.scopeKey || input.scope_key) || 'unknown';

  switch (action) {
    case 'claim':
      return {
        run_id: runId,
        request_id: requestId,
        scope_key: scopeKey,
        idempotency_key: safeString(input.idempotencyKey || input.idempotency_key) || requestId || runId,
        task_type: safeString(input.taskType || input.task_type) || 'paid_ai',
        lease_owner: config.leaseOwner,
        lease_duration_ms: config.leaseDurationMs,
        payload: input.payload && typeof input.payload === 'object' ? input.payload : {},
        ...(safeString(input.project_id) ? { project_id: safeString(input.project_id) } : {}),
        ...(safeString(input.device_id) ? { device_id: safeString(input.device_id) } : {}),
      };
    case 'release':
      return {
        run_id: runId,
        lease_token: safeString(input.leaseToken || input.lease_token),
        outcome: safeString(input.outcome) || 'completed',
      };
    case 'cancel':
      return {
        run_id: runId,
        reason: safeString(input.reason) || 'canceled',
      };
    default:
      throw new Error(`unknown scheduler authority HTTP action: ${action}`);
  }
}

function optionalFlag(name, value) {
  const cleaned = safeString(value);
  return cleaned ? [`--${name}`, cleaned] : [];
}

function parseRunnerJson(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const jsonLine = [...lines].reverse().find((line) => line.startsWith('{'));
  if (!jsonLine) {
    throw new Error('rust_scheduler_authority_empty_stdout');
  }
  const parsed = JSON.parse(jsonLine);
  if (!parsed || parsed.ok !== true) {
    throw new Error(`rust_scheduler_authority_not_ok:${jsonLine.slice(0, 200)}`);
  }
  return parsed;
}

async function httpGetJson(url, timeoutMs) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_scheduler_authority_http_unsupported_protocol:${parsedUrl.protocol}`);
  }
  const client = parsedUrl.protocol === 'https:' ? https : http;
  const stdout = await new Promise((resolve, reject) => {
    const req = client.get(parsedUrl, {
      timeout: timeoutMs,
      headers: { accept: 'application/json' },
    }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
        if (body.length > 1024 * 1024) {
          req.destroy(new Error('rust_scheduler_authority_http_response_too_large'));
        }
      });
      res.on('end', () => {
        const statusCode = Number(res.statusCode || 0);
        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`rust_scheduler_authority_http_status:${statusCode}:${body.slice(0, 240)}`));
          return;
        }
        resolve(body);
      });
    });
    req.on('timeout', () => req.destroy(new Error('rust_scheduler_authority_http_timeout')));
    req.on('error', reject);
  });
  return parseRunnerJson(stdout);
}

async function httpPostJson(url, payload, timeoutMs) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_scheduler_authority_http_unsupported_protocol:${parsedUrl.protocol}`);
  }
  const body = JSON.stringify(payload || {});
  const client = parsedUrl.protocol === 'https:' ? https : http;
  const stdout = await new Promise((resolve, reject) => {
    const req = client.request(parsedUrl, {
      method: 'POST',
      timeout: timeoutMs,
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(body),
      },
    }, (res) => {
      let responseBody = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        responseBody += chunk;
        if (responseBody.length > 1024 * 1024) {
          req.destroy(new Error('rust_scheduler_authority_http_response_too_large'));
        }
      });
      res.on('end', () => {
        const statusCode = Number(res.statusCode || 0);
        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`rust_scheduler_authority_http_status:${statusCode}:${responseBody.slice(0, 240)}`));
          return;
        }
        resolve(responseBody);
      });
    });
    req.on('timeout', () => req.destroy(new Error('rust_scheduler_authority_http_timeout')));
    req.on('error', reject);
    req.write(body);
    req.end();
  });
  return parseRunnerJson(stdout);
}

export function createSchedulerAuthorityBridge({
  env = process.env,
  execFileImpl = execFile,
  httpGetJsonImpl = httpGetJson,
  httpPostJsonImpl = httpPostJson,
  existsSync = fs.existsSync,
  setTimeoutImpl = setTimeout,
  clearTimeoutImpl = clearTimeout,
  nowMsImpl = Date.now,
  logger = console,
} = {}) {
  const config = resolveSchedulerAuthorityConfig(env);
  const runs = new Map();
  const warned = new Set();
  let readinessCache = null;

  function warnOnce(key, line) {
    if (warned.has(key)) return;
    warned.add(key);
    logger.warn?.(line);
  }

  function canRun() {
    if (!config.enabled) {
      return {
        ok: true,
        used: false,
        fallback: true,
        error_code: 'rust_scheduler_authority_disabled',
      };
    }
    if (!existsSync(config.runnerPath) && !config.httpEnabled) {
      warnOnce(
        'missing_runner',
        `[hub_grpc] rust scheduler authority disabled: missing runner=${config.runnerPath}`
      );
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_scheduler_authority_runner_missing',
      };
    }
    return null;
  }

  function readinessHttpUrl() {
    const url = new URL('/scheduler/cutover-readiness', config.httpBaseUrl);
    url.searchParams.set(
      'min_compare_reports',
      String(parseIntInRange(config.readiness?.minCompareReports, 10, 0, 1000000))
    );
    url.searchParams.set(
      'max_mismatches',
      String(parseIntInRange(config.readiness?.maxMismatches, 0, 0, 1000000))
    );
    url.searchParams.set(
      'min_lease_shadow_runs',
      String(parseIntInRange(config.readiness?.minLeaseShadowRuns, 1, 0, 1000000))
    );
    url.searchParams.set(
      'max_stale_active',
      String(parseIntInRange(config.readiness?.maxStaleActive, 0, 0, 1000000))
    );
    url.searchParams.set(
      'max_orphaned_leases',
      String(parseIntInRange(config.readiness?.maxOrphanedLeases, 0, 0, 1000000))
    );
    if (config.readiness?.allowActiveRuns) {
      url.searchParams.set('allow_active_runs', '1');
    }
    return url;
  }

  function schedulerCommandHttpUrl(action) {
    const pathByAction = {
      claim: '/scheduler/claim',
      release: '/scheduler/release',
      cancel: '/scheduler/cancel',
    };
    return new URL(pathByAction[action] || `/scheduler/${action}`, config.httpBaseUrl);
  }

  function stateFor(input = {}) {
    const requestId = safeString(input.requestId || input.request_id);
    if (!requestId) return null;
    const existing = runs.get(requestId);
    if (existing) return existing;
    const created = {
      requestId,
      runId: schedulerAuthorityRunId(requestId),
      leaseToken: '',
      done: false,
    };
    runs.set(requestId, created);
    return created;
  }

  async function execCliJson(args) {
    const childEnv = config.dbPath
      ? { ...process.env, HUB_DB_PATH: config.dbPath }
      : process.env;
    const stdout = await new Promise((resolve, reject) => {
      execFileImpl(config.runnerPath, args, {
        encoding: 'utf8',
        timeout: config.timeoutMs,
        maxBuffer: 1024 * 1024,
        env: childEnv,
      }, (error, out, stderr) => {
        if (error) {
          error.stderr = stderr;
          reject(error);
          return;
        }
        resolve(String(out || ''));
      });
    });
    return parseRunnerJson(stdout);
  }

  async function execJson(action, input = {}) {
    if (config.httpEnabled) {
      try {
        if (action === 'cutover-readiness') {
          const out = await httpGetJsonImpl(readinessHttpUrl(), config.httpTimeoutMs);
          if (config.verbose) {
            logger.log?.('[hub_grpc] rust scheduler authority HTTP readiness ok');
          }
          return out;
        }
        const out = await httpPostJsonImpl(
          schedulerCommandHttpUrl(action),
          buildSchedulerAuthorityHttpPayload(action, input, config),
          config.httpTimeoutMs
        );
        if (config.verbose) {
          logger.log?.(`[hub_grpc] rust scheduler authority HTTP ${action} ok`);
        }
        return out;
      } catch (error) {
        warnOnce(
          `http_${action}_failed`,
          `[hub_grpc] rust scheduler authority HTTP ${action} failed; ${config.httpFallbackToCli ? 'falling back to CLI' : 'CLI fallback disabled'}: ${error.message || error}`
        );
        if (!config.httpFallbackToCli) {
          throw error;
        }
        if (!existsSync(config.runnerPath)) {
          throw new Error('rust_scheduler_authority_cli_fallback_runner_missing');
        }
      }
    }
    return execCliJson(buildSchedulerAuthorityArgs(action, input, config));
  }

  async function checkReadiness() {
    if (!config.requireReady) {
      return { ok: true, ready: true, skipped: true };
    }
    const now = Number(nowMsImpl());
    if (
      config.readinessCacheMs > 0
      && readinessCache
      && now - readinessCache.checkedAtMs <= config.readinessCacheMs
    ) {
      return readinessCache.result;
    }

    try {
      const out = await execJson('cutover-readiness', {});
      const result = {
        ok: true,
        ready: out.ready === true,
        raw: out,
        error_code: out.ready === true ? '' : 'rust_scheduler_authority_not_ready',
      };
      readinessCache = { checkedAtMs: now, result };
      return result;
    } catch (error) {
      const result = {
        ok: false,
        ready: false,
        fallback: true,
        error_code: 'rust_scheduler_authority_readiness_failed',
        error_message: String(error.message || error),
      };
      readinessCache = { checkedAtMs: now, result };
      warnOnce(
        'readiness_failed',
        `[hub_grpc] rust scheduler authority readiness failed: ${error.message || error}`
      );
      return result;
    }
  }

  async function claimOnce(input = {}) {
    const blocked = canRun();
    if (blocked) return blocked;

    const readiness = await checkReadiness();
    if (readiness.ready !== true) {
      return {
        ok: readiness.ok === true,
        used: false,
        fallback: true,
        error_code: readiness.error_code || 'rust_scheduler_authority_not_ready',
        readiness: readiness.raw || null,
      };
    }

    const state = stateFor(input);
    if (!state) {
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_scheduler_authority_missing_request_id',
      };
    }

    try {
      const out = await execJson('claim', {
        ...input,
        requestId: state.requestId,
        runId: state.runId,
      });
      state.runId = safeString(out.run_id || out?.run?.run_id) || state.runId;
      if (out.leased === true) {
        state.leaseToken = safeString(out.lease_token);
      }
      return {
        ok: true,
        used: true,
        fallback: false,
        leased: out.leased === true,
        inserted: out.inserted === true,
        runId: state.runId,
        leaseToken: state.leaseToken,
        queuedMs: nonNegativeInt(out.queued_ms, 0),
        raw: out,
      };
    } catch (error) {
      warnOnce(
        'claim_failed',
        `[hub_grpc] rust scheduler authority claim failed: ${error.message || error}`
      );
      if (!config.fallbackOnError) {
        throw error;
      }
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_scheduler_authority_claim_failed',
        error_message: String(error.message || error),
      };
    }
  }

  async function release(input = {}) {
    const state = stateFor(input);
    if (!state || state.done || !state.leaseToken) return false;
    await execJson('release', {
      ...input,
      requestId: state.requestId,
      runId: state.runId,
      leaseToken: state.leaseToken,
    });
    state.done = true;
    runs.delete(state.requestId);
    return true;
  }

  async function cancel(input = {}) {
    const state = stateFor(input);
    if (!state || state.done) return false;
    await execJson('cancel', {
      ...input,
      requestId: state.requestId,
      runId: state.runId,
    });
    state.done = true;
    runs.delete(state.requestId);
    return true;
  }

  function delay(ms) {
    return new Promise((resolve) => {
      const timer = setTimeoutImpl(resolve, ms);
      if (timer && typeof timer.unref === 'function') timer.unref();
    });
  }

  async function acquireSlot({
    waitMs = 20000,
    shouldAbort,
    onQueued,
    ...input
  } = {}) {
    const timeoutMs = parseIntInRange(waitMs, 20000, 1000, 300000);
    const startedAtMs = Number(nowMsImpl());
    const shouldStop = typeof shouldAbort === 'function' ? shouldAbort : () => false;
    let queued = false;

    while (true) {
      if (shouldStop()) {
        await cancel({ ...input, reason: 'canceled' }).catch(() => false);
        throw new Error('canceled');
      }

      const claimed = await claimOnce(input);
      if (claimed.fallback === true || claimed.used !== true) {
        return claimed;
      }
      if (claimed.leased === true) {
        const requestId = safeString(input.requestId || input.request_id);
        return {
          ok: true,
          used: true,
          fallback: false,
          runId: claimed.runId,
          leaseToken: claimed.leaseToken,
          queuedMs: Math.max(0, Number(nowMsImpl()) - startedAtMs),
          release: () => {
            release({ requestId }).catch((error) => {
              warnOnce(
                'release_failed',
                `[hub_grpc] rust scheduler authority release failed: ${error.message || error}`
              );
            });
          },
        };
      }

      if (!queued) {
        queued = true;
        try {
          onQueued?.({
            depth: 0,
            wait_timeout_ms: timeoutMs,
            authority: 'rust',
          });
        } catch {
          // ignore callback errors
        }
      }

      const elapsedMs = Math.max(0, Number(nowMsImpl()) - startedAtMs);
      if (elapsedMs >= timeoutMs) {
        await cancel({ ...input, reason: 'hub_ai_queue_timeout' }).catch(() => false);
        throw new Error('hub_ai_queue_timeout');
      }
      await delay(Math.min(config.pollIntervalMs, Math.max(1, timeoutMs - elapsedMs)));
    }
  }

  return {
    config,
    claimOnce,
    acquireSlot,
    release,
    cancel,
    _state: runs,
    _clearPollTimer: clearTimeoutImpl,
  };
}
