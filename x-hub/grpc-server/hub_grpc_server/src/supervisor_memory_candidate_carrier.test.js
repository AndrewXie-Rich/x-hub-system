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

run('supervisor candidate shadow thread ingests carrier rows and keeps turn append intact', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeSupervisorClient();
    const threadId = openShadowThread(impl, client);

    const envelope = buildCarrierEnvelope({
      summary_line: 'user_scope, project_scope',
      scopes: ['user_scope', 'project_scope'],
      candidates: [
        {
          scope: 'user_scope',
          record_type: 'preferred_name',
          confidence: 0.98,
          why_promoted: 'explicit preferred-name statement',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:user_scope:preferred_name:andrew:1717000000000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'user_scope',
          idempotency_key: 'sha256:user-preferred-name-1',
          payload_summary: 'preferred_name=Andrew',
        },
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.91,
          why_promoted: 'focused project fact with durable planning/blocker significance',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-alpha:1717000000000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:project-blocker-1',
          payload_summary: 'project_id=proj-alpha;record_type=project_blocker',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-write-1',
      client,
      thread_id: threadId,
      messages: [
        {
          role: 'user',
          content: 'shadow_write durable_candidates scopes=user_scope,project_scope count=2',
        },
        {
          role: 'assistant',
          content: JSON.stringify(envelope),
        },
      ],
      created_at_ms: envelope.emitted_at_ms,
      allow_private: false,
    });

    assert.equal(appended.err, null);
    assert.equal(appended.res?.thread_id, threadId);
    assert.equal(appended.res?.appended, 2);

    const carrierRows = db.listSupervisorMemoryCandidateCarrier({
      device_id: client.device_id,
      app_id: client.app_id,
      request_id: 'shadow-write-1',
    });
    assert.equal(carrierRows.length, 2);

    const projectRow = carrierRows.find((row) => row.scope === 'project_scope');
    assert.ok(projectRow);
    assert.equal(projectRow.project_id, 'proj-alpha');
    assert.equal(projectRow.payload_fields.project_id, 'proj-alpha');
    assert.equal(projectRow.payload_fields.record_type, 'project_blocker');
    assert.equal(projectRow.schema_version, envelope.schema_version);
    assert.equal(projectRow.carrier_kind, envelope.carrier_kind);
    assert.equal(projectRow.mirror_target, envelope.mirror_target);

    const turns = db.listTurns({ thread_id: threadId, limit: 10 });
    assert.equal(turns.length, 2);

    const auditRows = db.listAuditEvents({
      device_id: client.device_id,
      request_id: 'shadow-write-1',
    });
    const eventTypes = auditRows.map((row) => String(row.event_type || ''));
    assert.ok(eventTypes.includes('supervisor.memory_candidate_carrier.ingested'));
    assert.ok(eventTypes.includes('memory.turns.appended'));
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
