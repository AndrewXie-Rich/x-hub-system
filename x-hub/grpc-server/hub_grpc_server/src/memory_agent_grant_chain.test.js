import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import { uploadSkillPackage } from './skills_store.js';
import { nowMs } from './util.js';

const TEST_FILTER = String(process.env.TEST_FILTER || '').trim();

function run(name, fn) {
  if (TEST_FILTER && !name.includes(TEST_FILTER)) return;
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function withEnv(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv)) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_agent_grant_chain_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

function sha256Hex(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function writeTarHeader(name, size) {
  const header = Buffer.alloc(512, 0);
  const nm = Buffer.from(String(name || ''), 'utf8');
  if (nm.length > 100) throw new Error('test tar path too long');
  nm.copy(header, 0);
  header.write('0000777\0', 100, 8, 'ascii');
  header.write('0000000\0', 108, 8, 'ascii');
  header.write('0000000\0', 116, 8, 'ascii');
  const sizeOct = Number(size || 0).toString(8).padStart(11, '0');
  header.write(`${sizeOct}\0`, 124, 12, 'ascii');
  const mtimeOct = Math.floor(Date.now() / 1000).toString(8).padStart(11, '0');
  header.write(`${mtimeOct}\0`, 136, 12, 'ascii');
  header.fill(0x20, 148, 156);
  header[156] = '0'.charCodeAt(0);
  header.write('ustar\0', 257, 6, 'ascii');
  header.write('00', 263, 2, 'ascii');
  let sum = 0;
  for (let i = 0; i < 512; i += 1) sum += header[i];
  const chk = sum.toString(8).padStart(6, '0');
  header.write(chk, 148, 6, 'ascii');
  header[154] = 0;
  header[155] = 0x20;
  return header;
}

function buildTgz(filesByPath) {
  const entries = Object.entries(filesByPath || {});
  const chunks = [];
  for (const [name, body] of entries) {
    const data = Buffer.isBuffer(body) ? body : Buffer.from(String(body || ''), 'utf8');
    chunks.push(writeTarHeader(name, data.length));
    chunks.push(data);
    const pad = (512 - (data.length % 512)) % 512;
    if (pad > 0) chunks.push(Buffer.alloc(pad, 0));
  }
  chunks.push(Buffer.alloc(1024, 0));
  return zlib.gzipSync(Buffer.concat(chunks));
}

function writeSkillRevocations(runtimeBaseDir, { revokedSha = [] } = {}) {
  const dir = path.join(runtimeBaseDir, 'skills_store');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'revoked.json'),
    `${JSON.stringify({
      schema_version: 'xhub.skill_revocations.v1',
      updated_at_ms: Date.now(),
      revoked_sha256: revokedSha,
      revoked_skill_ids: [],
      revoked_publishers: [],
    }, null, 2)}\n`,
    'utf8'
  );
}

function uploadUnsignedLowRiskSkill(runtimeBaseDir, { skillId = 'skill.runner.demo', version = '1.0.0' } = {}) {
  const mainJs = Buffer.from('console.log("skill runner demo");\n', 'utf8');
  const pkg = buildTgz({
    'dist/main.js': mainJs,
  });
  const manifest = {
    schema_version: 'xhub.skill_manifest.v1',
    skill_id: String(skillId || ''),
    name: String(skillId || ''),
    version: String(version || ''),
    description: 'skill runner execute gate test package',
    entrypoint: {
      runtime: 'node',
      command: 'node',
      args: ['dist/main.js'],
    },
    capabilities_required: [],
    network_policy: { direct_network_forbidden: true },
    files: [
      { path: 'dist/main.js', sha256: sha256Hex(mainJs) },
    ],
    publisher: {
      publisher_id: 'developer.test',
      public_key_ed25519: 'base64:',
    },
  };
  return uploadSkillPackage(runtimeBaseDir, {
    packageBytes: pkg,
    manifestJson: JSON.stringify(manifest),
    sourceId: 'local:upload',
  });
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x42).toString('base64')}`;

function baseEnv(runtimeBaseDir, extra = {}) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    ...extra,
  };
}

function invokeHubMemoryUnary(impl, methodName, request) {
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

function makeClient(projectId = 'proj-acp-main') {
  return {
    device_id: 'dev-acp-1',
    user_id: 'user-acp-1',
    app_id: 'ax-terminal',
    project_id: projectId,
    session_id: 'sess-acp-1',
  };
}

function openSession(impl, client, requestId = 'agent-session-open-1', overrides = {}) {
  const opts = overrides && typeof overrides === 'object' ? overrides : {};
  return invokeHubMemoryUnary(impl, 'AgentSessionOpen', {
    request_id: requestId,
    client,
    agent_instance_id: String(opts.agent_instance_id || 'agent-codex-1'),
    agent_name: String(opts.agent_name || 'codex'),
    agent_version: String(opts.agent_version || 'gpt-5'),
    gateway_provider: String(opts.gateway_provider || 'codex'),
  });
}

function requestTool(impl, client, {
  request_id,
  session_id,
  agent_instance_id = 'agent-codex-1',
  tool_name,
  tool_args_hash,
  risk_tier = 'high',
  required_grant_scope = 'privileged',
  exec_argv = ['bash', '-lc', 'echo safe'],
  exec_cwd = process.cwd(),
} = {}) {
  return invokeHubMemoryUnary(impl, 'AgentToolRequest', {
    request_id,
    client,
    session_id,
    agent_instance_id,
    tool_name,
    tool_args_hash,
    risk_tier,
    required_grant_scope,
    exec_argv,
    exec_cwd,
  });
}

function grantDecision(impl, client, {
  request_id,
  session_id,
  tool_request_id,
  decision,
  ttl_ms = 60 * 1000,
  deny_code = '',
} = {}) {
  return invokeHubMemoryUnary(impl, 'AgentToolGrantDecision', {
    request_id,
    client,
    session_id,
    tool_request_id,
    decision,
    ttl_ms,
    approver_id: 'supervisor-1',
    note: 'manual decision',
    deny_code,
  });
}

function executeTool(impl, client, {
  request_id,
  session_id,
  tool_request_id,
  tool_name,
  tool_args_hash,
  grant_id = '',
  exec_argv = ['bash', '-lc', 'echo safe'],
  exec_cwd = process.cwd(),
} = {}) {
  return invokeHubMemoryUnary(impl, 'AgentToolExecute', {
    request_id,
    client,
    session_id,
    tool_request_id,
    tool_name,
    tool_args_hash,
    grant_id,
    exec_argv,
    exec_cwd,
  });
}

function assertAuditEvent(db, {
  device_id,
  user_id,
  request_id,
  event_type,
  error_code = null,
} = {}) {
  const row = db.listAuditEvents({
    device_id: String(device_id || ''),
    user_id: String(user_id || ''),
    request_id: String(request_id || ''),
  }).find((item) => String(item?.event_type || '') === String(event_type || ''));
  assert.ok(row, `expected audit event ${event_type} for request_id=${request_id}`);
  if (error_code != null) {
    assert.equal(String(row?.error_code || ''), String(error_code || ''));
  }
  return row;
}

function parseAuditExt(row) {
  try {
    return JSON.parse(String(row?.ext_json || '{}'));
  } catch {
    return {};
  }
}

function percentileMs(rows = [], p = 95) {
  const nums = Array.isArray(rows) ? rows.filter((v) => Number.isFinite(v) && v >= 0).map((v) => Number(v)) : [];
  if (nums.length <= 0) return 0;
  nums.sort((a, b) => a - b);
  const rank = Math.min(nums.length - 1, Math.max(0, Math.ceil((Math.max(1, Math.min(99, Number(p) || 95)) / 100) * nums.length) - 1));
  return nums[rank];
}

run('M3-W1-02/grant chain deny: grant_missing + token_expired + request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient();

      const opened = openSession(impl, client, 'sess-open-deny');
      assert.equal(opened.err, null);
      assert.equal(!!opened.res?.opened, true);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-deny-chain',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-args-a1',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      assert.equal(String(toolReq.res?.deny_code || ''), 'grant_pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const missingGrant = executeTool(impl, client, {
        request_id: 'exec-deny-missing',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-args-a1',
      });
      assert.equal(missingGrant.err, null);
      assert.equal(!!missingGrant.res?.executed, false);
      assert.equal(String(missingGrant.res?.deny_code || ''), 'grant_missing');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-deny-missing',
        event_type: 'agent.tool.executed',
        error_code: 'grant_missing',
      });

      const approved = grantDecision(impl, client, {
        request_id: 'grant-approve-expire',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approved.err, null);
      assert.equal(!!approved.res?.applied, true);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      db.db.prepare('UPDATE agent_tool_requests SET capability_token_expires_at_ms = ?, grant_expires_at_ms = ? WHERE tool_request_id = ?').run(
        nowMs() - 1,
        nowMs() - 1,
        toolRequestId
      );

      const expiredGrant = executeTool(impl, client, {
        request_id: 'exec-deny-expired',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-args-a1',
        grant_id: grantId,
      });
      assert.equal(expiredGrant.err, null);
      assert.equal(!!expiredGrant.res?.executed, false);
      assert.equal(String(expiredGrant.res?.deny_code || ''), 'token_expired');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-deny-expired',
        event_type: 'agent.tool.executed',
        error_code: 'token_expired',
      });

      const reApproved = grantDecision(impl, client, {
        request_id: 'grant-approve-fresh',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(reApproved.err, null);
      assert.equal(!!reApproved.res?.applied, true);
      const freshGrantId = String(reApproved.res?.grant_id || '');
      assert.ok(freshGrantId);

      const tampered = executeTool(impl, client, {
        request_id: 'exec-deny-tampered',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-args-tampered',
        grant_id: freshGrantId,
      });
      assert.equal(tampered.err, null);
      assert.equal(!!tampered.res?.executed, false);
      assert.equal(String(tampered.res?.deny_code || ''), 'request_tampered');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-deny-tampered',
        event_type: 'agent.tool.executed',
        error_code: 'request_tampered',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/risk classify fails closed on downgraded hint', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-risk-floor');

      const opened = openSession(impl, client, 'sess-open-risk-floor');
      assert.equal(opened.err, null);
      assert.equal(!!opened.res?.opened, true);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-risk-floor',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-risk-floor',
        risk_tier: 'low',
        required_grant_scope: 'privileged',
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.risk_tier || ''), 'high');
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      assert.equal(String(toolReq.res?.deny_code || ''), 'grant_pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);
      const requestedAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-risk-floor',
        event_type: 'agent.tool.requested',
      });
      const requestedExt = requestedAudit?.ext_json ? JSON.parse(String(requestedAudit.ext_json)) : {};
      assert.equal(String(requestedExt?.risk_tier || ''), 'high');
      assert.equal(String(requestedExt?.risk_tier_hint || ''), 'low');
      assert.equal(!!requestedExt?.risk_floor_applied, true);
      const pendingAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-risk-floor',
        event_type: 'grant.pending',
      });
      const pendingExt = pendingAudit?.ext_json ? JSON.parse(String(pendingAudit.ext_json)) : {};
      assert.equal(!!pendingExt?.risk_floor_applied, true);

      const missingGrant = executeTool(impl, client, {
        request_id: 'exec-risk-floor-missing-grant',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-risk-floor',
      });
      assert.equal(missingGrant.err, null);
      assert.equal(!!missingGrant.res?.executed, false);
      assert.equal(String(missingGrant.res?.deny_code || ''), 'grant_missing');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-risk-floor-missing-grant',
        event_type: 'agent.tool.executed',
        error_code: 'grant_missing',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/policy evaluates against canonical session project scope', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const sessionClient = makeClient('proj-acp-policy-scope');
      const noProjectClient = { ...sessionClient, project_id: '' };

      const opened = openSession(impl, sessionClient, 'sess-open-policy-scope');
      assert.equal(opened.err, null);
      assert.equal(!!opened.res?.opened, true);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      let capturedPolicyProjectId = '';
      db.evaluateAgentToolPolicy = (input = {}) => {
        capturedPolicyProjectId = String(input?.client?.project_id || '');
        return {
          decision: 'approve',
          deny_code: '',
          grant_ttl_ms: 2 * 60 * 1000,
        };
      };

      const toolReq = requestTool(impl, noProjectClient, {
        request_id: 'tool-req-policy-scope',
        session_id: sessionId,
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-policy-scope',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      assert.equal(capturedPolicyProjectId, sessionClient.project_id);
      assert.equal(!!toolReq.res?.accepted, true);
      const requestedAudit = assertAuditEvent(db, {
        device_id: sessionClient.device_id,
        user_id: sessionClient.user_id,
        request_id: 'tool-req-policy-scope',
        event_type: 'agent.tool.requested',
      });
      assert.equal(String(requestedAudit?.project_id || ''), sessionClient.project_id);
      const approvedAudit = assertAuditEvent(db, {
        device_id: sessionClient.device_id,
        user_id: sessionClient.user_id,
        request_id: 'tool-req-policy-scope',
        event_type: 'grant.approved',
      });
      assert.equal(String(approvedAudit?.project_id || ''), sessionClient.project_id);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/provider metadata persists through grant chain audit', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-provider-metadata');

      const opened = openSession(impl, client, 'sess-open-provider-metadata', {
        agent_instance_id: 'agent-gemini-1',
        agent_name: 'gemini',
        agent_version: '2.1',
        gateway_provider: 'gemini',
      });
      assert.equal(opened.err, null);
      assert.equal(!!opened.res?.opened, true);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);
      const sessionRow = db.getAgentSession({
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.ok(sessionRow);
      assert.equal(String(sessionRow?.gateway_provider || ''), 'gemini');

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-provider-metadata',
        session_id: sessionId,
        agent_instance_id: 'agent-gemini-1',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-provider-metadata',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      assert.equal(!!toolReq.res?.accepted, true);
      assert.equal(String(toolReq.res?.decision || ''), 'approve');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);
      const grantId = String(toolReq.res?.grant_id || '');
      assert.ok(grantId);
      const toolReqRow = db.getAgentToolRequest({
        tool_request_id: toolRequestId,
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.ok(toolReqRow);
      assert.equal(String(toolReqRow?.gateway_provider || ''), 'gemini');

      const requestedAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-provider-metadata',
        event_type: 'agent.tool.requested',
      });
      const requestedExt = requestedAudit?.ext_json ? JSON.parse(String(requestedAudit.ext_json)) : {};
      assert.equal(String(requestedExt?.gateway_provider || ''), 'gemini');
      const approvedAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-provider-metadata',
        event_type: 'grant.approved',
      });
      const approvedExt = approvedAudit?.ext_json ? JSON.parse(String(approvedAudit.ext_json)) : {};
      assert.equal(String(approvedExt?.gateway_provider || ''), 'gemini');

      const executed = executeTool(impl, client, {
        request_id: 'exec-provider-metadata',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-provider-metadata',
        grant_id: grantId,
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(executed.err, null);
      assert.equal(!!executed.res?.executed, true);
      const executedAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-provider-metadata',
        event_type: 'agent.tool.executed',
      });
      const executedExt = executedAudit?.ext_json ? JSON.parse(String(executedAudit.ext_json)) : {};
      assert.equal(String(executedExt?.gateway_provider || ''), 'gemini');
      const executionRow = db.getAgentToolExecutionByIdempotency({
        request_id: 'exec-provider-metadata',
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.ok(executionRow);
      assert.equal(String(executionRow?.gateway_provider || ''), 'gemini');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent replay with provider drift fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-provider-drift');

      const opened = openSession(impl, client, 'sess-open-provider-drift', {
        agent_instance_id: 'agent-codex-provider-drift',
        gateway_provider: 'codex',
      });
      assert.equal(opened.err, null);
      assert.equal(!!opened.res?.opened, true);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const first = requestTool(impl, client, {
        request_id: 'tool-req-provider-drift',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-provider-drift',
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-provider-drift',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo provider drift'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(first.err, null);
      assert.equal(!!first.res?.accepted, true);
      assert.equal(String(first.res?.decision || ''), 'pending');
      assert.equal(String(first.res?.deny_code || ''), 'grant_pending');
      const toolRequestId = String(first.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      db.db.prepare(
        'UPDATE agent_sessions SET gateway_provider = ?, updated_at_ms = ? WHERE session_id = ?'
      ).run('claude', nowMs(), sessionId);

      const replay = requestTool(impl, client, {
        request_id: 'tool-req-provider-drift',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-provider-drift',
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-provider-drift',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo provider drift'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.accepted, false);
      assert.equal(String(replay.res?.decision || ''), 'deny');
      assert.equal(String(replay.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(replay.res?.tool_request_id || ''), toolRequestId);

      const deniedAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-provider-drift',
        event_type: 'grant.denied',
        error_code: 'request_tampered',
      });
      const deniedExt = deniedAudit?.ext_json ? JSON.parse(String(deniedAudit.ext_json)) : {};
      assert.equal(String(deniedExt?.decision || ''), 'deny');
      assert.equal(String(deniedExt?.deny_code || ''), 'request_tampered');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent replay with provider dropped fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-provider-drop');

      const opened = openSession(impl, client, 'sess-open-provider-drop', {
        agent_instance_id: 'agent-codex-provider-drop',
        gateway_provider: 'codex',
      });
      assert.equal(opened.err, null);
      assert.equal(!!opened.res?.opened, true);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const first = requestTool(impl, client, {
        request_id: 'tool-req-provider-drop',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-provider-drop',
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-provider-drop',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo provider drop'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(first.err, null);
      assert.equal(!!first.res?.accepted, true);
      assert.equal(String(first.res?.decision || ''), 'pending');
      const toolRequestId = String(first.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      db.db.prepare(
        'UPDATE agent_sessions SET gateway_provider = ?, updated_at_ms = ? WHERE session_id = ?'
      ).run('', nowMs(), sessionId);

      const replay = requestTool(impl, client, {
        request_id: 'tool-req-provider-drop',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-provider-drop',
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-provider-drop',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo provider drop'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.accepted, false);
      assert.equal(String(replay.res?.decision || ''), 'deny');
      assert.equal(String(replay.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(replay.res?.tool_request_id || ''), toolRequestId);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-provider-drop',
        event_type: 'grant.denied',
        error_code: 'request_tampered',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent replay with required scope drift fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-scope-drift');

      const opened = openSession(impl, client, 'sess-open-scope-drift', {
        agent_instance_id: 'agent-codex-scope-drift',
        gateway_provider: 'codex',
      });
      assert.equal(opened.err, null);
      assert.equal(!!opened.res?.opened, true);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const first = requestTool(impl, client, {
        request_id: 'tool-req-scope-drift',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-scope-drift',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-scope-drift',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(first.err, null);
      assert.equal(!!first.res?.accepted, true);
      assert.equal(String(first.res?.decision || ''), 'approve');
      const toolRequestId = String(first.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const replay = requestTool(impl, client, {
        request_id: 'tool-req-scope-drift',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-scope-drift',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-scope-drift',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.accepted, false);
      assert.equal(String(replay.res?.decision || ''), 'deny');
      assert.equal(String(replay.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(replay.res?.tool_request_id || ''), toolRequestId);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-scope-drift',
        event_type: 'grant.denied',
        error_code: 'request_tampered',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent replay with risk tier drift fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-risk-drift');

      const opened = openSession(impl, client, 'sess-open-risk-drift', {
        agent_instance_id: 'agent-codex-risk-drift',
        gateway_provider: 'codex',
      });
      assert.equal(opened.err, null);
      assert.equal(!!opened.res?.opened, true);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const first = requestTool(impl, client, {
        request_id: 'tool-req-risk-drift',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-risk-drift',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-risk-drift',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(first.err, null);
      assert.equal(!!first.res?.accepted, true);
      assert.equal(String(first.res?.decision || ''), 'approve');
      const toolRequestId = String(first.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const replay = requestTool(impl, client, {
        request_id: 'tool-req-risk-drift',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-risk-drift',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-risk-drift',
        risk_tier: 'high',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.accepted, false);
      assert.equal(String(replay.res?.decision || ''), 'deny');
      assert.equal(String(replay.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(replay.res?.tool_request_id || ''), toolRequestId);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-risk-drift',
        event_type: 'grant.denied',
        error_code: 'request_tampered',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/legacy tool-request row without provider stays idempotent', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-provider-legacy-idem');

      const opened = openSession(impl, client, 'sess-open-provider-legacy-idem', {
        agent_instance_id: 'agent-codex-legacy',
        gateway_provider: 'codex',
      });
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const first = requestTool(impl, client, {
        request_id: 'tool-req-provider-legacy-idem',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-legacy',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-provider-legacy-idem',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(first.err, null);
      assert.equal(!!first.res?.accepted, true);
      assert.equal(String(first.res?.deny_code || ''), '');
      const toolRequestId = String(first.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      // Simulate pre-migration row where gateway_provider is not yet backfilled.
      db.db.prepare(
        'UPDATE agent_tool_requests SET gateway_provider = NULL WHERE tool_request_id = ?'
      ).run(toolRequestId);

      const replay = requestTool(impl, client, {
        request_id: 'tool-req-provider-legacy-idem',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-legacy',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-provider-legacy-idem',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.accepted, true);
      assert.equal(String(replay.res?.deny_code || ''), '');
      assert.equal(String(replay.res?.tool_request_id || ''), toolRequestId);
      const replayedRow = db.getAgentToolRequest({
        tool_request_id: toolRequestId,
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.ok(replayedRow);
      assert.equal(String(replayedRow?.gateway_provider || ''), 'codex');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/legacy tool-request row without risk tier stays idempotent', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-risk-legacy-idem');

      const opened = openSession(impl, client, 'sess-open-risk-legacy-idem', {
        agent_instance_id: 'agent-codex-risk-legacy',
        gateway_provider: 'codex',
      });
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const first = requestTool(impl, client, {
        request_id: 'tool-req-risk-legacy-idem',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-risk-legacy',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-risk-legacy-idem',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(first.err, null);
      assert.equal(!!first.res?.accepted, true);
      assert.equal(String(first.res?.deny_code || ''), '');
      const toolRequestId = String(first.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      // Simulate pre-migration row where risk_tier is empty.
      db.db.prepare(
        'UPDATE agent_tool_requests SET risk_tier = ? WHERE tool_request_id = ?'
      ).run('', toolRequestId);

      const replay = requestTool(impl, client, {
        request_id: 'tool-req-risk-legacy-idem',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-risk-legacy',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-risk-legacy-idem',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.accepted, true);
      assert.equal(String(replay.res?.deny_code || ''), '');
      assert.equal(String(replay.res?.tool_request_id || ''), toolRequestId);

      const replayedRow = db.getAgentToolRequest({
        tool_request_id: toolRequestId,
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.ok(replayedRow);
      assert.equal(String(replayedRow?.risk_tier || ''), 'low');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/legacy tool-request row without required scope stays idempotent', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-scope-legacy-idem');

      const opened = openSession(impl, client, 'sess-open-scope-legacy-idem', {
        agent_instance_id: 'agent-codex-scope-legacy',
        gateway_provider: 'codex',
      });
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const first = requestTool(impl, client, {
        request_id: 'tool-req-scope-legacy-idem',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-scope-legacy',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-scope-legacy-idem',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(first.err, null);
      assert.equal(!!first.res?.accepted, true);
      assert.equal(String(first.res?.deny_code || ''), '');
      const toolRequestId = String(first.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      // Simulate pre-migration row where required_grant_scope is empty.
      db.db.prepare(
        'UPDATE agent_tool_requests SET required_grant_scope = ? WHERE tool_request_id = ?'
      ).run('', toolRequestId);

      const replay = requestTool(impl, client, {
        request_id: 'tool-req-scope-legacy-idem',
        session_id: sessionId,
        agent_instance_id: 'agent-codex-scope-legacy',
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-scope-legacy-idem',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
        exec_argv: ['bash', '-lc', 'cat README.md'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.accepted, true);
      assert.equal(String(replay.res?.deny_code || ''), '');
      assert.equal(String(replay.res?.tool_request_id || ''), toolRequestId);

      const replayedRow = db.getAgentToolRequest({
        tool_request_id: toolRequestId,
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.ok(replayedRow);
      assert.equal(String(replayedRow?.required_grant_scope || ''), 'readonly');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/approve then deny revokes grant and blocks execute', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-approve-deny-revoke');

      const opened = openSession(impl, client, 'sess-open-approve-deny-revoke');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-approve-deny-revoke',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-approve-deny-revoke',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approve = grantDecision(impl, client, {
        request_id: 'grant-approve-revoke',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approve.err, null);
      assert.equal(!!approve.res?.applied, true);
      assert.equal(String(approve.res?.decision || ''), 'approve');
      const approvedGrantId = String(approve.res?.grant_id || '');
      assert.ok(approvedGrantId);

      const deny = grantDecision(impl, client, {
        request_id: 'grant-deny-revoke',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'deny',
        deny_code: 'awaiting_instruction',
      });
      assert.equal(deny.err, null);
      assert.equal(!!deny.res?.applied, true);
      assert.equal(String(deny.res?.decision || ''), 'deny');
      assert.equal(String(deny.res?.deny_code || ''), 'awaiting_instruction');
      assert.equal(String(deny.res?.grant_id || ''), '');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'grant-deny-revoke',
        event_type: 'grant.denied',
        error_code: 'awaiting_instruction',
      });
      const deniedToolReq = db.getAgentToolRequest({
        tool_request_id: toolRequestId,
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.ok(deniedToolReq);
      assert.equal(String(deniedToolReq?.grant_id || ''), '');
      assert.equal(Math.max(0, Number(deniedToolReq?.grant_expires_at_ms || 0)), 0);

      const out = executeTool(impl, client, {
        request_id: 'exec-approve-deny-revoke',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-approve-deny-revoke',
        grant_id: approvedGrantId,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, false);
      assert.equal(String(out.res?.deny_code || ''), 'awaiting_instruction');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-approve-deny-revoke',
        event_type: 'agent.tool.executed',
        error_code: 'awaiting_instruction',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/deny+downgrade idempotent decisions stay fail-closed', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-idempotent-deny-downgrade');

      const opened = openSession(impl, client, 'sess-open-idem-deny-downgrade');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const deniedReq = requestTool(impl, client, {
        request_id: 'tool-req-idem-deny',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-idem-deny',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
      });
      assert.equal(deniedReq.err, null);
      const deniedToolRequestId = String(deniedReq.res?.tool_request_id || '');
      assert.ok(deniedToolRequestId);

      const deny1 = grantDecision(impl, client, {
        request_id: 'grant-idem-deny-1',
        session_id: sessionId,
        tool_request_id: deniedToolRequestId,
        decision: 'deny',
        deny_code: 'awaiting_instruction',
      });
      assert.equal(deny1.err, null);
      assert.equal(!!deny1.res?.applied, true);
      assert.equal(!!deny1.res?.idempotent, false);
      assert.equal(String(deny1.res?.deny_code || ''), 'awaiting_instruction');

      const deny2 = grantDecision(impl, client, {
        request_id: 'grant-idem-deny-2',
        session_id: sessionId,
        tool_request_id: deniedToolRequestId,
        decision: 'deny',
        deny_code: 'awaiting_instruction',
      });
      assert.equal(deny2.err, null);
      assert.equal(!!deny2.res?.applied, true);
      assert.equal(!!deny2.res?.idempotent, true);
      assert.equal(String(deny2.res?.deny_code || ''), 'awaiting_instruction');

      const deniedExec = executeTool(impl, client, {
        request_id: 'exec-idem-deny',
        session_id: sessionId,
        tool_request_id: deniedToolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-idem-deny',
      });
      assert.equal(deniedExec.err, null);
      assert.equal(!!deniedExec.res?.executed, false);
      assert.equal(String(deniedExec.res?.deny_code || ''), 'awaiting_instruction');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-idem-deny',
        event_type: 'agent.tool.executed',
        error_code: 'awaiting_instruction',
      });

      const downgradedReq = requestTool(impl, client, {
        request_id: 'tool-req-idem-downgrade',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-idem-downgrade',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
      });
      assert.equal(downgradedReq.err, null);
      const downgradedToolRequestId = String(downgradedReq.res?.tool_request_id || '');
      assert.ok(downgradedToolRequestId);

      const downgrade1 = grantDecision(impl, client, {
        request_id: 'grant-idem-downgrade-1',
        session_id: sessionId,
        tool_request_id: downgradedToolRequestId,
        decision: 'downgrade',
      });
      assert.equal(downgrade1.err, null);
      assert.equal(!!downgrade1.res?.applied, true);
      assert.equal(!!downgrade1.res?.idempotent, false);
      assert.equal(String(downgrade1.res?.deny_code || ''), 'downgrade_to_local');

      const downgrade2 = grantDecision(impl, client, {
        request_id: 'grant-idem-downgrade-2',
        session_id: sessionId,
        tool_request_id: downgradedToolRequestId,
        decision: 'downgrade',
      });
      assert.equal(downgrade2.err, null);
      assert.equal(!!downgrade2.res?.applied, true);
      assert.equal(!!downgrade2.res?.idempotent, true);
      assert.equal(String(downgrade2.res?.deny_code || ''), 'downgrade_to_local');

      const downgradedExec = executeTool(impl, client, {
        request_id: 'exec-idem-downgrade',
        session_id: sessionId,
        tool_request_id: downgradedToolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-idem-downgrade',
      });
      assert.equal(downgradedExec.err, null);
      assert.equal(!!downgradedExec.res?.executed, false);
      assert.equal(String(downgradedExec.res?.deny_code || ''), 'downgrade_to_local');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-idem-downgrade',
        event_type: 'agent.tool.executed',
        error_code: 'downgrade_to_local',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/kpi snapshot: gate p95 + low-risk false block + bypass rate', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-kpi-snapshot');

      const opened = openSession(impl, client, 'sess-open-kpi');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const lowRiskDurationsMs = [];
      const lowRiskRuns = 80;
      let lowRiskBlocked = 0;
      for (let i = 0; i < lowRiskRuns; i += 1) {
        const startedAt = process.hrtime.bigint();
        const out = requestTool(impl, client, {
          request_id: `tool-req-kpi-low-${i}`,
          session_id: sessionId,
          tool_name: 'terminal.read',
          tool_args_hash: `hash-kpi-low-${i}`,
          risk_tier: 'low',
          required_grant_scope: 'readonly',
          exec_argv: ['bash', '-lc', 'cat README.md'],
          exec_cwd: runtimeBaseDir,
        });
        const elapsedMs = Number(process.hrtime.bigint() - startedAt) / 1e6;
        lowRiskDurationsMs.push(elapsedMs);
        assert.equal(out.err, null);
        if (!out.res?.accepted || String(out.res?.decision || '') !== 'approve') {
          lowRiskBlocked += 1;
        }
      }

      const highRiskRuns = 24;
      let bypassGrantExecution = 0;
      for (let i = 0; i < highRiskRuns; i += 1) {
        const req = requestTool(impl, client, {
          request_id: `tool-req-kpi-high-${i}`,
          session_id: sessionId,
          tool_name: 'terminal.exec',
          tool_args_hash: `hash-kpi-high-${i}`,
          risk_tier: 'high',
          required_grant_scope: 'privileged',
        });
        assert.equal(req.err, null);
        assert.equal(String(req.res?.decision || ''), 'pending');
        const toolRequestId = String(req.res?.tool_request_id || '');
        assert.ok(toolRequestId);
        const out = executeTool(impl, client, {
          request_id: `exec-kpi-high-${i}`,
          session_id: sessionId,
          tool_request_id: toolRequestId,
          tool_name: 'terminal.exec',
          tool_args_hash: `hash-kpi-high-${i}`,
          grant_id: '',
        });
        assert.equal(out.err, null);
        if (out.res?.executed) {
          bypassGrantExecution += 1;
        }
      }

      const gateP95Ms = percentileMs(lowRiskDurationsMs, 95);
      const lowRiskFalseBlockRate = lowRiskBlocked / lowRiskRuns;
      assert.ok(gateP95Ms <= 35, `expected gate p95 <= 35ms, got ${gateP95Ms.toFixed(3)}ms`);
      assert.ok(lowRiskFalseBlockRate < 0.03, `expected low-risk false block rate < 3%, got ${(lowRiskFalseBlockRate * 100).toFixed(2)}%`);
      assert.equal(bypassGrantExecution, 0);

      process.stdout.write(
        `diag - M3-W1-02 KPI gate_p95_ms=${gateP95Ms.toFixed(3)} low_risk_false_block_rate=${(lowRiskFalseBlockRate * 100).toFixed(2)}% bypass_grant_execution=${bypassGrantExecution}\n`
      );
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/session_open runtime_error fail-closed', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-session-open-runtime');

      const originalOpenAgentSession = db.openAgentSession.bind(db);
      db.openAgentSession = () => {
        throw new Error('simulated session open runtime_error');
      };
      try {
        const opened = openSession(impl, client, 'sess-open-runtime-error');
        assert.equal(opened.err, null);
        assert.equal(!!opened.res?.opened, false);
        assert.equal(String(opened.res?.session_id || ''), '');
        assert.equal(String(opened.res?.deny_code || ''), 'runtime_error');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'sess-open-runtime-error',
          event_type: 'agent.session.denied',
          error_code: 'runtime_error',
        });
      } finally {
        db.openAgentSession = originalOpenAgentSession;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent approve + execute success', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-idem');

      const opened = openSession(impl, client, 'sess-open-idem');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-idem',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-args-idem',
        risk_tier: 'high',
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      assert.equal(String(toolReq.res?.deny_code || ''), 'grant_pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approve1 = grantDecision(impl, client, {
        request_id: 'grant-idem-1',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approve1.err, null);
      assert.equal(!!approve1.res?.applied, true);
      assert.equal(!!approve1.res?.idempotent, false);
      const grantId = String(approve1.res?.grant_id || '');
      assert.ok(grantId);

      const approve2 = grantDecision(impl, client, {
        request_id: 'grant-idem-2',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approve2.err, null);
      assert.equal(!!approve2.res?.applied, true);
      assert.equal(!!approve2.res?.idempotent, true);
      assert.equal(String(approve2.res?.grant_id || ''), grantId);

      const execute = executeTool(impl, client, {
        request_id: 'exec-success-idem',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-args-idem',
        grant_id: grantId,
      });
      assert.equal(execute.err, null);
      assert.equal(!!execute.res?.executed, true);
      assert.equal(String(execute.res?.deny_code || ''), '');
      assert.ok(String(execute.res?.execution_id || ''));
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-success-idem',
        event_type: 'agent.tool.executed',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});


run('SI-W1-02/one-time capability token contract enforces single use + token_expired + revoked audit', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-si-w1-02-capability-token');

      const opened = openSession(impl, client, 'sess-open-si-w1-02-capability-token');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-si-w1-02-single-use',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-si-w1-02-single-use',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approve = grantDecision(impl, client, {
        request_id: 'grant-si-w1-02-single-use',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approve.err, null);
      const tokenId = String(approve.res?.grant_id || '');
      assert.ok(tokenId);

      const approvedRow = db.getAgentToolRequest({
        tool_request_id: toolRequestId,
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.equal(String(approvedRow?.capability_token_kind || ''), 'one_time');
      assert.equal(String(approvedRow?.capability_token_id || ''), tokenId);
      assert.ok(String(approvedRow?.capability_token_nonce || ''));
      assert.equal(String(approvedRow?.capability_token_state || ''), 'issued');

      const firstExec = executeTool(impl, client, {
        request_id: 'exec-si-w1-02-first',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-si-w1-02-single-use',
        grant_id: tokenId,
      });
      assert.equal(firstExec.err, null);
      assert.equal(!!firstExec.res?.executed, true);

      const afterFirst = db.getAgentToolRequest({
        tool_request_id: toolRequestId,
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.equal(String(afterFirst?.capability_token_state || ''), 'consumed');
      assert.equal(String(afterFirst?.capability_token_bound_request_id || ''), 'exec-si-w1-02-first');
      assert.equal(String(afterFirst?.grant_id || ''), '');

      const secondExec = executeTool(impl, client, {
        request_id: 'exec-si-w1-02-second',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-si-w1-02-single-use',
        grant_id: tokenId,
      });
      assert.equal(secondExec.err, null);
      assert.equal(!!secondExec.res?.executed, false);
      assert.equal(String(secondExec.res?.deny_code || ''), 'token_consumed');
      const secondAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-si-w1-02-second',
        event_type: 'agent.tool.executed',
        error_code: 'token_consumed',
      });
      const secondExt = parseAuditExt(secondAudit);
      assert.equal(String(secondExt?.capability_token?.contract || ''), 'one_time');
      assert.equal(String(secondExt?.capability_token?.state || ''), 'consumed');
      assert.equal(String(secondExt?.capability_token?.bound_request_id || ''), 'exec-si-w1-02-first');

      const expiredReq = requestTool(impl, client, {
        request_id: 'tool-req-si-w1-02-expired',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-si-w1-02-expired',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
      });
      assert.equal(expiredReq.err, null);
      const expiredToolRequestId = String(expiredReq.res?.tool_request_id || '');
      const expiredApprove = grantDecision(impl, client, {
        request_id: 'grant-si-w1-02-expired',
        session_id: sessionId,
        tool_request_id: expiredToolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(expiredApprove.err, null);
      const expiredTokenId = String(expiredApprove.res?.grant_id || '');
      db.db.prepare(
        'UPDATE agent_tool_requests SET capability_token_expires_at_ms = ?, grant_expires_at_ms = ? WHERE tool_request_id = ?'
      ).run(Date.now() - 1000, Date.now() - 1000, expiredToolRequestId);
      const expiredExec = executeTool(impl, client, {
        request_id: 'exec-si-w1-02-expired',
        session_id: sessionId,
        tool_request_id: expiredToolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-si-w1-02-expired',
        grant_id: expiredTokenId,
      });
      assert.equal(expiredExec.err, null);
      assert.equal(!!expiredExec.res?.executed, false);
      assert.equal(String(expiredExec.res?.deny_code || ''), 'token_expired');
      const expiredAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-si-w1-02-expired',
        event_type: 'agent.tool.executed',
        error_code: 'token_expired',
      });
      const expiredExt = parseAuditExt(expiredAudit);
      assert.equal(String(expiredExt?.capability_token?.state || ''), 'expired');
      assert.equal(String(expiredExt?.capability_token?.contract || ''), 'one_time');

      const revokedReq = requestTool(impl, client, {
        request_id: 'tool-req-si-w1-02-revoked',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-si-w1-02-revoked',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
      });
      assert.equal(revokedReq.err, null);
      const revokedToolRequestId = String(revokedReq.res?.tool_request_id || '');
      const revokedApprove = grantDecision(impl, client, {
        request_id: 'grant-si-w1-02-revoked',
        session_id: sessionId,
        tool_request_id: revokedToolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(revokedApprove.err, null);
      const revokedTokenId = String(revokedApprove.res?.grant_id || '');
      const revokedDeny = grantDecision(impl, client, {
        request_id: 'grant-si-w1-02-revoked-deny',
        session_id: sessionId,
        tool_request_id: revokedToolRequestId,
        decision: 'deny',
        deny_code: 'awaiting_instruction',
      });
      assert.equal(revokedDeny.err, null);
      assert.equal(String(revokedDeny.res?.deny_code || ''), 'awaiting_instruction');
      const revokedExec = executeTool(impl, client, {
        request_id: 'exec-si-w1-02-revoked',
        session_id: sessionId,
        tool_request_id: revokedToolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-si-w1-02-revoked',
        grant_id: revokedTokenId,
      });
      assert.equal(revokedExec.err, null);
      assert.equal(!!revokedExec.res?.executed, false);
      assert.equal(String(revokedExec.res?.deny_code || ''), 'awaiting_instruction');
      const revokedRow = db.getAgentToolRequest({
        tool_request_id: revokedToolRequestId,
        session_id: sessionId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
      });
      assert.equal(String(revokedRow?.capability_token_state || ''), 'revoked');
      assert.equal(String(revokedRow?.capability_token_revoke_reason || ''), 'awaiting_instruction');
      const revokedAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-si-w1-02-revoked',
        event_type: 'agent.tool.executed',
        error_code: 'awaiting_instruction',
      });
      const revokedExt = parseAuditExt(revokedAudit);
      assert.equal(String(revokedExt?.capability_token?.contract || ''), 'one_time');
      assert.equal(String(revokedExt?.capability_token?.state || ''), 'revoked');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent execute replay tamper fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-exec-replay-tamper');

      const opened = openSession(impl, client, 'sess-open-exec-replay-tamper');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-exec-replay-tamper',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-tamper',
        risk_tier: 'high',
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approve = grantDecision(impl, client, {
        request_id: 'grant-exec-replay-tamper',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approve.err, null);
      assert.equal(!!approve.res?.applied, true);
      const grantId = String(approve.res?.grant_id || '');
      assert.ok(grantId);

      const firstExec = executeTool(impl, client, {
        request_id: 'exec-replay-tamper',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-tamper',
        grant_id: grantId,
      });
      assert.equal(firstExec.err, null);
      assert.equal(!!firstExec.res?.executed, true);
      assert.equal(!!firstExec.res?.idempotent, false);
      const executionId = String(firstExec.res?.execution_id || '');
      assert.ok(executionId);

      const tamperedReplay = executeTool(impl, client, {
        request_id: 'exec-replay-tamper',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-tamper-mutated',
        grant_id: grantId,
      });
      assert.equal(tamperedReplay.err, null);
      assert.equal(!!tamperedReplay.res?.executed, false);
      assert.equal(!!tamperedReplay.res?.idempotent, false);
      assert.equal(String(tamperedReplay.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(tamperedReplay.res?.execution_id || ''), executionId);

      const replayAudit = db.listAuditEvents({
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-replay-tamper',
      }).find((item) => String(item?.event_type || '') === 'agent.tool.executed' && String(item?.error_code || '') === 'request_tampered');
      assert.ok(replayAudit, 'expected replay tamper deny audit for execute idempotency');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent execute replay with grant drift fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-exec-replay-grant-drift');

      const opened = openSession(impl, client, 'sess-open-exec-replay-grant-drift');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-exec-replay-grant-drift',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-grant-drift',
        risk_tier: 'high',
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approve = grantDecision(impl, client, {
        request_id: 'grant-exec-replay-grant-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approve.err, null);
      assert.equal(!!approve.res?.applied, true);
      const grantId = String(approve.res?.grant_id || '');
      assert.ok(grantId);

      const firstExec = executeTool(impl, client, {
        request_id: 'exec-replay-grant-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-grant-drift',
        grant_id: grantId,
      });
      assert.equal(firstExec.err, null);
      assert.equal(!!firstExec.res?.executed, true);
      assert.equal(!!firstExec.res?.idempotent, false);
      const executionId = String(firstExec.res?.execution_id || '');
      assert.ok(executionId);

      const replayWithoutGrant = executeTool(impl, client, {
        request_id: 'exec-replay-grant-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-grant-drift',
        grant_id: '',
      });
      assert.equal(replayWithoutGrant.err, null);
      assert.equal(!!replayWithoutGrant.res?.executed, false);
      assert.equal(!!replayWithoutGrant.res?.idempotent, false);
      assert.equal(String(replayWithoutGrant.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(replayWithoutGrant.res?.execution_id || ''), executionId);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-replay-grant-drift',
        event_type: 'agent.tool.executed',
        error_code: 'request_tampered',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent execute replay with argv drift fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-exec-replay-argv-drift');

      const opened = openSession(impl, client, 'sess-open-exec-replay-argv-drift');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-exec-replay-argv-drift',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-argv-drift',
        risk_tier: 'high',
        exec_argv: ['bash', '-lc', 'echo stable'],
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approve = grantDecision(impl, client, {
        request_id: 'grant-exec-replay-argv-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approve.err, null);
      assert.equal(!!approve.res?.applied, true);
      const grantId = String(approve.res?.grant_id || '');
      assert.ok(grantId);

      const firstExec = executeTool(impl, client, {
        request_id: 'exec-replay-argv-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-argv-drift',
        grant_id: grantId,
        exec_argv: ['bash', '-lc', 'echo stable'],
      });
      assert.equal(firstExec.err, null);
      assert.equal(!!firstExec.res?.executed, true);
      assert.equal(!!firstExec.res?.idempotent, false);
      const executionId = String(firstExec.res?.execution_id || '');
      assert.ok(executionId);

      const replayWithArgvDrift = executeTool(impl, client, {
        request_id: 'exec-replay-argv-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-argv-drift',
        grant_id: grantId,
        exec_argv: ['bash', '-lc', 'echo drifted'],
      });
      assert.equal(replayWithArgvDrift.err, null);
      assert.equal(!!replayWithArgvDrift.res?.executed, false);
      assert.equal(!!replayWithArgvDrift.res?.idempotent, false);
      assert.equal(String(replayWithArgvDrift.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(replayWithArgvDrift.res?.execution_id || ''), executionId);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-replay-argv-drift',
        event_type: 'agent.tool.executed',
        error_code: 'request_tampered',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent execute replay with cwd drift fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const runtimeAltDir = makeTmp('runtime_alt');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  fs.mkdirSync(runtimeAltDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-exec-replay-cwd-drift');

      const opened = openSession(impl, client, 'sess-open-exec-replay-cwd-drift');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-exec-replay-cwd-drift',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-cwd-drift',
        risk_tier: 'high',
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approve = grantDecision(impl, client, {
        request_id: 'grant-exec-replay-cwd-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approve.err, null);
      assert.equal(!!approve.res?.applied, true);
      const grantId = String(approve.res?.grant_id || '');
      assert.ok(grantId);

      const firstExec = executeTool(impl, client, {
        request_id: 'exec-replay-cwd-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-cwd-drift',
        grant_id: grantId,
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(firstExec.err, null);
      assert.equal(!!firstExec.res?.executed, true);
      assert.equal(!!firstExec.res?.idempotent, false);
      const executionId = String(firstExec.res?.execution_id || '');
      assert.ok(executionId);

      const replayWithCwdDrift = executeTool(impl, client, {
        request_id: 'exec-replay-cwd-drift',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-cwd-drift',
        grant_id: grantId,
        exec_cwd: runtimeAltDir,
      });
      assert.equal(replayWithCwdDrift.err, null);
      assert.equal(!!replayWithCwdDrift.res?.executed, false);
      assert.equal(!!replayWithCwdDrift.res?.idempotent, false);
      assert.equal(String(replayWithCwdDrift.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(replayWithCwdDrift.res?.execution_id || ''), executionId);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-replay-cwd-drift',
        event_type: 'agent.tool.executed',
        error_code: 'request_tampered',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
  try { fs.rmSync(runtimeAltDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/idempotent denied execute replay with late grant fails closed as request_tampered', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-exec-replay-late-grant');

      const opened = openSession(impl, client, 'sess-open-exec-replay-late-grant');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-exec-replay-late-grant',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-late-grant',
        risk_tier: 'high',
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const firstDenied = executeTool(impl, client, {
        request_id: 'exec-replay-late-grant',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-late-grant',
        grant_id: '',
      });
      assert.equal(firstDenied.err, null);
      assert.equal(!!firstDenied.res?.executed, false);
      assert.equal(!!firstDenied.res?.idempotent, false);
      assert.equal(String(firstDenied.res?.deny_code || ''), 'grant_missing');
      const executionId = String(firstDenied.res?.execution_id || '');
      assert.ok(executionId);

      const approve = grantDecision(impl, client, {
        request_id: 'grant-exec-replay-late-grant',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
        ttl_ms: 60 * 1000,
      });
      assert.equal(approve.err, null);
      assert.equal(!!approve.res?.applied, true);
      const grantId = String(approve.res?.grant_id || '');
      assert.ok(grantId);

      const replayAfterGrant = executeTool(impl, client, {
        request_id: 'exec-replay-late-grant',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-replay-late-grant',
        grant_id: grantId,
      });
      assert.equal(replayAfterGrant.err, null);
      assert.equal(!!replayAfterGrant.res?.executed, false);
      assert.equal(!!replayAfterGrant.res?.idempotent, false);
      assert.equal(String(replayAfterGrant.res?.deny_code || ''), 'request_tampered');
      assert.equal(String(replayAfterGrant.res?.execution_id || ''), executionId);

      const replayAudit = db.listAuditEvents({
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-replay-late-grant',
      }).find((item) => String(item?.event_type || '') === 'agent.tool.executed' && String(item?.error_code || '') === 'request_tampered');
      assert.ok(replayAudit, 'expected late-grant replay deny audit for execute idempotency');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/gateway fail-closed in AgentToolRequest', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-fail-closed');

      const opened = openSession(impl, client, 'sess-open-fail-closed');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const originalPolicyEval = db.evaluateAgentToolPolicy;
      db.evaluateAgentToolPolicy = () => {
        throw new Error('gateway down');
      };
      try {
        const out = requestTool(impl, client, {
          request_id: 'tool-req-fail-closed',
          session_id: sessionId,
          tool_name: 'terminal.read',
          tool_args_hash: 'hash-read-safe',
          risk_tier: 'low',
          required_grant_scope: 'readonly',
        });
        assert.equal(out.err, null);
        assert.equal(!!out.res?.accepted, false);
        assert.equal(String(out.res?.decision || ''), 'deny');
        assert.equal(String(out.res?.deny_code || ''), 'gateway_fail_closed');
        assert.equal(String(out.res?.grant_id || ''), '');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'tool-req-fail-closed',
          event_type: 'grant.denied',
          error_code: 'gateway_fail_closed',
        });
      } finally {
        db.evaluateAgentToolPolicy = originalPolicyEval;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/session binding lookup runtime_error stays fail-closed in AgentToolRequest', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-session-binding-fail');

      const opened = openSession(impl, client, 'sess-open-session-binding-fail');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const originalGetSession = db.getAgentSession.bind(db);
      db.getAgentSession = () => {
        throw new Error('simulated_session_binding_lookup_error');
      };
      try {
        const out = requestTool(impl, client, {
          request_id: 'tool-req-session-binding-fail',
          session_id: sessionId,
          tool_name: 'terminal.exec',
          tool_args_hash: 'hash-session-binding-fail',
          risk_tier: 'high',
          required_grant_scope: 'privileged',
          exec_argv: ['bash', '-lc', 'echo fail-closed'],
          exec_cwd: runtimeBaseDir,
        });
        assert.equal(out.err, null);
        assert.equal(!!out.res?.accepted, false);
        assert.equal(String(out.res?.decision || ''), 'deny');
        assert.equal(String(out.res?.deny_code || ''), 'runtime_error');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'tool-req-session-binding-fail',
          event_type: 'grant.denied',
          error_code: 'runtime_error',
        });
      } finally {
        db.getAgentSession = originalGetSession;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/session binding lookup runtime_error remains fail-closed when audit append fails', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-session-binding-audit-fail');

      const opened = openSession(impl, client, 'sess-open-session-binding-audit-fail');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const originalGetSession = db.getAgentSession.bind(db);
      const originalAppendAudit = db.appendAudit.bind(db);
      db.getAgentSession = () => {
        throw new Error('simulated_session_binding_lookup_error');
      };
      db.appendAudit = () => {
        throw new Error('simulated_audit_sink_failure');
      };
      try {
        const out = requestTool(impl, client, {
          request_id: 'tool-req-session-binding-audit-fail',
          session_id: sessionId,
          tool_name: 'terminal.exec',
          tool_args_hash: 'hash-session-binding-audit-fail',
          risk_tier: 'high',
          required_grant_scope: 'privileged',
          exec_argv: ['bash', '-lc', 'echo fail-closed'],
          exec_cwd: runtimeBaseDir,
        });
        assert.equal(out.err, null);
        assert.equal(!!out.res?.accepted, false);
        assert.equal(String(out.res?.decision || ''), 'deny');
        assert.equal(String(out.res?.deny_code || ''), 'runtime_error');
      } finally {
        db.getAgentSession = originalGetSession;
        db.appendAudit = originalAppendAudit;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/grant decision fail-closed: tool_request_not_found + runtime_error', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-grant-decision-fail-closed');

      const opened = openSession(impl, client, 'sess-open-grant-decision-fc');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const missingToolRequest = grantDecision(impl, client, {
        request_id: 'grant-missing-tool-request',
        session_id: sessionId,
        tool_request_id: 'atr_not_found',
        decision: 'approve',
      });
      assert.equal(missingToolRequest.err, null);
      assert.equal(!!missingToolRequest.res?.applied, false);
      assert.equal(!!missingToolRequest.res?.idempotent, false);
      assert.equal(String(missingToolRequest.res?.decision || ''), 'deny');
      assert.equal(String(missingToolRequest.res?.deny_code || ''), 'tool_request_not_found');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'grant-missing-tool-request',
        event_type: 'grant.denied',
        error_code: 'tool_request_not_found',
      });

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-grant-decision-runtime',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-grant-runtime',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const originalDecideGrant = db.decideAgentToolGrant.bind(db);
      db.decideAgentToolGrant = () => {
        throw new Error('simulated grant decision runtime_error');
      };
      try {
        const runtimeError = grantDecision(impl, client, {
          request_id: 'grant-runtime-error',
          session_id: sessionId,
          tool_request_id: toolRequestId,
          decision: 'approve',
          ttl_ms: 60 * 1000,
        });
        assert.equal(runtimeError.err, null);
        assert.equal(!!runtimeError.res?.applied, false);
        assert.equal(!!runtimeError.res?.idempotent, false);
        assert.equal(String(runtimeError.res?.decision || ''), 'deny');
        assert.equal(String(runtimeError.res?.deny_code || ''), 'runtime_error');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'grant-runtime-error',
          event_type: 'grant.denied',
          error_code: 'runtime_error',
        });
      } finally {
        db.decideAgentToolGrant = originalDecideGrant;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/invalid request remains fail-closed when audit append fails', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-invalid-audit');

      const opened = openSession(impl, client, 'sess-open-invalid-audit');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const originalAppendAudit = db.appendAudit.bind(db);
      db.appendAudit = () => {
        throw new Error('simulated_audit_sink_failure');
      };
      try {
        const out = requestTool(impl, client, {
          request_id: 'tool-req-invalid-audit',
          session_id: sessionId,
          tool_name: 'terminal.exec',
          tool_args_hash: '',
          risk_tier: 'high',
          required_grant_scope: 'privileged',
        });
        assert.equal(out.err, null);
        assert.equal(!!out.res?.accepted, false);
        assert.equal(String(out.res?.decision || ''), 'deny');
        assert.equal(String(out.res?.deny_code || ''), 'invalid_request');
        assert.equal(String(out.res?.tool_request_id || ''), '');
      } finally {
        db.appendAudit = originalAppendAudit;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/awaiting_instruction deny_code propagation', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-awaiting');

      const opened = openSession(impl, client, 'sess-open-awaiting');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-awaiting',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-args-awaiting',
        risk_tier: 'high',
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const denied = grantDecision(impl, client, {
        request_id: 'grant-deny-awaiting',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'deny',
        deny_code: 'awaiting_instruction',
      });
      assert.equal(denied.err, null);
      assert.equal(!!denied.res?.applied, true);
      assert.equal(String(denied.res?.deny_code || ''), 'awaiting_instruction');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'grant-deny-awaiting',
        event_type: 'grant.denied',
        error_code: 'awaiting_instruction',
      });

      const executeDenied = executeTool(impl, client, {
        request_id: 'exec-awaiting',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-args-awaiting',
      });
      assert.equal(executeDenied.err, null);
      assert.equal(!!executeDenied.res?.executed, false);
      assert.equal(String(executeDenied.res?.deny_code || ''), 'awaiting_instruction');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-awaiting',
        event_type: 'agent.tool.executed',
        error_code: 'awaiting_instruction',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/execute fail-closed: tool_request_not_found', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-exec-missing-tool-request');

      const opened = openSession(impl, client, 'sess-open-exec-missing');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const out = executeTool(impl, client, {
        request_id: 'exec-missing-tool-request',
        session_id: sessionId,
        tool_request_id: 'atr_not_found',
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-exec-missing',
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, false);
      assert.equal(String(out.res?.deny_code || ''), 'tool_request_not_found');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-missing-tool-request',
        event_type: 'agent.tool.executed',
        error_code: 'tool_request_not_found',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/runtime_error fail-closed in AgentToolExecute', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-runtime-error');

      const opened = openSession(impl, client, 'sess-open-runtime');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-runtime',
        session_id: sessionId,
        tool_name: 'terminal.read',
        tool_args_hash: 'hash-read-runtime',
        risk_tier: 'low',
        required_grant_scope: 'readonly',
      });
      assert.equal(toolReq.err, null);
      assert.equal(!!toolReq.res?.accepted, true);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const originalRecord = db.recordAgentToolExecution.bind(db);
      db.recordAgentToolExecution = () => {
        throw new Error('simulated runtime_error');
      };
      try {
        const out = executeTool(impl, client, {
          request_id: 'exec-runtime-error',
          session_id: sessionId,
          tool_request_id: toolRequestId,
          tool_name: 'terminal.read',
          tool_args_hash: 'hash-read-runtime',
          grant_id: String(toolReq.res?.grant_id || ''),
        });
        assert.equal(out.err, null);
        assert.equal(!!out.res?.executed, false);
        assert.equal(String(out.res?.deny_code || ''), 'runtime_error');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'exec-runtime-error',
          event_type: 'agent.tool.executed',
          error_code: 'runtime_error',
        });
      } finally {
        db.recordAgentToolExecution = originalRecord;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-02/execute invalid request remains fail-closed when audit append fails', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-exec-invalid-audit');

      const opened = openSession(impl, client, 'sess-open-exec-invalid-audit');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const originalAppendAudit = db.appendAudit.bind(db);
      db.appendAudit = () => {
        throw new Error('simulated_audit_sink_failure');
      };
      try {
        const out = executeTool(impl, client, {
          request_id: 'exec-invalid-audit',
          session_id: sessionId,
          tool_request_id: 'atr_missing',
          tool_name: 'terminal.exec',
          tool_args_hash: 'hash-exec-invalid-audit',
          grant_id: '',
          exec_argv: ['bash', '-lc', 'echo fail-closed'],
          exec_cwd: '.',
        });
        assert.equal(out.err, null);
        assert.equal(!!out.res?.executed, false);
        assert.equal(String(out.res?.deny_code || ''), 'approval_cwd_invalid');
      } finally {
        db.appendAudit = originalAppendAudit;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/approval binding rejects trailing-space argv replay', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-argv-replay');

      const opened = openSession(impl, client, 'sess-open-argv-replay');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const requestArgv = ['/usr/bin/env', 'bash', '-lc', 'echo safe'];
      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-argv-replay',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-argv-replay',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: requestArgv,
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approved = grantDecision(impl, client, {
        request_id: 'grant-argv-replay',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      const replay = executeTool(impl, client, {
        request_id: 'exec-argv-replay',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-argv-replay',
        grant_id: grantId,
        exec_argv: ['/usr/bin/env', 'bash', '-lc', 'echo safe '],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.executed, false);
      assert.equal(String(replay.res?.deny_code || ''), 'approval_argv_mismatch');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-argv-replay',
        event_type: 'agent.tool.executed',
        error_code: 'approval_argv_mismatch',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/approval binding rejects cwd symlink retarget replay', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-cwd-replay');

      const opened = openSession(impl, client, 'sess-open-cwd-replay');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const cwdRoot = makeTmp('cwd-root');
      const dirA = path.join(cwdRoot, 'a');
      const dirB = path.join(cwdRoot, 'b');
      const link = path.join(cwdRoot, 'workdir');
      fs.mkdirSync(dirA, { recursive: true });
      fs.mkdirSync(dirB, { recursive: true });
      fs.symlinkSync(dirA, link);
      try {
        const toolReq = requestTool(impl, client, {
          request_id: 'tool-req-cwd-replay',
          session_id: sessionId,
          tool_name: 'terminal.exec',
          tool_args_hash: 'hash-cwd-replay',
          risk_tier: 'high',
          required_grant_scope: 'privileged',
          exec_argv: ['bash', '-lc', 'pwd'],
          exec_cwd: link,
        });
        assert.equal(toolReq.err, null);
        const toolRequestId = String(toolReq.res?.tool_request_id || '');
        assert.ok(toolRequestId);

        const approved = grantDecision(impl, client, {
          request_id: 'grant-cwd-replay',
          session_id: sessionId,
          tool_request_id: toolRequestId,
          decision: 'approve',
        });
        assert.equal(approved.err, null);
        const grantId = String(approved.res?.grant_id || '');
        assert.ok(grantId);

        fs.rmSync(link, { force: true });
        fs.symlinkSync(dirB, link);

        const replay = executeTool(impl, client, {
          request_id: 'exec-cwd-replay',
          session_id: sessionId,
          tool_request_id: toolRequestId,
          tool_name: 'terminal.exec',
          tool_args_hash: 'hash-cwd-replay',
          grant_id: grantId,
          exec_argv: ['bash', '-lc', 'pwd'],
          exec_cwd: link,
        });
        assert.equal(replay.err, null);
        assert.equal(!!replay.res?.executed, false);
        assert.equal(String(replay.res?.deny_code || ''), 'approval_cwd_mismatch');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'exec-cwd-replay',
          event_type: 'agent.tool.executed',
          error_code: 'approval_cwd_mismatch',
        });
      } finally {
        try { fs.rmSync(cwdRoot, { recursive: true, force: true }); } catch { /* ignore */ }
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/pre-execution secondary validation fails closed on binding corruption', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-binding-corrupt');

      const opened = openSession(impl, client, 'sess-open-binding-corrupt');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-binding-corrupt',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-binding-corrupt',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo strict'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approved = grantDecision(impl, client, {
        request_id: 'grant-binding-corrupt',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      db.db.prepare(
        'UPDATE agent_tool_requests SET approval_identity_hash = ? WHERE tool_request_id = ?'
      ).run('tampered_hash', toolRequestId);

      const out = executeTool(impl, client, {
        request_id: 'exec-binding-corrupt',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-binding-corrupt',
        grant_id: grantId,
        exec_argv: ['bash', '-lc', 'echo strict'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, false);
      assert.equal(String(out.res?.deny_code || ''), 'approval_binding_corrupt');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-binding-corrupt',
        event_type: 'agent.tool.executed',
        error_code: 'approval_binding_corrupt',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/approval binding rejects relative cwd at request boundary', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-relative-cwd');

      const opened = openSession(impl, client, 'sess-open-relative-cwd');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const out = requestTool(impl, client, {
        request_id: 'tool-req-relative-cwd',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-relative-cwd',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'pwd'],
        exec_cwd: '.',
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.accepted, false);
      assert.equal(String(out.res?.deny_code || ''), 'approval_cwd_invalid');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-relative-cwd',
        event_type: 'grant.denied',
        error_code: 'approval_cwd_invalid',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/approval binding rejects non-string argv item at request boundary', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-argv-type');

      const opened = openSession(impl, client, 'sess-open-argv-type');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const out = requestTool(impl, client, {
        request_id: 'tool-req-argv-type',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-argv-type',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 42],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.accepted, false);
      assert.equal(String(out.res?.deny_code || ''), 'approval_binding_invalid');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'tool-req-argv-type',
        event_type: 'grant.denied',
        error_code: 'approval_binding_invalid',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/grant approve fails closed when stored approval binding missing', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-binding-missing-grant');

      const opened = openSession(impl, client, 'sess-open-binding-missing-grant');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-binding-missing-grant',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-binding-missing-grant',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo strict'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      db.db.prepare(
        'UPDATE agent_tool_requests SET approval_identity_hash = ? WHERE tool_request_id = ?'
      ).run('', toolRequestId);

      const out = grantDecision(impl, client, {
        request_id: 'grant-binding-missing-grant',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.applied, false);
      assert.equal(String(out.res?.decision || ''), 'deny');
      assert.equal(String(out.res?.deny_code || ''), 'approval_binding_missing');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'grant-binding-missing-grant',
        event_type: 'grant.denied',
        error_code: 'approval_binding_missing',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/pre-execution validation fails closed on missing stored binding', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-binding-missing-exec');

      const opened = openSession(impl, client, 'sess-open-binding-missing-exec');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-binding-missing-exec',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-binding-missing-exec',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo strict'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approved = grantDecision(impl, client, {
        request_id: 'grant-binding-missing-exec',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      db.db.prepare(
        'UPDATE agent_tool_requests SET approval_argv_json = ? WHERE tool_request_id = ?'
      ).run('', toolRequestId);

      const out = executeTool(impl, client, {
        request_id: 'exec-binding-missing-exec',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-binding-missing-exec',
        grant_id: grantId,
        exec_argv: ['bash', '-lc', 'echo strict'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, false);
      assert.equal(String(out.res?.deny_code || ''), 'approval_binding_missing');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-binding-missing-exec',
        event_type: 'agent.tool.executed',
        error_code: 'approval_binding_missing',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/approval binding rejects relative cwd at execute boundary', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-relative-cwd-exec');

      const opened = openSession(impl, client, 'sess-open-relative-cwd-exec');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-relative-cwd-exec',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-relative-cwd-exec',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'pwd'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approved = grantDecision(impl, client, {
        request_id: 'grant-relative-cwd-exec',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      const out = executeTool(impl, client, {
        request_id: 'exec-relative-cwd-exec',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-relative-cwd-exec',
        grant_id: grantId,
        exec_argv: ['bash', '-lc', 'pwd'],
        exec_cwd: '.',
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, false);
      assert.equal(String(out.res?.deny_code || ''), 'approval_cwd_invalid');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-relative-cwd-exec',
        event_type: 'agent.tool.executed',
        error_code: 'approval_cwd_invalid',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/approval binding rejects non-string argv item at execute boundary', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-argv-type-exec');

      const opened = openSession(impl, client, 'sess-open-argv-type-exec');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-argv-type-exec',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-argv-type-exec',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo ok'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approved = grantDecision(impl, client, {
        request_id: 'grant-argv-type-exec',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      const out = executeTool(impl, client, {
        request_id: 'exec-argv-type-exec',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-argv-type-exec',
        grant_id: grantId,
        exec_argv: ['bash', '-lc', 7],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, false);
      assert.equal(String(out.res?.deny_code || ''), 'approval_binding_invalid');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-argv-type-exec',
        event_type: 'agent.tool.executed',
        error_code: 'approval_binding_invalid',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/approval identity binds canonical session project scope', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const sessionClient = makeClient('proj-acp-canonical-session-scope');
      const noProjectClient = { ...sessionClient, project_id: '' };

      const opened = openSession(impl, sessionClient, 'sess-open-canonical-session-scope');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, noProjectClient, {
        request_id: 'tool-req-canonical-session-scope',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-canonical-session-scope',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo stable'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);
      const requestedAudit = assertAuditEvent(db, {
        device_id: sessionClient.device_id,
        user_id: sessionClient.user_id,
        request_id: 'tool-req-canonical-session-scope',
        event_type: 'agent.tool.requested',
      });
      assert.equal(String(requestedAudit?.project_id || ''), sessionClient.project_id);
      const pendingAudit = assertAuditEvent(db, {
        device_id: sessionClient.device_id,
        user_id: sessionClient.user_id,
        request_id: 'tool-req-canonical-session-scope',
        event_type: 'grant.pending',
      });
      assert.equal(String(pendingAudit?.project_id || ''), sessionClient.project_id);

      const approved = grantDecision(impl, noProjectClient, {
        request_id: 'grant-canonical-session-scope',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);
      const approvedAudit = assertAuditEvent(db, {
        device_id: sessionClient.device_id,
        user_id: sessionClient.user_id,
        request_id: 'grant-canonical-session-scope',
        event_type: 'grant.approved',
      });
      assert.equal(String(approvedAudit?.project_id || ''), sessionClient.project_id);

      const out = executeTool(impl, noProjectClient, {
        request_id: 'exec-canonical-session-scope',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-canonical-session-scope',
        grant_id: grantId,
        exec_argv: ['bash', '-lc', 'echo stable'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, true);
      assert.equal(String(out.res?.deny_code || ''), '');
      const executedAudit = assertAuditEvent(db, {
        device_id: sessionClient.device_id,
        user_id: sessionClient.user_id,
        request_id: 'exec-canonical-session-scope',
        event_type: 'agent.tool.executed',
      });
      assert.equal(String(executedAudit?.project_id || ''), sessionClient.project_id);
      const execRow = db.getAgentToolExecutionByIdempotency({
        request_id: 'exec-canonical-session-scope',
        session_id: sessionId,
        device_id: sessionClient.device_id,
        user_id: sessionClient.user_id,
        app_id: sessionClient.app_id,
      });
      assert.ok(execRow);
      assert.equal(String(execRow?.project_id || ''), sessionClient.project_id);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('CM-W3-19/approval identity mismatch emits deny audit', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-acp-identity-mismatch');

      const opened = openSession(impl, client, 'sess-open-identity-mismatch');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-identity-mismatch',
        session_id: sessionId,
        tool_name: 'terminal.exec',
        tool_args_hash: 'hash-identity-mismatch',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: ['bash', '-lc', 'echo identity'],
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approved = grantDecision(impl, client, {
        request_id: 'grant-identity-mismatch',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      const originalGetAgentToolRequest = db.getAgentToolRequest;
      db.getAgentToolRequest = function getAgentToolRequestWithIdentityDrift(fields) {
        const row = originalGetAgentToolRequest.call(this, fields);
        if (!row) return row;
        let projectIdReadCount = 0;
        return new Proxy(row, {
          get(target, prop, receiver) {
            if (prop === 'project_id') {
              projectIdReadCount += 1;
              const originalProjectId = String(Reflect.get(target, prop, receiver) || '');
              return projectIdReadCount >= 3 ? `${originalProjectId}::identity-drift` : originalProjectId;
            }
            return Reflect.get(target, prop, receiver);
          },
        });
      };

      try {
        const out = executeTool(impl, client, {
          request_id: 'exec-identity-mismatch',
          session_id: sessionId,
          tool_request_id: toolRequestId,
          tool_name: 'terminal.exec',
          tool_args_hash: 'hash-identity-mismatch',
          grant_id: grantId,
          exec_argv: ['bash', '-lc', 'echo identity'],
          exec_cwd: runtimeBaseDir,
        });
        assert.equal(out.err, null);
        assert.equal(!!out.res?.executed, false);
        assert.equal(String(out.res?.deny_code || ''), 'approval_identity_mismatch');
        const executedAudit = assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'exec-identity-mismatch',
          event_type: 'agent.tool.executed',
          error_code: 'approval_identity_mismatch',
        });
        const executedExt = JSON.parse(String(executedAudit?.ext_json || '{}'));
        assert.equal(String(executedExt.deny_code || ''), 'approval_identity_mismatch');
      } finally {
        db.getAgentToolRequest = originalGetAgentToolRequest;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('SKC-W1-04/runner execute chain enforces skill execution gate with revoked deny_code', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir, { HUB_SKILLS_DEVELOPER_MODE: 'true' }), () => {
    const db = new HubDB({ dbPath });
    try {
      const uploaded = uploadUnsignedLowRiskSkill(runtimeBaseDir, {
        skillId: 'skill.runner.revoked',
        version: '1.0.0',
      });
      const packageSha = String(uploaded?.package_sha256 || '');
      assert.equal(packageSha.length, 64);

      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-skill-runner-revoked');
      const execArgv = [
        'xt-skill-runner',
        '--package-sha256',
        packageSha,
        '--skill-id',
        'skill.runner.revoked',
      ];

      const opened = openSession(impl, client, 'sess-open-skill-runner-revoked');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-skill-runner-revoked',
        session_id: sessionId,
        tool_name: 'skills.execute.runner',
        tool_args_hash: 'hash-skill-runner-revoked',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: execArgv,
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      assert.equal(String(toolReq.res?.deny_code || ''), 'grant_pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approved = grantDecision(impl, client, {
        request_id: 'grant-skill-runner-revoked',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      writeSkillRevocations(runtimeBaseDir, { revokedSha: [packageSha] });

      const out = executeTool(impl, client, {
        request_id: 'exec-skill-runner-revoked',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'skills.execute.runner',
        tool_args_hash: 'hash-skill-runner-revoked',
        grant_id: grantId,
        exec_argv: execArgv,
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, false);
      assert.equal(String(out.res?.deny_code || ''), 'revoked');

      const execAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-skill-runner-revoked',
        event_type: 'agent.tool.executed',
        error_code: 'revoked',
      });
      const ext = JSON.parse(String(execAudit?.ext_json || '{}'));
      assert.equal(ext.skill_execution_gate_checked, true);
      assert.equal(String(ext?.skill_execution_gate?.deny_code || ''), 'revoked');
      const bindingPackage = ext?.skill_execution_gate_binding?.package_sha256;
      if (bindingPackage && typeof bindingPackage === 'object') {
        assert.equal(String(bindingPackage.type || ''), 'string');
        assert.equal(Number(bindingPackage.bytes || 0), 64);
      } else {
        assert.equal(String(bindingPackage || ''), packageSha);
      }
      const chainField = ext?.chain;
      if (chainField && typeof chainField === 'object') {
        assert.equal(String(chainField.type || ''), 'string');
        assert.ok(Number(chainField.bytes || 0) > 0);
      } else {
        assert.equal(String(chainField || ''), 'ingress->risk_classify->policy->grant->execute->audit');
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('SKC-W1-04/skills execute fail-closed when package sha binding is missing', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir, { HUB_SKILLS_DEVELOPER_MODE: 'true' }), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-skill-runner-missing-sha');
      const execArgv = ['xt-skill-runner', '--skill-id', 'skill.runner.no.sha'];

      const opened = openSession(impl, client, 'sess-open-skill-runner-missing-sha');
      assert.equal(opened.err, null);
      const sessionId = String(opened.res?.session_id || '');
      assert.ok(sessionId);

      const toolReq = requestTool(impl, client, {
        request_id: 'tool-req-skill-runner-missing-sha',
        session_id: sessionId,
        tool_name: 'skills.execute.runner',
        tool_args_hash: 'hash-skill-runner-missing-sha',
        risk_tier: 'high',
        required_grant_scope: 'privileged',
        exec_argv: execArgv,
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(toolReq.err, null);
      assert.equal(String(toolReq.res?.decision || ''), 'pending');
      const toolRequestId = String(toolReq.res?.tool_request_id || '');
      assert.ok(toolRequestId);

      const approved = grantDecision(impl, client, {
        request_id: 'grant-skill-runner-missing-sha',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        decision: 'approve',
      });
      assert.equal(approved.err, null);
      const grantId = String(approved.res?.grant_id || '');
      assert.ok(grantId);

      const out = executeTool(impl, client, {
        request_id: 'exec-skill-runner-missing-sha',
        session_id: sessionId,
        tool_request_id: toolRequestId,
        tool_name: 'skills.execute.runner',
        tool_args_hash: 'hash-skill-runner-missing-sha',
        grant_id: grantId,
        exec_argv: execArgv,
        exec_cwd: runtimeBaseDir,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.executed, false);
      assert.equal(String(out.res?.deny_code || ''), 'request_tampered');

      const execAudit = assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'exec-skill-runner-missing-sha',
        event_type: 'agent.tool.executed',
        error_code: 'request_tampered',
      });
      const ext = JSON.parse(String(execAudit?.ext_json || '{}'));
      assert.equal(ext.skill_execution_gate_checked, true);
      const gateDeny = ext?.skill_execution_gate?.deny_code;
      if (gateDeny && typeof gateDeny === 'object') {
        assert.equal(String(gateDeny.type || ''), 'string');
        assert.ok(Number(gateDeny.bytes || 0) > 0);
      } else {
        assert.equal(String(gateDeny || ''), 'missing_package_sha256');
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
