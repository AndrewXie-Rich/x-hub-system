import assert from 'node:assert/strict';
import fs from 'node:fs';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import {
  baseEnv,
  buildCarrierEnvelope,
  cleanupDbArtifacts,
  invokeHubMemoryUnary,
  makeSupervisorClient,
  makeTmp,
  openShadowThread,
  run,
  withEnv,
} from './supervisor_memory_candidate_test_lib.js';

function setup() {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);
  const teardown = () => {
    cleanupDbArtifacts(dbPath);
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  };
  return { runtimeBaseDir, dbPath, teardown };
}

run('supervisor candidate carrier denies read_only participation class fail-closed', () => {
  const { runtimeBaseDir, dbPath, teardown } = setup();

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeSupervisorClient();
    const threadId = openShadowThread(impl, client);

    const envelope = buildCarrierEnvelope({
      summary_line: 'project_scope',
      scopes: ['project_scope'],
      candidates: [
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.91,
          why_promoted: 'focused project fact with durable planning/blocker significance',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-alpha:1717000000000',
          session_participation_class: 'read_only',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:project-blocker-read-only',
          payload_summary: 'project_id=proj-alpha;record_type=project_blocker',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-deny-read-only',
      client,
      thread_id: threadId,
      messages: [
        { role: 'user', content: 'shadow_write durable_candidates scopes=project_scope count=1' },
        { role: 'assistant', content: JSON.stringify(envelope) },
      ],
      created_at_ms: envelope.emitted_at_ms,
      allow_private: false,
    });

    assert.equal(String(appended.err?.message || ''), 'supervisor_candidate_session_participation_denied');
    assert.equal(db.listTurns({ thread_id: threadId, limit: 10 }).length, 0);
    assert.equal(
      db.listSupervisorMemoryCandidateCarrier({
        device_id: client.device_id,
        app_id: client.app_id,
        request_id: 'shadow-deny-read-only',
      }).length,
      0
    );

    const denyAudit = db.listAuditEvents({
      device_id: client.device_id,
      request_id: 'shadow-deny-read-only',
    });
    assert.equal(denyAudit.length, 1);
    assert.equal(String(denyAudit[0]?.event_type || ''), 'supervisor.memory_candidate_carrier.denied');
    assert.equal(String(denyAudit[0]?.error_code || ''), 'supervisor_candidate_session_participation_denied');
  });

  teardown();
});

run('supervisor candidate carrier rejects scope payload without required project binding', () => {
  const { runtimeBaseDir, dbPath, teardown } = setup();

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeSupervisorClient();
    const threadId = openShadowThread(impl, client);

    const envelope = buildCarrierEnvelope({
      summary_line: 'project_scope',
      scopes: ['project_scope'],
      candidates: [
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.91,
          why_promoted: 'focused project fact with durable planning/blocker significance',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:missing-project:1717000000000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:project-blocker-missing-project',
          payload_summary: 'record_type=project_blocker',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-deny-scope',
      client,
      thread_id: threadId,
      messages: [
        { role: 'user', content: 'shadow_write durable_candidates scopes=project_scope count=1' },
        { role: 'assistant', content: JSON.stringify(envelope) },
      ],
      created_at_ms: envelope.emitted_at_ms,
      allow_private: false,
    });

    assert.equal(String(appended.err?.message || ''), 'supervisor_candidate_project_id_missing');
    assert.equal(db.listTurns({ thread_id: threadId, limit: 10 }).length, 0);
    assert.equal(
      db.listSupervisorMemoryCandidateCarrier({
        device_id: client.device_id,
        app_id: client.app_id,
        request_id: 'shadow-deny-scope',
      }).length,
      0
    );
  });

  teardown();
});

run('supervisor candidate carrier rejects non-durable scopes from shadow thread', () => {
  const { runtimeBaseDir, dbPath, teardown } = setup();

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeSupervisorClient();
    const threadId = openShadowThread(impl, client);

    const envelope = buildCarrierEnvelope({
      summary_line: 'working_set_only',
      scopes: ['working_set_only'],
      candidates: [
        {
          scope: 'working_set_only',
          record_type: 'transient_turn_note',
          confidence: 0.66,
          why_promoted: 'turn carries temporary planning context but no durable verified fact',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:working_set_only:transient_turn_note:1717000000000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'working_set_only',
          idempotency_key: 'sha256:working-set-only',
          payload_summary: 'stable=temporary note',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-deny-non-durable-scope',
      client,
      thread_id: threadId,
      messages: [
        { role: 'user', content: 'shadow_write durable_candidates scopes=working_set_only count=1' },
        { role: 'assistant', content: JSON.stringify(envelope) },
      ],
      created_at_ms: envelope.emitted_at_ms,
      allow_private: false,
    });

    assert.equal(String(appended.err?.message || ''), 'supervisor_candidate_scope_invalid');
    assert.equal(db.listTurns({ thread_id: threadId, limit: 10 }).length, 0);
    assert.equal(
      db.listSupervisorMemoryCandidateCarrier({
        device_id: client.device_id,
        app_id: client.app_id,
        request_id: 'shadow-deny-non-durable-scope',
      }).length,
      0
    );
  });

  teardown();
});
