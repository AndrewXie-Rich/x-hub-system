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

run('supervisor candidate carrier treats duplicate request as idempotent and avoids duplicate turns', () => {
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
      summary_line: 'project_scope, cross_link_scope',
      scopes: ['project_scope', 'cross_link_scope'],
      candidates: [
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.91,
          why_promoted: 'focused project fact with durable planning/blocker significance',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-alpha:1717000000000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:project-blocker-idem',
          payload_summary: 'project_id=proj-alpha;record_type=project_blocker',
        },
        {
          scope: 'cross_link_scope',
          record_type: 'person_waiting_on_project',
          confidence: 0.93,
          why_promoted: 'person-project dependency is explicit in the current turn',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:cross_link_scope:person_waiting_on_project:liangliang|proj-alpha:1717000000000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'cross_link_scope',
          idempotency_key: 'sha256:cross-link-idem',
          payload_summary: 'person=LiangLiang;project_id=proj-alpha',
        },
      ],
    });

    const request = {
      request_id: 'shadow-idem-1',
      client,
      thread_id: threadId,
      messages: [
        { role: 'user', content: 'shadow_write durable_candidates scopes=project_scope,cross_link_scope count=2' },
        { role: 'assistant', content: JSON.stringify(envelope) },
      ],
      created_at_ms: envelope.emitted_at_ms,
      allow_private: false,
    };

    const first = invokeHubMemoryUnary(impl, 'AppendTurns', request);
    assert.equal(first.err, null);
    assert.equal(first.res?.appended, 2);

    const second = invokeHubMemoryUnary(impl, 'AppendTurns', request);
    assert.equal(second.err, null);
    assert.equal(second.res?.appended, 0);

    const carrierRows = db.listSupervisorMemoryCandidateCarrier({
      device_id: client.device_id,
      app_id: client.app_id,
      request_id: 'shadow-idem-1',
    });
    assert.equal(carrierRows.length, 2);
    assert.equal(db.listTurns({ thread_id: threadId, limit: 10 }).length, 2);

    const auditRows = db.listAuditEvents({
      device_id: client.device_id,
      request_id: 'shadow-idem-1',
    });
    const duplicateEvent = auditRows.find((row) => String(row.event_type || '') === 'supervisor.memory_candidate_carrier.duplicate');
    assert.ok(duplicateEvent);
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
