import fs from 'node:fs';
import path from 'node:path';

import {
  importAuthDir,
  importProxyConfig,
  listProviderKeyImportSources,
  pruneProviderKeyImportOwner,
  recordProviderKeyImportSourceStatus,
} from './provider_key_store.js';

const DEFAULT_POLL_INTERVAL_MS = 2000;

function safeString(value) {
  return String(value ?? '').trim();
}

function normalizePathRef(value) {
  const raw = safeString(value);
  if (!raw) return '';
  try {
    return path.resolve(raw);
  } catch {
    return raw;
  }
}

function parseImportSourceKey(raw) {
  const token = safeString(raw);
  if (!token) return null;
  if (token.startsWith('auth_dir:')) {
    return { kind: 'auth_dir', source_ref: normalizePathRef(token.slice('auth_dir:'.length)) };
  }
  if (token.startsWith('config_path:')) {
    return { kind: 'config_path', source_ref: normalizePathRef(token.slice('config_path:'.length)) };
  }
  return null;
}

function fileSignature(filePath) {
  const normalized = normalizePathRef(filePath);
  if (!normalized || !fs.existsSync(normalized)) return `${normalized}:missing`;
  try {
    const stat = fs.statSync(normalized);
    return `${normalized}:${stat.isDirectory() ? 'dir' : 'file'}:${Number(stat.mtimeMs || 0)}:${Number(stat.size || 0)}`;
  } catch {
    return `${normalized}:missing`;
  }
}

function collectAuthJsonFiles(rootDir, matcher = null) {
  const out = [];
  const seen = new Set();
  const stack = [];

  const pushDir = (candidate) => {
    const dirPath = normalizePathRef(candidate);
    if (!dirPath || seen.has(dirPath) || !fs.existsSync(dirPath)) return;
    let stat;
    try {
      stat = fs.statSync(dirPath);
    } catch {
      return;
    }
    if (!stat.isDirectory()) return;
    seen.add(dirPath);
    stack.push(dirPath);
  };

  const rootPath = normalizePathRef(rootDir);
  if (rootPath) {
    try {
      const stat = fs.statSync(rootPath);
      if (stat.isFile()) {
        if (rootPath.endsWith('.json') && (!matcher || matcher(rootPath))) {
          return [rootPath];
        }
        return [];
      }
    } catch {
      return [];
    }
  }

  pushDir(rootPath);
  pushDir(path.join(rootPath, 'auth'));
  pushDir(path.join(rootPath, 'auth-disabled'));
  pushDir(path.join(path.dirname(rootPath), 'auth-disabled'));

  while (stack.length > 0) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (entry.name.startsWith('.')) continue;
        stack.push(entryPath);
        continue;
      }
      if (!entry.isFile() || !entry.name.endsWith('.json')) continue;
      if (matcher && !matcher(entryPath)) continue;
      out.push(entryPath);
    }
  }

  return out.sort((lhs, rhs) => lhs.localeCompare(rhs));
}

function isLikelyCodexAuthFilename(filePath) {
  return /^auth(?:\d+)?\.json$/.test(path.basename(String(filePath || '')).toLowerCase());
}

function parseTomlStringValue(rawContent, key) {
  const escapedKey = String(key || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`^\\s*${escapedKey}\\s*=\\s*"([^"]*)"\\s*$`, 'm');
  const match = String(rawContent || '').match(pattern);
  return match ? safeString(match[1]) : '';
}

function authDirFingerprint(dirPath) {
  const dir = normalizePathRef(dirPath);
  if (!dir || !fs.existsSync(dir)) return `${dir}:missing`;
  const files = collectAuthJsonFiles(dir);
  const parts = [fileSignature(dir), ...files.map((filePath) => fileSignature(filePath))];
  return parts.join('|');
}

function configPathFingerprint(configPath) {
  const fp = normalizePathRef(configPath);
  if (!fp || !fs.existsSync(fp)) return `${fp}:missing`;

  const parts = [fileSignature(fp)];
  if (fp.toLowerCase().endsWith('.toml')) {
    let rawToml = '';
    try {
      rawToml = fs.readFileSync(fp, 'utf8');
    } catch {
      return `${fp}:unreadable`;
    }
    const explicitAuthFile = parseTomlStringValue(rawToml, 'auth_file');
    if (explicitAuthFile) {
      const authPath = path.isAbsolute(explicitAuthFile)
        ? explicitAuthFile
        : path.resolve(path.dirname(fp), explicitAuthFile);
      parts.push(...collectAuthJsonFiles(authPath).map((filePath) => fileSignature(filePath)));
    } else {
      parts.push(...collectAuthJsonFiles(
        path.dirname(fp),
        (candidate) => isLikelyCodexAuthFilename(candidate)
      ).map((filePath) => fileSignature(filePath)));
    }
  }

  return parts.join('|');
}

function sourceFingerprint(source) {
  if (!source) return '';
  if (source.kind === 'auth_dir') {
    return authDirFingerprint(source.source_ref);
  }
  if (source.kind === 'config_path') {
    return configPathFingerprint(source.source_ref);
  }
  return '';
}

function syncImportSource(runtimeBaseDir, source, logger) {
  const sourceRef = normalizePathRef(source?.source_ref);
  if (!sourceRef) return;
  if (!fs.existsSync(sourceRef)) {
    const prune = pruneProviderKeyImportOwner(runtimeBaseDir, source);
    if (!prune.ok && logger?.warn) {
      logger.warn(`[provider_key_source_watcher] prune failed for ${source.kind}:${sourceRef}: ${prune.error}`);
    }
    const status = recordProviderKeyImportSourceStatus(runtimeBaseDir, source, {
      state: 'missing',
      touch_last_sync: true,
      last_imported_count: 0,
      refresh_owned_account_count: true,
      last_error_count: 1,
      last_errors: ['source_path_missing'],
    });
    if (!status.ok && logger?.warn) {
      logger.warn(`[provider_key_source_watcher] status update failed for ${source.kind}:${sourceRef}: ${status.error}`);
    }
    return;
  }

  const result = source.kind === 'auth_dir'
    ? importAuthDir(runtimeBaseDir, sourceRef)
    : importProxyConfig(runtimeBaseDir, sourceRef);
  if (!result.ok && logger?.warn) {
    logger.warn(`[provider_key_source_watcher] sync failed for ${source.kind}:${sourceRef}: ${JSON.stringify(result.errors || [])}`);
  }
}

export function startProviderKeySourceWatcher({
  runtimeBaseDir,
  pollIntervalMs = DEFAULT_POLL_INTERVAL_MS,
  logger = console,
} = {}) {
  const baseDir = normalizePathRef(runtimeBaseDir);
  if (!baseDir) {
    return () => {};
  }

  const fingerprints = new Map();
  let interval = null;
  let inFlight = false;

  const tick = () => {
    if (inFlight) return;
    inFlight = true;
    try {
      const sourceKeys = listProviderKeyImportSources(baseDir);
      const active = new Set();
      for (const sourceKey of sourceKeys) {
        const source = parseImportSourceKey(sourceKey);
        if (!source) continue;
        active.add(sourceKey);
        const fingerprint = sourceFingerprint(source);
        if (fingerprint === fingerprints.get(sourceKey)) {
          continue;
        }
        syncImportSource(baseDir, source, logger);
        fingerprints.set(sourceKey, fingerprint);
      }

      for (const knownKey of Array.from(fingerprints.keys())) {
        if (!active.has(knownKey)) {
          fingerprints.delete(knownKey);
        }
      }
    } finally {
      inFlight = false;
    }
  };

  tick();
  interval = setInterval(tick, Math.max(250, Number(pollIntervalMs || DEFAULT_POLL_INTERVAL_MS)));
  interval.unref?.();

  return () => {
    if (interval) {
      clearInterval(interval);
      interval = null;
    }
  };
}
