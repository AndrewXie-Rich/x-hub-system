import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const SHADOW_THREAD_KEY = 'xterminal_supervisor_durable_candidate_device';
export const SCHEMA_VERSION = 'xt.supervisor.durable_candidate_mirror.v1';
export const CARRIER_KIND = 'supervisor_after_turn_durable_candidate_shadow_write';
export const MIRROR_TARGET = 'hub_candidate_carrier_shadow_thread';
export const LOCAL_STORE_ROLE = 'cache|fallback|edit_buffer';

export function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

export function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

export function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `supervisor_candidate_carrier_${token}${suffix}`);
}

export function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

export function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'false',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
  };
}

export function invokeHubMemoryUnary(impl, methodName, request) {
  let outErr = null;
  let outRes = null;
  impl.HubMemory[methodName](
    {
      request,
      metadata: {
        get() {
          return [];
        },
      },
    },
    (err, res) => {
      outErr = err || null;
      outRes = res || null;
    }
  );
  return { err: outErr, res: outRes };
}

export function makeSupervisorClient() {
  return {
    device_id: 'dev-supervisor-candidate-1',
    user_id: 'user-supervisor-candidate-1',
    app_id: 'x_terminal',
    project_id: '',
    session_id: 'sess-supervisor-candidate-1',
  };
}

export function openShadowThread(impl, client) {
  const opened = invokeHubMemoryUnary(impl, 'GetOrCreateThread', {
    client,
    thread_key: SHADOW_THREAD_KEY,
  });
  if (opened.err) throw opened.err;
  return String(opened.res?.thread?.thread_id || '');
}

export function buildCarrierEnvelope({
  emitted_at_ms = 1_717_000_000_000,
  summary_line = 'user_scope, project_scope',
  scopes = ['user_scope', 'project_scope'],
  candidates = [],
} = {}) {
  return {
    schema_version: SCHEMA_VERSION,
    carrier_kind: CARRIER_KIND,
    mirror_target: MIRROR_TARGET,
    local_store_role: LOCAL_STORE_ROLE,
    emitted_at_ms,
    summary_line,
    scopes,
    candidate_count: candidates.length,
    candidates,
  };
}
