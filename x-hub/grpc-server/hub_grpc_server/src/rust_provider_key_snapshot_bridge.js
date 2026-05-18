import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import { URL } from 'node:url';

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

function readAccessKey(env = process.env) {
  const direct = safeString(env.XHUB_RUST_HTTP_ACCESS_KEY || env.XHUB_RUST_HUB_ACCESS_KEY);
  if (direct) return direct;
  const filePath = safeString(env.XHUB_RUST_HTTP_ACCESS_KEY_FILE || env.XHUB_RUST_HUB_ACCESS_KEY_FILE);
  if (!filePath) return '';
  try {
    return safeString(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return '';
  }
}

export function resolveRustProviderKeySnapshotConfig(env = process.env) {
  const enabled = parseBoolEnv(
    env.XHUB_RUST_PROVIDER_KEY_SNAPSHOT
      ?? env.XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP
      ?? env.XHUB_ENABLE_RUST_PROVIDER_KEY_SNAPSHOT,
    false
  );
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled,
    fallbackOnError: parseBoolEnv(env.XHUB_RUST_PROVIDER_KEY_SNAPSHOT_FALLBACK_ON_ERROR, true),
    httpBaseUrl: safeString(env.XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP_BASE_URL)
      || safeString(env.XHUB_RUST_HUB_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    timeoutMs: parseIntInRange(env.XHUB_RUST_PROVIDER_KEY_SNAPSHOT_TIMEOUT_MS, 1000, 100, 60000),
    accessKey: readAccessKey(env),
    verbose: parseBoolEnv(env.XHUB_RUST_PROVIDER_KEY_SNAPSHOT_VERBOSE, false),
  };
}

function httpGetJson(url, { timeoutMs = 1000, accessKey = '' } = {}) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  const client = parsedUrl.protocol === 'https:' ? https : http;
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_provider_key_snapshot_http_unsupported_protocol:${parsedUrl.protocol}`);
  }
  const headers = { accept: 'application/json' };
  if (accessKey) {
    headers.authorization = `Bearer ${accessKey}`;
    headers['x-xhub-access-key'] = accessKey;
  }
  return new Promise((resolve, reject) => {
    const req = client.get(parsedUrl, {
      timeout: timeoutMs,
      headers,
    }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += String(chunk || '');
        if (body.length > 4 * 1024 * 1024) {
          req.destroy(new Error('rust_provider_key_snapshot_http_response_too_large'));
        }
      });
      res.on('end', () => {
        if (Number(res.statusCode || 0) < 200 || Number(res.statusCode || 0) >= 300) {
          reject(new Error(`rust_provider_key_snapshot_http_status:${res.statusCode || 0}:${body.slice(0, 240)}`));
          return;
        }
        try {
          resolve(JSON.parse(body || '{}'));
        } catch (error) {
          reject(new Error(`rust_provider_key_snapshot_http_invalid_json:${error.message || error}`));
        }
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('rust_provider_key_snapshot_http_timeout'));
    });
    req.on('error', reject);
  });
}

function unwrapSnapshot(out = {}) {
  if (!out || out.ok !== true) {
    throw new Error(`rust_provider_key_snapshot_not_ok:${JSON.stringify(out || {}).slice(0, 240)}`);
  }
  const snapshot = out.snapshot && typeof out.snapshot === 'object' ? out.snapshot : {};
  return { out, snapshot };
}

export function createRustProviderKeySnapshotBridge({
  env = process.env,
  httpGetJsonImpl = httpGetJson,
  logger = console,
} = {}) {
  const config = resolveRustProviderKeySnapshotConfig(env);

  function poolsUrl({ runtimeBaseDir = '', provider = '', modelId = '', includeMembers = false, nowMs = 0 } = {}) {
    const url = new URL('/provider/pools', config.httpBaseUrl);
    if (safeString(runtimeBaseDir)) url.searchParams.set('runtime_base_dir', safeString(runtimeBaseDir));
    if (safeString(provider)) url.searchParams.set('provider', safeString(provider));
    if (safeString(modelId)) url.searchParams.set('model_id', safeString(modelId));
    url.searchParams.set('include_members', includeMembers === true ? '1' : '0');
    if (nonNegativeInt(nowMs, 0) > 0) url.searchParams.set('now_ms', String(nonNegativeInt(nowMs, 0)));
    return url;
  }

  function runtimeSnapshotUrl({ runtimeBaseDir = '', provider = '' } = {}) {
    const url = new URL('/provider/runtime-snapshot', config.httpBaseUrl);
    if (safeString(runtimeBaseDir)) url.searchParams.set('runtime_base_dir', safeString(runtimeBaseDir));
    if (safeString(provider)) url.searchParams.set('provider', safeString(provider));
    return url;
  }

  function disabledResult(errorCode) {
    return {
      ok: false,
      used: false,
      fallback: true,
      error_code: errorCode,
    };
  }

  async function listProviderKeyPools(input = {}) {
    if (!config.enabled) {
      return disabledResult('rust_provider_key_snapshot_disabled');
    }
    try {
      const { out, snapshot } = unwrapSnapshot(
        await httpGetJsonImpl(poolsUrl(input), {
          timeoutMs: config.timeoutMs,
          accessKey: config.accessKey,
        })
      );
      return {
        ok: true,
        used: true,
        fallback: false,
        pools: Array.isArray(snapshot.pools) ? snapshot.pools : [],
        updated_at_ms: nonNegativeInt(snapshot.updated_at_ms, 0),
        routing_strategy: safeString(snapshot.routing_strategy) || 'fill-first',
        raw: out,
      };
    } catch (error) {
      logger.warn?.(`[hub_grpc] rust provider key pools snapshot failed: ${error.message || error}`);
      return {
        ok: false,
        used: false,
        fallback: config.fallbackOnError,
        error_code: 'rust_provider_key_pools_snapshot_failed',
        error_message: String(error.message || error),
      };
    }
  }

  async function getProviderKeyRuntimeSnapshot(input = {}) {
    if (!config.enabled) {
      return disabledResult('rust_provider_key_snapshot_disabled');
    }
    try {
      const { out, snapshot } = unwrapSnapshot(
        await httpGetJsonImpl(runtimeSnapshotUrl(input), {
          timeoutMs: config.timeoutMs,
          accessKey: config.accessKey,
        })
      );
      return {
        ok: true,
        used: true,
        fallback: false,
        accounts: Array.isArray(snapshot.accounts) ? snapshot.accounts : [],
        import_source_statuses: Array.isArray(snapshot.import_source_statuses)
          ? snapshot.import_source_statuses
          : [],
        updated_at_ms: nonNegativeInt(snapshot.updated_at_ms, 0),
        global_routing_strategy: safeString(snapshot.global_routing_strategy) || 'fill-first',
        providers: Array.isArray(snapshot.providers) ? snapshot.providers : [],
        raw: out,
      };
    } catch (error) {
      logger.warn?.(`[hub_grpc] rust provider key runtime snapshot failed: ${error.message || error}`);
      return {
        ok: false,
        used: false,
        fallback: config.fallbackOnError,
        error_code: 'rust_provider_key_runtime_snapshot_failed',
        error_message: String(error.message || error),
      };
    }
  }

  return {
    config,
    listProviderKeyPools,
    getProviderKeyRuntimeSnapshot,
  };
}
