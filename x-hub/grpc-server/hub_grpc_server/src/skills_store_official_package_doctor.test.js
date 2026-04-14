import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

import {
  getSkillPackageDoctorReport,
  listOfficialSkillPackageLifecycleRows,
  listOfficialSkillPackageDoctorSummaries,
  loadOfficialSkillPackageLifecycleSnapshot,
  refreshOfficialSkillPackageLifecycleSnapshot,
  setSkillPin,
} from './skills_store.js';
import {
  resolveOfficialSkillChannelSnapshotDir,
  syncOfficialSkillChannel,
} from './official_skill_channel_sync.js';

const require = createRequire(import.meta.url);
const { buildOfficialAgentSkills } = require('../../../../scripts/build_official_agent_skills.js');

function run(name, fn) {
  try {
    fn();
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

run('official skill package doctor reports ready and active states for governed official skills', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skills-store-official-doctor-'));
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;

  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = buildOfficialSkillFixture(tempRoot);

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = built.sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = built.outputRoot;

    const syncState = syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    assert.equal(String(syncState.status || ''), 'healthy');

    const report = getSkillPackageDoctorReport(runtimeBaseDir, {
      packageSha256: built.skill.package_sha256,
      surface: 'hub_cli',
    });
    assert.equal(String(report.kind || ''), 'official_skill');
    assert.equal(String(report.trust_tier || ''), 'governed_package');
    assert.equal(String(report.doctor_bundle || ''), 'official_skills');
    assert.equal(String(report.package_state || ''), 'discovered');
    assert.equal(String(report.overall_state || ''), 'ready');
    assert.equal(Number(report.summary?.failed || 0), 0);
    assert.equal(Number(report.summary?.warned || 0), 0);
    assert.equal(Array.isArray(report.checks), true);
    assert.equal(
      report.checks.some((check) => String(check.check_id || '') === 'catalog_snapshot_check' && String(check.status || '') === 'pass'),
      true
    );

    setSkillPin(runtimeBaseDir, {
      scope: 'project',
      userId: 'user-1',
      projectId: 'project-1',
      skillId: 'find-skills',
      packageSha256: built.skill.package_sha256,
      note: 'doctor active state',
    });

    const activeReport = getSkillPackageDoctorReport(runtimeBaseDir, {
      packageSha256: built.skill.package_sha256,
      userId: 'user-1',
      projectId: 'project-1',
      surface: 'hub_ui',
      xtVersion: 'xt-1.2.3',
    });
    assert.equal(String(activeReport.package_state || ''), 'active');
    assert.equal(String(activeReport.overall_state || ''), 'ready');
    assert.equal(String(activeReport.surface || ''), 'hub_ui');
    assert.equal(String(activeReport.runtime_snapshot?.xt_version || ''), 'xt-1.2.3');
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

run('official skill package doctor reports blocked when catalog artifacts are missing', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skills-store-official-doctor-missing-'));
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;

  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = buildOfficialSkillFixture(tempRoot);

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = built.sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = built.outputRoot;

    fs.rmSync(path.join(built.outputRoot, built.skill.package_path), { force: true });

    const report = getSkillPackageDoctorReport(runtimeBaseDir, {
      packageSha256: built.skill.package_sha256,
      surface: 'api',
    });
    assert.equal(String(report.package_state || ''), 'discovered');
    assert.equal(String(report.overall_state || ''), 'blocked');
    assert.equal(Number(report.summary?.failed || 0) >= 1, true);
    assert.equal(
      report.checks.some((check) => String(check.check_id || '') === 'artifact_integrity_check' && String(check.status || '') === 'fail'),
      true
    );
    assert.equal(
      report.next_steps.some((step) => String(step.kind || '') === 'repair_artifact'),
      true
    );
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

run('official skill package doctor summaries expose lifecycle rollup and filtering', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skills-store-official-doctor-summary-'));
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;

  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = buildOfficialSkillFixture(tempRoot);

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = built.sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = built.outputRoot;

    syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });
    setSkillPin(runtimeBaseDir, {
      scope: 'project',
      userId: 'user-1',
      projectId: 'project-1',
      skillId: 'find-skills',
      packageSha256: built.skill.package_sha256,
      note: 'doctor summary active state',
    });

    const active = listOfficialSkillPackageDoctorSummaries(runtimeBaseDir, {
      userId: 'user-1',
      projectId: 'project-1',
      overallState: 'ready',
      packageState: 'active',
      surface: 'xt_ui',
      xtVersion: 'xt-2.0.0',
    });
    assert.equal(active.length, 1);
    assert.equal(String(active[0]?.skill_id || ''), 'find-skills');
    assert.equal(String(active[0]?.package_state || ''), 'active');
    assert.equal(String(active[0]?.overall_state || ''), 'ready');
    assert.equal(Number(active[0]?.blocking_failures || 0), 0);

    const snapshotDir = resolveOfficialSkillChannelSnapshotDir(runtimeBaseDir, {});
    fs.rmSync(path.join(snapshotDir, built.skill.package_path), { force: true });
    const blocked = listOfficialSkillPackageDoctorSummaries(runtimeBaseDir, {
      overallState: 'blocked',
      skillId: 'find-skills',
      surface: 'api',
    });
    assert.equal(blocked.length, 1);
    assert.equal(String(blocked[0]?.skill_id || ''), 'find-skills');
    assert.equal(String(blocked[0]?.package_state || ''), 'discovered');
    assert.equal(String(blocked[0]?.overall_state || ''), 'blocked');
    assert.equal(Number(blocked[0]?.blocking_failures || 0) >= 1, true);
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

run('official skill package lifecycle snapshot persists transitions and filtered reads', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skills-store-official-lifecycle-'));
  const priorSourceRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
  const priorDistRoot = process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;

  try {
    const runtimeBaseDir = path.join(tempRoot, 'runtime');
    const built = buildOfficialSkillFixture(tempRoot);
    const firstRefreshAtMs = 1710000000100;
    const secondRefreshAtMs = 1710000000200;

    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = built.sourceRoot;
    process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = built.outputRoot;

    syncOfficialSkillChannel(runtimeBaseDir, {
      sourceRoot: built.sourceRoot,
    });

    const first = refreshOfficialSkillPackageLifecycleSnapshot(runtimeBaseDir, {
      surface: 'xt_ui',
      xtVersion: 'xt-2.0.0',
      generatedAtMs: firstRefreshAtMs,
    });
    assert.equal(String(first.schema_version || ''), 'xhub.official_skill_package_lifecycle_snapshot.v1');
    assert.equal(Number(first.updated_at_ms || 0), firstRefreshAtMs);
    assert.equal(Number(first.totals?.packages_total || 0), 1);
    assert.equal(Number(first.totals?.ready_total || 0), 1);
    assert.equal(Number(first.totals?.blocked_total || 0), 0);
    assert.equal(Number(first.totals?.not_supported_total || 0), 0);
    assert.equal(Array.isArray(first.packages), true);
    assert.equal(first.packages.length, 1);
    assert.equal(String(first.packages[0]?.skill_id || ''), 'find-skills');
    assert.equal(String(first.packages[0]?.package_state || ''), 'discovered');
    assert.equal(String(first.packages[0]?.overall_state || ''), 'ready');
    assert.equal(Number(first.packages[0]?.first_seen_at_ms || 0), firstRefreshAtMs);
    assert.equal(Number(first.packages[0]?.last_transition_at_ms || 0), firstRefreshAtMs);
    assert.equal(Number(first.packages[0]?.last_ready_at_ms || 0), firstRefreshAtMs);
    assert.equal(Number(first.packages[0]?.last_blocked_at_ms || 0), 0);
    assert.equal(Number(first.packages[0]?.transition_count || 0), 1);

    const loadedFirst = loadOfficialSkillPackageLifecycleSnapshot(runtimeBaseDir);
    assert.equal(Number(loadedFirst.updated_at_ms || 0), firstRefreshAtMs);
    assert.equal(loadedFirst.packages.length, 1);
    assert.equal(String(loadedFirst.packages[0]?.overall_state || ''), 'ready');

    const snapshotDir = resolveOfficialSkillChannelSnapshotDir(runtimeBaseDir, {});
    fs.rmSync(path.join(snapshotDir, built.skill.package_path), { force: true });

    const staleRead = listOfficialSkillPackageLifecycleRows(runtimeBaseDir, {
      skillId: 'find-skills',
      overallState: 'ready',
      refresh: false,
    });
    assert.equal(Number(staleRead.snapshot?.updated_at_ms || 0), firstRefreshAtMs);
    assert.equal(staleRead.packages.length, 1);
    assert.equal(String(staleRead.packages[0]?.overall_state || ''), 'ready');

    const second = refreshOfficialSkillPackageLifecycleSnapshot(runtimeBaseDir, {
      surface: 'api',
      generatedAtMs: secondRefreshAtMs,
    });
    assert.equal(Number(second.updated_at_ms || 0), secondRefreshAtMs);
    assert.equal(Number(second.totals?.ready_total || 0), 0);
    assert.equal(Number(second.totals?.blocked_total || 0), 1);
    assert.equal(second.packages.length, 1);
    assert.equal(String(second.packages[0]?.skill_id || ''), 'find-skills');
    assert.equal(String(second.packages[0]?.package_state || ''), 'discovered');
    assert.equal(String(second.packages[0]?.overall_state || ''), 'blocked');
    assert.equal(Number(second.packages[0]?.last_ready_at_ms || 0), firstRefreshAtMs);
    assert.equal(Number(second.packages[0]?.last_blocked_at_ms || 0), secondRefreshAtMs);
    assert.equal(Number(second.packages[0]?.last_transition_at_ms || 0), secondRefreshAtMs);
    assert.equal(Number(second.packages[0]?.transition_count || 0), 2);
    assert.equal(Number(second.packages[0]?.blocking_failures || 0) >= 1, true);

    const loadedSecond = loadOfficialSkillPackageLifecycleSnapshot(runtimeBaseDir);
    assert.equal(Number(loadedSecond.updated_at_ms || 0), secondRefreshAtMs);
    assert.equal(loadedSecond.packages.length, 1);
    assert.equal(Number(loadedSecond.totals?.blocked_total || 0), 1);
    assert.equal(Number(loadedSecond.totals?.ready_total || 0), 0);
    assert.equal(Number(loadedSecond.packages[0]?.last_ready_at_ms || 0), firstRefreshAtMs);
    assert.equal(Number(loadedSecond.packages[0]?.last_blocked_at_ms || 0), secondRefreshAtMs);
    assert.equal(Number(loadedSecond.packages[0]?.transition_count || 0), 2);

    const filteredBlocked = listOfficialSkillPackageLifecycleRows(runtimeBaseDir, {
      skillId: 'find-skills',
      overallState: 'blocked',
      refresh: false,
    });
    assert.equal(String(filteredBlocked.snapshot?.schema_version || ''), 'xhub.official_skill_package_lifecycle_snapshot.v1');
    assert.equal(Number(filteredBlocked.snapshot?.updated_at_ms || 0), secondRefreshAtMs);
    assert.equal(filteredBlocked.packages.length, 1);
    assert.equal(String(filteredBlocked.packages[0]?.overall_state || ''), 'blocked');
  } finally {
    if (priorSourceRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = priorSourceRoot;
    if (priorDistRoot == null) delete process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR;
    else process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = priorDistRoot;
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
