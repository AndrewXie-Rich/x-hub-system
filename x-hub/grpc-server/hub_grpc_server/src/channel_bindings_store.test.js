import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import {
  resolveSupervisorOperatorChannelBinding,
  upsertSupervisorOperatorChannelBinding,
} from './channel_bindings_store.js';

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
  return path.join(os.tmpdir(), `channel_bindings_store_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x42).toString('base64')}`;

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

run('XT-W3-24-H/channel bindings resolve exact thread first and then conversation fallback', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const group = upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'C123',
          channel_scope: 'group',
          scope_type: 'project',
          scope_id: 'payments-prod',
          allowed_actions: ['supervisor.status.get', 'grant.approve'],
          status: 'active',
        },
        request_id: 'binding-upsert-group',
      });
      assert.equal(!!group.ok, true);
      const thread = upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'C123',
          thread_key: '1741770000.12345',
          channel_scope: 'group',
          scope_type: 'project',
          scope_id: 'payments-prod',
          allowed_actions: ['deploy.plan'],
          status: 'active',
        },
        request_id: 'binding-upsert-thread',
      });
      assert.equal(!!thread.ok, true);

      const exact = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'slack',
        account_id: 'ops_bot',
        conversation_id: 'C123',
        thread_key: '1741770000.12345',
        channel_scope: 'group',
      });
      assert.equal(String(exact.binding_match_mode || ''), 'exact_thread');
      assert.deepEqual(exact.binding?.allowed_actions, ['deploy.plan']);

      const fallback = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'slack',
        account_id: 'ops_bot',
        conversation_id: 'C123',
        thread_key: '1741770000.99999',
        channel_scope: 'group',
      });
      assert.equal(String(fallback.binding_match_mode || ''), 'conversation_fallback');
      assert.deepEqual(fallback.binding?.allowed_actions, ['supervisor.status.get', 'grant.approve']);

      const audit = db.listAuditEvents({ request_id: 'binding-upsert-thread' })
        .find((item) => String(item?.event_type || '') === 'channel.binding.upserted');
      assert.ok(audit);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('XT-W3-24-H/channel bindings keep dm and group policies separate', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const dm = upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'telegram',
          account_id: 'ops_bot',
          conversation_id: 'dm-42',
          channel_scope: 'dm',
          scope_type: 'project',
          scope_id: 'proj-dm',
          allowed_actions: ['supervisor.status.get'],
          status: 'active',
        },
      });
      assert.equal(!!dm.ok, true);

      const groupResolution = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'telegram',
        account_id: 'ops_bot',
        conversation_id: 'dm-42',
        channel_scope: 'group',
      });
      assert.equal(groupResolution.binding, null);
      assert.equal(String(groupResolution.binding_match_mode || ''), 'none');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
