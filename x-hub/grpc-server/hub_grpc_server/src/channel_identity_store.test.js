import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import {
  getChannelIdentityBinding,
  listChannelIdentityBindings,
  upsertChannelIdentityBinding,
} from './channel_identity_store.js';

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
  return path.join(os.tmpdir(), `channel_identity_store_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x41).toString('base64')}`;

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

run('XT-W3-24-H/identity store upserts and looks up by provider stable id, not display text', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const first = upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'lark',
          external_user_id: 'ou_123',
          external_tenant_id: 'tenant_001',
          hub_user_id: 'user_ops_alice',
          roles: ['release_manager', 'approver'],
          access_groups: ['group_allowlist'],
          approval_only: false,
          display_name: 'Alice One',
          status: 'active',
        },
        audit: {
          device_id: 'hub-security-tests',
          app_id: 'channel-identity-tests',
          user_id: 'admin_ops',
        },
        request_id: 'identity-upsert-1',
      });
      assert.equal(!!first.ok, true);
      assert.equal(String(first.binding?.provider || ''), 'feishu');
      assert.equal(String(first.binding?.stable_external_id || ''), 'feishu/tenant_001/ou_123');
      assert.deepEqual(first.binding?.roles, ['release_manager', 'approval_only_identity']);
      assert.deepEqual(first.binding?.access_groups, ['group_allowlist']);

      const second = upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'feishu',
          external_user_id: 'ou_123',
          external_tenant_id: 'tenant_001',
          hub_user_id: 'user_ops_alice',
          roles: ['approver'],
          access_groups: ['group_allowlist', 'approval_only_identity'],
          approval_only: true,
          display_name: 'Alice Two',
          status: 'active',
        },
        audit: {
          device_id: 'hub-security-tests',
          app_id: 'channel-identity-tests',
          user_id: 'admin_ops',
        },
        request_id: 'identity-upsert-2',
      });
      assert.equal(!!second.ok, true);
      assert.equal(!!second.created, false);
      assert.equal(!!second.updated, true);
      assert.equal(!!second.binding?.approval_only, true);

      const fetched = getChannelIdentityBinding(db, {
        provider: 'feishu_bot',
        external_user_id: 'ou_123',
        external_tenant_id: 'tenant_001',
      });
      assert.ok(fetched);
      assert.equal(String(fetched?.hub_user_id || ''), 'user_ops_alice');
      assert.equal(String(fetched?.actor_ref || ''), 'xhub.im_identity_binding.v1:feishu/tenant_001/ou_123');
      assert.deepEqual(fetched?.roles, ['approval_only_identity']);
      assert.deepEqual(fetched?.access_groups, ['group_allowlist', 'approval_only_identity']);

      const rows = listChannelIdentityBindings(db, {
        stable_external_id: 'feishu/tenant_001/ou_123',
      });
      assert.equal(rows.length, 1);

      const audits = db.listAuditEvents({ request_id: 'identity-upsert-2' });
      const row = audits.find((item) => String(item?.event_type || '') === 'channel.identity_binding.upserted');
      assert.ok(row);
      assert.equal(String(row?.app_id || ''), 'channel-identity-tests');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('XT-W3-24-H/identity store rejects active bindings without roles', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const denied = upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'slack',
          external_user_id: 'U123',
          hub_user_id: 'user_ops_bob',
          roles: [],
          status: 'active',
        },
        request_id: 'identity-upsert-denied',
      });
      assert.equal(!!denied.ok, false);
      assert.equal(String(denied.deny_code || ''), 'roles_missing');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
