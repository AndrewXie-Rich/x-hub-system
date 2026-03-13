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
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
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
  return path.join(os.tmpdir(), `supervisor_control_plane_service_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x57).toString('base64')}`;

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'hub-connector-test',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_PROJECT_HEARTBEAT_TTL_MS: String(60 * 1000),
  };
}

function makeDirectCall(request = {}, token = '') {
  return {
    request,
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() === 'authorization') {
          return token ? [`Bearer ${token}`] : [];
        }
        return [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:55001';
    },
  };
}

function invokeUnary(fn, request, { token = '' } = {}) {
  let response = null;
  let error = null;
  fn(makeDirectCall(request, token), (err, out) => {
    error = err || null;
    response = out || null;
  });
  if (error) throw error;
  return response;
}

function writeJsonFile(runtimeBaseDir, fileName, payload) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  fs.writeFileSync(
    path.join(runtimeBaseDir, fileName),
    JSON.stringify(payload, null, 2) + '\n',
    'utf8'
  );
}

function writeClientsSnapshot(runtimeBaseDir, clients) {
  writeJsonFile(runtimeBaseDir, 'hub_grpc_clients.json', {
    schema_version: 'hub_grpc_clients.v1',
    updated_at_ms: Date.now(),
    clients,
  });
}

function writeGrpcDevicesStatus(runtimeBaseDir, devices) {
  writeJsonFile(runtimeBaseDir, 'grpc_devices_status.json', {
    schema_version: 'grpc_devices_status.v2',
    updated_at_ms: Date.now(),
    devices,
  });
}

function makeClientIdentity(project_id = '') {
  return {
    device_id: 'xt-supervisor-1',
    user_id: 'user-supervisor-1',
    app_id: 'x-terminal',
    project_id,
    session_id: 'sess-supervisor-1',
  };
}

function invokeHubMemoryUnary(impl, methodName, request, { token = '' } = {}) {
  let outErr = null;
  let outRes = null;
  impl.HubMemory[methodName](
    makeDirectCall(request, token),
    (err, res) => {
      outErr = err || null;
      outRes = res || null;
    }
  );
  return { err: outErr, res: outRes };
}

function seedProjectState(impl, client, {
  root_project_id,
  project_id,
  assigned_agent_profile = 'coder-fast-safe',
  blocked_reason = [],
  next_actions = [],
  queue_depth = 0,
  risk_tier = 'medium',
} = {}) {
  const rootLineage = invokeHubMemoryUnary(impl, 'UpsertProjectLineage', {
    request_id: `lineage-root-${root_project_id}`,
    client,
    lineage: {
      root_project_id,
      parent_project_id: '',
      project_id: root_project_id,
      lineage_path: root_project_id,
      split_round: 0,
      child_index: 0,
      status: 'active',
    },
  });
  assert.equal(rootLineage.err, null);
  assert.equal(!!rootLineage.res?.accepted, true);

  const lineage = invokeHubMemoryUnary(impl, 'UpsertProjectLineage', {
    request_id: `lineage-${project_id}`,
    client,
    lineage: {
      root_project_id,
      parent_project_id: root_project_id,
      project_id,
      lineage_path: `${root_project_id}/${project_id}`,
      split_round: 1,
      child_index: 0,
      status: 'active',
    },
  });
  assert.equal(lineage.err, null);
  assert.equal(!!lineage.res?.accepted, true);

  const dispatch = invokeHubMemoryUnary(impl, 'AttachDispatchContext', {
    request_id: `dispatch-${project_id}`,
    client,
    dispatch: {
      root_project_id,
      parent_project_id: root_project_id,
      project_id,
      assigned_agent_profile,
      queue_priority: 7,
      expected_artifacts: ['patch', 'verification'],
      parallel_lane_id: 'lane-g1',
      budget_class: 'standard',
      attach_source: 'x_terminal',
    },
  });
  assert.equal(dispatch.err, null);
  assert.equal(!!dispatch.res?.attached, true);

  const heartbeat = invokeHubMemoryUnary(impl, 'ProjectHeartbeat', {
    request_id: `heartbeat-${project_id}`,
    client,
    heartbeat: {
      root_project_id,
      parent_project_id: root_project_id,
      project_id,
      queue_depth,
      oldest_wait_ms: 1200,
      blocked_reason,
      next_actions,
      risk_tier,
      heartbeat_seq: 1,
      sent_at_ms: Date.now(),
    },
  });
  assert.equal(heartbeat.err, null);
  assert.equal(!!heartbeat.res?.accepted, true);
}

run('MMS/service api progress query without project stays hub-only', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const response = invokeUnary(
        impl.HubSupervisor.ResolveSupervisorRoute,
        {
          request_id: 'route-progress-no-project',
          client: makeClientIdentity(''),
          ingress: {
            surface_type: 'xt_voice',
            normalized_intent_type: 'progress_query',
            trust_level: 'paired_surface',
          },
        }
      );

      assert.equal(!!response.ok, true);
      assert.equal(String(response.deny_code || ''), '');
      assert.equal(String(response.route?.decision || ''), 'hub_only');
      assert.equal(String(response.route?.project_id || ''), '');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('MMS/service api directive routes to preferred online XT in same project', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  writeClientsSnapshot(runtimeBaseDir, [
    {
      device_id: 'xt-mac-mini-bj-01',
      token: 'client-token-xt-mac-mini-bj-01',
      enabled: true,
      capabilities: ['events'],
      trusted_automation_mode: 'standard',
      trusted_automation_state: 'off',
      allowed_project_ids: ['payments-prod'],
    },
  ]);
  writeGrpcDevicesStatus(runtimeBaseDir, [
    {
      device_id: 'xt-mac-mini-bj-01',
      connected: true,
      last_seen_at_ms: Date.now(),
      connected_at_ms: Date.now() - 1000,
    },
  ]);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const response = invokeUnary(
        impl.HubSupervisor.ResolveSupervisorRoute,
        {
          request_id: 'route-directive-xt',
          client: makeClientIdentity('payments-prod'),
          ingress: {
            surface_type: 'xt_voice',
            normalized_intent_type: 'directive',
            project_id: 'payments-prod',
            preferred_device_id: 'xt-mac-mini-bj-01',
          },
        },
        { token: 'client-token-xt-mac-mini-bj-01' }
      );

      assert.equal(!!response.ok, true);
      assert.equal(String(response.route?.decision || ''), 'hub_to_xt');
      assert.equal(String(response.route?.resolved_device_id || ''), 'xt-mac-mini-bj-01');
      assert.equal(!!response.route?.xt_online, true);
      assert.equal(!!response.route?.same_project_scope, true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('MMS/service api runner route fails closed when trusted runner is not ready', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  writeClientsSnapshot(runtimeBaseDir, [
    {
      device_id: 'xt-runner-01',
      token: 'client-token-xt-runner-01',
      enabled: true,
      capabilities: ['events'],
      trusted_automation_mode: 'trusted_automation',
      trusted_automation_state: 'armed',
      xt_binding_required: true,
      device_permission_owner_ref: '',
      allowed_project_ids: ['robot-shopping'],
    },
  ]);
  writeGrpcDevicesStatus(runtimeBaseDir, [
    {
      device_id: 'xt-runner-01',
      connected: true,
      last_seen_at_ms: Date.now(),
      connected_at_ms: Date.now() - 1000,
    },
  ]);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const response = invokeUnary(
        impl.HubSupervisor.ResolveSupervisorRoute,
        {
          request_id: 'route-runner-not-ready',
          client: makeClientIdentity('robot-shopping'),
          require_runner: true,
          ingress: {
            surface_type: 'wearable_companion',
            normalized_intent_type: 'directive',
            project_id: 'robot-shopping',
            preferred_device_id: 'xt-runner-01',
          },
        },
        { token: 'hub-connector-test' }
      );

      assert.equal(!!response.ok, false);
      assert.equal(String(response.deny_code || ''), 'device_permission_owner_missing');
      assert.equal(String(response.route?.decision || ''), 'fail_closed');
      assert.equal(!!response.route?.runner_required, true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('MMS/service api brief projection includes blocker and pending grants', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClientIdentity('payments-prod');
      seedProjectState(impl, client, {
        root_project_id: 'payments-root',
        project_id: 'payments-prod',
        blocked_reason: ['awaiting security review'],
        next_actions: ['approve release grant'],
        queue_depth: 2,
        risk_tier: 'high',
      });
      db.createGrantRequest({
        request_id: 'grant-brief-1',
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: 'payments-prod',
        capability: 'web.fetch',
        reason: 'release checklist',
        requested_ttl_sec: 900,
        requested_token_cap: 0,
      });

      const response = invokeUnary(
        impl.HubSupervisor.GetSupervisorBriefProjection,
        {
          request_id: 'brief-1',
          client,
          project_id: 'payments-prod',
          projection_kind: 'progress_brief',
          trigger: 'awaiting_authorization',
          include_tts_script: true,
          include_card_summary: true,
          max_evidence_refs: 6,
        }
      );

      assert.equal(!!response.ok, true);
      assert.equal(String(response.projection?.status || ''), 'awaiting_authorization');
      assert.equal(Number(response.projection?.pending_grant_count || 0), 1);
      assert.match(String(response.projection?.critical_blocker || ''), /awaiting security review/);
      assert.match(String(response.projection?.next_best_action || ''), /Review 1 pending grant request/);
      assert.equal(Array.isArray(response.projection?.tts_script), true);
      assert.equal(response.projection.tts_script.length >= 2, true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('MMS/service api guidance blocks direct tool jump', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const response = invokeUnary(
        impl.HubSupervisor.ResolveSupervisorGuidance,
        {
          request_id: 'guidance-direct-tool-jump',
          client: makeClientIdentity('payments-prod'),
          guidance_type: 'scope_hold',
          normalized_instruction: 'Please terminal.exec npm publish right now',
          ingress: {
            surface_type: 'xt_voice',
            normalized_intent_type: 'directive',
            project_id: 'payments-prod',
          },
          target_scope: {
            scope_type: 'project',
          },
        }
      );

      assert.equal(!!response.ok, false);
      assert.equal(String(response.deny_code || ''), 'direct_tool_jump_blocked');
      assert.equal(String(response.resolution?.resolution || ''), 'fail_closed');
      assert.equal(String(response.resolution?.project_id || ''), 'payments-prod');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('MMS/service api high-risk voice-only checkpoint is denied fail-closed', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const response = invokeUnary(
        impl.HubSupervisor.IssueSupervisorCheckpointChallenge,
        {
          request_id: 'checkpoint-voice-only-high-risk',
          client: makeClientIdentity('robot-shopping'),
          project_id: 'robot-shopping',
          checkpoint_type: 'payment',
          risk_tier: 'high',
          decision_path: 'voice_only',
          scope_digest: 'merchant:groceries',
          amount_digest: 'cny:18800',
          bound_device_id: 'xt-runner-01',
          evidence_refs: ['cart:robot-shopping:1'],
        }
      );

      assert.equal(!!response.ok, false);
      assert.equal(String(response.deny_code || ''), 'voice_only_not_allowed');
      assert.equal(String(response.challenge?.state || ''), 'denied');
      assert.equal(String(response.challenge?.underlying_flow || ''), 'none');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('MMS/service api payment checkpoint requires amount digest', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const response = invokeUnary(
        impl.HubSupervisor.IssueSupervisorCheckpointChallenge,
        {
          request_id: 'checkpoint-payment-missing-amount',
          client: makeClientIdentity('shopping-mission'),
          project_id: 'shopping-mission',
          checkpoint_type: 'payment',
          risk_tier: 'critical',
          decision_path: 'voice_plus_mobile',
          scope_digest: 'merchant:groceries',
          bound_device_id: 'bt-headset-1',
        }
      );

      assert.equal(!!response.ok, false);
      assert.equal(String(response.deny_code || ''), 'policy_denied');
      assert.equal(String(response.challenge?.state || ''), 'fail_closed');
      assert.equal(String(response.challenge?.underlying_flow || ''), 'none');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('MMS/service api voice-plus-mobile checkpoint delegates to voice grant chain', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const response = invokeUnary(
        impl.HubSupervisor.IssueSupervisorCheckpointChallenge,
        {
          request_id: 'checkpoint-voice-plus-mobile',
          client: makeClientIdentity('shopping-mission'),
          project_id: 'shopping-mission',
          mission_id: 'mission-voice-1',
          checkpoint_type: 'substitution',
          risk_tier: 'medium',
          decision_path: 'voice_plus_mobile',
          scope_digest: 'substitute:milk:oat',
          bound_device_id: 'bt-headset-1',
          ttl_ms: 120000,
          evidence_refs: ['mission:shopping-mission:substitution:1'],
        }
      );

      assert.equal(!!response.ok, true);
      assert.equal(String(response.deny_code || ''), '');
      assert.equal(String(response.challenge?.underlying_flow || ''), 'voice_grant');
      assert.match(String(response.challenge?.underlying_ref_id || ''), /^voice_chal_/);
      assert.equal(String(response.challenge?.state || ''), 'pending');
      assert.equal(!!response.challenge?.requires_mobile_confirm, true);
      assert.equal(
        Array.isArray(response.challenge?.evidence_refs)
          && response.challenge.evidence_refs.some((item) => String(item || '').startsWith('voice_grant:')),
        true
      );

      const rawVoice = db._getVoiceGrantChallengeRowRaw(String(response.challenge?.underlying_ref_id || ''));
      assert.ok(rawVoice);
      const parsedVoice = db._parseVoiceGrantChallengeRow(rawVoice);
      assert.equal(String(parsedVoice?.project_id || ''), 'shopping-mission');
      assert.equal(String(parsedVoice?.bound_device_id || ''), 'bt-headset-1');
      assert.equal(String(parsedVoice?.risk_level || ''), 'medium');
      assert.equal(!!parsedVoice?.requires_mobile_confirm, true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
