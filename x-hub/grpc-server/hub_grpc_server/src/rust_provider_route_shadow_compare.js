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

function nonNegativeInt(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
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

export function resolveProviderRouteShadowCompareConfig(env = process.env) {
  const root = resolveRustHubRoot(env);
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled: parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE, false),
    root,
    runnerPath: safeString(env.XHUB_RUST_HUB_RUNNER)
      || safeString(env.XHUB_RUST_PROVIDER_ROUTE_RUNNER)
      || path.join(root, 'tools', 'run_rust_hub.command'),
    throttleMs: parseIntInRange(env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_THROTTLE_MS, 1000, 0, 60000),
    timeoutMs: parseIntInRange(env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_TIMEOUT_MS, 5000, 500, 60000),
    httpEnabled: parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP, false),
    httpBaseUrl: safeString(env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    httpTimeoutMs: parseIntInRange(
      env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_TIMEOUT_MS,
      750,
      100,
      60000
    ),
    httpFallbackToCli: parseBoolEnv(
      env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_FALLBACK_TO_CLI
        ?? env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_FALLBACK_CLI,
      true
    ),
    maxInFlight: parseIntInRange(env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_MAX_IN_FLIGHT, 2, 1, 16),
    verbose: parseBoolEnv(env.XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_VERBOSE, false),
  };
}

export function buildProviderRouteShadowCompareArgs({
  runtimeBaseDir = '',
  modelId = '',
  provider = '',
  nodeDecision = {},
} = {}) {
  const selectedModelId = safeString(modelId) || safeString(nodeDecision?.requested_model_id);
  const selectedProvider = safeString(provider) || safeString(nodeDecision?.requested_provider);
  const args = [
    'provider',
    'compare',
    '--node-decision-json',
    JSON.stringify(nodeDecision || {}),
  ];
  if (selectedModelId) {
    args.push('--model-id', selectedModelId);
  }
  if (selectedProvider) {
    args.push('--provider', selectedProvider);
  }
  if (runtimeBaseDir) {
    args.push('--runtime-base-dir', safeString(runtimeBaseDir));
  }
  const updatedAtMs = nonNegativeInt(nodeDecision?.updated_at_ms);
  if (updatedAtMs > 0) {
    args.push('--now-ms', String(updatedAtMs));
  }
  return args;
}

export function buildProviderRouteShadowCompareHttpPayload({
  runtimeBaseDir = '',
  modelId = '',
  provider = '',
  nodeDecision = {},
} = {}) {
  const selectedModelId = safeString(modelId) || safeString(nodeDecision?.requested_model_id);
  const selectedProvider = safeString(provider) || safeString(nodeDecision?.requested_provider);
  const payload = {
    node_decision: nodeDecision || {},
  };
  if (selectedModelId) payload.model_id = selectedModelId;
  if (selectedProvider) payload.provider = selectedProvider;
  if (runtimeBaseDir) payload.runtime_base_dir = safeString(runtimeBaseDir);
  const updatedAtMs = nonNegativeInt(nodeDecision?.updated_at_ms);
  if (updatedAtMs > 0) payload.now_ms = updatedAtMs;
  return payload;
}

export function normalizeProviderRouteDecision(decision = {}) {
  return {
    requested_provider: safeString(decision?.requested_provider),
    requested_model_id: safeString(decision?.requested_model_id).toLowerCase(),
    resolved_provider: safeString(decision?.resolved_provider),
    strategy: safeString(decision?.strategy) || 'fill-first',
    selection_scope: safeString(decision?.selection_scope).toLowerCase(),
    selected_account_key: safeString(decision?.selected_account_key),
    fallback_reason_code: safeString(decision?.fallback_reason_code),
    available_count: nonNegativeInt(decision?.available_count),
    total_count: nonNegativeInt(decision?.total_count),
    candidates: normalizeCandidates(decision?.candidates),
  };
}

function normalizeCandidates(candidates) {
  if (!Array.isArray(candidates)) return [];
  return candidates.map((candidate) => ({
    account_key: safeString(candidate?.account_key),
    provider: safeString(candidate?.provider),
    provider_group: safeString(candidate?.provider_group),
    state: safeString(candidate?.state) || 'blocked',
    reason_code: safeString(candidate?.reason_code),
    selected: candidate?.selected === true,
    model_state_key: safeString(candidate?.model_state_key).toLowerCase(),
  }));
}

export function compareProviderRouteDecisions(nodeDecision, rustDecision) {
  const node = normalizeProviderRouteDecision(nodeDecision);
  const rust = normalizeProviderRouteDecision(rustDecision);
  const mismatches = [];
  collectDiffs('', node, rust, mismatches);
  return {
    matched: mismatches.length === 0,
    mismatches,
    node,
    rust,
  };
}

function collectDiffs(prefix, left, right, out) {
  if (Array.isArray(left) || Array.isArray(right)) {
    const leftArray = Array.isArray(left) ? left : [];
    const rightArray = Array.isArray(right) ? right : [];
    if (leftArray.length !== rightArray.length) {
      out.push(`${prefix || 'value'} length ${leftArray.length} != ${rightArray.length}`);
      return;
    }
    for (let i = 0; i < leftArray.length; i += 1) {
      collectDiffs(`${prefix}[${i}]`, leftArray[i], rightArray[i], out);
    }
    return;
  }
  if (left && typeof left === 'object' && right && typeof right === 'object') {
    const keys = [...new Set([...Object.keys(left), ...Object.keys(right)])].sort();
    for (const key of keys) {
      collectDiffs(prefix ? `${prefix}.${key}` : key, left[key], right[key], out);
    }
    return;
  }
  if (left !== right) {
    out.push(`${prefix || 'value'} ${JSON.stringify(left)} != ${JSON.stringify(right)}`);
  }
}

function parseRustRouteOutput(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const jsonLine = [...lines].reverse().find((line) => line.startsWith('{'));
  if (!jsonLine) {
    throw new Error('rust_provider_route_empty_stdout');
  }
  const parsed = JSON.parse(jsonLine);
  if (parsed?.ok !== true || !parsed?.decision) {
    throw new Error(`rust_provider_route_not_ok:${jsonLine.slice(0, 240)}`);
  }
  return parsed.decision;
}

function parseRustCompareOutput(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const jsonLine = [...lines].reverse().find((line) => line.startsWith('{'));
  if (!jsonLine) {
    throw new Error('rust_provider_compare_empty_stdout');
  }
  const parsed = JSON.parse(jsonLine);
  return validateRustCompareJson(parsed, jsonLine);
}

function validateRustCompareJson(parsed, source = '') {
  if (parsed?.ok !== true || parsed?.command !== 'compare') {
    const detail = source || JSON.stringify(parsed || {}).slice(0, 240);
    throw new Error(`rust_provider_compare_not_ok:${detail.slice(0, 240)}`);
  }
  return parsed;
}

async function httpPostJson(url, payload, timeoutMs) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_provider_compare_http_unsupported_protocol:${parsedUrl.protocol}`);
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
          req.destroy(new Error('rust_provider_compare_http_response_too_large'));
        }
      });
      res.on('end', () => {
        const statusCode = Number(res.statusCode || 0);
        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`rust_provider_compare_http_status:${statusCode}:${responseBody.slice(0, 240)}`));
          return;
        }
        resolve(responseBody);
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('rust_provider_compare_http_timeout'));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
  return parseRustCompareOutput(stdout);
}

export function createProviderRouteShadowComparer({
  env = process.env,
  execFileImpl = execFile,
  httpPostJsonImpl = httpPostJson,
  existsSync = fs.existsSync,
  now = () => Date.now(),
  logger = console,
} = {}) {
  const config = resolveProviderRouteShadowCompareConfig(env);
  const warned = new Set();
  const inFlightKeys = new Set();
  const lastStartedByKey = new Map();

  function warnOnce(key, line) {
    if (warned.has(key)) return;
    warned.add(key);
    logger.warn?.(line);
  }

  function compareHttpUrl() {
    return new URL('/provider/compare', config.httpBaseUrl);
  }

  async function execCompare(args) {
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
    return parseRustCompareOutput(stdout);
  }

  async function httpCompare(input = {}) {
    const out = await httpPostJsonImpl(
      compareHttpUrl(),
      buildProviderRouteShadowCompareHttpPayload(input),
      config.httpTimeoutMs
    );
    if (typeof out === 'string') {
      return parseRustCompareOutput(out);
    }
    return validateRustCompareJson(out);
  }

  async function compareWithFallback(input, args, runnerExists) {
    if (config.httpEnabled) {
      try {
        const comparison = await httpCompare(input);
        if (config.verbose) {
          logger.log?.('[hub_grpc] rust provider route shadow HTTP compare ok');
        }
        return comparison;
      } catch (error) {
        warnOnce(
          'http-compare-failed',
          `[hub_grpc] rust provider route shadow HTTP compare failed; ${config.httpFallbackToCli ? 'falling back to CLI' : 'CLI fallback disabled'}: ${error.message || error}`
        );
        if (!config.httpFallbackToCli) {
          throw error;
        }
        if (!runnerExists) {
          warnOnce(
            'missing-runner-fallback',
            `[hub_grpc] rust provider route shadow compare CLI fallback unavailable: missing runner=${config.runnerPath}`
          );
          throw new Error('rust_provider_compare_cli_fallback_runner_missing');
        }
      }
    }
    return execCompare(args);
  }

  function reportComparison(modelId, comparison) {
    if (comparison.match !== true) {
      const mismatches = Array.isArray(comparison.mismatches) ? comparison.mismatches : [];
      logger.warn?.(
        `[hub_grpc] rust provider route shadow mismatch model=${modelId} report_id=${safeString(comparison.report_id)} mismatches=${mismatches.slice(0, 6).join('; ')}`
      );
      return;
    }
    if (config.verbose) {
      logger.log?.(
        `[hub_grpc] rust provider route shadow match model=${modelId} report_id=${safeString(comparison.report_id)}`
      );
    }
  }

  function maybeCompare(input = {}) {
    if (!config.enabled) return false;
    const runtimeBaseDir = safeString(input.runtimeBaseDir);
    const nodeDecision = input.nodeDecision || {};
    const modelId = safeString(input.modelId) || safeString(nodeDecision.requested_model_id);
    if (!modelId) return false;
    const runnerExists = existsSync(config.runnerPath);
    if (!runnerExists && !config.httpEnabled) {
      warnOnce(
        'missing-runner',
        `[hub_grpc] rust provider route shadow compare disabled: missing runner=${config.runnerPath}`
      );
      return false;
    }

    const provider = safeString(input.provider) || safeString(nodeDecision.requested_provider);
    const key = `${runtimeBaseDir}::${provider}::${modelId}`;
    const current = now();
    if (inFlightKeys.has(key)) return false;
    if (inFlightKeys.size >= config.maxInFlight) return false;
    if (current - Number(lastStartedByKey.get(key) || 0) < config.throttleMs) return false;

    const args = buildProviderRouteShadowCompareArgs({
      runtimeBaseDir,
      modelId,
      provider,
      nodeDecision,
    });
    inFlightKeys.add(key);
    lastStartedByKey.set(key, current);

    compareWithFallback({
      runtimeBaseDir,
      modelId,
      provider,
      nodeDecision,
    }, args, runnerExists)
      .then((comparison) => {
        reportComparison(modelId, comparison);
      })
      .catch((error) => {
        logger.warn?.(
          `[hub_grpc] rust provider route shadow compare failed model=${modelId} error=${error.message || error} stderr=${safeString(error?.stderr)}`
        );
      })
      .finally(() => {
        inFlightKeys.delete(key);
      });

    return true;
  }

  return {
    config,
    maybeCompare,
  };
}
