import fs from 'node:fs';
import path from 'node:path';

function safeInt(v, def = 0) {
  const n = Number(v || 0);
  if (!Number.isFinite(n)) return def;
  return Math.max(0, Math.floor(n));
}

let cache = {
  loaded_at_ms: 0,
  file_path: '',
  obj: null,
};

export function quotaConfigPath(runtimeBaseDir) {
  const base = String(runtimeBaseDir || '').trim();
  if (!base) return '';
  return path.join(base, 'hub_quotas.json');
}

export function utcDayKey(epochMs = Date.now()) {
  const ms = safeInt(epochMs, Date.now());
  return new Date(ms).toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
}

export function loadQuotaConfig(runtimeBaseDir, maxAgeMs = 1000) {
  const fp = quotaConfigPath(runtimeBaseDir);
  if (!fp) {
    return { default_daily_token_cap: 0, devices: {} };
  }

  const now = Date.now();
  if (cache.obj && cache.file_path === fp && now - cache.loaded_at_ms <= Math.max(200, Number(maxAgeMs || 0))) {
    return cache.obj;
  }

  let obj = null;
  try {
    const raw = fs.readFileSync(fp, 'utf8');
    obj = JSON.parse(raw);
  } catch {
    obj = null;
  }

  const devicesIn = obj && typeof obj === 'object' && obj.devices && typeof obj.devices === 'object' ? obj.devices : {};
  const devices = {};
  for (const [k, v] of Object.entries(devicesIn)) {
    const id = String(k || '').trim();
    if (!id) continue;
    if (typeof v === 'number') {
      devices[id] = { daily_token_cap: safeInt(v, 0) };
      continue;
    }
    if (v && typeof v === 'object') {
      devices[id] = { daily_token_cap: safeInt(v.daily_token_cap ?? v.dailyTokenCap, 0) };
    }
  }

  const out = {
    default_daily_token_cap: safeInt(obj?.default_daily_token_cap ?? obj?.defaultDailyTokenCap, 0),
    devices,
  };

  cache = { loaded_at_ms: now, file_path: fp, obj: out };
  return out;
}

export function resolveDeviceDailyTokenCap(cfg, deviceId) {
  const dev = String(deviceId || '').trim();
  if (!dev) return safeInt(cfg?.default_daily_token_cap, 0);
  const cap = cfg?.devices?.[dev]?.daily_token_cap;
  if (cap != null) return safeInt(cap, 0);
  return safeInt(cfg?.default_daily_token_cap, 0);
}

