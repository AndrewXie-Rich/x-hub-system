import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {
  deriveSkillCapabilitySemantics,
  validateSkillCapabilityHints,
} from './skill_capability_derivation.js';

const CHANNEL_STATE_SCHEMA_VERSION = 'xhub.official_skill_channel_state.v1';
const DEFAULT_CHANNEL_ID = 'official-stable';

function safeString(value) {
  return String(value == null ? '' : value).trim();
}

function isObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function readJsonSafe(filePath) {
  try {
    return JSON.parse(fs.readFileSync(String(filePath || ''), 'utf8'));
  } catch {
    return null;
  }
}

function writeJsonAtomic(filePath, obj) {
  const fp = safeString(filePath);
  if (!fp) return false;
  try {
    fs.mkdirSync(path.dirname(fp), { recursive: true });
  } catch {
    // ignore
  }
  const tmp = `${fp}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  try {
    fs.writeFileSync(tmp, `${JSON.stringify(obj, null, 2)}\n`, 'utf8');
    fs.renameSync(tmp, fp);
    return true;
  } catch {
    try {
      fs.unlinkSync(tmp);
    } catch {
      // ignore
    }
    return false;
  }
}

function sha256Hex(data) {
  return crypto.createHash('sha256').update(data).digest('hex');
}

function safeRealpath(filePath) {
  try {
    if (typeof fs.realpathSync?.native === 'function') {
      return fs.realpathSync.native(String(filePath || ''));
    }
    return fs.realpathSync(String(filePath || ''));
  } catch {
    return '';
  }
}

function isPathInsideRoot(rootDir, targetPath) {
  const rootReal = safeRealpath(rootDir);
  const targetReal = safeRealpath(targetPath);
  if (!rootReal || !targetReal) return false;
  if (rootReal === targetReal) return true;
  const relative = path.relative(rootReal, targetReal);
  if (!relative) return true;
  if (relative.startsWith('..')) return false;
  if (path.isAbsolute(relative)) return false;
  return true;
}

function resolveExistingPathWithinRoot(rootDir, relativeOrAbsolutePath) {
  const candidate = safeString(relativeOrAbsolutePath);
  if (!candidate) return '';
  const resolved = path.resolve(rootDir, candidate);
  if (!isPathInsideRoot(rootDir, resolved)) return '';
  if (!fs.existsSync(resolved)) return '';
  return resolved;
}

function normalizeChannelId(input) {
  const raw = safeString(input || DEFAULT_CHANNEL_ID).toLowerCase();
  const cleaned = raw.replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '');
  return cleaned || DEFAULT_CHANNEL_ID;
}

function nowMs() {
  return Date.now();
}

function skillsStoreOfficialChannelsDir(runtimeBaseDir) {
  const runtime = safeString(runtimeBaseDir);
  if (!runtime) return '';
  return path.join(runtime, 'skills_store', 'official_channels');
}

function officialSkillChannelDir(runtimeBaseDir, { channelId = DEFAULT_CHANNEL_ID } = {}) {
  const baseDir = skillsStoreOfficialChannelsDir(runtimeBaseDir);
  if (!baseDir) return '';
  return path.join(baseDir, normalizeChannelId(channelId));
}

function officialSkillChannelStatePath(runtimeBaseDir, { channelId = DEFAULT_CHANNEL_ID } = {}) {
  const dir = officialSkillChannelDir(runtimeBaseDir, { channelId });
  if (!dir) return '';
  return path.join(dir, 'channel_state.json');
}

function officialSkillChannelCurrentDir(runtimeBaseDir, { channelId = DEFAULT_CHANNEL_ID } = {}) {
  const dir = officialSkillChannelDir(runtimeBaseDir, { channelId });
  if (!dir) return '';
  return path.join(dir, 'current');
}

function officialSkillChannelLastKnownGoodDir(runtimeBaseDir, { channelId = DEFAULT_CHANNEL_ID } = {}) {
  const dir = officialSkillChannelDir(runtimeBaseDir, { channelId });
  if (!dir) return '';
  return path.join(dir, 'last_known_good');
}

function hasRequiredSnapshotArtifacts(snapshotDir) {
  const root = safeString(snapshotDir);
  if (!root || !fs.existsSync(root)) return false;
  return (
    fs.existsSync(path.join(root, 'index.json'))
    && fs.existsSync(path.join(root, 'trusted_publishers.json'))
  );
}

function normalizeTrustedPublishers(input) {
  const obj = isObject(input) ? input : {};
  const publishers = Array.isArray(obj.publishers)
    ? obj.publishers.map((publisher) => ({
      publisher_id: safeString(publisher?.publisher_id || publisher?.id),
      public_key_ed25519: safeString(publisher?.public_key_ed25519),
      enabled: publisher?.enabled !== false,
    })).filter((publisher) => publisher.publisher_id)
    : [];
  return {
    schema_version: safeString(obj.schema_version || 'xhub.trusted_publishers.v1') || 'xhub.trusted_publishers.v1',
    updated_at_ms: Math.max(0, Number(obj.updated_at_ms || 0)),
    publishers,
  };
}

function normalizeRevocations(input) {
  const obj = isObject(input) ? input : {};
  const dedupe = (items, { lowercase = false } = {}) => {
    if (!Array.isArray(items)) return [];
    const seen = new Set();
    const out = [];
    for (const raw of items) {
      const value = lowercase ? safeString(raw).toLowerCase() : safeString(raw);
      if (!value || seen.has(value)) continue;
      seen.add(value);
      out.push(value);
    }
    return out;
  };
  return {
    schema_version: safeString(obj.schema_version || 'xhub.skill_revocations.v1') || 'xhub.skill_revocations.v1',
    updated_at_ms: Math.max(0, Number(obj.updated_at_ms || 0)),
    revoked_sha256: dedupe(obj.revoked_sha256, { lowercase: true }),
    revoked_skill_ids: dedupe(obj.revoked_skill_ids),
    revoked_publishers: dedupe(obj.revoked_publishers),
  };
}

function resolveSourcePublicRoot(sourceRoot) {
  const root = safeString(sourceRoot);
  if (!root) return '';
  const base = path.resolve(root);
  const candidates = [
    base,
    path.join(base, 'dist'),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'index.json'))) return candidate;
  }
  return '';
}

function readRequiredJson(publicRoot, fileName, errorCode) {
  const fp = path.join(publicRoot, fileName);
  const obj = readJsonSafe(fp);
  if (!isObject(obj)) {
    const err = new Error(errorCode);
    err.code = errorCode;
    err.file_path = fp;
    throw err;
  }
  return { file_path: fp, obj };
}

function readOptionalJson(publicRoot, fileNames) {
  for (const name of Array.isArray(fileNames) ? fileNames : []) {
    const fp = path.join(publicRoot, String(name || ''));
    if (!fs.existsSync(fp)) continue;
    const obj = readJsonSafe(fp);
    if (!isObject(obj)) {
      const err = new Error('invalid_optional_json');
      err.code = 'invalid_optional_json';
      err.file_path = fp;
      throw err;
    }
    return { file_name: path.basename(fp), file_path: fp, obj };
  }
  return null;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function buildValidationError(code, detail = {}) {
  const err = new Error(code);
  err.code = code;
  Object.assign(err, detail);
  return err;
}

function validatePublicSnapshot(publicRoot) {
  const indexJson = readRequiredJson(publicRoot, 'index.json', 'missing_index_json');
  const trustedJson = readRequiredJson(publicRoot, 'trusted_publishers.json', 'missing_trusted_publishers_json');
  const catalogJson = readOptionalJson(publicRoot, ['official_catalog_snapshot.json']);
  const revocationsJson = readOptionalJson(publicRoot, ['revocations.json', 'revoked.json']);

  const trusted = normalizeTrustedPublishers(trustedJson.obj);
  const trustedPublisherMap = new Map();
  for (const publisher of trusted.publishers) {
    if (!publisher.enabled) continue;
    trustedPublisherMap.set(publisher.publisher_id, publisher);
  }

  const rows = Array.isArray(indexJson.obj.skills) ? indexJson.obj.skills : [];
  const normalizedSkills = [];
  for (const raw of rows) {
    if (!isObject(raw)) {
      throw buildValidationError('invalid_index_skill_row');
    }
    const skill_id = safeString(raw.skill_id || raw.id);
    const package_sha256 = safeString(raw.package_sha256 || raw.sha256).toLowerCase();
    const manifest_sha256 = safeString(raw.manifest_sha256).toLowerCase();
    if (!skill_id || !/^[0-9a-f]{64}$/.test(package_sha256)) {
      throw buildValidationError('invalid_index_skill_entry', {
        skill_id,
        package_sha256,
      });
    }
    if (manifest_sha256 && !/^[0-9a-f]{64}$/.test(manifest_sha256)) {
      throw buildValidationError('invalid_manifest_sha256', {
        skill_id,
        manifest_sha256,
      });
    }
    const package_fp = resolveExistingPathWithinRoot(publicRoot, raw.package_path);
    const manifest_fp = resolveExistingPathWithinRoot(publicRoot, raw.manifest_path);
    if (!package_fp || !manifest_fp) {
      throw buildValidationError('index_path_outside_public_root', {
        skill_id,
        package_path: safeString(raw.package_path),
        manifest_path: safeString(raw.manifest_path),
      });
    }
    const packageBytes = fs.readFileSync(package_fp);
    const actualPackageSha = sha256Hex(packageBytes);
    if (actualPackageSha !== package_sha256) {
      throw buildValidationError('package_sha256_mismatch', {
        skill_id,
        expected_sha256: package_sha256,
        actual_sha256: actualPackageSha,
      });
    }
    const manifestText = fs.readFileSync(manifest_fp, 'utf8');
    const actualManifestSha = sha256Hex(Buffer.from(manifestText, 'utf8'));
    if (manifest_sha256 && actualManifestSha !== manifest_sha256) {
      throw buildValidationError('manifest_sha256_mismatch', {
        skill_id,
        expected_sha256: manifest_sha256,
        actual_sha256: actualManifestSha,
      });
    }
    let manifestObj = null;
    try {
      manifestObj = JSON.parse(manifestText);
    } catch {
      throw buildValidationError('invalid_manifest_json', {
        skill_id,
        manifest_path: manifest_fp,
      });
    }
    const publisher_id = safeString(
      manifestObj?.publisher?.publisher_id
      || manifestObj?.publisher_id
      || raw.publisher_id
    );
    if (!publisher_id) {
      throw buildValidationError('missing_manifest_publisher', { skill_id });
    }
    if (!trustedPublisherMap.has(publisher_id)) {
      throw buildValidationError('publisher_not_trusted', {
        skill_id,
        publisher_id,
      });
    }
    const derived = deriveSkillCapabilitySemantics({
      ...(isObject(raw) ? raw : {}),
      ...(isObject(manifestObj) ? manifestObj : {}),
      skill_id,
      publisher_id,
      source_id: 'builtin:catalog',
    });
    const hintValidation = validateSkillCapabilityHints({
      ...(isObject(raw) ? raw : {}),
      ...(isObject(manifestObj) ? manifestObj : {}),
      skill_id,
      publisher_id,
      source_id: 'builtin:catalog',
    }, derived);
    if (hintValidation.fail_closed) {
      throw buildValidationError('profile_hint_mismatch', {
        skill_id,
        mismatches: hintValidation.mismatches,
      });
    }
    normalizedSkills.push({
      row: {
        ...cloneJson(raw),
        package_sha256,
        manifest_sha256: manifest_sha256 || actualManifestSha,
        package_path: path.relative(publicRoot, package_fp).split(path.sep).join('/'),
        manifest_path: path.relative(publicRoot, manifest_fp).split(path.sep).join('/'),
        publisher_id: safeString(raw.publisher_id || publisher_id) || publisher_id,
        intent_families: derived.intent_families,
        capability_families: derived.capability_families,
        capability_profiles: derived.capability_profiles,
        grant_floor: derived.grant_floor,
        approval_floor: derived.approval_floor,
      },
      package_fp,
      manifest_fp,
    });
  }

  const normalizedIndex = {
    ...cloneJson(indexJson.obj),
    schema_version: safeString(indexJson.obj.schema_version || 'xhub.official_agent_skill_index.v1') || 'xhub.official_agent_skill_index.v1',
    skills: normalizedSkills.map((entry) => entry.row),
  };

  return {
    public_root: publicRoot,
    normalized_index: normalizedIndex,
    trusted_publishers: trusted,
    revocations: revocationsJson ? normalizeRevocations(revocationsJson.obj) : null,
    catalog_snapshot: catalogJson ? cloneJson(catalogJson.obj) : null,
    skills: normalizedSkills,
  };
}

function writePreparedSnapshot(preparedDir, validated) {
  fs.mkdirSync(preparedDir, { recursive: true });
  fs.writeFileSync(path.join(preparedDir, 'index.json'), `${JSON.stringify(validated.normalized_index, null, 2)}\n`, 'utf8');
  fs.writeFileSync(path.join(preparedDir, 'trusted_publishers.json'), `${JSON.stringify(validated.trusted_publishers, null, 2)}\n`, 'utf8');
  if (validated.catalog_snapshot) {
    fs.writeFileSync(path.join(preparedDir, 'official_catalog_snapshot.json'), `${JSON.stringify(validated.catalog_snapshot, null, 2)}\n`, 'utf8');
  }
  if (validated.revocations) {
    fs.writeFileSync(path.join(preparedDir, 'revocations.json'), `${JSON.stringify(validated.revocations, null, 2)}\n`, 'utf8');
  }
  for (const skill of validated.skills) {
    const packageDst = path.resolve(preparedDir, skill.row.package_path);
    const manifestDst = path.resolve(preparedDir, skill.row.manifest_path);
    fs.mkdirSync(path.dirname(packageDst), { recursive: true });
    fs.mkdirSync(path.dirname(manifestDst), { recursive: true });
    fs.copyFileSync(skill.package_fp, packageDst);
    fs.copyFileSync(skill.manifest_fp, manifestDst);
  }
}

function swapDirectory(preparedDir, targetDir) {
  const prepared = safeString(preparedDir);
  const target = safeString(targetDir);
  if (!prepared || !target) return;
  const backup = `${target}.bak_${process.pid}_${Math.random().toString(16).slice(2)}`;
  let movedExisting = false;
  try {
    if (fs.existsSync(target)) {
      fs.renameSync(target, backup);
      movedExisting = true;
    }
    fs.renameSync(prepared, target);
    if (movedExisting) {
      fs.rmSync(backup, { recursive: true, force: true });
    }
  } catch (err) {
    if (fs.existsSync(prepared)) {
      fs.rmSync(prepared, { recursive: true, force: true });
    }
    if (movedExisting && fs.existsSync(backup) && !fs.existsSync(target)) {
      fs.renameSync(backup, target);
    }
    throw err;
  }
}

function snapshotFingerprint(validated) {
  const parts = [
    JSON.stringify(validated.normalized_index),
    JSON.stringify(validated.trusted_publishers),
    JSON.stringify(validated.catalog_snapshot || {}),
    JSON.stringify(validated.revocations || {}),
  ];
  return sha256Hex(Buffer.from(parts.join('\n'), 'utf8'));
}

export function readOfficialSkillChannelState(runtimeBaseDir, { channelId = DEFAULT_CHANNEL_ID } = {}) {
  const normalizedChannelId = normalizeChannelId(channelId);
  const currentDir = officialSkillChannelCurrentDir(runtimeBaseDir, { channelId: normalizedChannelId });
  const lastKnownGoodDir = officialSkillChannelLastKnownGoodDir(runtimeBaseDir, { channelId: normalizedChannelId });
  const stateFp = officialSkillChannelStatePath(runtimeBaseDir, { channelId: normalizedChannelId });
  const stored = readJsonSafe(stateFp);
  const hasCurrent = hasRequiredSnapshotArtifacts(currentDir);
  const hasLastKnownGood = hasRequiredSnapshotArtifacts(lastKnownGoodDir);
  const status = safeString(stored?.status || (hasCurrent ? 'healthy' : hasLastKnownGood ? 'stale' : 'missing')) || 'missing';
  return {
    schema_version: safeString(stored?.schema_version || CHANNEL_STATE_SCHEMA_VERSION) || CHANNEL_STATE_SCHEMA_VERSION,
    channel_id: normalizedChannelId,
    status,
    updated_at_ms: Math.max(0, Number(stored?.updated_at_ms || 0)),
    last_attempt_at_ms: Math.max(0, Number(stored?.last_attempt_at_ms || 0)),
    last_success_at_ms: Math.max(0, Number(stored?.last_success_at_ms || 0)),
    source_root: safeString(stored?.source_root),
    public_root: safeString(stored?.public_root),
    current_snapshot_dir: hasCurrent ? currentDir : '',
    last_known_good_snapshot_dir: hasLastKnownGood ? lastKnownGoodDir : '',
    source_fingerprint: safeString(stored?.source_fingerprint),
    skill_count: Math.max(0, Number(stored?.skill_count || 0)),
    error_code: safeString(stored?.error_code),
    error_detail: safeString(stored?.error_detail),
  };
}

export function resolveOfficialSkillChannelSnapshotDir(runtimeBaseDir, { channelId = DEFAULT_CHANNEL_ID } = {}) {
  const state = readOfficialSkillChannelState(runtimeBaseDir, { channelId });
  if (state.current_snapshot_dir) return state.current_snapshot_dir;
  if (state.last_known_good_snapshot_dir) return state.last_known_good_snapshot_dir;
  return '';
}

export function maybeAutoSyncOfficialSkillChannel(
  runtimeBaseDir,
  {
    channelId = DEFAULT_CHANNEL_ID,
    sourceRoot,
    retryAfterMs = 60_000,
  } = {}
) {
  const normalizedChannelId = normalizeChannelId(channelId);
  const state = readOfficialSkillChannelState(runtimeBaseDir, { channelId: normalizedChannelId });
  const status = safeString(state.status).toLowerCase();
  const retryMs = Math.max(0, Number(retryAfterMs || 0));
  const now = nowMs();
  const source = resolveSourcePublicRoot(sourceRoot || state.source_root);
  const needsRepair = !state.current_snapshot_dir || status === 'missing' || status === 'failed' || status === 'stale';
  const retryAllowed = retryMs <= 0 || !state.last_attempt_at_ms || (now - Number(state.last_attempt_at_ms || 0)) >= retryMs;
  if (!needsRepair || !retryAllowed || !source) {
    return state;
  }
  return syncOfficialSkillChannel(runtimeBaseDir, {
    channelId: normalizedChannelId,
    sourceRoot: source,
  });
}

export function syncOfficialSkillChannel(runtimeBaseDir, { channelId = DEFAULT_CHANNEL_ID, sourceRoot } = {}) {
  const normalizedChannelId = normalizeChannelId(channelId);
  const attemptAtMs = nowMs();
  const channelDir = officialSkillChannelDir(runtimeBaseDir, { channelId: normalizedChannelId });
  const currentDir = officialSkillChannelCurrentDir(runtimeBaseDir, { channelId: normalizedChannelId });
  const lastKnownGoodDir = officialSkillChannelLastKnownGoodDir(runtimeBaseDir, { channelId: normalizedChannelId });
  const stateFp = officialSkillChannelStatePath(runtimeBaseDir, { channelId: normalizedChannelId });
  const previous = readOfficialSkillChannelState(runtimeBaseDir, { channelId: normalizedChannelId });

  try {
    if (!channelDir) {
      throw buildValidationError('missing_runtime_base_dir');
    }
    fs.mkdirSync(channelDir, { recursive: true });
    const publicRoot = resolveSourcePublicRoot(sourceRoot);
    if (!publicRoot) {
      throw buildValidationError('missing_public_source_root', {
        source_root: safeString(sourceRoot),
      });
    }
    const validated = validatePublicSnapshot(publicRoot);
    const currentPreparedDir = path.join(channelDir, `.current_next_${process.pid}_${Math.random().toString(16).slice(2)}`);
    const lastKnownGoodPreparedDir = path.join(channelDir, `.lkg_next_${process.pid}_${Math.random().toString(16).slice(2)}`);
    writePreparedSnapshot(currentPreparedDir, validated);
    fs.cpSync(currentPreparedDir, lastKnownGoodPreparedDir, { recursive: true, force: true });
    swapDirectory(currentPreparedDir, currentDir);
    swapDirectory(lastKnownGoodPreparedDir, lastKnownGoodDir);

    const state = {
      schema_version: CHANNEL_STATE_SCHEMA_VERSION,
      channel_id: normalizedChannelId,
      status: 'healthy',
      updated_at_ms: attemptAtMs,
      last_attempt_at_ms: attemptAtMs,
      last_success_at_ms: attemptAtMs,
      source_root: path.resolve(String(sourceRoot || '')),
      public_root: validated.public_root,
      current_snapshot_dir: currentDir,
      last_known_good_snapshot_dir: lastKnownGoodDir,
      source_fingerprint: snapshotFingerprint(validated),
      skill_count: validated.skills.length,
      error_code: '',
      error_detail: '',
    };
    writeJsonAtomic(stateFp, state);
    return state;
  } catch (err) {
    const state = {
      ...previous,
      schema_version: CHANNEL_STATE_SCHEMA_VERSION,
      channel_id: normalizedChannelId,
      status: previous.current_snapshot_dir || previous.last_known_good_snapshot_dir ? 'failed' : 'missing',
      updated_at_ms: attemptAtMs,
      last_attempt_at_ms: attemptAtMs,
      source_root: safeString(sourceRoot || previous.source_root),
      error_code: safeString(err?.code || err?.message || 'official_sync_failed'),
      error_detail: safeString(err?.file_path || err?.actual_sha256 || err?.expected_sha256 || err?.publisher_id || ''),
    };
    writeJsonAtomic(stateFp, state);
    return state;
  }
}
