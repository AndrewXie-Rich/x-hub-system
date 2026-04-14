import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

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

run('supervisor candidate review queue keeps full mixed-scope request under project filter', () => {
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
      emitted_at_ms: 1_717_000_100_000,
      summary_line: 'user_scope, project_scope',
      scopes: ['user_scope', 'project_scope'],
      candidates: [
        {
          scope: 'user_scope',
          record_type: 'preferred_name',
          confidence: 0.98,
          why_promoted: 'explicit preferred-name statement',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:user_scope:preferred_name:andrew:1717000100000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'user_scope',
          idempotency_key: 'sha256:user-preferred-name-review-1',
          payload_summary: 'preferred_name=Andrew',
        },
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.91,
          why_promoted: 'focused project fact with durable planning/blocker significance',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-alpha:1717000100000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:project-blocker-review-1',
          payload_summary: 'project_id=proj-alpha;record_type=project_blocker',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-review-1',
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

    const items = db.listSupervisorMemoryCandidateCarrierReviewQueue({
      project_id: 'proj-alpha',
      limit: 10,
    });
    assert.equal(items.length, 1);

    const item = items[0];
    assert.equal(item.request_id, 'shadow-review-1');
    assert.equal(item.project_id, 'proj-alpha');
    assert.equal(item.candidate_count, 2);
    assert.equal(item.review_state, 'pending_review');
    assert.equal(item.durable_promotion_state, 'not_promoted');
    assert.equal(item.promotion_boundary, 'candidate_carrier_only');
    assert.equal(item.evidence_ref, 'candidate_carrier_request:shadow-review-1');
    assert.ok(Array.isArray(item.project_ids) && item.project_ids.includes('proj-alpha'));
    assert.ok(Array.isArray(item.scopes) && item.scopes.includes('user_scope'));
    assert.ok(Array.isArray(item.scopes) && item.scopes.includes('project_scope'));
    assert.ok(Array.isArray(item.record_types) && item.record_types.includes('preferred_name'));
    assert.ok(Array.isArray(item.record_types) && item.record_types.includes('project_blocker'));
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('supervisor candidate review status export mirrors pending review snapshot', () => {
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
      emitted_at_ms: 1_717_000_200_000,
      summary_line: 'project_scope',
      scopes: ['project_scope'],
      candidates: [
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.94,
          why_promoted: 'stable project blocker worth downstream review',
          source_ref: 'assistant_summary',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-beta:1717000200000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:project-blocker-export-1',
          payload_summary: 'project_id=proj-beta;record_type=project_blocker',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-review-export-1',
      client,
      thread_id: threadId,
      messages: [
        {
          role: 'user',
          content: 'shadow_write durable_candidates scopes=project_scope count=1',
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

    const exported = JSON.parse(
      fs.readFileSync(
        path.join(runtimeBaseDir, 'supervisor_candidate_review_status.json'),
        'utf8'
      )
    );
    assert.equal(exported.schema_version, 'supervisor_candidate_review_status.v1');
    assert.ok(Array.isArray(exported.items));
    assert.equal(exported.items.length, 1);
    assert.equal(exported.items[0]?.request_id, 'shadow-review-export-1');
    assert.equal(exported.items[0]?.review_state, 'pending_review');
    assert.equal(exported.items[0]?.durable_promotion_state, 'not_promoted');
    assert.equal(exported.items[0]?.promotion_boundary, 'candidate_carrier_only');
    assert.ok(Array.isArray(exported.items[0]?.scopes) && exported.items[0].scopes.includes('project_scope'));
    assert.equal(exported.items[0]?.evidence_ref, 'candidate_carrier_request:shadow-review-export-1');
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
