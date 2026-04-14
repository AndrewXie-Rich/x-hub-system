import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_retrieval_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

function writeJSON(filePath, payload) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
}

function seedGovernedCodingRuntimeArtifacts(projectRoot) {
  const stateDir = path.join(projectRoot, '.xterminal');
  const reportsDir = path.join(projectRoot, 'build', 'reports');
  fs.mkdirSync(stateDir, { recursive: true });
  fs.mkdirSync(reportsDir, { recursive: true });

  const checkpointPath = path.join(reportsDir, 'xt_w3_25_run_checkpoint_2.v1.json');
  const handoffPath = path.join(reportsDir, 'xt_automation_run_handoff_run-1.v1.json');
  const retryPath = path.join(reportsDir, 'xt_automation_retry_package_run-1-retry.v1.json');
  const guidancePath = path.join(stateDir, 'supervisor_guidance_injections.json');
  const heartbeatPath = path.join(stateDir, 'heartbeat_memory_projection.json');

  writeJSON(checkpointPath, {
    schema_version: 'xt.automation_run_checkpoint.v1',
    run_id: 'run-1',
    recipe_id: 'recipe-1',
    state: 'blocked',
    attempt: 2,
    last_transition: 'blocked',
    retry_after_seconds: 120,
    resume_token: 'resume-1',
    checkpoint_ref: checkpointPath,
    stable_identity: true,
    current_step_id: 'step-verify',
    current_step_title: 'Verify focused smoke tests',
    current_step_state: 'retry_wait',
    current_step_summary: 'Waiting before retrying the reduced verify set.',
    audit_ref: 'audit-checkpoint-1',
  });

  writeJSON(handoffPath, {
    schema_version: 'xt.automation_run_handoff.v1',
    generated_at: 123.0,
    run_id: 'run-1',
    recipe_ref: 'recipe://run-1',
    delivery_ref: 'build/reports/delivery-card.v1.json',
    final_state: 'blocked',
    hold_reason: 'automation_verify_failed',
    detail: 'Smoke tests are still red.',
    action_results: [],
    verification_report: {
      required: true,
      executed: true,
      command_count: 3,
      passed_command_count: 1,
      hold_reason: 'automation_verify_failed',
    },
    suggested_next_actions: [
      'shrink verify scope',
      're-run smoke tests',
    ],
    structured_blocker: {
      code: 'automation_verify_failed',
      summary: 'Smoke tests are still red.',
      stage: 'verification',
      current_step_id: 'step-verify',
      current_step_title: 'Verify focused smoke tests',
      current_step_state: 'retry_wait',
      current_step_summary: 'Waiting before retrying the reduced verify set.',
    },
    current_step_id: 'step-verify',
    current_step_title: 'Verify focused smoke tests',
    current_step_state: 'retry_wait',
    current_step_summary: 'Waiting before retrying the reduced verify set.',
  });

  writeJSON(retryPath, {
    schema_version: 'xt.automation_retry_package.v1',
    generated_at: 124.0,
    project_id: 'project_alpha',
    delivery_ref: 'build/reports/delivery-card.v1.json',
    source_run_id: 'run-1',
    source_final_state: 'blocked',
    source_hold_reason: 'automation_verify_failed',
    source_handoff_artifact_path: handoffPath,
    source_blocker: {
      code: 'automation_verify_failed',
      summary: 'Smoke tests are still red.',
      stage: 'verification',
      current_step_id: 'step-verify',
      current_step_title: 'Verify focused smoke tests',
      current_step_state: 'retry_wait',
      current_step_summary: 'Waiting before retrying the reduced verify set.',
    },
    retry_strategy: 'shrink_verify_scope',
    retry_reason: 'automation_verify_failed',
    retry_reason_descriptor: {
      code: 'retry_verify_scope',
      summary: 'Retry with a reduced verify set',
      strategy: 'shrink_verify_scope',
      current_step_id: 'step-verify',
      current_step_title: 'Verify focused smoke tests',
      current_step_state: 'retry_wait',
      current_step_summary: 'Waiting before retrying the reduced verify set.',
    },
    planning_mode: 'verification_recovery',
    planning_summary: 'Retry with a reduced verify scope before escalating.',
    retry_run_id: 'run-1-retry',
    retry_artifact_path: retryPath,
  });

  writeJSON(guidancePath, {
    schema_version: 'xt.supervisor_guidance_injection_snapshot.v1',
    updated_at_ms: 900,
    items: [
      {
        schema_version: 'xt.supervisor_guidance_injection.v1',
        injection_id: 'guidance-1',
        review_id: 'review-1',
        project_id: 'project_alpha',
        target_role: 'coder',
        delivery_mode: 'priority_insert',
        intervention_mode: 'replan_next_safe_point',
        safe_point_policy: 'next_step_boundary',
        guidance_text: 'Pause the broader rollout and reduce the verify scope before the next retry.',
        ack_status: 'pending',
        ack_required: true,
        effective_supervisor_tier: 's3_strategic_coach',
        work_order_ref: 'xt-w4-guidance',
        ack_note: '',
        injected_at_ms: 880,
        ack_updated_at_ms: 880,
        audit_ref: 'audit-guidance-1',
      },
    ],
  });

  writeJSON(heartbeatPath, {
    schema_version: 'xt.heartbeat_memory_projection.v1',
    project_id: 'project_alpha',
    project_root: projectRoot,
    project_name: 'Runtime Project',
    created_at_ms: 950,
    raw_vault_ref: path.join(stateDir, 'raw_log.jsonl'),
    raw_payload: {
      status_digest: 'Blocked on smoke tests',
      current_state_summary: 'Verification failed after patch',
      next_step_summary: 'Retry with reduced verify scope',
      blocker_summary: 'Smoke tests are still red.',
      latest_quality_band: 'medium',
      latest_quality_score: 62,
      execution_status: 'blocked',
      risk_tier: 'medium',
      recovery_decision: {
        action: 'queue_strategic_review',
        urgency: 'active',
        reason_code: 'blocker_detected',
        summary: 'Queue a strategic review before retrying.',
        queued_review_trigger: 'blocker_detected',
        queued_review_level: 'r2_strategic',
        queued_review_run_kind: 'event_driven',
      },
    },
    canonical_projection: {
      audit_ref: 'audit-heartbeat-canonical-1',
    },
  });

  return {
    checkpointPath,
    handoffPath,
    retryPath,
    guidancePath,
    heartbeatPath,
  };
}

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'false',
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
    }
  );
  return { err: outErr, res: outRes };
}

function makeClient(projectId = 'project_alpha') {
  return {
    device_id: 'dev-retrieval-1',
    user_id: 'user-retrieval-1',
    app_id: 'x_terminal',
    project_id: projectId,
    session_id: 'sess-retrieval-1',
  };
}

run('RetrieveMemory returns v1-shaped current-project snippets and writes audit', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeClient();

    const canonical = invokeHubMemoryUnary(impl, 'UpsertCanonicalMemory', {
      client,
      scope: 'project',
      thread_id: '',
      key: 'stack_decision',
      value: 'Use governed Hub retrieval so XT and Hub share one retrieval contract.',
      pinned: false,
    });
    assert.equal(canonical.err, null);

    const opened = invokeHubMemoryUnary(impl, 'GetOrCreateThread', {
      client,
      thread_key: 'xterminal_project_project_alpha',
    });
    assert.equal(opened.err, null);
    const threadId = String(opened.res?.thread?.thread_id || '');
    assert.ok(threadId);

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'append-turns-1',
      client,
      thread_id: threadId,
      messages: [
        { role: 'user', content: '我们之前定的 stack 是什么？' },
        { role: 'assistant', content: '之前决定保留 governed Hub retrieval。' },
      ],
      created_at_ms: Date.now(),
      allow_private: false,
    });
    assert.equal(appended.err, null);

    const out = invokeHubMemoryUnary(impl, 'RetrieveMemory', {
      schema_version: 'xt.memory_retrieval_request.v1',
      request_id: 'mem-req-1',
      client,
      scope: 'current_project',
      requester_role: 'chat',
      mode: 'project_chat',
      project_id: client.project_id,
      query: 'governed retrieval stack',
      latest_user: 'governed retrieval stack',
      allowed_layers: ['l1_canonical'],
      retrieval_kind: 'search',
      max_results: 2,
      require_explainability: true,
      requested_kinds: ['decision_track'],
      explicit_refs: [],
      max_snippets: 2,
      max_snippet_chars: 240,
      audit_ref: 'audit-memory-route-test-1',
    });

    assert.equal(out.err, null);
    assert.equal(out.res?.schema_version, 'xt.memory_retrieval_result.v1');
    assert.equal(out.res?.request_id, 'mem-req-1');
    assert.equal(out.res?.resolved_scope, 'current_project');
    assert.equal(out.res?.source, 'hub_memory_retrieval_grpc_v1');
    assert.equal(out.res?.audit_ref, 'audit-memory-route-test-1');
    assert.ok(Array.isArray(out.res?.results));
    assert.ok((out.res?.results?.length || 0) >= 1);
    assert.ok(String(out.res?.results?.[0]?.ref || '').startsWith('memory://hub/'));
    assert.ok(Number(out.res?.budget_used_chars || 0) > 0);

    const auditRows = db.listAuditEvents({
      device_id: client.device_id,
      request_id: 'mem-req-1',
    });
    assert.equal(auditRows.length, 1);
    assert.equal(String(auditRows[0]?.event_type || ''), 'memory.retrieval.performed');
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('RetrieveMemory supports explicit ref read and denies unsupported scope', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = makeClient();

    invokeHubMemoryUnary(impl, 'UpsertCanonicalMemory', {
      client,
      scope: 'project',
      thread_id: '',
      key: 'goal',
      value: 'Keep memory retrieval contract consistent across XT and Hub.',
      pinned: false,
    });

    const searched = invokeHubMemoryUnary(impl, 'RetrieveMemory', {
      schema_version: 'xt.memory_retrieval_request.v1',
      request_id: 'mem-req-2-search',
      client,
      scope: 'current_project',
      requester_role: 'supervisor',
      mode: 'supervisor_orchestration',
      project_id: client.project_id,
      query: 'contract consistent',
      latest_user: 'contract consistent',
      retrieval_kind: 'search',
      max_results: 1,
      explicit_refs: [],
      audit_ref: 'audit-memory-route-test-2-search',
    });
    assert.equal(searched.err, null);
    const ref = String(searched.res?.results?.[0]?.ref || '');
    assert.ok(ref.startsWith('memory://hub/'));

    const refRead = invokeHubMemoryUnary(impl, 'RetrieveMemory', {
      schema_version: 'xt.memory_retrieval_request.v1',
      request_id: 'mem-req-2-ref',
      client,
      scope: 'current_project',
      requester_role: 'supervisor',
      mode: 'supervisor_orchestration',
      project_id: client.project_id,
      query: '展开 ref',
      latest_user: '展开 ref',
      retrieval_kind: 'get_ref',
      explicit_refs: [ref],
      max_results: 1,
      audit_ref: 'audit-memory-route-test-2-ref',
    });
    assert.equal(refRead.err, null);
    assert.equal(refRead.res?.status, 'ok');
    assert.equal(refRead.res?.results?.length, 1);
    assert.equal(refRead.res?.results?.[0]?.ref, ref);

    const denied = invokeHubMemoryUnary(impl, 'RetrieveMemory', {
      schema_version: 'xt.memory_retrieval_request.v1',
      request_id: 'mem-req-2-denied',
      client,
      scope: 'device',
      requester_role: 'chat',
      mode: 'project_chat',
      project_id: client.project_id,
      query: 'not allowed',
      latest_user: 'not allowed',
      retrieval_kind: 'search',
      max_results: 1,
      audit_ref: 'audit-memory-route-test-2-denied',
    });
    assert.equal(denied.err, null);
    assert.equal(denied.res?.status, 'denied');
    assert.equal(denied.res?.deny_code, 'cross_scope_memory_denied');
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('RetrieveMemory returns governed coding runtime truth source kinds for current project artifacts', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  const projectRoot = makeTmp('project_root');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  fs.mkdirSync(projectRoot, { recursive: true });
  cleanupDbArtifacts(dbPath);
  seedGovernedCodingRuntimeArtifacts(projectRoot);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = {
      ...makeClient(),
      project_root: projectRoot,
    };

    const out = invokeHubMemoryUnary(impl, 'RetrieveMemory', {
      schema_version: 'xt.memory_retrieval_request.v1',
      request_id: 'mem-req-runtime-kinds',
      client,
      scope: 'current_project',
      requester_role: 'supervisor',
      mode: 'supervisor_orchestration',
      project_id: client.project_id,
      project_root: projectRoot,
      query: 'blocker retry guidance heartbeat checkpoint',
      latest_user: 'blocker retry guidance heartbeat checkpoint',
      allowed_layers: ['l1_canonical', 'l2_observations'],
      retrieval_kind: 'search',
      max_results: 6,
      requested_kinds: [
        'automation_checkpoint',
        'automation_execution_report',
        'automation_retry_package',
        'guidance_injection',
        'heartbeat_projection',
      ],
      explicit_refs: [],
      audit_ref: 'audit-memory-route-runtime-kinds',
    });

    assert.equal(out.err, null);
    assert.equal(out.res?.status, 'ok');
    const sourceKinds = new Set((out.res?.results || []).map((item) => String(item?.source_kind || '')));
    assert.ok(sourceKinds.has('automation_checkpoint'));
    assert.ok(sourceKinds.has('automation_execution_report'));
    assert.ok(sourceKinds.has('automation_retry_package'));
    assert.ok(sourceKinds.has('guidance_injection'));
    assert.ok(sourceKinds.has('heartbeat_projection'));
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(projectRoot, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('RetrieveMemory supports explicit ref read for governed coding runtime docs', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  const projectRoot = makeTmp('project_root');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  fs.mkdirSync(projectRoot, { recursive: true });
  cleanupDbArtifacts(dbPath);
  seedGovernedCodingRuntimeArtifacts(projectRoot);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = {
      ...makeClient(),
      project_root: projectRoot,
    };

    const searched = invokeHubMemoryUnary(impl, 'RetrieveMemory', {
      schema_version: 'xt.memory_retrieval_request.v1',
      request_id: 'mem-req-runtime-ref-search',
      client,
      scope: 'current_project',
      requester_role: 'supervisor',
      mode: 'supervisor_orchestration',
      project_id: client.project_id,
      project_root: projectRoot,
      query: 'latest guidance',
      latest_user: 'latest guidance',
      retrieval_kind: 'search',
      max_results: 3,
      requested_kinds: ['guidance_injection'],
      explicit_refs: [],
      audit_ref: 'audit-memory-route-runtime-ref-search',
    });
    assert.equal(searched.err, null);
    const ref = String(
      (searched.res?.results || []).find((item) => String(item?.source_kind || '') === 'guidance_injection')?.ref || ''
    );
    assert.match(ref, /^memory:\/\/hub\/runtime:guidance_injection:/);

    const refRead = invokeHubMemoryUnary(impl, 'RetrieveMemory', {
      schema_version: 'xt.memory_retrieval_request.v1',
      request_id: 'mem-req-runtime-ref-read',
      client,
      scope: 'current_project',
      requester_role: 'supervisor',
      mode: 'supervisor_orchestration',
      project_id: client.project_id,
      project_root: projectRoot,
      query: '展开 guidance ref',
      latest_user: '展开 guidance ref',
      retrieval_kind: 'get_ref',
      explicit_refs: [ref],
      max_results: 1,
      audit_ref: 'audit-memory-route-runtime-ref-read',
    });

    assert.equal(refRead.err, null);
    assert.equal(refRead.res?.status, 'ok');
    assert.equal(refRead.res?.results?.length, 1);
    assert.equal(refRead.res?.results?.[0]?.ref, ref);
    assert.equal(refRead.res?.results?.[0]?.source_kind, 'guidance_injection');
    assert.match(String(refRead.res?.results?.[0]?.snippet || ''), /guidance_summary/i);
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(projectRoot, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
