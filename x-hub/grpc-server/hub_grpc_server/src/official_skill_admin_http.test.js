import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

import { startPairingHTTPServer } from './pairing_http.js';
import { HubDB } from './db.js';
import { normalizeSkillStoreError, setSkillPin } from './skills_store.js';
import {
  resolveOfficialSkillChannelSnapshotDir,
  syncOfficialSkillChannel,
} from './official_skill_channel_sync.js';

const require = createRequire(import.meta.url);
const { buildOfficialAgentSkills } = require('../../../../scripts/build_official_agent_skills.js');

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function writeFile(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents, 'utf8');
}

function fromBase64Url(text) {
  const raw = String(text || '').replace(/-/g, '+').replace(/_/g, '/');
  const padded = raw.padEnd(Math.ceil(raw.length / 4) * 4, '=');
  return Buffer.from(padded, 'base64');
}

function makePublisherTrust(publisherId = 'xhub.official') {
  const pair = crypto.generateKeyPairSync('ed25519');
  const jwk = pair.publicKey.export({ format: 'jwk' });
  const rawPublic = fromBase64Url(String(jwk.x || ''));
  return {
    publisher_id: publisherId,
    public_key_ed25519: `base64:${rawPublic.toString('base64')}`,
    private_pem: pair.privateKey.export({ format: 'pem', type: 'pkcs8' }).toString('utf8'),
  };
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms || 0))));
}

async function withEnvAsync(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function requestJson({
  method = 'GET',
  url,
  headers = {},
  timeout_ms = 2_000,
} = {}) {
  const target = new URL(String(url || ''));
  return new Promise((resolve, reject) => {
    const req = http.request({
      method: String(method || 'GET').toUpperCase(),
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers,
      timeout: Math.max(100, Number(timeout_ms || 0)),
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try {
          json = text ? JSON.parse(text) : null;
        } catch {
          json = null;
        }
        resolve({
          status: Number(res.statusCode || 0),
          text,
          json,
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    req.end();
  });
}

async function waitForHealth(baseUrl, timeoutMs = 2_000) {
  const deadline = Date.now() + Math.max(200, Number(timeoutMs || 0));
  while (Date.now() < deadline) {
    try {
      const out = await requestJson({ url: `${baseUrl}/health`, timeout_ms: 300 });
      if (out.status === 200) return;
    } catch {
      // ignore
    }
    await sleep(25);
  }
  throw new Error('pairing_server_not_ready');
}

async function withPairingServer(tempEnv, db, fn) {
  const port = 56000 + Math.floor(Math.random() * 6000);
  const baseUrl = `http://127.0.0.1:${port}`;
  await withEnvAsync({
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_HOST: '127.0.0.1',
    HUB_PORT: '50051',
    HUB_ADMIN_TOKEN: 'admin-token-official-skill-http',
    HUB_PAIRING_ALLOWED_CIDRS: 'any',
    ...tempEnv,
  }, async () => {
    const stop = startPairingHTTPServer({ db });
    try {
      await waitForHealth(baseUrl, 3_000);
      await fn({ baseUrl });
    } finally {
      try {
        stop?.();
      } catch {
        // ignore
      }
      await sleep(40);
    }
  });
}

function buildOfficialSkillFixture(tempRoot, publisherId = 'xhub.official') {
  const sourceRoot = path.join(tempRoot, 'official-agent-skills');
  const outputRoot = path.join(sourceRoot, 'dist');
  const publisherDir = path.join(sourceRoot, 'publisher');
  const publisher = makePublisherTrust(publisherId);
  const privateKeyPath = path.join(tempRoot, `${publisherId.replace(/[^a-z0-9._-]+/gi, '_')}_ed25519.pem`);

  writeFile(path.join(publisherDir, 'trusted_publishers.json'), JSON.stringify({
    schema_version: 'xhub.trusted_publishers.v1',
    updated_at_ms: 1710000000000,
    publishers: [
      {
        publisher_id: publisher.publisher_id,
        public_key_ed25519: publisher.public_key_ed25519,
        enabled: true,
      },
    ],
  }, null, 2));
  writeFile(privateKeyPath, publisher.private_pem);
  writeFile(path.join(sourceRoot, 'find-skills', 'SKILL.md'), `---
name: find-skills
version: 1.0.0
description: Discover governed skills.
---

# Find Skills
`);
  writeFile(path.join(sourceRoot, 'find-skills', 'skill.json'), JSON.stringify({
    schema_version: 'xhub.skill_manifest.v1',
    skill_id: 'find-skills',
    name: 'Find Skills',
    version: '1.0.0',
    description: 'Discover governed skills.',
    side_effect_class: 'read_only',
    risk_level: 'low',
    requires_grant: false,
    entrypoint: {
      runtime: 'text',
      command: 'cat',
      args: ['SKILL.md'],
    },
    capabilities_required: ['skills.search'],
    network_policy: {
      direct_network_forbidden: true,
    },
    publisher: {
      publisher_id: publisherId,
    },
    install_hint: 'Install via baseline.',
  }, null, 2));

  const index = buildOfficialAgentSkills({
    sourceRoot,
    outputRoot,
    generatedAtMs: 1710000000000,
    publisherTrustFile: path.join(publisherDir, 'trusted_publishers.json'),
    signingPrivateKeyFile: privateKeyPath,
    publisherIdOverride: publisherId,
  });
  return {
    sourceRoot,
    outputRoot,
    skill: index.skills[0],
  };
}

await runAsync('official skill admin doctor endpoint returns governed doctor report', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'official-skill-admin-http-'));
  const dbPath = path.join(tempRoot, 'hub.db');
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const db = new HubDB({ dbPath });

  try {
    const built = buildOfficialSkillFixture(tempRoot);
    syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    setSkillPin(runtimeBaseDir, {
      scope: 'project',
      userId: 'user-1',
      projectId: 'project-1',
      skillId: 'find-skills',
      packageSha256: built.skill.package_sha256,
      note: 'admin doctor endpoint',
    });

    await withPairingServer({
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      XHUB_OFFICIAL_AGENT_SKILLS_DIR: built.sourceRoot,
      XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: built.outputRoot,
    }, db, async ({ baseUrl }) => {
      const target = new URL(`${baseUrl}/admin/official-skills/doctor`);
      target.searchParams.set('package_sha256', built.skill.package_sha256);
      target.searchParams.set('user_id', 'user-1');
      target.searchParams.set('project_id', 'project-1');
      target.searchParams.set('surface', 'hub_ui');
      target.searchParams.set('xt_version', 'xt-1.0.0');

      const out = await requestJson({
        url: target.toString(),
        headers: {
          authorization: 'Bearer admin-token-official-skill-http',
        },
      });
      assert.equal(out.status, 200);
      assert.equal(out.json?.ok, true);
      assert.equal(String(out.json?.report?.kind || ''), 'official_skill');
      assert.equal(String(out.json?.report?.doctor_bundle || ''), 'official_skills');
      assert.equal(String(out.json?.report?.surface || ''), 'hub_ui');
      assert.equal(String(out.json?.report?.package_state || ''), 'active');
      assert.equal(String(out.json?.report?.overall_state || ''), 'ready');
      assert.equal(String(out.json?.report?.runtime_snapshot?.xt_version || ''), 'xt-1.0.0');
    });
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

await runAsync('official skill pin request is blocked when official doctor is not ready', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'official-skill-pin-blocked-http-'));
  const dbPath = path.join(tempRoot, 'hub.db');
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const db = new HubDB({ dbPath });

  try {
    const built = buildOfficialSkillFixture(tempRoot);
    syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    fs.writeFileSync(
      path.join(runtimeBaseDir, 'skills_store', 'trusted_publishers.json'),
      `${JSON.stringify({
        schema_version: 'xhub.trusted_publishers.v1',
        updated_at_ms: Date.now(),
        publishers: [
          {
            publisher_id: 'xhub.official',
            public_key_ed25519: 'base64:disabled',
            enabled: false,
          },
        ],
      }, null, 2)}\n`,
      'utf8'
    );

    let denied = false;
    try {
      setSkillPin(runtimeBaseDir, {
        scope: 'project',
        userId: 'user-1',
        projectId: 'project-1',
        skillId: 'find-skills',
        packageSha256: built.skill.package_sha256,
        note: 'admin blocked doctor gate',
      });
    } catch (error) {
      denied = true;
      const normalized = normalizeSkillStoreError(error, 'skill_pin_failed');
      assert.equal(String(normalized.code || ''), 'official_skill_review_blocked');
      assert.equal(String(normalized.detail?.skill_id || ''), 'find-skills');
      assert.equal(String(normalized.detail?.overall_state || ''), 'blocked');
      assert.equal(String(normalized.detail?.doctor_bundle || ''), 'official_skills');
    }
    assert.equal(denied, true);
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

await runAsync('official skill admin packages endpoint returns persisted lifecycle snapshot fields and refresh semantics', async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'official-skill-admin-http-packages-'));
  const dbPath = path.join(tempRoot, 'hub.db');
  const runtimeBaseDir = path.join(tempRoot, 'runtime');
  const db = new HubDB({ dbPath });

  try {
    const built = buildOfficialSkillFixture(tempRoot);
    syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    setSkillPin(runtimeBaseDir, {
      scope: 'project',
      userId: 'user-1',
      projectId: 'project-1',
      skillId: 'find-skills',
      packageSha256: built.skill.package_sha256,
      note: 'admin package list endpoint',
    });
    await withPairingServer({
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      XHUB_OFFICIAL_AGENT_SKILLS_DIR: built.sourceRoot,
      XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: built.outputRoot,
    }, db, async ({ baseUrl }) => {
      const readyTarget = new URL(`${baseUrl}/admin/official-skills/packages`);
      readyTarget.searchParams.set('skill_id', 'find-skills');
      readyTarget.searchParams.set('surface', 'api');

      const readyOut = await requestJson({
        url: readyTarget.toString(),
        headers: {
          authorization: 'Bearer admin-token-official-skill-http',
        },
      });
      assert.equal(readyOut.status, 200);
      assert.equal(readyOut.json?.ok, true);
      assert.equal(String(readyOut.json?.schema_version || ''), 'xhub.official_skill_package_lifecycle_snapshot.v1');
      assert.equal(Number(readyOut.json?.updated_at_ms || 0) > 0, true);
      assert.equal(Number(readyOut.json?.totals?.packages_total || 0), 1);
      assert.equal(Number(readyOut.json?.totals?.ready_total || 0), 1);
      assert.equal(Number(readyOut.json?.totals?.blocked_total || 0), 0);
      assert.equal(Number(readyOut.json?.totals?.not_supported_total || 0), 0);
      assert.equal(Array.isArray(readyOut.json?.packages), true);
      assert.equal(readyOut.json.packages.length, 1);
      assert.equal(String(readyOut.json.packages[0]?.skill_id || ''), 'find-skills');
      assert.equal(String(readyOut.json.packages[0]?.overall_state || ''), 'ready');
      assert.equal(String(readyOut.json.packages[0]?.package_state || ''), 'discovered');

      const firstUpdatedAtMs = Number(readyOut.json?.updated_at_ms || 0);
      const snapshotDir = resolveOfficialSkillChannelSnapshotDir(runtimeBaseDir, {});
      fs.rmSync(path.join(snapshotDir, built.skill.package_path), { force: true });

      const staleTarget = new URL(`${baseUrl}/admin/official-skills/packages`);
      staleTarget.searchParams.set('skill_id', 'find-skills');
      staleTarget.searchParams.set('refresh', '0');

      const staleOut = await requestJson({
        url: staleTarget.toString(),
        headers: {
          authorization: 'Bearer admin-token-official-skill-http',
        },
      });
      assert.equal(staleOut.status, 200);
      assert.equal(staleOut.json?.ok, true);
      assert.equal(Number(staleOut.json?.updated_at_ms || 0), firstUpdatedAtMs);
      assert.equal(Number(staleOut.json?.totals?.ready_total || 0), 1);
      assert.equal(Number(staleOut.json?.totals?.blocked_total || 0), 0);
      assert.equal(staleOut.json.packages.length, 1);
      assert.equal(String(staleOut.json.packages[0]?.overall_state || ''), 'ready');

      const blockedTarget = new URL(`${baseUrl}/admin/official-skills/packages`);
      blockedTarget.searchParams.set('skill_id', 'find-skills');
      blockedTarget.searchParams.set('overall_state', 'blocked');
      blockedTarget.searchParams.set('surface', 'api');
      blockedTarget.searchParams.set('refresh', '1');

      const blockedOut = await requestJson({
        url: blockedTarget.toString(),
        headers: {
          authorization: 'Bearer admin-token-official-skill-http',
        },
      });
      assert.equal(blockedOut.status, 200);
      assert.equal(blockedOut.json?.ok, true);
      assert.equal(String(blockedOut.json?.schema_version || ''), 'xhub.official_skill_package_lifecycle_snapshot.v1');
      assert.equal(Number(blockedOut.json?.updated_at_ms || 0) >= firstUpdatedAtMs, true);
      assert.equal(Number(blockedOut.json?.totals?.packages_total || 0), 1);
      assert.equal(Number(blockedOut.json?.totals?.ready_total || 0), 0);
      assert.equal(Number(blockedOut.json?.totals?.blocked_total || 0), 1);
      assert.equal(Array.isArray(blockedOut.json?.packages), true);
      assert.equal(blockedOut.json.packages.length, 1);
      assert.equal(String(blockedOut.json.packages[0]?.skill_id || ''), 'find-skills');
      assert.equal(String(blockedOut.json.packages[0]?.overall_state || ''), 'blocked');
      assert.equal(String(blockedOut.json.packages[0]?.package_state || ''), 'discovered');
      assert.equal(Number(blockedOut.json.packages[0]?.blocking_failures || 0) >= 1, true);
      assert.equal(Number(blockedOut.json.packages[0]?.transition_count || 0) >= 2, true);
    });
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
