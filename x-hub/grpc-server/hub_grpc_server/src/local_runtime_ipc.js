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

function normalizeTaskKinds(taskKinds, backend) {
  const out = safeStringList(taskKinds).map((value) => String(value || '').trim().toLowerCase()).filter(Boolean);
  if (out.length > 0) return out;
  return normalizeProviderId(backend) === 'mlx' ? ['text_generate'] : [];
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
      return {
        lease_id: String(row.leaseId || row.lease_id || '').trim(),
        task_kind: String(row.taskKind || row.task_kind || '').trim().toLowerCase(),
        model_id: String(row.modelId || row.model_id || '').trim(),
        request_id: String(row.requestId || row.request_id || '').trim(),
        device_id: String(row.deviceId || row.device_id || '').trim(),
        load_profile_hash: String(row.loadProfileHash || row.load_profile_hash || '').trim(),
        instance_key: String(row.instanceKey || row.instance_key || '').trim(),
        effective_context_length: Math.max(0, Math.floor(Number(row.effectiveContextLength || row.effective_context_length || 0) || 0)),
        started_at_ms: parseUpdatedAtMs(row, fallbackUpdatedAtMs),
      };
    }).filter((row) => row.lease_id)
    : [];
  return {
    concurrency_limit: Math.max(1, Math.floor(Number(obj.concurrencyLimit || obj.concurrency_limit || 1) || 1)),
    active_task_count: Math.max(0, Math.floor(Number(obj.activeTaskCount || obj.active_task_count || 0) || 0)),
    queued_task_count: Math.max(0, Math.floor(Number(obj.queuedTaskCount || obj.queued_task_count || 0) || 0)),
    queue_mode: String(obj.queueMode || obj.queue_mode || '').trim(),
    queueing_supported: !!(obj.queueingSupported ?? obj.queueing_supported ?? false),
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
    return {
      provider: String(row.provider || '').trim().toLowerCase(),
      instance_key: String(row.instanceKey || row.instance_key || '').trim(),
      model_id: String(row.modelId || row.model_id || '').trim(),
      task_kinds: safeStringList(row.taskKinds || row.task_kinds).map((taskKind) => String(taskKind || '').trim().toLowerCase()).filter(Boolean),
      load_profile_hash: String(row.loadProfileHash || row.load_profile_hash || '').trim(),
      effective_context_length: Math.max(0, Math.floor(Number(row.effectiveContextLength || row.effective_context_length || 0) || 0)),
      loaded_at_ms: parseUpdatedAtMs({ updatedAt: row.loadedAt || row.loaded_at || row.loadedAtMs || row.loaded_at_ms }, 0),
      last_used_at_ms: parseUpdatedAtMs({ updatedAt: row.lastUsedAt || row.last_used_at || row.lastUsedAtMs || row.last_used_at_ms }, 0),
      residency: String(row.residency || '').trim(),
      residency_scope: String(row.residencyScope || row.residency_scope || '').trim(),
      device_backend: String(row.deviceBackend || row.device_backend || '').trim(),
    };
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

function normalizeProviderStatus(rawProviderId, rawStatus, fallbackUpdatedAtMs, fallbackRuntimeVersion) {
  const providerId = normalizeProviderId(rawStatus?.provider || rawProviderId);
  const updatedAtMs = parseUpdatedAtMs(rawStatus, fallbackUpdatedAtMs);
  return {
    provider: providerId || normalizeProviderId(rawProviderId),
    ok: !!rawStatus?.ok,
    reason_code: String(rawStatus?.reasonCode || rawStatus?.reason_code || '').trim(),
    runtime_version: String(rawStatus?.runtimeVersion || rawStatus?.runtime_version || fallbackRuntimeVersion || '').trim(),
    available_task_kinds: safeStringList(rawStatus?.availableTaskKinds || rawStatus?.available_task_kinds),
    loaded_models: safeStringList(rawStatus?.loadedModels || rawStatus?.loaded_models),
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
    loaded_instances: normalizeLoadedInstances(rawStatus?.loadedInstances || rawStatus?.loaded_instances),
    idle_eviction: normalizeIdleEviction(rawStatus?.idleEviction || rawStatus?.idle_eviction),
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
  return new Promise((resolve, reject) => {
    const child = spawn(
      'python3',
      [LOCAL_RUNTIME_SCRIPT, runtimeCommand, '-'],
      {
        env: {
          ...process.env,
          REL_FLOW_HUB_BASE_DIR: baseDir,
        },
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
      loaded_instances: [],
      loaded_instance_count: 0,
      idle_eviction_by_provider: {},
      providers: {},
      mlx_ok: false,
    };
  }

  const updatedAtMs = parseUpdatedAtMs(raw, stat?.mtimeMs || 0);
  const ageMs = updatedAtMs > 0 ? Math.max(0, Date.now() - updatedAtMs) : Number.POSITIVE_INFINITY;
  const runtimeVersion = String(raw.runtimeVersion || raw.runtime_version || '').trim();
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
    loaded_instances: loadedInstances,
    loaded_instance_count: Math.max(loadedInstances.length, Math.floor(Number(raw.loadedInstanceCount || raw.loaded_instance_count || 0) || 0)),
    idle_eviction_by_provider: idleEvictionByProvider,
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
    out.push({
      model_id: modelId,
      name: String(model.name || modelId).trim(),
      backend: String(model.backend || '').trim(),
      model_path: String(model.modelPath || model.model_path || '').trim(),
      task_kinds: normalizeTaskKinds(model.taskKinds || model.task_kinds, model.backend),
      input_modalities: safeStringList(model.inputModalities || model.input_modalities),
      output_modalities: safeStringList(model.outputModalities || model.output_modalities),
      offline_ready: !!(model.offlineReady ?? model.offline_ready),
      model_format: String(model.modelFormat || model.model_format || '').trim(),
    });
  }
  return out;
}

export function localProviderForModel(baseDir, modelId) {
  const record = readRuntimeModelRecord(baseDir, modelId);
  if (!record) return '';
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
