import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { resolveRuntimeBaseDir } from './local_runtime_ipc.js';
import { sleep, uuid } from './util.js';

function expandHome(p) {
  const s = String(p || '').trim();
  if (!s) return s;
  if (s === '~') return os.homedir();
  if (s.startsWith('~/')) return path.join(os.homedir(), s.slice(2));
  return s;
}

function bridgeBaseCandidates() {
  const home = os.homedir();
  const out = [];

  const env = (process.env.HUB_BRIDGE_BASE_DIR || '').trim();
  if (env) out.push(expandHome(env));

  // If the runtime base dir is explicitly set, prefer it as a bridge candidate too.
  const envRuntime = (process.env.HUB_RUNTIME_BASE_DIR || process.env.REL_FLOW_HUB_BASE_DIR || '').trim();
  if (envRuntime) out.push(expandHome(envRuntime));

  // Include the best-effort runtime base dir (often the Hub container or App Group).
  try {
    const rt = resolveRuntimeBaseDir();
    if (rt) out.push(rt);
  } catch {
    // ignore
  }

  // Common locations used by different build/signing modes.
  out.push(path.join(home, 'Library', 'Group Containers', 'group.rel.flowhub'));
  out.push(path.join(home, 'Library', 'Containers', 'com.rel.flowhub', 'Data', 'XHub'));
  out.push(path.join(home, 'Library', 'Containers', 'com.rel.flowhub', 'Data', 'RELFlowHub'));
  out.push(path.join(home, 'Library', 'Containers', 'com.rel.flowhub.bridge', 'Data', 'XHub'));
  out.push(path.join(home, 'Library', 'Containers', 'com.rel.flowhub.bridge', 'Data', 'RELFlowHub'));
  out.push(path.join('/private/tmp', 'XHub'));
  out.push(path.join('/private/tmp', 'RELFlowHub'));
  out.push(path.join(home, 'XHub'));
  out.push(path.join(home, 'RELFlowHub'));

  // De-dup.
  const seen = new Set();
  const uniq = [];
  for (const d of out) {
    const s = String(d || '').trim();
    if (!s) continue;
    if (seen.has(s)) continue;
    seen.add(s);
    uniq.push(s);
  }
  return uniq;
}

export function resolveBridgeBaseDir() {
  // Explicit override (useful for headless deployments).
  const env = (process.env.HUB_BRIDGE_BASE_DIR || '').trim();
  if (env) return expandHome(env);

  // Prefer an *alive* bridge status among candidates. This avoids mismatches between
  // Hub runtime state (models_state.json) and Bridge IPC locations in dev builds.
  let bestAlive = '';
  let bestAliveSt = null;

  for (const cand of bridgeBaseCandidates()) {
    const st = readBridgeStatus(cand, 3500);
    if (!st.ok || !st.alive) continue;
    if (!bestAliveSt) {
      bestAlive = cand;
      bestAliveSt = st;
      continue;
    }
    // Prefer: enabled > most recent.
    const a = st;
    const b = bestAliveSt;
    if (a.enabled !== b.enabled) {
      if (a.enabled) {
        bestAlive = cand;
        bestAliveSt = st;
      }
      continue;
    }
    if (Number(a.updated_at_sec || 0) > Number(b.updated_at_sec || 0)) {
      bestAlive = cand;
      bestAliveSt = st;
    }
  }

  if (bestAlive) return bestAlive;

  // Fall back to the runtime base dir so callers have a stable place to write settings/commands.
  return resolveRuntimeBaseDir();
}

export function bridgePaths(baseDir) {
  const base = String(baseDir || '').trim();
  return {
    base,
    settingsPath: path.join(base, 'bridge_settings.json'),
    statusPath: path.join(base, 'bridge_status.json'),
    commandsDir: path.join(base, 'bridge_commands'),
    reqDir: path.join(base, 'bridge_requests'),
    respDir: path.join(base, 'bridge_responses'),
  };
}

export function ensureBridgeDirs(baseDir) {
  const p = bridgePaths(baseDir);
  fs.mkdirSync(p.commandsDir, { recursive: true });
  fs.mkdirSync(p.reqDir, { recursive: true });
  fs.mkdirSync(p.respDir, { recursive: true });
}

function isSafeId(id) {
  const s = String(id || '').trim();
  if (!s) return false;
  if (s.includes('/') || s.includes('\\') || s.includes('\0')) return false;
  return true;
}

function readJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function writeJsonAtomic(filePath, obj) {
  const out = String(filePath || '').trim();
  const dir = path.dirname(out);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${out}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  fs.writeFileSync(tmp, JSON.stringify(obj), { encoding: 'utf8' });
  fs.renameSync(tmp, out);
}

export function readBridgeStatus(baseDir, maxAgeMs = 3500) {
  const p = bridgePaths(baseDir);
  const obj = readJsonSafe(p.statusPath);
  const nowSec = Date.now() / 1000.0;
  const updatedAtSec = Number(obj?.updatedAt || 0);
  const enabledUntilSec = Number(obj?.enabledUntil || obj?.enabled_until || 0);

  const alive = updatedAtSec > 0 && (nowSec - updatedAtSec) * 1000.0 <= Math.max(500, Number(maxAgeMs || 0));
  const enabled = enabledUntilSec > 0 && enabledUntilSec > nowSec;

  return {
    ok: !!obj,
    alive,
    enabled,
    pid: obj?.pid != null ? Number(obj.pid) : 0,
    updated_at_sec: updatedAtSec,
    enabled_until_sec: enabledUntilSec,
  };
}

export function readBridgeSettings(baseDir) {
  const p = bridgePaths(baseDir);
  const obj = readJsonSafe(p.settingsPath);
  const enabledUntil = Number(obj?.enabled_until || obj?.enabledUntil || 0);
  const updatedAt = Number(obj?.updated_at || obj?.updatedAt || 0);
  return { ok: !!obj, enabled_until_sec: enabledUntil, updated_at_sec: updatedAt };
}

export function writeBridgeEnableUntil(baseDir, enabledUntilSec) {
  const p = bridgePaths(baseDir);
  ensureBridgeDirs(baseDir);

  const untilSec = Math.max(0, Number(enabledUntilSec || 0));
  writeJsonAtomic(p.settingsPath, { enabled_until: untilSec, updated_at: Date.now() / 1000.0 });

  // BridgeRunner listens on commandsDir for enable_until commands.
  const cmdId = uuid();
  const cmdPath = path.join(p.commandsDir, `cmd_${cmdId}.json`);
  writeJsonAtomic(cmdPath, { type: 'enable_until', enabled_until: untilSec });
}

export function ensureBridgeEnabledUntil(baseDir, enabledUntilSec) {
  const target = Math.max(0, Number(enabledUntilSec || 0));
  const cur = readBridgeSettings(baseDir);
  const curUntil = Number(cur.enabled_until_sec || 0);
  if (cur.ok && curUntil >= target - 1) {
    return { ok: true, changed: false, enabled_until_sec: curUntil };
  }
  writeBridgeEnableUntil(baseDir, target);
  return { ok: true, changed: true, enabled_until_sec: target };
}

export function writeBridgeStop(baseDir) {
  const p = bridgePaths(baseDir);
  ensureBridgeDirs(baseDir);
  const cmdId = uuid();
  const cmdPath = path.join(p.commandsDir, `cmd_${cmdId}.json`);
  writeJsonAtomic(cmdPath, { type: 'stop' });
  try {
    fs.unlinkSync(p.settingsPath);
  } catch {
    // ignore
  }
}

export async function waitForBridgeEnabled(baseDir, timeoutMs = 1500) {
  const deadline = Date.now() + Math.max(10, Number(timeoutMs || 0));
  while (Date.now() < deadline) {
    const st = readBridgeStatus(baseDir);
    if (!st.alive) return st;
    if (st.enabled) return st;
    await sleep(80);
  }
  return readBridgeStatus(baseDir);
}

export function enqueueBridgeFetch(baseDir, req) {
  const p = bridgePaths(baseDir);
  ensureBridgeDirs(baseDir);
  const rid = String(req?.request_id || '').trim();
  if (!isSafeId(rid)) throw new Error('unsafe request_id for bridge filesystem IPC');
  const filePath = path.join(p.reqDir, `req_${rid}.json`);
  const obj = {
    type: 'fetch',
    req_id: rid,
    url: String(req?.url || ''),
    method: String(req?.method || 'GET'),
    timeout_sec: Number(req?.timeout_sec || 12),
    max_bytes: Number(req?.max_bytes || 1_000_000),
  };
  writeJsonAtomic(filePath, obj);
  return { filePath, req_id: rid };
}

async function waitBridgeResult(baseDir, requestId, timeoutMs, timeoutError) {
  const p = bridgePaths(baseDir);
  const rid = String(requestId || '').trim();
  if (!isSafeId(rid)) throw new Error('unsafe request_id');
  const respPath = path.join(p.respDir, `resp_${rid}.json`);
  const deadline = Date.now() + Math.max(1000, Number(timeoutMs || 0));

  while (Date.now() < deadline) {
    let st;
    try {
      st = fs.statSync(respPath);
    } catch {
      await sleep(60);
      continue;
    }
    if (!st || Number(st.size || 0) <= 0) {
      await sleep(30);
      continue;
    }
    const obj = readJsonSafe(respPath);
    try {
      fs.unlinkSync(respPath);
    } catch {
      // ignore
    }
    return obj || null;
  }

  throw new Error(String(timeoutError || 'bridge_timeout'));
}

export async function waitBridgeFetchResult(baseDir, requestId, timeoutMs = 15000) {
  return await waitBridgeResult(baseDir, requestId, timeoutMs, 'bridge_fetch_timeout');
}

export function enqueueBridgeAIGenerate(baseDir, req) {
  const p = bridgePaths(baseDir);
  ensureBridgeDirs(baseDir);
  const rid = String(req?.request_id || '').trim();
  if (!isSafeId(rid)) throw new Error('unsafe request_id for bridge filesystem IPC');
  const filePath = path.join(p.reqDir, `req_${rid}.json`);
  const obj = {
    type: 'ai_generate',
    req_id: rid,
    app_id: String(req?.app_id || ''),
    project_id: String(req?.project_id || ''),
    queued_at_ms: Number(req?.queued_at_ms || Date.now()),
    model_id: String(req?.model_id || ''),
    prompt: String(req?.prompt || ''),
    max_tokens: Number(req?.max_tokens || 512),
    temperature: Number(req?.temperature ?? 0.2),
    top_p: Number(req?.top_p ?? 0.95),
    timeout_sec: Number(req?.timeout_sec || 60),
  };
  writeJsonAtomic(filePath, obj);
  return { filePath, req_id: rid };
}

export async function waitBridgeAIGenerateResult(baseDir, requestId, timeoutMs = 60000) {
  return await waitBridgeResult(baseDir, requestId, timeoutMs, 'bridge_ai_timeout');
}
