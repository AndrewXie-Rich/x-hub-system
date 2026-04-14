import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { buildProjectHeartbeatGovernanceSnapshot as buildSharedProjectHeartbeatGovernanceSnapshot } from './project_heartbeat_governance_projection.js';
import { buildProjectHeartbeatGovernanceSnapshot, makeServices } from './services.js';

function run(name, fn) {
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
  return path.join(os.tmpdir(), `hub_heartbeat_governance_projection_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x52).toString('base64')}`;

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
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
    },
  );
  return { err: outErr, res: outRes };
}

function makeClient(projectId = 'proj-hg-1') {
  return {
    device_id: 'dev-hg-1',
    user_id: 'user-hg-1',
    app_id: 'ax-terminal',
    project_id: projectId,
    session_id: 'sess-hg-1',
  };
}

function upsertCanonical(impl, client, { key, value, request_id = 'req-hg-upsert-1' } = {}) {
  return invokeHubMemoryUnary(impl, 'UpsertCanonicalMemory', {
    request_id,
    client,
    scope: 'project',
    key,
    value,
    pinned: false,
  });
}

run('heartbeat governance projection assembles XT summary_json from canonical memory', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-hg-1');
      const summary = {
        schema_version: 'xt.project_heartbeat.v1',
        project_id: 'proj-hg-1',
        project_name: 'Tank Battle',
        updated_at_ms: 1_710_000_000_000,
        last_heartbeat_at_ms: 1_710_000_000_000,
        status_digest: 'Core loop advancing',
        current_state_summary: 'Rendering shell is in place and game state is wired.',
        next_step_summary: 'Run one focused browser smoke for movement and firing.',
        blocker_summary: '',
        latest_quality_band: 'usable',
        latest_quality_score: 74,
        weak_reasons: ['evidence_thin'],
        open_anomaly_types: ['stale_repeat'],
        project_phase: 'build',
        execution_status: 'active',
        risk_tier: 'medium',
        cadence: {
          schemaVersion: 'xt.supervisor_cadence_explainability.v1',
          progressHeartbeat: {
            dimension: 'progress_heartbeat',
            configuredSeconds: 300,
            recommendedSeconds: 180,
            effectiveSeconds: 180,
            effectiveReasonCodes: ['phase_build'],
            nextDueAtMs: 1_710_000_180_000,
            nextDueReasonCodes: ['heartbeat_due_soon'],
            isDue: false,
          },
          reviewPulse: {
            dimension: 'review_pulse',
            configuredSeconds: 900,
            recommendedSeconds: 600,
            effectiveSeconds: 600,
            effectiveReasonCodes: ['quality_usable'],
            nextDueAtMs: 1_710_000_600_000,
            nextDueReasonCodes: ['pulse_due_window'],
            isDue: true,
          },
          brainstormReview: {
            dimension: 'brainstorm_review',
            configuredSeconds: 1800,
            recommendedSeconds: 1200,
            effectiveSeconds: 1200,
            effectiveReasonCodes: ['no_progress_window_idle'],
            nextDueAtMs: 1_710_001_200_000,
            nextDueReasonCodes: ['brainstorm_due_later'],
            isDue: false,
          },
          eventFollowUpCooldownSeconds: 300,
          reasonCodes: ['quality_usable', 'phase_build'],
          nextDueReasonCodes: ['pulse_due_window'],
        },
        next_review_kind: 'review_pulse',
        next_review_due_at_ms: 1_710_000_600_000,
        next_review_due: true,
        digestExplainability: {
          visibility: 'shown',
          reasonCodes: ['review_candidate_active', 'open_anomalies_present'],
          whatChangedText: '项目已从空骨架推进到可交互主循环。',
          whyImportantText: '这说明 MVP 主路径已经接近可验证。',
          systemNextStepText: '系统接下来会先做一轮浏览器验证，再决定是否进入收口。',
        },
        recoveryDecision: {
          schemaVersion: 'xt.heartbeat_recovery_decision.v1',
          action: 'queue_strategic_review',
          urgency: 'active',
          reasonCode: 'heartbeat_or_lane_signal_requires_governance_review',
          summary: 'Queue a deeper governance review before resuming autonomous execution.',
          sourceSignals: ['review_candidate'],
          anomalyTypes: ['stale_repeat'],
          blockedLaneReasons: [],
          blockedLaneCount: 0,
          stalledLaneCount: 0,
          failedLaneCount: 0,
          recoveringLaneCount: 0,
          requiresUserAction: false,
          queuedReviewTrigger: 'periodic_pulse',
          queuedReviewLevel: 'r2_strategic',
          queuedReviewRunKind: 'pulse',
        },
        audit_ref: 'supervisor_project_heartbeat:proj-hg-1:1710000000000',
      };

      const upsert = upsertCanonical(impl, client, {
        key: 'xterminal.project.heartbeat.summary_json',
        value: JSON.stringify(summary),
      });
      assert.equal(upsert.err, null);
      assert.match(String(upsert.res?.writeback_ref || ''), /^canonical_memory_item:/);

      const snapshot = buildProjectHeartbeatGovernanceSnapshot({
        db,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      const sharedSnapshot = buildSharedProjectHeartbeatGovernanceSnapshot({
        db,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.deepEqual(sharedSnapshot, snapshot);

      assert.deepEqual(snapshot, {
        project_id: 'proj-hg-1',
        project_name: 'Tank Battle',
        status_digest: 'Core loop advancing',
        current_state_summary: 'Rendering shell is in place and game state is wired.',
        next_step_summary: 'Run one focused browser smoke for movement and firing.',
        blocker_summary: '',
        last_heartbeat_at_ms: 1_710_000_000_000,
        latest_quality_band: 'usable',
        latest_quality_score: 74,
        weak_reasons: ['evidence_thin'],
        open_anomaly_types: ['stale_repeat'],
        project_phase: 'build',
        execution_status: 'active',
        risk_tier: 'medium',
        digest_visibility: 'shown',
        digest_reason_codes: ['review_candidate_active', 'open_anomalies_present'],
        digest_what_changed_text: '项目已从空骨架推进到可交互主循环。',
        digest_why_important_text: '这说明 MVP 主路径已经接近可验证。',
        digest_system_next_step_text: '系统接下来会先做一轮浏览器验证，再决定是否进入收口。',
        progress_heartbeat: {
          dimension: 'progress_heartbeat',
          configured_seconds: 300,
          recommended_seconds: 180,
          effective_seconds: 180,
          effective_reason_codes: ['phase_build'],
          next_due_at_ms: 1_710_000_180_000,
          next_due_reason_codes: ['heartbeat_due_soon'],
          due: false,
        },
        review_pulse: {
          dimension: 'review_pulse',
          configured_seconds: 900,
          recommended_seconds: 600,
          effective_seconds: 600,
          effective_reason_codes: ['quality_usable'],
          next_due_at_ms: 1_710_000_600_000,
          next_due_reason_codes: ['pulse_due_window'],
          due: true,
        },
        brainstorm_review: {
          dimension: 'brainstorm_review',
          configured_seconds: 1800,
          recommended_seconds: 1200,
          effective_seconds: 1200,
          effective_reason_codes: ['no_progress_window_idle'],
          next_due_at_ms: 1_710_001_200_000,
          next_due_reason_codes: ['brainstorm_due_later'],
          due: false,
        },
        next_review_due: {
          kind: 'review_pulse',
          due: true,
          at_ms: 1_710_000_600_000,
          reason_codes: ['pulse_due_window'],
        },
        recovery_decision: {
          action: 'queue_strategic_review',
          urgency: 'active',
          reason_code: 'heartbeat_or_lane_signal_requires_governance_review',
          summary: 'Queue a deeper governance review before resuming autonomous execution.',
          source_signals: ['review_candidate'],
          anomaly_types: ['stale_repeat'],
          blocked_lane_reasons: [],
          blocked_lane_count: 0,
          stalled_lane_count: 0,
          failed_lane_count: 0,
          recovering_lane_count: 0,
          requires_user_action: false,
          queued_review_trigger: 'periodic_pulse',
          queued_review_level: 'r2_strategic',
          queued_review_run_kind: 'pulse',
        },
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('heartbeat governance projection ignores missing or malformed summary_json', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-hg-2');

      const missing = buildProjectHeartbeatGovernanceSnapshot({
        db,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.equal(missing, null);

      const upsert = upsertCanonical(impl, client, {
        request_id: 'req-hg-upsert-malformed',
        key: 'xterminal.project.heartbeat.summary_json',
        value: '{not-json',
      });
      assert.equal(upsert.err, null);

      const malformed = buildProjectHeartbeatGovernanceSnapshot({
        db,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.equal(malformed, null);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
