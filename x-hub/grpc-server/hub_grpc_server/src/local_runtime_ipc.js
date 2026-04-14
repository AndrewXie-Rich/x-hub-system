import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export * from './mlx_runtime_ipc.js';

import {
  readTaskRoutingSettings as readSharedTaskRoutingSettings,
  resolveTaskRoutingBinding as resolveSharedTaskRoutingBinding,
  runtimePaths,
} from './mlx_runtime_ipc.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LOCAL_RUNTIME_SCRIPT = path.resolve(__dirname, '../../../python-runtime/python_service/relflowhub_local_runtime.py');
const BUILTIN_LOCAL_RUNTIME_PYTHON_CANDIDATES = [
  '/Library/Frameworks/Python.framework/Versions/3.11/bin/python3',
  '/Library/Frameworks/Python.framework/Versions/Current/bin/python3',
  '/opt/homebrew/bin/python3',
  '/usr/local/bin/python3',
];

function readJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function parseUpdatedAtMs(obj, fallbackMs = 0) {
  const raw = obj?.updatedAt ?? obj?.updated_at ?? obj?.updatedAtMs ?? obj?.updated_at_ms ?? 0;
  const n = Number(raw || 0);
  if (n > 10_000_000_000) return Math.max(0, Math.floor(n));
  if (n > 0) return Math.max(0, Math.floor(n * 1000.0));
  return Math.max(0, Number(fallbackMs || 0));
}

function safeString(value) {
  return String(value ?? '').trim();
}

function isExecutableFile(filePath) {
  const normalized = safeString(filePath);
  if (!normalized) return false;
  try {
    fs.accessSync(normalized, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function normalizeAbsolutePath(value) {
  const normalized = safeString(value);
  if (!normalized || !path.isAbsolute(normalized)) return '';
  return path.normalize(normalized);
}

export function isUnsafeLocalRuntimePython(value) {
  const normalized = normalizeAbsolutePath(value).toLowerCase();
  if (!normalized) return false;
  return normalized === '/usr/bin/python3'
    || normalized === '/usr/bin/python'
    || normalized.includes('/applications/xcode.app/contents/developer/')
    || normalized.includes('/library/developer/commandlinetools/');
}

function resolveCommandFromPath(commandName, env = process.env) {
  const command = safeString(commandName);
  if (!command) return '';
  if (path.isAbsolute(command)) {
    return normalizeAbsolutePath(command);
  }
  const searchPath = safeString(env?.PATH);
  if (!searchPath) return '';
  for (const entry of searchPath.split(path.delimiter)) {
    const directory = safeString(entry);
    if (!directory) continue;
    const candidate = path.join(directory, command);
    if (!isExecutableFile(candidate)) continue;
    return normalizeAbsolutePath(candidate);
  }
  return '';
}

function pushPythonCandidate(candidates, seen, rawValue, env = process.env) {
  const raw = safeString(rawValue);
  if (!raw) return;
  const resolved = path.isAbsolute(raw) ? normalizeAbsolutePath(raw) : resolveCommandFromPath(raw, env);
  if (!resolved || seen.has(resolved)) return;
  seen.add(resolved);
  candidates.push(resolved);
}

function runtimeStatusPythonCandidates(runtimeBaseDir) {
  const baseDir = safeString(runtimeBaseDir);
  if (!baseDir) return [];
  const status = readJsonSafe(path.join(baseDir, 'ai_runtime_status.json'));
  if (!status || typeof status !== 'object') return [];

  const out = [];
  const seen = new Set();
  const push = (value) => {
    const normalized = normalizeAbsolutePath(value);
    if (!normalized || seen.has(normalized)) return;
    seen.add(normalized);
    out.push(normalized);
  };

  push(status.runtimeSourcePath || status.runtime_source_path || status.pythonExecutable || status.python_executable);
  const providers = status.providers && typeof status.providers === 'object' ? status.providers : {};
  const preferredProviders = ['mlx', 'transformers'];
  for (const providerId of preferredProviders) {
    const provider = providers[providerId];
    if (!provider || typeof provider !== 'object') continue;
    push(provider.runtimeSourcePath || provider.runtime_source_path || provider.pythonExecutable || provider.python_executable);
  }
  for (const provider of Object.values(providers)) {
    if (!provider || typeof provider !== 'object') continue;
    push(provider.runtimeSourcePath || provider.runtime_source_path || provider.pythonExecutable || provider.python_executable);
  }
  return out;
}

export function resolveLocalRuntimePythonExecutable({ runtimeBaseDir = '', env = process.env } = {}) {
  const candidates = [];
  const seen = new Set();

  for (const value of [
    env?.RELFLOWHUB_AI_RUNTIME_PYTHON,
    env?.REL_FLOW_HUB_RUNTIME_PYTHON,
    env?.X_HUB_LOCAL_RUNTIME_PYTHON,
    env?.PYTHON3,
    env?.PYTHON,
  ]) {
    pushPythonCandidate(candidates, seen, value, env);
  }

  for (const value of runtimeStatusPythonCandidates(runtimeBaseDir)) {
    pushPythonCandidate(candidates, seen, value, env);
  }

  for (const value of BUILTIN_LOCAL_RUNTIME_PYTHON_CANDIDATES) {
    pushPythonCandidate(candidates, seen, value, env);
  }

  pushPythonCandidate(candidates, seen, 'python3', env);
  pushPythonCandidate(candidates, seen, 'python', env);

  for (const candidate of candidates) {
    if (isUnsafeLocalRuntimePython(candidate)) continue;
    if (isExecutableFile(candidate)) return candidate;
  }

  return '';
}

export function buildLocalRuntimeSpawnConfig({ runtimeBaseDir = '', env = process.env } = {}) {
  const baseDir = safeString(runtimeBaseDir);
  const executable = resolveLocalRuntimePythonExecutable({ runtimeBaseDir: baseDir, env });
  return {
    executable,
    env: {
      ...env,
      REL_FLOW_HUB_BASE_DIR: baseDir,
    },
    error: executable
      ? ''
      : 'local_runtime_python_unavailable: install a real Python 3.11 and restart AI Runtime to pin runtimeSourcePath',
  };
}

function safeStringList(values) {
  if (values == null) return [];
  const out = [];
  const seen = new Set();
  const items = Array.isArray(values) ? values : String(values || '').split(',');
  for (const raw of items) {
    const cleaned = String(raw || '').trim();
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

function normalizeProviderId(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function normalizeRouteTrace(raw) {
  const row = normalizeObject(raw);
  return Object.keys(row).length > 0 ? row : null;
}

function normalizeRouteTraceSummary(raw, routeTrace = null) {
  const summary = normalizeObject(raw);
  if (Object.keys(summary).length > 0) {
    return {
      schema_version: String(summary.schemaVersion || summary.schema_version || '').trim(),
      trace_schema_version: String(summary.traceSchemaVersion || summary.trace_schema_version || '').trim(),
      request_mode: String(summary.requestMode || summary.request_mode || '').trim(),
      selected_task_kind: String(summary.selectedTaskKind || summary.selected_task_kind || '').trim().toLowerCase(),
      selection_reason: String(summary.selectionReason || summary.selection_reason || '').trim(),
      explicit_task_kind: String(summary.explicitTaskKind || summary.explicit_task_kind || '').trim().toLowerCase(),
      image_count: Math.max(0, Math.floor(Number(summary.imageCount || summary.image_count || 0) || 0)),
      resolved_image_count: Math.max(0, Math.floor(Number(summary.resolvedImageCount || summary.resolved_image_count || 0) || 0)),
      blocked_reason_code: String(summary.blockedReasonCode || summary.blocked_reason_code || '').trim(),
      blocked_image_index: summary.blockedImageIndex == null && summary.blocked_image_index == null
        ? null
        : Math.max(0, Math.floor(Number(summary.blockedImageIndex || summary.blocked_image_index || 0) || 0)),
      prompt_chars: Math.max(0, Math.floor(Number(summary.promptChars || summary.prompt_chars || 0) || 0)),
      execution_path: String(summary.executionPath || summary.execution_path || '').trim(),
      fallback_mode: String(summary.fallbackMode || summary.fallback_mode || '').trim(),
      image_files: safeStringList(summary.imageFiles || summary.image_files),
      raw: summary,
    };
  }
  const trace = normalizeRouteTrace(routeTrace);
  if (!trace) return null;
  const resolvedImages = Array.isArray(trace.resolvedImages || trace.resolved_images) ? (trace.resolvedImages || trace.resolved_images) : [];
  const imageFiles = safeStringList(trace.imageFiles || trace.image_files);
  for (const fileName of safeStringList(
    resolvedImages
      .map((row) => normalizeObject(row))
      .map((row) => row.fileName || row.file_name)
  )) {
    if (!imageFiles.includes(fileName)) imageFiles.push(fileName);
  }
  return {
    schema_version: 'xhub.local_runtime.route_trace_summary.v1',
    trace_schema_version: String(trace.schemaVersion || trace.schema_version || '').trim(),
    request_mode: String(trace.requestMode || trace.request_mode || '').trim(),
    selected_task_kind: String(trace.selectedTaskKind || trace.selected_task_kind || trace.taskKind || trace.task_kind || '').trim().toLowerCase(),
    selection_reason: String(trace.selectionReason || trace.selection_reason || '').trim(),
    explicit_task_kind: String(trace.explicitTaskKind || trace.explicit_task_kind || '').trim().toLowerCase(),
    image_count: Math.max(0, Math.floor(Number(trace.imageCount || trace.image_count || 0) || 0)),
    resolved_image_count: Math.max(0, Math.floor(Number(trace.resolvedImageCount || trace.resolved_image_count || 0) || 0)),
    blocked_reason_code: String(trace.blockedReasonCode || trace.blocked_reason_code || '').trim(),
    blocked_image_index: trace.blockedImageIndex == null && trace.blocked_image_index == null
      ? null
      : Math.max(0, Math.floor(Number(trace.blockedImageIndex || trace.blocked_image_index || 0) || 0)),
    prompt_chars: Math.max(0, Math.floor(Number(trace.promptChars || trace.prompt_chars || 0) || 0)),
    execution_path: String(trace.executionPath || trace.execution_path || '').trim(),
    fallback_mode: String(trace.fallbackMode || trace.fallback_mode || '').trim(),
    image_files: imageFiles,
    raw: trace,
  };
}

function normalizeTaskKinds(taskKinds, backend) {
  const out = safeStringList(taskKinds).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean);
  if (out.length > 0) return out;
  return normalizeProviderId(backend) === 'mlx' ? ['text_generate'] : [];
}

function normalizePositiveInt(value, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.max(min, Math.min(max, Math.floor(n)));
}

function normalizePositiveNumber(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

function normalizeRatio(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.max(0, Math.min(1, n));
}

function normalizeLoadConfigVision(value) {
  const row = normalizeObject(value);
  const imageMaxDimension = normalizePositiveInt(
    row.imageMaxDimension ?? row.image_max_dimension,
    { min: 32, max: 16_384 }
  );
  if (imageMaxDimension == null) return null;
  return {
    image_max_dimension: imageMaxDimension,
  };
}

function normalizeLoadConfig(value, { fallbackContextLength = 0 } = {}) {
  const row = normalizeObject(value);
  const fallbackContext = normalizePositiveInt(fallbackContextLength, { min: 512 });
  const contextLength = normalizePositiveInt(
    row.contextLength ?? row.context_length ?? fallbackContext,
    { min: 512 }
  );
  const gpuOffloadRatio = normalizeRatio(row.gpuOffloadRatio ?? row.gpu_offload_ratio);
  const ropeFrequencyBase = normalizePositiveNumber(row.ropeFrequencyBase ?? row.rope_frequency_base);
  const ropeFrequencyScale = normalizePositiveNumber(row.ropeFrequencyScale ?? row.rope_frequency_scale);
  const evalBatchSize = normalizePositiveInt(row.evalBatchSize ?? row.eval_batch_size);
  const ttl = normalizePositiveInt(row.ttl ?? row.ttlSec ?? row.ttl_sec);
  const parallel = normalizePositiveInt(row.parallel);
  const identifier = safeString(row.identifier);
  const flatVision = normalizePositiveInt(
    row.visionImageMaxDimension ?? row.vision_image_max_dimension,
    { min: 32, max: 16_384 }
  );
  const vision = normalizeLoadConfigVision(row.vision)
    || (flatVision == null ? null : { image_max_dimension: flatVision });

  const out = {
    schema_version: 'xhub.load_config.v1',
  };
  if (contextLength != null) out.context_length = contextLength;
  if (gpuOffloadRatio != null) out.gpu_offload_ratio = gpuOffloadRatio;
  if (ropeFrequencyBase != null) out.rope_frequency_base = ropeFrequencyBase;
  if (ropeFrequencyScale != null) out.rope_frequency_scale = ropeFrequencyScale;
  if (evalBatchSize != null) out.eval_batch_size = evalBatchSize;
  if (ttl != null) out.ttl = ttl;
  if (parallel != null) out.parallel = parallel;
  if (identifier) out.identifier = identifier;
  if (vision) out.vision = vision;
  return Object.keys(out).length > 1 ? out : null;
}

function normalizeModelMaxContextLength(value, fallbackContextLength = 0) {
  const row = normalizeObject(value);
  const explicitMaxContextLength = normalizePositiveInt(
    row.maxContextLength ?? row.max_context_length,
    { min: 512 }
  ) || 0;
  const fallbackContext = normalizePositiveInt(fallbackContextLength, { min: 512 }) || 0;
  return Math.max(explicitMaxContextLength, fallbackContext);
}

function normalizeTaskLimits(value) {
  const obj = normalizeObject(value);
  const out = {};
  for (const [taskKind, rawLimit] of Object.entries(obj)) {
    const key = String(taskKind || '').trim().toLowerCase();
    if (!key) continue;
    const limit = Number(rawLimit || 0);
    out[key] = Number.isFinite(limit) && limit > 0 ? Math.floor(limit) : 1;
  }
  return out;
}

function normalizeRuntimeRequirements(value) {
  const obj = normalizeObject(value);
  return {
    execution_mode: String(obj.executionMode || obj.execution_mode || '').trim(),
    python_modules: safeStringList(obj.pythonModules || obj.python_modules).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean),
    helper_binary: String(obj.helperBinary || obj.helper_binary || '').trim(),
    native_dylib: String(obj.nativeDylib || obj.native_dylib || '').trim(),
    notes: safeStringList(obj.notes).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean),
  };
}

function normalizeProviderPack(value) {
  const row = normalizeObject(value);
  return {
    schema_version: String(row.schemaVersion || row.schema_version || '').trim(),
    provider_id: normalizeProviderId(row.providerId || row.provider_id),
    engine: String(row.engine || '').trim(),
    version: String(row.version || '').trim(),
    supported_formats: safeStringList(row.supportedFormats || row.supported_formats).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean),
    supported_domains: safeStringList(row.supportedDomains || row.supported_domains).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean),
    runtime_requirements: normalizeRuntimeRequirements(row.runtimeRequirements || row.runtime_requirements),
    min_hub_version: String(row.minHubVersion || row.min_hub_version || '').trim(),
    installed: !!(row.installed ?? false),
    enabled: !!(row.enabled ?? false),
    pack_state: String(row.packState || row.pack_state || '').trim().toLowerCase(),
    reason_code: String(row.reasonCode || row.reason_code || '').trim(),
  };
}

function deriveProviderPackFromRawStatus(providerId, rawStatus) {
  const row = normalizeObject(rawStatus);
  const normalizedProviderId = normalizeProviderId(
    row.packId || row.pack_id || row.providerId || row.provider_id || providerId
  );
  if (!normalizedProviderId) return null;

  const hasPackTruth = Boolean(
    safeString(row.packId || row.pack_id)
    || safeString(row.packEngine || row.pack_engine)
    || safeString(row.packVersion || row.pack_version)
    || safeString(row.packState || row.pack_state)
    || safeString(row.packReasonCode || row.pack_reason_code)
    || Object.prototype.hasOwnProperty.call(row, 'packInstalled')
    || Object.prototype.hasOwnProperty.call(row, 'pack_installed')
    || Object.prototype.hasOwnProperty.call(row, 'packEnabled')
    || Object.prototype.hasOwnProperty.call(row, 'pack_enabled')
  );
  if (!hasPackTruth) return null;

  const installedExplicit = row.packInstalled ?? row.pack_installed;
  const enabledExplicit = row.packEnabled ?? row.pack_enabled;
  const rawPackState = String(row.packState || row.pack_state || '').trim().toLowerCase();
  const packState = rawPackState
    || ((installedExplicit === false)
      ? 'not_installed'
      : ((enabledExplicit === false) ? 'disabled' : 'installed'));
  const installed = installedExplicit == null ? packState !== 'not_installed' : !!installedExplicit;
  const enabled = enabledExplicit == null ? (installed && packState !== 'disabled') : !!enabledExplicit;

  return normalizeProviderPack({
    schemaVersion: 'xhub.provider_pack_manifest.v1',
    providerId: normalizedProviderId,
    engine: String(row.packEngine || row.pack_engine || normalizedProviderId).trim(),
    version: String(row.packVersion || row.pack_version || 'provider_status_unversioned').trim(),
    supportedFormats: [],
    supportedDomains: [],
    runtimeRequirements: {
      executionMode: '',
      notes: ['derived_from_provider_status'],
    },
    minHubVersion: '',
    installed,
    enabled,
    packState,
    reasonCode: String(row.packReasonCode || row.pack_reason_code || 'provider_status_pack_truth').trim(),
  });
}

function synthesizeProviderPack(providerId) {
  return {
    schema_version: 'xhub.provider_pack_manifest.v1',
    provider_id: normalizeProviderId(providerId),
    engine: normalizeProviderId(providerId),
    version: 'legacy_unreported',
    supported_formats: [],
    supported_domains: [],
    runtime_requirements: {
      execution_mode: '',
      python_modules: [],
      helper_binary: '',
      native_dylib: '',
      notes: ['legacy_runtime_status_without_pack_inventory'],
    },
    min_hub_version: '',
    installed: false,
    enabled: false,
    pack_state: 'legacy_unreported',
    reason_code: 'runtime_status_missing_provider_pack_inventory',
  };
}

function normalizeResourcePolicy(value) {
  const obj = normalizeObject(value);
  return {
    preferred_device: String(obj.preferredDevice || obj.preferred_device || '').trim(),
    memory_floor_mb: Math.max(0, Math.floor(Number(obj.memoryFloorMB || obj.memory_floor_mb || 0) || 0)),
    dtype: String(obj.dtype || '').trim(),
    concurrency_limit: Math.max(1, Math.floor(Number(obj.concurrencyLimit || obj.concurrency_limit || 1) || 1)),
    selected_task_kind: String(obj.selectedTaskKind || obj.selected_task_kind || '').trim().toLowerCase(),
    selected_task_limit: Math.max(1, Math.floor(Number(obj.selectedTaskLimit || obj.selected_task_limit || 1) || 1)),
    queueing_supported: !!(obj.queueingSupported ?? obj.queueing_supported ?? false),
    queue_mode: String(obj.queueMode || obj.queue_mode || '').trim(),
    default_queue_poll_ms: Math.max(0, Math.floor(Number(obj.defaultQueuePollMs || obj.default_queue_poll_ms || 0) || 0)),
    task_limits: normalizeTaskLimits(obj.taskLimits || obj.task_limits),
  };
}

function normalizeSchedulerState(value, fallbackUpdatedAtMs) {
  const obj = normalizeObject(value);
  const activeTasks = Array.isArray(obj.activeTasks || obj.active_tasks)
    ? (obj.activeTasks || obj.active_tasks).map((entry) => {
      const row = normalizeObject(entry);
      const loadConfigHash = String(
        row.loadConfigHash || row.load_config_hash || row.loadProfileHash || row.load_profile_hash || ''
      ).trim();
      const currentContextLength = Math.max(
        0,
        Math.floor(Number(
          row.currentContextLength
          || row.current_context_length
          || row.effectiveContextLength
          || row.effective_context_length
          || 0
        ) || 0)
      );
      const maxContextLength = Math.max(
        currentContextLength,
        Math.floor(Number(row.maxContextLength || row.max_context_length || 0) || 0)
      );
      const leaseTtlSec = normalizePositiveInt(
        row.leaseTtlSec ?? row.lease_ttl_sec ?? row.ttlSec ?? row.ttl_sec
      );
      const leaseRemainingTtlRaw = row.leaseRemainingTtlSec
        ?? row.lease_remaining_ttl_sec
        ?? row.ttlRemainingSec
        ?? row.ttl_remaining_sec;
      const leaseRemainingTtlSec = leaseRemainingTtlRaw == null
        ? null
        : Math.max(0, Math.floor(Number(leaseRemainingTtlRaw || 0) || 0));
      const expiresAtMs = parseUpdatedAtMs({ updatedAt: row.expiresAt || row.expires_at }, 0);
      const progress = normalizeRatio(row.progress);
      const out = {
        lease_id: String(row.leaseId || row.lease_id || '').trim(),
        task_kind: String(row.taskKind || row.task_kind || '').trim().toLowerCase(),
        model_id: String(row.modelId || row.model_id || '').trim(),
        request_id: String(row.requestId || row.request_id || '').trim(),
        device_id: String(row.deviceId || row.device_id || '').trim(),
        load_profile_hash: loadConfigHash,
        load_config_hash: loadConfigHash,
        instance_key: String(row.instanceKey || row.instance_key || '').trim(),
        effective_context_length: currentContextLength,
        current_context_length: currentContextLength,
        max_context_length: maxContextLength,
        started_at_ms: parseUpdatedAtMs(row, fallbackUpdatedAtMs),
      };
      if (leaseTtlSec != null) out.lease_ttl_sec = leaseTtlSec;
      if (leaseRemainingTtlSec != null) out.lease_remaining_ttl_sec = leaseRemainingTtlSec;
      if (expiresAtMs > 0) out.expires_at_ms = expiresAtMs;
      if (progress != null) out.progress = progress;
      return out;
    }).filter((row) => row.lease_id)
    : [];
  return {
    concurrency_limit: Math.max(1, Math.floor(Number(obj.concurrencyLimit || obj.concurrency_limit || 1) || 1)),
    active_task_count: Math.max(0, Math.floor(Number(obj.activeTaskCount || obj.active_task_count || 0) || 0)),
    queued_task_count: Math.max(0, Math.floor(Number(obj.queuedTaskCount || obj.queued_task_count || 0) || 0)),
    queue_mode: String(obj.queueMode || obj.queue_mode || '').trim(),
    queueing_supported: !!(obj.queueingSupported ?? obj.queueing_supported ?? false),
    oldest_waiter_started_at_ms: parseUpdatedAtMs({ updatedAt: obj.oldestWaiterStartedAt || obj.oldest_waiter_started_at }, 0),
    oldest_waiter_age_ms: Math.max(0, Math.floor(Number(obj.oldestWaiterAgeMs || obj.oldest_waiter_age_ms || 0) || 0)),
    contention_count: Math.max(0, Math.floor(Number(obj.contentionCount || obj.contention_count || 0) || 0)),
    last_contention_at_ms: parseUpdatedAtMs({ updatedAt: obj.lastContentionAt || obj.last_contention_at }, 0),
    updated_at_ms: parseUpdatedAtMs(obj, fallbackUpdatedAtMs),
    active_tasks: activeTasks,
  };
}

function normalizeLoadedInstances(value) {
  const rows = Array.isArray(value) ? value : [];
  return rows.map((entry) => {
    const row = normalizeObject(entry);
    const loadConfigHash = String(
      row.loadConfigHash || row.load_config_hash || row.loadProfileHash || row.load_profile_hash || ''
    ).trim();
    const currentContextLength = Math.max(
      0,
      Math.floor(Number(
        row.currentContextLength
        || row.current_context_length
        || row.effectiveContextLength
        || row.effective_context_length
        || 0
      ) || 0)
    );
    const loadConfig = normalizeLoadConfig(
      row.loadConfig
      || row.load_config
      || row.effectiveLoadProfile
      || row.effective_load_profile,
      { fallbackContextLength: currentContextLength }
    );
    const maxContextLength = Math.max(
      currentContextLength,
      Math.floor(Number(row.maxContextLength || row.max_context_length || 0) || 0),
      Math.max(0, Math.floor(Number(loadConfig?.context_length || 0) || 0))
    );
    const ttl = normalizePositiveInt(row.ttl ?? row.ttlSec ?? row.ttl_sec ?? loadConfig?.ttl);
    const progress = normalizeRatio(row.progress);
    const out = {
      provider: String(row.provider || '').trim().toLowerCase(),
      instance_key: String(row.instanceKey || row.instance_key || '').trim(),
      model_id: String(row.modelId || row.model_id || '').trim(),
      task_kinds: safeStringList(row.taskKinds || row.task_kinds).map((taskKind) => String(taskKind || '').trim().toLowerCase()).filter(Boolean),
      load_profile_hash: loadConfigHash,
      load_config_hash: loadConfigHash,
      effective_context_length: currentContextLength,
      current_context_length: currentContextLength,
      max_context_length: maxContextLength,
      effective_load_profile: loadConfig,
      load_config: loadConfig,
      loaded_at_ms: parseUpdatedAtMs({ updatedAt: row.loadedAt || row.loaded_at || row.loadedAtMs || row.loaded_at_ms }, 0),
      last_used_at_ms: parseUpdatedAtMs({ updatedAt: row.lastUsedAt || row.last_used_at || row.lastUsedAtMs || row.last_used_at_ms }, 0),
      residency: String(row.residency || '').trim(),
      residency_scope: String(row.residencyScope || row.residency_scope || '').trim(),
      device_backend: String(row.deviceBackend || row.device_backend || '').trim(),
    };
    if (ttl != null) out.ttl = ttl;
    if (progress != null) out.progress = progress;
    return out;
  }).filter((row) => row.instance_key);
}

function normalizeIdleEviction(value) {
  const row = normalizeObject(value);
  return {
    policy: String(row.policy || '').trim(),
    automatic_idle_eviction_enabled: !!(row.automaticIdleEvictionEnabled ?? row.automatic_idle_eviction_enabled ?? false),
    idle_timeout_sec: Math.max(0, Math.floor(Number(row.idleTimeoutSec || row.idle_timeout_sec || 0) || 0)),
    process_scoped: !!(row.processScoped ?? row.process_scoped ?? false),
    last_eviction_reason: String(row.lastEvictionReason || row.last_eviction_reason || '').trim(),
    last_eviction_at_ms: parseUpdatedAtMs({ updatedAt: row.lastEvictionAt || row.last_eviction_at }, 0),
    last_evicted_instance_keys: safeStringList(row.lastEvictedInstanceKeys || row.last_evicted_instance_keys),
    last_evicted_model_ids: safeStringList(row.lastEvictedModelIds || row.last_evicted_model_ids),
    last_evicted_count: Math.max(0, Math.floor(Number(row.lastEvictedCount || row.last_evicted_count || 0) || 0)),
    total_evicted_instance_count: Math.max(0, Math.floor(Number(row.totalEvictedInstanceCount || row.total_evicted_instance_count || 0) || 0)),
    updated_at_ms: parseUpdatedAtMs(row, 0),
    owner_pid: Math.max(0, Math.floor(Number(row.ownerPid || row.owner_pid || 0) || 0)),
  };
}

function normalizeLowercaseTaskKinds(values) {
  return safeStringList(values).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean);
}

function normalizeProviderStatus(rawProviderId, rawStatus, fallbackUpdatedAtMs, fallbackRuntimeVersion) {
  const providerId = normalizeProviderId(rawStatus?.provider || rawProviderId);
  const updatedAtMs = parseUpdatedAtMs(rawStatus, fallbackUpdatedAtMs);
  const availableTaskKinds = normalizeLowercaseTaskKinds(rawStatus?.availableTaskKinds || rawStatus?.available_task_kinds);
  let realTaskKinds = normalizeLowercaseTaskKinds(rawStatus?.realTaskKinds || rawStatus?.real_task_kinds);
  let fallbackTaskKinds = normalizeLowercaseTaskKinds(rawStatus?.fallbackTaskKinds || rawStatus?.fallback_task_kinds);
  const unavailableTaskKinds = normalizeLowercaseTaskKinds(rawStatus?.unavailableTaskKinds || rawStatus?.unavailable_task_kinds);
  const reasonCode = String(rawStatus?.reasonCode || rawStatus?.reason_code || '').trim();
  if (realTaskKinds.length === 0 && fallbackTaskKinds.length === 0) {
    if (reasonCode === 'fallback_ready') {
      fallbackTaskKinds = [...availableTaskKinds];
    } else {
      realTaskKinds = [...availableTaskKinds];
    }
  }
  return {
    provider: providerId || normalizeProviderId(rawProviderId),
    ok: !!rawStatus?.ok,
    reason_code: reasonCode,
    runtime_version: String(rawStatus?.runtimeVersion || rawStatus?.runtime_version || fallbackRuntimeVersion || '').trim(),
    available_task_kinds: availableTaskKinds,
    real_task_kinds: realTaskKinds,
    fallback_task_kinds: fallbackTaskKinds,
    unavailable_task_kinds: unavailableTaskKinds,
    loaded_models: safeStringList(rawStatus?.loadedModels || rawStatus?.loaded_models),
    active_memory_bytes: Math.max(0, Math.floor(Number(rawStatus?.activeMemoryBytes || rawStatus?.active_memory_bytes || 0) || 0)),
    peak_memory_bytes: Math.max(0, Math.floor(Number(rawStatus?.peakMemoryBytes || rawStatus?.peak_memory_bytes || 0) || 0)),
    loaded_model_count: Math.max(
      safeStringList(rawStatus?.loadedModels || rawStatus?.loaded_models).length,
      Math.floor(Number(rawStatus?.loadedModelCount || rawStatus?.loaded_model_count || 0) || 0)
    ),
    registered_models: safeStringList(rawStatus?.registeredModels || rawStatus?.registered_models),
    device_backend: String(rawStatus?.deviceBackend || rawStatus?.device_backend || '').trim(),
    updated_at_ms: updatedAtMs,
    import_error: String(rawStatus?.importError || rawStatus?.import_error || '').trim(),
    resource_policy: normalizeResourcePolicy(rawStatus?.resourcePolicy || rawStatus?.resource_policy),
    scheduler_state: normalizeSchedulerState(rawStatus?.schedulerState || rawStatus?.scheduler_state, updatedAtMs),
    lifecycle_mode: String(rawStatus?.lifecycleMode || rawStatus?.lifecycle_mode || '').trim(),
    supported_lifecycle_actions: safeStringList(rawStatus?.supportedLifecycleActions || rawStatus?.supported_lifecycle_actions),
    warmup_task_kinds: safeStringList(rawStatus?.warmupTaskKinds || rawStatus?.warmup_task_kinds)
      .map((value) => String(value || '').trim().toLowerCase())
      .filter(Boolean),
    residency_scope: String(rawStatus?.residencyScope || rawStatus?.residency_scope || '').trim(),
    pack_id: String(rawStatus?.packId || rawStatus?.pack_id || '').trim().toLowerCase(),
    pack_engine: String(rawStatus?.packEngine || rawStatus?.pack_engine || '').trim(),
    pack_version: String(rawStatus?.packVersion || rawStatus?.pack_version || '').trim(),
    pack_installed: !!(rawStatus?.packInstalled ?? rawStatus?.pack_installed ?? false),
    pack_enabled: !!(rawStatus?.packEnabled ?? rawStatus?.pack_enabled ?? false),
    pack_state: String(rawStatus?.packState || rawStatus?.pack_state || '').trim().toLowerCase(),
    pack_reason_code: String(rawStatus?.packReasonCode || rawStatus?.pack_reason_code || '').trim(),
    runtime_source: String(rawStatus?.runtimeSource || rawStatus?.runtime_source || '').trim().toLowerCase(),
    runtime_source_path: String(rawStatus?.runtimeSourcePath || rawStatus?.runtime_source_path || '').trim(),
    runtime_resolution_state: String(rawStatus?.runtimeResolutionState || rawStatus?.runtime_resolution_state || '').trim().toLowerCase(),
    runtime_reason_code: String(rawStatus?.runtimeReasonCode || rawStatus?.runtime_reason_code || '').trim(),
    fallback_used: !!(rawStatus?.fallbackUsed ?? rawStatus?.fallback_used ?? false),
    runtime_hint: String(rawStatus?.runtimeHint || rawStatus?.runtime_hint || '').trim(),
    runtime_missing_requirements: safeStringList(
      rawStatus?.runtimeMissingRequirements || rawStatus?.runtime_missing_requirements
    ).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean),
    runtime_missing_optional_requirements: safeStringList(
      rawStatus?.runtimeMissingOptionalRequirements || rawStatus?.runtime_missing_optional_requirements
    ).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean),
    loaded_instances: normalizeLoadedInstances(rawStatus?.loadedInstances || rawStatus?.loaded_instances),
    idle_eviction: normalizeIdleEviction(rawStatus?.idleEviction || rawStatus?.idle_eviction),
  };
}

function buildMonitorActiveTasks(providers) {
  const rows = [];
  for (const [providerId, provider] of Object.entries(providers || {})) {
    const activeTasks = Array.isArray(provider?.scheduler_state?.active_tasks) ? provider.scheduler_state.active_tasks : [];
    for (const task of activeTasks) {
      if (!task || typeof task !== 'object') continue;
      const leaseTtlSec = normalizePositiveInt(task.lease_ttl_sec);
      const leaseRemainingTtlRaw = task.lease_remaining_ttl_sec;
      const leaseRemainingTtlSec = leaseRemainingTtlRaw == null
        ? null
        : Math.max(0, Math.floor(Number(leaseRemainingTtlRaw || 0) || 0));
      const expiresAtMs = Math.max(0, Math.floor(Number(task.expires_at_ms || 0) || 0));
      const progress = normalizeRatio(task.progress);
      const row = {
        provider: normalizeProviderId(providerId),
        lease_id: String(task.lease_id || '').trim(),
        task_kind: String(task.task_kind || '').trim().toLowerCase(),
        model_id: String(task.model_id || '').trim(),
        request_id: String(task.request_id || '').trim(),
        device_id: String(task.device_id || '').trim(),
        load_profile_hash: String(task.load_profile_hash || '').trim(),
        instance_key: String(task.instance_key || '').trim(),
        effective_context_length: Math.max(0, Math.floor(Number(task.effective_context_length || 0) || 0)),
        started_at_ms: Math.max(0, Math.floor(Number(task.started_at_ms || 0) || 0)),
      };
      if (leaseTtlSec != null) row.lease_ttl_sec = leaseTtlSec;
      if (leaseRemainingTtlSec != null) row.lease_remaining_ttl_sec = leaseRemainingTtlSec;
      if (expiresAtMs > 0) row.expires_at_ms = expiresAtMs;
      if (progress != null) row.progress = progress;
      rows.push(row);
    }
  }
  rows.sort((left, right) => {
    const lp = String(left.provider || '').trim();
    const rp = String(right.provider || '').trim();
    if (lp !== rp) return lp.localeCompare(rp);
    const lt = String(left.task_kind || '').trim();
    const rt = String(right.task_kind || '').trim();
    if (lt !== rt) return lt.localeCompare(rt);
    const lm = String(left.model_id || '').trim();
    const rm = String(right.model_id || '').trim();
    if (lm !== rm) return lm.localeCompare(rm);
    return String(left.lease_id || '').trim().localeCompare(String(right.lease_id || '').trim());
  });
  return rows;
}

function buildMonitorLastErrors(providers) {
  const rows = [];
  for (const [providerId, provider] of Object.entries(providers || {})) {
    const importError = String(provider?.import_error || '').trim();
    const reasonCode = String(provider?.reason_code || '').trim();
    const ok = !!provider?.ok;
    if (ok && !importError) continue;
    const message = importError || reasonCode || 'provider_unavailable';
    if (!message) continue;
    rows.push({
      provider: normalizeProviderId(providerId),
      code: reasonCode || (importError ? 'import_error' : 'provider_unavailable'),
      message,
      severity: ok ? 'warn' : 'error',
      updated_at_ms: Math.max(0, Math.floor(Number(provider?.updated_at_ms || 0) || 0)),
    });
  }
  rows.sort((left, right) => {
    const lp = String(left.provider || '').trim();
    const rp = String(right.provider || '').trim();
    if (lp !== rp) return lp.localeCompare(rp);
    return String(left.code || '').trim().localeCompare(String(right.code || '').trim());
  });
  return rows;
}

function buildMonitorFallbackCounters(providers) {
  const taskKindCounts = {};
  let fallbackReadyProviderCount = 0;
  let fallbackOnlyProviderCount = 0;
  let fallbackReadyTaskCount = 0;
  let fallbackOnlyTaskCount = 0;
  const providerCount = Object.keys(providers || {}).length;
  for (const provider of Object.values(providers || {})) {
    const fallbackTaskKinds = Array.isArray(provider?.fallback_task_kinds) ? provider.fallback_task_kinds : [];
    const realTaskKinds = Array.isArray(provider?.real_task_kinds) ? provider.real_task_kinds : [];
    if (fallbackTaskKinds.length === 0) continue;
    fallbackReadyProviderCount += 1;
    fallbackReadyTaskCount += fallbackTaskKinds.length;
    if (realTaskKinds.length === 0) {
      fallbackOnlyProviderCount += 1;
      fallbackOnlyTaskCount += fallbackTaskKinds.length;
    }
    for (const taskKind of fallbackTaskKinds) {
      const key = String(taskKind || '').trim().toLowerCase();
      if (!key) continue;
      taskKindCounts[key] = Math.max(0, Number(taskKindCounts[key] || 0)) + 1;
    }
  }
  return {
    provider_count: providerCount,
    fallback_ready_provider_count: fallbackReadyProviderCount,
    fallback_only_provider_count: fallbackOnlyProviderCount,
    fallback_ready_task_count: fallbackReadyTaskCount,
    fallback_only_task_count: fallbackOnlyTaskCount,
    task_kind_counts: taskKindCounts,
  };
}

function buildMonitorQueue(providers, updatedAtMs) {
  const providerRows = [];
  let activeTaskCount = 0;
  let queuedTaskCount = 0;
  let providersBusyCount = 0;
  let providersWithQueuedTasksCount = 0;
  let maxOldestWaitMs = 0;
  let contentionCount = 0;
  let lastContentionAtMs = 0;
  for (const [providerId, provider] of Object.entries(providers || {})) {
    const scheduler = provider?.scheduler_state || {};
    const row = {
      provider: normalizeProviderId(providerId),
      concurrency_limit: Math.max(1, Math.floor(Number(scheduler.concurrency_limit || 1) || 1)),
      active_task_count: Math.max(0, Math.floor(Number(scheduler.active_task_count || 0) || 0)),
      queued_task_count: Math.max(0, Math.floor(Number(scheduler.queued_task_count || 0) || 0)),
      queue_mode: String(scheduler.queue_mode || '').trim() || 'unknown',
      queueing_supported: !!scheduler.queueing_supported,
      oldest_waiter_started_at_ms: Math.max(0, Math.floor(Number(scheduler.oldest_waiter_started_at_ms || 0) || 0)),
      oldest_waiter_age_ms: Math.max(0, Math.floor(Number(scheduler.oldest_waiter_age_ms || 0) || 0)),
      contention_count: Math.max(0, Math.floor(Number(scheduler.contention_count || 0) || 0)),
      last_contention_at_ms: Math.max(0, Math.floor(Number(scheduler.last_contention_at_ms || 0) || 0)),
      updated_at_ms: Math.max(0, Math.floor(Number(scheduler.updated_at_ms || provider?.updated_at_ms || updatedAtMs || 0) || 0)),
    };
    providerRows.push(row);
    activeTaskCount += row.active_task_count;
    queuedTaskCount += row.queued_task_count;
    providersBusyCount += row.active_task_count >= row.concurrency_limit ? 1 : 0;
    providersWithQueuedTasksCount += row.queued_task_count > 0 ? 1 : 0;
    maxOldestWaitMs = Math.max(maxOldestWaitMs, row.oldest_waiter_age_ms);
    contentionCount += row.contention_count;
    lastContentionAtMs = Math.max(lastContentionAtMs, row.last_contention_at_ms);
  }
  providerRows.sort((left, right) => String(left.provider || '').trim().localeCompare(String(right.provider || '').trim()));
  return {
    provider_count: providerRows.length,
    active_task_count: activeTaskCount,
    queued_task_count: queuedTaskCount,
    providers_busy_count: providersBusyCount,
    providers_with_queued_tasks_count: providersWithQueuedTasksCount,
    max_oldest_wait_ms: maxOldestWaitMs,
    contention_count: contentionCount,
    last_contention_at_ms: lastContentionAtMs,
    updated_at_ms: Math.max(0, Math.floor(Number(updatedAtMs || 0) || 0)),
    providers: providerRows,
  };
}

function buildMonitorProviders(providers) {
  const rows = [];
  for (const [providerId, provider] of Object.entries(providers || {})) {
    const loadedInstances = Array.isArray(provider?.loaded_instances) ? provider.loaded_instances : [];
    const scheduler = provider?.scheduler_state || {};
    const activeMemoryBytes = Math.max(0, Math.floor(Number(provider?.active_memory_bytes || 0) || 0));
    const peakMemoryBytes = Math.max(0, Math.floor(Number(provider?.peak_memory_bytes || 0) || 0));
    rows.push({
      provider: normalizeProviderId(providerId),
      ok: !!provider?.ok,
      reason_code: String(provider?.reason_code || '').trim(),
      import_error: String(provider?.import_error || '').trim(),
      runtime_source: String(provider?.runtime_source || '').trim().toLowerCase(),
      runtime_resolution_state: String(provider?.runtime_resolution_state || '').trim().toLowerCase(),
      runtime_reason_code: String(provider?.runtime_reason_code || '').trim(),
      fallback_used: !!provider?.fallback_used,
      available_task_kinds: Array.isArray(provider?.available_task_kinds) ? provider.available_task_kinds : [],
      real_task_kinds: Array.isArray(provider?.real_task_kinds) ? provider.real_task_kinds : [],
      fallback_task_kinds: Array.isArray(provider?.fallback_task_kinds) ? provider.fallback_task_kinds : [],
      unavailable_task_kinds: Array.isArray(provider?.unavailable_task_kinds) ? provider.unavailable_task_kinds : [],
      device_backend: String(provider?.device_backend || '').trim() || 'unknown',
      lifecycle_mode: String(provider?.lifecycle_mode || '').trim(),
      residency_scope: String(provider?.residency_scope || '').trim(),
      loaded_instance_count: loadedInstances.length,
      loaded_model_count: Math.max(loadedInstances.length, Math.floor(Number(provider?.loaded_model_count || 0) || 0)),
      active_task_count: Math.max(0, Math.floor(Number(scheduler.active_task_count || 0) || 0)),
      queued_task_count: Math.max(0, Math.floor(Number(scheduler.queued_task_count || 0) || 0)),
      concurrency_limit: Math.max(1, Math.floor(Number(scheduler.concurrency_limit || 1) || 1)),
      queue_mode: String(scheduler.queue_mode || '').trim() || 'unknown',
      queueing_supported: !!scheduler.queueing_supported,
      oldest_waiter_started_at_ms: Math.max(0, Math.floor(Number(scheduler.oldest_waiter_started_at_ms || 0) || 0)),
      oldest_waiter_age_ms: Math.max(0, Math.floor(Number(scheduler.oldest_waiter_age_ms || 0) || 0)),
      contention_count: Math.max(0, Math.floor(Number(scheduler.contention_count || 0) || 0)),
      last_contention_at_ms: Math.max(0, Math.floor(Number(scheduler.last_contention_at_ms || 0) || 0)),
      active_memory_bytes: activeMemoryBytes,
      peak_memory_bytes: peakMemoryBytes,
      memory_state: activeMemoryBytes > 0 || peakMemoryBytes > 0 ? 'reported' : 'unknown',
      idle_eviction_policy: String(provider?.idle_eviction?.policy || '').trim() || 'unknown',
      last_idle_eviction_reason: String(provider?.idle_eviction?.last_eviction_reason || '').trim(),
      updated_at_ms: Math.max(0, Math.floor(Number(provider?.updated_at_ms || 0) || 0)),
    });
  }
  rows.sort((left, right) => String(left.provider || '').trim().localeCompare(String(right.provider || '').trim()));
  return rows;
}

function buildMonitorSnapshot({ providers = {}, loadedInstances = [], recentBenchResults = [], updatedAtMs = 0 } = {}) {
  return {
    schema_version: 'xhub.local_runtime_monitor.v1',
    updated_at_ms: Math.max(0, Math.floor(Number(updatedAtMs || 0) || 0)),
    providers: buildMonitorProviders(providers),
    active_tasks: buildMonitorActiveTasks(providers),
    loaded_instances: Array.isArray(loadedInstances) ? loadedInstances : [],
    recent_bench_results: recentBenchResults.map((row) => normalizeBenchResult(row)).filter((row) => !!row),
    queue: buildMonitorQueue(providers, updatedAtMs),
    last_errors: buildMonitorLastErrors(providers),
    fallback_counters: buildMonitorFallbackCounters(providers),
  };
}

function normalizeBenchResult(raw) {
  const row = normalizeObject(raw);
  const routeTrace = normalizeRouteTrace(row.routeTrace || row.route_trace);
  const routeTraceSummary = normalizeRouteTraceSummary(
    row.routeTraceSummary || row.route_trace_summary,
    routeTrace
  );
  const loadConfigHash = String(
    row.loadConfigHash || row.load_config_hash || row.loadProfileHash || row.load_profile_hash || ''
  ).trim();
  const currentContextLength = Math.max(
    0,
    Math.floor(Number(
      row.currentContextLength
      || row.current_context_length
      || row.effectiveContextLength
      || row.effective_context_length
      || 0
    ) || 0)
  );
  const loadConfig = normalizeLoadConfig(
    row.loadConfig
    || row.load_config
    || row.effectiveLoadProfile
    || row.effective_load_profile,
    { fallbackContextLength: currentContextLength }
  );
  return {
    ok: !!row.ok,
    provider: normalizeProviderId(row.provider || row.providerId || row.provider_id),
    task_kind: String(row.taskKind || row.task_kind || '').trim().toLowerCase(),
    model_id: String(row.modelId || row.model_id || '').trim(),
    fixture_profile: String(row.fixtureProfile || row.fixture_profile || '').trim(),
    fixture_title: String(row.fixtureTitle || row.fixture_title || '').trim(),
    result_kind: String(row.resultKind || row.result_kind || '').trim(),
    reason_code: String(row.reasonCode || row.reason_code || row.error || '').trim(),
    runtime_source: String(row.runtimeSource || row.runtime_source || '').trim().toLowerCase(),
    runtime_source_path: String(row.runtimeSourcePath || row.runtime_source_path || '').trim(),
    runtime_resolution_state: String(row.runtimeResolutionState || row.runtime_resolution_state || '').trim().toLowerCase(),
    runtime_reason_code: String(row.runtimeReasonCode || row.runtime_reason_code || '').trim(),
    fallback_used: Boolean(row.fallbackUsed ?? row.fallback_used),
    runtime_hint: String(row.runtimeHint || row.runtime_hint || '').trim(),
    runtime_missing_requirements: safeStringList(
      row.runtimeMissingRequirements || row.runtime_missing_requirements
    ),
    runtime_missing_optional_requirements: safeStringList(
      row.runtimeMissingOptionalRequirements || row.runtime_missing_optional_requirements
    ),
    verdict: String(row.verdict || '').trim(),
    fallback_mode: String(row.fallbackMode || row.fallback_mode || '').trim(),
    cold_start_ms: Math.max(0, Math.floor(Number(row.coldStartMs || row.cold_start_ms || 0) || 0)),
    latency_ms: Math.max(0, Math.floor(Number(row.latencyMs || row.latency_ms || 0) || 0)),
    peak_memory_bytes: Math.max(0, Math.floor(Number(row.peakMemoryBytes || row.peak_memory_bytes || 0) || 0)),
    throughput_value: Number(row.throughputValue || row.throughput_value || 0) || 0,
    throughput_unit: String(row.throughputUnit || row.throughput_unit || '').trim(),
    load_profile_hash: loadConfigHash,
    load_config_hash: loadConfigHash,
    effective_context_length: currentContextLength,
    current_context_length: currentContextLength,
    load_config: loadConfig,
    prompt_tokens: Math.max(0, Math.floor(Number(row.promptTokens || row.prompt_tokens || 0) || 0)),
    generation_tokens: Math.max(0, Math.floor(Number(row.generationTokens || row.generation_tokens || 0) || 0)),
    prompt_tps: Number(row.promptTPS || row.prompt_tps || 0) || 0,
    generation_tps: Number(row.generationTPS || row.generation_tps || 0) || 0,
    runtime_version: String(row.runtimeVersion || row.runtime_version || '').trim(),
    local_runtime_entry_version: String(row.localRuntimeEntryVersion || row.local_runtime_entry_version || '').trim(),
    updated_at_ms: parseUpdatedAtMs(row, 0),
    notes: safeStringList(row.notes),
    route_trace: routeTrace,
    route_trace_summary: routeTraceSummary,
    raw: row,
  };
}

function defaultLocalRuntimeCommandExecutor({
  runtimeBaseDir,
  command,
  request,
  timeoutMs = 30_000,
} = {}) {
  const baseDir = String(runtimeBaseDir || '').trim();
  const runtimeCommand = String(command || '').trim();
  const payload = JSON.stringify(request || {});
  const spawnConfig = buildLocalRuntimeSpawnConfig({ runtimeBaseDir: baseDir });
  if (!spawnConfig.executable) {
    return Promise.reject(new Error(spawnConfig.error || 'local_runtime_python_unavailable'));
  }
  return new Promise((resolve, reject) => {
    const child = spawn(
      spawnConfig.executable,
      [LOCAL_RUNTIME_SCRIPT, runtimeCommand, '-'],
      {
        env: spawnConfig.env,
        stdio: ['pipe', 'pipe', 'pipe'],
      }
    );

    let stdout = '';
    let stderr = '';
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
      reject(new Error(`local_runtime_${runtimeCommand || 'command'}_timeout`));
    }, Math.max(1000, Number(timeoutMs || 30_000)));

    child.stdout.on('data', (chunk) => {
      stdout += String(chunk || '');
    });
    child.stderr.on('data', (chunk) => {
      stderr += String(chunk || '');
    });
    child.on('error', (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    child.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (code !== 0) {
        reject(new Error(String(stderr || '').trim() || `local_runtime_${runtimeCommand || 'command'}_exit_${code}`));
        return;
      }
      try {
        resolve(JSON.parse(String(stdout || '{}')));
      } catch {
        reject(new Error(String(stdout || '').trim() || String(stderr || '').trim() || `local_runtime_${runtimeCommand || 'command'}_invalid_json`));
      }
    });

    try {
      child.stdin.write(payload, 'utf8');
      child.stdin.end();
    } catch (error) {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    }
  });
}

export function readRuntimeStatusSnapshot(baseDir, maxAgeMs = 10_000) {
  const p = runtimePaths(baseDir);
  let stat = null;
  try {
    stat = fs.statSync(p.runtimeStatusPath);
  } catch {
    stat = null;
  }
  const raw = readJsonSafe(p.runtimeStatusPath);
  if (!raw || typeof raw !== 'object') {
    return {
      ok: false,
      pid: 0,
      schema_version: '',
      runtime_version: '',
      updated_at_ms: 0,
      age_ms: Number.POSITIVE_INFINITY,
      is_alive: false,
      provider_ids: [],
      ready_provider_ids: [],
      active_tasks: [],
      loaded_instances: [],
      loaded_instance_count: 0,
      recent_bench_results: [],
      queue: {
        provider_count: 0,
        active_task_count: 0,
        queued_task_count: 0,
        providers_busy_count: 0,
        providers_with_queued_tasks_count: 0,
        max_oldest_wait_ms: 0,
        contention_count: 0,
        last_contention_at_ms: 0,
        updated_at_ms: 0,
        providers: [],
      },
      last_errors: [],
      fallback_counters: {
        provider_count: 0,
        fallback_ready_provider_count: 0,
        fallback_only_provider_count: 0,
        fallback_ready_task_count: 0,
        fallback_only_task_count: 0,
        task_kind_counts: {},
      },
      monitor_snapshot: {
        schema_version: 'xhub.local_runtime_monitor.v1',
        updated_at_ms: 0,
        providers: [],
        active_tasks: [],
        loaded_instances: [],
        recent_bench_results: [],
        queue: {
          provider_count: 0,
          active_task_count: 0,
          queued_task_count: 0,
          providers_busy_count: 0,
          providers_with_queued_tasks_count: 0,
          max_oldest_wait_ms: 0,
          contention_count: 0,
          last_contention_at_ms: 0,
          updated_at_ms: 0,
          providers: [],
        },
        last_errors: [],
        fallback_counters: {
          provider_count: 0,
          fallback_ready_provider_count: 0,
          fallback_only_provider_count: 0,
          fallback_ready_task_count: 0,
          fallback_only_task_count: 0,
          task_kind_counts: {},
        },
      },
      idle_eviction_by_provider: {},
      provider_packs: [],
      providers: {},
      mlx_ok: false,
    };
  }

  const updatedAtMs = parseUpdatedAtMs(raw, stat?.mtimeMs || 0);
  const ageMs = updatedAtMs > 0 ? Math.max(0, Date.now() - updatedAtMs) : Number.POSITIVE_INFINITY;
  const runtimeVersion = String(raw.runtimeVersion || raw.runtime_version || '').trim();
  const rawMonitorSnapshot = normalizeObject(raw.monitorSnapshot || raw.monitor_snapshot);
  const providers = {};
  const rawProviders = raw.providers && typeof raw.providers === 'object' ? raw.providers : {};
  for (const [providerId, status] of Object.entries(rawProviders)) {
    providers[normalizeProviderId(providerId)] = normalizeProviderStatus(providerId, status, updatedAtMs, runtimeVersion);
  }
  if (!providers.mlx) {
    providers.mlx = normalizeProviderStatus(
      'mlx',
      {
        provider: 'mlx',
        ok: !!raw.mlxOk,
        reasonCode: raw.mlxOk ? 'legacy_ready' : 'legacy_unavailable',
        runtimeVersion,
        importError: raw.importError || '',
        lifecycleMode: 'mlx_legacy',
        supportedLifecycleActions: [],
        warmupTaskKinds: [],
        residencyScope: 'legacy_runtime',
        updatedAt: Number(raw.updatedAt || raw.updated_at || 0),
      },
      updatedAtMs,
      runtimeVersion
    );
  }

  const providerIds = Object.keys(providers).sort();
  let providerPacks = Array.isArray(raw.providerPacks || raw.provider_packs)
    ? (raw.providerPacks || raw.provider_packs).map((entry) => normalizeProviderPack(entry)).filter((row) => row.provider_id)
    : [];
  if (providerPacks.length === 0 || providerPacks.length < providerIds.length) {
    const providerPackMap = new Map(providerPacks.map((pack) => [pack.provider_id, pack]));
    for (const providerId of providerIds) {
      if (providerPackMap.has(providerId)) continue;
      const derivedPack = deriveProviderPackFromRawStatus(providerId, rawProviders[providerId]);
      providerPackMap.set(providerId, derivedPack || synthesizeProviderPack(providerId));
    }
    providerPacks = Array.from(providerPackMap.values());
  }
  providerPacks.sort((left, right) => String(left.provider_id || '').localeCompare(String(right.provider_id || '')));
  const providerPackMap = Object.fromEntries(providerPacks.map((pack) => [pack.provider_id, pack]));
  for (const providerId of providerIds) {
    const provider = providers[providerId];
    const pack = providerPackMap[providerId];
    if (!provider || !pack) continue;
    if (!provider.pack_id) provider.pack_id = pack.provider_id;
    if (!provider.pack_engine) provider.pack_engine = pack.engine;
    if (!provider.pack_version) provider.pack_version = pack.version;
    if (!provider.pack_state) provider.pack_state = pack.pack_state;
    if (!provider.pack_reason_code) provider.pack_reason_code = pack.reason_code;
    if (provider.pack_installed !== true) provider.pack_installed = pack.installed;
    if (provider.pack_enabled !== true) provider.pack_enabled = pack.enabled;
  }
  const readyProviderIds = providerIds.filter((providerId) => providers[providerId]?.ok);
  const topLevelLoadedInstances = normalizeLoadedInstances(raw.loadedInstances || raw.loaded_instances);
  const loadedInstances = topLevelLoadedInstances.length > 0
    ? topLevelLoadedInstances
    : providerIds.flatMap((providerId) => {
      const rows = Array.isArray(providers[providerId]?.loaded_instances) ? providers[providerId].loaded_instances : [];
      return rows.map((row) => ({ ...row, provider: row.provider || providerId }));
    });
  loadedInstances.sort((left, right) => {
    const lp = String(left.provider || '').trim();
    const rp = String(right.provider || '').trim();
    if (lp !== rp) return lp.localeCompare(rp);
    const lm = String(left.model_id || '').trim();
    const rm = String(right.model_id || '').trim();
    if (lm !== rm) return lm.localeCompare(rm);
    return String(left.instance_key || '').trim().localeCompare(String(right.instance_key || '').trim());
  });
  const rawIdleEvictionByProvider = normalizeObject(raw.idleEvictionByProvider || raw.idle_eviction_by_provider);
  const idleEvictionByProvider = {};
  for (const providerId of providerIds) {
    idleEvictionByProvider[providerId] = normalizeIdleEviction(
      rawIdleEvictionByProvider[providerId] || providers[providerId]?.idle_eviction
    );
  }
  const recentBenchResults = Array.isArray(raw.recentBenchResults || raw.recent_bench_results)
    ? (raw.recentBenchResults || raw.recent_bench_results)
    : (Array.isArray(rawMonitorSnapshot.recentBenchResults || rawMonitorSnapshot.recent_bench_results)
      ? (rawMonitorSnapshot.recentBenchResults || rawMonitorSnapshot.recent_bench_results)
      : []);
  const monitorSnapshot = buildMonitorSnapshot({
    providers,
    loadedInstances,
    recentBenchResults,
    updatedAtMs,
  });
  return {
    ok: true,
    pid: Number(raw.pid || 0),
    schema_version: String(raw.schema_version || raw.schemaVersion || '').trim(),
    runtime_version: runtimeVersion,
    updated_at_ms: updatedAtMs,
    age_ms: ageMs,
    is_alive: ageMs <= Math.max(1000, Number(maxAgeMs || 0)),
    provider_ids: providerIds,
    ready_provider_ids: readyProviderIds,
    active_tasks: monitorSnapshot.active_tasks,
    loaded_instances: loadedInstances,
    loaded_instance_count: Math.max(loadedInstances.length, Math.floor(Number(raw.loadedInstanceCount || raw.loaded_instance_count || 0) || 0)),
    recent_bench_results: monitorSnapshot.recent_bench_results,
    queue: monitorSnapshot.queue,
    last_errors: monitorSnapshot.last_errors,
    fallback_counters: monitorSnapshot.fallback_counters,
    monitor_snapshot: monitorSnapshot,
    idle_eviction_by_provider: idleEvictionByProvider,
    provider_packs: providerPacks,
    providers,
    mlx_ok: !!raw.mlxOk,
  };
}

export function runtimeProviderStatus(baseDir, providerId, maxAgeMs = 10_000) {
  const snapshot = readRuntimeStatusSnapshot(baseDir, maxAgeMs);
  if (!snapshot.ok) return null;
  return snapshot.providers[normalizeProviderId(providerId)] || null;
}

export function isRuntimeProviderReady(baseDir, providerId, maxAgeMs = 10_000) {
  const snapshot = readRuntimeStatusSnapshot(baseDir, maxAgeMs);
  if (!snapshot.ok || !snapshot.is_alive) return false;
  return !!snapshot.providers[normalizeProviderId(providerId)]?.ok;
}

export async function manageLocalModelLifecycle({
  runtimeBaseDir,
  action,
  request = {},
  timeoutMs = 30_000,
  executor = null,
} = {}) {
  const lifecycleAction = String(action || request?.action || '').trim().replaceAll('-', '_').toLowerCase();
  if (!lifecycleAction) {
    throw new Error('missing_lifecycle_action');
  }
  if (!['warmup_local_model', 'unload_local_model', 'evict_local_instance'].includes(lifecycleAction)) {
    throw new Error(`unsupported_lifecycle_action:${lifecycleAction}`);
  }
  const taskExecutor = typeof executor === 'function' ? executor : defaultLocalRuntimeCommandExecutor;
  return taskExecutor({
    runtimeBaseDir,
    command: 'manage-local-model',
    request: {
      ...(request && typeof request === 'object' ? request : {}),
      action: lifecycleAction,
    },
    timeoutMs,
  });
}

export async function runLocalBench({
  runtimeBaseDir,
  request = {},
  timeoutMs = 45_000,
  executor = null,
} = {}) {
  const taskExecutor = typeof executor === 'function' ? executor : defaultLocalRuntimeCommandExecutor;
  const raw = await taskExecutor({
    runtimeBaseDir,
    command: 'run-local-bench',
    request,
    timeoutMs,
  });
  return normalizeBenchResult(raw);
}

export function readLocalTaskRoutingSettings(runtimeBaseDir) {
  return readSharedTaskRoutingSettings(runtimeBaseDir);
}

export function resolveLocalTaskRoutingBinding({
  runtimeBaseDir,
  taskKind = '',
  deviceId = '',
  modelId = '',
  preferredModelId = '',
} = {}) {
  return resolveSharedTaskRoutingBinding({
    baseDir: runtimeBaseDir,
    taskKind,
    deviceId,
    modelId,
    preferredModelId,
  });
}

function localTaskModelCompatibilityFailure(record, {
  taskKind = '',
  providerId = '',
  requireLocalPath = true,
} = {}) {
  const normalizedTaskKind = safeString(taskKind).toLowerCase();
  const normalizedProviderId = normalizeProviderId(providerId);
  const row = record && typeof record === 'object' ? record : null;
  const recordProviderId = normalizeProviderId(row?.backend);
  const recordModelId = safeString(row?.model_id);
  const recordTaskKinds = normalizeTaskKinds(row?.task_kinds, row?.backend);
  const hasLocalPath = !!safeString(row?.model_path);

  if (requireLocalPath && !hasLocalPath) {
    return {
      reason_code: 'routed_model_not_local',
      message: recordModelId
        ? `routed_model_not_local:${recordModelId}`
        : 'routed_model_not_local',
    };
  }
  if (normalizedProviderId && recordProviderId !== normalizedProviderId) {
    return {
      reason_code: 'routed_model_provider_mismatch',
      message: recordModelId
        ? `routed_model_provider_mismatch:${recordModelId}:${recordProviderId || 'unknown'}`
        : `routed_model_provider_mismatch:${recordProviderId || 'unknown'}`,
    };
  }
  if (normalizedTaskKind && !recordTaskKinds.includes(normalizedTaskKind)) {
    return {
      reason_code: 'routed_model_task_mismatch',
      message: recordModelId
        ? `routed_model_task_mismatch:${recordModelId}:${normalizedTaskKind}`
        : `routed_model_task_mismatch:${normalizedTaskKind}`,
    };
  }
  return {
    reason_code: '',
    message: '',
  };
}

export function resolveLocalTaskModelRecord({
  runtimeBaseDir,
  taskKind = '',
  deviceId = '',
  modelId = '',
  preferredModelId = '',
  providerId = '',
  requireLocalPath = true,
} = {}) {
  const normalizedTaskKind = safeString(taskKind).toLowerCase();
  const normalizedDeviceId = safeString(deviceId).toLowerCase();
  const normalizedProviderId = normalizeProviderId(providerId);
  const binding = resolveLocalTaskRoutingBinding({
    runtimeBaseDir,
    taskKind: normalizedTaskKind,
    deviceId: normalizedDeviceId,
    modelId,
    preferredModelId,
  });
  const records = listRuntimeModelRecords(runtimeBaseDir);
  const compatible = (record) => {
    const failure = localTaskModelCompatibilityFailure(record, {
      taskKind: normalizedTaskKind,
      providerId: normalizedProviderId,
      requireLocalPath,
    });
    return !failure.reason_code;
  };

  if (binding.model_id) {
    const exact = records.find((record) => safeString(record?.model_id) === binding.model_id) || null;
    if (!exact) {
      return {
        ok: false,
        task_kind: normalizedTaskKind,
        device_id: normalizedDeviceId,
        route_source: safeString(binding.source) || 'auto_selected',
        resolved_model_id: safeString(binding.model_id),
        reason_code: 'routed_model_not_registered',
        message: binding.model_id
          ? `routed_model_not_registered:${binding.model_id}`
          : 'routed_model_not_registered',
      };
    }
    const compatibilityFailure = localTaskModelCompatibilityFailure(exact, {
      taskKind: normalizedTaskKind,
      providerId: normalizedProviderId,
      requireLocalPath,
    });
    if (compatibilityFailure.reason_code) {
      return {
        ok: false,
        task_kind: normalizedTaskKind,
        device_id: normalizedDeviceId,
        route_source: safeString(binding.source) || 'auto_selected',
        resolved_model_id: safeString(binding.model_id),
        reason_code: compatibilityFailure.reason_code,
        message: compatibilityFailure.message || compatibilityFailure.reason_code,
      };
    }
    return {
      ok: true,
      task_kind: normalizedTaskKind,
      device_id: normalizedDeviceId,
      route_source: safeString(binding.source) || 'auto_selected',
      resolved_model_id: safeString(exact.model_id) || safeString(binding.model_id),
      model: exact,
    };
  }

  const selected = records.find((record) => compatible(record)) || null;
  if (!selected) {
    return {
      ok: false,
      task_kind: normalizedTaskKind,
      device_id: normalizedDeviceId,
      route_source: 'auto_selected',
      resolved_model_id: '',
      reason_code: 'no_compatible_model_registered',
      message: normalizedTaskKind
        ? `no_compatible_model_registered:${normalizedTaskKind}`
        : 'no_compatible_model_registered',
    };
  }
  return {
    ok: true,
    task_kind: normalizedTaskKind,
    device_id: normalizedDeviceId,
    route_source: 'auto_selected',
    resolved_model_id: safeString(selected.model_id),
    model: selected,
  };
}

export function readRuntimeModelRecord(baseDir, modelId) {
  const p = runtimePaths(baseDir);
  const raw = readJsonSafe(p.statePath);
  const models = Array.isArray(raw?.models) ? raw.models : [];
  const needle = String(modelId || '').trim();
  if (!needle) return null;
  for (const model of models) {
    if (!model || typeof model !== 'object') continue;
    if (String(model.id || '').trim() !== needle) continue;
    return {
      model_id: needle,
      name: String(model.name || needle).trim(),
      backend: String(model.backend || '').trim(),
      runtime_provider_id: normalizeProviderId(model.runtimeProviderId || model.runtime_provider_id),
      model_path: String(model.modelPath || model.model_path || '').trim(),
      task_kinds: normalizeTaskKinds(model.taskKinds || model.task_kinds, model.backend),
      input_modalities: safeStringList(model.inputModalities || model.input_modalities),
      output_modalities: safeStringList(model.outputModalities || model.output_modalities),
      offline_ready: !!(model.offlineReady ?? model.offline_ready),
      model_format: String(model.modelFormat || model.model_format || '').trim(),
    };
  }
  return null;
}

export function listRuntimeModelRecords(baseDir) {
  const p = runtimePaths(baseDir);
  const raw = readJsonSafe(p.statePath);
  const models = Array.isArray(raw?.models) ? raw.models : [];
  const out = [];
  for (const model of models) {
    if (!model || typeof model !== 'object') continue;
    const modelId = String(model.id || '').trim();
    if (!modelId) continue;
    const defaultLoadConfig = normalizeLoadConfig(
      model.defaultLoadConfig
        || model.default_load_config
        || model.defaultLoadProfile
        || model.default_load_profile,
      { fallbackContextLength: model.contextLength || model.context_length }
    );
    const defaultContextLength = Math.max(
      0,
      Math.floor(Number(defaultLoadConfig?.context_length || 0) || 0)
    );
    const maxContextLength = normalizeModelMaxContextLength(model, defaultContextLength);
    out.push({
      model_id: modelId,
      name: String(model.name || modelId).trim(),
      backend: String(model.backend || '').trim(),
      runtime_provider_id: normalizeProviderId(model.runtimeProviderId || model.runtime_provider_id),
      model_path: String(model.modelPath || model.model_path || '').trim(),
      task_kinds: normalizeTaskKinds(model.taskKinds || model.task_kinds, model.backend),
      input_modalities: safeStringList(model.inputModalities || model.input_modalities),
      output_modalities: safeStringList(model.outputModalities || model.output_modalities),
      offline_ready: !!(model.offlineReady ?? model.offline_ready),
      model_format: String(model.modelFormat || model.model_format || '').trim(),
      default_context_length: defaultContextLength,
      max_context_length: maxContextLength,
      default_load_profile: defaultLoadConfig,
      default_load_config: defaultLoadConfig,
    });
  }
  return out;
}

export function localProviderForModel(baseDir, modelId) {
  if (baseDir && typeof baseDir === 'object' && !Array.isArray(baseDir) && modelId == null) {
    const model = baseDir;
    const runtimeProviderId = normalizeProviderId(model.runtimeProviderId || model.runtime_provider_id);
    if (runtimeProviderId) return runtimeProviderId;
    return normalizeProviderId(model.backend);
  }
  const record = readRuntimeModelRecord(baseDir, modelId);
  if (!record) return '';
  if (normalizeProviderId(record.runtime_provider_id)) {
    return normalizeProviderId(record.runtime_provider_id);
  }
  if (!record.model_path && normalizeProviderId(record.backend) !== 'mlx') {
    return '';
  }
  return normalizeProviderId(record.backend);
}

export function runtimeModelTaskKinds(baseDir, modelId) {
  return readRuntimeModelRecord(baseDir, modelId)?.task_kinds || [];
}

export function runtimeModelSupportsTask(baseDir, modelId, taskKind) {
  const task = String(taskKind || '').trim().toLowerCase();
  if (!task) return false;
  const record = readRuntimeModelRecord(baseDir, modelId);
  if (!record) return false;
  return normalizeTaskKinds(record.task_kinds, record.backend).includes(task);
}
