import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { resolveRuntimeBaseDir } from './local_runtime_ipc.js';
import {
  maybeAutoSyncOfficialSkillChannel,
  readOfficialSkillChannelState,
} from './official_skill_channel_sync.js';

const OFFICIAL_AGENT_SKILL_SRC_DIR = path.dirname(fileURLToPath(import.meta.url));
const OFFICIAL_AGENT_SKILL_REPO_ROOT = path.resolve(OFFICIAL_AGENT_SKILL_SRC_DIR, '../../../../');
const MAINTENANCE_STATUS_SCHEMA_VERSION = 'xhub.official_skill_channel_maintenance_status.v1';
const MAINTENANCE_EVENT_SCHEMA_VERSION = 'xhub.official_skill_channel_maintenance_event.v1';

function safeString(value) {
  return String(value == null ? '' : value).trim();
}

function positiveIntOr(value, fallback, minimum = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(minimum, Math.floor(n));
}

function readJsonSafe(filePath) {
  try {
    return JSON.parse(fs.readFileSync(String(filePath || ''), 'utf8'));
  } catch {
    return null;
  }
}

function writeJsonAtomic(filePath, obj) {
  const fp = safeString(filePath);
  if (!fp) return false;
  try {
    fs.mkdirSync(path.dirname(fp), { recursive: true });
  } catch {
    // ignore
  }
  const tmp = `${fp}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  try {
    fs.writeFileSync(tmp, `${JSON.stringify(obj, null, 2)}\n`, 'utf8');
    fs.renameSync(tmp, fp);
    return true;
  } catch {
    try {
      fs.unlinkSync(tmp);
    } catch {
      // ignore
    }
    return false;
  }
}

function appendJsonlLine(filePath, obj) {
  const fp = safeString(filePath);
  if (!fp) return false;
  try {
    fs.mkdirSync(path.dirname(fp), { recursive: true });
  } catch {
    // ignore
  }
  try {
    fs.appendFileSync(fp, `${JSON.stringify(obj)}\n`, 'utf8');
    return true;
  } catch {
    return false;
  }
}

export function resolveOfficialSkillChannelMaintenanceSourceRoot(env = process.env) {
  const sourceOverride = safeString(env?.XHUB_OFFICIAL_AGENT_SKILLS_DIR);
  if (sourceOverride) return path.resolve(sourceOverride);
  const distOverride = safeString(env?.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR);
  if (distOverride) return path.resolve(distOverride);
  return path.join(OFFICIAL_AGENT_SKILL_REPO_ROOT, 'official-agent-skills');
}

function resolveOfficialSkillChannelMaintenanceEnvSourceRoot(env = process.env) {
  const sourceOverride = safeString(env?.XHUB_OFFICIAL_AGENT_SKILLS_DIR);
  if (sourceOverride) return path.resolve(sourceOverride);
  const distOverride = safeString(env?.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR);
  if (distOverride) return path.resolve(distOverride);
  return '';
}

function normalizeSourceKind(value) {
  const kind = safeString(value).toLowerCase();
  switch (kind) {
    case 'explicit':
    case 'env':
    case 'persisted':
    case 'repo_default':
    case 'none':
      return kind;
    default:
      return kind ? 'unknown' : '';
  }
}

function officialSkillChannelMaintenanceStatusPath(runtimeBaseDir, { channelId = 'official-stable' } = {}) {
  const runtime = safeString(runtimeBaseDir);
  if (!runtime) return '';
  return path.join(runtime, 'skills_store', 'official_channels', channelId, 'maintenance_status.json');
}

function officialSkillChannelMaintenanceEventsPath(runtimeBaseDir, { channelId = 'official-stable' } = {}) {
  const runtime = safeString(runtimeBaseDir);
  if (!runtime) return '';
  return path.join(runtime, 'skills_store', 'official_channels', channelId, 'maintenance_events.jsonl');
}

export function readOfficialSkillChannelMaintenanceStatus(runtimeBaseDir, { channelId = 'official-stable' } = {}) {
  const filePath = officialSkillChannelMaintenanceStatusPath(runtimeBaseDir, { channelId });
  const stored = readJsonSafe(filePath);
  return {
    schema_version: safeString(stored?.schema_version || MAINTENANCE_STATUS_SCHEMA_VERSION) || MAINTENANCE_STATUS_SCHEMA_VERSION,
    channel_id: safeString(stored?.channel_id || channelId) || channelId,
    maintenance_enabled: !!stored?.maintenance_enabled,
    maintenance_interval_ms: Math.max(0, Number(stored?.maintenance_interval_ms || 0)),
    maintenance_retry_after_ms: Math.max(0, Number(stored?.maintenance_retry_after_ms || 0)),
    maintenance_last_run_at_ms: Math.max(0, Number(stored?.maintenance_last_run_at_ms || 0)),
    maintenance_source_kind: normalizeSourceKind(stored?.maintenance_source_kind),
    last_transition_at_ms: Math.max(0, Number(stored?.last_transition_at_ms || 0)),
    last_transition_kind: safeString(stored?.last_transition_kind),
    last_transition_summary: safeString(stored?.last_transition_summary),
    last_result_status: safeString(stored?.last_result_status),
    last_result_error_code: safeString(stored?.last_result_error_code),
  };
}

export function readOfficialSkillChannelMaintenanceEvents(
  runtimeBaseDir,
  { channelId = 'official-stable', limit = 20 } = {}
) {
  const filePath = officialSkillChannelMaintenanceEventsPath(runtimeBaseDir, { channelId });
  if (!filePath || !fs.existsSync(filePath)) return [];
  let text = '';
  try {
    text = fs.readFileSync(filePath, 'utf8');
  } catch {
    return [];
  }
  const rows = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const obj = JSON.parse(trimmed);
      if (obj && typeof obj === 'object') rows.push(obj);
    } catch {
      // ignore malformed line
    }
  }
  const maxRows = Math.max(1, Math.floor(Number(limit || 20)));
  return rows.slice(-maxRows);
}

function writeOfficialSkillChannelMaintenanceStatus(
  runtimeBaseDir,
  {
    channelId = 'official-stable',
    maintenanceEnabled = true,
    maintenanceIntervalMs = 0,
    maintenanceRetryAfterMs = 0,
    maintenanceLastRunAtMs = 0,
    maintenanceSourceKind = '',
    lastTransitionAtMs = 0,
    lastTransitionKind = '',
    lastTransitionSummary = '',
    lastResultStatus = '',
    lastResultErrorCode = '',
  } = {}
) {
  const filePath = officialSkillChannelMaintenanceStatusPath(runtimeBaseDir, { channelId });
  if (!filePath) return false;
  return writeJsonAtomic(filePath, {
    schema_version: MAINTENANCE_STATUS_SCHEMA_VERSION,
    channel_id: channelId,
    maintenance_enabled: !!maintenanceEnabled,
    maintenance_interval_ms: Math.max(0, Number(maintenanceIntervalMs || 0)),
    maintenance_retry_after_ms: Math.max(0, Number(maintenanceRetryAfterMs || 0)),
    maintenance_last_run_at_ms: Math.max(0, Number(maintenanceLastRunAtMs || 0)),
    maintenance_source_kind: normalizeSourceKind(maintenanceSourceKind),
    last_transition_at_ms: Math.max(0, Number(lastTransitionAtMs || 0)),
    last_transition_kind: safeString(lastTransitionKind),
    last_transition_summary: safeString(lastTransitionSummary),
    last_result_status: safeString(lastResultStatus),
    last_result_error_code: safeString(lastResultErrorCode),
  });
}

function eventId() {
  return `evt_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function hasCurrentSnapshot(state) {
  return !!safeString(state?.current_snapshot_dir);
}

function hasLastKnownGoodSnapshot(state) {
  return !!safeString(state?.last_known_good_snapshot_dir);
}

function summarizeTransition({ kind, previousState, nextState, previousSourceKind, nextSourceKind }) {
  switch (kind) {
    case 'status_changed':
      return `${safeString(previousState?.status) || 'unknown'} -> ${safeString(nextState?.status) || 'unknown'}`
        + (nextSourceKind ? ` via ${nextSourceKind}` : '');
    case 'current_snapshot_repaired':
      return `current snapshot restored${nextSourceKind ? ` via ${nextSourceKind}` : ''}`;
    case 'source_changed':
      return `source ${previousSourceKind || 'unknown'} -> ${nextSourceKind || 'unknown'}`;
    default:
      return '';
  }
}

function buildOfficialSkillChannelMaintenanceTransition({
  channelId = 'official-stable',
  previousState,
  nextState,
  previousMaintenance,
  nextSourceKind,
  createdAtMs = Date.now(),
} = {}) {
  const previousStatus = safeString(previousState?.status);
  const nextStatus = safeString(nextState?.status);
  const previousSourceKind = normalizeSourceKind(previousMaintenance?.maintenance_source_kind);
  let kind = '';
  if (previousStatus !== nextStatus) {
    kind = 'status_changed';
  } else if (!hasCurrentSnapshot(previousState) && hasCurrentSnapshot(nextState)) {
    kind = 'current_snapshot_repaired';
  } else if (previousSourceKind && previousSourceKind !== normalizeSourceKind(nextSourceKind)) {
    kind = 'source_changed';
  }
  if (!kind) return null;
  const summary = summarizeTransition({
    kind,
    previousState,
    nextState,
    previousSourceKind,
    nextSourceKind: normalizeSourceKind(nextSourceKind),
  });
  return {
    schema_version: MAINTENANCE_EVENT_SCHEMA_VERSION,
    event_id: eventId(),
    created_at_ms: Math.max(0, Number(createdAtMs || Date.now())),
    channel_id: channelId,
    transition_kind: kind,
    summary,
    previous_status: previousStatus,
    next_status: nextStatus,
    previous_error_code: safeString(previousState?.error_code),
    next_error_code: safeString(nextState?.error_code),
    previous_source_kind: previousSourceKind,
    next_source_kind: normalizeSourceKind(nextSourceKind),
    current_snapshot_present: hasCurrentSnapshot(nextState),
    last_known_good_snapshot_present: hasLastKnownGoodSnapshot(nextState),
    skill_count: Math.max(0, Number(nextState?.skill_count || 0)),
  };
}

function appendOfficialSkillChannelMaintenanceTransition(runtimeBaseDir, transition) {
  const filePath = officialSkillChannelMaintenanceEventsPath(runtimeBaseDir, { channelId: transition?.channel_id || 'official-stable' });
  if (!filePath || !transition) return false;
  return appendJsonlLine(filePath, transition);
}

function resolveOfficialSkillChannelMaintenanceSelection({
  runtimeBaseDir,
  channelId = 'official-stable',
  sourceRoot,
  env = process.env,
} = {}) {
  const explicitSource = safeString(sourceRoot);
  if (explicitSource) {
    return { source_root: path.resolve(explicitSource), source_kind: 'explicit' };
  }
  const envSource = resolveOfficialSkillChannelMaintenanceEnvSourceRoot(env);
  if (envSource) {
    return { source_root: envSource, source_kind: 'env' };
  }
  const persistedState = readOfficialSkillChannelState(runtimeBaseDir, { channelId });
  const persistedSource = safeString(persistedState?.source_root);
  if (persistedSource) {
    return { source_root: persistedSource, source_kind: 'persisted' };
  }
  const repoDefaultSource = resolveOfficialSkillChannelMaintenanceSourceRoot(env);
  if (repoDefaultSource) {
    return { source_root: repoDefaultSource, source_kind: 'repo_default' };
  }
  return { source_root: '', source_kind: 'none' };
}

export function officialSkillChannelMaintenanceIntervalMs(env = process.env) {
  return positiveIntOr(
    env?.XHUB_OFFICIAL_AGENT_CHANNEL_MAINTENANCE_MS
      || env?.XHUB_OFFICIAL_AGENT_AUTO_SYNC_MAINTENANCE_MS
      || 5 * 60 * 1000,
    5 * 60 * 1000,
    1_000
  );
}

export function officialSkillChannelMaintenanceRetryMs(env = process.env) {
  return positiveIntOr(env?.XHUB_OFFICIAL_AGENT_AUTO_SYNC_RETRY_MS || 30_000, 30_000, 0);
}

export function runOfficialSkillChannelMaintenanceTick({
  runtimeBaseDir,
  channelId = 'official-stable',
  sourceRoot,
  retryAfterMs,
  maintenanceIntervalMs,
  env = process.env,
} = {}) {
  const runtime = safeString(runtimeBaseDir || resolveRuntimeBaseDir());
  if (!runtime) return null;
  const previousState = readOfficialSkillChannelState(runtime, { channelId });
  const previousMaintenance = readOfficialSkillChannelMaintenanceStatus(runtime, { channelId });
  const selection = resolveOfficialSkillChannelMaintenanceSelection({
    runtimeBaseDir: runtime,
    channelId,
    sourceRoot,
    env,
  });
  const retryMs = Number.isFinite(Number(retryAfterMs))
    ? Math.max(0, Math.floor(Number(retryAfterMs)))
    : officialSkillChannelMaintenanceRetryMs(env);
  const intervalMs = Number.isFinite(Number(maintenanceIntervalMs))
    ? Math.max(0, Math.floor(Number(maintenanceIntervalMs)))
    : officialSkillChannelMaintenanceIntervalMs(env);
  const state = maybeAutoSyncOfficialSkillChannel(runtime, {
    channelId,
    sourceRoot: selection.source_root,
    retryAfterMs: retryMs,
  });
  const transition = buildOfficialSkillChannelMaintenanceTransition({
    channelId,
    previousState,
    nextState: state,
    previousMaintenance,
    nextSourceKind: selection.source_kind,
  });
  if (transition) {
    appendOfficialSkillChannelMaintenanceTransition(runtime, transition);
  }
  writeOfficialSkillChannelMaintenanceStatus(runtime, {
    channelId,
    maintenanceEnabled: true,
    maintenanceIntervalMs: intervalMs,
    maintenanceRetryAfterMs: retryMs,
    maintenanceLastRunAtMs: Date.now(),
    maintenanceSourceKind: selection.source_kind,
    lastTransitionAtMs: Number(transition?.created_at_ms || previousMaintenance.last_transition_at_ms || 0),
    lastTransitionKind: safeString(transition?.transition_kind || previousMaintenance.last_transition_kind),
    lastTransitionSummary: safeString(transition?.summary || previousMaintenance.last_transition_summary),
    lastResultStatus: safeString(state?.status),
    lastResultErrorCode: safeString(state?.error_code),
  });
  return state;
}

export function startOfficialSkillChannelMaintenance({
  runtimeBaseDir,
  channelId = 'official-stable',
  interval_ms,
  retry_after_ms,
  sourceRoot,
  env = process.env,
} = {}) {
  const runtime = safeString(runtimeBaseDir || resolveRuntimeBaseDir());
  if (!runtime) return () => {};

  const intervalMs = Number.isFinite(Number(interval_ms))
    ? Math.max(25, Math.floor(Number(interval_ms)))
    : officialSkillChannelMaintenanceIntervalMs(env);
  const retryAfterMs = Number.isFinite(Number(retry_after_ms))
    ? Math.max(0, Math.floor(Number(retry_after_ms)))
    : officialSkillChannelMaintenanceRetryMs(env);

  let stopped = false;
  const previousMaintenance = readOfficialSkillChannelMaintenanceStatus(runtime, { channelId });

  const initialSelection = resolveOfficialSkillChannelMaintenanceSelection({
    runtimeBaseDir: runtime,
    channelId,
    sourceRoot,
    env,
  });
  writeOfficialSkillChannelMaintenanceStatus(runtime, {
    channelId,
    maintenanceEnabled: true,
    maintenanceIntervalMs: intervalMs,
    maintenanceRetryAfterMs: retryAfterMs,
    maintenanceLastRunAtMs: 0,
    maintenanceSourceKind: initialSelection.source_kind,
    lastTransitionAtMs: previousMaintenance.last_transition_at_ms,
    lastTransitionKind: previousMaintenance.last_transition_kind,
    lastTransitionSummary: previousMaintenance.last_transition_summary,
  });

  const tick = () => {
    if (stopped) return;
    try {
      runOfficialSkillChannelMaintenanceTick({
        runtimeBaseDir: runtime,
        channelId,
        sourceRoot,
        retryAfterMs,
        maintenanceIntervalMs: intervalMs,
        env,
      });
    } catch {
      // Keep Hub startup and steady-state resilient; state/error details are persisted by the sync path itself.
    }
  };

  const startupTimer = setTimeout(tick, 0);
  try {
    startupTimer.unref();
  } catch {
    // ignore
  }

  const intervalTimer = setInterval(tick, intervalMs);
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
