function safeStr(v) {
  return String(v || '').trim();
}

function round6(v) {
  return Number(Number.isFinite(Number(v)) ? Number(v).toFixed(6) : '0');
}

export const TRUST_SHARD_ORDER = Object.freeze(['public', 'internal', 'secret']);

export function normalizeSensitivity(v) {
  const s = safeStr(v).toLowerCase();
  if (s === 'secret') return 'secret';
  if (s === 'internal') return 'internal';
  return 'public';
}

export function normalizeTrust(v) {
  const s = safeStr(v).toLowerCase();
  if (s === 'untrusted') return 'untrusted';
  return 'trusted';
}

function normalizeAllowedSensitivityList(v, { remoteMode } = {}) {
  const input = Array.isArray(v) && v.length ? v : ['public', 'internal', 'secret'];
  const allowed = new Set(input.map((x) => normalizeSensitivity(x)));
  // Fail-closed: remote path never routes secret shard in M2-W2-03.
  if (remoteMode) allowed.delete('secret');
  if (allowed.size <= 0) {
    allowed.add('public');
    allowed.add('internal');
    if (!remoteMode) allowed.add('secret');
  }
  return allowed;
}

function defaultShardMap() {
  return {
    public: [],
    internal: [],
    secret: [],
  };
}

export function routeMemoryByTrustShards(input = {}) {
  const docs = Array.isArray(input?.documents) ? input.documents : [];
  const remoteMode = !!input?.remote_mode;
  const allowUntrusted = !!input?.allow_untrusted;
  const allowedSensitivitySet = normalizeAllowedSensitivityList(input?.allowed_sensitivity, { remoteMode });

  const shards = defaultShardMap();
  const routed = [];

  let droppedSecretRemote = 0;
  let droppedUntrusted = 0;

  for (const src of docs) {
    const doc = src && typeof src === 'object' ? { ...src } : {};
    const sensitivity = normalizeSensitivity(doc.sensitivity);
    const trustLevel = normalizeTrust(doc.trust_level);
    doc.sensitivity = sensitivity;
    doc.trust_level = trustLevel;

    shards[sensitivity].push(doc);

    if (remoteMode && sensitivity === 'secret') {
      droppedSecretRemote += 1;
      continue;
    }
    if (!allowedSensitivitySet.has(sensitivity)) continue;
    if (!allowUntrusted && trustLevel === 'untrusted') {
      droppedUntrusted += 1;
      continue;
    }
    routed.push(doc);
  }

  const inputByShard = {
    public: shards.public.length,
    internal: shards.internal.length,
    secret: shards.secret.length,
  };

  const routedByShard = {
    public: 0,
    internal: 0,
    secret: 0,
  };
  for (const d of routed) {
    const s = normalizeSensitivity(d?.sensitivity);
    routedByShard[s] += 1;
  }

  return {
    documents: routed,
    shards,
    policy: {
      remote_mode: remoteMode,
      allow_untrusted: allowUntrusted,
      allowed_sensitivity: TRUST_SHARD_ORDER.filter((s) => allowedSensitivitySet.has(s)),
      forced_secret_remote_deny: remoteMode,
    },
    stats: {
      input_total: docs.length,
      input_by_shard: inputByShard,
      routed_total: routed.length,
      routed_by_shard: routedByShard,
      dropped_secret_remote: droppedSecretRemote,
      dropped_untrusted: droppedUntrusted,
    },
  };
}

export function buildTrustShardHitStats({ routeResult, retrievalResults } = {}) {
  const routedByShard = routeResult?.stats?.routed_by_shard || { public: 0, internal: 0, secret: 0 };
  const rows = Array.isArray(retrievalResults) ? retrievalResults : [];

  const hitByShard = {
    public: 0,
    internal: 0,
    secret: 0,
  };

  for (const row of rows) {
    const s = normalizeSensitivity(row?.sensitivity);
    hitByShard[s] += 1;
  }

  const hitRateByShard = {
    public: routedByShard.public > 0 ? round6(hitByShard.public / routedByShard.public) : 0,
    internal: routedByShard.internal > 0 ? round6(hitByShard.internal / routedByShard.internal) : 0,
    secret: routedByShard.secret > 0 ? round6(hitByShard.secret / routedByShard.secret) : 0,
  };

  return {
    hit_total: hitByShard.public + hitByShard.internal + hitByShard.secret,
    hit_by_shard: hitByShard,
    hit_rate_by_shard: hitRateByShard,
  };
}
