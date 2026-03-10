import crypto from 'node:crypto';

import { normalizeSensitivity, normalizeTrust, routeMemoryByTrustShards } from './memory_trust_router.js';
import { nowMs } from './util.js';

const SCHEMA_VERSION = 'xhub.longterm_markdown_export.v1';
const DEFAULT_LIMIT = 200;
const MAX_LIMIT = 500;
const DEFAULT_MAX_CHARS = 48 * 1024;
const MIN_MAX_CHARS = 1024;
const MAX_MAX_CHARS = 512 * 1024;

const SECRET_PATTERNS = [
  /\[private\]/i,
  /\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)/i,
  /\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp|payment[_\s-]*(pin|code)|qr[_\s-]*code)\b/i,
  /\b(password|passcode|authorization|auth[_\s-]*code)\b/i,
  /[0-9a-f]{32,}/i,
];

function safeStr(v) {
  return String(v || '').trim();
}

function clampInt(v, fallback, min, max) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  const x = Math.floor(n);
  return Math.max(min, Math.min(max, x));
}

function plainSort(a, b) {
  const x = String(a || '');
  const y = String(b || '');
  if (x < y) return -1;
  if (x > y) return 1;
  return 0;
}

function shortLine(v, limit = 160) {
  const s = safeStr(v).replace(/\s+/g, ' ');
  if (!s) return '';
  if (s.length <= limit) return s;
  return `${s.slice(0, Math.max(1, limit - 3))}...`;
}

function scopeRefFromRow(row = {}) {
  return {
    device_id: safeStr(row.device_id),
    user_id: safeStr(row.user_id),
    app_id: safeStr(row.app_id),
    project_id: safeStr(row.project_id),
    thread_id: safeStr(row.thread_id),
  };
}

function normalizeScopeRef(scope = {}) {
  return {
    device_id: safeStr(scope.device_id),
    user_id: safeStr(scope.user_id),
    app_id: safeStr(scope.app_id),
    project_id: safeStr(scope.project_id),
    thread_id: safeStr(scope.thread_id),
  };
}

function looksSecretLikeText(input) {
  const text = String(input || '');
  if (!text.trim()) return false;
  return SECRET_PATTERNS.some((p) => p.test(text));
}

function inferCanonicalSensitivity(row) {
  const hint = safeStr(row?.sensitivity);
  if (hint) return normalizeSensitivity(hint);
  const key = safeStr(row?.key).toLowerCase();
  const value = String(row?.value || '').toLowerCase();
  if (looksSecretLikeText(`${key}\n${value}`)) return 'secret';
  return 'internal';
}

function toProjectionDoc(row) {
  const itemId = safeStr(row?.item_id);
  const key = safeStr(row?.key);
  const value = String(row?.value ?? '');
  if (!itemId || !key || !value.trim()) return null;
  return {
    id: `canonical:${itemId}`,
    item_id: itemId,
    key,
    value,
    title: key,
    text: value,
    sensitivity: inferCanonicalSensitivity(row),
    trust_level: normalizeTrust(row?.trust_level || 'trusted'),
    updated_at_ms: Math.max(0, Number(row?.updated_at_ms || 0)),
    scope: scopeRefFromRow(row),
  };
}

function exportDocId({ scope_filter, scope_ref } = {}) {
  const scopeFilter = safeStr(scope_filter || 'all') || 'all';
  const scopeRef = normalizeScopeRef(scope_ref || {});
  const parts = [
    'longterm',
    scopeRef.device_id || '~',
    scopeRef.user_id || '~',
    scopeRef.app_id || '~',
    scopeRef.project_id || '~',
    scopeFilter || 'all',
    scopeRef.thread_id || '~',
  ];
  return parts.join(':');
}

function toVersionHash(payload) {
  const raw = JSON.stringify(payload);
  return crypto.createHash('sha256').update(raw, 'utf8').digest('hex');
}

function renderMarkdown({ doc_id, version, scope_filter, scope_ref, entries }) {
  const scopeRef = normalizeScopeRef(scope_ref || {});
  const lines = [];
  lines.push(`<!-- ${SCHEMA_VERSION} -->`);
  lines.push('# X-Hub Longterm Markdown View');
  lines.push('');
  lines.push('- source_of_truth: db.canonical_memory (projection, non-authoritative)');
  lines.push(`- doc_id: ${safeStr(doc_id)}`);
  lines.push(`- version: ${safeStr(version)}`);
  lines.push(`- scope_filter: ${safeStr(scope_filter || 'all') || 'all'}`);
  lines.push(
    `- scope_ref: device_id=${scopeRef.device_id || '~'}; user_id=${scopeRef.user_id || '~'}; app_id=${scopeRef.app_id || '~'}; project_id=${scopeRef.project_id || '~'}; thread_id=${scopeRef.thread_id || '~'}`
  );
  lines.push(`- entries: ${entries.length}`);
  lines.push('');
  lines.push('## Entries');
  if (entries.length === 0) {
    lines.push('_No entries matched current filters/gates._');
    return lines.join('\n');
  }

  for (let i = 0; i < entries.length; i += 1) {
    const row = entries[i];
    const value = String(row?.value ?? '');
    const valueLines = value.split(/\r?\n/);
    lines.push('');
    lines.push(`### ${i + 1}. ${shortLine(row?.key, 200)} \`[${safeStr(row?.item_id)}]\``);
    lines.push(`- sensitivity: ${normalizeSensitivity(row?.sensitivity)}`);
    lines.push(`- trust_level: ${normalizeTrust(row?.trust_level)}`);
    lines.push(`- updated_at_ms: ${Math.max(0, Number(row?.updated_at_ms || 0))}`);
    lines.push(`- provenance_ref: canonical_memory:${safeStr(row?.item_id)}`);
    lines.push('');
    lines.push('value:');
    for (const line of valueLines) {
      lines.push(`> ${line}`);
    }
  }
  return lines.join('\n');
}

function normalizeAllowedSensitivity(list) {
  if (!Array.isArray(list)) return [];
  const out = [];
  const seen = new Set();
  for (const item of list) {
    const s = normalizeSensitivity(item);
    if (seen.has(s)) continue;
    seen.add(s);
    out.push(s);
  }
  return out;
}

function buildVersionedPayload({ doc_id, scope_filter, scope_ref, entries, policy }) {
  const basis = {
    schema_version: SCHEMA_VERSION,
    doc_id: safeStr(doc_id),
    scope_filter: safeStr(scope_filter || 'all') || 'all',
    scope_ref: normalizeScopeRef(scope_ref || {}),
    policy: {
      remote_mode: !!policy?.remote_mode,
      allow_untrusted: !!policy?.allow_untrusted,
      allowed_sensitivity: normalizeAllowedSensitivity(policy?.allowed_sensitivity),
    },
    entries: entries.map((row) => ({
      item_id: safeStr(row?.item_id),
      key: safeStr(row?.key),
      value: String(row?.value ?? ''),
      sensitivity: normalizeSensitivity(row?.sensitivity),
      trust_level: normalizeTrust(row?.trust_level),
      updated_at_ms: Math.max(0, Number(row?.updated_at_ms || 0)),
      scope: normalizeScopeRef(row?.scope || {}),
    })),
  };
  const hash = toVersionHash(basis);
  const version = `lmv1_${hash.slice(0, 24)}`;
  const markdown = renderMarkdown({
    doc_id,
    version,
    scope_filter,
    scope_ref,
    entries,
  });
  return { version, markdown };
}

function sortDocsForExport(rows) {
  return rows
    .slice()
    .sort((a, b) => {
      const at = Math.max(0, Number(a?.updated_at_ms || 0));
      const bt = Math.max(0, Number(b?.updated_at_ms || 0));
      if (bt !== at) return bt - at;
      const k = plainSort(a?.key, b?.key);
      if (k !== 0) return k;
      return plainSort(a?.item_id, b?.item_id);
    });
}

export function buildLongtermMarkdownExport(input = {}) {
  const rawRows = Array.isArray(input?.rows) ? input.rows : [];
  const docId = safeStr(input?.doc_id) || exportDocId({
    scope_filter: input?.scope_filter,
    scope_ref: input?.scope_ref,
  });
  const scopeFilter = safeStr(input?.scope_filter || 'all') || 'all';
  const scopeRef = normalizeScopeRef(input?.scope_ref || {});
  const limit = clampInt(input?.limit, DEFAULT_LIMIT, 1, MAX_LIMIT);
  const maxChars = clampInt(
    input?.max_markdown_chars,
    DEFAULT_MAX_CHARS,
    MIN_MAX_CHARS,
    MAX_MAX_CHARS
  );
  const remoteMode = !!input?.remote_mode;
  const allowUntrusted = !!input?.allow_untrusted;
  const allowedSensitivity = normalizeAllowedSensitivity(input?.allowed_sensitivity);

  const docs = rawRows
    .map((row) => toProjectionDoc(row))
    .filter(Boolean);

  const routed = routeMemoryByTrustShards({
    documents: docs,
    remote_mode: remoteMode,
    allow_untrusted: allowUntrusted,
    allowed_sensitivity: allowedSensitivity,
  });

  const routedSorted = sortDocsForExport(Array.isArray(routed?.documents) ? routed.documents : []);
  const totalItems = routedSorted.length;
  let entries = routedSorted.slice(0, limit);
  let truncated = totalItems > entries.length;

  let versioned = buildVersionedPayload({
    doc_id: docId,
    scope_filter: scopeFilter,
    scope_ref: scopeRef,
    entries,
    policy: routed?.policy,
  });

  while (versioned.markdown.length > maxChars && entries.length > 0) {
    entries = entries.slice(0, entries.length - 1);
    truncated = true;
    versioned = buildVersionedPayload({
      doc_id: docId,
      scope_filter: scopeFilter,
      scope_ref: scopeRef,
      entries,
      policy: routed?.policy,
    });
  }

  if (versioned.markdown.length > maxChars) {
    const fallback = buildVersionedPayload({
      doc_id: docId,
      scope_filter: scopeFilter,
      scope_ref: scopeRef,
      entries: [],
      policy: routed?.policy,
    });
    versioned = {
      version: fallback.version,
      markdown: fallback.markdown.slice(0, maxChars),
    };
    truncated = true;
    entries = [];
  }

  const provenanceRefs = entries
    .map((row) => `canonical_memory:${safeStr(row?.item_id)}`)
    .filter(Boolean);

  return {
    schema_version: SCHEMA_VERSION,
    doc_id: docId,
    version: versioned.version,
    markdown: versioned.markdown,
    provenance_refs: provenanceRefs,
    exported_at_ms: nowMs(),
    truncated,
    total_items: totalItems,
    included_items: entries.length,
    applied_sensitivity: Array.isArray(routed?.policy?.allowed_sensitivity)
      ? routed.policy.allowed_sensitivity.map((s) => normalizeSensitivity(s))
      : [],
    route_stats: routed?.stats || null,
    route_policy: routed?.policy || null,
  };
}

