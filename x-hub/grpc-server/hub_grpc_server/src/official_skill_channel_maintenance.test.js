import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

import {
  readOfficialSkillChannelMaintenanceEvents,
  readOfficialSkillChannelMaintenanceStatus,
  startOfficialSkillChannelMaintenance,
} from './official_skill_channel_maintenance.js';
import { readOfficialSkillChannelState } from './official_skill_channel_sync.js';

const require = createRequire(import.meta.url);
const { buildOfficialAgentSkills } = require('../../../../scripts/build_official_agent_skills.js');

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function tmpDir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `xhub_official_maintenance_${label}_`));
}

function cleanupDir(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch {
    // ignore
  }
}

function writeFile(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents, 'utf8');
}

function writeJson(filePath, value) {
  writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function sleepMs(ms) {
  const waitMs = Math.max(0, Math.floor(Number(ms || 0)));
  return new Promise((resolve) => setTimeout(resolve, waitMs));
}

function fromBase64Url(text) {
  const raw = String(text || '').replace(/-/g, '+').replace(/_/g, '/');
  const padded = raw.padEnd(Math.ceil(raw.length / 4) * 4, '=');
  return Buffer.from(padded, 'base64');
}

function makePublisherTrust(publisherId) {
  const pair = crypto.generateKeyPairSync('ed25519');
  const jwk = pair.publicKey.export({ format: 'jwk' });
  const rawPublic = fromBase64Url(String(jwk.x || ''));
  return {
    publisher_id: publisherId,
    public_key_ed25519: `base64:${rawPublic.toString('base64')}`,
    private_pem: pair.privateKey.export({ format: 'pem', type: 'pkcs8' }).toString('utf8'),
  };
}

async function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const [key, value] of Object.entries(tempEnv || {})) {
    previous.set(key, process.env[key]);
    if (value == null) delete process.env[key];
    else process.env[key] = String(value);
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

function createOfficialPublicSource(tempRoot, {
  skillId,
  name,
  description,
  version = '1.0.0',
  capabilitiesRequired = [],
  riskLevel = 'low',
  requiresGrant = false,
  sideEffectClass = 'read_only',
  publisherId = 'xhub.official',
} = {}) {
  const sourceRoot = path.join(tempRoot, 'official-agent-skills');
  const outputRoot = path.join(sourceRoot, 'dist');
  const publisherDir = path.join(sourceRoot, 'publisher');
  const publisher = makePublisherTrust(publisherId);
  const privateKeyPath = path.join(tempRoot, `${publisherId.replace(/[^a-z0-9._-]+/gi, '_')}_ed25519.pem`);

  writeJson(path.join(publisherDir, 'trusted_publishers.json'), {
    schema_version: 'xhub.trusted_publishers.v1',
    updated_at_ms: 1710000000000,
    publishers: [
      {
        publisher_id: publisher.publisher_id,
        public_key_ed25519: publisher.public_key_ed25519,
        enabled: true,
      },
    ],
  });
  writeFile(privateKeyPath, publisher.private_pem);
  writeFile(path.join(sourceRoot, skillId, 'SKILL.md'), `---
name: ${skillId}
version: ${version}
description: ${description}
---

# ${name}
`);
  writeJson(path.join(sourceRoot, skillId, 'skill.json'), {
    schema_version: 'xhub.skill_manifest.v1',
    skill_id: skillId,
    name,
    version,
    description,
    side_effect_class: sideEffectClass,
    risk_level: riskLevel,
    requires_grant: requiresGrant,
    entrypoint: {
      runtime: 'text',
      command: 'cat',
      args: ['SKILL.md'],
    },
    capabilities_required: capabilitiesRequired,
    network_policy: {
      direct_network_forbidden: true,
    },
    publisher: {
      publisher_id: publisherId,
    },
  });

  buildOfficialAgentSkills({
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
  };
}

await run('official skill channel maintainer syncs soon after startup', async () => {
  const tempRoot = tmpDir('startup');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = createOfficialPublicSource(tempRoot, {
      skillId: 'find-skills',
      name: 'Find Skills',
      description: 'Official governed search helper.',
      capabilitiesRequired: ['skills.search'],
    });

    await withEnv({
      XHUB_OFFICIAL_AGENT_SKILLS_DIR: built.sourceRoot,
      XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: built.outputRoot,
    }, async () => {
      const stop = startOfficialSkillChannelMaintenance({
        runtimeBaseDir,
        interval_ms: 40,
        retry_after_ms: 0,
      });
      try {
        await sleepMs(120);
        const state = readOfficialSkillChannelState(runtimeBaseDir, {});
        const maintenance = readOfficialSkillChannelMaintenanceStatus(runtimeBaseDir, {});
        const events = readOfficialSkillChannelMaintenanceEvents(runtimeBaseDir, {});
        assert.equal(String(state.status || ''), 'healthy');
        assert.ok(String(state.current_snapshot_dir || '').includes('/official_channels/official-stable/current'));
        assert.ok(fs.existsSync(path.join(String(state.current_snapshot_dir || ''), 'index.json')));
        assert.equal(maintenance.maintenance_enabled, true);
        assert.equal(maintenance.maintenance_source_kind, 'env');
        assert.equal(Number(maintenance.maintenance_interval_ms || 0), 40);
        assert.ok(Number(maintenance.maintenance_last_run_at_ms || 0) > 0);
        assert.equal(String(maintenance.last_transition_kind || ''), 'status_changed');
        assert.equal(events.length, 1);
        assert.equal(String(events[0]?.transition_kind || ''), 'status_changed');
      } finally {
        stop();
      }
    });
  } finally {
    cleanupDir(tempRoot);
  }
});

await run('official skill channel maintainer repairs a missing current snapshot using persisted source root', async () => {
  const tempRoot = tmpDir('repair');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = createOfficialPublicSource(tempRoot, {
      skillId: 'summarize',
      name: 'Summarize',
      description: 'Official governed summary helper.',
      capabilitiesRequired: ['web.fetch', 'ai.generate.local'],
      riskLevel: 'medium',
    });

    await withEnv({
      XHUB_OFFICIAL_AGENT_SKILLS_DIR: built.sourceRoot,
      XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: built.outputRoot,
    }, async () => {
      const stop = startOfficialSkillChannelMaintenance({
        runtimeBaseDir,
        interval_ms: 40,
        retry_after_ms: 0,
      });
      try {
        await sleepMs(120);
        const first = readOfficialSkillChannelState(runtimeBaseDir, {});
        assert.equal(String(first.status || ''), 'healthy');
        assert.ok(first.current_snapshot_dir);

        delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
        delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
        fs.rmSync(String(first.current_snapshot_dir || ''), { recursive: true, force: true });

        await sleepMs(160);
        const repaired = readOfficialSkillChannelState(runtimeBaseDir, {});
        const maintenance = readOfficialSkillChannelMaintenanceStatus(runtimeBaseDir, {});
        const events = readOfficialSkillChannelMaintenanceEvents(runtimeBaseDir, {});
        assert.equal(String(repaired.status || ''), 'healthy');
        assert.ok(repaired.current_snapshot_dir);
        assert.ok(fs.existsSync(path.join(String(repaired.current_snapshot_dir || ''), 'index.json')));
        assert.equal(String(repaired.source_root || ''), path.resolve(built.outputRoot));
        assert.equal(maintenance.maintenance_enabled, true);
        assert.equal(maintenance.maintenance_source_kind, 'persisted');
        assert.equal(String(maintenance.last_transition_kind || ''), 'current_snapshot_repaired');
        assert.equal(events.length, 2);
        assert.equal(String(events[1]?.transition_kind || ''), 'current_snapshot_repaired');
      } finally {
        stop();
      }
    });
  } finally {
    cleanupDir(tempRoot);
  }
});

await run('official skill channel maintainer no-ops when no public source is available', async () => {
  const tempRoot = tmpDir('noop');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    await withEnv({
      XHUB_OFFICIAL_AGENT_SKILLS_DIR: null,
      XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: null,
    }, async () => {
      const stop = startOfficialSkillChannelMaintenance({
        runtimeBaseDir,
        interval_ms: 40,
        retry_after_ms: 0,
        sourceRoot: path.join(tempRoot, 'missing-source'),
      });
      try {
        await sleepMs(120);
        const state = readOfficialSkillChannelState(runtimeBaseDir, {});
        const maintenance = readOfficialSkillChannelMaintenanceStatus(runtimeBaseDir, {});
        const events = readOfficialSkillChannelMaintenanceEvents(runtimeBaseDir, {});
        assert.equal(String(state.status || ''), 'missing');
        assert.equal(String(state.current_snapshot_dir || ''), '');
        assert.equal(String(state.last_known_good_snapshot_dir || ''), '');
        assert.equal(maintenance.maintenance_enabled, true);
        assert.equal(maintenance.maintenance_source_kind, 'explicit');
        assert.ok(Number(maintenance.maintenance_last_run_at_ms || 0) > 0);
        assert.equal(String(maintenance.last_transition_kind || ''), '');
        assert.equal(events.length, 0);
      } finally {
        stop();
      }
    });
  } finally {
    cleanupDir(tempRoot);
  }
});
