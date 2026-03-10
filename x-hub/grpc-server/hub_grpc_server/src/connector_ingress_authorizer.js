import { nowMs } from './util.js';

export const CONNECTOR_INGRESS_TYPES = ['message', 'reaction', 'pin', 'member', 'webhook'];
export const NON_MESSAGE_INGRESS_TYPES = ['reaction', 'pin', 'member', 'webhook'];
export const NON_MESSAGE_INGRESS_GATE_EVIDENCE_SCHEMA = 'xhub.connector.non_message_ingress_gate.v1';
export const NON_MESSAGE_INGRESS_GATE_DEFAULT_THRESHOLDS = Object.freeze({
  non_message_ingress_policy_coverage_min: 1,
  blocked_event_miss_rate_max_exclusive: 0.01,
});

const ING_TYPE_SET = new Set(CONNECTOR_INGRESS_TYPES);
const NON_MESSAGE_SET = new Set(NON_MESSAGE_INGRESS_TYPES);

function safeString(input) {
  return String(input || '').trim();
}

function asStringSet(input) {
  const out = new Set();
  const rows = Array.isArray(input) ? input : [];
  for (const raw of rows) {
    const s = safeString(raw);
    if (!s) continue;
    out.add(s);
  }
  return out;
}

function normalizeIngressType(input) {
  const t = safeString(input).toLowerCase();
  return ING_TYPE_SET.has(t) ? t : '';
}

function normalizeChannelScope(input) {
  const raw = safeString(input).toLowerCase();
  if (raw === 'dm' || raw === 'direct' || raw === 'direct_message') return 'dm';
  if (raw === 'group' || raw === 'channel' || raw === 'room') return 'group';
  return 'group';
}

function normalizePolicy(input = {}) {
  const src = input && typeof input === 'object' ? input : {};
  return {
    dm_allow_from: asStringSet(src.dm_allow_from || src.dm_allowlist || src.dm_allow || []),
    dm_pairing_allow_from: asStringSet(src.dm_pairing_allow_from || src.dm_pairing_allowlist || src.dm_pairing_allow || []),
    group_allow_from: asStringSet(src.group_allow_from || src.group_allowlist || src.group_allow || []),
    webhook_allow_from: asStringSet(src.webhook_allow_from || src.webhook_allowlist || src.webhook_allow || []),
  };
}

function normalizeIngressEvent(input = {}) {
  const src = input && typeof input === 'object' ? input : {};
  const ingress_type = normalizeIngressType(src.ingress_type || src.event_type || src.type);
  const channel_scope = normalizeChannelScope(src.channel_scope || src.scope || src.channel_type);
  return {
    ingress_type,
    channel_scope,
    sender_id: safeString(src.sender_id || src.actor_id || src.member_id || src.user_id),
    channel_id: safeString(src.channel_id || src.room_id || src.thread_id),
    message_id: safeString(src.message_id || src.event_id),
    source_id: safeString(src.source_id || src.webhook_id || src.app_id),
    signature_valid: src.signature_valid !== false,
    replay_detected: src.replay_detected === true,
  };
}

function deny(event, deny_code, detail) {
  return {
    allowed: false,
    deny_code: safeString(deny_code) || 'authz_denied',
    detail: safeString(detail) || 'connector_ingress_denied',
    ingress_type: event.ingress_type,
    channel_scope: event.channel_scope,
    non_message_ingress: NON_MESSAGE_SET.has(event.ingress_type),
    policy_checked: true,
    blocked: true,
  };
}

function allow(event) {
  return {
    allowed: true,
    deny_code: '',
    detail: 'allow',
    ingress_type: event.ingress_type,
    channel_scope: event.channel_scope,
    non_message_ingress: NON_MESSAGE_SET.has(event.ingress_type),
    policy_checked: true,
    blocked: false,
  };
}

export function authorizeConnectorIngress({ event = {}, policy = {} } = {}) {
  const e = normalizeIngressEvent(event);
  const p = normalizePolicy(policy);

  if (!e.ingress_type) {
    return deny(e, 'ingress_type_unsupported', 'unsupported connector ingress type');
  }

  if (e.ingress_type === 'webhook') {
    if (!e.source_id) {
      return deny(e, 'invalid_event', 'missing webhook source_id');
    }
    if (e.replay_detected) {
      return deny(e, 'webhook_replay_detected', 'webhook replay denied');
    }
    if (!e.signature_valid) {
      return deny(e, 'webhook_signature_invalid', 'webhook signature invalid');
    }
    if (!p.webhook_allow_from.has(e.source_id)) {
      return deny(e, 'webhook_not_allowlisted', 'webhook source is not in allowlist');
    }
    return allow(e);
  }

  if (!e.sender_id) {
    return deny(e, 'invalid_event', 'missing sender_id');
  }

  if (e.channel_scope === 'dm') {
    if (p.dm_allow_from.has(e.sender_id) || p.dm_pairing_allow_from.has(e.sender_id)) {
      return allow(e);
    }
    return deny(e, 'sender_not_allowlisted', 'sender is not allowed for dm ingress');
  }

  if (e.channel_scope === 'group') {
    if (p.group_allow_from.has(e.sender_id)) {
      return allow(e);
    }
    if (p.dm_pairing_allow_from.has(e.sender_id)) {
      // Critical boundary: DM pairing grant never auto-expands into group allowlist.
      return deny(e, 'dm_pairing_scope_violation', 'dm pairing does not grant group ingress permission');
    }
    return deny(e, 'sender_not_allowlisted', 'sender is not allowed for group ingress');
  }

  return deny(e, 'authz_denied', 'connector ingress denied');
}

function parseJsonLike(input) {
  if (!input) return {};
  if (input && typeof input === 'object') return input;
  const raw = safeString(input);
  if (!raw) return {};
  try {
    const out = JSON.parse(raw);
    return out && typeof out === 'object' ? out : {};
  } catch {
    return {};
  }
}

function ratio(n, d, fallback = 0) {
  if (!Number.isFinite(n) || !Number.isFinite(d) || d <= 0) return fallback;
  return n / d;
}

function asFiniteNumber(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? n : fallback;
}

function clamp(input, min, max, fallback) {
  const n = asFiniteNumber(input, fallback);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

export function buildNonMessageIngressScanStats(entries = []) {
  const rows = Array.isArray(entries) ? entries : [];
  let ingress_total = 0;
  let non_message_ingress_total = 0;
  let non_message_ingress_policy_checked = 0;
  let blocked_event_total = 0;
  let blocked_event_audited = 0;
  const by_type = {
    message: 0,
    reaction: 0,
    pin: 0,
    member: 0,
    webhook: 0,
  };

  for (const row of rows) {
    const r = row && typeof row === 'object' ? row : {};
    const ingress_type = normalizeIngressType(r.ingress_type || r.event_type || r.type);
    if (!ingress_type) continue;
    ingress_total += 1;
    by_type[ingress_type] += 1;

    const non_message_ingress = NON_MESSAGE_SET.has(ingress_type);
    if (non_message_ingress) {
      non_message_ingress_total += 1;
      if (r.policy_checked !== false) non_message_ingress_policy_checked += 1;
    }

    const blocked = r.blocked === true || r.allowed === false || !!safeString(r.deny_code);
    if (!blocked) continue;
    blocked_event_total += 1;
    if (r.audit_logged !== false) blocked_event_audited += 1;
  }

  const blocked_event_miss_total = Math.max(0, blocked_event_total - blocked_event_audited);
  const non_message_ingress_policy_coverage = ratio(
    non_message_ingress_policy_checked,
    non_message_ingress_total,
    1
  );
  const blocked_event_miss_rate = ratio(blocked_event_miss_total, blocked_event_total, 0);

  return {
    ingress_total,
    by_type,
    non_message_ingress_total,
    non_message_ingress_policy_checked,
    non_message_ingress_policy_coverage,
    blocked_event_total,
    blocked_event_audited,
    blocked_event_miss_total,
    blocked_event_miss_rate,
  };
}

export function buildNonMessageIngressScanStatsFromAuditRows(auditRows = []) {
  const rows = Array.isArray(auditRows) ? auditRows : [];
  const normalized = [];
  for (const row of rows) {
    const eventType = safeString(row?.event_type).toLowerCase();
    if (eventType !== 'connector.ingress.allowed' && eventType !== 'connector.ingress.denied') continue;
    const ext = parseJsonLike(row?.ext_json);
    normalized.push({
      ingress_type: ext.ingress_type,
      policy_checked: ext.policy_checked !== false,
      allowed: !!row?.ok,
      blocked: row?.ok === false,
      deny_code: safeString(row?.error_code || ext.deny_code),
      audit_logged: true,
    });
  }
  return buildNonMessageIngressScanStats(normalized);
}

export function buildNonMessageIngressGateEvidence({ stats = {}, thresholds = {} } = {}) {
  const s = stats && typeof stats === 'object' ? stats : {};
  const t = thresholds && typeof thresholds === 'object' ? thresholds : {};
  const coverageMin = clamp(
    t.non_message_ingress_policy_coverage_min,
    0,
    1,
    NON_MESSAGE_INGRESS_GATE_DEFAULT_THRESHOLDS.non_message_ingress_policy_coverage_min
  );
  const blockedMissRateMaxExclusive = clamp(
    t.blocked_event_miss_rate_max_exclusive,
    0,
    1,
    NON_MESSAGE_INGRESS_GATE_DEFAULT_THRESHOLDS.blocked_event_miss_rate_max_exclusive
  );

  const metrics = {
    ingress_total: Math.max(0, asFiniteNumber(s.ingress_total, 0)),
    non_message_ingress_total: Math.max(0, asFiniteNumber(s.non_message_ingress_total, 0)),
    non_message_ingress_policy_checked: Math.max(0, asFiniteNumber(s.non_message_ingress_policy_checked, 0)),
    non_message_ingress_policy_coverage: clamp(s.non_message_ingress_policy_coverage, 0, 1, 0),
    blocked_event_total: Math.max(0, asFiniteNumber(s.blocked_event_total, 0)),
    blocked_event_audited: Math.max(0, asFiniteNumber(s.blocked_event_audited, 0)),
    blocked_event_miss_total: Math.max(0, asFiniteNumber(s.blocked_event_miss_total, 0)),
    blocked_event_miss_rate: clamp(s.blocked_event_miss_rate, 0, 1, 0),
  };

  const coveragePass = metrics.non_message_ingress_policy_coverage >= coverageMin;
  const missRatePass = metrics.blocked_event_miss_rate < blockedMissRateMaxExclusive;
  const incident_codes = [];
  if (!coveragePass) incident_codes.push('non_message_ingress_policy_coverage_low');
  if (!missRatePass) incident_codes.push('blocked_event_miss_rate_high');

  return {
    schema_version: NON_MESSAGE_INGRESS_GATE_EVIDENCE_SCHEMA,
    measured_at_ms: nowMs(),
    thresholds: {
      non_message_ingress_policy_coverage_min: coverageMin,
      blocked_event_miss_rate_max_exclusive: blockedMissRateMaxExclusive,
    },
    metrics,
    checks: [
      {
        key: 'non_message_ingress_policy_coverage',
        pass: coveragePass,
        comparator: '>=',
        expected: coverageMin,
        actual: metrics.non_message_ingress_policy_coverage,
      },
      {
        key: 'blocked_event_miss_rate',
        pass: missRatePass,
        comparator: '<',
        expected: blockedMissRateMaxExclusive,
        actual: metrics.blocked_event_miss_rate,
      },
    ],
    pass: coveragePass && missRatePass,
    incident_codes,
  };
}

export function buildNonMessageIngressGateSnapshot({ stats = {}, thresholds = {} } = {}) {
  const evidence = buildNonMessageIngressGateEvidence({ stats, thresholds });
  const metrics = evidence && typeof evidence.metrics === 'object' ? evidence.metrics : {};
  return {
    schema_version: safeString(evidence?.schema_version || NON_MESSAGE_INGRESS_GATE_EVIDENCE_SCHEMA),
    measured_at_ms: Math.max(0, Number(evidence?.measured_at_ms || 0)),
    pass: evidence?.pass === true,
    incident_codes: Array.isArray(evidence?.incident_codes)
      ? evidence.incident_codes.map((code) => safeString(code)).filter(Boolean)
      : [],
    thresholds: evidence && typeof evidence.thresholds === 'object'
      ? {
          non_message_ingress_policy_coverage_min: Number(evidence.thresholds.non_message_ingress_policy_coverage_min || 0),
          blocked_event_miss_rate_max_exclusive: Number(evidence.thresholds.blocked_event_miss_rate_max_exclusive || 0),
        }
      : {},
    checks: Array.isArray(evidence?.checks)
      ? evidence.checks.map((check) => ({
          key: safeString(check?.key || ''),
          pass: check?.pass === true,
          comparator: safeString(check?.comparator || ''),
          expected: Number(check?.expected || 0),
          actual: Number(check?.actual || 0),
        }))
      : [],
    metrics: {
      ingress_total: Math.max(0, Number(metrics.ingress_total || 0)),
      non_message_ingress_total: Math.max(0, Number(metrics.non_message_ingress_total || 0)),
      non_message_ingress_policy_checked: Math.max(0, Number(metrics.non_message_ingress_policy_checked || 0)),
      non_message_ingress_policy_coverage: Number(metrics.non_message_ingress_policy_coverage || 0),
      blocked_event_total: Math.max(0, Number(metrics.blocked_event_total || 0)),
      blocked_event_audited: Math.max(0, Number(metrics.blocked_event_audited || 0)),
      blocked_event_miss_total: Math.max(0, Number(metrics.blocked_event_miss_total || 0)),
      blocked_event_miss_rate: Number(metrics.blocked_event_miss_rate || 0),
    },
  };
}

export function buildNonMessageIngressGateEvidenceFromAuditRows(auditRows = [], options = {}) {
  const stats = buildNonMessageIngressScanStatsFromAuditRows(auditRows);
  return buildNonMessageIngressGateEvidence({
    stats,
    thresholds: options && typeof options === 'object' ? options.thresholds : {},
  });
}

export function buildNonMessageIngressGateSnapshotFromAuditRows(auditRows = [], options = {}) {
  const stats = buildNonMessageIngressScanStatsFromAuditRows(auditRows);
  return buildNonMessageIngressGateSnapshot({
    stats,
    thresholds: options && typeof options === 'object' ? options.thresholds : {},
  });
}

export function appendConnectorIngressAudit({
  db,
  event = {},
  authz = null,
  client = {},
  request_id = '',
} = {}) {
  if (!db || typeof db.appendAudit !== 'function') return false;

  const decision = authz && typeof authz === 'object'
    ? authz
    : authorizeConnectorIngress({ event, policy: {} });
  const e = normalizeIngressEvent(event);
  const c = client && typeof client === 'object' ? client : {};
  const created_at_ms = nowMs();

  db.appendAudit({
    event_type: decision.allowed ? 'connector.ingress.allowed' : 'connector.ingress.denied',
    created_at_ms,
    severity: decision.allowed ? 'info' : 'warn',
    device_id: safeString(c.device_id || 'connector_ingress'),
    user_id: safeString(c.user_id) || null,
    app_id: safeString(c.app_id || 'connector_ingress'),
    project_id: safeString(c.project_id) || null,
    session_id: safeString(c.session_id) || null,
    request_id: safeString(request_id || e.message_id) || null,
    capability: `connector.ingress.${e.ingress_type || 'unknown'}`,
    model_id: null,
    ok: !!decision.allowed,
    error_code: decision.allowed ? null : safeString(decision.deny_code || 'authz_denied'),
    error_message: decision.allowed ? null : 'connector_ingress_denied',
    ext_json: JSON.stringify({
      ingress_type: e.ingress_type,
      channel_scope: e.channel_scope,
      sender_id: e.sender_id,
      channel_id: e.channel_id,
      source_id: e.source_id,
      non_message_ingress: !!decision.non_message_ingress,
      policy_checked: decision.policy_checked !== false,
      deny_code: safeString(decision.deny_code || ''),
      detail: safeString(decision.detail || ''),
    }),
  });

  return true;
}

export function evaluateConnectorIngressWithAudit({
  db,
  event = {},
  policy = {},
  client = {},
  request_id = '',
} = {}) {
  const decision = authorizeConnectorIngress({ event, policy });
  const audit_logged = (() => {
    try {
      return appendConnectorIngressAudit({ db, event, authz: decision, client, request_id });
    } catch {
      return false;
    }
  })();

  return {
    ...decision,
    audit_logged,
  };
}
