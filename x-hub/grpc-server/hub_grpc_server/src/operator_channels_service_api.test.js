import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import { resolveSupervisorOperatorChannelBinding } from './channel_bindings_store.js';
import {
  claimChannelDeliveryJobs,
  enqueueChannelDeliveryJob,
  recordChannelDeliveryJobAttempt,
} from './channel_delivery_jobs.js';
import { getChannelIdentityBinding, upsertChannelIdentityBinding } from './channel_identity_store.js';
import { getChannelOnboardingFirstSmokeReceiptByTicketId } from './channel_onboarding_first_smoke.js';
import { listChannelOutboxItems } from './channel_outbox.js';
import {
  getChannelOnboardingAutoBindReceiptByTicketId,
  getChannelOnboardingAutoBindRevocationByTicketId,
} from './channel_onboarding_transaction.js';
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

async function withFetchAsync(tempFetch, fn) {
  const previous = globalThis.fetch;
  globalThis.fetch = tempFetch;
  try {
    return await fn();
  } finally {
    globalThis.fetch = previous;
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

function actionAuditPhases(db, request_id) {
  const rank = {
    'operator_channel.action.requested': 0,
    'operator_channel.action.approved': 1,
    'operator_channel.action.queued': 1,
    'operator_channel.action.denied': 1,
    'operator_channel.action.executed': 2,
  };
  return db.listAuditEvents({ request_id })
    .filter((row) => String(row?.event_type || '').startsWith('operator_channel.action.'))
    .sort((a, b) => (rank[String(a?.event_type || '')] ?? 99) - (rank[String(b?.event_type || '')] ?? 99))
    .map((row) => String(row?.event_type || ''));
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms || 0))));
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
              access_groups: ['group_allowlist'],
              approval_only: false,
              status: 'active',
            },
          },
        })
      );

      assert.equal(!!upserted.ok, true);
      assert.equal(!!upserted.created, true);
      assert.equal(String(upserted.binding?.stable_external_id || ''), 'slack/T001/U123');
      assert.equal(String(upserted.binding?.actor_ref || ''), 'xhub.im_identity_binding.v1:slack/T001/U123');

      const listed = invokeUnary(
        impl.HubRuntime.ListChannelIdentityBindings,
        makeConnectorCall({
          request: {
            stable_external_id: 'slack/T001/U123',
          },
        })
      );

      assert.equal(Array.isArray(listed.bindings), true);
      assert.equal(listed.bindings.length, 1);
      assert.equal(String(listed.bindings[0].external_user_id || ''), 'U123');
      assert.deepEqual(listed.bindings[0].access_groups, ['group_allowlist']);
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
      assert.deepEqual(slack.repair_hints || [], []);
      assert.equal(Number(snapshot.totals?.bindings_total || 0), 2);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api projects delivery outbox degradation into supervisor runtime snapshot', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const baseNow = Date.now();

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      writeChannelRuntimeAccountsSnapshot(runtimeBaseDir, [
        {
          provider: 'slack',
          account_id: 'ops-slack',
          runtime_state: 'ready',
          delivery_ready: true,
          command_entry_ready: true,
          updated_at_ms: baseNow - 500,
        },
      ]);

      const queued = enqueueChannelDeliveryJob(db, {
        request_id: 'runtime-delivery-degraded-1',
        audit: {
          device_id: 'hub-supervisor',
          app_id: 'hub_runtime_operator_channels',
        },
        job: {
          provider: 'slack',
          account_id: 'ops-slack',
          conversation_id: 'C-runtime',
          delivery_class: 'alert',
          payload_ref: 'local://channel-payloads/runtime-alert-1.json',
          dedupe_key: 'sha256:runtime-alert-1',
          audit_ref: 'audit-runtime-alert-1',
          max_attempts: 1,
        },
      });
      assert.equal(!!queued.ok, true);

      const claimStart = Number(queued.job?.created_at_ms || baseNow) + 10;
      const claimed = claimChannelDeliveryJobs(db, {
        provider: 'slack',
        account_id: 'ops-slack',
        now_ms: claimStart,
        limit: 5,
      });
      assert.equal(claimed.length, 1);

      const failed = recordChannelDeliveryJobAttempt(db, {
        job_id: queued.job?.job_id,
        delivered: false,
        deny_code: 'slack_rate_limited',
        error_message: 'slack_rate_limited',
        retry_after_ms: 30000,
        provider_backoff_ms: 30000,
        now_ms: claimStart + 200,
      });
      assert.equal(!!failed.ok, true);

      const snapshot = invokeUnary(
        impl.HubRuntime.GetChannelRuntimeStatusSnapshot,
        makeConnectorCall()
      );
      const slack = (snapshot.providers || []).find((row) => String(row.provider || '') === 'slack');
      assert.ok(slack, 'expected slack runtime provider row');
      assert.equal(String(slack.runtime_state || ''), 'degraded');
      assert.equal(String(slack.last_error_code || ''), 'slack_rate_limited');
      assert.equal(!!slack.delivery_ready, false);
      assert.equal(!!slack.command_entry_ready, true);
      assert.equal(
        (slack.repair_hints || []).some((item) => String(item || '').includes('回复投递处于降级状态')),
        true
      );
      assert.equal(Number(snapshot.totals?.degraded_total || 0) >= 1, true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api creates and dedupes onboarding discovery tickets for unknown ingress', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-create-1',
            ticket: {
              provider: 'slack',
              account_id: 'T001',
              external_user_id: 'U123',
              external_tenant_id: 'T001',
              conversation_id: 'C001',
              thread_key: '171.1',
              ingress_surface: 'group',
              display_name: 'Alice Ops',
              first_message_preview: 'deploy.plan',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);
      assert.equal(!!created.created, true);
      assert.equal(!!created.updated, false);
      assert.equal(String(created.ticket?.status || ''), 'pending');
      assert.equal(Number(created.ticket?.event_count || 0), 1);

      const touched = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-create-2',
            ticket: {
              provider: 'slack',
              account_id: 'T001',
              external_user_id: 'U123',
              external_tenant_id: 'T001',
              conversation_id: 'C001',
              thread_key: '171.1',
              ingress_surface: 'group',
              display_name: 'Alice Renamed',
              first_message_preview: 'supervisor.status.get',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!touched.ok, true);
      assert.equal(!!touched.created, false);
      assert.equal(!!touched.updated, true);
      assert.equal(String(touched.ticket?.ticket_id || ''), String(created.ticket?.ticket_id || ''));
      assert.equal(Number(touched.ticket?.event_count || 0), 2);

      const listed = invokeUnary(
        impl.HubRuntime.ListChannelOnboardingDiscoveryTickets,
        makeAdminCall({
          request: {
            provider: 'slack',
            status: 'pending',
          },
        })
      );
      assert.equal(Array.isArray(listed.tickets), true);
      assert.equal(listed.tickets.length, 1);
      assert.equal(String(listed.tickets[0].ticket_id || ''), String(created.ticket?.ticket_id || ''));
      assert.equal(Number(listed.tickets[0].event_count || 0), 2);

      const auditRows = db.listAuditEvents({
        request_id: 'disc-create-1',
      }).filter((row) => String(row?.event_type || '').startsWith('channel.onboarding.discovery.'));
      assert.equal(auditRows.length, 1);
      assert.equal(String(auditRows[0]?.event_type || ''), 'channel.onboarding.discovery.created');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api discovery dedupe ignores display name and still separates different stable ids', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const first = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-display-dedupe-1',
            ticket: {
              provider: 'slack',
              account_id: 'ops-slack',
              external_user_id: 'U_DISPLAY_A',
              external_tenant_id: 'T001',
              conversation_id: 'C_DISPLAY',
              thread_key: '171.88',
              ingress_surface: 'group',
              display_name: 'Same Visible Name',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!first.ok, true);

      const second = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-display-dedupe-2',
            ticket: {
              provider: 'slack',
              account_id: 'ops-slack',
              external_user_id: 'U_DISPLAY_B',
              external_tenant_id: 'T001',
              conversation_id: 'C_DISPLAY',
              thread_key: '171.88',
              ingress_surface: 'group',
              display_name: 'Same Visible Name',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!second.ok, true);
      assert.notEqual(String(first.ticket?.ticket_id || ''), String(second.ticket?.ticket_id || ''));

      const listed = invokeUnary(
        impl.HubRuntime.ListChannelOnboardingDiscoveryTickets,
        makeAdminCall({
          request: {
            provider: 'slack',
            status: 'pending',
            conversation_id: 'C_DISPLAY',
          },
        })
      );
      assert.equal(listed.tickets.length, 2);
      assert.deepEqual(
        listed.tickets.map((ticket) => String(ticket.external_user_id || '')).sort(),
        ['U_DISPLAY_A', 'U_DISPLAY_B']
      );
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api keeps unknown ingress in quarantine with zero auto-bind side effects before approval', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-quarantine-1',
            ticket: {
              provider: 'slack',
              account_id: 'ops-slack',
              external_user_id: 'U_QUARANTINE',
              external_tenant_id: 'T001',
              conversation_id: 'C_QUARANTINE',
              thread_key: '171.55',
              ingress_surface: 'group',
              first_message_preview: 'deploy.execute',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);
      assert.equal(String(created.ticket?.status || ''), 'pending');

      const identityBinding = getChannelIdentityBinding(db, {
        provider: 'slack',
        external_user_id: 'U_QUARANTINE',
        external_tenant_id: 'T001',
      });
      assert.equal(identityBinding, null);

      const routeBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'slack',
        account_id: 'ops-slack',
        conversation_id: 'C_QUARANTINE',
        thread_key: '171.55',
        channel_scope: 'group',
      });
      assert.equal(routeBinding.binding, null);

      const autoBindReceipt = getChannelOnboardingAutoBindReceiptByTicketId(db, {
        ticket_id: created.ticket.ticket_id,
      });
      assert.equal(autoBindReceipt, null);

      const firstSmokeReceipt = getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
        ticket_id: created.ticket.ticket_id,
      });
      assert.equal(firstSmokeReceipt, null);

      const outboxItems = listChannelOutboxItems(db, {
        ticket_id: created.ticket.ticket_id,
        limit: 10,
      });
      assert.deepEqual(outboxItems, []);

      const onboardingAuditRows = db.listAuditEvents({ limit: 200 }).filter((row) => (
        String(row?.request_id || '') === 'disc-quarantine-1'
        && String(row?.event_type || '').startsWith('channel.onboarding.')
      ));
      assert.equal(onboardingAuditRows.length, 1);
      assert.equal(String(onboardingAuditRows[0]?.event_type || ''), 'channel.onboarding.discovery.created');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api keeps discovery queue admin-only and expires stale pending tickets on read', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-expire-1',
            ticket: {
              provider: 'whatsapp_cloud_api',
              account_id: 'ops_whatsapp_cloud',
              external_user_id: '15551234567',
              external_tenant_id: 'ops_whatsapp_cloud',
              conversation_id: '15551234567',
              ingress_surface: 'dm',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
              expires_at_ms: Date.now() - 10,
            },
          },
        })
      );
      assert.equal(!!created.ok, true);
      assert.equal(String(created.ticket?.status || ''), 'pending');

      assert.throws(
        () => invokeUnary(
          impl.HubRuntime.ListChannelOnboardingDiscoveryTickets,
          makeConnectorCall({
            request: {
              provider: 'whatsapp_cloud_api',
              status: 'pending',
            },
          })
        ),
        /Missing\/invalid admin token/
      );

      const listedPending = invokeUnary(
        impl.HubRuntime.ListChannelOnboardingDiscoveryTickets,
        makeAdminCall({
          request: {
            provider: 'whatsapp_cloud_api',
            status: 'pending',
          },
        })
      );
      assert.equal(Array.isArray(listedPending.tickets), true);
      assert.equal(listedPending.tickets.length, 0);

      const fetched = invokeUnary(
        impl.HubRuntime.GetChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            ticket_id: created.ticket.ticket_id,
          },
        })
      );
      assert.equal(!!fetched.ok, true);
      assert.equal(String(fetched.ticket?.status || ''), 'expired');

      const listedExpired = invokeUnary(
        impl.HubRuntime.ListChannelOnboardingDiscoveryTickets,
        makeAdminCall({
          request: {
            provider: 'whatsapp_cloud_api',
            status: 'expired',
          },
        })
      );
      assert.equal(listedExpired.tickets.length, 1);
      assert.equal(String(listedExpired.tickets[0]?.ticket_id || ''), String(created.ticket?.ticket_id || ''));
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

runAsync('XT-W3-24/service api reviews onboarding discovery tickets through local admin approval decision', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-review-create-1',
            ticket: {
              provider: 'telegram',
              account_id: 'telegram_ops_bot',
              external_user_id: '123456',
              external_tenant_id: 'telegram_ops_bot',
              conversation_id: '-1001234567890',
              thread_key: 'topic:42',
              ingress_surface: 'group',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);

      const reviewed = invokeUnary(
        impl.HubRuntime.ReviewChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-review-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: created.ticket.ticket_id,
            decision: {
              decision: 'approve',
              approved_by_hub_user_id: 'user_ops_admin',
              approved_via: 'hub_local_ui',
              hub_user_id: 'user_ops_alice',
              scope_type: 'project',
              scope_id: 'project_alpha',
              binding_mode: 'thread_binding',
              preferred_device_id: 'xt-alpha-1',
              allowed_actions: ['supervisor.status.get', 'supervisor.queue.get'],
              grant_profile: 'low_risk_readonly',
              note: 'approved after local review',
            },
          },
        })
      );
      assert.equal(!!reviewed.ok, true);
      assert.equal(String(reviewed.ticket?.status || ''), 'approved');
      assert.equal(String(reviewed.ticket?.recommended_binding_mode || ''), 'thread_binding');
      assert.equal(String(reviewed.decision?.decision || ''), 'approve');
      assert.equal(String(reviewed.decision?.hub_user_id || ''), 'user_ops_alice');
      assert.equal(String(reviewed.automation_state?.ticket_id || ''), String(created.ticket?.ticket_id || ''));
      assert.equal(String(reviewed.automation_state?.first_smoke?.status || ''), 'query_executed');
      assert.deepEqual(
        (reviewed.automation_state?.outbox_items || []).map((item) => String(item?.item_kind || '')).sort(),
        ['onboarding_ack', 'onboarding_first_smoke']
      );
      assert.equal(String(reviewed.automation_state?.delivery_readiness?.provider || ''), 'telegram');
      assert.equal(reviewed.automation_state?.delivery_readiness?.ready, false);
      assert.equal(reviewed.automation_state?.delivery_readiness?.reply_enabled, true);
      assert.equal(reviewed.automation_state?.delivery_readiness?.credentials_configured, false);
      assert.equal(
        String(reviewed.automation_state?.delivery_readiness?.remediation_hint || '').includes('HUB_TELEGRAM_OPERATOR_BOT_TOKEN'),
        true
      );

      const identityBinding = getChannelIdentityBinding(db, {
        provider: 'telegram',
        external_user_id: '123456',
        external_tenant_id: 'telegram_ops_bot',
      });
      assert.equal(String(identityBinding?.hub_user_id || ''), 'user_ops_alice');
      assert.deepEqual(identityBinding?.roles || [], ['viewer']);

      const routeBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'telegram',
        account_id: 'telegram_ops_bot',
        conversation_id: '-1001234567890',
        thread_key: 'topic:42',
        channel_scope: 'group',
      });
      assert.equal(String(routeBinding.binding_match_mode || ''), 'exact_thread');
      assert.deepEqual(routeBinding.binding?.allowed_actions || [], ['supervisor.status.get', 'supervisor.queue.get']);

      const autoBindReceipt = getChannelOnboardingAutoBindReceiptByTicketId(db, {
        ticket_id: created.ticket.ticket_id,
      });
      assert.equal(String(autoBindReceipt?.status || ''), 'applied');
      assert.equal(String(autoBindReceipt?.channel_binding_id || ''), String(routeBinding.binding?.binding_id || ''));

      const firstSmokeReceipt = getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
        ticket_id: created.ticket.ticket_id,
      });
      assert.equal(String(firstSmokeReceipt?.ticket_id || ''), String(created.ticket?.ticket_id || ''));
      assert.equal(String(firstSmokeReceipt?.status || ''), 'query_executed');
      assert.equal(String(firstSmokeReceipt?.action_name || ''), 'supervisor.status.get');

      const queuedOutbox = listChannelOutboxItems(db, {
        ticket_id: created.ticket.ticket_id,
        limit: 10,
      });
      assert.deepEqual(
        queuedOutbox.map((item) => String(item.item_kind || '')).sort(),
        ['onboarding_ack', 'onboarding_first_smoke']
      );

      const fetched = invokeUnary(
        impl.HubRuntime.GetChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            ticket_id: created.ticket.ticket_id,
          },
        })
      );
      assert.equal(!!fetched.ok, true);
      assert.equal(String(fetched.ticket?.ticket_id || ''), String(created.ticket?.ticket_id || ''));
      assert.equal(String(fetched.latest_decision?.decision_id || ''), String(reviewed.decision?.decision_id || ''));
      assert.deepEqual(fetched.latest_decision?.allowed_actions, ['supervisor.status.get', 'supervisor.queue.get']);
      assert.equal(String(fetched.automation_state?.ticket_id || ''), String(created.ticket?.ticket_id || ''));
      assert.equal(String(fetched.automation_state?.first_smoke?.receipt_id || ''), String(firstSmokeReceipt?.receipt_id || ''));
      assert.deepEqual(
        (fetched.automation_state?.outbox_items || []).map((item) => String(item?.item_kind || '')).sort(),
        ['onboarding_ack', 'onboarding_first_smoke']
      );
      assert.equal(String(fetched.automation_state?.delivery_readiness?.provider || ''), 'telegram');
      assert.equal(fetched.automation_state?.delivery_readiness?.ready, false);

      const gated = invokeUnary(
        impl.HubRuntime.EvaluateChannelCommandGate,
        makeConnectorCall({
          request: {
            request_id: 'disc-review-gated-1',
            actor: {
              provider: 'telegram',
              external_user_id: '123456',
              external_tenant_id: 'telegram_ops_bot',
            },
            channel: {
              provider: 'telegram',
              account_id: 'telegram_ops_bot',
              conversation_id: '-1001234567890',
              thread_key: 'topic:42',
              channel_scope: 'group',
            },
            action_name: 'supervisor.status.get',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );
      assert.equal(gated.decision?.allowed, true);

      await sleep(30);

      const flushedOutbox = listChannelOutboxItems(db, {
        ticket_id: created.ticket.ticket_id,
        limit: 10,
      });
      assert.equal(flushedOutbox.length, 2);
      assert.equal(flushedOutbox.every((item) => String(item.status || '') === 'pending'), true);
      assert.equal(flushedOutbox.every((item) => Number(item.attempt_count || 0) >= 1), true);
      assert.equal(
        flushedOutbox.every((item) => String(item.last_error_code || '') === 'provider_delivery_not_configured'),
        true
      );

      const auditRows = db.listAuditEvents({ limit: 200 }).filter((row) => (
        String(row?.event_type || '').startsWith('channel.onboarding.')
        && String(row?.request_id || '').startsWith('disc-review-1')
      ));
      assert.equal(auditRows.length >= 3, true);
      const eventTypes = new Set(auditRows.map((row) => String(row?.event_type || '')));
      assert.equal(eventTypes.has('channel.onboarding.discovery.approved'), true);
      assert.equal(eventTypes.has('channel.onboarding.auto_bind.succeeded'), true);
      assert.equal(eventTypes.has('channel.onboarding.first_smoke.completed'), true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

runAsync('XT-W3-24/service api retries pending onboarding outbox after credentials are configured', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-retry-create-1',
            ticket: {
              provider: 'slack',
              account_id: 'T_OPS',
              external_user_id: 'URETRY',
              external_tenant_id: 'T_OPS',
              conversation_id: 'C_retry_grpc',
              thread_key: '171.9',
              ingress_surface: 'group',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);

      const reviewed = invokeUnary(
        impl.HubRuntime.ReviewChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-retry-review-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: created.ticket.ticket_id,
            decision: {
              decision: 'approve',
              approved_by_hub_user_id: 'user_ops_admin',
              approved_via: 'hub_local_ui',
              hub_user_id: 'user_ops_alice',
              scope_type: 'project',
              scope_id: 'project_alpha',
              binding_mode: 'thread_binding',
              allowed_actions: ['supervisor.status.get', 'supervisor.blockers.get'],
            },
          },
        })
      );
      assert.equal(!!reviewed.ok, true);
      assert.equal(Number(reviewed.automation_state?.outbox_pending_count || 0), 2);

      await sleep(40);

      let fetchCalls = 0;
      await withEnv({
        ...baseEnv(runtimeBaseDir),
        HUB_SLACK_OPERATOR_REPLY_ENABLE: '1',
        HUB_SLACK_OPERATOR_BOT_TOKEN: 'xoxb-grpc-retry',
      }, async () => {
        await withFetchAsync(async (url, options = {}) => {
          fetchCalls += 1;
          assert.equal(String(url || '').endsWith('/chat.postMessage'), true);
          assert.equal(String(options?.headers?.authorization || ''), 'Bearer xoxb-grpc-retry');
          return {
            ok: true,
            async text() {
              return JSON.stringify({
                ok: true,
                channel: 'C_retry_grpc',
                ts: `171.9.${fetchCalls}`,
              });
            },
          };
        }, async () => {
          const retried = await invokeUnaryAsync(
            impl.HubRuntime.RetryChannelOnboardingOutbox,
            makeAdminCall({
              request: {
                request_id: 'disc-retry-outbox-1',
                admin: {
                  device_id: 'hub-admin-local',
                  user_id: 'user_ops_admin',
                  app_id: 'hub_local_ui',
                },
                ticket_id: created.ticket.ticket_id,
              },
            })
          );
          assert.equal(!!retried.ok, true);
          assert.equal(String(retried.ticket_id || ''), String(created.ticket.ticket_id || ''));
          assert.equal(Number(retried.delivered_count || 0), 2);
          assert.equal(Number(retried.pending_count || 0), 0);
          assert.equal(Number(retried.automation_state?.outbox_delivered_count || 0), 2);
          assert.equal(Number(retried.automation_state?.outbox_pending_count || 0), 0);
          assert.equal(String(retried.automation_state?.delivery_readiness?.provider || ''), 'slack');
          assert.equal(retried.automation_state?.delivery_readiness?.ready, true);
          assert.equal(retried.automation_state?.delivery_readiness?.reply_enabled, true);
          assert.equal(retried.automation_state?.delivery_readiness?.credentials_configured, true);
          assert.equal(
            (retried.automation_state?.outbox_items || []).every((item) => String(item?.status || '') === 'delivered'),
            true
          );
        });
      });
      assert.equal(fetchCalls, 2);

      const outboxItems = listChannelOutboxItems(db, {
        ticket_id: created.ticket.ticket_id,
        limit: 10,
      });
      assert.equal(outboxItems.length, 2);
      assert.equal(outboxItems.every((item) => String(item.status || '') === 'delivered'), true);
      assert.equal(outboxItems.every((item) => Number(item.attempt_count || 0) === 2), true);

      const retryAuditRows = db.listAuditEvents({ limit: 200 }).filter((row) => (
        String(row?.request_id || '') === 'disc-retry-outbox-1'
        && String(row?.event_type || '') === 'channel.onboarding.outbox.retry.completed'
      ));
      assert.equal(retryAuditRows.length, 1);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api approval of a DM binding does not expand the actor to unrelated group conversations', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-dm-scope-create-1',
            ticket: {
              provider: 'slack',
              account_id: 'ops-slack',
              external_user_id: 'U_DM_SCOPE',
              external_tenant_id: 'T001',
              conversation_id: 'D900',
              thread_key: '',
              ingress_surface: 'dm',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);

      const reviewed = invokeUnary(
        impl.HubRuntime.ReviewChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-dm-scope-review-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: created.ticket.ticket_id,
            decision: {
              decision: 'approve',
              approved_by_hub_user_id: 'user_ops_admin',
              approved_via: 'hub_local_ui',
              hub_user_id: 'user_ops_alice',
              scope_type: 'project',
              scope_id: 'project_alpha',
              binding_mode: 'conversation_binding',
              allowed_actions: ['supervisor.status.get'],
              grant_profile: 'low_risk_readonly',
              note: 'dm only',
            },
          },
        })
      );
      assert.equal(!!reviewed.ok, true);

      const dmRouteBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'slack',
        account_id: 'ops-slack',
        conversation_id: 'D900',
        thread_key: '',
        channel_scope: 'dm',
      });
      assert.ok(dmRouteBinding.binding, 'expected exact DM binding after approval');
      assert.equal(String(dmRouteBinding.binding_match_mode || ''), 'conversation_exact');

      const groupRouteBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'slack',
        account_id: 'ops-slack',
        conversation_id: 'C901',
        thread_key: '',
        channel_scope: 'group',
      });
      assert.equal(groupRouteBinding.binding, null);
      assert.equal(String(groupRouteBinding.binding_match_mode || ''), 'none');

      const allowedInDm = invokeUnary(
        impl.HubRuntime.EvaluateChannelCommandGate,
        makeConnectorCall({
          request: {
            request_id: 'disc-dm-scope-gate-dm-1',
            actor: {
              provider: 'slack',
              external_user_id: 'U_DM_SCOPE',
              external_tenant_id: 'T001',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'D900',
              channel_scope: 'dm',
            },
            action_name: 'supervisor.status.get',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );
      assert.equal(allowedInDm.decision?.allowed, true);

      const deniedInGroup = invokeUnary(
        impl.HubRuntime.EvaluateChannelCommandGate,
        makeConnectorCall({
          request: {
            request_id: 'disc-dm-scope-gate-group-1',
            actor: {
              provider: 'slack',
              external_user_id: 'U_DM_SCOPE',
              external_tenant_id: 'T001',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C901',
              channel_scope: 'group',
            },
            action_name: 'supervisor.status.get',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );
      assert.equal(deniedInGroup.decision?.allowed, false);
      assert.equal(String(deniedInGroup.decision?.deny_code || ''), 'channel_binding_missing');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api fails closed when onboarding approval requests unsafe actions', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-review-create-unsafe-1',
            ticket: {
              provider: 'slack',
              account_id: 'T001',
              external_user_id: 'U123',
              external_tenant_id: 'T001',
              conversation_id: 'C001',
              thread_key: '171.1',
              ingress_surface: 'group',
              first_message_preview: 'deploy execute',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);

      const reviewed = invokeUnary(
        impl.HubRuntime.ReviewChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-review-unsafe-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: created.ticket.ticket_id,
            decision: {
              decision: 'approve',
              approved_by_hub_user_id: 'user_ops_admin',
              approved_via: 'hub_local_ui',
              hub_user_id: 'user_ops_alice',
              scope_type: 'project',
              scope_id: 'project_alpha',
              binding_mode: 'thread_binding',
              allowed_actions: ['deploy.execute'],
              note: 'should fail closed',
            },
          },
        })
      );
      assert.equal(!!reviewed.ok, false);
      assert.equal(String(reviewed.deny_code || ''), 'allowed_actions_unsafe');

      const fetched = invokeUnary(
        impl.HubRuntime.GetChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            ticket_id: created.ticket.ticket_id,
          },
        })
      );
      assert.equal(!!fetched.ok, true);
      assert.equal(String(fetched.ticket?.status || ''), 'pending');
      assert.equal(String(fetched.latest_decision?.decision_id || ''), '');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api fails closed when onboarding auto-bind sees identity conflicts', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const seededIdentity = upsertChannelIdentityBinding(db, {
        request_id: 'disc-review-conflict-seed-identity-1',
        binding: {
          provider: 'feishu',
          external_user_id: 'ou_conflict_1',
          external_tenant_id: 'tenant_ops',
          hub_user_id: 'user_ops_bob',
          roles: ['viewer'],
          access_groups: ['group_allowlist'],
          approval_only: false,
          status: 'active',
        },
      });
      assert.equal(!!seededIdentity.ok, true);

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-review-conflict-create-1',
            ticket: {
              provider: 'feishu',
              account_id: 'tenant_ops',
              external_user_id: 'ou_conflict_1',
              external_tenant_id: 'tenant_ops',
              conversation_id: 'oc_conflict_1',
              thread_key: 'om_conflict_1',
              ingress_surface: 'group',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);

      const reviewed = invokeUnary(
        impl.HubRuntime.ReviewChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-review-conflict-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: created.ticket.ticket_id,
            decision: {
              decision: 'approve',
              approved_by_hub_user_id: 'user_ops_admin',
              approved_via: 'hub_local_ui',
              hub_user_id: 'user_ops_alice',
              scope_type: 'project',
              scope_id: 'project_alpha',
              binding_mode: 'thread_binding',
              allowed_actions: ['supervisor.status.get'],
            },
          },
        })
      );
      assert.equal(!!reviewed.ok, false);
      assert.equal(String(reviewed.deny_code || ''), 'identity_binding_conflict');

      const fetched = invokeUnary(
        impl.HubRuntime.GetChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            ticket_id: created.ticket.ticket_id,
          },
        })
      );
      assert.equal(!!fetched.ok, true);
      assert.equal(String(fetched.ticket?.status || ''), 'pending');
      assert.equal(String(fetched.latest_decision?.decision_id || ''), '');

      const conflictingIdentity = getChannelIdentityBinding(db, {
        provider: 'feishu',
        external_user_id: 'ou_conflict_1',
        external_tenant_id: 'tenant_ops',
      });
      assert.equal(String(conflictingIdentity?.hub_user_id || ''), 'user_ops_bob');

      const routeBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'feishu',
        account_id: 'tenant_ops',
        conversation_id: 'oc_conflict_1',
        thread_key: 'om_conflict_1',
        channel_scope: 'group',
      });
      assert.equal(routeBinding.binding, null);

      const autoBindReceipt = getChannelOnboardingAutoBindReceiptByTicketId(db, {
        ticket_id: created.ticket.ticket_id,
      });
      assert.equal(autoBindReceipt, null);

      const auditRows = db.listAuditEvents({
        request_id: 'disc-review-conflict-1',
      }).filter((row) => String(row?.event_type || '').startsWith('channel.onboarding.'));
      assert.equal(auditRows.length, 1);
      assert.equal(String(auditRows[0]?.event_type || ''), 'channel.onboarding.auto_bind.rejected');
      assert.equal(String(auditRows[0]?.ok), '0');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

runAsync('XT-W3-24/service api fails closed when onboarding auto-bind sees a newer identity route drift ticket', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnv(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const stale = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-review-drift-create-1',
            ticket: {
              provider: 'slack',
              account_id: 'T_DRIFT',
              external_user_id: 'U_DRIFT',
              external_tenant_id: 'T_DRIFT',
              conversation_id: 'C_STALE',
              thread_key: '171.1',
              ingress_surface: 'group',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!stale.ok, true);

      await sleep(10);

      const latest = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-review-drift-create-2',
            ticket: {
              provider: 'slack',
              account_id: 'T_DRIFT',
              external_user_id: 'U_DRIFT',
              external_tenant_id: 'T_DRIFT',
              conversation_id: 'C_LATEST',
              thread_key: '171.2',
              ingress_surface: 'group',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!latest.ok, true);
      assert.notEqual(String(stale.ticket?.ticket_id || ''), String(latest.ticket?.ticket_id || ''));

      const reviewed = invokeUnary(
        impl.HubRuntime.ReviewChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-review-drift-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: stale.ticket.ticket_id,
            decision: {
              decision: 'approve',
              approved_by_hub_user_id: 'user_ops_admin',
              approved_via: 'hub_local_ui',
              hub_user_id: 'user_ops_alice',
              scope_type: 'project',
              scope_id: 'project_alpha',
              binding_mode: 'thread_binding',
              allowed_actions: ['supervisor.status.get'],
            },
          },
        })
      );
      assert.equal(!!reviewed.ok, false);
      assert.equal(String(reviewed.deny_code || ''), 'identity_route_drift_detected');

      const staleFetched = invokeUnary(
        impl.HubRuntime.GetChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            ticket_id: stale.ticket.ticket_id,
          },
        })
      );
      assert.equal(!!staleFetched.ok, true);
      assert.equal(String(staleFetched.ticket?.status || ''), 'pending');
      assert.equal(String(staleFetched.latest_decision?.decision_id || ''), '');

      const latestFetched = invokeUnary(
        impl.HubRuntime.GetChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            ticket_id: latest.ticket.ticket_id,
          },
        })
      );
      assert.equal(!!latestFetched.ok, true);
      assert.equal(String(latestFetched.ticket?.status || ''), 'pending');

      const identityBinding = getChannelIdentityBinding(db, {
        provider: 'slack',
        external_user_id: 'U_DRIFT',
        external_tenant_id: 'T_DRIFT',
      });
      assert.equal(identityBinding, null);

      const staleRouteBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'slack',
        account_id: 'T_DRIFT',
        conversation_id: 'C_STALE',
        thread_key: '171.1',
        channel_scope: 'group',
      });
      assert.equal(staleRouteBinding.binding, null);

      const latestRouteBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'slack',
        account_id: 'T_DRIFT',
        conversation_id: 'C_LATEST',
        thread_key: '171.2',
        channel_scope: 'group',
      });
      assert.equal(latestRouteBinding.binding, null);

      const autoBindReceipt = getChannelOnboardingAutoBindReceiptByTicketId(db, {
        ticket_id: stale.ticket.ticket_id,
      });
      assert.equal(autoBindReceipt, null);

      const auditRows = db.listAuditEvents({
        request_id: 'disc-review-drift-1',
      }).filter((row) => String(row?.event_type || '').startsWith('channel.onboarding.'));
      assert.equal(auditRows.length, 1);
      assert.equal(String(auditRows[0]?.event_type || ''), 'channel.onboarding.auto_bind.rejected');
      assert.equal(String(auditRows[0]?.ok), '0');
      const ext = JSON.parse(String(auditRows[0]?.ext_json || '{}'));
      assert.equal(String(ext?.detail?.superseding_ticket_id || ''), String(latest.ticket?.ticket_id || ''));
      assert.equal(String(ext?.detail?.superseding_conversation_id || ''), 'C_LATEST');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api revokes approved onboarding bindings and surfaces effective status through gRPC', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-revoke-create-1',
            ticket: {
              provider: 'slack',
              account_id: 'T_REVOKE_GRPC',
              external_user_id: 'U_REVOKE_GRPC',
              external_tenant_id: 'T_REVOKE_GRPC',
              conversation_id: 'C_REVOKE_GRPC',
              thread_key: '171.11',
              ingress_surface: 'group',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);

      const reviewed = invokeUnary(
        impl.HubRuntime.ReviewChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-revoke-review-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: created.ticket.ticket_id,
            decision: {
              decision: 'approve',
              approved_by_hub_user_id: 'user_ops_admin',
              approved_via: 'hub_local_ui',
              hub_user_id: 'user_ops_alice',
              scope_type: 'project',
              scope_id: 'project_alpha',
              binding_mode: 'thread_binding',
              preferred_device_id: 'xt-alpha-1',
              allowed_actions: ['supervisor.status.get', 'supervisor.blockers.get'],
            },
          },
        })
      );
      assert.equal(!!reviewed.ok, true);
      assert.equal(String(reviewed.ticket?.effective_status || ''), 'approved');

      const revoked = invokeUnary(
        impl.HubRuntime.RevokeChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-revoke-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: created.ticket.ticket_id,
            revoked_by_hub_user_id: 'user_ops_admin',
            revoked_via: 'hub_local_ui',
            note: 'retired route',
          },
        })
      );
      assert.equal(!!revoked.ok, true);
      assert.equal(String(revoked.latest_decision?.decision || ''), 'approve');
      assert.equal(String(revoked.revocation?.status || ''), 'revoked');
      assert.equal(String(revoked.revocation?.revoked_by_hub_user_id || ''), 'user_ops_admin');
      assert.equal(String(revoked.revocation?.note || ''), 'retired route');
      assert.equal(String(revoked.ticket?.effective_status || ''), 'revoked');
      assert.equal(!!revoked.idempotent, false);

      const fetched = invokeUnary(
        impl.HubRuntime.GetChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            ticket_id: created.ticket.ticket_id,
          },
        })
      );
      assert.equal(!!fetched.ok, true);
      assert.equal(String(fetched.ticket?.effective_status || ''), 'revoked');
      assert.equal(
        String(fetched.revocation?.revocation_id || ''),
        String(revoked.revocation?.revocation_id || '')
      );
      assert.equal(String(fetched.revocation?.status || ''), 'revoked');

      const listed = invokeUnary(
        impl.HubRuntime.ListChannelOnboardingDiscoveryTickets,
        makeAdminCall({
          request: {
            provider: 'slack',
          },
        })
      );
      const listedTicket = (listed.tickets || []).find((item) => (
        String(item?.ticket_id || '') === String(created.ticket?.ticket_id || '')
      ));
      assert.equal(String(listedTicket?.effective_status || ''), 'revoked');

      const identityBinding = getChannelIdentityBinding(db, {
        provider: 'slack',
        external_user_id: 'U_REVOKE_GRPC',
        external_tenant_id: 'T_REVOKE_GRPC',
      });
      assert.equal(String(identityBinding?.status || ''), 'revoked');

      const routeBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'slack',
        account_id: 'T_REVOKE_GRPC',
        conversation_id: 'C_REVOKE_GRPC',
        thread_key: '171.11',
        channel_scope: 'group',
      });
      assert.equal(String(routeBinding.binding?.status || ''), 'revoked');

      const autoBindReceipt = getChannelOnboardingAutoBindReceiptByTicketId(db, {
        ticket_id: created.ticket.ticket_id,
      });
      assert.equal(String(autoBindReceipt?.status || ''), 'revoked');

      const revocation = getChannelOnboardingAutoBindRevocationByTicketId(db, {
        ticket_id: created.ticket.ticket_id,
      });
      assert.equal(String(revocation?.status || ''), 'revoked');
      assert.equal(String(revocation?.revoked_by_hub_user_id || ''), 'user_ops_admin');

      const denied = invokeUnary(
        impl.HubRuntime.EvaluateChannelCommandGate,
        makeConnectorCall({
          request: {
            request_id: 'gate-deny-revoked-binding-grpc',
            actor: {
              provider: 'slack',
              external_user_id: 'U_REVOKE_GRPC',
              external_tenant_id: 'T_REVOKE_GRPC',
            },
            channel: {
              provider: 'slack',
              account_id: 'T_REVOKE_GRPC',
              conversation_id: 'C_REVOKE_GRPC',
              thread_key: '171.11',
              channel_scope: 'group',
            },
            action_name: 'supervisor.status.get',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );
      assert.equal(denied.decision?.allowed, false);
      assert.equal(String(denied.decision?.deny_code || ''), 'identity_binding_inactive');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('XT-W3-24/service api revoke fails closed for unapproved onboarding tickets', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      const created = invokeUnary(
        impl.HubRuntime.CreateOrTouchChannelOnboardingDiscoveryTicket,
        makeConnectorCall({
          request: {
            request_id: 'disc-revoke-pending-create-1',
            ticket: {
              provider: 'feishu',
              account_id: 'tenant_pending_grpc',
              external_user_id: 'ou_pending_grpc',
              external_tenant_id: 'tenant_pending_grpc',
              conversation_id: 'oc_pending_grpc',
              thread_key: 'om_pending_grpc',
              ingress_surface: 'group',
              first_message_preview: 'status',
              proposed_scope_type: 'project',
              proposed_scope_id: 'project_alpha',
            },
          },
        })
      );
      assert.equal(!!created.ok, true);

      const revoked = invokeUnary(
        impl.HubRuntime.RevokeChannelOnboardingDiscoveryTicket,
        makeAdminCall({
          request: {
            request_id: 'disc-revoke-pending-1',
            admin: {
              device_id: 'hub-admin-local',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
            ticket_id: created.ticket.ticket_id,
            revoked_by_hub_user_id: 'user_ops_admin',
            revoked_via: 'hub_local_ui',
          },
        })
      );
      assert.equal(!!revoked.ok, false);
      assert.equal(String(revoked.deny_code || ''), 'auto_bind_receipt_missing');
      assert.equal(String(revoked.ticket?.effective_status || ''), 'pending');
      assert.equal(revoked.revocation, null);
      assert.equal(!!revoked.idempotent, false);
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
              access_groups: ['group_allowlist'],
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
      assert.equal(typeof routed.route?.governance_runtime_readiness, 'object');
      assert.equal(Boolean(routed.route?.governance_runtime_readiness?.runtime_ready), true);
      assert.equal(
        String(routed.route?.governance_runtime_readiness?.components_by_xt_key?.route_ready?.state || ''),
        'ready'
      );
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
              access_groups: ['group_allowlist'],
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
      const heartbeatGovernance = db.upsertCanonicalItem({
        scope: 'project',
        device_id: 'xt-alpha-1',
        user_id: 'xt-owner',
        app_id: 'x_terminal',
        project_id: 'project_alpha',
        key: 'xterminal.project.heartbeat.summary_json',
        value: JSON.stringify({
          schema_version: 'xt.project_heartbeat.v1',
          project_id: 'project_alpha',
          project_name: 'Alpha',
          updated_at_ms: now,
          last_heartbeat_at_ms: now,
          status_digest: 'Core loop advancing',
          current_state_summary: 'Project is executing the current release lane.',
          next_step_summary: 'Run the next governed review pulse.',
          blocker_summary: 'waiting_on_review',
          latest_quality_band: 'usable',
          latest_quality_score: 72,
          weak_reasons: ['evidence_thin'],
          open_anomaly_types: ['stale_repeat'],
          project_phase: 'build',
          execution_status: 'active',
          risk_tier: 'medium',
          cadence: {
            progressHeartbeat: {
              dimension: 'progress_heartbeat',
              configuredSeconds: 300,
              recommendedSeconds: 180,
              effectiveSeconds: 180,
              effectiveReasonCodes: ['phase_build'],
              nextDueAtMs: now + 180_000,
              nextDueReasonCodes: ['heartbeat_due_soon'],
              isDue: false,
            },
            reviewPulse: {
              dimension: 'review_pulse',
              configuredSeconds: 900,
              recommendedSeconds: 600,
              effectiveSeconds: 600,
              effectiveReasonCodes: ['quality_usable'],
              nextDueAtMs: now + 600_000,
              nextDueReasonCodes: ['pulse_due_window'],
              isDue: true,
            },
            brainstormReview: {
              dimension: 'brainstorm_review',
              configuredSeconds: 1800,
              recommendedSeconds: 1200,
              effectiveSeconds: 1200,
              effectiveReasonCodes: ['no_progress_window_idle'],
              nextDueAtMs: now + 1_200_000,
              nextDueReasonCodes: ['brainstorm_due_later'],
              isDue: false,
            },
          },
          next_review_kind: 'review_pulse',
          next_review_due_at_ms: now + 600_000,
          next_review_due: true,
          digestExplainability: {
            visibility: 'shown',
            reasonCodes: ['review_candidate_active'],
            whatChangedText: 'Project has advanced into a governed build phase.',
            whyImportantText: 'Supervisor can now see review pressure without re-parsing raw lines.',
            systemNextStepText: 'Queue a pulse review at the next safe point.',
          },
        }),
        pinned: false,
      });
      assert.equal(String(heartbeatGovernance?.key || ''), 'xterminal.project.heartbeat.summary_json');

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
      const heartbeatGovernanceSnapshot = JSON.parse(String(out.query?.heartbeat_governance_snapshot_json || '{}'));
      assert.equal(String(heartbeatGovernanceSnapshot.project_id || ''), 'project_alpha');
      assert.equal(String(heartbeatGovernanceSnapshot.latest_quality_band || ''), 'usable');
      assert.deepEqual(heartbeatGovernanceSnapshot.open_anomaly_types || [], ['stale_repeat']);
      assert.equal(String(heartbeatGovernanceSnapshot.next_review_due?.kind || ''), 'review_pulse');
      assert.equal(heartbeatGovernanceSnapshot.next_review_due?.due, true);
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

run('XT-W3-24/service api ignores display name text when authorizing an approved operator identity', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });

      invokeUnary(
        impl.HubRuntime.UpsertChannelIdentityBinding,
        makeConnectorCall({
          request: {
            request_id: 'identity-upsert-display-auth-1',
            binding: {
              provider: 'slack',
              external_user_id: 'U_REAL_OWNER',
              external_tenant_id: 'T001',
              hub_user_id: 'user_ops_admin',
              roles: ['release_manager'],
              access_groups: ['group_allowlist'],
              approval_only: false,
              display_name: 'Alice Visible',
              status: 'active',
            },
          },
        })
      );

      invokeUnary(
        impl.HubRuntime.UpsertSupervisorOperatorChannelBinding,
        makeConnectorCall({
          request: {
            request_id: 'binding-upsert-display-auth-1',
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C_DISPLAY_AUTH',
              channel_scope: 'group',
              scope_type: 'project',
              scope_id: 'project_alpha',
              allowed_actions: ['deploy.plan'],
              status: 'active',
            },
          },
        })
      );

      const ownerGate = invokeUnary(
        impl.HubRuntime.EvaluateChannelCommandGate,
        makeConnectorCall({
          request: {
            request_id: 'gate-display-auth-owner-1',
            actor: {
              provider: 'slack',
              external_user_id: 'U_REAL_OWNER',
              external_tenant_id: 'T001',
              display_name: 'Alice Visible',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C_DISPLAY_AUTH',
              channel_scope: 'group',
            },
            action_name: 'deploy.plan',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );
      assert.equal(ownerGate.decision?.allowed, true);

      const impostorGate = invokeUnary(
        impl.HubRuntime.EvaluateChannelCommandGate,
        makeConnectorCall({
          request: {
            request_id: 'gate-display-auth-impostor-1',
            actor: {
              provider: 'slack',
              external_user_id: 'U_IMPOSTOR',
              external_tenant_id: 'T001',
              display_name: 'Alice Visible',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'C_DISPLAY_AUTH',
              channel_scope: 'group',
            },
            action_name: 'deploy.plan',
            scope_type: 'project',
            scope_id: 'project_alpha',
          },
        })
      );
      assert.equal(impostorGate.decision?.allowed, false);
      assert.equal(String(impostorGate.decision?.deny_code || ''), 'identity_binding_missing');
      assert.equal(String(impostorGate.decision?.stable_external_id || ''), '');
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
              access_groups: ['group_allowlist', 'approval_only_identity'],
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
      assert.equal(String(out.gate?.risk_tier || ''), 'high');
      assert.equal(String(out.gate?.required_grant_scope || ''), 'project_approval');
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

      const phases = actionAuditPhases(db, 'channel-exec-approve-1');
      assert.deepEqual(phases, [
        'operator_channel.action.requested',
        'operator_channel.action.approved',
        'operator_channel.action.executed',
      ]);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('XT-W3-24/service api rejects grant approval when actual pending grant belongs to another project even if request omits project_id', async () => {
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
            request_id: 'identity-upsert-approve-2',
            binding: {
              provider: 'slack',
              external_user_id: 'UAPPROVE2',
              external_tenant_id: 'T001',
              hub_user_id: 'user_release_manager_2',
              roles: ['approver'],
              access_groups: ['group_allowlist', 'approval_only_identity'],
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
            request_id: 'binding-upsert-approve-2',
            binding: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CA2',
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
        request_id: 'grant-request-2',
        device_id: 'xt-beta-1',
        user_id: 'xt-owner-2',
        app_id: 'x_terminal',
        project_id: 'project_beta',
        capability: 'web.fetch',
        reason: 'Need web access',
        requested_ttl_sec: 1200,
        requested_token_cap: 0,
      });

      const out = await invokeUnaryAsync(
        impl.HubRuntime.ExecuteOperatorChannelHubCommand,
        makeConnectorCall({
          request: {
            request_id: 'channel-exec-approve-2',
            actor: {
              provider: 'slack',
              external_user_id: 'UAPPROVE2',
              external_tenant_id: 'T001',
            },
            channel: {
              provider: 'slack',
              account_id: 'ops-slack',
              conversation_id: 'CA2',
              channel_scope: 'group',
            },
            action_name: 'grant.approve',
            scope_type: 'project',
            scope_id: 'project_alpha',
            pending_grant: {
              grant_request_id: pending.grant_request_id,
              status: 'pending',
            },
            note: 'approve without project id should still fail closed',
          },
        })
      );

      assert.equal(!!out.ok, false);
      assert.equal(String(out.deny_code || ''), 'pending_grant_scope_mismatch');

      const grantRequestRow = db.getGrantRequest(pending.grant_request_id);
      assert.equal(String(grantRequestRow?.status || ''), 'pending');

      const phases = actionAuditPhases(db, 'channel-exec-approve-2');
      assert.deepEqual(phases, [
        'operator_channel.action.requested',
        'operator_channel.action.denied',
      ]);
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
              access_groups: ['group_allowlist'],
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

      const phases = actionAuditPhases(db, 'channel-exec-deploy-plan-1');
      assert.deepEqual(phases, [
        'operator_channel.action.requested',
        'operator_channel.action.queued',
      ]);
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
              access_groups: ['group_allowlist'],
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
        'requested-audit-uuid',
        'gate-audit-uuid',
        'route-id-uuid',
        'route-audit-uuid',
        'static_uuid',
        'queue-audit-uuid',
        'action-queued-audit-uuid',
        'completed-audit-uuid',
        'action-executed-audit-uuid',
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

      const phases = actionAuditPhases(db, 'channel-exec-deploy-plan-2');
      assert.deepEqual(phases, [
        'operator_channel.action.requested',
        'operator_channel.action.queued',
        'operator_channel.action.executed',
      ]);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
