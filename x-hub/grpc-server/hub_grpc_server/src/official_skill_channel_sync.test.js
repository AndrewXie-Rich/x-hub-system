import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

import {
  maybeAutoSyncOfficialSkillChannel,
  readOfficialSkillChannelState,
  resolveOfficialSkillChannelSnapshotDir,
  syncOfficialSkillChannel,
} from './official_skill_channel_sync.js';
import {
  getSkillPackageMeta,
  loadSkillRevocations,
  loadSkillSources,
  loadTrustedPublishers,
  searchSkills,
} from './skills_store.js';

const require = createRequire(import.meta.url);
const { buildOfficialAgentSkills } = require('../../../../scripts/build_official_agent_skills.js');

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function tmpDir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `xhub_official_sync_${label}_`));
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

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, value) {
  writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`);
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

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const [key, value] of Object.entries(tempEnv || {})) {
    previous.set(key, process.env[key]);
    if (value == null) delete process.env[key];
    else process.env[key] = String(value);
  }
  try {
    return fn();
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
  installHint = 'Install through Hub-governed approval.',
  revocations = null,
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
    install_hint: installHint,
  });

  const index = buildOfficialAgentSkills({
    sourceRoot,
    outputRoot,
    generatedAtMs: 1710000000000,
    publisherTrustFile: path.join(publisherDir, 'trusted_publishers.json'),
    signingPrivateKeyFile: privateKeyPath,
    publisherIdOverride: publisherId,
  });
  const builtSkill = index.skills.find((entry) => String(entry?.skill_id || '') === skillId);
  writeJson(path.join(outputRoot, 'official_catalog_snapshot.json'), {
    schema_version: 'xhub.official_skill_catalog_snapshot.v1',
    updated_at_ms: 1710000000000,
    publisher_id: publisherId,
    profiles: [],
    skills: [
      {
        skill_id: skillId,
        version,
        name,
        description,
        publisher_id: publisherId,
        risk_level: riskLevel,
        requires_grant: requiresGrant,
        side_effect_class: sideEffectClass,
        capabilities_required: capabilitiesRequired,
        package_sha256: String(builtSkill?.package_sha256 || ''),
        install_hint: installHint,
      },
    ],
  });
  if (revocations) {
    writeJson(path.join(outputRoot, 'revocations.json'), revocations);
  }

  return {
    sourceRoot,
    outputRoot,
    skill: builtSkill,
    publisher,
  };
}

run('official skill channel sync writes current and last-known-good snapshots', () => {
  const tempRoot = tmpDir('success');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = createOfficialPublicSource(tempRoot, {
      skillId: 'tavily-websearch',
      name: 'Tavily Websearch',
      description: 'Fresh governed web search skill.',
      capabilitiesRequired: ['web.search'],
      riskLevel: 'medium',
      requiresGrant: false,
    });

    const state = syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    assert.equal(String(state.status || ''), 'healthy');
    assert.equal(Number(state.skill_count || 0), 1);
    assert.ok(fs.existsSync(path.join(String(state.current_snapshot_dir || ''), 'index.json')));
    assert.ok(fs.existsSync(path.join(String(state.last_known_good_snapshot_dir || ''), 'index.json')));

    const resolved = resolveOfficialSkillChannelSnapshotDir(runtimeBaseDir, {});
    assert.equal(resolved, String(state.current_snapshot_dir || ''));

    const stored = readOfficialSkillChannelState(runtimeBaseDir, {});
    assert.equal(String(stored.status || ''), 'healthy');
    assert.equal(String(stored.source_root || ''), path.resolve(built.sourceRoot));

    const sources = loadSkillSources(runtimeBaseDir);
    const builtin = Array.isArray(sources.sources)
      ? sources.sources.find((row) => String(row?.source_id || '') === 'builtin:catalog')
      : null;
    assert.ok(builtin);
    const discoveryIds = new Set((Array.isArray(builtin.discovery_index) ? builtin.discovery_index : []).map((row) => String(row?.skill_id || '')));
    assert.equal(discoveryIds.has('tavily-websearch'), true);
  } finally {
    cleanupDir(tempRoot);
  }
});

run('skills_store prefers synced official snapshot over env dist roots', () => {
  const tempRoot = tmpDir('search');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = createOfficialPublicSource(tempRoot, {
      skillId: 'tavily-websearch',
      name: 'Tavily Websearch',
      description: 'Fresh governed web search skill.',
      capabilitiesRequired: ['web.search'],
      riskLevel: 'medium',
      requiresGrant: false,
    });
    const syncState = syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    assert.equal(String(syncState.status || ''), 'healthy');

    const results = withEnv({
      XHUB_OFFICIAL_AGENT_SKILLS_DIR: path.join(tempRoot, 'missing-source'),
      XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: path.join(tempRoot, 'missing-dist'),
    }, () => searchSkills(runtimeBaseDir, {
      query: 'tavily',
      sourceFilter: 'builtin:catalog',
      limit: 10,
    }));
    assert.equal(results.length, 1);
    assert.equal(String(results[0]?.skill_id || ''), 'tavily-websearch');
    assert.equal(String(results[0]?.package_sha256 || ''), String(built.skill?.package_sha256 || ''));

    const meta = withEnv({
      XHUB_OFFICIAL_AGENT_SKILLS_DIR: path.join(tempRoot, 'missing-source'),
      XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: path.join(tempRoot, 'missing-dist'),
    }, () => getSkillPackageMeta(runtimeBaseDir, String(built.skill?.package_sha256 || '')));
    assert.ok(meta);
    assert.equal(String(meta?.skill_id || ''), 'tavily-websearch');
    assert.ok(String(meta?.package_fp || '').includes('/official_channels/official-stable/current/'));
  } finally {
    cleanupDir(tempRoot);
  }
});

run('skills_store auto-syncs official channel on first search when public source is available', () => {
  const tempRoot = tmpDir('auto_sync');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = createOfficialPublicSource(tempRoot, {
      skillId: 'code-review',
      name: 'Code Review',
      description: 'Governed code review skill.',
      capabilitiesRequired: ['repo.read.file'],
      riskLevel: 'low',
      requiresGrant: false,
    });

    const results = withEnv({
      XHUB_OFFICIAL_AGENT_SKILLS_DIR: built.sourceRoot,
      XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: built.outputRoot,
      XHUB_OFFICIAL_AGENT_AUTO_SYNC_RETRY_MS: '0',
    }, () => searchSkills(runtimeBaseDir, {
      query: 'code-review',
      sourceFilter: 'builtin:catalog',
      limit: 10,
    }));
    assert.equal(results.length, 1);
    assert.equal(String(results[0]?.skill_id || ''), 'code-review');

    const state = readOfficialSkillChannelState(runtimeBaseDir, {});
    assert.equal(String(state.status || ''), 'healthy');
    assert.ok(String(state.current_snapshot_dir || '').includes('/official_channels/official-stable/current'));
    assert.ok(fs.existsSync(path.join(String(state.current_snapshot_dir || ''), 'index.json')));

    const meta = getSkillPackageMeta(runtimeBaseDir, String(built.skill?.package_sha256 || ''));
    assert.ok(meta);
    assert.ok(String(meta?.package_fp || '').includes('/official_channels/official-stable/current/'));
  } finally {
    cleanupDir(tempRoot);
  }
});

run('failed official sync preserves previously usable snapshot', () => {
  const tempRoot = tmpDir('rollback');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = createOfficialPublicSource(tempRoot, {
      skillId: 'tavily-websearch',
      name: 'Tavily Websearch',
      description: 'Fresh governed web search skill.',
      capabilitiesRequired: ['web.search'],
      riskLevel: 'medium',
      requiresGrant: false,
    });
    const first = syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    assert.equal(String(first.status || ''), 'healthy');

    const indexPath = path.join(built.outputRoot, 'index.json');
    const indexObj = readJson(indexPath);
    indexObj.skills[0].package_sha256 = '0'.repeat(64);
    writeJson(indexPath, indexObj);

    const failed = syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    assert.equal(String(failed.status || ''), 'failed');
    assert.equal(String(failed.error_code || ''), 'package_sha256_mismatch');

    const snapshotDir = resolveOfficialSkillChannelSnapshotDir(runtimeBaseDir, {});
    const cachedIndex = readJson(path.join(snapshotDir, 'index.json'));
    assert.equal(String(cachedIndex.skills[0]?.package_sha256 || ''), String(built.skill?.package_sha256 || ''));

    const results = searchSkills(runtimeBaseDir, {
      query: 'tavily',
      sourceFilter: 'builtin:catalog',
      limit: 10,
    });
    assert.equal(results.length, 1);
    assert.equal(String(results[0]?.package_sha256 || ''), String(built.skill?.package_sha256 || ''));
  } finally {
    cleanupDir(tempRoot);
  }
});

run('auto-sync can reuse persisted source root after a previous successful sync', () => {
  const tempRoot = tmpDir('persisted_source_root');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = createOfficialPublicSource(tempRoot, {
      skillId: 'openclaw-backup',
      name: 'OpenClaw Backup',
      description: 'Governed backup skill.',
      capabilitiesRequired: ['filesystem.read'],
      riskLevel: 'medium',
      requiresGrant: false,
    });

    const first = syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    assert.equal(String(first.status || ''), 'healthy');

    fs.rmSync(String(first.current_snapshot_dir || ''), { recursive: true, force: true });
    const failedState = readOfficialSkillChannelState(runtimeBaseDir, {});
    assert.equal(String(failedState.status || ''), 'healthy');

    const repaired = maybeAutoSyncOfficialSkillChannel(runtimeBaseDir, {
      retryAfterMs: 0,
    });
    assert.equal(String(repaired.status || ''), 'healthy');
    assert.ok(fs.existsSync(path.join(String(repaired.current_snapshot_dir || ''), 'index.json')));
    assert.equal(String(repaired.source_root || ''), path.resolve(built.outputRoot));
  } finally {
    cleanupDir(tempRoot);
  }
});

run('synced trust and revocations flow into skills_store governance reads', () => {
  const tempRoot = tmpDir('trust_revocations');
  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = createOfficialPublicSource(tempRoot, {
      skillId: 'team-search',
      name: 'Team Search',
      description: 'Internal governed search skill.',
      capabilitiesRequired: ['web.search'],
      riskLevel: 'medium',
      requiresGrant: true,
      sideEffectClass: 'external_side_effect',
      publisherId: 'team.official',
      revocations: {
        schema_version: 'xhub.skill_revocations.v1',
        updated_at_ms: 1710000001000,
        revoked_sha256: [String('')],
        revoked_skill_ids: [],
        revoked_publishers: [],
      },
    });
    writeJson(path.join(built.outputRoot, 'revocations.json'), {
      schema_version: 'xhub.skill_revocations.v1',
      updated_at_ms: 1710000001000,
      revoked_sha256: [String(built.skill?.package_sha256 || '')],
      revoked_skill_ids: [],
      revoked_publishers: [],
    });

    const state = syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    assert.equal(String(state.status || ''), 'healthy');

    const trusted = loadTrustedPublishers(runtimeBaseDir);
    const publisherIds = new Set((Array.isArray(trusted.publishers) ? trusted.publishers : []).map((row) => String(row?.publisher_id || '')));
    assert.equal(publisherIds.has('team.official'), true);

    const revocations = loadSkillRevocations(runtimeBaseDir);
    assert.equal(revocations.revoked_sha256.includes(String(built.skill?.package_sha256 || '').toLowerCase()), true);

    const results = searchSkills(runtimeBaseDir, {
      query: 'team-search',
      sourceFilter: 'builtin:catalog',
      limit: 10,
    });
    assert.equal(results.length, 0);
  } finally {
    cleanupDir(tempRoot);
  }
});
