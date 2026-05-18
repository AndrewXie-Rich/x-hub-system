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

export function resolveRustProviderQuotaApplyConfig(env = process.env) {
  const enabled = parseBoolEnv(
    env.XHUB_RUST_PROVIDER_QUOTA_APPLY
      ?? env.XHUB_RUST_PROVIDER_KEY_QUOTA_APPLY
      ?? env.XHUB_ENABLE_RUST_PROVIDER_QUOTA_APPLY,
    false
  );
  const httpHost = safeString(env.XHUB_RUST_HUB_HOST) || '127.0.0.1';
  const httpPort = parseIntInRange(env.XHUB_RUST_HUB_HTTP_PORT, 50151, 1, 65535);
  return {
    enabled,
    planEnabled: parseBoolEnv(
      env.XHUB_RUST_PROVIDER_QUOTA_PLAN
        ?? env.XHUB_RUST_PROVIDER_QUOTA_REFRESH_PLAN
        ?? env.XHUB_ENABLE_RUST_PROVIDER_QUOTA_PLAN
        ?? env.XHUB_ENABLE_RUST_PROVIDER_QUOTA_SCHEDULER,
      enabled
    ),
    failureEnabled: parseBoolEnv(
      env.XHUB_RUST_PROVIDER_QUOTA_FAILURE
        ?? env.XHUB_RUST_PROVIDER_QUOTA_REFRESH_FAILURE
        ?? env.XHUB_ENABLE_RUST_PROVIDER_QUOTA_FAILURE
        ?? env.XHUB_ENABLE_RUST_PROVIDER_QUOTA_SCHEDULER,
      enabled
    ),
    fallbackOnError: parseBoolEnv(env.XHUB_RUST_PROVIDER_QUOTA_APPLY_FALLBACK_ON_ERROR, true),
    httpBaseUrl: safeString(env.XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP_BASE_URL)
      || safeString(env.XHUB_RUST_HUB_HTTP_BASE_URL)
      || `http://${httpHost}:${httpPort}`,
    timeoutMs: parseIntInRange(env.XHUB_RUST_PROVIDER_QUOTA_APPLY_TIMEOUT_MS, 1500, 100, 60000),
    accessKey: readAccessKey(env),
    verbose: parseBoolEnv(env.XHUB_RUST_PROVIDER_QUOTA_APPLY_VERBOSE, false),
  };
}

function httpPostJson(url, body, { timeoutMs = 1500, accessKey = '' } = {}) {
  const parsedUrl = url instanceof URL ? url : new URL(String(url));
  const client = parsedUrl.protocol === 'https:' ? https : http;
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    throw new Error(`rust_provider_quota_apply_http_unsupported_protocol:${parsedUrl.protocol}`);
  }
  const payload = JSON.stringify(body || {});
  const headers = {
    accept: 'application/json',
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(payload),
  };
  if (accessKey) {
    headers.authorization = `Bearer ${accessKey}`;
    headers['x-xhub-access-key'] = accessKey;
  }
  return new Promise((resolve, reject) => {
    const req = client.request(parsedUrl, {
      method: 'POST',
      timeout: timeoutMs,
      headers,
    }, (res) => {
      let responseBody = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        responseBody += String(chunk || '');
        if (responseBody.length > 4 * 1024 * 1024) {
          req.destroy(new Error('rust_provider_quota_apply_http_response_too_large'));
        }
      });
      res.on('end', () => {
        if (Number(res.statusCode || 0) < 200 || Number(res.statusCode || 0) >= 300) {
          reject(new Error(`rust_provider_quota_apply_http_status:${res.statusCode || 0}:${responseBody.slice(0, 240)}`));
          return;
        }
        try {
          resolve(JSON.parse(responseBody || '{}'));
        } catch (error) {
          reject(new Error(`rust_provider_quota_apply_http_invalid_json:${error.message || error}`));
        }
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('rust_provider_quota_apply_http_timeout'));
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function unwrapApplyResult(out = {}) {
  if (!out || out.ok !== true) {
    throw new Error(`rust_provider_quota_apply_not_ok:${JSON.stringify(out || {}).slice(0, 240)}`);
  }
  const result = out.result && typeof out.result === 'object' ? out.result : {};
  if (result.ok !== true) {
    throw new Error(`rust_provider_quota_apply_result_not_ok:${JSON.stringify(result || {}).slice(0, 240)}`);
  }
  return { out, result };
}

export function createRustProviderQuotaApplyBridge({
  env = process.env,
  httpPostJsonImpl = httpPostJson,
  logger = console,
} = {}) {
  const config = resolveRustProviderQuotaApplyConfig(env);

  function applyUrl() {
    return new URL('/provider/openai-quota-refresh/apply', config.httpBaseUrl);
  }

  function planUrl() {
    return new URL('/provider/openai-quota-refresh/plan', config.httpBaseUrl);
  }

  function failureUrl() {
    return new URL('/provider/openai-quota-refresh/failure', config.httpBaseUrl);
  }

  function disabledResult(errorCode) {
    return {
      ok: false,
      used: false,
      fallback: true,
      error_code: errorCode,
    };
  }

  async function planOpenAIQuotaRefresh(input = {}) {
    if (!config.enabled || !config.planEnabled) {
      return disabledResult('rust_provider_quota_plan_disabled');
    }
    try {
      const { out, result } = unwrapApplyResult(
        await httpPostJsonImpl(planUrl(), {
          runtime_base_dir: safeString(input.runtimeBaseDir || input.runtime_base_dir),
          now_ms: nonNegativeInt(input.nowMs ?? input.now_ms, 0),
          include_skipped: input.includeSkipped === true || input.include_skipped === true,
          in_flight_account_keys: Array.isArray(input.inFlightAccountKeys)
            ? input.inFlightAccountKeys.map(safeString).filter(Boolean)
            : (Array.isArray(input.in_flight_account_keys)
              ? input.in_flight_account_keys.map(safeString).filter(Boolean)
              : []),
        }, {
          timeoutMs: config.timeoutMs,
          accessKey: config.accessKey,
        })
      );
      const accounts = Array.isArray(result.accounts) ? result.accounts : [];
      return {
        ok: true,
        used: true,
        fallback: false,
        accounts,
        account_keys: accounts.map((account) => safeString(account.account_key)).filter(Boolean),
        due_accounts: nonNegativeInt(result.due_accounts, accounts.length),
        eligible_accounts: nonNegativeInt(result.eligible_accounts, 0),
        total_accounts: nonNegativeInt(result.total_accounts, 0),
        skipped_count: nonNegativeInt(result.skipped_count, 0),
        skipped_accounts: Array.isArray(result.skipped_accounts) ? result.skipped_accounts : [],
        raw: out,
      };
    } catch (error) {
      logger.warn?.(`[hub_grpc] rust provider quota plan failed: ${error.message || error}`);
      return {
        ok: false,
        used: false,
        fallback: config.fallbackOnError,
        error_code: 'rust_provider_quota_plan_failed',
        error_message: String(error.message || error),
      };
    }
  }

  async function applyOpenAIQuotaRefresh(input = {}) {
    if (!config.enabled) {
      return disabledResult('rust_provider_quota_apply_disabled');
    }
    try {
      const { out, result } = unwrapApplyResult(
        await httpPostJsonImpl(applyUrl(), {
          runtime_base_dir: safeString(input.runtimeBaseDir || input.runtime_base_dir),
          account_key: safeString(input.accountKey || input.account_key),
          usage: input.usage && typeof input.usage === 'object' ? input.usage : {},
          now_ms: nonNegativeInt(input.nowMs ?? input.now_ms, 0),
          refreshed_at_ms: nonNegativeInt(input.refreshedAtMs ?? input.refreshed_at_ms, 0),
          success_interval_ms: nonNegativeInt(input.successIntervalMs ?? input.success_interval_ms, 0),
          high_water_interval_ms: nonNegativeInt(input.highWaterIntervalMs ?? input.high_water_interval_ms, 0),
          account_id: safeString(input.accountId || input.account_id),
          oauth_source_key: safeString(input.oauthSourceKey || input.oauth_source_key),
        }, {
          timeoutMs: config.timeoutMs,
          accessKey: config.accessKey,
        })
      );
      return {
        ok: true,
        used: true,
        fallback: false,
        account_key: safeString(result.account_key),
        next_refresh_at_ms: nonNegativeInt(result.next_refresh_at_ms, 0),
        refreshed_at_ms: nonNegativeInt(result.refreshed_at_ms, 0),
        limited: result.limited === true,
        raw: out,
      };
    } catch (error) {
      logger.warn?.(`[hub_grpc] rust provider quota apply failed: ${error.message || error}`);
      return {
        ok: false,
        used: false,
        fallback: config.fallbackOnError,
        error_code: 'rust_provider_quota_apply_failed',
        error_message: String(error.message || error),
      };
    }
  }

  async function recordOpenAIQuotaRefreshFailure(input = {}) {
    if (!config.enabled || !config.failureEnabled) {
      return disabledResult('rust_provider_quota_failure_disabled');
    }
    try {
      const { out, result } = unwrapApplyResult(
        await httpPostJsonImpl(failureUrl(), {
          runtime_base_dir: safeString(input.runtimeBaseDir || input.runtime_base_dir),
          account_key: safeString(input.accountKey || input.account_key),
          failed_at_ms: nonNegativeInt(
            input.failedAtMs ?? input.failed_at_ms ?? input.nowMs ?? input.now_ms,
            0
          ),
          base_failure_backoff_ms: nonNegativeInt(
            input.baseFailureBackoffMs ?? input.base_failure_backoff_ms,
            0
          ),
          max_failure_backoff_ms: nonNegativeInt(
            input.maxFailureBackoffMs ?? input.max_failure_backoff_ms,
            0
          ),
          error_code: safeString(input.errorCode || input.error_code),
          error_message: safeString(input.errorMessage || input.error_message),
        }, {
          timeoutMs: config.timeoutMs,
          accessKey: config.accessKey,
        })
      );
      return {
        ok: true,
        used: true,
        fallback: false,
        account_key: safeString(result.account_key),
        failure_count: nonNegativeInt(result.failure_count, 0),
        next_refresh_at_ms: nonNegativeInt(result.next_refresh_at_ms, 0),
        failed_at_ms: nonNegativeInt(result.failed_at_ms, 0),
        raw: out,
      };
    } catch (error) {
      logger.warn?.(`[hub_grpc] rust provider quota failure record failed: ${error.message || error}`);
      return {
        ok: false,
        used: false,
        fallback: config.fallbackOnError,
        error_code: 'rust_provider_quota_failure_failed',
        error_message: String(error.message || error),
      };
    }
  }

  return {
    config,
    planOpenAIQuotaRefresh,
    applyOpenAIQuotaRefresh,
    recordOpenAIQuotaRefreshFailure,
  };
}
