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

function makeProjectClient(project_id = 'proj-stage-1') {
  return {
    ...makeSupervisorClient(),
    project_id,
  };
}

function seedProjectCanonical(db, client, project_id, value = 'Ask user before payment') {
  db.upsertCanonicalItem({
    scope: 'project',
    thread_id: '',
    device_id: client.device_id,
    user_id: client.user_id,
    app_id: client.app_id,
    project_id,
    key: 'workflow.next_step',
    value,
    pinned: 1,
  });
}

run('supervisor candidate review stage materializes longterm markdown draft and advances queue state', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeProjectClient('proj-stage-1');
    seedProjectCanonical(db, client, 'proj-stage-1');
    const threadId = openShadowThread(impl, client);

    const envelope = buildCarrierEnvelope({
      emitted_at_ms: 1_717_001_000_000,
      summary_line: 'user_scope, project_scope',
      scopes: ['user_scope', 'project_scope'],
      candidates: [
        {
          scope: 'user_scope',
          record_type: 'preferred_name',
          confidence: 0.98,
          why_promoted: 'explicit preferred-name statement',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:user_scope:preferred_name:andrew:1717001000000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'user_scope',
          idempotency_key: 'sha256:stage-user-preferred-name-1',
          payload_summary: 'preferred_name=Andrew',
        },
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.93,
          why_promoted: 'stable project blocker worth downstream review',
          source_ref: 'assistant_summary',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-stage-1:1717001000000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:stage-project-blocker-1',
          payload_summary: 'project_id=proj-stage-1;record_type=project_blocker',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-stage-1',
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

    const staged = invokeHubMemoryUnary(impl, 'StageSupervisorCandidateReview', {
      client,
      candidate_request_id: 'shadow-stage-1',
    });
    assert.equal(staged.err, null);
    assert.equal(!!staged.res?.staged, true);
    assert.equal(!!staged.res?.idempotent, false);
    assert.equal(String(staged.res?.review_state || ''), 'draft_staged');
    assert.equal(String(staged.res?.promotion_boundary || ''), 'longterm_markdown_pending_change');
    assert.equal(String(staged.res?.status || ''), 'draft');
    assert.match(String(staged.res?.doc_id || ''), /^longterm:/);
    assert.match(String(staged.res?.markdown || ''), /Supervisor Candidate Review Handoff/);

    const draftItem = db.listSupervisorMemoryCandidateCarrierReviewQueue({
      project_id: 'proj-stage-1',
      request_id: 'shadow-stage-1',
      limit: 1,
    })[0];
    assert.ok(draftItem);
    assert.equal(String(draftItem.review_state || ''), 'draft_staged');
    assert.equal(String(draftItem.pending_change_status || ''), 'draft');
    assert.equal(String(draftItem.pending_change_id || ''), String(staged.res?.pending_change_id || ''));

    const draftChange = db.getMemoryMarkdownPendingChange({
      change_id: String(staged.res?.pending_change_id || ''),
    });
    assert.ok(draftChange);
    assert.equal(Array.isArray(draftChange.provenance_refs), true);
    assert.equal(String(draftChange.provenance_refs[0] || ''), 'candidate_carrier_request:shadow-stage-1');

    const reviewed = invokeHubMemoryUnary(impl, 'LongtermMarkdownReview', {
      client,
      pending_change_id: String(staged.res?.pending_change_id || ''),
      review_decision: 'approve',
      on_secret: 'sanitize',
    });
    assert.equal(reviewed.err, null);
    assert.equal(String(reviewed.res?.status || ''), 'approved');

    const approvedItem = db.listSupervisorMemoryCandidateCarrierReviewQueue({
      project_id: 'proj-stage-1',
      request_id: 'shadow-stage-1',
      limit: 1,
    })[0];
    assert.ok(approvedItem);
    assert.equal(String(approvedItem.review_state || ''), 'approved_for_writeback');
    assert.equal(String(approvedItem.pending_change_status || ''), 'approved');

    const written = invokeHubMemoryUnary(impl, 'LongtermMarkdownWriteback', {
      client,
      pending_change_id: String(staged.res?.pending_change_id || ''),
      writeback_note: 'queue candidate review draft',
    });
    assert.equal(written.err, null);
    assert.equal(String(written.res?.status || ''), 'written');
    assert.equal(String(written.res?.evidence_ref || ''), 'candidate_carrier_request:shadow-stage-1');

    const writtenItem = db.listSupervisorMemoryCandidateCarrierReviewQueue({
      project_id: 'proj-stage-1',
      request_id: 'shadow-stage-1',
      limit: 1,
    })[0];
    assert.ok(writtenItem);
    assert.equal(String(writtenItem.review_state || ''), 'writeback_queued');
    assert.equal(String(writtenItem.durable_promotion_state || ''), 'queued_for_writeback');
    assert.equal(String(writtenItem.promotion_boundary || ''), 'longterm_markdown_writeback_queue');
    assert.equal(String(writtenItem.pending_change_status || ''), 'written');
    assert.equal(String(writtenItem.writeback_ref || ''), String(written.res?.candidate_id || ''));
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('supervisor candidate review stage is idempotent per candidate request evidence ref', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeProjectClient('proj-stage-2');
    seedProjectCanonical(db, client, 'proj-stage-2');
    const threadId = openShadowThread(impl, client);

    const envelope = buildCarrierEnvelope({
      emitted_at_ms: 1_717_001_100_000,
      summary_line: 'project_scope',
      scopes: ['project_scope'],
      candidates: [
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.94,
          why_promoted: 'stable project blocker worth downstream review',
          source_ref: 'assistant_summary',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-stage-2:1717001100000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:stage-project-blocker-2',
          payload_summary: 'project_id=proj-stage-2;record_type=project_blocker',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-stage-2',
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

    const first = invokeHubMemoryUnary(impl, 'StageSupervisorCandidateReview', {
      client,
      candidate_request_id: 'shadow-stage-2',
    });
    assert.equal(first.err, null);
    const second = invokeHubMemoryUnary(impl, 'StageSupervisorCandidateReview', {
      client,
      candidate_request_id: 'shadow-stage-2',
    });
    assert.equal(second.err, null);
    assert.equal(!!second.res?.idempotent, true);
    assert.equal(String(second.res?.pending_change_id || ''), String(first.res?.pending_change_id || ''));
    assert.equal(String(second.res?.edit_session_id || ''), String(first.res?.edit_session_id || ''));
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('supervisor candidate review stage fails closed on client scope mismatch', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeProjectClient('proj-stage-3');
    seedProjectCanonical(db, client, 'proj-stage-3');
    const threadId = openShadowThread(impl, client);

    const envelope = buildCarrierEnvelope({
      emitted_at_ms: 1_717_001_200_000,
      summary_line: 'project_scope',
      scopes: ['project_scope'],
      candidates: [
        {
          scope: 'project_scope',
          record_type: 'project_blocker',
          confidence: 0.89,
          why_promoted: 'project blocker',
          source_ref: 'user_message',
          audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-stage-3:1717001200000',
          session_participation_class: 'scoped_write',
          write_permission_scope: 'project_scope',
          idempotency_key: 'sha256:stage-project-blocker-3',
          payload_summary: 'project_id=proj-stage-3;record_type=project_blocker',
        },
      ],
    });

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-stage-3',
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

    const mismatchedClient = {
      ...client,
      device_id: 'dev-supervisor-candidate-2',
    };
    const staged = invokeHubMemoryUnary(impl, 'StageSupervisorCandidateReview', {
      client: mismatchedClient,
      candidate_request_id: 'shadow-stage-3',
    });
    assert.ok(staged.err);
    assert.equal(String(staged.err.message || ''), 'supervisor_candidate_review_scope_mismatch');
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
