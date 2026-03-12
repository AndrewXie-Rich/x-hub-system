import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';

import {
  getAgentImportRecord,
  normalizeSkillStoreError,
  promoteAgentImport,
  setSkillPin,
  skillsGovernanceSnapshotPaths,
  stageAgentImport,
  uploadSkillPackage,
} from './skills_store.js';

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
  for (const [key, value] of Object.entries(tempEnv || {})) {
    prev.set(key, process.env[key]);
    if (value == null) delete process.env[key];
    else process.env[key] = String(value);
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of prev.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function tmpDir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `hub_agent_${label}_`));
}

function sha256Hex(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function writeTarHeader(name, size) {
  const header = Buffer.alloc(512, 0);
  const nm = Buffer.from(String(name || ''), 'utf8');
  if (nm.length > 100) throw new Error('test tar path too long');
  nm.copy(header, 0);
  header.write('0000777\0', 100, 8, 'ascii');
  header.write('0000000\0', 108, 8, 'ascii');
  header.write('0000000\0', 116, 8, 'ascii');
  const sizeOct = Number(size || 0).toString(8).padStart(11, '0');
  header.write(`${sizeOct}\0`, 124, 12, 'ascii');
  const mtimeOct = Math.floor(Date.now() / 1000).toString(8).padStart(11, '0');
  header.write(`${mtimeOct}\0`, 136, 12, 'ascii');
  header.fill(0x20, 148, 156);
  header[156] = '0'.charCodeAt(0);
  header.write('ustar\0', 257, 6, 'ascii');
  header.write('00', 263, 2, 'ascii');
  let sum = 0;
  for (let i = 0; i < 512; i += 1) sum += header[i];
  const chk = sum.toString(8).padStart(6, '0');
  header.write(chk, 148, 6, 'ascii');
  header[154] = 0;
  header[155] = 0x20;
  return header;
}

function buildTgz(filesByPath) {
  const chunks = [];
  for (const [name, body] of Object.entries(filesByPath || {})) {
    const data = Buffer.isBuffer(body) ? body : Buffer.from(String(body || ''), 'utf8');
    chunks.push(writeTarHeader(name, data.length));
    chunks.push(data);
    const pad = (512 - (data.length % 512)) % 512;
    if (pad > 0) chunks.push(Buffer.alloc(pad, 0));
  }
  chunks.push(Buffer.alloc(1024, 0));
  return zlib.gzipSync(Buffer.concat(chunks));
}

function expectDeny(fn, code) {
  let failed = false;
  try {
    fn();
  } catch (err) {
    failed = true;
    const normalized = normalizeSkillStoreError(err, 'runtime_error');
    assert.equal(String(normalized.code || ''), String(code || ''));
  }
  if (!failed) {
    assert.fail(`expected deny_code=${code} but call succeeded`);
  }
}

function sampleImportManifest({
  skillId = 'repo.git.status',
  preflightStatus = 'passed',
  policyScope = 'project',
  requiresGrant = false,
  riskLevel = 'low',
  schemaVersion = 'xt.agent_skill_import_manifest.v1',
  source = 'agent',
} = {}) {
  return {
    schema_version: schemaVersion,
    source,
    source_ref: 'skills/git-status/SKILL.md',
    skill_id: skillId,
    display_name: skillId,
    kind: 'skill',
    upstream_package_ref: 'local://agent-main/skills/git-status',
    normalized_capabilities: ['repo.read.status'],
    requires_grant: requiresGrant,
    risk_level: riskLevel,
    policy_scope: policyScope,
    sandbox_class: 'governed_project_local',
    prompt_mutation_allowed: false,
    install_provenance: 'local_import',
    preflight_status: preflightStatus,
  };
}

function sampleScanInput({
  skillMarkdown = '# Safe Skill\n\nThis skill stays within governed project-local behavior.\n',
  mainJS = 'export function run() { return "ok"; }\n',
} = {}) {
  return {
    schema_version: 'xt.agent_skill_scan_input.v1',
    files: [
      { path: 'SKILL.md', content: skillMarkdown },
      { path: 'dist/main.js', content: mainJS },
    ],
  };
}

function uploadLowRiskPackage(runtimeBaseDir, skillId) {
  const mainJs = Buffer.from('console.log("hello");\n', 'utf8');
  const pkg = buildTgz({ 'dist/main.js': mainJs });
  const manifest = {
    schema_version: 'xhub.skill_manifest.v1',
    skill_id: skillId,
    name: skillId,
    version: '1.0.0',
    description: 'test skill',
    entrypoint: { runtime: 'node', command: 'node', args: ['dist/main.js'] },
    capabilities_required: ['repo.read.status'],
    files: [{ path: 'dist/main.js', sha256: sha256Hex(mainJs) }],
    publisher: { publisher_id: 'local.dev' },
  };
  return withEnv({ HUB_SKILLS_DEVELOPER_MODE: '1' }, () =>
    uploadSkillPackage(runtimeBaseDir, {
      packageBytes: pkg,
      manifestJson: JSON.stringify(manifest),
      sourceId: 'local:upload',
    })
  );
}

run('agent staged import writes staged record and governance paths expose dirs', () => {
  const runtime = tmpDir('stage');
  const result = stageAgentImport(runtime, {
    importManifestJson: JSON.stringify(sampleImportManifest()),
    findingsJson: JSON.stringify([{ code: 'note_only', detail: 'manual review suggested' }]),
    scanInputJson: JSON.stringify(sampleScanInput()),
    requestedBy: 'xt-supervisor',
    note: 'stage for review',
  });

  assert.equal(String(result.status || ''), 'staged');
  assert.equal(String(result.vetter_status || ''), 'passed');
  const record = getAgentImportRecord(runtime, result.staging_id);
  assert.ok(record);
  assert.equal(String(record.status || ''), 'staged');
  assert.equal(String(record.vetter_status || ''), 'passed');
  assert.equal(String(record.schema_version || ''), 'xhub.agent_import_record.v1');
  assert.equal(String(record.import_manifest.skill_id || ''), 'repo.git.status');
  assert.equal(String(record.import_manifest.schema_version || ''), 'xt.agent_skill_import_manifest.v1');
  assert.equal(String(record.import_manifest.source || ''), 'agent');
  assert.equal(Array.isArray(record.findings) ? record.findings.length : 0, 1);

  const paths = skillsGovernanceSnapshotPaths(runtime);
  assert.ok(fs.existsSync(String(paths.agent_imports.staging_dir || '')));
  assert.ok(fs.existsSync(String(paths.agent_imports.mirror_dir || '')));
  assert.ok(fs.existsSync(String(paths.agent_imports.reports_dir || '')));
  assert.ok(fs.existsSync(String(result.record_path || '')));
  assert.ok(fs.existsSync(String(record.vetter_report_ref || '')));
});

run('legacy upstream import manifest is normalized into agent staging', () => {
  const runtime = tmpDir('legacy');
  const result = stageAgentImport(runtime, {
    importManifestJson: JSON.stringify(sampleImportManifest({
      schemaVersion: 'xt.openclaw_skill_import_manifest.v1',
      source: 'openclaw',
    })),
    scanInputJson: JSON.stringify(sampleScanInput()),
    requestedBy: 'xt-supervisor',
  });

  const record = getAgentImportRecord(runtime, result.staging_id);
  assert.ok(record);
  assert.equal(String(record.import_manifest.schema_version || ''), 'xt.agent_skill_import_manifest.v1');
  assert.equal(String(record.import_manifest.source || ''), 'agent');
  assert.equal(String(record.vetter_status || ''), 'passed');
});

run('quarantined agent import is written to quarantine and cannot be promoted', () => {
  const runtime = tmpDir('quarantine');
  const result = stageAgentImport(runtime, {
    importManifestJson: JSON.stringify(sampleImportManifest({ preflightStatus: 'quarantined' })),
    findingsJson: JSON.stringify([{ code: 'unsafe_upstream_behavior', detail: 'prompt mutation detected' }]),
    requestedBy: 'xt-supervisor',
  });

  assert.equal(String(result.status || ''), 'quarantined');
  const record = getAgentImportRecord(runtime, result.staging_id);
  assert.ok(record);
  assert.equal(String(record.status || ''), 'quarantined');
  assert.ok(String(result.record_path || '').includes('/quarantine/'));

  expectDeny(() =>
    promoteAgentImport(runtime, {
      stagingId: result.staging_id,
      packageSha256: 'a'.repeat(64),
      userId: 'u-demo',
      projectId: 'project-demo',
    }), 'agent_import_quarantined');
});

run('promote agent import repins matching package into project scope', () => {
  const runtime = tmpDir('promote');
  const upload = uploadLowRiskPackage(runtime, 'repo.git.status');
  const staged = stageAgentImport(runtime, {
    importManifestJson: JSON.stringify(sampleImportManifest({ skillId: 'repo.git.status', policyScope: 'project' })),
    scanInputJson: JSON.stringify(sampleScanInput()),
    requestedBy: 'xt-supervisor',
    note: 'promote me',
  });

  const promoted = promoteAgentImport(runtime, {
    stagingId: staged.staging_id,
    packageSha256: String(upload.package_sha256 || ''),
    userId: 'u-demo',
    projectId: 'project-demo',
    note: 'enable project skill',
  });

  assert.equal(String(promoted.status || ''), 'enabled');
  assert.equal(String(promoted.scope || ''), 'SKILL_PIN_SCOPE_PROJECT');
  const record = getAgentImportRecord(runtime, staged.staging_id);
  assert.ok(record);
  assert.equal(String(record.status || ''), 'enabled');
  assert.equal(String(record.enabled_package_sha256 || ''), String(upload.package_sha256 || ''));

  const repin = setSkillPin(runtime, {
    scope: 'SKILL_PIN_SCOPE_PROJECT',
    userId: 'u-demo',
    projectId: 'project-demo',
    skillId: 'repo.git.status',
    packageSha256: String(upload.package_sha256 || ''),
    note: 'idempotent check',
  });
  assert.equal(String(repin.package_sha256 || ''), String(upload.package_sha256 || ''));
});

run('promote agent import fails closed when staged skill does not match package skill', () => {
  const runtime = tmpDir('mismatch');
  const upload = uploadLowRiskPackage(runtime, 'repo.git.status');
  const staged = stageAgentImport(runtime, {
    importManifestJson: JSON.stringify(sampleImportManifest({ skillId: 'repo.test.run' })),
    scanInputJson: JSON.stringify(sampleScanInput()),
    requestedBy: 'xt-supervisor',
  });

  expectDeny(() =>
    promoteAgentImport(runtime, {
      stagingId: staged.staging_id,
      packageSha256: String(upload.package_sha256 || ''),
      userId: 'u-demo',
      projectId: 'project-demo',
    }), 'staged_skill_package_mismatch');
});

run('promote agent import blocks when hub vetter input is missing', () => {
  const runtime = tmpDir('pending');
  const upload = uploadLowRiskPackage(runtime, 'repo.git.status');
  const staged = stageAgentImport(runtime, {
    importManifestJson: JSON.stringify(sampleImportManifest({ skillId: 'repo.git.status' })),
    requestedBy: 'xt-supervisor',
  });

  assert.equal(String(staged.status || ''), 'staged');
  assert.equal(String(staged.vetter_status || ''), 'pending');

  expectDeny(() =>
    promoteAgentImport(runtime, {
      stagingId: staged.staging_id,
      packageSha256: String(upload.package_sha256 || ''),
      userId: 'u-demo',
      projectId: 'project-demo',
    }), 'agent_import_vetter_pending');
});

run('critical hub vetter findings quarantine import and block promote', () => {
  const runtime = tmpDir('critical');
  const upload = uploadLowRiskPackage(runtime, 'repo.git.status');
  const staged = stageAgentImport(runtime, {
    importManifestJson: JSON.stringify(sampleImportManifest({ skillId: 'repo.git.status' })),
    scanInputJson: JSON.stringify(sampleScanInput({
      mainJS: [
        'import { exec } from "child_process";',
        'exec("whoami");',
      ].join('\n'),
    })),
    requestedBy: 'xt-supervisor',
  });

  assert.equal(String(staged.status || ''), 'quarantined');
  assert.equal(String(staged.vetter_status || ''), 'critical');
  assert.equal(Number(staged.vetter_critical_count || 0) > 0, true);

  expectDeny(() =>
    promoteAgentImport(runtime, {
      stagingId: staged.staging_id,
      packageSha256: String(upload.package_sha256 || ''),
      userId: 'u-demo',
      projectId: 'project-demo',
    }), 'agent_import_quarantined');
});
