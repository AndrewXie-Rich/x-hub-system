import assert from 'node:assert/strict';
import fs from 'node:fs';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import {
  baseEnv,
  cleanupDbArtifacts,
  invokeHubMemoryUnary,
  makeTmp,
  run,
  withEnv,
} from './supervisor_memory_candidate_test_lib.js';

function makeClient(projectId = 'project-role-alpha') {
  return {
    device_id: 'dev-role-turn-1',
    user_id: 'user-role-turn-1',
    app_id: 'x_terminal',
    project_id: projectId,
    session_id: 'sess-role-turn-1',
  };
}

function openProjectThread(impl, client, threadKey = 'xterminal_project_project-role-alpha') {
  const opened = invokeHubMemoryUnary(impl, 'GetOrCreateThread', {
    client,
    thread_key: threadKey,
  });
  if (opened.err) throw opened.err;
  return String(opened.res?.thread?.thread_id || '');
}

run('AppendTurns stores role metadata columns, audit evidence, and GetWorkingSet echoes metadata', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeClient();
    const threadId = openProjectThread(impl, client);
    const dispatchId = 'dispatch-role-alpha-1';

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'role-turn-append-1',
      client,
      thread_id: threadId,
      messages: [
        {
          role: 'user',
          content: 'Supervisor dispatches coder to wire the role-aware contract.',
          turn_metadata: {
            schema_version: 'xhub.role_turn_metadata.v1',
            client_message_id: 'msg-supervisor-1',
            source_role: 'supervisor',
            target_role: 'coder',
            project_id: client.project_id,
            thread_key: 'xterminal_project_project-role-alpha',
            dispatch_id: dispatchId,
            dispatch_kind: 'supervisor_to_coder',
            run_id: 'run-role-1',
            launch_run_id: 'launch-role-1',
            status: 'dispatched',
            evidence_refs: ['evidence-supervisor-1'],
            audit_refs: ['audit-supervisor-1'],
            observed_at_ms: 1_778_000_000_000,
          },
        },
        {
          role: 'assistant',
          content: 'Coder reply keeps the same dispatch id.',
          turn_metadata: {
            schema_version: 'xhub.role_turn_metadata.v1',
            client_message_id: 'msg-coder-1',
            source_role: 'coder',
            target_role: 'supervisor',
            project_id: client.project_id,
            thread_key: 'xterminal_project_project-role-alpha',
            dispatch_id: dispatchId,
            dispatch_kind: 'coder_reply',
            run_id: 'run-role-1',
            launch_run_id: 'launch-role-1',
            status: 'completed',
            observed_at_ms: 1_778_000_000_001,
          },
        },
        {
          role: 'user',
          content: 'Reviewer note asks Coder to add one smoke test.',
          turn_metadata: {
            schema_version: 'xhub.role_turn_metadata.v1',
            client_message_id: 'msg-reviewer-1',
            source_role: 'reviewer',
            target_role: 'coder',
            project_id: client.project_id,
            thread_key: 'xterminal_project_project-role-alpha',
            dispatch_id: dispatchId,
            dispatch_kind: 'reviewer_note',
            reviewer_note_id: 'review-note-1',
            status: 'observed',
            observed_at_ms: 1_778_000_000_002,
          },
        },
        {
          role: 'tool',
          content: 'Tool approval awaiting authorization.',
          turn_metadata: {
            schema_version: 'xhub.role_turn_metadata.v1',
            client_message_id: 'msg-tool-approval-1',
            source_role: 'tool',
            target_role: 'supervisor',
            project_id: client.project_id,
            thread_key: 'xterminal_project_project-role-alpha',
            dispatch_id: dispatchId,
            dispatch_kind: 'tool_approval',
            tool_call_id: 'call-role-1',
            status: 'awaiting_authorization',
            observed_at_ms: 1_778_000_000_003,
          },
        },
        {
          role: 'system',
          content: 'Tool approval decision observed.',
          turn_metadata: {
            schema_version: 'xhub.role_turn_metadata.v1',
            client_message_id: 'msg-tool-approval-decision-1',
            source_role: 'user',
            target_role: 'coder',
            project_id: client.project_id,
            thread_key: 'xterminal_project_project-role-alpha',
            dispatch_id: dispatchId,
            dispatch_kind: 'tool_approval_decision',
            tool_call_id: 'call-role-1',
            status: 'completed',
            observed_at_ms: 1_778_000_000_004,
          },
        },
        {
          role: 'tool',
          content: 'Tool result observed.',
          turn_metadata: {
            schema_version: 'xhub.role_turn_metadata.v1',
            client_message_id: 'msg-tool-result-1',
            source_role: 'tool',
            target_role: 'coder',
            project_id: client.project_id,
            thread_key: 'xterminal_project_project-role-alpha',
            dispatch_id: dispatchId,
            dispatch_kind: 'tool_result',
            tool_call_id: 'call-role-1',
            status: 'completed',
            observed_at_ms: 1_778_000_000_005,
          },
        },
      ],
      created_at_ms: 1_778_000_000_000,
      allow_private: false,
    });

    assert.equal(appended.err, null);
    assert.equal(appended.res?.appended, 6);

    const rows = db.db.prepare(
      `SELECT client_message_id, source_role, target_role, dispatch_id, dispatch_kind,
              run_id, launch_run_id, reviewer_note_id, status, role_metadata_json
       FROM turns
       WHERE thread_id = ?
       ORDER BY created_at_ms ASC`
    ).all(threadId);
    assert.equal(rows.length, 6);
    assert.equal(rows[0].source_role, 'supervisor');
    assert.equal(rows[0].target_role, 'coder');
    assert.equal(rows[0].dispatch_id, dispatchId);
    assert.equal(rows[0].dispatch_kind, 'supervisor_to_coder');
    assert.equal(rows[1].source_role, 'coder');
    assert.equal(rows[1].target_role, 'supervisor');
    assert.equal(rows[1].dispatch_id, dispatchId);
    assert.equal(rows[2].source_role, 'reviewer');
    assert.equal(rows[2].reviewer_note_id, 'review-note-1');
    assert.equal(JSON.parse(rows[2].role_metadata_json).schema_version, 'xhub.role_turn_metadata.v1');
    assert.equal(rows[3].dispatch_kind, 'tool_approval');
    assert.equal(JSON.parse(rows[3].role_metadata_json).tool_call_id, 'call-role-1');
    assert.equal(rows[3].status, 'awaiting_authorization');
    assert.equal(rows[4].dispatch_kind, 'tool_approval_decision');
    assert.equal(rows[4].source_role, 'user');
    assert.equal(JSON.parse(rows[4].role_metadata_json).tool_call_id, 'call-role-1');
    assert.equal(rows[5].dispatch_kind, 'tool_result');
    assert.equal(rows[5].target_role, 'coder');
    assert.equal(JSON.parse(rows[5].role_metadata_json).tool_call_id, 'call-role-1');

    const workingSet = invokeHubMemoryUnary(impl, 'GetWorkingSet', {
      client,
      thread_id: threadId,
      limit: 10,
    });
    assert.equal(workingSet.err, null);
    assert.equal(workingSet.res?.messages?.length, 6);
    assert.equal(workingSet.res.messages[0].turn_metadata.source_role, 'supervisor');
    assert.equal(workingSet.res.messages[1].turn_metadata.dispatch_id, dispatchId);
    assert.equal(workingSet.res.messages[2].turn_metadata.dispatch_kind, 'reviewer_note');
    assert.equal(workingSet.res.messages[3].turn_metadata.dispatch_kind, 'tool_approval');
    assert.equal(workingSet.res.messages[4].turn_metadata.dispatch_kind, 'tool_approval_decision');
    assert.equal(workingSet.res.messages[5].turn_metadata.dispatch_kind, 'tool_result');

    const projection = invokeHubMemoryUnary(impl, 'GetProjectRoleTranscriptProjection', {
      client,
      project_id: client.project_id,
      thread_key: 'xterminal_project_project-role-alpha',
      limit: 10,
      include_content: true,
    });
    assert.equal(projection.err, null);
    assert.equal(projection.res?.schema_version, 'xhub.project_role_transcript_projection.v1');
    assert.equal(projection.res?.source, 'hub_memory_turns');
    assert.equal(projection.res?.project_id, client.project_id);
    assert.equal(projection.res?.thread_id, threadId);
    assert.equal(projection.res?.thread_key, 'xterminal_project_project-role-alpha');
    assert.equal(projection.res?.status, 'latest_coder_reply_observed');
    assert.equal(projection.res?.latest_supervisor_dispatch?.turn_metadata?.source_role, 'supervisor');
    assert.equal(projection.res?.latest_coder_reply?.turn_metadata?.source_role, 'coder');
    assert.equal(projection.res?.latest_reviewer_note?.turn_metadata?.reviewer_note_id, 'review-note-1');
    assert.equal(projection.res?.recent_lines?.length, 6);
    assert.equal(projection.res.recent_lines[0].role, 'supervisor');
    assert.equal(projection.res.recent_lines[1].role, 'coder');
    assert.equal(projection.res.recent_lines[2].role, 'reviewer');
    assert.equal(projection.res.recent_lines[5].turn_metadata.dispatch_kind, 'tool_result');

    const metadataOnlyProjection = invokeHubMemoryUnary(impl, 'GetProjectRoleTranscriptProjection', {
      client,
      project_id: client.project_id,
      thread_key: 'xterminal_project_project-role-alpha',
      limit: 2,
      include_content: false,
    });
    assert.equal(metadataOnlyProjection.err, null);
    assert.equal(metadataOnlyProjection.res?.recent_lines?.length, 2);
    assert.equal(metadataOnlyProjection.res.recent_lines[0].content, '');
    assert.equal(metadataOnlyProjection.res.recent_lines[0].turn_metadata.dispatch_kind, 'tool_approval_decision');
    assert.equal(metadataOnlyProjection.res.recent_lines[1].turn_metadata.dispatch_kind, 'tool_result');

    const auditRows = db.listAuditEvents({
      device_id: client.device_id,
      request_id: 'role-turn-append-1',
    });
    const appendAudit = auditRows.find((row) => row.event_type === 'memory.turns.appended');
    assert.ok(appendAudit);
    const ext = JSON.parse(appendAudit.ext_json);
    assert.equal(ext.schema_version, 'xhub.role_turn_metadata.v1');
    assert.equal(ext.role_metadata_count, 6);
    assert.deepEqual(ext.dispatch_ids, [dispatchId]);
    assert.deepEqual(ext.source_roles, ['supervisor', 'coder', 'reviewer', 'tool', 'user']);
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('AppendTurns fails closed when role metadata project_id mismatches authenticated scope', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeClient('project-role-alpha');
    const threadId = openProjectThread(impl, client);

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'role-turn-mismatch-1',
      client,
      thread_id: threadId,
      messages: [
        {
          role: 'user',
          content: 'This metadata claims another project.',
          turn_metadata: {
            schema_version: 'xhub.role_turn_metadata.v1',
            source_role: 'supervisor',
            target_role: 'coder',
            project_id: 'project-role-beta',
            dispatch_id: 'dispatch-mismatch',
            dispatch_kind: 'supervisor_to_coder',
          },
        },
      ],
      created_at_ms: 1_778_000_010_000,
      allow_private: false,
    });

    assert.ok(appended.err);
    assert.match(String(appended.err?.message || ''), /role_metadata_project_mismatch/);
    const row = db.db.prepare(`SELECT COUNT(*) AS n FROM turns WHERE thread_id = ?`).get(threadId);
    assert.equal(Number(row?.n || 0), 0);

    const projection = invokeHubMemoryUnary(impl, 'GetProjectRoleTranscriptProjection', {
      client,
      project_id: 'project-role-beta',
      thread_key: 'xterminal_project_project-role-alpha',
      limit: 10,
      include_content: true,
    });
    assert.ok(projection.err);
    assert.match(String(projection.err?.message || ''), /role_metadata_project_mismatch/);
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('AppendTurns remains compatible with legacy role/content-only clients', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeClient();
    const threadId = openProjectThread(impl, client);

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'legacy-append-1',
      client,
      thread_id: threadId,
      messages: [{ role: 'user', content: 'legacy message with no metadata' }],
      created_at_ms: 1_778_000_020_000,
      allow_private: false,
    });

    assert.equal(appended.err, null);
    assert.equal(appended.res?.appended, 1);

    const raw = db.db.prepare(`SELECT role_metadata_json, source_role FROM turns WHERE thread_id = ? LIMIT 1`).get(threadId);
    assert.equal(raw.role_metadata_json, null);
    assert.equal(raw.source_role, null);

    const workingSet = invokeHubMemoryUnary(impl, 'GetWorkingSet', {
      client,
      thread_id: threadId,
      limit: 10,
    });
    assert.equal(workingSet.err, null);
    assert.equal(workingSet.res?.messages?.length, 1);
    assert.equal(workingSet.res.messages[0].role, 'user');
    assert.equal(workingSet.res.messages[0].content, 'legacy message with no metadata');
    assert.equal(workingSet.res.messages[0].turn_metadata, undefined);

    const projection = invokeHubMemoryUnary(impl, 'GetProjectRoleTranscriptProjection', {
      client,
      project_id: client.project_id,
      thread_key: 'xterminal_project_project-role-alpha',
      limit: 10,
      include_content: true,
    });
    assert.equal(projection.err, null);
    assert.equal(projection.res?.schema_version, 'xhub.project_role_transcript_projection.v1');
    assert.equal(projection.res?.status, 'observed');
    assert.equal(projection.res?.recent_lines?.length, 1);
    assert.equal(projection.res.recent_lines[0].role, 'user');
    assert.equal(projection.res.recent_lines[0].content, 'legacy message with no metadata');
    assert.equal(projection.res.recent_lines[0].turn_metadata, undefined);
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
