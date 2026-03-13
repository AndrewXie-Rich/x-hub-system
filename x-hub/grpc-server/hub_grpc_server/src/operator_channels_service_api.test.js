import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import { resolveSupervisorChannelSessionRoute } from './supervisor_channel_session_store.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
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

  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  };

  try {
    const out = fn();
    if (out && typeof out.then === 'function') {
      return out.finally(restore);
    }
    restore();
    return out;
  } catch (error) {
    restore();
    throw error;
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `operator_channels_service_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x5a).toString('base64')}`;

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_ADMIN_TOKEN: 'hub-admin-test',
    HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN: 'hub-connector-test',
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
  };
}

function makeAdminCall({ request = {}, token = 'hub-admin-test', peer = 'ipv4:127.0.0.1:55001' } = {}) {
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
      return peer;
    },
  };
}

function makeConnectorCall({ request = {}, token = 'hub-connector-test', peer = 'ipv4:127.0.0.1:55001' } = {}) {
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
      return peer;
    },
  };
}

function makeStreamingConnectorCall({ request = {}, token = 'hub-connector-test', peer = 'ipv4:127.0.0.1:55001' } = {}) {
  const listeners = new Map();
  const written = [];
  let ended = false;
  return {
    request,
    written,
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
      return peer;
    },
    write(event) {
      written.push(event);
    },
    end() {
      ended = true;
    },
    on(eventName, handler) {
      if (!listeners.has(eventName)) listeners.set(eventName, []);
      listeners.get(eventName).push(handler);
    },
  };
}

function invokeUnary(fn, call) {
  let response;
  let error;
  fn(call, (err, out) => {
    error = err;
    response = out;
  });
  if (error) throw error;
  return response;
}

function invokeUnaryAsync(fn, call) {
  return new Promise((resolve, reject) => {
    fn(call, (err, out) => {
      if (err) reject(err);
      else resolve(out);
    });
  });
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

function writeChannelRuntimeAccountsSnapshot(runtimeBaseDir, accounts) {
  writeJsonFile(runtimeBaseDir, 'channel_runtime_accounts_status.json', {
    schema_version: 'xhub.channel_runtime_accounts_status.v1',
    updated_at_ms: Date.now(),
    accounts,
  });
}

run('XT-W3-24/service api operator-channel runtime endpoints require dedicated connector auth', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      assert.throws(
        () => invokeUnary(
          impl.HubRuntime.GetChannelRuntimeStatusSnapshot,
          makeAdminCall({ token: '' })
        ),
        /Missing\/invalid operator-channel connector token/
      );
      assert.throws(
        () => invokeUnary(
          impl.HubRuntime.GetChannelRuntimeStatusSnapshot,
          makeAdminCall()
        ),
        /Missing\/invalid operator-channel connector token/
      );
      assert.throws(
        () => invokeUnary(
          impl.HubRuntime.GetChannelRuntimeStatusSnapshot,
          makeConnectorCall({ peer: 'ipv4:10.24.6.8:55001' })
        ),
        /Operator-channel connector RPCs are local-only/
      );
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api connector grant event subscription is local-only and grants-only', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const bus = new HubEventBus();
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus });
      const deniedCall = makeStreamingConnectorCall({
        request: {
          scopes: ['requests'],
        },
      });
      impl.HubEvents.Subscribe(deniedCall);
      assert.equal(deniedCall.ended, true);
      assert.equal(deniedCall.written.length, 0);

      const grantedCall = makeStreamingConnectorCall({
        request: {
          scopes: ['grants'],
          client: {
            app_id: 'slack_operator_adapter',
          },
        },
      });
      impl.HubEvents.Subscribe(grantedCall);
      assert.equal(grantedCall.ended, false);

      bus.emitHubEvent(
        bus.grantDecision({
          grant_request_id: 'grant_req_stream_1',
          decision: 'GRANT_DECISION_APPROVED',
          grant: {
            grant_id: 'grant_1',
            capability: 'CAPABILITY_WEB_FETCH',
            client: {
              device_id: 'xt-alpha-1',
              project_id: 'project_alpha',
            },
          },
          deny_reason: '',
          client: {
            device_id: 'xt-alpha-1',
            project_id: 'project_alpha',
          },
        })
      );

      assert.equal(grantedCall.written.length, 1);
      assert.equal(String(grantedCall.written[0]?.grant_decision?.grant_request_id || ''), 'grant_req_stream_1');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api upserts and lists channel identity bindings with dedicated connector governance', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const upserted = invokeUnary(
        impl.HubRuntime.UpsertChannelIdentityBinding,
        makeConnectorCall({
          request: {
            request_id: 'identity-upsert-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'ops-admin',
              app_id: 'hub-ui',
            },
            binding: {
              provider: 'slack',
              external_user_id: 'U123',
              external_tenant_id: 'T001',
              hub_user_id: 'user_ops_admin',
              roles: ['release_manager', 'approver'],
              approval_only: false,
              status: 'active',
            },
          },
        })
      );

      assert.equal(!!upserted.ok, true);
      assert.equal(!!upserted.created, true);
      assert.equal(String(upserted.binding?.actor_ref || ''), 'xhub.im_identity_binding.v1:slack/U123');

      const listed = invokeUnary(
        impl.HubRuntime.ListChannelIdentityBindings,
        makeConnectorCall({
          request: {
            provider: 'slack',
            hub_user_id: 'user_ops_admin',
          },
        })
      );

      assert.equal(Array.isArray(listed.bindings), true);
      assert.equal(listed.bindings.length, 1);
      assert.equal(String(listed.bindings[0].external_user_id || ''), 'U123');
      assert.equal(String(listed.bindings[0].status || ''), 'active');

      const auditRow = db.listAuditEvents({
        request_id: 'identity-upsert-1',
      }).find((row) => String(row?.event_type || '') === 'channel.identity_binding.upserted');
      assert.ok(auditRow, 'expected channel.identity_binding.upserted audit row');
      assert.equal(String(auditRow?.device_id || ''), 'hub_operator_channel_connector');
      assert.equal(String(auditRow?.app_id || ''), 'hub_runtime_channel_identity');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api resolves runtime snapshot from account rows plus active binding counts', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      invokeUnary(
        impl.HubRuntime.UpsertSupervisorOperatorChannelBinding,
        makeConnectorCall({
          request: {
            request_id: 'binding-upsert-snapshot-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'ops-admin',
              app_id: 'hub-ui',
            },
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C100',
              scope_type: 'project',
              scope_id: 'project_alpha',
              channel_scope: 'group',
              allowed_actions: ['deploy.plan'],
              status: 'active',
            },
          },
        })
      );
      invokeUnary(
        impl.HubRuntime.UpsertSupervisorOperatorChannelBinding,
        makeConnectorCall({
          request: {
            request_id: 'binding-upsert-snapshot-2',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'ops-admin',
              app_id: 'hub-ui',
            },
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C101',
              scope_type: 'project',
              scope_id: 'project_alpha',
              channel_scope: 'group',
              allowed_actions: ['deploy.plan'],
              status: 'active',
            },
          },
        })
      );

      writeChannelRuntimeAccountsSnapshot(runtimeBaseDir, [
        {
          provider: 'slack',
          account_id: 'ops-slack',
          runtime_state: 'ready',
          delivery_ready: true,
          command_entry_ready: true,
          updated_at_ms: 2200,
        },
      ]);

      const snapshot = invokeUnary(
        impl.HubRuntime.GetChannelRuntimeStatusSnapshot,
        makeConnectorCall()
      );

      const slack = (snapshot.providers || []).find((row) => String(row.provider || '') === 'slack');
      assert.ok(slack, 'expected slack runtime provider row');
      assert.equal(String(slack.runtime_state || ''), 'ready');
      assert.equal(Number(slack.active_binding_count || 0), 2);
      assert.equal(!!slack.delivery_ready, true);
      assert.equal(!!slack.command_entry_ready, true);
      assert.equal(Number(snapshot.totals?.bindings_total || 0), 2);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api evaluates command gate and persists project-first route resolution', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      writeClientsSnapshot(runtimeBaseDir, [
        {
          device_id: 'xt-alpha-1',
          user_id: 'xt-alpha-1',
          name: 'XT Alpha 1',
          token: 'token-xt-alpha-1',
          enabled: true,
          allowed_project_ids: ['project_alpha'],
        },
      ]);
      writeGrpcDevicesStatus(runtimeBaseDir, [
        {
          device_id: 'xt-alpha-1',
          connected: true,
          connected_at_ms: Date.now() - 5000,
          last_seen_at_ms: Date.now() - 200,
        },
      ]);

      invokeUnary(
        impl.HubRuntime.UpsertChannelIdentityBinding,
        makeConnectorCall({
          request: {
            request_id: 'identity-upsert-route-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'ops-admin',
              app_id: 'hub-ui',
            },
            binding: {
              provider: 'slack',
              external_user_id: 'U999',
              external_tenant_id: 'T001',
              hub_user_id: 'user_ops_admin',
              roles: ['release_manager'],
              approval_only: false,
              status: 'active',
            },
          },
        })
      );

      const bindingResp = invokeUnary(
        impl.HubRuntime.UpsertSupervisorOperatorChannelBinding,
        makeConnectorCall({
          request: {
            request_id: 'binding-upsert-route-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'ops-admin',
              app_id: 'hub-ui',
            },
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C900',
              channel_scope: 'group',
              scope_type: 'project',
              scope_id: 'project_alpha',
              preferred_device_id: 'xt-alpha-1',
              allowed_actions: ['deploy.plan'],
              status: 'active',
            },
          },
        })
      );
      assert.equal(!!bindingResp.ok, true);

      const gate = invokeUnary(
        impl.HubRuntime.EvaluateChannelCommandGate,
        makeConnectorCall({
          request: {
            request_id: 'gate-eval-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'ops-admin',
              app_id: 'hub-ui',
            },
            client: {
              device_id: 'hub-channel-adapter',
              user_id: 'ops-admin',
              app_id: 'hub-runtime-channel-gateway',
              project_id: 'project_alpha',
            },
            actor: {
              provider: 'slack',
              external_user_id: 'U999',
              external_tenant_id: 'T001',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C900',
              channel_scope: 'group',
            },
            action_name: 'deploy.plan',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );

      assert.equal(!!gate.decision?.allowed, true);
      assert.equal(String(gate.decision?.route_mode || ''), 'hub_to_xt');
      assert.equal(!!gate.audit_logged, true);

      const routed = invokeUnary(
        impl.HubRuntime.ResolveSupervisorChannelRoute,
        makeConnectorCall({
          request: {
            request_id: 'route-resolve-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'ops-admin',
              app_id: 'hub-ui',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C900',
              channel_scope: 'group',
            },
            action_name: 'deploy.plan',
            project_id: 'project_alpha',
          },
        })
      );

      assert.equal(!!routed.ok, true);
      assert.equal(String(routed.route?.route_mode || ''), 'hub_to_xt');
      assert.equal(String(routed.route?.resolved_device_id || ''), 'xt-alpha-1');
      assert.equal(!!routed.route?.xt_online, true);
      assert.equal(!!routed.audit_logged, true);

      const stored = resolveSupervisorChannelSessionRoute(db, {
        provider: 'slack',
        account_id: 'ops-slack',
        conversation_id: 'C900',
        thread_key: '',
      });
      assert.ok(stored, 'expected persisted supervisor channel route');
      assert.equal(String(stored?.route_mode || ''), 'hub_to_xt');
      assert.equal(String(stored?.resolved_device_id || ''), 'xt-alpha-1');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('XT-W3-24/service api executes connector-scoped supervisor queue query via HubRuntime', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      invokeUnary(
        impl.HubRuntime.UpsertChannelIdentityBinding,
        makeConnectorCall({
          request: {
            request_id: 'identity-upsert-exec-1',
            binding: {
              provider: 'slack',
              external_user_id: 'UQUEUE',
              external_tenant_id: 'T001',
              hub_user_id: 'user_queue_operator',
              roles: ['operator'],
              approval_only: false,
              status: 'active',
            },
          },
        })
      );

      invokeUnary(
        impl.HubRuntime.UpsertSupervisorOperatorChannelBinding,
        makeConnectorCall({
          request: {
            request_id: 'binding-upsert-exec-1',
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CQ1',
              channel_scope: 'group',
              scope_type: 'project',
              scope_id: 'project_alpha',
              allowed_actions: ['supervisor.status.get', 'supervisor.blockers.get', 'supervisor.queue.get'],
              status: 'active',
            },
          },
        })
      );

      writeChannelRuntimeAccountsSnapshot(runtimeBaseDir, [
        {
          provider: 'slack',
          account_id: 'ops-slack',
          runtime_state: 'ready',
          delivery_ready: true,
          command_entry_ready: true,
          updated_at_ms: 2200,
        },
      ]);

      const now = Date.now();
      const root = db.upsertProjectLineage({
        request_id: 'lineage-root-1',
        device_id: 'xt-alpha-1',
        user_id: 'xt-owner',
        app_id: 'x_terminal',
        root_project_id: 'project_root',
        parent_project_id: '',
        project_id: 'project_root',
        status: 'active',
        created_at_ms: now - 5000,
      });
      assert.equal(!!root.accepted, true);
      const child = db.upsertProjectLineage({
        request_id: 'lineage-child-1',
        device_id: 'xt-alpha-1',
        user_id: 'xt-owner',
        app_id: 'x_terminal',
        root_project_id: 'project_root',
        parent_project_id: 'project_root',
        project_id: 'project_alpha',
        status: 'active',
        created_at_ms: now - 4000,
      });
      assert.equal(!!child.accepted, true);
      const dispatch = db.attachProjectDispatchContext({
        request_id: 'dispatch-1',
        device_id: 'xt-alpha-1',
        user_id: 'xt-owner',
        app_id: 'x_terminal',
        root_project_id: 'project_root',
        parent_project_id: 'project_root',
        project_id: 'project_alpha',
        assigned_agent_profile: 'release-agent',
        queue_priority: 7,
      });
      assert.equal(!!dispatch.attached, true);
      const heartbeat = db.upsertProjectHeartbeat({
        request_id: 'heartbeat-1',
        device_id: 'xt-alpha-1',
        user_id: 'xt-owner',
        app_id: 'x_terminal',
        root_project_id: 'project_root',
        parent_project_id: 'project_root',
        project_id: 'project_alpha',
        queue_depth: 3,
        oldest_wait_ms: 9000,
        blocked_reason: ['waiting_on_review'],
        next_actions: ['approve release'],
        risk_tier: 'medium',
        heartbeat_seq: 1,
        sent_at_ms: now,
      });
      assert.equal(!!heartbeat.accepted, true);

      const out = await invokeUnaryAsync(
        impl.HubRuntime.ExecuteOperatorChannelHubCommand,
        makeConnectorCall({
          request: {
            request_id: 'channel-exec-query-1',
            actor: {
              provider: 'slack',
              external_user_id: 'UQUEUE',
              external_tenant_id: 'T001',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CQ1',
              channel_scope: 'group',
            },
            action_name: 'supervisor.queue.get',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );

      assert.equal(!!out.ok, true);
      assert.equal(String(out.query?.project_id || ''), 'project_alpha');
      assert.equal(String(out.query?.root_project_id || ''), 'project_root');
      assert.equal(String(out.query?.provider_status?.provider || ''), 'slack');
      assert.equal(String(out.query?.dispatch?.assigned_agent_profile || ''), 'release-agent');
      assert.equal(Number(out.query?.heartbeat?.queue_depth || 0), 3);
      assert.equal(!!out.query?.queue?.planned, true);
      assert.equal(Array.isArray(out.query?.queue?.items), true);
      assert.equal(out.query.queue.items.length >= 1, true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('XT-W3-24/service api executes connector-scoped grant approval without admin token reuse', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      invokeUnary(
        impl.HubRuntime.UpsertChannelIdentityBinding,
        makeConnectorCall({
          request: {
            request_id: 'identity-upsert-approve-1',
            binding: {
              provider: 'slack',
              external_user_id: 'UAPPROVE',
              external_tenant_id: 'T001',
              hub_user_id: 'user_release_manager',
              roles: ['approver'],
              approval_only: false,
              status: 'active',
            },
          },
        })
      );

      invokeUnary(
        impl.HubRuntime.UpsertSupervisorOperatorChannelBinding,
        makeConnectorCall({
          request: {
            request_id: 'binding-upsert-approve-1',
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CA1',
              channel_scope: 'group',
              scope_type: 'project',
              scope_id: 'project_alpha',
              allowed_actions: ['grant.approve'],
              status: 'active',
            },
          },
        })
      );

      const pending = db.createGrantRequest({
        request_id: 'grant-request-1',
        device_id: 'xt-alpha-1',
        user_id: 'xt-owner',
        app_id: 'x_terminal',
        project_id: 'project_alpha',
        capability: 'web.fetch',
        reason: 'Need web access',
        requested_ttl_sec: 1200,
        requested_token_cap: 0,
      });

      const out = await invokeUnaryAsync(
        impl.HubRuntime.ExecuteOperatorChannelHubCommand,
        makeConnectorCall({
          request: {
            request_id: 'channel-exec-approve-1',
            actor: {
              provider: 'slack',
              external_user_id: 'UAPPROVE',
              external_tenant_id: 'T001',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CA1',
              channel_scope: 'group',
            },
            action_name: 'grant.approve',
            scope_type: 'project',
            scope_id: 'project_alpha',
            pending_grant: {
              grant_request_id: pending.grant_request_id,
              project_id: 'project_alpha',
              status: 'pending',
            },
            note: 'approved after slack review',
          },
        })
      );
      assert.equal(!!out.ok, true);
      assert.equal(String(out.grant_action?.decision || ''), 'approved');
      assert.equal(String(out.grant_action?.grant_request_id || ''), String(pending.grant_request_id || ''));
      assert.equal(String(out.grant_action?.grant?.client?.project_id || ''), 'project_alpha');
      assert.equal(String(out.grant_action?.note || ''), 'approved after slack review');

      const grantRequestRow = db.getGrantRequest(pending.grant_request_id);
      assert.equal(String(grantRequestRow?.status || ''), 'approved');
      const auditRow = db.listAuditEvents({
        capability: 'web.fetch',
      }).find((row) => String(row?.event_type || '') === 'grant.request.approved');
      assert.ok(auditRow, 'expected grant.request.approved audit row');
      assert.match(String(auditRow?.ext_json || ''), /operator_channel_connector/);
      assert.match(String(auditRow?.ext_json || ''), /"note":\{"type":"string","bytes":27,"sha256":"/);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('XT-W3-24/service api queues governed XT deploy plan and returns queued receipt when XT has not replied yet', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv({
    ...baseEnv(runtimeBaseDir),
    HUB_OPERATOR_CHANNEL_XT_COMMAND_WAIT_MS: '0',
  }, async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      invokeUnary(
        impl.HubRuntime.UpsertChannelIdentityBinding,
        makeConnectorCall({
          request: {
            request_id: 'identity-upsert-xt-1',
            binding: {
              provider: 'slack',
              external_user_id: 'UXT1',
              external_tenant_id: 'T001',
              hub_user_id: 'user_operator_1',
              roles: ['operator'],
              approval_only: false,
              status: 'active',
            },
          },
        })
      );

      invokeUnary(
        impl.HubRuntime.UpsertSupervisorOperatorChannelBinding,
        makeConnectorCall({
          request: {
            request_id: 'binding-upsert-xt-1',
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CXT1',
              channel_scope: 'group',
              scope_type: 'project',
              scope_id: 'project_alpha',
              preferred_device_id: 'device_xt_001',
              allowed_actions: ['deploy.plan'],
              status: 'active',
            },
          },
        })
      );

      writeClientsSnapshot(runtimeBaseDir, [
        {
          device_id: 'device_xt_001',
          user_id: 'device_xt_001',
          name: 'XT Device 001',
          token: 'token-device-xt-001',
          enabled: true,
          trusted_automation_mode: 'trusted_automation',
          trusted_automation_state: 'armed',
          xt_binding_required: true,
          device_permission_owner_ref: 'owner-1',
          allowed_project_ids: ['project_alpha'],
          trust_profile_present: true,
        },
      ]);
      writeGrpcDevicesStatus(runtimeBaseDir, [
        {
          device_id: 'device_xt_001',
          connected: true,
          last_seen_at_ms: Date.now(),
          connected_at_ms: Date.now(),
        },
      ]);

      const out = await invokeUnaryAsync(
        impl.HubRuntime.ExecuteOperatorChannelHubCommand,
        makeConnectorCall({
          request: {
            request_id: 'channel-exec-deploy-plan-1',
            actor: {
              provider: 'slack',
              external_user_id: 'UXT1',
              external_tenant_id: 'T001',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CXT1',
              channel_scope: 'group',
            },
            action_name: 'deploy.plan',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );

      assert.equal(!!out.ok, true);
      assert.equal(String(out.xt_command?.status || ''), 'queued');
      assert.equal(String(out.xt_command?.action_name || ''), 'deploy.plan');
      assert.equal(String(out.xt_command?.resolved_device_id || ''), 'device_xt_001');
      assert.equal(String(out.route?.route_mode || ''), 'hub_to_xt');

      const queuePath = path.join(runtimeBaseDir, 'operator_channel_xt_command_queue_status.json');
      const queued = JSON.parse(fs.readFileSync(queuePath, 'utf8'));
      assert.equal(String(queued?.schema_version || ''), 'operator_channel_xt_command_queue_status.v1');
      assert.equal(Array.isArray(queued?.items), true);
      assert.equal(String(queued.items[0]?.action_name || ''), 'deploy.plan');
      assert.equal(String(queued.items[0]?.resolved_device_id || ''), 'device_xt_001');

      const auditRow = db.listAuditEvents({
        request_id: 'channel-exec-deploy-plan-1',
      }).find((row) => String(row?.event_type || '') === 'operator_channel.xt_command.queued');
      assert.ok(auditRow, 'expected operator_channel.xt_command.queued audit row');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('XT-W3-24/service api returns XT prepare result when command result is already available', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv({
    ...baseEnv(runtimeBaseDir),
    HUB_OPERATOR_CHANNEL_XT_COMMAND_WAIT_MS: '1',
  }, async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      invokeUnary(
        impl.HubRuntime.UpsertChannelIdentityBinding,
        makeConnectorCall({
          request: {
            request_id: 'identity-upsert-xt-2',
            binding: {
              provider: 'slack',
              external_user_id: 'UXT2',
              external_tenant_id: 'T001',
              hub_user_id: 'user_operator_2',
              roles: ['operator'],
              approval_only: false,
              status: 'active',
            },
          },
        })
      );

      invokeUnary(
        impl.HubRuntime.UpsertSupervisorOperatorChannelBinding,
        makeConnectorCall({
          request: {
            request_id: 'binding-upsert-xt-2',
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CXT2',
              channel_scope: 'group',
              scope_type: 'project',
              scope_id: 'project_beta',
              preferred_device_id: 'device_xt_002',
              allowed_actions: ['deploy.plan'],
              status: 'active',
            },
          },
        })
      );

      writeClientsSnapshot(runtimeBaseDir, [
        {
          device_id: 'device_xt_002',
          user_id: 'device_xt_002',
          name: 'XT Device 002',
          token: 'token-device-xt-002',
          enabled: true,
          trusted_automation_mode: 'trusted_automation',
          trusted_automation_state: 'armed',
          xt_binding_required: true,
          device_permission_owner_ref: 'owner-2',
          allowed_project_ids: ['project_beta'],
          trust_profile_present: true,
        },
      ]);
      writeGrpcDevicesStatus(runtimeBaseDir, [
        {
          device_id: 'device_xt_002',
          connected: true,
          last_seen_at_ms: Date.now(),
          connected_at_ms: Date.now(),
        },
      ]);
      writeJsonFile(runtimeBaseDir, 'operator_channel_xt_command_results_status.json', {
        schema_version: 'operator_channel_xt_command_results_status.v1',
        updated_at_ms: Date.now(),
        items: [
          {
            command_id: 'xtcmd_static_uuid',
            request_id: 'channel-exec-deploy-plan-2',
            action_name: 'deploy.plan',
            project_id: 'project_beta',
            resolved_device_id: 'device_xt_002',
            status: 'prepared',
            deny_code: '',
            detail: 'automation prepared',
            run_id: 'run-beta-1',
            created_at_ms: Date.now() - 500,
            completed_at_ms: Date.now(),
            audit_ref: 'audit-static',
          },
        ],
      });

      const originalNow = Date.now;
      const originalRandomUUID = crypto.randomUUID;
      Date.now = () => 1_773_203_000_000;
      const deterministicUUIDs = [
        'gate-audit-uuid',
        'route-id-uuid',
        'route-audit-uuid',
        'static_uuid',
        'queue-audit-uuid',
        'completed-audit-uuid',
      ];
      let deterministicUUIDIndex = 0;
      crypto.randomUUID = () => {
        const next = deterministicUUIDs[deterministicUUIDIndex];
        deterministicUUIDIndex += 1;
        return next || `deterministic-extra-uuid-${deterministicUUIDIndex}`;
      };
      try {
        const out = await invokeUnaryAsync(
          impl.HubRuntime.ExecuteOperatorChannelHubCommand,
          makeConnectorCall({
            request: {
              request_id: 'channel-exec-deploy-plan-2',
              actor: {
                provider: 'slack',
                external_user_id: 'UXT2',
                external_tenant_id: 'T001',
              },
              channel: {
                provider: 'slack',
                account_id: 'ops-slack',
                conversation_id: 'CXT2',
                channel_scope: 'group',
              },
              action_name: 'deploy.plan',
              scope_type: 'project',
              scope_id: 'project_beta',
            },
          })
        );

        assert.equal(!!out.ok, true);
        assert.equal(String(out.xt_command?.status || ''), 'prepared');
        assert.equal(String(out.xt_command?.run_id || ''), 'run-beta-1');
        assert.equal(String(out.xt_command?.resolved_device_id || ''), 'device_xt_002');
      } finally {
        Date.now = originalNow;
        crypto.randomUUID = originalRandomUUID;
      }

      const auditRow = db.listAuditEvents({
        request_id: 'channel-exec-deploy-plan-2',
      }).find((row) => String(row?.event_type || '') === 'operator_channel.xt_command.completed');
      assert.ok(auditRow, 'expected operator_channel.xt_command.completed audit row');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
