import {
  invalidateProviderKeyCache,
  listProviderKeysFull,
  normalizeProviderRetrySource,
  updateProviderKey,
} from './provider_key_store.js';
import { callManagementApi } from './provider_key_management_api.js';
import { createRustProviderQuotaApplyBridge } from './rust_provider_quota_apply_bridge.js';
import { nowMs } from './util.js';

const DEFAULT_INTERVAL_MS = 60_000;
const DEFAULT_SUCCESS_INTERVAL_MS = 5 * 60_000;
const DEFAULT_HIGH_WATER_INTERVAL_MS = 60_000;
const DEFAULT_FAILURE_BACKOFF_MS = 60_000;
const DEFAULT_MAX_FAILURE_BACKOFF_MS = 15 * 60_000;
const QUOTA_REFRESH_RETRY_SOURCE = 'usage_window';
const QUOTA_BASIS_POINTS_CAP = 10_000;
const OPENAI_USAGE_URL = 'https://chatgpt.com/backend-api/wham/usage';
const OPENAI_OAUTH_SOURCES = new Set([
  'chatgpt',
  'openai-chatgpt',
  'openai',
  'codex',
]);

function safeString(value) {
  return String(value ?? '').trim();
}

function safeInt(value, fallback = 0) {
  const number = Number(value || 0);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

function safeNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function decodeBase64URLJSON(raw) {
  const value = safeString(raw);
  if (!value) return null;
  const padded = value
    .replace(/-/g, '+')
    .replace(/_/g, '/')
    .padEnd(Math.ceil(value.length / 4) * 4, '=');
  try {
    return JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
  } catch {
    return null;
  }
}

function decodeJWTPayload(token) {
  const value = safeString(token);
  if (!value) return null;
  const segments = value.split('.');
  if (segments.length < 2) return null;
  const payload = decodeBase64URLJSON(segments[1]);
  return payload && typeof payload === 'object' ? payload : null;
}

function inferredOpenAIQuotaMetadata(account) {
  const claims = decodeJWTPayload(account?.api_key);
  const authClaims = claims?.['https://api.openai.com/auth'];
  const accountId = safeString(
    account?.account_id
    || authClaims?.chatgpt_account_id
    || claims?.chatgpt_account_id
    || claims?.account_id
  );
  const oauthSourceKey = safeString(
    account?.oauth_source_key
    || (accountId && claims ? 'chatgpt' : '')
  ).toLowerCase();
  return {
    authIndex: safeInt(account?.auth_index, 0),
    accountId,
    oauthSourceKey,
    canUseDirectAccessToken: !!claims && !!accountId,
  };
}

function normalizeQuota(raw) {
  if (!raw || typeof raw !== 'object') {
    return {
      daily_token_cap: 0,
      daily_tokens_used: 0,
      daily_tokens_remaining: 0,
      total_tokens_used: 0,
      last_used_at_ms: 0,
      last_error_at_ms: 0,
      consecutive_errors: 0,
      cooldown_until_ms: 0,
      next_refresh_at_ms: 0,
    };
  }
  return {
    daily_token_cap: safeInt(raw.daily_token_cap, 0),
    daily_tokens_used: safeInt(raw.daily_tokens_used, 0),
    daily_tokens_remaining: safeInt(raw.daily_tokens_remaining, 0),
    total_tokens_used: safeInt(raw.total_tokens_used, 0),
    last_used_at_ms: safeInt(raw.last_used_at_ms, 0),
    last_error_at_ms: safeInt(raw.last_error_at_ms, 0),
    consecutive_errors: safeInt(raw.consecutive_errors, 0),
    cooldown_until_ms: safeInt(raw.cooldown_until_ms, 0),
    next_refresh_at_ms: safeInt(raw.next_refresh_at_ms, 0),
  };
}

function normalizeErrorState(raw) {
  if (!raw || typeof raw !== 'object') {
    return {
      status: 'healthy',
      status_message: '',
      reason_code: '',
      last_error_code: '',
      last_error_at_ms: 0,
      next_retry_at_ms: 0,
      retry_at_source: '',
      auto_disabled: false,
    };
  }
  return {
    status: safeString(raw.status) || 'healthy',
    status_message: safeString(raw.status_message),
    reason_code: safeString(raw.reason_code || raw.last_error_code),
    last_error_code: safeString(raw.last_error_code),
    last_error_at_ms: safeInt(raw.last_error_at_ms, 0),
    next_retry_at_ms: safeInt(raw.next_retry_at_ms, 0),
    retry_at_source: normalizeProviderRetrySource(raw.retry_at_source, {
      status: raw.status,
      reasonCode: raw.reason_code || raw.last_error_code,
      nextRetryAtMs: raw.next_retry_at_ms,
      quotaCooldownUntilMs: raw.cooldown_until_ms,
    }),
    auto_disabled: !!raw.auto_disabled,
  };
}

function safePercent(value) {
  return Math.max(0, Math.min(100, safeNumber(value, 0)));
}

function quotaRefreshIntervalMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_QUOTA_REFRESH_INTERVAL_MS, 0);
  return explicit > 0 ? explicit : DEFAULT_INTERVAL_MS;
}

function quotaRefreshSuccessIntervalMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_QUOTA_REFRESH_SUCCESS_INTERVAL_MS, 0);
  return explicit > 0 ? explicit : DEFAULT_SUCCESS_INTERVAL_MS;
}

function quotaRefreshHighWaterIntervalMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_QUOTA_REFRESH_HIGH_WATER_INTERVAL_MS, 0);
  return explicit > 0 ? explicit : DEFAULT_HIGH_WATER_INTERVAL_MS;
}

function quotaRefreshFailureBackoffMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_QUOTA_REFRESH_FAILURE_BACKOFF_MS, 0);
  return explicit > 0 ? explicit : DEFAULT_FAILURE_BACKOFF_MS;
}

function quotaRefreshMaxBackoffMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_QUOTA_REFRESH_MAX_FAILURE_BACKOFF_MS, 0);
  return explicit > 0 ? explicit : DEFAULT_MAX_FAILURE_BACKOFF_MS;
}

function basisPointsFromPercent(percent) {
  return Math.max(0, Math.min(QUOTA_BASIS_POINTS_CAP, Math.round(safePercent(percent) * 100)));
}

function quotaManagedErrorState(errorState) {
  const current = normalizeErrorState(errorState);
  const reason = safeString(current.reason_code || current.last_error_code).toLowerCase();
  return reason === 'blocked_quota'
    || reason === 'rate_limited'
    || safeString(current.retry_at_source).toLowerCase() === QUOTA_REFRESH_RETRY_SOURCE
    || safeString(current.status).toLowerCase() === 'blocked_quota'
    || safeString(current.status).toLowerCase() === 'rate_limited';
}

function clearQuotaManagedErrorState(errorState) {
  const current = normalizeErrorState(errorState);
  if (!quotaManagedErrorState(current)) return null;
  return {
    ...current,
    status: 'healthy',
    status_message: '',
    reason_code: '',
    last_error_code: '',
    last_error_at_ms: 0,
    next_retry_at_ms: 0,
    retry_at_source: '',
    auto_disabled: false,
  };
}

function resetAtMsFromWindow(window, baseNowMs) {
  const explicitResetAt = safeInt(window?.reset_at, 0);
  if (explicitResetAt > 0) {
    const resetAtMs = explicitResetAt > 1_000_000_000_000
      ? explicitResetAt
      : explicitResetAt * 1000;
    if (resetAtMs > baseNowMs) return resetAtMs;
  }
  const resetAfterSeconds = safeInt(window?.reset_after_seconds, 0);
  return resetAfterSeconds > 0 ? baseNowMs + (resetAfterSeconds * 1000) : 0;
}

function codexWindowLabel(window, prefix = '') {
  const seconds = safeInt(window?.limit_window_seconds, 0);
  let label = 'usage window';
  if (seconds >= 7 * 24 * 3600) label = '7-day window';
  else if (seconds >= 24 * 3600) label = '24-hour window';
  else if (seconds >= 5 * 3600) label = '5-hour window';
  else if (seconds >= 3600) label = '1-hour window';
  return prefix ? `${prefix} ${label}` : label;
}

function openAIWindowSnapshot({
  source,
  windowKey,
  window,
  limitReached,
  labelPrefix,
  baseNowMs,
} = {}) {
  const rawWindow = window && typeof window === 'object' ? window : null;
  if (!rawWindow) return null;
  const usedPercent = safePercent(rawWindow.used_percent);
  const usedBasisPoints = basisPointsFromPercent(usedPercent);
  const limitWindowSeconds = safeInt(rawWindow.limit_window_seconds, 0);
  const normalizedSource = safeString(source) || 'rate_limit';
  const normalizedWindowKey = safeString(windowKey) || 'window';
  return {
    key: `${normalizedSource}:${normalizedWindowKey}:${limitWindowSeconds || codexWindowLabel(rawWindow)}`,
    source: normalizedSource,
    window_key: normalizedWindowKey,
    label: codexWindowLabel(rawWindow, labelPrefix),
    limit_window_seconds: limitWindowSeconds,
    used_percent: usedPercent,
    used_basis_points: usedBasisPoints,
    remaining_basis_points: Math.max(0, QUOTA_BASIS_POINTS_CAP - usedBasisPoints),
    limited: !!limitReached || usedPercent >= 100,
    reset_at_ms: resetAtMsFromWindow(rawWindow, baseNowMs),
    updated_at_ms: baseNowMs,
  };
}

function supportedOpenAIQuotaAccount(account) {
  const provider = safeString(account?.provider).toLowerCase();
  const metadata = inferredOpenAIQuotaMetadata(account);
  if (!metadata.accountId) return false;
  if (provider === 'openai' || provider === 'codex') {
    return metadata.authIndex > 0 || metadata.canUseDirectAccessToken;
  }
  if (OPENAI_OAUTH_SOURCES.has(metadata.oauthSourceKey)) {
    return metadata.authIndex > 0 || metadata.canUseDirectAccessToken;
  }
  return metadata.canUseDirectAccessToken;
}

function defaultQuotaExecutorForAccount(account) {
  if (supportedOpenAIQuotaAccount(account)) {
    return executeOpenAIQuotaRefresh;
  }
  return null;
}

function resolveQuotaExecutor(account, options = {}) {
  if (typeof options.executorForAccount === 'function') {
    return options.executorForAccount(account, options);
  }
  const executors = options.executors;
  if (executors && typeof executors === 'object') {
    if (typeof executors[account?.account_key] === 'function') {
      return executors[account.account_key];
    }
    if (typeof executors[account?.provider] === 'function') {
      return executors[account.provider];
    }
  }
  return defaultQuotaExecutorForAccount(account, options);
}

function failureBackoffMs(failureCount, baseBackoffMs, maxBackoffMs) {
  const failures = Math.max(1, safeInt(failureCount, 1));
  const base = Math.max(100, safeInt(baseBackoffMs, DEFAULT_FAILURE_BACKOFF_MS));
  const max = Math.max(base, safeInt(maxBackoffMs, DEFAULT_MAX_FAILURE_BACKOFF_MS));
  const computed = base * Math.pow(2, Math.max(0, failures - 1));
  return Math.min(max, computed);
}

function extractOpenAIUsageFromManagementPayload(payload) {
  let parsedPayload = payload;
  if (typeof parsedPayload === 'string') {
    try {
      parsedPayload = JSON.parse(parsedPayload);
    } catch {
      const error = new Error('invalid management api-call payload for OpenAI usage');
      error.code = 'invalid_management_payload';
      throw error;
    }
  }

  if (!parsedPayload || typeof parsedPayload !== 'object') {
    const error = new Error('invalid management api-call payload for OpenAI usage');
    error.code = 'invalid_management_payload';
    throw error;
  }

  const objectPayload = parsedPayload;
  const statusCode = safeInt(objectPayload.status_code, 0);
  if (statusCode >= 400) {
    let detail = safeString(objectPayload.error || '');
    if (!detail && typeof objectPayload.body === 'string') {
      detail = safeString(objectPayload.body);
      try {
        const parsedBody = JSON.parse(objectPayload.body);
        detail = safeString(parsedBody?.detail || parsedBody?.error?.message || parsedBody?.error || detail);
      } catch {
        // keep raw body
      }
    }
    const error = new Error(detail || `OpenAI usage request failed (${statusCode})`);
    error.code = statusCode === 401 || statusCode === 403 ? 'management_auth_failed' : `management_status_${statusCode}`;
    error.http_status = statusCode;
    error.status_message = detail || error.message;
    throw error;
  }

  if (objectPayload.success === false) {
    const error = new Error(safeString(objectPayload.error) || 'OpenAI management api-call failed');
    error.code = 'management_call_failed';
    error.status_message = safeString(objectPayload.error || error.message);
    throw error;
  }

  if (typeof objectPayload.body === 'string') {
    try {
      const parsedBody = JSON.parse(objectPayload.body);
      if (parsedBody && typeof parsedBody === 'object' && parsedBody.rate_limit) {
        return parsedBody;
      }
    } catch {
      const error = new Error('invalid OpenAI usage payload');
      error.code = 'invalid_management_payload';
      throw error;
    }
  }

  const candidate = objectPayload.data && typeof objectPayload.data === 'object'
    ? objectPayload.data
    : objectPayload;
  if (candidate && typeof candidate === 'object' && candidate.rate_limit) {
    return candidate;
  }

  const error = new Error('unexpected OpenAI usage payload');
  error.code = 'invalid_management_payload';
  throw error;
}

function openAIWindowsFromUsage(usage, baseNowMs) {
  const windows = [];
  if (usage?.rate_limit?.primary_window) {
    windows.push(openAIWindowSnapshot({
      source: 'rate_limit',
      windowKey: 'primary',
      window: usage.rate_limit.primary_window,
      limitReached: usage.rate_limit.limit_reached,
      labelPrefix: 'primary',
      baseNowMs,
    }));
  }
  if (usage?.rate_limit?.secondary_window) {
    windows.push(openAIWindowSnapshot({
      source: 'rate_limit',
      windowKey: 'secondary',
      window: usage.rate_limit.secondary_window,
      limitReached: false,
      labelPrefix: 'secondary',
      baseNowMs,
    }));
  }
  if (usage?.code_review_rate_limit?.primary_window) {
    windows.push(openAIWindowSnapshot({
      source: 'code_review_rate_limit',
      windowKey: 'primary',
      window: usage.code_review_rate_limit.primary_window,
      limitReached: usage.code_review_rate_limit.limit_reached,
      labelPrefix: 'code-review primary',
      baseNowMs,
    }));
  }
  if (usage?.code_review_rate_limit?.secondary_window) {
    windows.push(openAIWindowSnapshot({
      source: 'code_review_rate_limit',
      windowKey: 'secondary',
      window: usage.code_review_rate_limit.secondary_window,
      limitReached: false,
      labelPrefix: 'code-review secondary',
      baseNowMs,
    }));
  }
  return windows.filter(Boolean);
}

function normalizeOpenAIQuotaRefreshResult(account, usage, options = {}) {
  const currentQuota = normalizeQuota(account?.quota);
  const currentErrorState = normalizeErrorState(account?.error_state);
  const refreshedAtMs = safeInt(options.refreshedAtMs, nowMs());
  const successIntervalMs = Math.max(250, safeInt(options.successIntervalMs, DEFAULT_SUCCESS_INTERVAL_MS));
  const highWaterIntervalMs = Math.max(250, safeInt(options.highWaterIntervalMs, DEFAULT_HIGH_WATER_INTERVAL_MS));
  const windows = openAIWindowsFromUsage(usage, refreshedAtMs);
  const mostConstrainedWindow = windows.reduce((best, candidate) => {
    if (!best) return candidate;
    if (candidate.used_percent !== best.used_percent) {
      return candidate.used_percent > best.used_percent ? candidate : best;
    }
    if (candidate.limited !== best.limited) {
      return candidate.limited ? candidate : best;
    }
    return best;
  }, null);
  const limitedWindows = windows.filter((window) => window.limited);
  const usedBasisPoints = basisPointsFromPercent(mostConstrainedWindow?.used_percent || 0);
  const nextRetryAtMs = limitedWindows
    .map((window) => safeInt(window.reset_at_ms, 0))
    .filter((value) => value > refreshedAtMs)
    .sort((lhs, rhs) => lhs - rhs)[0] || 0;

  const quota = {
    ...currentQuota,
    daily_token_cap: QUOTA_BASIS_POINTS_CAP,
    daily_tokens_used: usedBasisPoints,
    daily_tokens_remaining: Math.max(0, QUOTA_BASIS_POINTS_CAP - usedBasisPoints),
    cooldown_until_ms: nextRetryAtMs,
    usage_windows: windows,
  };

  const updates = {
    tier: safeString(usage?.plan_type) || safeString(account?.tier),
    quota,
    last_refresh_at_ms: refreshedAtMs,
  };
  if (safeString(options.accountId)) {
    updates.account_id = safeString(options.accountId);
  }
  if (safeString(options.oauthSourceKey)) {
    updates.oauth_source_key = safeString(options.oauthSourceKey);
  }

  if (limitedWindows.length > 0) {
    const statusMessage = safeString(
      `${mostConstrainedWindow?.label || 'usage window'} exhausted (${safePercent(mostConstrainedWindow?.used_percent).toFixed(1)}%)`
    );
    updates.error_state = {
      ...currentErrorState,
      status: 'blocked_quota',
      status_message: statusMessage,
      reason_code: 'blocked_quota',
      last_error_code: 'blocked_quota',
      last_error_at_ms: refreshedAtMs,
      next_retry_at_ms: nextRetryAtMs,
      retry_at_source: QUOTA_REFRESH_RETRY_SOURCE,
      auto_disabled: false,
    };
  } else {
    const clearedErrorState = clearQuotaManagedErrorState(currentErrorState);
    if (clearedErrorState) {
      updates.error_state = clearedErrorState;
    }
  }

  const nextRefreshAtMs = limitedWindows.length > 0 && nextRetryAtMs > refreshedAtMs
    ? nextRetryAtMs
    : refreshedAtMs + ((mostConstrainedWindow?.used_percent || 0) >= 90 ? highWaterIntervalMs : successIntervalMs);
  updates.quota.next_refresh_at_ms = nextRefreshAtMs;
  updates.refresh_state = {
    status: 'idle',
    last_attempt_at_ms: refreshedAtMs,
    last_success_at_ms: refreshedAtMs,
    next_refresh_at_ms: 0,
    failure_count: 0,
    last_error_code: '',
    last_error_message: '',
  };

  return {
    account_updates: updates,
    next_refresh_at_ms: nextRefreshAtMs,
  };
}

async function executeOpenAIQuotaRefresh(account, options = {}) {
  const metadata = inferredOpenAIQuotaMetadata(account);
  const authIndex = metadata.authIndex;
  const accountId = metadata.accountId;
  if (!accountId) {
    const error = new Error('missing auth_index or account_id');
    error.code = 'missing_quota_metadata';
    throw error;
  }

  let payload;
  if (authIndex > 0) {
    payload = await (options.callManagementApiFn || callManagementApi)({
      method: 'GET',
      url: OPENAI_USAGE_URL,
      authIndex,
      header: {
        Authorization: 'Bearer $TOKEN$',
        Accept: 'application/json',
        'ChatGPT-Account-Id': accountId,
      },
    }, {
      env: options.env,
      httpRequestFn: options.httpRequestFn,
    });
  } else if (metadata.canUseDirectAccessToken) {
    payload = await fetchOpenAIUsageDirect(account, {
      accountId,
      httpRequestFn: options.httpRequestFn,
    });
  } else {
    const error = new Error('missing auth_index or direct access token metadata');
    error.code = 'missing_quota_metadata';
    throw error;
  }

  const usage = extractOpenAIUsageFromManagementPayload(payload);
  const refreshedAtMs = safeInt(options.nowMs, nowMs());
  if (options.rustQuotaApplyBridge && typeof options.rustQuotaApplyBridge.applyOpenAIQuotaRefresh === 'function') {
    const applyResult = await options.rustQuotaApplyBridge.applyOpenAIQuotaRefresh({
      runtimeBaseDir: options.runtimeBaseDir,
      accountKey: account?.account_key,
      usage,
      nowMs: refreshedAtMs,
      refreshedAtMs,
      successIntervalMs: options.successIntervalMs,
      highWaterIntervalMs: options.highWaterIntervalMs,
      accountId,
      oauthSourceKey: metadata.oauthSourceKey,
    });
    if (applyResult?.ok && applyResult.used) {
      return {
        rust_applied: true,
        next_refresh_at_ms: safeInt(applyResult.next_refresh_at_ms, 0),
      };
    }
    if (applyResult && applyResult.fallback === false) {
      const error = new Error(applyResult.error_message || applyResult.error_code || 'rust_provider_quota_apply_failed');
      error.code = applyResult.error_code || 'rust_provider_quota_apply_failed';
      error.status_message = applyResult.error_message || '';
      throw error;
    }
  }

  return normalizeOpenAIQuotaRefreshResult(account, usage, {
    refreshedAtMs,
    successIntervalMs: options.successIntervalMs,
    highWaterIntervalMs: options.highWaterIntervalMs,
    accountId,
    oauthSourceKey: metadata.oauthSourceKey,
  });
}

async function fetchOpenAIUsageDirect(account, options = {}) {
  const accessToken = safeString(account?.api_key);
  const accountId = safeString(options.accountId);
  if (!accessToken || !accountId) {
    const error = new Error('missing direct access token or account_id');
    error.code = 'missing_quota_metadata';
    throw error;
  }

  const requestHeaders = {
    Authorization: `Bearer ${accessToken}`,
    Accept: 'application/json',
    'ChatGPT-Account-Id': accountId,
  };

  if (typeof options.httpRequestFn === 'function') {
    const response = await options.httpRequestFn({
      url: OPENAI_USAGE_URL,
      method: 'GET',
      headers: requestHeaders,
      body: '',
      timeoutMs: 15_000,
    });
    return {
      status_code: safeInt(response?.statusCode || response?.status, 0),
      body: typeof response?.bodyText === 'string'
        ? response.bodyText
        : (typeof response?.body === 'string' ? response.body : ''),
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);
  try {
    const response = await fetch(OPENAI_USAGE_URL, {
      method: 'GET',
      headers: requestHeaders,
      signal: controller.signal,
    });
    const body = await response.text();
    return {
      status_code: safeInt(response.status, 0),
      body,
    };
  } catch (error) {
    const directError = new Error(safeString(error?.message || error) || 'OpenAI usage request failed');
    directError.code = error?.name === 'AbortError' ? 'ETIMEDOUT' : safeString(error?.code || 'fetch_failed');
    directError.status_message = safeString(error?.message || error);
    throw directError;
  } finally {
    clearTimeout(timeout);
  }
}

function cleanupRefreshState(refreshStateByAccountKey, accountKeys) {
  if (!(refreshStateByAccountKey instanceof Map)) return;
  const active = new Set(accountKeys);
  for (const knownKey of Array.from(refreshStateByAccountKey.keys())) {
    if (!active.has(knownKey)) {
      refreshStateByAccountKey.delete(knownKey);
    }
  }
}

function shouldRefreshAccount(account, state, now) {
  if (!account || account.enabled === false) return false;
  const accountKey = safeString(account?.account_key);
  if (!accountKey) return false;
  const nextRefreshAtMs = safeInt(state?.next_refresh_at_ms, 0);
  return nextRefreshAtMs <= 0 || nextRefreshAtMs <= now;
}

async function executeAccountQuotaRefresh(runtimeBaseDir, account, options = {}) {
  const accountKey = safeString(account?.account_key);
  if (!runtimeBaseDir || !accountKey) {
    return { ok: false, account_key: accountKey, error_code: 'invalid_account' };
  }
  const executor = resolveQuotaExecutor(account, options);
  if (!executor) {
    return { ok: false, account_key: accountKey, error_code: 'missing_quota_executor' };
  }

  try {
    const result = await executor(account, {
      env: options.env,
      runtimeBaseDir,
      httpRequestFn: options.httpRequestFn,
      callManagementApiFn: options.callManagementApiFn,
      rustQuotaApplyBridge: options.rustQuotaApplyBridge,
      nowMs: options.nowFn(),
      successIntervalMs: options.successIntervalMs,
      highWaterIntervalMs: options.highWaterIntervalMs,
    });
    if (result?.rust_applied) {
      invalidateProviderKeyCache();
      return {
        ok: true,
        account_key: accountKey,
        error_code: '',
        next_refresh_at_ms: safeInt(result.next_refresh_at_ms, 0),
      };
    }
    const saved = updateProviderKey(runtimeBaseDir, accountKey, result.account_updates || {});
    return {
      ok: !!saved.ok,
      account_key: accountKey,
      error_code: saved.ok ? '' : (saved.error || 'save_failed'),
      next_refresh_at_ms: safeInt(result.next_refresh_at_ms, 0),
    };
  } catch (error) {
    return {
      ok: false,
      account_key: accountKey,
      error_code: safeString(error?.code || 'quota_refresh_failed'),
      error_message: safeString(error?.status_message || error?.message || error),
    };
  }
}

export async function runProviderKeyQuotaRefreshConductorTick({
  runtimeBaseDir,
  executorForAccount,
  executors,
  inFlight = new Set(),
  refreshStateByAccountKey = new Map(),
  logger = console,
  env = process.env,
  httpRequestFn,
  callManagementApiFn,
  rustQuotaApplyBridge,
  nowFn = nowMs,
  successIntervalMs = quotaRefreshSuccessIntervalMsFromEnv(env),
  highWaterIntervalMs = quotaRefreshHighWaterIntervalMsFromEnv(env),
  baseFailureBackoffMs = quotaRefreshFailureBackoffMsFromEnv(env),
  maxFailureBackoffMs = quotaRefreshMaxBackoffMsFromEnv(env),
} = {}) {
  const runtime = safeString(runtimeBaseDir);
  if (!runtime) {
    return {
      scheduled: 0,
      refreshed: 0,
      failed: 0,
      skipped: 0,
    };
  }

  const accounts = listProviderKeysFull(runtime).filter((account) => {
    return typeof resolveQuotaExecutor(account, { executorForAccount, executors }) === 'function';
  });
  const resolvedRustQuotaApplyBridge = rustQuotaApplyBridge || createRustProviderQuotaApplyBridge({
    env,
    logger,
  });
  cleanupRefreshState(refreshStateByAccountKey, accounts.map((account) => safeString(account.account_key)));

  const now = nowFn();
  let rustPlanUsed = false;
  let dueAccounts = [];
  if (resolvedRustQuotaApplyBridge
    && typeof resolvedRustQuotaApplyBridge.planOpenAIQuotaRefresh === 'function') {
    const plan = await resolvedRustQuotaApplyBridge.planOpenAIQuotaRefresh({
      runtimeBaseDir: runtime,
      nowMs: now,
      inFlightAccountKeys: Array.from(inFlight),
    });
    if (plan?.ok && plan.used) {
      rustPlanUsed = true;
      const dueAccountKeys = new Set((plan.account_keys || []).map(safeString).filter(Boolean));
      dueAccounts = accounts.filter((account) => {
        const accountKey = safeString(account?.account_key);
        return accountKey && dueAccountKeys.has(accountKey) && !inFlight.has(accountKey);
      });
    } else if (plan && plan.fallback === false) {
      return {
        scheduled: 0,
        refreshed: 0,
        failed: 0,
        skipped: accounts.length,
        rust_plan_used: false,
        error_code: plan.error_code || 'rust_provider_quota_plan_failed',
      };
    }
  }
  if (!rustPlanUsed) {
    dueAccounts = accounts.filter((account) => {
      const accountKey = safeString(account?.account_key);
      if (!accountKey || inFlight.has(accountKey)) return false;
      return shouldRefreshAccount(account, refreshStateByAccountKey.get(accountKey), now);
    });
  }

  let refreshed = 0;
  let failed = 0;
  let rustFailuresRecorded = 0;
  let skipped = accounts.length - dueAccounts.length;
  for (const account of dueAccounts) {
    const accountKey = safeString(account.account_key);
    inFlight.add(accountKey);
    try {
      const result = await executeAccountQuotaRefresh(runtime, account, {
        executorForAccount,
        executors,
        logger,
        env,
        httpRequestFn,
        callManagementApiFn,
        rustQuotaApplyBridge: resolvedRustQuotaApplyBridge,
        nowFn,
        successIntervalMs,
        highWaterIntervalMs,
      });
      if (result.ok) {
        refreshed += 1;
        refreshStateByAccountKey.set(accountKey, {
          failure_count: 0,
          next_refresh_at_ms: safeInt(result.next_refresh_at_ms, 0) || (nowFn() + successIntervalMs),
        });
      } else {
        failed += 1;
        const previousState = refreshStateByAccountKey.get(accountKey) || { failure_count: 0, next_refresh_at_ms: 0 };
        let failureCount = safeInt(previousState.failure_count, 0) + 1;
        let nextRefreshAtMs = 0;
        if (resolvedRustQuotaApplyBridge
          && typeof resolvedRustQuotaApplyBridge.recordOpenAIQuotaRefreshFailure === 'function') {
          const failedAtMs = nowFn();
          const failureRecord = await resolvedRustQuotaApplyBridge.recordOpenAIQuotaRefreshFailure({
            runtimeBaseDir: runtime,
            accountKey,
            failedAtMs,
            baseFailureBackoffMs,
            maxFailureBackoffMs,
            errorCode: result.error_code || 'quota_refresh_failed',
            errorMessage: result.error_message || '',
          });
          if (failureRecord?.ok && failureRecord.used) {
            rustFailuresRecorded += 1;
            failureCount = safeInt(failureRecord.failure_count, failureCount);
            nextRefreshAtMs = safeInt(failureRecord.next_refresh_at_ms, 0);
            invalidateProviderKeyCache();
          } else if (failureRecord && failureRecord.fallback === false) {
            if (logger?.warn) {
              logger.warn(`[provider_key_quota_refresh_conductor] rust quota failure record failed for ${accountKey}: ${failureRecord.error_code || 'rust_provider_quota_failure_failed'} ${failureRecord.error_message || ''}`.trim());
            }
          }
        }
        if (nextRefreshAtMs <= 0) {
          nextRefreshAtMs = nowFn() + failureBackoffMs(
            failureCount,
            baseFailureBackoffMs,
            maxFailureBackoffMs
          );
        }
        refreshStateByAccountKey.set(accountKey, {
          failure_count: failureCount,
          next_refresh_at_ms: nextRefreshAtMs,
        });
        if (logger?.warn) {
          logger.warn(`[provider_key_quota_refresh_conductor] quota refresh failed for ${accountKey}: ${result.error_code || 'quota_refresh_failed'} ${result.error_message || ''}`.trim());
        }
      }
    } finally {
      inFlight.delete(accountKey);
    }
  }

  return {
    scheduled: dueAccounts.length,
    refreshed,
    failed,
    skipped,
    rust_plan_used: rustPlanUsed,
    rust_failures_recorded: rustFailuresRecorded,
  };
}

export function startProviderKeyQuotaRefreshConductor({
  runtimeBaseDir,
  intervalMs,
  executorForAccount,
  executors,
  logger = console,
  env = process.env,
  httpRequestFn,
  callManagementApiFn,
  rustQuotaApplyBridge,
  nowFn = nowMs,
  successIntervalMs,
  highWaterIntervalMs,
  baseFailureBackoffMs,
  maxFailureBackoffMs,
} = {}) {
  const runtime = safeString(runtimeBaseDir);
  if (!runtime) return () => {};
  if (safeString(env.HUB_PROVIDER_KEY_QUOTA_REFRESH_ENABLED).toLowerCase() === 'false') {
    return () => {};
  }

  const resolvedIntervalMs = Math.max(
    250,
    safeInt(intervalMs, quotaRefreshIntervalMsFromEnv(env)) || quotaRefreshIntervalMsFromEnv(env)
  );
  const resolvedSuccessIntervalMs = Math.max(
    250,
    safeInt(successIntervalMs, quotaRefreshSuccessIntervalMsFromEnv(env)) || quotaRefreshSuccessIntervalMsFromEnv(env)
  );
  const resolvedHighWaterIntervalMs = Math.max(
    250,
    safeInt(highWaterIntervalMs, quotaRefreshHighWaterIntervalMsFromEnv(env)) || quotaRefreshHighWaterIntervalMsFromEnv(env)
  );
  const resolvedBaseBackoffMs = Math.max(
    250,
    safeInt(baseFailureBackoffMs, quotaRefreshFailureBackoffMsFromEnv(env)) || quotaRefreshFailureBackoffMsFromEnv(env)
  );
  const resolvedMaxBackoffMs = Math.max(
    resolvedBaseBackoffMs,
    safeInt(maxFailureBackoffMs, quotaRefreshMaxBackoffMsFromEnv(env)) || quotaRefreshMaxBackoffMsFromEnv(env)
  );

  let stopped = false;
  let tickRunning = false;
  const inFlight = new Set();
  const refreshStateByAccountKey = new Map();

  const tick = async () => {
    if (stopped || tickRunning) return;
    tickRunning = true;
    try {
      await runProviderKeyQuotaRefreshConductorTick({
        runtimeBaseDir: runtime,
        executorForAccount,
        executors,
        inFlight,
        refreshStateByAccountKey,
        logger,
        env,
        httpRequestFn,
        callManagementApiFn,
        rustQuotaApplyBridge,
        nowFn,
        successIntervalMs: resolvedSuccessIntervalMs,
        highWaterIntervalMs: resolvedHighWaterIntervalMs,
        baseFailureBackoffMs: resolvedBaseBackoffMs,
        maxFailureBackoffMs: resolvedMaxBackoffMs,
      });
    } catch (error) {
      if (logger?.warn) {
        logger.warn(`[provider_key_quota_refresh_conductor] tick failed: ${String(error?.message || error)}`);
      }
    } finally {
      tickRunning = false;
    }
  };

  const startupTimer = setTimeout(() => {
    void tick();
  }, 0);
  startupTimer.unref?.();

  const intervalTimer = setInterval(() => {
    void tick();
  }, resolvedIntervalMs);
  intervalTimer.unref?.();

  return () => {
    stopped = true;
    clearTimeout(startupTimer);
    clearInterval(intervalTimer);
  };
}
