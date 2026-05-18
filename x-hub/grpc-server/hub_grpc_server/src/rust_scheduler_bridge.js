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
  if (sourceRoot) {
    return path.resolve(sourceRoot, '..', 'rust', 'rust hub');
  }
  return path.resolve(MODULE_DIR, '..', '..', '..', '..', '..', 'rust', 'rust hub');
}

export function resolveSchedulerStatusBridgeConfig(env = process.env) {
  const enabled = parseBoolEnv(env.XHUB_RUST_SCHEDULER_STATUS_READ, false);
  const root = resolveRustHubRoot(env);
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled,
    requireReady: parseBoolEnv(env.XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY, false),
    root,
    runnerPath: safeString(env.XHUB_RUST_HUB_RUNNER)
      || safeString(env.XHUB_RUST_SCHEDULER_BRIDGE_RUNNER)
      || path.join(root, 'tools', 'run_rust_hub.command'),
    timeoutMs: parseIntInRange(env.XHUB_RUST_SCHEDULER_STATUS_TIMEOUT_MS, 5000, 100, 10000),
    httpEnabled: parseBoolEnv(env.XHUB_RUST_SCHEDULER_STATUS_HTTP, false),
    httpBaseUrl: safeString(env.XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    httpTimeoutMs: parseIntInRange(
      env.XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS,
      750,
      100,
      60000
    ),
    httpFallbackToCli: parseBoolEnv(
      env.XHUB_RUST_SCHEDULER_STATUS_HTTP_FALLBACK_TO_CLI
        ?? env.XHUB_RUST_SCHEDULER_STATUS_HTTP_FALLBACK_CLI,
      true
    ),
    cacheTtlMs: parseIntInRange(env.XHUB_RUST_SCHEDULER_STATUS_CACHE_MS, 250, 0, 5000),
    verbose: parseBoolEnv(env.XHUB_RUST_SCHEDULER_STATUS_VERBOSE, false),
    readiness: {
      minCompareReports: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_STATUS_MIN_COMPARE_REPORTS,
        10,
        0,
        1000000
      ),
      maxMismatches: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_STATUS_MAX_MISMATCHES,
        0,
        0,
        1000000
      ),
      minLeaseShadowRuns: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_STATUS_MIN_LEASE_SHADOW_RUNS,
        1,
        0,
        1000000
      ),
      maxStaleActive: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_STATUS_MAX_STALE_ACTIVE,
        0,
        0,
        1000000
      ),
      maxOrphanedLeases: parseIntInRange(
        env.XHUB_RUST_SCHEDULER_STATUS_MAX_ORPHANED_LEASES,
        0,
        0,
        1000000
      ),
    },
  };
}

export function buildSchedulerStatusArgs({
  includeQueueItems = true,
  queueItemsLimit = 100,
} = {}) {
  const args = [
    'scheduler',
    'status',
    '--queue-items-limit',
    String(parseIntInRange(queueItemsLimit, 100, 1, 500)),
  ];
  if (includeQueueItems !== false) args.push('--include-queue-items');
  return args;
}

export function buildSchedulerCutoverReadinessArgs({
  minCompareReports = 10,
  maxMismatches = 0,
  minLeaseShadowRuns = 1,
  maxStaleActive = 0,
  maxOrphanedLeases = 0,
} = {}) {
  return [
    'scheduler',
    'cutover-readiness',
    '--min-compare-reports',
    String(parseIntInRange(minCompareReports, 10, 0, 1000000)),
    '--max-mismatches',
    String(parseIntInRange(maxMismatches, 0, 0, 1000000)),
    '--min-lease-shadow-runs',
    String(parseIntInRange(minLeaseShadowRuns, 1, 0, 1000000)),
    '--max-stale-active',
    String(parseIntInRange(maxStaleActive, 0, 0, 1000000)),
    '--max-orphaned-leases',
    String(parseIntInRange(maxOrphanedLeases, 0, 0, 1000000)),
  ];
}

function parseRunnerJson(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const jsonLine = [...lines].reverse().find((line) => line.startsWith('{'));
  if (!jsonLine) {
    throw new Error('rust_scheduler_bridge_empty_stdout');
  }
  return JSON.parse(jsonLine);
}

async function httpGetJson(url, timeoutMs) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_scheduler_status_http_unsupported_protocol:${parsedUrl.protocol}`);
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
          req.destroy(new Error('rust_scheduler_status_http_response_too_large'));
        }
      });
      res.on('end', () => {
        const statusCode = Number(res.statusCode || 0);
        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`rust_scheduler_status_http_status:${statusCode}:${body.slice(0, 240)}`));
          return;
        }
        resolve(body);
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('rust_scheduler_status_http_timeout'));
    });
    req.on('error', reject);
  });
  return parseRunnerJson(stdout);
}

export function normalizeRustSchedulerStatus(raw, {
  includeQueueItems = true,
  queueItemsLimit = 100,
  fallback = {},
} = {}) {
  const queueItems = Array.isArray(raw?.queue_items) ? raw.queue_items : [];
  const wantedQueueLimit = parseIntInRange(queueItemsLimit, 100, 1, 500);

  return {
    updated_at_ms: nonNegativeInt(raw?.updated_at_ms, nonNegativeInt(fallback.updated_at_ms, Date.now())),
    global_concurrency: nonNegativeInt(fallback.global_concurrency, 0),
    per_project_concurrency: nonNegativeInt(fallback.per_project_concurrency, 0),
    queue_limit: nonNegativeInt(fallback.queue_limit, 0),
    queue_timeout_ms: nonNegativeInt(fallback.queue_timeout_ms, 0),
    in_flight_total: nonNegativeInt(raw?.in_flight_total, 0),
    queue_depth: nonNegativeInt(raw?.queue_depth, 0),
    oldest_queued_ms: nonNegativeInt(raw?.oldest_queued_ms, 0),
    in_flight_by_scope: normalizeScopeCounts(raw?.in_flight_by_scope, 'in_flight'),
    queued_by_scope: normalizeScopeCounts(raw?.queued_by_scope, 'queued'),
    queue_items: includeQueueItems === false
      ? []
      : queueItems.slice(0, wantedQueueLimit).map((item) => ({
        request_id: safeString(item?.request_id),
        scope_key: safeString(item?.scope_key) || 'unknown',
        enqueued_at_ms: nonNegativeInt(item?.enqueued_at_ms, 0),
        queued_ms: nonNegativeInt(item?.queued_ms, 0),
      })),
  };
}

function normalizeScopeCounts(rows, countField) {
  if (!Array.isArray(rows)) return [];
  return rows
    .map((row) => ({
      scope_key: safeString(row?.scope_key) || 'unknown',
      [countField]: nonNegativeInt(row?.[countField] ?? row?.count, 0),
    }))
    .filter((row) => row.scope_key)
    .sort((left, right) => {
      const leftCount = Number(left[countField] || 0);
      const rightCount = Number(right[countField] || 0);
      return rightCount - leftCount || left.scope_key.localeCompare(right.scope_key);
    });
}

export function createSchedulerStatusBridge({
  env = process.env,
  execFileImpl = execFile,
  execFileSyncImpl = null,
  httpGetJsonImpl = httpGetJson,
  existsSync = fs.existsSync,
  nowMsImpl = Date.now,
  logger = console,
} = {}) {
  const config = resolveSchedulerStatusBridgeConfig(env);
  const warned = new Set();
  let cachedRead = null;
  let inFlightRead = null;

  function warnOnce(key, line) {
    if (warned.has(key)) return;
    warned.add(key);
    logger.warn?.(line);
  }

  function buildStatusHttpUrl({ includeQueueItems = true, queueItemsLimit = 100 } = {}) {
    const url = new URL('/scheduler/status', config.httpBaseUrl);
    url.searchParams.set('include_queue_items', includeQueueItems === false ? '0' : '1');
    url.searchParams.set('queue_items_limit', String(parseIntInRange(queueItemsLimit, 100, 1, 500)));
    return url;
  }

  function buildReadinessHttpUrl() {
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
    return url;
  }

  async function execRunner(args) {
    if (typeof execFileSyncImpl === 'function') {
      return String(execFileSyncImpl(config.runnerPath, args, {
        encoding: 'utf8',
        timeout: config.timeoutMs,
        stdio: ['ignore', 'pipe', 'pipe'],
      }) || '');
    }

    return await new Promise((resolve, reject) => {
      execFileImpl(config.runnerPath, args, {
        encoding: 'utf8',
        timeout: config.timeoutMs,
        maxBuffer: 1024 * 1024,
      }, (error, stdout, stderr) => {
        if (error) {
          error.stderr = stderr;
          reject(error);
          return;
        }
        resolve(String(stdout || ''));
      });
    });
  }

  async function execRunnerJson(args) {
    return parseRunnerJson(await execRunner(args));
  }

  async function readHttpJson(url, action) {
    const out = await httpGetJsonImpl(url, config.httpTimeoutMs);
    if (!out || out.ok !== true) {
      throw new Error(`rust_scheduler_${action}_not_ok`);
    }
    if (config.verbose) {
      logger.log?.(`[hub_grpc] rust scheduler status bridge HTTP ${action} ok url=${url.origin}${url.pathname}`);
    }
    return out;
  }

  async function readJsonWithFallback({ action, args, url }) {
    if (config.httpEnabled) {
      try {
        return await readHttpJson(url, action);
      } catch (error) {
        warnOnce(
          `http_${action}_failed`,
          `[hub_grpc] rust scheduler status bridge HTTP ${action} failed; ${config.httpFallbackToCli ? 'falling back to CLI' : 'CLI fallback disabled'}: ${error.message || error}`
        );
        if (!config.httpFallbackToCli) {
          throw error;
        }
        if (!existsSync(config.runnerPath)) {
          throw new Error('rust_scheduler_status_cli_fallback_runner_missing');
        }
      }
    }
    const out = await execRunnerJson(args);
    if (!out || out.ok !== true) {
      throw new Error(`rust_scheduler_${action}_not_ok`);
    }
    return out;
  }

  function cacheKeyFor({ includeQueueItems = true, queueItemsLimit = 100 } = {}) {
    return JSON.stringify({
      includeQueueItems: includeQueueItems !== false,
      queueItemsLimit: parseIntInRange(queueItemsLimit, 100, 1, 500),
    });
  }

  function materializePayload(payload, {
    includeQueueItems = true,
    queueItemsLimit = 100,
    fallback = {},
    cacheHit = false,
  } = {}) {
    if (!payload || payload.ok !== true || payload.used !== true) {
      return {
        ...(payload || {
          ok: false,
          used: false,
          error_code: 'rust_scheduler_status_read_failed',
        }),
        paid_ai: fallback,
        cache_hit: cacheHit,
      };
    }

    const paid_ai = normalizeRustSchedulerStatus(payload.raw, {
      includeQueueItems,
      queueItemsLimit,
      fallback,
    });
    if (config.verbose && !cacheHit) {
      logger.log?.(`[hub_grpc] rust scheduler status bridge read ok queue_depth=${paid_ai.queue_depth}`);
    }
    return {
      ok: true,
      used: true,
      paid_ai,
      raw: payload.raw,
      readiness: payload.readiness || null,
      cache_hit: cacheHit,
    };
  }

  async function readRustPayload({ includeQueueItems = true, queueItemsLimit = 100 } = {}) {
    let readiness = null;
    if (config.requireReady) {
      const readinessArgs = buildSchedulerCutoverReadinessArgs(config.readiness);
      try {
        readiness = await readJsonWithFallback({
          action: 'cutover_readiness',
          args: readinessArgs,
          url: buildReadinessHttpUrl(),
        });
      } catch (error) {
        warnOnce(
          'readiness_failed',
          `[hub_grpc] rust scheduler status bridge fallback: cutover readiness check failed: ${error.message || error}`
        );
        return {
          ok: false,
          used: false,
          error_code: 'rust_scheduler_cutover_readiness_failed',
          error_message: String(error.message || error),
        };
      }

      if (readiness.ready !== true) {
        const decision = safeString(readiness.decision) || 'not_ready';
        warnOnce(
          'cutover_not_ready',
          `[hub_grpc] rust scheduler status bridge fallback: cutover readiness not ready decision=${decision}`
        );
        return {
          ok: false,
          used: false,
          error_code: 'rust_scheduler_cutover_not_ready',
          readiness,
        };
      }
    }

    const args = buildSchedulerStatusArgs({ includeQueueItems, queueItemsLimit });
    try {
      const raw = await readJsonWithFallback({
        action: 'status',
        args,
        url: buildStatusHttpUrl({ includeQueueItems, queueItemsLimit }),
      });
      return { ok: true, used: true, raw, readiness };
    } catch (error) {
      warnOnce(
        'read_failed',
        `[hub_grpc] rust scheduler status bridge fallback: ${error.message || error}`
      );
      return {
        ok: false,
        used: false,
        error_code: 'rust_scheduler_status_read_failed',
        error_message: String(error.message || error),
      };
    }
  }

  async function maybeReadStatus({
    includeQueueItems = true,
    queueItemsLimit = 100,
    fallback = {},
  } = {}) {
    if (!config.enabled) {
      return { ok: true, used: false, paid_ai: fallback };
    }
    if (!existsSync(config.runnerPath) && !config.httpEnabled) {
      warnOnce(
        'missing_runner',
        `[hub_grpc] rust scheduler status bridge disabled: missing runner=${config.runnerPath}`
      );
      return {
        ok: false,
        used: false,
        error_code: 'rust_scheduler_runner_missing',
        paid_ai: fallback,
      };
    }

    const key = cacheKeyFor({ includeQueueItems, queueItemsLimit });
    const now = Number(nowMsImpl());
    if (
      config.cacheTtlMs > 0
      && cachedRead
      && cachedRead.key === key
      && now - cachedRead.cachedAtMs <= config.cacheTtlMs
    ) {
      return materializePayload(cachedRead.payload, {
        includeQueueItems,
        queueItemsLimit,
        fallback,
        cacheHit: true,
      });
    }

    if (inFlightRead && inFlightRead.key === key) {
      const payload = await inFlightRead.promise;
      return materializePayload(payload, {
        includeQueueItems,
        queueItemsLimit,
        fallback,
        cacheHit: false,
      });
    }

    const promise = readRustPayload({ includeQueueItems, queueItemsLimit });
    inFlightRead = { key, promise };
    const payload = await promise.finally(() => {
      if (inFlightRead?.promise === promise) inFlightRead = null;
    });
    if (
      config.cacheTtlMs > 0
      && (payload.ok === true || payload.error_code === 'rust_scheduler_cutover_not_ready')
    ) {
      cachedRead = {
        key,
        cachedAtMs: Number(nowMsImpl()),
        payload,
      };
    }
    return materializePayload(payload, {
      includeQueueItems,
      queueItemsLimit,
      fallback,
      cacheHit: false,
    });
  }

  return {
    config,
    maybeReadStatus,
  };
}
