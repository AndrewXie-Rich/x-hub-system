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
  loadSkillSources,
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

function assertGovernedOfficialSkillMeta(meta, { packageSha256, publisherId }) {
  assert.equal(String(meta?.package_id || ''), 'find-skills');
  assert.equal(String(meta?.package_kind || ''), 'official_skill');
  assert.equal(String(meta?.trust_tier || ''), 'governed_package');
  assert.equal(String(meta?.contract_version || ''), '2026-03-18');
  assert.equal(String(meta?.package_state || ''), 'discovered');
  assert.equal(String(meta?.catalog_tier || ''), 'embedded_official');
  assert.equal(String(meta?.source_type || ''), 'embedded_catalog');
  assert.equal(String(meta?.downloadability || ''), 'offline_only');
  assert.equal(String(meta?.buildability || ''), 'prebuilt_only');
  assert.equal(String(meta?.support_tier || ''), 'official');
  assert.equal(String(meta?.revoke_state || ''), 'active');
  assert.equal(String(meta?.artifact_resolution_mode || ''), 'embedded_only');
  assert.deepEqual(meta?.doctor_bundles, ['official_skills']);
  assert.equal(String(meta?.compatibility_state || ''), 'supported');
  assert.equal(String(meta?.compatibility_envelope?.manifest_contract_version || ''), 'xhub.skill_manifest.v1');
  assert.equal(String(meta?.compatibility_envelope?.compatibility_state || ''), 'verified');
  assert.deepEqual(meta?.compatibility_envelope?.protocol_versions, ['skills_abi_compat.v1']);
  assert.deepEqual(meta?.compatibility_envelope?.runtime_hosts, ['hub_runtime', 'xt_runtime']);
  assert.equal(String(meta?.quality_evidence_status?.replay || ''), 'missing');
  assert.equal(String(meta?.quality_evidence_status?.fuzz || ''), 'missing');
  assert.equal(String(meta?.quality_evidence_status?.doctor || ''), 'missing');
  assert.equal(String(meta?.quality_evidence_status?.smoke || ''), 'missing');
  assert.equal(String(meta?.artifact_integrity?.package_sha256 || ''), packageSha256);
  assert.equal(String(meta?.artifact_integrity?.manifest_sha256 || ''), String(meta?.manifest_sha256 || ''));
  assert.equal(String(meta?.artifact_integrity?.package_format || ''), 'tar.gz');
  assert.equal(Number(meta?.artifact_integrity?.file_hash_count || 0), 2);
  assert.equal(Number(meta?.artifact_integrity?.package_size_bytes || 0) > 0, true);
  assert.equal(String(meta?.artifact_integrity?.signature?.algorithm || ''), 'ed25519');
  assert.equal(!!meta?.artifact_integrity?.signature?.present, true);
  assert.equal(!!meta?.artifact_integrity?.signature?.trusted_publisher, true);
  assert.equal(String(meta?.signature_alg || ''), 'ed25519');
  assert.equal(!!meta?.signature_verified, true);
  assert.equal(!!meta?.signature_bypassed, false);
  assert.equal(String(meta?.security_profile || ''), 'low_risk');
  assert.equal(String(meta?.package_format || ''), 'tar.gz');
  assert.equal(Number(meta?.file_hash_count || 0), 2);
  assert.equal(Number(meta?.package_size_bytes || 0) > 0, true);
  assert.equal(String(meta?.publisher_id || ''), publisherId);
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
    assert.equal(String(search[0].risk_level || ''), 'low');
    assert.equal(!!search[0].requires_grant, false);
    assert.equal(String(search[0].side_effect_class || ''), 'read_only');
    assertGovernedOfficialSkillMeta(search[0], {
      packageSha256: skill.package_sha256,
      publisherId: 'xhub.official',
    });

    const meta = getSkillPackageMeta(runtimeBaseDir, skill.package_sha256);
    assert.equal(String(meta?.skill_id || ''), 'find-skills');
    assert.equal(String(meta?.source_id || ''), 'builtin:catalog');
    assert.equal(String(meta?.risk_level || ''), 'low');
    assert.equal(!!meta?.requires_grant, false);
    assert.equal(String(meta?.side_effect_class || ''), 'read_only');
    assertGovernedOfficialSkillMeta(meta, {
      packageSha256: skill.package_sha256,
      publisherId: 'xhub.official',
    });

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
    assert.equal(String(resolved[0]?.skill?.risk_level || ''), 'low');
    assert.equal(!!resolved[0]?.skill?.requires_grant, false);
    assert.equal(String(resolved[0]?.skill?.side_effect_class || ''), 'read_only');
    assertGovernedOfficialSkillMeta(resolved[0]?.skill, {
      packageSha256: skill.package_sha256,
      publisherId: 'xhub.official',
    });

    const runtimeIndex = loadSkillsIndex(runtimeBaseDir);
    assert.equal(runtimeIndex.skills.length, 1);
    assert.equal(String(runtimeIndex.skills[0]?.skill_id || ''), 'find-skills');
    assert.equal(String(runtimeIndex.skills[0]?.package_sha256 || ''), skill.package_sha256);
    assert.equal(String(runtimeIndex.skills[0]?.risk_level || ''), 'low');
    assert.equal(!!runtimeIndex.skills[0]?.requires_grant, false);
    assert.equal(String(runtimeIndex.skills[0]?.side_effect_class || ''), 'read_only');
    assertGovernedOfficialSkillMeta(runtimeIndex.skills[0], {
      packageSha256: skill.package_sha256,
      publisherId: 'xhub.official',
    });
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
    assert.equal(String(search[0].risk_level || ''), 'low');
    assert.equal(!!search[0].requires_grant, false);
    assert.equal(String(search[0].side_effect_class || ''), 'read_only');
    assertGovernedOfficialSkillMeta(search[0], {
      packageSha256: skill.package_sha256,
      publisherId: 'xhub.local.dev',
    });

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
    assert.equal(String(resolved[0]?.skill?.risk_level || ''), 'low');
    assert.equal(!!resolved[0]?.skill?.requires_grant, false);
    assert.equal(String(resolved[0]?.skill?.side_effect_class || ''), 'read_only');
    assertGovernedOfficialSkillMeta(resolved[0]?.skill, {
      packageSha256: skill.package_sha256,
      publisherId: 'xhub.local.dev',
    });

    const runtimeIndex = loadSkillsIndex(runtimeBaseDir);
    assert.equal(runtimeIndex.skills.length, 1);
    assert.equal(String(runtimeIndex.skills[0]?.publisher_id || ''), 'xhub.local.dev');
    assert.equal(String(runtimeIndex.skills[0]?.package_sha256 || ''), skill.package_sha256);
    assert.equal(String(runtimeIndex.skills[0]?.risk_level || ''), 'low');
    assert.equal(!!runtimeIndex.skills[0]?.requires_grant, false);
    assert.equal(String(runtimeIndex.skills[0]?.side_effect_class || ''), 'read_only');
    assertGovernedOfficialSkillMeta(runtimeIndex.skills[0], {
      packageSha256: skill.package_sha256,
      publisherId: 'xhub.local.dev',
    });
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

run('official published index ignores package and manifest paths that escape dist root', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skills-store-official-escape-'));
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;

  try {
    const sourceRoot = path.join(tempRoot, 'official-agent-skills');
    const outputRoot = path.join(sourceRoot, 'dist');
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const outsideRoot = path.join(tempRoot, 'outside');
    const safePackagePath = path.join(outputRoot, 'packages', 'safe.tgz');
    const safeManifestPath = path.join(outputRoot, 'manifests', 'safe.json');
    const unsafePackagePath = path.join(outsideRoot, 'escape.tgz');
    const unsafeManifestPath = path.join(outsideRoot, 'escape.json');
    const safePackageBytes = Buffer.from('safe package', 'utf8');
    const unsafePackageBytes = Buffer.from('unsafe package', 'utf8');

    fs.mkdirSync(path.dirname(safePackagePath), { recursive: true });
    fs.mkdirSync(path.dirname(safeManifestPath), { recursive: true });
    fs.mkdirSync(outsideRoot, { recursive: true });
    fs.writeFileSync(safePackagePath, safePackageBytes);
    fs.writeFileSync(safeManifestPath, JSON.stringify({ skill_id: 'safe-skill' }, null, 2));
    fs.writeFileSync(unsafePackagePath, unsafePackageBytes);
    fs.writeFileSync(unsafeManifestPath, JSON.stringify({ skill_id: 'escape-skill' }, null, 2));
    writeFile(path.join(outputRoot, 'index.json'), JSON.stringify({
      generated_at_ms: 1710000000000,
      skills: [
        {
          skill_id: 'safe-skill',
          name: 'Safe Skill',
          version: '1.0.0',
          description: 'Safe published skill.',
          publisher_id: 'xhub.official',
          package_sha256: crypto.createHash('sha256').update(safePackageBytes).digest('hex'),
          package_path: 'packages/safe.tgz',
          manifest_path: 'manifests/safe.json',
        },
        {
          skill_id: 'escape-skill',
          name: 'Escape Skill',
          version: '1.0.0',
          description: 'Should be ignored because its files escape dist root.',
          publisher_id: 'xhub.official',
          package_sha256: crypto.createHash('sha256').update(unsafePackageBytes).digest('hex'),
          package_path: '../../outside/escape.tgz',
          manifest_path: '../../outside/escape.json',
        },
      ],
    }, null, 2));

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = outputRoot;

    const safeResults = searchSkills(runtimeBaseDir, { query: 'safe-skill', limit: 10 });
    const escapedResults = searchSkills(runtimeBaseDir, { query: 'escape-skill', limit: 10 });

    assert.equal(safeResults.some((it) => String(it.skill_id || '') === 'safe-skill'), true);
    assert.equal(escapedResults.some((it) => String(it.skill_id || '') === 'escape-skill'), false);
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

run('official source catalog ignores manifest symlinks that escape source root', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skills-store-official-source-'));
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;

  try {
    const sourceRoot = path.join(tempRoot, 'official-agent-skills');
    const outputRoot = path.join(sourceRoot, 'dist');
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const outsideRoot = path.join(tempRoot, 'outside');
    const escapedManifestPath = path.join(outsideRoot, 'rogue.skill.json');

    writeFile(path.join(sourceRoot, 'valid-skill', 'skill.json'), JSON.stringify({
      skill_id: 'valid-skill',
      version: '1.0.0',
      name: 'Valid Skill',
      description: 'Safe local source manifest.',
      publisher_id: 'xhub.official',
      capabilities_required: ['skills.search'],
    }, null, 2));
    fs.mkdirSync(path.join(sourceRoot, 'rogue-skill'), { recursive: true });
    fs.mkdirSync(outsideRoot, { recursive: true });
    fs.mkdirSync(outputRoot, { recursive: true });
    fs.writeFileSync(escapedManifestPath, JSON.stringify({
      skill_id: 'rogue-skill',
      version: '1.0.0',
      name: 'Rogue Skill',
      description: 'Should be ignored because manifest is a symlink outside root.',
      publisher_id: 'xhub.official',
    }, null, 2));
    fs.symlinkSync(escapedManifestPath, path.join(sourceRoot, 'rogue-skill', 'skill.json'));

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = outputRoot;

    const sources = loadSkillSources(runtimeBaseDir);
    const builtin = Array.isArray(sources.sources)
      ? sources.sources.find((it) => String(it?.source_id || '') === 'builtin:catalog')
      : null;
    const discovery = Array.isArray(builtin?.discovery_index) ? builtin.discovery_index : [];
    const skillIds = new Set(discovery.map((it) => String(it?.skill_id || '')));

    assert.equal(skillIds.has('valid-skill'), true);
    assert.equal(skillIds.has('rogue-skill'), false);

    const rogueSearch = searchSkills(runtimeBaseDir, { query: 'rogue-skill', sourceFilter: 'builtin:catalog', limit: 10 });
    assert.equal(rogueSearch.some((it) => String(it.skill_id || '') === 'rogue-skill'), false);
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
