import fs from 'node:fs';
import path from 'node:path';

import { nowMs, uuid } from './util.js';

const OPERATOR_CHANNEL_XT_COMMAND_QUEUE_FILE = 'operator_channel_xt_command_queue_status.json';
const OPERATOR_CHANNEL_XT_COMMAND_RESULTS_FILE = 'operator_channel_xt_command_results_status.json';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
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
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', { encoding: 'utf8', mode: 0o600 });
    fs.renameSync(tmp, outPath);
    try {
      fs.chmodSync(outPath, 0o600);
    } catch {
      // ignore
    }
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

export function operatorChannelXTCommandQueueFileName() {
  return OPERATOR_CHANNEL_XT_COMMAND_QUEUE_FILE;
}

export function operatorChannelXTCommandResultsFileName() {
  return OPERATOR_CHANNEL_XT_COMMAND_RESULTS_FILE;
}

export function normalizeOperatorChannelXTCommandItem(input = {}) {
  const src = input && typeof input === 'object' ? input : {};
  const command_id = safeString(src.command_id || src.id);
  if (!command_id) return null;
  return {
    command_id,
    request_id: safeString(src.request_id),
    action_name: safeString(src.action_name).toLowerCase(),
    binding_id: safeString(src.binding_id),
    route_id: safeString(src.route_id),
    scope_type: safeString(src.scope_type).toLowerCase(),
    scope_id: safeString(src.scope_id),
    project_id: safeString(src.project_id || src.scope_id),
    provider: safeString(src.provider).toLowerCase(),
    account_id: safeString(src.account_id),
    conversation_id: safeString(src.conversation_id),
    thread_key: safeString(src.thread_key),
    actor_ref: safeString(src.actor_ref),
    resolved_device_id: safeString(src.resolved_device_id),
    preferred_device_id: safeString(src.preferred_device_id),
    note: safeString(src.note),
    created_at_ms: safeInt(src.created_at_ms, 0),
    audit_ref: safeString(src.audit_ref),
  };
}

export function normalizeOperatorChannelXTCommandResultItem(input = {}) {
  const src = input && typeof input === 'object' ? input : {};
  const command_id = safeString(src.command_id || src.id);
  if (!command_id) return null;
  return {
    command_id,
    request_id: safeString(src.request_id),
    action_name: safeString(src.action_name).toLowerCase(),
    project_id: safeString(src.project_id),
    resolved_device_id: safeString(src.resolved_device_id),
    status: safeString(src.status).toLowerCase(),
    deny_code: safeString(src.deny_code),
    detail: safeString(src.detail),
    run_id: safeString(src.run_id),
    created_at_ms: safeInt(src.created_at_ms, 0),
    completed_at_ms: safeInt(src.completed_at_ms, 0),
    audit_ref: safeString(src.audit_ref),
  };
}

function sortedCommands(rows = []) {
  return rows.sort((left, right) => {
    const lts = safeInt(left?.created_at_ms, 0);
    const rts = safeInt(right?.created_at_ms, 0);
    if (lts !== rts) return rts - lts;
    return safeString(left?.command_id).localeCompare(safeString(right?.command_id));
  });
}

function sortedResults(rows = []) {
  return rows.sort((left, right) => {
    const lts = safeInt(left?.completed_at_ms || left?.created_at_ms, 0);
    const rts = safeInt(right?.completed_at_ms || right?.created_at_ms, 0);
    if (lts !== rts) return rts - lts;
    return safeString(left?.command_id).localeCompare(safeString(right?.command_id));
  });
}

export function readOperatorChannelXTCommandQueueSnapshot(runtimeBaseDir, { limit = 240 } = {}) {
  const base = safeString(runtimeBaseDir);
  if (!base) {
    return {
      updated_at_ms: 0,
      items: [],
    };
  }
  const decoded = readJsonSafe(path.join(base, OPERATOR_CHANNEL_XT_COMMAND_QUEUE_FILE));
  const boundedLimit = Math.max(1, Math.min(1000, safeInt(limit, 240) || 240));
  const items = sortedCommands(
    (Array.isArray(decoded?.items) ? decoded.items : [])
      .map(normalizeOperatorChannelXTCommandItem)
      .filter(Boolean)
  ).slice(0, boundedLimit);
  return {
    updated_at_ms: safeInt(decoded?.updated_at_ms, 0),
    items,
  };
}

export function readOperatorChannelXTCommandResultsSnapshot(runtimeBaseDir, { limit = 240 } = {}) {
  const base = safeString(runtimeBaseDir);
  if (!base) {
    return {
      updated_at_ms: 0,
      items: [],
    };
  }
  const decoded = readJsonSafe(path.join(base, OPERATOR_CHANNEL_XT_COMMAND_RESULTS_FILE));
  const boundedLimit = Math.max(1, Math.min(1000, safeInt(limit, 240) || 240));
  const items = sortedResults(
    (Array.isArray(decoded?.items) ? decoded.items : [])
      .map(normalizeOperatorChannelXTCommandResultItem)
      .filter(Boolean)
  ).slice(0, boundedLimit);
  return {
    updated_at_ms: safeInt(decoded?.updated_at_ms, 0),
    items,
  };
}

export function enqueueOperatorChannelXTCommand(runtimeBaseDir, input = {}) {
  const base = safeString(runtimeBaseDir);
  if (!base) return null;

  const created_at_ms = safeInt(input.created_at_ms, nowMs()) || nowMs();
  const normalized = normalizeOperatorChannelXTCommandItem({
    ...input,
    command_id: safeString(input.command_id) || `xtcmd_${uuid()}`,
    created_at_ms,
  });
  if (!normalized) return null;

  const existing = readOperatorChannelXTCommandQueueSnapshot(base, { limit: 1000 });
  const deduped = new Map((existing.items || []).map((item) => [item.command_id, item]));
  deduped.set(normalized.command_id, normalized);

  const limitRaw = safeInt(process.env.HUB_OPERATOR_CHANNEL_XT_COMMAND_QUEUE_MAX, 240);
  const maxItems = Math.max(16, Math.min(2000, limitRaw || 240));
  const merged = sortedCommands(Array.from(deduped.values())).slice(0, maxItems);
  const updated_at_ms = Math.max(created_at_ms, safeInt(existing.updated_at_ms, 0), nowMs());

  const ok = writeJsonAtomic(base, OPERATOR_CHANNEL_XT_COMMAND_QUEUE_FILE, {
    schema_version: 'operator_channel_xt_command_queue_status.v1',
    updated_at_ms,
    items: merged,
  });
  return ok ? normalized : null;
}

export async function waitForOperatorChannelXTCommandResult(
  runtimeBaseDir,
  commandId,
  { timeout_ms = 4500, poll_ms = 250 } = {}
) {
  const base = safeString(runtimeBaseDir);
  const wanted = safeString(commandId);
  if (!base || !wanted) return null;

  const timeoutMs = Math.max(0, Math.min(30_000, safeInt(timeout_ms, 4500) || 4500));
  const pollMs = Math.max(40, Math.min(1000, safeInt(poll_ms, 250) || 250));
  const deadline = Date.now() + timeoutMs;

  while (Date.now() <= deadline) {
    const snapshot = readOperatorChannelXTCommandResultsSnapshot(base, { limit: 1000 });
    const hit = (snapshot.items || []).find((item) => safeString(item.command_id) === wanted) || null;
    if (hit) return hit;
    if (timeoutMs <= 0) break;
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  return null;
}
