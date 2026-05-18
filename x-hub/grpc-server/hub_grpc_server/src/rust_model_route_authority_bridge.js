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

function safeStringList(values) {
  const out = [];
  const seen = new Set();
  const items = Array.isArray(values)
    ? values
    : String(values || '').split(',');
  for (const raw of items) {
    const cleaned = safeString(raw);
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
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

export function resolveModelRouteAuthorityConfig(env = process.env) {
  const root = resolveRustHubRoot(env);
  const prepEnabled = parseBoolEnv(env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP, false);
  const candidateEnabled = parseBoolEnv(
    env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE,
    prepEnabled
  );
  const productionAuthority = parseBoolEnv(
    env.XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY
      ?? env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION
      ?? env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER
      ?? env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY,
    false
  );
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled: prepEnabled || candidateEnabled || productionAuthority,
    prepEnabled,
    candidateEnabled,
    productionAuthority,
    requireReady: parseBoolEnv(env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY, true),
    requireNodeMatch: parseBoolEnv(env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH, true),
    fallbackOnError: parseBoolEnv(env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR, true),
    root,
    runnerPath: safeString(env.XHUB_RUST_HUB_RUNNER)
      || safeString(env.XHUB_RUST_MODEL_ROUTE_RUNNER)
      || path.join(root, 'tools', 'run_rust_hub.command'),
    timeoutMs: parseIntInRange(env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_TIMEOUT_MS, 5000, 500, 60000),
    httpEnabled: parseBoolEnv(env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP, false),
    httpBaseUrl: safeString(env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    httpTimeoutMs: parseIntInRange(
      env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS,
      750,
      100,
      60000
    ),
    httpFallbackToCli: parseBoolEnv(
      env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI
        ?? env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_CLI,
      true
    ),
    prepThrottleMs: parseIntInRange(
      env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_THROTTLE_MS,
      1000,
      0,
      60000
    ),
    prepMaxInFlight: parseIntInRange(
      env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT,
      2,
      1,
      16
    ),
    candidateCacheMs: parseIntInRange(
      env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS,
      250,
      0,
      60000
    ),
    candidateCacheMaxEntries: parseIntInRange(
      env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES,
      128,
      1,
      10000
    ),
    readinessCacheMs: parseIntInRange(
      env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_READINESS_CACHE_MS,
      1000,
      0,
      60000
    ),
    readiness: {
      minCompareReports: parseIntInRange(
        env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS,
        10,
        0,
        1000000
      ),
      maxMismatches: parseIntInRange(
        env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_MAX_MISMATCHES,
        0,
        0,
        1000000
      ),
      reportLimit: parseIntInRange(
        env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_REPORT_LIMIT,
        20,
        1,
        500
      ),
    },
    verbose: parseBoolEnv(env.XHUB_RUST_MODEL_ROUTE_AUTHORITY_VERBOSE, false),
  };
}

export function buildModelRouteAuthorityArgs(action, input = {}, config = resolveModelRouteAuthorityConfig({})) {
  switch (action) {
    case 'readiness':
      return [
        'model',
        'readiness',
        '--min-compare-reports',
        String(parseIntInRange(config.readiness?.minCompareReports, 10, 0, 1000000)),
        '--max-mismatches',
        String(parseIntInRange(config.readiness?.maxMismatches, 0, 0, 1000000)),
        '--limit',
        String(parseIntInRange(config.readiness?.reportLimit, 20, 1, 500)),
      ];
    case 'route': {
      const modelId = safeString(input.modelId || input.model_id) || 'auto';
      const taskType = safeString(input.taskType || input.task_type) || 'text_generate';
      const runtimeBaseDir = safeString(input.runtimeBaseDir || input.runtime_base_dir);
      const privacyMode = safeString(input.privacyMode || input.privacy_mode);
      const costPreference = safeString(input.costPreference || input.cost_preference);
      const nowMs = nonNegativeInt(input.nowMs || input.now_ms, 0);
      const args = [
        'model',
        'route',
        '--task-type',
        taskType,
        '--model-id',
        modelId,
      ];
      for (const capability of safeStringList(
        input.requiredCapabilities
          || input.required_capabilities
          || input.requiredCapability
          || input.required_capability
      )) {
        args.push('--required-capability', capability);
      }
      if (privacyMode) args.push('--privacy-mode', privacyMode);
      if (costPreference) args.push('--cost-preference', costPreference);
      if (runtimeBaseDir) args.push('--runtime-base-dir', runtimeBaseDir);
      if (nowMs > 0) args.push('--now-ms', String(nowMs));
      return args;
    }
    default:
      throw new Error(`unknown model route authority action: ${action}`);
  }
}

function assertNoSecretMaterial(value, pathLabel = 'root') {
  const secretKeyPattern = /^(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|authorization|provider[_-]?key)$/i;
  const secretValuePattern = /\b(sk-[A-Za-z0-9_\-]{8,}|Bearer\s+[A-Za-z0-9_\-.=]{8,}|xox[baprs]-[A-Za-z0-9-]{8,})\b/;
  const visit = (item, currentPath) => {
    if (item == null) return;
    if (typeof item === 'string') {
      if (secretValuePattern.test(item)) {
        throw new Error(`rust_model_route_authority_secret_material:${currentPath}`);
      }
      return;
    }
    if (typeof item !== 'object') return;
    if (Array.isArray(item)) {
      item.forEach((entry, index) => visit(entry, `${currentPath}[${index}]`));
      return;
    }
    for (const [key, entry] of Object.entries(item)) {
      const nextPath = `${currentPath}.${key}`;
      if (secretKeyPattern.test(String(key || ''))) {
        throw new Error(`rust_model_route_authority_secret_key:${nextPath}`);
      }
      visit(entry, nextPath);
    }
  };
  visit(value, pathLabel);
}

function parseRunnerJson(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const jsonLine = [...lines].reverse().find((line) => line.startsWith('{'));
  if (!jsonLine) {
    throw new Error('rust_model_route_authority_empty_stdout');
  }
  const parsed = JSON.parse(jsonLine);
  return validateRunnerJson(parsed, jsonLine);
}

function validateRunnerJson(parsed, source = '') {
  if (!parsed || parsed.ok !== true) {
    const detail = source || JSON.stringify(parsed || {}).slice(0, 240);
    throw new Error(`rust_model_route_authority_not_ok:${detail.slice(0, 240)}`);
  }
  assertNoSecretMaterial(parsed);
  return parsed;
}

async function httpGetJson(url, timeoutMs) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  const client = parsedUrl.protocol === 'https:' ? https : http;
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_model_route_authority_http_unsupported_protocol:${parsedUrl.protocol}`);
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
          req.destroy(new Error('rust_model_route_authority_http_response_too_large'));
        }
      });
      res.on('end', () => {
        if (Number(res.statusCode || 0) < 200 || Number(res.statusCode || 0) >= 300) {
          reject(new Error(`rust_model_route_authority_http_status:${res.statusCode || 0}:${body.slice(0, 240)}`));
          return;
        }
        resolve(body);
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('rust_model_route_authority_http_timeout'));
    });
    req.on('error', reject);
  });
  return parseRunnerJson(stdout);
}

export function normalizeRustModelRouteDecision(out = {}) {
  const request = out.request && typeof out.request === 'object' ? out.request : {};
  const remoteCandidates = Array.isArray(out.remote_candidates) ? out.remote_candidates : [];
  const localCandidates = Array.isArray(out.local_candidates) ? out.local_candidates : [];
  return {
    schemaVersion: safeString(out.schema_version),
    requestedTaskType: safeString(request.task_type || request.taskType),
    requestedModelId: safeString(request.model_id || request.modelId),
    requiredCapabilities: safeStringList(request.required_capabilities || request.requiredCapabilities),
    privacyMode: safeString(request.privacy_mode || request.privacyMode),
    costPreference: safeString(request.cost_preference || request.costPreference),
    selectedRouteKind: safeString(out.selected_route_kind || out.selectedRouteKind),
    selectedModelId: safeString(out.selected_model_id || out.selectedModelId),
    blockingReasonCode: safeString(out.blocking_reason_code || out.blockingReasonCode),
    remoteCandidateCount: remoteCandidates.length,
    localCandidateCount: localCandidates.length,
    updatedAtMs: nonNegativeInt(out.updated_at_ms || out.updatedAtMs, 0),
  };
}

export function createModelRouteAuthorityBridge({
  env = process.env,
  execFileImpl = execFile,
  httpGetJsonImpl = httpGetJson,
  existsSync = fs.existsSync,
  nowMsImpl = Date.now,
  logger = console,
} = {}) {
  const config = resolveModelRouteAuthorityConfig(env);
  const warned = new Set();
  const prepInFlightKeys = new Set();
  const prepLastStartedByKey = new Map();
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
    const taskType = safeString(input.taskType || input.task_type) || 'text_generate';
    const modelId = safeString(input.modelId || input.model_id) || 'auto';
    const privacyMode = safeString(input.privacyMode || input.privacy_mode);
    const costPreference = safeString(input.costPreference || input.cost_preference);
    const capabilities = safeStringList(input.requiredCapabilities || input.required_capabilities).join(',');
    const nowMs = nonNegativeInt(input.nowMs || input.now_ms, 0);
    return `${runtimeBaseDir}::${taskType}::${modelId}::${privacyMode}::${costPreference}::${capabilities}::${nowMs || ''}`;
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
        error_code: 'rust_model_route_authority_disabled',
      };
    }
    if (!existsSync(config.runnerPath) && !config.httpEnabled) {
      warnOnce(
        'missing_runner',
        `[hub_grpc] rust model route authority disabled: missing runner=${config.runnerPath}`
      );
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_model_route_authority_runner_missing',
      };
    }
    return null;
  }

  function buildRouteHttpUrl(input = {}) {
    const url = new URL('/model/route', config.httpBaseUrl);
    url.searchParams.set('task_type', safeString(input.taskType || input.task_type) || 'text_generate');
    url.searchParams.set('model_id', safeString(input.modelId || input.model_id) || 'auto');
    const runtimeBaseDir = safeString(input.runtimeBaseDir || input.runtime_base_dir);
    const privacyMode = safeString(input.privacyMode || input.privacy_mode);
    const costPreference = safeString(input.costPreference || input.cost_preference);
    const nowMs = nonNegativeInt(input.nowMs || input.now_ms, 0);
    for (const capability of safeStringList(input.requiredCapabilities || input.required_capabilities)) {
      url.searchParams.append('required_capability', capability);
    }
    if (privacyMode) url.searchParams.set('privacy_mode', privacyMode);
    if (costPreference) url.searchParams.set('cost_preference', costPreference);
    if (runtimeBaseDir) url.searchParams.set('runtime_base_dir', runtimeBaseDir);
    if (nowMs > 0) url.searchParams.set('now_ms', String(nowMs));
    return url;
  }

  function buildReadinessHttpUrl() {
    const url = new URL('/model/readiness', config.httpBaseUrl);
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
          logger.log?.(`[hub_grpc] rust model route authority HTTP route ok url=${url.origin}${url.pathname}`);
        }
        return validateRunnerJson(out);
      } catch (error) {
        warnOnce(
          'http_route_failed',
          `[hub_grpc] rust model route authority HTTP route failed; ${config.httpFallbackToCli ? 'falling back to CLI' : 'CLI fallback disabled'}: ${error.message || error}`
        );
        if (!config.httpFallbackToCli) {
          throw error;
        }
      }
    }
    return await execJson(buildModelRouteAuthorityArgs('route', input, config));
  }

  async function readinessJson() {
    if (config.httpEnabled) {
      const url = buildReadinessHttpUrl();
      try {
        const out = await httpGetJsonImpl(url, config.httpTimeoutMs);
        if (config.verbose) {
          logger.log?.(`[hub_grpc] rust model route authority HTTP readiness ok url=${url.origin}${url.pathname}`);
        }
        return validateRunnerJson(out);
      } catch (error) {
        warnOnce(
          'http_readiness_failed',
          `[hub_grpc] rust model route authority HTTP readiness failed; ${config.httpFallbackToCli ? 'falling back to CLI' : 'CLI fallback disabled'}: ${error.message || error}`
        );
        if (!config.httpFallbackToCli) {
          throw error;
        }
      }
    }
    return await execJson(buildModelRouteAuthorityArgs('readiness', {}, config));
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
        error_code: out.ready === true ? '' : 'rust_model_route_authority_not_ready',
      };
      readinessCache = { checkedAtMs: now, result };
      return result;
    } catch (error) {
      const result = {
        ok: false,
        ready: false,
        fallback: true,
        error_code: 'rust_model_route_authority_readiness_failed',
        error_message: String(error.message || error),
      };
      readinessCache = { checkedAtMs: now, result };
      warnOnce(
        'readiness_failed',
        `[hub_grpc] rust model route authority readiness failed: ${error.message || error}`
      );
      return result;
    }
  }

  async function route(input = {}) {
    const blocked = canRun();
    if (blocked) return blocked;

    const nodeModelId = safeString(input.nodeModelId || input.node_model_id);
    const nodeRouteKind = safeString(input.nodeRouteKind || input.node_route_kind);
    const requireNodeMatch = config.requireNodeMatch && input.requireNodeMatch !== false && input.require_node_match !== false;

    const readiness = await checkReadiness();
    if (readiness.ready !== true) {
      return {
        ok: readiness.ok === true,
        used: false,
        fallback: true,
        error_code: readiness.error_code || 'rust_model_route_authority_not_ready',
        readiness: readiness.raw || null,
      };
    }

    try {
      const out = await routeJson(input);
      const decision = normalizeRustModelRouteDecision(out);
      if (!decision.selectedModelId) {
        return {
          ok: true,
          used: true,
          fallback: true,
          selected: false,
          error_code: decision.blockingReasonCode || 'no_model_route_available',
          decision,
          raw: out,
        };
      }
      if (config.verbose) {
        logger.log?.(
          `[hub_grpc] rust model route authority selected route=${decision.selectedRouteKind} model=${decision.selectedModelId}`
        );
      }
      if (requireNodeMatch && nodeModelId && decision.selectedModelId !== nodeModelId) {
        logger.warn?.(
          `[hub_grpc] rust model route authority model mismatch node_model_id=${nodeModelId} rust_model_id=${decision.selectedModelId}`
        );
        return {
          ok: true,
          used: true,
          fallback: true,
          selected: false,
          mismatch: true,
          error_code: 'rust_model_route_authority_model_mismatch',
          nodeModelId,
          selectedModelId: decision.selectedModelId,
          decision,
          raw: out,
        };
      }
      if (requireNodeMatch && nodeRouteKind && decision.selectedRouteKind && decision.selectedRouteKind !== nodeRouteKind) {
        logger.warn?.(
          `[hub_grpc] rust model route authority route-kind mismatch model=${decision.selectedModelId} node_route_kind=${nodeRouteKind} rust_route_kind=${decision.selectedRouteKind}`
        );
        return {
          ok: true,
          used: true,
          fallback: true,
          selected: false,
          mismatch: true,
          error_code: 'rust_model_route_authority_route_kind_mismatch',
          nodeRouteKind,
          selectedRouteKind: decision.selectedRouteKind,
          decision,
          raw: out,
        };
      }
      return {
        ok: true,
        used: true,
        fallback: false,
        selected: true,
        selectedModelId: decision.selectedModelId,
        selectedRouteKind: decision.selectedRouteKind,
        decision,
        raw: out,
      };
    } catch (error) {
      warnOnce(
        'route_failed',
        `[hub_grpc] rust model route authority route failed: ${error.message || error}`
      );
      if (!config.fallbackOnError) {
        throw error;
      }
      return {
        ok: false,
        used: false,
        fallback: true,
        error_code: 'rust_model_route_authority_route_failed',
        error_message: String(error.message || error),
      };
    }
  }

  function prepRoute(input = {}) {
    if (!config.prepEnabled) return false;
    const modelId = safeString(input.modelId || input.model_id) || 'auto';
    const runtimeBaseDir = safeString(input.runtimeBaseDir || input.runtime_base_dir);
    const taskType = safeString(input.taskType || input.task_type) || 'text_generate';
    const prepKey = `${runtimeBaseDir}::${taskType}::${modelId}`;
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
              `[hub_grpc] rust model route prep skipped model=${modelId} reason=${safeString(out?.error_code)}`
            );
          }
          return;
        }
        if (out.selected !== true) {
          logger.warn?.(
            `[hub_grpc] rust model route prep no selection model=${modelId} reason=${safeString(out.error_code)} node_model_id=${safeString(input.nodeModelId || input.node_model_id)}`
          );
          return;
        }
        if (config.verbose) {
          logger.log?.(
            `[hub_grpc] rust model route prep match model=${modelId} selected=${out.selectedModelId}`
          );
        }
      })
      .catch((error) => {
        logger.warn?.(
          `[hub_grpc] rust model route prep failed model=${modelId} error=${error.message || error}`
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
        error_code: 'rust_model_route_authority_candidate_disabled',
      };
    }
    const modelId = safeString(input.modelId || input.model_id) || 'auto';
    if (!modelId || config.candidateCacheMs <= 0) {
      return await route(input);
    }

    const cacheKey = routeCacheKey(input);
    const current = Number(nowMsImpl());
    const cached = candidateCache.get(cacheKey);
    if (cached && current - cached.cachedAtMs <= config.candidateCacheMs) {
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust model route candidate cache hit model=${modelId}`);
      }
      return cached.out;
    }
    if (cached) {
      candidateCache.delete(cacheKey);
    }

    const inFlight = candidateInFlightByKey.get(cacheKey);
    if (inFlight) {
      if (config.verbose) {
        logger.log?.(`[hub_grpc] rust model route candidate single-flight model=${modelId}`);
      }
      return await inFlight;
    }

    const promise = route(input)
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
    candidateRoute,
    _clearReadinessCache() {
      readinessCache = null;
    },
  };
}
