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

export function resolveProviderRouteAuthorityConfig(env = process.env) {
  const root = resolveRustHubRoot(env);
  const observeEnabled = parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE, false);
  const prepEnabled = parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP, false);
  const candidateEnabled = parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE, false);
  const productionAuthority = parseBoolEnv(
    env.XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY
      ?? env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION
      ?? env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER
      ?? env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY,
    false
  );
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled: prepEnabled || observeEnabled || candidateEnabled || productionAuthority,
    prepEnabled,
    observeEnabled,
    candidateEnabled,
    productionAuthority,
    requireReady: parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY, true),
    requireNodeMatch: parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH, true),
    fallbackOnError: parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_FALLBACK_ON_ERROR, true),
    root,
    runnerPath: safeString(env.XHUB_RUST_HUB_RUNNER)
      || safeString(env.XHUB_RUST_PROVIDER_ROUTE_RUNNER)
      || path.join(root, 'tools', 'run_rust_hub.command'),
    timeoutMs: parseIntInRange(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_TIMEOUT_MS, 5000, 500, 60000),
    httpEnabled: parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP, false),
    httpBaseUrl: safeString(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    httpTimeoutMs: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS,
      750,
      100,
      60000
    ),
    httpFallbackToCli: parseBoolEnv(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI
        ?? env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_CLI,
      true
    ),
    prepThrottleMs: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS,
      1000,
      0,
      60000
    ),
    prepMaxInFlight: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT,
      2,
      1,
      16
    ),
    observeThrottleMs: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_THROTTLE_MS,
      1000,
      0,
      60000
    ),
    observeMaxInFlight: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_MAX_IN_FLIGHT,
      2,
      1,
      16
    ),
    candidateCacheMs: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS,
      250,
      0,
      60000
    ),
    candidateCacheMaxEntries: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES,
      128,
      1,
      10000
    ),
    readinessCacheMs: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_READINESS_CACHE_MS,
      1000,
      0,
      60000
    ),
    readiness: {
      minCompareReports: parseIntInRange(
        env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS,
        10,
        0,
        1000000
      ),
      maxMismatches: parseIntInRange(
        env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES,
        0,
        0,
        1000000
      ),
      reportLimit: parseIntInRange(
        env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REPORT_LIMIT,
        20,
        1,
        500
      ),
    },
    verbose: parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_VERBOSE, false),
  };
}

export function buildProviderRouteAuthorityArgs(action, input = {}, config = resolveProviderRouteAuthorityConfig({})) {
  switch (action) {
    case 'readiness':
      return [
        'provider',
        'readiness',
        '--min-compare-reports',
        String(parseIntInRange(config.readiness?.minCompareReports, 10, 0, 1000000)),
        '--max-mismatches',
        String(parseIntInRange(config.readiness?.maxMismatches, 0, 0, 1000000)),
        '--limit',
        String(parseIntInRange(config.readiness?.reportLimit, 20, 1, 500)),
      ];
    case 'route': {
      const modelId = safeString(input.modelId || input.model_id);
      const provider = safeString(input.provider || input.providerOverride || input.provider_override);
      const runtimeBaseDir = safeString(input.runtimeBaseDir || input.runtime_base_dir);
      const nowMs = nonNegativeInt(input.nowMs || input.now_ms, 0);
      const args = ['provider', 'route', '--model-id', modelId];
      if (provider) args.push('--provider', provider);
      if (runtimeBaseDir) args.push('--runtime-base-dir', runtimeBaseDir);
      if (nowMs > 0) args.push('--now-ms', String(nowMs));
      return args;
    }
    default:
      throw new Error(`unknown provider route authority action: ${action}`);
  }
}

function parseRunnerJson(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const jsonLine = [...lines].reverse().find((line) => line.startsWith('{'));
  if (!jsonLine) {
    throw new Error('rust_provider_route_authority_empty_stdout');
  }
  const parsed = JSON.parse(jsonLine);
  return validateRunnerJson(parsed, jsonLine);
}

function validateRunnerJson(parsed, source = '') {
  if (!parsed || parsed.ok !== true) {
    const detail = source || JSON.stringify(parsed || {}).slice(0, 240);
    throw new Error(`rust_provider_route_authority_not_ok:${detail.slice(0, 240)}`);
  }
  return parsed;
}

async function httpGetJson(url, timeoutMs) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  const client = parsedUrl.protocol === 'https:' ? https : http;
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_provider_route_authority_http_unsupported_protocol:${parsedUrl.protocol}`);
  }
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
          req.destroy(new Error('rust_provider_route_authority_http_response_too_large'));
        }
      });
      res.on('end', () => {
        if (Number(res.statusCode || 0) < 200 || Number(res.statusCode || 0) >= 300) {
          reject(new Error(`rust_provider_route_authority_http_status:${res.statusCode || 0}:${body.slice(0, 240)}`));
          return;
        }
        resolve(body);
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('rust_provider_route_authority_http_timeout'));
    });
    req.on('error', reject);
  });
  return parseRunnerJson(stdout);
}

export function normalizeRustProviderRouteDecision(decision = {}) {
  return {
    requestedProvider: safeString(decision.requested_provider),
    requestedModelId: safeString(decision.requested_model_id),
    resolvedProvider: safeString(decision.resolved_provider),
    strategy: safeString(decision.strategy) || 'fill-first',
    selectionScope: safeString(decision.selection_scope),
    selectedAccountKey: safeString(decision.selected_account_key),
    fallbackReasonCode: safeString(decision.fallback_reason_code),
    availableCount: nonNegativeInt(decision.available_count, 0),
    totalCount: nonNegativeInt(decision.total_count, 0),
    candidates: Array.isArray(decision.candidates) ? decision.candidates : [],
    updatedAtMs: nonNegativeInt(decision.updated_at_ms, 0),
  };
}

export function createProviderRouteAuthorityBridge({
  env = process.env,
  execFileImpl = execFile,
  httpGetJsonImpl = httpGetJson,
  existsSync = fs.existsSync,
  nowMsImpl = Date.now,
  logger = console,
} = {}) {
  const config = resolveProviderRouteAuthorityConfig(env);
  const warned = new Set();
  const prepInFlightKeys = new Set();
  const prepLastStartedByKey = new Map();
  const observeInFlightKeys = new Set();
  const observeLastStartedByKey = new Map();
  const candidateCache = new Map();
  const candidateInFlightByKey = new Map();
  let readinessCache = null;

  function warnOnce(key, line) {
    if (warned.has(key)) return;
    warned.add(key);
    logger.warn?.(line);
  }

  function routeCacheKey(input = {}) {
    const runtimeBaseDir = safeString(input.runtimeBaseDir || input.runtime_base_dir);
    const provider = safeString(input.provider || input.providerOverride || input.provider_override);
    const modelId = safeString(input.modelId || input.model_id);
    const nowMs = nonNegativeInt(input.nowMs || input.now_ms, 0);
    return `${runtimeBaseDir}::${provider}::${modelId}::${nowMs || ''}`;
  }

  function pruneCandidateCache() {
    while (candidateCache.size > config.candidateCacheMaxEntries) {
      const firstKey = candidateCache.keys().next().value;
      if (firstKey == null) break;
      candidateCache.delete(firstKey);
    }
  }

  function canRun() {
    if (!config.enabled) {
      return {
        ok: true,
        used: false,
        fallback: true,
        error_code: 'rust_provider_route_authority_disabled',
      };
    }
    if (!existsSync(config.runnerPath) && !config.httpEnabled) {
      warnOnce(
        'missing_runner',
        `[hub_grpc] rust provider route authority disabled: missing runner=${config.runnerPath}`
      );
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_provider_route_authority_runner_missing',
      };
    }
    return null;
  }

  function buildRouteHttpUrl(input = {}) {
    const url = new URL('/provider/route', config.httpBaseUrl);
    const modelId = safeString(input.modelId || input.model_id);
    const provider = safeString(input.provider || input.providerOverride || input.provider_override);
    const runtimeBaseDir = safeString(input.runtimeBaseDir || input.runtime_base_dir);
    const nowMs = nonNegativeInt(input.nowMs || input.now_ms, 0);
    url.searchParams.set('model_id', modelId);
    if (provider) url.searchParams.set('provider', provider);
    if (runtimeBaseDir) url.searchParams.set('runtime_base_dir', runtimeBaseDir);
    if (nowMs > 0) url.searchParams.set('now_ms', String(nowMs));
    return url;
  }

  function buildReadinessHttpUrl() {
    const url = new URL('/provider/readiness', config.httpBaseUrl);
    url.searchParams.set(
      'min_compare_reports',
      String(parseIntInRange(config.readiness?.minCompareReports, 10, 0, 1000000))
    );
    url.searchParams.set(
      'max_mismatches',
      String(parseIntInRange(config.readiness?.maxMismatches, 0, 0, 1000000))
    );
    url.searchParams.set(
      'limit',
      String(parseIntInRange(config.readiness?.reportLimit, 20, 1, 500))
    );
    return url;
  }

  async function execJson(args) {
    const stdout = await new Promise((resolve, reject) => {
      execFileImpl(config.runnerPath, args, {
        encoding: 'utf8',
        timeout: config.timeoutMs,
        maxBuffer: 1024 * 1024,
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

  async function routeJson(input = {}) {
    if (config.httpEnabled) {
      const url = buildRouteHttpUrl(input);
      try {
        const out = await httpGetJsonImpl(url, config.httpTimeoutMs);
        if (config.verbose) {
          logger.log?.(`[hub_grpc] rust provider route authority HTTP route ok url=${url.origin}${url.pathname}`);
        }
        return validateRunnerJson(out);
      } catch (error) {
        warnOnce(
          'http_route_failed',
          `[hub_grpc] rust provider route authority HTTP route failed; ${config.httpFallbackToCli ? 'falling back to CLI' : 'CLI fallback disabled'}: ${error.message || error}`
        );
        if (!config.httpFallbackToCli) {
          throw error;
        }
      }
    }
    return await execJson(buildProviderRouteAuthorityArgs('route', input, config));
  }

  async function readinessJson() {
    if (config.httpEnabled) {
      const url = buildReadinessHttpUrl();
      try {
        const out = await httpGetJsonImpl(url, config.httpTimeoutMs);
        if (config.verbose) {
          logger.log?.(`[hub_grpc] rust provider route authority HTTP readiness ok url=${url.origin}${url.pathname}`);
        }
        return validateRunnerJson(out);
      } catch (error) {
        warnOnce(
          'http_readiness_failed',
          `[hub_grpc] rust provider route authority HTTP readiness failed; ${config.httpFallbackToCli ? 'falling back to CLI' : 'CLI fallback disabled'}: ${error.message || error}`
        );
        if (!config.httpFallbackToCli) {
          throw error;
        }
      }
    }
    return await execJson(buildProviderRouteAuthorityArgs('readiness', {}, config));
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
      const out = await readinessJson();
      const result = {
        ok: true,
        ready: out.ready === true,
        raw: out,
        error_code: out.ready === true ? '' : 'rust_provider_route_authority_not_ready',
      };
      readinessCache = { checkedAtMs: now, result };
      return result;
    } catch (error) {
      const result = {
        ok: false,
        ready: false,
        fallback: true,
        error_code: 'rust_provider_route_authority_readiness_failed',
        error_message: String(error.message || error),
      };
      readinessCache = { checkedAtMs: now, result };
      warnOnce(
        'readiness_failed',
        `[hub_grpc] rust provider route authority readiness failed: ${error.message || error}`
      );
      return result;
    }
  }

  async function route(input = {}) {
    const blocked = canRun();
    if (blocked) return blocked;

    const modelId = safeString(input.modelId || input.model_id);
    if (!modelId) {
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_provider_route_authority_missing_model_id',
      };
    }
    const nodeAccountKey = safeString(input.nodeAccountKey || input.node_account_key);
    const requireNodeMatch = config.requireNodeMatch && input.requireNodeMatch !== false && input.require_node_match !== false;

    const readiness = await checkReadiness();
    if (readiness.ready !== true) {
      return {
        ok: readiness.ok === true,
        used: false,
        fallback: true,
        error_code: readiness.error_code || 'rust_provider_route_authority_not_ready',
        readiness: readiness.raw || null,
      };
    }

    try {
      const out = await routeJson(input);
      const decision = normalizeRustProviderRouteDecision(out.decision || {});
      if (!decision.selectedAccountKey) {
        return {
          ok: true,
          used: true,
          fallback: true,
          selected: false,
          error_code: decision.fallbackReasonCode || 'rust_provider_route_no_account',
          decision,
          raw: out,
        };
      }
      if (config.verbose) {
        logger.log?.(
          `[hub_grpc] rust provider route authority selected account_key=${decision.selectedAccountKey} model=${decision.requestedModelId}`
        );
      }
      if (requireNodeMatch && nodeAccountKey && decision.selectedAccountKey !== nodeAccountKey) {
        logger.warn?.(
          `[hub_grpc] rust provider route authority account mismatch model=${decision.requestedModelId} node_account_key=${nodeAccountKey} rust_account_key=${decision.selectedAccountKey}`
        );
        return {
          ok: true,
          used: true,
          fallback: true,
          selected: false,
          mismatch: true,
          error_code: 'rust_provider_route_authority_account_mismatch',
          nodeAccountKey,
          selectedAccountKey: decision.selectedAccountKey,
          decision,
          raw: out,
        };
      }
      return {
        ok: true,
        used: true,
        fallback: false,
        selected: true,
        selectedAccountKey: decision.selectedAccountKey,
        decision,
        raw: out,
      };
    } catch (error) {
      warnOnce(
        'route_failed',
        `[hub_grpc] rust provider route authority route failed: ${error.message || error}`
      );
      if (!config.fallbackOnError) {
        throw error;
      }
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_provider_route_authority_route_failed',
        error_message: String(error.message || error),
      };
    }
  }

  function observeRoute(input = {}) {
    if (!config.observeEnabled) return false;
    const nodeAccountKey = safeString(input.nodeAccountKey || input.node_account_key);
    const modelId = safeString(input.modelId || input.model_id);
    if (!modelId) return false;
    const runtimeBaseDir = safeString(input.runtimeBaseDir || input.runtime_base_dir);
    const provider = safeString(input.provider || input.providerOverride || input.provider_override);
    const observeKey = `${runtimeBaseDir}::${provider}::${modelId}`;
    const current = Number(nowMsImpl());

    if (observeInFlightKeys.has(observeKey)) return false;
    if (observeInFlightKeys.size >= config.observeMaxInFlight) return false;
    if (current - Number(observeLastStartedByKey.get(observeKey) || 0) < config.observeThrottleMs) {
      return false;
    }

    observeInFlightKeys.add(observeKey);
    observeLastStartedByKey.set(observeKey, current);
    route({ ...input, requireNodeMatch: false })
      .then((out) => {
        if (!out || out.used !== true) {
          if (config.verbose) {
            logger.log?.(
              `[hub_grpc] rust provider route observe skipped model=${modelId} reason=${safeString(out?.error_code)}`
            );
          }
          return;
        }
        if (out.selected !== true) {
          logger.warn?.(
            `[hub_grpc] rust provider route observe no selection model=${modelId} reason=${safeString(out.error_code)} node_account_key=${nodeAccountKey}`
          );
          return;
        }
        if (nodeAccountKey && out.selectedAccountKey !== nodeAccountKey) {
          logger.warn?.(
            `[hub_grpc] rust provider route observe mismatch model=${modelId} node_account_key=${nodeAccountKey} rust_account_key=${out.selectedAccountKey}`
          );
          return;
        }
        if (config.verbose) {
          logger.log?.(
            `[hub_grpc] rust provider route observe match model=${modelId} account_key=${out.selectedAccountKey}`
          );
        }
      })
      .catch((error) => {
        logger.warn?.(
          `[hub_grpc] rust provider route observe failed model=${modelId} error=${error.message || error}`
        );
      })
      .finally(() => {
        observeInFlightKeys.delete(observeKey);
      });
    return true;
  }

  function prepRoute(input = {}) {
    if (!config.prepEnabled) return false;
    const nodeAccountKey = safeString(input.nodeAccountKey || input.node_account_key);
    const modelId = safeString(input.modelId || input.model_id);
    if (!modelId) return false;
    const runtimeBaseDir = safeString(input.runtimeBaseDir || input.runtime_base_dir);
    const provider = safeString(input.provider || input.providerOverride || input.provider_override);
    const prepKey = `${runtimeBaseDir}::${provider}::${modelId}`;
    const current = Number(nowMsImpl());

    if (prepInFlightKeys.has(prepKey)) return false;
    if (prepInFlightKeys.size >= config.prepMaxInFlight) return false;
    if (current - Number(prepLastStartedByKey.get(prepKey) || 0) < config.prepThrottleMs) {
      return false;
    }

    prepInFlightKeys.add(prepKey);
    prepLastStartedByKey.set(prepKey, current);
    route(input)
      .then((out) => {
        if (!out || out.used !== true) {
          if (config.verbose) {
            logger.log?.(
              `[hub_grpc] rust provider route prep skipped model=${modelId} reason=${safeString(out?.error_code)}`
            );
          }
          return;
        }
        if (out.selected !== true) {
          logger.warn?.(
            `[hub_grpc] rust provider route prep no selection model=${modelId} reason=${safeString(out.error_code)} node_account_key=${nodeAccountKey}`
          );
          return;
        }
        if (nodeAccountKey && out.selectedAccountKey !== nodeAccountKey) {
          logger.warn?.(
            `[hub_grpc] rust provider route prep mismatch model=${modelId} node_account_key=${nodeAccountKey} rust_account_key=${out.selectedAccountKey}`
          );
          return;
        }
        if (config.verbose) {
          logger.log?.(
            `[hub_grpc] rust provider route prep match model=${modelId} account_key=${out.selectedAccountKey}`
          );
        }
      })
      .catch((error) => {
        logger.warn?.(
          `[hub_grpc] rust provider route prep failed model=${modelId} error=${error.message || error}`
        );
      })
      .finally(() => {
        prepInFlightKeys.delete(prepKey);
      });
    return true;
  }

  async function candidateRoute(input = {}) {
    if (!config.candidateEnabled) {
      return {
        ok: true,
        used: false,
        fallback: true,
        error_code: 'rust_provider_route_authority_candidate_disabled',
      };
    }
    const modelId = safeString(input.modelId || input.model_id);
    if (!modelId || config.candidateCacheMs <= 0) {
      return await route({ ...input, requireNodeMatch: false });
    }

    const cacheKey = routeCacheKey(input);
    const current = Number(nowMsImpl());
    const cached = candidateCache.get(cacheKey);
    if (cached && current - cached.cachedAtMs <= config.candidateCacheMs) {
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust provider route candidate cache hit model=${modelId}`);
      }
      return cached.out;
    }
    if (cached) {
      candidateCache.delete(cacheKey);
    }

    const inFlight = candidateInFlightByKey.get(cacheKey);
    if (inFlight) {
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust provider route candidate single-flight model=${modelId}`);
      }
      return await inFlight;
    }

    const promise = route({ ...input, requireNodeMatch: false })
      .then((out) => {
        if (out && out.ok === true && out.used === true) {
          candidateCache.set(cacheKey, { cachedAtMs: Number(nowMsImpl()), out });
          pruneCandidateCache();
        }
        return out;
      })
      .finally(() => {
        candidateInFlightByKey.delete(cacheKey);
      });
    candidateInFlightByKey.set(cacheKey, promise);
    return await promise;
  }

  return {
    config,
    checkReadiness,
    route,
    prepRoute,
    observeRoute,
    candidateRoute,
    _clearReadinessCache() {
      readinessCache = null;
    },
  };
}
