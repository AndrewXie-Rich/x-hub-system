import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';

import {
  evaluateSkillExecutionGate,
  getSkillManifest,
  normalizeSkillStoreError,
  readSkillPackage,
  resolveSkillsWithTrace,
  setSkillPin,
  skillsGovernanceSnapshotPaths,
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
  for (const [k, v] of Object.entries(tempEnv || {})) {
    prev.set(k, process.env[k]);
    if (v == null) delete process.env[k];
    else process.env[k] = String(v);
  }
  try {
    return fn();
  } finally {
    for (const [k, v] of prev.entries()) {
      if (v == null) delete process.env[k];
      else process.env[k] = v;
    }
  }
}

function tmpDir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `hub_skills_${label}_`));
}

function sha256Hex(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function toCanonical(v) {
  if (Array.isArray(v)) return v.map((it) => toCanonical(it));
  if (!v || typeof v !== 'object') return v;
  const out = {};
  for (const key of Object.keys(v).sort()) {
    out[key] = toCanonical(v[key]);
  }
  return out;
}

function canonicalManifestBytes(manifestObj) {
  const plain = manifestObj && typeof manifestObj === 'object' ? { ...manifestObj } : {};
  delete plain.signature;
  return Buffer.from(JSON.stringify(toCanonical(plain)), 'utf8');
}

function fromBase64Url(text) {
  const raw = String(text || '').replace(/-/g, '+').replace(/_/g, '/');
  const padded = raw.padEnd(Math.ceil(raw.length / 4) * 4, '=');
  return Buffer.from(padded, 'base64');
}

function makePublisher(publisherId = 'publisher.test') {
  const pair = crypto.generateKeyPairSync('ed25519');
  const jwk = pair.publicKey.export({ format: 'jwk' });
  const rawPublic = fromBase64Url(String(jwk.x || ''));
  return {
    publisher_id: publisherId,
    public_key_ed25519: `base64:${rawPublic.toString('base64')}`,
    private_key: pair.privateKey,
  };
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
  header.fill(0x20, 148, 156); // checksum bytes must be spaces during sum
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
  const entries = Object.entries(filesByPath || {});
  const chunks = [];
  for (const [name, body] of entries) {
    const data = Buffer.isBuffer(body) ? body : Buffer.from(String(body || ''), 'utf8');
    chunks.push(writeTarHeader(name, data.length));
    chunks.push(data);
    const pad = (512 - (data.length % 512)) % 512;
    if (pad > 0) chunks.push(Buffer.alloc(pad, 0));
  }
  chunks.push(Buffer.alloc(1024, 0));
  return zlib.gzipSync(Buffer.concat(chunks));
}

function buildSignedManifest({
  skillId,
  version,
  publisher,
  fileHashes,
  capabilities = [],
  withSignature = true,
}) {
  const manifest = {
    schema_version: 'xhub.skill_manifest.v1',
    skill_id: String(skillId || ''),
    name: String(skillId || ''),
    version: String(version || ''),
    description: 'test skill',
    entrypoint: {
      runtime: 'node',
      command: 'node',
      args: ['dist/main.js'],
    },
    capabilities_required: Array.isArray(capabilities) ? capabilities : [],
    network_policy: { direct_network_forbidden: true },
    files: Object.entries(fileHashes || {}).map(([p, h]) => ({
      path: p,
      sha256: h,
    })),
    publisher: {
      publisher_id: String(publisher?.publisher_id || ''),
      public_key_ed25519: String(publisher?.public_key_ed25519 || ''),
    },
  };
  if (!withSignature) return manifest;
  const sig = crypto.sign(null, canonicalManifestBytes(manifest), publisher.private_key);
  return {
    ...manifest,
    signature: {
      alg: 'ed25519',
      sig: `base64:${sig.toString('base64')}`,
    },
  };
}

function writeTrustedPublishers(runtimeBaseDir, publisher) {
  const dir = path.join(runtimeBaseDir, 'skills_store');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'trusted_publishers.json'),
    `${JSON.stringify({
      schema_version: 'xhub.trusted_publishers.v1',
      updated_at_ms: Date.now(),
      publishers: [
        {
          publisher_id: publisher.publisher_id,
          public_key_ed25519: publisher.public_key_ed25519,
          enabled: true,
        },
      ],
    }, null, 2)}\n`,
    'utf8'
  );
}

function writeRevocations(runtimeBaseDir, { revokedSha = [], revokedSkills = [] } = {}) {
  const dir = path.join(runtimeBaseDir, 'skills_store');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'revoked.json'),
    `${JSON.stringify({
      schema_version: 'xhub.skill_revocations.v1',
      updated_at_ms: Date.now(),
      revoked_sha256: revokedSha,
      revoked_skill_ids: revokedSkills,
      revoked_publishers: [],
    }, null, 2)}\n`,
    'utf8'
  );
}

function expectDeny(fn, code) {
  let failed = false;
  try {
    fn();
  } catch (err) {
    failed = true;
    const normalized = normalizeSkillStoreError(err, 'runtime_error');
    assert.equal(String(normalized.code || ''), String(code || ''), `expected deny_code=${code}, got=${normalized.code}`);
  }
  if (!failed) {
    assert.fail(`expected deny_code=${code} but call succeeded`);
  }
}

run('SKC-W1-03/signature tamper -> deny(signature_invalid)', () => {
  const runtime = tmpDir('sig_tamper');
  const publisher = makePublisher('publisher.sig.tamper');
  writeTrustedPublishers(runtime, publisher);

  const mainJs = Buffer.from('console.log("hello");\n', 'utf8');
  const pkg = buildTgz({ 'dist/main.js': mainJs });
  const manifest = buildSignedManifest({
    skillId: 'skill.sig.tamper',
    version: '1.0.0',
    publisher,
    capabilities: ['connectors.email'],
    fileHashes: {
      'dist/main.js': sha256Hex(mainJs),
    },
  });
  // Deterministically tamper signature bytes; regex replacement can be a no-op.
  const sigBytes = Buffer.from(String(manifest.signature.sig || '').replace(/^base64:/, ''), 'base64');
  sigBytes[0] ^= 0x01;
  manifest.signature.sig = `base64:${sigBytes.toString('base64')}`;

  expectDeny(() => {
    uploadSkillPackage(runtime, {
      packageBytes: pkg,
      manifestJson: JSON.stringify(manifest),
      sourceId: 'local:upload',
    });
  }, 'signature_invalid');
});

run('SKC-W1-03/file hash drift -> deny(hash_mismatch)', () => {
  const runtime = tmpDir('hash_mismatch');
  const publisher = makePublisher('publisher.hash.mismatch');
  writeTrustedPublishers(runtime, publisher);

  const baseJs = Buffer.from('console.log("base");\n', 'utf8');
  const driftJs = Buffer.from('console.log("drift");\n', 'utf8');
  const pkg = buildTgz({ 'dist/main.js': driftJs });
  const manifest = buildSignedManifest({
    skillId: 'skill.hash.mismatch',
    version: '1.0.0',
    publisher,
    capabilities: ['connectors.email'],
    fileHashes: {
      'dist/main.js': sha256Hex(baseJs),
    },
  });

  expectDeny(() => {
    uploadSkillPackage(runtime, {
      packageBytes: pkg,
      manifestJson: JSON.stringify(manifest),
      sourceId: 'local:upload',
    });
  }, 'hash_mismatch');
});

run('SKC-W1-03/unsigned high-risk is denied even in developer_mode; low-risk can bypass in developer_mode', () => {
  const runtime = tmpDir('developer_mode');

  const highRiskJs = Buffer.from('console.log("high");\n', 'utf8');
  const lowRiskJs = Buffer.from('console.log("low");\n', 'utf8');
  const highPkg = buildTgz({ 'dist/main.js': highRiskJs });
  const lowPkg = buildTgz({ 'dist/main.js': lowRiskJs });
  const devPublisher = {
    publisher_id: 'publisher.dev.local',
    public_key_ed25519: '',
    private_key: null,
  };

  const unsignedHigh = buildSignedManifest({
    skillId: 'skill.high.unsigned',
    version: '1.0.0',
    publisher: devPublisher,
    capabilities: ['connectors.email'],
    fileHashes: { 'dist/main.js': sha256Hex(highRiskJs) },
    withSignature: false,
  });
  const unsignedLow = buildSignedManifest({
    skillId: 'skill.low.unsigned',
    version: '1.0.0',
    publisher: devPublisher,
    capabilities: [],
    fileHashes: { 'dist/main.js': sha256Hex(lowRiskJs) },
    withSignature: false,
  });

  withEnv({ HUB_SKILLS_DEVELOPER_MODE: '1' }, () => {
    expectDeny(() => {
      uploadSkillPackage(runtime, {
        packageBytes: highPkg,
        manifestJson: JSON.stringify(unsignedHigh),
        sourceId: 'local:upload',
      });
    }, 'signature_missing');

    const out = uploadSkillPackage(runtime, {
      packageBytes: lowPkg,
      manifestJson: JSON.stringify(unsignedLow),
      sourceId: 'local:upload',
    });
    assert.equal(!!out?.security?.signature?.signature_bypassed, true);
  });
});

run('SKC-W1-04/revoked blocks hub download and runner execute; pin resolution is deterministic fail-closed', () => {
  const runtime = tmpDir('revocation');
  const publisher = makePublisher('publisher.revocation');
  writeTrustedPublishers(runtime, publisher);

  const v1Js = Buffer.from('console.log("v1");\n', 'utf8');
  const v2Js = Buffer.from('console.log("v2");\n', 'utf8');
  const pkgV1 = buildTgz({ 'dist/main.js': v1Js });
  const pkgV2 = buildTgz({ 'dist/main.js': v2Js });
  const manifestV1 = buildSignedManifest({
    skillId: 'skill.revocation.demo',
    version: '1.0.0',
    publisher,
    capabilities: ['connectors.email'],
    fileHashes: { 'dist/main.js': sha256Hex(v1Js) },
  });
  const manifestV2 = buildSignedManifest({
    skillId: 'skill.revocation.demo',
    version: '2.0.0',
    publisher,
    capabilities: ['connectors.email'],
    fileHashes: { 'dist/main.js': sha256Hex(v2Js) },
  });

  const up1 = uploadSkillPackage(runtime, {
    packageBytes: pkgV1,
    manifestJson: JSON.stringify(manifestV1),
    sourceId: 'local:upload',
  });
  const up2 = uploadSkillPackage(runtime, {
    packageBytes: pkgV2,
    manifestJson: JSON.stringify(manifestV2),
    sourceId: 'local:upload',
  });

  setSkillPin(runtime, {
    scope: 'SKILL_PIN_SCOPE_GLOBAL',
    userId: 'user-1',
    projectId: '',
    skillId: 'skill.revocation.demo',
    packageSha256: up1.package_sha256,
    note: 'global',
  });
  setSkillPin(runtime, {
    scope: 'SKILL_PIN_SCOPE_PROJECT',
    userId: 'user-1',
    projectId: 'proj-1',
    skillId: 'skill.revocation.demo',
    packageSha256: up2.package_sha256,
    note: 'project',
  });

  const before = resolveSkillsWithTrace(runtime, { userId: 'user-1', projectId: 'proj-1' });
  assert.equal(before.resolved.length, 1);
  assert.equal(String(before.resolved[0]?.skill?.package_sha256 || ''), String(up1.package_sha256 || ''));

  writeRevocations(runtime, { revokedSha: [String(up1.package_sha256 || '')] });

  const afterA = resolveSkillsWithTrace(runtime, { userId: 'user-1', projectId: 'proj-1' });
  const afterB = resolveSkillsWithTrace(runtime, { userId: 'user-1', projectId: 'proj-1' });
  assert.deepEqual(afterA, afterB, 'pin resolution must be deterministic');
  assert.equal(afterA.resolved.length, 0, 'revoked winner should fail-closed (no fallback to lower scope)');
  assert.equal(afterA.blocked.length, 1);
  assert.equal(String(afterA.blocked[0]?.deny_code || ''), 'revoked');

  expectDeny(() => getSkillManifest(runtime, up1.package_sha256), 'revoked');
  expectDeny(() => readSkillPackage(runtime, up1.package_sha256), 'revoked');

  const gate = evaluateSkillExecutionGate(runtime, {
    packageSha256: up1.package_sha256,
    packageBytes: pkgV1,
    manifestJson: JSON.stringify(manifestV1),
    skillId: 'skill.revocation.demo',
  });
  assert.equal(!!gate.allowed, false);
  assert.equal(String(gate.deny_code || ''), 'revoked');

  const rollbackPaths = skillsGovernanceSnapshotPaths(runtime);
  assert.ok(rollbackPaths?.pins?.previous_stable, 'expected rollback snapshot path');
  assert.ok(fs.existsSync(String(rollbackPaths.pins.previous_stable || '')), 'expected pins stable snapshot file');
});

run('SKC-W1-04/three-layer pin conflict resolves deterministically and revocation does not fallback across layers', () => {
  const runtime = tmpDir('three_layer_conflict');
  const publisher = makePublisher('publisher.three.layer');
  writeTrustedPublishers(runtime, publisher);

  const coreJs = Buffer.from('console.log("core");\n', 'utf8');
  const globalJs = Buffer.from('console.log("global");\n', 'utf8');
  const projectJs = Buffer.from('console.log("project");\n', 'utf8');
  const upCore = uploadSkillPackage(runtime, {
    packageBytes: buildTgz({ 'dist/main.js': coreJs }),
    manifestJson: JSON.stringify(buildSignedManifest({
      skillId: 'skill.layered.demo',
      version: '3.0.0',
      publisher,
      capabilities: ['connectors.email'],
      fileHashes: { 'dist/main.js': sha256Hex(coreJs) },
    })),
    sourceId: 'local:upload',
  });
  const upGlobal = uploadSkillPackage(runtime, {
    packageBytes: buildTgz({ 'dist/main.js': globalJs }),
    manifestJson: JSON.stringify(buildSignedManifest({
      skillId: 'skill.layered.demo',
      version: '2.0.0',
      publisher,
      capabilities: ['connectors.email'],
      fileHashes: { 'dist/main.js': sha256Hex(globalJs) },
    })),
    sourceId: 'local:upload',
  });
  const upProject = uploadSkillPackage(runtime, {
    packageBytes: buildTgz({ 'dist/main.js': projectJs }),
    manifestJson: JSON.stringify(buildSignedManifest({
      skillId: 'skill.layered.demo',
      version: '1.0.0',
      publisher,
      capabilities: ['connectors.email'],
      fileHashes: { 'dist/main.js': sha256Hex(projectJs) },
    })),
    sourceId: 'local:upload',
  });

  setSkillPin(runtime, {
    scope: 'SKILL_PIN_SCOPE_GLOBAL',
    userId: 'user-layer',
    projectId: '',
    skillId: 'skill.layered.demo',
    packageSha256: upGlobal.package_sha256,
    note: 'global',
  });
  setSkillPin(runtime, {
    scope: 'SKILL_PIN_SCOPE_PROJECT',
    userId: 'user-layer',
    projectId: 'proj-layer',
    skillId: 'skill.layered.demo',
    packageSha256: upProject.package_sha256,
    note: 'project',
  });

  // Inject memory-core pin as a system-layer pin (setSkillPin intentionally reserves this scope).
  const pinsPath = path.join(runtime, 'skills_store', 'skills_pins.json');
  const pins = JSON.parse(fs.readFileSync(pinsPath, 'utf8'));
  pins.memory_core_pins = [
    {
      scope: 'SKILL_PIN_SCOPE_MEMORY_CORE',
      skill_id: 'skill.layered.demo',
      package_sha256: String(upCore.package_sha256 || ''),
      note: 'memory_core',
      updated_at_ms: Date.now(),
    },
  ];
  fs.writeFileSync(pinsPath, `${JSON.stringify(pins, null, 2)}\n`, 'utf8');

  const resolvedA = resolveSkillsWithTrace(runtime, { userId: 'user-layer', projectId: 'proj-layer' });
  const resolvedB = resolveSkillsWithTrace(runtime, { userId: 'user-layer', projectId: 'proj-layer' });
  assert.deepEqual(resolvedA, resolvedB);
  assert.equal(resolvedA.resolved.length, 1);
  assert.equal(String(resolvedA.resolved[0]?.scope || ''), 'SKILL_PIN_SCOPE_MEMORY_CORE');
  assert.equal(String(resolvedA.resolved[0]?.skill?.package_sha256 || ''), String(upCore.package_sha256 || ''));

  writeRevocations(runtime, { revokedSha: [String(upCore.package_sha256 || '')] });
  const blocked = resolveSkillsWithTrace(runtime, { userId: 'user-layer', projectId: 'proj-layer' });
  assert.equal(blocked.resolved.length, 0);
  assert.equal(blocked.blocked.length, 1);
  assert.equal(String(blocked.blocked[0]?.deny_code || ''), 'revoked');
  // Fail-closed: do not fallback to global/project when memory-core winner is revoked.
  assert.equal(String(blocked.blocked[0]?.scope || ''), 'SKILL_PIN_SCOPE_MEMORY_CORE');
});
