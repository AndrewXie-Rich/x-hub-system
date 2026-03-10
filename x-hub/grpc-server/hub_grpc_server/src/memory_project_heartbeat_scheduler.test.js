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

function sleepMs(ms) {
  const waitMs = Math.max(0, Math.floor(Number(ms || 0)));
  if (waitMs <= 0) return;
  const sab = new SharedArrayBuffer(4);
  const view = new Int32Array(sab);
  Atomics.wait(view, 0, 0, waitMs);
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_project_heartbeat_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x42).toString('base64')}`;

function baseEnv(runtimeBaseDir, extra = {}) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'true',
    HUB_MEMORY_RETENTION_AUTO_JOB_ENABLED: 'false',
    HUB_MEMORY_RETENTION_BATCH_LIMIT: '200',
    HUB_MEMORY_RETENTION_TURNS_TTL_MS: '86400000',
    HUB_MEMORY_RETENTION_CANONICAL_TTL_MS: '86400000',
    HUB_MEMORY_RETENTION_CANONICAL_INCLUDE_PINNED: 'false',
    HUB_MEMORY_RETENTION_TOMBSTONE_TTL_MS: String(60 * 1000),
    HUB_MEMORY_RETENTION_AUDIT_ENABLED: 'true',
    HUB_PROJECT_HEARTBEAT_TTL_MS: String(60 * 1000),
    HUB_PROJECT_DISPATCH_STARVATION_MS: String(20 * 1000),
    HUB_PROJECT_DISPATCH_DEFAULT_BATCH_SIZE: '4',
    HUB_PROJECT_DISPATCH_CONSERVATIVE_PENALTY: '4000',
    ...extra,
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

function makeClient(projectId = 'root-hb') {
  return {
    device_id: 'dev-heartbeat-1',
    user_id: 'user-heartbeat-1',
    app_id: 'ax-terminal',
    project_id: projectId,
    session_id: 'sess-heartbeat-1',
  };
}

function upsertLineage(impl, client, {
  request_id,
  root_project_id,
  parent_project_id = '',
  project_id,
  lineage_path,
  split_round = 0,
  child_index = 0,
  status = 'active',
} = {}) {
  return invokeHubMemoryUnary(impl, 'UpsertProjectLineage', {
    request_id,
    client,
    lineage: {
      root_project_id,
      parent_project_id,
      project_id,
      lineage_path,
      split_round,
      child_index,
      status,
    },
  });
}

function attachDispatch(impl, client, {
  request_id,
  root_project_id,
  parent_project_id,
  project_id,
  assigned_agent_profile,
  queue_priority = 0,
  expected_artifacts = [],
  parallel_lane_id = 'lane-g4',
  budget_class = 'standard',
  attach_source = 'x_terminal',
} = {}) {
  return invokeHubMemoryUnary(impl, 'AttachDispatchContext', {
    request_id,
    client,
    dispatch: {
      root_project_id,
      parent_project_id,
      project_id,
      assigned_agent_profile,
      queue_priority,
      expected_artifacts,
      parallel_lane_id,
      budget_class,
      attach_source,
    },
  });
}

function projectHeartbeat(impl, client, {
  request_id,
  root_project_id,
  parent_project_id = '',
  project_id,
  queue_depth = 0,
  oldest_wait_ms = 0,
  blocked_reason = [],
  next_actions = [],
  risk_tier = '',
  heartbeat_seq = 1,
  sent_at_ms = Date.now(),
} = {}) {
  return invokeHubMemoryUnary(impl, 'ProjectHeartbeat', {
    request_id,
    client,
    heartbeat: {
      root_project_id,
      parent_project_id,
      project_id,
      queue_depth,
      oldest_wait_ms,
      blocked_reason,
      next_actions,
      risk_tier,
      heartbeat_seq,
      sent_at_ms,
    },
  });
}

function getDispatchPlan(impl, client, {
  request_id,
  root_project_id,
  max_projects = 4,
} = {}) {
  return invokeHubMemoryUnary(impl, 'GetDispatchPlan', {
    request_id,
    client,
    root_project_id,
    max_projects,
  });
}

function seedRootAndChildren(impl, client, { root_project_id, children = [] } = {}) {
  const root = upsertLineage(impl, client, {
    request_id: `req-root-${root_project_id}`,
    root_project_id,
    project_id: root_project_id,
    lineage_path: root_project_id,
  });
  assert.equal(root.err, null);
  assert.equal(!!root.res?.accepted, true);

  for (let i = 0; i < children.length; i += 1) {
    const child = children[i] || {};
    const projectId = String(child.project_id || `child-${i + 1}`);
    const parentProjectId = String(child.parent_project_id || root_project_id);
    const lineagePath = String(child.lineage_path || `${root_project_id}/${projectId}`);
    const upsert = upsertLineage(impl, client, {
      request_id: `req-lineage-${projectId}`,
      root_project_id,
      parent_project_id: parentProjectId,
      project_id: projectId,
      lineage_path: lineagePath,
      split_round: 1,
      child_index: i,
    });
    assert.equal(upsert.err, null);
    assert.equal(!!upsert.res?.accepted, true);

    const dispatch = attachDispatch(impl, client, {
      request_id: `req-dispatch-${projectId}`,
      root_project_id,
      parent_project_id: parentProjectId,
      project_id: projectId,
      assigned_agent_profile: String(child.assigned_agent_profile || 'coder-fast-safe'),
      queue_priority: Number(child.queue_priority || 0),
      expected_artifacts: Array.isArray(child.expected_artifacts) ? child.expected_artifacts : ['src_patch'],
    });
    assert.equal(dispatch.err, null);
    assert.equal(!!dispatch.res?.attached, true);
  }
}

run('M3-W2-03/heartbeat TTL expiry -> conservative dispatch fail-closed', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir, {
    HUB_PROJECT_HEARTBEAT_TTL_MS: '40',
    HUB_PROJECT_DISPATCH_STARVATION_MS: '10000',
  }), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('root-expiry');
      seedRootAndChildren(impl, client, {
        root_project_id: 'root-expiry',
        children: [{ project_id: 'a-child-expiry', assigned_agent_profile: 'coder-fast-safe' }],
      });

      const hb = projectHeartbeat(impl, client, {
        request_id: 'req-hb-expiry-1',
        root_project_id: 'root-expiry',
        parent_project_id: 'root-expiry',
        project_id: 'a-child-expiry',
        queue_depth: 3,
        oldest_wait_ms: 1800,
        risk_tier: 'medium',
        heartbeat_seq: 1,
      });
      assert.equal(hb.err, null);
      assert.equal(!!hb.res?.accepted, true);

      const firstPlan = getDispatchPlan(impl, client, {
        request_id: 'req-plan-expiry-1',
        root_project_id: 'root-expiry',
        max_projects: 1,
      });
      assert.equal(firstPlan.err, null);
      assert.equal(!!firstPlan.res?.planned, true);
      assert.equal(firstPlan.res?.items?.length, 1);
      assert.equal(String(firstPlan.res.items[0].project_id || ''), 'a-child-expiry');
      assert.equal(!!firstPlan.res.items[0].conservative_only, false);

      sleepMs(80);
      const fallbackPlan = getDispatchPlan(impl, client, {
        request_id: 'req-plan-expiry-2',
        root_project_id: 'root-expiry',
        max_projects: 1,
      });
      assert.equal(fallbackPlan.err, null);
      assert.equal(!!fallbackPlan.res?.planned, true);
      assert.equal(!!fallbackPlan.res?.conservative_mode, true);
      const item = fallbackPlan.res?.items?.[0] || {};
      assert.equal(String(item.project_id || ''), 'a-child-expiry');
      assert.equal(!!item.conservative_only, true);
      assert.equal(String(item.risk_tier || ''), 'high');
      assert.ok(Array.isArray(item.prewarm_targets));
      assert.ok(item.prewarm_targets.includes('agent:safe-default'));
      assert.ok(!item.prewarm_targets.includes('agent:coder-fast-safe'));

      const freshStates = db.listProjectHeartbeatStates({
        root_project_id: 'root-expiry',
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        include_expired: false,
      });
      assert.equal(freshStates.length, 0);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-03/burst concurrency: 10 projects oldest-first fairness order', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('root-burst');
      const children = [];
      for (let i = 1; i <= 10; i += 1) children.push({ project_id: `child-burst-${i}` });
      seedRootAndChildren(impl, client, { root_project_id: 'root-burst', children });

      for (let i = 1; i <= 10; i += 1) {
        const hb = projectHeartbeat(impl, client, {
          request_id: `req-hb-burst-${i}`,
          root_project_id: 'root-burst',
          parent_project_id: 'root-burst',
          project_id: `child-burst-${i}`,
          queue_depth: 1,
          oldest_wait_ms: i * 100,
          risk_tier: 'low',
          heartbeat_seq: 1,
        });
        assert.equal(hb.err, null);
        assert.equal(!!hb.res?.accepted, true);
      }

      const plan = getDispatchPlan(impl, client, {
        request_id: 'req-plan-burst',
        root_project_id: 'root-burst',
        max_projects: 5,
      });
      assert.equal(plan.err, null);
      assert.equal(!!plan.res?.planned, true);
      assert.equal(plan.res?.items?.length, 5);
      assert.deepEqual(
        plan.res.items.map((item) => String(item.project_id || '')),
        ['child-burst-10', 'child-burst-9', 'child-burst-8', 'child-burst-7', 'child-burst-6']
      );
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-03/restart recovery: heartbeat persistence survives scheduler restart', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    let db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('root-restart');
      seedRootAndChildren(impl, client, {
        root_project_id: 'root-restart',
        children: [{ project_id: 'child-restart-1' }],
      });

      const hb = projectHeartbeat(impl, client, {
        request_id: 'req-hb-restart-1',
        root_project_id: 'root-restart',
        parent_project_id: 'root-restart',
        project_id: 'child-restart-1',
        queue_depth: 2,
        oldest_wait_ms: 800,
        risk_tier: 'medium',
        heartbeat_seq: 1,
      });
      assert.equal(hb.err, null);
      assert.equal(!!hb.res?.accepted, true);

      db.close();
      db = new HubDB({ dbPath });
      const implAfterRestart = makeServices({ db, bus: new HubEventBus() });
      const plan = getDispatchPlan(implAfterRestart, client, {
        request_id: 'req-plan-restart-1',
        root_project_id: 'root-restart',
        max_projects: 1,
      });
      assert.equal(plan.err, null);
      assert.equal(!!plan.res?.planned, true);
      assert.equal(plan.res?.items?.length, 1);
      assert.equal(String(plan.res.items[0].project_id || ''), 'child-restart-1');
      assert.equal(!!plan.res.items[0].conservative_only, false);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-03/missing risk_tier defaults to high-risk conservative path', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('root-risk-default');
      seedRootAndChildren(impl, client, {
        root_project_id: 'root-risk-default',
        children: [{ project_id: 'child-risk-default', assigned_agent_profile: 'coder-privileged' }],
      });

      const hb = projectHeartbeat(impl, client, {
        request_id: 'req-hb-risk-default',
        root_project_id: 'root-risk-default',
        parent_project_id: 'root-risk-default',
        project_id: 'child-risk-default',
        queue_depth: 4,
        oldest_wait_ms: 2100,
        risk_tier: '',
        heartbeat_seq: 1,
      });
      assert.equal(hb.err, null);
      assert.equal(!!hb.res?.accepted, true);
      assert.equal(String(hb.res?.heartbeat?.risk_tier || ''), 'high');
      assert.equal(!!hb.res?.heartbeat?.conservative_only, true);

      const plan = getDispatchPlan(impl, client, {
        request_id: 'req-plan-risk-default',
        root_project_id: 'root-risk-default',
        max_projects: 1,
      });
      assert.equal(plan.err, null);
      assert.equal(!!plan.res?.planned, true);
      const item = plan.res?.items?.[0] || {};
      assert.equal(String(item.project_id || ''), 'child-risk-default');
      assert.equal(String(item.risk_tier || ''), 'high');
      assert.equal(!!item.conservative_only, true);
      assert.ok(Array.isArray(item.prewarm_targets));
      assert.ok(item.prewarm_targets.includes('agent:safe-default'));
      assert.ok(!item.prewarm_targets.includes('agent:coder-privileged'));
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-03/anti-starvation: repeated max_projects=1 rotates across waiting projects', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir, {
    HUB_PROJECT_DISPATCH_STARVATION_MS: String(5 * 1000),
  }), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('root-starvation');
      seedRootAndChildren(impl, client, {
        root_project_id: 'root-starvation',
        children: [
          { project_id: 'child-starve-a' },
          { project_id: 'child-starve-b' },
          { project_id: 'child-starve-c' },
        ],
      });

      for (const id of ['child-starve-a', 'child-starve-b', 'child-starve-c']) {
        const hb = projectHeartbeat(impl, client, {
          request_id: `req-hb-${id}`,
          root_project_id: 'root-starvation',
          parent_project_id: 'root-starvation',
          project_id: id,
          queue_depth: 1,
          oldest_wait_ms: 1200,
          risk_tier: 'low',
          heartbeat_seq: 1,
        });
        assert.equal(hb.err, null);
        assert.equal(!!hb.res?.accepted, true);
      }

      const picked = [];
      for (let i = 1; i <= 3; i += 1) {
        const plan = getDispatchPlan(impl, client, {
          request_id: `req-plan-starve-${i}`,
          root_project_id: 'root-starvation',
          max_projects: 1,
        });
        assert.equal(plan.err, null);
        assert.equal(!!plan.res?.planned, true);
        assert.equal(plan.res?.items?.length, 1);
        picked.push(String(plan.res.items[0].project_id || ''));
      }
      assert.deepEqual(picked, ['child-starve-a', 'child-starve-b', 'child-starve-c']);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
