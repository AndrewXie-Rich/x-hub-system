import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';
import {
  isAgentSkillScannable,
  scanAgentSkillDirectoryWithSummary,
} from './agent_skill_vetter.js';

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

const OFFICIAL_AGENT_CATALOG_SOURCE_ID = 'builtin:catalog';
const OFFICIAL_AGENT_SKILL_SRC_DIR = path.dirname(fileURLToPath(import.meta.url));
const OFFICIAL_AGENT_SKILL_REPO_ROOT = path.resolve(OFFICIAL_AGENT_SKILL_SRC_DIR, '../../../../');
const OFFICIAL_AGENT_BASELINE_FALLBACK = Object.freeze([
  {
    skill_id: 'find-skills',
    name: 'Find Skills',
    version: '1.0.0',
    description: 'Official discovery wrapper over Hub skills.search; default baseline for finding capabilities and usage.',
    publisher_id: 'xhub.official',
    capabilities_required: ['skills.search'],
    install_hint: 'Included in the default Agent baseline profile; prefer the built-in SearchSkills flow in X-Terminal.',
  },
  {
    skill_id: 'agent-browser',
    name: 'Agent Browser',
    version: '1.0.0',
    description: 'Governed browser automation package for navigation, screenshot capture, structured extraction, and Secret Vault-aware credential handling.',
    publisher_id: 'xhub.official',
    capabilities_required: ['browser.read', 'device.browser.control', 'web.fetch'],
    install_hint: 'Recommended default managed skill; enable through Hub-governed import and pin flow before browser-heavy tasks.',
  },
  {
    skill_id: 'self-improving-agent',
    name: 'Self Improving Agent',
    version: '1.0.0',
    description: 'Supervisor retrospective and self-improvement workflow pack for learning from failed runs without bypassing governance.',
    publisher_id: 'xhub.official',
    capabilities_required: ['memory.snapshot', 'project.snapshot', 'repo.read.file'],
    install_hint: 'Recommended default managed skill; intended for the Agent baseline profile and Supervisor retrospectives.',
  },
  {
    skill_id: 'summarize',
    name: 'Summarize',
    version: '1.0.0',
    description: 'Governed summarize wrapper for webpages, PDFs, and long documents using Hub-routed fetch and model generation.',
    publisher_id: 'xhub.official',
    capabilities_required: ['web.fetch', 'browser.read', 'ai.generate.local'],
    install_hint: 'Included in the default Agent baseline profile; use for document and webpage summarization under Hub policy.',
  },
]);

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

export const SKILL_ABI_COMPAT_VERSION = 'skills_abi_compat.v1';

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

function agentImportsBaseDir(runtimeBaseDir) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'agent_imports');
}

function agentStagingDir(runtimeBaseDir) {
  const dir = agentImportsBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'staging');
}

function agentQuarantineDir(runtimeBaseDir) {
  const dir = agentImportsBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'quarantine');
}

function agentMirrorBaseDir(runtimeBaseDir) {
  const dir = agentImportsBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'mirror');
}

function agentReportsDir(runtimeBaseDir) {
  const dir = agentImportsBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'reports');
}

function legacyOpenClawImportsBaseDir(runtimeBaseDir) {
  const dir = skillsStoreBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'openclaw_imports');
}

function legacyOpenClawStagingDir(runtimeBaseDir) {
  const dir = legacyOpenClawImportsBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'staging');
}

function legacyOpenClawQuarantineDir(runtimeBaseDir) {
  const dir = legacyOpenClawImportsBaseDir(runtimeBaseDir);
  if (!dir) return '';
  return path.join(dir, 'quarantine');
}

function normalizeRecordToken(input, fallback = 'record') {
  const raw = safeString(input).toLowerCase();
  const cleaned = raw.replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '');
  return cleaned || fallback;
}

function agentImportRecordPath(runtimeBaseDir, stagingId, status = 'staged') {
  const token = normalizeRecordToken(stagingId, 'record');
  if (!token) return '';
  const baseDir = status === 'quarantined'
    ? agentQuarantineDir(runtimeBaseDir)
    : agentStagingDir(runtimeBaseDir);
  if (!baseDir) return '';
  return path.join(baseDir, `${token}.json`);
}

function agentImportMirrorDir(runtimeBaseDir, stagingId) {
  const token = normalizeRecordToken(stagingId, 'record');
  const baseDir = agentMirrorBaseDir(runtimeBaseDir);
  if (!token || !baseDir) return '';
  return path.join(baseDir, token);
}

function agentImportVetterReportPath(runtimeBaseDir, stagingId) {
  const token = normalizeRecordToken(stagingId, 'record');
  const baseDir = agentReportsDir(runtimeBaseDir);
  if (!token || !baseDir) return '';
  return path.join(baseDir, `${token}.json`);
}

function legacyOpenClawImportRecordPath(runtimeBaseDir, stagingId, status = 'staged') {
  const token = normalizeRecordToken(stagingId, 'record');
  if (!token) return '';
  const baseDir = status === 'quarantined'
    ? legacyOpenClawQuarantineDir(runtimeBaseDir)
    : legacyOpenClawStagingDir(runtimeBaseDir);
  if (!baseDir) return '';
  return path.join(baseDir, `${token}.json`);
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

function officialAgentSkillsSourceRoot() {
  const override = safeString(process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR);
  if (override) return path.resolve(override);
  return path.join(OFFICIAL_AGENT_SKILL_REPO_ROOT, 'official-agent-skills');
}

function officialAgentSkillsDistRoot() {
  const override = safeString(process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR);
  if (override) return path.resolve(override);
  return path.join(officialAgentSkillsSourceRoot(), 'dist');
}

function defaultOfficialAgentCatalogFallback() {
  return OFFICIAL_AGENT_BASELINE_FALLBACK.map((row) => ({ ...row }));
}

function loadOfficialAgentCatalogEntriesFromSource() {
  const root = officialAgentSkillsSourceRoot();
  if (!root || !fs.existsSync(root)) return [];
  let rows = [];
  try {
    rows = fs.readdirSync(root, { withFileTypes: true });
  } catch {
    return [];
  }
  const entries = [];
  for (const row of rows) {
    if (!row?.isDirectory?.()) continue;
    const dirName = safeString(row.name);
    if (!dirName || dirName.startsWith('.') || dirName === 'dist') continue;
    const manifestFp = path.join(root, dirName, 'skill.json');
    const manifestObj = readJsonSafe(manifestFp);
    const meta = normalizeSkillMeta(manifestObj, OFFICIAL_AGENT_CATALOG_SOURCE_ID);
    if (!meta) continue;
    entries.push(meta);
  }
  entries.sort((lhs, rhs) => safeString(lhs.skill_id).localeCompare(safeString(rhs.skill_id)));
  return entries;
}

function loadOfficialAgentPublishedIndex() {
  const distRoot = officialAgentSkillsDistRoot();
  const indexFp = path.join(distRoot, 'index.json');
  const obj = readJsonSafe(indexFp);
  if (!isObject(obj)) {
    return {
      index_path: indexFp,
      dist_root: distRoot,
      generated_at_ms: 0,
      skills: [],
    };
  }
  const rows = Array.isArray(obj.skills) ? obj.skills : [];
  const skills = rows
    .map((row) => {
      const normalized = normalizePackageEntry(row);
      if (!normalized) return null;
      const packageRel = safeString(row.package_path);
      const manifestRel = safeString(row.manifest_path);
      const package_fp = packageRel ? path.resolve(distRoot, packageRel) : '';
      const manifest_fp = manifestRel ? path.resolve(distRoot, manifestRel) : '';
      if (!package_fp || !manifest_fp) return null;
      if (!fs.existsSync(package_fp) || !fs.existsSync(manifest_fp)) return null;
      return {
        ...normalized,
        source_id: OFFICIAL_AGENT_CATALOG_SOURCE_ID,
        package_fp,
        manifest_fp,
      };
    })
    .filter(Boolean);
  return {
    index_path: indexFp,
    dist_root: distRoot,
    generated_at_ms: Number(obj.generated_at_ms || 0),
    skills,
  };
}

function findOfficialAgentPublishedSkill(packageSha256) {
  const sha = safeString(packageSha256).toLowerCase();
  if (!sha) return null;
  const index = loadOfficialAgentPublishedIndex();
  for (const row of index.skills) {
    if (safeString(row.package_sha256).toLowerCase() === sha) return row;
  }
  return null;
}

function defaultAgentBaselineCatalogEntries() {
  const entries = loadOfficialAgentCatalogEntriesFromSource();
  if (entries.length > 0) {
    return entries.map((row) => ({
      skill_id: safeString(row.skill_id),
      name: safeString(row.name),
      version: safeString(row.version),
      description: safeString(row.description),
      publisher_id: safeString(row.publisher_id),
      capabilities_required: safeStringArray(row.capabilities_required),
      install_hint: safeString(row.install_hint),
    }));
  }
  return defaultOfficialAgentCatalogFallback();
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
        discovery_index: defaultAgentBaselineCatalogEntries(),
      },
    ],
  };
}

function officialAgentTrustedPublishersPath() {
  const sourceRoot = officialAgentSkillsSourceRoot();
  const sourcePath = path.join(sourceRoot, 'publisher', 'trusted_publishers.json');
  if (fs.existsSync(sourcePath)) return sourcePath;
  const distPath = path.join(officialAgentSkillsDistRoot(), 'trusted_publishers.json');
  if (fs.existsSync(distPath)) return distPath;
  return sourcePath;
}

function loadBundledOfficialTrustedPublishers() {
  const fp = officialAgentTrustedPublishersPath();
  const obj = readJsonSafe(fp);
  if (!isObject(obj)) {
    return {
      schema_version: 'xhub.trusted_publishers.v1',
      updated_at_ms: 0,
      publishers: [],
    };
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

function defaultTrustedPublishers() {
  const bundled = loadBundledOfficialTrustedPublishers();
  return {
    schema_version: safeString(bundled.schema_version || 'xhub.trusted_publishers.v1') || 'xhub.trusted_publishers.v1',
    updated_at_ms: Number(bundled.updated_at_ms || 0),
    publishers: Array.isArray(bundled.publishers) ? bundled.publishers : [],
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
  const defaults = defaultTrustedPublishers();
  ensureStableSnapshotExists(fp);
  const obj = readJsonSafe(fp);
  if (!isObject(obj)) {
    writeJsonAtomic(fp, defaults);
    return defaults;
  }
  const publishers = Array.isArray(obj.publishers)
    ? obj.publishers.map((it) => normalizeTrustedPublisher(it)).filter(Boolean)
    : [];
  const merged = new Map();
  for (const row of Array.isArray(defaults.publishers) ? defaults.publishers : []) {
    const key = safeString(row?.publisher_id);
    if (!key) continue;
    merged.set(key, row);
  }
  for (const row of publishers) {
    const key = safeString(row?.publisher_id);
    if (!key) continue;
    merged.set(key, row);
  }
  return {
    schema_version: safeString(obj.schema_version || defaults.schema_version || 'xhub.trusted_publishers.v1') || 'xhub.trusted_publishers.v1',
    updated_at_ms: Math.max(Number(defaults.updated_at_ms || 0), Number(obj.updated_at_ms || 0)),
    publishers: Array.from(merged.values()),
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
    install_hint: safeString(it.install_hint),
    manifest_json: safeString(it.manifest_json),
    manifest_sha256: safeString(it.manifest_sha256).toLowerCase(),
    abi_compat_version: safeString(it.abi_compat_version || SKILL_ABI_COMPAT_VERSION) || SKILL_ABI_COMPAT_VERSION,
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
    package_fp: safeString(it.package_fp || ''),
    manifest_fp: safeString(it.manifest_fp || ''),
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

export function normalizeCompatibleSkillManifest(manifestObj, { sourceId, packageSha = '' } = {}) {
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
    abi_compat_version: SKILL_ABI_COMPAT_VERSION,
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
  const mapped = normalizeCompatibleSkillManifest(manifestObj, { sourceId, packageSha });
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
    fs.mkdirSync(agentStagingDir(runtimeBaseDir), { recursive: true });
    fs.mkdirSync(agentQuarantineDir(runtimeBaseDir), { recursive: true });
    fs.mkdirSync(agentMirrorBaseDir(runtimeBaseDir), { recursive: true });
    fs.mkdirSync(agentReportsDir(runtimeBaseDir), { recursive: true });
    fs.mkdirSync(legacyOpenClawStagingDir(runtimeBaseDir), { recursive: true });
    fs.mkdirSync(legacyOpenClawQuarantineDir(runtimeBaseDir), { recursive: true });
    return true;
  } catch {
    return false;
  }
}

function normalizeAgentPreflightStatus(raw) {
  const text = safeString(raw).toLowerCase();
  if (text === 'passed') return 'passed';
  if (text === 'pending') return 'pending';
  if (text === 'failed') return 'failed';
  if (text === 'quarantined') return 'quarantined';
  throw new SkillStoreDenyError('invalid_agent_import_manifest', {
    reason: 'preflight_status_invalid',
    value: text,
  });
}

function normalizeAgentPolicyScope(raw) {
  const text = safeString(raw).toLowerCase();
  if (!text || text === 'project') return 'project';
  if (text === 'global') return 'global';
  if (text === 'memory_core') return 'memory_core';
  throw new SkillStoreDenyError('invalid_agent_import_manifest', {
    reason: 'policy_scope_invalid',
    value: text,
  });
}

function normalizeAgentImportManifest(input) {
  const obj = isObject(input) ? input : {};
  const schema_version = safeString(obj.schema_version);
  if (schema_version !== 'xt.agent_skill_import_manifest.v1'
      && schema_version !== 'xt.openclaw_skill_import_manifest.v1') {
    throw new SkillStoreDenyError('invalid_agent_import_manifest', {
      reason: 'schema_version_invalid',
      value: schema_version,
    });
  }
  const source = safeString(obj.source || 'agent').toLowerCase();
  if (source !== 'agent' && source !== 'openclaw') {
    throw new SkillStoreDenyError('invalid_agent_import_manifest', {
      reason: 'source_invalid',
      value: source,
    });
  }
  const source_ref = safeString(obj.source_ref);
  const skill_id = safeString(obj.skill_id);
  const upstream_package_ref = safeString(obj.upstream_package_ref);
  if (!source_ref || !skill_id || !upstream_package_ref) {
    throw new SkillStoreDenyError('invalid_agent_import_manifest', {
      reason: 'required_field_missing',
      source_ref,
      skill_id,
      upstream_package_ref,
    });
  }
  return {
    schema_version: 'xt.agent_skill_import_manifest.v1',
    source: 'agent',
    source_ref,
    skill_id,
    display_name: safeString(obj.display_name || skill_id) || skill_id,
    kind: safeString(obj.kind || 'skill') || 'skill',
    upstream_package_ref,
    normalized_capabilities: safeStringArray(obj.normalized_capabilities),
    requires_grant: !!obj.requires_grant,
    risk_level: safeString(obj.risk_level || 'low').toLowerCase() || 'low',
    policy_scope: normalizeAgentPolicyScope(obj.policy_scope),
    sandbox_class: safeString(obj.sandbox_class || 'governed_project_local') || 'governed_project_local',
    prompt_mutation_allowed: !!obj.prompt_mutation_allowed,
    install_provenance: safeString(obj.install_provenance || 'local_import') || 'local_import',
    preflight_status: normalizeAgentPreflightStatus(obj.preflight_status),
  };
}

function normalizeAgentImportFindings(input) {
  if (!Array.isArray(input)) return [];
  const out = [];
  for (const row of input) {
    if (!isObject(row)) continue;
    const code = safeString(row.code);
    const detail = safeString(row.detail);
    if (!code) continue;
    out.push({ code, detail });
  }
  return out;
}

function normalizeAgentScanInput(input) {
  const obj = isObject(input) ? input : {};
  const schema_version = safeString(obj.schema_version);
  if (schema_version !== 'xt.agent_skill_scan_input.v1'
      && schema_version !== 'xt.openclaw_skill_scan_input.v1') {
    throw new SkillStoreDenyError('invalid_agent_import_scan_input', {
      reason: 'schema_version_invalid',
      value: schema_version,
    });
  }
  if (!Array.isArray(obj.files)) {
    throw new SkillStoreDenyError('invalid_agent_import_scan_input', {
      reason: 'files_missing',
    });
  }

  const normalized = [];
  let totalBytes = 0;
  for (const row of obj.files) {
    if (!isObject(row)) continue;
    const filePath = normalizeArchivePath(row.path);
    if (!filePath) {
      throw new SkillStoreDenyError('invalid_agent_import_scan_input', {
        reason: 'file_path_invalid',
        value: row.path,
      });
    }
    const content = typeof row.content === 'string'
      ? row.content
      : safeString(row.content_base64)
        ? Buffer.from(safeString(row.content_base64), 'base64').toString('utf8')
        : '';
    totalBytes += Buffer.byteLength(content, 'utf8');
    if (totalBytes > 2 * 1024 * 1024) {
      throw new SkillStoreDenyError('invalid_agent_import_scan_input', {
        reason: 'scan_input_too_large',
        total_bytes: totalBytes,
      });
    }
    normalized.push({ path: filePath, content });
    if (normalized.length > 500) {
      throw new SkillStoreDenyError('invalid_agent_import_scan_input', {
        reason: 'too_many_files',
        file_count: normalized.length,
      });
    }
  }

  return {
    schema_version: 'xt.agent_skill_scan_input.v1',
    files: normalized,
  };
}

function normalizeAgentVetterStatus(raw, fallback = 'pending') {
  const text = safeString(raw).toLowerCase();
  if (text === 'pending') return 'pending';
  if (text === 'passed') return 'passed';
  if (text === 'warn_only') return 'warn_only';
  if (text === 'critical') return 'critical';
  if (text === 'scan_error') return 'scan_error';
  return fallback;
}

function agentImportStatusForManifest(manifest) {
  const preflight = normalizeAgentPreflightStatus(manifest?.preflight_status);
  if (preflight === 'quarantined' || preflight === 'failed') return 'quarantined';
  return 'staged';
}

function buildAgentImportRecord({
  manifest,
  findings,
  requestedBy,
  note,
  auditRef,
  userId,
  projectId,
  createdAtMs,
  status,
}) {
  const manifestObj = normalizeAgentImportManifest(manifest);
  const now = Math.max(0, Number(createdAtMs || nowMs()));
  const tokenSeed = sha256Hex(Buffer.from(JSON.stringify(toCanonicalValue(manifestObj)), 'utf8')).slice(0, 12);
  const staging_id = `agent-${now}-${tokenSeed}`;
  const resolvedStatus = status || agentImportStatusForManifest(manifestObj);
  return {
    schema_version: 'xhub.agent_import_record.v1',
    staging_id,
    status: resolvedStatus,
    created_at_ms: now,
    updated_at_ms: now,
    audit_ref: safeString(auditRef || `audit-agent-import-${tokenSeed}`) || `audit-agent-import-${tokenSeed}`,
    requested_by: safeString(requestedBy),
    note: safeString(note),
    import_manifest: manifestObj,
    findings: normalizeAgentImportFindings(findings),
    vetter_status: resolvedStatus === 'quarantined' ? 'critical' : 'pending',
    vetter_audit_ref: '',
    vetter_report_ref: '',
    vetter_critical_count: 0,
    vetter_warn_count: 0,
    promotion_blocked_reason: resolvedStatus === 'quarantined' ? 'preflight_quarantined' : 'vetter_pending',
    enabled_package_sha256: '',
    enabled_scope: '',
    user_id: safeString(userId),
    project_id: safeString(projectId),
    pin_note: '',
  };
}

function writeAgentImportMirror(runtimeBaseDir, stagingId, scanInput) {
  const mirrorDir = agentImportMirrorDir(runtimeBaseDir, stagingId);
  if (!mirrorDir) {
    throw new SkillStoreDenyError('skills_store_unavailable');
  }
  try {
    fs.rmSync(mirrorDir, { recursive: true, force: true });
    fs.mkdirSync(mirrorDir, { recursive: true });
    let writtenFiles = 0;
    for (const row of scanInput.files) {
      if (!isAgentSkillScannable(row.path)) continue;
      const target = path.join(mirrorDir, row.path);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, String(row.content || ''), 'utf8');
      writtenFiles += 1;
    }
    return { mirror_dir: mirrorDir, written_files: writtenFiles };
  } catch (err) {
    throw new SkillStoreDenyError('agent_import_vetter_mirror_failed', {
      staging_id: stagingId,
      reason: String(err?.message || err || 'mirror_failed'),
    });
  }
}

function writeAgentImportVetterReport(runtimeBaseDir, stagingId, report) {
  const reportPath = agentImportVetterReportPath(runtimeBaseDir, stagingId);
  if (!reportPath) {
    throw new SkillStoreDenyError('skills_store_unavailable');
  }
  writeJsonAtomic(reportPath, report);
  return reportPath;
}

function evaluateAgentImportVetter(runtimeBaseDir, record, scanInputJson) {
  const staging_id = safeString(record?.staging_id);
  const current_status = safeString(record?.status).toLowerCase();
  const audit_ref = `audit-agent-vetter-${normalizeRecordToken(staging_id, 'record')}`;
  const generated_at_ms = nowMs();

  if (current_status === 'quarantined') {
    return {
      vetter_status: 'critical',
      vetter_audit_ref: audit_ref,
      vetter_report_ref: '',
      vetter_critical_count: Math.max(1, Array.isArray(record?.findings) ? record.findings.length : 1),
      vetter_warn_count: 0,
      promotion_blocked_reason: 'preflight_quarantined',
    };
  }

  const scanInputText = safeString(scanInputJson);
  if (!scanInputText) {
    return {
      vetter_status: 'pending',
      vetter_audit_ref: '',
      vetter_report_ref: '',
      vetter_critical_count: 0,
      vetter_warn_count: 0,
      promotion_blocked_reason: 'vetter_scan_input_missing',
    };
  }

  let scanInputObj = null;
  try {
    scanInputObj = JSON.parse(scanInputText);
  } catch {
    throw new SkillStoreDenyError('invalid_agent_import_scan_input_json');
  }

  const normalizedScanInput = normalizeAgentScanInput(scanInputObj);
  const mirror = writeAgentImportMirror(runtimeBaseDir, staging_id, normalizedScanInput);
  if (mirror.written_files <= 0) {
    return {
      vetter_status: 'scan_error',
      vetter_audit_ref: audit_ref,
      vetter_report_ref: '',
      vetter_critical_count: 0,
      vetter_warn_count: 0,
      promotion_blocked_reason: 'vetter_no_scannable_files',
    };
  }

  let reportPath = '';
  try {
    const report = scanAgentSkillDirectoryWithSummary(mirror.mirror_dir);
    const finalReport = {
      ...report,
      staging_id,
      audit_ref,
      generated_at_ms,
    };
    reportPath = writeAgentImportVetterReport(runtimeBaseDir, staging_id, finalReport);
    const status = normalizeAgentVetterStatus(finalReport.status, 'scan_error');
    return {
      vetter_status: status,
      vetter_audit_ref: audit_ref,
      vetter_report_ref: reportPath,
      vetter_critical_count: Number(finalReport?.summary?.critical_count || 0),
      vetter_warn_count: Number(finalReport?.summary?.warn_count || 0),
      promotion_blocked_reason: status === 'critical'
        ? 'vetter_critical_findings'
        : status === 'scan_error'
          ? 'vetter_scan_error'
          : '',
    };
  } catch (err) {
    const report = {
      schema_version: 'xhub.agent_skill_vetter_report.v1',
      scanner_version: 'hub.agent.vetter.v1',
      staging_id,
      status: 'scan_error',
      summary: {
        scanned_files: 0,
        critical_count: 0,
        warn_count: 0,
        info_count: 0,
      },
      findings: [],
      audit_ref,
      generated_at_ms,
      error: String(err?.message || err || 'scan_error'),
    };
    try {
      reportPath = writeAgentImportVetterReport(runtimeBaseDir, staging_id, report);
    } catch {
      reportPath = '';
    }
    return {
      vetter_status: 'scan_error',
      vetter_audit_ref: audit_ref,
      vetter_report_ref: reportPath,
      vetter_critical_count: 0,
      vetter_warn_count: 0,
      promotion_blocked_reason: 'vetter_scan_error',
    };
  }
}

function writeAgentImportRecord(runtimeBaseDir, record) {
  const status = safeString(record?.status).toLowerCase() === 'quarantined' ? 'quarantined' : 'staged';
  const fp = agentImportRecordPath(runtimeBaseDir, record?.staging_id, status);
  if (!fp) return false;
  return writeJsonAtomic(fp, record);
}

export function getAgentImportRecord(runtimeBaseDir, stagingId) {
  const candidates = [
    agentImportRecordPath(runtimeBaseDir, stagingId, 'staged'),
    agentImportRecordPath(runtimeBaseDir, stagingId, 'quarantined'),
    legacyOpenClawImportRecordPath(runtimeBaseDir, stagingId, 'staged'),
    legacyOpenClawImportRecordPath(runtimeBaseDir, stagingId, 'quarantined'),
  ].filter(Boolean);
  for (const fp of candidates) {
    const obj = readJsonSafe(fp);
    if (isObject(obj)) return obj;
  }
  return null;
}

function normalizeAgentImportRecordSelector(raw, {
  hasSkillId = false,
  hasProjectId = false,
} = {}) {
  const text = safeString(raw).toLowerCase().replace(/-/g, '_');
  if (!text) {
    if (hasSkillId) return 'latest_for_skill';
    if (hasProjectId) return 'latest_for_project';
    return 'last_import';
  }
  if (text === 'last'
      || text === 'latest'
      || text === 'last_import'
      || text === 'latest_import') {
    return 'last_import';
  }
  if (text === 'skill'
      || text === 'latest_skill'
      || text === 'skill_latest'
      || text === 'latest_for_skill') {
    return 'latest_for_skill';
  }
  if (text === 'project'
      || text === 'latest_project'
      || text === 'project_latest'
      || text === 'latest_for_project') {
    return 'latest_for_project';
  }
  throw new SkillStoreDenyError('invalid_agent_import_selector', {
    selector: safeString(raw),
  });
}

function agentImportRecordSortScore(record) {
  return Math.max(
    Number(record?.updated_at_ms || 0),
    Number(record?.created_at_ms || 0),
    Number(record?.pin_result?.updated_at_ms || 0)
  );
}

function listAgentImportRecords(runtimeBaseDir) {
  const dirs = [
    agentStagingDir(runtimeBaseDir),
    agentQuarantineDir(runtimeBaseDir),
    legacyOpenClawStagingDir(runtimeBaseDir),
    legacyOpenClawQuarantineDir(runtimeBaseDir),
  ].filter(Boolean);
  const byStagingId = new Map();
  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    let names = [];
    try {
      names = fs.readdirSync(dir);
    } catch {
      continue;
    }
    for (const name of names) {
      if (!String(name).toLowerCase().endsWith('.json')) continue;
      const record = readJsonSafe(path.join(dir, name));
      if (!isObject(record)) continue;
      const stagingId = safeString(record.staging_id);
      if (!stagingId) continue;
      const prev = byStagingId.get(stagingId);
      if (!prev || agentImportRecordSortScore(record) >= agentImportRecordSortScore(prev)) {
        byStagingId.set(stagingId, record);
      }
    }
  }
  return Array.from(byStagingId.values());
}

export function resolveLatestAgentImportRecord(runtimeBaseDir, {
  selector,
  skillId,
  projectId,
} = {}) {
  const skill_id = safeString(skillId);
  const project_id = safeString(projectId);
  const normalizedSelector = normalizeAgentImportRecordSelector(selector, {
    hasSkillId: !!skill_id,
    hasProjectId: !!project_id,
  });

  if (normalizedSelector === 'latest_for_skill' && !skill_id) {
    throw new SkillStoreDenyError('missing_agent_skill_id');
  }
  if (normalizedSelector === 'latest_for_project' && !project_id) {
    throw new SkillStoreDenyError('missing_agent_project_id');
  }

  const matched = listAgentImportRecords(runtimeBaseDir)
    .filter((record) => {
      const recordSkillId = safeString(record?.import_manifest?.skill_id);
      const recordProjectId = safeString(record?.project_id);
      if (skill_id && recordSkillId !== skill_id) return false;
      if (project_id && recordProjectId !== project_id) return false;
      if (normalizedSelector === 'latest_for_skill' && recordSkillId !== skill_id) return false;
      if (normalizedSelector === 'latest_for_project' && recordProjectId !== project_id) return false;
      return true;
    })
    .sort((left, right) => {
      const delta = agentImportRecordSortScore(right) - agentImportRecordSortScore(left);
      if (delta !== 0) return delta;
      return safeString(right?.staging_id).localeCompare(safeString(left?.staging_id));
    });

  const record = matched[0];
  if (!isObject(record)) {
    throw new SkillStoreDenyError('agent_import_not_found', {
      selector: normalizedSelector,
      skill_id,
      project_id,
    });
  }
  return {
    selector: normalizedSelector,
    staging_id: safeString(record.staging_id),
    status: safeString(record.status),
    audit_ref: safeString(record.audit_ref),
    schema_version: safeString(record.schema_version),
    skill_id: safeString(record?.import_manifest?.skill_id),
    record_json: JSON.stringify(record),
    project_id: safeString(record.project_id),
  };
}

export function stageAgentImport(runtimeBaseDir, {
  importManifestJson,
  findingsJson,
  scanInputJson,
  requestedBy,
  note,
  auditRef,
  userId,
  projectId,
} = {}) {
  if (!ensureSkillsStoreDirs(runtimeBaseDir)) {
    throw new SkillStoreDenyError('skills_store_unavailable');
  }
  const manifestText = safeString(importManifestJson);
  if (!manifestText) {
    throw new SkillStoreDenyError('missing_agent_import_manifest');
  }

  let manifestObj = null;
  try {
    manifestObj = JSON.parse(manifestText);
  } catch {
    throw new SkillStoreDenyError('invalid_agent_import_manifest_json');
  }

  let findingsObj = [];
  const findingsText = safeString(findingsJson);
  if (findingsText) {
    try {
      findingsObj = JSON.parse(findingsText);
    } catch {
      throw new SkillStoreDenyError('invalid_agent_import_findings_json');
    }
  }

  const record = buildAgentImportRecord({
    manifest: manifestObj,
    findings: findingsObj,
    requestedBy,
    note,
    auditRef,
    userId,
    projectId,
    createdAtMs: nowMs(),
  });
  const vetter = evaluateAgentImportVetter(runtimeBaseDir, record, scanInputJson);
  record.vetter_status = vetter.vetter_status;
  record.vetter_audit_ref = vetter.vetter_audit_ref;
  record.vetter_report_ref = vetter.vetter_report_ref;
  record.vetter_critical_count = vetter.vetter_critical_count;
  record.vetter_warn_count = vetter.vetter_warn_count;
  record.promotion_blocked_reason = vetter.promotion_blocked_reason;
  if (record.status !== 'quarantined' && vetter.vetter_status === 'critical') {
    record.status = 'quarantined';
  }
  record.updated_at_ms = nowMs();
  if (!writeAgentImportRecord(runtimeBaseDir, record)) {
    throw new SkillStoreDenyError('skills_store_unavailable');
  }
  return {
    staging_id: record.staging_id,
    status: record.status,
    audit_ref: record.audit_ref,
    preflight_status: record.import_manifest.preflight_status,
    skill_id: record.import_manifest.skill_id,
    policy_scope: record.import_manifest.policy_scope,
    findings_count: Array.isArray(record.findings) ? record.findings.length : 0,
    vetter_status: normalizeAgentVetterStatus(record.vetter_status, 'pending'),
    vetter_critical_count: Number(record.vetter_critical_count || 0),
    vetter_warn_count: Number(record.vetter_warn_count || 0),
    vetter_audit_ref: safeString(record.vetter_audit_ref),
    record_path: agentImportRecordPath(runtimeBaseDir, record.staging_id, record.status),
  };
}

export function promoteAgentImport(runtimeBaseDir, {
  stagingId,
  packageSha256,
  userId,
  projectId,
  note,
  auditRef,
} = {}) {
  const staging_id = normalizeRecordToken(stagingId, '');
  if (!staging_id) {
    throw new SkillStoreDenyError('missing_agent_staging_id');
  }
  const record = getAgentImportRecord(runtimeBaseDir, staging_id);
  if (!isObject(record)) {
    throw new SkillStoreDenyError('agent_import_not_found', { staging_id });
  }
  if (safeString(record.status).toLowerCase() === 'quarantined') {
    throw new SkillStoreDenyError('agent_import_quarantined', { staging_id });
  }
  const vetter_status = normalizeAgentVetterStatus(record?.vetter_status, 'pending');
  if (vetter_status === 'pending') {
    throw new SkillStoreDenyError('agent_import_vetter_pending', { staging_id });
  }
  if (vetter_status === 'scan_error') {
    throw new SkillStoreDenyError('agent_import_vetter_scan_error', { staging_id });
  }
  if (vetter_status === 'critical') {
    throw new SkillStoreDenyError('agent_import_vetter_critical', { staging_id });
  }

  const manifest = normalizeAgentImportManifest(record.import_manifest);
  const scope = manifest.policy_scope === 'global'
    ? 'SKILL_PIN_SCOPE_GLOBAL'
    : manifest.policy_scope === 'project'
      ? 'SKILL_PIN_SCOPE_PROJECT'
      : 'SKILL_PIN_SCOPE_UNSPECIFIED';
  if (scope === 'SKILL_PIN_SCOPE_UNSPECIFIED') {
    throw new SkillStoreDenyError('unsupported_agent_policy_scope', {
      staging_id,
      policy_scope: manifest.policy_scope,
    });
  }

  const package_sha256 = safeString(packageSha256).toLowerCase();
  if (!package_sha256) {
    throw new SkillStoreDenyError('missing_package_sha256');
  }
  const meta = getSkillPackageMeta(runtimeBaseDir, package_sha256);
  if (!meta) {
    throw new SkillStoreDenyError('package_not_found', { package_sha256 });
  }
  if (safeString(meta.skill_id) !== safeString(manifest.skill_id)) {
    throw new SkillStoreDenyError('staged_skill_package_mismatch', {
      staging_id,
      expected_skill_id: manifest.skill_id,
      actual_skill_id: safeString(meta.skill_id),
      package_sha256,
    });
  }

  const pin = setSkillPin(runtimeBaseDir, {
    scope,
    userId,
    projectId,
    skillId: manifest.skill_id,
    packageSha256: package_sha256,
    note: safeString(note || record.note || ''),
  });

  const updated = {
    ...record,
    status: 'enabled',
    updated_at_ms: nowMs(),
    audit_ref: safeString(auditRef || record.audit_ref) || record.audit_ref,
    enabled_package_sha256: package_sha256,
    enabled_scope: scope,
    user_id: safeString(userId),
    project_id: safeString(projectId),
    pin_note: safeString(note || record.note || ''),
    promotion_blocked_reason: '',
    pin_result: {
      scope: safeString(pin.scope),
      package_sha256: safeString(pin.package_sha256).toLowerCase(),
      previous_package_sha256: safeString(pin.previous_package_sha256).toLowerCase(),
      updated_at_ms: Number(pin.updated_at_ms || 0),
    },
  };
  if (!writeAgentImportRecord(runtimeBaseDir, updated)) {
    throw new SkillStoreDenyError('skills_store_unavailable');
  }
  return {
    staging_id,
    status: 'enabled',
    audit_ref: updated.audit_ref,
    package_sha256,
    scope,
    skill_id: manifest.skill_id,
    previous_package_sha256: safeString(pin.previous_package_sha256).toLowerCase(),
    record_path: agentImportRecordPath(runtimeBaseDir, staging_id, 'staged'),
  };
}

export function getOpenClawImportRecord(runtimeBaseDir, stagingId) {
  return getAgentImportRecord(runtimeBaseDir, stagingId);
}

export function stageOpenClawImport(runtimeBaseDir, args = {}) {
  return stageAgentImport(runtimeBaseDir, args);
}

export function promoteOpenClawImport(runtimeBaseDir, args = {}) {
  return promoteAgentImport(runtimeBaseDir, args);
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
  const mapped = normalizeCompatibleSkillManifest(manifestObj, { sourceId: normalizedSourceId, packageSha: package_sha256 });
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
  const official = findOfficialAgentPublishedSkill(sha);
  if (official) return official;
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
  if (meta?.manifest_fp) {
    try {
      return fs.readFileSync(meta.manifest_fp, 'utf8');
    } catch {
      return '';
    }
  }
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
  if (meta?.package_fp) {
    try {
      return fs.readFileSync(meta.package_fp);
    } catch {
      return null;
    }
  }
  const fp = packagePath(runtimeBaseDir, packageSha256);
  if (!fp) return null;
  try {
    return fs.readFileSync(fp);
  } catch {
    return null;
  }
}

function mirrorSkillPackageMetaIntoRuntimeIndex(runtimeBaseDir, packageSha256) {
  const package_sha256 = safeString(packageSha256).toLowerCase();
  if (!package_sha256) return null;
  if (!ensureSkillsStoreDirs(runtimeBaseDir)) return null;

  const meta = getSkillPackageMeta(runtimeBaseDir, package_sha256);
  if (!meta) return null;

  const manifest_json = safeString(meta.manifest_json || getSkillManifest(runtimeBaseDir, package_sha256));
  let package_size_bytes = Math.max(0, Number(meta.package_size_bytes || 0));
  if (!(package_size_bytes > 0)) {
    const packageBytes = readSkillPackage(runtimeBaseDir, package_sha256);
    package_size_bytes = Buffer.isBuffer(packageBytes) ? packageBytes.length : 0;
  }

  const now = nowMs();
  const normalized = normalizePackageEntry({
    ...meta,
    package_sha256,
    manifest_json,
    package_size_bytes,
    package_fp: safeString(meta.package_fp || ''),
    manifest_fp: safeString(meta.manifest_fp || ''),
    created_at_ms: Number(meta.created_at_ms || now),
    updated_at_ms: now,
  });
  if (!normalized) return null;

  const snap = loadSkillsIndex(runtimeBaseDir);
  const skills = Array.isArray(snap.skills) ? [...snap.skills] : [];
  const next = [];
  let updated = false;
  for (const row of skills) {
    if (safeString(row?.package_sha256).toLowerCase() !== package_sha256) {
      next.push(row);
      continue;
    }
    next.push({
      ...row,
      ...normalized,
      created_at_ms: Number(row?.created_at_ms || normalized.created_at_ms || now),
      updated_at_ms: now,
    });
    updated = true;
  }
  if (!updated) {
    next.push(normalized);
  }
  saveSkillsIndex(runtimeBaseDir, {
    schema_version: 'skills_store_index.v1',
    updated_at_ms: now,
    skills: next,
  });
  return normalized;
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
  mirrorSkillPackageMetaIntoRuntimeIndex(runtimeBaseDir, package_sha256);

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

  const official = loadOfficialAgentPublishedIndex();
  for (const it of official.skills) {
    const revoked = revocationDecision(runtimeBaseDir, {
      package_sha256: it.package_sha256,
      skill_id: it.skill_id,
      publisher_id: it.publisher_id,
    });
    if (revoked.revoked) continue;
    const meta = normalizeSkillMeta(it, OFFICIAL_AGENT_CATALOG_SOURCE_ID);
    if (!meta) continue;
    meta.package_sha256 = safeString(it.package_sha256).toLowerCase();
    meta.install_hint = safeString(it.install_hint || '');
    if (sf && safeString(meta.source_id) !== sf) continue;
    merged.push({
      meta,
      uploaded: true,
      sort_updated_at_ms: Number(it.updated_at_ms || official.generated_at_ms || 0),
    });
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
    const winnerSha = safeString(winner.package_sha256).toLowerCase();
    const pkg = bySha.get(winnerSha) || getSkillPackageMeta(runtimeBaseDir, winnerSha);
    if (!pkg) {
      blocked.push({
        skill_id: sid,
        package_sha256: winnerSha,
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
    meta.package_sha256 = winnerSha;
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
    agent_imports: {
      staging_dir: agentStagingDir(runtimeBaseDir),
      quarantine_dir: agentQuarantineDir(runtimeBaseDir),
      mirror_dir: agentMirrorBaseDir(runtimeBaseDir),
      reports_dir: agentReportsDir(runtimeBaseDir),
    },
    openclaw_imports: {
      staging_dir: agentStagingDir(runtimeBaseDir),
      quarantine_dir: agentQuarantineDir(runtimeBaseDir),
    },
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
