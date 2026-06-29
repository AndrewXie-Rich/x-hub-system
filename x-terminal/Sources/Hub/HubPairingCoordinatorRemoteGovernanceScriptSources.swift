import Foundation

extension HubPairingCoordinator {
    func remoteMemorySnapshotScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = safe(projectIdOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function listCanonical(memoryClient, md, client, scope, limit) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.ListCanonicalMemory(
      {
        client,
        scope,
        thread_id: '',
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
  return Array.isArray(resp?.items) ? resp.items : [];
}

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function getWorkingSet(memoryClient, md, client, threadId, limit) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetWorkingSet(
      {
        client,
        thread_id: threadId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
  return Array.isArray(resp?.messages) ? resp.messages : [];
}

async function getProjectRoleTranscriptProjection(memoryClient, md, client, projectId, threadKey, limit) {
  if (typeof memoryClient.GetProjectRoleTranscriptProjection !== 'function') return null;
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetProjectRoleTranscriptProjection(
      {
        client,
        project_id: projectId,
        thread_key: threadKey,
        limit,
        include_content: true,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
  return resp && typeof resp === 'object' ? resp : null;
}

function clipText(v, n = 360) {
  const s = safe(v);
  if (!s) return '';
  if (s.length <= n) return s;
  return `${s.slice(0, n)}…`;
}

function roleTurnMessagesFromProjection(projection) {
  const lines = Array.isArray(projection?.recent_lines) ? projection.recent_lines : [];
  return lines
    .map((line) => {
      const content = clipText(line?.content || '', 420);
      if (!content) return null;
      const metadata = line?.turn_metadata && typeof line.turn_metadata === 'object'
        ? line.turn_metadata
        : null;
      const role = safe(line?.role || metadata?.source_role || 'assistant') || 'assistant';
      const out = { role, content };
      if (metadata) out.turn_metadata = metadata;
      return out;
    })
    .filter(Boolean);
}

async function main() {
  const mode = safe(process.env.XTERMINAL_MEM_MODE || 'project').toLowerCase();
  const projectId = safe(process.env.XTERMINAL_MEM_PROJECT_ID || '');
  const canonicalLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_MEM_CANONICAL_LIMIT || '24'), 10);
  const workingLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_MEM_WORKING_LIMIT || '12'), 10);
  const canonicalLimit = Math.max(1, Math.min(80, Number.isFinite(canonicalLimitRaw) ? canonicalLimitRaw : 24));
  const workingLimit = Math.max(1, Math.min(80, Number.isFinite(workingLimitRaw) ? workingLimitRaw : 12));

  const scope = mode === 'project' ? 'project' : 'device';
  const client = reqClientFromEnv(mode === 'project' ? projectId : '');
  if (scope === 'project' && !safe(client.project_id)) {
    throw new Error('project_id_empty');
  }

  const threadKey = scope === 'project'
    ? `xterminal_project_${safe(client.project_id)}`
    : 'xterminal_supervisor_device';

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const canonicalItems = await listCanonical(memoryClient, md, client, scope, canonicalLimit);
  const canonicalEntries = canonicalItems
    .map((it) => {
      const key = safe(it?.key || '');
      const value = clipText(it?.value || '', 460);
      if (!key || !value) return '';
      return `${key} = ${value}`;
    })
    .filter(Boolean);

  const th = await getOrCreateThread(memoryClient, md, client, threadKey);
  const threadId = safe(th?.thread_id || '');
  let workingEntries = [];
  let roleTurnMessages = [];
  let projectionRoleTurnMessages = [];
  if (scope === 'project') {
    try {
      const projection = await getProjectRoleTranscriptProjection(
        memoryClient,
        md,
        client,
        safe(client.project_id),
        threadKey,
        workingLimit
      );
      projectionRoleTurnMessages = roleTurnMessagesFromProjection(projection);
    } catch {}
  }
  if (threadId) {
    const ws = await getWorkingSet(memoryClient, md, client, threadId, workingLimit);
    workingEntries = ws
      .map((m) => {
        const role = safe(m?.role || 'assistant');
        const content = clipText(m?.content || '', 420);
        if (!content) return '';
        const roleTurn = { role, content };
        if (m?.turn_metadata && typeof m.turn_metadata === 'object') {
          roleTurn.turn_metadata = m.turn_metadata;
        }
        roleTurnMessages.push(roleTurn);
        return `${role}: ${content}`;
      })
      .filter(Boolean);
  }
  if (projectionRoleTurnMessages.length > 0) {
    roleTurnMessages = projectionRoleTurnMessages;
    workingEntries = projectionRoleTurnMessages.map((m) => `${safe(m?.role || 'assistant')}: ${clipText(m?.content || '', 420)}`);
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    canonical_entries: canonicalEntries,
    working_entries: workingEntries,
    role_turn_messages: roleTurnMessages,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    canonical_entries: [],
    working_entries: [],
    role_turn_messages: [],
    reason: msg || 'remote_memory_snapshot_failed',
    error_code: msg || 'remote_memory_snapshot_failed',
    error_message: msg || 'remote_memory_snapshot_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteMemoryRetrievalScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

function parseJsonList(raw) {
  const text = safe(raw);
  if (!text) return [];
  try {
    const decoded = JSON.parse(text);
    if (!Array.isArray(decoded)) return [];
    return decoded.map((item) => safe(item)).filter(Boolean);
  } catch {
    return [];
  }
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function retrieveMemory(memoryClient, md, payload) {
  return await new Promise((resolve, reject) => {
    memoryClient.RetrieveMemory(payload, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const projectId = safe(process.env.XTERMINAL_MEM_RETR_PROJECT_ID || process.env.HUB_PROJECT_ID || '');
  const client = reqClientFromEnv(projectId);
  const payload = {
    schema_version: safe(process.env.XTERMINAL_MEM_RETR_SCHEMA_VERSION || 'xt.memory_retrieval_request.v1'),
    request_id: safe(process.env.XTERMINAL_MEM_RETR_REQUEST_ID || ''),
    client,
    scope: safe(process.env.XTERMINAL_MEM_RETR_SCOPE || 'current_project'),
    requester_role: safe(process.env.XTERMINAL_MEM_RETR_REQUESTER_ROLE || 'chat'),
    mode: safe(process.env.XTERMINAL_MEM_RETR_MODE || 'project_chat'),
    project_id: projectId,
    cross_project_target_ids: parseJsonList(process.env.XTERMINAL_MEM_RETR_CROSS_PROJECT_TARGET_IDS_JSON || '[]'),
    project_root: safe(process.env.XTERMINAL_MEM_RETR_PROJECT_ROOT || ''),
    display_name: safe(process.env.XTERMINAL_MEM_RETR_DISPLAY_NAME || ''),
    query: safe(process.env.XTERMINAL_MEM_RETR_QUERY || ''),
    latest_user: safe(process.env.XTERMINAL_MEM_RETR_LATEST_USER || ''),
    allowed_layers: parseJsonList(process.env.XTERMINAL_MEM_RETR_ALLOWED_LAYERS_JSON || '[]'),
    retrieval_kind: safe(process.env.XTERMINAL_MEM_RETR_RETRIEVAL_KIND || ''),
    max_results: Number.parseInt(safe(process.env.XTERMINAL_MEM_RETR_MAX_RESULTS || '3'), 10) || 3,
    reason: safe(process.env.XTERMINAL_MEM_RETR_REASON || ''),
    require_explainability: ['1', 'true', 'yes'].includes(safe(process.env.XTERMINAL_MEM_RETR_REQUIRE_EXPLAINABILITY || '').toLowerCase()),
    requested_kinds: parseJsonList(process.env.XTERMINAL_MEM_RETR_REQUESTED_KINDS_JSON || '[]'),
    explicit_refs: parseJsonList(process.env.XTERMINAL_MEM_RETR_EXPLICIT_REFS_JSON || '[]'),
    max_snippets: Number.parseInt(safe(process.env.XTERMINAL_MEM_RETR_MAX_SNIPPETS || '3'), 10) || 3,
    max_snippet_chars: Number.parseInt(safe(process.env.XTERMINAL_MEM_RETR_MAX_SNIPPET_CHARS || '420'), 10) || 420,
    audit_ref: safe(process.env.XTERMINAL_MEM_RETR_AUDIT_REF || ''),
  };

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const response = await retrieveMemory(memoryClient, md, payload);

  out({
    ok: true,
    ...response,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    schema_version: 'xt.memory_retrieval_result.v1',
    request_id: safe(process.env.XTERMINAL_MEM_RETR_REQUEST_ID || ''),
    status: '',
    resolved_scope: safe(process.env.XTERMINAL_MEM_RETR_SCOPE || 'current_project'),
    source: 'hub_memory_retrieval_grpc_v1',
    scope: safe(process.env.XTERMINAL_MEM_RETR_SCOPE || 'current_project'),
    audit_ref: safe(process.env.XTERMINAL_MEM_RETR_AUDIT_REF || ''),
    reason: msg || 'remote_memory_retrieval_failed',
    reason_code: msg || 'remote_memory_retrieval_failed',
    deny_code: '',
    results: [],
    truncated: false,
    budget_used_chars: 0,
    truncated_items: 0,
    redacted_items: 0,
    error_code: msg || 'remote_memory_retrieval_failed',
    error_message: msg || 'remote_memory_retrieval_failed',
  });
  process.exit(1);
});
"""#
    }

    func remotePendingGrantRequestsScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_PENDING_GRANTS_PROJECT_ID || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANTS_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetPendingGrantRequests(
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        grant_request_id: safe(it?.grant_request_id || ''),
        request_id: safe(it?.request_id || ''),
        device_id: safe(it?.client?.device_id || ''),
        user_id: safe(it?.client?.user_id || ''),
        app_id: safe(it?.client?.app_id || ''),
        project_id: safe(it?.client?.project_id || ''),
        capability: safe(it?.capability || ''),
        model_id: safe(it?.model_id || ''),
        reason: safe(it?.reason || ''),
        requested_ttl_sec: asInt(it?.requested_ttl_sec || 0),
        requested_token_cap: asInt(it?.requested_token_cap || 0),
        status: safe(it?.status || ''),
        decision: safe(it?.decision || ''),
        created_at_ms: asMs(it?.created_at_ms || 0),
        decided_at_ms: asMs(it?.decided_at_ms || 0),
      })).filter((it) => it.grant_request_id)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_pending_grants_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSupervisorCandidateReviewQueueScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asList(v) {
  return Array.isArray(v) ? v.map((item) => safe(item)).filter(Boolean) : [];
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_PROJECT_ID || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetSupervisorCandidateReviewQueue(
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        schema_version: safe(it?.schema_version || ''),
        review_id: safe(it?.review_id || ''),
        request_id: safe(it?.request_id || ''),
        evidence_ref: safe(it?.evidence_ref || ''),
        review_state: safe(it?.review_state || ''),
        durable_promotion_state: safe(it?.durable_promotion_state || ''),
        promotion_boundary: safe(it?.promotion_boundary || ''),
        device_id: safe(it?.device_id || ''),
        user_id: safe(it?.user_id || ''),
        app_id: safe(it?.app_id || ''),
        thread_id: safe(it?.thread_id || ''),
        thread_key: safe(it?.thread_key || ''),
        project_id: safe(it?.project_id || ''),
        project_ids: asList(it?.project_ids),
        scopes: asList(it?.scopes),
        record_types: asList(it?.record_types),
        audit_refs: asList(it?.audit_refs),
        idempotency_keys: asList(it?.idempotency_keys),
        candidate_count: asInt(it?.candidate_count || 0),
        summary_line: safe(it?.summary_line || ''),
        mirror_target: safe(it?.mirror_target || ''),
        local_store_role: safe(it?.local_store_role || ''),
        carrier_kind: safe(it?.carrier_kind || ''),
        carrier_schema_version: safe(it?.carrier_schema_version || ''),
        pending_change_id: safe(it?.pending_change_id || ''),
        pending_change_status: safe(it?.pending_change_status || ''),
        edit_session_id: safe(it?.edit_session_id || ''),
        doc_id: safe(it?.doc_id || ''),
        writeback_ref: safe(it?.writeback_ref || ''),
        stage_created_at_ms: asMs(it?.stage_created_at_ms || 0),
        stage_updated_at_ms: asMs(it?.stage_updated_at_ms || 0),
        latest_emitted_at_ms: asMs(it?.latest_emitted_at_ms || 0),
        created_at_ms: asMs(it?.created_at_ms || 0),
        updated_at_ms: asMs(it?.updated_at_ms || 0),
      })).filter((it) => it.request_id)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_supervisor_candidate_review_queue_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteConnectorIngressReceiptsScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_CONNECTOR_INGRESS_PROJECT_ID || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_CONNECTOR_INGRESS_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetConnectorIngressReceipts(
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        receipt_id: safe(it?.receipt_id || ''),
        request_id: safe(it?.request_id || ''),
        project_id: safe(it?.project_id || ''),
        connector: safe(it?.connector || ''),
        target_id: safe(it?.target_id || ''),
        ingress_type: safe(it?.ingress_type || ''),
        channel_scope: safe(it?.channel_scope || ''),
        source_id: safe(it?.source_id || ''),
        message_id: safe(it?.message_id || ''),
        dedupe_key: safe(it?.dedupe_key || ''),
        received_at_ms: asMs(it?.received_at_ms || 0),
        event_sequence: asMs(it?.event_sequence || 0),
        delivery_state: safe(it?.delivery_state || ''),
        runtime_state: safe(it?.runtime_state || ''),
      })).filter((it) => it.receipt_id)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_connector_ingress_receipts_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteRuntimeSurfaceOverridesScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const projectId = safe(
    process.env.XTERMINAL_RUNTIME_SURFACE_OVERRIDE_PROJECT_ID
      || process.env.\#(HubRemoteRuntimeSurfaceCompatContract.legacyProjectIdEnv)
      || ''
  );
  const limitRaw = Number.parseInt(
    safe(
      process.env.XTERMINAL_RUNTIME_SURFACE_OVERRIDE_LIMIT
        || process.env.\#(HubRemoteRuntimeSurfaceCompatContract.legacyLimitEnv)
        || '200'
    ),
    10
  );
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient[\#(String(reflecting: HubRemoteRuntimeSurfaceCompatContract.grpcMethod))](
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        project_id: safe(it?.project_id || ''),
        override_mode: safe(it?.override_mode || '').toLowerCase(),
        updated_at_ms: asMs(it?.updated_at_ms || 0),
        reason: safe(it?.reason || ''),
        audit_ref: safe(it?.audit_ref || ''),
      })).filter((it) => it.project_id && it.override_mode)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || '\#(HubRemoteRuntimeSurfaceCompatContract.failureReasonCode)');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    @available(*, deprecated, message: "Use remoteRuntimeSurfaceOverridesScriptSource()")
    func remoteAutonomyPolicyOverridesScriptSource() -> String {
        remoteRuntimeSurfaceOverridesScriptSource()
    }

    func remotePendingGrantActionScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function callApprove(runtimeClient, md, req) {
  return await new Promise((resolve, reject) => {
    runtimeClient.ApprovePendingGrantRequest(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function callDeny(runtimeClient, md, req) {
  return await new Promise((resolve, reject) => {
    runtimeClient.DenyPendingGrantRequest(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function main() {
  const action = safe(process.env.XTERMINAL_PENDING_GRANT_ACTION || '').toLowerCase();
  if (action !== 'approve' && action !== 'deny') throw new Error('invalid_action');

  const grantRequestId = safe(process.env.XTERMINAL_PENDING_GRANT_ID || '');
  if (!grantRequestId) throw new Error('grant_request_id_empty');

  const projectId = safe(process.env.XTERMINAL_PENDING_GRANT_PROJECT_ID || '');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  if (action === 'approve') {
    const ttlRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANT_TTL_SEC || ''), 10);
    const tokenCapRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANT_TOKEN_CAP || ''), 10);
    const note = safe(process.env.XTERMINAL_PENDING_GRANT_NOTE || '');
    const req = {
      client,
      grant_request_id: grantRequestId,
      ttl_sec: Number.isFinite(ttlRaw) && ttlRaw > 0 ? Math.max(10, Math.min(86400, ttlRaw)) : 0,
      token_cap: Number.isFinite(tokenCapRaw) && tokenCapRaw > 0 ? Math.max(0, tokenCapRaw) : 0,
      note,
    };
    const resp = await callApprove(runtimeClient, md, req);
    out({
      ok: true,
      decision: 'approved',
      grant_request_id: safe(resp?.grant_request_id || grantRequestId),
      grant_id: safe(resp?.grant?.grant_id || ''),
      expires_at_ms: asMs(resp?.grant?.expires_at_ms || 0),
    });
    return;
  }

  const reason = safe(process.env.XTERMINAL_PENDING_GRANT_REASON || '');
  const resp = await callDeny(runtimeClient, md, {
    client,
    grant_request_id: grantRequestId,
    reason,
  });
  out({
    ok: true,
    decision: 'denied',
    grant_request_id: safe(resp?.grant_request_id || grantRequestId),
    grant_id: '',
    expires_at_ms: 0,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_runtime_unimplemented'
    : (msg || 'remote_pending_grant_action_failed');
  out({
    ok: false,
    decision: 'failed',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSupervisorCandidateReviewStageScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const candidateRequestId = safe(process.env.XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_REQUEST_ID || '');
  if (!candidateRequestId) throw new Error('candidate_request_id_empty');

  const projectId = safe(process.env.XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_PROJECT_ID || '');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    memoryClient.StageSupervisorCandidateReview(
      {
        client,
        candidate_request_id: candidateRequestId,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    staged: !!resp?.staged,
    idempotent: !!resp?.idempotent,
    review_state: safe(resp?.review_state || ''),
    durable_promotion_state: safe(resp?.durable_promotion_state || ''),
    promotion_boundary: safe(resp?.promotion_boundary || ''),
    candidate_request_id: safe(resp?.candidate_request_id || candidateRequestId),
    evidence_ref: safe(resp?.evidence_ref || ''),
    edit_session_id: safe(resp?.edit_session_id || ''),
    pending_change_id: safe(resp?.pending_change_id || ''),
    doc_id: safe(resp?.doc_id || ''),
    base_version: safe(resp?.base_version || ''),
    working_version: safe(resp?.working_version || ''),
    session_revision: asInt(resp?.session_revision || 0),
    status: safe(resp?.status || ''),
    markdown: typeof resp?.markdown === 'string' ? resp.markdown : '',
    created_at_ms: asMs(resp?.created_at_ms || 0),
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    expires_at_ms: asMs(resp?.expires_at_ms || 0),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_supervisor_candidate_review_stage_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    staged: false,
    idempotent: false,
    review_state: '',
    durable_promotion_state: '',
    promotion_boundary: '',
    candidate_request_id: '',
    evidence_ref: '',
    edit_session_id: '',
    pending_change_id: '',
    doc_id: '',
    base_version: '',
    working_version: '',
    session_revision: 0,
    status: '',
    markdown: '',
    created_at_ms: 0,
    updated_at_ms: 0,
    expires_at_ms: 0,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSchedulerStatusScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const includeQueueItems = ['1', 'true', 'yes', 'on'].includes(safe(process.env.XTERMINAL_SCHED_INCLUDE_QUEUE_ITEMS || '1').toLowerCase());
  const queueItemsLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_SCHED_QUEUE_ITEMS_LIMIT || '80'), 10);
  const queueItemsLimit = Math.max(1, Math.min(500, Number.isFinite(queueItemsLimitRaw) ? queueItemsLimitRaw : 80));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetSchedulerStatus(
      {
        client,
        include_queue_items: includeQueueItems,
        queue_items_limit: queueItemsLimit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const paid = resp?.paid_ai || {};
  const inFlightByScope = Array.isArray(paid?.in_flight_by_scope)
    ? paid.in_flight_by_scope.map((it) => ({
        scope_key: safe(it?.scope_key || ''),
        in_flight: asInt(it?.in_flight || 0),
      })).filter((it) => it.scope_key)
    : [];
  const queuedByScope = Array.isArray(paid?.queued_by_scope)
    ? paid.queued_by_scope.map((it) => ({
        scope_key: safe(it?.scope_key || ''),
        queued: asInt(it?.queued || 0),
      })).filter((it) => it.scope_key)
    : [];
  const queueItems = Array.isArray(paid?.queue_items)
    ? paid.queue_items.map((it) => ({
        request_id: safe(it?.request_id || ''),
        scope_key: safe(it?.scope_key || ''),
        enqueued_at_ms: asMs(it?.enqueued_at_ms || 0),
        queued_ms: asMs(it?.queued_ms || 0),
      })).filter((it) => it.request_id && it.scope_key)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(paid?.updated_at_ms || 0),
    in_flight_total: asInt(paid?.in_flight_total || 0),
    queue_depth: asInt(paid?.queue_depth || 0),
    oldest_queued_ms: asMs(paid?.oldest_queued_ms || 0),
    in_flight_by_scope: inFlightByScope,
    queued_by_scope: queuedByScope,
    queue_items: queueItems,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_scheduler_status_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    in_flight_total: 0,
    queue_depth: 0,
    oldest_queued_ms: 0,
    in_flight_by_scope: [],
    queued_by_scope: [],
    queue_items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSupervisorBriefProjectionScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asBool(v, fallback = false) {
  const token = safe(v).toLowerCase();
  if (!token) return fallback;
  if (token === '1' || token === 'true' || token === 'yes' || token === 'on') return true;
  if (token === '0' || token === 'false' || token === 'no' || token === 'off') return false;
  return fallback;
}

async function main() {
  const requestId = safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_REQUEST_ID || '');
  const projectId = safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_PROJECT_ID || '');
  if (!requestId) throw new Error('request_id_empty');
  if (!projectId) throw new Error('project_id_empty');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSupervisor && !proto?.HubRuntime) throw new Error('hub_supervisor_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = proto?.HubRuntime ? new proto.HubRuntime(addr, creds, options) : null;
  const supervisorClient = (() => {
    if (runtimeClient && typeof runtimeClient.GetSupervisorBriefProjection === 'function') return runtimeClient;
    if (proto?.HubSupervisor) return new proto.HubSupervisor(addr, creds, options);
    throw new Error('hub_supervisor_missing');
  })();

  const request = {
    request_id: requestId,
    client,
    project_id: projectId,
    run_id: safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_RUN_ID || ''),
    mission_id: safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_MISSION_ID || ''),
    projection_kind: safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_KIND || 'progress_brief') || 'progress_brief',
    trigger: safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_TRIGGER || 'daily_digest') || 'daily_digest',
    include_tts_script: asBool(process.env.XTERMINAL_SUPERVISOR_BRIEF_INCLUDE_TTS || '1', true),
    include_card_summary: asBool(process.env.XTERMINAL_SUPERVISOR_BRIEF_INCLUDE_CARD_SUMMARY || '0', false),
    max_evidence_refs: Math.max(0, Math.min(12, Number.parseInt(safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_MAX_EVIDENCE_REFS || '4'), 10) || 4)),
  };

  const resp = await new Promise((resolve, reject) => {
    supervisorClient.GetSupervisorBriefProjection(
      request,
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const projection = resp?.projection
    ? {
        schema_version: safe(resp.projection?.schema_version || 'xhub.supervisor_brief_projection.v1'),
        projection_id: safe(resp.projection?.projection_id || ''),
        projection_kind: safe(resp.projection?.projection_kind || ''),
        project_id: safe(resp.projection?.project_id || ''),
        run_id: safe(resp.projection?.run_id || ''),
        mission_id: safe(resp.projection?.mission_id || ''),
        trigger: safe(resp.projection?.trigger || ''),
        status: safe(resp.projection?.status || ''),
        critical_blocker: safe(resp.projection?.critical_blocker || ''),
        topline: safe(resp.projection?.topline || ''),
        next_best_action: safe(resp.projection?.next_best_action || ''),
        pending_grant_count: asInt(resp.projection?.pending_grant_count || 0),
        tts_script: Array.isArray(resp.projection?.tts_script)
          ? resp.projection.tts_script.map((item) => safe(item)).filter(Boolean)
          : [],
        card_summary: safe(resp.projection?.card_summary || ''),
        evidence_refs: Array.isArray(resp.projection?.evidence_refs)
          ? resp.projection.evidence_refs.map((item) => safe(item)).filter(Boolean)
          : [],
        generated_at_ms: asMs(resp.projection?.generated_at_ms || 0),
        expires_at_ms: asMs(resp.projection?.expires_at_ms || 0),
        audit_ref: safe(resp.projection?.audit_ref || ''),
      }
    : null;

  const denyCode = safe(resp?.deny_code || '');
  out({
    ok: resp?.ok === true,
    source: 'hub_supervisor_grpc',
    projection,
    reason: denyCode || '',
    error_code: denyCode || '',
    error_message: denyCode || '',
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_supervisor_unimplemented'
    : (msg || 'remote_supervisor_brief_projection_failed');
  out({
    ok: false,
    source: 'hub_supervisor_grpc',
    projection: null,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSupervisorRouteDecisionScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asBool(v, fallback = false) {
  const token = safe(v).toLowerCase();
  if (!token) return fallback;
  if (token === '1' || token === 'true' || token === 'yes' || token === 'on') return true;
  if (token === '0' || token === 'false' || token === 'no' || token === 'off') return false;
  return fallback;
}

async function buildGovernanceRuntimeReadiness({ route, request }) {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'governance_runtime_readiness_projection.js');
  if (!fs.existsSync(helper)) return null;

  try {
    const mod = await import(pathToFileURL(helper).href);
    if (typeof mod.buildSupervisorRouteGovernanceRuntimeReadinessProjection !== 'function') {
      return null;
    }

    const projection = mod.buildSupervisorRouteGovernanceRuntimeReadinessProjection({
      route,
      intent: safe(request?.ingress?.normalized_intent_type || ''),
      require_xt: request?.require_xt === true,
      require_runner: request?.require_runner === true,
      auth_kind: safe(process.env.HUB_CLIENT_TOKEN || '') ? 'client' : '',
      client_capability: 'events',
      trust_profile_present: false,
      trusted_automation_mode: safe(process.env.HUB_TRUSTED_AUTOMATION_MODE || ''),
      trusted_automation_state: safe(process.env.HUB_TRUSTED_AUTOMATION_STATE || ''),
    });
    if (!projection || typeof projection !== 'object') return null;

    const components = [];
    const byKey = projection.components_by_xt_key && typeof projection.components_by_xt_key === 'object'
      ? projection.components_by_xt_key
      : {};
    for (const [key, value] of Object.entries(byKey)) {
      const row = value && typeof value === 'object' ? value : {};
      components.push({
        key: safe(key),
        state: safe(row.state || ''),
        deny_code: safe(row.deny_code || ''),
        summary_line: safe(row.summary_line || row.summary || ''),
        missing_reason_codes: Array.isArray(row.missing_reason_codes)
          ? row.missing_reason_codes.map((item) => safe(item)).filter(Boolean)
          : [],
      });
    }

    return {
      schema_version: safe(projection.schema_version || 'xhub.governance_runtime_readiness.v1'),
      source: safe(projection.source || 'hub'),
      governance_surface: safe(projection.governance_surface || 'a4_agent'),
      context: safe(projection.context || 'supervisor_route'),
      configured: projection.configured === true,
      state: safe(projection.state || ''),
      runtime_ready: projection.runtime_ready === true,
      project_id: safe(projection.project_id || route?.project_id || ''),
      blockers: Array.isArray(projection.blockers)
        ? projection.blockers.map((item) => safe(item)).filter(Boolean)
        : [],
      blocked_component_keys: Array.isArray(projection.blocked_component_keys)
        ? projection.blocked_component_keys.map((item) => safe(item)).filter(Boolean)
        : [],
      missing_reason_codes: Array.isArray(projection.missing_reason_codes)
        ? projection.missing_reason_codes.map((item) => safe(item)).filter(Boolean)
        : [],
      summary_line: safe(projection.summary_line || ''),
      missing_summary_line: safe(projection.missing_summary_line || ''),
      components,
    };
  } catch {
    return null;
  }
}

async function main() {
  const requestId = safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_REQUEST_ID || '');
  const projectId = safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_PROJECT_ID || '');
  if (!requestId) throw new Error('request_id_empty');
  if (!projectId) throw new Error('project_id_empty');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSupervisor && !proto?.HubRuntime) throw new Error('hub_supervisor_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = proto?.HubRuntime ? new proto.HubRuntime(addr, creds, options) : null;
  const supervisorClient = (() => {
    if (runtimeClient && typeof runtimeClient.ResolveSupervisorRoute === 'function') return runtimeClient;
    if (proto?.HubSupervisor) return new proto.HubSupervisor(addr, creds, options);
    throw new Error('hub_supervisor_missing');
  })();

  const preferredDeviceId = safe(
    process.env.XTERMINAL_SUPERVISOR_ROUTE_PREFERRED_DEVICE_ID || client.device_id || ''
  );
  const runId = safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_RUN_ID || '');
  const missionId = safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_MISSION_ID || '');
  const request = {
    request_id: requestId,
    client,
    require_xt: asBool(process.env.XTERMINAL_SUPERVISOR_ROUTE_REQUIRE_XT || '1', true),
    require_runner: asBool(process.env.XTERMINAL_SUPERVISOR_ROUTE_REQUIRE_RUNNER || '0', false),
    ingress: {
      schema_version: 'xhub.supervisor_surface_ingress.v1',
      ingress_id: requestId,
      request_id: requestId,
      surface_type: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_SURFACE_TYPE || 'xt_ui') || 'xt_ui',
      surface_instance_id: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_SURFACE_INSTANCE_ID || client.device_id || ''),
      actor_ref: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_ACTOR_REF || 'xt.route_diagnose'),
      project_id: projectId,
      run_id: runId,
      trust_level: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_TRUST_LEVEL || 'paired_surface') || 'paired_surface',
      normalized_intent_type: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_INTENT_TYPE || 'directive') || 'directive',
      raw_intent_ref: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_RAW_INTENT_REF || 'route_diagnose'),
      received_at_ms: Date.now(),
      audit_ref: '',
      conversation_id: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_CONVERSATION_ID || ''),
      thread_key: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_THREAD_KEY || ''),
      preferred_device_id: preferredDeviceId,
      mission_id: missionId,
      structured_action_ref: safe(process.env.XTERMINAL_SUPERVISOR_ROUTE_STRUCTURED_ACTION_REF || 'route_diagnose'),
    },
    preferred_device_id_override: preferredDeviceId,
  };

  const resp = await new Promise((resolve, reject) => {
    supervisorClient.ResolveSupervisorRoute(
      request,
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const route = resp?.route
    ? {
        schema_version: safe(resp.route?.schema_version || 'xhub.supervisor_route_decision.v1'),
        route_id: safe(resp.route?.route_id || ''),
        request_id: safe(resp.route?.request_id || ''),
        project_id: safe(resp.route?.project_id || ''),
        run_id: safe(resp.route?.run_id || ''),
        mission_id: safe(resp.route?.mission_id || ''),
        decision: safe(resp.route?.decision || ''),
        risk_tier: safe(resp.route?.risk_tier || ''),
        preferred_device_id: safe(resp.route?.preferred_device_id || ''),
        resolved_device_id: safe(resp.route?.resolved_device_id || ''),
        runner_id: safe(resp.route?.runner_id || ''),
        xt_online: resp.route?.xt_online === true,
        runner_required: resp.route?.runner_required === true,
        same_project_scope: resp.route?.same_project_scope === true,
        requires_grant: resp.route?.requires_grant === true,
        grant_scope: safe(resp.route?.grant_scope || ''),
        deny_code: safe(resp.route?.deny_code || ''),
        updated_at_ms: asMs(resp.route?.updated_at_ms || 0),
        audit_ref: safe(resp.route?.audit_ref || ''),
      }
    : null;

  const governanceRuntimeReadiness = route
    ? await buildGovernanceRuntimeReadiness({ route, request })
    : null;

  const denyCode = safe(resp?.deny_code || route?.deny_code || '');
  out({
    ok: resp?.ok === true,
    source: 'hub_supervisor_grpc',
    route,
    governance_runtime_readiness: governanceRuntimeReadiness,
    reason: denyCode || '',
    error_code: denyCode || '',
    error_message: denyCode || '',
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_supervisor_unimplemented'
    : (msg || 'remote_supervisor_route_decision_failed');
  out({
    ok: false,
    source: 'hub_supervisor_grpc',
    route: null,
    governance_runtime_readiness: null,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

}
