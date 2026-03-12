import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { parseEncryptedEnvelopeMeta } from './at_rest_crypto.js';
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
  return path.join(os.tmpdir(), `hub_memory_secret_vault_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x61).toString('base64')}`;

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

function makeClient(projectId = 'project-secret-1') {
  return {
    device_id: 'dev-secret-1',
    user_id: 'user-secret-1',
    app_id: 'x_terminal',
    project_id: projectId,
    session_id: 'sess-secret-1',
  };
}

run('secret vault create/list/begin_use encrypts at rest and exports metadata-only snapshot', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('vault', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const bus = new HubEventBus();
    const impl = makeServices({ db, bus });
    try {
      const client = makeClient('proj-minecraft');
      const plaintext = 'CorrectHorseBatteryStaple!';

      const created = invokeHubMemoryUnary(impl, 'CreateSecretVaultItem', {
        client,
        scope: 'project',
        name: 'minecraft-login',
        plaintext_bytes: Buffer.from(plaintext, 'utf8'),
        sensitivity: 'credential',
        display_name: 'Minecraft Login',
        reason: 'website_sign_in',
      });
      assert.equal(created.err, null);
      assert.ok(created.res?.item);
      assert.equal(String(created.res.item.scope || ''), 'project');
      assert.equal(String(created.res.item.name || ''), 'minecraft-login');

      const rawItem = db.db.prepare(`SELECT * FROM secret_vault_items LIMIT 1`).get();
      assert.ok(rawItem);
      assert.notEqual(String(rawItem.ciphertext_text || ''), plaintext);
      assert.ok(parseEncryptedEnvelopeMeta(String(rawItem.ciphertext_text || '')));

      const listed = invokeHubMemoryUnary(impl, 'ListSecretVaultItems', {
        client,
        scope: 'project',
        limit: 10,
      });
      assert.equal(listed.err, null);
      assert.equal(Array.isArray(listed.res?.items), true);
      assert.equal(listed.res.items.length, 1);
      assert.equal(String(listed.res.items[0].item_id || ''), String(created.res.item.item_id || ''));

      const lease = invokeHubMemoryUnary(impl, 'BeginSecretVaultUse', {
        client,
        item_id: created.res.item.item_id,
        purpose: 'browser_login',
        target: 'https://example.com/login',
        ttl_ms: 45_000,
      });
      assert.equal(lease.err, null);
      assert.ok(String(lease.res?.lease_id || '').startsWith('svl_'));
      assert.ok(String(lease.res?.use_token || '').startsWith('svtok_'));
      assert.equal(String(lease.res?.item_id || ''), String(created.res.item.item_id || ''));

      const rawLease = db.db.prepare(`SELECT * FROM secret_vault_use_leases LIMIT 1`).get();
      assert.ok(rawLease);
      assert.notEqual(String(rawLease.use_token_hash || ''), String(lease.res?.use_token || ''));

      const snapshotPath = path.join(runtimeBaseDir, 'secret_vault_items_status.json');
      assert.equal(fs.existsSync(snapshotPath), true);
      const snapshotRaw = fs.readFileSync(snapshotPath, 'utf8');
      assert.ok(snapshotRaw.includes('minecraft-login'));
      assert.equal(snapshotRaw.includes(plaintext), false);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run('secret vault project scope is fail-closed across projects', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('vault', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const bus = new HubEventBus();
    const impl = makeServices({ db, bus });
    try {
      const owner = makeClient('proj-owner');
      const otherProject = makeClient('proj-other');

      const created = invokeHubMemoryUnary(impl, 'CreateSecretVaultItem', {
        client: owner,
        scope: 'project',
        name: 'deploy-secret',
        plaintext_bytes: Buffer.from('shh', 'utf8'),
        sensitivity: 'secret',
      });
      assert.equal(created.err, null);

      const listed = invokeHubMemoryUnary(impl, 'ListSecretVaultItems', {
        client: otherProject,
        scope: 'project',
        limit: 10,
      });
      assert.equal(listed.err, null);
      assert.equal(Array.isArray(listed.res?.items), true);
      assert.equal(listed.res.items.length, 0);

      const deniedLease = invokeHubMemoryUnary(impl, 'BeginSecretVaultUse', {
        client: otherProject,
        item_id: created.res?.item?.item_id || '',
        purpose: 'deploy',
      });
      assert.ok(deniedLease.err);
      assert.match(String(deniedLease.err.message || deniedLease.err), /secret_vault_item_not_found/);
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run('secret vault redeem decrypts plaintext and consumes lease', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('vault', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const client = makeClient('proj-minecraft');
      const created = db.createOrUpdateSecretVaultItem({
        scope: 'project',
        name: 'minecraft-login',
        plaintext: 'CorrectHorseBatteryStaple!',
        sensitivity: 'credential',
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.equal(created.ok, true);
      assert.ok(created.item?.item_id);

      const lease = db.beginSecretVaultUse({
        item_id: created.item.item_id,
        purpose: 'browser_login',
        target: 'https://example.com/login',
        ttl_ms: 45_000,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.equal(lease.ok, true);
      assert.ok(String(lease.lease?.use_token || '').startsWith('svtok_'));

      const redeemed = db.redeemSecretVaultUse({
        use_token: lease.lease.use_token,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.equal(redeemed.ok, true);
      assert.equal(String(redeemed.plaintext || ''), 'CorrectHorseBatteryStaple!');
      assert.equal(String(redeemed.item?.item_id || ''), String(created.item.item_id || ''));
      assert.equal(String(redeemed.lease?.status || ''), 'used');

      const replay = db.redeemSecretVaultUse({
        use_token: lease.lease.use_token,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.equal(replay.ok, false);
      assert.equal(String(replay.deny_code || ''), 'secret_vault_use_token_used');
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});
