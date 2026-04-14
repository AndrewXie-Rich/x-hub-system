import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function safeString(value) {
  return String(value ?? '').trim();
}

function expandHome(input) {
  const value = safeString(input);
  if (!value) return '';
  if (value === '~') return os.homedir();
  if (value.startsWith('~/')) return path.join(os.homedir(), value.slice(2));
  return value;
}

function firstNonEmpty(...values) {
  for (const raw of values) {
    const value = safeString(raw);
    if (value) return value;
  }
  return '';
}

function readJsonSafe(filePath) {
  try {
    return JSON.parse(fs.readFileSync(String(filePath || ''), 'utf8'));
  } catch {
    return null;
  }
}

function shellUnquote(value) {
  const text = safeString(value);
  if (text.length < 2) return text;
  if ((text.startsWith("'") && text.endsWith("'")) || (text.startsWith('"') && text.endsWith('"'))) {
    return text.slice(1, -1);
  }
  return text;
}

function readEnvFile(filePath) {
  const out = {};
  const text = safeString(filePath);
  if (!text) return out;
  let raw = '';
  try {
    raw = fs.readFileSync(text, 'utf8');
  } catch {
    return out;
  }
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = safeString(line);
    if (!trimmed || trimmed.startsWith('#')) continue;
    const normalized = trimmed.startsWith('export ')
      ? safeString(trimmed.slice('export '.length))
      : trimmed;
    const index = normalized.indexOf('=');
    if (index <= 0) continue;
    const key = safeString(normalized.slice(0, index));
    if (!key) continue;
    out[key] = shellUnquote(normalized.slice(index + 1));
  }
  return out;
}

function normalizeHostOnly(value) {
  const raw = safeString(value);
  if (!raw) return '';
  if (/^[a-z][a-z0-9+\-.]*:\/\//i.test(raw)) {
    try {
      return safeString(new URL(raw).hostname).toLowerCase();
    } catch {
      return '';
    }
  }
  if (raw.startsWith('[')) {
    const end = raw.indexOf(']');
    if (end > 1) return safeString(raw.slice(1, end)).toLowerCase();
  }
  const colonCount = (raw.match(/:/g) || []).length;
  if (colonCount === 1 && raw.includes(':')) {
    return safeString(raw.split(':')[0]).toLowerCase();
  }
  return raw.toLowerCase();
}

function isLoopbackHost(value) {
  const host = normalizeHostOnly(value);
  return host === 'localhost' || host === '127.0.0.1' || host === '::1' || host === '[::1]';
}

function isUsableInternetHost(value) {
  const host = normalizeHostOnly(value);
  if (!host) return false;
  if (host === '0.0.0.0') return false;
  if (host.endsWith('.local')) return false;
  return !isLoopbackHost(host);
}

function normalizeHubInstanceId(value) {
  const lowered = safeString(value).toLowerCase();
  if (!lowered) return '';
  const normalized = lowered
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^[-_]+|[-_]+$/g, '');
  if (!/^[a-z0-9][a-z0-9_-]{7,63}$/.test(normalized)) return '';
  return normalized;
}

function normalizeLanDiscoveryName(value) {
  const lowered = safeString(value).toLowerCase();
  if (!lowered) return '';
  const normalized = lowered
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (!/^[a-z0-9][a-z0-9-]{2,62}$/.test(normalized)) return '';
  return normalized;
}

function createHubInstanceId() {
  return `hub_${crypto.randomBytes(10).toString('hex')}`;
}

function defaultLanDiscoveryName(hubInstanceId) {
  const normalizedId = normalizeHubInstanceId(hubInstanceId) || createHubInstanceId();
  const suffix = normalizedId
    .replace(/^hub[_-]?/, '')
    .replace(/[^a-z0-9]+/g, '')
    .slice(0, 10);
  const candidate = `axhub-${suffix || crypto.randomBytes(4).toString('hex')}`;
  return normalizeLanDiscoveryName(candidate) || 'axhub-local';
}

function hubIdentityFilePath(runtimeBaseDir = '') {
  return path.join(expandHome(runtimeBaseDir), 'hub_identity.json');
}

function resolveAxhubStateDir(env = process.env) {
  const explicit = firstNonEmpty(env.AXHUB_STATE_DIR, env.AXHUBCTL_STATE_DIR);
  if (explicit) return expandHome(explicit);
  return path.join(os.homedir(), '.axhub');
}

export function resolveHubIdentity({
  runtimeBaseDir = '',
  env = process.env,
} = {}) {
  const base = expandHome(runtimeBaseDir);
  const envHubInstanceId = normalizeHubInstanceId(env.HUB_INSTANCE_ID);
  const envLanDiscoveryName = normalizeLanDiscoveryName(env.HUB_LAN_DISCOVERY_NAME);
  const filePath = base ? hubIdentityFilePath(base) : '';

  let persisted = null;
  if (filePath) {
    persisted = readJsonSafe(filePath);
  }

  const persistedHubInstanceId = normalizeHubInstanceId(persisted?.hub_instance_id);
  const persistedLanDiscoveryName = normalizeLanDiscoveryName(persisted?.lan_discovery_name);
  const createdAtMs = Math.max(0, Number(persisted?.created_at_ms || 0)) || Date.now();

  const hubInstanceId = envHubInstanceId || persistedHubInstanceId || createHubInstanceId();
  const lanDiscoveryName = envLanDiscoveryName
    || persistedLanDiscoveryName
    || defaultLanDiscoveryName(hubInstanceId);

  const identity = {
    schema_version: 'xhub.hub_identity.v1',
    hub_instance_id: hubInstanceId,
    lan_discovery_name: lanDiscoveryName,
    created_at_ms: createdAtMs,
  };

  if (filePath && !envHubInstanceId && !envLanDiscoveryName) {
    const shouldWrite = !persisted
      || persistedHubInstanceId !== hubInstanceId
      || persistedLanDiscoveryName !== lanDiscoveryName
      || Number(persisted?.created_at_ms || 0) !== createdAtMs;
    if (shouldWrite) {
      try {
        fs.mkdirSync(path.dirname(filePath), { recursive: true });
        fs.writeFileSync(filePath, `${JSON.stringify(identity, null, 2)}\n`, 'utf8');
      } catch {
        // Ignore persistence failures; callers can still use the in-memory identity.
      }
    }
  }

  return {
    ...identity,
    file_path: filePath,
  };
}

export function resolveHubInternetHostHint({
  runtimeBaseDir = '',
  env = process.env,
} = {}) {
  const explicit = normalizeHostOnly(firstNonEmpty(
    env.HUB_PAIRING_PUBLIC_HOST,
    env.HUB_INTERNET_HOST,
    env.AXHUB_INTERNET_HOST,
    env.HUB_TAILNET_HOST,
    env.HUB_TAILSCALE_HOST,
    env.TAILSCALE_DNS_NAME,
  ));
  if (isUsableInternetHost(explicit)) return explicit;

  const tunnelConfigPath = expandHome(firstNonEmpty(
    env.AXHUB_TUNNEL_CONFIG_ENV_PATH,
    path.join(resolveAxhubStateDir(env), 'tunnel_config.env'),
  ));
  const tunnelEnv = readEnvFile(tunnelConfigPath);
  const remoteHost = normalizeHostOnly(tunnelEnv.AXHUB_TUNNEL_REMOTE_HOST);
  if (isUsableInternetHost(remoteHost)) return remoteHost;

  const runtimeBase = expandHome(runtimeBaseDir);
  if (runtimeBase) {
    const runtimeTunnelConfig = readEnvFile(path.join(runtimeBase, 'axhub_tunnel_config.env'));
    const runtimeRemoteHost = normalizeHostOnly(runtimeTunnelConfig.AXHUB_TUNNEL_REMOTE_HOST);
    if (isUsableInternetHost(runtimeRemoteHost)) return runtimeRemoteHost;
  }

  return '';
}
