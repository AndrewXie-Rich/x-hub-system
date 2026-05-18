import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import yaml from 'js-yaml';
import { nowMs } from './util.js';

const SCHEMA_VERSION = 'hub_provider_keys.v1';
const STORE_FILENAME = 'hub_provider_keys.json';
const MAX_ACCOUNTS_PER_PROVIDER = 32;
const VALID_IMPORT_SOURCE_KINDS = new Set([
  'auth_dir',
  'config_path',
]);
const VALID_IMPORT_SOURCE_STATES = new Set([
  'pending',
  'ready',
  'missing',
  'sync_failed',
]);
const MAX_IMPORT_SOURCE_ERRORS = 4;

const VALID_PROVIDERS = new Set([
  'openai',
  'claude',
  'gemini',
  'codex',
  'kiro',
  'copilot',
  'antigravity',
  'qwen',
  'iflow',
  'custom',
]);

const VALID_AUTH_TYPES = new Set([
  'api_key',
  'oauth',
  'copilot',
]);

const VALID_ROUTING_STRATEGIES = new Set([
  'round-robin',
  'fill-first',
  'quota-aware',
  'priority',
]);
const VALID_REFRESH_STATES = new Set([
  'idle',
  'pending',
  'refreshing',
  'cooldown',
  'failed',
]);
const VALID_MODEL_STATE_STATUSES = new Set([
  'ready',
  'cooldown',
  'blocked',
  'disabled',
  'stale',
]);

const PROVIDER_ALIASES = {
  'openai-chatgpt': 'codex',
  chatgpt: 'codex',
  'github-copilot': 'copilot',
};

function safeString(v) {
  return String(v ?? '').trim();
}

function safeInt(v, def = 0) {
  const n = Number(v || 0);
  if (!Number.isFinite(n)) return def;
  return Math.max(0, Math.floor(n));
}

function safeNumber(v, def = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

function safePercent(v) {
  return Math.max(0, Math.min(100, safeNumber(v, 0)));
}

function safeStringArray(values) {
  if (!Array.isArray(values)) return [];
  const out = [];
  const seen = new Set();
  for (const raw of values) {
    const value = safeString(raw);
    if (!value || seen.has(value)) continue;
    seen.add(value);
    out.push(value);
  }
  return out;
}

function normalizePathRef(v) {
  const value = safeString(v);
  if (!value) return '';
  try {
    return path.resolve(value);
  } catch {
    return value;
  }
}

function safeStringMap(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    const normalizedKey = safeString(key).toLowerCase();
    const normalizedValue = safeString(value);
    if (!normalizedKey || !normalizedValue) continue;
    out[normalizedKey] = normalizedValue;
  }
  return Object.fromEntries(
    Object.entries(out).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
  );
}

function safeObject(raw) {
  return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const normalized = safeString(value);
    if (normalized) return normalized;
  }
  return '';
}

function storePath(runtimeBaseDir) {
  const base = String(runtimeBaseDir || '').trim();
  if (!base) return '';
  return path.join(base, STORE_FILENAME);
}

function readJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function writeJsonAtomic(dirPath, fileName, obj) {
  const dir = safeString(dirPath);
  if (!dir) return false;
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // ignore
  }
  const outPath = path.join(dir, fileName);
  const tmp = path.join(dir, `.${fileName}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`);
  try {
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', { encoding: 'utf8' });
    fs.renameSync(tmp, outPath);
    return true;
  } catch {
    try { fs.unlinkSync(tmp); } catch { /* ignore */ }
    return false;
  }
}

function normalizeProvider(v) {
  const s = safeString(v).toLowerCase();
  if (PROVIDER_ALIASES[s]) return PROVIDER_ALIASES[s];
  if (VALID_PROVIDERS.has(s)) return s;
  return '';
}

function normalizeAuthType(v) {
  const s = safeString(v).toLowerCase();
  if (VALID_AUTH_TYPES.has(s)) return s;
  return 'api_key';
}

function normalizeRoutingStrategy(v) {
  const s = safeString(v).toLowerCase();
  if (VALID_ROUTING_STRATEGIES.has(s)) return s;
  return 'fill-first';
}

function normalizeImportSourceKind(v) {
  const s = safeString(v).toLowerCase();
  if (VALID_IMPORT_SOURCE_KINDS.has(s)) return s;
  return '';
}

function normalizeImportSource(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const kind = normalizeImportSourceKind(raw.kind || raw.type || raw.source_type);
  const sourceRef = normalizePathRef(raw.source_ref || raw.sourceRef || raw.path || raw.ref);
  if (!kind || !sourceRef) return null;
  return {
    kind,
    source_ref: sourceRef,
  };
}

function parseImportSourceKey(raw) {
  const token = safeString(raw);
  if (!token) return null;
  const separator = token.indexOf(':');
  if (separator <= 0) return null;
  const kind = normalizeImportSourceKind(token.slice(0, separator));
  const sourceRef = normalizePathRef(token.slice(separator + 1));
  if (!kind || !sourceRef) return null;
  return {
    kind,
    source_ref: sourceRef,
  };
}

function importSourceKey(kind, sourceRef) {
  const normalizedKind = normalizeImportSourceKind(kind);
  const normalizedRef = normalizePathRef(sourceRef);
  if (!normalizedKind || !normalizedRef) return '';
  return `${normalizedKind}:${normalizedRef}`;
}

function normalizeImportSourceEntry(raw) {
  const parsed = normalizeImportSource(raw && typeof raw === 'object'
    ? raw
    : parseImportSourceKey(raw));
  return parsed ? importSourceKey(parsed.kind, parsed.source_ref) : '';
}

function normalizeImportSourceList(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  const seen = new Set();
  for (const item of raw) {
    const entry = normalizeImportSourceEntry(item);
    if (!entry || seen.has(entry)) continue;
    seen.add(entry);
    out.push(entry);
  }
  return out.sort((lhs, rhs) => lhs.localeCompare(rhs));
}

function normalizeImportSourceState(v) {
  const s = safeString(v).toLowerCase();
  if (VALID_IMPORT_SOURCE_STATES.has(s)) return s;
  return 'pending';
}

function normalizeImportSourceStatus(raw, fallbackSourceKey = '') {
  const source = normalizeImportSource(raw) || parseImportSourceKey(fallbackSourceKey);
  if (!source) return null;
  const lastErrors = safeStringArray(raw?.last_errors).slice(0, MAX_IMPORT_SOURCE_ERRORS);
  return {
    kind: source.kind,
    source_ref: source.source_ref,
    state: normalizeImportSourceState(raw?.state),
    last_sync_at_ms: safeInt(raw?.last_sync_at_ms, 0),
    last_imported_count: safeInt(raw?.last_imported_count, 0),
    owned_account_count: safeInt(raw?.owned_account_count, 0),
    last_error_count: Math.max(safeInt(raw?.last_error_count, 0), lastErrors.length),
    last_errors: lastErrors,
    updated_at_ms: safeInt(raw?.updated_at_ms, 0),
  };
}

function normalizeImportSourceStatusMap(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  const out = {};
  for (const [sourceKeyRaw, sourceStatusRaw] of Object.entries(raw)) {
    const sourceKey = normalizeImportSourceEntry(sourceKeyRaw);
    if (!sourceKey) continue;
    const status = normalizeImportSourceStatus(sourceStatusRaw, sourceKey);
    if (!status) continue;
    out[sourceKey] = status;
  }
  return Object.fromEntries(
    Object.entries(out).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
  );
}

function normalizeWireAPI(v) {
  const s = safeString(v).toLowerCase();
  switch (s) {
    case 'responses':
    case 'response':
    case 'responses_api':
      return 'responses';
    case 'chat':
    case 'chatcompletions':
    case 'chat_completions':
    case 'chat-completions':
    case 'chat/completions':
      return 'chat_completions';
    default:
      return '';
  }
}

function redactApiKey(key) {
  const s = safeString(key);
  if (s.length <= 8) return '****';
  return s.slice(0, 4) + '...' + s.slice(-4);
}

function canonicalPoolProvider(v) {
  const provider = normalizeProvider(v) || safeString(v).toLowerCase();
  switch (provider) {
    case 'chatgpt':
    case 'openai-chatgpt':
    case 'codex':
    case 'openai':
      return 'openai';
    case 'anthropic':
    case 'claude':
      return 'claude';
    case 'google':
    case 'gemini':
      return 'gemini';
    default:
      return provider;
  }
}

function defaultProviderHost(provider) {
  switch (canonicalPoolProvider(provider)) {
    case 'openai':
      return 'api.openai.com';
    case 'claude':
      return 'api.anthropic.com';
    case 'gemini':
      return 'generativelanguage.googleapis.com';
    default:
      return '';
  }
}

function hostFromURL(rawURL) {
  const value = safeString(rawURL);
  if (!value) return '';
  try {
    const parsed = new URL(value);
    return safeString(parsed.hostname).toLowerCase();
  } catch {
    return '';
  }
}

function normalizedOriginScope(rawURL) {
  const value = safeString(rawURL);
  if (!value) return '';
  try {
    const parsed = new URL(value);
    const protocol = safeString(parsed.protocol).toLowerCase();
    const host = safeString(parsed.hostname).toLowerCase();
    if (!protocol || !host) return '';
    const port = safeString(parsed.port);
    const pathname = safeString(parsed.pathname).replace(/\/+$/, '').toLowerCase();
    return `${protocol}//${host}${port ? `:${port}` : ''}${pathname}`;
  } catch {
    return '';
  }
}

function nonDefaultBasePathScope(rawURL, provider) {
  const value = safeString(rawURL);
  if (!value) return '';
  try {
    const parsed = new URL(value);
    const pathname = safeString(parsed.pathname).replace(/\/+$/, '').toLowerCase();
    const defaults = new Set(['', '/']);
    switch (canonicalPoolProvider(provider)) {
      case 'openai':
      case 'claude':
        defaults.add('/v1');
        break;
      case 'gemini':
        defaults.add('/v1');
        defaults.add('/v1beta');
        break;
      default:
        break;
    }
    return defaults.has(pathname) ? '' : pathname;
  } catch {
    return '';
  }
}

function shortFingerprint(payload) {
  const normalized = safeString(payload);
  if (!normalized) return '';
  return crypto.createHash('sha256')
    .update(normalized)
    .digest('hex')
    .slice(0, 12);
}

function resolvedProviderHost(provider, baseURL, proxyURL) {
  return hostFromURL(baseURL) || hostFromURL(proxyURL) || defaultProviderHost(provider);
}

function derivedPoolBoundaryFingerprint({
  provider,
  baseURL,
  proxyURL,
  customHeaders,
}) {
  const material = {};
  const basePath = nonDefaultBasePathScope(baseURL, provider);
  const proxyScope = normalizedOriginScope(proxyURL);
  const headerMap = safeStringMap(customHeaders);
  if (basePath) material.base_path = basePath;
  if (proxyScope) material.proxy_scope = proxyScope;
  if (Object.keys(headerMap).length > 0) {
    material.custom_headers = headerMap;
  }
  if (Object.keys(material).length === 0) return '';
  return shortFingerprint(JSON.stringify(material));
}

function derivedPoolID({
  provider,
  providerHost,
  wireAPI,
  baseURL,
  proxyURL,
  customHeaders,
}) {
  const canonicalProvider = canonicalPoolProvider(provider) || 'default';
  const hostPart = safeString(providerHost) || defaultProviderHost(provider) || 'default';
  const wirePart = normalizeWireAPI(wireAPI) || 'default';
  const boundaryFingerprint = derivedPoolBoundaryFingerprint({
    provider,
    baseURL,
    proxyURL,
    customHeaders,
  });
  if (!boundaryFingerprint) {
    return `${canonicalProvider}:${hostPart}:${wirePart}`;
  }
  return `${canonicalProvider}:${hostPart}:${wirePart}:${boundaryFingerprint}`;
}

function buildAccountKey(provider, account) {
  const email = safeString(account.email || account.username || '');
  const apiKey = safeString(account.api_key || account.access_token || '');
  const hash = crypto.createHash('sha256')
    .update(`${provider}:${email}:${apiKey}`)
    .digest('hex')
    .slice(0, 12);
  return `${provider}:${hash}`;
}

function buildImportedFileAccountKey(provider, fileIdentity) {
  const hash = crypto.createHash('sha256')
    .update(`${provider}:${safeString(fileIdentity)}`)
    .digest('hex')
    .slice(0, 16);
  return `${provider}:${hash}`;
}

function buildImportedConfigAccountKey(provider, configPath, namespace, index = 0) {
  const hash = crypto.createHash('sha256')
    .update(`${provider}:${safeString(configPath)}:${safeString(namespace)}:${safeInt(index, 0)}`)
    .digest('hex')
    .slice(0, 12);
  return `${provider}:${hash}`;
}

function normalizeQuotaUsageWindow(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const source = safeString(raw.source || raw.window_source || 'rate_limit').toLowerCase();
  const windowKey = safeString(raw.window_key || raw.window || raw.key || '').toLowerCase();
  const limitWindowSeconds = safeInt(raw.limit_window_seconds || raw.window_seconds, 0);
  const usedPercent = safePercent(raw.used_percent);
  const usedBasisPoints = safeInt(raw.used_basis_points, Math.round(usedPercent * 100));
  const remainingBasisPoints = safeInt(
    raw.remaining_basis_points,
    Math.max(0, 10000 - usedBasisPoints)
  );
  const resetAtMs = safeInt(raw.reset_at_ms || raw.reset_at, 0);
  const updatedAtMs = safeInt(raw.updated_at_ms, 0);
  const label = safeString(raw.label || raw.display_name || '');
  const key = safeString(raw.key) || [
    source,
    windowKey || 'window',
    limitWindowSeconds > 0 ? String(limitWindowSeconds) : label,
  ].filter(Boolean).join(':');

  if (
    !key
    && !label
    && limitWindowSeconds <= 0
    && usedPercent <= 0
    && resetAtMs <= 0
    && updatedAtMs <= 0
  ) {
    return null;
  }

  return {
    key,
    source,
    window_key: windowKey,
    label,
    limit_window_seconds: limitWindowSeconds,
    used_percent: usedPercent,
    used_basis_points: Math.max(0, Math.min(10000, usedBasisPoints)),
    remaining_basis_points: Math.max(0, Math.min(10000, remainingBasisPoints)),
    reset_at_ms: resetAtMs,
    limited: !!raw.limited,
    updated_at_ms: updatedAtMs,
  };
}

function normalizeQuotaUsageWindows(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  const seen = new Set();
  for (const item of raw) {
    const normalized = normalizeQuotaUsageWindow(item);
    if (!normalized) continue;
    const dedupeKey = normalized.key || `${normalized.source}:${normalized.window_key}:${normalized.limit_window_seconds}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    out.push(normalized);
  }
  return out.sort((lhs, rhs) => {
    const sourceOrder = String(lhs.source).localeCompare(String(rhs.source));
    if (sourceOrder !== 0) return sourceOrder;
    return safeInt(lhs.limit_window_seconds, 0) - safeInt(rhs.limit_window_seconds, 0);
  });
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
      usage_windows: [],
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
    usage_windows: normalizeQuotaUsageWindows(raw.usage_windows),
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
    status: [
      'healthy',
      'degraded',
      'rate_limited',
      'auth_failed',
      'disabled',
      'blocked_auth',
      'blocked_quota',
      'blocked_network',
      'blocked_provider',
      'blocked_config',
      'unknown_stale',
    ].includes(raw.status) ? raw.status : 'healthy',
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
    status: VALID_REFRESH_STATES.has(status) ? status : 'idle',
    last_attempt_at_ms: safeInt(raw.last_attempt_at_ms, 0),
    last_success_at_ms: safeInt(raw.last_success_at_ms, 0),
    next_refresh_at_ms: safeInt(raw.next_refresh_at_ms, 0),
    failure_count: safeInt(raw.failure_count, 0),
    last_error_code: safeString(raw.last_error_code),
    last_error_message: safeString(raw.last_error_message),
  };
}

function normalizedToken(value) {
  return safeString(value).toLowerCase();
}

function normalizeModelState(raw, fallbackModelID = '') {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const modelID = normalizedToken(raw.model_id || raw.modelId || fallbackModelID);
  const status = normalizedToken(raw.status);
  if (!modelID || !VALID_MODEL_STATE_STATUSES.has(status)) return null;
  return {
    model_id: modelID,
    status,
    reason_code: safeString(raw.reason_code || raw.reasonCode || raw.last_error_code),
    status_message: safeString(raw.status_message || raw.statusMessage),
    next_retry_at_ms: safeInt(raw.next_retry_at_ms, 0),
    retry_at_source: normalizeProviderRetrySource(raw.retry_at_source || raw.retryAtSource, {
      status,
      reasonCode: raw.reason_code || raw.reasonCode || raw.last_error_code,
      nextRetryAtMs: raw.next_retry_at_ms,
    }),
    last_error_code: safeString(raw.last_error_code || raw.lastErrorCode),
    last_error_at_ms: safeInt(raw.last_error_at_ms, 0),
    updated_at_ms: safeInt(raw.updated_at_ms, 0),
  };
}

function normalizeModelStateMap(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  const out = {};
  for (const [rawModelID, rawState] of Object.entries(raw)) {
    const state = normalizeModelState(rawState, rawModelID);
    if (!state) continue;
    out[state.model_id] = state;
  }
  return Object.fromEntries(
    Object.entries(out).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
  );
}

function modelStateMatch(stateMap, modelId) {
  const normalizedStates = stateMap && typeof stateMap === 'object' && !Array.isArray(stateMap)
    ? stateMap
    : {};
  const lookup = modelLookupKeys(modelId);
  if (lookup.length === 0) return null;

  for (const key of lookup) {
    const matched = normalizedStates[key];
    if (matched) return matched;
  }

  for (const [key, state] of Object.entries(normalizedStates)) {
    if (!key.endsWith('*')) continue;
    const prefix = key.slice(0, -1);
    if (!prefix) continue;
    if (lookup.some((candidate) => candidate.startsWith(prefix))) {
      return state;
    }
  }

  return null;
}

export function resolveAccountModelState(account, modelId) {
  return modelStateMatch(account?.model_states, modelId);
}

function runtimeStateFromModelState(modelState) {
  const state = normalizeModelState(modelState);
  if (!state) return null;
  return {
    state: state.status,
    reason_code: safeString(state.reason_code || state.last_error_code),
    status_message: safeString(state.status_message),
    retry_at_ms: safeInt(state.next_retry_at_ms, 0),
    retry_at_source: safeString(state.retry_at_source),
    matched_model_id: state.model_id,
  };
}

function applyAccountModelState(account, modelId, patch) {
  const normalizedModelID = normalizedToken(modelId);
  if (!normalizedModelID || !account || typeof account !== 'object') return;
  const currentStates = normalizeModelStateMap(account.model_states);
  if (!patch || typeof patch !== 'object') {
    delete currentStates[normalizedModelID];
    account.model_states = currentStates;
    return;
  }
  const nextState = normalizeModelState({
    ...(currentStates[normalizedModelID] || {}),
    ...patch,
    model_id: normalizedModelID,
  }, normalizedModelID);
  if (!nextState) return;
  currentStates[normalizedModelID] = nextState;
  account.model_states = currentStates;
}

function modelLookupKeys(modelId) {
  const raw = normalizedToken(modelId);
  if (!raw) return [];

  const out = [];
  const seen = new Set();
  const push = (value) => {
    const token = normalizedToken(value);
    if (!token || seen.has(token)) return;
    seen.add(token);
    out.push(token);
  };

  push(raw);
  if (raw.includes('/')) {
    const parts = raw.split('/').map((part) => normalizedToken(part)).filter(Boolean);
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

function inferCapabilityProviderFromModelId(modelId) {
  const candidates = modelLookupKeys(modelId);
  if (candidates.length === 0) return '';

  for (const lower of candidates) {
    if (lower.startsWith('openai/')) return 'openai';
    if (lower.startsWith('codex/')) return 'openai';
  }

  for (const lower of candidates) {
    if (
      lower.startsWith('gpt-')
      || lower.startsWith('o1')
      || lower.startsWith('o3')
      || lower.startsWith('o4')
      || lower.startsWith('chatgpt')
      || lower.startsWith('codex')
      || lower.includes('gpt-5')
    ) {
      return 'openai';
    }
    if (lower.startsWith('claude')) return 'claude';
    if (lower.startsWith('gemini')) return 'gemini';
    if (lower.startsWith('qwen')) return 'qwen';
    if (lower.startsWith('kiro')) return 'kiro';
    if (lower.startsWith('copilot')) return 'copilot';
    if (lower.startsWith('iflow')) return 'iflow';
    if (lower.startsWith('antigravity')) return 'antigravity';
  }

  return '';
}

function deriveCapabilityModelFamily(modelId) {
  const candidates = modelLookupKeys(modelId);
  if (candidates.length === 0) return 'all';

  for (const lower of candidates) {
    if (lower.includes('gpt-5.4')) return 'gpt-5.4';
    if (lower.startsWith('gpt-5.3-codex') || lower.startsWith('gpt-5-codex') || lower.includes('codex')) {
      return 'gpt-5-codex';
    }
    if (lower.startsWith('gpt-5')) return 'gpt-5';
    if (lower.startsWith('gpt-4') || lower.startsWith('gpt-4o')) return 'gpt-4';
    if (lower.startsWith('o1') || lower.startsWith('o3') || lower.startsWith('o4')) return 'o-series';
    if (lower.startsWith('claude')) return 'claude';
    if (lower.startsWith('gemini')) return 'gemini';
    if (lower.startsWith('qwen')) return 'qwen';
    if (lower.startsWith('kiro')) return 'kiro';
    if (lower.startsWith('copilot')) return 'copilot';
    if (lower.startsWith('iflow')) return 'iflow';
    if (lower.startsWith('antigravity')) return 'antigravity';
  }

  return candidates[0] || 'all';
}

function accountSupportsCapabilityTarget(account, modelId) {
  const target = safeString(modelId);
  if (!target) return true;

  const targetProvider = inferCapabilityProviderFromModelId(target);
  if (targetProvider) {
    if (canonicalPoolProvider(account?.provider) !== canonicalPoolProvider(targetProvider)) {
      return false;
    }
    return matchesAccountModel(account, target);
  }

  const patterns = Array.isArray(account?.models) ? account.models : [];
  if (patterns.length === 0) return false;
  return matchesAccountModel(account, target);
}

function normalizeTierBucket(rawTier) {
  const tier = normalizedToken(rawTier);
  if (!tier) return 'unknown';
  if (tier.includes('free')) return 'free';
  if (tier.includes('plus')) return 'plus';
  if (tier.includes('pro')) return 'pro';
  if (tier.includes('team')) return 'team';
  if (tier.includes('enterprise')) return 'enterprise';
  if (tier.includes('paid') || tier.includes('premium')) return 'paid';
  return tier;
}

function isPaidTierBucket(tierBucket) {
  return ['plus', 'pro', 'team', 'enterprise', 'paid'].includes(normalizedToken(tierBucket));
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
    || account?.refresh_state?.last_error_code
    || fallback
  );
}

function accountPoolState(account, now = nowMs(), modelId = '') {
  if (!account?.enabled) {
    return {
      state: 'disabled',
      reason_code: normalizedReasonCode(account, 'disabled') || 'disabled',
      status_message: safeString(account?.error_state?.status_message),
      retry_at_ms: effectiveRetryAtMs(account),
    };
  }
  if (!safeString(account?.api_key) && !safeString(account?.refresh_token)) {
    return {
      state: 'blocked',
      reason_code: 'auth_missing',
      status_message: 'auth_missing',
      retry_at_ms: effectiveRetryAtMs(account),
    };
  }
  if (modelId && !accountSupportsCapabilityTarget(account, modelId)) {
    return {
      state: 'blocked',
      reason_code: 'model_unsupported',
      status_message: 'model_unsupported',
      retry_at_ms: 0,
    };
  }

  const expiresAtMs = safeInt(account?.expires_at_ms, 0);
  const refreshState = normalizeRefreshState(account?.refresh_state);
  const errorState = normalizeErrorState(account?.error_state);
  const retryAtMs = effectiveRetryAtMs(account);

  if (expiresAtMs > 0 && now > expiresAtMs) {
    return {
      state: 'expired',
      reason_code: normalizedReasonCode(account, 'token_expired') || 'token_expired',
      status_message: safeString(errorState.status_message || refreshState.last_error_message || 'token_expired'),
      retry_at_ms: retryAtMs,
    };
  }

  if (refreshState.status === 'pending' || refreshState.status === 'refreshing') {
    return {
      state: 'cooldown',
      reason_code: normalizedReasonCode(account, 'refresh_pending') || 'refresh_pending',
      status_message: safeString(refreshState.last_error_message || refreshState.status),
      retry_at_ms: retryAtMs,
    };
  }
  if (refreshState.status === 'failed' || refreshState.status === 'cooldown') {
    return {
      state: retryAtMs > now ? 'cooldown' : 'blocked',
      reason_code: normalizedReasonCode(account, 'refresh_failed') || 'refresh_failed',
      status_message: safeString(refreshState.last_error_message || errorState.status_message),
      retry_at_ms: retryAtMs,
    };
  }

  if (errorState.status === 'disabled' || errorState.auto_disabled) {
    return {
      state: 'disabled',
      reason_code: normalizedReasonCode(account, errorState.status || 'disabled') || 'disabled',
      status_message: safeString(errorState.status_message),
      retry_at_ms: retryAtMs,
    };
  }

  if (errorState.status === 'auth_failed' || errorState.status === 'blocked_auth') {
    return {
      state: 'blocked',
      reason_code: normalizedReasonCode(account, 'auth_failed') || 'auth_failed',
      status_message: safeString(errorState.status_message),
      retry_at_ms: retryAtMs,
    };
  }

  if (modelId) {
    const modelState = runtimeStateFromModelState(resolveAccountModelState(account, modelId));
    if (modelState) {
      return {
        state: modelState.state,
        reason_code: modelState.reason_code,
        status_message: modelState.status_message,
        retry_at_ms: modelState.retry_at_ms,
        retry_at_source: modelState.retry_at_source,
        matched_model_id: modelState.matched_model_id,
      };
    }
  }

  if (errorState.status === 'unknown_stale' || normalizedReasonCode(account) === 'runtime_stale') {
    return {
      state: 'stale',
      reason_code: normalizedReasonCode(account, 'runtime_stale') || 'runtime_stale',
      status_message: safeString(errorState.status_message),
      retry_at_ms: retryAtMs,
    };
  }

  if (retryAtMs > 0 && now < retryAtMs) {
    return {
      state: 'cooldown',
      reason_code: normalizedReasonCode(account, 'cooldown_active') || 'cooldown_active',
      status_message: safeString(errorState.status_message || refreshState.last_error_message),
      retry_at_ms: retryAtMs,
    };
  }

  if (errorState.status === 'blocked_quota' || errorState.status === 'rate_limited') {
    return {
      state: 'blocked',
      reason_code: normalizedReasonCode(account, errorState.status || 'blocked_quota') || 'blocked_quota',
      status_message: safeString(errorState.status_message),
      retry_at_ms: retryAtMs,
    };
  }

  if (
    errorState.status === 'blocked_provider'
    || errorState.status === 'blocked_network'
    || errorState.status === 'blocked_config'
    || errorState.status === 'degraded'
  ) {
    return {
      state: 'blocked',
      reason_code: normalizedReasonCode(account, errorState.status || 'blocked_provider') || 'blocked_provider',
      status_message: safeString(errorState.status_message),
      retry_at_ms: retryAtMs,
    };
  }

  const quota = normalizeQuota(account?.quota);
  if (quota.daily_token_cap > 0 && quota.daily_tokens_used >= quota.daily_token_cap) {
    return {
      state: 'blocked',
      reason_code: normalizedReasonCode(account, 'daily_token_cap_exceeded') || 'daily_token_cap_exceeded',
      status_message: safeString(errorState.status_message),
      retry_at_ms: retryAtMs,
    };
  }

  return {
    state: 'ready',
    reason_code: '',
    status_message: '',
    retry_at_ms: retryAtMs,
  };
}

function removalReasonForAccountState(account, state) {
  const reasonCode = normalizedToken(state?.reason_code);
  if (state?.state === 'expired') return reasonCode || 'token_expired';
  if (!account?.enabled && reasonCode) return reasonCode;
  if (['auth_failed', 'blocked_auth', 'invalid_api_key', 'authentication_failed', 'token_expired'].includes(reasonCode)) {
    return reasonCode;
  }
  if (reasonCode.startsWith('refresh_http_401') || reasonCode.startsWith('refresh_http_403')) {
    return reasonCode;
  }
  return '';
}

function knownQuotaForAccount(account) {
  const quota = normalizeQuota(account?.quota);
  return quota.daily_token_cap > 0
    || quota.daily_tokens_used > 0
    || quota.daily_tokens_remaining > 0
    || quota.total_tokens_used > 0
    || quota.last_used_at_ms > 0
    || quota.last_error_at_ms > 0;
}

function normalizeOAuthRefreshConfig(raw) {
  const source = safeObject(raw);
  if (Object.keys(source).length === 0) return null;

  const scopeRaw = source.scopes ?? source.scope;
  const scopes = Array.isArray(scopeRaw)
    ? safeStringArray(scopeRaw)
    : safeString(scopeRaw)
      .split(/[\s,]+/g)
      .map((value) => safeString(value))
      .filter(Boolean);

  const config = {};
  const tokenURI = safeString(
    source.token_uri
    || source.tokenURI
    || source.tokenUrl
    || source.token_url
    || source['token-uri']
  );
  const clientID = safeString(
    source.client_id
    || source.clientId
    || source['client-id']
  );
  const clientSecret = safeString(
    source.client_secret
    || source.clientSecret
    || source['client-secret']
  );
  const universeDomain = safeString(
    source.universe_domain
    || source.universeDomain
    || source['universe-domain']
  );

  if (tokenURI) config.token_uri = tokenURI;
  if (clientID) config.client_id = clientID;
  if (clientSecret) config.client_secret = clientSecret;
  if (scopes.length > 0) config.scopes = scopes;
  if (universeDomain) config.universe_domain = universeDomain;

  return Object.keys(config).length > 0 ? config : null;
}

function normalizeAccount(raw) {
  if (!raw || typeof raw !== 'object') return null;

  const provider = normalizeProvider(raw.provider);
  if (!provider) return null;

  const apiKey = safeString(raw.api_key || raw.access_token || '');
  const refreshToken = safeString(raw.refresh_token || '');
  const authType = normalizeAuthType(raw.auth_type);
  const baseURL = safeString(raw.base_url || '');
  const proxyURL = safeString(raw.proxy_url || '');
  const customHeaders = safeStringMap(raw.custom_headers);
  const wireAPI = normalizeWireAPI(raw.wire_api);
  const oauthRefreshConfig = normalizeOAuthRefreshConfig(
    raw.oauth_refresh_config
    || raw.oauthRefreshConfig
    || raw.oauth_refresh
    || raw.oauthRefresh
  );
  const providerHost = safeString(raw.provider_host).toLowerCase()
    || resolvedProviderHost(provider, baseURL, proxyURL);
  const poolID = safeString(raw.pool_id)
    || derivedPoolID({
      provider,
      providerHost,
      wireAPI,
      baseURL,
      proxyURL,
      customHeaders,
    });

  if (authType === 'api_key' && !apiKey) return null;
  if (authType === 'oauth' && !apiKey && !refreshToken) return null;

  const email = safeString(raw.email || raw.username || '');
  const accountKey = safeString(raw.account_key) || buildAccountKey(provider, raw);

  const account = {
    account_key: accountKey,
    provider,
    pool_id: poolID,
    provider_host: providerHost,
    email,
    api_key: apiKey,
    refresh_token: refreshToken,
    base_url: baseURL,
    proxy_url: proxyURL,
    enabled: raw.enabled !== false,
    auth_type: authType,
    wire_api: wireAPI,
    expires_at_ms: safeInt(raw.expires_at_ms, 0),
    tier: safeString(raw.tier || ''),
    custom_headers: customHeaders,
    models: safeStringArray(raw.models),
    notes: safeString(raw.notes || ''),
    priority: safeInt(raw.priority, 0),
    account_id: safeString(raw.account_id || ''),
    source_type: safeString(raw.source_type || ''),
    source_ref: normalizePathRef(raw.source_ref || ''),
    oauth_source_key: safeString(raw.oauth_source_key || ''),
    oauth_refresh_config: oauthRefreshConfig,
    auth_index: safeInt(raw.auth_index, 0),
    source_owners: safeStringArray(raw.source_owners),
    created_at_ms: safeInt(raw.created_at_ms, 0) || nowMs(),
    updated_at_ms: safeInt(raw.updated_at_ms, 0) || safeInt(raw.created_at_ms, 0) || nowMs(),
    last_refresh_at_ms: safeInt(raw.last_refresh_at_ms, 0),
    quota: normalizeQuota(raw.quota),
    error_state: normalizeErrorState(raw.error_state),
    refresh_state: normalizeRefreshState(raw.refresh_state),
    model_states: normalizeModelStateMap(raw.model_states || raw.modelStates),
  };
  if (account.refresh_state.last_success_at_ms === 0 && account.last_refresh_at_ms > 0) {
    account.refresh_state.last_success_at_ms = account.last_refresh_at_ms;
  }

  return account;
}

let cache = {
  loaded_at_ms: 0,
  file_path: '',
  obj: null,
};

function emptyStore() {
  return {
    schema_version: SCHEMA_VERSION,
    updated_at_ms: 0,
    routing_strategy: 'fill-first',
    import_sources: [],
    import_source_statuses: {},
    providers: {},
  };
}

function countOwnedAccountsForSource(store, ownerKey) {
  if (!ownerKey) return 0;
  let count = 0;
  for (const providerData of Object.values(store?.providers || {})) {
    if (!providerData || !Array.isArray(providerData.accounts)) continue;
    for (const account of providerData.accounts) {
      if (safeStringArray(account?.source_owners).includes(ownerKey)) {
        count += 1;
      }
    }
  }
  return count;
}

function updateImportSourceStatusInStore(store, sourceInput, patch = {}) {
  const source = normalizeImportSource(sourceInput) || parseImportSourceKey(sourceInput);
  if (!source) return '';
  const sourceKey = importSourceKey(source.kind, source.source_ref);
  if (!sourceKey) return '';

  const current = normalizeImportSourceStatus(
    store?.import_source_statuses?.[sourceKey],
    sourceKey
  ) || {
    kind: source.kind,
    source_ref: source.source_ref,
    state: 'pending',
    last_sync_at_ms: 0,
    last_imported_count: 0,
    owned_account_count: 0,
    last_error_count: 0,
    last_errors: [],
    updated_at_ms: 0,
  };

  const has = (key) => Object.prototype.hasOwnProperty.call(patch, key);
  const lastErrors = has('last_errors')
    ? safeStringArray(patch.last_errors).slice(0, MAX_IMPORT_SOURCE_ERRORS)
    : current.last_errors;
  const ownedAccountCount = has('owned_account_count')
    ? safeInt(patch.owned_account_count, 0)
    : (patch.refresh_owned_account_count
        ? countOwnedAccountsForSource(store, sourceKey)
        : current.owned_account_count);
  const lastErrorCount = has('last_error_count')
    ? safeInt(patch.last_error_count, lastErrors.length)
    : Math.max(lastErrors.length, has('last_errors') ? 0 : current.last_error_count);

  store.import_source_statuses = {
    ...(store.import_source_statuses || {}),
    [sourceKey]: {
      kind: source.kind,
      source_ref: source.source_ref,
      state: has('state') ? normalizeImportSourceState(patch.state) : current.state,
      last_sync_at_ms: has('last_sync_at_ms')
        ? safeInt(patch.last_sync_at_ms, 0)
        : (patch.touch_last_sync ? nowMs() : current.last_sync_at_ms),
      last_imported_count: has('last_imported_count')
        ? safeInt(patch.last_imported_count, 0)
        : current.last_imported_count,
      owned_account_count: ownedAccountCount,
      last_error_count: lastErrorCount,
      last_errors: lastErrors,
      updated_at_ms: has('updated_at_ms') ? safeInt(patch.updated_at_ms, 0) : nowMs(),
    },
  };

  return sourceKey;
}

export function loadProviderKeyStore(runtimeBaseDir, maxAgeMs = 2000) {
  const fp = storePath(runtimeBaseDir);
  if (!fp) return emptyStore();

  const now = Date.now();
  if (cache.obj && cache.file_path === fp && now - cache.loaded_at_ms <= Math.max(200, Number(maxAgeMs || 0))) {
    return cache.obj;
  }

  const obj = readJsonSafe(fp);
  if (!obj || typeof obj !== 'object') {
    const empty = emptyStore();
    cache = { loaded_at_ms: now, file_path: fp, obj: empty };
    return empty;
  }

  const providers = {};
  const providersIn = (obj.providers && typeof obj.providers === 'object') ? obj.providers : {};
  for (const [providerId, providerData] of Object.entries(providersIn)) {
    const normalizedId = normalizeProvider(providerId);
    if (!normalizedId) continue;
    if (!providerData || typeof providerData !== 'object') continue;

    const accounts = Array.isArray(providerData.accounts) ? providerData.accounts : [];
    const normalizedAccounts = [];
    for (const raw of accounts) {
      const account = normalizeAccount({ ...raw, provider: normalizedId });
      if (account) normalizedAccounts.push(account);
    }

    providers[normalizedId] = {
      accounts: normalizedAccounts,
      routing_strategy: normalizeRoutingStrategy(providerData.routing_strategy),
    };
  }

  const out = {
    schema_version: SCHEMA_VERSION,
    updated_at_ms: safeInt(obj.updated_at_ms, 0),
    routing_strategy: normalizeRoutingStrategy(obj.routing_strategy),
    import_sources: normalizeImportSourceList(obj.import_sources),
    import_source_statuses: normalizeImportSourceStatusMap(obj.import_source_statuses),
    providers,
  };

  cache = { loaded_at_ms: now, file_path: fp, obj: out };
  return out;
}

export function saveProviderKeyStore(runtimeBaseDir, store) {
  const base = String(runtimeBaseDir || '').trim();
  if (!base) return false;

  const out = {
    schema_version: SCHEMA_VERSION,
    updated_at_ms: nowMs(),
    routing_strategy: store.routing_strategy || 'fill-first',
    import_sources: normalizeImportSourceList(store.import_sources),
    import_source_statuses: normalizeImportSourceStatusMap(store.import_source_statuses),
    providers: store.providers || {},
  };

  const ok = writeJsonAtomic(base, STORE_FILENAME, out);
  if (ok) {
    cache = { loaded_at_ms: Date.now(), file_path: storePath(base), obj: out };
  }
  return ok;
}

export function invalidateProviderKeyCache() {
  cache = { loaded_at_ms: 0, file_path: '', obj: null };
}

export function listProviderKeyImportSources(runtimeBaseDir) {
  return normalizeImportSourceList(loadProviderKeyStore(runtimeBaseDir).import_sources);
}

export function listProviderKeyImportSourceStatuses(runtimeBaseDir) {
  const store = loadProviderKeyStore(runtimeBaseDir);
  return Object.entries(normalizeImportSourceStatusMap(store.import_source_statuses)).map(([sourceKey, status]) => ({
    source_key: sourceKey,
    ...status,
  }));
}

export function recordProviderKeyImportSourceStatus(runtimeBaseDir, sourceInput, patch = {}) {
  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const sourceKey = updateImportSourceStatusInStore(store, sourceInput, patch);
  if (!sourceKey) {
    return { ok: false, error: 'invalid_import_source', source_key: '' };
  }
  const saved = saveProviderKeyStore(runtimeBaseDir, store);
  return {
    ok: saved,
    error: saved ? '' : 'save_failed',
    source_key: sourceKey,
  };
}

export function registerProviderKeyImportSource(runtimeBaseDir, sourceInput) {
  const sourceKey = normalizeImportSourceEntry(sourceInput);
  if (!sourceKey) {
    return { ok: false, error: 'invalid_import_source', registered: false };
  }

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const existing = new Set(normalizeImportSourceList(store.import_sources));
  const alreadyRegistered = existing.has(sourceKey);
  const hasStatus = !!normalizeImportSourceStatus(store.import_source_statuses?.[sourceKey], sourceKey);
  if (alreadyRegistered && hasStatus) {
    return { ok: true, error: '', registered: false };
  }

  existing.add(sourceKey);
  store.import_sources = [...existing].sort((lhs, rhs) => lhs.localeCompare(rhs));
  if (!hasStatus) {
    updateImportSourceStatusInStore(store, sourceKey, {
      state: 'pending',
      refresh_owned_account_count: true,
      last_error_count: 0,
      last_errors: [],
    });
  }
  const saved = saveProviderKeyStore(runtimeBaseDir, store);
  return {
    ok: saved,
    error: saved ? '' : 'save_failed',
    registered: saved && !alreadyRegistered,
  };
}

export function pruneProviderKeyImportOwner(runtimeBaseDir, sourceInput) {
  const ownerKey = normalizeImportSourceEntry(sourceInput);
  if (!ownerKey) {
    return { ok: false, error: 'invalid_import_source', removed: 0 };
  }

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  let removed = 0;
  for (const providerData of Object.values(store.providers)) {
    if (!providerData || !Array.isArray(providerData.accounts)) continue;
    const nextAccounts = [];
    for (const account of providerData.accounts) {
      const owners = safeStringArray(account?.source_owners);
      if (!owners.includes(ownerKey)) {
        nextAccounts.push(account);
        continue;
      }
      const remainingOwners = owners.filter((owner) => owner !== ownerKey);
      if (remainingOwners.length > 0) {
        account.source_owners = remainingOwners;
        nextAccounts.push(account);
        continue;
      }
      removed += 1;
    }
    providerData.accounts = nextAccounts;
  }
  updateImportSourceStatusInStore(store, ownerKey, {
    refresh_owned_account_count: true,
  });

  const saved = saveProviderKeyStore(runtimeBaseDir, store);
  return {
    ok: saved,
    error: saved ? '' : 'save_failed',
    removed: saved ? removed : 0,
  };
}

export function listProviderKeys(runtimeBaseDir, providerFilter) {
  const store = loadProviderKeyStore(runtimeBaseDir);
  const result = [];

  for (const [providerId, providerData] of Object.entries(store.providers)) {
    if (providerFilter && providerId !== providerFilter) continue;
    for (const account of providerData.accounts) {
      result.push({
        ...account,
        api_key: redactApiKey(account.api_key),
        refresh_token: account.refresh_token ? '****' : '',
      });
    }
  }

  return result;
}

export function listProviderKeysFull(runtimeBaseDir, providerFilter) {
  const store = loadProviderKeyStore(runtimeBaseDir);
  const result = [];

  for (const [providerId, providerData] of Object.entries(store.providers)) {
    if (providerFilter && providerId !== providerFilter) continue;
    for (const account of providerData.accounts) {
      result.push(account);
    }
  }

  return result;
}

function providerMatchesPoolFilter(account, providerFilter) {
  const filter = normalizeProvider(providerFilter) || normalizedToken(providerFilter);
  if (!filter) return true;
  return canonicalPoolProvider(account?.provider) === canonicalPoolProvider(filter);
}

function isAuthFailureReason(reasonCode) {
  const normalized = normalizedToken(reasonCode);
  if (!normalized) return false;
  return [
    'auth_failed',
    'blocked_auth',
    'invalid_api_key',
    'authentication_failed',
    'missing_scope',
    'scope_missing',
    'token_expired',
    'invalid_grant',
    'invalid_client',
    'unauthorized_client',
    'access_denied',
    'refresh_token_reused',
  ].includes(normalized)
    || normalized.startsWith('refresh_http_401')
    || normalized.startsWith('refresh_http_403');
}

function isQuotaFailureReason(reasonCode) {
  const normalized = normalizedToken(reasonCode);
  if (!normalized) return false;
  return [
    'blocked_quota',
    'quota_exceeded',
    'rate_limited',
    'rate_limit_exceeded',
    'insufficient_quota',
    'daily_token_cap_exceeded',
  ].includes(normalized)
    || normalized.startsWith('http_429');
}

function isNetworkFailureReason(reasonCode) {
  const normalized = normalizedToken(reasonCode);
  if (!normalized) return false;
  return [
    'blocked_network',
    'network_unreachable',
    'provider_timeout',
    'timeout',
    'timed_out',
    'fetch_failed',
    'network_error',
    'dns_error',
    'connection_refused',
    'connection_reset',
  ].includes(normalized)
    || normalized.startsWith('http_408')
    || normalized.startsWith('http_504');
}

function isConfigFailureReason(reasonCode) {
  const normalized = normalizedToken(reasonCode);
  if (!normalized) return false;
  return [
    'blocked_config',
    'invalid_base_url',
    'auth_missing',
    'missing_api_key',
    'invalid_request_shape',
    'invalid_request',
    'invalid_model_request',
    'model_unsupported',
    'unsupported_refresh_schema',
    'missing_refresh_token',
    'missing_oauth_client',
    'missing_oauth_client_id',
    'missing_oauth_client_secret',
    'missing_oauth_client_credentials',
  ].includes(normalized);
}

function normalizedRuntimeEventOutcome(raw) {
  const normalized = normalizedToken(raw);
  if (!normalized) return '';
  switch (normalized) {
    case 'success':
      return 'success';
    case 'auth_error':
      return 'auth_error';
    case 'quota_error':
      return 'quota_error';
    case 'network_error':
      return 'network_error';
    case 'provider_error':
      return 'provider_error';
    case 'config_error':
      return 'config_error';
    default:
      return '';
  }
}

function normalizedRuntimeEventReason(raw, fallback = '') {
  const normalized = normalizedToken(raw || fallback);
  return normalized || normalizedToken(fallback);
}

function normalizedRuntimeEventMessage(raw, fallback = '') {
  return safeString(raw || fallback);
}

function inferredProviderErrorStatus({
  account,
  outcome,
  reasonCode,
  httpStatus,
}) {
  const normalizedOutcome = normalizedRuntimeEventOutcome(outcome);
  const normalizedReason = normalizedRuntimeEventReason(reasonCode);
  const statusCode = safeInt(httpStatus, 0);

  if (
    normalizedOutcome === 'auth_error'
    || isAuthFailureReason(normalizedReason)
    || normalizedReason === '401'
    || normalizedReason === '403'
    || statusCode === 401
    || statusCode === 403
  ) {
    if (normalizedReason === 'missing_scope' || normalizedReason === 'scope_missing') {
      return 'blocked_auth';
    }
    if (normalizedReason === 'token_expired' && safeString(account?.refresh_token)) {
      return 'blocked_auth';
    }
    return 'auth_failed';
  }
  if (
    normalizedOutcome === 'quota_error'
    || isQuotaFailureReason(normalizedReason)
    || normalizedReason === '402'
    || normalizedReason === '429'
    || statusCode === 402
    || statusCode === 429
  ) {
    if (normalizedReason === '429'
        || normalizedReason === 'rate_limited'
        || normalizedReason === 'rate_limit_exceeded'
        || statusCode === 429) {
      return 'rate_limited';
    }
    return 'blocked_quota';
  }
  if (
    normalizedOutcome === 'network_error'
    || isNetworkFailureReason(normalizedReason)
    || normalizedReason === '408'
    || normalizedReason === '504'
  ) {
    return 'blocked_network';
  }
  if (normalizedOutcome === 'config_error' || isConfigFailureReason(normalizedReason)) {
    return 'blocked_config';
  }
  if (normalizedOutcome === 'provider_error') {
    return 'blocked_provider';
  }
  return 'blocked_provider';
}

function inferredProviderErrorAutoDisabled({
  account,
  status,
  reasonCode,
  httpStatus,
}) {
  const normalizedStatus = safeString(status);
  const normalizedReason = normalizedRuntimeEventReason(reasonCode);
  const statusCode = safeInt(httpStatus, 0);
  if (normalizedStatus === 'auth_failed') {
    if (normalizedReason === 'missing_scope' || normalizedReason === 'scope_missing') return false;
    if (normalizedReason === 'token_expired' && safeString(account?.refresh_token)) return false;
    if (normalizedReason === '401' || normalizedReason === '403') return true;
    return true;
  }
  return false;
}

export function normalizeProviderRetrySource(rawSource, {
  status = '',
  reasonCode = '',
  nextRetryAtMs = 0,
  quotaCooldownUntilMs = 0,
} = {}) {
  const normalized = normalizedToken(rawSource);
  if (normalized === 'quota_refresh' || normalized === 'codex_usage') {
    return 'usage_window';
  }
  if (normalized === 'refresh_schema') {
    return 'manual';
  }
  if ([
    'quota',
    'provider_header',
    'usage_window',
    'scheduler',
    'refresh',
    'manual',
  ].includes(normalized)) {
    return normalized;
  }

  const normalizedStatus = normalizedToken(status);
  const normalizedReason = normalizedRuntimeEventReason(reasonCode);
  const resolvedNextRetryAtMs = safeInt(nextRetryAtMs, 0);
  const resolvedQuotaCooldownUntilMs = safeInt(quotaCooldownUntilMs, 0);

  if (normalizedReason === 'token_expired') {
    return 'refresh';
  }
  if (
    [
      'missing_scope',
      'scope_missing',
      'auth_missing',
      'model_not_supported',
      'model_not_configured',
      'unsupported_refresh_schema',
    ].includes(normalizedReason)
    || ['blocked_auth', 'auth_failed', 'blocked_config'].includes(normalizedStatus)
  ) {
    return 'manual';
  }
  if (
    ['blocked_quota', 'rate_limited'].includes(normalizedStatus)
    || resolvedQuotaCooldownUntilMs > 0
  ) {
    return resolvedNextRetryAtMs > 0 || resolvedQuotaCooldownUntilMs > 0 ? 'quota' : '';
  }
  if (['blocked_network', 'blocked_provider', 'degraded'].includes(normalizedStatus)) {
    return resolvedNextRetryAtMs > 0 ? 'scheduler' : '';
  }
  return '';
}

function inferredProviderErrorRetrySource({
  account,
  status,
  outcome,
  reasonCode,
  explicitRetrySource,
}) {
  const explicit = normalizeProviderRetrySource(explicitRetrySource, {
    status,
    reasonCode,
  });
  if (explicit) return explicit;
  const normalizedStatus = safeString(status);
  const normalizedOutcome = normalizedRuntimeEventOutcome(outcome);
  const normalizedReason = normalizedRuntimeEventReason(reasonCode);
  return normalizeProviderRetrySource('', {
    status: normalizedStatus,
    reasonCode: normalizedReason === 'token_expired' && !safeString(account?.refresh_token)
      ? 'auth_failed'
      : normalizedReason,
    nextRetryAtMs: (
      normalizedStatus === 'blocked_quota'
      || normalizedStatus === 'rate_limited'
      || normalizedOutcome === 'network_error'
      || normalizedOutcome === 'provider_error'
      || (normalizedReason === 'token_expired' && safeString(account?.refresh_token))
    ) ? 1 : 0,
  });
}

function inferredProviderErrorRetryAtMs({
  now,
  status,
  reasonCode,
  explicitNextRetryAtMs,
  explicitRetrySource,
  quota,
}) {
  const explicit = safeInt(explicitNextRetryAtMs, 0);
  if (explicit > 0) return explicit;

  const normalizedStatus = safeString(status);
  const normalizedReason = normalizedRuntimeEventReason(reasonCode);
  const retrySource = safeString(explicitRetrySource);

  if (normalizedStatus === 'blocked_quota' || normalizedStatus === 'rate_limited') {
    if (safeInt(quota?.cooldown_until_ms, 0) > now) {
      return safeInt(quota?.cooldown_until_ms, 0);
    }
    return now + 30_000;
  }
  if (normalizedStatus === 'blocked_network') {
    return now + 60_000;
  }
  if (normalizedStatus === 'blocked_provider') {
    return now + 30_000;
  }
  if (normalizedStatus === 'blocked_auth' || normalizedStatus === 'auth_failed' || normalizedStatus === 'blocked_config') {
    return retrySource === 'refresh' ? now + 60_000 : 0;
  }
  if (normalizedReason === 'provider_timeout') {
    return now + 60_000;
  }
  return 0;
}

function stateSortWeight(state) {
  switch (safeString(state)) {
    case 'ready':
      return 0;
    case 'cooldown':
      return 1;
    case 'blocked':
      return 2;
    case 'expired':
      return 3;
    case 'disabled':
      return 4;
    case 'stale':
      return 5;
    default:
      return 6;
  }
}

function summarizedPoolState(pool) {
  if (pool.ready_accounts > 0) return 'ready';
  if (pool.cooldown_accounts > 0) return 'cooldown';
  if (pool.blocked_accounts > 0) return 'blocked';
  if (pool.expired_accounts > 0 && pool.expired_accounts === pool.total_accounts) return 'expired';
  if (pool.disabled_accounts > 0 && pool.disabled_accounts === pool.total_accounts) return 'disabled';
  if (pool.stale_accounts > 0 && pool.stale_accounts === pool.total_accounts) return 'stale';
  if (pool.expired_accounts > 0) return 'blocked';
  if (pool.disabled_accounts > 0) return 'disabled';
  if (pool.stale_accounts > 0) return 'stale';
  return 'empty';
}

function accountEffectivePoolId(account) {
  return safeString(account?.pool_id)
    || derivedPoolID({
      provider: account?.provider,
      providerHost: account?.provider_host,
      wireAPI: account?.wire_api,
      baseURL: account?.base_url,
      proxyURL: account?.proxy_url,
      customHeaders: account?.custom_headers,
    });
}

export function listProviderKeyPools(runtimeBaseDir, options = {}) {
  const store = loadProviderKeyStore(runtimeBaseDir);
  const providerFilter = safeString(options?.provider);
  const modelID = safeString(options?.model_id || options?.modelId);
  const includeMembers = options?.include_members !== false && options?.includeMembers !== false;
  const modelFamily = deriveCapabilityModelFamily(modelID);
  const pools = new Map();
  const now = nowMs();

  for (const providerData of Object.values(store.providers || {})) {
    if (!providerData || !Array.isArray(providerData.accounts)) continue;
    for (const account of providerData.accounts) {
      if (!providerMatchesPoolFilter(account, providerFilter)) continue;
      if (!accountSupportsCapabilityTarget(account, modelID)) continue;

      const canonicalProvider = canonicalPoolProvider(account?.provider) || safeString(account?.provider);
      const poolID = accountEffectivePoolId(account);
      const capabilityPoolID = `${poolID}#${canonicalProvider}:${modelFamily}`;

      let summary = pools.get(capabilityPoolID);
      if (!summary) {
        summary = {
          pool_id: poolID,
          capability_pool_id: capabilityPoolID,
          provider: canonicalProvider,
          provider_host: safeString(account?.provider_host),
          wire_api: normalizeWireAPI(account?.wire_api),
          model_id: modelID,
          model_family: modelFamily,
          state: 'empty',
          total_accounts: 0,
          enabled_accounts: 0,
          ready_accounts: 0,
          cooldown_accounts: 0,
          blocked_accounts: 0,
          expired_accounts: 0,
          disabled_accounts: 0,
          stale_accounts: 0,
          auth_failed_accounts: 0,
          free_accounts: 0,
          paid_accounts: 0,
          unknown_tier_accounts: 0,
          removable_accounts: 0,
          known_quota_accounts: 0,
          daily_token_cap: 0,
          daily_tokens_used: 0,
          daily_tokens_remaining: 0,
          total_tokens_used: 0,
          next_retry_at_ms: 0,
          last_used_at_ms: 0,
          last_refresh_at_ms: 0,
          blocker_reason_codes: [],
          source_providers: [],
          members: [],
          _reason_counts: {},
          _source_provider_set: new Set(),
        };
        pools.set(capabilityPoolID, summary);
      }

      const quota = normalizeQuota(account?.quota);
      const state = accountPoolState(account, now, modelID);
      const tierBucket = normalizeTierBucket(account?.tier);
      const removalReason = removalReasonForAccountState(account, state);

      summary.total_accounts += 1;
      if (account?.enabled) summary.enabled_accounts += 1;
      if (state.state === 'ready') summary.ready_accounts += 1;
      if (state.state === 'cooldown') summary.cooldown_accounts += 1;
      if (state.state === 'blocked') summary.blocked_accounts += 1;
      if (state.state === 'expired') summary.expired_accounts += 1;
      if (state.state === 'disabled') summary.disabled_accounts += 1;
      if (state.state === 'stale') summary.stale_accounts += 1;
      if (isAuthFailureReason(removalReason || state.reason_code)) summary.auth_failed_accounts += 1;
      if (tierBucket === 'free') summary.free_accounts += 1;
      else if (isPaidTierBucket(tierBucket)) summary.paid_accounts += 1;
      else summary.unknown_tier_accounts += 1;
      if (removalReason) summary.removable_accounts += 1;
      if (knownQuotaForAccount(account)) summary.known_quota_accounts += 1;

      summary.daily_token_cap += quota.daily_token_cap;
      summary.daily_tokens_used += quota.daily_tokens_used;
      summary.daily_tokens_remaining += quota.daily_tokens_remaining;
      summary.total_tokens_used += quota.total_tokens_used;
      summary.last_used_at_ms = Math.max(summary.last_used_at_ms, quota.last_used_at_ms || 0);
      summary.last_refresh_at_ms = Math.max(
        summary.last_refresh_at_ms,
        safeInt(account?.last_refresh_at_ms, 0),
        safeInt(account?.refresh_state?.last_success_at_ms, 0)
      );
      if (state.retry_at_ms > now) {
        summary.next_retry_at_ms = summary.next_retry_at_ms > 0
          ? Math.min(summary.next_retry_at_ms, state.retry_at_ms)
          : state.retry_at_ms;
      }
      if (state.reason_code) {
        summary._reason_counts[state.reason_code] = safeInt(summary._reason_counts[state.reason_code], 0) + 1;
      }
      summary._source_provider_set.add(safeString(account?.provider));

      if (includeMembers) {
        summary.members.push({
          account_key: safeString(account?.account_key),
          provider: safeString(account?.provider),
          email: safeString(account?.email),
          tier: safeString(account?.tier),
          enabled: account?.enabled !== false,
          auth_type: safeString(account?.auth_type),
          account_id: safeString(account?.account_id),
          source_ref: safeString(account?.source_ref),
          oauth_source_key: safeString(account?.oauth_source_key),
          pool_id: poolID,
          state: state.state,
          reason_code: safeString(state.reason_code),
          status_message: safeString(state.status_message),
          retry_at_ms: safeInt(state.retry_at_ms, 0),
          expires_at_ms: safeInt(account?.expires_at_ms, 0),
          last_refresh_at_ms: Math.max(
            safeInt(account?.last_refresh_at_ms, 0),
            safeInt(account?.refresh_state?.last_success_at_ms, 0)
          ),
          last_used_at_ms: safeInt(quota.last_used_at_ms, 0),
          daily_token_cap: safeInt(quota.daily_token_cap, 0),
          daily_tokens_used: safeInt(quota.daily_tokens_used, 0),
          daily_tokens_remaining: safeInt(quota.daily_tokens_remaining, 0),
          total_tokens_used: safeInt(quota.total_tokens_used, 0),
          removable: !!removalReason,
          removal_reason: removalReason,
          api_key_redacted: redactApiKey(account?.api_key),
        });
      }
    }
  }

  const out = [];
  for (const summary of pools.values()) {
    summary.state = summarizedPoolState(summary);
    summary.source_providers = Array.from(summary._source_provider_set).sort((lhs, rhs) => lhs.localeCompare(rhs));
    summary.blocker_reason_codes = Object.entries(summary._reason_counts)
      .sort((lhs, rhs) => {
        if (rhs[1] !== lhs[1]) return rhs[1] - lhs[1];
        return lhs[0].localeCompare(rhs[0]);
      })
      .map(([reason]) => reason);
    if (includeMembers) {
      summary.members.sort((lhs, rhs) => {
        const stateOrder = stateSortWeight(lhs.state) - stateSortWeight(rhs.state);
        if (stateOrder !== 0) return stateOrder;
        const retryOrder = safeInt(lhs.retry_at_ms, 0) - safeInt(rhs.retry_at_ms, 0);
        if (retryOrder !== 0) return retryOrder;
        return safeString(lhs.email || lhs.account_key).localeCompare(safeString(rhs.email || rhs.account_key));
      });
    } else {
      summary.members = [];
    }
    delete summary._reason_counts;
    delete summary._source_provider_set;
    out.push(summary);
  }

  out.sort((lhs, rhs) => {
    if (rhs.ready_accounts !== lhs.ready_accounts) return rhs.ready_accounts - lhs.ready_accounts;
    if (rhs.total_accounts !== lhs.total_accounts) return rhs.total_accounts - lhs.total_accounts;
    return safeString(lhs.capability_pool_id).localeCompare(safeString(rhs.capability_pool_id));
  });
  return out;
}

function refreshOwnedAccountCountsForAllSources(store) {
  const owners = new Set(Object.keys(store?.import_source_statuses || {}));
  for (const providerData of Object.values(store?.providers || {})) {
    if (!providerData || !Array.isArray(providerData.accounts)) continue;
    for (const account of providerData.accounts) {
      for (const owner of safeStringArray(account?.source_owners)) {
        owners.add(owner);
      }
    }
  }
  for (const owner of owners) {
    updateImportSourceStatusInStore(store, owner, {
      refresh_owned_account_count: true,
    });
  }
}

function removeProviderKeysInStore(store, accountKeys) {
  const requestedKeys = safeStringArray(accountKeys);
  const targetSet = new Set(requestedKeys);
  const foundSet = new Set();
  let removed = 0;

  if (targetSet.size === 0) {
    return {
      removed,
      missing_account_keys: [],
    };
  }

  for (const [providerId, providerData] of Object.entries(store.providers || {})) {
    if (!providerData || !Array.isArray(providerData.accounts)) continue;
    const nextAccounts = [];
    for (const account of providerData.accounts) {
      if (!targetSet.has(account?.account_key)) {
        nextAccounts.push(account);
        continue;
      }
      foundSet.add(account.account_key);
      removed += 1;
    }
    if (nextAccounts.length > 0) {
      providerData.accounts = nextAccounts;
    } else {
      delete store.providers[providerId];
    }
  }

  refreshOwnedAccountCountsForAllSources(store);
  return {
    removed,
    missing_account_keys: requestedKeys.filter((key) => !foundSet.has(key)),
  };
}

export function addProviderKey(runtimeBaseDir, accountInput) {
  const account = normalizeAccount(accountInput);
  if (!account) return { ok: false, error: 'invalid_account' };

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const providerId = account.provider;

  if (!store.providers[providerId]) {
    store.providers[providerId] = { accounts: [], routing_strategy: 'fill-first' };
  }

  const existing = store.providers[providerId].accounts;
  if (existing.length >= MAX_ACCOUNTS_PER_PROVIDER) {
    return { ok: false, error: 'max_accounts_reached' };
  }

  const duplicateKey = existing.find(a => a.api_key && a.api_key === account.api_key);
  if (duplicateKey) {
    return { ok: false, error: 'duplicate_api_key', account_key: duplicateKey.account_key };
  }

  existing.push(account);
  const saved = saveProviderKeyStore(runtimeBaseDir, store);
  return { ok: saved, account_key: account.account_key, error: saved ? '' : 'save_failed' };
}

function updateExistingAccountInPlace(existing, incoming) {
  existing.email = incoming.email;
  existing.api_key = incoming.api_key;
  existing.refresh_token = incoming.refresh_token;
  existing.base_url = incoming.base_url;
  existing.proxy_url = incoming.proxy_url;
  existing.enabled = incoming.enabled;
  existing.auth_type = incoming.auth_type;
  existing.wire_api = incoming.wire_api;
  existing.provider_host = incoming.provider_host;
  existing.pool_id = incoming.pool_id;
  existing.expires_at_ms = incoming.expires_at_ms;
  existing.tier = incoming.tier;
  existing.custom_headers = incoming.custom_headers;
  existing.models = incoming.models;
  existing.notes = incoming.notes;
  existing.priority = incoming.priority;
  existing.account_id = incoming.account_id || existing.account_id || '';
  existing.source_type = incoming.source_type || existing.source_type || '';
  existing.source_ref = incoming.source_ref || existing.source_ref || '';
  existing.oauth_source_key = incoming.oauth_source_key || existing.oauth_source_key || '';
  existing.oauth_refresh_config = incoming.oauth_refresh_config || null;
  existing.auth_index = incoming.auth_index !== undefined
    ? safeInt(incoming.auth_index, 0)
    : (existing.auth_index || 0);
  existing.source_owners = safeStringArray([
    ...(Array.isArray(existing.source_owners) ? existing.source_owners : []),
    ...(Array.isArray(incoming.source_owners) ? incoming.source_owners : []),
  ]);
  existing.last_refresh_at_ms = incoming.last_refresh_at_ms || existing.last_refresh_at_ms || 0;
  existing.error_state = normalizeErrorState({
    ...existing.error_state,
    ...incoming.error_state,
  });
  existing.refresh_state = normalizeRefreshState({
    ...existing.refresh_state,
    ...incoming.refresh_state,
  });
  existing.model_states = normalizeModelStateMap({
    ...existing.model_states,
    ...incoming.model_states,
  });
  if (existing.refresh_state.last_success_at_ms === 0 && existing.last_refresh_at_ms > 0) {
    existing.refresh_state.last_success_at_ms = existing.last_refresh_at_ms;
  }
  existing.updated_at_ms = nowMs();
}

function refreshDerivedAccountFields(account) {
  if (!account || typeof account !== 'object') return;
  account.custom_headers = safeStringMap(account.custom_headers);
  account.wire_api = normalizeWireAPI(account.wire_api);
  account.provider_host = safeString(account.provider_host).toLowerCase()
    || resolvedProviderHost(account.provider, account.base_url, account.proxy_url);
  account.pool_id = safeString(account.pool_id)
    || derivedPoolID({
      provider: account.provider,
      providerHost: account.provider_host,
      wireAPI: account.wire_api,
      baseURL: account.base_url,
      proxyURL: account.proxy_url,
      customHeaders: account.custom_headers,
    });
}

function shouldMatchImportedSource(existing, incoming) {
  if (!existing || !incoming) return false;
  if (safeString(existing.source_type) !== safeString(incoming.source_type)) return false;
  if (safeString(incoming.source_type) !== 'auth_file') return false;
  return safeString(existing.source_ref) === safeString(incoming.source_ref);
}

function upsertImportedAccount(runtimeBaseDir, accountInput) {
  const account = normalizeAccount(accountInput);
  if (!account) return { ok: false, error: 'invalid_account' };

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const providerId = account.provider;
  if (!store.providers[providerId]) {
    store.providers[providerId] = { accounts: [], routing_strategy: 'fill-first' };
  }

  const existingAccounts = store.providers[providerId].accounts;
  const existing = existingAccounts.find((row) => row.account_key === account.account_key)
    || (account.source_ref
      ? existingAccounts.find((row) => shouldMatchImportedSource(row, account))
      : null)
    || existingAccounts.find((row) => row.api_key && row.api_key === account.api_key);

  if (existing) {
    updateExistingAccountInPlace(existing, account);
    const saved = saveProviderKeyStore(runtimeBaseDir, store);
    return {
      ok: saved,
      updated: true,
      account_key: existing.account_key,
      error: saved ? '' : 'save_failed',
    };
  }

  if (existingAccounts.length >= MAX_ACCOUNTS_PER_PROVIDER) {
    return { ok: false, error: 'max_accounts_reached' };
  }

  existingAccounts.push(account);
  const saved = saveProviderKeyStore(runtimeBaseDir, store);
  return {
    ok: saved,
    updated: false,
    account_key: account.account_key,
    error: saved ? '' : 'save_failed',
  };
}

export function removeProviderKey(runtimeBaseDir, accountKey) {
  const ak = safeString(accountKey);
  if (!ak) return { ok: false, error: 'missing_account_key' };

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const removed = removeProviderKeysInStore(store, [ak]);
  if (removed.removed === 0) {
    return { ok: false, error: 'account_not_found' };
  }
  const saved = saveProviderKeyStore(runtimeBaseDir, store);
  return { ok: saved, error: saved ? '' : 'save_failed' };
}

export function removeProviderKeys(runtimeBaseDir, accountKeys) {
  const requestedKeys = safeStringArray(accountKeys);
  if (requestedKeys.length === 0) {
    return { ok: false, error: 'missing_account_keys', removed: 0, missing_account_keys: [] };
  }

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const result = removeProviderKeysInStore(store, requestedKeys);
  if (result.removed === 0) {
    return {
      ok: false,
      error: 'accounts_not_found',
      removed: 0,
      missing_account_keys: result.missing_account_keys,
    };
  }

  const saved = saveProviderKeyStore(runtimeBaseDir, store);
  return {
    ok: saved,
    error: saved ? '' : 'save_failed',
    removed: saved ? result.removed : 0,
    missing_account_keys: result.missing_account_keys,
  };
}

export function updateProviderKey(runtimeBaseDir, accountKey, updates) {
  const ak = safeString(accountKey);
  if (!ak) return { ok: false, error: 'missing_account_key' };

  const store = loadProviderKeyStore(runtimeBaseDir, 0);

  for (const providerData of Object.values(store.providers)) {
    const account = providerData.accounts.find(a => a.account_key === ak);
    if (!account) continue;
    const shouldRecomputePool = updates.base_url !== undefined
      || updates.proxy_url !== undefined
      || updates.custom_headers !== undefined
      || updates.wire_api !== undefined;

    if (updates.email !== undefined) account.email = safeString(updates.email);
    if (updates.account_id !== undefined) account.account_id = safeString(updates.account_id);
    if (updates.api_key !== undefined) account.api_key = safeString(updates.api_key);
    if (updates.refresh_token !== undefined) account.refresh_token = safeString(updates.refresh_token);
    if (updates.base_url !== undefined) account.base_url = safeString(updates.base_url);
    if (updates.proxy_url !== undefined) account.proxy_url = safeString(updates.proxy_url);
    if (updates.enabled !== undefined) account.enabled = !!updates.enabled;
    if (updates.tier !== undefined) account.tier = safeString(updates.tier);
    if (updates.notes !== undefined) account.notes = safeString(updates.notes);
    if (updates.priority !== undefined) account.priority = safeInt(updates.priority, 0);
    if (updates.auth_type !== undefined) account.auth_type = normalizeAuthType(updates.auth_type);
    if (updates.oauth_refresh_config !== undefined || updates.oauthRefreshConfig !== undefined) {
      account.oauth_refresh_config = normalizeOAuthRefreshConfig(
        updates.oauth_refresh_config ?? updates.oauthRefreshConfig
      );
    }
    if (updates.expires_at_ms !== undefined) account.expires_at_ms = safeInt(updates.expires_at_ms, 0);
    if (updates.custom_headers !== undefined && typeof updates.custom_headers === 'object') {
      account.custom_headers = safeStringMap(updates.custom_headers);
    }
    if (updates.models !== undefined && Array.isArray(updates.models)) {
      account.models = safeStringArray(updates.models);
    }
    if (updates.wire_api !== undefined) {
      account.wire_api = normalizeWireAPI(updates.wire_api);
    }
    if (updates.last_refresh_at_ms !== undefined) {
      account.last_refresh_at_ms = safeInt(updates.last_refresh_at_ms, 0);
    }
    if (updates.quota !== undefined && updates.quota && typeof updates.quota === 'object') {
      account.quota = normalizeQuota({
        ...account.quota,
        ...updates.quota,
      });
    }
    if (updates.error_state !== undefined && updates.error_state && typeof updates.error_state === 'object') {
      account.error_state = normalizeErrorState({
        ...account.error_state,
        ...updates.error_state,
      });
    }
    if (updates.refresh_state !== undefined && updates.refresh_state && typeof updates.refresh_state === 'object') {
      account.refresh_state = normalizeRefreshState({
        ...account.refresh_state,
        ...updates.refresh_state,
      });
      if (account.refresh_state.last_success_at_ms === 0 && account.last_refresh_at_ms > 0) {
        account.refresh_state.last_success_at_ms = account.last_refresh_at_ms;
      }
    }
    if (updates.model_states !== undefined && updates.model_states && typeof updates.model_states === 'object') {
      account.model_states = normalizeModelStateMap({
        ...account.model_states,
        ...updates.model_states,
      });
    }
    if (updates.pool_id !== undefined) {
      account.pool_id = safeString(updates.pool_id);
    }
    if (updates.provider_host !== undefined) {
      account.provider_host = safeString(updates.provider_host).toLowerCase();
    }
    if (shouldRecomputePool && updates.provider_host === undefined) {
      account.provider_host = '';
    }
    if (shouldRecomputePool && updates.pool_id === undefined) {
      account.pool_id = '';
    }

    refreshDerivedAccountFields(account);
    account.updated_at_ms = nowMs();
    const saved = saveProviderKeyStore(runtimeBaseDir, store);
    return { ok: saved, error: saved ? '' : 'save_failed' };
  }

  return { ok: false, error: 'account_not_found' };
}

export function setProviderRoutingStrategy(runtimeBaseDir, provider, strategy) {
  const providerId = normalizeProvider(provider);
  if (!providerId) return { ok: false, error: 'invalid_provider' };
  const rawStrategy = safeString(strategy).toLowerCase();
  if (!VALID_ROUTING_STRATEGIES.has(rawStrategy)) return { ok: false, error: 'invalid_strategy' };

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  if (!store.providers[providerId]) {
    store.providers[providerId] = { accounts: [], routing_strategy: rawStrategy };
  } else {
    store.providers[providerId].routing_strategy = rawStrategy;
  }

  const saved = saveProviderKeyStore(runtimeBaseDir, store);
  return { ok: saved, error: saved ? '' : 'save_failed' };
}

export function getProviderRoutingStrategy(runtimeBaseDir, provider) {
  const providerId = normalizeProvider(provider);
  if (!providerId) return 'fill-first';
  const store = loadProviderKeyStore(runtimeBaseDir);
  return store.providers[providerId]?.routing_strategy || 'fill-first';
}

export function selectProviderKey(runtimeBaseDir, provider, modelId) {
  const providerId = normalizeProvider(provider);
  if (!providerId) return null;

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const providerData = store.providers[providerId];
  if (!providerData) return null;

  const now = nowMs();
  const scoped = safeString(modelId)
    ? providerData.accounts.filter((account) => accountPoolState(account, now, modelId).state === 'ready')
    : providerData.accounts.filter((account) => accountPoolState(account, now).state === 'ready');
  if (scoped.length === 0) return null;

  const strategy = providerData.routing_strategy || 'fill-first';

  switch (strategy) {
    case 'round-robin': {
      const idx = safeInt(process.env.__HUB_KEY_RR_INDEX, 0) % scoped.length;
      process.env.__HUB_KEY_RR_INDEX = String(idx + 1);
      return scoped[idx];
    }
    case 'priority': {
      const sorted = [...scoped].sort((a, b) => b.priority - a.priority);
      return sorted[0];
    }
    case 'fill-first':
    default:
      return scoped[0];
  }
}

function parseDateLikeToMs(rawValue) {
  const raw = rawValue == null ? '' : String(rawValue).trim();
  if (!raw) return 0;
  const numeric = Number(raw);
  if (Number.isFinite(numeric) && numeric > 0) {
    if (numeric > 10_000_000_000) return Math.floor(numeric);
    return Math.floor(numeric * 1000);
  }
  const parsed = Date.parse(raw);
  return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
}

function parseJsonFile(filePath) {
  const raw = readJsonSafe(filePath);
  if (!raw || typeof raw !== 'object') return null;
  return raw;
}

function decodeJwtPayload(token) {
  const raw = safeString(token);
  if (!raw) return null;
  const parts = raw.split('.');
  if (parts.length < 2) return null;
  try {
    const normalized = parts[1]
      .replace(/-/g, '+')
      .replace(/_/g, '/')
      .padEnd(Math.ceil(parts[1].length / 4) * 4, '=');
    const decoded = Buffer.from(normalized, 'base64').toString('utf8');
    const payload = JSON.parse(decoded);
    return payload && typeof payload === 'object' ? payload : null;
  } catch {
    return null;
  }
}

function parseTomlStringValue(rawContent, key) {
  const escapedKey = String(key || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`^\\s*${escapedKey}\\s*=\\s*"([^"]*)"\\s*$`, 'm');
  const match = String(rawContent || '').match(pattern);
  return match ? safeString(match[1]) : '';
}

function isLikelyCodexAuthFilename(filePath) {
  const fileName = path.basename(String(filePath || '')).toLowerCase();
  return /^auth(?:\d+)?\.json$/.test(fileName);
}

function looksLikeCodexCliToml(rawContent) {
  const raw = String(rawContent || '');
  if (!raw.trim()) return false;
  return /^\s*model\s*=.+$/m.test(raw)
    || /^\s*model_reasoning_effort\s*=.+$/m.test(raw)
    || /^\s*\[projects\./m.test(raw);
}

function detectDisabledSource(filePath) {
  return String(filePath || '')
    .split(path.sep)
    .some((segment) => safeString(segment).toLowerCase() === 'auth-disabled');
}

function collectAuthJsonFiles(rootDir, matcher = null) {
  const out = [];
  const seen = new Set();
  const stack = [];
  const pushDir = (candidate) => {
    const dirPath = safeString(candidate);
    if (!dirPath || seen.has(dirPath)) return;
    if (!fs.existsSync(dirPath)) return;
    let stat;
    try {
      stat = fs.statSync(dirPath);
    } catch {
      return;
    }
    if (!stat.isDirectory()) return;
    seen.add(dirPath);
    stack.push(dirPath);
  };

  const rootPath = safeString(rootDir);
  if (rootPath) {
    try {
      const stat = fs.statSync(rootPath);
      if (stat.isFile()) {
        if (rootPath.endsWith('.json') && (!matcher || matcher(rootPath))) {
          return [rootPath];
        }
        return [];
      }
    } catch {
      return [];
    }
  }

  pushDir(rootDir);
  pushDir(path.join(rootDir, 'auth'));
  pushDir(path.join(rootDir, 'auth-disabled'));
  pushDir(path.join(path.dirname(rootDir), 'auth-disabled'));

  while (stack.length > 0) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (entry.name.startsWith('.')) continue;
        stack.push(entryPath);
        continue;
      }
      if (!entry.isFile() || !entry.name.endsWith('.json')) continue;
      if (matcher && !matcher(entryPath)) continue;
      out.push(entryPath);
    }
  }

  out.sort((lhs, rhs) => lhs.localeCompare(rhs));
  return out;
}

function parseProviderFromPayload(payload, filename) {
  const rawProvider = safeString(
    payload?.provider
    || payload?.type
    || payload?.account_type
    || payload?.accountType
    || payload?.auth_mode
    || payload?.auth_provider
    || payload?.oauth_source
    || payload?.['oauth-source']
  ).toLowerCase();
  const normalized = normalizeProvider(rawProvider);
  if (normalized) return normalized;
  return parseProviderFromFilename(filename);
}

function authFileDefaultBaseURL(provider, authType, oauthSourceKey) {
  if (authType === 'oauth' && oauthSourceKey === 'chatgpt') {
    return 'https://api.openai.com/v1';
  }
  switch (canonicalPoolProvider(provider)) {
    case 'openai':
      return 'https://api.openai.com/v1';
    case 'claude':
      return 'https://api.anthropic.com';
    case 'gemini':
      return 'https://generativelanguage.googleapis.com';
    default:
      return '';
  }
}

function authFileDefaultWireAPI(provider, authType, oauthSourceKey) {
  if (authType === 'oauth' && oauthSourceKey === 'chatgpt') {
    return 'chat_completions';
  }
  if (canonicalPoolProvider(provider) === 'openai') {
    return 'chat_completions';
  }
  return '';
}

function resolvedImportedWireAPI(explicitWireAPI, provider, authType, oauthSourceKey, overlaySource = '') {
  const normalizedExplicit = normalizeWireAPI(explicitWireAPI);
  const defaultWire = authFileDefaultWireAPI(provider, authType, oauthSourceKey);
  if (overlaySource === 'fallback_openai' && defaultWire) {
    return defaultWire;
  }
  return normalizedExplicit || defaultWire;
}

function parseImportedAuthAccount(filePath, raw, options = {}) {
  const payload = raw?.data && typeof raw.data === 'object' && !Array.isArray(raw.data) ? raw.data : raw;
  if (!payload || typeof payload !== 'object') return null;

  const overlay = options && typeof options === 'object' ? options : {};
  const provider = normalizeProvider(overlay.provider)
    || parseProviderFromPayload(payload, path.basename(filePath));
  if (!provider) return null;

  const tokenBag = {
    ...safeObject(payload.token),
    ...safeObject(payload.tokens),
  };
  const oauthRefreshConfig = normalizeOAuthRefreshConfig({
    ...tokenBag,
    ...safeObject(payload.oauth_refresh_config),
    ...safeObject(payload.oauth_refresh),
    ...safeObject(payload.oauth_metadata),
  });
  const idToken = safeString(payload.id_token || tokenBag.id_token || '');
  const idClaims = decodeJwtPayload(idToken) || {};

  const accessToken = safeString(
    payload.access_token
    || payload.token?.access_token
    || payload.accessToken
    || tokenBag.access_token
    || payload.id_token?.access_token
  );
  const refreshToken = safeString(
    payload.refresh_token
    || payload.token?.refresh_token
    || payload.refreshToken
    || tokenBag.refresh_token
  );
  if (!accessToken && !refreshToken) return null;

  const disabledBySource = detectDisabledSource(filePath);
  const authType = payload.token_type === 'bearer' || refreshToken ? 'oauth' : 'api_key';
  const oauthSourceKey = safeString(payload.oauth_source || payload['oauth-source'] || payload.auth_mode || provider);
  const resolvedBaseURL = firstNonEmpty(
    safeString(overlay.base_url),
    safeString(payload.base_url || payload.baseUrl || ''),
    authFileDefaultBaseURL(provider, authType, oauthSourceKey)
  );
  const resolvedProxyURL = firstNonEmpty(
    safeString(overlay.proxy_url),
    safeString(payload.proxy_url || payload.proxyUrl || '')
  );
  const resolvedWire = resolvedImportedWireAPI(
    firstNonEmpty(
      safeString(overlay.wire_api),
      safeString(payload.wire_api || payload.wireAPI || '')
    ),
    provider,
    authType,
    oauthSourceKey,
    safeString(overlay.source)
  );
  const authIndex = safeInt(payload.auth_index ?? payload.authIndex, 0);
  const email = safeString(
    payload.email
    || payload.username
    || payload.account_email
    || idClaims.email
    || idClaims.preferred_username
    || ''
  );
  const accountId = safeString(
    payload.account_id
    || payload.accountId
    || tokenBag.account_id
    || idClaims.chatgpt_account_id
    || idClaims.account_id
    || ''
  );
  const fileIdentity = accountId
    ? `${oauthSourceKey || provider}:${accountId}:${authIndex}`
    : (email ? `${oauthSourceKey || provider}:${email}:${authIndex}` : path.resolve(String(filePath || '')));
  const accountKey = buildImportedFileAccountKey(provider, fileIdentity);

  return {
    account_key: accountKey,
    provider,
    email,
    api_key: accessToken,
    refresh_token: refreshToken,
    base_url: resolvedBaseURL,
    proxy_url: resolvedProxyURL,
    enabled: payload.enabled === false ? false : !disabledBySource,
    auth_type: authType,
    wire_api: resolvedWire,
    expires_at_ms: parseDateLikeToMs(
      payload.expires_at
      || payload.expired
      || payload.token?.expiry
      || payload.expiresAt
      || tokenBag.expiry
      || idClaims.exp
    ),
    tier: safeString(payload.tier_name || payload.account_type || ''),
    notes: `imported from ${path.basename(filePath)}`,
    priority: safeInt(payload.priority, 0),
    account_id: accountId,
    source_type: 'auth_file',
    source_ref: normalizePathRef(filePath),
    oauth_source_key: oauthSourceKey || provider,
    oauth_refresh_config: oauthRefreshConfig,
    auth_index: authIndex,
    source_owners: safeStringArray([
      importSourceKey(options.import_source_kind, options.import_source_ref),
    ]),
  };
}

function buildImportedAuthAccounts(files, options = {}) {
  const accounts = [];
  const errors = [];

  for (const filePath of files) {
    const file = path.basename(filePath);
    try {
      const stat = fs.statSync(filePath);
      if (!stat.isFile()) continue;

      const raw = parseJsonFile(filePath);
      if (!raw) continue;

      const account = parseImportedAuthAccount(filePath, raw, options);
      if (!account) continue;
      accounts.push(account);
    } catch (e) {
      errors.push(`${file}: ${String(e?.message || e)}`);
    }
  }

  return { accounts, errors };
}

function applyImportedAccounts(runtimeBaseDir, accounts, options = {}) {
  const ownerKey = importSourceKey(options.import_source_kind, options.import_source_ref);
  const pruneOwned = ownerKey && options.prune_owned !== false;
  const errors = [];
  let imported = 0;
  const resolvedAccountKeys = new Set();

  for (const account of accounts) {
    const result = upsertImportedAccount(runtimeBaseDir, account);
    if (result.ok) {
      imported += 1;
      resolvedAccountKeys.add(safeString(result.account_key || account.account_key));
    } else {
      errors.push(`${safeString(account.source_ref || account.account_key)}: ${result.error}`);
    }
  }

  if (pruneOwned && errors.length === 0) {
    const desiredKeys = resolvedAccountKeys;
    const store = loadProviderKeyStore(runtimeBaseDir, 0);
    let removed = 0;

    for (const providerData of Object.values(store.providers)) {
      if (!providerData || !Array.isArray(providerData.accounts)) continue;
      const nextAccounts = [];
      for (const account of providerData.accounts) {
        const owners = safeStringArray(account?.source_owners);
        if (!owners.includes(ownerKey)) {
          nextAccounts.push(account);
          continue;
        }
        if (desiredKeys.has(safeString(account.account_key))) {
          account.source_owners = safeStringArray([...owners, ownerKey]);
          nextAccounts.push(account);
          continue;
        }
        const remainingOwners = owners.filter((owner) => owner !== ownerKey);
        if (remainingOwners.length > 0) {
          account.source_owners = remainingOwners;
          nextAccounts.push(account);
          continue;
        }
        removed += 1;
      }
      providerData.accounts = nextAccounts;
    }

    if (removed > 0 || accounts.length === 0) {
      const saved = saveProviderKeyStore(runtimeBaseDir, store);
      if (!saved) {
        errors.push('prune_owned: save_failed');
      }
    }
  }

  return { ok: errors.length === 0, imported, errors };
}

export function importAuthDir(runtimeBaseDir, authDirPath, options = {}) {
  const dir = normalizePathRef(authDirPath);
  if (!dir || !fs.existsSync(dir)) return { ok: false, imported: 0, errors: [] };

  registerProviderKeyImportSource(runtimeBaseDir, {
    kind: 'auth_dir',
    source_ref: dir,
  });

  const files = collectAuthJsonFiles(dir);
  const build = buildImportedAuthAccounts(files, {
    ...options,
    import_source_kind: 'auth_dir',
    import_source_ref: dir,
  });
  const applied = applyImportedAccounts(runtimeBaseDir, build.accounts, {
    ...options,
    import_source_kind: 'auth_dir',
    import_source_ref: dir,
    prune_owned: build.errors.length === 0,
  });
  const errors = [...build.errors, ...(applied.errors || [])];
  const statusResult = recordProviderKeyImportSourceStatus(runtimeBaseDir, {
    kind: 'auth_dir',
    source_ref: dir,
  }, {
    state: errors.length === 0 ? 'ready' : 'sync_failed',
    touch_last_sync: true,
    last_imported_count: applied.imported,
    refresh_owned_account_count: true,
    last_error_count: errors.length,
    last_errors: errors,
  });
  if (!statusResult.ok) {
    errors.push(`import_source_status: ${statusResult.error}`);
  }
  return {
    ok: errors.length === 0,
    imported: applied.imported,
    errors,
  };
}

function parseProviderFromFilename(filename) {
  const lower = filename.toLowerCase();
  const providers = ['codex', 'antigravity', 'claude', 'gemini', 'kiro', 'copilot', 'qwen', 'iflow'];
  for (const p of providers) {
    if (lower.startsWith(p)) return p;
  }
  return '';
}

function parseTomlBooleanValue(rawContent, key) {
  const escapedKey = String(key || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`^\\s*${escapedKey}\\s*=\\s*(true|false)\\s*$`, 'mi');
  const match = String(rawContent || '').match(pattern);
  return match ? match[1].toLowerCase() === 'true' : null;
}

function unquoteTomlValue(raw) {
  const value = safeString(raw);
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.slice(1, -1);
  }
  return value;
}

function parseCodexCliProviderOverlay(rawToml) {
  const text = String(rawToml || '');
  if (!text.trim()) return null;

  let preferredProviderName = '';
  let preferredModelID = '';
  let current = null;
  const providers = [];

  const flushCurrent = () => {
    if (current && current.name) {
      providers.push(current);
    }
    current = null;
  };

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;

    if (line.startsWith('[') && line.endsWith(']')) {
      flushCurrent();
      const section = line.slice(1, -1).trim();
      const prefix = 'model_providers.';
      if (section.startsWith(prefix)) {
        current = {
          name: section.slice(prefix.length).trim(),
          base_url: '',
          requires_openai_auth: false,
          wire_api: '',
        };
      }
      continue;
    }

    const eqIndex = line.indexOf('=');
    if (eqIndex === -1) continue;
    const key = line.slice(0, eqIndex).trim();
    const value = line.slice(eqIndex + 1).trim();

    if (!current) {
      if (key === 'model_provider') {
        preferredProviderName = unquoteTomlValue(value).toLowerCase();
      } else if (key === 'model') {
        preferredModelID = unquoteTomlValue(value);
      }
      continue;
    }

    switch (key) {
      case 'base_url':
        current.base_url = unquoteTomlValue(value);
        break;
      case 'requires_openai_auth':
        current.requires_openai_auth = value.toLowerCase() === 'true';
        break;
      case 'wire_api':
        current.wire_api = normalizeWireAPI(unquoteTomlValue(value));
        break;
      default:
        break;
    }
  }

  flushCurrent();

  const explicitProviders = providers.filter((row) => row.requires_openai_auth && row.base_url);
  let selected = null;
  if (preferredProviderName) {
    selected = explicitProviders.find((row) => row.name.toLowerCase() === preferredProviderName) || null;
  }
  if (!selected) {
    selected = explicitProviders[0] || null;
  }

  if (selected) {
    return {
      provider: '',
      base_url: selected.base_url,
      proxy_url: '',
      wire_api: normalizeWireAPI(selected.wire_api),
      source: 'explicit_provider',
    };
  }

  if (!providers.length && (!preferredProviderName || preferredProviderName === 'openai' || preferredProviderName === 'chatgpt' || preferredModelID)) {
    return {
      provider: '',
      base_url: 'https://api.openai.com/v1',
      proxy_url: '',
      wire_api: 'responses',
      source: 'fallback_openai',
    };
  }

  return null;
}

function appendImportedConfigAccount(accounts, errors, label, accountInput) {
  const account = normalizeAccount(accountInput);
  if (!account) {
    errors.push(`${label}: invalid_account`);
    return;
  }
  accounts.push(account);
}

function buildImportedProxyConfigAccounts(configPath) {
  const fp = normalizePathRef(configPath);
  const errors = [];
  const accounts = [];
  const ownerKey = importSourceKey('config_path', fp);

  if (fp.toLowerCase().endsWith('.toml')) {
    let rawToml = '';
    try {
      rawToml = fs.readFileSync(fp, 'utf8');
    } catch (e) {
      return { accounts, errors: [`toml_read_failed: ${String(e?.message || e)}`] };
    }

    if (!looksLikeCodexCliToml(rawToml)) {
      return { accounts, errors: ['unsupported_toml_config'] };
    }

    const providerOverlay = parseCodexCliProviderOverlay(rawToml) || {};
    const explicitAuthFile = parseTomlStringValue(rawToml, 'auth_file');
    if (explicitAuthFile) {
      const configDir = path.dirname(fp);
      const authPath = path.isAbsolute(explicitAuthFile)
        ? explicitAuthFile
        : path.resolve(configDir, explicitAuthFile);
      if (fs.existsSync(authPath)) {
        const build = buildImportedAuthAccounts(collectAuthJsonFiles(authPath), {
          ...providerOverlay,
          import_source_kind: 'config_path',
          import_source_ref: fp,
        });
        return {
          accounts: build.accounts,
          errors: build.errors,
        };
      }
    }

    const siblingAuthFiles = collectAuthJsonFiles(
      path.dirname(fp),
      (candidate) => isLikelyCodexAuthFilename(candidate)
    );
    const build = buildImportedAuthAccounts(siblingAuthFiles, {
      ...providerOverlay,
      import_source_kind: 'config_path',
      import_source_ref: fp,
    });
    return {
      accounts: build.accounts,
      errors: build.errors,
    };
  }

  let config;
  try {
    const raw = fs.readFileSync(fp, 'utf8');
    config = yaml.load(raw);
  } catch (e) {
    return { accounts, errors: [`yaml_parse_failed: ${String(e?.message || e)}`] };
  }

  if (!config || typeof config !== 'object') {
    return { accounts, errors: ['invalid_config'] };
  }

  const openaiCompat = Array.isArray(config['openai-compatibility']) ? config['openai-compatibility'] : [];
  for (let providerIndex = 0; providerIndex < openaiCompat.length; providerIndex += 1) {
    const provider = openaiCompat[providerIndex];
    if (!provider || typeof provider !== 'object') continue;
    const entries = Array.isArray(provider['api-key-entries']) ? provider['api-key-entries'] : [];
    for (let entryIndex = 0; entryIndex < entries.length; entryIndex += 1) {
      const entry = entries[entryIndex];
      if (!entry || typeof entry !== 'object') continue;
      const apiKey = safeString(entry['api-key']);
      if (!apiKey) continue;
      appendImportedConfigAccount(
        accounts,
        errors,
        `openai:${provider.name || provider['base-url'] || 'default'}`,
        {
          account_key: buildImportedConfigAccountKey('openai', fp, `openai-compat:${provider.name || provider['base-url'] || 'default'}`, providerIndex * 1000 + entryIndex),
          provider: 'openai',
          email: safeString(provider.name || ''),
          api_key: apiKey,
          base_url: safeString(provider['base-url'] || ''),
          proxy_url: safeString(entry['proxy-url'] || ''),
          auth_type: 'api_key',
          custom_headers: provider.headers || {},
          wire_api: 'chat_completions',
          models: Array.isArray(provider.models) ? provider.models.map((m) => m.name || m).filter(Boolean) : [],
          notes: `imported from proxy config: ${provider.name || 'openai-compat'}`,
          source_type: 'proxy_config',
          source_ref: fp,
          source_owners: [ownerKey],
        }
      );
    }
  }

  const claudeKeys = Array.isArray(config['claude-api-key']) ? config['claude-api-key'] : [];
  for (let entryIndex = 0; entryIndex < claudeKeys.length; entryIndex += 1) {
    const entry = claudeKeys[entryIndex];
    if (!entry || typeof entry !== 'object') continue;
    const apiKey = safeString(entry['api-key']);
    if (!apiKey) continue;
    appendImportedConfigAccount(
      accounts,
      errors,
      `claude:${entry.name || entry['base-url'] || 'default'}`,
      {
        account_key: buildImportedConfigAccountKey('claude', fp, `claude:${entry.name || entry['base-url'] || 'default'}`, entryIndex),
        provider: 'claude',
        email: safeString(entry.name || ''),
        api_key: apiKey,
        base_url: safeString(entry['base-url'] || 'https://api.anthropic.com'),
        proxy_url: safeString(entry['proxy-url'] || ''),
        auth_type: 'api_key',
        custom_headers: entry.headers || {},
        wire_api: '',
        models: Array.isArray(entry.models) ? entry.models.map((m) => m.name || m).filter(Boolean) : [],
        notes: `imported from proxy config: ${entry.name || 'claude'}`,
        source_type: 'proxy_config',
        source_ref: fp,
        source_owners: [ownerKey],
      }
    );
  }

  const geminiKeys = Array.isArray(config['gemini-api-key']) ? config['gemini-api-key'] : [];
  for (let entryIndex = 0; entryIndex < geminiKeys.length; entryIndex += 1) {
    const entry = geminiKeys[entryIndex];
    if (!entry || typeof entry !== 'object') continue;
    const apiKey = safeString(entry['api-key']);
    if (!apiKey) continue;
    appendImportedConfigAccount(
      accounts,
      errors,
      `gemini:${entry.name || entry['base-url'] || 'default'}`,
      {
        account_key: buildImportedConfigAccountKey('gemini', fp, `gemini:${entry.name || entry['base-url'] || 'default'}`, entryIndex),
        provider: 'gemini',
        email: safeString(entry.name || ''),
        api_key: apiKey,
        base_url: safeString(entry['base-url'] || 'https://generativelanguage.googleapis.com'),
        proxy_url: safeString(entry['proxy-url'] || ''),
        auth_type: 'api_key',
        custom_headers: entry.headers || {},
        wire_api: '',
        models: Array.isArray(entry.models) ? entry.models.map((m) => m.name || m).filter(Boolean) : [],
        notes: `imported from proxy config: ${entry.name || 'gemini'}`,
        source_type: 'proxy_config',
        source_ref: fp,
        source_owners: [ownerKey],
      }
    );
  }

  const codexKeys = Array.isArray(config['codex-api-key']) ? config['codex-api-key'] : [];
  for (let entryIndex = 0; entryIndex < codexKeys.length; entryIndex += 1) {
    const entry = codexKeys[entryIndex];
    if (!entry || typeof entry !== 'object') continue;
    const apiKey = safeString(entry['api-key']);
    if (!apiKey) continue;
    appendImportedConfigAccount(
      accounts,
      errors,
      `codex:${entry.name || entry['base-url'] || 'default'}`,
      {
        account_key: buildImportedConfigAccountKey('codex', fp, `codex:${entry.name || entry['base-url'] || 'default'}`, entryIndex),
        provider: 'codex',
        email: safeString(entry.name || ''),
        api_key: apiKey,
        base_url: safeString(entry['base-url'] || ''),
        proxy_url: safeString(entry['proxy-url'] || ''),
        auth_type: 'api_key',
        custom_headers: entry.headers || {},
        wire_api: normalizeWireAPI(entry['wire-api'] || entry['wire_api'] || ''),
        models: Array.isArray(entry.models) ? entry.models.map((m) => m.name || m).filter(Boolean) : [],
        notes: `imported from proxy config: ${entry.name || 'codex'}`,
        source_type: 'proxy_config',
        source_ref: fp,
        source_owners: [ownerKey],
      }
    );
  }

  const ampcode = config.ampcode;
  if (ampcode && typeof ampcode === 'object') {
    const upstreamUrl = safeString(ampcode['upstream-url']);
    const upstreamApiKey = safeString(ampcode['upstream-api-key']);
    const upstreamApiKeys = Array.isArray(ampcode['upstream-api-keys']) ? ampcode['upstream-api-keys'] : [];

    if (upstreamApiKey) {
      appendImportedConfigAccount(
        accounts,
        errors,
        'ampcode:upstream',
        {
          account_key: buildImportedConfigAccountKey('custom', fp, 'ampcode:upstream', 0),
          provider: 'custom',
          email: 'ampcode',
          api_key: upstreamApiKey,
          base_url: upstreamUrl,
          auth_type: 'api_key',
          wire_api: 'chat_completions',
          notes: 'imported from proxy config: ampcode',
          source_type: 'proxy_config',
          source_ref: fp,
          source_owners: [ownerKey],
        }
      );
    }

    for (const entry of upstreamApiKeys) {
      if (!entry || typeof entry !== 'object') continue;
      const key = safeString(entry['upstream-api-key']);
      if (!key) continue;
      const subKeys = Array.isArray(entry['api-keys']) ? entry['api-keys'] : [];
      for (let idx = 0; idx < subKeys.length; idx += 1) {
        appendImportedConfigAccount(
          accounts,
          errors,
          `ampcode:sub:${key}`,
          {
            account_key: buildImportedConfigAccountKey('custom', fp, `ampcode:sub:${key}`, idx),
            provider: 'custom',
            email: `ampcode:${redactApiKey(subKeys[idx])}`,
            api_key: subKeys[idx],
            base_url: upstreamUrl,
            auth_type: 'api_key',
            wire_api: 'chat_completions',
            notes: 'imported from proxy config: ampcode sub-key',
            source_type: 'proxy_config',
            source_ref: fp,
            source_owners: [ownerKey],
          }
        );
      }
    }
  }

  return { accounts, errors };
}

export function importProxyConfig(runtimeBaseDir, configPath) {
  const fp = normalizePathRef(configPath);
  if (!fp || !fs.existsSync(fp)) return { ok: false, imported: 0, errors: [] };

  registerProviderKeyImportSource(runtimeBaseDir, {
    kind: 'config_path',
    source_ref: fp,
  });

  const build = buildImportedProxyConfigAccounts(fp);
  const applied = applyImportedAccounts(runtimeBaseDir, build.accounts, {
    import_source_kind: 'config_path',
    import_source_ref: fp,
    prune_owned: build.errors.length === 0,
  });
  const errors = [...build.errors, ...(applied.errors || [])];
  const statusResult = recordProviderKeyImportSourceStatus(runtimeBaseDir, {
    kind: 'config_path',
    source_ref: fp,
  }, {
    state: errors.length === 0 ? 'ready' : 'sync_failed',
    touch_last_sync: true,
    last_imported_count: applied.imported,
    refresh_owned_account_count: true,
    last_error_count: errors.length,
    last_errors: errors,
  });
  if (!statusResult.ok) {
    errors.push(`import_source_status: ${statusResult.error}`);
  }
  return {
    ok: errors.length === 0,
    imported: applied.imported,
    errors,
  };
}

export function providerKeyStoreSummary(runtimeBaseDir) {
  const store = loadProviderKeyStore(runtimeBaseDir);
  const providers = [];

  for (const [providerId, providerData] of Object.entries(store.providers)) {
    const accounts = providerData.accounts || [];
    providers.push({
      provider: providerId,
      total_accounts: accounts.length,
      enabled_accounts: accounts.filter(a => a.enabled).length,
      routing_strategy: providerData.routing_strategy || 'fill-first',
    });
  }

  return {
    schema_version: store.schema_version,
    updated_at_ms: store.updated_at_ms,
    global_routing_strategy: store.routing_strategy,
    providers,
  };
}

export function reportKeyUsage(runtimeBaseDir, accountKey, usage) {
  const ak = safeString(accountKey);
  if (!ak) return { ok: false, error: 'missing_account_key' };

  const tokensUsed = safeInt(usage?.tokens_used, 0);
  const costUsd = Number(usage?.cost_usd || 0);
  const modelID = safeString(usage?.model_id || usage?.modelId);
  const occurredAtMs = safeInt(usage?.occurred_at_ms || usage?.occurredAtMs, 0);
  const eventAtMs = occurredAtMs > 0 ? occurredAtMs : nowMs();

  const store = loadProviderKeyStore(runtimeBaseDir, 0);

  for (const providerData of Object.values(store.providers)) {
    const account = providerData.accounts.find(a => a.account_key === ak);
    if (!account) continue;

    const quota = account.quota || normalizeQuota(null);
    const todayKey = new Date(eventAtMs).toISOString().slice(0, 10);
    const lastUsedDay = quota.last_used_at_ms ? new Date(quota.last_used_at_ms).toISOString().slice(0, 10) : '';

    if (lastUsedDay !== todayKey) {
      quota.daily_tokens_used = 0;
    }

    quota.daily_tokens_used += tokensUsed;
    quota.total_tokens_used += tokensUsed;
    quota.last_used_at_ms = eventAtMs;

    if (quota.daily_token_cap > 0) {
      quota.daily_tokens_remaining = Math.max(0, quota.daily_token_cap - quota.daily_tokens_used);
    }

    if (quota.consecutive_errors > 0) {
      quota.consecutive_errors = 0;
    }

    account.quota = quota;
    account.error_state = account.error_state || normalizeErrorState(null);
    if (account.error_state.status !== 'healthy') {
      account.error_state.status = 'healthy';
      account.error_state.status_message = '';
      account.error_state.reason_code = '';
      account.error_state.last_error_code = '';
      account.error_state.next_retry_at_ms = 0;
      account.error_state.retry_at_source = '';
    }
    if (modelID) {
      applyAccountModelState(account, modelID, {
        status: 'ready',
        reason_code: '',
        status_message: '',
        next_retry_at_ms: 0,
        retry_at_source: '',
        last_error_code: '',
        last_error_at_ms: 0,
        updated_at_ms: eventAtMs,
      });
    }

    account.updated_at_ms = eventAtMs;
    const saved = saveProviderKeyStore(runtimeBaseDir, store);
    return { ok: saved, error: saved ? '' : 'save_failed' };
  }

  return { ok: false, error: 'account_not_found' };
}

export function reportKeyError(runtimeBaseDir, accountKey, errorInfo) {
  const ak = safeString(accountKey);
  if (!ak) return { ok: false, error: 'missing_account_key' };

  const outcome = normalizedRuntimeEventOutcome(errorInfo?.outcome);
  const errorCode = normalizedRuntimeEventReason(
    errorInfo?.reason_code || errorInfo?.reasonCode,
    errorInfo?.error_code || errorInfo?.errorCode
  );
  const modelID = safeString(errorInfo?.model_id || errorInfo?.modelId);
  const httpStatus = safeInt(errorInfo?.http_status || errorInfo?.httpStatus, 0);
  const statusMessage = normalizedRuntimeEventMessage(
    errorInfo?.status_message || errorInfo?.statusMessage,
    errorInfo?.message || errorInfo?.detail || errorInfo?.error
  );
  const occurredAtMs = safeInt(errorInfo?.occurred_at_ms || errorInfo?.occurredAtMs, 0);

  const store = loadProviderKeyStore(runtimeBaseDir, 0);

  for (const providerData of Object.values(store.providers)) {
    const account = providerData.accounts.find(a => a.account_key === ak);
    if (!account) continue;

    const now = occurredAtMs > 0 ? occurredAtMs : nowMs();
    const quota = account.quota || normalizeQuota(null);
    const errorState = account.error_state || normalizeErrorState(null);
    const status = inferredProviderErrorStatus({
      account,
      outcome,
      reasonCode: errorCode,
      httpStatus,
    });
    const autoDisabled = inferredProviderErrorAutoDisabled({
      account,
      status,
      reasonCode: errorCode,
      httpStatus,
    });
    const retrySource = inferredProviderErrorRetrySource({
      account,
      status,
      outcome,
      reasonCode: errorCode,
      explicitRetrySource: errorInfo?.retry_at_source || errorInfo?.retryAtSource,
    });

    quota.last_error_at_ms = now;
    quota.consecutive_errors += 1;

    errorState.last_error_code = errorCode;
    errorState.last_error_at_ms = now;
    errorState.status = status;
    errorState.reason_code = errorCode || normalizedRuntimeEventReason(status);
    errorState.status_message = statusMessage || (errorCode ? `${status}:${errorCode}` : status);
    errorState.auto_disabled = autoDisabled;

    if (status === 'blocked_quota' || status === 'rate_limited') {
      const existingCooldown = safeInt(quota.cooldown_until_ms, 0);
      const nextRetryAtMs = inferredProviderErrorRetryAtMs({
        now,
        status,
        reasonCode: errorCode,
        explicitNextRetryAtMs: errorInfo?.next_retry_at_ms || errorInfo?.nextRetryAtMs,
        explicitRetrySource: retrySource,
        quota,
      });
      quota.cooldown_until_ms = Math.max(existingCooldown, nextRetryAtMs);
      errorState.next_retry_at_ms = quota.cooldown_until_ms;
      errorState.retry_at_source = retrySource || 'quota';
    } else {
      errorState.next_retry_at_ms = inferredProviderErrorRetryAtMs({
        now,
        status,
        reasonCode: errorCode,
        explicitNextRetryAtMs: errorInfo?.next_retry_at_ms || errorInfo?.nextRetryAtMs,
        explicitRetrySource: retrySource,
        quota,
      });
      errorState.retry_at_source = retrySource;
    }

    if (quota.consecutive_errors >= 5 && !autoDisabled && status === 'blocked_provider') {
      errorState.status = 'degraded';
      errorState.reason_code = errorCode || 'consecutive_errors';
      errorState.status_message = statusMessage || (errorCode ? `degraded:${errorCode}` : 'degraded');
      errorState.auto_disabled = true;
    }

    account.enabled = errorState.auto_disabled ? false : account.enabled !== false;

    if (modelID) {
      let modelStateStatus = 'blocked';
      if (errorState.auto_disabled) modelStateStatus = 'disabled';
      else if (
        safeInt(errorState.next_retry_at_ms, 0) > now
        && ['blocked_quota', 'blocked_network', 'blocked_provider'].includes(safeString(errorState.status))
      ) {
        modelStateStatus = 'cooldown';
      }
      applyAccountModelState(account, modelID, {
        status: modelStateStatus,
        reason_code: errorCode || errorState.reason_code || errorState.status,
        status_message: errorState.status_message,
        next_retry_at_ms: safeInt(errorState.next_retry_at_ms, 0),
        retry_at_source: safeString(errorState.retry_at_source),
        last_error_code: errorCode,
        last_error_at_ms: now,
        updated_at_ms: now,
      });
    }

    account.quota = quota;
    account.error_state = errorState;
    account.updated_at_ms = now;
    const saved = saveProviderKeyStore(runtimeBaseDir, store);
    return { ok: saved, error: saved ? '' : 'save_failed', auto_disabled: errorState.auto_disabled };
  }

  return { ok: false, error: 'account_not_found' };
}

export function getKeyUsage(runtimeBaseDir, accountKey) {
  const ak = safeString(accountKey);
  if (!ak) return null;

  const store = loadProviderKeyStore(runtimeBaseDir);
  for (const providerData of Object.values(store.providers)) {
    const account = providerData.accounts.find(a => a.account_key === ak);
    if (!account) continue;
    return {
      account_key: ak,
      provider: account.provider,
      quota: account.quota || normalizeQuota(null),
      error_state: account.error_state || normalizeErrorState(null),
      model_states: account.model_states || {},
    };
  }

  return null;
}

export function resetKeyErrorState(runtimeBaseDir, accountKey) {
  const ak = safeString(accountKey);
  if (!ak) return { ok: false, error: 'missing_account_key' };

  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  for (const providerData of Object.values(store.providers)) {
    const account = providerData.accounts.find(a => a.account_key === ak);
    if (!account) continue;

    account.error_state = normalizeErrorState(null);
    account.quota = account.quota || normalizeQuota(null);
    account.quota.consecutive_errors = 0;
    account.quota.cooldown_until_ms = 0;
    account.model_states = {};
    account.enabled = true;
    account.updated_at_ms = nowMs();
    const saved = saveProviderKeyStore(runtimeBaseDir, store);
    return { ok: saved, error: saved ? '' : 'save_failed' };
  }

  return { ok: false, error: 'account_not_found' };
}
