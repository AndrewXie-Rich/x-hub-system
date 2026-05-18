import {
  listProviderKeysFull,
  loadProviderKeyStore,
  normalizeProviderRetrySource,
  updateProviderKey,
} from './provider_key_store.js';
import { defaultRefreshExecutorForAccount } from './provider_key_refresh_executors.js';
import { nowMs } from './util.js';

const DEFAULT_INTERVAL_MS = 30_000;
const DEFAULT_REFRESH_LEAD_MS = 5 * 60 * 1000;
const DEFAULT_FAILURE_BACKOFF_MS = 60 * 1000;
const DEFAULT_MAX_FAILURE_BACKOFF_MS = 30 * 60 * 1000;
const UNSUPPORTED_REFRESH_SCHEMA_CODE = 'unsupported_refresh_schema';
const UNSUPPORTED_REFRESH_RETRY_SOURCE = 'manual';
const REFRESH_RETRY_SOURCE = 'refresh';
const MANUAL_RETRY_SOURCE = 'manual';

function safeString(value) {
  return String(value ?? '').trim();
}

function safeInt(value, fallback = 0) {
  const number = Number(value || 0);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

function refreshIntervalMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_REFRESH_INTERVAL_MS, 0);
  return explicit > 0 ? Math.max(100, explicit) : DEFAULT_INTERVAL_MS;
}

function refreshLeadMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_REFRESH_LEAD_MS, 0);
  return explicit > 0 ? explicit : DEFAULT_REFRESH_LEAD_MS;
}

function refreshFailureBackoffMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_REFRESH_FAILURE_BACKOFF_MS, 0);
  return explicit > 0 ? explicit : DEFAULT_FAILURE_BACKOFF_MS;
}

function refreshMaxBackoffMsFromEnv(env = process.env) {
  const explicit = safeInt(env.HUB_PROVIDER_KEY_REFRESH_MAX_BACKOFF_MS, 0);
  return explicit > 0 ? explicit : DEFAULT_MAX_FAILURE_BACKOFF_MS;
}

function normalizeRefreshState(raw) {
  if (!raw || typeof raw !== 'object') {
    return {
      status: 'idle',
      last_attempt_at_ms: 0,
      last_success_at_ms: 0,
      next_refresh_at_ms: 0,
      failure_count: 0,
      last_error_code: '',
      last_error_message: '',
    };
  }
  const status = safeString(raw.status).toLowerCase();
  return {
    status: status || 'idle',
    last_attempt_at_ms: safeInt(raw.last_attempt_at_ms, 0),
    last_success_at_ms: safeInt(raw.last_success_at_ms, 0),
    next_refresh_at_ms: safeInt(raw.next_refresh_at_ms, 0),
    failure_count: safeInt(raw.failure_count, 0),
    last_error_code: safeString(raw.last_error_code),
    last_error_message: safeString(raw.last_error_message),
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
    }),
    auto_disabled: !!raw.auto_disabled,
  };
}

function isRefreshManagedReasonCode(code) {
  const normalized = safeString(code).toLowerCase();
  if (!normalized) return false;
  if (normalized === UNSUPPORTED_REFRESH_SCHEMA_CODE) return true;
  if (normalized.startsWith('refresh_')) return true;
  return [
    'missing_refresh_token',
    'missing_oauth_client',
    'missing_oauth_client_id',
    'missing_oauth_client_secret',
    'missing_oauth_client_credentials',
    'invalid_grant',
    'invalid_client',
    'unauthorized_client',
    'access_denied',
    'token_expired',
    'refresh_token_reused',
  ].includes(normalized);
}

function canOverwriteRefreshErrorState(errorState) {
  const current = normalizeErrorState(errorState);
  const currentCode = safeString(current.reason_code || current.last_error_code);
  if (isRefreshManagedReasonCode(currentCode)) return true;
  if ([REFRESH_RETRY_SOURCE, MANUAL_RETRY_SOURCE, UNSUPPORTED_REFRESH_RETRY_SOURCE].includes(
    safeString(current.retry_at_source)
  )) {
    return true;
  }
  if (current.auto_disabled) return false;
  return [
    'healthy',
    'degraded',
    'blocked_config',
    'blocked_auth',
    'blocked_network',
    'blocked_provider',
  ].includes(safeString(current.status));
}

function shouldClearRefreshErrorState(errorState) {
  const current = normalizeErrorState(errorState);
  const currentCode = safeString(current.reason_code || current.last_error_code);
  if (isRefreshManagedReasonCode(currentCode)) return true;
  return [REFRESH_RETRY_SOURCE, MANUAL_RETRY_SOURCE, UNSUPPORTED_REFRESH_RETRY_SOURCE].includes(
    safeString(current.retry_at_source)
  );
}

function isRefreshConfigErrorCode(code) {
  return [
    'missing_refresh_token',
    'missing_oauth_client',
    'missing_oauth_client_id',
    'missing_oauth_client_secret',
    'missing_oauth_client_credentials',
    'refresh_invalid_payload',
    'invalid_refresh_url',
  ].includes(safeString(code).toLowerCase());
}

function isRefreshAuthErrorCode(code, statusCode = 0) {
  const normalized = safeString(code).toLowerCase();
  if (statusCode === 401 || statusCode === 403) return true;
  return [
    'token_expired',
    'invalid_grant',
    'invalid_client',
    'unauthorized_client',
    'access_denied',
    'refresh_token_reused',
    'refresh_http_401',
    'refresh_http_403',
  ].includes(normalized);
}

function isRefreshNetworkErrorCode(code, message = '') {
  const normalized = safeString(code).toLowerCase();
  if ([
    'refresh_timeout',
    'etimedout',
    'econnrefused',
    'econnreset',
    'ehostunreach',
    'enotfound',
    'eai_again',
    'network_error',
    'fetch_failed',
  ].includes(normalized)) {
    return true;
  }
  const normalizedMessage = safeString(message).toLowerCase();
  return normalizedMessage.includes('timed out')
    || normalizedMessage.includes('network is unreachable')
    || normalizedMessage.includes('network unreachable')
    || normalizedMessage.includes('dns')
    || normalizedMessage.includes('could not resolve');
}

function buildRefreshFailureErrorState(account, failedAtMs, nextRefreshAtMs, error) {
  const currentErrorState = normalizeErrorState(account?.error_state);
  if (!canOverwriteRefreshErrorState(currentErrorState)) {
    return null;
  }

  const errorCode = safeString(
    error?.error_code
    || error?.code
    || error?.name
    || 'refresh_failed'
  );
  const errorMessage = safeString(
    error?.status_message
    || error?.message
    || error
  );
  const httpStatus = safeInt(error?.http_status, 0);
  const explicitNextRetryAtMs = safeInt(error?.next_retry_at_ms || error?.nextRetryAtMs, 0);
  const explicitRetrySource = normalizeProviderRetrySource(
    error?.retry_at_source || error?.retryAtSource,
    {
      status: currentErrorState.status,
      reasonCode: errorCode,
      nextRetryAtMs: explicitNextRetryAtMs,
    }
  );

  let status = 'blocked_provider';
  let retryAtMs = nextRefreshAtMs;
  let retryAtSource = explicitRetrySource || REFRESH_RETRY_SOURCE;
  if (isRefreshConfigErrorCode(errorCode)) {
    status = 'blocked_config';
    retryAtMs = 0;
    retryAtSource = MANUAL_RETRY_SOURCE;
  } else if (isRefreshAuthErrorCode(errorCode, httpStatus)) {
    status = 'blocked_auth';
    retryAtSource = explicitRetrySource
      || (safeString(errorCode).toLowerCase() === 'token_expired' ? REFRESH_RETRY_SOURCE : MANUAL_RETRY_SOURCE);
    retryAtMs = retryAtSource === REFRESH_RETRY_SOURCE
      ? (explicitNextRetryAtMs || nextRefreshAtMs)
      : explicitNextRetryAtMs;
  } else if (isRefreshNetworkErrorCode(errorCode, errorMessage)) {
    status = 'blocked_network';
    retryAtMs = explicitNextRetryAtMs || nextRefreshAtMs;
    retryAtSource = explicitRetrySource || REFRESH_RETRY_SOURCE;
  } else if (explicitNextRetryAtMs > 0) {
    retryAtMs = explicitNextRetryAtMs;
  }

  return {
    ...currentErrorState,
    status,
    status_message: errorMessage,
    reason_code: errorCode,
    last_error_code: errorCode,
    last_error_at_ms: failedAtMs,
    next_retry_at_ms: retryAtMs,
    retry_at_source: retryAtSource,
    auto_disabled: !!currentErrorState.auto_disabled,
  };
}

function hasRefreshExecutor(account, options) {
  return typeof resolveRefreshExecutor(account, options) === 'function';
}

function resolveRefreshExecutor(account, options = {}) {
  if (typeof options.executorForAccount === 'function') {
    return options.executorForAccount;
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
  return defaultRefreshExecutorForAccount(account, options);
}

function isOAuthRefreshAccount(account) {
  return !!account
    && account.enabled !== false
    && safeString(account.auth_type).toLowerCase() === 'oauth'
    && !!safeString(account.refresh_token);
}

function refreshSchemaDescriptor(account) {
  const provider = safeString(account?.provider).toLowerCase() || 'unknown';
  const oauthSourceKey = safeString(account?.oauth_source_key).toLowerCase() || provider;
  return `provider=${provider} oauth_source_key=${oauthSourceKey}`;
}

function unsupportedRefreshStatus(account, now) {
  const hasAPIKey = !!safeString(account?.api_key);
  const expiresAtMs = safeInt(account?.expires_at_ms, 0);
  if (!hasAPIKey) return 'blocked_config';
  if (expiresAtMs > 0 && expiresAtMs <= now) return 'blocked_config';
  return 'degraded';
}

function canOverwriteUnsupportedRefreshErrorState(errorState) {
  const current = normalizeErrorState(errorState);
  const currentCode = safeString(current.reason_code || current.last_error_code);
  if (currentCode === UNSUPPORTED_REFRESH_SCHEMA_CODE) return true;
  if (current.auto_disabled) return false;
  return ['healthy', 'degraded', 'blocked_config'].includes(safeString(current.status));
}

function buildUnsupportedRefreshBlockerUpdates(account, now) {
  if (!isOAuthRefreshAccount(account)) return null;

  const detail = refreshSchemaDescriptor(account);
  const status = unsupportedRefreshStatus(account, now);
  const message = `oauth refresh schema is not supported by Hub runtime (${detail})`;
  const currentErrorState = normalizeErrorState(account?.error_state);
  const currentRefreshState = normalizeRefreshState(account?.refresh_state);

  const updates = {};
  const refreshNeedsUpdate = safeString(currentRefreshState.last_error_code) !== UNSUPPORTED_REFRESH_SCHEMA_CODE
    || safeString(currentRefreshState.last_error_message) !== message
    || safeString(currentRefreshState.status) !== 'idle'
    || safeInt(currentRefreshState.next_refresh_at_ms, 0) !== 0;
  if (refreshNeedsUpdate) {
    updates.refresh_state = {
      ...currentRefreshState,
      status: 'idle',
      next_refresh_at_ms: 0,
      last_error_code: UNSUPPORTED_REFRESH_SCHEMA_CODE,
      last_error_message: message,
    };
  }

  if (canOverwriteUnsupportedRefreshErrorState(currentErrorState)) {
    const errorNeedsUpdate = safeString(currentErrorState.status) !== status
      || safeString(currentErrorState.reason_code) !== UNSUPPORTED_REFRESH_SCHEMA_CODE
      || safeString(currentErrorState.last_error_code) !== UNSUPPORTED_REFRESH_SCHEMA_CODE
      || safeString(currentErrorState.status_message) !== message
      || safeString(currentErrorState.retry_at_source) !== UNSUPPORTED_REFRESH_RETRY_SOURCE
      || safeInt(currentErrorState.next_retry_at_ms, 0) !== 0;
    if (errorNeedsUpdate) {
      updates.error_state = {
        ...currentErrorState,
        status,
        status_message: message,
        reason_code: UNSUPPORTED_REFRESH_SCHEMA_CODE,
        last_error_code: UNSUPPORTED_REFRESH_SCHEMA_CODE,
        last_error_at_ms: now,
        next_retry_at_ms: 0,
        retry_at_source: normalizeProviderRetrySource(UNSUPPORTED_REFRESH_RETRY_SOURCE, {
          status,
          reasonCode: UNSUPPORTED_REFRESH_SCHEMA_CODE,
        }),
        auto_disabled: false,
      };
    }
  }

  return Object.keys(updates).length > 0 ? updates : null;
}

function buildClearUnsupportedRefreshBlockerUpdates(account) {
  const currentErrorState = normalizeErrorState(account?.error_state);
  const currentRefreshState = normalizeRefreshState(account?.refresh_state);
  const updates = {};

  const refreshHasUnsupportedBlocker = safeString(currentRefreshState.last_error_code) === UNSUPPORTED_REFRESH_SCHEMA_CODE;
  if (refreshHasUnsupportedBlocker) {
    updates.refresh_state = {
      ...currentRefreshState,
      last_error_code: '',
      last_error_message: '',
    };
  }

  const errorHasUnsupportedBlocker = safeString(currentErrorState.reason_code || currentErrorState.last_error_code) === UNSUPPORTED_REFRESH_SCHEMA_CODE
    && ['healthy', 'degraded', 'blocked_config'].includes(safeString(currentErrorState.status))
    && !currentErrorState.auto_disabled;
  if (errorHasUnsupportedBlocker) {
    updates.error_state = {
      ...currentErrorState,
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

  return Object.keys(updates).length > 0 ? updates : null;
}

function reconcileRefreshSupportState(runtimeBaseDir, accounts, options = {}) {
  const runtime = safeString(runtimeBaseDir);
  if (!runtime || !Array.isArray(accounts) || accounts.length === 0) return 0;

  const now = options.nowFn();
  let updated = 0;
  for (const account of accounts) {
    const hasExecutor = typeof resolveRefreshExecutor(account, options) === 'function';
    const patch = isOAuthRefreshAccount(account) && !hasExecutor
      ? buildUnsupportedRefreshBlockerUpdates(account, now)
      : buildClearUnsupportedRefreshBlockerUpdates(account);
    if (!patch) continue;
    const result = updateProviderKey(runtime, safeString(account.account_key), patch);
    if (result.ok) {
      updated += 1;
    } else if (options.logger?.warn) {
      options.logger.warn(`[provider_key_runtime_conductor] failed to reconcile refresh support state for ${safeString(account.account_key)}: ${result.error || 'save_failed'}`);
    }
  }
  return updated;
}

function shouldRefreshAccount(account, now, refreshLeadMs) {
  if (!account || account.enabled === false) return false;
  if (!safeString(account.refresh_token)) return false;

  const refreshState = normalizeRefreshState(account.refresh_state);
  if (refreshState.status === 'pending' || refreshState.status === 'refreshing') {
    return false;
  }
  if ((refreshState.status === 'failed' || refreshState.status === 'cooldown')
      && refreshState.next_refresh_at_ms > now) {
    return false;
  }

  const expiresAtMs = safeInt(account.expires_at_ms, 0);
  if (!safeString(account.api_key)) {
    return true;
  }
  if (expiresAtMs > 0) {
    return expiresAtMs <= now + Math.max(0, safeInt(refreshLeadMs, DEFAULT_REFRESH_LEAD_MS));
  }
  return false;
}

function failureBackoffMs(failureCount, baseBackoffMs, maxBackoffMs) {
  const failures = Math.max(1, safeInt(failureCount, 1));
  const base = Math.max(100, safeInt(baseBackoffMs, DEFAULT_FAILURE_BACKOFF_MS));
  const max = Math.max(base, safeInt(maxBackoffMs, DEFAULT_MAX_FAILURE_BACKOFF_MS));
  const computed = base * Math.pow(2, Math.max(0, failures - 1));
  return Math.min(max, computed);
}

function currentAccountSnapshot(runtimeBaseDir, accountKey) {
  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  for (const providerData of Object.values(store.providers || {})) {
    const account = Array.isArray(providerData?.accounts)
      ? providerData.accounts.find((entry) => entry?.account_key === accountKey)
      : null;
    if (account) return account;
  }
  return null;
}

function buildSuccessUpdates(account, attemptAtMs, refreshedAtMs, result) {
  const accountUpdates = result?.account_updates && typeof result.account_updates === 'object'
    ? result.account_updates
    : {};
  const explicitLastRefreshAtMs = Number(
    accountUpdates.last_refresh_at_ms
    ?? result?.last_refresh_at_ms
    ?? refreshedAtMs
  );
  const nextRefreshAtMs = safeInt(
    result?.next_refresh_at_ms
      || (safeInt(result?.next_refresh_after_ms, 0) > 0
        ? refreshedAtMs + safeInt(result.next_refresh_after_ms, 0)
        : 0),
    0
  );
  const updates = {
    ...accountUpdates,
    last_refresh_at_ms: Number.isFinite(explicitLastRefreshAtMs) && explicitLastRefreshAtMs > 0
      ? Math.floor(explicitLastRefreshAtMs)
      : refreshedAtMs,
    refresh_state: {
      ...(account?.refresh_state || {}),
      status: nextRefreshAtMs > refreshedAtMs ? 'cooldown' : 'idle',
      last_attempt_at_ms: attemptAtMs,
      last_success_at_ms: refreshedAtMs,
      next_refresh_at_ms: nextRefreshAtMs,
      failure_count: 0,
      last_error_code: '',
      last_error_message: '',
    },
  };
  if (shouldClearRefreshErrorState(account?.error_state)) {
    updates.error_state = {
      ...normalizeErrorState(account?.error_state),
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
  return updates;
}

function buildFailureUpdates(account, attemptAtMs, failedAtMs, error, options) {
  const refreshState = normalizeRefreshState(account?.refresh_state);
  const failureCount = refreshState.failure_count + 1;
  const nextRefreshAtMs = failedAtMs + failureBackoffMs(
    failureCount,
    options.baseFailureBackoffMs,
    options.maxFailureBackoffMs,
  );
  const errorCode = safeString(
    error?.error_code
    || error?.code
    || error?.name
    || 'refresh_failed'
  );
  const errorMessage = safeString(
    error?.status_message
    || error?.message
    || error
  );
  const updates = {
    refresh_state: {
      ...refreshState,
      status: 'failed',
      last_attempt_at_ms: attemptAtMs,
      last_success_at_ms: refreshState.last_success_at_ms || safeInt(account?.last_refresh_at_ms, 0),
      next_refresh_at_ms: nextRefreshAtMs,
      failure_count: failureCount,
      last_error_code: errorCode,
      last_error_message: errorMessage,
    },
  };
  const errorState = buildRefreshFailureErrorState(
    account,
    failedAtMs,
    nextRefreshAtMs,
    error,
  );
  if (errorState) {
    updates.error_state = errorState;
  }
  return updates;
}

async function executeAccountRefresh(runtimeBaseDir, account, options = {}) {
  const accountKey = safeString(account?.account_key);
  if (!runtimeBaseDir || !accountKey) {
    return { ok: false, account_key: accountKey, error_code: 'invalid_account' };
  }
  const executor = resolveRefreshExecutor(account, options);
  if (!executor) {
    return { ok: false, account_key: accountKey, error_code: 'missing_refresh_executor' };
  }

  const attemptAtMs = options.nowFn();
  const markRefreshing = updateProviderKey(runtimeBaseDir, accountKey, {
    refresh_state: {
      ...(account.refresh_state || {}),
      status: 'refreshing',
      last_attempt_at_ms: attemptAtMs,
      next_refresh_at_ms: 0,
    },
  });
  if (!markRefreshing.ok) {
    return { ok: false, account_key: accountKey, error_code: markRefreshing.error || 'save_failed' };
  }

  try {
    const result = await executor(
      currentAccountSnapshot(runtimeBaseDir, accountKey) || account,
      {
        runtimeBaseDir,
        nowMs: attemptAtMs,
        env: options.env,
        logger: options.logger,
        httpRequestFn: options.httpRequestFn,
      }
    );
    if (result && result.ok === false) {
      throw Object.assign(
        new Error(safeString(result.error || result.status_message || 'refresh_failed')),
        {
          code: safeString(result.error_code || result.code || 'refresh_failed'),
          status_message: safeString(result.status_message || result.error || ''),
        }
      );
    }
    const refreshedAtMs = options.nowFn();
    const successUpdates = buildSuccessUpdates(
      currentAccountSnapshot(runtimeBaseDir, accountKey) || account,
      attemptAtMs,
      refreshedAtMs,
      result,
    );
    const saved = updateProviderKey(runtimeBaseDir, accountKey, successUpdates);
    return {
      ok: !!saved.ok,
      account_key: accountKey,
      error_code: saved.ok ? '' : (saved.error || 'save_failed'),
    };
  } catch (error) {
    const failedAtMs = options.nowFn();
    const failureUpdates = buildFailureUpdates(
      currentAccountSnapshot(runtimeBaseDir, accountKey) || account,
      attemptAtMs,
      failedAtMs,
      error,
      options,
    );
    const saved = updateProviderKey(runtimeBaseDir, accountKey, failureUpdates);
    if (!saved.ok && options.logger?.warn) {
      options.logger.warn(`[provider_key_runtime_conductor] failed to persist refresh failure for ${accountKey}: ${saved.error}`);
    }
    return {
      ok: false,
      account_key: accountKey,
      error_code: safeString(error?.code || error?.error_code || 'refresh_failed'),
    };
  }
}

export async function runProviderKeyRuntimeConductorTick({
  runtimeBaseDir,
  refreshLeadMs = DEFAULT_REFRESH_LEAD_MS,
  executorForAccount,
  executors,
  inFlight = new Set(),
  logger = console,
  env = process.env,
  httpRequestFn,
  nowFn = nowMs,
  baseFailureBackoffMs = DEFAULT_FAILURE_BACKOFF_MS,
  maxFailureBackoffMs = DEFAULT_MAX_FAILURE_BACKOFF_MS,
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

  const accounts = listProviderKeysFull(runtime);
  reconcileRefreshSupportState(runtime, accounts, {
    executorForAccount,
    executors,
    logger,
    env,
    httpRequestFn,
    nowFn,
  });
  const dueAccounts = accounts.filter((account) => {
    const accountKey = safeString(account?.account_key);
    if (!accountKey || inFlight.has(accountKey)) return false;
    if (!hasRefreshExecutor(account, { executorForAccount, executors })) return false;
    return shouldRefreshAccount(account, nowFn(), refreshLeadMs);
  });

  let refreshed = 0;
  let failed = 0;
  let skipped = accounts.length - dueAccounts.length;
  for (const account of dueAccounts) {
    const accountKey = safeString(account.account_key);
    inFlight.add(accountKey);
    try {
      const result = await executeAccountRefresh(runtime, account, {
        executorForAccount,
        executors,
        logger,
        env,
        httpRequestFn,
        nowFn,
        baseFailureBackoffMs,
        maxFailureBackoffMs,
      });
      if (result.ok) refreshed += 1;
      else failed += 1;
    } catch (error) {
      failed += 1;
      if (logger?.warn) {
        logger.warn(`[provider_key_runtime_conductor] unexpected refresh error for ${accountKey}: ${String(error?.message || error)}`);
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
  };
}

export function startProviderKeyRuntimeConductor({
  runtimeBaseDir,
  intervalMs,
  refreshLeadMs,
  executorForAccount,
  executors,
  logger = console,
  env = process.env,
  httpRequestFn,
  nowFn = nowMs,
  baseFailureBackoffMs,
  maxFailureBackoffMs,
} = {}) {
  const runtime = safeString(runtimeBaseDir);
  if (!runtime) return () => {};
  if (safeString(env.HUB_PROVIDER_KEY_REFRESH_ENABLED).toLowerCase() === 'false') {
    return () => {};
  }

  const resolvedIntervalMs = Math.max(
    100,
    safeInt(intervalMs, refreshIntervalMsFromEnv(env)) || refreshIntervalMsFromEnv(env)
  );
  const resolvedRefreshLeadMs = safeInt(refreshLeadMs, refreshLeadMsFromEnv(env)) || refreshLeadMsFromEnv(env);
  const resolvedBaseBackoffMs = safeInt(baseFailureBackoffMs, refreshFailureBackoffMsFromEnv(env)) || refreshFailureBackoffMsFromEnv(env);
  const resolvedMaxBackoffMs = safeInt(maxFailureBackoffMs, refreshMaxBackoffMsFromEnv(env)) || refreshMaxBackoffMsFromEnv(env);

  let stopped = false;
  let tickRunning = false;
  const inFlight = new Set();

  const tick = async () => {
    if (stopped || tickRunning) return;
    tickRunning = true;
    try {
      await runProviderKeyRuntimeConductorTick({
        runtimeBaseDir: runtime,
        refreshLeadMs: resolvedRefreshLeadMs,
        executorForAccount,
        executors,
        inFlight,
        logger,
        env,
        httpRequestFn,
        nowFn,
        baseFailureBackoffMs: resolvedBaseBackoffMs,
        maxFailureBackoffMs: resolvedMaxBackoffMs,
      });
    } catch (error) {
      if (logger?.warn) {
        logger.warn(`[provider_key_runtime_conductor] tick failed: ${String(error?.message || error)}`);
      }
    } finally {
      tickRunning = false;
    }
  };

  const startupTimer = setTimeout(() => {
    void tick();
  }, 0);
  try {
    startupTimer.unref();
  } catch {
    // ignore
  }

  const intervalTimer = setInterval(() => {
    void tick();
  }, resolvedIntervalMs);
  try {
    intervalTimer.unref();
  } catch {
    // ignore
  }

  return () => {
    stopped = true;
    clearTimeout(startupTimer);
    clearInterval(intervalTimer);
  };
}
