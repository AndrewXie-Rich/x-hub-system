export const MEMORY_METRICS_SCHEMA_VERSION = 'xhub.memory.metrics.v1';

const METRIC_CODE_RE = /^[a-z0-9._:-]{1,128}$/i;
const MAX_SAFE_INT = 9007199254740991;
const MAX_COST_USD = 1000000000;
const MAX_REASON_LEN = 256;
const MAX_SCOPE_ID_LEN = 128;

function safeCode(v) {
  const raw = String(v || '').trim().toLowerCase();
  if (!raw) return '';
  if (METRIC_CODE_RE.test(raw)) return raw;
  return '';
}

function safeDenyCode(v) {
  const raw = String(v || '').trim().toLowerCase();
  if (!raw) return '';
  const head = raw.includes(':') ? raw.split(':')[0] : raw;
  const normalizedHead = safeCode(head);
  if (normalizedHead) return normalizedHead;
  const normalizedRaw = safeCode(raw);
  return normalizedRaw || 'unknown';
}

function safeReason(v) {
  const raw = String(v || '').trim();
  if (!raw) return '';
  const compact = raw.replace(/\s+/g, ' ');
  if (compact.length > MAX_REASON_LEN) return compact.slice(0, MAX_REASON_LEN);
  return compact;
}

function safeScopeId(v) {
  const raw = String(v || '').trim();
  if (!raw) return '';
  const compact = raw.replace(/\s+/g, ' ');
  if (compact.length > MAX_SCOPE_ID_LEN) return compact.slice(0, MAX_SCOPE_ID_LEN);
  return compact;
}

function boolOrDefault(v, fallback = false) {
  if (v == null) return !!fallback;
  return !!v;
}

function boolOrNull(v) {
  if (v == null) return null;
  return !!v;
}

function intOrNull(v, minValue = 0, maxValue = MAX_SAFE_INT) {
  if (v == null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const x = Math.floor(n);
  return Math.max(minValue, Math.min(maxValue, x));
}

function numberOrNull(v, minValue = 0, maxValue = MAX_SAFE_INT) {
  if (v == null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const clamped = Math.max(minValue, Math.min(maxValue, n));
  return Number(clamped.toFixed(6));
}

function ratioOrNull(v) {
  return numberOrNull(v, 0, 1);
}

function normalizeBlock(src = {}) {
  return src && typeof src === 'object' ? src : {};
}

function normalizeScope(scope = {}) {
  const src = scope && typeof scope === 'object' ? scope : {};
  return {
    kind: safeCode(src.kind || src.scope || src.scope_kind || ''),
    device_id: safeScopeId(src.device_id),
    user_id: safeScopeId(src.user_id),
    app_id: safeScopeId(src.app_id),
    project_id: safeScopeId(src.project_id),
    thread_id: safeScopeId(src.thread_id),
  };
}

export function buildMemoryMetricsPayload(input = {}) {
  const src = input && typeof input === 'object' ? input : {};
  const latency = normalizeBlock(src.latency);
  const quality = normalizeBlock(src.quality);
  const cost = normalizeBlock(src.cost);
  const freshness = normalizeBlock(src.freshness);
  const security = normalizeBlock(src.security);
  const scope = normalizeScope(src.scope);

  const blocked = boolOrDefault(security.blocked, false);
  const denyReason = safeReason(
    security.deny_reason
    || src.deny_reason
    || security.deny_code
    || src.deny_code
    || ''
  );
  let denyCode = safeDenyCode(
    security.deny_code
    || denyReason
    || src.deny_code
    || ''
  );
  if (blocked && !denyCode) denyCode = 'blocked';
  const normalizedDenyReason = denyReason || (denyCode || '');

  return {
    schema_version: MEMORY_METRICS_SCHEMA_VERSION,
    event_kind: safeCode(src.event_kind || src.event_type || ''),
    job_type: safeCode(src.job_type || src.op || src.event_kind || src.event_type || ''),
    op: safeCode(src.op || ''),
    channel: safeCode(src.channel || ''),
    remote_mode: boolOrDefault(src.remote_mode, false),
    scope,
    latency: {
      duration_ms: intOrNull(latency.duration_ms),
      queue_wait_ms: intOrNull(latency.queue_wait_ms),
      first_token_ms: intOrNull(latency.first_token_ms),
      wall_time_ms: intOrNull(latency.wall_time_ms),
    },
    quality: {
      recall_at_k: ratioOrNull(quality.recall_at_k),
      precision_at_k: ratioOrNull(quality.precision_at_k),
      ndcg_at_k: ratioOrNull(quality.ndcg_at_k),
      result_count: intOrNull(quality.result_count),
      total_items: intOrNull(quality.total_items),
      included_items: intOrNull(quality.included_items),
      findings_count: intOrNull(quality.findings_count),
      redacted_count: intOrNull(quality.redacted_count),
      patch_size_chars: intOrNull(quality.patch_size_chars),
      patch_line_count: intOrNull(quality.patch_line_count),
      session_revision: intOrNull(quality.session_revision),
      truncated: boolOrNull(quality.truncated),
      score_explain_enabled: boolOrNull(quality.score_explain_enabled),
      auto_rejected: boolOrNull(quality.auto_rejected),
    },
    cost: {
      prompt_tokens: intOrNull(cost.prompt_tokens),
      completion_tokens: intOrNull(cost.completion_tokens),
      total_tokens: intOrNull(cost.total_tokens),
      cost_usd_estimate: numberOrNull(cost.cost_usd_estimate, 0, MAX_COST_USD),
    },
    freshness: {
      index_freshness_ms: intOrNull(freshness.index_freshness_ms),
      exported_at_ms: intOrNull(freshness.exported_at_ms),
      source_updated_at_ms: intOrNull(freshness.source_updated_at_ms),
      snapshot_version: safeCode(freshness.snapshot_version || freshness.version || ''),
    },
    security: {
      blocked,
      downgraded: boolOrDefault(security.downgraded, false),
      deny_code: denyCode,
      deny_reason: normalizedDenyReason,
    },
  };
}

export function attachMemoryMetrics(ext = {}, metricsInput = {}) {
  const base = ext && typeof ext === 'object' ? { ...ext } : {};
  base.metrics = buildMemoryMetricsPayload(metricsInput);
  if (base.queue_wait_ms == null && base.metrics?.latency?.queue_wait_ms != null) {
    base.queue_wait_ms = base.metrics.latency.queue_wait_ms;
  }
  return base;
}
