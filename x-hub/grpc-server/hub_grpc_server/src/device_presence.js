import fs from 'node:fs';
import path from 'node:path';

function safeString(value) {
  return String(value ?? '').trim();
}

function boundedInt(raw, { fallback, min, max }) {
  const n = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function nonNegativeInt(raw, fallback = 0) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function writeJsonAtomic(filePath, obj) {
  const out = safeString(filePath);
  if (!out) return false;
  try {
    fs.mkdirSync(path.dirname(out), { recursive: true });
  } catch {
    // ignore
  }

  const tmp = `${out}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  try {
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', { encoding: 'utf8' });
    fs.renameSync(tmp, out);
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

export function devicePresenceTTLms() {
  return boundedInt(process.env.HUB_REMOTE_DEVICE_PRESENCE_TTL_MS, {
    fallback: 90_000,
    min: 20_000,
    max: 10 * 60 * 1000,
  });
}

function devicePresencePruneTTLms() {
  return boundedInt(process.env.HUB_REMOTE_DEVICE_PRESENCE_PRUNE_TTL_MS, {
    fallback: 24 * 60 * 60 * 1000,
    min: devicePresenceTTLms(),
    max: 7 * 24 * 60 * 60 * 1000,
  });
}

export function devicePresencePath(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'grpc_device_presence.json');
}

function normalizeEntry(raw, fallbackNowMs = Date.now()) {
  const device_id = safeString(raw?.device_id);
  if (!device_id) return null;

  const lastSeenAtMs = nonNegativeInt(raw?.last_seen_at_ms, fallbackNowMs) || fallbackNowMs;
  const firstSeenCandidate = nonNegativeInt(raw?.first_seen_at_ms, lastSeenAtMs) || lastSeenAtMs;
  const firstSeenAtMs = Math.min(firstSeenCandidate, lastSeenAtMs);

  return {
    device_id,
    app_id: safeString(raw?.app_id),
    name: safeString(raw?.name || raw?.device_name) || device_id,
    peer_ip: safeString(raw?.peer_ip),
    transport_mode: safeString(raw?.transport_mode),
    route: safeString(raw?.route),
    source: safeString(raw?.source) || 'paired_client_presence',
    first_seen_at_ms: firstSeenAtMs,
    last_seen_at_ms: lastSeenAtMs,
    updated_at_ms: nonNegativeInt(raw?.updated_at_ms, fallbackNowMs) || fallbackNowMs,
  };
}

function emptySnapshot() {
  return {
    schema_version: 'grpc_device_presence.v1',
    updated_at_ms: 0,
    presence_ttl_ms: devicePresenceTTLms(),
    devices: [],
  };
}

export function loadDevicePresenceSnapshot(runtimeBaseDir) {
  const filePath = devicePresencePath(runtimeBaseDir);
  if (!filePath) return emptySnapshot();

  let parsed = null;
  try {
    parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    parsed = null;
  }

  if (!parsed || typeof parsed !== 'object') {
    return emptySnapshot();
  }

  const now = Date.now();
  const rawDevices = Array.isArray(parsed.devices) ? parsed.devices : [];
  const devices = rawDevices
    .map((entry) => normalizeEntry(entry, now))
    .filter(Boolean);

  return {
    schema_version: safeString(parsed.schema_version) || 'grpc_device_presence.v1',
    updated_at_ms: nonNegativeInt(parsed.updated_at_ms, 0),
    presence_ttl_ms: nonNegativeInt(parsed.presence_ttl_ms, devicePresenceTTLms()) || devicePresenceTTLms(),
    devices,
  };
}

export function isDevicePresenceFresh(entry, nowMs = Date.now(), ttlMs = devicePresenceTTLms()) {
  const lastSeenAtMs = nonNegativeInt(entry?.last_seen_at_ms, 0);
  if (lastSeenAtMs <= 0) return false;
  if (lastSeenAtMs > nowMs + 2_000) return false;
  return (nowMs - lastSeenAtMs) <= Math.max(1_000, nonNegativeInt(ttlMs, devicePresenceTTLms()));
}

export function upsertDevicePresence(runtimeBaseDir, rawEntry) {
  const base = safeString(runtimeBaseDir);
  if (!base) return null;

  const now = Date.now();
  const incoming = normalizeEntry(
    {
      ...(rawEntry && typeof rawEntry === 'object' ? rawEntry : {}),
      updated_at_ms: now,
      last_seen_at_ms: nonNegativeInt(rawEntry?.last_seen_at_ms, now) || now,
    },
    now
  );
  if (!incoming) return null;

  const snapshot = loadDevicePresenceSnapshot(base);
  const pruneTTL = devicePresencePruneTTLms();
  const byDeviceId = new Map();

  for (const existing of Array.isArray(snapshot.devices) ? snapshot.devices : []) {
    const normalized = normalizeEntry(existing, now);
    if (!normalized) continue;
    if ((now - normalized.last_seen_at_ms) > pruneTTL) continue;
    byDeviceId.set(normalized.device_id, normalized);
  }

  const previous = byDeviceId.get(incoming.device_id) || null;
  const merged = {
    device_id: incoming.device_id,
    app_id: incoming.app_id || safeString(previous?.app_id),
    name: incoming.name || safeString(previous?.name) || incoming.device_id,
    peer_ip: incoming.peer_ip || safeString(previous?.peer_ip),
    transport_mode: incoming.transport_mode || safeString(previous?.transport_mode),
    route: incoming.route || safeString(previous?.route),
    source: incoming.source || safeString(previous?.source) || 'paired_client_presence',
    first_seen_at_ms: previous
      ? Math.min(
          nonNegativeInt(previous.first_seen_at_ms, incoming.first_seen_at_ms) || incoming.first_seen_at_ms,
          incoming.last_seen_at_ms
        )
      : incoming.first_seen_at_ms,
    last_seen_at_ms: incoming.last_seen_at_ms,
    updated_at_ms: now,
  };

  byDeviceId.set(merged.device_id, merged);

  const devices = Array.from(byDeviceId.values()).sort((left, right) => {
    const leftName = safeString(left.name || left.device_id).toLowerCase();
    const rightName = safeString(right.name || right.device_id).toLowerCase();
    if (leftName !== rightName) return leftName < rightName ? -1 : 1;
    return safeString(left.device_id).localeCompare(safeString(right.device_id));
  });

  writeJsonAtomic(devicePresencePath(base), {
    schema_version: 'grpc_device_presence.v1',
    updated_at_ms: now,
    presence_ttl_ms: devicePresenceTTLms(),
    devices,
  });

  return merged;
}
