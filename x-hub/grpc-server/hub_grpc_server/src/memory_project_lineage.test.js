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

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_project_lineage_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x41).toString('base64')}`;

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

function makeClient(projectId = 'root-a') {
  return {
    device_id: 'dev-lineage-1',
    user_id: 'user-lineage-1',
    app_id: 'ax-terminal',
    project_id: projectId,
    session_id: 'sess-lineage-1',
  };
}

function upsertLineage(impl, client, {
  request_id = '',
  root_project_id,
  parent_project_id = '',
  project_id,
  lineage_path = '',
  parent_task_id = '',
  split_round = 0,
  split_reason = '',
  child_index = 0,
  status = 'active',
  expected_root_project_id = '',
} = {}) {
  return invokeHubMemoryUnary(impl, 'UpsertProjectLineage', {
    request_id,
    client,
    expected_root_project_id,
    lineage: {
      root_project_id,
      parent_project_id,
      project_id,
      lineage_path,
      parent_task_id,
      split_round,
      split_reason,
      child_index,
      status,
    },
  });
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
}

run('M3-W1-03/upsert_project_lineage fail-closed: parent missing + root mismatch + cycle + parent inactive', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('root-a');

      // CT-LIN-D001
      const missingParent = upsertLineage(impl, client, {
        request_id: 'req-parent-missing',
        root_project_id: 'root-a',
        parent_project_id: 'ghost-parent',
        project_id: 'child-a1',
        lineage_path: 'root-a/child-a1',
        split_round: 1,
        child_index: 0,
      });
      assert.equal(missingParent.err, null);
      assert.equal(!!missingParent.res?.accepted, false);
      assert.equal(String(missingParent.res?.deny_code || ''), 'lineage_parent_missing');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-parent-missing',
        event_type: 'project.lineage.rejected',
        error_code: 'lineage_parent_missing',
      });

      // CT-LIN-S001
      const rootNode = upsertLineage(impl, client, {
        request_id: 'req-root-create',
        root_project_id: 'root-a',
        project_id: 'root-a',
        lineage_path: 'root-a',
        split_round: 0,
        child_index: 0,
      });
      assert.equal(rootNode.err, null);
      assert.equal(!!rootNode.res?.accepted, true);
      assert.equal(!!rootNode.res?.created, true);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-root-create',
        event_type: 'project.lineage.upserted',
      });

      // CT-LIN-D003
      const rootMismatch = upsertLineage(impl, client, {
        request_id: 'req-root-mismatch',
        root_project_id: 'root-z',
        parent_project_id: 'root-a',
        project_id: 'child-a1',
        lineage_path: 'root-z/child-a1',
        split_round: 1,
        child_index: 0,
      });
      assert.equal(rootMismatch.err, null);
      assert.equal(!!rootMismatch.res?.accepted, false);
      assert.equal(String(rootMismatch.res?.deny_code || ''), 'lineage_root_mismatch');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-root-mismatch',
        event_type: 'project.lineage.rejected',
        error_code: 'lineage_root_mismatch',
      });

      const childB = upsertLineage(impl, client, {
        request_id: 'req-child-b',
        root_project_id: 'root-a',
        parent_project_id: 'root-a',
        project_id: 'child-b',
        lineage_path: 'root-a/child-b',
        split_round: 1,
        child_index: 0,
      });
      assert.equal(childB.err, null);
      assert.equal(!!childB.res?.accepted, true);

      const childC = upsertLineage(impl, client, {
        request_id: 'req-child-c',
        root_project_id: 'root-a',
        parent_project_id: 'child-b',
        project_id: 'child-c',
        lineage_path: 'root-a/child-b/child-c',
        split_round: 1,
        child_index: 1,
      });
      assert.equal(childC.err, null);
      assert.equal(!!childC.res?.accepted, true);

      // CT-LIN-D002
      const cycle = upsertLineage(impl, client, {
        request_id: 'req-cycle',
        root_project_id: 'root-a',
        parent_project_id: 'child-c',
        project_id: 'child-b',
        lineage_path: 'root-a/child-b/child-c/child-b',
        split_round: 2,
        child_index: 0,
      });
      assert.equal(cycle.err, null);
      assert.equal(!!cycle.res?.accepted, false);
      assert.equal(String(cycle.res?.deny_code || ''), 'lineage_cycle_detected');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-cycle',
        event_type: 'project.lineage.rejected',
        error_code: 'lineage_cycle_detected',
      });

      const archiveRoot = upsertLineage(impl, client, {
        request_id: 'req-root-archive',
        root_project_id: 'root-a',
        project_id: 'root-a',
        lineage_path: 'root-a',
        status: 'archived',
      });
      assert.equal(archiveRoot.err, null);
      assert.equal(!!archiveRoot.res?.accepted, true);
      assert.equal(String(archiveRoot.res?.lineage?.status || ''), 'archived');

      // CT-LIN-D004
      const inactiveParent = upsertLineage(impl, client, {
        request_id: 'req-parent-inactive',
        root_project_id: 'root-a',
        parent_project_id: 'root-a',
        project_id: 'child-after-archive',
        lineage_path: 'root-a/child-after-archive',
        split_round: 3,
        child_index: 0,
      });
      assert.equal(inactiveParent.err, null);
      assert.equal(!!inactiveParent.res?.accepted, false);
      assert.equal(String(inactiveParent.res?.deny_code || ''), 'parent_inactive');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-parent-inactive',
        event_type: 'project.lineage.rejected',
        error_code: 'parent_inactive',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-03/idempotent upsert + lineage tree + dispatch attach validation', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('root-idem');

      // Root setup for idempotent lineage flow.
      const root = upsertLineage(impl, client, {
        request_id: 'req-idem-root-1',
        root_project_id: 'root-idem',
        project_id: 'root-idem',
        lineage_path: 'root-idem',
      });
      assert.equal(root.err, null);
      assert.equal(!!root.res?.accepted, true);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-idem-root-1',
        event_type: 'project.lineage.upserted',
      });

      // CT-LIN-S002
      const childInsert = upsertLineage(impl, client, {
        request_id: 'req-idem-child-1',
        root_project_id: 'root-idem',
        parent_project_id: 'root-idem',
        project_id: 'child-idem-1',
        lineage_path: 'root-idem/child-idem-1',
        split_round: 1,
        child_index: 0,
      });
      assert.equal(childInsert.err, null);
      assert.equal(!!childInsert.res?.accepted, true);
      assert.equal(!!childInsert.res?.created, true);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-idem-child-1',
        event_type: 'project.lineage.upserted',
      });

      const childRepeat = upsertLineage(impl, client, {
        request_id: 'req-idem-child-2',
        root_project_id: 'root-idem',
        parent_project_id: 'root-idem',
        project_id: 'child-idem-1',
        lineage_path: 'root-idem/child-idem-1',
        split_round: 1,
        child_index: 0,
      });
      assert.equal(childRepeat.err, null);
      assert.equal(!!childRepeat.res?.accepted, true);
      assert.equal(!!childRepeat.res?.created, false);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-idem-child-2',
        event_type: 'project.lineage.upserted',
      });

      // CT-LIN-S003
      const tree = invokeHubMemoryUnary(impl, 'GetProjectLineageTree', {
        client,
        root_project_id: 'root-idem',
      });
      assert.equal(tree.err, null);
      assert.ok(tree.res);
      assert.equal(String(tree.res.root_project_id || ''), 'root-idem');
      assert.equal(Array.isArray(tree.res.nodes), true);
      assert.equal(tree.res.nodes.length, 2);
      assert.deepEqual(
        tree.res.nodes.map((n) => String(n.project_id || '')),
        ['root-idem', 'child-idem-1']
      );

      // CT-DIS-S001
      const dispatchAttached = invokeHubMemoryUnary(impl, 'AttachDispatchContext', {
        request_id: 'req-dispatch-attach-1',
        client,
        dispatch: {
          root_project_id: 'root-idem',
          parent_project_id: 'root-idem',
          project_id: 'child-idem-1',
          assigned_agent_profile: 'coder-fast-safe',
          parallel_lane_id: 'lane-2',
          budget_class: 'standard',
          queue_priority: 7,
          expected_artifacts: ['src_patch', 'unit_test'],
          attach_source: 'x_terminal',
        },
      });
      assert.equal(dispatchAttached.err, null);
      assert.equal(!!dispatchAttached.res?.attached, true);
      assert.equal(String(dispatchAttached.res?.deny_code || ''), '');
      assert.equal(String(dispatchAttached.res?.dispatch?.project_id || ''), 'child-idem-1');
      assert.equal(Array.isArray(dispatchAttached.res?.dispatch?.expected_artifacts), true);
      assert.equal(dispatchAttached.res.dispatch.expected_artifacts.length, 2);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-dispatch-attach-1',
        event_type: 'project.dispatch.lineage_attached',
      });

      // CT-DIS-D003
      const dispatchMismatch = invokeHubMemoryUnary(impl, 'AttachDispatchContext', {
        request_id: 'req-dispatch-attach-2',
        client,
        dispatch: {
          root_project_id: 'wrong-root',
          parent_project_id: 'root-idem',
          project_id: 'child-idem-1',
          assigned_agent_profile: 'coder-fast-safe',
          parallel_lane_id: 'lane-2',
          budget_class: 'standard',
          queue_priority: 7,
          expected_artifacts: ['src_patch'],
          attach_source: 'x_terminal',
        },
      });
      assert.equal(dispatchMismatch.err, null);
      assert.equal(!!dispatchMismatch.res?.attached, false);
      assert.equal(String(dispatchMismatch.res?.deny_code || ''), 'lineage_root_mismatch');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-dispatch-attach-2',
        event_type: 'project.lineage.rejected',
        error_code: 'lineage_root_mismatch',
      });

      // CT-DIS-D007
      const originalAttachProjectDispatchContext = db.attachProjectDispatchContext.bind(db);
      db.attachProjectDispatchContext = () => ({ attached: false });
      try {
        const dispatchFallbackRejected = invokeHubMemoryUnary(impl, 'AttachDispatchContext', {
          request_id: 'req-dispatch-attach-3',
          client,
          dispatch: {
            root_project_id: 'root-idem',
            parent_project_id: 'root-idem',
            project_id: 'child-idem-1',
            assigned_agent_profile: 'coder-fast-safe',
            parallel_lane_id: 'lane-3',
            budget_class: 'standard',
            queue_priority: 8,
            expected_artifacts: ['fallback_probe'],
            attach_source: 'manual',
          },
        });
        assert.equal(dispatchFallbackRejected.err, null);
        assert.equal(!!dispatchFallbackRejected.res?.attached, false);
        assert.equal(String(dispatchFallbackRejected.res?.deny_code || ''), 'dispatch_rejected');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'req-dispatch-attach-3',
          event_type: 'project.lineage.rejected',
          error_code: 'dispatch_rejected',
        });
      } finally {
        db.attachProjectDispatchContext = originalAttachProjectDispatchContext;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-03/contract deny_code matrix: invalid_request + permission_denied (+ audit)', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const clientA = makeClient('root-perm-a');
      const clientB = {
        device_id: 'dev-lineage-2',
        user_id: 'user-lineage-2',
        app_id: 'ax-terminal',
        project_id: 'root-perm-b',
        session_id: 'sess-lineage-2',
      };

      // CT-LIN-D005
      const invalidLineage = invokeHubMemoryUnary(impl, 'UpsertProjectLineage', {
        request_id: 'req-invalid-lineage',
        client: clientA,
        lineage: {
          root_project_id: '',
          project_id: '',
        },
      });
      assert.equal(invalidLineage.err, null);
      assert.equal(!!invalidLineage.res?.accepted, false);
      assert.equal(String(invalidLineage.res?.deny_code || ''), 'invalid_request');
      assertAuditEvent(db, {
        device_id: clientA.device_id,
        user_id: clientA.user_id,
        request_id: 'req-invalid-lineage',
        event_type: 'project.lineage.rejected',
        error_code: 'invalid_request',
      });

      // CT-DIS-D005
      const invalidDispatch = invokeHubMemoryUnary(impl, 'AttachDispatchContext', {
        request_id: 'req-invalid-dispatch',
        client: clientA,
        dispatch: {
          root_project_id: 'root-perm-a',
          project_id: 'child-perm-a1',
          assigned_agent_profile: '',
        },
      });
      assert.equal(invalidDispatch.err, null);
      assert.equal(!!invalidDispatch.res?.attached, false);
      assert.equal(String(invalidDispatch.res?.deny_code || ''), 'invalid_request');
      assertAuditEvent(db, {
        device_id: clientA.device_id,
        user_id: clientA.user_id,
        request_id: 'req-invalid-dispatch',
        event_type: 'project.lineage.rejected',
        error_code: 'invalid_request',
      });

      const rootA = upsertLineage(impl, clientA, {
        request_id: 'req-perm-root-a',
        root_project_id: 'root-perm-a',
        project_id: 'root-perm-a',
        lineage_path: 'root-perm-a',
      });
      assert.equal(rootA.err, null);
      assert.equal(!!rootA.res?.accepted, true);

      // CT-LIN-D006
      const crossScope = upsertLineage(impl, clientB, {
        request_id: 'req-perm-cross-scope',
        root_project_id: 'root-perm-a',
        project_id: 'root-perm-a',
        lineage_path: 'root-perm-a',
      });
      assert.equal(crossScope.err, null);
      assert.equal(!!crossScope.res?.accepted, false);
      assert.equal(String(crossScope.res?.deny_code || ''), 'permission_denied');
      assertAuditEvent(db, {
        device_id: clientB.device_id,
        user_id: clientB.user_id,
        request_id: 'req-perm-cross-scope',
        event_type: 'project.lineage.rejected',
        error_code: 'permission_denied',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
