import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

import {
  evaluateSkillExecutionGate,
  getSkillManifest,
  getSkillPackageMeta,
  listResolvedSkills,
  loadSkillsIndex,
  readSkillPackage,
  searchSkills,
  setSkillPin,
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

run('official agent skill dist packages are searchable and pinnable through skills_store', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skills-store-official-'));
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;

  try {
    const sourceRoot = path.join(tempRoot, 'official-agent-skills');
    const outputRoot = path.join(sourceRoot, 'dist');
    const publisherDir = path.join(sourceRoot, 'publisher');
    const publisher = makePublisherTrust();
    const privateKeyPath = path.join(tempRoot, 'xhub_official_ed25519.pem');
    const runtimeBaseDir = path.join(tempRoot, 'runtime');

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
        publisher_id: 'xhub.official',
      },
      install_hint: 'Install via baseline.',
    }, null, 2));

    const index = buildOfficialAgentSkills({
      sourceRoot,
      outputRoot,
      generatedAtMs: 1710000000000,
      publisherTrustFile: path.join(publisherDir, 'trusted_publishers.json'),
      signingPrivateKeyFile: privateKeyPath,
    });
    const skill = index.skills[0];

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = outputRoot;

    const search = searchSkills(runtimeBaseDir, { query: 'find-skills', limit: 10 });
    assert.equal(search.length, 1);
    assert.equal(search[0].skill_id, 'find-skills');
    assert.equal(search[0].package_sha256, skill.package_sha256);

    const meta = getSkillPackageMeta(runtimeBaseDir, skill.package_sha256);
    assert.equal(String(meta?.skill_id || ''), 'find-skills');
    assert.equal(String(meta?.source_id || ''), 'builtin:catalog');

    const manifestText = getSkillManifest(runtimeBaseDir, skill.package_sha256);
    assert.equal(typeof manifestText, 'string');
    assert.equal(manifestText.includes('"skill_id": "find-skills"'), true);
    assert.equal(manifestText.includes('"alg": "ed25519"'), true);

    const packageBytes = readSkillPackage(runtimeBaseDir, skill.package_sha256);
    assert.equal(Buffer.isBuffer(packageBytes), true);
    assert.equal(packageBytes.length > 0, true);

    const gate = evaluateSkillExecutionGate(runtimeBaseDir, {
      packageSha256: skill.package_sha256,
      packageBytes,
      manifestJson: manifestText,
      skillId: 'find-skills',
      publisherId: 'xhub.official',
    });
    assert.equal(!!gate.allowed, true);

    const pin = setSkillPin(runtimeBaseDir, {
      scope: 'project',
      userId: 'user-1',
      projectId: 'project-1',
      skillId: 'find-skills',
      packageSha256: skill.package_sha256,
      note: 'official package',
    });
    assert.equal(pin.skill_id, 'find-skills');
    assert.equal(pin.package_sha256, skill.package_sha256);

    const resolved = listResolvedSkills(runtimeBaseDir, {
      userId: 'user-1',
      projectId: 'project-1',
    });
    assert.equal(resolved.length, 1);
    assert.equal(String(resolved[0]?.skill?.skill_id || ''), 'find-skills');
    assert.equal(String(resolved[0]?.skill?.package_sha256 || ''), skill.package_sha256);

    const runtimeIndex = loadSkillsIndex(runtimeBaseDir);
    assert.equal(runtimeIndex.skills.length, 1);
    assert.equal(String(runtimeIndex.skills[0]?.skill_id || ''), 'find-skills');
    assert.equal(String(runtimeIndex.skills[0]?.package_sha256 || ''), skill.package_sha256);
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

run('local dev published agent skill dist remains searchable and executable through skills_store', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skills-store-local-dev-'));
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;

  try {
    const sourceRoot = path.join(tempRoot, 'official-agent-skills');
    const outputRoot = path.join(sourceRoot, 'dist');
    const publisherDir = path.join(sourceRoot, 'publisher');
    const publisher = makePublisherTrust('xhub.local.dev');
    const privateKeyPath = path.join(tempRoot, 'xhub_local_dev_ed25519.pem');
    const runtimeBaseDir = path.join(tempRoot, 'runtime');

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
        publisher_id: 'xhub.official',
      },
      install_hint: 'Install via baseline.',
    }, null, 2));

    const index = buildOfficialAgentSkills({
      sourceRoot,
      outputRoot,
      generatedAtMs: 1710000000000,
      publisherTrustFile: path.join(publisherDir, 'trusted_publishers.json'),
      signingPrivateKeyFile: privateKeyPath,
      publisherIdOverride: 'xhub.local.dev',
    });
    const skill = index.skills[0];

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = outputRoot;

    const search = searchSkills(runtimeBaseDir, { query: 'find-skills', limit: 10 });
    assert.equal(search.length, 1);
    assert.equal(search[0].skill_id, 'find-skills');
    assert.equal(search[0].publisher_id, 'xhub.local.dev');

    const manifestText = getSkillManifest(runtimeBaseDir, skill.package_sha256);
    const packageBytes = readSkillPackage(runtimeBaseDir, skill.package_sha256);
    const gate = evaluateSkillExecutionGate(runtimeBaseDir, {
      packageSha256: skill.package_sha256,
      packageBytes,
      manifestJson: manifestText,
      skillId: 'find-skills',
      publisherId: 'xhub.local.dev',
    });
    assert.equal(!!gate.allowed, true);

    const pin = setSkillPin(runtimeBaseDir, {
      scope: 'global',
      userId: 'user-1',
      projectId: '',
      skillId: 'find-skills',
      packageSha256: skill.package_sha256,
      note: 'local dev package',
    });
    assert.equal(pin.skill_id, 'find-skills');
    assert.equal(pin.package_sha256, skill.package_sha256);

    const resolved = listResolvedSkills(runtimeBaseDir, {
      userId: 'user-1',
      projectId: '',
    });
    assert.equal(resolved.length, 1);
    assert.equal(String(resolved[0]?.skill?.skill_id || ''), 'find-skills');
    assert.equal(String(resolved[0]?.skill?.publisher_id || ''), 'xhub.local.dev');
    assert.equal(String(resolved[0]?.skill?.package_sha256 || ''), skill.package_sha256);

    const runtimeIndex = loadSkillsIndex(runtimeBaseDir);
    assert.equal(runtimeIndex.skills.length, 1);
    assert.equal(String(runtimeIndex.skills[0]?.publisher_id || ''), 'xhub.local.dev');
    assert.equal(String(runtimeIndex.skills[0]?.package_sha256 || ''), skill.package_sha256);
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
