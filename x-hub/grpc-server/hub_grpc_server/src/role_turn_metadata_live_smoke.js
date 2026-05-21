import assert from 'node:assert/strict';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

import { HubDB } from './db.js';
import { resolveHubProtoPath } from './proto_path.js';

const SRC_DIR = path.dirname(fileURLToPath(import.meta.url));
const SERVER_ROOT = path.resolve(SRC_DIR, '..');
const REPO_ROOT = path.resolve(SRC_DIR, '..', '..', '..', '..');
const REPORTS_DIR = path.join(REPO_ROOT, 'build', 'reports');
const SCHEMA_VERSION = 'xhub.role_turn_metadata_live_smoke.v1';
const TURN_METADATA_SCHEMA_VERSION = 'xhub.role_turn_metadata.v1';

function safeString(value) {
  return String(value ?? '').trim();
}

function safeTimestamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  return grpc.loadPackageDefinition(packageDef)?.ax?.hub?.v1;
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const port = Number(server.address()?.port || 0);
      server.close((err) => {
        if (err) reject(err);
        else resolve(port);
      });
    });
  });
}

function metadataWithBearer(token) {
  const md = new grpc.Metadata();
  md.set('authorization', `Bearer ${token}`);
  return md;
}

function unary(client, methodName, request, metadata) {
  return new Promise((resolve, reject) => {
    client[methodName](request, metadata, (err, response) => {
      if (err) reject(err);
      else resolve(response);
    });
  });
}

function waitForReady(client, timeoutMs = 10_000) {
  return new Promise((resolve, reject) => {
    client.waitForReady(Date.now() + timeoutMs, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

function waitForServer(child, timeoutMs = 15_000) {
  return new Promise((resolve, reject) => {
    let stdout = '';
    let stderr = '';
    let done = false;

    const cleanup = () => {
      clearTimeout(timer);
      child.stdout?.off('data', onStdout);
      child.stderr?.off('data', onStderr);
      child.off('exit', onExit);
      child.off('error', onError);
    };
    const finish = (fn, value) => {
      if (done) return;
      done = true;
      cleanup();
      fn(value);
    };
    const onStdout = (chunk) => {
      const text = chunk.toString('utf8');
      stdout += text;
      if (text.includes('[hub_grpc] listening') || stdout.includes('[hub_grpc] listening')) {
        finish(resolve, { stdout, stderr });
      }
    };
    const onStderr = (chunk) => {
      stderr += chunk.toString('utf8');
    };
    const onExit = (code, signal) => {
      finish(reject, new Error(`server exited before listening code=${code} signal=${signal} stdout=${stdout} stderr=${stderr}`));
    };
    const onError = (err) => {
      finish(reject, err);
    };
    const timer = setTimeout(() => {
      finish(reject, new Error(`timeout waiting for server stdout=${stdout} stderr=${stderr}`));
    }, timeoutMs);

    child.stdout?.on('data', onStdout);
    child.stderr?.on('data', onStderr);
    child.on('exit', onExit);
    child.on('error', onError);
  });
}

function stopServer(child) {
  return new Promise((resolve) => {
    if (!child || child.exitCode != null || child.signalCode != null) {
      resolve();
      return;
    }
    const timer = setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
      resolve();
    }, 5_000);
    child.once('exit', () => {
      clearTimeout(timer);
      resolve();
    });
    try {
      child.kill('SIGTERM');
    } catch {
      clearTimeout(timer);
      resolve();
    }
  });
}

function queryEvidence(dbPath, threadId, appendRequestId, mismatchDispatchId, legacyContent) {
  const db = new HubDB({ dbPath });
  try {
    const rows = db.db.prepare(
      `SELECT role, content, role_metadata_json, client_message_id, source_role, target_role,
              dispatch_id, dispatch_kind, run_id, launch_run_id, reviewer_note_id, status
       FROM turns
       WHERE thread_id = ?
       ORDER BY created_at_ms ASC, turn_id ASC`
    ).all(threadId);
    const mismatch = db.db.prepare(
      `SELECT COUNT(*) AS n FROM turns WHERE dispatch_id = ?`
    ).get(mismatchDispatchId);
    const legacy = db.db.prepare(
      `SELECT role_metadata_json, source_role, dispatch_id
       FROM turns
       WHERE thread_id = ? AND content = ?
       LIMIT 1`
    ).get(threadId, legacyContent);
    const auditRows = db.listAuditEvents({ request_id: appendRequestId });
    const appendAudit = auditRows.find((row) => row.event_type === 'memory.turns.appended') || null;
    const auditExt = appendAudit ? JSON.parse(appendAudit.ext_json || '{}') : null;
    return {
      rows,
      mismatch_row_count: Number(mismatch?.n || 0),
      legacy_row: legacy || null,
      append_audit_ext: auditExt,
    };
  } finally {
    db.close();
  }
}

async function runSmoke() {
  const startedAtMs = Date.now();
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub_role_turn_live_smoke_'));
  const runtimeBaseDir = path.join(tmpRoot, 'runtime');
  const dbPath = path.join(tmpRoot, 'data', 'hub.sqlite3');
  const grpcPort = await freePort();
  const pairingPort = await freePort();
  const token = `role-turn-smoke-${process.pid}-${Date.now()}`;
  const nodeBin = safeString(process.env.XHUB_ROLE_TURN_SMOKE_NODE_BIN) || process.execPath;
  const serverJs = path.resolve(safeString(process.env.XHUB_ROLE_TURN_SMOKE_SERVER_JS) || path.join(SRC_DIR, 'server.js'));
  const serverRoot = path.resolve(safeString(process.env.XHUB_ROLE_TURN_SMOKE_SERVER_ROOT) || path.dirname(path.dirname(serverJs)));
  const protoPath = resolveHubProtoPath({
    HUB_PROTO_PATH: safeString(process.env.XHUB_ROLE_TURN_SMOKE_PROTO_PATH) || process.env.HUB_PROTO_PATH,
  });
  const proto = loadProto(protoPath);
  assert.ok(proto?.HubMemory, 'HubMemory proto service missing');
  assert.ok(fs.existsSync(nodeBin), `node binary missing: ${nodeBin}`);
  assert.ok(fs.existsSync(serverJs), `server.js missing: ${serverJs}`);
  assert.ok(fs.existsSync(protoPath), `proto missing: ${protoPath}`);

  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  const child = spawn(nodeBin, [serverJs], {
    cwd: serverRoot,
    env: {
      ...process.env,
      HUB_HOST: '127.0.0.1',
      HUB_PORT: String(grpcPort),
      HUB_PAIRING_PORT: String(pairingPort),
      HUB_PAIRING_ENABLE: '0',
      HUB_DB_PATH: dbPath,
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_CLIENT_TOKEN: token,
      HUB_GRPC_TLS_MODE: 'insecure',
      HUB_PROVIDER_KEY_REFRESH_ENABLED: 'false',
      HUB_PROVIDER_KEY_QUOTA_REFRESH_ENABLED: 'false',
      HUB_MEMORY_AT_REST_ENABLED: 'false',
      HUB_MEMORY_RETENTION_ENABLED: 'false',
      HUB_PROTO_PATH: protoPath,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let threadId = '';
  const appendRequestId = `role_turn_live_append_${Date.now()}`;
  const mismatchDispatchId = `dispatch_mismatch_${Date.now()}`;
  const legacyContent = 'legacy role/content-only turn survives role metadata upgrade';
  const dispatchId = `dispatch_live_${Date.now()}`;
  const clientIdentity = {
    device_id: 'dev-role-turn-live-smoke',
    user_id: 'user-role-turn-live-smoke',
    app_id: 'x_terminal',
    project_id: 'project-role-turn-live-smoke',
    session_id: 'session-role-turn-live-smoke',
  };

  try {
    await waitForServer(child);
    const addr = `127.0.0.1:${grpcPort}`;
    const md = metadataWithBearer(token);
    const memoryClient = new proto.HubMemory(addr, grpc.credentials.createInsecure(), {
      'grpc.max_receive_message_length': 32 * 1024 * 1024,
      'grpc.max_send_message_length': 32 * 1024 * 1024,
    });
    await waitForReady(memoryClient);

    const thread = await unary(memoryClient, 'GetOrCreateThread', {
      client: clientIdentity,
      thread_key: 'xterminal_project_project-role-turn-live-smoke',
    }, md);
    threadId = String(thread?.thread?.thread_id || '');
    assert.ok(threadId, 'thread_id missing');

    const roleMessages = [
      {
        role: 'user',
        content: 'Supervisor dispatches the live role-turn metadata smoke.',
        turn_metadata: {
          schema_version: TURN_METADATA_SCHEMA_VERSION,
          client_message_id: 'live-msg-supervisor-1',
          source_role: 'supervisor',
          target_role: 'coder',
          project_id: clientIdentity.project_id,
          thread_key: 'xterminal_project_project-role-turn-live-smoke',
          dispatch_id: dispatchId,
          dispatch_kind: 'supervisor_to_coder',
          run_id: 'live-run-1',
          launch_run_id: 'live-launch-run-1',
          status: 'dispatched',
          evidence_refs: ['live-evidence-supervisor-1'],
          audit_refs: ['live-audit-supervisor-1'],
          observed_at_ms: Date.now(),
        },
      },
      {
        role: 'assistant',
        content: 'Coder replies with the same dispatch id.',
        turn_metadata: {
          schema_version: TURN_METADATA_SCHEMA_VERSION,
          client_message_id: 'live-msg-coder-1',
          source_role: 'coder',
          target_role: 'supervisor',
          project_id: clientIdentity.project_id,
          thread_key: 'xterminal_project_project-role-turn-live-smoke',
          dispatch_id: dispatchId,
          dispatch_kind: 'coder_reply',
          run_id: 'live-run-1',
          launch_run_id: 'live-launch-run-1',
          status: 'completed',
          observed_at_ms: Date.now(),
        },
      },
      {
        role: 'user',
        content: 'Reviewer note is stored in Hub truth and points back to the coder.',
        turn_metadata: {
          schema_version: TURN_METADATA_SCHEMA_VERSION,
          client_message_id: 'live-msg-reviewer-1',
          source_role: 'reviewer',
          target_role: 'coder',
          project_id: clientIdentity.project_id,
          thread_key: 'xterminal_project_project-role-turn-live-smoke',
          dispatch_id: dispatchId,
          dispatch_kind: 'reviewer_note',
          reviewer_note_id: 'live-review-note-1',
          status: 'observed',
          observed_at_ms: Date.now(),
        },
      },
    ];

    const appended = await unary(memoryClient, 'AppendTurns', {
      request_id: appendRequestId,
      client: clientIdentity,
      thread_id: threadId,
      messages: roleMessages,
      created_at_ms: Date.now(),
      allow_private: false,
    }, md);
    assert.equal(Number(appended?.appended || 0), 3);

    const legacyAppend = await unary(memoryClient, 'AppendTurns', {
      request_id: `role_turn_live_legacy_${Date.now()}`,
      client: clientIdentity,
      thread_id: threadId,
      messages: [{ role: 'user', content: legacyContent }],
      created_at_ms: Date.now(),
      allow_private: false,
    }, md);
    assert.equal(Number(legacyAppend?.appended || 0), 1);

    let mismatchRejected = false;
    try {
      await unary(memoryClient, 'AppendTurns', {
        request_id: `role_turn_live_mismatch_${Date.now()}`,
        client: clientIdentity,
        thread_id: threadId,
        messages: [
          {
            role: 'user',
            content: 'This turn must be rejected because the metadata project mismatches.',
            turn_metadata: {
              schema_version: TURN_METADATA_SCHEMA_VERSION,
              source_role: 'supervisor',
              target_role: 'coder',
              project_id: 'another-project',
              dispatch_id: mismatchDispatchId,
              dispatch_kind: 'supervisor_to_coder',
            },
          },
        ],
        created_at_ms: Date.now(),
        allow_private: false,
      }, md);
    } catch (error) {
      mismatchRejected = /role_metadata_project_mismatch/.test(String(error?.message || ''));
    }
    assert.equal(mismatchRejected, true, 'project mismatch append was not rejected with role_metadata_project_mismatch');

    const workingSet = await unary(memoryClient, 'GetWorkingSet', {
      client: clientIdentity,
      thread_id: threadId,
      limit: 10,
    }, md);
    const messages = Array.isArray(workingSet?.messages) ? workingSet.messages : [];
    const metadataMessages = messages.filter((message) => message?.turn_metadata?.schema_version === TURN_METADATA_SCHEMA_VERSION);
    assert.equal(metadataMessages.length, 3);
    assert.equal(metadataMessages[0].turn_metadata.source_role, 'supervisor');
    assert.equal(metadataMessages[0].turn_metadata.target_role, 'coder');
    assert.equal(metadataMessages[1].turn_metadata.source_role, 'coder');
    assert.equal(metadataMessages[1].turn_metadata.dispatch_id, dispatchId);
    assert.equal(metadataMessages[2].turn_metadata.source_role, 'reviewer');
    assert.equal(metadataMessages[2].turn_metadata.reviewer_note_id, 'live-review-note-1');
    const legacyReadback = messages.find((message) => message?.content === legacyContent);
    assert.ok(legacyReadback, 'legacy role/content-only turn missing from GetWorkingSet');
    const legacyMetadata = legacyReadback.turn_metadata;
    assert.ok(
      legacyMetadata == null || !String(legacyMetadata.schema_version || '').trim(),
      'legacy role/content-only turn unexpectedly returned role metadata'
    );

    await stopServer(child);
    const evidence = queryEvidence(dbPath, threadId, appendRequestId, mismatchDispatchId, legacyContent);
    const roleRows = evidence.rows.filter((row) => row.dispatch_id === dispatchId);
    assert.equal(roleRows.length, 3);
    assert.equal(roleRows[0].source_role, 'supervisor');
    assert.equal(roleRows[0].target_role, 'coder');
    assert.equal(roleRows[1].source_role, 'coder');
    assert.equal(roleRows[1].target_role, 'supervisor');
    assert.equal(roleRows[2].source_role, 'reviewer');
    assert.equal(roleRows[2].reviewer_note_id, 'live-review-note-1');
    assert.equal(evidence.mismatch_row_count, 0);
    assert.equal(evidence.legacy_row?.role_metadata_json, null);
    assert.equal(evidence.append_audit_ext?.schema_version, TURN_METADATA_SCHEMA_VERSION);
    assert.equal(evidence.append_audit_ext?.role_metadata_count, 3);
    assert.deepEqual(evidence.append_audit_ext?.dispatch_ids, [dispatchId]);
    assert.deepEqual(evidence.append_audit_ext?.source_roles, ['supervisor', 'coder', 'reviewer']);

    return {
      ok: true,
      schema_version: SCHEMA_VERSION,
      generated_at_ms: Date.now(),
      duration_ms: Date.now() - startedAtMs,
      grpc_addr: addr,
      db_path: dbPath,
      runtime_base_dir: runtimeBaseDir,
      proto_path: protoPath,
      server_js: serverJs,
      server_root: serverRoot,
      node_bin: nodeBin,
      thread_id: threadId,
      dispatch_id: dispatchId,
      append_request_id: appendRequestId,
      assertions: {
        supervisor_dispatch_persisted: true,
        coder_reply_same_dispatch_id: true,
        reviewer_note_persisted: true,
        get_working_set_metadata_readback: true,
        legacy_turn_compatible: true,
        project_mismatch_fail_closed: true,
        role_aware_audit_evidence: true,
      },
      evidence,
    };
  } finally {
    await stopServer(child);
  }
}

async function main() {
  fs.mkdirSync(REPORTS_DIR, { recursive: true });
  const reportPath = path.resolve(
    safeString(process.env.XHUB_ROLE_TURN_SMOKE_REPORT_PATH)
      || path.join(REPORTS_DIR, `role_turn_metadata_live_smoke_${safeTimestamp()}.json`)
  );
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  let report;
  try {
    report = await runSmoke();
    report.report_path = reportPath;
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } catch (error) {
    report = {
      ok: false,
      schema_version: SCHEMA_VERSION,
      generated_at_ms: Date.now(),
      error: String(error?.stack || error?.message || error),
      report_path: reportPath,
    };
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    process.exitCode = 1;
  }
}

main();
