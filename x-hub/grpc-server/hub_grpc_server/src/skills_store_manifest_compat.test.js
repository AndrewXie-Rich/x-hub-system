import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';

import {
  loadSkillsIndex,
  normalizeCompatibleSkillManifest,
  setSkillPin,
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

function makeTmpDir(label) {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const dir = path.join(os.tmpdir(), `xhub_skills_store_${token}`);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function cleanupDir(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch {
    // ignore
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

run('missing entrypoint rejects with invalid_manifest', () => {
  assert.throws(
    () => normalizeCompatibleSkillManifest({ skill_id: 'demo.skill', version: '1.0.0' }, { sourceId: 'local:upload' }),
    /invalid_manifest: missing entrypoint\.command/
  );
});

run('legacy aliases map into canonical fields with alias audit markers', () => {
  const mapped = normalizeCompatibleSkillManifest(
    {
      id: 'legacy.alias.skill',
      skill_version: '0.3.2',
      title: 'Legacy Alias Skill',
      summary: 'legacy description',
      main: 'dist/index.js',
      capabilities: ['web.fetch'],
      publisher_id: 'legacy.publisher',
    },
    { sourceId: 'local:upload' }
  );

  assert.equal(String(mapped.skill.skill_id || ''), 'legacy.alias.skill');
  assert.equal(String(mapped.skill.version || ''), '0.3.2');
  assert.equal(String(mapped.skill.name || ''), 'Legacy Alias Skill');
  assert.equal(String(mapped.skill.description || ''), 'legacy description');
  assert.equal(String(mapped.skill.entrypoint_command || ''), 'dist/index.js');
  assert.equal(String(mapped.skill.publisher_id || ''), 'legacy.publisher');
  assert.deepEqual(mapped.skill.capabilities_required, ['web.fetch']);
  assert.equal(String(mapped.compatibility_state || ''), 'partial');

  assert.ok(Array.isArray(mapped.mapping_aliases_used));
  assert.ok(mapped.mapping_aliases_used.includes('skill_id<-id'));
  assert.ok(mapped.mapping_aliases_used.includes('version<-skill_version'));
  assert.ok(mapped.mapping_aliases_used.includes('entrypoint.command<-main'));
  assert.ok(Array.isArray(mapped.defaults_applied));
  assert.ok(mapped.defaults_applied.includes('network_policy.direct_network_forbidden'));
});

run('duplicate upload is deduped and repeated pin is idempotent', () => {
  const runtimeBaseDir = makeTmpDir('dedup_pin');
  try {
    const entryBytes = Buffer.from('console.log("dedup");\n', 'utf8');
    const packageBytes = buildTgz({ 'dist/main.js': entryBytes });
    const manifest = {
      schema_version: 'xhub.skill_manifest.v1',
      skill_id: 'dedup.skill',
      version: '1.0.0',
      entrypoint: { runtime: 'node', command: 'node', args: ['dist/main.js'] },
      files: [{ path: 'dist/main.js', sha256: sha256Hex(entryBytes) }],
      publisher: { publisher_id: 'local.dev' },
    };
    const manifestJson = JSON.stringify(manifest);

    withEnv({ HUB_SKILLS_DEVELOPER_MODE: '1' }, () => {
      const first = uploadSkillPackage(runtimeBaseDir, {
        packageBytes,
        manifestJson,
        sourceId: 'local:upload',
      });
      const second = uploadSkillPackage(runtimeBaseDir, {
        packageBytes,
        manifestJson,
        sourceId: 'local:upload',
      });

      assert.equal(first.already_present, false);
      assert.equal(second.already_present, true);
      assert.equal(String(first.package_sha256 || ''), String(second.package_sha256 || ''));

      const firstPin = setSkillPin(runtimeBaseDir, {
        scope: 'SKILL_PIN_SCOPE_GLOBAL',
        userId: 'u-demo',
        projectId: '',
        skillId: 'dedup.skill',
        packageSha256: String(first.package_sha256 || ''),
        note: 'initial pin',
      });
      const secondPin = setSkillPin(runtimeBaseDir, {
        scope: 'SKILL_PIN_SCOPE_GLOBAL',
        userId: 'u-demo',
        projectId: '',
        skillId: 'dedup.skill',
        packageSha256: String(first.package_sha256 || ''),
        note: 'idempotent pin',
      });

      assert.equal(String(firstPin.package_sha256 || ''), String(secondPin.package_sha256 || ''));
      assert.equal(String(secondPin.previous_package_sha256 || ''), String(first.package_sha256 || ''));

      const idx = loadSkillsIndex(runtimeBaseDir);
      const skills = Array.isArray(idx.skills) ? idx.skills.filter((s) => String(s.skill_id || '') === 'dedup.skill') : [];
      assert.equal(skills.length, 1);
    });
  } finally {
    cleanupDir(runtimeBaseDir);
  }
});

run('source outside allowlist is fail-closed', () => {
  const runtimeBaseDir = makeTmpDir('source_gate');
  try {
    assert.throws(
      () =>
        uploadSkillPackage(runtimeBaseDir, {
          packageBytes: Buffer.from('x', 'utf8'),
          manifestJson: JSON.stringify({
            skill_id: 'source.gate.skill',
            version: '1.0.0',
            entrypoint: { command: 'node' },
          }),
          sourceId: 'github:vercel-labs/skills',
        }),
      /source_not_allowlisted/
    );
  } finally {
    cleanupDir(runtimeBaseDir);
  }
});
