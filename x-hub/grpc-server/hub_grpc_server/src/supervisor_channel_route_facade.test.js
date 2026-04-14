import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { upsertSupervisorOperatorChannelBinding } from './channel_bindings_store.js';
import {
  evaluateSupervisorChannelRouteWithStore,
  resolveSupervisorChannelRoute,
} from './supervisor_channel_route_facade.js';

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
  return path.join(os.tmpdir(), `supervisor_channel_route_facade_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x45).toString('base64')}`;

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

function makeClient({
  device_id,
  connected = true,
  trusted_automation_mode = 'standard',
  trusted_automation_state = 'off',
  allowed_project_ids = [],
  xt_binding_required = false,
  device_permission_owner_ref = '',
}) {
  return {
    device_id,
    enabled: true,
    trusted_automation_mode,
    trusted_automation_state,
    allowed_project_ids,
    xt_binding_required,
    device_permission_owner_ref,
    approved_trust_profile: {
      schema_version: 'hub.paired_terminal_trust_profile.v1',
    },
    trust_profile_present: true,
    __connected: connected,
  };
}

function makeDevicesStatus(devices) {
  return {
    schema_version: 'grpc_devices_status.v2',
    updated_at_ms: Date.now(),
    devices: devices.map((device) => ({
      device_id: device.device_id,
      connected: !!device.__connected,
      last_seen_at_ms: 1000,
      connected_at_ms: device.__connected ? 900 : 0,
    })),
  };
}

run('XT-W3-24-I/route facade keeps status query project-first and hub-only', () => {
  const binding = {
    provider: 'feishu',
    account_id: 'default',
    conversation_id: 'oc_payments_room',
    thread_key: '',
    scope_type: 'project',
    scope_id: 'payments-prod',
    preferred_device_id: 'xt-mac-mini-bj-01',
  };
  const clients = [
    makeClient({
      device_id: 'xt-mac-mini-bj-01',
      connected: false,
      allowed_project_ids: ['payments-prod'],
    }),
  ];
  const route = resolveSupervisorChannelRoute({
    binding,
    action_name: 'supervisor.status.get',
    clients_snapshot: clients,
    devices_status_snapshot: makeDevicesStatus(clients),
  });

  assert.equal(String(route.route_mode || ''), 'hub_only_status');
  assert.equal(!!route.xt_online, false);
  assert.equal(String(route.deny_code || ''), '');
});

run('XT-W3-24-I/route facade resolves preferred project device to hub_to_xt when online and same-project', () => {
  const binding = {
    provider: 'slack',
    account_id: 'ops_bot',
    conversation_id: 'C123',
    thread_key: '1741770000.12345',
    scope_type: 'project',
    scope_id: 'payments-prod',
    preferred_device_id: 'xt-mac-mini-bj-01',
  };
  const clients = [
    makeClient({
      device_id: 'xt-mac-mini-bj-01',
      connected: true,
      allowed_project_ids: ['payments-prod'],
    }),
  ];
  const route = resolveSupervisorChannelRoute({
    binding,
    action_name: 'deploy.plan',
    clients_snapshot: clients,
    devices_status_snapshot: makeDevicesStatus(clients),
  });

  assert.equal(String(route.route_mode || ''), 'hub_to_xt');
  assert.equal(String(route.resolved_device_id || ''), 'xt-mac-mini-bj-01');
  assert.equal(!!route.xt_online, true);
  assert.equal(!!route.same_project_scope, true);
});

run('XT-W3-24-I/route facade returns xt_offline when preferred device is offline for XT-bound action', () => {
  const binding = {
    provider: 'slack',
    account_id: 'ops_bot',
    conversation_id: 'C123',
    thread_key: '',
    scope_type: 'project',
    scope_id: 'payments-prod',
    preferred_device_id: 'xt-mac-mini-bj-01',
  };
  const clients = [
    makeClient({
      device_id: 'xt-mac-mini-bj-01',
      connected: false,
      allowed_project_ids: ['payments-prod'],
    }),
  ];
  const route = resolveSupervisorChannelRoute({
    binding,
    action_name: 'deploy.execute',
    clients_snapshot: clients,
    devices_status_snapshot: makeDevicesStatus(clients),
  });

  assert.equal(String(route.route_mode || ''), 'xt_offline');
  assert.equal(String(route.deny_code || ''), 'preferred_device_offline');
  assert.equal(Boolean(route?.governance_runtime_readiness?.runtime_ready), false);
  assert.equal(
    String(route?.governance_runtime_readiness?.components_by_xt_key?.route_ready?.deny_code || ''),
    'preferred_device_offline'
  );
});

run('XT-W3-24-I/route facade keeps device diagnostics off the project main thread until scope switches explicitly', () => {
  const binding = {
    provider: 'slack',
    account_id: 'ops_bot',
    conversation_id: 'C123',
    thread_key: '1741770000.12345',
    scope_type: 'project',
    scope_id: 'payments-prod',
    preferred_device_id: 'xt-mac-mini-bj-01',
  };
  const clients = [
    makeClient({
      device_id: 'xt-mac-mini-bj-01',
      connected: true,
      trusted_automation_mode: 'trusted_automation',
      trusted_automation_state: 'armed',
      xt_binding_required: true,
      device_permission_owner_ref: 'owner-1',
      allowed_project_ids: ['payments-prod'],
    }),
  ];
  const route = resolveSupervisorChannelRoute({
    binding,
    action_name: 'device.doctor.get',
    clients_snapshot: clients,
    devices_status_snapshot: makeDevicesStatus(clients),
  });

  assert.equal(String(route.route_mode || ''), 'hub_only_status');
  assert.equal(String(route.deny_code || ''), 'scope_switch_required');
  assert.equal(String(route.resolved_device_id || ''), '');
});

run('XT-W3-24-I/route facade returns runner_not_ready when device diagnostics target lacks ready trusted runner', () => {
  const binding = {
    provider: 'telegram',
    account_id: 'ops_bot',
    conversation_id: '-1001',
    thread_key: 'topic:42',
    scope_type: 'device',
    scope_id: 'xt-mac-mini-bj-01',
    preferred_device_id: '',
  };
  const clients = [
    makeClient({
      device_id: 'xt-mac-mini-bj-01',
      connected: true,
      trusted_automation_mode: 'trusted_automation',
      trusted_automation_state: 'armed',
      xt_binding_required: true,
      device_permission_owner_ref: '',
      allowed_project_ids: [],
    }),
  ];
  const route = resolveSupervisorChannelRoute({
    binding,
    action_name: 'device.doctor.get',
    clients_snapshot: clients,
    devices_status_snapshot: makeDevicesStatus(clients),
  });

  assert.equal(String(route.route_mode || ''), 'runner_not_ready');
  assert.equal(String(route.deny_code || ''), 'device_permission_owner_missing');
  assert.equal(!!route.runner_required, true);
  assert.equal(!!route.xt_online, true);
  assert.equal(Boolean(route?.governance_runtime_readiness?.runtime_ready), false);
  assert.equal(
    String(route?.governance_runtime_readiness?.components_by_xt_key?.grant_ready?.deny_code || ''),
    'device_permission_owner_missing'
  );
  assert.ok(
    Array.isArray(route?.governance_runtime_readiness?.missing_reason_codes)
      && route.governance_runtime_readiness.missing_reason_codes.includes('permission_owner_not_ready')
  );
});

run('XT-W3-24-I/route facade routes explicit device diagnostics scope to runner and keeps incident scope hub-only', () => {
  const deviceBinding = {
    provider: 'telegram',
    account_id: 'ops_bot',
    conversation_id: '-1001',
    thread_key: 'topic:99',
    scope_type: 'device',
    scope_id: 'xt-mac-mini-bj-01',
    preferred_device_id: '',
  };
  const clients = [
    makeClient({
      device_id: 'xt-mac-mini-bj-01',
      connected: true,
      trusted_automation_mode: 'trusted_automation',
      trusted_automation_state: 'armed',
      xt_binding_required: true,
      device_permission_owner_ref: 'owner-1',
      allowed_project_ids: ['payments-prod'],
    }),
  ];
  const deviceRoute = resolveSupervisorChannelRoute({
    binding: deviceBinding,
    action_name: 'device.doctor.get',
    clients_snapshot: clients,
    devices_status_snapshot: makeDevicesStatus(clients),
  });

  assert.equal(String(deviceRoute.route_mode || ''), 'hub_to_runner');
  assert.equal(String(deviceRoute.resolved_device_id || ''), 'xt-mac-mini-bj-01');
  assert.equal(!!deviceRoute.runner_required, true);
  assert.equal(!!deviceRoute.xt_online, true);
  assert.equal(Boolean(deviceRoute?.governance_runtime_readiness?.runtime_ready), true);
  assert.equal(
    String(deviceRoute?.governance_runtime_readiness?.components_by_xt_key?.grant_ready?.state || ''),
    'ready'
  );

  const incidentRoute = resolveSupervisorChannelRoute({
    binding: {
      provider: 'feishu',
      account_id: 'default',
      conversation_id: 'incident-room',
      thread_key: '',
      scope_type: 'incident',
      scope_id: 'incident-payments-p1',
      preferred_device_id: 'xt-mac-mini-bj-01',
    },
    action_name: 'supervisor.status.get',
    clients_snapshot: clients,
    devices_status_snapshot: makeDevicesStatus(clients),
  });

  assert.equal(String(incidentRoute.route_mode || ''), 'hub_only_status');
  assert.equal(String(incidentRoute.deny_code || ''), '');
});

run('XT-W3-24-I/route facade persists resolved route and keeps project/device scopes isolated', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const binding = upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'feishu',
          account_id: 'default',
          conversation_id: 'oc_payments_room',
          thread_key: 'thread-1',
          channel_scope: 'group',
          scope_type: 'project',
          scope_id: 'payments-prod',
          preferred_device_id: 'xt-mac-mini-bj-01',
          allowed_actions: ['deploy.plan', 'device.doctor.get'],
          status: 'active',
        },
      }).binding;

      const clients = [
        makeClient({
          device_id: 'xt-mac-mini-bj-01',
          connected: true,
          allowed_project_ids: ['payments-prod'],
        }),
      ];
      const stored = evaluateSupervisorChannelRouteWithStore({
        db,
        binding,
        action_name: 'deploy.plan',
        clients_snapshot: clients,
        devices_status_snapshot: makeDevicesStatus(clients),
        request_id: 'route-store-1',
      });
      assert.equal(!!stored.ok, true);
      assert.equal(String(stored.route?.route_mode || ''), 'hub_to_xt');
      assert.equal(typeof stored.route?.governance_runtime_readiness, 'object');
      assert.equal(Boolean(stored.route?.governance_runtime_readiness?.runtime_ready), true);
      const storedAudit = db.listAuditEvents({ request_id: 'route-store-1' })
        .find((item) => String(item?.event_type || '') === 'channel.session_route.upserted');
      assert.ok(storedAudit);
      const storedExt = JSON.parse(String(storedAudit?.ext_json || '{}'));
      assert.equal(typeof storedExt?.governance_runtime_readiness, 'object');
      assert.equal(Boolean(storedExt?.governance_runtime_readiness?.runtime_ready), true);
      assert.equal(
        String(storedExt?.governance_runtime_readiness?.components_by_xt_key?.route_ready?.state || ''),
        'ready'
      );

      const denied = evaluateSupervisorChannelRouteWithStore({
        db,
        binding: {
          ...binding,
          scope_type: 'device',
          scope_id: 'xt-mac-mini-bj-01',
        },
        action_name: 'device.doctor.get',
        clients_snapshot: clients,
        devices_status_snapshot: makeDevicesStatus(clients),
        request_id: 'route-store-2',
      });
      assert.equal(!!denied.ok, false);
      assert.equal(String(denied.deny_code || ''), 'session_scope_conflict');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
