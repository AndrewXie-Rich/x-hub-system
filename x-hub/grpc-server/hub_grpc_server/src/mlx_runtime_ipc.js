import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { sleep } from './util.js';

function expandHome(p) {
  const s = String(p || '').trim();
  if (!s) return s;
  if (s === '~') return os.homedir();
  if (s.startsWith('~/')) return path.join(os.homedir(), s.slice(2));
  return s;
}

function readJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function fileMtimeMs(filePath) {
  try {
    return Number(fs.statSync(String(filePath || '')).mtimeMs || 0);
  } catch {
    return 0;
  }
}

function parseEpochMs(obj, keys) {
  if (!obj || typeof obj !== 'object') return 0;
  for (const k of keys) {
    const n = Number(obj?.[k] || 0);
    if (!n) continue;
    // Heuristic: values below year-2286 ms are probably seconds.
    if (n > 10_000_000_000) return Math.max(0, Math.floor(n));
    return Math.max(0, Math.floor(n * 1000));
  }
  return 0;
}

function freshnessPoints(epochMs, nowMs, maxAgeMs, maxPoints) {
  const ts = Number(epochMs || 0);
  if (!ts) return 0;
  const age = Math.max(0, nowMs - ts);
  if (age > Math.max(1, Number(maxAgeMs || 0))) return 0;
  const ratio = 1.0 - age / Math.max(1, Number(maxAgeMs || 1));
  return Math.max(0, Math.floor(Number(maxPoints || 0) * ratio));
}

function runtimeBaseCandidates() {
  const home = os.homedir();
  return [
    path.join(home, 'Library', 'Containers', 'com.rel.flowhub', 'Data', 'XHub'),
    path.join(home, 'Library', 'Containers', 'com.rel.flowhub', 'Data', 'RELFlowHub'),
    path.join('/private/tmp', 'XHub'),
    path.join('/private/tmp', 'RELFlowHub'),
    path.join(home, 'Library', 'Group Containers', 'group.rel.flowhub'),
    path.join(home, 'XHub'),
    path.join(home, 'RELFlowHub'),
  ];
}

function scoreRuntimeBaseDir(baseDir, nowMs) {
  const dir = String(baseDir || '').trim();
  if (!dir) return -1;

  let score = fs.existsSync(dir) ? 1 : 0;

  const hubObj = readJsonSafe(path.join(dir, 'hub_status.json'));
  const hubMs = parseEpochMs(hubObj, ['updatedAt', 'updated_at']);
  score += freshnessPoints(hubMs, nowMs, 15_000, 200_000);

  const statePath = path.join(dir, 'models_state.json');
  const stateObj = readJsonSafe(statePath);
  let stateMs = parseEpochMs(stateObj, ['updatedAt', 'updated_at']);
  if (!stateMs) stateMs = fileMtimeMs(statePath);
  score += freshnessPoints(stateMs, nowMs, 6 * 60 * 60 * 1000, 80_000);
  if (stateObj && Array.isArray(stateObj.models) && stateObj.models.length > 0) {
    score += 500;
  }

  const rtObj = readJsonSafe(path.join(dir, 'ai_runtime_status.json'));
  const rtMs = parseEpochMs(rtObj, ['updatedAt', 'updated_at']);
  score += freshnessPoints(rtMs, nowMs, 20_000, 60_000);

  const bridgeObj = readJsonSafe(path.join(dir, 'bridge_status.json'));
  const bridgeMs = parseEpochMs(bridgeObj, ['updatedAt', 'updated_at']);
  score += freshnessPoints(bridgeMs, nowMs, 20_000, 30_000);

  const remoteMs = fileMtimeMs(path.join(dir, 'remote_models.json'));
  score += freshnessPoints(remoteMs, nowMs, 24 * 60 * 60 * 1000, 8_000);

  return score;
}

export function resolveRuntimeBaseDir() {
  const env = (process.env.HUB_RUNTIME_BASE_DIR || process.env.REL_FLOW_HUB_BASE_DIR || '').trim();
  if (env) return expandHome(env);

  const nowMs = Date.now();
  let bestDir = '';
  let bestScore = -1;
  const seen = new Set();

  for (const cand of runtimeBaseCandidates()) {
    const c = expandHome(cand);
    if (!c || seen.has(c)) continue;
    seen.add(c);
    const s = scoreRuntimeBaseDir(c, nowMs);
    if (s > bestScore) {
      bestScore = s;
      bestDir = c;
    }
  }

  if (bestDir) return bestDir;
  return path.join(os.homedir(), 'Library', 'Group Containers', 'group.rel.flowhub');
}

export function runtimePaths(baseDir) {
  const base = String(baseDir || '').trim();
  return {
    base,
    reqDir: path.join(base, 'ai_requests'),
    respDir: path.join(base, 'ai_responses'),
    cancelDir: path.join(base, 'ai_cancels'),
    statePath: path.join(base, 'models_state.json'),
    runtimeStatusPath: path.join(base, 'ai_runtime_status.json'),
    routingSettingsPath: path.join(base, 'routing_settings.json'),
  };
}

export function ensureRuntimeDirs(baseDir) {
  const p = runtimePaths(baseDir);
  fs.mkdirSync(p.reqDir, { recursive: true });
  fs.mkdirSync(p.respDir, { recursive: true });
  fs.mkdirSync(p.cancelDir, { recursive: true });
}

function writeJsonAtomic(filePath, obj) {
  const out = String(filePath || '').trim();
  const dir = path.dirname(out);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${out}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  fs.writeFileSync(tmp, JSON.stringify(obj), { encoding: 'utf8' });
  fs.renameSync(tmp, out);
}

function parseUpdatedAtMs(obj, fallbackMs) {
  const raw = obj?.updatedAt ?? obj?.updated_at ?? obj?.updatedAtMs ?? obj?.updated_at_ms ?? 0;
  const n = Number(raw || 0);
  if (n > 10_000_000_000) return Math.max(0, Math.floor(n)); // already ms
  if (n > 0) return Math.max(0, Math.floor(n * 1000.0)); // seconds -> ms
  return Math.max(0, Number(fallbackMs || 0));
}

function safeString(value) {
  return String(value ?? '').trim();
}

function safeStringList(values) {
  if (values == null) return [];
  const items = Array.isArray(values) ? values : String(values || '').split(',');
  const out = [];
  const seen = new Set();
  for (const raw of items) {
    const cleaned = safeString(raw);
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

function normalizeRuntimeModelTaskKinds(taskKinds, backend) {
  const out = safeStringList(taskKinds).map((value) => value.toLowerCase()).filter(Boolean);
  if (out.length > 0) return out;
  return safeString(backend).toLowerCase() === 'mlx' ? ['text_generate'] : [];
}

function runtimeModelId(model) {
  return safeString(model?.id || model?.model_id);
}

function normalizeRuntimeModelMeta(model, {
  modelId = '',
  updatedAtMs = 0,
} = {}) {
  const row = model && typeof model === 'object' ? model : null;
  const canonicalModelId = runtimeModelId(row) || safeString(modelId);
  if (!row || !canonicalModelId) return null;
  const backend = safeString(row.backend);
  const modelPath = safeString(row.modelPath || row.model_path);
  const taskKinds = normalizeRuntimeModelTaskKinds(row.taskKinds || row.task_kinds, backend);
  const isRemote = !!backend && backend.toLowerCase() !== 'mlx' && !modelPath;
  const normalized = {
    model_id: canonicalModelId,
    name: safeString(row.name) || canonicalModelId,
    kind: isRemote ? 'paid_online' : 'local_offline',
    backend,
    context_length: Number(row.contextLength || row.context_length || 0),
    requires_grant: isRemote ? 1 : 0,
    enabled: row.enabled == null ? 1 : Number(row.enabled ? 1 : 0),
    model_path: modelPath,
    task_kinds: taskKinds,
    runtime_provider_id: safeString(
      row.runtimeProviderId
      || row.runtimeProviderID
      || row.runtime_provider_id
      || row.provider
    ),
    input_modalities: safeStringList(row.inputModalities || row.input_modalities),
    output_modalities: safeStringList(row.outputModalities || row.output_modalities),
    offline_ready: !!(row.offlineReady ?? row.offline_ready),
    model_format: safeString(row.modelFormat || row.model_format),
  };
  if (updatedAtMs) normalized.updated_at_ms = updatedAtMs;
  return normalized;
}

function normalizeTaskRoutingMap(value) {
  const obj = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  const out = {};
  for (const [taskKind, modelId] of Object.entries(obj)) {
    const normalizedTaskKind = safeString(taskKind).toLowerCase();
    const normalizedModelId = safeString(modelId);
    if (!normalizedTaskKind || !normalizedModelId) continue;
    out[normalizedTaskKind] = normalizedModelId;
  }
  return out;
}

function normalizeDeviceTaskRoutingMap(value) {
  const obj = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  const out = {};
  for (const [deviceId, rawTaskMap] of Object.entries(obj)) {
    const normalizedDeviceId = safeString(deviceId).toLowerCase();
    if (!normalizedDeviceId) continue;
    const taskMap = normalizeTaskRoutingMap(rawTaskMap);
    if (Object.keys(taskMap).length === 0) continue;
    out[normalizedDeviceId] = taskMap;
  }
  return out;
}

function normalizeTaskRoutingSettings(value) {
  const obj = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  let hubDefaultModelIdByTaskKind = normalizeTaskRoutingMap(
    obj.hubDefaultModelIdByTaskKind
    || obj.hub_default_model_id_by_task_kind
    || obj.preferredModelIdByTaskKind
    || obj.preferred_model_id_by_task_kind
    || obj.preferredModelIdByTask
    || obj.preferred_model_id_by_task
  );
  if (Object.keys(hubDefaultModelIdByTaskKind).length === 0) {
    const rawMap = { ...obj };
    delete rawMap.type;
    delete rawMap.schemaVersion;
    delete rawMap.schema_version;
    delete rawMap.updatedAt;
    delete rawMap.updated_at;
    delete rawMap.updatedAtMs;
    delete rawMap.updated_at_ms;
    delete rawMap.hubDefaultModelIdByTaskKind;
    delete rawMap.hub_default_model_id_by_task_kind;
    delete rawMap.preferredModelIdByTaskKind;
    delete rawMap.preferred_model_id_by_task_kind;
    delete rawMap.preferredModelIdByTask;
    delete rawMap.preferred_model_id_by_task;
    delete rawMap.devicePreferredModelIdByTaskKind;
    delete rawMap.device_preferred_model_id_by_task_kind;
    delete rawMap.deviceOverrideModelIdByTaskKind;
    delete rawMap.device_override_model_id_by_task_kind;
    hubDefaultModelIdByTaskKind = normalizeTaskRoutingMap(rawMap);
  }
  const devicePreferredModelIdByTaskKind = normalizeDeviceTaskRoutingMap(
    obj.devicePreferredModelIdByTaskKind
    || obj.device_preferred_model_id_by_task_kind
    || obj.deviceOverrideModelIdByTaskKind
    || obj.device_override_model_id_by_task_kind
  );
  return {
    type: safeString(obj.type) || 'routing_settings',
    schema_version: safeString(obj.schemaVersion || obj.schema_version) || 'xhub.routing_settings.v2',
    updated_at_ms: parseUpdatedAtMs(obj, 0),
    hub_default_model_id_by_task_kind: hubDefaultModelIdByTaskKind,
    device_preferred_model_id_by_task_kind: devicePreferredModelIdByTaskKind,
  };
}

export function readTaskRoutingSettings(baseDir) {
  const p = runtimePaths(baseDir);
  const raw = readJsonSafe(p.routingSettingsPath);
  if (!raw || typeof raw !== 'object') {
    return normalizeTaskRoutingSettings({});
  }
  return normalizeTaskRoutingSettings(raw);
}

export function resolveTaskRoutingBinding({
  baseDir,
  taskKind = '',
  deviceId = '',
  modelId = '',
  preferredModelId = '',
} = {}) {
  const explicitModelId = safeString(modelId || preferredModelId);
  const normalizedTaskKind = safeString(taskKind).toLowerCase();
  const normalizedDeviceId = safeString(deviceId).toLowerCase();
  if (explicitModelId) {
    return {
      model_id: explicitModelId,
      task_kind: normalizedTaskKind,
      device_id: normalizedDeviceId,
      source: 'request_override',
    };
  }
  const settings = readTaskRoutingSettings(baseDir);
  if (!normalizedTaskKind) {
    return {
      model_id: '',
      task_kind: '',
      device_id: normalizedDeviceId,
      source: 'auto_selected',
      settings,
    };
  }
  const deviceTaskMap = settings.device_preferred_model_id_by_task_kind[normalizedDeviceId] || {};
  const deviceModelId = safeString(deviceTaskMap[normalizedTaskKind]);
  if (deviceModelId) {
    return {
      model_id: deviceModelId,
      task_kind: normalizedTaskKind,
      device_id: normalizedDeviceId,
      source: 'device_override',
      settings,
    };
  }
  const hubDefaultModelId = safeString(settings.hub_default_model_id_by_task_kind[normalizedTaskKind]);
  if (hubDefaultModelId) {
    return {
      model_id: hubDefaultModelId,
      task_kind: normalizedTaskKind,
      device_id: normalizedDeviceId,
      source: 'hub_default',
      settings,
    };
  }
  return {
    model_id: '',
    task_kind: normalizedTaskKind,
    device_id: normalizedDeviceId,
    source: 'auto_selected',
    settings,
  };
}

export function runtimeModelMeta(baseDir, modelId) {
  const p = runtimePaths(baseDir);
  if (!modelId) return null;
  try {
    const raw = fs.readFileSync(p.statePath, 'utf8');
    const obj = JSON.parse(raw);
    const ms = Array.isArray(obj?.models) ? obj.models : [];
    const requested = safeString(modelId);
    const m = ms.find((x) => x && typeof x === 'object' && runtimeModelId(x) === requested);
    return normalizeRuntimeModelMeta(m, { modelId });
  } catch {
    return null;
  }
}

export function runtimeModelsSnapshot(baseDir) {
  const p = runtimePaths(baseDir);
  try {
    const raw = fs.readFileSync(p.statePath, 'utf8');
    const obj = JSON.parse(raw);
    const ms = Array.isArray(obj?.models) ? obj.models : [];
    let st;
    try {
      st = fs.statSync(p.statePath);
    } catch {
      st = null;
    }
    const updated_at_ms = parseUpdatedAtMs(obj, st?.mtimeMs || Date.now());

    const models = ms
      .map((m) => {
        if (!m || typeof m !== 'object') return null;
        return normalizeRuntimeModelMeta(m, { updatedAtMs: updated_at_ms });
      })
      .filter(Boolean);

    return { ok: true, updated_at_ms, models };
  } catch {
    return { ok: false, updated_at_ms: 0, models: [] };
  }
}

export function isRuntimeAlive(baseDir, maxAgeMs = 10_000) {
  const p = runtimePaths(baseDir);
  try {
    const raw = fs.readFileSync(p.runtimeStatusPath, 'utf8');
    const obj = JSON.parse(raw);
    const updatedAtSec = Number(obj?.updatedAt || 0);
    if (!updatedAtSec) return false;
    const ageMs = Date.now() - Math.floor(updatedAtSec * 1000);
    return ageMs >= 0 && ageMs <= Math.max(1000, Number(maxAgeMs || 0));
  } catch {
    return false;
  }
}

export function writeGenerateRequest(baseDir, req) {
  ensureRuntimeDirs(baseDir);
  const requestId = String(req?.request_id || '').trim();
  if (!requestId) throw new Error('missing request_id');
  if (requestId.includes('/') || requestId.includes('\\') || requestId.includes('\0')) {
    throw new Error('unsafe request_id for filesystem IPC');
  }

  const p = runtimePaths(baseDir);
  const filePath = path.join(p.reqDir, `req_${requestId}.json`);
  const createdAtSec = Number(req?.created_at_ms || Date.now()) / 1000.0;
  const obj = {
    type: 'generate',
    req_id: requestId,
    app_id: String(req?.app_id || 'unknown'),
    model_id: String(req?.model_id || ''),
    task_type: String(req?.task_type || ''),
    preferred_model_id: String(req?.preferred_model_id || ''),
    device_id: String(req?.device_id || ''),
    prompt: String(req?.prompt || ''),
    max_tokens: Number(req?.max_tokens || 512),
    temperature: Number(req?.temperature ?? 0.2),
    top_p: Number(req?.top_p ?? 0.95),
    created_at: createdAtSec,
    auto_load: !!req?.auto_load,
  };
  writeJsonAtomic(filePath, obj);
  return { filePath, req_id: requestId };
}

export function writeCancelRequest(baseDir, req) {
  ensureRuntimeDirs(baseDir);
  const requestId = String(req?.request_id || '').trim();
  if (!requestId) throw new Error('missing request_id');
  if (requestId.includes('/') || requestId.includes('\\') || requestId.includes('\0')) {
    throw new Error('unsafe request_id for filesystem IPC');
  }
  const p = runtimePaths(baseDir);
  const filePath = path.join(p.cancelDir, `cancel_${requestId}.json`);
  writeJsonAtomic(filePath, {
    type: 'cancel',
    req_id: requestId,
    reason: String(req?.reason || ''),
    created_at: Date.now() / 1000.0,
  });
  return { filePath };
}

export function responsePathForRequest(baseDir, requestId) {
  const p = runtimePaths(baseDir);
  return path.join(p.respDir, `resp_${String(requestId || '').trim()}.jsonl`);
}

export async function* tailResponseJsonl(baseDir, requestId, opts) {
  const respPath = responsePathForRequest(baseDir, requestId);
  const pollMs = Math.max(10, Number(opts?.poll_ms || 20));
  const timeoutMs = Math.max(1000, Number(opts?.timeout_ms || 180_000));
  const deadline = Date.now() + timeoutMs;
  const shouldStop = typeof opts?.should_stop === 'function' ? opts.should_stop : () => false;

  let offset = Math.max(0, Number(opts?.start_offset || 0));
  let buf = '';

  while (Date.now() < deadline) {
    if (shouldStop()) break;

    let st;
    try {
      st = fs.statSync(respPath);
    } catch {
      await sleep(pollMs);
      continue;
    }

    const size = Number(st.size || 0);
    if (size < offset) {
      offset = 0;
      buf = '';
    }

    if (size > offset) {
      const toRead = Math.min(256 * 1024, size - offset);
      const fd = fs.openSync(respPath, 'r');
      try {
        const b = Buffer.allocUnsafe(toRead);
        const n = fs.readSync(fd, b, 0, toRead, offset);
        offset += n;
        buf += b.subarray(0, n).toString('utf8');
      } finally {
        try {
          fs.closeSync(fd);
        } catch {
          // ignore
        }
      }

      // Parse complete JSONL lines.
      while (true) {
        const idx = buf.indexOf('\n');
        if (idx < 0) break;
        const line = buf.slice(0, idx).trim();
        buf = buf.slice(idx + 1);
        if (!line) continue;
        try {
          const obj = JSON.parse(line);
          yield obj;
        } catch {
          // ignore parse errors; keep going
        }
      }

      // Tight-loop a bit if data keeps flowing.
      continue;
    }

    await sleep(pollMs);
  }

  if (Date.now() >= deadline) {
    throw new Error('runtime_response_timeout');
  }
}
