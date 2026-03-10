import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const SKILL_SCOPE_PRIORITY = {
  SKILL_PIN_SCOPE_MEMORY_CORE: 3,
  SKILL_PIN_SCOPE_GLOBAL: 2,
  SKILL_PIN_SCOPE_PROJECT: 1,
};

const HIGH_RISK_CAPABILITY_RE = [
  /^connectors?\./i,
  /^web\./i,
  /^network\./i,
  /^ai\.generate\.paid$/i,
  /^ai\.generate\.remote$/i,
  /^payments?\./i,
  /^shell\./i,
  /^filesystem\./i,
  /^fs\./i,
];

function parseBoolLike(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return Number.isFinite(v) ? v !== 0 : null;
  const s = String(v ?? '').trim().toLowerCase();
  if (!s) return null;
  if (['1', 'true', 'yes', 'y', 'on'].includes(s)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(s)) return false;
  return null;
}

function isHex64(v) {
  return /^[0-9a-f]{64}$/i.test(String(v || '').trim());
}

function isObject(v) {
  return !!v && typeof v === 'object' && !Array.isArray(v);
}

function toCanonicalValue(v) {
  if (Array.isArray(v)) return v.map((it) => toCanonicalValue(it));
  if (!isObject(v)) return v;
  const out = {};
  for (const k of Object.keys(v).sort()) {
    out[k] = toCanonicalValue(v[k]);
  }
  return out;
}

function canonicalJsonWithoutSignatureBytes(manifestObj) {
  const plain = isObject(manifestObj) ? { ...manifestObj } : {};
  delete plain.signature;
  return Buffer.from(JSON.stringify(toCanonicalValue(plain)), 'utf8');
}

function decodeMaybeBase64(raw) {
  const text = safeString(raw);
  if (!text) return Buffer.alloc(0);
  const body = text.startsWith('base64:') ? text.slice('base64:'.length) : text;
  try {
    return Buffer.from(body, 'base64');
  } catch {
    return Buffer.alloc(0);
  }
}

function decodeSignatureBytes(raw) {
  const text = safeString(raw);
  if (!text) return Buffer.alloc(0);
  if (/^[0-9a-f]{128}$/i.test(text)) {
    try {
      return Buffer.from(text, 'hex');
    } catch {
      return Buffer.alloc(0);
    }
  }
  return decodeMaybeBase64(text);
}

function toBase64Url(buf) {
  return Buffer.from(buf)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function parseEd25519PublicKey(rawKey) {
  const text = safeString(rawKey);
  if (!text) return null;
  if (text.includes('BEGIN PUBLIC KEY')) {
    try {
      return crypto.createPublicKey(text);
    } catch {
      return null;
    }
  }
  const decoded = decodeMaybeBase64(text);
  if (!decoded.length) return null;
  if (decoded.length === 32) {
    try {
      return crypto.createPublicKey({
        key: {
          kty: 'OKP',
          crv: 'Ed25519',
          x: toBase64Url(decoded),
        },
        format: 'jwk',
      });
    } catch {
      return null;
    }
  }
  try {
    return crypto.createPublicKey({
      key: decoded,
      format: 'der',
      type: 'spki',
    });
  } catch {
    return null;
  }
}

function isHighRiskManifest(manifestObj) {
  const obj = isObject(manifestObj) ? manifestObj : {};
  const riskProfile = safeString(obj.risk_profile || obj.risk_level).toLowerCase();
  if (riskProfile === 'high' || riskProfile === 'critical') return true;
  const caps = safeStringArray(obj.capabilities_required);
  for (const cap of caps) {
    if (HIGH_RISK_CAPABILITY_RE.some((re) => re.test(cap))) return true;
  }
  return false;
}

function normalizeArchivePath(rawPath) {
  const text = String(rawPath || '').replace(/\\/g, '/').replace(/\0/g, '');
  const trimmed = text.replace(/^\.\/+/, '').trim();
  if (!trimmed) return '';
  if (trimmed.startsWith('/')) return '';
  const normalized = path.posix.normalize(trimmed);
  if (!normalized || normalized === '.' || normalized === '..') return '';
  if (normalized.startsWith('../')) return '';
  return normalized;
}

function readOctalInt(input) {
  const s = String(input || '').replace(/\0.*$/g, '').trim();
  if (!s) return 0;
  return Number.parseInt(s, 8) || 0;
}

function readTarString(buf, off, len) {
  return buf.slice(off, off + len).toString('utf8').replace(/\0.*$/g, '').trim();
}

function collectTarFileHashes(tarBytes) {
  const byPath = new Map();
  let off = 0;
  let nextLongName = '';

  while (off + 512 <= tarBytes.length) {
    const header = tarBytes.slice(off, off + 512);
    const zeroBlock = header.every((b) => b === 0);
    if (zeroBlock) break;

    const name = readTarString(header, 0, 100);
    const prefix = readTarString(header, 345, 155);
    const size = readOctalInt(readTarString(header, 124, 12));
    const typeflag = header[156];

    const dataOff = off + 512;
    const dataEnd = dataOff + size;
    const padded = Math.ceil(size / 512) * 512;
    const nextOff = dataOff + padded;
    if (dataEnd > tarBytes.length) {
      throw new SkillStoreDenyError('archive_corrupt', { kind: 'tar_out_of_bounds' });
    }

    let fullName = name;
    if (nextLongName) {
      fullName = nextLongName;
      nextLongName = '';
    } else if (prefix) {
      fullName = `${prefix}/${name}`;
    }

    if (typeflag === 76 /* L */) {
      nextLongName = tarBytes.slice(dataOff, dataEnd).toString('utf8').replace(/\0.*$/g, '').trim();
      off = nextOff;
      continue;
    }

    const isFile = typeflag === 0 || typeflag === 48 /* '0' */;
    if (isFile) {
      const normalized = normalizeArchivePath(fullName);
      if (!normalized) {
        throw new SkillStoreDenyError('archive_path_invalid', { path: fullName, format: 'tar' });
      }
      if (byPath.has(normalized)) {
        throw new SkillStoreDenyError('archive_duplicate_path', { path: normalized, format: 'tar' });
      }
      const fileBytes = tarBytes.slice(dataOff, dataEnd);
      byPath.set(normalized, {
        path: normalized,
        sha256: sha256Hex(fileBytes),
        size_bytes: fileBytes.length,
      });
    }

    off = nextOff;
  }

  return byPath;
}

function findZipEndOfCentralDirectory(buf) {
  const minSize = 22;
  if (buf.length < minSize) return -1;
  const maxComment = 0xffff;
  const start = Math.max(0, buf.length - minSize - maxComment);
  for (let i = buf.length - minSize; i >= start; i -= 1) {
    if (buf.readUInt32LE(i) === 0x06054b50) return i;
  }
  return -1;
}

function collectZipFileHashes(zipBytes) {
  const byPath = new Map();
  const eocdOff = findZipEndOfCentralDirectory(zipBytes);
  if (eocdOff < 0) {
    throw new SkillStoreDenyError('archive_corrupt', { kind: 'zip_eocd_missing' });
  }

  const entriesCount = zipBytes.readUInt16LE(eocdOff + 10);
  const cdSize = zipBytes.readUInt32LE(eocdOff + 12);
  const cdOffset = zipBytes.readUInt32LE(eocdOff + 16);
  if (cdOffset + cdSize > zipBytes.length) {
    throw new SkillStoreDenyError('archive_corrupt', { kind: 'zip_cd_out_of_bounds' });
  }

  let ptr = cdOffset;
  for (let i = 0; i < entriesCount; i += 1) {
    if (ptr + 46 > zipBytes.length || zipBytes.readUInt32LE(ptr) !== 0x02014b50) {
      throw new SkillStoreDenyError('archive_corrupt', { kind: 'zip_cd_entry_invalid' });
    }
    const flags = zipBytes.readUInt16LE(ptr + 8);
    const method = zipBytes.readUInt16LE(ptr + 10);
    const compressedSize = zipBytes.readUInt32LE(ptr + 20);
    const uncompressedSize = zipBytes.readUInt32LE(ptr + 24);
    const nameLen = zipBytes.readUInt16LE(ptr + 28);
    const extraLen = zipBytes.readUInt16LE(ptr + 30);
    const commentLen = zipBytes.readUInt16LE(ptr + 32);
    const localHeaderOffset = zipBytes.readUInt32LE(ptr + 42);
    const nameStart = ptr + 46;
    const nameEnd = nameStart + nameLen;
    if (nameEnd > zipBytes.length) {
      throw new SkillStoreDenyError('archive_corrupt', { kind: 'zip_name_out_of_bounds' });
    }
    const rawName = zipBytes.slice(nameStart, nameEnd).toString('utf8');
    ptr = nameEnd + extraLen + commentLen;

    if (rawName.endsWith('/')) continue;
    if (flags & 0x0001) {
      throw new SkillStoreDenyError('archive_unsupported', { kind: 'zip_encrypted' });
    }

    if (localHeaderOffset + 30 > zipBytes.length || zipBytes.readUInt32LE(localHeaderOffset) !== 0x04034b50) {
      throw new SkillStoreDenyError('archive_corrupt', { kind: 'zip_local_header_invalid' });
    }
    const localNameLen = zipBytes.readUInt16LE(localHeaderOffset + 26);
    const localExtraLen = zipBytes.readUInt16LE(localHeaderOffset + 28);
    const dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen;
    const dataEnd = dataStart + compressedSize;
    if (dataEnd > zipBytes.length) {
      throw new SkillStoreDenyError('archive_corrupt', { kind: 'zip_data_out_of_bounds' });
    }

    let plain;
    if (method === 0) {
      plain = zipBytes.slice(dataStart, dataEnd);
    } else if (method === 8) {
      try {
        plain = zlib.inflateRawSync(zipBytes.slice(dataStart, dataEnd));
      } catch {
        throw new SkillStoreDenyError('archive_corrupt', { kind: 'zip_inflate_failed' });
      }
    } else {
      throw new SkillStoreDenyError('archive_unsupported', { kind: 'zip_method_unsupported', method });
    }

    if (plain.length !== uncompressedSize) {
      throw new SkillStoreDenyError('archive_corrupt', { kind: 'zip_size_mismatch', path: rawName });
    }

    const normalized = normalizeArchivePath(rawName);
    if (!normalized) {
      throw new SkillStoreDenyError('archive_path_invalid', { path: rawName, format: 'zip' });
    }
    if (byPath.has(normalized)) {
      throw new SkillStoreDenyError('archive_duplicate_path', { path: normalized, format: 'zip' });
    }
    byPath.set(normalized, {
      path: normalized,
      sha256: sha256Hex(plain),
      size_bytes: plain.length,
    });
  }

  return byPath;
}

function collectPackageFileHashes(packageBytes) {
  if (!Buffer.isBuffer(packageBytes) || packageBytes.length <= 0) {
    throw new SkillStoreDenyError('invalid_package_bytes');
  }
  const b = packageBytes;
  if (b.length >= 2 && b[0] === 0x1f && b[1] === 0x8b) {
    let tarBytes = null;
    try {
      tarBytes = zlib.gunzipSync(b);
    } catch {
      throw new SkillStoreDenyError('archive_corrupt', { kind: 'gzip_invalid' });
    }
    return { format: 'tgz', filesByPath: collectTarFileHashes(tarBytes) };
  }
  if (b.length >= 4 && b.readUInt32LE(0) === 0x04034b50) {
    return { format: 'zip', filesByPath: collectZipFileHashes(b) };
  }
  // Fallback: treat as uncompressed tar.
  return { format: 'tar', filesByPath: collectTarFileHashes(b) };
}

function normalizeManifestFileEntries(filesRaw) {
  if (!Array.isArray(filesRaw)) return [];
  const out = [];
  const seen = new Set();
  for (const it of filesRaw) {
    if (!isObject(it)) {
      throw new SkillStoreDenyError('invalid_manifest', { reason: 'files_entry_invalid' });
    }
    const p = normalizeArchivePath(it.path);
    const h = safeString(it.sha256).toLowerCase();
    if (!p || !isHex64(h)) {
      throw new SkillStoreDenyError('invalid_manifest', { reason: 'files_entry_invalid', path: safeString(it.path) });
    }
    if (seen.has(p)) {
      throw new SkillStoreDenyError('invalid_manifest', { reason: 'files_entry_duplicate', path: p });
    }
    seen.add(p);
    out.push({ path: p, sha256: h });
  }
  return out;
}

function manifestPublisher(manifestObj) {
  const pubObj = isObject(manifestObj?.publisher) ? manifestObj.publisher : {};
  return {
    publisher_id: safeString(pubObj.publisher_id || manifestObj?.publisher_id),
    public_key_ed25519: safeString(pubObj.public_key_ed25519 || manifestObj?.public_key_ed25519),
  };
}

function verifyManifestSignature({
  manifestObj,
  trustedPublisher,
  allowUntrustedPublisher,
  allowUnsigned,
}) {
  const sigObj = isObject(manifestObj?.signature) ? manifestObj.signature : {};
  const alg = safeString(sigObj.alg).toLowerCase();
  const sigRaw = safeString(sigObj.sig);
  const hasSig = !!sigRaw;
  const publisher = manifestPublisher(manifestObj);

  if (!hasSig) {
    if (allowUnsigned) {
      return {
        verified: false,
        signature_required: false,
        signature_bypassed: true,
        publisher_id: publisher.publisher_id,
        signature_alg: '',
      };
    }
    throw new SkillStoreDenyError('signature_missing', {
      publisher_id: publisher.publisher_id,
    });
  }

  if (alg && alg !== 'ed25519') {
    throw new SkillStoreDenyError('signature_algorithm_unsupported', { alg });
  }

  const trustedPub = trustedPublisher && trustedPublisher.enabled ? trustedPublisher : null;
  if (!trustedPub && !allowUntrustedPublisher) {
    throw new SkillStoreDenyError('publisher_untrusted', { publisher_id: publisher.publisher_id });
  }

  if (trustedPub && publisher.public_key_ed25519 && trustedPub.public_key_ed25519) {
    if (safeString(trustedPub.public_key_ed25519) !== safeString(publisher.public_key_ed25519)) {
      throw new SkillStoreDenyError('publisher_key_mismatch', { publisher_id: publisher.publisher_id });
    }
  }

  const keyText = safeString(trustedPub?.public_key_ed25519 || publisher.public_key_ed25519);
  const keyObj = parseEd25519PublicKey(keyText);
  if (!keyObj) {
    throw new SkillStoreDenyError('signature_key_invalid', { publisher_id: publisher.publisher_id });
  }

  const sigBytes = decodeSignatureBytes(sigRaw);
  if (!sigBytes.length) {
    throw new SkillStoreDenyError('signature_invalid', { reason: 'empty_signature' });
  }

  let verified = false;
  try {
    const msg = canonicalJsonWithoutSignatureBytes(manifestObj);
    verified = crypto.verify(null, msg, keyObj, sigBytes);
  } catch {
    throw new SkillStoreDenyError('signature_invalid', { reason: 'verify_exception' });
  }
  if (!verified) {
    throw new SkillStoreDenyError('signature_invalid', { reason: 'verify_false' });
  }

  return {
    verified: true,
    signature_required: true,
    signature_bypassed: false,
    publisher_id: publisher.publisher_id,
    signature_alg: 'ed25519',
  };
}

function verifyManifestHashes({ manifestObj, packageBytes, packageSha256 }) {
  const expectedPkg = safeString(
    manifestObj?.package_sha256
      || manifestObj?.package?.sha256
      || manifestObj?.dist?.package_sha256
  ).toLowerCase();
  if (expectedPkg && expectedPkg !== safeString(packageSha256).toLowerCase()) {
    throw new SkillStoreDenyError('hash_mismatch', {
      reason: 'package_sha_mismatch',
      expected: expectedPkg,
      actual: safeString(packageSha256).toLowerCase(),
    });
  }

  const manifestFiles = normalizeManifestFileEntries(manifestObj?.files);
  if (!manifestFiles.length) {
    throw new SkillStoreDenyError('invalid_manifest', { reason: 'files_missing' });
  }

  const archive = collectPackageFileHashes(packageBytes);
  const byPath = archive.filesByPath;
  for (const f of manifestFiles) {
    const row = byPath.get(f.path);
    if (!row || safeString(row.sha256).toLowerCase() !== f.sha256) {
      throw new SkillStoreDenyError('hash_mismatch', { reason: 'file_sha_mismatch', path: f.path });
    }
  }

  // Fail-closed: no unlisted file can silently ride along.
  for (const p of byPath.keys()) {
    if (!manifestFiles.some((f) => f.path === p)) {
      throw new SkillStoreDenyError('hash_mismatch', { reason: 'file_unlisted', path: p });
    }
  }

  return {
    package_sha256: safeString(packageSha256).toLowerCase(),
    package_format: archive.format,
    file_count: manifestFiles.length,
  };
}

function normalizeRevocationList(items, { lowercase = false } = {}) {
  if (!Array.isArray(items)) return [];
  const out = [];
  const seen = new Set();
  for (const raw of items) {
    const v = lowercase ? safeString(raw).toLowerCase() : safeString(raw);
    if (!v) continue;
    if (seen.has(v)) continue;
    seen.add(v);
    out.push(v);
  }
  return out;
}

export class SkillStoreDenyError extends Error {
  constructor(code, detail = {}) {
    const deny = safeString(code) || 'runtime_error';
    super(deny);
    this.name = 'SkillStoreDenyError';
    this.code = deny;
    this.detail = isObject(detail) ? detail : {};
  }
}

export function normalizeSkillStoreError(err, fallbackCode = 'runtime_error') {
  const code = safeString(err?.code || err?.message || fallbackCode) || fallbackCode;
  return {
    code,
    detail: isObject(err?.detail) ? err.detail : {},
    message: safeString(err?.message || code) || code,
  };
}

function safeString(v) {
  return String(v ?? '').trim();
}

function safeStringArray(v) {
  if (!Array.isArray(v)) return [];
  return v.map((s) => safeString(s)).filter(Boolean);
}

function safeBool(v, fallback) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  const s = String(v ?? '').trim().toLowerCase();
  if (s === 'true' || s === '1' || s === 'yes') return true;
  if (s === 'false' || s === '0' || s === 'no') return false;
  return !!fallback;
}

function isPlainObject(v) {
  return !!v && typeof v === 'object' && !Array.isArray(v);
}

function getByPath(obj, dottedPath) {
  const root = isPlainObject(obj) ? obj : {};
  const pathText = safeString(dottedPath);
  if (!pathText) return undefined;
  const parts = pathText.split('.');
  let cur = root;
  for (const part of parts) {
    if (!isPlainObject(cur)) return undefined;
    cur = cur[part];
  }
  return cur;
}

function canonicalizeJsonValue(value) {
  if (Array.isArray(value)) {
    return value.map((item) => canonicalizeJsonValue(item));
  }
  if (!isPlainObject(value)) return value;
  const out = {};
  for (const key of Object.keys(value).sort()) {
    out[key] = canonicalizeJsonValue(value[key]);
  }
  return out;
}

function canonicalizeManifest(manifestObj) {
  return JSON.stringify(canonicalizeJsonValue(manifestObj || {}));
}

function resolveStringField(obj, canonicalField, aliases, { required = false, defaultValue = '' } = {}, tracker) {
  const fields = Array.isArray(aliases) ? aliases.map((s) => safeString(s)).filter(Boolean) : [];
  for (let i = 0; i < fields.length; i += 1) {
    const alias = fields[i];
    const raw = getByPath(obj, alias);
    const value = safeString(raw);
    if (!value) continue;
    if (tracker && i > 0) tracker.aliases.add(`${canonicalField}<-${alias}`);
    return value;
  }
  if (required) {
    throw new Error(`invalid_manifest: missing ${canonicalField}`);
  }
  if (tracker) tracker.defaults.add(canonicalField);
  return safeString(defaultValue);
}

function resolveStringArrayField(obj, canonicalField, aliases, { required = false, defaultValue = [] } = {}, tracker) {
  const fields = Array.isArray(aliases) ? aliases.map((s) => safeString(s)).filter(Boolean) : [];
  for (let i = 0; i < fields.length; i += 1) {
    const alias = fields[i];
    const raw = getByPath(obj, alias);
    if (raw == null) continue;
    const arr = safeStringArray(raw);
    if (Array.isArray(raw)) {
      if (tracker && i > 0) tracker.aliases.add(`${canonicalField}<-${alias}`);
      return arr;
    }
    if (typeof raw === 'string') {
      const split = String(raw)
        .split(',')
        .map((s) => safeString(s))
        .filter(Boolean);
      if (tracker && i > 0) tracker.aliases.add(`${canonicalField}<-${alias}`);
      return split;
    }
    throw new Error(`invalid_manifest: ${canonicalField} must be array<string>`);
  }
  if (required) {
    throw new Error(`invalid_manifest: missing ${canonicalField}`);
  }
  if (tracker) tracker.defaults.add(canonicalField);
  return Array.isArray(defaultValue) ? [...defaultValue] : [];
}

function nowMs() {
  return Date.now();
}

function readJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
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

function sha256Hex(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

export const OPENCLAW_SKILL_ABI_COMPAT_VERSION = 'openclaw_skill_abi_compat.v1';

export function skillsStoreBaseDir(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'skills_store');
}

function sourcesPath(runtimeBaseDir) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'skill_sources.json');
}

function indexPath(runtimeBaseDir) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'skills_store_index.json');
}

function pinsPath(runtimeBaseDir) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'skills_pins.json');
}

function trustedPublishersPath(runtimeBaseDir) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'trusted_publishers.json');
}

function revocationsPath(runtimeBaseDir) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'revoked.json');
}

function policyPath(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'policy', 'xhub_policy.json');
}

function stableSnapshotPath(filePath) {
  const fp = safeString(filePath);
  if (!fp) return '';
  if (fp.endsWith('.json')) return `${fp.slice(0, -5)}.last_stable.json`;
  return `${fp}.last_stable`;
}

function captureStableSnapshot(filePath) {
  const fp = safeString(filePath);
  if (!fp || !fs.existsSync(fp)) return;
  const snap = stableSnapshotPath(fp);
  if (!snap) return;
  try {
    fs.copyFileSync(fp, snap);
  } catch {
    // ignore snapshot failures (non-blocking)
  }
}

function ensureStableSnapshotExists(filePath) {
  const fp = safeString(filePath);
  if (!fp || !fs.existsSync(fp)) return;
  const snap = stableSnapshotPath(fp);
  if (!snap || fs.existsSync(snap)) return;
  try {
    fs.copyFileSync(fp, snap);
  } catch {
    // ignore snapshot failures (non-blocking)
  }
}

function packagePath(runtimeBaseDir, packageSha256) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  const sha = safeString(packageSha256).toLowerCase();
  if (!dir || !sha) return '';
  return path.join(dir, 'packages', `${sha}.tgz`);
}

function manifestPath(runtimeBaseDir, packageSha256) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  const sha = safeString(packageSha256).toLowerCase();
  if (!dir || !sha) return '';
  return path.join(dir, 'manifests', `${sha}.json`);
}

function defaultSources() {
  return {
    schema_version: 'skill_sources.v1',
    updated_at_ms: 0,
    sources: [
      {
        source_id: 'builtin:catalog',
        type: 'catalog',
        default_trust_policy: 'trusted_official',
        updated_at_ms: 0,
        discovery_index: [],
      },
    ],
  };
}

function defaultTrustedPublishers() {
  return {
    schema_version: 'xhub.trusted_publishers.v1',
    updated_at_ms: 0,
    publishers: [],
  };
}

function defaultSkillRevocations() {
  return {
    schema_version: 'xhub.skill_revocations.v1',
    updated_at_ms: 0,
    revoked_sha256: [],
    revoked_skill_ids: [],
    revoked_publishers: [],
  };
}

function normalizeTrustedPublisher(it) {
  if (!isObject(it)) return null;
  const publisher_id = safeString(it.publisher_id || it.id);
  if (!publisher_id) return null;
  return {
    publisher_id,
    public_key_ed25519: safeString(it.public_key_ed25519 || ''),
    enabled: it.enabled == null ? true : !!it.enabled,
  };
}

export function loadTrustedPublishers(runtimeBaseDir) {
  const fp = trustedPublishersPath(runtimeBaseDir);
  ensureStableSnapshotExists(fp);
  const obj = readJsonSafe(fp);
  if (!isObject(obj)) {
    const def = defaultTrustedPublishers();
    writeJsonAtomic(fp, def);
    return def;
  }
  const publishers = Array.isArray(obj.publishers)
    ? obj.publishers.map((it) => normalizeTrustedPublisher(it)).filter(Boolean)
    : [];
  return {
    schema_version: safeString(obj.schema_version || 'xhub.trusted_publishers.v1') || 'xhub.trusted_publishers.v1',
    updated_at_ms: Number(obj.updated_at_ms || 0),
    publishers,
  };
}

export function loadSkillRevocations(runtimeBaseDir) {
  const fp = revocationsPath(runtimeBaseDir);
  ensureStableSnapshotExists(fp);
  const obj = readJsonSafe(fp);
  if (!isObject(obj)) {
    const def = defaultSkillRevocations();
    writeJsonAtomic(fp, def);
    return def;
  }
  return {
    schema_version: safeString(obj.schema_version || 'xhub.skill_revocations.v1') || 'xhub.skill_revocations.v1',
    updated_at_ms: Number(obj.updated_at_ms || 0),
    revoked_sha256: normalizeRevocationList(obj.revoked_sha256, { lowercase: true }),
    revoked_skill_ids: normalizeRevocationList(obj.revoked_skill_ids),
    revoked_publishers: normalizeRevocationList(obj.revoked_publishers),
  };
}

function loadSkillsPolicy(runtimeBaseDir) {
  const env = parseBoolLike(process.env.HUB_SKILLS_DEVELOPER_MODE);
  if (env != null) return { developer_mode: env };
  const fp = policyPath(runtimeBaseDir);
  const obj = readJsonSafe(fp);
  if (!isObject(obj)) return { developer_mode: false };
  const nested = isObject(obj.overrides) ? obj.overrides : {};
  const fromNested = parseBoolLike(nested.developer_mode);
  if (fromNested != null) return { developer_mode: fromNested };
  const fromRoot = parseBoolLike(obj.developer_mode);
  if (fromRoot != null) return { developer_mode: fromRoot };
  return { developer_mode: false };
}

function trustedPublisherMap(runtimeBaseDir) {
  const rows = loadTrustedPublishers(runtimeBaseDir).publishers;
  const map = new Map();
  for (const row of rows) {
    if (!row.enabled) continue;
    const key = safeString(row.publisher_id);
    if (!key) continue;
    map.set(key, row);
  }
  return map;
}

function revocationDecision(runtimeBaseDir, { package_sha256, skill_id, publisher_id } = {}) {
  const revoked = loadSkillRevocations(runtimeBaseDir);
  const sha = safeString(package_sha256).toLowerCase();
  const sid = safeString(skill_id);
  const pid = safeString(publisher_id);
  if (sha && revoked.revoked_sha256.includes(sha)) {
    return { revoked: true, deny_code: 'revoked', reason: 'package_sha256', value: sha };
  }
  if (sid && revoked.revoked_skill_ids.includes(sid)) {
    return { revoked: true, deny_code: 'revoked', reason: 'skill_id', value: sid };
  }
  if (pid && revoked.revoked_publishers.includes(pid)) {
    return { revoked: true, deny_code: 'revoked', reason: 'publisher_id', value: pid };
  }
  return { revoked: false, deny_code: '', reason: '', value: '' };
}

function verifySkillPackageSecurity(runtimeBaseDir, { manifestObj, manifestText, packageBytes, package_sha256 }) {
  const policy = loadSkillsPolicy(runtimeBaseDir);
  const publisher = manifestPublisher(manifestObj);
  const highRisk = isHighRiskManifest(manifestObj);

  const revocation = revocationDecision(runtimeBaseDir, {
    package_sha256,
    skill_id: safeString(manifestObj?.skill_id || manifestObj?.id),
    publisher_id: publisher.publisher_id,
  });
  if (revocation.revoked) {
    throw new SkillStoreDenyError(revocation.deny_code, {
      reason: revocation.reason,
      value: revocation.value,
    });
  }

  const trusted = trustedPublisherMap(runtimeBaseDir);
  const trustedPublisher = trusted.get(publisher.publisher_id) || null;
  const developerMode = !!policy.developer_mode;

  // High-risk skills are never allowed to bypass signature + trust root checks.
  const allowUnsigned = developerMode && !highRisk;
  const allowUntrustedPublisher = developerMode && !highRisk;
  const signature = verifyManifestSignature({
    manifestObj,
    trustedPublisher,
    allowUntrustedPublisher,
    allowUnsigned,
  });
  const hashes = verifyManifestHashes({
    manifestObj,
    packageBytes,
    packageSha256: package_sha256,
  });

  return {
    security_profile: highRisk ? 'high_risk' : 'low_risk',
    developer_mode: developerMode,
    signature,
    hashes,
    canonical_manifest_sha256: sha256Hex(canonicalJsonWithoutSignatureBytes(manifestObj)),
    manifest_sha256: sha256Hex(Buffer.from(String(manifestText || ''), 'utf8')),
  };
}

export function loadSkillSources(runtimeBaseDir) {
  const fp = sourcesPath(runtimeBaseDir);
  const obj = readJsonSafe(fp);
  if (!obj || typeof obj !== 'object') {
    const def = defaultSources();
    writeJsonAtomic(fp, def);
    return def;
  }
  const inSources = Array.isArray(obj.sources) ? obj.sources : [];
  const sources = inSources
    .map((it) => {
      if (!it || typeof it !== 'object') return null;
      const source_id = safeString(it.source_id || it.id);
      if (!source_id) return null;
      const discoveryRaw = Array.isArray(it.discovery_index) ? it.discovery_index : [];
      const discovery_index = discoveryRaw
        .map((r) => normalizeSkillMeta(r, source_id))
        .filter(Boolean)
        .map((r) => ({ ...r, package_sha256: '' }));
      return {
        source_id,
        type: safeString(it.type || 'catalog') || 'catalog',
        default_trust_policy: safeString(it.default_trust_policy || 'manual_review') || 'manual_review',
        updated_at_ms: Number(it.updated_at_ms || 0),
        discovery_index,
      };
    })
    .filter(Boolean);
  if (!sources.length) {
    const def = defaultSources();
    writeJsonAtomic(fp, def);
    return def;
  }
  return {
    schema_version: safeString(obj.schema_version || 'skill_sources.v1') || 'skill_sources.v1',
    updated_at_ms: Number(obj.updated_at_ms || 0),
    sources,
  };
}

function normalizePackageEntry(it) {
  if (!it || typeof it !== 'object') return null;
  const skill_id = safeString(it.skill_id);
  const package_sha256 = safeString(it.package_sha256 || it.sha256).toLowerCase();
  if (!skill_id || !package_sha256) return null;
  return {
    package_sha256,
    skill_id,
    name: safeString(it.name),
    version: safeString(it.version),
    description: safeString(it.description),
    publisher_id: safeString(it.publisher_id),
    capabilities_required: safeStringArray(it.capabilities_required),
    source_id: safeString(it.source_id || 'local'),
    manifest_json: safeString(it.manifest_json),
    manifest_sha256: safeString(it.manifest_sha256).toLowerCase(),
    abi_compat_version: safeString(it.abi_compat_version || OPENCLAW_SKILL_ABI_COMPAT_VERSION) || OPENCLAW_SKILL_ABI_COMPAT_VERSION,
    compatibility_state: safeString(it.compatibility_state || 'supported') || 'supported',
    mapping_aliases_used: safeStringArray(it.mapping_aliases_used),
    defaults_applied: safeStringArray(it.defaults_applied),
    entrypoint_runtime: safeString(it.entrypoint_runtime),
    entrypoint_command: safeString(it.entrypoint_command),
    entrypoint_args: safeStringArray(it.entrypoint_args),
    canonical_manifest_sha256: safeString(it.canonical_manifest_sha256).toLowerCase(),
    signature_alg: safeString(it.signature_alg || ''),
    signature_verified: !!it.signature_verified,
    signature_bypassed: !!it.signature_bypassed,
    security_profile: safeString(it.security_profile || ''),
    package_format: safeString(it.package_format || ''),
    file_hash_count: Math.max(0, Number(it.file_hash_count || 0)),
    package_size_bytes: Math.max(0, Number(it.package_size_bytes || 0)),
    created_at_ms: Number(it.created_at_ms || 0),
    updated_at_ms: Number(it.updated_at_ms || 0),
  };
}

export function loadSkillsIndex(runtimeBaseDir) {
  const fp = indexPath(runtimeBaseDir);
  const obj = readJsonSafe(fp);
  if (!obj || typeof obj !== 'object') {
    return { schema_version: 'skills_store_index.v1', updated_at_ms: 0, skills: [] };
  }
  const skills = Array.isArray(obj.skills) ? obj.skills.map(normalizePackageEntry).filter(Boolean) : [];
  return {
    schema_version: safeString(obj.schema_version || 'skills_store_index.v1') || 'skills_store_index.v1',
    updated_at_ms: Number(obj.updated_at_ms || 0),
    skills,
  };
}

function saveSkillsIndex(runtimeBaseDir, snap) {
  const fp = indexPath(runtimeBaseDir);
  return writeJsonAtomic(fp, snap);
}

function normalizePinScope(scope) {
  const s = safeString(scope).toUpperCase();
  if (s === 'SKILL_PIN_SCOPE_MEMORY_CORE' || s === 'MEMORY_CORE') return 'SKILL_PIN_SCOPE_MEMORY_CORE';
  if (s === 'SKILL_PIN_SCOPE_GLOBAL' || s === 'GLOBAL') return 'SKILL_PIN_SCOPE_GLOBAL';
  if (s === 'SKILL_PIN_SCOPE_PROJECT' || s === 'PROJECT') return 'SKILL_PIN_SCOPE_PROJECT';
  return 'SKILL_PIN_SCOPE_UNSPECIFIED';
}

function normalizePin(it, scope) {
  if (!it || typeof it !== 'object') return null;
  const skill_id = safeString(it.skill_id);
  const package_sha256 = safeString(it.package_sha256).toLowerCase();
  if (!skill_id || !package_sha256) return null;
  const sc = normalizePinScope(scope);
  if (sc === 'SKILL_PIN_SCOPE_MEMORY_CORE') {
    return {
      scope: sc,
      skill_id,
      package_sha256,
      note: safeString(it.note),
      updated_at_ms: Number(it.updated_at_ms || 0),
    };
  }
  if (sc === 'SKILL_PIN_SCOPE_GLOBAL') {
    const user_id = safeString(it.user_id);
    if (!user_id) return null;
    return {
      scope: sc,
      user_id,
      skill_id,
      package_sha256,
      note: safeString(it.note),
      updated_at_ms: Number(it.updated_at_ms || 0),
    };
  }
  if (sc === 'SKILL_PIN_SCOPE_PROJECT') {
    const user_id = safeString(it.user_id);
    const project_id = safeString(it.project_id);
    if (!user_id || !project_id) return null;
    return {
      scope: sc,
      user_id,
      project_id,
      skill_id,
      package_sha256,
      note: safeString(it.note),
      updated_at_ms: Number(it.updated_at_ms || 0),
    };
  }
  return null;
}

export function loadSkillsPins(runtimeBaseDir) {
  const fp = pinsPath(runtimeBaseDir);
  ensureStableSnapshotExists(fp);
  const obj = readJsonSafe(fp);
  if (!obj || typeof obj !== 'object') {
    return {
      schema_version: 'skills_pins.v1',
      updated_at_ms: 0,
      memory_core_pins: [],
      global_pins: [],
      project_pins: [],
    };
  }
  const memory_core_pins = Array.isArray(obj.memory_core_pins)
    ? obj.memory_core_pins.map((it) => normalizePin(it, 'SKILL_PIN_SCOPE_MEMORY_CORE')).filter(Boolean)
    : [];
  const global_pins = Array.isArray(obj.global_pins)
    ? obj.global_pins.map((it) => normalizePin(it, 'SKILL_PIN_SCOPE_GLOBAL')).filter(Boolean)
    : [];
  const project_pins = Array.isArray(obj.project_pins)
    ? obj.project_pins.map((it) => normalizePin(it, 'SKILL_PIN_SCOPE_PROJECT')).filter(Boolean)
    : [];
  return {
    schema_version: safeString(obj.schema_version || 'skills_pins.v1') || 'skills_pins.v1',
    updated_at_ms: Number(obj.updated_at_ms || 0),
    memory_core_pins,
    global_pins,
    project_pins,
  };
}

function saveSkillsPins(runtimeBaseDir, snap) {
  const fp = pinsPath(runtimeBaseDir);
  captureStableSnapshot(fp);
  return writeJsonAtomic(fp, snap);
}

function isSourceAllowlisted(runtimeBaseDir, sourceId) {
  const sid = safeString(sourceId);
  if (!sid) return false;
  if (sid.startsWith('local:') || sid === 'builtin:catalog') return true;
  const sources = loadSkillSources(runtimeBaseDir);
  const rows = Array.isArray(sources?.sources) ? sources.sources : [];
  return rows.some((row) => safeString(row?.source_id) === sid);
}

function normalizeEntrypoint(manifestObj, tracker) {
  const entryObj = getByPath(manifestObj, 'entrypoint');
  const entrypoint = isPlainObject(entryObj) ? entryObj : {};
  const commandFromStringEntrypoint = typeof entryObj === 'string' ? safeString(entryObj) : '';
  if (commandFromStringEntrypoint && tracker) {
    tracker.aliases.add('entrypoint.command<-entrypoint');
  }
  const command =
    commandFromStringEntrypoint
    || resolveStringField(
      manifestObj,
      'entrypoint.command',
      ['entrypoint.command', 'entrypoint.exec', 'command', 'main', 'runner.command'],
      { required: true },
      tracker
    );
  const runtime = resolveStringField(
    manifestObj,
    'entrypoint.runtime',
    ['entrypoint.runtime', 'runtime', 'entrypoint.type'],
    { defaultValue: 'node' },
    tracker
  );
  const args = resolveStringArrayField(
    manifestObj,
    'entrypoint.args',
    ['entrypoint.args', 'entrypoint.arguments', 'args'],
    { defaultValue: [] },
    tracker
  );
  return {
    runtime: runtime || 'node',
    command,
    args,
  };
}

export function normalizeOpenClawSkillManifest(manifestObj, { sourceId, packageSha = '' } = {}) {
  const obj = isPlainObject(manifestObj) ? manifestObj : {};
  const tracker = {
    aliases: new Set(),
    defaults: new Set(),
  };
  const skill_id = resolveStringField(obj, 'skill_id', ['skill_id', 'id'], { required: true }, tracker);
  const version = resolveStringField(obj, 'version', ['version', 'skill_version'], { required: true }, tracker);
  const schema_version = resolveStringField(
    obj,
    'schema_version',
    ['schema_version', 'manifest_version'],
    { defaultValue: 'xhub.skill_manifest.v1' },
    tracker
  );
  const name = resolveStringField(obj, 'name', ['name', 'title'], { defaultValue: skill_id }, tracker);
  const description = resolveStringField(obj, 'description', ['description', 'summary'], { defaultValue: '' }, tracker);
  const capabilities_required = resolveStringArrayField(
    obj,
    'capabilities_required',
    ['capabilities_required', 'capabilities', 'required_capabilities'],
    { defaultValue: [] },
    tracker
  );
  const publisher_id = resolveStringField(
    obj,
    'publisher.publisher_id',
    ['publisher.publisher_id', 'publisher_id', 'publisher.id', 'author_id', 'author'],
    { defaultValue: 'unknown' },
    tracker
  );
  const install_hint = resolveStringField(
    obj,
    'install_hint',
    ['install_hint', 'install.command', 'install_hint.command'],
    { defaultValue: '' },
    tracker
  );
  const entrypoint = normalizeEntrypoint(obj, tracker);
  const direct_network_forbidden = safeBool(
    getByPath(obj, 'network_policy.direct_network_forbidden'),
    true
  );
  if (getByPath(obj, 'network_policy.direct_network_forbidden') == null) {
    tracker.defaults.add('network_policy.direct_network_forbidden');
  }
  const normalized_manifest = {
    schema_version,
    skill_id,
    name: name || skill_id,
    version,
    description,
    entrypoint,
    capabilities_required,
    network_policy: {
      direct_network_forbidden,
    },
    publisher: {
      publisher_id: publisher_id || 'unknown',
    },
    install_hint,
  };
  const manifest_sha256 = sha256Hex(Buffer.from(canonicalizeManifest(normalized_manifest), 'utf8'));
  const mapping_aliases_used = Array.from(tracker.aliases).sort();
  const defaults_applied = Array.from(tracker.defaults).sort();
  return {
    abi_compat_version: OPENCLAW_SKILL_ABI_COMPAT_VERSION,
    compatibility_state: mapping_aliases_used.length > 0 ? 'partial' : 'supported',
    mapping_aliases_used,
    defaults_applied,
    manifest_sha256,
    normalized_manifest,
    skill: {
      skill_id,
      name: name || skill_id,
      version,
      description,
      publisher_id: publisher_id || 'unknown',
      capabilities_required,
      source_id: safeString(sourceId || 'local') || 'local',
      package_sha256: safeString(packageSha).toLowerCase(),
      install_hint,
      entrypoint_runtime: safeString(entrypoint.runtime || 'node') || 'node',
      entrypoint_command: safeString(entrypoint.command),
      entrypoint_args: safeStringArray(entrypoint.args),
    },
  };
}

function normalizeUploadSourceId(runtimeBaseDir, sourceId) {
  const sid = safeString(sourceId || 'local:upload') || 'local:upload';
  if (!isSourceAllowlisted(runtimeBaseDir, sid)) {
    throw new SkillStoreDenyError('source_not_allowlisted', { source_id: sid });
  }
  return sid;
}

function skillMetaFromManifest(manifestObj, sourceId, packageSha = '') {
  const mapped = normalizeOpenClawSkillManifest(manifestObj, { sourceId, packageSha });
  return {
    ...mapped.skill,
    manifest_sha256: mapped.manifest_sha256,
    abi_compat_version: mapped.abi_compat_version,
    compatibility_state: mapped.compatibility_state,
    mapping_aliases_used: mapped.mapping_aliases_used,
    defaults_applied: mapped.defaults_applied,
  };
}

function ensureSkillsStoreDirs(runtimeBaseDir) {
  const base = skillsStoreBaseDir(runtimeBaseDir);
  if (!base) return false;
  try {
    fs.mkdirSync(path.join(base, 'packages'), { recursive: true });
    fs.mkdirSync(path.join(base, 'manifests'), { recursive: true });
    return true;
  } catch {
    return false;
  }
}

export function normalizeSkillMeta(input, fallbackSourceId = '') {
  if (!input || typeof input !== 'object') return null;
  const skill_id = safeString(input.skill_id || input.id);
  const version = safeString(input.version);
  if (!skill_id || !version) return null;
  return {
    skill_id,
    name: safeString(input.name || skill_id),
    version,
    description: safeString(input.description),
    publisher_id: safeString(input.publisher_id || input.publisher || 'unknown'),
    capabilities_required: safeStringArray(input.capabilities_required),
    source_id: safeString(input.source_id || fallbackSourceId || 'builtin:catalog') || 'builtin:catalog',
    package_sha256: safeString(input.package_sha256 || '').toLowerCase(),
    install_hint: safeString(input.install_hint),
  };
}

export function uploadSkillPackage(runtimeBaseDir, { packageBytes, manifestJson, sourceId }) {
  if (!ensureSkillsStoreDirs(runtimeBaseDir)) {
    throw new SkillStoreDenyError('skills_store_unavailable');
  }
  if (!Buffer.isBuffer(packageBytes) || packageBytes.length <= 0) {
    throw new SkillStoreDenyError('invalid_package_bytes');
  }
  const manifestText = safeString(manifestJson);
  if (!manifestText) {
    throw new SkillStoreDenyError('missing_manifest_json');
  }

  let manifestObj = null;
  try {
    manifestObj = JSON.parse(manifestText);
  } catch {
    throw new SkillStoreDenyError('invalid_manifest_json');
  }

  const normalizedSourceId = normalizeUploadSourceId(runtimeBaseDir, sourceId);
  const package_sha256 = sha256Hex(packageBytes);
  const security = verifySkillPackageSecurity(runtimeBaseDir, {
    manifestObj,
    manifestText,
    packageBytes,
    package_sha256,
  });
  const mapped = normalizeOpenClawSkillManifest(manifestObj, { sourceId: normalizedSourceId, packageSha: package_sha256 });
  const meta = {
    ...skillMetaFromManifest(manifestObj, normalizedSourceId, package_sha256),
    source_id: normalizedSourceId,
    canonical_manifest_sha256: security.canonical_manifest_sha256,
    signature_alg: safeString(security?.signature?.signature_alg || ''),
    signature_verified: !!security?.signature?.verified,
    signature_bypassed: !!security?.signature?.signature_bypassed,
    security_profile: safeString(security.security_profile),
    package_format: safeString(security?.hashes?.package_format || ''),
    file_hash_count: Math.max(0, Number(security?.hashes?.file_count || 0)),
  };
  const pkgPath = packagePath(runtimeBaseDir, package_sha256);
  const manPath = manifestPath(runtimeBaseDir, package_sha256);

  const already_present = fs.existsSync(pkgPath);
  if (!already_present) {
    fs.writeFileSync(pkgPath, packageBytes);
  }
  fs.writeFileSync(manPath, `${manifestText}\n`, 'utf8');

  const snap = loadSkillsIndex(runtimeBaseDir);
  const now = nowMs();
  const skills = Array.isArray(snap.skills) ? [...snap.skills] : [];
  let found = false;
  for (let i = 0; i < skills.length; i += 1) {
    const it = skills[i];
    if (safeString(it.package_sha256).toLowerCase() !== package_sha256) continue;
    found = true;
    skills[i] = {
      ...it,
      ...meta,
      manifest_json: manifestText,
      manifest_sha256: mapped.manifest_sha256,
      abi_compat_version: mapped.abi_compat_version,
      compatibility_state: mapped.compatibility_state,
      mapping_aliases_used: mapped.mapping_aliases_used,
      defaults_applied: mapped.defaults_applied,
      entrypoint_runtime: meta.entrypoint_runtime,
      entrypoint_command: meta.entrypoint_command,
      entrypoint_args: meta.entrypoint_args,
      canonical_manifest_sha256: meta.canonical_manifest_sha256,
      signature_alg: meta.signature_alg,
      signature_verified: meta.signature_verified,
      signature_bypassed: meta.signature_bypassed,
      security_profile: meta.security_profile,
      package_format: meta.package_format,
      file_hash_count: meta.file_hash_count,
      package_size_bytes: packageBytes.length,
      updated_at_ms: now,
      created_at_ms: Number(it.created_at_ms || now),
    };
    break;
  }
  if (!found) {
    skills.push({
      ...meta,
      manifest_json: manifestText,
      manifest_sha256: mapped.manifest_sha256,
      abi_compat_version: mapped.abi_compat_version,
      compatibility_state: mapped.compatibility_state,
      mapping_aliases_used: mapped.mapping_aliases_used,
      defaults_applied: mapped.defaults_applied,
      entrypoint_runtime: meta.entrypoint_runtime,
      entrypoint_command: meta.entrypoint_command,
      entrypoint_args: meta.entrypoint_args,
      canonical_manifest_sha256: meta.canonical_manifest_sha256,
      signature_alg: meta.signature_alg,
      signature_verified: meta.signature_verified,
      signature_bypassed: meta.signature_bypassed,
      security_profile: meta.security_profile,
      package_format: meta.package_format,
      file_hash_count: meta.file_hash_count,
      package_size_bytes: packageBytes.length,
      created_at_ms: now,
      updated_at_ms: now,
    });
  }
  saveSkillsIndex(runtimeBaseDir, {
    schema_version: 'skills_store_index.v1',
    updated_at_ms: now,
    skills,
  });

  return {
    package_sha256,
    already_present,
    manifest_sha256: mapped.manifest_sha256,
    abi_compat_version: mapped.abi_compat_version,
    compatibility_state: mapped.compatibility_state,
    mapping_aliases_used: mapped.mapping_aliases_used,
    defaults_applied: mapped.defaults_applied,
    normalized_manifest: mapped.normalized_manifest,
    security,
    skill: meta,
  };
}

export function getSkillPackageMeta(runtimeBaseDir, packageSha256) {
  const sha = safeString(packageSha256).toLowerCase();
  if (!sha) return null;
  const snap = loadSkillsIndex(runtimeBaseDir);
  for (const it of snap.skills) {
    if (safeString(it.package_sha256).toLowerCase() === sha) return it;
  }
  return null;
}

function assertSkillNotRevoked(runtimeBaseDir, { package_sha256, skill_id, publisher_id } = {}) {
  const decision = revocationDecision(runtimeBaseDir, {
    package_sha256,
    skill_id,
    publisher_id,
  });
  if (decision.revoked) {
    throw new SkillStoreDenyError('revoked', {
      reason: decision.reason,
      value: decision.value,
      package_sha256: safeString(package_sha256).toLowerCase(),
      skill_id: safeString(skill_id),
      publisher_id: safeString(publisher_id),
    });
  }
}

export function getSkillManifest(runtimeBaseDir, packageSha256) {
  const sha = safeString(packageSha256).toLowerCase();
  if (!sha) return '';
  const meta = getSkillPackageMeta(runtimeBaseDir, sha);
  if (meta) {
    assertSkillNotRevoked(runtimeBaseDir, {
      package_sha256: sha,
      skill_id: meta.skill_id,
      publisher_id: meta.publisher_id,
    });
  }
  if (meta?.manifest_json) return String(meta.manifest_json);
  const fp = manifestPath(runtimeBaseDir, sha);
  try {
    return fs.readFileSync(fp, 'utf8');
  } catch {
    return '';
  }
}

export function readSkillPackage(runtimeBaseDir, packageSha256) {
  const sha = safeString(packageSha256).toLowerCase();
  if (!sha) return null;
  const meta = getSkillPackageMeta(runtimeBaseDir, sha);
  if (meta) {
    assertSkillNotRevoked(runtimeBaseDir, {
      package_sha256: sha,
      skill_id: meta.skill_id,
      publisher_id: meta.publisher_id,
    });
  }
  const fp = packagePath(runtimeBaseDir, packageSha256);
  if (!fp) return null;
  try {
    return fs.readFileSync(fp);
  } catch {
    return null;
  }
}

export function setSkillPin(runtimeBaseDir, { scope, userId, projectId, skillId, packageSha256, note }) {
  const sc = normalizePinScope(scope);
  const uid = safeString(userId);
  const pid = safeString(projectId);
  const skill_id = safeString(skillId);
  const package_sha256 = safeString(packageSha256).toLowerCase();
  if (!skill_id || !package_sha256) {
    throw new SkillStoreDenyError('invalid_pin_request');
  }
  if (sc !== 'SKILL_PIN_SCOPE_GLOBAL' && sc !== 'SKILL_PIN_SCOPE_PROJECT') {
    throw new SkillStoreDenyError('unsupported_scope');
  }
  if (!uid) throw new SkillStoreDenyError('missing_user_id');
  if (sc === 'SKILL_PIN_SCOPE_PROJECT' && !pid) throw new SkillStoreDenyError('missing_project_id');

  const skill = getSkillPackageMeta(runtimeBaseDir, package_sha256);
  if (!skill) throw new SkillStoreDenyError('package_not_found');
  if (safeString(skill.skill_id) !== skill_id) throw new SkillStoreDenyError('skill_package_mismatch');
  assertSkillNotRevoked(runtimeBaseDir, {
    package_sha256,
    skill_id,
    publisher_id: skill.publisher_id,
  });

  const pins = loadSkillsPins(runtimeBaseDir);
  const now = nowMs();
  const n = safeString(note);
  let previous = '';

  if (sc === 'SKILL_PIN_SCOPE_GLOBAL') {
    const next = [];
    let updated = false;
    for (const p of pins.global_pins) {
      if (safeString(p.user_id) === uid && safeString(p.skill_id) === skill_id) {
        previous = safeString(p.package_sha256);
        next.push({ ...p, package_sha256, note: n || p.note || '', updated_at_ms: now });
        updated = true;
      } else {
        next.push(p);
      }
    }
    if (!updated) {
      next.push({ scope: sc, user_id: uid, skill_id, package_sha256, note: n, updated_at_ms: now });
    }
    pins.global_pins = next;
  } else {
    const next = [];
    let updated = false;
    for (const p of pins.project_pins) {
      if (safeString(p.user_id) === uid && safeString(p.project_id) === pid && safeString(p.skill_id) === skill_id) {
        previous = safeString(p.package_sha256);
        next.push({ ...p, package_sha256, note: n || p.note || '', updated_at_ms: now });
        updated = true;
      } else {
        next.push(p);
      }
    }
    if (!updated) {
      next.push({ scope: sc, user_id: uid, project_id: pid, skill_id, package_sha256, note: n, updated_at_ms: now });
    }
    pins.project_pins = next;
  }

  const out = {
    schema_version: 'skills_pins.v1',
    updated_at_ms: now,
    memory_core_pins: pins.memory_core_pins || [],
    global_pins: pins.global_pins || [],
    project_pins: pins.project_pins || [],
  };
  saveSkillsPins(runtimeBaseDir, out);

  return {
    scope: sc,
    user_id: uid,
    project_id: pid,
    skill_id,
    package_sha256,
    previous_package_sha256: previous,
    updated_at_ms: now,
  };
}

function scoreSearch(meta, q) {
  if (!q) return 1;
  const hay = `${safeString(meta.skill_id)} ${safeString(meta.name)} ${safeString(meta.description)} ${safeString(meta.publisher_id)}`.toLowerCase();
  if (!hay.includes(q)) return 0;
  const sid = safeString(meta.skill_id).toLowerCase();
  const name = safeString(meta.name).toLowerCase();
  if (sid === q || name === q) return 200;
  if (sid.startsWith(q) || name.startsWith(q)) return 120;
  if (sid.includes(q) || name.includes(q)) return 90;
  return 50;
}

export function searchSkills(runtimeBaseDir, { query, sourceFilter, limit }) {
  const q = safeString(query).toLowerCase();
  const sf = safeString(sourceFilter);
  const lim = Math.max(1, Math.min(100, Number(limit || 20)));

  const merged = [];
  const index = loadSkillsIndex(runtimeBaseDir);
  for (const it of index.skills) {
    const revoked = revocationDecision(runtimeBaseDir, {
      package_sha256: it.package_sha256,
      skill_id: it.skill_id,
      publisher_id: it.publisher_id,
    });
    if (revoked.revoked) continue;
    const meta = normalizeSkillMeta(it, it.source_id || 'local');
    if (!meta) continue;
    meta.package_sha256 = safeString(it.package_sha256).toLowerCase();
    meta.install_hint = safeString(it.install_hint || '');
    if (sf && safeString(meta.source_id) !== sf) continue;
    merged.push({ meta, uploaded: true, sort_updated_at_ms: Number(it.updated_at_ms || 0) });
  }

  const sources = loadSkillSources(runtimeBaseDir);
  for (const src of sources.sources) {
    const sid = safeString(src.source_id);
    if (!sid) continue;
    if (sf && sid !== sf) continue;
    const arr = Array.isArray(src.discovery_index) ? src.discovery_index : [];
    for (const raw of arr) {
      const meta = normalizeSkillMeta(raw, sid);
      if (!meta) continue;
      const revoked = revocationDecision(runtimeBaseDir, {
        package_sha256: meta.package_sha256,
        skill_id: meta.skill_id,
        publisher_id: meta.publisher_id,
      });
      if (revoked.revoked) continue;
      merged.push({
        meta,
        uploaded: !!safeString(meta.package_sha256),
        sort_updated_at_ms: Number(src.updated_at_ms || 0),
      });
    }
  }

  const dedup = new Map();
  for (const row of merged) {
    const m = row.meta;
    const key = `${safeString(m.skill_id)}::${safeString(m.version)}::${safeString(m.source_id)}`;
    const prev = dedup.get(key);
    if (!prev) {
      dedup.set(key, row);
      continue;
    }
    if (row.uploaded && !prev.uploaded) {
      dedup.set(key, row);
      continue;
    }
    if (row.sort_updated_at_ms > prev.sort_updated_at_ms) {
      dedup.set(key, row);
    }
  }

  const out = [];
  for (const row of dedup.values()) {
    const score = scoreSearch(row.meta, q);
    if (q && score <= 0) continue;
    out.push({ ...row, score });
  }

  out.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    if ((b.uploaded ? 1 : 0) !== (a.uploaded ? 1 : 0)) return (b.uploaded ? 1 : 0) - (a.uploaded ? 1 : 0);
    if (b.sort_updated_at_ms !== a.sort_updated_at_ms) return b.sort_updated_at_ms - a.sort_updated_at_ms;
    return safeString(a.meta.skill_id).localeCompare(safeString(b.meta.skill_id));
  });

  return out.slice(0, lim).map((r) => r.meta);
}

function collectVisiblePins(runtimeBaseDir, { userId, projectId }) {
  const uid = safeString(userId);
  const pid = safeString(projectId);
  const pins = loadSkillsPins(runtimeBaseDir);
  const out = [];
  const pushPin = (p, scope) => {
    const sid = safeString(p?.skill_id);
    const sha = safeString(p?.package_sha256).toLowerCase();
    if (!sid || !sha) return;
    out.push({
      scope,
      user_id: safeString(p?.user_id),
      project_id: safeString(p?.project_id),
      skill_id: sid,
      package_sha256: sha,
      note: safeString(p?.note),
      updated_at_ms: Number(p?.updated_at_ms || 0),
    });
  };

  for (const p of pins.memory_core_pins || []) {
    pushPin(p, 'SKILL_PIN_SCOPE_MEMORY_CORE');
  }
  for (const p of pins.global_pins || []) {
    if (safeString(p?.user_id) !== uid) continue;
    pushPin(p, 'SKILL_PIN_SCOPE_GLOBAL');
  }
  for (const p of pins.project_pins || []) {
    if (safeString(p?.user_id) !== uid) continue;
    if (safeString(p?.project_id) !== pid) continue;
    pushPin(p, 'SKILL_PIN_SCOPE_PROJECT');
  }
  return out;
}

function comparePinCandidate(a, b) {
  const pa = Number(SKILL_SCOPE_PRIORITY[safeString(a?.scope)] || 0);
  const pb = Number(SKILL_SCOPE_PRIORITY[safeString(b?.scope)] || 0);
  if (pb !== pa) return pb - pa;
  const ta = Number(a?.updated_at_ms || 0);
  const tb = Number(b?.updated_at_ms || 0);
  if (tb !== ta) return tb - ta;
  const sa = safeString(a?.package_sha256);
  const sb = safeString(b?.package_sha256);
  if (sa !== sb) return sa.localeCompare(sb);
  return safeString(a?.scope).localeCompare(safeString(b?.scope));
}

export function resolveSkillsWithTrace(runtimeBaseDir, { userId, projectId }) {
  const index = loadSkillsIndex(runtimeBaseDir);
  const bySha = new Map();
  for (const it of index.skills) {
    bySha.set(safeString(it.package_sha256).toLowerCase(), it);
  }

  const grouped = new Map();
  const pins = collectVisiblePins(runtimeBaseDir, { userId, projectId });
  for (const p of pins) {
    if (!grouped.has(p.skill_id)) grouped.set(p.skill_id, []);
    grouped.get(p.skill_id).push(p);
  }

  const resolved = [];
  const blocked = [];
  const skillIds = Array.from(grouped.keys()).sort((a, b) => a.localeCompare(b));
  for (const sid of skillIds) {
    const rows = grouped.get(sid) || [];
    rows.sort(comparePinCandidate);
    const winner = rows[0];
    if (!winner) continue;
    const pkg = bySha.get(safeString(winner.package_sha256).toLowerCase());
    if (!pkg) {
      blocked.push({
        skill_id: sid,
        package_sha256: safeString(winner.package_sha256).toLowerCase(),
        scope: winner.scope,
        deny_code: 'package_not_found',
      });
      continue;
    }
    const revocation = revocationDecision(runtimeBaseDir, {
      package_sha256: winner.package_sha256,
      skill_id: sid,
      publisher_id: pkg.publisher_id,
    });
    if (revocation.revoked) {
      blocked.push({
        skill_id: sid,
        package_sha256: safeString(winner.package_sha256).toLowerCase(),
        scope: winner.scope,
        deny_code: 'revoked',
        revocation_reason: revocation.reason,
      });
      continue;
    }

    const meta = normalizeSkillMeta(pkg, pkg.source_id || 'local');
    if (!meta) continue;
    meta.package_sha256 = safeString(winner.package_sha256).toLowerCase();
    resolved.push({
      scope: winner.scope,
      skill: meta,
      resolution: {
        selected_scope: winner.scope,
        selected_updated_at_ms: Number(winner.updated_at_ms || 0),
      },
    });
  }

  return { resolved, blocked };
}

export function listResolvedSkills(runtimeBaseDir, { userId, projectId }) {
  return resolveSkillsWithTrace(runtimeBaseDir, { userId, projectId }).resolved;
}

export function skillsGovernanceSnapshotPaths(runtimeBaseDir) {
  const pins = pinsPath(runtimeBaseDir);
  const trusted = trustedPublishersPath(runtimeBaseDir);
  const revoked = revocationsPath(runtimeBaseDir);
  return {
    pins: { active: pins, previous_stable: stableSnapshotPath(pins) },
    trusted_publishers: { active: trusted, previous_stable: stableSnapshotPath(trusted) },
    revoked: { active: revoked, previous_stable: stableSnapshotPath(revoked) },
  };
}

export function evaluateSkillExecutionGate(runtimeBaseDir, {
  packageSha256,
  packageBytes,
  manifestJson,
  skillId,
  publisherId,
} = {}) {
  const package_sha256 = safeString(packageSha256).toLowerCase();
  const skill_id_input = safeString(skillId);
  const publisher_id_input = safeString(publisherId);
  if (!package_sha256) {
    return {
      allowed: false,
      deny_code: 'missing_package_sha256',
      detail: {},
    };
  }

  let manifestText = safeString(manifestJson);
  let pkgBytes = Buffer.isBuffer(packageBytes) ? packageBytes : null;
  let meta = getSkillPackageMeta(runtimeBaseDir, package_sha256);
  if (!manifestText) {
    try {
      manifestText = safeString(getSkillManifest(runtimeBaseDir, package_sha256));
    } catch (err) {
      const normalized = normalizeSkillStoreError(err, 'manifest_not_found');
      return {
        allowed: false,
        deny_code: normalized.code,
        detail: normalized.detail,
      };
    }
  }
  if (!pkgBytes) {
    try {
      pkgBytes = readSkillPackage(runtimeBaseDir, package_sha256);
    } catch (err) {
      const normalized = normalizeSkillStoreError(err, 'package_not_found');
      return {
        allowed: false,
        deny_code: normalized.code,
        detail: normalized.detail,
      };
    }
  }
  if (!pkgBytes || !Buffer.isBuffer(pkgBytes) || pkgBytes.length <= 0) {
    return {
      allowed: false,
      deny_code: 'package_not_found',
      detail: {},
    };
  }
  if (!manifestText) {
    return {
      allowed: false,
      deny_code: 'manifest_not_found',
      detail: {},
    };
  }

  let manifestObj = null;
  try {
    manifestObj = JSON.parse(manifestText);
  } catch {
    return {
      allowed: false,
      deny_code: 'invalid_manifest_json',
      detail: {},
    };
  }

  const derivedSkillId = safeString(manifestObj?.skill_id || manifestObj?.id || meta?.skill_id || skill_id_input);
  const derivedPublisherId = safeString(
    manifestObj?.publisher?.publisher_id
      || manifestObj?.publisher_id
      || meta?.publisher_id
      || publisher_id_input
  );
  const revocation = revocationDecision(runtimeBaseDir, {
    package_sha256,
    skill_id: derivedSkillId,
    publisher_id: derivedPublisherId,
  });
  if (revocation.revoked) {
    return {
      allowed: false,
      deny_code: 'revoked',
      detail: {
        reason: revocation.reason,
        value: revocation.value,
      },
    };
  }

  try {
    const security = verifySkillPackageSecurity(runtimeBaseDir, {
      manifestObj,
      manifestText,
      packageBytes: pkgBytes,
      package_sha256,
    });
    if (!meta) {
      meta = skillMetaFromManifest(manifestObj, safeString(manifestObj?.source_id || 'local'), package_sha256);
    }
    return {
      allowed: true,
      deny_code: '',
      detail: {
        skill_id: safeString(meta?.skill_id || derivedSkillId),
        security_profile: safeString(security.security_profile),
        signature_verified: !!security?.signature?.verified,
      },
    };
  } catch (err) {
    const normalized = normalizeSkillStoreError(err, 'runtime_error');
    return {
      allowed: false,
      deny_code: normalized.code,
      detail: normalized.detail,
    };
  }
}
