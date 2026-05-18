import {
  loadProviderKeyStore,
  listProviderKeysFull,
  selectProviderKey,
  reportKeyUsage,
  reportKeyError,
  invalidateProviderKeyCache,
  resolveAccountModelState,
} from './provider_key_store.js';

const PROVIDER_MODEL_MAP = {
  openai: ['gpt-', 'gpt-4', 'gpt-4o', 'gpt-4-turbo', 'gpt-3.5-turbo', 'o1', 'o1-mini', 'o3', 'o3-mini', 'o4', 'o4-mini', 'chatgpt', 'dall-e', 'deepseek'],
  claude: ['claude-3.5-sonnet', 'claude-3-opus', 'claude-3-haiku', 'claude-3.5-haiku', 'claude-sonnet-4', 'claude-opus-4'],
  gemini: ['gemini-1.5-pro', 'gemini-1.5-flash', 'gemini-2.0-flash', 'gemini-2.5-pro', 'gemini-2.5-flash'],
  codex: ['codex', 'gpt-5.3-codex', 'gpt-5-codex', 'codex-mini'],
  kiro: ['kiro'],
  copilot: ['copilot', 'gpt-4', 'gpt-4o', 'o1', 'o3-mini'],
  antigravity: ['antigravity'],
  qwen: ['qwen-turbo', 'qwen-plus', 'qwen-max', 'qwen-vl'],
  iflow: ['iflow'],
  custom: [],
};

const SHARED_PROVIDER_POOLS = {
  openai: ['openai', 'codex'],
  codex: ['codex', 'openai'],
};

function normalizedToken(value) {
  return String(value || '').trim().toLowerCase();
}

function requiredRefreshMetadataForAccount(account) {
  if (normalizedToken(account?.auth_type) !== 'oauth') return [];

  const source = normalizedToken(account?.oauth_source_key) || normalizedToken(account?.provider);
  let requiredFields = [];
  switch (source) {
    case 'gemini':
    case 'gemini-cli':
    case 'google':
    case 'antigravity':
      requiredFields = ['client_id', 'client_secret', 'token_uri'];
      break;
    default:
      requiredFields = [];
      break;
  }
  if (requiredFields.length === 0) return [];

  const config = account?.oauth_refresh_config && typeof account.oauth_refresh_config === 'object'
    ? account.oauth_refresh_config
    : {};
  const present = new Set(
    Object.keys(config).map((key) => normalizedToken(String(key || '').replace(/-/g, '_')))
  );
  return requiredFields.filter((field) => !present.has(field));
}

function availabilitySortRank(state) {
  switch (normalizedToken(state)) {
    case 'ready':
      return 0;
    case 'cooldown':
      return 1;
    case 'stale':
      return 2;
    case 'blocked':
    case 'expired':
      return 3;
    case 'disabled':
      return 4;
    default:
      return 5;
  }
}

function candidateReasonCode(candidate) {
  if (candidate?.selected) return 'selected_by_scheduler';
  if (candidate?.state === 'ready') return 'lower_ranked_by_strategy';
  return normalizedToken(candidate?.reason_code) || 'unavailable';
}

function fallbackReasonCode(candidates) {
  if (!Array.isArray(candidates) || candidates.length === 0) {
    return 'no_keys_for_provider';
  }

  if (candidates.every((candidate) => candidate.state === 'disabled')) {
    return 'all_keys_disabled';
  }
  if (candidates.every((candidate) => candidate.state === 'cooldown')) {
    return 'all_keys_in_cooldown';
  }
  if (candidates.every((candidate) => candidate.state === 'stale')) {
    return 'all_keys_stale';
  }
  if (candidates.every((candidate) => ['blocked', 'disabled', 'expired'].includes(candidate.state)
      && ['auth_failed', 'blocked_auth', 'missing_scope', 'token_expired', 'auth_missing'].includes(candidate.reason_code))) {
    return 'all_keys_auth_blocked';
  }
  if (candidates.every((candidate) => candidate.state === 'blocked'
      && ['rate_limited', 'blocked_quota', 'quota_exceeded', 'daily_token_cap_exceeded'].includes(candidate.reason_code))) {
    return 'all_keys_rate_limited';
  }
  return 'all_keys_unavailable';
}

function selectionScopeKey(provider, modelId, accounts = []) {
  const poolIDs = [...new Set(
    (Array.isArray(accounts) ? accounts : [])
      .map((account) => normalizedToken(account?.pool_id))
      .filter(Boolean)
  )].sort((lhs, rhs) => lhs.localeCompare(rhs));
  if (poolIDs.length === 1) {
    return `${normalizedToken(provider)}::${poolIDs[0]}`;
  }
  return `${normalizedToken(provider)}::${normalizedToken(modelId)}`;
}

function finiteDecisionScore(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return -1e12;
  }
  return numeric;
}

function modelLookupKeys(modelId) {
  const raw = normalizedToken(modelId);
  if (!raw) return [];

  const out = [];
  const seen = new Set();
  const push = (value) => {
    const token = String(value || '').trim().toLowerCase();
    if (!token || seen.has(token)) return;
    seen.add(token);
    out.push(token);
  };

  push(raw);
  if (raw.includes('/')) {
    const parts = raw.split('/').map((part) => part.trim()).filter(Boolean);
    for (const part of parts) {
      push(part);
    }
    push(parts[parts.length - 1]);
  }
  if (raw.startsWith('models/')) {
    push(raw.slice('models/'.length));
  }

  return out;
}

function matchesAccountModel(account, modelId) {
  const patterns = Array.isArray(account?.models)
    ? account.models.map(normalizedToken).filter(Boolean)
    : [];
  if (patterns.length === 0) return true;

  const lookup = new Set(modelLookupKeys(modelId));
  if (lookup.size === 0) return false;

  for (const pattern of patterns) {
    if (pattern === '*' || lookup.has(pattern)) return true;
    if (pattern.endsWith('*')) {
      const prefix = pattern.slice(0, -1);
      if ([...lookup].some((candidate) => candidate.startsWith(prefix))) {
        return true;
      }
    }
  }
  return false;
}

function preferredAccountsForModel(accounts, modelId) {
  const restrictedMatching = accounts.filter((account) => {
    const hasModelRestrictions = Array.isArray(account?.models) && account.models.length > 0;
    return hasModelRestrictions && matchesAccountModel(account, modelId);
  });
  if (restrictedMatching.length > 0) {
    return restrictedMatching;
  }
  const matching = accounts.filter((account) => matchesAccountModel(account, modelId));
  return matching.length > 0 ? matching : accounts;
}

function effectiveRetryAtMs(account) {
  const quotaRetry = Number(account?.quota?.cooldown_until_ms || 0);
  const stateRetry = Number(account?.error_state?.next_retry_at_ms || 0);
  const refreshRetry = Number(account?.refresh_state?.next_refresh_at_ms || 0);
  return Math.max(quotaRetry, stateRetry, refreshRetry);
}

function normalizedReasonCode(account, fallback = '') {
  return normalizedToken(
    account?.error_state?.reason_code
    || account?.error_state?.last_error_code
    || fallback
  );
}

function availabilityFromModelState(modelState) {
  if (!modelState || typeof modelState !== 'object') return null;
  const status = normalizedToken(modelState.status);
  const reasonCode = normalizedToken(
    modelState.reason_code
    || modelState.last_error_code
    || status
  );
  const retryAtMs = Number(modelState.next_retry_at_ms || 0);
  if (status === 'ready') {
    return { state: 'ready', reason_code: '', retry_at_ms: 0 };
  }
  if (status === 'cooldown') {
    return {
      state: 'cooldown',
      reason_code: reasonCode || 'cooldown_active',
      retry_at_ms: retryAtMs,
    };
  }
  if (status === 'disabled') {
    return {
      state: 'disabled',
      reason_code: reasonCode || 'disabled',
      retry_at_ms: retryAtMs,
    };
  }
  if (status === 'stale') {
    return {
      state: 'stale',
      reason_code: reasonCode || 'runtime_stale',
      retry_at_ms: retryAtMs,
    };
  }
  if (status === 'blocked') {
    return {
      state: 'blocked',
      reason_code: reasonCode || 'blocked',
      retry_at_ms: retryAtMs,
    };
  }
  return null;
}

function providerPoolCandidates(provider) {
  const pool = SHARED_PROVIDER_POOLS[String(provider || '').trim()];
  return Array.isArray(pool) && pool.length > 0 ? pool : [provider];
}

function inferProviderFromModelId(modelId) {
  const candidates = modelLookupKeys(modelId);
  if (candidates.length === 0) return '';

  for (const lower of candidates) {
    if (lower.startsWith('openai/')) return 'openai';
    if (lower.startsWith('codex/')) return 'codex';
  }

  for (const [provider, patterns] of Object.entries(PROVIDER_MODEL_MAP)) {
    for (const lower of candidates) {
      for (const pattern of patterns) {
        if (lower.startsWith(pattern) || lower.includes(pattern)) {
          return provider;
        }
      }
    }
  }

  for (const lower of candidates) {
    if (lower.startsWith('gpt-') || lower.startsWith('o1') || lower.startsWith('o3') || lower.startsWith('o4')) return 'openai';
    if (lower.startsWith('claude')) return 'claude';
    if (lower.startsWith('gemini')) return 'gemini';
    if (lower.startsWith('deepseek')) return 'openai';
    if (lower.startsWith('qwen')) return 'qwen';
  }

  return '';
}

function accountAvailabilityState(account, nowMs, modelId = '') {
  if (!account?.enabled) {
    return { state: 'disabled', reason_code: 'disabled', retry_at_ms: 0 };
  }
  if (!account?.api_key) {
    return { state: 'blocked', reason_code: 'auth_missing', retry_at_ms: 0 };
  }
  if (modelId && !matchesAccountModel(account, modelId)) {
    return { state: 'blocked', reason_code: 'model_unsupported', retry_at_ms: 0 };
  }
  if (Number(account?.expires_at_ms || 0) > 0 && nowMs > Number(account.expires_at_ms || 0)) {
    return { state: 'blocked', reason_code: 'token_expired', retry_at_ms: 0 };
  }

  const refreshState = account?.refresh_state || {};
  const refreshStatus = normalizedToken(refreshState.status);
  const refreshRetryAtMs = Number(refreshState.next_refresh_at_ms || 0);
  const refreshReasonCode = normalizedToken(
    refreshState.last_error_code
    || refreshState.last_error_message
    || ''
  );
  if (refreshStatus === 'pending' || refreshStatus === 'refreshing') {
    return {
      state: 'cooldown',
      reason_code: refreshReasonCode || 'refresh_pending',
      retry_at_ms: refreshRetryAtMs,
    };
  }
  if (refreshStatus === 'failed' || refreshStatus === 'cooldown') {
    return {
      state: 'cooldown',
      reason_code: refreshReasonCode || 'refresh_failed',
      retry_at_ms: refreshRetryAtMs,
    };
  }

  const errorState = account?.error_state || {};
  const status = normalizedToken(errorState.status);
  const reasonCode = normalizedReasonCode(account, status);
  const retryAtMs = effectiveRetryAtMs(account);

  if (status === 'disabled' || errorState.auto_disabled) {
    return {
      state: 'disabled',
      reason_code: reasonCode || 'disabled',
      retry_at_ms: retryAtMs,
    };
  }
  if (status === 'auth_failed' || status === 'blocked_auth') {
    return {
      state: 'blocked',
      reason_code: reasonCode || 'auth_failed',
      retry_at_ms: retryAtMs,
    };
  }
  if (status === 'blocked_config') {
    return {
      state: 'blocked',
      reason_code: reasonCode || 'blocked_config',
      retry_at_ms: retryAtMs,
    };
  }

  if (modelId) {
    const modelState = availabilityFromModelState(resolveAccountModelState(account, modelId));
    if (modelState) {
      return modelState;
    }
  }

  if (retryAtMs > 0 && nowMs < retryAtMs) {
    return {
      state: 'cooldown',
      reason_code: reasonCode || 'cooldown_active',
      retry_at_ms: retryAtMs,
    };
  }

  const quota = account?.quota;
  if (quota && quota.daily_token_cap > 0 && quota.daily_tokens_used >= quota.daily_token_cap) {
    return {
      state: 'blocked',
      reason_code: reasonCode || 'daily_token_cap_exceeded',
      retry_at_ms: retryAtMs,
    };
  }
  if (status === 'unknown_stale' || reasonCode === 'runtime_stale') {
    return {
      state: 'stale',
      reason_code: reasonCode || 'runtime_stale',
      retry_at_ms: retryAtMs,
    };
  }
  if (['blocked_quota', 'rate_limited'].includes(status)) {
    return {
      state: 'blocked',
      reason_code: reasonCode || status,
      retry_at_ms: retryAtMs,
    };
  }
  if (['blocked_provider', 'blocked_network'].includes(status)) {
    return {
      state: 'blocked',
      reason_code: reasonCode || status,
      retry_at_ms: retryAtMs,
    };
  }

  return { state: 'ready', reason_code: '', retry_at_ms: retryAtMs };
}

function isAccountAvailable(account, nowMs, modelId = '') {
  return accountAvailabilityState(account, nowMs, modelId).state === 'ready';
}

function scoreAccount(account, nowMs, modelId = '') {
  if (!isAccountAvailable(account, nowMs, modelId)) {
    return Number.NEGATIVE_INFINITY;
  }
  let score = 1000;

  if (matchesAccountModel(account, modelId)) {
    score += 250;
  }
  if (account.priority > 0) {
    score += account.priority * 100;
  }

  const errorState = account.error_state;
  if (errorState) {
    if (errorState.status === 'healthy') score += 150;
    if (errorState.status === 'rate_limited' || errorState.status === 'blocked_quota') score -= 500;
    if (errorState.status === 'degraded') score -= 200;
  }

  const quota = account.quota;
  if (quota && quota.daily_token_cap > 0) {
    const usageRatio = quota.daily_tokens_used / quota.daily_token_cap;
    score -= Math.floor(usageRatio * 300);
  }

  if (quota && quota.consecutive_errors > 0) {
    score -= quota.consecutive_errors * 50;
  }

  if (effectiveRetryAtMs(account) > nowMs) {
    score -= 500;
  }

  return score;
}

function fillFirstScore(account, nowMs, modelId = '') {
  if (!isAccountAvailable(account, nowMs, modelId)) {
    return Number.NEGATIVE_INFINITY;
  }
  let score = 0;
  if (matchesAccountModel(account, modelId)) score += 500;
  const errorState = account.error_state;
  if (!errorState || errorState.status === 'healthy') score += 500;
  if (errorState?.status === 'degraded') score -= 200;
  if (errorState?.status === 'rate_limited' || errorState?.status === 'blocked_quota') score -= 400;

  const quota = account.quota;
  if (quota?.consecutive_errors > 0) {
    score -= quota.consecutive_errors * 50;
  }
  if (quota?.daily_token_cap > 0) {
    score += (quota.daily_tokens_remaining / quota.daily_token_cap) * 100;
  }
  if (effectiveRetryAtMs(account) > 0 && nowMs < effectiveRetryAtMs(account)) {
    score -= 500;
  }

  return score;
}

function selectAccount(accounts, strategy, nowMs, rrKey, modelId = '', advanceRoundRobin = true) {
  if (!Array.isArray(accounts) || accounts.length === 0) return null;

  switch (strategy) {
    case 'round-robin': {
      const idx = (Number(process.env[rrKey] || 0)) % accounts.length;
      if (advanceRoundRobin) {
        process.env[rrKey] = String(idx + 1);
      }
      return accounts[idx];
    }
    case 'priority':
    case 'quota-aware': {
      const sorted = [...accounts].sort((a, b) => scoreAccount(b, nowMs, modelId) - scoreAccount(a, nowMs, modelId));
      return sorted[0];
    }
    case 'fill-first':
    default: {
      const sorted = [...accounts].sort((a, b) => fillFirstScore(b, nowMs, modelId) - fillFirstScore(a, nowMs, modelId));
      return sorted[0];
    }
  }
}

function pooledProviderRows(store, provider) {
  const providers = providerPoolCandidates(provider);
  const groups = providers
    .map((providerId) => ({
      provider: providerId,
      data: store.providers[providerId],
    }))
    .filter((row) => row.data && Array.isArray(row.data.accounts));

  const allAccounts = groups.flatMap((row) => row.data.accounts.map((account) => ({
    ...account,
    provider_pool: provider,
    provider_group: row.provider,
  })));

  const strategy = groups[0]?.data?.routing_strategy || 'fill-first';
  return {
    groups,
    strategy,
    accounts: allAccounts,
  };
}

export function resolveProviderKeyForModel(runtimeBaseDir, modelId) {
  const now = Date.now();
  const provider = inferProviderFromModelId(modelId);

  if (!provider) {
    return { account: null, provider: '', fallback_reason: 'unknown_model_provider' };
  }

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const pooled = pooledProviderRows(store, provider);
  if (!pooled.accounts || pooled.accounts.length === 0) {
    return { account: null, provider, fallback_reason: 'no_keys_for_provider' };
  }

  const strategy = pooled.strategy || 'fill-first';
  const scopedAccounts = preferredAccountsForModel(pooled.accounts, modelId);
  const available = scopedAccounts.filter(a => isAccountAvailable(a, now, modelId));

  if (available.length === 0) {
    const states = scopedAccounts.map((account) => accountAvailabilityState(account, now, modelId));
    const allDisabled = states.every((entry) => entry.state === 'disabled');
    const allRateLimited = states.every((entry) => entry.state === 'blocked' && ['rate_limited', 'blocked_quota', 'quota_exceeded', 'daily_token_cap_exceeded'].includes(entry.reason_code));
    const allCooldown = states.every((entry) => entry.state === 'cooldown');
    const allStale = states.every((entry) => entry.state === 'stale');
    const allBlockedAuth = states.every((entry) => (entry.state === 'blocked' || entry.state === 'disabled') && ['auth_failed', 'blocked_auth', 'missing_scope', 'token_expired', 'auth_missing'].includes(entry.reason_code));

    let fallbackReason = 'all_keys_unavailable';
    if (allDisabled) fallbackReason = 'all_keys_disabled';
    else if (allRateLimited) fallbackReason = 'all_keys_rate_limited';
    else if (allCooldown) fallbackReason = 'all_keys_in_cooldown';
    else if (allStale) fallbackReason = 'all_keys_stale';
    else if (allBlockedAuth) fallbackReason = 'all_keys_auth_blocked';

    return { account: null, provider, fallback_reason: fallbackReason };
  }

  const selected = selectAccount(available, strategy, now, `__hub_rr_${provider}`, modelId, true);

  return {
    account: selected,
    provider,
    fallback_reason: '',
    strategy,
    available_count: available.length,
    total_count: scopedAccounts.length,
  };
}

export function buildProviderKeyRouteDecision(runtimeBaseDir, modelId, providerOverride = '') {
  const now = Date.now();
  const requestedModelId = normalizedToken(modelId);
  const requestedProvider = normalizedToken(providerOverride) || inferProviderFromModelId(modelId);

  if (!requestedProvider) {
    return {
      requested_provider: '',
      requested_model_id: requestedModelId,
      resolved_provider: '',
      strategy: 'fill-first',
      selection_scope: `unknown::${requestedModelId}`,
      selected_account_key: '',
      fallback_reason_code: 'unknown_model_provider',
      available_count: 0,
      total_count: 0,
      candidates: [],
      updated_at_ms: now,
    };
  }

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const pooled = pooledProviderRows(store, requestedProvider);
  const strategy = pooled.strategy || 'fill-first';
  const scopedAccounts = preferredAccountsForModel(pooled.accounts || [], modelId);
  const selectionScope = selectionScopeKey(requestedProvider, modelId, scopedAccounts);

  if (scopedAccounts.length === 0) {
    return {
      requested_provider: requestedProvider,
      requested_model_id: requestedModelId,
      resolved_provider: requestedProvider,
      strategy,
      selection_scope: selectionScope,
      selected_account_key: '',
      fallback_reason_code: 'no_keys_for_provider',
      available_count: 0,
      total_count: 0,
      candidates: [],
      updated_at_ms: now,
    };
  }

  const available = scopedAccounts.filter((account) => isAccountAvailable(account, now, modelId));
  const selected = available.length > 0
    ? selectAccount(available, strategy, now, `__hub_rr_${requestedProvider}`, modelId, false)
    : null;

  const candidates = scopedAccounts.map((account) => {
    const availability = accountAvailabilityState(account, now, modelId);
    const matchedModelState = resolveAccountModelState(account, modelId);
    let score = Number.NEGATIVE_INFINITY;
    switch (strategy) {
      case 'priority':
      case 'quota-aware':
        score = scoreAccount(account, now, modelId);
        break;
      case 'round-robin':
        score = isAccountAvailable(account, now, modelId) ? 0 : Number.NEGATIVE_INFINITY;
        break;
      case 'fill-first':
      default:
        score = fillFirstScore(account, now, modelId);
        break;
    }

    const retryAtSource = normalizedToken(
      matchedModelState?.retry_at_source
      || account?.error_state?.retry_at_source
    );
    const statusMessage = String(
      matchedModelState?.status_message
      || account?.error_state?.status_message
      || account?.refresh_state?.last_error_message
      || availability?.status_message
      || ''
    ).trim();
    const candidate = {
      account_key: String(account?.account_key || '').trim(),
      provider: String(account?.provider || '').trim(),
      provider_group: String(account?.provider_group || account?.provider || '').trim(),
      pool_id: String(account?.pool_id || '').trim(),
      provider_host: String(account?.provider_host || '').trim(),
      wire_api: String(account?.wire_api || '').trim(),
      state: normalizedToken(availability?.state) || 'blocked',
      reason_code: normalizedToken(availability?.reason_code),
      status_message: statusMessage,
      retry_at_ms: Number(availability?.retry_at_ms || 0),
      retry_at_source: retryAtSource,
      score: finiteDecisionScore(score),
      selected: selected?.account_key === account?.account_key,
      models: Array.isArray(account?.models) ? account.models : [],
      source_owners: Array.isArray(account?.source_owners) ? account.source_owners : [],
      required_refresh_metadata: requiredRefreshMetadataForAccount(account),
      model_state_key: String(matchedModelState?.model_id || '').trim().toLowerCase(),
    };
    candidate.reason_code = candidateReasonCode(candidate);
    return candidate;
  }).sort((lhs, rhs) => {
    if (lhs.selected !== rhs.selected) return lhs.selected ? -1 : 1;
    const rankOrder = availabilitySortRank(lhs.state) - availabilitySortRank(rhs.state);
    if (rankOrder !== 0) return rankOrder;
    if (lhs.score !== rhs.score) return rhs.score - lhs.score;
    return lhs.account_key.localeCompare(rhs.account_key);
  });

  return {
    requested_provider: requestedProvider,
    requested_model_id: requestedModelId,
    resolved_provider: String(selected?.provider_group || selected?.provider || requestedProvider),
    strategy,
    selection_scope: selectionScope,
    selected_account_key: String(selected?.account_key || ''),
    fallback_reason_code: selected ? '' : fallbackReasonCode(candidates),
    available_count: available.length,
    total_count: scopedAccounts.length,
    candidates,
    updated_at_ms: now,
  };
}

export function resolveProviderKeyWithFallback(runtimeBaseDir, modelId, fallbackProviders = []) {
  const primary = resolveProviderKeyForModel(runtimeBaseDir, modelId);
  if (primary.account) return primary;

  const primaryProvider = primary.provider || inferProviderFromModelId(modelId);

  const candidates = [...fallbackProviders];
  if (primaryProvider && !candidates.includes(primaryProvider)) {
    // already tried
  }

  for (const fbProvider of candidates) {
    const store = loadProviderKeyStore(runtimeBaseDir, 0);
    const providerData = store.providers[fbProvider];
    if (!providerData) continue;

    const now = Date.now();
    const scopedAccounts = preferredAccountsForModel(providerData.accounts, modelId);
    const available = scopedAccounts.filter(a => isAccountAvailable(a, now, modelId));
    if (available.length === 0) continue;

    const sorted = [...available].sort((a, b) => scoreAccount(b, now, modelId) - scoreAccount(a, now, modelId));
    const selected = sorted[0];

    return {
      account: selected,
      provider: fbProvider,
      fallback_reason: `fallback_from_${primaryProvider || 'unknown'}`,
      strategy: 'fallback',
      available_count: available.length,
      total_count: scopedAccounts.length,
    };
  }

  return {
    account: null,
    provider: primaryProvider,
    fallback_reason: primary.fallback_reason || 'no_available_keys',
  };
}

export function buildProviderRequestHeaders(account) {
  if (!account) return {};

  const headers = { ...account.custom_headers };

  if (account.provider === 'claude') {
    headers['x-api-key'] = account.api_key;
    headers['anthropic-version'] = headers['anthropic-version'] || '2023-06-01';
  } else if (account.provider === 'gemini') {
    // Gemini uses key as query param, but we can set it in headers for proxy
  } else {
    if (!headers['Authorization']) {
      headers['Authorization'] = `Bearer ${account.api_key}`;
    }
  }

  return headers;
}

export function buildProviderRequestUrl(account, modelId) {
  if (!account) return '';

  const baseUrl = account.base_url || account.proxy_url || '';
  if (!baseUrl) return '';

  if (account.provider === 'claude') {
    return `${baseUrl.replace(/\/+$/, '')}/v1/messages`;
  }

  if (account.provider === 'gemini') {
    return `${baseUrl.replace(/\/+$/, '')}/v1beta/models/${modelId}:generateContent?key=${account.api_key}`;
  }

  return `${baseUrl.replace(/\/+$/, '')}/v1/chat/completions`;
}

export { inferProviderFromModelId, isAccountAvailable, scoreAccount };
