import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { loadClients } from './clients.js';
import { HubEventBus } from './event_bus.js';
import { responsePathForRequest } from './local_runtime_ipc.js';
import { makeServices, resolvePaidModelRuntimeAccess } from './services.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
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

async function withEnvAsync(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `xt_w328_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x55).toString('base64')}`;
const TRUSTED_AUTOMATION_TEST_CAPABILITIES = [
  'models',
  'events',
  'memory',
  'skills',
  'ai.generate.local',
  'ai.generate.paid',
  'web.fetch',
];
const TRUSTED_AUTOMATION_ALLOWED_WORKSPACE_ROOT = '/Users/andrew.xie/Documents/AX';

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_AUDIT_LEVEL: 'full_content',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '100',
  };
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

function writeModelsState(runtimeBaseDir, models) {
  writeJson(path.join(runtimeBaseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models,
  });
}

function writeProviderAwareMLXStatus(runtimeBaseDir, { ok, importError = '' }) {
  writeJson(path.join(runtimeBaseDir, 'ai_runtime_status.json'), {
    schema_version: 'xhub.local_runtime_status.v2',
    pid: 12345,
    updatedAt: Date.now() / 1000.0,
    mlxOk: !!ok,
    runtimeVersion: 'paired-terminal-policy-usage-test',
    providers: {
      mlx: {
        provider: 'mlx',
        ok: !!ok,
        reasonCode: ok ? 'ready' : 'import_error',
        importError,
        updatedAt: Date.now() / 1000.0,
      },
    },
  });
}

function seedGovernedCodingRuntimeArtifacts(projectRoot, projectId = 'proj-w328') {
  const stateDir = path.join(projectRoot, '.xterminal');
  const reportsDir = path.join(projectRoot, 'build', 'reports');
  fs.mkdirSync(stateDir, { recursive: true });
  fs.mkdirSync(reportsDir, { recursive: true });

  const checkpointPath = path.join(reportsDir, 'xt_w3_25_run_checkpoint_2.v1.json');
  const handoffPath = path.join(reportsDir, 'xt_automation_run_handoff_run-1.v1.json');
  const retryPath = path.join(reportsDir, 'xt_automation_retry_package_run-1-retry.v1.json');
  const guidancePath = path.join(stateDir, 'supervisor_guidance_injections.json');
  const heartbeatPath = path.join(stateDir, 'heartbeat_memory_projection.json');

  writeJson(checkpointPath, {
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
  writeJson(handoffPath, {
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
  writeJson(retryPath, {
    schema_version: 'xt.automation_retry_package.v1',
    generated_at: 124.0,
    project_id: projectId,
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
  writeJson(guidancePath, {
    schema_version: 'xt.supervisor_guidance_injection_snapshot.v1',
    updated_at_ms: 900,
    items: [
      {
        schema_version: 'xt.supervisor_guidance_injection.v1',
        injection_id: 'guidance-1',
        review_id: 'review-1',
        project_id: projectId,
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
  writeJson(heartbeatPath, {
    schema_version: 'xt.heartbeat_memory_projection.v1',
    project_id: projectId,
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
}

function makeTrustedAutomationClientEntry({
  deviceId,
  token,
  name,
  allowedProjectIds = ['project_alpha'],
  allowedWorkspaceRoots = [],
  devicePermissionOwnerRef = 'xt.device_permission_owner_readiness.v1:local_owner',
  xtBindingRequired = true,
}) {
  return {
    device_id: deviceId,
    user_id: deviceId,
    name,
    token,
    enabled: true,
    capabilities: TRUSTED_AUTOMATION_TEST_CAPABILITIES,
    policy_mode: 'new_profile',
    approved_trust_profile: makeApprovedTrustProfile({
      deviceId,
      deviceName: name,
      capabilities: TRUSTED_AUTOMATION_TEST_CAPABILITIES,
      mode: 'trusted_automation',
      state: 'armed',
      allowedProjectIds,
      allowedWorkspaceRoots,
      xtBindingRequired,
      autoGrantProfile: 'trusted_automation_default',
      devicePermissionOwnerRef,
      paidModelPolicyMode: 'all_paid_models',
    }),
  };
}

function makeApprovedTrustProfile({
  deviceId,
  deviceName,
  capabilities,
  trustMode = 'trusted_daily',
  mode = 'standard',
  state = 'off',
  allowedProjectIds = [],
  allowedWorkspaceRoots = [],
  xtBindingRequired = false,
  autoGrantProfile = '',
  devicePermissionOwnerRef = '',
  paidModelPolicyMode,
  allowedModelIds = [],
  defaultWebFetchEnabled = true,
  dailyTokenLimit = 500,
  singleRequestTokenLimit = 120,
  auditRef = 'audit-xt-w328',
}) {
  return {
    schema_version: 'hub.paired_terminal_trust_profile.v1',
    device_id: deviceId,
    device_name: deviceName,
    trust_mode: trustMode,
    mode,
    state,
    capabilities,
    allowed_project_ids: allowedProjectIds,
    allowed_workspace_roots: allowedWorkspaceRoots,
    xt_binding_required: xtBindingRequired,
    auto_grant_profile: autoGrantProfile,
    device_permission_owner_ref: devicePermissionOwnerRef,
    paid_model_policy: {
      schema_version: 'hub.paired_terminal_paid_model_policy.v1',
      mode: paidModelPolicyMode,
      allowed_model_ids: paidModelPolicyMode === 'custom_selected_models' ? allowedModelIds : [],
    },
    network_policy: {
      default_web_fetch_enabled: defaultWebFetchEnabled,
    },
    budget_policy: {
      daily_token_limit: dailyTokenLimit,
      single_request_token_limit: singleRequestTokenLimit,
    },
    audit_ref: auditRef,
  };
}

function writeClientsSnapshot(runtimeBaseDir, clients) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const snapshot = {
    schema_version: 'hub_grpc_clients.v1',
    updated_at_ms: Date.now(),
    clients,
  };
  fs.writeFileSync(
    path.join(runtimeBaseDir, 'hub_grpc_clients.json'),
    JSON.stringify(snapshot, null, 2) + '\n',
    'utf8'
  );
}

function makeClientCall({ request, token }) {
  const writes = [];
  let ended = false;
  return {
    request,
    writes,
    get ended() {
      return ended;
    },
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() === 'authorization') {
          return token ? [`Bearer ${token}`] : [];
        }
        return [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:54321';
    },
    write(payload) {
      writes.push(payload);
    },
    end() {
      ended = true;
    },
    on() {
      // no-op for targeted deny-path tests
    },
  };
}

function lastErrorCode(call) {
  const last = [...call.writes].reverse().find((item) => item?.error?.error?.code);
  return String(last?.error?.error?.code || '');
}

function lastGenerateError(call) {
  return [...(call?.writes || [])].reverse().find((item) => item?.error)?.error || null;
}

function lastGenerateDone(call) {
  return [...(call?.writes || [])].reverse().find((item) => item?.done)?.done || null;
}

async function satisfyLocalRuntimeRequest(runtimeBaseDir, requestId, onRequest = () => {}) {
  const reqPath = path.join(runtimeBaseDir, 'ai_requests', `req_${requestId}.json`);
  const respPath = responsePathForRequest(runtimeBaseDir, requestId);
  const deadline = Date.now() + 2000;

  while (Date.now() < deadline) {
    if (fs.existsSync(reqPath)) break;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }

  assert.equal(fs.existsSync(reqPath), true, 'expected runtime request file to be written');
  const req = JSON.parse(fs.readFileSync(reqPath, 'utf8'));
  onRequest(req);

  fs.mkdirSync(path.dirname(respPath), { recursive: true });
  const startedAt = Date.now() / 1000.0;
  const lines = [
    JSON.stringify({ type: 'start', req_id: requestId, model_id: String(req.model_id || ''), started_at: startedAt }),
    JSON.stringify({ type: 'delta', req_id: requestId, seq: 1, text: 'local-ok' }),
    JSON.stringify({ type: 'done', req_id: requestId, ok: true, reason: 'eos', promptTokens: 7, generationTokens: 3 }),
  ];
  fs.writeFileSync(respPath, `${lines.join('\n')}\n`, 'utf8');
  return req;
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

function auditExt(row) {
  try {
    return JSON.parse(String(row?.ext_json || '{}'));
  } catch {
    return {};
  }
}

function expectedGovernanceReadinessForDeny(denyCode) {
  const raw = String(denyCode || '').trim();
  if (!raw) return null;
  if (raw === 'trusted_automation_capabilities_empty_blocked') {
    return {
      componentKey: 'capability_ready',
      missingReason: 'capability_device_tools_unavailable',
    };
  }
  if (raw === 'device_permission_owner_missing') {
    return {
      componentKey: 'grant_ready',
      missingReason: 'permission_owner_not_ready',
    };
  }
  if (
    raw === 'trusted_automation_project_not_bound'
    || raw === 'trusted_automation_workspace_mismatch'
    || raw === 'trusted_automation_mode_off'
    || raw === 'trusted_automation_profile_missing'
  ) {
    return {
      componentKey: 'grant_ready',
      missingReason: 'trusted_automation_not_ready',
    };
  }
  return null;
}

function assertGovernanceRuntimeReadinessAudit(row, denyCode) {
  const expectation = expectedGovernanceReadinessForDeny(denyCode);
  if (!expectation) return;
  const ext = auditExt(row);
  if (!ext?.governance_runtime_readiness) return;
  assert.equal(Boolean(ext?.governance_runtime_readiness?.runtime_ready), false);
  assert.ok(
    Array.isArray(ext?.governance_runtime_readiness?.missing_reason_codes)
      && ext.governance_runtime_readiness.missing_reason_codes.includes(expectation.missingReason)
  );
  assert.ok(
    Array.isArray(ext?.governance_runtime_readiness?.blocked_component_keys)
      && ext.governance_runtime_readiness.blocked_component_keys.includes(expectation.componentKey)
  );
  assert.equal(
    String(ext?.governance_runtime_readiness?.components_by_xt_key?.[expectation.componentKey]?.state || ''),
    'blocked'
  );
}

async function assertTrustedAutomationProjectMismatch({
  runtimeLabel,
  dbLabel,
  deviceId,
  token,
  name,
  invoke,
  requestOverrides = {},
  requestId = '',
  event_type,
}) {
  await assertTrustedAutomationDenyAudit({
    runtimeLabel,
    dbLabel,
    deviceId,
    token,
    name,
    invoke,
    requestOverrides: {
      ...requestOverrides,
      client: {
        ...((requestOverrides.client && typeof requestOverrides.client === 'object') ? requestOverrides.client : {}),
        project_id: 'project_beta',
      },
    },
    requestId,
    event_type,
    denyCode: 'trusted_automation_project_not_bound',
  });
}

async function assertTrustedAutomationDenyAudit({
  runtimeLabel,
  dbLabel,
  deviceId,
  token,
  name,
  invoke,
  requestOverrides = {},
  requestId = '',
  event_type,
  denyCode,
  allowedProjectIds = ['project_alpha'],
  allowedWorkspaceRoots = [],
  devicePermissionOwnerRef = 'xt.device_permission_owner_readiness.v1:local_owner',
  xtBindingRequired = true,
}) {
  const runtimeBaseDir = makeTmp(runtimeLabel);
  const dbPath = makeTmp(dbLabel, '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const clientEntry = makeTrustedAutomationClientEntry({
        deviceId,
        token,
        name,
        allowedProjectIds,
        allowedWorkspaceRoots,
        devicePermissionOwnerRef,
        xtBindingRequired,
      });
      await assert.rejects(
        invoke({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides,
        }),
        (error) => {
          assert.equal(String(error?.message || ''), String(denyCode || ''));
          return true;
        }
      );
      const row = assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type,
        error_code: denyCode,
      });
      assertGovernanceRuntimeReadinessAudit(row, denyCode);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
}

async function invokeHubMemoryUnary({ db, runtimeBaseDir, clientEntry, rpcName, baseRequest = {}, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      ...baseRequest,
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory[rpcName](call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeGenerate({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const request = {
    request_id: `rid_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    model_id: 'openai/gpt-4.1',
    max_tokens: 32,
    messages: [{ role: 'user', content: 'hello from XT-W3-28' }],
    ...requestOverrides,
    client: {
      ...baseClient,
      ...overrideClient,
    },
  };
  const call = makeClientCall({ request, token: clientEntry.token });
  await impl.HubAI.Generate(call);
  return call;
}

async function invokeListModels({ db, runtimeBaseDir, clientEntry }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const call = makeClientCall({
    request: {},
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubModels.ListModels(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeSearchSkills({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      query: 'trusted automation',
      limit: 5,
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubSkills.SearchSkills(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeGetOrCreateThread({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      thread_key: 'default',
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.GetOrCreateThread(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeRetrieveMemory({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'RetrieveMemory',
    baseRequest: {
      schema_version: 'xt.memory_retrieval_request.v1',
      request_id: `mem_retr_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      scope: 'current_project',
      requester_role: 'chat',
      mode: 'project_chat',
      query: 'governed retrieval',
      latest_user: 'governed retrieval',
      retrieval_kind: 'search',
      max_results: 3,
      require_explainability: true,
      requested_kinds: ['decision_track'],
      explicit_refs: [],
      max_snippets: 3,
      max_snippet_chars: 320,
      audit_ref: 'audit-paired-terminal-memory-retrieval',
    },
    requestOverrides,
  });
}

async function invokeEvaluateRiskTuningProfile({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      request_id: `risk_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      profile: { profile_id: 'risk-profile-1' },
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.EvaluateRiskTuningProfile(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeAgentSessionOpen({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      request_id: `agent_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      agent_instance_id: 'agent-instance-1',
      agent_name: 'test-agent',
      agent_version: '1.0.0',
      gateway_provider: 'hub',
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.AgentSessionOpen(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeCreatePaymentIntent({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      request_id: `pay_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      amount_minor: 100,
      currency: 'usd',
      merchant_id: 'merchant-1',
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.CreatePaymentIntent(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeLongtermMarkdownExport({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      scope: 'all',
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.LongtermMarkdownExport(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokePromoteRiskTuningProfile({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'PromoteRiskTuningProfile',
    baseRequest: {
      request_id: `risk_promote_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      profile_id: 'risk-profile-1',
      expected_active_profile_id: 'risk-active-1',
    },
    requestOverrides,
  });
}

async function invokeIssueVoiceGrantChallenge({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'IssueVoiceGrantChallenge',
    baseRequest: {
      request_id: `voice_issue_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      template_id: 'voice-template-1',
      risk_level: 'high',
      mobile_terminal_id: 'mobile-1',
    },
    requestOverrides,
  });
}

async function invokeVerifyVoiceGrantResponse({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'VerifyVoiceGrantResponse',
    baseRequest: {
      request_id: `voice_verify_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      challenge_id: 'voice-challenge-1',
      transcript_hash: 'sha256:voice-transcript',
    },
    requestOverrides,
  });
}

async function invokeRegisterAgentCapsule({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'RegisterAgentCapsule',
    baseRequest: {
      request_id: `capsule_register_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      capsule_id: 'capsule-1',
      agent_name: 'agent-capsule',
      agent_version: '1.0.0',
    },
    requestOverrides,
  });
}

async function invokeVerifyAgentCapsule({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'VerifyAgentCapsule',
    baseRequest: {
      request_id: `capsule_verify_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      capsule_id: 'capsule-1',
    },
    requestOverrides,
  });
}

async function invokeActivateAgentCapsule({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'ActivateAgentCapsule',
    baseRequest: {
      request_id: `capsule_activate_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      capsule_id: 'capsule-1',
    },
    requestOverrides,
  });
}

async function invokeAttachPaymentEvidence({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'AttachPaymentEvidence',
    baseRequest: {
      request_id: `pay_evidence_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      intent_id: 'intent-1',
      evidence: {
        price_amount_minor: 100,
        currency: 'USD',
        merchant_id: 'merchant-1',
        nonce: 'nonce-1',
      },
    },
    requestOverrides,
  });
}

async function invokeIssuePaymentChallenge({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'IssuePaymentChallenge',
    baseRequest: {
      request_id: `pay_challenge_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      intent_id: 'intent-1',
      mobile_terminal_id: 'mobile-1',
    },
    requestOverrides,
  });
}

async function invokeConfirmPaymentIntent({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'ConfirmPaymentIntent',
    baseRequest: {
      request_id: `pay_confirm_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      intent_id: 'intent-1',
      challenge_id: 'challenge-1',
      mobile_terminal_id: 'mobile-1',
      auth_factor: 'voice+device',
    },
    requestOverrides,
  });
}

async function invokeAbortPaymentIntent({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'AbortPaymentIntent',
    baseRequest: {
      request_id: `pay_abort_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      intent_id: 'intent-1',
      reason: 'operator_cancelled',
    },
    requestOverrides,
  });
}

async function invokeLongtermMarkdownBeginEdit({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'LongtermMarkdownBeginEdit',
    baseRequest: {
      scope: 'all',
    },
    requestOverrides,
  });
}

async function invokeLongtermMarkdownApplyPatch({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'LongtermMarkdownApplyPatch',
    baseRequest: {
      edit_session_id: 'edit-session-1',
      base_version: 'v1',
      session_revision: 0,
      patch_mode: 'replace',
      patch_markdown: '# patched',
    },
    requestOverrides,
  });
}

async function invokeLongtermMarkdownReview({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'LongtermMarkdownReview',
    baseRequest: {
      pending_change_id: 'change-1',
      expected_status: 'draft',
      review_decision: 'approve',
      on_secret: 'deny',
    },
    requestOverrides,
  });
}

async function invokeLongtermMarkdownWriteback({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'LongtermMarkdownWriteback',
    baseRequest: {
      pending_change_id: 'change-1',
      expected_status: 'approved',
    },
    requestOverrides,
  });
}

async function invokeLongtermMarkdownRollback({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  return invokeHubMemoryUnary({
    db,
    runtimeBaseDir,
    clientEntry,
    rpcName: 'LongtermMarkdownRollback',
    baseRequest: {
      pending_change_id: 'change-1',
      expected_status: 'written',
    },
    requestOverrides,
  });
}

async function invokeUpsertProjectLineage({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const overrideLineage = requestOverrides.lineage && typeof requestOverrides.lineage === 'object'
    ? requestOverrides.lineage
    : {};
  const baseRequest = {
    request_id: `lineage_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    lineage: {
      root_project_id: 'proj-w328',
      project_id: 'proj-w328',
      lineage_path: 'proj-w328',
    },
  };
  const call = makeClientCall({
    request: {
      ...baseRequest,
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
      lineage: {
        ...baseRequest.lineage,
        ...overrideLineage,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.UpsertProjectLineage(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeGetProjectLineageTree({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      root_project_id: 'proj-w328',
      project_id: '',
      max_depth: 0,
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.GetProjectLineageTree(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeAttachDispatchContext({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const overrideDispatch = requestOverrides.dispatch && typeof requestOverrides.dispatch === 'object'
    ? requestOverrides.dispatch
    : {};
  const baseRequest = {
    request_id: `dispatch_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    dispatch: {
      root_project_id: 'proj-w328',
      project_id: 'proj-w328',
      assigned_agent_profile: 'agent-default',
    },
  };
  const call = makeClientCall({
    request: {
      ...baseRequest,
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
      dispatch: {
        ...baseRequest.dispatch,
        ...overrideDispatch,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.AttachDispatchContext(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeProjectHeartbeat({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const overrideHeartbeat = requestOverrides.heartbeat && typeof requestOverrides.heartbeat === 'object'
    ? requestOverrides.heartbeat
    : {};
  const baseRequest = {
    request_id: `heartbeat_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    heartbeat: {
      root_project_id: 'proj-w328',
      project_id: 'proj-w328',
      heartbeat_seq: 1,
      sent_at_ms: Date.now(),
    },
  };
  const call = makeClientCall({
    request: {
      ...baseRequest,
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
      heartbeat: {
        ...baseRequest.heartbeat,
        ...overrideHeartbeat,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.ProjectHeartbeat(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

async function invokeGetDispatchPlan({ db, runtimeBaseDir, clientEntry, requestOverrides = {} }) {
  writeClientsSnapshot(runtimeBaseDir, [clientEntry]);
  const impl = makeServices({ db, bus: new HubEventBus() });
  const baseClient = {
    device_id: clientEntry.device_id,
    user_id: clientEntry.user_id,
    app_id: 'xt-w328-test',
    project_id: 'proj-w328',
  };
  const overrideClient = requestOverrides.client && typeof requestOverrides.client === 'object'
    ? requestOverrides.client
    : {};
  const call = makeClientCall({
    request: {
      request_id: `plan_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      root_project_id: 'proj-w328',
      max_projects: 4,
      ...requestOverrides,
      client: {
        ...baseClient,
        ...overrideClient,
      },
    },
    token: clientEntry.token,
  });
  return await new Promise((resolve, reject) => {
    impl.HubMemory.GetDispatchPlan(call, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response);
    });
  });
}

run('resolver emits all frozen deny codes', () => {
  const baseClient = {
    device_id: 'dev-resolver',
    name: 'Resolver Device',
    policy_mode: 'new_profile',
    trust_profile_present: true,
    paid_model_policy_mode: 'all_paid_models',
    paid_model_allowed_model_ids: [],
    daily_token_limit: 500,
    single_request_token_limit: 100,
    default_web_fetch_enabled: true,
  };

  const allowed = resolvePaidModelRuntimeAccess({
    runtimeClient: baseClient,
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
    requestedTotalTokensEstimate: 80,
    usedTokensToday: 120,
  });
  assert.equal(allowed.allow, true);

  const disabled = resolvePaidModelRuntimeAccess({
    runtimeClient: { ...baseClient, paid_model_policy_mode: 'off' },
    capabilityAllowed: false,
    modelId: 'openai/gpt-4.1',
  });
  assert.equal(disabled.deny_code, 'device_paid_model_disabled');

  const notAllowed = resolvePaidModelRuntimeAccess({
    runtimeClient: {
      ...baseClient,
      paid_model_policy_mode: 'custom_selected_models',
      paid_model_allowed_model_ids: ['anthropic/claude-3-7-sonnet'],
    },
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
  });
  assert.equal(notAllowed.deny_code, 'device_paid_model_not_allowed');

  const singleExceeded = resolvePaidModelRuntimeAccess({
    runtimeClient: baseClient,
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
    requestedTotalTokensEstimate: 140,
    usedTokensToday: 0,
  });
  assert.equal(singleExceeded.deny_code, 'device_single_request_token_exceeded');

  const dailyExceeded = resolvePaidModelRuntimeAccess({
    runtimeClient: baseClient,
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
    requestedTotalTokensEstimate: 30,
    usedTokensToday: 490,
  });
  assert.equal(dailyExceeded.deny_code, 'device_daily_token_budget_exceeded');

  const strictEmptyCaps = resolvePaidModelRuntimeAccess({
    runtimeClient: {
      ...baseClient,
      trusted_automation_mode: 'trusted_automation',
      trusted_automation_state: 'armed',
    },
    capabilityAllowed: false,
    capabilityDenyCode: 'trusted_automation_capabilities_empty_blocked',
    modelId: 'openai/gpt-4.1',
  });
  assert.equal(strictEmptyCaps.deny_code, 'trusted_automation_capabilities_empty_blocked');

  const legacy = resolvePaidModelRuntimeAccess({
    runtimeClient: null,
    capabilityAllowed: true,
    modelId: 'openai/gpt-4.1',
  });
  assert.equal(legacy.deny_code, 'legacy_grant_flow_required');
});

run('loadClients normalizes trusted automation fields from approved trust profile', () => {
  const runtimeBaseDir = makeTmp('runtime_tam_profile');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  writeClientsSnapshot(runtimeBaseDir, [{
    device_id: 'dev-tam-profile',
    user_id: 'dev-tam-profile',
    name: 'Trusted Automation Device',
    token: 'tok-tam-profile',
    enabled: true,
    capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
    policy_mode: 'new_profile',
    approved_trust_profile: makeApprovedTrustProfile({
      deviceId: 'dev-tam-profile',
      deviceName: 'Trusted Automation Device',
      capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
      mode: 'trusted_automation',
      state: 'armed',
      allowedProjectIds: ['project_alpha', 'project_alpha'],
      allowedWorkspaceRoots: ['/Users/andrew.xie/Documents/AX'],
      xtBindingRequired: true,
      autoGrantProfile: 'trusted_automation_default',
      devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
      paidModelPolicyMode: 'all_paid_models',
    }),
  }]);
  try {
    const [client] = loadClients(runtimeBaseDir, 0);
    assert.ok(client);
    assert.equal(client.trusted_automation_mode, 'trusted_automation');
    assert.equal(client.trusted_automation_state, 'armed');
    assert.deepEqual(client.allowed_project_ids, ['project_alpha']);
    assert.deepEqual(client.allowed_workspace_roots, ['/Users/andrew.xie/Documents/AX']);
    assert.equal(client.xt_binding_required, true);
    assert.equal(client.auto_grant_profile, 'trusted_automation_default');
    assert.equal(client.device_permission_owner_ref, 'xt.device_permission_owner_readiness.v1:local_owner');
    assert.equal(client.approved_trust_profile.mode, 'trusted_automation');
    assert.equal(client.approved_trust_profile.state, 'armed');
  } finally {
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

run('db metering tracks device/model/day usage summary fields', () => {
  const runtimeBaseDir = makeTmp('runtime_db');
  const dbPath = makeTmp('db_usage', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const dayBucket = '2026-03-08';
      db.recordTerminalModelUsageDaily({
        device_id: 'dev-usage',
        device_name: 'Usage Device',
        model_id: 'openai/gpt-4.1',
        day_bucket: dayBucket,
        prompt_tokens: 11,
        completion_tokens: 7,
        total_tokens: 18,
        last_used_at_ms: 1000,
      });
      db.recordTerminalModelUsageDaily({
        device_id: 'dev-usage',
        device_name: 'Usage Device',
        model_id: 'openai/gpt-4.1',
        day_bucket: dayBucket,
        prompt_tokens: 9,
        completion_tokens: 3,
        total_tokens: 12,
        last_used_at_ms: 2000,
      });
      db.recordTerminalModelBlockedDaily({
        device_id: 'dev-usage',
        device_name: 'Usage Device',
        model_id: 'openai/gpt-4.1',
        day_bucket: dayBucket,
        last_blocked_at_ms: 2500,
        last_blocked_reason: 'device_paid_model_not_allowed',
        last_deny_code: 'device_paid_model_not_allowed',
      });

      const rows = db.listTerminalModelUsageDaily({ device_id: 'dev-usage', day_bucket: dayBucket, limit: 5 });
      assert.equal(rows.length, 1);
      assert.equal(rows[0].device_id, 'dev-usage');
      assert.equal(rows[0].device_name, 'Usage Device');
      assert.equal(rows[0].model_id, 'openai/gpt-4.1');
      assert.equal(rows[0].day_bucket, dayBucket);
      assert.equal(rows[0].total_tokens, 30);
      assert.equal(rows[0].request_count, 2);
      assert.equal(rows[0].blocked_count, 1);

      const summary = db.getTerminalUsageSummaryDaily({ device_id: 'dev-usage', day_bucket: dayBucket });
      assert.equal(summary.device_id, 'dev-usage');
      assert.equal(summary.day_bucket, dayBucket);
      assert.equal(summary.total_tokens, 30);
      assert.equal(summary.request_count, 2);
      assert.equal(summary.blocked_count, 1);
      assert.equal(summary.top_model, 'openai/gpt-4.1');
      assert.equal(summary.last_deny_code, 'device_paid_model_not_allowed');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_paid_model_disabled for new-profile off mode', async () => {
  const runtimeBaseDir = makeTmp('runtime_disabled');
  const dbPath = makeTmp('db_disabled', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-disabled';
      const token = 'tok-disabled';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Disabled Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Disabled Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local'],
          paidModelPolicyMode: 'off',
        }),
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'device_paid_model_disabled');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_paid_model_not_allowed and writes dashboard snapshot', async () => {
  const runtimeBaseDir = makeTmp('runtime_not_allowed');
  const dbPath = makeTmp('db_not_allowed', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-not-allowed';
      const token = 'tok-not-allowed';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        app_id: 'x_terminal',
        name: 'Allowlist Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Allowlist Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          paidModelPolicyMode: 'custom_selected_models',
          allowedModelIds: ['anthropic/claude-3-7-sonnet'],
          dailyTokenLimit: 500,
          singleRequestTokenLimit: 128,
        }),
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'device_paid_model_not_allowed');

      const snapshot = JSON.parse(fs.readFileSync(path.join(runtimeBaseDir, 'grpc_devices_status.json'), 'utf8'));
      const device = (snapshot.devices || []).find((item) => item.device_id === deviceId);
      assert.ok(device);
      assert.equal(String(device.app_id || ''), 'x_terminal');
      assert.equal(device.paid_model_policy_mode, 'custom_selected_models');
      assert.equal(device.daily_token_limit, 500);
      assert.equal(device.remaining_daily_token_budget, 500);
      assert.equal(device.last_deny_code, 'device_paid_model_not_allowed');
      assert.ok(Array.isArray(device.model_breakdown));
      assert.equal(device.model_breakdown[0].device_id, deviceId);
      assert.equal(device.model_breakdown[0].model_id, 'openai/gpt-4.1');
      assert.equal(device.model_breakdown[0].blocked_count, 1);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_single_request_token_exceeded for trusted profile budget gate', async () => {
  const runtimeBaseDir = makeTmp('runtime_single');
  const dbPath = makeTmp('db_single', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-single-budget';
      const token = 'tok-single-budget';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Single Budget Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Single Budget Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
          paidModelPolicyMode: 'all_paid_models',
          dailyTokenLimit: 500,
          singleRequestTokenLimit: 8,
        }),
      };
      const call = await invokeGenerate({
        db,
        runtimeBaseDir,
        clientEntry,
        requestOverrides: {
          max_tokens: 32,
          messages: [{ role: 'user', content: 'single request should exceed budget' }],
        },
      });
      assert.equal(lastErrorCode(call), 'device_single_request_token_exceeded');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('list models returns paired terminal paid access budget truth', async () => {
  const runtimeBaseDir = makeTmp('runtime_list_models_paid_access_truth');
  const dbPath = makeTmp('db_list_models_paid_access_truth', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-list-models-budget';
      const token = 'tok-list-models-budget';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'List Models Budget Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'List Models Budget Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          paidModelPolicyMode: 'all_paid_models',
          dailyTokenLimit: 640,
          singleRequestTokenLimit: 256,
        }),
      };

      const response = await invokeListModels({ db, runtimeBaseDir, clientEntry });
      assert.equal(response.trust_profile_present, true);
      assert.equal(response.paid_model_policy_mode, 'all_paid_models');
      assert.equal(response.daily_token_limit, 640);
      assert.equal(response.single_request_token_limit, 256);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_daily_token_budget_exceeded when usage summary is near cap', async () => {
  const runtimeBaseDir = makeTmp('runtime_daily');
  const dbPath = makeTmp('db_daily', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const dayBucket = '2026-03-08';
      db.recordTerminalModelUsageDaily({
        device_id: 'dev-daily-budget',
        device_name: 'Daily Budget Device',
        model_id: 'openai/gpt-4.1',
        day_bucket: dayBucket,
        prompt_tokens: 220,
        completion_tokens: 220,
        total_tokens: 440,
        last_used_at_ms: Date.now(),
      });
      const deviceId = 'dev-daily-budget';
      const token = 'tok-daily-budget';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Daily Budget Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Daily Budget Device',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
          paidModelPolicyMode: 'all_paid_models',
          dailyTokenLimit: 450,
          singleRequestTokenLimit: 64,
        }),
      };
      const call = await invokeGenerate({
        db,
        runtimeBaseDir,
        clientEntry,
        requestOverrides: {
          created_at_ms: Date.parse('2026-03-08T12:00:00Z'),
          max_tokens: 32,
          messages: [{ role: 'user', content: 'daily budget should be exceeded' }],
        },
      });
      assert.equal(lastErrorCode(call), 'device_daily_token_budget_exceeded');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns legacy_grant_flow_required for legacy paired device', async () => {
  const runtimeBaseDir = makeTmp('runtime_legacy');
  const dbPath = makeTmp('db_legacy', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-legacy';
      const token = 'tok-legacy';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Legacy Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
        policy_mode: 'legacy_grant',
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'legacy_grant_flow_required');
      assert.equal(lastErrorCode(call) === 'grant_required', false);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate denied error exposes route audit metadata for legacy grant path', async () => {
  const runtimeBaseDir = makeTmp('runtime_legacy_audit');
  const dbPath = makeTmp('db_legacy_audit', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-legacy-audit';
      const token = 'tok-legacy-audit';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Legacy Audit Device',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid'],
        policy_mode: 'legacy_grant',
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      const errorEvent = lastGenerateError(call);
      assert.ok(errorEvent);
      assert.equal(String(errorEvent?.error?.code || ''), 'legacy_grant_flow_required');
      assert.equal(String(errorEvent?.model_id || ''), 'openai/gpt-4.1');
      assert.equal(String(errorEvent?.runtime_provider || ''), 'Hub (Remote)');
      assert.equal(String(errorEvent?.execution_path || ''), 'remote_error');
      assert.equal(String(errorEvent?.deny_code || ''), 'legacy_grant_flow_required');
      assert.ok(String(errorEvent?.audit_ref || '').length > 0);

      const auditRow = assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: String(call.request?.request_id || ''),
        event_type: 'ai.generate.denied',
        error_code: 'legacy_grant_flow_required',
      });
      assert.equal(String(errorEvent?.audit_ref || ''), String(auditRow?.event_id || ''));
      const ext = auditExt(auditRow);
      assert.equal(String(ext?.governance_runtime_readiness?.schema_version || ''), 'xhub.governance_runtime_readiness.v1');
      assert.equal(Boolean(ext?.governance_runtime_readiness?.runtime_ready), false);
      assert.equal(String(ext?.governance_runtime_readiness?.components?.grant?.deny_code || ''), 'legacy_grant_flow_required');
      assert.equal(Boolean(ext?.governance_runtime_readiness?.components?.capability?.ready), true);
      assert.equal(Boolean(ext?.governance_runtime_readiness?.components?.checkpoint_recovery?.ready), true);
      assert.equal(Boolean(ext?.governance_runtime_readiness?.components?.evidence_export?.ready), true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate done exposes downgrade audit metadata after remote export local fallback', async () => {
  const runtimeBaseDir = makeTmp('runtime_downgrade_done');
  const dbPath = makeTmp('db_downgrade_done', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(
    {
      ...baseEnv(runtimeBaseDir),
      HUB_REMOTE_EXPORT_ON_BLOCK: 'downgrade_to_local',
      HUB_REMOTE_EXPORT_SECRET_MODE: 'deny',
      HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '1500',
    },
    async () => {
      writeModelsState(runtimeBaseDir, [
        {
          model_id: 'mlx/qwen2.5-7b-instruct',
          name: 'Qwen 2.5 7B',
          kind: 'local_offline',
          backend: 'mlx',
          task_kinds: ['text_generate'],
        },
      ]);
      writeProviderAwareMLXStatus(runtimeBaseDir, { ok: true });

      const db = new HubDB({ dbPath });
      try {
        const deviceId = 'dev-downgrade-done';
        const token = 'tok-downgrade-done';
        const clientEntry = {
          device_id: deviceId,
          user_id: deviceId,
          name: 'Downgrade Done Device',
          token,
          enabled: true,
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          policy_mode: 'new_profile',
          approved_trust_profile: makeApprovedTrustProfile({
            deviceId,
            deviceName: 'Downgrade Done Device',
            capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
            paidModelPolicyMode: 'all_paid_models',
          }),
        };
        const requestId = `rid_down_done_${Date.now()}_${Math.random().toString(16).slice(2)}`;
        const callPromise = invokeGenerate({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            messages: [{ role: 'user', content: 'Please export [private]payment pin 7788[/private]' }],
          },
        });

        const runtimeRequest = await satisfyLocalRuntimeRequest(runtimeBaseDir, requestId);
        const call = await callPromise;
        const doneEvent = lastGenerateDone(call);
        assert.ok(doneEvent);
        assert.equal(doneEvent.ok, true);
        assert.equal(String(doneEvent.actual_model_id || ''), 'mlx/qwen2.5-7b-instruct');
        assert.equal(String(doneEvent.runtime_provider || ''), 'Hub (Local)');
        assert.equal(String(doneEvent.execution_path || ''), 'hub_downgraded_to_local');
        assert.ok(String(doneEvent.audit_ref || '').length > 0);
        assert.ok(String(doneEvent.deny_code || '').length > 0);
        assert.equal(String(runtimeRequest.model_id || ''), 'mlx/qwen2.5-7b-instruct');

        const rows = db.listAuditEvents({ device_id: deviceId, request_id: requestId }) || [];
        const downgradedRow = rows.find((row) =>
          String(row?.event_type || '') === 'ai.generate.downgraded_to_local'
        );
        assert.ok(downgradedRow);
        assert.equal(String(doneEvent.audit_ref || ''), String(downgradedRow?.event_id || ''));
        assert.equal(String(doneEvent.deny_code || ''), String(downgradedRow?.error_code || ''));
      } finally {
        db.close();
      }
    }
  );

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate memory route injects governed coding runtime truth into prompt assembly', async () => {
  const runtimeBaseDir = makeTmp('runtime_memory_runtime_truth');
  const dbPath = makeTmp('db_memory_runtime_truth', '.db');
  const projectRoot = makeTmp('project_root_memory_runtime_truth');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  fs.mkdirSync(projectRoot, { recursive: true });

  await withEnvAsync(
    {
      ...baseEnv(runtimeBaseDir),
      HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS: '1500',
    },
    async () => {
      writeModelsState(runtimeBaseDir, [
        {
          model_id: 'mlx/qwen2.5-7b-instruct',
          name: 'Qwen 2.5 7B',
          kind: 'local_offline',
          backend: 'mlx',
          task_kinds: ['text_generate'],
        },
      ]);
      writeProviderAwareMLXStatus(runtimeBaseDir, { ok: true });
      seedGovernedCodingRuntimeArtifacts(projectRoot, 'proj-w328');

      const db = new HubDB({ dbPath });
      try {
        const deviceId = 'dev-memory-runtime-truth';
        const token = 'tok-memory-runtime-truth';
        const clientEntry = makeTrustedAutomationClientEntry({
          deviceId,
          token,
          name: 'Memory Runtime Truth Device',
          allowedProjectIds: ['proj-w328'],
        });
        const thread = await invokeGetOrCreateThread({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            thread_key: 'xterminal_project_proj-w328',
            client: {
              project_root: projectRoot,
            },
          },
        });
        const threadId = String(thread?.thread?.thread_id || '');
        assert.ok(threadId);

        const requestId = `rid_memory_runtime_truth_${Date.now()}_${Math.random().toString(16).slice(2)}`;
        const callPromise = invokeGenerate({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            model_id: 'mlx/qwen2.5-7b-instruct',
            thread_id: threadId,
            messages: [{ role: 'user', content: '请结合 checkpoint blocker retry guidance heartbeat 继续推进' }],
            client: {
              project_root: projectRoot,
            },
          },
        });

        const runtimeRequest = await satisfyLocalRuntimeRequest(runtimeBaseDir, requestId, (req) => {
          const prompt = String(req?.prompt || '');
          assert.match(prompt, /\[GOVERNED CODING RUNTIME TRUTH\]/);
          assert.match(prompt, /source_kind=guidance_injection/);
          assert.match(prompt, /guidance_summary: Pause the broader rollout and reduce the verify scope before the next retry\./);
          assert.match(prompt, /source_kind=automation_retry_package/);
          assert.match(prompt, /retry_strategy: shrink_verify_scope/);
          assert.match(prompt, /source_kind=heartbeat_projection/);
          assert.match(prompt, /blocker_summary: Smoke tests are still red\./);
        });
        const call = await callPromise;
        const doneEvent = lastGenerateDone(call);
        assert.ok(doneEvent);
        assert.equal(String(runtimeRequest.model_id || ''), 'mlx/qwen2.5-7b-instruct');
        assert.ok(doneEvent.memory_prompt_projection);
        assert.ok(Number(doneEvent.memory_prompt_projection.runtime_truth_item_count || 0) >= 1);
        assert.ok(
          Array.isArray(doneEvent.memory_prompt_projection.runtime_truth_source_kinds)
          && doneEvent.memory_prompt_projection.runtime_truth_source_kinds.includes('guidance_injection')
        );

        const routeRow = assertAuditEvent(db, {
          device_id: deviceId,
          user_id: deviceId,
          request_id: requestId,
          event_type: 'memory.route.applied',
        });
        const ext = JSON.parse(String(routeRow?.ext_json || '{}'));
        assert.ok(ext?.retrieval?.prompt_projection);
        assert.ok(Number(ext.retrieval.prompt_projection.runtime_truth_item_count || 0) >= 1);
        assert.ok(
          Array.isArray(ext.retrieval.prompt_projection.runtime_truth_source_kinds)
          && ext.retrieval.prompt_projection.runtime_truth_source_kinds.includes('guidance_injection')
        );
      } finally {
        db.close();
      }
    }
  );

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(projectRoot, { recursive: true, force: true }); } catch { /* ignore */ }
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns trusted_automation_capabilities_empty_blocked for strict empty capabilities', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_empty_caps');
  const dbPath = makeTmp('db_tam_empty_caps', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-empty-caps';
      const token = 'tok-tam-empty-caps';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Empty Caps',
        token,
        enabled: true,
        capabilities: [],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Empty Caps',
          capabilities: [],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['proj-w328'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
          dailyTokenLimit: 500,
          singleRequestTokenLimit: 128,
        }),
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'trusted_automation_capabilities_empty_blocked');
      const auditRow = assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: String(call.request?.request_id || ''),
        event_type: 'ai.generate.denied',
        error_code: 'trusted_automation_capabilities_empty_blocked',
      });
      assertGovernanceRuntimeReadinessAudit(auditRow, 'trusted_automation_capabilities_empty_blocked');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('list models returns trusted_automation_capabilities_empty_blocked for strict empty capabilities', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_models_empty_caps');
  const dbPath = makeTmp('db_tam_models_empty_caps', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-models-empty-caps';
      const token = 'tok-tam-models-empty-caps';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Models Empty Caps',
        token,
        enabled: true,
        capabilities: [],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Models Empty Caps',
          capabilities: [],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['proj-w328'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeListModels({ db, runtimeBaseDir, clientEntry }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_capabilities_empty_blocked');
          return true;
        }
      );
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_project_mismatch');
  const dbPath = makeTmp('db_tam_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-project-mismatch';
      const token = 'tok-tam-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      const call = await invokeGenerate({
        db,
        runtimeBaseDir,
        clientEntry,
        requestOverrides: {
          client: {
            project_id: 'project_beta',
          },
        },
      });
      assert.equal(lastErrorCode(call), 'trusted_automation_project_not_bound');
      const auditRow = assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: String(call.request?.request_id || ''),
        event_type: 'ai.generate.denied',
        error_code: 'trusted_automation_project_not_bound',
      });
      const ext = auditExt(auditRow);
      assert.equal(String(ext?.governance_runtime_readiness?.components?.grant?.deny_code || ''), 'trusted_automation_project_not_bound');
      assert.equal(Boolean(ext?.governance_runtime_readiness?.components?.route?.ready), true);
      assert.equal(Boolean(ext?.governance_runtime_readiness?.components?.capability?.ready), true);
      assert.ok(
        Array.isArray(ext?.governance_runtime_readiness?.missing_reason_codes)
          && ext.governance_runtime_readiness.missing_reason_codes.includes('trusted_automation_not_ready')
      );
      assert.equal(
        String(ext?.governance_runtime_readiness?.components_by_xt_key?.grant_ready?.state || ''),
        'blocked'
      );
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns device_permission_owner_missing when xt binding has no local owner ref', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_owner_missing');
  const dbPath = makeTmp('db_tam_owner_missing', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-owner-missing';
      const token = 'tok-tam-owner-missing';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Owner Missing',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Owner Missing',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['proj-w328'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: '',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      const call = await invokeGenerate({ db, runtimeBaseDir, clientEntry });
      assert.equal(lastErrorCode(call), 'device_permission_owner_missing');
      const auditRow = assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: String(call.request?.request_id || ''),
        event_type: 'ai.generate.denied',
        error_code: 'device_permission_owner_missing',
      });
      assertGovernanceRuntimeReadinessAudit(auditRow, 'device_permission_owner_missing');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('generate returns trusted_automation_workspace_mismatch for workspace-bound trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_workspace_mismatch');
  const dbPath = makeTmp('db_tam_workspace_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-workspace-mismatch';
      const token = 'tok-tam-workspace-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Workspace Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Workspace Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: [],
          allowedWorkspaceRoots: ['/Users/andrew.xie/Documents/AX'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      const call = await invokeGenerate({
        db,
        runtimeBaseDir,
        clientEntry,
        requestOverrides: {
          client: {
            project_id: '',
            project_root: '/tmp/untrusted-workspace',
          },
        },
      });
      assert.equal(lastErrorCode(call), 'trusted_automation_workspace_mismatch');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('search skills returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_skills_project_mismatch');
  const dbPath = makeTmp('db_tam_skills_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-skills-project-mismatch';
      const token = 'tok-tam-skills-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Skills Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Skills Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeSearchSkills({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            client: {
              project_id: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: '',
        event_type: 'skills.search.performed',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('get or create thread returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_memory_project_mismatch');
  const dbPath = makeTmp('db_tam_memory_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-memory-project-mismatch';
      const token = 'tok-tam-memory-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Memory Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Memory Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeGetOrCreateThread({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            client: {
              project_id: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: '',
        event_type: 'memory.thread.opened',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('retrieve memory returns governed current-project results for paired trusted automation client', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_memory_retrieve_ok');
  const dbPath = makeTmp('db_tam_memory_retrieve_ok', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-memory-retrieve-ok';
      const token = 'tok-tam-memory-retrieve-ok';
      const requestId = 'req-tam-memory-retrieve-ok';
      const clientEntry = makeTrustedAutomationClientEntry({
        deviceId,
        token,
        name: 'Trusted Automation Memory Retrieve OK',
        allowedProjectIds: ['proj-w328'],
      });

      await invokeHubMemoryUnary({
        db,
        runtimeBaseDir,
        clientEntry,
        rpcName: 'UpsertCanonicalMemory',
        requestOverrides: {
          scope: 'project',
          key: 'stack_decision',
          value: 'Use governed Hub retrieval so XT and Hub share one retrieval contract.',
          pinned: false,
        },
      });

      const response = await invokeRetrieveMemory({
        db,
        runtimeBaseDir,
        clientEntry,
        requestOverrides: {
          request_id: requestId,
          query: 'retrieval contract',
          latest_user: 'retrieval contract',
          requested_kinds: ['decision_track', 'canonical_memory'],
          audit_ref: 'audit-tam-memory-retrieve-ok',
        },
      });

      assert.equal(String(response?.schema_version || ''), 'xt.memory_retrieval_result.v1');
      assert.equal(String(response?.request_id || ''), requestId);
      assert.equal(String(response?.status || ''), 'ok');
      assert.equal(String(response?.resolved_scope || ''), 'current_project');
      assert.ok(Array.isArray(response?.results));
      assert.ok((response?.results?.length || 0) >= 1);
      assert.match(String(response?.results?.[0]?.ref || ''), /^memory:\/\/hub\//);

      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'memory.retrieval.performed',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('upsert canonical memory returns audit and durable refs for paired trusted automation client', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_memory_upsert_audit_ok');
  const dbPath = makeTmp('db_tam_memory_upsert_audit_ok', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-memory-upsert-audit-ok';
      const token = 'tok-tam-memory-upsert-audit-ok';
      const requestId = 'req-tam-memory-upsert-audit-ok';
      const auditRef = 'audit-tam-memory-upsert-audit-ok';
      const clientEntry = makeTrustedAutomationClientEntry({
        deviceId,
        token,
        name: 'Trusted Automation Memory Upsert Audit OK',
        allowedProjectIds: ['proj-w328'],
      });

      const response = await invokeHubMemoryUnary({
        db,
        runtimeBaseDir,
        clientEntry,
        rpcName: 'UpsertCanonicalMemory',
        requestOverrides: {
          scope: 'project',
          key: 'writeback_closure',
          value: 'Return audit_ref and durable refs to XT retry status.',
          pinned: false,
          request_id: requestId,
          audit_ref: auditRef,
        },
      });

      assert.equal(String(response?.audit_ref || ''), auditRef);
      assert.match(String(response?.evidence_ref || ''), /^canonical_memory_item:/);
      assert.equal(String(response?.writeback_ref || ''), String(response?.evidence_ref || ''));
      assert.ok(String(response?.item?.item_id || '').trim().length > 0);

      const row = assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'memory.canonical.upserted',
      });
      const ext = JSON.parse(String(row?.ext_json || '{}'));
      assert.equal(String(ext.audit_ref || ''), auditRef);
      assert.equal(String(ext.writeback_ref || ''), String(response?.writeback_ref || ''));
      assert.equal(String(ext.item_id || ''), String(response?.item?.item_id || ''));
      assert.equal(String(ext.scope || ''), 'project');
      assert.equal(String(ext.key || ''), 'writeback_closure');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('retrieve memory returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  await assertTrustedAutomationProjectMismatch({
    runtimeLabel: 'runtime_tam_memory_retrieve_project_mismatch',
    dbLabel: 'db_tam_memory_retrieve_project_mismatch',
    deviceId: 'dev-tam-memory-retrieve-project-mismatch',
    token: 'tok-tam-memory-retrieve-project-mismatch',
    name: 'Trusted Automation Memory Retrieve Project Mismatch',
    invoke: invokeRetrieveMemory,
    requestOverrides: {
      request_id: 'req-tam-memory-retrieve-project-mismatch',
    },
    requestId: 'req-tam-memory-retrieve-project-mismatch',
    event_type: 'memory.retrieval.denied',
  });
});

for (const spec of [
  {
    name: 'search skills returns trusted_automation_workspace_mismatch for workspace-bound trusted automation request',
    runtimeLabel: 'runtime_tam_skills_workspace_mismatch',
    dbLabel: 'db_tam_skills_workspace_mismatch',
    deviceId: 'dev-tam-skills-workspace-mismatch',
    token: 'tok-tam-skills-workspace-mismatch',
    nameForClient: 'Trusted Automation Skills Workspace Mismatch',
    invoke: invokeSearchSkills,
    requestOverrides: {
      client: {
        project_id: '',
        project_root: '/tmp/untrusted-workspace',
      },
    },
    event_type: 'skills.search.performed',
    denyCode: 'trusted_automation_workspace_mismatch',
    allowedProjectIds: [],
    allowedWorkspaceRoots: [TRUSTED_AUTOMATION_ALLOWED_WORKSPACE_ROOT],
  },
  {
    name: 'get or create thread returns trusted_automation_workspace_mismatch for workspace-bound trusted automation request',
    runtimeLabel: 'runtime_tam_memory_workspace_mismatch',
    dbLabel: 'db_tam_memory_workspace_mismatch',
    deviceId: 'dev-tam-memory-workspace-mismatch',
    token: 'tok-tam-memory-workspace-mismatch',
    nameForClient: 'Trusted Automation Memory Workspace Mismatch',
    invoke: invokeGetOrCreateThread,
    requestOverrides: {
      client: {
        project_id: '',
        project_root: '/tmp/untrusted-workspace',
      },
    },
    event_type: 'memory.thread.opened',
    denyCode: 'trusted_automation_workspace_mismatch',
    allowedProjectIds: [],
    allowedWorkspaceRoots: [TRUSTED_AUTOMATION_ALLOWED_WORKSPACE_ROOT],
  },
  {
    name: 'search skills returns device_permission_owner_missing when xt binding has no local owner ref',
    runtimeLabel: 'runtime_tam_skills_owner_missing',
    dbLabel: 'db_tam_skills_owner_missing',
    deviceId: 'dev-tam-skills-owner-missing',
    token: 'tok-tam-skills-owner-missing',
    nameForClient: 'Trusted Automation Skills Owner Missing',
    invoke: invokeSearchSkills,
    event_type: 'skills.search.performed',
    denyCode: 'device_permission_owner_missing',
    allowedProjectIds: ['proj-w328'],
    devicePermissionOwnerRef: '',
  },
  {
    name: 'get or create thread returns device_permission_owner_missing when xt binding has no local owner ref',
    runtimeLabel: 'runtime_tam_memory_owner_missing',
    dbLabel: 'db_tam_memory_owner_missing',
    deviceId: 'dev-tam-memory-owner-missing',
    token: 'tok-tam-memory-owner-missing',
    nameForClient: 'Trusted Automation Memory Owner Missing',
    invoke: invokeGetOrCreateThread,
    event_type: 'memory.thread.opened',
    denyCode: 'device_permission_owner_missing',
    allowedProjectIds: ['proj-w328'],
    devicePermissionOwnerRef: '',
  },
]) {
  await runAsync(spec.name, async () => {
    await assertTrustedAutomationDenyAudit({
      runtimeLabel: spec.runtimeLabel,
      dbLabel: spec.dbLabel,
      deviceId: spec.deviceId,
      token: spec.token,
      name: spec.nameForClient,
      invoke: spec.invoke,
      requestOverrides: spec.requestOverrides || {},
      requestId: '',
      event_type: spec.event_type,
      denyCode: spec.denyCode,
      allowedProjectIds: spec.allowedProjectIds,
      allowedWorkspaceRoots: spec.allowedWorkspaceRoots || [],
      devicePermissionOwnerRef: spec.devicePermissionOwnerRef,
    });
  });
}

await runAsync('evaluate risk tuning returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_risk_project_mismatch');
  const dbPath = makeTmp('db_tam_risk_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-risk-project-mismatch';
      const token = 'tok-tam-risk-project-mismatch';
      const requestId = 'req-tam-risk-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Risk Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Risk Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeEvaluateRiskTuningProfile({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            client: {
              project_id: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'memory.risk_tuning.evaluated',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('agent session open returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_agent_project_mismatch');
  const dbPath = makeTmp('db_tam_agent_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-agent-project-mismatch';
      const token = 'tok-tam-agent-project-mismatch';
      const requestId = 'req-tam-agent-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Agent Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Agent Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeAgentSessionOpen({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            client: {
              project_id: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'agent.session.denied',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('create payment intent returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_payment_project_mismatch');
  const dbPath = makeTmp('db_tam_payment_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-payment-project-mismatch';
      const token = 'tok-tam-payment-project-mismatch';
      const requestId = 'req-tam-payment-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Payment Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Payment Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeCreatePaymentIntent({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            client: {
              project_id: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'payment.intent.created',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('longterm markdown export returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_markdown_project_mismatch');
  const dbPath = makeTmp('db_tam_markdown_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-markdown-project-mismatch';
      const token = 'tok-tam-markdown-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Markdown Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Markdown Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeLongtermMarkdownExport({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            client: {
              project_id: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: '',
        event_type: 'memory.longterm_markdown.exported',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

const TRUSTED_AUTOMATION_AUDITED_RPC_SPECS = [
  {
    name: 'promote risk tuning returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_risk_promote_project_mismatch',
    dbLabel: 'db_tam_risk_promote_project_mismatch',
    deviceId: 'dev-tam-risk-promote-project-mismatch',
    token: 'tok-tam-risk-promote-project-mismatch',
    nameForClient: 'Trusted Automation Risk Promote Project Mismatch',
    invoke: invokePromoteRiskTuningProfile,
    requestId: 'req-tam-risk-promote-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-risk-promote-project-mismatch',
    },
    event_type: 'memory.risk_tuning.promoted',
  },
  {
    name: 'issue voice grant challenge returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_voice_issue_project_mismatch',
    dbLabel: 'db_tam_voice_issue_project_mismatch',
    deviceId: 'dev-tam-voice-issue-project-mismatch',
    token: 'tok-tam-voice-issue-project-mismatch',
    nameForClient: 'Trusted Automation Voice Issue Project Mismatch',
    invoke: invokeIssueVoiceGrantChallenge,
    requestId: 'req-tam-voice-issue-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-voice-issue-project-mismatch',
    },
    event_type: 'supervisor.voice.denied',
  },
  {
    name: 'verify voice grant response returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_voice_verify_project_mismatch',
    dbLabel: 'db_tam_voice_verify_project_mismatch',
    deviceId: 'dev-tam-voice-verify-project-mismatch',
    token: 'tok-tam-voice-verify-project-mismatch',
    nameForClient: 'Trusted Automation Voice Verify Project Mismatch',
    invoke: invokeVerifyVoiceGrantResponse,
    requestId: 'req-tam-voice-verify-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-voice-verify-project-mismatch',
    },
    event_type: 'supervisor.voice.denied',
  },
  {
    name: 'register agent capsule returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_capsule_register_project_mismatch',
    dbLabel: 'db_tam_capsule_register_project_mismatch',
    deviceId: 'dev-tam-capsule-register-project-mismatch',
    token: 'tok-tam-capsule-register-project-mismatch',
    nameForClient: 'Trusted Automation Capsule Register Project Mismatch',
    invoke: invokeRegisterAgentCapsule,
    requestId: 'req-tam-capsule-register-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-capsule-register-project-mismatch',
    },
    event_type: 'agent.capsule.denied',
  },
  {
    name: 'verify agent capsule returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_capsule_verify_project_mismatch',
    dbLabel: 'db_tam_capsule_verify_project_mismatch',
    deviceId: 'dev-tam-capsule-verify-project-mismatch',
    token: 'tok-tam-capsule-verify-project-mismatch',
    nameForClient: 'Trusted Automation Capsule Verify Project Mismatch',
    invoke: invokeVerifyAgentCapsule,
    requestId: 'req-tam-capsule-verify-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-capsule-verify-project-mismatch',
    },
    event_type: 'agent.capsule.denied',
  },
  {
    name: 'activate agent capsule returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_capsule_activate_project_mismatch',
    dbLabel: 'db_tam_capsule_activate_project_mismatch',
    deviceId: 'dev-tam-capsule-activate-project-mismatch',
    token: 'tok-tam-capsule-activate-project-mismatch',
    nameForClient: 'Trusted Automation Capsule Activate Project Mismatch',
    invoke: invokeActivateAgentCapsule,
    requestId: 'req-tam-capsule-activate-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-capsule-activate-project-mismatch',
    },
    event_type: 'agent.capsule.denied',
  },
  {
    name: 'attach payment evidence returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_payment_evidence_project_mismatch',
    dbLabel: 'db_tam_payment_evidence_project_mismatch',
    deviceId: 'dev-tam-payment-evidence-project-mismatch',
    token: 'tok-tam-payment-evidence-project-mismatch',
    nameForClient: 'Trusted Automation Payment Evidence Project Mismatch',
    invoke: invokeAttachPaymentEvidence,
    requestId: 'req-tam-payment-evidence-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-payment-evidence-project-mismatch',
    },
    event_type: 'payment.evidence.verified',
  },
  {
    name: 'issue payment challenge returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_payment_challenge_project_mismatch',
    dbLabel: 'db_tam_payment_challenge_project_mismatch',
    deviceId: 'dev-tam-payment-challenge-project-mismatch',
    token: 'tok-tam-payment-challenge-project-mismatch',
    nameForClient: 'Trusted Automation Payment Challenge Project Mismatch',
    invoke: invokeIssuePaymentChallenge,
    requestId: 'req-tam-payment-challenge-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-payment-challenge-project-mismatch',
    },
    event_type: 'payment.challenge.issued',
  },
  {
    name: 'confirm payment intent returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_payment_confirm_project_mismatch',
    dbLabel: 'db_tam_payment_confirm_project_mismatch',
    deviceId: 'dev-tam-payment-confirm-project-mismatch',
    token: 'tok-tam-payment-confirm-project-mismatch',
    nameForClient: 'Trusted Automation Payment Confirm Project Mismatch',
    invoke: invokeConfirmPaymentIntent,
    requestId: 'req-tam-payment-confirm-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-payment-confirm-project-mismatch',
    },
    event_type: 'payment.confirmed',
  },
  {
    name: 'abort payment intent returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_payment_abort_project_mismatch',
    dbLabel: 'db_tam_payment_abort_project_mismatch',
    deviceId: 'dev-tam-payment-abort-project-mismatch',
    token: 'tok-tam-payment-abort-project-mismatch',
    nameForClient: 'Trusted Automation Payment Abort Project Mismatch',
    invoke: invokeAbortPaymentIntent,
    requestId: 'req-tam-payment-abort-project-mismatch',
    requestOverrides: {
      request_id: 'req-tam-payment-abort-project-mismatch',
    },
    event_type: 'payment.aborted',
  },
  {
    name: 'longterm markdown begin edit returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_markdown_begin_project_mismatch',
    dbLabel: 'db_tam_markdown_begin_project_mismatch',
    deviceId: 'dev-tam-markdown-begin-project-mismatch',
    token: 'tok-tam-markdown-begin-project-mismatch',
    nameForClient: 'Trusted Automation Markdown Begin Project Mismatch',
    invoke: invokeLongtermMarkdownBeginEdit,
    event_type: 'memory.longterm_markdown.begin_edit',
  },
  {
    name: 'longterm markdown apply patch returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_markdown_patch_project_mismatch',
    dbLabel: 'db_tam_markdown_patch_project_mismatch',
    deviceId: 'dev-tam-markdown-patch-project-mismatch',
    token: 'tok-tam-markdown-patch-project-mismatch',
    nameForClient: 'Trusted Automation Markdown Patch Project Mismatch',
    invoke: invokeLongtermMarkdownApplyPatch,
    event_type: 'memory.longterm_markdown.patch_applied',
  },
  {
    name: 'longterm markdown review returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_markdown_review_project_mismatch',
    dbLabel: 'db_tam_markdown_review_project_mismatch',
    deviceId: 'dev-tam-markdown-review-project-mismatch',
    token: 'tok-tam-markdown-review-project-mismatch',
    nameForClient: 'Trusted Automation Markdown Review Project Mismatch',
    invoke: invokeLongtermMarkdownReview,
    event_type: 'memory.longterm_markdown.reviewed',
  },
  {
    name: 'longterm markdown writeback returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_markdown_writeback_project_mismatch',
    dbLabel: 'db_tam_markdown_writeback_project_mismatch',
    deviceId: 'dev-tam-markdown-writeback-project-mismatch',
    token: 'tok-tam-markdown-writeback-project-mismatch',
    nameForClient: 'Trusted Automation Markdown Writeback Project Mismatch',
    invoke: invokeLongtermMarkdownWriteback,
    event_type: 'memory.longterm_markdown.written',
  },
  {
    name: 'longterm markdown rollback returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_markdown_rollback_project_mismatch',
    dbLabel: 'db_tam_markdown_rollback_project_mismatch',
    deviceId: 'dev-tam-markdown-rollback-project-mismatch',
    token: 'tok-tam-markdown-rollback-project-mismatch',
    nameForClient: 'Trusted Automation Markdown Rollback Project Mismatch',
    invoke: invokeLongtermMarkdownRollback,
    event_type: 'memory.longterm_markdown.rolled_back',
  },
];

for (const spec of TRUSTED_AUTOMATION_AUDITED_RPC_SPECS) {
  await runAsync(spec.name, async () => {
    await assertTrustedAutomationProjectMismatch({
      runtimeLabel: spec.runtimeLabel,
      dbLabel: spec.dbLabel,
      deviceId: spec.deviceId,
      token: spec.token,
      name: spec.nameForClient,
      invoke: spec.invoke,
      requestOverrides: spec.requestOverrides || {},
      requestId: spec.requestId || '',
      event_type: spec.event_type,
    });
  });
}

for (const spec of TRUSTED_AUTOMATION_AUDITED_RPC_SPECS.map((item) => {
  const nextRequestId = typeof item.requestId === 'string' && item.requestId
    ? item.requestId.replace('project-mismatch', 'workspace-mismatch')
    : '';
  const nextRequestOverrides = {
    ...(item.requestOverrides || {}),
    client: {
      ...(((item.requestOverrides || {}).client && typeof (item.requestOverrides || {}).client === 'object')
        ? (item.requestOverrides || {}).client
        : {}),
      project_id: '',
      project_root: '/tmp/untrusted-workspace',
    },
  };
  if (nextRequestId) nextRequestOverrides.request_id = nextRequestId;
  return {
    ...item,
    name: item.name.replace(
      'trusted_automation_project_not_bound for cross-project trusted automation request',
      'trusted_automation_workspace_mismatch for workspace-bound trusted automation request'
    ),
    runtimeLabel: item.runtimeLabel.replace('project_mismatch', 'workspace_mismatch'),
    dbLabel: item.dbLabel.replace('project_mismatch', 'workspace_mismatch'),
    deviceId: item.deviceId.replace('project-mismatch', 'workspace-mismatch'),
    token: item.token.replace('project-mismatch', 'workspace-mismatch'),
    nameForClient: item.nameForClient.replace('Project Mismatch', 'Workspace Mismatch'),
    requestId: nextRequestId,
    requestOverrides: nextRequestOverrides,
  };
})) {
  await runAsync(spec.name, async () => {
    await assertTrustedAutomationDenyAudit({
      runtimeLabel: spec.runtimeLabel,
      dbLabel: spec.dbLabel,
      deviceId: spec.deviceId,
      token: spec.token,
      name: spec.nameForClient,
      invoke: spec.invoke,
      requestOverrides: spec.requestOverrides || {},
      requestId: spec.requestId || '',
      event_type: spec.event_type,
      denyCode: 'trusted_automation_workspace_mismatch',
      allowedProjectIds: [],
      allowedWorkspaceRoots: [TRUSTED_AUTOMATION_ALLOWED_WORKSPACE_ROOT],
    });
  });
}

for (const spec of TRUSTED_AUTOMATION_AUDITED_RPC_SPECS.map((item) => {
  const nextRequestId = typeof item.requestId === 'string' && item.requestId
    ? item.requestId.replace('project-mismatch', 'owner-missing')
    : '';
  const nextRequestOverrides = {
    ...(item.requestOverrides || {}),
  };
  if (nextRequestId) nextRequestOverrides.request_id = nextRequestId;
  return {
    ...item,
    name: item.name.replace(
      'returns trusted_automation_project_not_bound for cross-project trusted automation request',
      'returns device_permission_owner_missing when xt binding has no local owner ref'
    ),
    runtimeLabel: item.runtimeLabel.replace('project_mismatch', 'owner_missing'),
    dbLabel: item.dbLabel.replace('project_mismatch', 'owner_missing'),
    deviceId: item.deviceId.replace('project-mismatch', 'owner-missing'),
    token: item.token.replace('project-mismatch', 'owner-missing'),
    nameForClient: item.nameForClient.replace('Project Mismatch', 'Owner Missing'),
    requestId: nextRequestId,
    requestOverrides: nextRequestOverrides,
  };
})) {
  await runAsync(spec.name, async () => {
    await assertTrustedAutomationDenyAudit({
      runtimeLabel: spec.runtimeLabel,
      dbLabel: spec.dbLabel,
      deviceId: spec.deviceId,
      token: spec.token,
      name: spec.nameForClient,
      invoke: spec.invoke,
      requestOverrides: spec.requestOverrides || {},
      requestId: spec.requestId || '',
      event_type: spec.event_type,
      denyCode: 'device_permission_owner_missing',
      allowedProjectIds: ['proj-w328'],
      devicePermissionOwnerRef: '',
    });
  });
}

await runAsync('upsert project lineage returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_lineage_project_mismatch');
  const dbPath = makeTmp('db_tam_lineage_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-lineage-project-mismatch';
      const token = 'tok-tam-lineage-project-mismatch';
      const requestId = 'req-tam-lineage-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Lineage Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Lineage Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeUpsertProjectLineage({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            lineage: {
              root_project_id: 'project_beta',
              project_id: 'project_beta',
              lineage_path: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'project.lineage.rejected',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('get project lineage tree returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_lineage_tree_project_mismatch');
  const dbPath = makeTmp('db_tam_lineage_tree_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-lineage-tree-project-mismatch';
      const token = 'tok-tam-lineage-tree-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Lineage Tree Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Lineage Tree Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeGetProjectLineageTree({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            root_project_id: 'project_beta',
            project_id: 'project_beta',
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: '',
        event_type: 'project.lineage.rejected',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

const TRUSTED_AUTOMATION_CORE_AUDITED_RPC_SPECS = [
  {
    name: 'evaluate risk tuning returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_risk_project_mismatch_core',
    dbLabel: 'db_tam_risk_project_mismatch_core',
    deviceId: 'dev-tam-risk-project-mismatch-core',
    token: 'tok-tam-risk-project-mismatch-core',
    nameForClient: 'Trusted Automation Risk Project Mismatch Core',
    invoke: invokeEvaluateRiskTuningProfile,
    requestId: 'req-tam-risk-project-mismatch-core',
    requestOverrides: {
      request_id: 'req-tam-risk-project-mismatch-core',
    },
    event_type: 'memory.risk_tuning.evaluated',
  },
  {
    name: 'agent session open returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_agent_project_mismatch_core',
    dbLabel: 'db_tam_agent_project_mismatch_core',
    deviceId: 'dev-tam-agent-project-mismatch-core',
    token: 'tok-tam-agent-project-mismatch-core',
    nameForClient: 'Trusted Automation Agent Project Mismatch Core',
    invoke: invokeAgentSessionOpen,
    requestId: 'req-tam-agent-project-mismatch-core',
    requestOverrides: {
      request_id: 'req-tam-agent-project-mismatch-core',
    },
    event_type: 'agent.session.denied',
  },
  {
    name: 'create payment intent returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_payment_project_mismatch_core',
    dbLabel: 'db_tam_payment_project_mismatch_core',
    deviceId: 'dev-tam-payment-project-mismatch-core',
    token: 'tok-tam-payment-project-mismatch-core',
    nameForClient: 'Trusted Automation Payment Project Mismatch Core',
    invoke: invokeCreatePaymentIntent,
    requestId: 'req-tam-payment-project-mismatch-core',
    requestOverrides: {
      request_id: 'req-tam-payment-project-mismatch-core',
    },
    event_type: 'payment.intent.created',
  },
  {
    name: 'longterm markdown export returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_markdown_project_mismatch_core',
    dbLabel: 'db_tam_markdown_project_mismatch_core',
    deviceId: 'dev-tam-markdown-project-mismatch-core',
    token: 'tok-tam-markdown-project-mismatch-core',
    nameForClient: 'Trusted Automation Markdown Project Mismatch Core',
    invoke: invokeLongtermMarkdownExport,
    event_type: 'memory.longterm_markdown.exported',
  },
  {
    name: 'upsert project lineage returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_lineage_project_mismatch_core',
    dbLabel: 'db_tam_lineage_project_mismatch_core',
    deviceId: 'dev-tam-lineage-project-mismatch-core',
    token: 'tok-tam-lineage-project-mismatch-core',
    nameForClient: 'Trusted Automation Lineage Project Mismatch Core',
    invoke: invokeUpsertProjectLineage,
    requestId: 'req-tam-lineage-project-mismatch-core',
    requestOverrides: {
      request_id: 'req-tam-lineage-project-mismatch-core',
      lineage: {
        root_project_id: 'project_beta',
        project_id: 'project_beta',
        lineage_path: 'project_beta',
      },
    },
    event_type: 'project.lineage.rejected',
  },
  {
    name: 'get project lineage tree returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_lineage_tree_project_mismatch_core',
    dbLabel: 'db_tam_lineage_tree_project_mismatch_core',
    deviceId: 'dev-tam-lineage-tree-project-mismatch-core',
    token: 'tok-tam-lineage-tree-project-mismatch-core',
    nameForClient: 'Trusted Automation Lineage Tree Project Mismatch Core',
    invoke: invokeGetProjectLineageTree,
    requestOverrides: {
      root_project_id: 'project_beta',
      project_id: 'project_beta',
    },
    event_type: 'project.lineage.rejected',
  },
  {
    name: 'attach dispatch context returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_dispatch_attach_project_mismatch_core',
    dbLabel: 'db_tam_dispatch_attach_project_mismatch_core',
    deviceId: 'dev-tam-dispatch-attach-project-mismatch-core',
    token: 'tok-tam-dispatch-attach-project-mismatch-core',
    nameForClient: 'Trusted Automation Dispatch Attach Project Mismatch Core',
    invoke: invokeAttachDispatchContext,
    requestId: 'req-tam-dispatch-attach-project-mismatch-core',
    requestOverrides: {
      request_id: 'req-tam-dispatch-attach-project-mismatch-core',
      dispatch: {
        root_project_id: 'project_beta',
        project_id: 'project_beta',
      },
    },
    event_type: 'project.lineage.rejected',
  },
  {
    name: 'project heartbeat returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_project_heartbeat_mismatch_core',
    dbLabel: 'db_tam_project_heartbeat_mismatch_core',
    deviceId: 'dev-tam-project-heartbeat-mismatch-core',
    token: 'tok-tam-project-heartbeat-mismatch-core',
    nameForClient: 'Trusted Automation Project Heartbeat Mismatch Core',
    invoke: invokeProjectHeartbeat,
    requestId: 'req-tam-project-heartbeat-mismatch-core',
    requestOverrides: {
      request_id: 'req-tam-project-heartbeat-mismatch-core',
      heartbeat: {
        root_project_id: 'project_beta',
        project_id: 'project_beta',
      },
    },
    event_type: 'project.heartbeat.rejected',
  },
  {
    name: 'get dispatch plan returns trusted_automation_project_not_bound for cross-project trusted automation request',
    runtimeLabel: 'runtime_tam_dispatch_plan_mismatch_core',
    dbLabel: 'db_tam_dispatch_plan_mismatch_core',
    deviceId: 'dev-tam-dispatch-plan-mismatch-core',
    token: 'tok-tam-dispatch-plan-mismatch-core',
    nameForClient: 'Trusted Automation Dispatch Plan Mismatch Core',
    invoke: invokeGetDispatchPlan,
    requestId: 'req-tam-dispatch-plan-mismatch-core',
    requestOverrides: {
      request_id: 'req-tam-dispatch-plan-mismatch-core',
      root_project_id: 'project_beta',
    },
    event_type: 'project.dispatch.rejected',
  },
];

for (const spec of TRUSTED_AUTOMATION_CORE_AUDITED_RPC_SPECS.map((item) => {
  const nextRequestId = typeof item.requestId === 'string' && item.requestId
    ? item.requestId.replace('project-mismatch', 'workspace-mismatch')
    : '';
  const nextRequestOverrides = {
    ...(item.requestOverrides || {}),
    client: {
      ...(((item.requestOverrides || {}).client && typeof (item.requestOverrides || {}).client === 'object')
        ? (item.requestOverrides || {}).client
        : {}),
      project_id: '',
      project_root: '/tmp/untrusted-workspace',
    },
  };
  if (nextRequestId) nextRequestOverrides.request_id = nextRequestId;
  return {
    ...item,
    name: item.name.replace(
      'trusted_automation_project_not_bound for cross-project trusted automation request',
      'trusted_automation_workspace_mismatch for workspace-bound trusted automation request'
    ),
    runtimeLabel: item.runtimeLabel.replace('project_mismatch', 'workspace_mismatch'),
    dbLabel: item.dbLabel.replace('project_mismatch', 'workspace_mismatch'),
    deviceId: item.deviceId.replace('project-mismatch', 'workspace-mismatch'),
    token: item.token.replace('project-mismatch', 'workspace-mismatch'),
    nameForClient: item.nameForClient.replace('Project Mismatch', 'Workspace Mismatch'),
    requestId: nextRequestId,
    requestOverrides: nextRequestOverrides,
  };
})) {
  await runAsync(spec.name, async () => {
    await assertTrustedAutomationDenyAudit({
      runtimeLabel: spec.runtimeLabel,
      dbLabel: spec.dbLabel,
      deviceId: spec.deviceId,
      token: spec.token,
      name: spec.nameForClient,
      invoke: spec.invoke,
      requestOverrides: spec.requestOverrides || {},
      requestId: spec.requestId || '',
      event_type: spec.event_type,
      denyCode: 'trusted_automation_workspace_mismatch',
      allowedProjectIds: [],
      allowedWorkspaceRoots: [TRUSTED_AUTOMATION_ALLOWED_WORKSPACE_ROOT],
    });
  });
}

for (const spec of TRUSTED_AUTOMATION_CORE_AUDITED_RPC_SPECS.map((item) => {
  const nextRequestId = typeof item.requestId === 'string' && item.requestId
    ? item.requestId.replace('project-mismatch', 'owner-missing')
    : '';
  const nextRequestOverrides = {
    ...(item.requestOverrides || {}),
  };
  if (nextRequestId) nextRequestOverrides.request_id = nextRequestId;
  return {
    ...item,
    name: item.name.replace(
      'returns trusted_automation_project_not_bound for cross-project trusted automation request',
      'returns device_permission_owner_missing when xt binding has no local owner ref'
    ),
    runtimeLabel: item.runtimeLabel.replace('project_mismatch', 'owner_missing'),
    dbLabel: item.dbLabel.replace('project_mismatch', 'owner_missing'),
    deviceId: item.deviceId.replace('project-mismatch', 'owner-missing'),
    token: item.token.replace('project-mismatch', 'owner-missing'),
    nameForClient: item.nameForClient.replace('Project Mismatch', 'Owner Missing'),
    requestId: nextRequestId,
    requestOverrides: nextRequestOverrides,
  };
})) {
  await runAsync(spec.name, async () => {
    await assertTrustedAutomationDenyAudit({
      runtimeLabel: spec.runtimeLabel,
      dbLabel: spec.dbLabel,
      deviceId: spec.deviceId,
      token: spec.token,
      name: spec.nameForClient,
      invoke: spec.invoke,
      requestOverrides: spec.requestOverrides || {},
      requestId: spec.requestId || '',
      event_type: spec.event_type,
      denyCode: 'device_permission_owner_missing',
      allowedProjectIds: ['proj-w328'],
      devicePermissionOwnerRef: '',
    });
  });
}

await runAsync('attach dispatch context returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_dispatch_attach_project_mismatch');
  const dbPath = makeTmp('db_tam_dispatch_attach_project_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-dispatch-attach-project-mismatch';
      const token = 'tok-tam-dispatch-attach-project-mismatch';
      const requestId = 'req-tam-dispatch-attach-project-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Dispatch Attach Project Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Dispatch Attach Project Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeAttachDispatchContext({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            dispatch: {
              root_project_id: 'project_beta',
              project_id: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'project.lineage.rejected',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('project heartbeat returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_project_heartbeat_mismatch');
  const dbPath = makeTmp('db_tam_project_heartbeat_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-project-heartbeat-mismatch';
      const token = 'tok-tam-project-heartbeat-mismatch';
      const requestId = 'req-tam-project-heartbeat-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Project Heartbeat Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Project Heartbeat Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeProjectHeartbeat({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            heartbeat: {
              root_project_id: 'project_beta',
              project_id: 'project_beta',
            },
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'project.heartbeat.rejected',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('get dispatch plan returns trusted_automation_project_not_bound for cross-project trusted automation request', async () => {
  const runtimeBaseDir = makeTmp('runtime_tam_dispatch_plan_mismatch');
  const dbPath = makeTmp('db_tam_dispatch_plan_mismatch', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const deviceId = 'dev-tam-dispatch-plan-mismatch';
      const token = 'tok-tam-dispatch-plan-mismatch';
      const requestId = 'req-tam-dispatch-plan-mismatch';
      const clientEntry = {
        device_id: deviceId,
        user_id: deviceId,
        name: 'Trusted Automation Dispatch Plan Mismatch',
        token,
        enabled: true,
        capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
        policy_mode: 'new_profile',
        approved_trust_profile: makeApprovedTrustProfile({
          deviceId,
          deviceName: 'Trusted Automation Dispatch Plan Mismatch',
          capabilities: ['models', 'events', 'memory', 'skills', 'ai.generate.local', 'ai.generate.paid', 'web.fetch'],
          mode: 'trusted_automation',
          state: 'armed',
          allowedProjectIds: ['project_alpha'],
          xtBindingRequired: true,
          autoGrantProfile: 'trusted_automation_default',
          devicePermissionOwnerRef: 'xt.device_permission_owner_readiness.v1:local_owner',
          paidModelPolicyMode: 'all_paid_models',
        }),
      };
      await assert.rejects(
        invokeGetDispatchPlan({
          db,
          runtimeBaseDir,
          clientEntry,
          requestOverrides: {
            request_id: requestId,
            root_project_id: 'project_beta',
          },
        }),
        (error) => {
          assert.equal(String(error?.message || ''), 'trusted_automation_project_not_bound');
          return true;
        }
      );
      assertAuditEvent(db, {
        device_id: deviceId,
        user_id: deviceId,
        request_id: requestId,
        event_type: 'project.dispatch.rejected',
        error_code: 'trusted_automation_project_not_bound',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
