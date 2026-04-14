function safeStr(value) {
  return String(value ?? '').trim();
}

function toBool(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const raw = safeStr(value).toLowerCase();
  if (!raw) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(raw)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(raw)) return false;
  return fallback;
}

function toMs(value, fallback = 0) {
  const num = Number(value);
  if (!Number.isFinite(num)) return fallback;
  const out = Math.floor(num);
  return out > 0 ? out : fallback;
}

function parseJsonValue(value, fallback) {
  if (value == null || value === '') return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(String(value));
  } catch {
    return fallback;
  }
}

function parseObject(value) {
  const parsed = parseJsonValue(value, null);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
  return parsed;
}

function normalizeSensitivity(value) {
  const raw = safeStr(value).toLowerCase();
  if (raw === 'secret') return 'secret';
  if (raw === 'internal') return 'internal';
  return 'public';
}

function normalizeTrustLevel(value) {
  const raw = safeStr(value).toLowerCase();
  if (raw === 'untrusted') return 'untrusted';
  return 'trusted';
}

function normalizeBudgetClass(value) {
  return safeStr(value).toLowerCase();
}

function normalizeFallbackAction(value) {
  return safeStr(value).toLowerCase();
}

function normalizeMaybeNullableMs(value) {
  if (value == null || value === '') return null;
  const out = toMs(value, 0);
  return out > 0 ? out : null;
}

function routeSourceForStrategy(strategy) {
  if (strategy === 'single_model') return 'user_single_model';
  if (strategy === 'job_map') return 'user_job_map';
  if (strategy === 'mode_profile') return 'user_mode_profile';
  return '';
}

function routeSourceForDeny(profile) {
  if (profile && profile.selection_strategy) return routeSourceForStrategy(profile.selection_strategy);
  return 'system_default_fallback';
}

function normalizeModelPointer(value) {
  if (value == null) return null;
  if (typeof value === 'string') {
    const modelId = safeStr(value);
    return modelId ? { model_id: modelId } : null;
  }
  if (typeof value !== 'object' || Array.isArray(value)) return null;

  const modelId = safeStr(value.model_id || value.id || value.primary_model_id);
  const fallbackModelId = safeStr(value.fallback_model_id || value.fallbackModelId);
  const localModelId = safeStr(value.local_model_id || value.localModelId || value.downgrade_model_id);
  const providerHint = safeStr(value.provider_hint || value.provider || value.backend);
  const out = {};
  if (modelId) out.model_id = modelId;
  if (fallbackModelId) out.fallback_model_id = fallbackModelId;
  if (localModelId) out.local_model_id = localModelId;
  if (providerHint) out.provider_hint = providerHint;
  if (value.remote_allowed != null) out.remote_allowed = toBool(value.remote_allowed, true);
  return Object.keys(out).length ? out : null;
}

function modelIdFromPointer(value) {
  const pointer = normalizeModelPointer(value);
  return safeStr(pointer?.model_id || '');
}

function normalizePointerMap(value, keyNormalizer) {
  const input = parseObject(value);
  const out = {};
  for (const [rawKey, rawValue] of Object.entries(input)) {
    const key = keyNormalizer(rawKey);
    const pointer = normalizeModelPointer(rawValue);
    if (!key || !pointer) continue;
    out[key] = pointer;
  }
  return out;
}

function serializeMap(mapValue) {
  const input = mapValue && typeof mapValue === 'object' && !Array.isArray(mapValue) ? mapValue : {};
  return JSON.stringify(input);
}

const LOCAL_DOWNGRADE_ACTIONS = new Set([
  'downgrade_to_local',
  'downgrade',
  'fallback',
  'local_fallback',
  'use_local',
  'local_only',
]);
const DENY_FALLBACK_ACTIONS = new Set(['deny', 'error', 'block']);

function fallbackActionAllowsLocalDowngrade(action) {
  return LOCAL_DOWNGRADE_ACTIONS.has(normalizeFallbackAction(action));
}

function fallbackActionDenies(action) {
  return DENY_FALLBACK_ACTIONS.has(normalizeFallbackAction(action));
}

function normalizeFallbackPolicy(value) {
  const input = parseObject(value);
  const out = {
    on_unavailable: normalizeFallbackAction(input.on_unavailable),
    on_remote_block: normalizeFallbackAction(input.on_remote_block),
    on_budget_exceeded: normalizeFallbackAction(input.on_budget_exceeded),
    allow_downgrade_to_local: toBool(input.allow_downgrade_to_local, false),
    allow_job_specific_fallback: toBool(input.allow_job_specific_fallback, false),
    fallback_model_id: safeStr(input.fallback_model_id || input.primary_fallback_model_id),
    local_model_id: safeStr(input.local_model_id || input.local_fallback_model_id || input.downgrade_model_id),
    job_fallback_map: normalizePointerMap(
      input.job_fallback_map || input.job_model_map,
      (key) => normalizeMemoryModelJobType(key, '')
    ),
    mode_fallback_map: normalizePointerMap(
      input.mode_fallback_map || input.mode_model_map,
      (key) => normalizeMemoryModelMode(key, '')
    ),
  };
  out.job_fallback_map_json = serializeMap(out.job_fallback_map);
  out.mode_fallback_map_json = serializeMap(out.mode_fallback_map);
  return out;
}

export const MEMORY_MODEL_SCOPE_ORDER = Object.freeze(['project_mode', 'project', 'mode', 'user_default']);
export const MEMORY_MODEL_SCOPE_KINDS = Object.freeze([...MEMORY_MODEL_SCOPE_ORDER]);
export const MEMORY_MODEL_SELECTION_STRATEGIES = Object.freeze(['single_model', 'job_map', 'mode_profile']);
export const MEMORY_MODEL_MODES = Object.freeze(['assistant_personal', 'project_code']);
export const MEMORY_MODEL_JOB_TYPES = Object.freeze([
  'ingest_redact',
  'extract_observations',
  'summarize_run',
  'aggregate_longterm',
  'canonicalize_candidates',
  'verify_gate',
  'mine_skill_candidates',
]);

const MEMORY_MODEL_SCOPE_KIND_SET = new Set(MEMORY_MODEL_SCOPE_KINDS);
const MEMORY_MODEL_SELECTION_STRATEGY_SET = new Set(MEMORY_MODEL_SELECTION_STRATEGIES);
const MEMORY_MODEL_MODE_SET = new Set(MEMORY_MODEL_MODES);
const MEMORY_MODEL_JOB_TYPE_SET = new Set(MEMORY_MODEL_JOB_TYPES);
const REMOTE_BLOCKED_BUDGET_CLASSES = new Set(['local_only', 'offline_only', 'no_remote']);
const LOCAL_MODEL_BACKENDS = new Set([
  'mlx',
  'ollama',
  'llama.cpp',
  'llamacpp',
  'transformers',
  'coreml',
  'whisper.cpp',
  'local',
]);

export function normalizeMemoryModelPreferenceScopeKind(value, fallback = '') {
  const raw = safeStr(value).toLowerCase();
  if (MEMORY_MODEL_SCOPE_KIND_SET.has(raw)) return raw;
  return safeStr(fallback).toLowerCase();
}

export function normalizeMemoryModelPreferenceSelectionStrategy(value, fallback = '') {
  const raw = safeStr(value).toLowerCase();
  if (MEMORY_MODEL_SELECTION_STRATEGY_SET.has(raw)) return raw;
  return safeStr(fallback).toLowerCase();
}

export function normalizeMemoryModelMode(value, fallback = '') {
  const raw = safeStr(value).toLowerCase();
  if (MEMORY_MODEL_MODE_SET.has(raw)) return raw;
  return safeStr(fallback).toLowerCase();
}

export function normalizeMemoryModelJobType(value, fallback = '') {
  const raw = safeStr(value).toLowerCase();
  if (MEMORY_MODEL_JOB_TYPE_SET.has(raw)) return raw;
  return safeStr(fallback).toLowerCase();
}

export function normalizeMemoryModelPreferenceRow(row) {
  if (!row || typeof row !== 'object') return null;

  const jobModelMap = normalizePointerMap(
    row.job_model_map_json ?? row.job_model_map,
    (key) => normalizeMemoryModelJobType(key, '')
  );
  const modeModelMap = normalizePointerMap(
    row.mode_model_map_json ?? row.mode_model_map,
    (key) => normalizeMemoryModelMode(key, '')
  );
  const fallbackPolicy = normalizeFallbackPolicy(row.fallback_policy_json ?? row.fallback_policy);

  return {
    profile_id: safeStr(row.profile_id),
    user_id: safeStr(row.user_id),
    scope_kind: normalizeMemoryModelPreferenceScopeKind(row.scope_kind, ''),
    scope_ref: safeStr(row.scope_ref),
    mode: normalizeMemoryModelMode(row.mode, ''),
    selection_strategy: normalizeMemoryModelPreferenceSelectionStrategy(row.selection_strategy, ''),
    primary_model_id: safeStr(row.primary_model_id),
    job_model_map: jobModelMap,
    job_model_map_json: serializeMap(jobModelMap),
    mode_model_map: modeModelMap,
    mode_model_map_json: serializeMap(modeModelMap),
    fallback_policy: fallbackPolicy,
    fallback_policy_json: JSON.stringify({
      on_unavailable: fallbackPolicy.on_unavailable,
      on_remote_block: fallbackPolicy.on_remote_block,
      on_budget_exceeded: fallbackPolicy.on_budget_exceeded,
      allow_downgrade_to_local: fallbackPolicy.allow_downgrade_to_local,
      allow_job_specific_fallback: fallbackPolicy.allow_job_specific_fallback,
      fallback_model_id: fallbackPolicy.fallback_model_id,
      local_model_id: fallbackPolicy.local_model_id,
      job_fallback_map: fallbackPolicy.job_fallback_map,
      mode_fallback_map: fallbackPolicy.mode_fallback_map,
    }),
    remote_allowed: toBool(row.remote_allowed, false),
    policy_version: safeStr(row.policy_version),
    note: safeStr(row.note),
    updated_at_ms: toMs(row.updated_at_ms, 0),
    disabled_at_ms: normalizeMaybeNullableMs(row.disabled_at_ms),
  };
}

export function validateMemoryModelPreference(row) {
  const value = normalizeMemoryModelPreferenceRow(row);
  const errors = [];

  if (!value?.profile_id) errors.push('profile_id');
  if (!value?.user_id) errors.push('user_id');
  if (!value?.scope_kind) errors.push('scope_kind');
  if (!value?.selection_strategy) errors.push('selection_strategy');
  if (!value?.policy_version) errors.push('policy_version');

  if (value?.scope_kind === 'project' || value?.scope_kind === 'project_mode') {
    if (!value.scope_ref) errors.push('scope_ref');
  }
  if (value?.scope_kind === 'mode' || value?.scope_kind === 'project_mode') {
    if (!value.mode) errors.push('mode');
  }

  if (value?.selection_strategy === 'single_model' && !value.primary_model_id) {
    errors.push('primary_model_id');
  }
  if (value?.selection_strategy === 'job_map' && Object.keys(value.job_model_map || {}).length <= 0) {
    errors.push('job_model_map');
  }
  if (value?.selection_strategy === 'mode_profile' && Object.keys(value.mode_model_map || {}).length <= 0) {
    errors.push('mode_model_map');
  }

  const fallbackPolicy = value?.fallback_policy || {};
  if (!fallbackPolicy.on_unavailable) errors.push('fallback_policy.on_unavailable');
  if (!fallbackPolicy.on_remote_block) errors.push('fallback_policy.on_remote_block');
  if (!fallbackPolicy.on_budget_exceeded) errors.push('fallback_policy.on_budget_exceeded');

  return {
    ok: errors.length <= 0,
    errors,
    value,
  };
}

export function isMemoryModelPreferenceDisabled(profile) {
  const normalized = normalizeMemoryModelPreferenceRow(profile);
  return !!normalized?.disabled_at_ms;
}

function preferenceMatchesRequest(profile, request) {
  if (!profile || !request) return false;
  if (!profile.profile_id || !profile.user_id || profile.user_id !== request.user_id) return false;
  if (profile.scope_kind === 'project_mode') {
    return !!request.project_id && !!request.mode && profile.scope_ref === request.project_id && profile.mode === request.mode;
  }
  if (profile.scope_kind === 'project') {
    return !!request.project_id && profile.scope_ref === request.project_id;
  }
  if (profile.scope_kind === 'mode') {
    return !!request.mode && profile.mode === request.mode;
  }
  if (profile.scope_kind === 'user_default') return true;
  return false;
}

function preferencePrecedence(profile) {
  return MEMORY_MODEL_SCOPE_ORDER.indexOf(profile?.scope_kind);
}

function normalizeRouteRequest(request) {
  return {
    user_id: safeStr(request?.user_id),
    project_id: safeStr(request?.project_id),
    mode: normalizeMemoryModelMode(request?.mode, ''),
    job_type: normalizeMemoryModelJobType(request?.job_type, ''),
    sensitivity: normalizeSensitivity(request?.sensitivity),
    trust_level: normalizeTrustLevel(request?.trust_level),
    budget_class: normalizeBudgetClass(request?.budget_class),
    remote_allowed_by_policy: toBool(request?.remote_allowed_by_policy, true),
    preferred_profile_id: safeStr(request?.preferred_profile_id),
    request_id: safeStr(request?.request_id),
    kill_switch_state: parseObject(request?.kill_switch_state),
  };
}

export function selectWinningMemoryModelPreference(rows, request) {
  const normalizedRequest = normalizeRouteRequest(request);
  const profiles = (Array.isArray(rows) ? rows : [])
    .map((row) => normalizeMemoryModelPreferenceRow(row))
    .filter((row) => row && row.user_id === normalizedRequest.user_id);

  if (!normalizedRequest.user_id) {
    return {
      ok: false,
      profile: null,
      deny_code: 'memory_model_profile_missing',
    };
  }

  if (normalizedRequest.preferred_profile_id) {
    const preferred = profiles.find((row) => row.profile_id === normalizedRequest.preferred_profile_id);
    if (preferred && preferenceMatchesRequest(preferred, normalizedRequest)) {
      if (isMemoryModelPreferenceDisabled(preferred)) {
        return {
          ok: false,
          profile: null,
          deny_code: 'memory_model_profile_disabled',
        };
      }
      return {
        ok: true,
        profile: preferred,
        precedence: preferencePrecedence(preferred),
      };
    }
  }

  const matches = profiles.filter((row) => preferenceMatchesRequest(row, normalizedRequest));
  const active = matches.filter((row) => !isMemoryModelPreferenceDisabled(row));

  if (active.length > 0) {
    active.sort((a, b) => {
      const precedenceDiff = preferencePrecedence(a) - preferencePrecedence(b);
      if (precedenceDiff !== 0) return precedenceDiff;
      if (b.updated_at_ms !== a.updated_at_ms) return b.updated_at_ms - a.updated_at_ms;
      return a.profile_id.localeCompare(b.profile_id);
    });
    return {
      ok: true,
      profile: active[0],
      precedence: preferencePrecedence(active[0]),
    };
  }

  return {
    ok: false,
    profile: null,
    deny_code: matches.some((row) => isMemoryModelPreferenceDisabled(row))
      ? 'memory_model_profile_disabled'
      : 'memory_model_profile_missing',
  };
}

function normalizeRegistryRow(row, keyHint = '') {
  const value = row && typeof row === 'object' ? row : {};
  const modelId = safeStr(value.model_id || keyHint);
  if (!modelId) return null;
  return {
    model_id: modelId,
    name: safeStr(value.name),
    backend: safeStr(value.backend || value.provider),
    kind: safeStr(value.kind),
    enabled: value.enabled == null ? true : toBool(value.enabled, true),
    requires_grant: value.requires_grant == null ? false : toBool(value.requires_grant, false),
  };
}

export function isMemoryModelRemote(model) {
  const kind = safeStr(model?.kind).toLowerCase();
  const backend = safeStr(model?.backend).toLowerCase();
  if (kind.includes('local') || kind.includes('offline')) return false;
  if (kind.includes('online') || kind.includes('remote')) return true;
  if (LOCAL_MODEL_BACKENDS.has(backend)) return false;
  if (model?.requires_grant) return true;
  return backend === 'openai';
}

export function buildMemoryModelRegistry(models) {
  const out = new Map();
  if (models instanceof Map) {
    for (const [key, value] of models.entries()) {
      const normalized = normalizeRegistryRow(value, String(key || ''));
      if (!normalized) continue;
      out.set(normalized.model_id, normalized);
    }
    return out;
  }

  if (Array.isArray(models)) {
    for (const row of models) {
      const normalized = normalizeRegistryRow(row);
      if (!normalized) continue;
      out.set(normalized.model_id, normalized);
    }
    return out;
  }

  if (models && typeof models === 'object') {
    for (const [key, value] of Object.entries(models)) {
      const normalized = normalizeRegistryRow(value, key);
      if (!normalized) continue;
      out.set(normalized.model_id, normalized);
    }
  }
  return out;
}

function denyRoute({ profile = null, denyCode, routeReasonCode = '', routeSource = '' } = {}) {
  const normalized = profile ? normalizeMemoryModelPreferenceRow(profile) : null;
  return {
    schema_version: 'xhub.memory_model_route_result.v1',
    resolved_profile_id: normalized?.profile_id || '',
    selection_strategy: normalized?.selection_strategy || '',
    selected_by_user: !!normalized,
    provider: '',
    model_id: '',
    route_source: routeSource || routeSourceForDeny(normalized),
    route_reason_code: routeReasonCode || denyCode || 'route_denied',
    fallback_applied: false,
    fallback_reason: '',
    export_class: 'local_only',
    remote_allowed: false,
    writer_policy_version: normalized?.policy_version || '',
    audit_ref: 'route_unpersisted',
    deny_code: denyCode || 'memory_model_profile_missing',
  };
}

function buildSuccessRoute({
  profile,
  model,
  routeSource,
  routeReasonCode,
  fallbackApplied = false,
  fallbackReason = '',
} = {}) {
  const normalized = normalizeMemoryModelPreferenceRow(profile);
  const remote = isMemoryModelRemote(model);
  return {
    schema_version: 'xhub.memory_model_route_result.v1',
    resolved_profile_id: normalized?.profile_id || '',
    selection_strategy: normalized?.selection_strategy || '',
    selected_by_user: true,
    provider: safeStr(model?.backend),
    model_id: safeStr(model?.model_id),
    route_source: routeSource || routeSourceForStrategy(normalized?.selection_strategy || ''),
    route_reason_code: routeReasonCode || 'route_selected',
    fallback_applied: !!fallbackApplied,
    fallback_reason: safeStr(fallbackReason),
    export_class: remote ? 'prompt_bundle' : 'local_only',
    remote_allowed: remote,
    writer_policy_version: normalized?.policy_version || '',
    audit_ref: 'route_unpersisted',
  };
}

function resolveSelection(profile, request) {
  const routeSource = routeSourceForStrategy(profile?.selection_strategy || '');
  if (profile?.selection_strategy === 'single_model') {
    if (!profile.primary_model_id) {
      return {
        deny_code: 'memory_model_invalid',
        route_source: routeSource,
        route_reason_code: 'single_model_missing_primary',
      };
    }
    return {
      pointer: { model_id: profile.primary_model_id },
      route_source: routeSource,
      route_reason_code: 'single_model_primary',
    };
  }

  if (profile?.selection_strategy === 'job_map') {
    const jobPointer = request.job_type ? profile.job_model_map?.[request.job_type] : null;
    if (jobPointer) {
      return {
        pointer: jobPointer,
        route_source: routeSource,
        route_reason_code: 'job_map_hit',
      };
    }
    if (profile.primary_model_id) {
      return {
        pointer: { model_id: profile.primary_model_id },
        route_source: routeSource,
        route_reason_code: 'job_map_primary_fallback',
      };
    }
    return {
      deny_code: 'memory_model_not_allowed_for_job',
      route_source: routeSource,
      route_reason_code: 'job_map_miss',
    };
  }

  if (profile?.selection_strategy === 'mode_profile') {
    const modePointer = request.mode ? profile.mode_model_map?.[request.mode] : null;
    if (modePointer) {
      return {
        pointer: modePointer,
        route_source: routeSource,
        route_reason_code: 'mode_profile_hit',
      };
    }
    if (profile.primary_model_id) {
      return {
        pointer: { model_id: profile.primary_model_id },
        route_source: routeSource,
        route_reason_code: 'mode_profile_primary_fallback',
      };
    }
    return {
      deny_code: 'memory_model_not_allowed_for_job',
      route_source: routeSource,
      route_reason_code: 'mode_profile_miss',
    };
  }

  return {
    deny_code: 'memory_model_invalid',
    route_source: routeSource,
    route_reason_code: 'selection_strategy_invalid',
  };
}

function remoteBlockedByPolicy({ profile, request, model }) {
  if (!isMemoryModelRemote(model)) return false;
  if (!profile.remote_allowed) return true;
  if (!request.remote_allowed_by_policy) return true;
  if (request.sensitivity === 'secret') return true;
  if (toBool(request.kill_switch_state?.network_disabled, false)) return true;
  return false;
}

function budgetBlockedByPolicy({ request, model }) {
  if (!isMemoryModelRemote(model)) return false;
  return REMOTE_BLOCKED_BUDGET_CLASSES.has(request.budget_class);
}

function collectFallbackCandidateIds({ profile, request, selectedPointer, selectedModelId }) {
  const policy = profile?.fallback_policy || {};
  const selected = normalizeModelPointer(selectedPointer);
  const ids = [];

  if (policy.allow_job_specific_fallback && request.job_type) {
    ids.push(modelIdFromPointer(policy.job_fallback_map?.[request.job_type]));
  }
  if (request.mode) {
    ids.push(modelIdFromPointer(policy.mode_fallback_map?.[request.mode]));
  }
  ids.push(safeStr(selected?.local_model_id));
  ids.push(safeStr(policy.local_model_id));
  ids.push(safeStr(policy.fallback_model_id));
  ids.push(safeStr(selected?.fallback_model_id));
  if (profile?.primary_model_id && profile.primary_model_id !== selectedModelId) {
    ids.push(profile.primary_model_id);
  }

  const out = [];
  const seen = new Set();
  for (const id of ids) {
    const modelId = safeStr(id);
    if (!modelId || seen.has(modelId) || modelId === selectedModelId) continue;
    seen.add(modelId);
    out.push(modelId);
  }
  return out;
}

function findLocalFallbackModel({ profile, request, registry, selectedPointer, selectedModelId, action }) {
  const policy = profile?.fallback_policy || {};
  if (fallbackActionDenies(action)) return null;
  if (!policy.allow_downgrade_to_local && !fallbackActionAllowsLocalDowngrade(action)) return null;

  const candidateIds = collectFallbackCandidateIds({
    profile,
    request,
    selectedPointer,
    selectedModelId,
  });

  for (const candidateId of candidateIds) {
    const model = registry.get(candidateId) || null;
    if (!model || !model.enabled || isMemoryModelRemote(model)) continue;
    return model;
  }
  return null;
}

export function resolveMemoryModelRoute({ profiles, request, modelsById } = {}) {
  const normalizedRequest = normalizeRouteRequest(request);
  const registry = buildMemoryModelRegistry(modelsById);
  const winner = selectWinningMemoryModelPreference(profiles, normalizedRequest);

  if (!winner.ok || !winner.profile) {
    return denyRoute({
      denyCode: winner.deny_code || 'memory_model_profile_missing',
      routeReasonCode: 'profile_resolution_failed',
      routeSource: 'system_default_fallback',
    });
  }

  const profile = normalizeMemoryModelPreferenceRow(winner.profile);
  const validation = validateMemoryModelPreference(profile);
  if (!validation.ok) {
    return denyRoute({
      profile,
      denyCode: 'memory_model_invalid',
      routeReasonCode: 'profile_contract_invalid',
    });
  }

  const selection = resolveSelection(profile, normalizedRequest);
  if (selection.deny_code) {
    return denyRoute({
      profile,
      denyCode: selection.deny_code,
      routeReasonCode: selection.route_reason_code,
      routeSource: selection.route_source,
    });
  }

  const selectedPointer = normalizeModelPointer(selection.pointer);
  const selectedModelId = modelIdFromPointer(selectedPointer);
  const selectedModel = registry.get(selectedModelId) || null;
  if (!selectedModel || !selectedModel.enabled) {
    return denyRoute({
      profile,
      denyCode: 'memory_model_invalid',
      routeReasonCode: 'selected_model_invalid',
      routeSource: selection.route_source,
    });
  }

  if (budgetBlockedByPolicy({ request: normalizedRequest, model: selectedModel })) {
    const fallbackModel = findLocalFallbackModel({
      profile,
      request: normalizedRequest,
      registry,
      selectedPointer,
      selectedModelId,
      action: profile.fallback_policy?.on_budget_exceeded,
    });
    if (!fallbackModel) {
      return denyRoute({
        profile,
        denyCode: 'memory_model_budget_blocked',
        routeReasonCode: 'budget_blocked',
        routeSource: selection.route_source,
      });
    }
    return buildSuccessRoute({
      profile,
      model: fallbackModel,
      routeSource: 'local_downgrade_fallback',
      routeReasonCode: 'local_downgrade_budget_blocked',
      fallbackApplied: true,
      fallbackReason: 'memory_model_budget_blocked',
    });
  }

  if (remoteBlockedByPolicy({ profile, request: normalizedRequest, model: selectedModel })) {
    const fallbackModel = findLocalFallbackModel({
      profile,
      request: normalizedRequest,
      registry,
      selectedPointer,
      selectedModelId,
      action: profile.fallback_policy?.on_remote_block,
    });
    if (!fallbackModel) {
      return denyRoute({
        profile,
        denyCode: 'memory_model_remote_blocked',
        routeReasonCode: 'remote_blocked',
        routeSource: selection.route_source,
      });
    }
    return buildSuccessRoute({
      profile,
      model: fallbackModel,
      routeSource: 'local_downgrade_fallback',
      routeReasonCode: 'local_downgrade_remote_blocked',
      fallbackApplied: true,
      fallbackReason: 'memory_model_remote_blocked',
    });
  }

  return buildSuccessRoute({
    profile,
    model: selectedModel,
    routeSource: selection.route_source,
    routeReasonCode: selection.route_reason_code,
  });
}
