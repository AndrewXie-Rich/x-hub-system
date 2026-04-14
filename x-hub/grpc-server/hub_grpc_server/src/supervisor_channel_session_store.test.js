import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import {
  resolveSupervisorChannelSessionRoute,
  upsertSupervisorChannelSessionRoute,
} from './supervisor_channel_session_store.js';

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
  return path.join(os.tmpdir(), `supervisor_channel_session_store_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x44).toString('base64')}`;

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

run('XT-W3-24-I/session store upserts and resolves a route by exact provider/account/conversation/thread', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const upserted = upsertSupervisorChannelSessionRoute(db, {
        route: {
          provider: 'feishu',
          account_id: 'default',
          conversation_id: 'oc_payments_room',
          thread_key: 'thread-1',
          scope_type: 'project',
          scope_id: 'payments-prod',
          preferred_device_id: 'xt-mac-mini-bj-01',
          resolved_device_id: 'xt-mac-mini-bj-01',
          route_mode: 'hub_to_xt',
          xt_online: true,
          same_project_scope: true,
          governance_runtime_readiness: {
            schema_version: 'xhub.governance_runtime_readiness.v1',
            runtime_ready: false,
            blocked_component_keys: ['grant_ready'],
            missing_reason_codes: ['permission_owner_not_ready'],
            components_by_xt_key: {
              grant_ready: {
                state: 'blocked',
                deny_code: 'device_permission_owner_missing',
              },
            },
          },
        },
        request_id: 'session-route-upsert-1',
      });
      assert.equal(!!upserted.ok, true);
      assert.equal(String(upserted.route?.route_mode || ''), 'hub_to_xt');
      assert.equal(String(upserted.route?.supervisor_session_id || ''), String(upserted.route?.route_id || ''));
      assert.equal(typeof upserted.route?.governance_runtime_readiness, 'object');
      assert.equal(Boolean(upserted.route?.governance_runtime_readiness?.runtime_ready), false);

      const resolved = resolveSupervisorChannelSessionRoute(db, {
        provider: 'lark',
        account_id: 'default',
        conversation_id: 'oc_payments_room',
        thread_key: 'thread-1',
      });
      assert.ok(resolved);
      assert.equal(String(resolved?.scope_id || ''), 'payments-prod');
      assert.equal(String(resolved?.resolved_device_id || ''), 'xt-mac-mini-bj-01');

      const audit = db.listAuditEvents({ request_id: 'session-route-upsert-1' })
        .find((item) => String(item?.event_type || '') === 'channel.session_route.upserted');
      assert.ok(audit);
      const ext = JSON.parse(String(audit?.ext_json || '{}'));
      assert.equal(typeof ext?.governance_runtime_readiness, 'object');
      assert.equal(Boolean(ext?.governance_runtime_readiness?.runtime_ready), false);
      assert.deepEqual(ext?.governance_runtime_readiness?.blocked_component_keys, ['grant_ready']);
      assert.equal(
        String(ext?.governance_runtime_readiness?.components_by_xt_key?.grant_ready?.deny_code || ''),
        'device_permission_owner_missing'
      );
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('XT-W3-24-I/session store rejects scope switching on the same IM session', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const first = upsertSupervisorChannelSessionRoute(db, {
        route: {
          provider: 'telegram',
          account_id: 'ops_bot',
          conversation_id: '-1001',
          thread_key: 'topic:42',
          scope_type: 'project',
          scope_id: 'payments-prod',
          route_mode: 'hub_only_status',
        },
      });
      assert.equal(!!first.ok, true);

      const denied = upsertSupervisorChannelSessionRoute(db, {
        route: {
          provider: 'telegram',
          account_id: 'ops_bot',
          conversation_id: '-1001',
          thread_key: 'topic:42',
          scope_type: 'device',
          scope_id: 'xt-mac-mini-bj-01',
          route_mode: 'hub_to_runner',
        },
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
