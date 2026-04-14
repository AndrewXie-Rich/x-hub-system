import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

import { nowMs, uuid } from './util.js';
import {
  decryptTextWithDek,
  encryptTextWithDek,
  parseEncryptedEnvelopeMeta,
  parseFixedKeyMaterial,
  randomDekBytes,
  unwrapDekWithKek,
  wrapDekWithKek,
} from './at_rest_crypto.js';
import {
  normalizeMemoryModelMode,
  normalizeMemoryModelPreferenceRow,
  normalizeMemoryModelPreferenceScopeKind,
  normalizeMemoryModelPreferenceSelectionStrategy,
  selectWinningMemoryModelPreference,
  validateMemoryModelPreference,
} from './memory_model_preferences.js';

function parseBoolEnv(v, fallback = false) {
  if (v == null) return fallback;
  const s = String(v).trim().toLowerCase();
  if (!s) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(s)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(s)) return false;
  return fallback;
}

function parseIntEnv(v, fallback, min, max) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  const x = Math.floor(n);
  return Math.max(min, Math.min(max, x));
}

function normalizeAuditLevel(v) {
  const s = String(v || '').trim().toLowerCase();
  if (s === 'full_content') return 'full_content';
  if (s === 'content_redacted') return 'content_redacted';
  return 'metadata_only';
}

function sha256Hex(text) {
  return crypto.createHash('sha256').update(String(text), 'utf8').digest('hex');
}

function utf8Bytes(text) {
  return Buffer.byteLength(String(text), 'utf8');
}

function parseJsonObject(rawValue, fallback = {}) {
  if (rawValue == null || rawValue === '') return fallback;
  try {
    const parsed = JSON.parse(String(rawValue));
    return parsed && typeof parsed === 'object' ? parsed : fallback;
  } catch {
    return fallback;
  }
}

function uniqueOrderedStrings(values) {
  if (!Array.isArray(values)) return [];
  const out = [];
  const seen = new Set();
  for (const raw of values) {
    const cleaned = String(raw || '').trim();
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

function escapeSqlLikePattern(value) {
  return String(value || '')
    .replace(/\\/g, '\\\\')
    .replace(/%/g, '\\%')
    .replace(/_/g, '\\_');
}

const DEFAULT_RISK_TUNING_PROFILE_ID = 'risk_default_v1';
const RISK_LEVELS = new Set(['low', 'medium', 'high']);
const VOICE_CHALLENGE_STATUSES = new Set(['issued', 'verified', 'denied', 'expired']);
const SECRET_VAULT_SCOPES = new Set(['device', 'user', 'app', 'project']);
const SECRET_VAULT_LEASE_STATUSES = new Set(['active', 'used', 'expired', 'revoked']);

function defaultRiskTuningProfile(now = nowMs()) {
  return {
    profile_id: DEFAULT_RISK_TUNING_PROFILE_ID,
    profile_label: 'risk-default-v1',
    vector_weight: 1.0,
    text_weight: 1.0,
    recency_weight: 0.4,
    risk_weight: 1.0,
    risk_penalty_low: 0.10,
    risk_penalty_medium: 0.35,
    risk_penalty_high: 0.75,
    recall_floor: 0.97,
    latency_ceiling_ratio: 1.50,
    block_precision_floor: 0.95,
    max_recall_drop: 0.03,
    max_latency_ratio_increase: 0.20,
    max_block_precision_drop: 0.02,
    max_online_offline_drift: 0.12,
    created_at_ms: now,
    updated_at_ms: now,
  };
}

const SENSITIVE_KEY_RE = /(?:^|_)(content|preview|prompt|response|body|text|snippet|note|reason|message|url|query|cookie|header|payload|authorization|token|secret|password|credential|private|email|phone|ssn|card|iban|otp|pin|address|key)(?:$|_)/i;
const SAFE_KEY_RE = /(?:^|_)(id|scope|status|type|capability|model|backend|kind|host|port|code|ok|allowed|level|mode|state|count|tokens|ms|bytes|cost|decision|day|cursor|offset|limit|runtime_alive|queue_wait_ms)(?:$|_)/i;

function normalizeKillSwitchList(values) {
  if (values == null) return [];
  const out = [];
  const seen = new Set();
  const items = Array.isArray(values) ? values : String(values || '').split(',');
  for (const raw of items) {
    const cleaned = String(raw ?? '').trim();
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

function parseKillSwitchList(rawValue) {
  if (rawValue == null || rawValue === '') return [];
  if (Array.isArray(rawValue)) return normalizeKillSwitchList(rawValue);
  try {
    const parsed = JSON.parse(String(rawValue));
    return normalizeKillSwitchList(parsed);
  } catch {
    return normalizeKillSwitchList(String(rawValue));
  }
}

function normalizeKillSwitchRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    scope: String(row.scope || ''),
    models_disabled: Number(row.models_disabled || 0) > 0,
    network_disabled: Number(row.network_disabled || 0) > 0,
    reason: row.reason == null ? '' : String(row.reason || ''),
    updated_at_ms: Number(row.updated_at_ms || 0),
    disabled_local_capabilities: parseKillSwitchList(
      row.disabled_local_capabilities_json ?? row.disabled_local_capabilities
    ),
    disabled_local_providers: parseKillSwitchList(
      row.disabled_local_providers_json ?? row.disabled_local_providers
    ),
  };
}

function looksSimpleToken(s) {
  // Keep compact identifiers visible in metadata-only mode.
  return /^[A-Za-z0-9._:@/-]{1,64}$/.test(s);
}

function makeRedactedStringMeta(text, { allowContentPreview, contentPreviewChars }) {
  const value = String(text ?? '');
  const meta = {
    type: 'string',
    bytes: utf8Bytes(value),
    sha256: sha256Hex(value),
  };
  if (allowContentPreview && contentPreviewChars > 0) {
    const preview = value.length > contentPreviewChars
      ? `${value.slice(0, contentPreviewChars)}...`
      : value;
    meta.content_preview = preview;
  }
  return meta;
}

function shouldRedactStringValue({ keyName, value, auditLevel }) {
  if (auditLevel === 'full_content') return false;
  const key = String(keyName || '').toLowerCase();
  const str = String(value ?? '');
  if (!str) return false;
  if (SENSITIVE_KEY_RE.test(key)) return true;
  if (str.includes('<private') || str.includes('</private>')) return true;
  if (/\r|\n|\t/.test(str)) return true;
  if (str.length > 96) return true;
  if (SAFE_KEY_RE.test(key) && looksSimpleToken(str)) return false;
  if (looksSimpleToken(str) && str.length <= 32) return false;
  return auditLevel === 'metadata_only';
}

function sanitizeAuditExtValue(value, ctx, keyName = '') {
  if (value == null) return value;
  if (typeof value === 'number' || typeof value === 'boolean') return value;

  if (typeof value === 'string') {
    if (!shouldRedactStringValue({ keyName, value, auditLevel: ctx.auditLevel })) {
      return value;
    }
    ctx.redactedItems += 1;
    return makeRedactedStringMeta(value, ctx);
  }

  if (Array.isArray(value)) {
    return value.map((it) => sanitizeAuditExtValue(it, ctx, keyName));
  }

  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = sanitizeAuditExtValue(v, ctx, k);
    }
    return out;
  }

  // bigint/symbol/function should not appear in JSON payloads; stringify safely.
  const raw = String(value);
  ctx.redactedItems += 1;
  return makeRedactedStringMeta(raw, ctx);
}

function stripContentPreviewFields(value) {
  if (value == null) return value;
  if (Array.isArray(value)) return value.map((it) => stripContentPreviewFields(it));
  if (typeof value !== 'object') return value;
  const out = {};
  for (const [k, v] of Object.entries(value)) {
    if (k === 'content_preview') continue;
    out[k] = stripContentPreviewFields(v);
  }
  return out;
}

export function sanitizeAuditExtJsonForStorage(extJson, opts = {}) {
  if (extJson == null || extJson === '') return null;

  const auditLevel = normalizeAuditLevel(opts.auditLevel);
  const allowContentPreview = !!opts.allowContentPreview;
  const contentPreviewChars = parseIntEnv(opts.contentPreviewChars, 0, 0, 2048);
  const contentPreviewTtlMs = parseIntEnv(opts.contentPreviewTtlMs, 0, 0, 30 * 24 * 60 * 60 * 1000);

  let payload = extJson;
  if (typeof extJson === 'string') {
    const raw = String(extJson).trim();
    if (!raw) return null;
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        payload = JSON.parse(raw);
      } catch {
        payload = { raw_text: raw };
      }
    } else {
      payload = { raw_text: raw };
    }
  }

  if (auditLevel === 'full_content') {
    if (typeof payload === 'string') return payload;
    try {
      return JSON.stringify(payload);
    } catch {
      return JSON.stringify({ raw_text: String(extJson) });
    }
  }

  const ctx = {
    auditLevel,
    allowContentPreview: auditLevel !== 'metadata_only' && allowContentPreview,
    contentPreviewChars: auditLevel !== 'metadata_only' ? contentPreviewChars : 0,
    redactedItems: 0,
  };
  const sanitized = sanitizeAuditExtValue(payload, ctx);

  if (sanitized && typeof sanitized === 'object' && !Array.isArray(sanitized)) {
    sanitized._audit_redaction = {
      audit_level: auditLevel,
      redaction_mode: ctx.allowContentPreview ? 'hash_with_preview' : 'hash_only',
      redacted_items: ctx.redactedItems,
      ...(ctx.allowContentPreview && contentPreviewTtlMs > 0 ? { content_preview_ttl_ms: contentPreviewTtlMs } : {}),
    };
    return JSON.stringify(sanitized);
  }

  return JSON.stringify({
    value: sanitized,
    _audit_redaction: {
      audit_level: auditLevel,
      redaction_mode: ctx.allowContentPreview ? 'hash_with_preview' : 'hash_only',
      redacted_items: ctx.redactedItems,
      ...(ctx.allowContentPreview && contentPreviewTtlMs > 0 ? { content_preview_ttl_ms: contentPreviewTtlMs } : {}),
    },
  });
}

function normalizeKekMapFromObject(rawObj) {
  const out = new Map();
  if (!rawObj || typeof rawObj !== 'object') return out;
  for (const [versionRaw, materialRaw] of Object.entries(rawObj)) {
    const version = String(versionRaw || '').trim();
    if (!version) continue;
    const keyBytes = parseFixedKeyMaterial(materialRaw);
    if (!keyBytes) throw new Error(`invalid KEK material for version: ${version}`);
    out.set(version, keyBytes);
  }
  return out;
}

function loadLocalKekFile(filePath, autoCreate = true) {
  const target = String(filePath || '').trim();
  if (!target) return { active_kek_version: '', keks: {} };

  if (fs.existsSync(target)) {
    const raw = fs.readFileSync(target, 'utf8');
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') {
      throw new Error(`invalid HUB_MEMORY_KEK_FILE payload: ${target}`);
    }
    const active = String(parsed.active_kek_version || '').trim();
    const keks = parsed.keks && typeof parsed.keks === 'object' ? parsed.keks : {};
    return { active_kek_version: active, keks };
  }

  if (!autoCreate) {
    throw new Error(`missing HUB_MEMORY_KEK_FILE: ${target}`);
  }

  const now = nowMs();
  const active = 'kek_local_v1';
  const keyText = `base64:${crypto.randomBytes(32).toString('base64')}`;
  const payload = {
    schema_version: 'xhub.memory.kek.v1',
    active_kek_version: active,
    keks: { [active]: keyText },
    created_at_ms: now,
    updated_at_ms: now,
  };
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify(payload, null, 2), { mode: 0o600 });
  try {
    fs.chmodSync(target, 0o600);
  } catch {
    // ignore
  }
  return { active_kek_version: active, keks: { [active]: keyText } };
}

function loadMemoryAtRestConfig({ dbPath, env = process.env }) {
  const enabled = parseBoolEnv(env.HUB_MEMORY_AT_REST_ENABLED, true);
  if (!enabled) {
    return {
      enabled: false,
      activeKekVersion: '',
      kekRing: new Map(),
      keyFilePath: '',
    };
  }

  let activeKekVersion = String(env.HUB_MEMORY_KEK_ACTIVE_VERSION || '').trim();
  let rawKeks = null;

  const ringJson = String(env.HUB_MEMORY_KEK_RING_JSON || '').trim();
  if (ringJson) {
    let parsed = null;
    try {
      parsed = JSON.parse(ringJson);
    } catch {
      throw new Error('invalid HUB_MEMORY_KEK_RING_JSON');
    }
    rawKeks = parsed;
  }

  if (!rawKeks) {
    const singleKek = String(env.HUB_MEMORY_KEK || '').trim();
    if (singleKek) {
      const version = activeKekVersion || 'kek_v1';
      rawKeks = { [version]: singleKek };
      activeKekVersion = version;
    }
  }

  let keyFilePath = '';
  if (!rawKeks) {
    keyFilePath = String(env.HUB_MEMORY_KEK_FILE || '').trim();
    if (!keyFilePath) keyFilePath = path.join(path.dirname(dbPath), 'hub_memory_kek.json');
    const autoCreate = parseBoolEnv(env.HUB_MEMORY_KEK_FILE_AUTOCREATE, true);
    const loaded = loadLocalKekFile(keyFilePath, autoCreate);
    if (!activeKekVersion) activeKekVersion = String(loaded.active_kek_version || '').trim();
    rawKeks = loaded.keks;
  }

  const kekRing = normalizeKekMapFromObject(rawKeks);
  if (!kekRing.size) throw new Error('missing KEK material for memory at-rest encryption');
  if (!activeKekVersion || !kekRing.has(activeKekVersion)) {
    activeKekVersion = Array.from(kekRing.keys())[0];
  }

  return {
    enabled: true,
    activeKekVersion,
    kekRing,
    keyFilePath,
  };
}

export class HubDB {
  /** @param {{ dbPath: string }} opts */
  constructor(opts) {
    const dbPath = String(opts?.dbPath || '').trim();
    if (!dbPath) throw new Error('missing dbPath');

    const dir = path.dirname(dbPath);
    fs.mkdirSync(dir, { recursive: true });

    this.db = new DatabaseSync(dbPath);

    this.auditLevel = normalizeAuditLevel(process.env.HUB_AUDIT_LEVEL || 'metadata_only');
    this.auditAllowContentPreview = parseBoolEnv(process.env.HUB_AUDIT_ALLOW_CONTENT_PREVIEW, false);
    this.auditContentPreviewChars = parseIntEnv(process.env.HUB_AUDIT_CONTENT_PREVIEW_CHARS, 200, 0, 2048);
    this.auditContentPreviewTtlMs = parseIntEnv(
      process.env.HUB_AUDIT_CONTENT_PREVIEW_TTL_MS,
      10 * 60 * 1000,
      0,
      30 * 24 * 60 * 60 * 1000
    );
    this.auditPreviewScrubIntervalMs = parseIntEnv(
      process.env.HUB_AUDIT_CONTENT_PREVIEW_SCRUB_INTERVAL_MS,
      60 * 1000,
      10 * 1000,
      24 * 60 * 60 * 1000
    );
    this._nextAuditPreviewScrubAtMs = 0;

    const memEnc = loadMemoryAtRestConfig({ dbPath, env: process.env });
    this.memoryAtRestEnabled = !!memEnc.enabled;
    this.memoryKekActiveVersion = String(memEnc.activeKekVersion || '');
    this.memoryKekRing = memEnc.kekRing || new Map();
    this.memoryKekFilePath = String(memEnc.keyFilePath || '');
    this.memoryDekPurpose = 'memory_at_rest_v1';
    this._activeMemoryDekCache = null;

    this.memoryRetentionEnabled = parseBoolEnv(process.env.HUB_MEMORY_RETENTION_ENABLED, true);
    this.memoryRetentionAutoJobEnabled = parseBoolEnv(process.env.HUB_MEMORY_RETENTION_AUTO_JOB_ENABLED, true);
    this.memoryRetentionJobIntervalMs = parseIntEnv(
      process.env.HUB_MEMORY_RETENTION_JOB_INTERVAL_MS,
      10 * 60 * 1000,
      10 * 1000,
      30 * 24 * 60 * 60 * 1000
    );
    this.memoryRetentionTurnsTtlMs = parseIntEnv(
      process.env.HUB_MEMORY_RETENTION_TURNS_TTL_MS,
      30 * 24 * 60 * 60 * 1000,
      0,
      5 * 365 * 24 * 60 * 60 * 1000
    );
    this.memoryRetentionCanonicalTtlMs = parseIntEnv(
      process.env.HUB_MEMORY_RETENTION_CANONICAL_TTL_MS,
      90 * 24 * 60 * 60 * 1000,
      0,
      5 * 365 * 24 * 60 * 60 * 1000
    );
    this.memoryRetentionCanonicalIncludePinned = parseBoolEnv(
      process.env.HUB_MEMORY_RETENTION_CANONICAL_INCLUDE_PINNED,
      false
    );
    this.memoryRetentionBatchLimit = parseIntEnv(
      process.env.HUB_MEMORY_RETENTION_BATCH_LIMIT,
      500,
      1,
      10000
    );
    this.memoryRetentionTombstoneTtlMs = parseIntEnv(
      process.env.HUB_MEMORY_RETENTION_TOMBSTONE_TTL_MS,
      7 * 24 * 60 * 60 * 1000,
      0,
      180 * 24 * 60 * 60 * 1000
    );
    this.memoryRetentionAuditEnabled = parseBoolEnv(process.env.HUB_MEMORY_RETENTION_AUDIT_ENABLED, true);
    this._nextMemoryRetentionRunAtMs = 0;
    this.projectHeartbeatTtlMs = parseIntEnv(
      process.env.HUB_PROJECT_HEARTBEAT_TTL_MS,
      30 * 1000,
      10,
      30 * 60 * 1000
    );
    this.projectDispatchStarvationMs = parseIntEnv(
      process.env.HUB_PROJECT_DISPATCH_STARVATION_MS,
      20 * 1000,
      1000,
      30 * 60 * 1000
    );
    this.projectDispatchDefaultBatchSize = parseIntEnv(
      process.env.HUB_PROJECT_DISPATCH_DEFAULT_BATCH_SIZE,
      4,
      1,
      64
    );
    this.projectDispatchConservativePenalty = parseIntEnv(
      process.env.HUB_PROJECT_DISPATCH_CONSERVATIVE_PENALTY,
      4000,
      0,
      200000
    );
    this.paymentEvidenceSignatureEnforced = parseBoolEnv(
      process.env.HUB_PAYMENT_EVIDENCE_SIGNATURE_ENFORCED,
      true
    );
    this.paymentEvidenceSigningSecret = String(
      process.env.HUB_PAYMENT_EVIDENCE_SIGNING_SECRET || ''
    ).trim();
    this.paymentReceiptUndoWindowMs = parseIntEnv(
      process.env.HUB_PAYMENT_RECEIPT_UNDO_WINDOW_MS,
      30 * 1000,
      1000,
      10 * 60 * 1000
    );
    this.paymentReceiptCompensationDelayMs = parseIntEnv(
      process.env.HUB_PAYMENT_RECEIPT_COMPENSATION_DELAY_MS,
      0,
      0,
      5 * 60 * 1000
    );

    // Performance defaults.
    this.db.exec('PRAGMA journal_mode = WAL;');
    this.db.exec('PRAGMA synchronous = NORMAL;');
    this.db.exec('PRAGMA busy_timeout = 2000;');

    this._migrate();
    this._initMemoryAtRestState();
    this._seedDefaultsIfEmpty();
  }

  close() {
    try {
      this.db.close();
    } catch {
      // ignore
    }
  }

  _migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS models (
        model_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        backend TEXT NOT NULL,
        context_length INTEGER NOT NULL,
        requires_grant INTEGER NOT NULL,
        enabled INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS memory_model_preferences (
        profile_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        scope_kind TEXT NOT NULL,
        scope_ref TEXT NOT NULL DEFAULT '',
        mode TEXT NOT NULL DEFAULT '',
        selection_strategy TEXT NOT NULL,
        primary_model_id TEXT,
        job_model_map_json TEXT,
        mode_model_map_json TEXT,
        fallback_policy_json TEXT,
        remote_allowed INTEGER NOT NULL,
        policy_version TEXT NOT NULL,
        note TEXT,
        updated_at_ms INTEGER NOT NULL,
        disabled_at_ms INTEGER
      );

      CREATE INDEX IF NOT EXISTS idx_memory_model_preferences_user
        ON memory_model_preferences(user_id, updated_at_ms DESC);

      CREATE INDEX IF NOT EXISTS idx_memory_model_preferences_scope
        ON memory_model_preferences(user_id, scope_kind, scope_ref, mode, disabled_at_ms, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS grant_requests (
        grant_request_id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT,
        app_id TEXT NOT NULL,
        project_id TEXT,
        capability TEXT NOT NULL,
        model_id TEXT,
        reason TEXT,
        requested_ttl_sec INTEGER NOT NULL,
        requested_token_cap INTEGER NOT NULL,
        status TEXT NOT NULL,
        decision TEXT,
        deny_reason TEXT,
        approver_id TEXT,
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        decided_at_ms INTEGER
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_grant_requests_idempotency
        ON grant_requests(device_id, request_id);

      CREATE TABLE IF NOT EXISTS grants (
        grant_id TEXT PRIMARY KEY,
        grant_request_id TEXT,
        device_id TEXT NOT NULL,
        user_id TEXT,
        app_id TEXT NOT NULL,
        project_id TEXT,
        capability TEXT NOT NULL,
        model_id TEXT,
        token_cap INTEGER NOT NULL,
        token_used INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        status TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        revoked_at_ms INTEGER,
        revoke_reason TEXT,
        revoker_id TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_grants_active
        ON grants(device_id, status, expires_at_ms);

      CREATE TABLE IF NOT EXISTS audit_events (
        event_id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        severity TEXT,
        device_id TEXT NOT NULL,
        user_id TEXT,
        app_id TEXT NOT NULL,
        project_id TEXT,
        session_id TEXT,
        request_id TEXT,
        capability TEXT,
        model_id TEXT,
        prompt_tokens INTEGER,
        completion_tokens INTEGER,
        total_tokens INTEGER,
        cost_usd_estimate REAL,
        network_allowed INTEGER,
        ok INTEGER NOT NULL,
        error_code TEXT,
        error_message TEXT,
        duration_ms INTEGER,
        ext_json TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_events(created_at_ms);
      CREATE INDEX IF NOT EXISTS idx_audit_device ON audit_events(device_id, created_at_ms);
      CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_events(user_id, created_at_ms);
      CREATE INDEX IF NOT EXISTS idx_audit_request ON audit_events(request_id);

      CREATE TABLE IF NOT EXISTS kill_switches (
        scope TEXT PRIMARY KEY,
        models_disabled INTEGER NOT NULL,
        network_disabled INTEGER NOT NULL,
        disabled_local_capabilities_json TEXT,
        disabled_local_providers_json TEXT,
        reason TEXT,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS threads (
        thread_id TEXT PRIMARY KEY,
        thread_key TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_threads_key
        ON threads(device_id, app_id, project_id, thread_key);

      CREATE TABLE IF NOT EXISTS turns (
        turn_id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        request_id TEXT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        is_private INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_turns_thread_time
        ON turns(thread_id, created_at_ms);

      CREATE TABLE IF NOT EXISTS supervisor_memory_candidate_carrier (
        carrier_id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        thread_key TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        scope TEXT NOT NULL,
        record_type TEXT NOT NULL,
        confidence REAL NOT NULL,
        why_promoted TEXT NOT NULL,
        source_ref TEXT NOT NULL,
        audit_ref TEXT NOT NULL,
        session_participation_class TEXT NOT NULL,
        write_permission_scope TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        payload_summary TEXT NOT NULL,
        payload_fields_json TEXT NOT NULL,
        candidate_payload_json TEXT NOT NULL,
        schema_version TEXT NOT NULL,
        carrier_kind TEXT NOT NULL,
        mirror_target TEXT NOT NULL,
        local_store_role TEXT NOT NULL,
        summary_line TEXT NOT NULL,
        emitted_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_supervisor_memory_candidate_carrier_idem
        ON supervisor_memory_candidate_carrier(device_id, app_id, idempotency_key);

      CREATE INDEX IF NOT EXISTS idx_supervisor_memory_candidate_carrier_request
        ON supervisor_memory_candidate_carrier(device_id, app_id, request_id);

      CREATE TABLE IF NOT EXISTS canonical_memory (
        item_id TEXT PRIMARY KEY,
        scope TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        pinned INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_unique
        ON canonical_memory(scope, thread_id, device_id, user_id, app_id, project_id, key);

      CREATE INDEX IF NOT EXISTS idx_canonical_scope_time
        ON canonical_memory(scope, device_id, app_id, project_id, updated_at_ms);

      CREATE TABLE IF NOT EXISTS project_lineage (
        project_id TEXT PRIMARY KEY,
        root_project_id TEXT NOT NULL,
        parent_project_id TEXT,
        lineage_path TEXT NOT NULL,
        parent_task_id TEXT,
        split_round INTEGER NOT NULL,
        split_reason TEXT,
        child_index INTEGER NOT NULL,
        status TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_project_lineage_root_scope
        ON project_lineage(device_id, user_id, app_id, root_project_id, updated_at_ms DESC);

      CREATE INDEX IF NOT EXISTS idx_project_lineage_parent_scope
        ON project_lineage(device_id, user_id, app_id, parent_project_id, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS project_dispatch_context (
        project_id TEXT PRIMARY KEY,
        root_project_id TEXT NOT NULL,
        parent_project_id TEXT,
        assigned_agent_profile TEXT NOT NULL,
        parallel_lane_id TEXT NOT NULL,
        budget_class TEXT NOT NULL,
        queue_priority INTEGER NOT NULL,
        expected_artifacts_json TEXT,
        attached_at_ms INTEGER NOT NULL,
        attach_source TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_project_dispatch_root_scope
        ON project_dispatch_context(device_id, user_id, app_id, root_project_id, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_risk_tuning_profiles (
        profile_id TEXT PRIMARY KEY,
        profile_json TEXT NOT NULL,
        status TEXT NOT NULL,
        previous_profile_id TEXT,
        last_evaluation_id TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        promoted_at_ms INTEGER,
        rolled_back_at_ms INTEGER,
        rollback_reason TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_memory_risk_tuning_profiles_status
        ON memory_risk_tuning_profiles(status, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_risk_tuning_evaluations (
        evaluation_id TEXT PRIMARY KEY,
        request_id TEXT,
        profile_id TEXT NOT NULL,
        baseline_profile_id TEXT,
        baseline_metrics_json TEXT,
        holdout_metrics_json TEXT,
        online_metrics_json TEXT,
        offline_metrics_json TEXT,
        accepted INTEGER NOT NULL,
        holdout_passed INTEGER NOT NULL,
        rollback_triggered INTEGER NOT NULL,
        rollback_to_profile_id TEXT,
        deny_code TEXT,
        decision TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_memory_risk_tuning_eval_profile_time
        ON memory_risk_tuning_evaluations(profile_id, created_at_ms DESC);

      CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_risk_tuning_eval_request
        ON memory_risk_tuning_evaluations(request_id);

      CREATE TABLE IF NOT EXISTS memory_risk_tuning_state (
        state_id INTEGER PRIMARY KEY CHECK (state_id = 1),
        active_profile_id TEXT NOT NULL,
        stable_profile_id TEXT,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS memory_voice_grant_challenges (
        challenge_id TEXT PRIMARY KEY,
        request_id TEXT,
        template_id TEXT NOT NULL,
        action_digest TEXT NOT NULL,
        scope_digest TEXT NOT NULL,
        amount_digest TEXT,
        challenge_code_hash TEXT NOT NULL,
        risk_level TEXT NOT NULL,
        requires_mobile_confirm INTEGER NOT NULL,
        allow_voice_only INTEGER NOT NULL,
        bound_device_id TEXT,
        mobile_terminal_id TEXT,
        status TEXT NOT NULL,
        deny_code TEXT,
        transcript_hash TEXT,
        semantic_match_score REAL,
        challenge_match INTEGER,
        device_binding_ok INTEGER,
        mobile_confirmed INTEGER,
        issued_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        verified_at_ms INTEGER,
        updated_at_ms INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_memory_voice_grant_challenges_status
        ON memory_voice_grant_challenges(status, expires_at_ms, updated_at_ms DESC);

      CREATE INDEX IF NOT EXISTS idx_memory_voice_grant_challenges_scope
        ON memory_voice_grant_challenges(device_id, user_id, app_id, project_id, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_voice_grant_nonces (
        nonce_hash TEXT PRIMARY KEY,
        challenge_id TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_memory_voice_grant_nonces_challenge
        ON memory_voice_grant_nonces(challenge_id, created_at_ms DESC);

      CREATE TABLE IF NOT EXISTS secret_vault_items (
        item_id TEXT PRIMARY KEY,
        scope TEXT NOT NULL,
        name TEXT NOT NULL,
        name_key TEXT NOT NULL,
        sensitivity TEXT NOT NULL,
        display_name TEXT,
        reason TEXT,
        ciphertext_text TEXT NOT NULL,
        owner_device_id TEXT NOT NULL,
        owner_user_id TEXT NOT NULL,
        owner_app_id TEXT NOT NULL,
        owner_project_id TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_secret_vault_items_owner_name
        ON secret_vault_items(scope, owner_device_id, owner_user_id, owner_app_id, owner_project_id, name_key);

      CREATE INDEX IF NOT EXISTS idx_secret_vault_items_updated
        ON secret_vault_items(updated_at_ms DESC, scope, name_key);

      CREATE INDEX IF NOT EXISTS idx_secret_vault_items_owner_scope
        ON secret_vault_items(scope, owner_device_id, owner_user_id, owner_app_id, owner_project_id, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS secret_vault_use_leases (
        lease_id TEXT PRIMARY KEY,
        use_token_hash TEXT NOT NULL,
        item_id TEXT NOT NULL,
        scope TEXT NOT NULL,
        name TEXT NOT NULL,
        purpose TEXT NOT NULL,
        target TEXT,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        used_at_ms INTEGER,
        revoked_at_ms INTEGER,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_secret_vault_use_leases_token
        ON secret_vault_use_leases(use_token_hash);

      CREATE INDEX IF NOT EXISTS idx_secret_vault_use_leases_item_status
        ON secret_vault_use_leases(item_id, status, expires_at_ms, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS agent_capsules (
        capsule_id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        agent_name TEXT NOT NULL,
        agent_version TEXT NOT NULL,
        platform TEXT NOT NULL,
        sha256 TEXT NOT NULL,
        signature TEXT NOT NULL,
        sbom_hash TEXT NOT NULL,
        manifest_payload TEXT NOT NULL,
        sbom_payload TEXT NOT NULL,
        allowed_egress_json TEXT NOT NULL,
        risk_profile TEXT NOT NULL,
        status TEXT NOT NULL,
        deny_code TEXT,
        verification_report_ref TEXT,
        verified_at_ms INTEGER,
        activated_at_ms INTEGER,
        active_generation INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_capsules_idempotency
        ON agent_capsules(device_id, user_id, app_id, request_id);

      CREATE INDEX IF NOT EXISTS idx_agent_capsules_scope_status
        ON agent_capsules(device_id, user_id, app_id, status, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS agent_capsule_runtime_state (
        state_id TEXT PRIMARY KEY,
        active_capsule_id TEXT,
        active_generation INTEGER NOT NULL,
        previous_active_capsule_id TEXT,
        previous_active_generation INTEGER NOT NULL,
        last_activation_request_id TEXT,
        last_error_code TEXT,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS agent_sessions (
        session_id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        agent_instance_id TEXT NOT NULL,
        agent_name TEXT,
        agent_version TEXT,
        gateway_provider TEXT,
        status TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_sessions_idempotency
        ON agent_sessions(device_id, user_id, app_id, request_id);

      CREATE INDEX IF NOT EXISTS idx_agent_sessions_project_status
        ON agent_sessions(project_id, status, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS agent_tool_requests (
        tool_request_id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        agent_instance_id TEXT NOT NULL,
        gateway_provider TEXT,
        tool_name TEXT NOT NULL,
        tool_args_hash TEXT NOT NULL,
        approval_argv_json TEXT NOT NULL,
        approval_cwd_input TEXT NOT NULL,
        approval_cwd_canonical TEXT NOT NULL,
        approval_identity_hash TEXT NOT NULL,
        required_grant_scope TEXT NOT NULL,
        risk_tier TEXT NOT NULL,
        policy_decision TEXT NOT NULL,
        deny_code TEXT,
        grant_id TEXT,
        grant_expires_at_ms INTEGER,
        grant_decided_at_ms INTEGER,
        grant_decided_by TEXT,
        grant_note TEXT,
        capability_token_kind TEXT,
        capability_token_id TEXT,
        capability_token_nonce TEXT,
        capability_token_state TEXT,
        capability_token_issued_at_ms INTEGER,
        capability_token_expires_at_ms INTEGER,
        capability_token_bound_request_id TEXT,
        capability_token_consumed_at_ms INTEGER,
        capability_token_revoked_at_ms INTEGER,
        capability_token_revoke_reason TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_tool_requests_idempotency
        ON agent_tool_requests(session_id, request_id);

      CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_tool_requests_grant
        ON agent_tool_requests(grant_id)
        WHERE grant_id IS NOT NULL;

      CREATE INDEX IF NOT EXISTS idx_agent_tool_requests_session
        ON agent_tool_requests(session_id, created_at_ms DESC);

      CREATE TABLE IF NOT EXISTS agent_tool_executions (
        execution_id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        tool_request_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        grant_id TEXT,
        gateway_provider TEXT,
        tool_name TEXT NOT NULL,
        tool_args_hash TEXT NOT NULL,
        exec_argv_json TEXT NOT NULL,
        exec_cwd_input TEXT NOT NULL,
        exec_cwd_canonical TEXT NOT NULL,
        approval_identity_hash TEXT NOT NULL,
        status TEXT NOT NULL,
        deny_code TEXT,
        result_json TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_tool_exec_idempotency
        ON agent_tool_executions(session_id, request_id);

      CREATE INDEX IF NOT EXISTS idx_agent_tool_exec_tool_request
        ON agent_tool_executions(tool_request_id, created_at_ms DESC);

      CREATE TABLE IF NOT EXISTS project_heartbeat_state (
        project_id TEXT PRIMARY KEY,
        root_project_id TEXT NOT NULL,
        parent_project_id TEXT,
        lineage_depth INTEGER NOT NULL,
        queue_depth INTEGER NOT NULL,
        oldest_wait_ms INTEGER NOT NULL,
        blocked_reason_json TEXT,
        next_actions_json TEXT,
        risk_tier TEXT NOT NULL,
        heartbeat_seq INTEGER NOT NULL,
        sent_at_ms INTEGER NOT NULL,
        received_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        conservative_only INTEGER NOT NULL,
        last_dispatch_planned_at_ms INTEGER,
        dispatch_count INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        app_id TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_project_heartbeat_root_scope
        ON project_heartbeat_state(device_id, user_id, app_id, root_project_id, updated_at_ms DESC);

      CREATE INDEX IF NOT EXISTS idx_project_heartbeat_expiry
        ON project_heartbeat_state(expires_at_ms);

      CREATE INDEX IF NOT EXISTS idx_project_heartbeat_dispatch_fairness
        ON project_heartbeat_state(device_id, user_id, app_id, root_project_id, last_dispatch_planned_at_ms, oldest_wait_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_payment_intents (
        intent_id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT,
        app_id TEXT NOT NULL,
        project_id TEXT,
        status TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        currency TEXT NOT NULL,
        merchant_id TEXT,
        source_terminal_id TEXT,
        allowed_mobile_terminal_id TEXT,
        expected_photo_hash TEXT,
        expected_geo_hash TEXT,
        expected_qr_payload_hash TEXT,
        preview_fee_minor INTEGER,
        preview_risk_level TEXT,
        preview_undo_window_ms INTEGER,
        preview_card_hash TEXT,
        evidence_photo_hash TEXT,
        evidence_geo_hash TEXT,
        evidence_qr_payload_hash TEXT,
        evidence_nonce TEXT,
        evidence_currency TEXT,
        evidence_merchant_id TEXT,
        evidence_price_amount_minor INTEGER,
        evidence_captured_at_ms INTEGER,
        evidence_device_signature TEXT,
        evidence_verified_at_ms INTEGER,
        challenge_id TEXT,
        challenge_nonce TEXT,
        challenge_mobile_terminal_id TEXT,
        challenge_issued_at_ms INTEGER,
        challenge_expires_at_ms INTEGER,
        challenge_ttl_ms INTEGER NOT NULL,
        confirm_nonce TEXT,
        auth_factor TEXT,
        authorized_at_ms INTEGER,
        committed_at_ms INTEGER,
        commit_txn_id TEXT,
        receipt_delivery_state TEXT,
        receipt_commit_deadline_at_ms INTEGER,
        receipt_compensation_due_at_ms INTEGER,
        receipt_compensated_at_ms INTEGER,
        receipt_compensation_reason TEXT,
        abort_reason TEXT,
        aborted_at_ms INTEGER,
        expired_at_ms INTEGER,
        expires_at_ms INTEGER NOT NULL,
        deny_code TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_payment_intents_scope_request
        ON memory_payment_intents(device_id, user_id, app_id, project_id, request_id);

      CREATE INDEX IF NOT EXISTS idx_memory_payment_intents_state_expiry
        ON memory_payment_intents(status, expires_at_ms, challenge_expires_at_ms, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_payment_nonces (
        nonce_key TEXT PRIMARY KEY,
        nonce_kind TEXT NOT NULL,
        nonce_value TEXT NOT NULL,
        intent_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT,
        app_id TEXT NOT NULL,
        project_id TEXT,
        created_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_memory_payment_nonces_expiry
        ON memory_payment_nonces(expires_at_ms);

      CREATE TABLE IF NOT EXISTS memory_encryption_keys (
        dek_id TEXT PRIMARY KEY,
        purpose TEXT NOT NULL,
        kek_version TEXT NOT NULL,
        wrapped_dek_nonce_b64 TEXT NOT NULL,
        wrapped_dek_ct_b64 TEXT NOT NULL,
        wrapped_dek_tag_b64 TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        activated_at_ms INTEGER NOT NULL,
        retired_at_ms INTEGER
      );

      CREATE INDEX IF NOT EXISTS idx_memory_encryption_keys_status
        ON memory_encryption_keys(purpose, status, activated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_delete_tombstones (
        tombstone_id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        reason TEXT,
        run_id TEXT,
        deleted_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_memory_tombstones_expiry
        ON memory_delete_tombstones(expires_at_ms);

      CREATE INDEX IF NOT EXISTS idx_memory_tombstones_record
        ON memory_delete_tombstones(table_name, record_id);

      CREATE TABLE IF NOT EXISTS memory_retention_runs (
        run_id TEXT PRIMARY KEY,
        trigger TEXT NOT NULL,
        dry_run INTEGER NOT NULL,
        turns_ttl_ms INTEGER NOT NULL,
        canonical_ttl_ms INTEGER NOT NULL,
        turns_candidates INTEGER NOT NULL,
        turns_deleted INTEGER NOT NULL,
        canonical_candidates INTEGER NOT NULL,
        canonical_deleted INTEGER NOT NULL,
        tombstones_written INTEGER NOT NULL,
        tombstones_purged INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        details_json TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_memory_retention_runs_time
        ON memory_retention_runs(created_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_index_changelog (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        scope_json TEXT,
        source TEXT NOT NULL,
        payload_json TEXT,
        created_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_memory_index_changelog_time
        ON memory_index_changelog(created_at_ms, seq);

      CREATE INDEX IF NOT EXISTS idx_memory_index_changelog_record
        ON memory_index_changelog(table_name, record_id, seq);

      CREATE INDEX IF NOT EXISTS idx_memory_index_changelog_source
        ON memory_index_changelog(source, seq);

      CREATE TABLE IF NOT EXISTS memory_index_consumer_checkpoints (
        consumer_id TEXT PRIMARY KEY,
        checkpoint_seq INTEGER NOT NULL,
        last_event_id TEXT,
        status TEXT NOT NULL,
        retry_count INTEGER NOT NULL,
        last_error TEXT,
        last_processed_at_ms INTEGER,
        last_failed_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_memory_index_consumer_checkpoints_updated
        ON memory_index_consumer_checkpoints(updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_index_consumer_processed_events (
        consumer_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        table_name TEXT NOT NULL,
        source TEXT NOT NULL,
        processed_at_ms INTEGER NOT NULL,
        PRIMARY KEY(consumer_id, event_id)
      );

      CREATE INDEX IF NOT EXISTS idx_memory_index_consumer_processed_seq
        ON memory_index_consumer_processed_events(consumer_id, seq);

      CREATE TABLE IF NOT EXISTS memory_search_index_generations (
        generation_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        source TEXT NOT NULL,
        snapshot_from_seq INTEGER NOT NULL,
        snapshot_to_seq INTEGER NOT NULL,
        docs_total INTEGER NOT NULL,
        turns_total INTEGER NOT NULL,
        canonical_total INTEGER NOT NULL,
        started_at_ms INTEGER NOT NULL,
        finished_at_ms INTEGER,
        duration_ms INTEGER,
        swapped_from_generation_id TEXT,
        error_code TEXT,
        error_message TEXT,
        meta_json TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_memory_search_index_generations_status_time
        ON memory_search_index_generations(status, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_search_index_docs (
        generation_id TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        source_table TEXT NOT NULL,
        source_record_id TEXT NOT NULL,
        scope_json TEXT,
        sensitivity TEXT NOT NULL,
        trust_level TEXT NOT NULL,
        title TEXT,
        text_sha256 TEXT,
        text_bytes INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        PRIMARY KEY(generation_id, doc_id)
      );

      CREATE INDEX IF NOT EXISTS idx_memory_search_index_docs_generation
        ON memory_search_index_docs(generation_id, created_at_ms DESC);

      CREATE INDEX IF NOT EXISTS idx_memory_search_index_docs_source
        ON memory_search_index_docs(generation_id, source_table, source_record_id);

      CREATE TABLE IF NOT EXISTS memory_search_index_state (
        state_id INTEGER PRIMARY KEY CHECK (state_id = 1),
        active_generation_id TEXT,
        active_updated_at_ms INTEGER NOT NULL,
        last_rebuild_id TEXT,
        last_rebuild_status TEXT,
        last_error TEXT
      );

      CREATE TABLE IF NOT EXISTS memory_markdown_edit_sessions (
        edit_session_id TEXT PRIMARY KEY,
        doc_id TEXT NOT NULL,
        base_version TEXT NOT NULL,
        working_version TEXT NOT NULL,
        session_revision INTEGER NOT NULL,
        scope_filter TEXT NOT NULL,
        scope_ref_json TEXT,
        route_policy_json TEXT,
        route_stats_json TEXT,
        base_markdown TEXT NOT NULL,
        working_markdown TEXT NOT NULL,
        provenance_refs_json TEXT,
        status TEXT NOT NULL,
        created_by_device_id TEXT NOT NULL,
        created_by_user_id TEXT,
        created_by_app_id TEXT NOT NULL,
        created_by_project_id TEXT,
        created_by_session_id TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        last_patch_at_ms INTEGER,
        last_change_id TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_memory_markdown_edit_sessions_status_expiry
        ON memory_markdown_edit_sessions(status, expires_at_ms, updated_at_ms DESC);

      CREATE INDEX IF NOT EXISTS idx_memory_markdown_edit_sessions_scope
        ON memory_markdown_edit_sessions(created_by_device_id, created_by_user_id, created_by_app_id, created_by_project_id, updated_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_markdown_pending_changes (
        change_id TEXT PRIMARY KEY,
        edit_session_id TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        base_version TEXT NOT NULL,
        from_version TEXT NOT NULL,
        to_version TEXT NOT NULL,
        session_revision INTEGER NOT NULL,
        status TEXT NOT NULL,
        patch_mode TEXT NOT NULL,
        patch_note TEXT,
        patch_size_chars INTEGER NOT NULL,
        patch_line_count INTEGER NOT NULL,
        patch_sha256 TEXT NOT NULL,
        patched_markdown TEXT NOT NULL,
        provenance_refs_json TEXT,
        route_policy_json TEXT,
        created_by_device_id TEXT NOT NULL,
        created_by_user_id TEXT,
        created_by_app_id TEXT NOT NULL,
        created_by_project_id TEXT,
        created_by_session_id TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        reviewed_markdown TEXT,
        review_findings_json TEXT,
        review_decision TEXT,
        review_note TEXT,
        reviewed_at_ms INTEGER,
        reviewed_by_device_id TEXT,
        reviewed_by_user_id TEXT,
        reviewed_by_app_id TEXT,
        reviewed_by_project_id TEXT,
        reviewed_by_session_id TEXT,
        approved_at_ms INTEGER,
        approved_by_device_id TEXT,
        approved_by_user_id TEXT,
        approved_by_app_id TEXT,
        approved_by_project_id TEXT,
        approved_by_session_id TEXT,
        writeback_ref TEXT,
        written_at_ms INTEGER,
        rollback_ref TEXT,
        rolled_back_at_ms INTEGER,
        rolled_back_by_device_id TEXT,
        rolled_back_by_user_id TEXT,
        rolled_back_by_app_id TEXT,
        rolled_back_by_project_id TEXT,
        rolled_back_by_session_id TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_memory_markdown_pending_changes_session
        ON memory_markdown_pending_changes(edit_session_id, created_at_ms DESC);

      CREATE INDEX IF NOT EXISTS idx_memory_markdown_pending_changes_status
        ON memory_markdown_pending_changes(status, created_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_longterm_writeback_queue (
        candidate_id TEXT PRIMARY KEY,
        change_id TEXT NOT NULL UNIQUE,
        edit_session_id TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        base_version TEXT NOT NULL,
        source_version TEXT NOT NULL,
        content_markdown TEXT NOT NULL,
        scope_ref_json TEXT,
        provenance_refs_json TEXT,
        policy_decision_json TEXT,
        status TEXT NOT NULL,
        created_by_device_id TEXT NOT NULL,
        created_by_user_id TEXT,
        created_by_app_id TEXT NOT NULL,
        created_by_project_id TEXT,
        created_by_session_id TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        written_at_ms INTEGER NOT NULL,
        rolled_back_at_ms INTEGER,
        evidence_ref TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_memory_longterm_writeback_queue_status
        ON memory_longterm_writeback_queue(status, written_at_ms DESC);

      CREATE INDEX IF NOT EXISTS idx_memory_longterm_writeback_queue_doc
        ON memory_longterm_writeback_queue(doc_id, written_at_ms DESC);

      CREATE TABLE IF NOT EXISTS memory_longterm_writeback_changelog (
        log_id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        change_id TEXT NOT NULL,
        candidate_id TEXT,
        restored_candidate_id TEXT,
        doc_id TEXT NOT NULL,
        source_version TEXT,
        restored_source_version TEXT,
        scope_ref_json TEXT,
        policy_decision_json TEXT,
        evidence_ref TEXT,
        actor_device_id TEXT NOT NULL,
        actor_user_id TEXT,
        actor_app_id TEXT NOT NULL,
        actor_project_id TEXT,
        actor_session_id TEXT,
        note TEXT,
        created_at_ms INTEGER NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_longterm_writeback_changelog_event_change
        ON memory_longterm_writeback_changelog(event_type, change_id);

      CREATE INDEX IF NOT EXISTS idx_memory_longterm_writeback_changelog_doc
        ON memory_longterm_writeback_changelog(doc_id, created_at_ms DESC);

      CREATE TABLE IF NOT EXISTS quota_usage_daily (
        scope TEXT NOT NULL,
        day TEXT NOT NULL,
        token_used INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        PRIMARY KEY(scope, day)
      );

      CREATE INDEX IF NOT EXISTS idx_quota_scope_day
        ON quota_usage_daily(scope, day);

      CREATE TABLE IF NOT EXISTS terminal_model_usage_daily (
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        model_id TEXT NOT NULL,
        day_bucket TEXT NOT NULL,
        prompt_tokens INTEGER NOT NULL,
        completion_tokens INTEGER NOT NULL,
        total_tokens INTEGER NOT NULL,
        request_count INTEGER NOT NULL,
        blocked_count INTEGER NOT NULL,
        last_used_at_ms INTEGER,
        last_blocked_at_ms INTEGER,
        last_blocked_reason TEXT,
        last_deny_code TEXT,
        updated_at_ms INTEGER NOT NULL,
        PRIMARY KEY(device_id, model_id, day_bucket)
      );

      CREATE INDEX IF NOT EXISTS idx_terminal_model_usage_daily_device
        ON terminal_model_usage_daily(device_id, day_bucket, total_tokens DESC);

      CREATE INDEX IF NOT EXISTS idx_terminal_model_usage_daily_blocked
        ON terminal_model_usage_daily(device_id, day_bucket, last_blocked_at_ms DESC);

      CREATE TABLE IF NOT EXISTS pairing_requests (
        pairing_request_id TEXT PRIMARY KEY,
        pairing_secret_hash TEXT NOT NULL,
        request_id TEXT,
        claimed_device_id TEXT,
        user_id TEXT,
        app_id TEXT NOT NULL,
        device_name TEXT,
        device_info_json TEXT,
        requested_scopes_json TEXT,
        peer_ip TEXT,
        status TEXT NOT NULL,
        deny_reason TEXT,
        approved_device_id TEXT,
        approved_client_token TEXT,
        approved_capabilities_json TEXT,
        approved_allowed_cidrs_json TEXT,
        policy_mode TEXT,
        approved_trust_profile_json TEXT,
        created_at_ms INTEGER NOT NULL,
        decided_at_ms INTEGER,
        token_claimed_at_ms INTEGER
      );

      CREATE INDEX IF NOT EXISTS idx_pairing_status_time
        ON pairing_requests(status, created_at_ms);

      CREATE TABLE IF NOT EXISTS connector_webhook_replay_guard (
        connector TEXT NOT NULL,
        target_id TEXT NOT NULL,
        replay_key_hash TEXT NOT NULL,
        first_seen_at_ms INTEGER NOT NULL,
        expire_at_ms INTEGER NOT NULL,
        last_seen_at_ms INTEGER NOT NULL,
        PRIMARY KEY(connector, target_id, replay_key_hash)
      );

      CREATE INDEX IF NOT EXISTS idx_connector_webhook_replay_guard_expiry
        ON connector_webhook_replay_guard(expire_at_ms, last_seen_at_ms);
    `);

    // Non-breaking schema extensions (old DBs won't have these columns).
    this._ensureColumn('grant_requests', 'user_ack_understood', 'INTEGER');
    this._ensureColumn('grant_requests', 'explain_rounds', 'INTEGER');
    this._ensureColumn('grant_requests', 'options_presented', 'INTEGER');
    this._ensureColumn('memory_markdown_pending_changes', 'reviewed_markdown', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'review_findings_json', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'review_decision', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'review_note', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'reviewed_at_ms', 'INTEGER');
    this._ensureColumn('memory_markdown_pending_changes', 'reviewed_by_device_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'reviewed_by_user_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'reviewed_by_app_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'reviewed_by_project_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'reviewed_by_session_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'approved_at_ms', 'INTEGER');
    this._ensureColumn('memory_markdown_pending_changes', 'approved_by_device_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'approved_by_user_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'approved_by_app_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'approved_by_project_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'approved_by_session_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'writeback_ref', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'written_at_ms', 'INTEGER');
    this._ensureColumn('memory_markdown_pending_changes', 'rollback_ref', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'rolled_back_at_ms', 'INTEGER');
    this._ensureColumn('memory_markdown_pending_changes', 'rolled_back_by_device_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'rolled_back_by_user_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'rolled_back_by_app_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'rolled_back_by_project_id', 'TEXT');
    this._ensureColumn('memory_markdown_pending_changes', 'rolled_back_by_session_id', 'TEXT');
    this._ensureColumn('memory_longterm_writeback_queue', 'rolled_back_at_ms', 'INTEGER');
    this._ensureColumn('memory_longterm_writeback_queue', 'evidence_ref', 'TEXT');
    this._ensureColumn('agent_capsules', 'deny_code', 'TEXT');
    this._ensureColumn('agent_capsules', 'verification_report_ref', 'TEXT');
    this._ensureColumn('agent_capsules', 'verified_at_ms', 'INTEGER');
    this._ensureColumn('agent_capsules', 'activated_at_ms', 'INTEGER');
    this._ensureColumn('agent_capsules', 'active_generation', 'INTEGER');
    this._ensureColumn('agent_tool_requests', 'approval_argv_json', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'approval_cwd_input', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'approval_cwd_canonical', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'approval_identity_hash', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'gateway_provider', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'capability_token_kind', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'capability_token_id', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'capability_token_nonce', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'capability_token_state', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'capability_token_issued_at_ms', 'INTEGER');
    this._ensureColumn('pairing_requests', 'policy_mode', 'TEXT');
    this._ensureColumn('pairing_requests', 'approved_trust_profile_json', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'capability_token_expires_at_ms', 'INTEGER');
    this._ensureColumn('agent_tool_requests', 'capability_token_bound_request_id', 'TEXT');
    this._ensureColumn('agent_tool_requests', 'capability_token_consumed_at_ms', 'INTEGER');
    this._ensureColumn('agent_tool_requests', 'capability_token_revoked_at_ms', 'INTEGER');
    this._ensureColumn('agent_tool_requests', 'capability_token_revoke_reason', 'TEXT');
    this._ensureColumn('kill_switches', 'disabled_local_capabilities_json', 'TEXT');
    this._ensureColumn('kill_switches', 'disabled_local_providers_json', 'TEXT');
    this.db.exec(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_tool_requests_capability_token
        ON agent_tool_requests(capability_token_id)
        WHERE capability_token_id IS NOT NULL;
    `);
    this._ensureColumn('agent_tool_executions', 'exec_argv_json', 'TEXT');
    this._ensureColumn('agent_tool_executions', 'exec_cwd_input', 'TEXT');
    this._ensureColumn('agent_tool_executions', 'exec_cwd_canonical', 'TEXT');
    this._ensureColumn('agent_tool_executions', 'approval_identity_hash', 'TEXT');
    this._ensureColumn('agent_tool_executions', 'gateway_provider', 'TEXT');
    this._ensureColumn('memory_payment_intents', 'receipt_delivery_state', 'TEXT');
    this._ensureColumn('memory_payment_intents', 'receipt_commit_deadline_at_ms', 'INTEGER');
    this._ensureColumn('memory_payment_intents', 'receipt_compensation_due_at_ms', 'INTEGER');
    this._ensureColumn('memory_payment_intents', 'receipt_compensated_at_ms', 'INTEGER');
    this._ensureColumn('memory_payment_intents', 'receipt_compensation_reason', 'TEXT');
    this._ensureColumn('memory_payment_intents', 'preview_fee_minor', 'INTEGER');
    this._ensureColumn('memory_payment_intents', 'preview_risk_level', 'TEXT');
    this._ensureColumn('memory_payment_intents', 'preview_undo_window_ms', 'INTEGER');
    this._ensureColumn('memory_payment_intents', 'preview_card_hash', 'TEXT');
  }

  _ensureColumn(tableName, columnName, columnSql) {
    const table = String(tableName || '').trim();
    const col = String(columnName || '').trim();
    const sql = String(columnSql || '').trim();
    if (!table || !col || !sql) return;
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(table)) return;
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(col)) return;

    try {
      const rows = this.db.prepare(`PRAGMA table_info(${table})`).all();
      const hasCol = Array.isArray(rows)
        ? rows.some((r) => String(r?.name || '').trim() === col)
        : false;
      if (hasCol) return;
      this.db.exec(`ALTER TABLE ${table} ADD COLUMN ${col} ${sql}`);
    } catch {
      // ignore best-effort migrations
    }
  }

  _persistMemoryKekFileState() {
    if (!this.memoryKekFilePath) return;
    if (!this.memoryAtRestEnabled) return;
    const keks = {};
    for (const [version, keyBytes] of this.memoryKekRing.entries()) {
      keks[String(version)] = `base64:${Buffer.from(keyBytes).toString('base64')}`;
    }
    const payload = {
      schema_version: 'xhub.memory.kek.v1',
      active_kek_version: String(this.memoryKekActiveVersion || ''),
      keks,
      updated_at_ms: nowMs(),
    };
    fs.mkdirSync(path.dirname(this.memoryKekFilePath), { recursive: true });
    fs.writeFileSync(this.memoryKekFilePath, JSON.stringify(payload, null, 2), { mode: 0o600 });
    try {
      fs.chmodSync(this.memoryKekFilePath, 0o600);
    } catch {
      // ignore
    }
  }

  _memoryDekWrapAad({ dek_id, purpose, created_at_ms }) {
    return {
      schema: 'xhub.memory.dek.wrap.v1',
      dek_id: String(dek_id || ''),
      purpose: String(purpose || this.memoryDekPurpose || ''),
      created_at_ms: Number(created_at_ms || 0),
    };
  }

  _readMemoryDekRowById(dekId) {
    const id = String(dekId || '').trim();
    if (!id) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_encryption_keys
         WHERE dek_id = ? AND purpose = ?
         LIMIT 1`
      )
      .get(id, this.memoryDekPurpose) || null;
  }

  _readActiveMemoryDekRow() {
    return this.db
      .prepare(
        `SELECT *
         FROM memory_encryption_keys
         WHERE purpose = ? AND status = 'active'
         ORDER BY activated_at_ms DESC
         LIMIT 1`
      )
      .get(this.memoryDekPurpose) || null;
  }

  _unwrapMemoryDekRow(row) {
    if (!row) throw new Error('missing DEK row');
    const kekVersion = String(row.kek_version || '').trim();
    const kekBytes = this.memoryKekRing.get(kekVersion);
    if (!kekBytes) {
      throw new Error(`missing KEK material for version: ${kekVersion}`);
    }
    const wrapAad = this._memoryDekWrapAad(row);
    const dekBytes = unwrapDekWithKek({
      wrapped: {
        iv_b64: String(row.wrapped_dek_nonce_b64 || ''),
        ct_b64: String(row.wrapped_dek_ct_b64 || ''),
        tag_b64: String(row.wrapped_dek_tag_b64 || ''),
      },
      kekBytes,
      aad: wrapAad,
    });
    return {
      dek_id: String(row.dek_id || ''),
      dek_bytes: dekBytes,
      kek_version: kekVersion,
      status: String(row.status || ''),
      created_at_ms: Number(row.created_at_ms || 0),
      activated_at_ms: Number(row.activated_at_ms || 0),
    };
  }

  _loadMemoryDekById(dekId) {
    const id = String(dekId || '').trim();
    if (!id) throw new Error('missing dek_id');
    if (this._activeMemoryDekCache && this._activeMemoryDekCache.dek_id === id) {
      return this._activeMemoryDekCache;
    }
    const row = this._readMemoryDekRowById(id);
    if (!row) throw new Error(`missing DEK row: ${id}`);
    return this._unwrapMemoryDekRow(row);
  }

  _getActiveMemoryDekMaterial() {
    if (!this.memoryAtRestEnabled) {
      throw new Error('memory at-rest encryption disabled');
    }
    if (this._activeMemoryDekCache && this._activeMemoryDekCache.dek_id) {
      return this._activeMemoryDekCache;
    }
    const row = this._readActiveMemoryDekRow();
    if (!row) throw new Error('missing active DEK');
    const unwrapped = this._unwrapMemoryDekRow(row);
    this._activeMemoryDekCache = unwrapped;
    return unwrapped;
  }

  _createAndActivateMemoryDek() {
    if (!this.memoryAtRestEnabled) {
      return null;
    }
    const now = nowMs();
    const dekId = `dek_${uuid()}`;
    const dekBytes = randomDekBytes();
    const kekVersion = String(this.memoryKekActiveVersion || '').trim();
    if (!kekVersion || !this.memoryKekRing.has(kekVersion)) {
      throw new Error(`missing active KEK: ${kekVersion || '<empty>'}`);
    }
    const wrapped = wrapDekWithKek({
      dekBytes,
      kekBytes: this.memoryKekRing.get(kekVersion),
      aad: this._memoryDekWrapAad({ dek_id: dekId, purpose: this.memoryDekPurpose, created_at_ms: now }),
    });

    this.db.exec('BEGIN;');
    try {
      this.db
        .prepare(
          `UPDATE memory_encryption_keys
           SET status = 'retired', retired_at_ms = ?
           WHERE purpose = ? AND status = 'active'`
        )
        .run(now, this.memoryDekPurpose);

      this.db
        .prepare(
          `INSERT INTO memory_encryption_keys(
             dek_id, purpose, kek_version,
             wrapped_dek_nonce_b64, wrapped_dek_ct_b64, wrapped_dek_tag_b64,
             status, created_at_ms, activated_at_ms, retired_at_ms
           ) VALUES(?,?,?,?,?,?,?,?,?,?)`
        )
        .run(
          dekId,
          this.memoryDekPurpose,
          kekVersion,
          wrapped.iv_b64,
          wrapped.ct_b64,
          wrapped.tag_b64,
          'active',
          now,
          now,
          null
        );
      this.db.exec('COMMIT;');
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }

    const mat = {
      dek_id: dekId,
      dek_bytes: dekBytes,
      kek_version: kekVersion,
      status: 'active',
      created_at_ms: now,
      activated_at_ms: now,
    };
    this._activeMemoryDekCache = mat;
    return mat;
  }

  _buildTurnContentAad({ turn_id, thread_id, role }) {
    return {
      schema: 'xhub.memory.at_rest.v1',
      table: 'turns',
      field: 'content',
      turn_id: String(turn_id || ''),
      thread_id: String(thread_id || ''),
      role: String(role || ''),
    };
  }

  _buildCanonicalValueAad({ item_id, scope, thread_id, device_id, user_id, app_id, project_id, key }) {
    return {
      schema: 'xhub.memory.at_rest.v1',
      table: 'canonical_memory',
      field: 'value',
      item_id: String(item_id || ''),
      scope: String(scope || ''),
      thread_id: String(thread_id || ''),
      device_id: String(device_id || ''),
      user_id: String(user_id || ''),
      app_id: String(app_id || ''),
      project_id: String(project_id || ''),
      key: String(key || ''),
    };
  }

  _buildSecretVaultPayloadAad({
    item_id,
    scope,
    name_key,
    sensitivity,
    owner_device_id,
    owner_user_id,
    owner_app_id,
    owner_project_id,
    created_at_ms,
  }) {
    return {
      schema: 'xhub.memory.at_rest.v1',
      table: 'secret_vault_items',
      field: 'ciphertext_text',
      item_id: String(item_id || ''),
      scope: String(scope || ''),
      name_key: String(name_key || ''),
      sensitivity: String(sensitivity || 'secret'),
      owner_device_id: String(owner_device_id || ''),
      owner_user_id: String(owner_user_id || ''),
      owner_app_id: String(owner_app_id || ''),
      owner_project_id: String(owner_project_id || ''),
      created_at_ms: Math.max(0, Number(created_at_ms || 0)),
    };
  }

  _encryptMemoryField(valueText, aad) {
    const raw = String(valueText ?? '');
    if (!this.memoryAtRestEnabled) return raw;
    const activeDek = this._getActiveMemoryDekMaterial();
    return encryptTextWithDek({
      plaintext: raw,
      dekBytes: activeDek.dek_bytes,
      dekId: activeDek.dek_id,
      kekVersion: activeDek.kek_version,
      aad,
    });
  }

  _decryptMemoryField(valueText, aad) {
    const raw = String(valueText ?? '');
    const meta = parseEncryptedEnvelopeMeta(raw);
    if (!meta) return raw;
    if (!this.memoryAtRestEnabled) {
      throw new Error('memory at-rest encryption disabled; cannot decrypt encrypted rows');
    }
    const dek = this._loadMemoryDekById(meta.dek_id);
    const out = decryptTextWithDek({
      envelopeText: raw,
      dekBytes: dek.dek_bytes,
      aad,
    });
    return String(out.plaintext || '');
  }

  _encryptTurnContent({ turn_id, thread_id, role, content }) {
    return this._encryptMemoryField(content, this._buildTurnContentAad({ turn_id, thread_id, role }));
  }

  _decryptTurnContentRow(row) {
    return this._decryptMemoryField(
      row?.content ?? '',
      this._buildTurnContentAad({
        turn_id: row?.turn_id,
        thread_id: row?.thread_id,
        role: row?.role,
      })
    );
  }

  _encryptCanonicalValue(rowLike) {
    return this._encryptMemoryField(
      rowLike?.value ?? '',
      this._buildCanonicalValueAad({
        item_id: rowLike?.item_id,
        scope: rowLike?.scope,
        thread_id: rowLike?.thread_id,
        device_id: rowLike?.device_id,
        user_id: rowLike?.user_id,
        app_id: rowLike?.app_id,
        project_id: rowLike?.project_id,
        key: rowLike?.key,
      })
    );
  }

  _decryptCanonicalRow(row) {
    if (!row) return null;
    const out = { ...row };
    out.value = this._decryptMemoryField(
      row.value ?? '',
      this._buildCanonicalValueAad({
        item_id: row.item_id,
        scope: row.scope,
        thread_id: row.thread_id,
        device_id: row.device_id,
        user_id: row.user_id,
        app_id: row.app_id,
        project_id: row.project_id,
        key: row.key,
      })
    );
    return out;
  }

  _encryptSecretVaultPlaintext(rowLike) {
    return this._encryptMemoryField(
      rowLike?.plaintext ?? '',
      this._buildSecretVaultPayloadAad(rowLike)
    );
  }

  _decryptSecretVaultPlaintextRow(row) {
    if (!row) return '';
    return this._decryptMemoryField(
      row.ciphertext_text ?? '',
      this._buildSecretVaultPayloadAad(row)
    );
  }

  _initMemoryAtRestState() {
    if (!this.memoryAtRestEnabled) return;
    const active = this._readActiveMemoryDekRow();
    if (active) {
      this._activeMemoryDekCache = this._unwrapMemoryDekRow(active);
      return;
    }
    this._createAndActivateMemoryDek();
  }

  getMemoryAtRestStatus() {
    const active = this.memoryAtRestEnabled ? this._readActiveMemoryDekRow() : null;
    return {
      enabled: !!this.memoryAtRestEnabled,
      active_kek_version: String(this.memoryKekActiveVersion || ''),
      active_dek_id: active ? String(active.dek_id || '') : '',
      kek_versions: Array.from(this.memoryKekRing.keys()),
    };
  }

  setMemoryActiveKekVersion(kekVersion) {
    const v = String(kekVersion || '').trim();
    if (!v) throw new Error('missing kekVersion');
    if (!this.memoryKekRing.has(v)) throw new Error(`unknown KEK version: ${v}`);
    this.memoryKekActiveVersion = v;
    this._persistMemoryKekFileState();
    return v;
  }

  addMemoryKekVersion({ kek_version, key_material, set_active }) {
    const version = String(kek_version || '').trim();
    if (!version) throw new Error('missing kek_version');
    const keyBytes = parseFixedKeyMaterial(key_material);
    if (!keyBytes) throw new Error('invalid key_material (expect 32-byte base64/hex)');
    this.memoryKekRing.set(version, keyBytes);
    if (set_active) {
      this.memoryKekActiveVersion = version;
    }
    this._persistMemoryKekFileState();
    return {
      kek_version: version,
      active_kek_version: String(this.memoryKekActiveVersion || ''),
      total_versions: this.memoryKekRing.size,
    };
  }

  rotateMemoryDek() {
    const created = this._createAndActivateMemoryDek();
    if (!created) return { ok: false, reason: 'memory_at_rest_disabled' };
    return {
      ok: true,
      dek_id: created.dek_id,
      kek_version: created.kek_version,
      rotated_at_ms: created.activated_at_ms,
    };
  }

  rewrapMemoryDeksToActiveKek() {
    if (!this.memoryAtRestEnabled) {
      return { ok: false, reason: 'memory_at_rest_disabled', rewrapped: 0 };
    }
    const activeKekVersion = String(this.memoryKekActiveVersion || '').trim();
    const activeKekBytes = this.memoryKekRing.get(activeKekVersion);
    if (!activeKekVersion || !activeKekBytes) {
      throw new Error('missing active KEK material');
    }
    const now = nowMs();
    const rows = this.db
      .prepare(
        `SELECT *
         FROM memory_encryption_keys
         WHERE purpose = ?
         ORDER BY created_at_ms ASC`
      )
      .all(this.memoryDekPurpose);

    let rewrapped = 0;
    this.db.exec('BEGIN;');
    try {
      const upd = this.db.prepare(
        `UPDATE memory_encryption_keys
         SET kek_version = ?, wrapped_dek_nonce_b64 = ?, wrapped_dek_ct_b64 = ?, wrapped_dek_tag_b64 = ?
         WHERE dek_id = ?`
      );

      for (const row of rows) {
        const oldVersion = String(row?.kek_version || '').trim();
        if (!oldVersion || oldVersion === activeKekVersion) continue;
        const oldKekBytes = this.memoryKekRing.get(oldVersion);
        if (!oldKekBytes) {
          throw new Error(`missing KEK material for existing DEK row: ${oldVersion}`);
        }

        const dekBytes = unwrapDekWithKek({
          wrapped: {
            iv_b64: String(row.wrapped_dek_nonce_b64 || ''),
            ct_b64: String(row.wrapped_dek_ct_b64 || ''),
            tag_b64: String(row.wrapped_dek_tag_b64 || ''),
          },
          kekBytes: oldKekBytes,
          aad: this._memoryDekWrapAad({
            dek_id: row.dek_id,
            purpose: row.purpose,
            created_at_ms: row.created_at_ms,
          }),
        });

        const nextWrapped = wrapDekWithKek({
          dekBytes,
          kekBytes: activeKekBytes,
          aad: this._memoryDekWrapAad({
            dek_id: row.dek_id,
            purpose: row.purpose,
            created_at_ms: row.created_at_ms,
          }),
        });

        upd.run(
          activeKekVersion,
          nextWrapped.iv_b64,
          nextWrapped.ct_b64,
          nextWrapped.tag_b64,
          String(row.dek_id || '')
        );
        rewrapped += 1;
        if (this._activeMemoryDekCache && this._activeMemoryDekCache.dek_id === String(row.dek_id || '')) {
          this._activeMemoryDekCache = {
            ...this._activeMemoryDekCache,
            kek_version: activeKekVersion,
            activated_at_ms: Math.max(Number(this._activeMemoryDekCache.activated_at_ms || 0), now),
          };
        }
      }
      this.db.exec('COMMIT;');
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
    return { ok: true, rewrapped, active_kek_version: activeKekVersion, at_ms: now };
  }

  _recordMemoryRetentionRun(summary) {
    this.db
      .prepare(
        `INSERT INTO memory_retention_runs(
           run_id, trigger, dry_run,
           turns_ttl_ms, canonical_ttl_ms,
           turns_candidates, turns_deleted, canonical_candidates, canonical_deleted,
           tombstones_written, tombstones_purged,
           created_at_ms, details_json
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        String(summary.run_id || ''),
        String(summary.trigger || ''),
        summary.dry_run ? 1 : 0,
        Number(summary.turns_ttl_ms || 0),
        Number(summary.canonical_ttl_ms || 0),
        Number(summary.turns_candidates || 0),
        Number(summary.turns_deleted || 0),
        Number(summary.canonical_candidates || 0),
        Number(summary.canonical_deleted || 0),
        Number(summary.tombstones_written || 0),
        Number(summary.tombstones_purged || 0),
        Number(summary.created_at_ms || 0),
        JSON.stringify({
          include_pinned: !!summary.include_pinned,
          batch_limit: Number(summary.batch_limit || 0),
          reason: String(summary.reason || ''),
        })
      );
  }

  _normalizeMemoryIndexScope(scope = {}) {
    const out = {};
    const keys = ['scope', 'thread_id', 'device_id', 'user_id', 'app_id', 'project_id'];
    for (const k of keys) {
      const raw = scope?.[k];
      if (raw == null) continue;
      const v = String(raw).trim();
      if (!v) continue;
      out[k] = v;
    }
    return out;
  }

  _safeJsonStringify(value) {
    if (value == null) return null;
    try {
      return JSON.stringify(value);
    } catch {
      return null;
    }
  }

  _safeJsonParse(value, fallback = null) {
    if (value == null || value === '') return fallback;
    if (typeof value === 'object') return value;
    try {
      return JSON.parse(String(value));
    } catch {
      return fallback;
    }
  }

  _normalizeMemoryIndexConsumerId(v) {
    const id = String(v || '').trim();
    if (!id) throw new Error('missing consumer_id');
    if (id.length > 128) return id.slice(0, 128);
    return id;
  }

  _appendMemoryIndexChangelog(entry = {}) {
    const eventType = String(entry?.event_type || '').trim().toLowerCase();
    if (!['insert', 'update', 'delete', 'restore'].includes(eventType)) return false;

    const tableName = String(entry?.table_name || '').trim();
    if (!tableName) return false;

    const recordId = String(entry?.record_id || '').trim();
    if (!recordId) return false;

    const source = String(entry?.source || 'unknown').trim() || 'unknown';
    const eventId = String(entry?.event_id || '').trim() || `midx_${uuid()}`;
    const createdAtMs = Math.max(0, Number(entry?.created_at_ms || nowMs()));

    const scopeObj = this._normalizeMemoryIndexScope(entry?.scope || {});
    const scopeJson = Object.keys(scopeObj).length > 0 ? this._safeJsonStringify(scopeObj) : null;
    const payloadJson = this._safeJsonStringify(entry?.payload);

    try {
      if (!this._insMemoryIndexChangelogStmt) {
        this._insMemoryIndexChangelogStmt = this.db.prepare(
          `INSERT OR IGNORE INTO memory_index_changelog(
             event_id, event_type, table_name, record_id, scope_json, source, payload_json, created_at_ms
           ) VALUES(?,?,?,?,?,?,?,?)`
        );
      }
      this._insMemoryIndexChangelogStmt.run(
        eventId,
        eventType,
        tableName,
        recordId,
        scopeJson,
        source,
        payloadJson,
        createdAtMs
      );
      return true;
    } catch {
      // Best-effort: changelog must not block primary write path.
      return false;
    }
  }

  _appendMemoryRetentionAudit(summary, err = null) {
    if (!this.memoryRetentionAuditEnabled) return;
    const ok = !err;
    let extObj = {
      run_id: String(summary?.run_id || ''),
      trigger: String(summary?.trigger || ''),
      dry_run: !!summary?.dry_run,
      turns_candidates: Number(summary?.turns_candidates || 0),
      turns_deleted: Number(summary?.turns_deleted || 0),
      canonical_candidates: Number(summary?.canonical_candidates || 0),
      canonical_deleted: Number(summary?.canonical_deleted || 0),
      tombstones_written: Number(summary?.tombstones_written || 0),
      tombstones_purged: Number(summary?.tombstones_purged || 0),
    };
    if (err) {
      extObj = {
        ...extObj,
        error: String(err?.message || err || 'unknown_error'),
      };
    }
    this.appendAudit({
      event_type: ok ? 'memory.retention.completed' : 'memory.retention.failed',
      severity: ok ? 'info' : 'error',
      created_at_ms: Number(summary?.created_at_ms || nowMs()),
      device_id: 'hub',
      app_id: 'hub.memory.retention',
      ok,
      error_code: ok ? null : 'memory_retention_failed',
      error_message: ok ? null : String(err?.message || err || 'memory retention failed'),
      ext_json: JSON.stringify(extObj),
    });
  }

  runMemoryRetentionJob(opts = {}) {
    const now = Math.max(0, Number(opts?.now_ms || nowMs()));
    const dryRun = !!opts?.dry_run;
    const trigger = String(opts?.trigger || 'manual').trim() || 'manual';
    const reason = String(opts?.reason || '').trim();

    if (!this.memoryRetentionEnabled) {
      return {
        ok: false,
        reason: 'memory_retention_disabled',
        run_id: '',
        trigger,
        dry_run: dryRun,
        created_at_ms: now,
      };
    }

    const turnsTtlMs = Math.max(0, Number(this.memoryRetentionTurnsTtlMs || 0));
    const canonicalTtlMs = Math.max(0, Number(this.memoryRetentionCanonicalTtlMs || 0));
    const includePinned = !!this.memoryRetentionCanonicalIncludePinned;
    const batchLimit = Math.max(1, Number(this.memoryRetentionBatchLimit || 1));
    const tombstoneTtlMs = Math.max(0, Number(this.memoryRetentionTombstoneTtlMs || 0));
    const runId = `ret_${uuid()}`;

    const turnsCutoff = turnsTtlMs > 0 ? (now - turnsTtlMs) : 0;
    const canonicalCutoff = canonicalTtlMs > 0 ? (now - canonicalTtlMs) : 0;

    const turnsRows = turnsTtlMs > 0
      ? this.db
        .prepare(
          `SELECT turn_id, thread_id, request_id, role, content, is_private, created_at_ms
           FROM turns
           WHERE created_at_ms <= ?
           ORDER BY created_at_ms ASC
           LIMIT ?`
        )
        .all(turnsCutoff, batchLimit)
      : [];

    const canonicalRows = canonicalTtlMs > 0
      ? this.db
        .prepare(
          includePinned
            ? `SELECT *
               FROM canonical_memory
               WHERE updated_at_ms <= ?
               ORDER BY updated_at_ms ASC
               LIMIT ?`
            : `SELECT *
               FROM canonical_memory
               WHERE updated_at_ms <= ? AND pinned = 0
               ORDER BY updated_at_ms ASC
               LIMIT ?`
        )
        .all(canonicalCutoff, batchLimit)
      : [];

    const expiredTombstones = this.db
      .prepare(
        `SELECT tombstone_id
         FROM memory_delete_tombstones
         WHERE expires_at_ms <= ?
         ORDER BY expires_at_ms ASC
         LIMIT ?`
      )
      .all(now, batchLimit);

    const summary = {
      ok: true,
      run_id: runId,
      trigger,
      reason,
      dry_run: dryRun,
      include_pinned: includePinned,
      batch_limit: batchLimit,
      turns_ttl_ms: turnsTtlMs,
      canonical_ttl_ms: canonicalTtlMs,
      turns_candidates: turnsRows.length,
      turns_deleted: 0,
      canonical_candidates: canonicalRows.length,
      canonical_deleted: 0,
      tombstones_written: 0,
      tombstones_purged: dryRun ? expiredTombstones.length : 0,
      created_at_ms: now,
    };

    if (!dryRun) {
      this.db.exec('BEGIN;');
      try {
        const deleteTombstoneStmt = this.db.prepare(`DELETE FROM memory_delete_tombstones WHERE tombstone_id = ?`);
        for (const row of expiredTombstones) {
          deleteTombstoneStmt.run(String(row?.tombstone_id || ''));
          summary.tombstones_purged += 1;
        }

        const insTombstone = tombstoneTtlMs > 0
          ? this.db.prepare(
            `INSERT INTO memory_delete_tombstones(
               tombstone_id, table_name, record_id, payload_json, reason, run_id, deleted_at_ms, expires_at_ms
             ) VALUES(?,?,?,?,?,?,?,?)`
          )
          : null;

        const delTurn = this.db.prepare(`DELETE FROM turns WHERE turn_id = ?`);
        for (const row of turnsRows) {
          const turnId = String(row?.turn_id || '').trim();
          if (!turnId) continue;
          if (insTombstone) {
            insTombstone.run(
              `ts_${uuid()}`,
              'turns',
              turnId,
              JSON.stringify(row),
              'retention.turns_ttl',
              runId,
              now,
              now + tombstoneTtlMs
            );
            summary.tombstones_written += 1;
          }
          delTurn.run(turnId);
          summary.turns_deleted += 1;
          this._appendMemoryIndexChangelog({
            event_type: 'delete',
            table_name: 'turns',
            record_id: turnId,
            scope: {
              thread_id: String(row?.thread_id || ''),
            },
            source: 'memory_retention',
            created_at_ms: now,
            payload: {
              reason: 'retention.turns_ttl',
              run_id: runId,
              deleted_at_ms: now,
              request_id: row?.request_id != null ? String(row.request_id) : null,
              role: String(row?.role || ''),
              is_private: Number(row?.is_private || 0) ? 1 : 0,
              created_at_ms: Number(row?.created_at_ms || 0),
            },
          });
        }

        const delCanonical = this.db.prepare(`DELETE FROM canonical_memory WHERE item_id = ?`);
        for (const row of canonicalRows) {
          const itemId = String(row?.item_id || '').trim();
          if (!itemId) continue;
          if (insTombstone) {
            insTombstone.run(
              `ts_${uuid()}`,
              'canonical_memory',
              itemId,
              JSON.stringify(row),
              'retention.canonical_ttl',
              runId,
              now,
              now + tombstoneTtlMs
            );
            summary.tombstones_written += 1;
          }
          delCanonical.run(itemId);
          summary.canonical_deleted += 1;
          this._appendMemoryIndexChangelog({
            event_type: 'delete',
            table_name: 'canonical_memory',
            record_id: itemId,
            scope: {
              scope: String(row?.scope || ''),
              thread_id: String(row?.thread_id || ''),
              device_id: String(row?.device_id || ''),
              user_id: String(row?.user_id || ''),
              app_id: String(row?.app_id || ''),
              project_id: String(row?.project_id || ''),
            },
            source: 'memory_retention',
            created_at_ms: now,
            payload: {
              reason: 'retention.canonical_ttl',
              run_id: runId,
              deleted_at_ms: now,
              key: String(row?.key || ''),
              pinned: Number(row?.pinned || 0) ? 1 : 0,
              updated_at_ms: Number(row?.updated_at_ms || 0),
            },
          });
        }

        this.db.exec('COMMIT;');
      } catch (e) {
        try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
        this._appendMemoryRetentionAudit(summary, e);
        throw e;
      }
    }

    this._recordMemoryRetentionRun(summary);
    this._appendMemoryRetentionAudit(summary, null);
    return summary;
  }

  _maybeRunMemoryRetentionJob(trigger = 'auto') {
    if (!this.memoryRetentionEnabled) return;
    if (!this.memoryRetentionAutoJobEnabled) return;
    const now = nowMs();
    if (now < this._nextMemoryRetentionRunAtMs) return;
    this._nextMemoryRetentionRunAtMs = now + this.memoryRetentionJobIntervalMs;
    try {
      this.runMemoryRetentionJob({ trigger: `auto:${String(trigger || 'unknown')}` });
    } catch {
      // Best-effort only; retention must not break request handling.
    }
  }

  listMemoryRetentionRuns({ limit } = {}) {
    const lim = Math.max(1, Math.min(500, Number(limit || 100)));
    return this.db
      .prepare(
        `SELECT *
         FROM memory_retention_runs
         ORDER BY created_at_ms DESC
         LIMIT ?`
      )
      .all(lim);
  }

  listMemoryIndexChangelog({ since_seq, limit, table_name, event_type } = {}) {
    const sinceSeq = Math.max(0, Number(since_seq || 0));
    const lim = Math.max(1, Math.min(5000, Number(limit || 200)));
    const tableName = String(table_name || '').trim();
    const eventType = String(event_type || '').trim().toLowerCase();

    const where = ['seq > ?'];
    const args = [sinceSeq];
    if (tableName) {
      where.push('table_name = ?');
      args.push(tableName);
    }
    if (eventType) {
      where.push('event_type = ?');
      args.push(eventType);
    }
    args.push(lim);

    return this.db
      .prepare(
        `SELECT *
         FROM memory_index_changelog
         WHERE ${where.join(' AND ')}
         ORDER BY seq ASC
         LIMIT ?`
      )
      .all(...args);
  }

  getMemoryIndexChangelogMaxSeq() {
    const row = this.db
      .prepare(`SELECT MAX(seq) AS max_seq FROM memory_index_changelog`)
      .get();
    return Math.max(0, Number(row?.max_seq || 0));
  }

  createMemorySearchIndexGeneration(fields = {}) {
    const now = nowMs();
    const generationId = String(fields?.generation_id || '').trim() || `midxg_${uuid()}`;
    const statusRaw = String(fields?.status || 'building').trim().toLowerCase();
    const status = ['building', 'ready', 'active', 'failed', 'retired'].includes(statusRaw)
      ? statusRaw
      : 'building';
    const source = String(fields?.source || 'manual').trim() || 'manual';
    const snapshotFromSeq = Math.max(0, Number(fields?.snapshot_from_seq || 0));
    const snapshotToSeq = Math.max(snapshotFromSeq, Number(fields?.snapshot_to_seq || snapshotFromSeq));
    const startedAtMs = Math.max(0, Number(fields?.started_at_ms || now));
    const createdAtMs = Math.max(0, Number(fields?.created_at_ms || startedAtMs));
    const updatedAtMs = Math.max(0, Number(fields?.updated_at_ms || startedAtMs));
    const docsTotal = Math.max(0, Number(fields?.docs_total || 0));
    const turnsTotal = Math.max(0, Number(fields?.turns_total || 0));
    const canonicalTotal = Math.max(0, Number(fields?.canonical_total || 0));
    const finishedAtMs = fields?.finished_at_ms != null ? Math.max(0, Number(fields.finished_at_ms || 0)) : null;
    const durationMs = fields?.duration_ms != null ? Math.max(0, Number(fields.duration_ms || 0)) : null;
    const swappedFrom = fields?.swapped_from_generation_id != null
      ? (String(fields.swapped_from_generation_id || '').trim() || null)
      : null;
    const errorCode = fields?.error_code != null ? (String(fields.error_code || '').trim() || null) : null;
    const errorMessage = fields?.error_message != null ? (String(fields.error_message || '').trim() || null) : null;
    const metaJson = this._safeJsonStringify(fields?.meta_json ?? fields?.meta);

    this.db
      .prepare(
        `INSERT INTO memory_search_index_generations(
           generation_id, status, source,
           snapshot_from_seq, snapshot_to_seq,
           docs_total, turns_total, canonical_total,
           started_at_ms, finished_at_ms, duration_ms,
           swapped_from_generation_id, error_code, error_message, meta_json,
           created_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        generationId,
        status,
        source,
        snapshotFromSeq,
        snapshotToSeq,
        docsTotal,
        turnsTotal,
        canonicalTotal,
        startedAtMs,
        finishedAtMs,
        durationMs,
        swappedFrom,
        errorCode,
        errorMessage,
        metaJson,
        createdAtMs,
        updatedAtMs
      );
    return this.getMemorySearchIndexGeneration({ generation_id: generationId });
  }

  getMemorySearchIndexGeneration({ generation_id } = {}) {
    const generationId = String(generation_id || '').trim();
    if (!generationId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_search_index_generations
         WHERE generation_id = ?
         LIMIT 1`
      )
      .get(generationId) || null;
  }

  updateMemorySearchIndexGeneration({ generation_id, ...patch } = {}) {
    const generationId = String(generation_id || '').trim();
    if (!generationId) throw new Error('missing generation_id');
    const current = this.getMemorySearchIndexGeneration({ generation_id: generationId });
    if (!current) throw new Error('generation_not_found');

    const now = nowMs();
    const statusRaw = patch?.status != null
      ? String(patch.status || '').trim().toLowerCase()
      : String(current.status || '').trim().toLowerCase();
    const status = ['building', 'ready', 'active', 'failed', 'retired'].includes(statusRaw)
      ? statusRaw
      : 'building';

    const source = patch?.source != null
      ? (String(patch.source || '').trim() || 'manual')
      : String(current.source || 'manual');
    const snapshotFromSeq = patch?.snapshot_from_seq != null
      ? Math.max(0, Number(patch.snapshot_from_seq || 0))
      : Math.max(0, Number(current.snapshot_from_seq || 0));
    const snapshotToSeq = patch?.snapshot_to_seq != null
      ? Math.max(snapshotFromSeq, Number(patch.snapshot_to_seq || 0))
      : Math.max(snapshotFromSeq, Number(current.snapshot_to_seq || snapshotFromSeq));
    const docsTotal = patch?.docs_total != null
      ? Math.max(0, Number(patch.docs_total || 0))
      : Math.max(0, Number(current.docs_total || 0));
    const turnsTotal = patch?.turns_total != null
      ? Math.max(0, Number(patch.turns_total || 0))
      : Math.max(0, Number(current.turns_total || 0));
    const canonicalTotal = patch?.canonical_total != null
      ? Math.max(0, Number(patch.canonical_total || 0))
      : Math.max(0, Number(current.canonical_total || 0));

    const startedAtMs = patch?.started_at_ms != null
      ? Math.max(0, Number(patch.started_at_ms || 0))
      : Math.max(0, Number(current.started_at_ms || now));
    const finishedAtMs = patch?.finished_at_ms !== undefined
      ? (patch.finished_at_ms != null ? Math.max(0, Number(patch.finished_at_ms || 0)) : null)
      : (current.finished_at_ms != null ? Math.max(0, Number(current.finished_at_ms || 0)) : null);
    const durationMs = patch?.duration_ms !== undefined
      ? (patch.duration_ms != null ? Math.max(0, Number(patch.duration_ms || 0)) : null)
      : (current.duration_ms != null ? Math.max(0, Number(current.duration_ms || 0)) : null);
    const swappedFrom = patch?.swapped_from_generation_id !== undefined
      ? (patch.swapped_from_generation_id != null ? (String(patch.swapped_from_generation_id || '').trim() || null) : null)
      : (current.swapped_from_generation_id != null ? String(current.swapped_from_generation_id) : null);
    const errorCode = patch?.error_code !== undefined
      ? (patch.error_code != null ? (String(patch.error_code || '').trim() || null) : null)
      : (current.error_code != null ? String(current.error_code) : null);
    const errorMessage = patch?.error_message !== undefined
      ? (patch.error_message != null ? (String(patch.error_message || '').trim() || null) : null)
      : (current.error_message != null ? String(current.error_message) : null);
    const metaJson = patch?.meta_json !== undefined || patch?.meta !== undefined
      ? this._safeJsonStringify(patch?.meta_json ?? patch?.meta)
      : (current.meta_json != null ? String(current.meta_json) : null);
    const createdAtMs = Math.max(0, Number(current.created_at_ms || startedAtMs));
    const updatedAtMs = patch?.updated_at_ms != null ? Math.max(0, Number(patch.updated_at_ms || 0)) : now;

    this.db
      .prepare(
        `UPDATE memory_search_index_generations
         SET status = ?, source = ?,
             snapshot_from_seq = ?, snapshot_to_seq = ?,
             docs_total = ?, turns_total = ?, canonical_total = ?,
             started_at_ms = ?, finished_at_ms = ?, duration_ms = ?,
             swapped_from_generation_id = ?, error_code = ?, error_message = ?, meta_json = ?,
             created_at_ms = ?, updated_at_ms = ?
         WHERE generation_id = ?`
      )
      .run(
        status,
        source,
        snapshotFromSeq,
        snapshotToSeq,
        docsTotal,
        turnsTotal,
        canonicalTotal,
        startedAtMs,
        finishedAtMs,
        durationMs,
        swappedFrom,
        errorCode,
        errorMessage,
        metaJson,
        createdAtMs,
        updatedAtMs,
        generationId
      );
    return this.getMemorySearchIndexGeneration({ generation_id: generationId });
  }

  listMemorySearchIndexGenerations({ limit, status } = {}) {
    const lim = Math.max(1, Math.min(1000, Number(limit || 100)));
    const s = String(status || '').trim().toLowerCase();
    if (!s) {
      return this.db
        .prepare(
          `SELECT *
           FROM memory_search_index_generations
           ORDER BY updated_at_ms DESC
           LIMIT ?`
        )
        .all(lim);
    }
    return this.db
      .prepare(
        `SELECT *
         FROM memory_search_index_generations
         WHERE status = ?
         ORDER BY updated_at_ms DESC
         LIMIT ?`
      )
      .all(s, lim);
  }

  _ensureMemorySearchIndexStateRow() {
    const now = nowMs();
    this.db
      .prepare(
        `INSERT OR IGNORE INTO memory_search_index_state(
           state_id, active_generation_id, active_updated_at_ms, last_rebuild_id, last_rebuild_status, last_error
         ) VALUES(1,NULL,?,?,?,?)`
      )
      .run(now, null, 'idle', null);
  }

  getMemorySearchIndexState() {
    this._ensureMemorySearchIndexStateRow();
    return this.db
      .prepare(`SELECT * FROM memory_search_index_state WHERE state_id = 1 LIMIT 1`)
      .get() || null;
  }

  _updateMemorySearchIndexState({
    active_generation_id,
    active_updated_at_ms,
    last_rebuild_id,
    last_rebuild_status,
    last_error,
  } = {}) {
    const cur = this.getMemorySearchIndexState() || {};
    const activeGen = active_generation_id !== undefined
      ? (active_generation_id != null ? (String(active_generation_id || '').trim() || null) : null)
      : (cur.active_generation_id != null ? String(cur.active_generation_id) : null);
    const activeUpdatedAt = active_updated_at_ms != null
      ? Math.max(0, Number(active_updated_at_ms || 0))
      : Math.max(0, Number(cur.active_updated_at_ms || nowMs()));
    const lastRebuildId = last_rebuild_id !== undefined
      ? (last_rebuild_id != null ? (String(last_rebuild_id || '').trim() || null) : null)
      : (cur.last_rebuild_id != null ? String(cur.last_rebuild_id) : null);
    const lastRebuildStatus = last_rebuild_status !== undefined
      ? (last_rebuild_status != null ? (String(last_rebuild_status || '').trim() || null) : null)
      : (cur.last_rebuild_status != null ? String(cur.last_rebuild_status) : null);
    const lastError = last_error !== undefined
      ? (last_error != null ? (String(last_error || '').trim() || null) : null)
      : (cur.last_error != null ? String(cur.last_error) : null);

    this.db
      .prepare(
        `UPDATE memory_search_index_state
         SET active_generation_id = ?, active_updated_at_ms = ?, last_rebuild_id = ?, last_rebuild_status = ?, last_error = ?
         WHERE state_id = 1`
      )
      .run(activeGen, activeUpdatedAt, lastRebuildId, lastRebuildStatus, lastError);
    return this.getMemorySearchIndexState();
  }

  getActiveMemorySearchIndexGeneration() {
    const st = this.getMemorySearchIndexState();
    const generationId = String(st?.active_generation_id || '').trim();
    if (!generationId) return null;
    return this.getMemorySearchIndexGeneration({ generation_id: generationId });
  }

  ensureMemorySearchIndexBaselineActive({ source } = {}) {
    const active = this.getActiveMemorySearchIndexGeneration();
    if (active) return active;

    const now = nowMs();
    const generationId = `midxg_bootstrap_${uuid()}`;
    this.db.exec('BEGIN;');
    try {
      this.createMemorySearchIndexGeneration({
        generation_id: generationId,
        status: 'active',
        source: String(source || 'bootstrap').trim() || 'bootstrap',
        snapshot_from_seq: 0,
        snapshot_to_seq: 0,
        docs_total: 0,
        turns_total: 0,
        canonical_total: 0,
        started_at_ms: now,
        finished_at_ms: now,
        duration_ms: 0,
      });
      this._updateMemorySearchIndexState({
        active_generation_id: generationId,
        active_updated_at_ms: now,
        last_rebuild_id: generationId,
        last_rebuild_status: 'active',
        last_error: null,
      });
      this.db.exec('COMMIT;');
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
    return this.getActiveMemorySearchIndexGeneration();
  }

  clearMemorySearchIndexGenerationDocs({ generation_id } = {}) {
    const generationId = String(generation_id || '').trim();
    if (!generationId) throw new Error('missing generation_id');
    this.db
      .prepare(`DELETE FROM memory_search_index_docs WHERE generation_id = ?`)
      .run(generationId);
  }

  appendMemorySearchIndexGenerationDocs({ generation_id, docs } = {}) {
    const generationId = String(generation_id || '').trim();
    if (!generationId) throw new Error('missing generation_id');
    const rows = Array.isArray(docs) ? docs : [];
    if (!rows.length) return 0;
    const ins = this.db.prepare(
      `INSERT INTO memory_search_index_docs(
         generation_id, doc_id, source_table, source_record_id, scope_json,
         sensitivity, trust_level, title, text_sha256, text_bytes, created_at_ms
       ) VALUES(?,?,?,?,?,?,?,?,?,?,?)`
    );
    let inserted = 0;
    for (const d of rows) {
      const docId = String(d?.doc_id || '').trim();
      const sourceTable = String(d?.source_table || '').trim();
      const sourceRecordId = String(d?.source_record_id || '').trim();
      if (!docId || !sourceTable || !sourceRecordId) continue;
      const scopeJson = this._safeJsonStringify(d?.scope || d?.scope_json || null);
      const sensitivity = String(d?.sensitivity || 'public').trim().toLowerCase() || 'public';
      const trustLevel = String(d?.trust_level || 'trusted').trim().toLowerCase() || 'trusted';
      const title = d?.title != null ? String(d.title) : null;
      const textSha = d?.text_sha256 != null ? String(d.text_sha256 || '').trim() : null;
      const textBytes = Math.max(0, Number(d?.text_bytes || 0));
      const createdAtMs = Math.max(0, Number(d?.created_at_ms || nowMs()));
      ins.run(
        generationId,
        docId,
        sourceTable,
        sourceRecordId,
        scopeJson,
        sensitivity,
        trustLevel,
        title,
        textSha || null,
        textBytes,
        createdAtMs
      );
      inserted += 1;
    }
    return inserted;
  }

  replaceMemorySearchIndexGenerationDocs({ generation_id, docs } = {}) {
    const generationId = String(generation_id || '').trim();
    if (!generationId) throw new Error('missing generation_id');
    const rows = Array.isArray(docs) ? docs : [];
    this.db.exec('BEGIN;');
    try {
      this.clearMemorySearchIndexGenerationDocs({ generation_id: generationId });
      this.appendMemorySearchIndexGenerationDocs({ generation_id: generationId, docs: rows });
      this.db.exec('COMMIT;');
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
    return this.countMemorySearchIndexGenerationDocs({ generation_id: generationId });
  }

  countMemorySearchIndexGenerationDocs({ generation_id } = {}) {
    const generationId = String(generation_id || '').trim();
    if (!generationId) throw new Error('missing generation_id');
    const row = this.db
      .prepare(
        `SELECT COUNT(*) AS n
         FROM memory_search_index_docs
         WHERE generation_id = ?`
      )
      .get(generationId);
    return Math.max(0, Number(row?.n || 0));
  }

  listMemorySearchIndexGenerationDocs({ generation_id, limit, offset } = {}) {
    const generationId = String(generation_id || '').trim();
    if (!generationId) throw new Error('missing generation_id');
    const lim = Math.max(1, Math.min(5000, Number(limit || 100)));
    const off = Math.max(0, Number(offset || 0));
    return this.db
      .prepare(
        `SELECT *
         FROM memory_search_index_docs
         WHERE generation_id = ?
         ORDER BY created_at_ms DESC
         LIMIT ? OFFSET ?`
      )
      .all(generationId, lim, off);
  }

  swapActiveMemorySearchIndexGeneration({
    generation_id,
    swapped_at_ms,
    fail_after_pointer_update,
  } = {}) {
    const generationId = String(generation_id || '').trim();
    if (!generationId) throw new Error('missing generation_id');
    const now = Math.max(0, Number(swapped_at_ms || nowMs()));

    this.db.exec('BEGIN;');
    try {
      const state = this.getMemorySearchIndexState() || {};
      const prevActive = String(state.active_generation_id || '').trim();
      const target = this.getMemorySearchIndexGeneration({ generation_id: generationId });
      if (!target) throw new Error('target_generation_not_found');
      const targetStatus = String(target.status || '').trim().toLowerCase();
      if (!['building', 'ready', 'active'].includes(targetStatus)) {
        throw new Error(`target_generation_not_swappable:${targetStatus || 'unknown'}`);
      }

      if (prevActive && prevActive !== generationId) {
        this.updateMemorySearchIndexGeneration({
          generation_id: prevActive,
          status: 'retired',
          updated_at_ms: now,
        });
      }

      this.updateMemorySearchIndexGeneration({
        generation_id: generationId,
        status: 'active',
        swapped_from_generation_id: prevActive || null,
        updated_at_ms: now,
      });
      this._updateMemorySearchIndexState({
        active_generation_id: generationId,
        active_updated_at_ms: now,
        last_rebuild_id: generationId,
        last_rebuild_status: 'active',
        last_error: null,
      });

      if (fail_after_pointer_update) {
        throw new Error('simulated_swap_failure');
      }

      this.db.exec('COMMIT;');
      return {
        ok: true,
        active_generation_id: generationId,
        previous_active_generation_id: prevActive || null,
        swapped_at_ms: now,
      };
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
  }

  getMemoryIndexConsumerCheckpoint({ consumer_id, create_if_missing } = {}) {
    const consumerId = this._normalizeMemoryIndexConsumerId(consumer_id);
    const create = create_if_missing !== false;
    if (create) {
      const now = nowMs();
      this.db
        .prepare(
          `INSERT OR IGNORE INTO memory_index_consumer_checkpoints(
             consumer_id, checkpoint_seq, last_event_id, status, retry_count, last_error,
             last_processed_at_ms, last_failed_at_ms, created_at_ms, updated_at_ms
           ) VALUES(?,?,?,?,?,?,?,?,?,?)`
        )
        .run(consumerId, 0, null, 'idle', 0, null, null, null, now, now);
    }
    return this.db
      .prepare(
        `SELECT *
         FROM memory_index_consumer_checkpoints
         WHERE consumer_id = ?
         LIMIT 1`
      )
      .get(consumerId) || null;
  }

  upsertMemoryIndexConsumerCheckpoint({
    consumer_id,
    checkpoint_seq,
    last_event_id,
    status,
    retry_count,
    last_error,
    last_processed_at_ms,
    last_failed_at_ms,
    updated_at_ms,
  } = {}) {
    const consumerId = this._normalizeMemoryIndexConsumerId(consumer_id);
    const current = this.getMemoryIndexConsumerCheckpoint({
      consumer_id: consumerId,
      create_if_missing: true,
    }) || {};
    const now = Math.max(0, Number(updated_at_ms || nowMs()));
    const statusRaw = String(status || current.status || 'idle').trim().toLowerCase();
    const statusSafe = ['idle', 'running', 'error'].includes(statusRaw) ? statusRaw : 'idle';

    const hasCheckpoint = Number.isFinite(Number(checkpoint_seq));
    const nextCheckpoint = hasCheckpoint
      ? Math.max(0, Number(checkpoint_seq))
      : Math.max(0, Number(current.checkpoint_seq || 0));

    const hasRetry = Number.isFinite(Number(retry_count));
    const nextRetryCount = hasRetry
      ? Math.max(0, Number(retry_count))
      : Math.max(0, Number(current.retry_count || 0));

    const nextLastEventId = last_event_id != null
      ? (String(last_event_id).trim() || null)
      : (current.last_event_id != null ? String(current.last_event_id) : null);

    const nextLastError = last_error != null
      ? (String(last_error).trim() || null)
      : (current.last_error != null ? String(current.last_error) : null);

    const hasProcessedAt = Number.isFinite(Number(last_processed_at_ms));
    const nextLastProcessedAt = hasProcessedAt
      ? Math.max(0, Number(last_processed_at_ms))
      : (current.last_processed_at_ms != null ? Math.max(0, Number(current.last_processed_at_ms)) : null);

    const hasFailedAt = Number.isFinite(Number(last_failed_at_ms));
    const nextLastFailedAt = hasFailedAt
      ? Math.max(0, Number(last_failed_at_ms))
      : (current.last_failed_at_ms != null ? Math.max(0, Number(current.last_failed_at_ms)) : null);

    const createdAt = Math.max(0, Number(current.created_at_ms || now));

    this.db
      .prepare(
        `INSERT INTO memory_index_consumer_checkpoints(
           consumer_id, checkpoint_seq, last_event_id, status, retry_count, last_error,
           last_processed_at_ms, last_failed_at_ms, created_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(consumer_id) DO UPDATE SET
           checkpoint_seq = excluded.checkpoint_seq,
           last_event_id = excluded.last_event_id,
           status = excluded.status,
           retry_count = excluded.retry_count,
           last_error = excluded.last_error,
           last_processed_at_ms = excluded.last_processed_at_ms,
           last_failed_at_ms = excluded.last_failed_at_ms,
           updated_at_ms = excluded.updated_at_ms`
      )
      .run(
        consumerId,
        nextCheckpoint,
        nextLastEventId,
        statusSafe,
        nextRetryCount,
        nextLastError,
        nextLastProcessedAt,
        nextLastFailedAt,
        createdAt,
        now
      );
    return this.getMemoryIndexConsumerCheckpoint({ consumer_id: consumerId, create_if_missing: false });
  }

  listMemoryIndexConsumerCheckpoints({ limit } = {}) {
    const lim = Math.max(1, Math.min(1000, Number(limit || 100)));
    return this.db
      .prepare(
        `SELECT *
         FROM memory_index_consumer_checkpoints
         ORDER BY updated_at_ms DESC
         LIMIT ?`
      )
      .all(lim);
  }

  hasMemoryIndexConsumerProcessedEvent({ consumer_id, event_id } = {}) {
    const consumerId = this._normalizeMemoryIndexConsumerId(consumer_id);
    const eventId = String(event_id || '').trim();
    if (!eventId) return false;
    const row = this.db
      .prepare(
        `SELECT event_id
         FROM memory_index_consumer_processed_events
         WHERE consumer_id = ? AND event_id = ?
         LIMIT 1`
      )
      .get(consumerId, eventId);
    return !!row;
  }

  recordMemoryIndexConsumerProcessedEvent({
    consumer_id,
    event_id,
    seq,
    event_type,
    table_name,
    source,
    processed_at_ms,
  } = {}) {
    const consumerId = this._normalizeMemoryIndexConsumerId(consumer_id);
    const eventId = String(event_id || '').trim();
    const eventType = String(event_type || '').trim().toLowerCase();
    const tableName = String(table_name || '').trim();
    const sourceSafe = String(source || 'unknown').trim() || 'unknown';
    const s = Math.max(0, Number(seq || 0));
    const ts = Math.max(0, Number(processed_at_ms || nowMs()));
    if (!eventId) throw new Error('missing event_id');
    if (!eventType) throw new Error('missing event_type');
    if (!tableName) throw new Error('missing table_name');

    const res = this.db
      .prepare(
        `INSERT OR IGNORE INTO memory_index_consumer_processed_events(
           consumer_id, event_id, seq, event_type, table_name, source, processed_at_ms
         ) VALUES(?,?,?,?,?,?,?)`
      )
      .run(consumerId, eventId, s, eventType, tableName, sourceSafe, ts);
    return Number(res?.changes || 0) > 0;
  }

  listMemoryIndexConsumerProcessedEvents({ consumer_id, since_seq, limit } = {}) {
    const consumerId = this._normalizeMemoryIndexConsumerId(consumer_id);
    const sinceSeq = Math.max(0, Number(since_seq || 0));
    const lim = Math.max(1, Math.min(5000, Number(limit || 200)));
    return this.db
      .prepare(
        `SELECT *
         FROM memory_index_consumer_processed_events
         WHERE consumer_id = ? AND seq > ?
         ORDER BY seq ASC
         LIMIT ?`
      )
      .all(consumerId, sinceSeq, lim);
  }

  listMemoryDeleteTombstones({ table_name, limit, include_payload } = {}) {
    const t = String(table_name || '').trim();
    const lim = Math.max(1, Math.min(500, Number(limit || 100)));
    const rows = t
      ? this.db
        .prepare(
          `SELECT *
           FROM memory_delete_tombstones
           WHERE table_name = ?
           ORDER BY deleted_at_ms DESC
           LIMIT ?`
        )
        .all(t, lim)
      : this.db
        .prepare(
          `SELECT *
           FROM memory_delete_tombstones
           ORDER BY deleted_at_ms DESC
           LIMIT ?`
        )
        .all(lim);
    if (include_payload) return rows;
    return rows.map((r) => {
      const out = { ...r };
      delete out.payload_json;
      return out;
    });
  }

  restoreMemoryDeleteTombstone({ tombstone_id, keep_tombstone } = {}) {
    const tid = String(tombstone_id || '').trim();
    if (!tid) throw new Error('missing tombstone_id');
    const ts = this.db
      .prepare(`SELECT * FROM memory_delete_tombstones WHERE tombstone_id = ? LIMIT 1`)
      .get(tid);
    if (!ts) return { ok: false, reason: 'not_found', tombstone_id: tid };

    const now = nowMs();
    const expiresAt = Number(ts.expires_at_ms || 0);
    if (expiresAt > 0 && expiresAt <= now) {
      return { ok: false, reason: 'expired', tombstone_id: tid };
    }

    let payload = null;
    try {
      payload = JSON.parse(String(ts.payload_json || '{}'));
    } catch {
      return { ok: false, reason: 'bad_payload_json', tombstone_id: tid };
    }

    const tableName = String(ts.table_name || '');
    if (tableName !== 'turns' && tableName !== 'canonical_memory') {
      return { ok: false, reason: 'unsupported_table', tombstone_id: tid };
    }

    if (tableName === 'turns') {
      const turnId = String(payload?.turn_id || '').trim();
      if (!turnId) return { ok: false, reason: 'invalid_turn_payload', tombstone_id: tid };
      const existing = this.db.prepare(`SELECT turn_id FROM turns WHERE turn_id = ? LIMIT 1`).get(turnId);
      if (existing) return { ok: false, reason: 'already_exists', tombstone_id: tid, table_name: tableName };
      this.db.exec('BEGIN;');
      try {
        this.db
          .prepare(
            `INSERT INTO turns(turn_id, thread_id, request_id, role, content, is_private, created_at_ms)
             VALUES(?,?,?,?,?,?,?)`
          )
          .run(
            turnId,
            String(payload.thread_id || ''),
            payload.request_id != null ? String(payload.request_id) : null,
            String(payload.role || ''),
            String(payload.content || ''),
            Number(payload.is_private || 0) ? 1 : 0,
            Number(payload.created_at_ms || now)
          );
        this._appendMemoryIndexChangelog({
          event_type: 'restore',
          table_name: 'turns',
          record_id: turnId,
          scope: {
            thread_id: String(payload.thread_id || ''),
          },
          source: 'memory_retention_restore',
          created_at_ms: now,
          payload: {
            tombstone_id: tid,
            restored_at_ms: now,
            keep_tombstone: !!keep_tombstone,
            reason: String(ts?.reason || ''),
            request_id: payload.request_id != null ? String(payload.request_id) : null,
            role: String(payload.role || ''),
            is_private: Number(payload.is_private || 0) ? 1 : 0,
            created_at_ms: Number(payload.created_at_ms || 0),
          },
        });
        if (!keep_tombstone) {
          this.db.prepare(`DELETE FROM memory_delete_tombstones WHERE tombstone_id = ?`).run(tid);
        }
        this.db.exec('COMMIT;');
      } catch (e) {
        try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
        throw e;
      }
      this.appendAudit({
        event_type: 'memory.retention.restore',
        severity: 'info',
        created_at_ms: now,
        device_id: 'hub',
        app_id: 'hub.memory.retention',
        ok: true,
        ext_json: JSON.stringify({ table_name: tableName, record_id: turnId, tombstone_id: tid }),
      });
      return { ok: true, tombstone_id: tid, table_name: tableName, record_id: turnId };
    }

    const itemId = String(payload?.item_id || '').trim();
    if (!itemId) return { ok: false, reason: 'invalid_canonical_payload', tombstone_id: tid };
    const existing = this.db.prepare(`SELECT item_id FROM canonical_memory WHERE item_id = ? LIMIT 1`).get(itemId);
    if (existing) return { ok: false, reason: 'already_exists', tombstone_id: tid, table_name: tableName };
    this.db.exec('BEGIN;');
    try {
      this.db
        .prepare(
          `INSERT INTO canonical_memory(item_id, scope, thread_id, device_id, user_id, app_id, project_id, key, value, pinned, updated_at_ms)
           VALUES(?,?,?,?,?,?,?,?,?,?,?)`
        )
        .run(
          itemId,
          String(payload.scope || ''),
          String(payload.thread_id || ''),
          String(payload.device_id || ''),
          String(payload.user_id || ''),
          String(payload.app_id || ''),
          String(payload.project_id || ''),
          String(payload.key || ''),
          String(payload.value || ''),
          Number(payload.pinned || 0) ? 1 : 0,
          Number(payload.updated_at_ms || now)
        );
      this._appendMemoryIndexChangelog({
        event_type: 'restore',
        table_name: 'canonical_memory',
        record_id: itemId,
        scope: {
          scope: String(payload.scope || ''),
          thread_id: String(payload.thread_id || ''),
          device_id: String(payload.device_id || ''),
          user_id: String(payload.user_id || ''),
          app_id: String(payload.app_id || ''),
          project_id: String(payload.project_id || ''),
        },
        source: 'memory_retention_restore',
        created_at_ms: now,
        payload: {
          tombstone_id: tid,
          restored_at_ms: now,
          keep_tombstone: !!keep_tombstone,
          reason: String(ts?.reason || ''),
          key: String(payload.key || ''),
          pinned: Number(payload.pinned || 0) ? 1 : 0,
          updated_at_ms: Number(payload.updated_at_ms || 0),
        },
      });
      if (!keep_tombstone) {
        this.db.prepare(`DELETE FROM memory_delete_tombstones WHERE tombstone_id = ?`).run(tid);
      }
      this.db.exec('COMMIT;');
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
    this.appendAudit({
      event_type: 'memory.retention.restore',
      severity: 'info',
      created_at_ms: now,
      device_id: 'hub',
      app_id: 'hub.memory.retention',
      ok: true,
      ext_json: JSON.stringify({ table_name: tableName, record_id: itemId, tombstone_id: tid }),
    });
    return { ok: true, tombstone_id: tid, table_name: tableName, record_id: itemId };
  }

  _seedDefaultsIfEmpty() {
    const row = this.db.prepare('SELECT COUNT(*) AS n FROM models').get();
    const n = Number(row?.n || 0);
    if (n > 0) return;

    const now = nowMs();
    const ins = this.db.prepare(
      `INSERT INTO models(model_id,name,kind,backend,context_length,requires_grant,enabled,updated_at_ms)
       VALUES(?,?,?,?,?,?,?,?)`
    );

    // A couple of seed models for smoke tests.
    ins.run('mlx/qwen2.5-7b-instruct', 'Qwen2.5 7B (Local)', 'local_offline', 'mlx', 8192, 0, 1, now);
    ins.run('openai/gpt-4.1', 'GPT-4.1', 'paid_online', 'openai', 128000, 1, 1, now);
  }

  // -------------------- Models --------------------

  listModels() {
    const rows = this.db
      .prepare(
        `SELECT model_id,name,kind,backend,context_length,requires_grant,enabled,updated_at_ms
         FROM models WHERE enabled = 1 ORDER BY kind ASC, name ASC`
      )
      .all();
    return rows.map((r) => ({
      model_id: String(r.model_id),
      name: String(r.name),
      kind: String(r.kind),
      backend: String(r.backend),
      context_length: Number(r.context_length || 0),
      requires_grant: Number(r.requires_grant || 0) ? 1 : 0,
      updated_at_ms: Number(r.updated_at_ms || 0),
    }));
  }

  getModel(modelId) {
    const r = this.db
      .prepare(
        `SELECT model_id,name,kind,backend,context_length,requires_grant,enabled,updated_at_ms
         FROM models WHERE model_id = ? LIMIT 1`
      )
      .get(String(modelId || ''));
    if (!r) return null;
    return {
      model_id: String(r.model_id),
      name: String(r.name),
      kind: String(r.kind),
      backend: String(r.backend),
      context_length: Number(r.context_length || 0),
      requires_grant: Number(r.requires_grant || 0) ? 1 : 0,
      enabled: Number(r.enabled || 0) ? 1 : 0,
      updated_at_ms: Number(r.updated_at_ms || 0),
    };
  }

  _getMemoryModelPreferenceRowRaw(profileId) {
    const normalizedId = String(profileId || '').trim();
    if (!normalizedId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_model_preferences
         WHERE profile_id = ?
         LIMIT 1`
      )
      .get(normalizedId) || null;
  }

  _parseMemoryModelPreferenceRow(row) {
    return normalizeMemoryModelPreferenceRow(row);
  }

  getMemoryModelPreference(profileId) {
    return this._parseMemoryModelPreferenceRow(this._getMemoryModelPreferenceRowRaw(profileId));
  }

  getMemoryModelPreferences(profileId) {
    return this.getMemoryModelPreference(profileId);
  }

  listMemoryModelPreferences(filters = {}) {
    const wh = [];
    const args = [];

    const profileId = String(filters?.profile_id || '').trim();
    const userId = String(filters?.user_id || '').trim();
    const scopeKind = normalizeMemoryModelPreferenceScopeKind(filters?.scope_kind, '');
    const scopeRef = String(filters?.scope_ref || '').trim();
    const mode = normalizeMemoryModelMode(filters?.mode, '');
    const selectionStrategy = normalizeMemoryModelPreferenceSelectionStrategy(filters?.selection_strategy, '');
    const includeDisabled = !!filters?.include_disabled;
    const limit = Math.max(1, Math.min(500, Number(filters?.limit || 100)));

    if (profileId) {
      wh.push('profile_id = ?');
      args.push(profileId);
    }
    if (userId) {
      wh.push('user_id = ?');
      args.push(userId);
    }
    if (scopeKind) {
      wh.push('scope_kind = ?');
      args.push(scopeKind);
    }
    if (scopeRef) {
      wh.push('scope_ref = ?');
      args.push(scopeRef);
    }
    if (mode) {
      wh.push('mode = ?');
      args.push(mode);
    }
    if (selectionStrategy) {
      wh.push('selection_strategy = ?');
      args.push(selectionStrategy);
    }
    if (!includeDisabled) wh.push('disabled_at_ms IS NULL');

    const where = wh.length ? `WHERE ${wh.join(' AND ')}` : '';
    return this.db
      .prepare(
        `SELECT *
         FROM memory_model_preferences
         ${where}
         ORDER BY updated_at_ms DESC, profile_id ASC
         LIMIT ${limit}`
      )
      .all(...args)
      .map((row) => this._parseMemoryModelPreferenceRow(row))
      .filter(Boolean);
  }

  upsertMemoryModelPreferences(fields = {}) {
    const validated = validateMemoryModelPreference(fields);
    if (!validated.ok || !validated.value) {
      throw new Error(`invalid memory model preferences: ${validated.errors.join(',')}`);
    }

    const value = validated.value;
    const now = nowMs();
    const updatedAtMs = Math.max(0, Number(value.updated_at_ms || 0)) || now;
    const disabledAtMs = value.disabled_at_ms != null ? Math.max(0, Number(value.disabled_at_ms || 0)) : null;
    const existing = this._getMemoryModelPreferenceRowRaw(value.profile_id);

    if (existing) {
      this.db
        .prepare(
          `UPDATE memory_model_preferences
           SET user_id = ?,
               scope_kind = ?,
               scope_ref = ?,
               mode = ?,
               selection_strategy = ?,
               primary_model_id = ?,
               job_model_map_json = ?,
               mode_model_map_json = ?,
               fallback_policy_json = ?,
               remote_allowed = ?,
               policy_version = ?,
               note = ?,
               updated_at_ms = ?,
               disabled_at_ms = ?
           WHERE profile_id = ?`
        )
        .run(
          value.user_id,
          value.scope_kind,
          value.scope_ref,
          value.mode,
          value.selection_strategy,
          value.primary_model_id || null,
          value.job_model_map_json,
          value.mode_model_map_json,
          value.fallback_policy_json,
          value.remote_allowed ? 1 : 0,
          value.policy_version,
          value.note || null,
          updatedAtMs,
          disabledAtMs,
          value.profile_id
        );
    } else {
      this.db
        .prepare(
          `INSERT INTO memory_model_preferences(
             profile_id, user_id, scope_kind, scope_ref, mode, selection_strategy,
             primary_model_id, job_model_map_json, mode_model_map_json, fallback_policy_json,
             remote_allowed, policy_version, note, updated_at_ms, disabled_at_ms
           ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
        )
        .run(
          value.profile_id,
          value.user_id,
          value.scope_kind,
          value.scope_ref,
          value.mode,
          value.selection_strategy,
          value.primary_model_id || null,
          value.job_model_map_json,
          value.mode_model_map_json,
          value.fallback_policy_json,
          value.remote_allowed ? 1 : 0,
          value.policy_version,
          value.note || null,
          updatedAtMs,
          disabledAtMs
        );
    }

    return this.getMemoryModelPreference(value.profile_id);
  }

  resolveMemoryModelPreferencesWinner(filters = {}) {
    const userId = String(filters?.user_id || '').trim();
    const projectId = String(filters?.project_id || '').trim();
    const mode = normalizeMemoryModelMode(filters?.mode, '');
    const preferredProfileId = String(filters?.preferred_profile_id || '').trim();
    const clauses = [`scope_kind = 'user_default'`];
    const args = [userId];

    if (!userId) {
      return {
        ok: false,
        profile: null,
        deny_code: 'memory_model_profile_missing',
      };
    }

    if (projectId && mode) {
      clauses.unshift(`(scope_kind = 'project_mode' AND scope_ref = ? AND mode = ?)`);
      args.push(projectId, mode);
    }
    if (projectId) {
      clauses.push(`(scope_kind = 'project' AND scope_ref = ?)`);
      args.push(projectId);
    }
    if (mode) {
      clauses.push(`(scope_kind = 'mode' AND mode = ?)`);
      args.push(mode);
    }
    if (preferredProfileId) {
      clauses.push(`profile_id = ?`);
      args.push(preferredProfileId);
    }

    const rows = this.db
      .prepare(
        `SELECT *
         FROM memory_model_preferences
         WHERE user_id = ?
           AND (${clauses.join(' OR ')})
         ORDER BY updated_at_ms DESC, profile_id ASC
         LIMIT 128`
      )
      .all(...args)
      .map((row) => this._parseMemoryModelPreferenceRow(row))
      .filter(Boolean);

    return selectWinningMemoryModelPreference(rows, {
      user_id: userId,
      project_id: projectId,
      mode,
      preferred_profile_id: preferredProfileId,
    });
  }

  // -------------------- Grants --------------------

  getGrantRequest(grantRequestId) {
    const r = this.db
      .prepare(`SELECT * FROM grant_requests WHERE grant_request_id = ? LIMIT 1`)
      .get(String(grantRequestId || ''));
    return r || null;
  }

  listPendingGrantRequests(filters) {
    const deviceId = String(filters?.device_id || '').trim();
    const userId = String(filters?.user_id || '').trim();
    const appId = String(filters?.app_id || '').trim();
    const projectId = String(filters?.project_id || '').trim();
    const capability = String(filters?.capability || '').trim();
    const lim = Math.max(1, Math.min(500, Number(filters?.limit || 200)));

    const wh = [`status = 'pending'`];
    const args = [];
    if (deviceId) {
      wh.push('device_id = ?');
      args.push(deviceId);
    }
    if (userId) {
      wh.push('user_id = ?');
      args.push(userId);
    }
    if (appId) {
      wh.push('app_id = ?');
      args.push(appId);
    }
    if (projectId) {
      wh.push('project_id = ?');
      args.push(projectId);
    }
    if (capability) {
      wh.push('capability = ?');
      args.push(capability);
    }

    const where = wh.length ? `WHERE ${wh.join(' AND ')}` : '';
    const sql = `
      SELECT *
      FROM grant_requests
      ${where}
      ORDER BY created_at_ms ASC
      LIMIT ${lim}
    `;
    return this.db.prepare(sql).all(...args);
  }

  findGrantRequestByIdempotency(deviceId, requestId) {
    const r = this.db
      .prepare(
        `SELECT * FROM grant_requests WHERE device_id = ? AND request_id = ? LIMIT 1`
      )
      .get(String(deviceId || ''), String(requestId || ''));
    return r || null;
  }

  createGrantRequest(req) {
    const now = nowMs();
    const grantRequestId = uuid();

    this.db
      .prepare(
        `INSERT INTO grant_requests(
          grant_request_id, request_id, device_id, user_id, app_id, project_id,
          capability, model_id, reason,
          requested_ttl_sec, requested_token_cap,
          status, decision, deny_reason, approver_id, note, user_ack_understood, explain_rounds, options_presented,
          created_at_ms, decided_at_ms
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        grantRequestId,
        String(req.request_id || ''),
        String(req.device_id || ''),
        req.user_id ? String(req.user_id) : null,
        String(req.app_id || ''),
        req.project_id ? String(req.project_id) : null,
        String(req.capability || ''),
        req.model_id ? String(req.model_id) : null,
        req.reason ? String(req.reason) : null,
        Number(req.requested_ttl_sec || 0),
        Number(req.requested_token_cap || 0),
        'pending',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        now,
        null
      );

    return { grant_request_id: grantRequestId, created_at_ms: now };
  }

  decideGrantRequest(grantRequestId, decision) {
    const now = nowMs();
    const ack = decision?.user_ack_understood == null ? null : (decision.user_ack_understood ? 1 : 0);
    const roundsRaw = decision?.explain_rounds;
    const rounds = roundsRaw == null ? null : Math.max(0, Number(roundsRaw || 0));
    const options = decision?.options_presented == null ? null : (decision.options_presented ? 1 : 0);
    this.db
      .prepare(
        `UPDATE grant_requests
         SET status = ?, decision = ?, deny_reason = ?, approver_id = ?, note = ?, user_ack_understood = ?, explain_rounds = ?, options_presented = ?, decided_at_ms = ?
         WHERE grant_request_id = ?`
      )
      .run(
        String(decision.status || 'pending'),
        decision.decision ? String(decision.decision) : null,
        decision.deny_reason ? String(decision.deny_reason) : null,
        decision.approver_id ? String(decision.approver_id) : null,
        decision.note ? String(decision.note) : null,
        ack,
        rounds,
        options,
        now,
        String(grantRequestId || '')
      );
    return now;
  }

  createGrant(grant) {
    const now = nowMs();
    const grantId = uuid();
    this.db
      .prepare(
        `INSERT INTO grants(
          grant_id, grant_request_id,
          device_id, user_id, app_id, project_id,
          capability, model_id,
          token_cap, token_used,
          expires_at_ms, status,
          created_at_ms, updated_at_ms
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        grantId,
        grant.grant_request_id ? String(grant.grant_request_id) : null,
        String(grant.device_id || ''),
        grant.user_id ? String(grant.user_id) : null,
        String(grant.app_id || ''),
        grant.project_id ? String(grant.project_id) : null,
        String(grant.capability || ''),
        grant.model_id ? String(grant.model_id) : null,
        Number(grant.token_cap || 0),
        0,
        Number(grant.expires_at_ms || 0),
        'active',
        now,
        now
      );
    return this.getGrant(grantId);
  }

  getGrant(grantId) {
    const r = this.db.prepare(`SELECT * FROM grants WHERE grant_id = ? LIMIT 1`).get(String(grantId || ''));
    return r || null;
  }

  findActiveGrant({ device_id, user_id, app_id, capability, model_id }) {
    const now = nowMs();
    const rows = this.db
      .prepare(
        `SELECT * FROM grants
         WHERE device_id = ?
           AND app_id = ?
           AND status = 'active'
           AND expires_at_ms > ?
           AND capability = ?
           AND (model_id IS NULL OR model_id = ?)
           AND (user_id IS NULL OR user_id = ?)
         ORDER BY expires_at_ms DESC
         LIMIT 1`
      )
      .all(
        String(device_id || ''),
        String(app_id || ''),
        now,
        String(capability || ''),
        model_id ? String(model_id) : '',
        String(user_id || '')
      );
    const r = rows[0];
    if (!r) return null;
    if (Number(r.token_cap || 0) > 0 && Number(r.token_used || 0) >= Number(r.token_cap || 0)) {
      return null;
    }
    return r;
  }

  addGrantUsage(grantId, tokens) {
    const now = nowMs();
    const add = Math.max(0, Number(tokens || 0));
    this.db
      .prepare(
        `UPDATE grants
         SET token_used = token_used + ?, updated_at_ms = ?
         WHERE grant_id = ?`
      )
      .run(add, now, String(grantId || ''));
  }

  // -------------------- Quotas (MVP: per-scope daily tokens) --------------------

  getQuotaUsageDaily(scope, day) {
    const s = String(scope || '').trim();
    const d = String(day || '').trim();
    if (!s || !d) return 0;
    try {
      const row = this.db.prepare(`SELECT token_used AS token_used FROM quota_usage_daily WHERE scope = ? AND day = ?`).get(s, d);
      return Math.max(0, Number(row?.token_used || 0));
    } catch {
      return 0;
    }
  }

  addQuotaUsageDaily(scope, day, deltaTokens) {
    const s = String(scope || '').trim();
    const d = String(day || '').trim();
    const n = Math.max(0, Number(deltaTokens || 0));
    if (!s || !d || n <= 0) return { ok: false };
    const now = nowMs();
    try {
      this.db
        .prepare(
          `INSERT INTO quota_usage_daily(scope, day, token_used, updated_at_ms)
           VALUES(?,?,?,?)
           ON CONFLICT(scope, day) DO UPDATE SET
             token_used = token_used + excluded.token_used,
             updated_at_ms = excluded.updated_at_ms`
        )
        .run(s, d, n, now);
      return { ok: true };
    } catch {
      return { ok: false };
    }
  }

  recordTerminalModelUsageDaily(fields) {
    const deviceId = String(fields?.device_id || '').trim();
    const deviceName = String(fields?.device_name || '').trim() || deviceId;
    const modelId = String(fields?.model_id || '').trim();
    const dayBucket = String(fields?.day_bucket || '').trim();
    const promptTokens = Math.max(0, Number(fields?.prompt_tokens || 0));
    const completionTokens = Math.max(0, Number(fields?.completion_tokens || 0));
    const totalTokens = Math.max(0, Number(fields?.total_tokens || 0));
    const lastUsedAtMs = Math.max(0, Number(fields?.last_used_at_ms || nowMs()));
    if (!deviceId || !modelId || !dayBucket) return { ok: false };

    const now = nowMs();
    try {
      this.db
        .prepare(
          `INSERT INTO terminal_model_usage_daily(
             device_id, device_name, model_id, day_bucket,
             prompt_tokens, completion_tokens, total_tokens,
             request_count, blocked_count,
             last_used_at_ms, last_blocked_at_ms, last_blocked_reason, last_deny_code,
             updated_at_ms
           ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(device_id, model_id, day_bucket) DO UPDATE SET
             device_name = excluded.device_name,
             prompt_tokens = terminal_model_usage_daily.prompt_tokens + excluded.prompt_tokens,
             completion_tokens = terminal_model_usage_daily.completion_tokens + excluded.completion_tokens,
             total_tokens = terminal_model_usage_daily.total_tokens + excluded.total_tokens,
             request_count = terminal_model_usage_daily.request_count + 1,
             last_used_at_ms = CASE
               WHEN COALESCE(terminal_model_usage_daily.last_used_at_ms, 0) > excluded.last_used_at_ms THEN terminal_model_usage_daily.last_used_at_ms
               ELSE excluded.last_used_at_ms
             END,
             updated_at_ms = excluded.updated_at_ms`
        )
        .run(
          deviceId,
          deviceName,
          modelId,
          dayBucket,
          promptTokens,
          completionTokens,
          totalTokens,
          1,
          0,
          lastUsedAtMs,
          null,
          null,
          null,
          now
        );
      return { ok: true };
    } catch {
      return { ok: false };
    }
  }

  recordTerminalModelBlockedDaily(fields) {
    const deviceId = String(fields?.device_id || '').trim();
    const deviceName = String(fields?.device_name || '').trim() || deviceId;
    const modelId = String(fields?.model_id || '').trim();
    const dayBucket = String(fields?.day_bucket || '').trim();
    const lastBlockedAtMs = Math.max(0, Number(fields?.last_blocked_at_ms || nowMs()));
    const lastBlockedReason = String(fields?.last_blocked_reason || '').trim();
    const lastDenyCode = String(fields?.last_deny_code || '').trim();
    if (!deviceId || !modelId || !dayBucket) return { ok: false };

    const now = nowMs();
    try {
      this.db
        .prepare(
          `INSERT INTO terminal_model_usage_daily(
             device_id, device_name, model_id, day_bucket,
             prompt_tokens, completion_tokens, total_tokens,
             request_count, blocked_count,
             last_used_at_ms, last_blocked_at_ms, last_blocked_reason, last_deny_code,
             updated_at_ms
           ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(device_id, model_id, day_bucket) DO UPDATE SET
             device_name = excluded.device_name,
             blocked_count = terminal_model_usage_daily.blocked_count + 1,
             last_blocked_at_ms = CASE
               WHEN COALESCE(terminal_model_usage_daily.last_blocked_at_ms, 0) > excluded.last_blocked_at_ms THEN terminal_model_usage_daily.last_blocked_at_ms
               ELSE excluded.last_blocked_at_ms
             END,
             last_blocked_reason = excluded.last_blocked_reason,
             last_deny_code = excluded.last_deny_code,
             updated_at_ms = excluded.updated_at_ms`
        )
        .run(
          deviceId,
          deviceName,
          modelId,
          dayBucket,
          0,
          0,
          0,
          0,
          1,
          null,
          lastBlockedAtMs,
          lastBlockedReason || null,
          lastDenyCode || null,
          now
        );
      return { ok: true };
    } catch {
      return { ok: false };
    }
  }

  listTerminalModelUsageDaily({ device_id, day_bucket, limit } = {}) {
    const deviceId = String(device_id || '').trim();
    const dayBucket = String(day_bucket || '').trim();
    const lim = Math.max(1, Math.min(100, Number(limit || 20)));
    if (!deviceId || !dayBucket) return [];
    try {
      const rows = this.db
        .prepare(
          `SELECT device_id, device_name, model_id, day_bucket,
                  prompt_tokens, completion_tokens, total_tokens,
                  request_count, blocked_count,
                  last_used_at_ms, last_blocked_at_ms, last_blocked_reason, last_deny_code
           FROM terminal_model_usage_daily
           WHERE device_id = ? AND day_bucket = ?
           ORDER BY total_tokens DESC, request_count DESC, model_id ASC
           LIMIT ${lim}`
        )
        .all(deviceId, dayBucket);
      return (rows || []).map((r) => ({
        device_id: String(r.device_id || ''),
        device_name: String(r.device_name || ''),
        model_id: String(r.model_id || ''),
        day_bucket: String(r.day_bucket || ''),
        prompt_tokens: Math.max(0, Number(r.prompt_tokens || 0)),
        completion_tokens: Math.max(0, Number(r.completion_tokens || 0)),
        total_tokens: Math.max(0, Number(r.total_tokens || 0)),
        request_count: Math.max(0, Number(r.request_count || 0)),
        blocked_count: Math.max(0, Number(r.blocked_count || 0)),
        last_used_at_ms: Math.max(0, Number(r.last_used_at_ms || 0)),
        last_blocked_at_ms: Math.max(0, Number(r.last_blocked_at_ms || 0)),
        last_blocked_reason: r.last_blocked_reason != null ? String(r.last_blocked_reason || '') : '',
        last_deny_code: r.last_deny_code != null ? String(r.last_deny_code || '') : '',
      }));
    } catch {
      return [];
    }
  }

  getTerminalUsageSummaryDaily({ device_id, day_bucket } = {}) {
    const deviceId = String(device_id || '').trim();
    const dayBucket = String(day_bucket || '').trim();
    const empty = {
      device_id: deviceId,
      day_bucket: dayBucket,
      total_tokens: 0,
      request_count: 0,
      blocked_count: 0,
      top_model: '',
      last_blocked_reason: '',
      last_deny_code: '',
      last_used_at_ms: 0,
      last_blocked_at_ms: 0,
    };
    if (!deviceId || !dayBucket) return empty;

    try {
      const summary = this.db
        .prepare(
          `SELECT
             COALESCE(SUM(total_tokens), 0) AS total_tokens,
             COALESCE(SUM(request_count), 0) AS request_count,
             COALESCE(SUM(blocked_count), 0) AS blocked_count,
             COALESCE(MAX(last_used_at_ms), 0) AS last_used_at_ms
           FROM terminal_model_usage_daily
           WHERE device_id = ? AND day_bucket = ?`
        )
        .get(deviceId, dayBucket) || {};

      const top = this.db
        .prepare(
          `SELECT model_id
           FROM terminal_model_usage_daily
           WHERE device_id = ? AND day_bucket = ?
           ORDER BY total_tokens DESC, request_count DESC, model_id ASC
           LIMIT 1`
        )
        .get(deviceId, dayBucket) || null;

      const blocked = this.db
        .prepare(
          `SELECT last_blocked_reason, last_deny_code, COALESCE(last_blocked_at_ms, 0) AS last_blocked_at_ms
           FROM terminal_model_usage_daily
           WHERE device_id = ? AND day_bucket = ? AND blocked_count > 0
           ORDER BY COALESCE(last_blocked_at_ms, 0) DESC, model_id ASC
           LIMIT 1`
        )
        .get(deviceId, dayBucket) || null;

      return {
        device_id: deviceId,
        day_bucket: dayBucket,
        total_tokens: Math.max(0, Number(summary.total_tokens || 0)),
        request_count: Math.max(0, Number(summary.request_count || 0)),
        blocked_count: Math.max(0, Number(summary.blocked_count || 0)),
        top_model: String(top?.model_id || ''),
        last_blocked_reason: blocked?.last_blocked_reason != null ? String(blocked.last_blocked_reason || '') : '',
        last_deny_code: blocked?.last_deny_code != null ? String(blocked.last_deny_code || '') : '',
        last_used_at_ms: Math.max(0, Number(summary.last_used_at_ms || 0)),
        last_blocked_at_ms: Math.max(0, Number(blocked?.last_blocked_at_ms || 0)),
      };
    } catch {
      return empty;
    }
  }

  // -------------------- Device Activity (for UI dashboards) --------------------

  /**
   * Latest AI/Web activity for a device (best-effort dashboard helper).
   * Returns a raw row shape from `audit_events` or null.
   */
  getLatestDeviceActivity(deviceId) {
    const did = String(deviceId || '').trim();
    if (!did) return null;
    try {
      const row = this.db
        .prepare(
          `SELECT event_type, created_at_ms, capability, model_id, total_tokens, network_allowed, ok, error_code, error_message, app_id
           FROM audit_events
           WHERE device_id = ?
             AND (
               event_type LIKE 'ai.generate.%'
               OR event_type LIKE 'web.fetch.%'
               OR event_type LIKE 'grant.%'
               OR event_type LIKE 'killswitch.%'
             )
           ORDER BY created_at_ms DESC
           LIMIT 1`
        )
        .get(did);
      return row || null;
    } catch {
      return null;
    }
  }

  /**
   * Token usage time series buckets for a device, derived from audit events.
   * Buckets include ai.generate.completed/failed totals; other events are ignored.
   *
   * @returns {{ bucket_start_ms: number, tokens: number }[]}
   */
  listDeviceTokenBuckets({ device_id, since_ms, bucket_ms }) {
    const did = String(device_id || '').trim();
    const since = Math.max(0, Number(since_ms || 0));
    const bucket = Math.max(1000, Number(bucket_ms || 0));
    if (!did || !since || !bucket) return [];
    try {
      const rows = this.db
        .prepare(
          `SELECT CAST(created_at_ms / ? AS INTEGER) AS bucket,
                  SUM(COALESCE(total_tokens, 0)) AS tokens
           FROM audit_events
           WHERE device_id = ?
             AND created_at_ms >= ?
             AND total_tokens IS NOT NULL
             AND (event_type = 'ai.generate.completed' OR event_type = 'ai.generate.failed')
           GROUP BY bucket
           ORDER BY bucket ASC`
        )
        .all(bucket, did, since);
      return (rows || []).map((r) => ({
        bucket_start_ms: Number(r?.bucket || 0) * bucket,
        tokens: Math.max(0, Number(r?.tokens || 0)),
      }));
    } catch {
      return [];
    }
  }

  revokeGrant(grantId, { revoker_id, reason }) {
    const now = nowMs();
    this.db
      .prepare(
        `UPDATE grants
         SET status = 'revoked', revoked_at_ms = ?, revoker_id = ?, revoke_reason = ?, updated_at_ms = ?
         WHERE grant_id = ?`
      )
      .run(now, revoker_id ? String(revoker_id) : null, reason ? String(reason) : null, now, String(grantId || ''));
    return this.getGrant(grantId);
  }

  // -------------------- Audit --------------------

  _maybeScrubExpiredAuditContentPreview(now) {
    if (!this.auditAllowContentPreview) return;
    if (this.auditLevel !== 'content_redacted') return;
    if (!this.auditContentPreviewTtlMs || this.auditContentPreviewTtlMs <= 0) return;
    if (now < this._nextAuditPreviewScrubAtMs) return;
    this._nextAuditPreviewScrubAtMs = now + this.auditPreviewScrubIntervalMs;

    const cutoff = now - this.auditContentPreviewTtlMs;
    let rows = [];
    try {
      rows = this.db
        .prepare(
          `SELECT event_id, ext_json
           FROM audit_events
           WHERE created_at_ms <= ?
             AND ext_json LIKE '%"content_preview"%'
           ORDER BY created_at_ms ASC
           LIMIT 200`
        )
        .all(cutoff);
    } catch {
      return;
    }
    if (!rows.length) return;

    const update = this.db.prepare(`UPDATE audit_events SET ext_json = ? WHERE event_id = ?`);
    this.db.exec('BEGIN;');
    try {
      for (const row of rows) {
        const eventId = String(row?.event_id || '').trim();
        const extRaw = String(row?.ext_json || '');
        if (!eventId || !extRaw) continue;
        let parsed = null;
        try {
          parsed = JSON.parse(extRaw);
        } catch {
          continue;
        }
        if (!parsed || typeof parsed !== 'object') continue;
        const scrubbed = stripContentPreviewFields(parsed);
        if (scrubbed && typeof scrubbed === 'object') {
          scrubbed._audit_redaction = {
            ...(scrubbed._audit_redaction && typeof scrubbed._audit_redaction === 'object'
              ? scrubbed._audit_redaction
              : {}),
            preview_scrubbed_at_ms: now,
          };
        }
        update.run(JSON.stringify(scrubbed), eventId);
      }
      this.db.exec('COMMIT;');
    } catch {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
    }
  }

  appendAudit(ev) {
    const now = nowMs();
    const eventId = String(ev.event_id || uuid());
    const extJson = sanitizeAuditExtJsonForStorage(ev.ext_json, {
      auditLevel: this.auditLevel,
      allowContentPreview: this.auditAllowContentPreview,
      contentPreviewChars: this.auditContentPreviewChars,
      contentPreviewTtlMs: this.auditContentPreviewTtlMs,
    });
    this.db
      .prepare(
        `INSERT INTO audit_events(
          event_id, event_type, created_at_ms, severity,
          device_id, user_id, app_id, project_id, session_id,
          request_id, capability, model_id,
          prompt_tokens, completion_tokens, total_tokens, cost_usd_estimate,
          network_allowed, ok, error_code, error_message, duration_ms, ext_json
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        eventId,
        String(ev.event_type || ''),
        Number(ev.created_at_ms || now),
        ev.severity ? String(ev.severity) : null,
        String(ev.device_id || ''),
        ev.user_id ? String(ev.user_id) : null,
        String(ev.app_id || ''),
        ev.project_id ? String(ev.project_id) : null,
        ev.session_id ? String(ev.session_id) : null,
        ev.request_id ? String(ev.request_id) : null,
        ev.capability ? String(ev.capability) : null,
        ev.model_id ? String(ev.model_id) : null,
        ev.prompt_tokens != null ? Number(ev.prompt_tokens) : null,
        ev.completion_tokens != null ? Number(ev.completion_tokens) : null,
        ev.total_tokens != null ? Number(ev.total_tokens) : null,
        ev.cost_usd_estimate != null ? Number(ev.cost_usd_estimate) : null,
        ev.network_allowed != null ? (ev.network_allowed ? 1 : 0) : null,
        ev.ok ? 1 : 0,
        ev.error_code ? String(ev.error_code) : null,
        ev.error_message ? String(ev.error_message) : null,
        ev.duration_ms != null ? Number(ev.duration_ms) : null,
        extJson
      );
    this._maybeScrubExpiredAuditContentPreview(now);
    return eventId;
  }

  listAuditEvents(filters) {
    const since = Number(filters?.since_ms || 0);
    const until = Number(filters?.until_ms || 0);
    const deviceId = String(filters?.device_id || '').trim();
    const userId = String(filters?.user_id || '').trim();
    const projectId = String(filters?.project_id || '').trim();
    const requestId = String(filters?.request_id || '').trim();

    const wh = [];
    const args = [];

    if (since > 0) {
      wh.push('created_at_ms >= ?');
      args.push(since);
    }
    if (until > 0) {
      wh.push('created_at_ms <= ?');
      args.push(until);
    }
    if (deviceId) {
      wh.push('device_id = ?');
      args.push(deviceId);
    }
    if (userId) {
      wh.push('user_id = ?');
      args.push(userId);
    }
    if (projectId) {
      wh.push('project_id = ?');
      args.push(projectId);
    }
    if (requestId) {
      wh.push('request_id = ?');
      args.push(requestId);
    }

    const where = wh.length ? `WHERE ${wh.join(' AND ')}` : '';
    const sql = `SELECT * FROM audit_events ${where} ORDER BY created_at_ms DESC LIMIT 200`;
    return this.db.prepare(sql).all(...args);
  }

  // -------------------- Kill Switch --------------------

  getKillSwitch(scope) {
    const s = String(scope || '').trim();
    if (!s) return null;
    const r = this.db.prepare(`SELECT * FROM kill_switches WHERE scope = ? LIMIT 1`).get(s);
    return normalizeKillSwitchRow(r);
  }

  upsertKillSwitch(k) {
    const now = nowMs();
    const scope = String(k?.scope || '').trim();
    if (!scope) throw new Error('missing scope');
    const modelsDisabled = k?.models_disabled ? 1 : 0;
    const networkDisabled = k?.network_disabled ? 1 : 0;
    const disabledLocalCapabilitiesJson = JSON.stringify(normalizeKillSwitchList(k?.disabled_local_capabilities));
    const disabledLocalProvidersJson = JSON.stringify(normalizeKillSwitchList(k?.disabled_local_providers));
    const reason = k?.reason ? String(k.reason) : null;

    this.db
      .prepare(
        `INSERT INTO kill_switches(
           scope,
           models_disabled,
           network_disabled,
           disabled_local_capabilities_json,
           disabled_local_providers_json,
           reason,
           updated_at_ms
         )
         VALUES(?,?,?,?,?,?,?)
         ON CONFLICT(scope) DO UPDATE SET
           models_disabled = excluded.models_disabled,
           network_disabled = excluded.network_disabled,
           disabled_local_capabilities_json = excluded.disabled_local_capabilities_json,
           disabled_local_providers_json = excluded.disabled_local_providers_json,
           reason = excluded.reason,
           updated_at_ms = excluded.updated_at_ms`
      )
      .run(
        scope,
        modelsDisabled,
        networkDisabled,
        disabledLocalCapabilitiesJson,
        disabledLocalProvidersJson,
        reason,
        now
      );

    return this.getKillSwitch(scope);
  }

  getEffectiveKillSwitch({ device_id, user_id, project_id }) {
    const scopes = [];
    scopes.push('global:*');
    const dev = String(device_id || '').trim();
    const usr = String(user_id || '').trim();
    const proj = String(project_id || '').trim();
    if (dev) scopes.push(`device:${dev}`);
    if (usr) scopes.push(`user:${usr}`);
    if (proj) scopes.push(`project:${proj}`);

    const qs = scopes.map(() => '?').join(',');
    const rows = this.db.prepare(`SELECT * FROM kill_switches WHERE scope IN (${qs})`).all(...scopes);

    let models_disabled = false;
    let network_disabled = false;
    let updated_at_ms = 0;
    const reasons = [];
    const matched = [];
    const disabledLocalCapabilities = new Set();
    const disabledLocalProviders = new Set();

    for (const r of rows) {
      const normalized = normalizeKillSwitchRow(r);
      if (!normalized) continue;
      matched.push(String(normalized.scope || ''));
      if (normalized.models_disabled) models_disabled = true;
      if (normalized.network_disabled) network_disabled = true;
      updated_at_ms = Math.max(updated_at_ms, Number(normalized.updated_at_ms || 0));
      for (const capability of normalizeKillSwitchList(normalized.disabled_local_capabilities)) {
        disabledLocalCapabilities.add(capability);
      }
      for (const provider of normalizeKillSwitchList(normalized.disabled_local_providers)) {
        disabledLocalProviders.add(provider);
      }
      const rr = (normalized.reason ? String(normalized.reason) : '').trim();
      if (rr) reasons.push(rr);
    }

    const reason = Array.from(new Set(reasons)).join(' | ');
    return {
      models_disabled,
      network_disabled,
      reason,
      updated_at_ms,
      matched_scopes: matched,
      disabled_local_capabilities: Array.from(disabledLocalCapabilities),
      disabled_local_providers: Array.from(disabledLocalProviders),
    };
  }

  // -------------------- Memory (threads/turns/canonical) --------------------

  getThread(threadId) {
    const r = this.db
      .prepare(`SELECT * FROM threads WHERE thread_id = ? LIMIT 1`)
      .get(String(threadId || ''));
    return r || null;
  }

  findThreadByKey({ device_id, app_id, project_id, thread_key }) {
    const r = this.db
      .prepare(
        `SELECT * FROM threads
         WHERE device_id = ? AND app_id = ? AND project_id = ? AND thread_key = ?
         LIMIT 1`
      )
      .get(
        String(device_id || ''),
        String(app_id || ''),
        String(project_id || ''),
        String(thread_key || '')
      );
    return r || null;
  }

  getOrCreateThread({ device_id, user_id, app_id, project_id, thread_key }) {
    const deviceId = String(device_id || '').trim();
    const appId = String(app_id || '').trim();
    const projectId = String(project_id || '').trim();
    const threadKey = String(thread_key || 'default').trim() || 'default';
    const userId = String(user_id || '').trim();

    if (!deviceId || !appId) throw new Error('missing device_id/app_id');

    const existing = this.findThreadByKey({ device_id: deviceId, app_id: appId, project_id: projectId, thread_key: threadKey });
    if (existing && existing.thread_id) return existing;

    const now = nowMs();
    const threadId = uuid();
    this.db
      .prepare(
        `INSERT INTO threads(thread_id, thread_key, device_id, user_id, app_id, project_id, created_at_ms, updated_at_ms)
         VALUES(?,?,?,?,?,?,?,?)`
      )
      .run(threadId, threadKey, deviceId, userId, appId, projectId, now, now);
    return this.getThread(threadId);
  }

  touchThread(threadId) {
    const now = nowMs();
    this.db
      .prepare(`UPDATE threads SET updated_at_ms = ? WHERE thread_id = ?`)
      .run(now, String(threadId || ''));
    return now;
  }

  appendTurns({ thread_id, request_id, turns }) {
    const threadId = String(thread_id || '').trim();
    if (!threadId) throw new Error('missing thread_id');
    if (!Array.isArray(turns) || turns.length === 0) return 0;
    const thread = this.getThread(threadId);
    const baseScope = {
      thread_id: threadId,
      device_id: String(thread?.device_id || ''),
      user_id: String(thread?.user_id || ''),
      app_id: String(thread?.app_id || ''),
      project_id: String(thread?.project_id || ''),
    };

    const ins = this.db.prepare(
      `INSERT INTO turns(turn_id, thread_id, request_id, role, content, is_private, created_at_ms)
       VALUES(?,?,?,?,?,?,?)`
    );

    let n = 0;
    this.db.exec('BEGIN;');
    try {
      for (const t of turns) {
        const turnId = uuid();
        const role = String(t?.role || '').trim();
        const content = String(t?.content ?? '');
        if (!role || !content) continue;
        const isPrivate = t?.is_private ? 1 : 0;
        const createdAt = Number(t?.created_at_ms || nowMs());
        const storedContent = this._encryptTurnContent({
          turn_id: turnId,
          thread_id: threadId,
          role,
          content,
        });
        ins.run(turnId, threadId, request_id ? String(request_id) : null, role, storedContent, isPrivate, createdAt);
        this._appendMemoryIndexChangelog({
          event_type: 'insert',
          table_name: 'turns',
          record_id: turnId,
          scope: baseScope,
          source: 'append_turns',
          created_at_ms: createdAt,
          payload: {
            role,
            is_private: isPrivate,
            request_id: request_id ? String(request_id) : null,
            created_at_ms: createdAt,
            content_bytes: utf8Bytes(content),
          },
        });
        n += 1;
      }
      this.touchThread(threadId);
      this.db.exec('COMMIT;');
      if (n > 0) this._maybeRunMemoryRetentionJob('append_turns');
      return n;
    } catch (e) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw e;
    }
  }

  hasSupervisorMemoryCandidateCarrierRequest({ device_id, app_id, request_id }) {
    const row = this.db
      .prepare(
        `SELECT request_id
         FROM supervisor_memory_candidate_carrier
         WHERE device_id = ? AND app_id = ? AND request_id = ?
         LIMIT 1`
      )
      .get(
        String(device_id || '').trim(),
        String(app_id || '').trim(),
        String(request_id || '').trim()
      );
    return !!row;
  }

  appendSupervisorMemoryCandidateCarrierTurns({
    thread,
    request_id,
    turns,
    envelope,
    candidates,
  }) {
    const scopeThread = thread && typeof thread === 'object' ? thread : {};
    const threadId = String(scopeThread.thread_id || '').trim();
    const threadKey = String(scopeThread.thread_key || '').trim();
    const deviceId = String(scopeThread.device_id || '').trim();
    const userId = String(scopeThread.user_id || '').trim();
    const appId = String(scopeThread.app_id || '').trim();
    const requestId = String(request_id || '').trim();
    if (!threadId) throw new Error('missing thread_id');
    if (!deviceId || !appId) throw new Error('missing device_id/app_id');
    if (!requestId) throw new Error('missing request_id');
    if (!Array.isArray(turns) || turns.length === 0) throw new Error('missing turns');
    if (!Array.isArray(candidates) || candidates.length === 0) throw new Error('missing candidates');
    if (this.hasSupervisorMemoryCandidateCarrierRequest({
      device_id: deviceId,
      app_id: appId,
      request_id: requestId,
    })) {
      return {
        duplicate: true,
        appended_turns: 0,
        inserted_candidates: 0,
      };
    }

    const carrierEnvelope = envelope && typeof envelope === 'object' ? envelope : {};
    const baseScope = {
      thread_id: threadId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: String(scopeThread.project_id || ''),
    };
    const insertTurn = this.db.prepare(
      `INSERT INTO turns(turn_id, thread_id, request_id, role, content, is_private, created_at_ms)
       VALUES(?,?,?,?,?,?,?)`
    );
    const insertCarrier = this.db.prepare(
      `INSERT INTO supervisor_memory_candidate_carrier(
         carrier_id, request_id, thread_id, thread_key, device_id, user_id, app_id, project_id,
         scope, record_type, confidence, why_promoted, source_ref, audit_ref,
         session_participation_class, write_permission_scope, idempotency_key, payload_summary,
         payload_fields_json, candidate_payload_json, schema_version, carrier_kind, mirror_target,
         local_store_role, summary_line, emitted_at_ms, created_at_ms, updated_at_ms
       ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
    );
    const touchThread = this.db.prepare(`UPDATE threads SET updated_at_ms = ? WHERE thread_id = ?`);
    const storedAt = nowMs();
    let appendedTurns = 0;
    let insertedCandidates = 0;

    this.db.exec('BEGIN;');
    try {
      for (const t of turns) {
        const turnId = uuid();
        const role = String(t?.role || '').trim();
        const content = String(t?.content ?? '');
        if (!role || !content) continue;
        const isPrivate = t?.is_private ? 1 : 0;
        const createdAt = Number(t?.created_at_ms || nowMs());
        const storedContent = this._encryptTurnContent({
          turn_id: turnId,
          thread_id: threadId,
          role,
          content,
        });
        insertTurn.run(turnId, threadId, requestId, role, storedContent, isPrivate, createdAt);
        this._appendMemoryIndexChangelog({
          event_type: 'insert',
          table_name: 'turns',
          record_id: turnId,
          scope: baseScope,
          source: 'append_supervisor_memory_candidate_carrier_turns',
          created_at_ms: createdAt,
          payload: {
            role,
            is_private: isPrivate,
            request_id: requestId,
            created_at_ms: createdAt,
            content_bytes: utf8Bytes(content),
          },
        });
        appendedTurns += 1;
      }

      for (const candidate of candidates) {
        const row = candidate && typeof candidate === 'object' ? candidate : {};
        const carrierId = uuid();
        const candidateProjectId = String(row.project_id || '').trim();
        const candidateCreatedAt = Number(row.created_at_ms || storedAt);
        insertCarrier.run(
          carrierId,
          requestId,
          threadId,
          threadKey,
          deviceId,
          userId,
          appId,
          candidateProjectId,
          String(row.scope || ''),
          String(row.record_type || ''),
          Number(row.confidence || 0),
          String(row.why_promoted || ''),
          String(row.source_ref || ''),
          String(row.audit_ref || ''),
          String(row.session_participation_class || ''),
          String(row.write_permission_scope || ''),
          String(row.idempotency_key || ''),
          String(row.payload_summary || ''),
          JSON.stringify(row.payload_fields || {}),
          JSON.stringify(row.raw_candidate || {}),
          String(carrierEnvelope.schema_version || ''),
          String(carrierEnvelope.carrier_kind || ''),
          String(carrierEnvelope.mirror_target || ''),
          String(carrierEnvelope.local_store_role || ''),
          String(carrierEnvelope.summary_line || ''),
          Number(carrierEnvelope.emitted_at_ms || candidateCreatedAt),
          candidateCreatedAt,
          storedAt
        );
        this._appendMemoryIndexChangelog({
          event_type: 'insert',
          table_name: 'supervisor_memory_candidate_carrier',
          record_id: carrierId,
          scope: {
            thread_id: threadId,
            device_id: deviceId,
            user_id: userId,
            app_id: appId,
            project_id: candidateProjectId,
          },
          source: 'append_supervisor_memory_candidate_carrier_turns',
          created_at_ms: candidateCreatedAt,
          payload: {
            request_id: requestId,
            scope: String(row.scope || ''),
            record_type: String(row.record_type || ''),
            session_participation_class: String(row.session_participation_class || ''),
            write_permission_scope: String(row.write_permission_scope || ''),
            idempotency_key: String(row.idempotency_key || ''),
            emitted_at_ms: Number(carrierEnvelope.emitted_at_ms || candidateCreatedAt),
          },
        });
        insertedCandidates += 1;
      }

      touchThread.run(storedAt, threadId);
      this.db.exec('COMMIT;');
      if (appendedTurns > 0) this._maybeRunMemoryRetentionJob('append_supervisor_memory_candidate_carrier_turns');
      return {
        duplicate: false,
        appended_turns: appendedTurns,
        inserted_candidates: insertedCandidates,
      };
    } catch (e) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw e;
    }
  }

  listSupervisorMemoryCandidateCarrier(filters = {}) {
    const deviceId = String(filters.device_id || '').trim();
    const appId = String(filters.app_id || '').trim();
    const requestId = String(filters.request_id || '').trim();
    const idempotencyKey = String(filters.idempotency_key || '').trim();
    const threadId = String(filters.thread_id || '').trim();
    const projectId = String(filters.project_id || '').trim();
    const limit = Math.max(1, Math.min(2000, Number(filters.limit || 200)));
    const wh = [];
    const args = [];

    if (deviceId) {
      wh.push('device_id = ?');
      args.push(deviceId);
    }
    if (appId) {
      wh.push('app_id = ?');
      args.push(appId);
    }
    if (requestId) {
      wh.push('request_id = ?');
      args.push(requestId);
    }
    if (idempotencyKey) {
      wh.push('idempotency_key = ?');
      args.push(idempotencyKey);
    }
    if (threadId) {
      wh.push('thread_id = ?');
      args.push(threadId);
    }
    if (projectId) {
      wh.push('project_id = ?');
      args.push(projectId);
    }

    const sql = [
      `SELECT * FROM supervisor_memory_candidate_carrier`,
      wh.length > 0 ? `WHERE ${wh.join(' AND ')}` : '',
      `ORDER BY created_at_ms DESC, scope ASC, record_type ASC`,
      `LIMIT ?`,
    ].filter(Boolean).join('\n');
    args.push(limit);

    const rows = this.db.prepare(sql).all(...args);
    return rows.map((row) => ({
      carrier_id: String(row.carrier_id || ''),
      request_id: String(row.request_id || ''),
      thread_id: String(row.thread_id || ''),
      thread_key: String(row.thread_key || ''),
      device_id: String(row.device_id || ''),
      user_id: String(row.user_id || ''),
      app_id: String(row.app_id || ''),
      project_id: String(row.project_id || ''),
      scope: String(row.scope || ''),
      record_type: String(row.record_type || ''),
      confidence: Number(row.confidence || 0),
      why_promoted: String(row.why_promoted || ''),
      source_ref: String(row.source_ref || ''),
      audit_ref: String(row.audit_ref || ''),
      session_participation_class: String(row.session_participation_class || ''),
      write_permission_scope: String(row.write_permission_scope || ''),
      idempotency_key: String(row.idempotency_key || ''),
      payload_summary: String(row.payload_summary || ''),
      payload_fields: parseJsonObject(row.payload_fields_json),
      candidate_payload: parseJsonObject(row.candidate_payload_json),
      schema_version: String(row.schema_version || ''),
      carrier_kind: String(row.carrier_kind || ''),
      mirror_target: String(row.mirror_target || ''),
      local_store_role: String(row.local_store_role || ''),
      summary_line: String(row.summary_line || ''),
      emitted_at_ms: Number(row.emitted_at_ms || 0),
      created_at_ms: Number(row.created_at_ms || 0),
      updated_at_ms: Number(row.updated_at_ms || 0),
    }));
  }

  listSupervisorMemoryCandidateCarrierReviewQueue(filters = {}) {
    const deviceId = String(filters.device_id || '').trim();
    const appId = String(filters.app_id || '').trim();
    const requestId = String(filters.request_id || '').trim();
    const idempotencyKey = String(filters.idempotency_key || '').trim();
    const threadId = String(filters.thread_id || '').trim();
    const projectId = String(filters.project_id || '').trim();
    const limit = Math.max(1, Math.min(500, Number(filters.limit || 200)));

    const seedWhere = [];
    const seedArgs = [];
    if (deviceId) {
      seedWhere.push('device_id = ?');
      seedArgs.push(deviceId);
    }
    if (appId) {
      seedWhere.push('app_id = ?');
      seedArgs.push(appId);
    }
    if (requestId) {
      seedWhere.push('request_id = ?');
      seedArgs.push(requestId);
    }
    if (idempotencyKey) {
      seedWhere.push('idempotency_key = ?');
      seedArgs.push(idempotencyKey);
    }
    if (threadId) {
      seedWhere.push('thread_id = ?');
      seedArgs.push(threadId);
    }
    if (projectId) {
      seedWhere.push('project_id = ?');
      seedArgs.push(projectId);
    }

    const seedSql = [
      `SELECT request_id, device_id, app_id,
              MAX(COALESCE(emitted_at_ms, created_at_ms)) AS latest_emitted_at_ms
       FROM supervisor_memory_candidate_carrier`,
      seedWhere.length > 0 ? `WHERE ${seedWhere.join(' AND ')}` : '',
      `GROUP BY request_id, device_id, app_id`,
      `ORDER BY latest_emitted_at_ms DESC, request_id ASC`,
      `LIMIT ?`,
    ].filter(Boolean).join('\n');
    const seeds = this.db.prepare(seedSql).all(...seedArgs, limit);
    const out = [];

    for (const seed of seeds) {
      const groupRows = this.listSupervisorMemoryCandidateCarrier({
        device_id: String(seed?.device_id || ''),
        app_id: String(seed?.app_id || ''),
        request_id: String(seed?.request_id || ''),
        thread_id: threadId,
        limit: 512,
      });
      if (!Array.isArray(groupRows) || groupRows.length === 0) continue;

      const latestRow = groupRows[0] || {};
      const projectIds = uniqueOrderedStrings(groupRows.map((row) => row.project_id));
      const scopes = uniqueOrderedStrings(groupRows.map((row) => row.scope));
      const recordTypes = uniqueOrderedStrings(groupRows.map((row) => row.record_type));
      const auditRefs = uniqueOrderedStrings(groupRows.map((row) => row.audit_ref));
      const idempotencyKeys = uniqueOrderedStrings(groupRows.map((row) => row.idempotency_key));
      const latestEmittedAtMs = Math.max(
        0,
        ...groupRows.map((row) => Number(row?.emitted_at_ms || row?.created_at_ms || 0))
      );
      const latestCreatedAtMs = Math.max(
        0,
        ...groupRows.map((row) => Number(row?.created_at_ms || 0))
      );
      const earliestCreatedAtMs = groupRows.reduce((min, row) => {
        const ts = Number(row?.created_at_ms || 0);
        if (ts <= 0) return min;
        if (min <= 0) return ts;
        return Math.min(min, ts);
      }, 0);
      const latestUpdatedAtMs = Math.max(
        0,
        ...groupRows.map((row) => Number(row?.updated_at_ms || 0))
      );
      const primaryProjectId = projectId || (projectIds.length === 1 ? projectIds[0] : '');
      const normalizedRequestId = String(seed?.request_id || '').trim();
      const evidenceRef = normalizedRequestId ? `candidate_carrier_request:${normalizedRequestId}` : '';
      const stagedChange = evidenceRef
        ? this.findLatestMemoryMarkdownPendingChangeByProvenanceRef({
            provenance_ref: evidenceRef,
            created_by_device_id: String(seed?.device_id || ''),
            created_by_user_id: String(latestRow.user_id || ''),
            created_by_app_id: String(seed?.app_id || ''),
            created_by_project_id: primaryProjectId,
          })
        : null;
      const stageStatus = String(stagedChange?.status || '').trim().toLowerCase();
      let reviewState = 'pending_review';
      let durablePromotionState = 'not_promoted';
      let promotionBoundary = 'candidate_carrier_only';
      if (stageStatus === 'draft') {
        reviewState = 'draft_staged';
        promotionBoundary = 'longterm_markdown_pending_change';
      } else if (stageStatus === 'reviewed') {
        reviewState = 'reviewed_pending_approval';
        promotionBoundary = 'longterm_markdown_pending_change';
      } else if (stageStatus === 'approved') {
        reviewState = 'approved_for_writeback';
        promotionBoundary = 'longterm_markdown_pending_change';
      } else if (stageStatus === 'written') {
        reviewState = 'writeback_queued';
        durablePromotionState = 'queued_for_writeback';
        promotionBoundary = 'longterm_markdown_writeback_queue';
      } else if (stageStatus === 'rejected') {
        reviewState = 'rejected';
        promotionBoundary = 'longterm_markdown_pending_change';
      } else if (stageStatus === 'rolled_back') {
        reviewState = 'rolled_back';
        durablePromotionState = 'rolled_back';
        promotionBoundary = 'longterm_markdown_writeback_queue';
      }

      out.push({
        schema_version: 'xhub.supervisor_candidate_review_item.v1',
        review_id: `sup_cand_review:${String(seed?.device_id || '')}:${String(seed?.app_id || '')}:${normalizedRequestId}`,
        request_id: normalizedRequestId,
        evidence_ref: evidenceRef,
        review_state: reviewState,
        durable_promotion_state: durablePromotionState,
        promotion_boundary: promotionBoundary,
        device_id: String(seed?.device_id || ''),
        user_id: String(latestRow.user_id || ''),
        app_id: String(seed?.app_id || ''),
        thread_id: String(latestRow.thread_id || ''),
        thread_key: String(latestRow.thread_key || ''),
        project_id: primaryProjectId,
        project_ids: projectIds,
        scopes,
        record_types: recordTypes,
        audit_refs: auditRefs,
        idempotency_keys: idempotencyKeys,
        candidate_count: groupRows.length,
        summary_line: String(latestRow.summary_line || '') || scopes.join(', '),
        mirror_target: String(latestRow.mirror_target || ''),
        local_store_role: String(latestRow.local_store_role || ''),
        carrier_kind: String(latestRow.carrier_kind || ''),
        carrier_schema_version: String(latestRow.schema_version || ''),
        pending_change_id: String(stagedChange?.change_id || ''),
        pending_change_status: stageStatus,
        edit_session_id: String(stagedChange?.edit_session_id || ''),
        doc_id: String(stagedChange?.doc_id || ''),
        writeback_ref: String(stagedChange?.writeback_ref || ''),
        stage_created_at_ms: Math.max(0, Number(stagedChange?.created_at_ms || 0)),
        stage_updated_at_ms: Math.max(0, Number(stagedChange?.updated_at_ms || 0)),
        latest_emitted_at_ms: latestEmittedAtMs,
        created_at_ms: earliestCreatedAtMs,
        updated_at_ms: Math.max(latestUpdatedAtMs, latestCreatedAtMs, latestEmittedAtMs),
      });
    }

    out.sort((left, right) => {
      const lts = Number(left?.latest_emitted_at_ms || 0);
      const rts = Number(right?.latest_emitted_at_ms || 0);
      if (lts !== rts) return rts - lts;
      const lcount = Number(left?.candidate_count || 0);
      const rcount = Number(right?.candidate_count || 0);
      if (lcount !== rcount) return rcount - lcount;
      const lreq = String(left?.request_id || '');
      const rreq = String(right?.request_id || '');
      return lreq.localeCompare(rreq);
    });

    return out.slice(0, limit);
  }

  findLatestMemoryMarkdownPendingChangeByProvenanceRef({
    provenance_ref,
    created_by_device_id,
    created_by_user_id,
    created_by_app_id,
    created_by_project_id,
  } = {}) {
    const provenanceRef = String(provenance_ref || '').trim();
    const deviceId = String(created_by_device_id || '').trim();
    const userId = created_by_user_id != null ? String(created_by_user_id).trim() : '';
    const appId = String(created_by_app_id || '').trim();
    const projectId = created_by_project_id != null ? String(created_by_project_id).trim() : '';
    if (!provenanceRef || !deviceId || !appId) return null;

    const pattern = `%\"${escapeSqlLikePattern(provenanceRef)}\"%`;
    const row = this.db
      .prepare(
        `SELECT *
         FROM memory_markdown_pending_changes
         WHERE created_by_device_id = ?
           AND IFNULL(created_by_user_id, '') = ?
           AND created_by_app_id = ?
           AND IFNULL(created_by_project_id, '') = ?
           AND provenance_refs_json LIKE ? ESCAPE '\\'
         ORDER BY created_at_ms DESC, updated_at_ms DESC
         LIMIT 1`
      )
      .get(deviceId, userId, appId, projectId, pattern) || null;
    return this._parseMemoryMarkdownPendingChangeRow(row);
  }

  listTurns({ thread_id, limit }) {
    const threadId = String(thread_id || '').trim();
    const lim = Math.max(1, Math.min(2000, Number(limit || 50)));
    const rows = this.db
      .prepare(
        `SELECT turn_id, thread_id, role, content, created_at_ms
         FROM turns
         WHERE thread_id = ?
         ORDER BY created_at_ms DESC
         LIMIT ?`
      )
      .all(threadId, lim);
    return rows.map((r) => ({
      role: String(r.role || ''),
      content: this._decryptTurnContentRow(r),
      created_at_ms: Number(r.created_at_ms || 0),
    }));
  }

  _getCanonicalItemRaw({ scope, thread_id, device_id, user_id, app_id, project_id, key }) {
    return this.db
      .prepare(
        `SELECT * FROM canonical_memory
         WHERE scope = ? AND thread_id = ? AND device_id = ? AND user_id = ? AND app_id = ? AND project_id = ? AND key = ?
         LIMIT 1`
      )
      .get(
        String(scope || ''),
        String(thread_id || ''),
        String(device_id || ''),
        String(user_id || ''),
        String(app_id || ''),
        String(project_id || ''),
        String(key || '')
      ) || null;
  }

  getCanonicalItem({ scope, thread_id, device_id, user_id, app_id, project_id, key }) {
    const row = this._getCanonicalItemRaw({ scope, thread_id, device_id, user_id, app_id, project_id, key });
    return this._decryptCanonicalRow(row);
  }

  upsertCanonicalItem({ scope, thread_id, device_id, user_id, app_id, project_id, key, value, pinned }) {
    const now = nowMs();
    const s = String(scope || '').trim();
    const tid = String(thread_id || '').trim();
    const did = String(device_id || '').trim();
    const uid = String(user_id || '').trim();
    const aid = String(app_id || '').trim();
    const pid = String(project_id || '').trim();
    const k = String(key || '').trim();
    const v = String(value ?? '').trim();
    const p = pinned ? 1 : 0;
    if (!s || !did || !aid || !k) throw new Error('missing scope/device_id/app_id/key');

    const existing = this._getCanonicalItemRaw({
      scope: s,
      thread_id: tid,
      device_id: did,
      user_id: uid,
      app_id: aid,
      project_id: pid,
      key: k,
    });
    if (existing && existing.item_id) {
      const storedValue = this._encryptCanonicalValue({
        item_id: String(existing.item_id || ''),
        scope: s,
        thread_id: tid,
        device_id: did,
        user_id: uid,
        app_id: aid,
        project_id: pid,
        key: k,
        value: v,
      });
      this.db
        .prepare(`UPDATE canonical_memory SET value = ?, pinned = ?, updated_at_ms = ? WHERE item_id = ?`)
        .run(storedValue, p, now, String(existing.item_id));
      this._appendMemoryIndexChangelog({
        event_type: 'update',
        table_name: 'canonical_memory',
        record_id: String(existing.item_id || ''),
        scope: {
          scope: s,
          thread_id: tid,
          device_id: did,
          user_id: uid,
          app_id: aid,
          project_id: pid,
        },
        source: 'upsert_canonical',
        created_at_ms: now,
        payload: {
          op: 'update',
          key: k,
          pinned: p,
          updated_at_ms: now,
          value_bytes: utf8Bytes(v),
        },
      });
      const row = this.db.prepare(`SELECT * FROM canonical_memory WHERE item_id = ? LIMIT 1`).get(String(existing.item_id)) || null;
      this._maybeRunMemoryRetentionJob('upsert_canonical_update');
      return this._decryptCanonicalRow(row);
    }

    const itemId = uuid();
    const storedValue = this._encryptCanonicalValue({
      item_id: itemId,
      scope: s,
      thread_id: tid,
      device_id: did,
      user_id: uid,
      app_id: aid,
      project_id: pid,
      key: k,
      value: v,
    });
    this.db
      .prepare(
        `INSERT INTO canonical_memory(item_id, scope, thread_id, device_id, user_id, app_id, project_id, key, value, pinned, updated_at_ms)
         VALUES(?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(itemId, s, tid, did, uid, aid, pid, k, storedValue, p, now);
    this._appendMemoryIndexChangelog({
      event_type: 'insert',
      table_name: 'canonical_memory',
      record_id: itemId,
      scope: {
        scope: s,
        thread_id: tid,
        device_id: did,
        user_id: uid,
        app_id: aid,
        project_id: pid,
      },
      source: 'upsert_canonical',
      created_at_ms: now,
      payload: {
        op: 'insert',
        key: k,
        pinned: p,
        updated_at_ms: now,
        value_bytes: utf8Bytes(v),
      },
    });
    const row = this.db.prepare(`SELECT * FROM canonical_memory WHERE item_id = ? LIMIT 1`).get(itemId) || null;
    this._maybeRunMemoryRetentionJob('upsert_canonical_insert');
    return this._decryptCanonicalRow(row);
  }

  listCanonicalItems(filters) {
    const scope = String(filters?.scope || '').trim();
    const threadId = String(filters?.thread_id || '').trim();
    const deviceId = String(filters?.device_id || '').trim();
    const userId = String(filters?.user_id || '').trim();
    const appId = String(filters?.app_id || '').trim();
    const projectId = String(filters?.project_id || '').trim();
    const lim = Math.max(1, Math.min(500, Number(filters?.limit || 100)));

    const wh = [];
    const args = [];
    if (scope) {
      wh.push('scope = ?');
      args.push(scope);
    }
    if (threadId) {
      wh.push('thread_id = ?');
      args.push(threadId);
    }
    if (deviceId) {
      wh.push('device_id = ?');
      args.push(deviceId);
    }
    if (userId) {
      wh.push('user_id = ?');
      args.push(userId);
    }
    if (appId) {
      wh.push('app_id = ?');
      args.push(appId);
    }
    if (projectId) {
      wh.push('project_id = ?');
      args.push(projectId);
    }

    const where = wh.length ? `WHERE ${wh.join(' AND ')}` : '';
    const sql = `SELECT * FROM canonical_memory ${where} ORDER BY updated_at_ms DESC LIMIT ${lim}`;
    return this.db.prepare(sql).all(...args).map((r) => this._decryptCanonicalRow(r));
  }

  _normalizeAgentRiskTier(value, fallback = 'high') {
    const raw = String(value || '').trim().toLowerCase();
    if (['low', 'medium', 'high', 'critical'].includes(raw)) return raw;
    return String(fallback || 'high').trim().toLowerCase() || 'high';
  }

  _normalizeAgentPolicyDecision(value, fallback = 'pending') {
    const raw = String(value || '').trim().toLowerCase();
    if (['pending', 'approve', 'deny', 'downgrade'].includes(raw)) return raw;
    return String(fallback || 'pending').trim().toLowerCase() || 'pending';
  }

  _normalizeAgentToolCapabilityTokenState(value, fallback = '') {
    const raw = String(value || '').trim().toLowerCase();
    if (['issued', 'consumed', 'revoked', 'expired'].includes(raw)) return raw;
    return String(fallback || '').trim().toLowerCase();
  }

  _agentToolCapabilityTokenRequired(value) {
    const tier = this._normalizeAgentRiskTier(value, 'high');
    return tier === 'high' || tier === 'critical';
  }

  _newAgentToolCapabilityTokenId() {
    return `agt_${uuid()}`;
  }

  _newAgentToolCapabilityTokenNonce() {
    return crypto.randomBytes(16).toString('hex');
  }

  _normalizeAgentCapsuleStatus(value, fallback = 'registered') {
    const raw = String(value || '').trim().toLowerCase();
    if (['registered', 'verified', 'active', 'denied'].includes(raw)) return raw;
    return String(fallback || 'registered').trim().toLowerCase() || 'registered';
  }

  _parseAgentCapsuleAllowedEgress(rawJson) {
    const raw = String(rawJson || '').trim();
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      return parsed.map((item) => String(item || '').trim()).filter(Boolean);
    } catch {
      return [];
    }
  }

  _validateAgentCapsuleEgress(allowed = []) {
    const rows = Array.isArray(allowed) ? allowed : [];
    if (rows.length === 0) return { ok: true, deny_code: '' };
    const endpointPattern = /^https?:\/\/[a-z0-9.-]+(?::\d{1,5})?(?:\/.*)?$/i;
    for (const item of rows) {
      const value = String(item || '').trim();
      if (!value) return { ok: false, deny_code: 'egress_policy_violation' };
      const lower = value.toLowerCase();
      if (
        lower.includes('*')
        || lower.includes('0.0.0.0')
        || lower.includes('::/0')
        || lower.includes('localhost')
      ) {
        return { ok: false, deny_code: 'egress_policy_violation' };
      }
      if (!endpointPattern.test(value)) return { ok: false, deny_code: 'egress_policy_violation' };
    }
    return { ok: true, deny_code: '' };
  }

  _expectedAgentCapsuleSignature({ capsule_id, sha256, sbom_hash } = {}) {
    const capsuleId = String(capsule_id || '').trim();
    const digest = String(sha256 || '').trim();
    const sbomHash = String(sbom_hash || '').trim();
    const signingKey = String(process.env.HUB_AGENT_CAPSULE_SIGNING_KEY || '').trim();
    if (!capsuleId || !digest || !sbomHash || !signingKey) return '';
    return crypto
      .createHmac('sha256', signingKey)
      .update(`${capsuleId}:${digest}:${sbomHash}`, 'utf8')
      .digest('hex');
  }

  _parseAgentCapsuleRow(row) {
    if (!row) return null;
    const allowedEgress = this._parseAgentCapsuleAllowedEgress(row.allowed_egress_json);
    return {
      ...row,
      capsule_id: String(row.capsule_id || ''),
      request_id: String(row.request_id || ''),
      device_id: String(row.device_id || ''),
      user_id: String(row.user_id || ''),
      app_id: String(row.app_id || ''),
      project_id: String(row.project_id || ''),
      agent_name: String(row.agent_name || ''),
      agent_version: String(row.agent_version || ''),
      platform: String(row.platform || ''),
      sha256: String(row.sha256 || ''),
      signature: String(row.signature || ''),
      sbom_hash: String(row.sbom_hash || ''),
      manifest_payload: String(row.manifest_payload || ''),
      sbom_payload: String(row.sbom_payload || ''),
      allowed_egress_json: JSON.stringify(allowedEgress),
      allowed_egress: allowedEgress,
      risk_profile: String(row.risk_profile || ''),
      status: this._normalizeAgentCapsuleStatus(row.status, 'registered'),
      deny_code: String(row.deny_code || ''),
      verification_report_ref: String(row.verification_report_ref || ''),
      verified_at_ms: Math.max(0, Number(row.verified_at_ms || 0)),
      activated_at_ms: Math.max(0, Number(row.activated_at_ms || 0)),
      active_generation: Math.max(0, Number(row.active_generation || 0)),
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _parseAgentCapsuleRuntimeStateRow(row) {
    if (!row) return null;
    return {
      ...row,
      state_id: String(row.state_id || ''),
      active_capsule_id: String(row.active_capsule_id || ''),
      active_generation: Math.max(0, Number(row.active_generation || 0)),
      previous_active_capsule_id: String(row.previous_active_capsule_id || ''),
      previous_active_generation: Math.max(0, Number(row.previous_active_generation || 0)),
      last_activation_request_id: String(row.last_activation_request_id || ''),
      last_error_code: String(row.last_error_code || ''),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _parseAgentSessionRow(row) {
    if (!row) return null;
    return {
      ...row,
      session_id: String(row.session_id || ''),
      request_id: String(row.request_id || ''),
      device_id: String(row.device_id || ''),
      user_id: String(row.user_id || ''),
      app_id: String(row.app_id || ''),
      project_id: String(row.project_id || ''),
      agent_instance_id: String(row.agent_instance_id || ''),
      agent_name: String(row.agent_name || ''),
      agent_version: String(row.agent_version || ''),
      gateway_provider: String(row.gateway_provider || ''),
      status: String(row.status || 'active'),
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _parseAgentToolRequestRow(row) {
    if (!row) return null;
    return {
      ...row,
      tool_request_id: String(row.tool_request_id || ''),
      request_id: String(row.request_id || ''),
      session_id: String(row.session_id || ''),
      device_id: String(row.device_id || ''),
      user_id: String(row.user_id || ''),
      app_id: String(row.app_id || ''),
      project_id: String(row.project_id || ''),
      agent_instance_id: String(row.agent_instance_id || ''),
      gateway_provider: String(row.gateway_provider || ''),
      tool_name: String(row.tool_name || ''),
      tool_args_hash: String(row.tool_args_hash || ''),
      approval_argv_json: String(row.approval_argv_json || ''),
      approval_cwd_input: String(row.approval_cwd_input || ''),
      approval_cwd_canonical: String(row.approval_cwd_canonical || ''),
      approval_identity_hash: String(row.approval_identity_hash || ''),
      required_grant_scope: String(row.required_grant_scope || ''),
      risk_tier: this._normalizeAgentRiskTier(row.risk_tier, 'high'),
      policy_decision: this._normalizeAgentPolicyDecision(row.policy_decision, 'pending'),
      deny_code: String(row.deny_code || ''),
      grant_id: String(row.grant_id || ''),
      grant_expires_at_ms: Math.max(0, Number(row.grant_expires_at_ms || 0)),
      grant_decided_at_ms: Math.max(0, Number(row.grant_decided_at_ms || 0)),
      grant_decided_by: String(row.grant_decided_by || ''),
      grant_note: String(row.grant_note || ''),
      capability_token_kind: String(row.capability_token_kind || ''),
      capability_token_id: String(row.capability_token_id || ''),
      capability_token_nonce: String(row.capability_token_nonce || ''),
      capability_token_state: this._normalizeAgentToolCapabilityTokenState(row.capability_token_state, ''),
      capability_token_issued_at_ms: Math.max(0, Number(row.capability_token_issued_at_ms || 0)),
      capability_token_expires_at_ms: Math.max(0, Number(row.capability_token_expires_at_ms || 0)),
      capability_token_bound_request_id: String(row.capability_token_bound_request_id || ''),
      capability_token_consumed_at_ms: Math.max(0, Number(row.capability_token_consumed_at_ms || 0)),
      capability_token_revoked_at_ms: Math.max(0, Number(row.capability_token_revoked_at_ms || 0)),
      capability_token_revoke_reason: String(row.capability_token_revoke_reason || ''),
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _parseAgentToolExecutionRow(row) {
    if (!row) return null;
    return {
      ...row,
      execution_id: String(row.execution_id || ''),
      request_id: String(row.request_id || ''),
      session_id: String(row.session_id || ''),
      tool_request_id: String(row.tool_request_id || ''),
      device_id: String(row.device_id || ''),
      user_id: String(row.user_id || ''),
      app_id: String(row.app_id || ''),
      project_id: String(row.project_id || ''),
      grant_id: String(row.grant_id || ''),
      gateway_provider: String(row.gateway_provider || ''),
      tool_name: String(row.tool_name || ''),
      tool_args_hash: String(row.tool_args_hash || ''),
      exec_argv_json: String(row.exec_argv_json || ''),
      exec_cwd_input: String(row.exec_cwd_input || ''),
      exec_cwd_canonical: String(row.exec_cwd_canonical || ''),
      approval_identity_hash: String(row.approval_identity_hash || ''),
      status: String(row.status || ''),
      deny_code: String(row.deny_code || ''),
      result_json: row.result_json == null ? '' : String(row.result_json || ''),
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _getAgentCapsuleRowRaw({ capsule_id, device_id, user_id, app_id }) {
    const capsuleId = String(capsule_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!capsuleId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM agent_capsules
         WHERE capsule_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(capsuleId, deviceId, userId, appId) || null;
  }

  _getAnyAgentCapsuleByIdRaw({ capsule_id }) {
    const capsuleId = String(capsule_id || '').trim();
    if (!capsuleId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM agent_capsules
         WHERE capsule_id = ?
         LIMIT 1`
      )
      .get(capsuleId) || null;
  }

  _findAgentCapsuleByIdempotencyRaw({ request_id, device_id, user_id, app_id }) {
    const requestId = String(request_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!requestId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM agent_capsules
         WHERE request_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(requestId, deviceId, userId, appId) || null;
  }

  getAgentCapsule({ capsule_id, device_id, user_id, app_id } = {}) {
    return this._parseAgentCapsuleRow(this._getAgentCapsuleRowRaw({
      capsule_id,
      device_id,
      user_id,
      app_id,
    }));
  }

  getAgentCapsuleRuntimeState({ state_id = 'default' } = {}) {
    const stateId = String(state_id || 'default').trim() || 'default';
    return this._parseAgentCapsuleRuntimeStateRow(
      this.db.prepare(`SELECT * FROM agent_capsule_runtime_state WHERE state_id = ? LIMIT 1`).get(stateId) || null
    );
  }

  registerAgentCapsule(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const capsuleId = String(fields.capsule_id || '').trim();
    const agentName = String(fields.agent_name || '').trim();
    const agentVersion = String(fields.agent_version || '').trim();
    const platform = String(fields.platform || '').trim();
    const sha256 = String(fields.sha256 || '').trim().toLowerCase();
    const signature = String(fields.signature || '').trim().toLowerCase();
    const sbomHash = String(fields.sbom_hash || '').trim().toLowerCase();
    const manifestPayload = String(fields.manifest_payload || '').trim();
    const sbomPayload = String(fields.sbom_payload || '').trim();
    const allowedEgress = Array.isArray(fields.allowed_egress)
      ? fields.allowed_egress.map((item) => String(item || '').trim()).filter(Boolean)
      : [];
    const riskProfile = String(fields.risk_profile || '').trim();

    if (
      !requestId
      || !deviceId
      || !appId
      || !capsuleId
      || !agentName
      || !agentVersion
      || !platform
      || !sha256
      || !signature
      || !sbomHash
      || !manifestPayload
      || !sbomPayload
    ) {
      return {
        registered: false,
        created: false,
        deny_code: 'invalid_request',
        capsule: null,
      };
    }

    const existingByRequest = this._findAgentCapsuleByIdempotencyRaw({
      request_id: requestId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (existingByRequest) {
      const capsule = this._parseAgentCapsuleRow(existingByRequest);
      return {
        registered: capsule?.status !== 'denied',
        created: false,
        deny_code: String(capsule?.deny_code || ''),
        capsule,
      };
    }

    const existingAny = this._parseAgentCapsuleRow(this._getAnyAgentCapsuleByIdRaw({ capsule_id: capsuleId }));
    if (existingAny && (
      existingAny.device_id !== deviceId
      || existingAny.user_id !== userId
      || existingAny.app_id !== appId
    )) {
      return {
        registered: false,
        created: false,
        deny_code: 'permission_denied',
        capsule: null,
      };
    }
    if (existingAny) {
      const stableMatch = (
        String(existingAny.agent_name || '') === agentName
        && String(existingAny.agent_version || '') === agentVersion
        && String(existingAny.platform || '') === platform
        && String(existingAny.sha256 || '') === sha256
        && String(existingAny.signature || '') === signature
        && String(existingAny.sbom_hash || '') === sbomHash
        && String(existingAny.manifest_payload || '') === manifestPayload
        && String(existingAny.sbom_payload || '') === sbomPayload
        && String(existingAny.allowed_egress_json || '') === JSON.stringify(allowedEgress)
        && String(existingAny.risk_profile || '') === riskProfile
      );
      if (!stableMatch) {
        return {
          registered: false,
          created: false,
          deny_code: 'capsule_conflict',
          capsule: existingAny,
        };
      }
      this.db
        .prepare(
          `UPDATE agent_capsules
           SET request_id = ?, project_id = ?, updated_at_ms = ?
           WHERE capsule_id = ?`
        )
        .run(
          requestId,
          projectId || existingAny.project_id || '',
          now,
          capsuleId
        );
      return {
        registered: true,
        created: false,
        deny_code: String(existingAny.deny_code || ''),
        capsule: this.getAgentCapsule({
          capsule_id: capsuleId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        }),
      };
    }

    this.db
      .prepare(
        `INSERT INTO agent_capsules(
           capsule_id, request_id, device_id, user_id, app_id, project_id,
           agent_name, agent_version, platform, sha256, signature, sbom_hash,
           manifest_payload, sbom_payload, allowed_egress_json, risk_profile,
           status, deny_code, verification_report_ref, verified_at_ms, activated_at_ms, active_generation,
           created_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        capsuleId,
        requestId,
        deviceId,
        userId,
        appId,
        projectId,
        agentName,
        agentVersion,
        platform,
        sha256,
        signature,
        sbomHash,
        manifestPayload,
        sbomPayload,
        JSON.stringify(allowedEgress),
        riskProfile || '',
        'registered',
        null,
        null,
        null,
        null,
        0,
        now,
        now
      );

    return {
      registered: true,
      created: true,
      deny_code: '',
      capsule: this.getAgentCapsule({
        capsule_id: capsuleId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      }),
    };
  }

  verifyAgentCapsule(fields = {}) {
    const now = nowMs();
    const capsuleId = String(fields.capsule_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    if (!capsuleId || !deviceId || !appId) {
      return {
        verified: false,
        deny_code: 'invalid_request',
        verification_report_ref: '',
        capsule: null,
      };
    }

    const current = this.getAgentCapsule({
      capsule_id: capsuleId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (!current) {
      return {
        verified: false,
        deny_code: 'capsule_not_found',
        verification_report_ref: '',
        capsule: null,
      };
    }
    if (current.status === 'denied') {
      return {
        verified: false,
        deny_code: 'state_corrupt',
        verification_report_ref: String(current.verification_report_ref || ''),
        capsule: current,
      };
    }

    let denyCode = '';
    const manifestHash = sha256Hex(String(current.manifest_payload || ''));
    if (manifestHash !== String(current.sha256 || '')) {
      denyCode = 'hash_mismatch';
    }
    if (!denyCode) {
      const sbomPayload = String(current.sbom_payload || '');
      if (!sbomPayload) {
        denyCode = 'sbom_invalid';
      } else if (sha256Hex(sbomPayload) !== String(current.sbom_hash || '')) {
        denyCode = 'sbom_invalid';
      }
    }
    if (!denyCode) {
      const expectedSignature = this._expectedAgentCapsuleSignature({
        capsule_id: current.capsule_id,
        sha256: current.sha256,
        sbom_hash: current.sbom_hash,
      });
      if (!expectedSignature || expectedSignature !== String(current.signature || '')) {
        denyCode = 'signature_invalid';
      }
    }
    if (!denyCode) {
      const egressResult = this._validateAgentCapsuleEgress(current.allowed_egress);
      if (!egressResult.ok) denyCode = String(egressResult.deny_code || 'egress_policy_violation');
    }

    const verificationReportRef = `capvr_${uuid()}`;
    if (denyCode) {
      this.db
        .prepare(
          `UPDATE agent_capsules
           SET status = 'denied',
               deny_code = ?,
               verification_report_ref = ?,
               updated_at_ms = ?
           WHERE capsule_id = ?
             AND device_id = ?
             AND user_id = ?
             AND app_id = ?`
        )
        .run(
          denyCode,
          verificationReportRef,
          now,
          capsuleId,
          deviceId,
          userId,
          appId
        );
      return {
        verified: false,
        deny_code: denyCode,
        verification_report_ref: verificationReportRef,
        capsule: this.getAgentCapsule({
          capsule_id: capsuleId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        }),
      };
    }

    const nextStatus = current.status === 'active' ? 'active' : 'verified';
    this.db
      .prepare(
        `UPDATE agent_capsules
         SET status = ?,
             deny_code = NULL,
             verification_report_ref = ?,
             verified_at_ms = ?,
             updated_at_ms = ?
         WHERE capsule_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?`
      )
      .run(
        nextStatus,
        verificationReportRef,
        now,
        now,
        capsuleId,
        deviceId,
        userId,
        appId
      );
    return {
      verified: true,
      deny_code: '',
      verification_report_ref: verificationReportRef,
      capsule: this.getAgentCapsule({
        capsule_id: capsuleId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      }),
    };
  }

  activateAgentCapsule(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const capsuleId = String(fields.capsule_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    if (!requestId || !capsuleId || !deviceId || !appId) {
      return {
        activated: false,
        idempotent: false,
        deny_code: 'invalid_request',
        capsule: null,
        runtime_state: this.getAgentCapsuleRuntimeState({}),
      };
    }

    const capsule = this.getAgentCapsule({
      capsule_id: capsuleId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (!capsule) {
      return {
        activated: false,
        idempotent: false,
        deny_code: 'capsule_not_found',
        capsule: null,
        runtime_state: this.getAgentCapsuleRuntimeState({}),
      };
    }
    if (!(capsule.status === 'verified' || capsule.status === 'active')) {
      return {
        activated: false,
        idempotent: false,
        deny_code: 'state_corrupt',
        capsule,
        runtime_state: this.getAgentCapsuleRuntimeState({}),
      };
    }

    try {
      this.db.exec('BEGIN;');
      let state = this.getAgentCapsuleRuntimeState({});
      if (!state) {
        this.db
          .prepare(
            `INSERT INTO agent_capsule_runtime_state(
               state_id, active_capsule_id, active_generation, previous_active_capsule_id, previous_active_generation,
               last_activation_request_id, last_error_code, updated_at_ms
             ) VALUES(?,?,?,?,?,?,?,?)`
          )
          .run('default', null, 0, null, 0, null, null, now);
        state = this.getAgentCapsuleRuntimeState({});
      }
      state = state || {
        state_id: 'default',
        active_capsule_id: '',
        active_generation: 0,
        previous_active_capsule_id: '',
        previous_active_generation: 0,
      };

      if (
        String(state.active_capsule_id || '') === capsuleId
        && requestId
        && String(state.last_activation_request_id || '') === requestId
      ) {
        this.db.exec('COMMIT;');
        return {
          activated: true,
          idempotent: true,
          deny_code: '',
          capsule: this.getAgentCapsule({
            capsule_id: capsuleId,
            device_id: deviceId,
            user_id: userId,
            app_id: appId,
          }),
          runtime_state: this.getAgentCapsuleRuntimeState({}),
        };
      }

      const previousActiveCapsuleId = String(state.active_capsule_id || '');
      const previousActiveGeneration = Math.max(0, Number(state.active_generation || 0));
      const nextGeneration = Math.max(
        previousActiveGeneration,
        Math.max(0, Number(capsule.active_generation || 0))
      ) + 1;

      if (previousActiveCapsuleId && previousActiveCapsuleId !== capsuleId) {
        this.db
          .prepare(
            `UPDATE agent_capsules
             SET status = CASE WHEN status = 'active' THEN 'verified' ELSE status END,
                 updated_at_ms = ?
             WHERE capsule_id = ?`
          )
          .run(now, previousActiveCapsuleId);
      }

      this.db
        .prepare(
          `UPDATE agent_capsules
           SET status = 'active',
               deny_code = NULL,
               activated_at_ms = ?,
               active_generation = ?,
               updated_at_ms = ?
           WHERE capsule_id = ?
             AND device_id = ?
             AND user_id = ?
             AND app_id = ?`
        )
        .run(
          now,
          nextGeneration,
          now,
          capsuleId,
          deviceId,
          userId,
          appId
        );

      this.db
        .prepare(
          `UPDATE agent_capsule_runtime_state
           SET active_capsule_id = ?,
               active_generation = ?,
               previous_active_capsule_id = ?,
               previous_active_generation = ?,
               last_activation_request_id = ?,
               last_error_code = NULL,
               updated_at_ms = ?
           WHERE state_id = ?`
        )
        .run(
          capsuleId,
          nextGeneration,
          previousActiveCapsuleId || null,
          previousActiveGeneration,
          requestId,
          now,
          'default'
        );

      this.db.exec('COMMIT;');
      return {
        activated: true,
        idempotent: false,
        deny_code: '',
        capsule: this.getAgentCapsule({
          capsule_id: capsuleId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        }),
        runtime_state: this.getAgentCapsuleRuntimeState({}),
      };
    } catch {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      return {
        activated: false,
        idempotent: false,
        deny_code: 'runtime_error',
        capsule: this.getAgentCapsule({
          capsule_id: capsuleId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        }),
        runtime_state: this.getAgentCapsuleRuntimeState({}),
      };
    }
  }

  _getAgentSessionRowRaw({ session_id, device_id, user_id, app_id }) {
    const sessionId = String(session_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!sessionId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM agent_sessions
         WHERE session_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(sessionId, deviceId, userId, appId) || null;
  }

  _findAgentSessionByIdempotencyRaw({ request_id, device_id, user_id, app_id }) {
    const requestId = String(request_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!requestId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM agent_sessions
         WHERE request_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(requestId, deviceId, userId, appId) || null;
  }

  getAgentSession({ session_id, device_id, user_id, app_id } = {}) {
    return this._parseAgentSessionRow(this._getAgentSessionRowRaw({
      session_id,
      device_id,
      user_id,
      app_id,
    }));
  }

  openAgentSession(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const agentInstanceId = String(fields.agent_instance_id || '').trim();
    const agentName = String(fields.agent_name || '').trim();
    const agentVersion = String(fields.agent_version || '').trim();
    const gatewayProvider = String(fields.gateway_provider || '').trim();

    if (!requestId || !deviceId || !appId || !agentInstanceId) {
      return {
        opened: false,
        created: false,
        deny_code: 'invalid_request',
        session: null,
      };
    }

    const existing = this._findAgentSessionByIdempotencyRaw({
      request_id: requestId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (existing) {
      return {
        opened: true,
        created: false,
        deny_code: '',
        session: this._parseAgentSessionRow(existing),
      };
    }

    const sessionId = String(fields.session_id || '').trim() || `ags_${uuid()}`;
    this.db
      .prepare(
        `INSERT INTO agent_sessions(
           session_id, request_id, device_id, user_id, app_id, project_id,
           agent_instance_id, agent_name, agent_version, gateway_provider,
           status, created_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        sessionId,
        requestId,
        deviceId,
        userId,
        appId,
        projectId,
        agentInstanceId,
        agentName || null,
        agentVersion || null,
        gatewayProvider || null,
        'active',
        now,
        now
      );

    return {
      opened: true,
      created: true,
      deny_code: '',
      session: this.getAgentSession({
        session_id: sessionId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      }),
    };
  }

  _getAgentToolRequestRowRaw({ tool_request_id, session_id, device_id, user_id, app_id }) {
    const toolRequestId = String(tool_request_id || '').trim();
    const sessionId = String(session_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!toolRequestId || !sessionId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM agent_tool_requests
         WHERE tool_request_id = ?
           AND session_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(toolRequestId, sessionId, deviceId, userId, appId) || null;
  }

  _findAgentToolRequestByIdempotencyRaw({ request_id, session_id, device_id, user_id, app_id }) {
    const requestId = String(request_id || '').trim();
    const sessionId = String(session_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!requestId || !sessionId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM agent_tool_requests
         WHERE request_id = ?
           AND session_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(requestId, sessionId, deviceId, userId, appId) || null;
  }

  getAgentToolRequest({ tool_request_id, session_id, device_id, user_id, app_id } = {}) {
    return this._parseAgentToolRequestRow(this._getAgentToolRequestRowRaw({
      tool_request_id,
      session_id,
      device_id,
      user_id,
      app_id,
    }));
  }

  consumeAgentToolCapabilityToken(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const sessionId = String(fields.session_id || '').trim();
    const toolRequestId = String(fields.tool_request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const requestedGrantId = String(fields.grant_id || '').trim();

    if (!requestId || !sessionId || !toolRequestId || !deviceId || !appId) {
      return {
        consumed: false,
        idempotent: false,
        deny_code: 'invalid_request',
        tool_request: null,
      };
    }

    const existing = this.getAgentToolRequest({
      tool_request_id: toolRequestId,
      session_id: sessionId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (!existing) {
      return {
        consumed: false,
        idempotent: false,
        deny_code: 'tool_request_not_found',
        tool_request: null,
      };
    }

    const tokenId = String(existing.capability_token_id || '').trim();
    const tokenState = this._normalizeAgentToolCapabilityTokenState(existing.capability_token_state, tokenId ? 'issued' : '');
    const tokenExpiryCandidates = [existing.capability_token_expires_at_ms, existing.grant_expires_at_ms]
      .map((value) => Math.max(0, Number(value || 0)))
      .filter((value) => value > 0);
    const tokenExpiresAtMs = tokenExpiryCandidates.length > 0 ? Math.min(...tokenExpiryCandidates) : 0;
    if (!requestedGrantId || !tokenId) {
      return {
        consumed: false,
        idempotent: false,
        deny_code: 'grant_missing',
        tool_request: existing,
      };
    }
    if (requestedGrantId !== tokenId) {
      return {
        consumed: false,
        idempotent: false,
        deny_code: 'request_tampered',
        tool_request: existing,
      };
    }
    if (tokenState === 'revoked' || existing.policy_decision === 'deny' || existing.policy_decision === 'downgrade') {
      return {
        consumed: false,
        idempotent: false,
        deny_code: String(existing.deny_code || (existing.policy_decision === 'downgrade' ? 'downgrade_to_local' : 'policy_denied')),
        tool_request: existing,
      };
    }
    if (tokenState === 'expired' || tokenExpiresAtMs <= now) {
      if (tokenState !== 'expired') {
        this.db
          .prepare(
            `UPDATE agent_tool_requests
             SET capability_token_state = 'expired',
                 grant_id = NULL,
                 grant_expires_at_ms = NULL,
                 updated_at_ms = ?
             WHERE tool_request_id = ?
               AND session_id = ?
               AND device_id = ?
               AND user_id = ?
               AND app_id = ?`
          )
          .run(now, toolRequestId, sessionId, deviceId, userId, appId);
      }
      return {
        consumed: false,
        idempotent: false,
        deny_code: 'token_expired',
        tool_request: this.getAgentToolRequest({
          tool_request_id: toolRequestId,
          session_id: sessionId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        }),
      };
    }
    if (tokenState === 'consumed') {
      return {
        consumed: false,
        idempotent: String(existing.capability_token_bound_request_id || '') === requestId,
        deny_code: String(existing.capability_token_bound_request_id || '') === requestId ? '' : 'token_consumed',
        tool_request: existing,
      };
    }
    if (tokenState && tokenState !== 'issued') {
      return {
        consumed: false,
        idempotent: false,
        deny_code: 'grant_missing',
        tool_request: existing,
      };
    }

    const out = this.db
      .prepare(
        `UPDATE agent_tool_requests
         SET capability_token_state = 'consumed',
             capability_token_bound_request_id = ?,
             capability_token_consumed_at_ms = ?,
             grant_id = NULL,
             grant_expires_at_ms = NULL,
             updated_at_ms = ?
         WHERE tool_request_id = ?
           AND session_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
           AND capability_token_id = ?
           AND capability_token_state = 'issued'
           AND capability_token_expires_at_ms > ?`
      )
      .run(requestId, now, now, toolRequestId, sessionId, deviceId, userId, appId, tokenId, now);
    const refreshed = this.getAgentToolRequest({
      tool_request_id: toolRequestId,
      session_id: sessionId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (Number(out?.changes || 0) > 0) {
      return {
        consumed: true,
        idempotent: false,
        deny_code: '',
        tool_request: refreshed,
      };
    }

    const latest = refreshed || existing;
    const latestState = this._normalizeAgentToolCapabilityTokenState(latest.capability_token_state, '');
    if (latestState === 'revoked') {
      return {
        consumed: false,
        idempotent: false,
        deny_code: String(latest.deny_code || 'policy_denied'),
        tool_request: latest,
      };
    }
    if (latestState === 'expired' || Math.max(0, Number(latest.capability_token_expires_at_ms || 0)) <= now) {
      return {
        consumed: false,
        idempotent: false,
        deny_code: 'token_expired',
        tool_request: latest,
      };
    }
    if (latestState === 'consumed') {
      return {
        consumed: false,
        idempotent: String(latest.capability_token_bound_request_id || '') === requestId,
        deny_code: String(latest.capability_token_bound_request_id || '') === requestId ? '' : 'token_consumed',
        tool_request: latest,
      };
    }
    return {
      consumed: false,
      idempotent: false,
      deny_code: 'runtime_error',
      tool_request: latest,
    };
  }

  createAgentToolRequest(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const sessionId = String(fields.session_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const agentInstanceId = String(fields.agent_instance_id || '').trim();
    const gatewayProvider = String(fields.gateway_provider || '').trim();
    const toolName = String(fields.tool_name || '').trim();
    const toolArgsHash = String(fields.tool_args_hash || '').trim();
    const approvalArgvJson = String(fields.approval_argv_json || '').trim();
    const approvalCwdInput = String(fields.approval_cwd_input || '').trim();
    const approvalCwdCanonical = String(fields.approval_cwd_canonical || '').trim();
    const approvalIdentityHash = String(fields.approval_identity_hash || '').trim();
    const requiredGrantScope = String(fields.required_grant_scope || '').trim();
    const riskTier = this._normalizeAgentRiskTier(fields.risk_tier, 'high');
    const policyDecision = this._normalizeAgentPolicyDecision(fields.policy_decision, 'pending');

    if (
      !requestId
      || !sessionId
      || !deviceId
      || !appId
      || !toolName
      || !toolArgsHash
      || !agentInstanceId
      || !approvalArgvJson
      || !approvalCwdInput
      || !approvalCwdCanonical
      || !approvalIdentityHash
    ) {
      return {
        accepted: false,
        created: false,
        deny_code: 'invalid_request',
        tool_request: null,
      };
    }

    const session = this._parseAgentSessionRow(this._getAgentSessionRowRaw({
      session_id: sessionId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    }));
    if (!session) {
      return {
        accepted: false,
        created: false,
        deny_code: 'session_not_found',
        tool_request: null,
      };
    }

    const existing = this._findAgentToolRequestByIdempotencyRaw({
      request_id: requestId,
      session_id: sessionId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (existing) {
      let parsedExisting = this._parseAgentToolRequestRow(existing);
      const existingGatewayProvider = String(parsedExisting.gateway_provider || '').trim();
      const existingRequiredGrantScope = String(parsedExisting.required_grant_scope || '').trim();
      const existingRiskTierRaw = String(existing.risk_tier || '').trim().toLowerCase();
      const providerMismatch = (
        !!existingGatewayProvider
        && existingGatewayProvider !== gatewayProvider
      );
      const requiredGrantScopeMismatch = (
        !!existingRequiredGrantScope
        && (!requiredGrantScope || existingRequiredGrantScope !== requiredGrantScope)
      );
      const riskTierMismatch = (
        !!existingRiskTierRaw
        && this._normalizeAgentRiskTier(existingRiskTierRaw, 'high') !== riskTier
      );
      const isTamperedReplay = (
        String(parsedExisting.tool_name || '') !== toolName
        || String(parsedExisting.tool_args_hash || '') !== toolArgsHash
        || requiredGrantScopeMismatch
        || riskTierMismatch
        || providerMismatch
        || String(parsedExisting.approval_argv_json || '') !== approvalArgvJson
        || String(parsedExisting.approval_cwd_canonical || '') !== approvalCwdCanonical
        || String(parsedExisting.approval_identity_hash || '') !== approvalIdentityHash
      );
      if (!isTamperedReplay && (
        (!existingGatewayProvider && gatewayProvider)
        || (!existingRequiredGrantScope && requiredGrantScope)
        || (!existingRiskTierRaw && riskTier)
      )) {
        this.db
          .prepare(
            `UPDATE agent_tool_requests
             SET gateway_provider = ?,
                 required_grant_scope = ?,
                 risk_tier = ?,
                 updated_at_ms = ?
             WHERE tool_request_id = ?
               AND session_id = ?
               AND device_id = ?
               AND user_id = ?
               AND app_id = ?`
          )
          .run(
            gatewayProvider || existingGatewayProvider || null,
            requiredGrantScope || existingRequiredGrantScope || '',
            riskTier,
            now,
            String(parsedExisting.tool_request_id || ''),
            sessionId,
            deviceId,
            userId,
            appId
          );
        parsedExisting = this._parseAgentToolRequestRow(this._getAgentToolRequestRowRaw({
          tool_request_id: String(parsedExisting.tool_request_id || ''),
          session_id: sessionId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        }));
      }
      return {
        accepted: !isTamperedReplay && parsedExisting.policy_decision !== 'deny' && parsedExisting.policy_decision !== 'downgrade',
        created: false,
        deny_code: isTamperedReplay ? 'request_tampered' : String(parsedExisting.deny_code || ''),
        tool_request: parsedExisting,
      };
    }

    let denyCode = String(fields.deny_code || '').trim();
    let grantId = '';
    let grantExpiresAtMs = null;
    let grantDecidedAtMs = null;
    let grantDecidedBy = '';
    let grantNote = '';
    let capabilityTokenId = '';
    let capabilityTokenNonce = '';
    let capabilityTokenExpiresAtMs = null;
    if (policyDecision === 'approve') {
      const ttlMs = Math.max(1000, Math.min(24 * 60 * 60 * 1000, Number(fields.grant_ttl_ms || (10 * 60 * 1000))));
      grantId = String(fields.grant_id || '').trim() || this._newAgentToolCapabilityTokenId();
      grantExpiresAtMs = now + ttlMs;
      grantDecidedAtMs = now;
      grantDecidedBy = String(fields.grant_decided_by || 'policy_engine').trim();
      grantNote = String(fields.grant_note || '').trim();
      if (this._agentToolCapabilityTokenRequired(riskTier)) {
        capabilityTokenId = grantId;
        capabilityTokenNonce = this._newAgentToolCapabilityTokenNonce();
        capabilityTokenExpiresAtMs = grantExpiresAtMs;
      }
      denyCode = '';
    } else if (!denyCode && policyDecision === 'deny') {
      denyCode = 'policy_denied';
    } else if (!denyCode && policyDecision === 'downgrade') {
      denyCode = 'downgrade_to_local';
    }

    const toolRequestId = `atr_${uuid()}`;
    this.db
      .prepare(
        `INSERT INTO agent_tool_requests(
           tool_request_id, request_id, session_id, device_id, user_id, app_id, project_id,
           agent_instance_id, gateway_provider, tool_name, tool_args_hash, approval_argv_json, approval_cwd_input, approval_cwd_canonical, approval_identity_hash,
           required_grant_scope, risk_tier,
           policy_decision, deny_code, grant_id, grant_expires_at_ms, grant_decided_at_ms,
           grant_decided_by, grant_note, created_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        toolRequestId,
        requestId,
        sessionId,
        deviceId,
        userId,
        appId,
        projectId || session.project_id || '',
        agentInstanceId,
        gatewayProvider || null,
        toolName,
        toolArgsHash,
        approvalArgvJson,
        approvalCwdInput,
        approvalCwdCanonical,
        approvalIdentityHash,
        requiredGrantScope,
        riskTier,
        policyDecision,
        denyCode || null,
        grantId || null,
        grantExpiresAtMs,
        grantDecidedAtMs,
        grantDecidedBy || null,
        grantNote || null,
        now,
        now
      );

    if (capabilityTokenId) {
      this.db
        .prepare(
          `UPDATE agent_tool_requests
           SET capability_token_kind = 'one_time',
               capability_token_id = ?,
               capability_token_nonce = ?,
               capability_token_state = 'issued',
               capability_token_issued_at_ms = ?,
               capability_token_expires_at_ms = ?,
               capability_token_bound_request_id = NULL,
               capability_token_consumed_at_ms = NULL,
               capability_token_revoked_at_ms = NULL,
               capability_token_revoke_reason = NULL,
               updated_at_ms = ?
           WHERE tool_request_id = ?
             AND session_id = ?
             AND device_id = ?
             AND user_id = ?
             AND app_id = ?`
        )
        .run(
          capabilityTokenId,
          capabilityTokenNonce,
          now,
          capabilityTokenExpiresAtMs,
          now,
          toolRequestId,
          sessionId,
          deviceId,
          userId,
          appId
        );
    }

    const row = this._parseAgentToolRequestRow(this._getAgentToolRequestRowRaw({
      tool_request_id: toolRequestId,
      session_id: sessionId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    }));
    return {
      accepted: row ? (row.policy_decision !== 'deny' && row.policy_decision !== 'downgrade') : false,
      created: true,
      deny_code: String(row?.deny_code || ''),
      tool_request: row,
    };
  }

  decideAgentToolGrant(fields = {}) {
    const now = nowMs();
    const sessionId = String(fields.session_id || '').trim();
    const toolRequestId = String(fields.tool_request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const decision = this._normalizeAgentPolicyDecision(fields.decision, '');
    const approverId = String(fields.approver_id || '').trim();
    const note = String(fields.note || '').trim();

    if (!sessionId || !toolRequestId || !deviceId || !appId) {
      return {
        applied: false,
        idempotent: false,
        deny_code: 'invalid_request',
        tool_request: null,
      };
    }
    if (!['approve', 'deny', 'downgrade'].includes(decision)) {
      return {
        applied: false,
        idempotent: false,
        deny_code: 'invalid_request',
        tool_request: null,
      };
    }

    const existing = this._parseAgentToolRequestRow(this._getAgentToolRequestRowRaw({
      tool_request_id: toolRequestId,
      session_id: sessionId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    }));
    if (!existing) {
      return {
        applied: false,
        idempotent: false,
        deny_code: 'tool_request_not_found',
        tool_request: null,
      };
    }

    if (decision === 'approve') {
      if (
        !String(existing.approval_argv_json || '')
        || !String(existing.approval_cwd_canonical || '')
        || !String(existing.approval_identity_hash || '')
      ) {
        return {
          applied: false,
          idempotent: false,
          deny_code: 'approval_binding_missing',
          tool_request: existing,
        };
      }
      if (
        existing.policy_decision === 'approve'
        && existing.grant_id
        && Number(existing.grant_expires_at_ms || 0) > now
      ) {
        return {
          applied: true,
          idempotent: true,
          deny_code: '',
          tool_request: existing,
        };
      }

      const ttlMs = Math.max(1000, Math.min(24 * 60 * 60 * 1000, Number(fields.ttl_ms || (10 * 60 * 1000))));
      const grantId = String(existing.grant_id || '').trim() || this._newAgentToolCapabilityTokenId();
      const grantExpiresAtMs = now + ttlMs;
      const capabilityTokenEnabled = this._agentToolCapabilityTokenRequired(existing.risk_tier);
      const capabilityTokenNonce = capabilityTokenEnabled ? this._newAgentToolCapabilityTokenNonce() : '';
      this.db
        .prepare(
          `UPDATE agent_tool_requests
           SET policy_decision = 'approve',
               deny_code = NULL,
               grant_id = ?,
               grant_expires_at_ms = ?,
               grant_decided_at_ms = ?,
               grant_decided_by = ?,
               grant_note = ?,
               updated_at_ms = ?
           WHERE tool_request_id = ?
             AND session_id = ?
             AND device_id = ?
             AND user_id = ?
             AND app_id = ?`
        )
        .run(
          grantId,
          grantExpiresAtMs,
          now,
          approverId || null,
          note || null,
          now,
          toolRequestId,
          sessionId,
          deviceId,
          userId,
          appId
        );
      if (capabilityTokenEnabled) {
        this.db
          .prepare(
            `UPDATE agent_tool_requests
             SET capability_token_kind = 'one_time',
                 capability_token_id = ?,
                 capability_token_nonce = ?,
                 capability_token_state = 'issued',
                 capability_token_issued_at_ms = ?,
                 capability_token_expires_at_ms = ?,
                 capability_token_bound_request_id = NULL,
                 capability_token_consumed_at_ms = NULL,
                 capability_token_revoked_at_ms = NULL,
                 capability_token_revoke_reason = NULL,
                 updated_at_ms = ?
             WHERE tool_request_id = ?
               AND session_id = ?
               AND device_id = ?
               AND user_id = ?
               AND app_id = ?`
          )
          .run(
            grantId,
            capabilityTokenNonce,
            now,
            grantExpiresAtMs,
            now,
            toolRequestId,
            sessionId,
            deviceId,
            userId,
            appId
          );
      }
      return {
        applied: true,
        idempotent: false,
        deny_code: '',
        tool_request: this.getAgentToolRequest({
          tool_request_id: toolRequestId,
          session_id: sessionId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        }),
      };
    }

    let denyCode = String(fields.deny_code || '').trim();
    if (!denyCode) denyCode = decision === 'downgrade' ? 'downgrade_to_local' : 'policy_denied';
    if (existing.policy_decision === decision && String(existing.deny_code || '') === denyCode) {
      return {
        applied: true,
        idempotent: true,
        deny_code: denyCode,
        tool_request: existing,
      };
    }

    this.db
      .prepare(
        `UPDATE agent_tool_requests
         SET policy_decision = ?,
             deny_code = ?,
             grant_id = NULL,
             grant_expires_at_ms = NULL,
             grant_decided_at_ms = ?,
             grant_decided_by = ?,
             grant_note = ?,
             updated_at_ms = ?
         WHERE tool_request_id = ?
           AND session_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?`
      )
      .run(
        decision,
        denyCode,
        now,
        approverId || null,
        note || null,
        now,
        toolRequestId,
        sessionId,
        deviceId,
        userId,
        appId
      );
    if (String(existing.capability_token_id || existing.grant_id || '').trim()) {
      this.db
        .prepare(
          `UPDATE agent_tool_requests
           SET capability_token_kind = 'one_time',
               capability_token_id = COALESCE(capability_token_id, ?),
               capability_token_state = 'revoked',
               capability_token_revoked_at_ms = ?,
               capability_token_revoke_reason = ?,
               updated_at_ms = ?
           WHERE tool_request_id = ?
             AND session_id = ?
             AND device_id = ?
             AND user_id = ?
             AND app_id = ?`
        )
        .run(
          String(existing.capability_token_id || existing.grant_id || '').trim(),
          now,
          denyCode,
          now,
          toolRequestId,
          sessionId,
          deviceId,
          userId,
          appId
        );
    }
    return {
      applied: true,
      idempotent: false,
      deny_code: denyCode,
      tool_request: this.getAgentToolRequest({
        tool_request_id: toolRequestId,
        session_id: sessionId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      }),
    };
  }

  _getAgentToolExecutionByIdempotencyRaw({ request_id, session_id, device_id, user_id, app_id }) {
    const requestId = String(request_id || '').trim();
    const sessionId = String(session_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!requestId || !sessionId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM agent_tool_executions
         WHERE request_id = ?
           AND session_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(requestId, sessionId, deviceId, userId, appId) || null;
  }

  getAgentToolExecutionByIdempotency({ request_id, session_id, device_id, user_id, app_id } = {}) {
    return this._parseAgentToolExecutionRow(this._getAgentToolExecutionByIdempotencyRaw({
      request_id,
      session_id,
      device_id,
      user_id,
      app_id,
    }));
  }

  recordAgentToolExecution(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const sessionId = String(fields.session_id || '').trim();
    const toolRequestId = String(fields.tool_request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const grantId = String(fields.grant_id || '').trim();
    const gatewayProvider = String(fields.gateway_provider || '').trim();
    const toolName = String(fields.tool_name || '').trim();
    const toolArgsHash = String(fields.tool_args_hash || '').trim();
    const execArgvJson = String(fields.exec_argv_json || '').trim();
    const execCwdInput = String(fields.exec_cwd_input || '').trim();
    const execCwdCanonical = String(fields.exec_cwd_canonical || '').trim();
    const approvalIdentityHash = String(fields.approval_identity_hash || '').trim();
    const status = String(fields.status || '').trim().toLowerCase() || 'denied';
    const denyCode = String(fields.deny_code || '').trim();
    const resultJsonRaw = fields.result_json;
    const resultJson = resultJsonRaw == null
      ? null
      : (typeof resultJsonRaw === 'string' ? resultJsonRaw : this._safeJsonStringify(resultJsonRaw));

    if (
      !requestId
      || !sessionId
      || !toolRequestId
      || !deviceId
      || !appId
      || !toolName
      || !toolArgsHash
      || !execArgvJson
      || !execCwdInput
      || !execCwdCanonical
      || !approvalIdentityHash
    ) {
      return {
        created: false,
        deny_code: 'invalid_request',
        execution: null,
      };
    }

    const existing = this.getAgentToolExecutionByIdempotency({
      request_id: requestId,
      session_id: sessionId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (existing) {
      return {
        created: false,
        deny_code: String(existing.deny_code || ''),
        execution: existing,
      };
    }

    const executionId = `aexec_${uuid()}`;
    this.db
      .prepare(
        `INSERT INTO agent_tool_executions(
           execution_id, request_id, session_id, tool_request_id, device_id, user_id, app_id, project_id,
           grant_id, gateway_provider, tool_name, tool_args_hash, exec_argv_json, exec_cwd_input, exec_cwd_canonical, approval_identity_hash,
           status, deny_code, result_json, created_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        executionId,
        requestId,
        sessionId,
        toolRequestId,
        deviceId,
        userId,
        appId,
        projectId,
        grantId || null,
        gatewayProvider || null,
        toolName,
        toolArgsHash,
        execArgvJson,
        execCwdInput,
        execCwdCanonical,
        approvalIdentityHash,
        status,
        denyCode || null,
        resultJson,
        now,
        now
      );

    return {
      created: true,
      deny_code: denyCode,
      execution: this._parseAgentToolExecutionRow(
        this.db.prepare(`SELECT * FROM agent_tool_executions WHERE execution_id = ? LIMIT 1`).get(executionId)
      ),
    };
  }

  _normalizeProjectLineageStatus(value, fallback = 'active') {
    const raw = String(value || '').trim().toLowerCase();
    if (raw === 'active' || raw === 'archived') return raw;
    return String(fallback || 'active').trim().toLowerCase() || 'active';
  }

  _lineageDepth(lineagePath) {
    const pathValue = String(lineagePath || '').trim();
    if (!pathValue) return 0;
    return pathValue.split('/').map((part) => String(part || '').trim()).filter(Boolean).length;
  }

  _parseProjectLineageRow(row) {
    if (!row) return null;
    return {
      ...row,
      root_project_id: String(row.root_project_id || ''),
      parent_project_id: row.parent_project_id != null ? String(row.parent_project_id || '') : '',
      project_id: String(row.project_id || ''),
      lineage_path: String(row.lineage_path || ''),
      parent_task_id: row.parent_task_id != null ? String(row.parent_task_id || '') : '',
      split_round: Math.max(0, Number(row.split_round || 0)),
      split_reason: row.split_reason != null ? String(row.split_reason || '') : '',
      child_index: Math.max(0, Number(row.child_index || 0)),
      status: this._normalizeProjectLineageStatus(row.status, 'active'),
      device_id: String(row.device_id || ''),
      user_id: row.user_id != null ? String(row.user_id || '') : '',
      app_id: String(row.app_id || ''),
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _parseProjectDispatchContextRow(row) {
    if (!row) return null;
    let expectedArtifacts = [];
    try {
      const parsed = row.expected_artifacts_json ? JSON.parse(String(row.expected_artifacts_json)) : [];
      if (Array.isArray(parsed)) {
        expectedArtifacts = parsed.map((v) => String(v || '').trim()).filter(Boolean);
      }
    } catch {
      expectedArtifacts = [];
    }
    return {
      ...row,
      root_project_id: String(row.root_project_id || ''),
      parent_project_id: row.parent_project_id != null ? String(row.parent_project_id || '') : '',
      project_id: String(row.project_id || ''),
      assigned_agent_profile: String(row.assigned_agent_profile || ''),
      parallel_lane_id: String(row.parallel_lane_id || ''),
      budget_class: String(row.budget_class || ''),
      queue_priority: Math.floor(Number(row.queue_priority || 0)),
      expected_artifacts: expectedArtifacts,
      attached_at_ms: Math.max(0, Number(row.attached_at_ms || 0)),
      attach_source: String(row.attach_source || ''),
      device_id: String(row.device_id || ''),
      user_id: row.user_id != null ? String(row.user_id || '') : '',
      app_id: String(row.app_id || ''),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _normalizeProjectRiskTier(value, fallback = 'high') {
    const raw = String(value || '').trim().toLowerCase();
    if (raw === 'low' || raw === 'medium' || raw === 'high' || raw === 'critical') return raw;
    const fb = String(fallback || 'high').trim().toLowerCase();
    if (fb === 'low' || fb === 'medium' || fb === 'high' || fb === 'critical') return fb;
    return 'high';
  }

  _parseStringJsonArray(raw, maxLen = 64) {
    let rows = [];
    try {
      const parsed = raw ? JSON.parse(String(raw)) : [];
      if (Array.isArray(parsed)) rows = parsed;
    } catch {
      rows = [];
    }
    return rows
      .map((item) => String(item || '').trim())
      .filter(Boolean)
      .slice(0, Math.max(0, Number(maxLen || 0)));
  }

  _parseProjectHeartbeatRow(row) {
    if (!row) return null;
    const blockedReason = this._parseStringJsonArray(row.blocked_reason_json, 64);
    const nextActions = this._parseStringJsonArray(row.next_actions_json, 64);
    return {
      ...row,
      root_project_id: String(row.root_project_id || ''),
      parent_project_id: row.parent_project_id != null ? String(row.parent_project_id || '') : '',
      project_id: String(row.project_id || ''),
      lineage_depth: Math.max(0, Math.floor(Number(row.lineage_depth || 0))),
      queue_depth: Math.max(0, Math.floor(Number(row.queue_depth || 0))),
      oldest_wait_ms: Math.max(0, Math.floor(Number(row.oldest_wait_ms || 0))),
      blocked_reason: blockedReason,
      next_actions: nextActions,
      risk_tier: this._normalizeProjectRiskTier(row.risk_tier, 'high'),
      heartbeat_seq: Math.max(0, Math.floor(Number(row.heartbeat_seq || 0))),
      sent_at_ms: Math.max(0, Number(row.sent_at_ms || 0)),
      received_at_ms: Math.max(0, Number(row.received_at_ms || 0)),
      expires_at_ms: Math.max(0, Number(row.expires_at_ms || 0)),
      conservative_only: !!Number(row.conservative_only || 0),
      last_dispatch_planned_at_ms: row.last_dispatch_planned_at_ms != null
        ? Math.max(0, Number(row.last_dispatch_planned_at_ms || 0))
        : 0,
      dispatch_count: Math.max(0, Math.floor(Number(row.dispatch_count || 0))),
      device_id: String(row.device_id || ''),
      user_id: row.user_id != null ? String(row.user_id || '') : '',
      app_id: String(row.app_id || ''),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _getProjectLineageRowRaw({ project_id, device_id, user_id, app_id }) {
    const projectId = String(project_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!projectId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM project_lineage
         WHERE project_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(projectId, deviceId, userId, appId) || null;
  }

  _getProjectLineageRowRawByProjectId(project_id) {
    const projectId = String(project_id || '').trim();
    if (!projectId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM project_lineage
         WHERE project_id = ?
         LIMIT 1`
      )
      .get(projectId) || null;
  }

  getProjectLineageNode({ project_id, device_id, user_id, app_id }) {
    return this._parseProjectLineageRow(this._getProjectLineageRowRaw({
      project_id,
      device_id,
      user_id,
      app_id,
    }));
  }

  listProjectLineageNodes({ root_project_id, device_id, user_id, app_id, include_archived }) {
    const rootProjectId = String(root_project_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!rootProjectId || !deviceId || !appId) return [];

    const includeArchived = !!include_archived;
    const where = [
      'device_id = ?',
      'user_id = ?',
      'app_id = ?',
      'root_project_id = ?',
    ];
    const args = [deviceId, userId, appId, rootProjectId];
    if (!includeArchived) where.push(`status = 'active'`);

    const sql = `SELECT *
                 FROM project_lineage
                 WHERE ${where.join(' AND ')}
                 ORDER BY lineage_path ASC, child_index ASC, project_id ASC`;
    return this.db.prepare(sql).all(...args).map((row) => this._parseProjectLineageRow(row));
  }

  _lineageDeny(deny_code, detail = {}) {
    return {
      accepted: false,
      created: false,
      deny_code: String(deny_code || 'lineage_rejected'),
      detail: detail && typeof detail === 'object' ? detail : {},
      lineage: null,
    };
  }

  upsertProjectLineage(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    let rootProjectId = String(fields.root_project_id || '').trim();
    const parentProjectId = String(fields.parent_project_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const suppliedLineagePath = String(fields.lineage_path || '').trim();
    const parentTaskId = String(fields.parent_task_id || '').trim();
    const splitRound = Math.max(0, Math.floor(Number(fields.split_round || 0)));
    const splitReason = String(fields.split_reason || '').trim();
    const childIndex = Math.max(0, Math.floor(Number(fields.child_index || 0)));
    const status = this._normalizeProjectLineageStatus(fields.status, 'active');
    const expectedRootProjectId = String(fields.expected_root_project_id || '').trim();
    const createdAtMs = Math.max(0, Number(fields.created_at_ms || now));

    if (!deviceId || !appId || !projectId || !rootProjectId) {
      return this._lineageDeny('invalid_request');
    }
    if (parentProjectId && parentProjectId === projectId) {
      return this._lineageDeny('lineage_cycle_detected');
    }
    if (!parentProjectId && projectId !== rootProjectId) {
      return this._lineageDeny('lineage_parent_missing');
    }
    if (parentProjectId && projectId === rootProjectId) {
      return this._lineageDeny('lineage_root_mismatch');
    }
    if (expectedRootProjectId && expectedRootProjectId !== rootProjectId) {
      return this._lineageDeny('lineage_root_mismatch');
    }

    const existing = this._getProjectLineageRowRaw({
      project_id: projectId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (!existing) {
      const existingAny = this._getProjectLineageRowRawByProjectId(projectId);
      if (existingAny) return this._lineageDeny('permission_denied');
    }
    if (existing && String(existing.root_project_id || '') !== rootProjectId) {
      return this._lineageDeny('lineage_root_mismatch');
    }

    let parentRow = null;
    if (parentProjectId) {
      parentRow = this._getProjectLineageRowRaw({
        project_id: parentProjectId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      });
      if (!parentRow) return this._lineageDeny('lineage_parent_missing');
      if (this._normalizeProjectLineageStatus(parentRow.status, 'active') !== 'active') {
        return this._lineageDeny('parent_inactive');
      }
      const parentRootId = String(parentRow.root_project_id || '').trim();
      if (!parentRootId || parentRootId !== rootProjectId) {
        return this._lineageDeny('lineage_root_mismatch');
      }
      rootProjectId = parentRootId;
    } else if (projectId !== rootProjectId) {
      return this._lineageDeny('lineage_root_mismatch');
    }

    const lineagePath = parentRow
      ? `${String(parentRow.lineage_path || '').replace(/\/+$/, '')}/${projectId}`
      : projectId;
    if (!lineagePath || this._lineageDepth(lineagePath) <= 0) {
      return this._lineageDeny('lineage_root_mismatch');
    }
    if (suppliedLineagePath && suppliedLineagePath !== lineagePath) {
      return this._lineageDeny('lineage_root_mismatch');
    }

    if (parentRow) {
      const visited = new Set([projectId]);
      let current = parentRow;
      let hops = 0;
      while (current) {
        const currentProjectId = String(current.project_id || '').trim();
        if (!currentProjectId) return this._lineageDeny('lineage_parent_missing');
        if (visited.has(currentProjectId)) return this._lineageDeny('lineage_cycle_detected');
        visited.add(currentProjectId);

        const cursorParent = String(current.parent_project_id || '').trim();
        if (!cursorParent) break;
        const next = this._getProjectLineageRowRaw({
          project_id: cursorParent,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        });
        if (!next) return this._lineageDeny('lineage_parent_missing');
        if (String(next.root_project_id || '') !== rootProjectId) {
          return this._lineageDeny('lineage_root_mismatch');
        }
        current = next;
        hops += 1;
        if (hops > 2048) return this._lineageDeny('lineage_cycle_detected');
      }
    }

    this.db.exec('BEGIN;');
    try {
      if (existing && (
        String(existing.device_id || '') !== deviceId
        || String(existing.user_id || '') !== userId
        || String(existing.app_id || '') !== appId
      )) {
        this.db.exec('ROLLBACK;');
        return this._lineageDeny('permission_denied');
      }

      let created = false;
      if (existing && existing.project_id) {
        this.db
          .prepare(
            `UPDATE project_lineage
             SET root_project_id = ?,
                 parent_project_id = ?,
                 lineage_path = ?,
                 parent_task_id = ?,
                 split_round = ?,
                 split_reason = ?,
                 child_index = ?,
                 status = ?,
                 updated_at_ms = ?
             WHERE project_id = ?
               AND device_id = ?
               AND user_id = ?
               AND app_id = ?`
          )
          .run(
            rootProjectId,
            parentProjectId || null,
            lineagePath,
            parentTaskId || null,
            splitRound,
            splitReason || null,
            childIndex,
            status,
            now,
            projectId,
            deviceId,
            userId,
            appId
          );
      } else {
        created = true;
        this.db
          .prepare(
            `INSERT INTO project_lineage(
               project_id, root_project_id, parent_project_id, lineage_path, parent_task_id,
               split_round, split_reason, child_index, status,
               device_id, user_id, app_id, created_at_ms, updated_at_ms
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
          )
          .run(
            projectId,
            rootProjectId,
            parentProjectId || null,
            lineagePath,
            parentTaskId || null,
            splitRound,
            splitReason || null,
            childIndex,
            status,
            deviceId,
            userId,
            appId,
            createdAtMs,
            now
          );
      }

      const row = this._parseProjectLineageRow(
        this._getProjectLineageRowRaw({
          project_id: projectId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
        })
      );
      this.db.exec('COMMIT;');
      return {
        accepted: true,
        created,
        deny_code: '',
        request_id: requestId,
        lineage: row,
      };
    } catch (err) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw err;
    }
  }

  getProjectLineageTree({
    root_project_id,
    project_id,
    max_depth,
    include_archived,
    device_id,
    user_id,
    app_id,
  } = {}) {
    const rootProjectId = String(root_project_id || '').trim();
    const projectId = String(project_id || '').trim();
    const maxDepth = Number(max_depth || 0);
    const includeArchived = !!include_archived;
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!rootProjectId || !deviceId || !appId) {
      return {
        root_project_id: rootProjectId,
        nodes: [],
        generated_at_ms: nowMs(),
      };
    }

    const rows = this.listProjectLineageNodes({
      root_project_id: rootProjectId,
      include_archived: includeArchived,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (!rows.length) {
      return {
        root_project_id: rootProjectId,
        nodes: [],
        generated_at_ms: nowMs(),
      };
    }

    let basePath = '';
    if (projectId) {
      const anchor = rows.find((row) => String(row.project_id || '') === projectId);
      if (!anchor) {
        return {
          root_project_id: rootProjectId,
          nodes: [],
          generated_at_ms: nowMs(),
        };
      }
      basePath = String(anchor.lineage_path || '');
    } else {
      const rootNode = rows.find((row) => String(row.project_id || '') === rootProjectId);
      basePath = rootNode ? String(rootNode.lineage_path || '') : rootProjectId;
    }

    const baseDepth = this._lineageDepth(basePath);
    const hasDepthCap = Number.isFinite(maxDepth) && maxDepth > 0;
    const pathPrefix = `${basePath}/`;
    const filtered = rows.filter((row) => {
      const pathValue = String(row.lineage_path || '');
      if (pathValue !== basePath && !pathValue.startsWith(pathPrefix)) return false;
      if (!hasDepthCap) return true;
      const depthDelta = this._lineageDepth(pathValue) - baseDepth;
      return depthDelta >= 0 && depthDelta <= Math.floor(maxDepth);
    });

    return {
      root_project_id: rootProjectId,
      nodes: filtered,
      generated_at_ms: nowMs(),
    };
  }

  _getProjectDispatchContextRowRaw({ project_id, device_id, user_id, app_id }) {
    const projectId = String(project_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!projectId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM project_dispatch_context
         WHERE project_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(projectId, deviceId, userId, appId) || null;
  }

  _getProjectDispatchContextRowRawByProjectId(project_id) {
    const projectId = String(project_id || '').trim();
    if (!projectId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM project_dispatch_context
         WHERE project_id = ?
         LIMIT 1`
      )
      .get(projectId) || null;
  }

  listProjectDispatchContexts({ root_project_id, device_id, user_id, app_id } = {}) {
    const rootProjectId = String(root_project_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!rootProjectId || !deviceId || !appId) return [];
    return this.db
      .prepare(
        `SELECT *
         FROM project_dispatch_context
         WHERE device_id = ?
           AND user_id = ?
           AND app_id = ?
           AND root_project_id = ?
         ORDER BY queue_priority DESC, attached_at_ms ASC, project_id ASC`
      )
      .all(deviceId, userId, appId, rootProjectId)
      .map((row) => this._parseProjectDispatchContextRow(row));
  }

  _getProjectHeartbeatRowRaw({ project_id, device_id, user_id, app_id }) {
    const projectId = String(project_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    if (!projectId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM project_heartbeat_state
         WHERE project_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
         LIMIT 1`
      )
      .get(projectId, deviceId, userId, appId) || null;
  }

  _getProjectHeartbeatRowRawByProjectId(project_id) {
    const projectId = String(project_id || '').trim();
    if (!projectId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM project_heartbeat_state
         WHERE project_id = ?
         LIMIT 1`
      )
      .get(projectId) || null;
  }

  _deleteExpiredProjectHeartbeatRows({ now_ms } = {}) {
    const now = Math.max(0, Number(now_ms || nowMs()));
    const result = this.db
      .prepare(
        `DELETE FROM project_heartbeat_state
         WHERE expires_at_ms > 0
           AND expires_at_ms <= ?`
      )
      .run(now);
    return Math.max(0, Number(result?.changes || 0));
  }

  listProjectHeartbeatStates({
    root_project_id,
    device_id,
    user_id,
    app_id,
    include_expired,
    now_ms,
  } = {}) {
    const rootProjectId = String(root_project_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    const includeExpired = !!include_expired;
    const now = Math.max(0, Number(now_ms || nowMs()));
    if (!rootProjectId || !deviceId || !appId) return [];
    if (!includeExpired) {
      this._deleteExpiredProjectHeartbeatRows({ now_ms: now });
    }
    return this.db
      .prepare(
        `SELECT *
         FROM project_heartbeat_state
         WHERE device_id = ?
           AND user_id = ?
           AND app_id = ?
           AND root_project_id = ?
         ORDER BY oldest_wait_ms DESC, queue_depth DESC, project_id ASC`
      )
      .all(deviceId, userId, appId, rootProjectId)
      .map((row) => this._parseProjectHeartbeatRow(row))
      .filter((row) => includeExpired || Number(row.expires_at_ms || 0) > now);
  }

  _projectHeartbeatDeny(deny_code, detail = {}) {
    return {
      accepted: false,
      created: false,
      deny_code: String(deny_code || 'heartbeat_rejected'),
      detail: detail && typeof detail === 'object' ? detail : {},
      heartbeat: null,
    };
  }

  upsertProjectHeartbeat(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const rootProjectId = String(fields.root_project_id || '').trim();
    const parentProjectId = String(fields.parent_project_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const queueDepth = Math.max(0, Math.floor(Number(fields.queue_depth || 0)));
    const oldestWaitMs = Math.max(0, Math.floor(Number(fields.oldest_wait_ms || 0)));
    const blockedReason = Array.isArray(fields.blocked_reason)
      ? fields.blocked_reason.map((item) => String(item || '').trim()).filter(Boolean).slice(0, 64)
      : [];
    const nextActions = Array.isArray(fields.next_actions)
      ? fields.next_actions.map((item) => String(item || '').trim()).filter(Boolean).slice(0, 64)
      : [];
    const riskTier = this._normalizeProjectRiskTier(fields.risk_tier, 'high');
    const heartbeatSeq = Math.max(0, Math.floor(Number(fields.heartbeat_seq || 0)));
    const sentAtMs = Math.max(0, Number(fields.sent_at_ms || now));
    const receivedAtMs = Math.max(0, Number(fields.received_at_ms || now));
    const ttlMs = Math.max(10, Math.floor(Number(fields.ttl_ms || this.projectHeartbeatTtlMs || 10)));
    const expiresAtMs = sentAtMs + ttlMs;

    if (!deviceId || !appId || !rootProjectId || !projectId || heartbeatSeq <= 0) {
      return this._projectHeartbeatDeny('invalid_request');
    }
    if (expiresAtMs <= now) {
      return this._projectHeartbeatDeny('heartbeat_expired');
    }

    const lineage = this._parseProjectLineageRow(this._getProjectLineageRowRaw({
      project_id: projectId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    }));
    if (!lineage) return this._projectHeartbeatDeny('lineage_parent_missing');
    if (String(lineage.root_project_id || '') !== rootProjectId) {
      return this._projectHeartbeatDeny('lineage_root_mismatch');
    }
    if (parentProjectId && String(lineage.parent_project_id || '') !== parentProjectId) {
      return this._projectHeartbeatDeny('lineage_root_mismatch');
    }
    if (String(lineage.status || 'active') !== 'active') {
      return this._projectHeartbeatDeny('parent_inactive');
    }

    const lineageDepth = Math.max(1, this._lineageDepth(lineage.lineage_path || projectId));
    const conservativeOnly = riskTier === 'high' || riskTier === 'critical';
    const existing = this._getProjectHeartbeatRowRaw({
      project_id: projectId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (!existing) {
      const existingAny = this._getProjectHeartbeatRowRawByProjectId(projectId);
      if (existingAny) return this._projectHeartbeatDeny('permission_denied');
    }
    if (existing && (
      String(existing.device_id || '') !== deviceId
      || String(existing.user_id || '') !== userId
      || String(existing.app_id || '') !== appId
    )) {
      return this._projectHeartbeatDeny('permission_denied');
    }
    if (existing && heartbeatSeq < Math.max(0, Number(existing.heartbeat_seq || 0))) {
      return this._projectHeartbeatDeny('heartbeat_stale');
    }
    if (existing
      && heartbeatSeq === Math.max(0, Number(existing.heartbeat_seq || 0))
      && sentAtMs <= Math.max(0, Number(existing.sent_at_ms || 0))
    ) {
      return this._projectHeartbeatDeny('heartbeat_stale');
    }

    this.db.exec('BEGIN;');
    try {
      this._deleteExpiredProjectHeartbeatRows({ now_ms: now });
      let created = false;
      if (existing && existing.project_id) {
        this.db
          .prepare(
            `UPDATE project_heartbeat_state
             SET root_project_id = ?,
                 parent_project_id = ?,
                 lineage_depth = ?,
                 queue_depth = ?,
                 oldest_wait_ms = ?,
                 blocked_reason_json = ?,
                 next_actions_json = ?,
                 risk_tier = ?,
                 heartbeat_seq = ?,
                 sent_at_ms = ?,
                 received_at_ms = ?,
                 expires_at_ms = ?,
                 conservative_only = ?,
                 updated_at_ms = ?
             WHERE project_id = ?
               AND device_id = ?
               AND user_id = ?
               AND app_id = ?`
          )
          .run(
            rootProjectId,
            lineage.parent_project_id || null,
            lineageDepth,
            queueDepth,
            oldestWaitMs,
            JSON.stringify(blockedReason),
            JSON.stringify(nextActions),
            riskTier,
            heartbeatSeq,
            sentAtMs,
            receivedAtMs,
            expiresAtMs,
            conservativeOnly ? 1 : 0,
            now,
            projectId,
            deviceId,
            userId,
            appId
          );
      } else {
        created = true;
        this.db
          .prepare(
            `INSERT INTO project_heartbeat_state(
               project_id, root_project_id, parent_project_id, lineage_depth,
               queue_depth, oldest_wait_ms, blocked_reason_json, next_actions_json,
               risk_tier, heartbeat_seq, sent_at_ms, received_at_ms, expires_at_ms,
               conservative_only, last_dispatch_planned_at_ms, dispatch_count,
               device_id, user_id, app_id, updated_at_ms
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
          )
          .run(
            projectId,
            rootProjectId,
            lineage.parent_project_id || null,
            lineageDepth,
            queueDepth,
            oldestWaitMs,
            JSON.stringify(blockedReason),
            JSON.stringify(nextActions),
            riskTier,
            heartbeatSeq,
            sentAtMs,
            receivedAtMs,
            expiresAtMs,
            conservativeOnly ? 1 : 0,
            null,
            0,
            deviceId,
            userId,
            appId,
            now
          );
      }
      const row = this._parseProjectHeartbeatRow(this._getProjectHeartbeatRowRaw({
        project_id: projectId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      }));
      this.db.exec('COMMIT;');
      return {
        accepted: true,
        created,
        deny_code: '',
        request_id: requestId,
        heartbeat: row,
      };
    } catch (err) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw err;
    }
  }

  _buildDispatchPlanPrewarmTargets({ dispatch, heartbeat, conservative_only } = {}) {
    const out = [];
    const pushUnique = (value) => {
      const token = String(value || '').trim();
      if (!token || out.includes(token)) return;
      out.push(token);
    };
    if (conservative_only) {
      pushUnique('agent:safe-default');
      pushUnique('index:readonly');
      return out;
    }

    const assignedProfile = String(dispatch?.assigned_agent_profile || '').trim();
    pushUnique(assignedProfile ? `agent:${assignedProfile}` : 'agent:default');
    pushUnique('index:project-hot');

    const queueDepth = Math.max(0, Number(heartbeat?.queue_depth || 0));
    const oldestWaitMs = Math.max(0, Number(heartbeat?.oldest_wait_ms || 0));
    if (queueDepth > 0) pushUnique('cache:queue-hot');
    if (oldestWaitMs >= 1500) pushUnique('cache:wait-hot');

    const expectedArtifacts = Array.isArray(dispatch?.expected_artifacts)
      ? dispatch.expected_artifacts
      : [];
    for (const artifact of expectedArtifacts) {
      const token = String(artifact || '').toLowerCase();
      if (token.includes('patch') || token.includes('diff')) pushUnique('cache:diff-context');
      if (token.includes('test')) pushUnique('cache:test-fixture');
      if (token.includes('index')) pushUnique('index:project-hot');
    }

    return out.slice(0, 8);
  }

  buildProjectDispatchPlan(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const rootProjectId = String(fields.root_project_id || '').trim();
    const maxProjects = Math.max(
      1,
      Math.min(64, Math.floor(Number(fields.max_projects || this.projectDispatchDefaultBatchSize || 4)))
    );

    if (!deviceId || !appId || !rootProjectId) {
      return {
        planned: false,
        deny_code: 'invalid_request',
        request_id: requestId,
        generated_at_ms: now,
        batch_id: '',
        conservative_mode: true,
        items: [],
      };
    }

    const rootLineage = this._parseProjectLineageRow(this._getProjectLineageRowRaw({
      project_id: rootProjectId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    }));
    if (!rootLineage) {
      return {
        planned: false,
        deny_code: 'lineage_parent_missing',
        request_id: requestId,
        generated_at_ms: now,
        batch_id: '',
        conservative_mode: true,
        items: [],
      };
    }
    if (String(rootLineage.status || 'active') !== 'active') {
      return {
        planned: false,
        deny_code: 'parent_inactive',
        request_id: requestId,
        generated_at_ms: now,
        batch_id: '',
        conservative_mode: true,
        items: [],
      };
    }
    if (String(rootLineage.root_project_id || '') !== rootProjectId) {
      return {
        planned: false,
        deny_code: 'lineage_root_mismatch',
        request_id: requestId,
        generated_at_ms: now,
        batch_id: '',
        conservative_mode: true,
        items: [],
      };
    }

    const ttlPruned = this._deleteExpiredProjectHeartbeatRows({ now_ms: now });
    const lineageRows = this.listProjectLineageNodes({
      root_project_id: rootProjectId,
      include_archived: false,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    });
    if (!lineageRows.length) {
      return {
        planned: true,
        deny_code: '',
        request_id: requestId,
        generated_at_ms: now,
        batch_id: uuid(),
        ttl_pruned: ttlPruned,
        conservative_mode: true,
        items: [],
      };
    }

    const dispatchMap = new Map(
      this.listProjectDispatchContexts({
        root_project_id: rootProjectId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      }).map((row) => [String(row.project_id || ''), row])
    );
    const heartbeatMap = new Map(
      this.listProjectHeartbeatStates({
        root_project_id: rootProjectId,
        include_expired: false,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        now_ms: now,
      }).map((row) => [String(row.project_id || ''), row])
    );
    const starvationMs = Math.max(1000, Number(this.projectDispatchStarvationMs || 1000));
    const conservativePenalty = Math.max(0, Number(this.projectDispatchConservativePenalty || 0));
    const batchId = uuid();

    const ranked = [];
    for (const lineage of lineageRows) {
      const projectId = String(lineage.project_id || '').trim();
      if (!projectId) continue;
      const heartbeat = heartbeatMap.get(projectId) || null;
      const dispatch = dispatchMap.get(projectId) || null;
      const riskTier = this._normalizeProjectRiskTier(heartbeat?.risk_tier || '', 'high');
      const hasFreshHeartbeat = !!heartbeat;
      const conservativeOnly = !hasFreshHeartbeat || riskTier === 'high' || riskTier === 'critical';
      const queueDepth = Math.max(0, Math.floor(Number(heartbeat?.queue_depth || 0)));
      const oldestWaitMs = Math.max(0, Math.floor(Number(heartbeat?.oldest_wait_ms || 0)));
      const queuePriority = Math.floor(Number(dispatch?.queue_priority || 0));
      const lineageDepth = Math.max(1, this._lineageDepth(String(lineage?.lineage_path || projectId)));
      const lineagePriorityBoost = Math.max(0, (lineageDepth - 1) * 120);
      const lastPlannedAt = Math.max(0, Number(heartbeat?.last_dispatch_planned_at_ms || 0));
      const starvationAgeMs = lastPlannedAt > 0 ? Math.max(0, now - lastPlannedAt) : starvationMs + 1;
      const starved = hasFreshHeartbeat && starvationAgeMs >= starvationMs;
      const fairnessBucket = conservativeOnly ? 'conservative' : (starved ? 'starved' : 'normal');
      let priorityScore = (
        oldestWaitMs
        + (queueDepth * 250)
        + (queuePriority * 100)
        + lineagePriorityBoost
      );
      if (starved) priorityScore += starvationMs;
      if (riskTier === 'critical') priorityScore -= 2000;
      if (conservativeOnly) priorityScore -= conservativePenalty;
      const splitGroupParent = String(lineage.parent_project_id || rootProjectId || '').trim() || rootProjectId;
      const splitGroupId = `${rootProjectId}:${splitGroupParent}`;
      const prewarmTargets = this._buildDispatchPlanPrewarmTargets({
        dispatch,
        heartbeat,
        conservative_only: conservativeOnly,
      });

      ranked.push({
        root_project_id: rootProjectId,
        parent_project_id: String(lineage.parent_project_id || ''),
        project_id: projectId,
        priority_score: Number(priorityScore || 0),
        prewarm_targets: prewarmTargets,
        batch_id: batchId,
        fairness_bucket: fairnessBucket,
        lineage_priority_boost: lineagePriorityBoost,
        split_group_id: splitGroupId,
        risk_tier: riskTier,
        conservative_only: conservativeOnly,
        queue_depth: queueDepth,
        oldest_wait_ms: oldestWaitMs,
      });
    }

    const bucketRank = { starved: 0, normal: 1, conservative: 2 };
    ranked.sort((a, b) => {
      const aBucket = bucketRank[String(a.fairness_bucket || 'conservative')] ?? 2;
      const bBucket = bucketRank[String(b.fairness_bucket || 'conservative')] ?? 2;
      if (aBucket !== bBucket) return aBucket - bBucket;
      const scoreDelta = Number(b.priority_score || 0) - Number(a.priority_score || 0);
      if (scoreDelta !== 0) return scoreDelta;
      const waitDelta = Number(b.oldest_wait_ms || 0) - Number(a.oldest_wait_ms || 0);
      if (waitDelta !== 0) return waitDelta;
      return String(a.project_id || '').localeCompare(String(b.project_id || ''));
    });

    const picked = ranked.slice(0, maxProjects);
    const pickedHeartbeatRows = picked
      .map((item) => heartbeatMap.get(String(item.project_id || '')))
      .filter(Boolean);
    if (pickedHeartbeatRows.length > 0) {
      this.db.exec('BEGIN;');
      try {
        const stmt = this.db.prepare(
          `UPDATE project_heartbeat_state
           SET last_dispatch_planned_at_ms = ?,
               dispatch_count = dispatch_count + 1,
               updated_at_ms = ?
           WHERE project_id = ?
             AND device_id = ?
             AND user_id = ?
             AND app_id = ?`
        );
        for (const row of pickedHeartbeatRows) {
          stmt.run(
            now,
            now,
            String(row.project_id || ''),
            deviceId,
            userId,
            appId
          );
        }
        this.db.exec('COMMIT;');
      } catch (err) {
        try {
          this.db.exec('ROLLBACK;');
        } catch {
          // ignore
        }
        throw err;
      }
    }

    return {
      planned: true,
      deny_code: '',
      request_id: requestId,
      generated_at_ms: now,
      batch_id: batchId,
      ttl_pruned: ttlPruned,
      total_candidates: ranked.length,
      conservative_mode: picked.length <= 0 || picked.some((item) => !!item.conservative_only),
      items: picked,
    };
  }

  attachProjectDispatchContext(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const rootProjectId = String(fields.root_project_id || '').trim();
    const parentProjectId = String(fields.parent_project_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const assignedAgentProfile = String(fields.assigned_agent_profile || '').trim();
    const parallelLaneId = String(fields.parallel_lane_id || '').trim();
    const budgetClass = String(fields.budget_class || '').trim();
    const queuePriority = Math.floor(Number(fields.queue_priority || 0));
    const expectedArtifacts = Array.isArray(fields.expected_artifacts)
      ? fields.expected_artifacts.map((v) => String(v || '').trim()).filter(Boolean).slice(0, 128)
      : [];
    const attachedAtMs = Math.max(0, Number(fields.attached_at_ms || now));
    const attachSource = String(fields.attach_source || '').trim() || 'x_terminal';

    if (!deviceId || !appId || !rootProjectId || !projectId || !assignedAgentProfile) {
      return {
        attached: false,
        deny_code: 'invalid_request',
        request_id: requestId,
        dispatch: null,
      };
    }

    const lineage = this._parseProjectLineageRow(this._getProjectLineageRowRaw({
      project_id: projectId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
    }));
    if (!lineage) {
      return {
        attached: false,
        deny_code: 'lineage_parent_missing',
        request_id: requestId,
        dispatch: null,
      };
    }
    if (lineage.status !== 'active') {
      return {
        attached: false,
        deny_code: 'parent_inactive',
        request_id: requestId,
        dispatch: null,
      };
    }
    if (String(lineage.root_project_id || '') !== rootProjectId) {
      return {
        attached: false,
        deny_code: 'lineage_root_mismatch',
        request_id: requestId,
        dispatch: null,
      };
    }
    if (parentProjectId && String(lineage.parent_project_id || '') !== parentProjectId) {
      return {
        attached: false,
        deny_code: 'lineage_root_mismatch',
        request_id: requestId,
        dispatch: null,
      };
    }

    this.db.exec('BEGIN;');
    try {
      const existing = this._getProjectDispatchContextRowRaw({
        project_id: projectId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      });
      if (!existing) {
        const existingAny = this._getProjectDispatchContextRowRawByProjectId(projectId);
        if (existingAny) {
          this.db.exec('ROLLBACK;');
          return {
            attached: false,
            deny_code: 'permission_denied',
            request_id: requestId,
            dispatch: null,
          };
        }
      }
      if (existing && (
        String(existing.device_id || '') !== deviceId
        || String(existing.user_id || '') !== userId
        || String(existing.app_id || '') !== appId
      )) {
        this.db.exec('ROLLBACK;');
        return {
          attached: false,
          deny_code: 'permission_denied',
          request_id: requestId,
          dispatch: null,
        };
      }

      if (existing && existing.project_id) {
        this.db
          .prepare(
            `UPDATE project_dispatch_context
             SET root_project_id = ?,
                 parent_project_id = ?,
                 assigned_agent_profile = ?,
                 parallel_lane_id = ?,
                 budget_class = ?,
                 queue_priority = ?,
                 expected_artifacts_json = ?,
                 attached_at_ms = ?,
                 attach_source = ?,
                 updated_at_ms = ?
             WHERE project_id = ?
               AND device_id = ?
               AND user_id = ?
               AND app_id = ?`
          )
          .run(
            rootProjectId,
            lineage.parent_project_id || null,
            assignedAgentProfile,
            parallelLaneId,
            budgetClass,
            queuePriority,
            JSON.stringify(expectedArtifacts),
            attachedAtMs,
            attachSource,
            now,
            projectId,
            deviceId,
            userId,
            appId
          );
      } else {
        this.db
          .prepare(
            `INSERT INTO project_dispatch_context(
               project_id, root_project_id, parent_project_id,
               assigned_agent_profile, parallel_lane_id, budget_class, queue_priority,
               expected_artifacts_json, attached_at_ms, attach_source,
               device_id, user_id, app_id, updated_at_ms
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
          )
          .run(
            projectId,
            rootProjectId,
            lineage.parent_project_id || null,
            assignedAgentProfile,
            parallelLaneId,
            budgetClass,
            queuePriority,
            JSON.stringify(expectedArtifacts),
            attachedAtMs,
            attachSource,
            deviceId,
            userId,
            appId,
            now
          );
      }

      const row = this._parseProjectDispatchContextRow(this._getProjectDispatchContextRowRaw({
        project_id: projectId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
      }));
      this.db.exec('COMMIT;');
      return {
        attached: true,
        deny_code: '',
        request_id: requestId,
        dispatch: row,
      };
    } catch (err) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw err;
    }
  }

  _normalizePaymentIntentStatus(value, fallback = 'prepared') {
    const raw = String(value || '').trim().toLowerCase();
    if ([
      'prepared',
      'evidence_verified',
      'pending_user_auth',
      'authorized',
      'committed',
      'aborted',
      'expired',
    ].includes(raw)) {
      return raw;
    }
    return String(fallback || 'prepared').trim().toLowerCase() || 'prepared';
  }

  _normalizePaymentReceiptDeliveryState(value, fallback = 'prepared') {
    const raw = String(value || '').trim().toLowerCase();
    if ([
      'prepared',
      'committed',
      'undo_pending',
      'compensated',
    ].includes(raw)) {
      return raw;
    }
    return String(fallback || 'prepared').trim().toLowerCase() || 'prepared';
  }

  _normalizePaymentPreviewRiskLevel(value, fallback = 'high') {
    const raw = String(value || '').trim().toLowerCase();
    if (raw === 'low' || raw === 'medium' || raw === 'high') return raw;
    const normalizedFallback = String(fallback || 'high').trim().toLowerCase();
    return normalizedFallback === 'low' || normalizedFallback === 'medium' || normalizedFallback === 'high'
      ? normalizedFallback
      : 'high';
  }

  _buildPaymentPreviewCard(fields = {}) {
    const src = fields && typeof fields === 'object' ? fields : {};
    const card = {
      amount_minor: Math.max(0, Math.floor(Number(src.amount_minor || 0))),
      currency: String(src.currency || '').trim().toUpperCase(),
      merchant_id: String(src.merchant_id || '').trim(),
      source_terminal_id: String(src.source_terminal_id || '').trim(),
      allowed_mobile_terminal_id: String(src.allowed_mobile_terminal_id || '').trim(),
      preview_fee_minor: Math.max(0, Math.floor(Number(src.preview_fee_minor || 0))),
      preview_risk_level: this._normalizePaymentPreviewRiskLevel(src.preview_risk_level, 'high'),
      preview_undo_window_ms: Math.max(0, Math.floor(Number(src.preview_undo_window_ms || 0))),
    };
    return {
      ...card,
      preview_card_hash: sha256Hex(JSON.stringify(card)),
    };
  }

  _derivePaymentTwoPhaseState(row) {
    const status = this._normalizePaymentIntentStatus(row?.status, 'prepared');
    const receiptState = this._normalizePaymentReceiptDeliveryState(row?.receipt_delivery_state, 'prepared');
    if (receiptState === 'compensated') return 'compensated';
    if (status === 'authorized') return 'approved';
    if (status === 'committed' && receiptState === 'prepared') return 'dispatched';
    if (status === 'committed') return 'acked';
    return 'prepared';
  }

  _isPaymentIntentTerminalStatus(status) {
    const normalized = this._normalizePaymentIntentStatus(status, '');
    return normalized === 'committed' || normalized === 'aborted' || normalized === 'expired';
  }

  _parsePaymentIntentRow(row) {
    if (!row) return null;
    return {
      intent_id: String(row.intent_id || ''),
      request_id: String(row.request_id || ''),
      device_id: String(row.device_id || ''),
      user_id: row.user_id != null ? String(row.user_id || '') : '',
      app_id: String(row.app_id || ''),
      project_id: row.project_id != null ? String(row.project_id || '') : '',
      status: this._normalizePaymentIntentStatus(row.status, 'prepared'),
      amount_minor: Math.max(0, Math.floor(Number(row.amount_minor || 0))),
      currency: String(row.currency || ''),
      merchant_id: row.merchant_id != null ? String(row.merchant_id || '') : '',
      source_terminal_id: row.source_terminal_id != null ? String(row.source_terminal_id || '') : '',
      allowed_mobile_terminal_id: row.allowed_mobile_terminal_id != null ? String(row.allowed_mobile_terminal_id || '') : '',
      expected_photo_hash: row.expected_photo_hash != null ? String(row.expected_photo_hash || '') : '',
      expected_geo_hash: row.expected_geo_hash != null ? String(row.expected_geo_hash || '') : '',
      expected_qr_payload_hash: row.expected_qr_payload_hash != null ? String(row.expected_qr_payload_hash || '') : '',
      preview_fee_minor: row.preview_fee_minor != null
        ? Math.max(0, Math.floor(Number(row.preview_fee_minor || 0)))
        : 0,
      preview_risk_level: this._normalizePaymentPreviewRiskLevel(row.preview_risk_level, 'high'),
      preview_undo_window_ms: row.preview_undo_window_ms != null
        ? Math.max(0, Math.floor(Number(row.preview_undo_window_ms || 0)))
        : Math.max(0, Math.floor(Number(this.paymentReceiptUndoWindowMs || 0))),
      preview_card_hash: row.preview_card_hash != null ? String(row.preview_card_hash || '') : '',
      evidence_photo_hash: row.evidence_photo_hash != null ? String(row.evidence_photo_hash || '') : '',
      evidence_geo_hash: row.evidence_geo_hash != null ? String(row.evidence_geo_hash || '') : '',
      evidence_qr_payload_hash: row.evidence_qr_payload_hash != null ? String(row.evidence_qr_payload_hash || '') : '',
      evidence_nonce: row.evidence_nonce != null ? String(row.evidence_nonce || '') : '',
      evidence_currency: row.evidence_currency != null ? String(row.evidence_currency || '') : '',
      evidence_merchant_id: row.evidence_merchant_id != null ? String(row.evidence_merchant_id || '') : '',
      evidence_price_amount_minor: row.evidence_price_amount_minor != null
        ? Math.max(0, Math.floor(Number(row.evidence_price_amount_minor || 0)))
        : 0,
      evidence_captured_at_ms: Math.max(0, Number(row.evidence_captured_at_ms || 0)),
      evidence_device_signature: row.evidence_device_signature != null ? String(row.evidence_device_signature || '') : '',
      evidence_verified_at_ms: Math.max(0, Number(row.evidence_verified_at_ms || 0)),
      challenge_id: row.challenge_id != null ? String(row.challenge_id || '') : '',
      challenge_nonce: row.challenge_nonce != null ? String(row.challenge_nonce || '') : '',
      challenge_mobile_terminal_id: row.challenge_mobile_terminal_id != null ? String(row.challenge_mobile_terminal_id || '') : '',
      challenge_issued_at_ms: Math.max(0, Number(row.challenge_issued_at_ms || 0)),
      challenge_expires_at_ms: Math.max(0, Number(row.challenge_expires_at_ms || 0)),
      challenge_ttl_ms: Math.max(0, Number(row.challenge_ttl_ms || 0)),
      confirm_nonce: row.confirm_nonce != null ? String(row.confirm_nonce || '') : '',
      auth_factor: row.auth_factor != null ? String(row.auth_factor || '') : '',
      authorized_at_ms: Math.max(0, Number(row.authorized_at_ms || 0)),
      committed_at_ms: Math.max(0, Number(row.committed_at_ms || 0)),
      commit_txn_id: row.commit_txn_id != null ? String(row.commit_txn_id || '') : '',
      receipt_delivery_state: this._normalizePaymentReceiptDeliveryState(row.receipt_delivery_state, 'prepared'),
      receipt_commit_deadline_at_ms: Math.max(0, Number(row.receipt_commit_deadline_at_ms || 0)),
      receipt_compensation_due_at_ms: Math.max(0, Number(row.receipt_compensation_due_at_ms || 0)),
      receipt_compensated_at_ms: Math.max(0, Number(row.receipt_compensated_at_ms || 0)),
      receipt_compensation_reason: row.receipt_compensation_reason != null ? String(row.receipt_compensation_reason || '') : '',
      two_phase_state: this._derivePaymentTwoPhaseState(row),
      approved_at_ms: Math.max(0, Number(row.authorized_at_ms || 0)),
      dispatched_at_ms: Math.max(0, Number(row.committed_at_ms || 0)),
      acked_at_ms: (
        this._normalizePaymentIntentStatus(row.status, 'prepared') === 'committed'
        || this._normalizePaymentReceiptDeliveryState(row.receipt_delivery_state, 'prepared') === 'compensated'
      )
        ? Math.max(0, Number(row.committed_at_ms || 0))
        : 0,
      abort_reason: row.abort_reason != null ? String(row.abort_reason || '') : '',
      aborted_at_ms: Math.max(0, Number(row.aborted_at_ms || 0)),
      expired_at_ms: Math.max(0, Number(row.expired_at_ms || 0)),
      expires_at_ms: Math.max(0, Number(row.expires_at_ms || 0)),
      deny_code: row.deny_code != null ? String(row.deny_code || '') : '',
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _paymentIntentDeny(deny_code, detail = {}) {
    return {
      accepted: false,
      deny_code: String(deny_code || 'payment_rejected'),
      detail: detail && typeof detail === 'object' ? detail : {},
      intent: null,
    };
  }

  _normalizePaymentIntentTtlMs(v, fallbackMs, minMs, maxMs) {
    const raw = Number(v);
    if (!Number.isFinite(raw)) return Math.max(minMs, Math.min(maxMs, Math.floor(fallbackMs)));
    return Math.max(minMs, Math.min(maxMs, Math.floor(raw)));
  }

  _normalizeEvidenceSignatureHex(signature) {
    const raw = String(signature || '').trim().toLowerCase();
    if (!raw) return '';
    let hex = raw;
    if (hex.startsWith('sha256:')) hex = hex.slice('sha256:'.length);
    if (hex.startsWith('hmac-sha256:')) hex = hex.slice('hmac-sha256:'.length);
    if (!/^[0-9a-f]{64}$/.test(hex)) return '';
    return hex;
  }

  _buildPaymentEvidenceSigningPayload({
    intent,
    device_id,
    user_id,
    app_id,
    project_id,
    evidence,
  } = {}) {
    const safeIntent = intent && typeof intent === 'object' ? intent : {};
    const safeEvidence = evidence && typeof evidence === 'object' ? evidence : {};
    return JSON.stringify({
      v: 1,
      intent_id: String(safeIntent.intent_id || ''),
      request_id: String(safeIntent.request_id || ''),
      device_id: String(device_id || ''),
      user_id: String(user_id || ''),
      app_id: String(app_id || ''),
      project_id: String(project_id || ''),
      amount_minor: Math.max(0, Math.floor(Number(safeIntent.amount_minor || 0))),
      currency: String(safeEvidence.currency || '').trim().toUpperCase(),
      merchant_id: String(safeEvidence.merchant_id || '').trim(),
      photo_hash: String(safeEvidence.photo_hash || '').trim(),
      geo_hash: String(safeEvidence.geo_hash || '').trim(),
      qr_payload_hash: String(safeEvidence.qr_payload_hash || '').trim(),
      nonce: String(safeEvidence.nonce || '').trim(),
      captured_at_ms: Math.max(0, Number(safeEvidence.captured_at_ms || 0)),
    });
  }

  _verifyPaymentEvidenceSignature({
    intent,
    device_id,
    user_id,
    app_id,
    project_id,
    evidence,
  } = {}) {
    if (!this.paymentEvidenceSignatureEnforced) {
      return { ok: true, scheme: 'disabled' };
    }
    const safeEvidence = evidence && typeof evidence === 'object' ? evidence : {};
    const normalizedSig = this._normalizeEvidenceSignatureHex(safeEvidence.device_signature);
    if (!normalizedSig) {
      return { ok: false, deny_code: 'evidence_mismatch', scheme: 'missing' };
    }
    const payload = this._buildPaymentEvidenceSigningPayload({
      intent,
      device_id,
      user_id,
      app_id,
      project_id,
      evidence: safeEvidence,
    });
    if (this.paymentEvidenceSigningSecret) {
      const expected = crypto
        .createHmac('sha256', this.paymentEvidenceSigningSecret)
        .update(payload, 'utf8')
        .digest('hex');
      if (normalizedSig !== expected) {
        return { ok: false, deny_code: 'evidence_mismatch', scheme: 'hmac_sha256' };
      }
      return { ok: true, scheme: 'hmac_sha256' };
    }
    const expected = sha256Hex(payload);
    if (normalizedSig !== expected) {
      return { ok: false, deny_code: 'evidence_mismatch', scheme: 'sha256' };
    }
    return { ok: true, scheme: 'sha256' };
  }

  _getPaymentIntentRowRaw({
    intent_id,
    device_id,
    user_id,
    app_id,
    project_id,
  }) {
    const intentId = String(intent_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    const projectId = String(project_id || '').trim();
    if (!intentId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_payment_intents
         WHERE intent_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
           AND project_id = ?
         LIMIT 1`
      )
      .get(intentId, deviceId, userId, appId, projectId) || null;
  }

  _getPaymentIntentRowRawByIntentId(intent_id) {
    const intentId = String(intent_id || '').trim();
    if (!intentId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_payment_intents
         WHERE intent_id = ?
         LIMIT 1`
      )
      .get(intentId) || null;
  }

  _getPaymentIntentRowRawByScopeRequest({
    request_id,
    device_id,
    user_id,
    app_id,
    project_id,
  }) {
    const requestId = String(request_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    const projectId = String(project_id || '').trim();
    if (!requestId || !deviceId || !appId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_payment_intents
         WHERE request_id = ?
           AND device_id = ?
           AND user_id = ?
           AND app_id = ?
           AND project_id = ?
         LIMIT 1`
      )
      .get(requestId, deviceId, userId, appId, projectId) || null;
  }

  _cleanupPaymentNonceRegistry(now = nowMs()) {
    const ts = Math.max(0, Number(now || 0));
    this.db
      .prepare(
        `DELETE FROM memory_payment_nonces
         WHERE expires_at_ms <= ?`
      )
      .run(ts);
  }

  _claimPaymentNonce({
    nonce_kind,
    nonce_value,
    intent_id,
    device_id,
    user_id,
    app_id,
    project_id,
    created_at_ms,
    expires_at_ms,
  } = {}) {
    const kind = String(nonce_kind || '').trim().toLowerCase();
    const nonceValue = String(nonce_value || '').trim();
    const intentId = String(intent_id || '').trim();
    const deviceId = String(device_id || '').trim();
    const userId = String(user_id || '').trim();
    const appId = String(app_id || '').trim();
    const projectId = String(project_id || '').trim();
    const createdAtMs = Math.max(0, Number(created_at_ms || nowMs()));
    const expiresAtMs = Math.max(createdAtMs + 1, Number(expires_at_ms || createdAtMs + 1));
    if (!kind || !nonceValue || !intentId || !deviceId || !appId) {
      return { ok: false, deny_code: 'invalid_request' };
    }

    this._cleanupPaymentNonceRegistry(createdAtMs);
    const nonceKey = `${kind}:${nonceValue}`;
    const existing = this.db
      .prepare(
        `SELECT *
         FROM memory_payment_nonces
         WHERE nonce_key = ?
         LIMIT 1`
      )
      .get(nonceKey) || null;
    if (existing) {
      return {
        ok: false,
        deny_code: 'replay_detected',
        existing_intent_id: String(existing.intent_id || ''),
      };
    }

    this.db
      .prepare(
        `INSERT INTO memory_payment_nonces(
           nonce_key, nonce_kind, nonce_value, intent_id,
           device_id, user_id, app_id, project_id,
           created_at_ms, expires_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        nonceKey,
        kind,
        nonceValue,
        intentId,
        deviceId,
        userId,
        appId,
        projectId,
        createdAtMs,
        expiresAtMs
      );

    return { ok: true };
  }

  expireStalePaymentIntents({ now_ms, limit } = {}) {
    const now = Math.max(0, Number(now_ms || nowMs()));
    const cappedLimit = Math.max(1, Math.min(500, Math.floor(Number(limit || 200))));
    const rows = this.db
      .prepare(
        `SELECT intent_id, status, challenge_expires_at_ms, expires_at_ms
         FROM memory_payment_intents
         WHERE status IN ('prepared', 'evidence_verified', 'pending_user_auth', 'authorized')
           AND (
             (expires_at_ms > 0 AND expires_at_ms <= ?)
             OR
             (status = 'pending_user_auth' AND challenge_expires_at_ms > 0 AND challenge_expires_at_ms <= ?)
           )
         ORDER BY updated_at_ms ASC
         LIMIT ?`
      )
      .all(now, now, cappedLimit);
    if (!Array.isArray(rows) || rows.length <= 0) return [];

    const updatedIds = [];
    this.db.exec('BEGIN;');
    try {
      const upd = this.db.prepare(
        `UPDATE memory_payment_intents
         SET status = 'expired',
             deny_code = ?,
             expired_at_ms = ?,
             updated_at_ms = ?
         WHERE intent_id = ?`
      );
      for (const row of rows) {
        const intentId = String(row?.intent_id || '').trim();
        if (!intentId) continue;
        const denyCode = Number(row?.challenge_expires_at_ms || 0) > 0
          && Number(row?.challenge_expires_at_ms || 0) <= now
          ? 'challenge_expired'
          : 'intent_expired';
        upd.run(denyCode, now, now, intentId);
        updatedIds.push(intentId);
      }
      this.db.exec('COMMIT;');
    } catch (err) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw err;
    }

    if (!updatedIds.length) return [];
    const out = [];
    const getById = this.db.prepare(
      `SELECT *
       FROM memory_payment_intents
       WHERE intent_id = ?
       LIMIT 1`
    );
    for (const intentId of updatedIds) {
      const row = getById.get(intentId);
      const parsed = this._parsePaymentIntentRow(row);
      if (parsed) out.push(parsed);
    }
    return out;
  }

  runPaymentReceiptCompensationWorker({ now_ms, limit } = {}) {
    const now = Math.max(0, Number(now_ms || nowMs()));
    const cappedLimit = Math.max(1, Math.min(500, Math.floor(Number(limit || 200))));
    const compensateDueAt = now + Math.max(0, Number(this.paymentReceiptCompensationDelayMs || 0));
    const promotedIds = [];
    const compensatedIds = [];
    this.db.exec('BEGIN;');
    try {
      const committedRows = this.db
        .prepare(
          `SELECT intent_id
           FROM memory_payment_intents
           WHERE status = 'committed'
             AND receipt_delivery_state = 'committed'
             AND receipt_commit_deadline_at_ms > 0
             AND receipt_commit_deadline_at_ms <= ?
           ORDER BY updated_at_ms ASC
           LIMIT ?`
        )
        .all(now, cappedLimit);
      const promoteStmt = this.db.prepare(
        `UPDATE memory_payment_intents
         SET receipt_delivery_state = 'undo_pending',
             receipt_compensation_due_at_ms = ?,
             receipt_compensation_reason = COALESCE(NULLIF(receipt_compensation_reason, ''), 'undo_window_expired'),
             updated_at_ms = ?
         WHERE intent_id = ?`
      );
      for (const row of committedRows) {
        const intentId = String(row?.intent_id || '').trim();
        if (!intentId) continue;
        promoteStmt.run(compensateDueAt, now, intentId);
        promotedIds.push(intentId);
      }

      const dueRows = this.db
        .prepare(
          `SELECT intent_id
           FROM memory_payment_intents
           WHERE status = 'committed'
             AND receipt_delivery_state = 'undo_pending'
             AND receipt_compensation_due_at_ms > 0
             AND receipt_compensation_due_at_ms <= ?
           ORDER BY updated_at_ms ASC
           LIMIT ?`
        )
        .all(now, cappedLimit);
      const compensateStmt = this.db.prepare(
        `UPDATE memory_payment_intents
         SET status = 'aborted',
             abort_reason = COALESCE(NULLIF(abort_reason, ''), COALESCE(NULLIF(receipt_compensation_reason, ''), 'receipt_compensated')),
             aborted_at_ms = COALESCE(NULLIF(aborted_at_ms, 0), ?),
             receipt_delivery_state = 'compensated',
             receipt_compensated_at_ms = ?,
             deny_code = '',
             updated_at_ms = ?
         WHERE intent_id = ?`
      );
      for (const row of dueRows) {
        const intentId = String(row?.intent_id || '').trim();
        if (!intentId) continue;
        compensateStmt.run(now, now, now, intentId);
        compensatedIds.push(intentId);
      }

      this.db.exec('COMMIT;');
    } catch (err) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw err;
    }

    if (!promotedIds.length && !compensatedIds.length) {
      return {
        promoted: [],
        compensated: [],
      };
    }
    const promoted = [];
    const compensated = [];
    const getById = this.db.prepare(
      `SELECT *
       FROM memory_payment_intents
       WHERE intent_id = ?
       LIMIT 1`
    );
    for (const intentId of promotedIds) {
      const row = getById.get(intentId);
      const parsed = this._parsePaymentIntentRow(row);
      if (parsed) promoted.push(parsed);
    }
    for (const intentId of compensatedIds) {
      const row = getById.get(intentId);
      const parsed = this._parsePaymentIntentRow(row);
      if (parsed) compensated.push(parsed);
    }
    return {
      promoted,
      compensated,
    };
  }

  createPaymentIntent(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const amountMinor = Math.floor(Number(fields.amount_minor || 0));
    const currency = String(fields.currency || '').trim().toUpperCase();
    const merchantId = String(fields.merchant_id || '').trim();
    const sourceTerminalId = String(fields.source_terminal_id || '').trim();
    const allowedMobileTerminalId = String(fields.allowed_mobile_terminal_id || '').trim();
    const expectedPhotoHash = String(fields.expected_photo_hash || '').trim();
    const expectedGeoHash = String(fields.expected_geo_hash || '').trim();
    const expectedQrPayloadHash = String(fields.expected_qr_payload_hash || '').trim();
    const createdAtMs = Math.max(0, Number(fields.created_at_ms || now));
    const ttlMs = this._normalizePaymentIntentTtlMs(fields.ttl_ms, 60 * 1000, 5 * 1000, 15 * 60 * 1000);
    const challengeTtlMs = this._normalizePaymentIntentTtlMs(fields.challenge_ttl_ms, 30 * 1000, 2 * 1000, 5 * 60 * 1000);
    const previewCard = this._buildPaymentPreviewCard({
      amount_minor: amountMinor,
      currency,
      merchant_id: merchantId,
      source_terminal_id: sourceTerminalId,
      allowed_mobile_terminal_id: allowedMobileTerminalId,
      preview_fee_minor: 0,
      preview_risk_level: 'high',
      preview_undo_window_ms: Math.max(0, Number(this.paymentReceiptUndoWindowMs || 0)),
    });

    if (!requestId || !deviceId || !appId || !currency || amountMinor <= 0) {
      return this._paymentIntentDeny('invalid_request');
    }

    const expired = this.expireStalePaymentIntents({ now_ms: now, limit: 200 });
    const existing = this._getPaymentIntentRowRawByScopeRequest({
      request_id: requestId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
    });
    if (existing) {
      return {
        accepted: true,
        created: false,
        deny_code: '',
        expired,
        intent: this._parsePaymentIntentRow(existing),
      };
    }

    const intentId = `pi_${uuid()}`;
    let expiresAtMs = createdAtMs + ttlMs;
    if (!Number.isFinite(expiresAtMs) || expiresAtMs <= now) {
      expiresAtMs = now + ttlMs;
    }

    this.db
      .prepare(
        `INSERT INTO memory_payment_intents(
           intent_id, request_id, device_id, user_id, app_id, project_id,
           status, amount_minor, currency, merchant_id, source_terminal_id, allowed_mobile_terminal_id,
           expected_photo_hash, expected_geo_hash, expected_qr_payload_hash,
           preview_fee_minor, preview_risk_level, preview_undo_window_ms, preview_card_hash,
           challenge_ttl_ms, expires_at_ms, deny_code,
           receipt_delivery_state, receipt_commit_deadline_at_ms, receipt_compensation_due_at_ms, receipt_compensated_at_ms, receipt_compensation_reason,
           created_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        intentId,
        requestId,
        deviceId,
        userId,
        appId,
        projectId,
        'prepared',
        amountMinor,
        currency,
        merchantId || null,
        sourceTerminalId || null,
        allowedMobileTerminalId || null,
        expectedPhotoHash || null,
        expectedGeoHash || null,
        expectedQrPayloadHash || null,
        previewCard.preview_fee_minor,
        previewCard.preview_risk_level,
        previewCard.preview_undo_window_ms,
        previewCard.preview_card_hash,
        challengeTtlMs,
        expiresAtMs,
        null,
        'prepared',
        0,
        0,
        0,
        null,
        createdAtMs,
        now
      );

    return {
      accepted: true,
      created: true,
      deny_code: '',
      expired,
      intent: this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      })),
    };
  }

  attachPaymentEvidence(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const intentId = String(fields.intent_id || '').trim();
    const evidence = fields.evidence && typeof fields.evidence === 'object' ? fields.evidence : {};
    const photoHash = String(evidence.photo_hash || '').trim();
    const priceAmountMinor = Math.floor(Number(evidence.price_amount_minor || 0));
    const currency = String(evidence.currency || '').trim().toUpperCase();
    const merchantId = String(evidence.merchant_id || '').trim();
    const geoHash = String(evidence.geo_hash || '').trim();
    const qrPayloadHash = String(evidence.qr_payload_hash || '').trim();
    const nonce = String(evidence.nonce || '').trim();
    const capturedAtMs = Math.max(0, Number(evidence.captured_at_ms || now));
    const deviceSignature = String(evidence.device_signature || '').trim();

    if (!requestId || !deviceId || !appId || !intentId || !currency || !nonce || priceAmountMinor <= 0) {
      return this._paymentIntentDeny('invalid_request');
    }

    const expired = this.expireStalePaymentIntents({ now_ms: now, limit: 200 });
    const row = this._getPaymentIntentRowRaw({
      intent_id: intentId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
    });
    if (!row) {
      const rowAny = this._getPaymentIntentRowRawByIntentId(intentId);
      if (rowAny) return this._paymentIntentDeny('permission_denied', { expired });
      return this._paymentIntentDeny('invalid_request', { expired });
    }

    const current = this._parsePaymentIntentRow(row);
    if (!current) return this._paymentIntentDeny('invalid_request', { expired });
    if (current.status === 'expired') return this._paymentIntentDeny('challenge_expired', { expired, intent: current });
    if (this._isPaymentIntentTerminalStatus(current.status)) {
      return this._paymentIntentDeny('intent_state_invalid', { expired, intent: current });
    }
    if (current.status !== 'prepared' && current.status !== 'evidence_verified') {
      return this._paymentIntentDeny('intent_state_invalid', { expired, intent: current });
    }

    if (priceAmountMinor !== current.amount_minor || currency !== String(current.currency || '').toUpperCase()) {
      return this._paymentIntentDeny('amount_mismatch', { expired, intent: current });
    }
    if (current.merchant_id && merchantId && merchantId !== current.merchant_id) {
      return this._paymentIntentDeny('evidence_mismatch', { expired, intent: current });
    }
    if (current.expected_photo_hash && current.expected_photo_hash !== photoHash) {
      return this._paymentIntentDeny('evidence_mismatch', { expired, intent: current });
    }
    if (current.expected_geo_hash && current.expected_geo_hash !== geoHash) {
      return this._paymentIntentDeny('evidence_mismatch', { expired, intent: current });
    }
    if (current.expected_qr_payload_hash && current.expected_qr_payload_hash !== qrPayloadHash) {
      return this._paymentIntentDeny('evidence_mismatch', { expired, intent: current });
    }
    const signatureCheck = this._verifyPaymentEvidenceSignature({
      intent: current,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
      evidence: {
        photo_hash: photoHash,
        price_amount_minor: priceAmountMinor,
        currency,
        merchant_id: merchantId,
        geo_hash: geoHash,
        qr_payload_hash: qrPayloadHash,
        nonce,
        captured_at_ms: capturedAtMs,
        device_signature: deviceSignature,
      },
    });
    if (!signatureCheck.ok) {
      return this._paymentIntentDeny(String(signatureCheck.deny_code || 'evidence_mismatch'), {
        expired,
        intent: current,
        signature_scheme: String(signatureCheck.scheme || ''),
      });
    }

    if (current.status === 'evidence_verified') {
      const sameEvidence = current.evidence_nonce === nonce
        && current.evidence_price_amount_minor === priceAmountMinor
        && String(current.evidence_currency || '').toUpperCase() === currency
        && current.evidence_photo_hash === photoHash
        && current.evidence_geo_hash === geoHash
        && current.evidence_qr_payload_hash === qrPayloadHash
        && current.evidence_merchant_id === merchantId
        && current.evidence_device_signature === deviceSignature;
      if (!sameEvidence) {
        return this._paymentIntentDeny('evidence_mismatch', { expired, intent: current });
      }
      return {
        accepted: true,
        deny_code: '',
        expired,
        signature_scheme: String(signatureCheck.scheme || ''),
        intent: current,
      };
    }

    const nonceClaim = this._claimPaymentNonce({
      nonce_kind: 'evidence',
      nonce_value: nonce,
      intent_id: intentId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
      created_at_ms: now,
      expires_at_ms: Math.max(now + 1, current.expires_at_ms || (now + 60 * 1000)),
    });
    if (!nonceClaim.ok) return this._paymentIntentDeny(String(nonceClaim.deny_code || 'replay_detected'), { expired, intent: current });

    this.db
      .prepare(
        `UPDATE memory_payment_intents
         SET status = 'evidence_verified',
             evidence_photo_hash = ?,
             evidence_geo_hash = ?,
             evidence_qr_payload_hash = ?,
             evidence_nonce = ?,
             evidence_currency = ?,
             evidence_merchant_id = ?,
             evidence_price_amount_minor = ?,
             evidence_captured_at_ms = ?,
             evidence_device_signature = ?,
             evidence_verified_at_ms = ?,
             deny_code = '',
             updated_at_ms = ?
         WHERE intent_id = ?`
      )
      .run(
        photoHash || null,
        geoHash || null,
        qrPayloadHash || null,
        nonce,
        currency,
        merchantId || null,
        priceAmountMinor,
        capturedAtMs,
        deviceSignature || null,
        now,
        now,
        intentId
      );

    return {
      accepted: true,
      deny_code: '',
      expired,
      signature_scheme: String(signatureCheck.scheme || ''),
      intent: this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      })),
    };
  }

  issuePaymentChallenge(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const intentId = String(fields.intent_id || '').trim();
    const mobileTerminalId = String(fields.mobile_terminal_id || '').trim();
    const challengeNonceInput = String(fields.challenge_nonce || '').trim();
    const issuedAtMs = Math.max(0, Number(fields.issued_at_ms || now));

    if (!requestId || !deviceId || !appId || !intentId || !mobileTerminalId) {
      return {
        issued: false,
        deny_code: 'invalid_request',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: null,
        expired: [],
      };
    }

    const expired = this.expireStalePaymentIntents({ now_ms: now, limit: 200 });
    const row = this._getPaymentIntentRowRaw({
      intent_id: intentId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
    });
    if (!row) {
      const rowAny = this._getPaymentIntentRowRawByIntentId(intentId);
      return {
        issued: false,
        deny_code: rowAny ? 'permission_denied' : 'invalid_request',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: null,
        expired,
      };
    }

    const current = this._parsePaymentIntentRow(row);
    if (!current) {
      return {
        issued: false,
        deny_code: 'invalid_request',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: null,
        expired,
      };
    }
    if (current.status === 'expired') {
      return {
        issued: false,
        deny_code: 'challenge_expired',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: current,
        expired,
      };
    }
    if (this._isPaymentIntentTerminalStatus(current.status)) {
      return {
        issued: false,
        deny_code: 'intent_state_invalid',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: current,
        expired,
      };
    }
    if (current.status !== 'evidence_verified' && current.status !== 'pending_user_auth') {
      return {
        issued: false,
        deny_code: 'intent_state_invalid',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: current,
        expired,
      };
    }
    if (current.allowed_mobile_terminal_id && current.allowed_mobile_terminal_id !== mobileTerminalId) {
      return {
        issued: false,
        deny_code: 'terminal_not_allowed',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: current,
        expired,
      };
    }
    if (current.status === 'pending_user_auth' && current.challenge_expires_at_ms > now) {
      const boundTerminal = current.challenge_mobile_terminal_id || current.allowed_mobile_terminal_id;
      if (!boundTerminal || boundTerminal === mobileTerminalId) {
        return {
          issued: true,
          deny_code: '',
          challenge_id: current.challenge_id,
          challenge_nonce: current.challenge_nonce,
          expires_at_ms: current.challenge_expires_at_ms,
          intent: current,
          expired,
        };
      }
      return {
        issued: false,
        deny_code: 'terminal_not_allowed',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: current,
        expired,
      };
    }

    const challengeTtlMs = this._normalizePaymentIntentTtlMs(
      current.challenge_ttl_ms,
      30 * 1000,
      2 * 1000,
      5 * 60 * 1000
    );
    const challengeId = `pch_${uuid()}`;
    const challengeNonce = challengeNonceInput || `nonce_${uuid()}`;
    let challengeExpiresAtMs = issuedAtMs + challengeTtlMs;
    if (current.expires_at_ms > 0) {
      challengeExpiresAtMs = Math.min(challengeExpiresAtMs, current.expires_at_ms);
    }
    if (challengeExpiresAtMs <= now) {
      this.db
        .prepare(
          `UPDATE memory_payment_intents
           SET status = 'expired', deny_code = 'challenge_expired', expired_at_ms = ?, updated_at_ms = ?
           WHERE intent_id = ?`
        )
        .run(now, now, intentId);
      const expiredRow = this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      }));
      return {
        issued: false,
        deny_code: 'challenge_expired',
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: expiredRow,
        expired: expiredRow ? [...expired, expiredRow] : expired,
      };
    }

    const challengeClaim = this._claimPaymentNonce({
      nonce_kind: 'challenge',
      nonce_value: challengeNonce,
      intent_id: intentId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
      created_at_ms: now,
      expires_at_ms: challengeExpiresAtMs,
    });
    if (!challengeClaim.ok) {
      return {
        issued: false,
        deny_code: String(challengeClaim.deny_code || 'replay_detected'),
        challenge_id: '',
        challenge_nonce: '',
        expires_at_ms: 0,
        intent: current,
        expired,
      };
    }

    this.db
      .prepare(
        `UPDATE memory_payment_intents
         SET status = 'pending_user_auth',
             allowed_mobile_terminal_id = ?,
             challenge_id = ?,
             challenge_nonce = ?,
             challenge_mobile_terminal_id = ?,
             challenge_issued_at_ms = ?,
             challenge_expires_at_ms = ?,
             challenge_ttl_ms = ?,
             deny_code = '',
             updated_at_ms = ?
         WHERE intent_id = ?`
      )
      .run(
        current.allowed_mobile_terminal_id || mobileTerminalId,
        challengeId,
        challengeNonce,
        mobileTerminalId,
        issuedAtMs,
        challengeExpiresAtMs,
        challengeTtlMs,
        now,
        intentId
      );

    return {
      issued: true,
      deny_code: '',
      challenge_id: challengeId,
      challenge_nonce: challengeNonce,
      expires_at_ms: challengeExpiresAtMs,
      intent: this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      })),
      expired,
    };
  }

  confirmPaymentIntent(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const intentId = String(fields.intent_id || '').trim();
    const challengeId = String(fields.challenge_id || '').trim();
    const mobileTerminalId = String(fields.mobile_terminal_id || '').trim();
    const authFactor = String(fields.auth_factor || '').trim() || 'tap_only';
    const confirmNonce = String(fields.confirm_nonce || '').trim();
    const confirmedAtMs = Math.max(0, Number(fields.confirmed_at_ms || now));

    if (!requestId || !deviceId || !appId || !intentId || !challengeId || !mobileTerminalId || !confirmNonce) {
      return {
        committed: false,
        idempotent: false,
        deny_code: 'invalid_request',
        intent: null,
        expired: [],
      };
    }

    const expired = this.expireStalePaymentIntents({ now_ms: now, limit: 200 });
    const row = this._getPaymentIntentRowRaw({
      intent_id: intentId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
    });
    if (!row) {
      const rowAny = this._getPaymentIntentRowRawByIntentId(intentId);
      return {
        committed: false,
        idempotent: false,
        deny_code: rowAny ? 'permission_denied' : 'invalid_request',
        intent: null,
        expired,
      };
    }

    const current = this._parsePaymentIntentRow(row);
    if (!current) {
      return {
        committed: false,
        idempotent: false,
        deny_code: 'invalid_request',
        intent: null,
        expired,
      };
    }

    const recomputedPreview = this._buildPaymentPreviewCard(current);
    if (!current.preview_card_hash || current.preview_card_hash !== recomputedPreview.preview_card_hash) {
      return {
        committed: false,
        idempotent: false,
        deny_code: 'request_tampered',
        intent: current,
        expired,
      };
    }

    if (current.status === 'committed') {
      if (current.receipt_delivery_state === 'undo_pending') {
        return {
          committed: false,
          idempotent: false,
          deny_code: 'intent_state_invalid',
          intent: current,
          expired,
        };
      }
      if (current.challenge_id && current.challenge_id !== challengeId) {
        return {
          committed: false,
          idempotent: false,
          deny_code: 'invalid_request',
          intent: current,
          expired,
        };
      }
      const committedBoundTerminal = current.challenge_mobile_terminal_id || current.allowed_mobile_terminal_id;
      if (committedBoundTerminal && committedBoundTerminal !== mobileTerminalId) {
        return {
          committed: false,
          idempotent: false,
          deny_code: 'terminal_not_allowed',
          intent: current,
          expired,
        };
      }
      if (current.confirm_nonce && current.confirm_nonce === confirmNonce) {
        return {
          committed: true,
          idempotent: true,
          deny_code: '',
          intent: current,
          expired,
        };
      }
      return {
        committed: false,
        idempotent: false,
        deny_code: 'intent_state_invalid',
        intent: current,
        expired,
      };
    }
    if (current.status === 'expired') {
      return {
        committed: false,
        idempotent: false,
        deny_code: 'challenge_expired',
        intent: current,
        expired,
      };
    }
    if (current.status === 'aborted') {
      return {
        committed: false,
        idempotent: false,
        deny_code: 'intent_state_invalid',
        intent: current,
        expired,
      };
    }
    if (current.status !== 'pending_user_auth' && current.status !== 'authorized') {
      return {
        committed: false,
        idempotent: false,
        deny_code: 'intent_state_invalid',
        intent: current,
        expired,
      };
    }
    if (!current.challenge_id || current.challenge_id !== challengeId) {
      return {
        committed: false,
        idempotent: false,
        deny_code: 'invalid_request',
        intent: current,
        expired,
      };
    }
    const boundTerminal = current.challenge_mobile_terminal_id || current.allowed_mobile_terminal_id;
    if (boundTerminal && boundTerminal !== mobileTerminalId) {
      return {
        committed: false,
        idempotent: false,
        deny_code: 'terminal_not_allowed',
        intent: current,
        expired,
      };
    }
    if ((current.challenge_expires_at_ms > 0 && current.challenge_expires_at_ms <= confirmedAtMs)
        || (current.expires_at_ms > 0 && current.expires_at_ms <= confirmedAtMs)) {
      this.db
        .prepare(
          `UPDATE memory_payment_intents
           SET status = 'expired', deny_code = 'challenge_expired', expired_at_ms = ?, updated_at_ms = ?
           WHERE intent_id = ?`
        )
        .run(now, now, intentId);
      const expiredRow = this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      }));
      return {
        committed: false,
        idempotent: false,
        deny_code: 'challenge_expired',
        intent: expiredRow,
        expired: expiredRow ? [...expired, expiredRow] : expired,
      };
    }

    const claim = this._claimPaymentNonce({
      nonce_kind: 'confirm',
      nonce_value: confirmNonce,
      intent_id: intentId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
      created_at_ms: confirmedAtMs,
      expires_at_ms: Math.max(confirmedAtMs + 1, current.expires_at_ms || (confirmedAtMs + 5 * 60 * 1000)),
    });
    if (!claim.ok) {
      const latest = this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      }));
      if (latest && latest.status === 'committed' && latest.confirm_nonce === confirmNonce) {
        if (latest.receipt_delivery_state === 'undo_pending') {
          return {
            committed: false,
            idempotent: false,
            deny_code: 'intent_state_invalid',
            intent: latest,
            expired,
          };
        }
        if (latest.challenge_id && latest.challenge_id !== challengeId) {
          return {
            committed: false,
            idempotent: false,
            deny_code: 'invalid_request',
            intent: latest,
            expired,
          };
        }
        const latestBoundTerminal = latest.challenge_mobile_terminal_id || latest.allowed_mobile_terminal_id;
        if (latestBoundTerminal && latestBoundTerminal !== mobileTerminalId) {
          return {
            committed: false,
            idempotent: false,
            deny_code: 'terminal_not_allowed',
            intent: latest,
            expired,
          };
        }
        return {
          committed: true,
          idempotent: true,
          deny_code: '',
          intent: latest,
          expired,
        };
      }
      return {
        committed: false,
        idempotent: false,
        deny_code: String(claim.deny_code || 'replay_detected'),
        intent: latest || current,
        expired,
      };
    }

    const commitTxnId = current.commit_txn_id || `pay_${uuid()}`;
    const receiptCommitDeadlineAtMs = confirmedAtMs + Math.max(0, Number(this.paymentReceiptUndoWindowMs || 0));
    this.db.exec('BEGIN;');
    try {
      this.db
        .prepare(
          `UPDATE memory_payment_intents
           SET status = 'authorized',
               auth_factor = ?,
               authorized_at_ms = COALESCE(NULLIF(authorized_at_ms, 0), ?),
               deny_code = '',
               updated_at_ms = ?
           WHERE intent_id = ?`
        )
        .run(authFactor, confirmedAtMs, now, intentId);
      this.db
        .prepare(
          `UPDATE memory_payment_intents
           SET status = 'committed',
               confirm_nonce = ?,
               committed_at_ms = COALESCE(NULLIF(committed_at_ms, 0), ?),
               commit_txn_id = ?,
               receipt_delivery_state = 'committed',
               receipt_commit_deadline_at_ms = ?,
               receipt_compensation_due_at_ms = 0,
               receipt_compensated_at_ms = 0,
               receipt_compensation_reason = NULL,
               deny_code = '',
               updated_at_ms = ?
           WHERE intent_id = ?`
        )
        .run(confirmNonce, confirmedAtMs, commitTxnId, receiptCommitDeadlineAtMs, now, intentId);
      this.db.exec('COMMIT;');
    } catch (err) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw err;
    }

    return {
      committed: true,
      idempotent: false,
      deny_code: '',
      intent: this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      })),
      expired,
    };
  }

  abortPaymentIntent(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const intentId = String(fields.intent_id || '').trim();
    const reason = String(fields.reason || '').trim();
    const abortedAtMs = Math.max(0, Number(fields.aborted_at_ms || now));

    if (!requestId || !deviceId || !appId || !intentId) {
      return {
        aborted: false,
        idempotent: false,
        deny_code: 'invalid_request',
        intent: null,
        expired: [],
      };
    }

    const expired = this.expireStalePaymentIntents({ now_ms: now, limit: 200 });
    const row = this._getPaymentIntentRowRaw({
      intent_id: intentId,
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
    });
    if (!row) {
      const rowAny = this._getPaymentIntentRowRawByIntentId(intentId);
      return {
        aborted: false,
        idempotent: false,
        deny_code: rowAny ? 'permission_denied' : 'invalid_request',
        intent: null,
        expired,
      };
    }

    const current = this._parsePaymentIntentRow(row);
    if (!current) {
      return {
        aborted: false,
        idempotent: false,
        deny_code: 'invalid_request',
        intent: null,
        expired,
      };
    }
    if (current.status === 'aborted') {
      return {
        aborted: true,
        idempotent: true,
        deny_code: '',
        intent: current,
        expired,
      };
    }
    if (current.status === 'committed') {
      if (current.receipt_delivery_state === 'compensated') {
        return {
          aborted: true,
          idempotent: true,
          deny_code: '',
          intent: current,
          expired,
        };
      }
      if (current.receipt_delivery_state === 'undo_pending') {
        return {
          aborted: true,
          idempotent: true,
          deny_code: '',
          intent: current,
          expired,
        };
      }
      const undoDeadline = Math.max(
        0,
        Number(current.receipt_commit_deadline_at_ms || 0),
        Number(current.committed_at_ms || 0) + Math.max(0, Number(this.paymentReceiptUndoWindowMs || 0))
      );
      if (undoDeadline > 0 && abortedAtMs > undoDeadline) {
        return {
          aborted: false,
          idempotent: false,
          deny_code: 'intent_state_invalid',
          intent: current,
          expired,
        };
      }
      const compensateDueAtMs = abortedAtMs + Math.max(0, Number(this.paymentReceiptCompensationDelayMs || 0));
      this.db
        .prepare(
          `UPDATE memory_payment_intents
           SET receipt_delivery_state = 'undo_pending',
               receipt_compensation_due_at_ms = ?,
               receipt_compensation_reason = ?,
               updated_at_ms = ?
           WHERE intent_id = ?`
        )
        .run(compensateDueAtMs, reason || 'user_abort', now, intentId);
      return {
        aborted: true,
        idempotent: false,
        deny_code: '',
        intent: this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
          intent_id: intentId,
          device_id: deviceId,
          user_id: userId,
          app_id: appId,
          project_id: projectId,
        })),
        expired,
      };
    }
    if (current.status === 'expired') {
      return {
        aborted: false,
        idempotent: true,
        deny_code: 'challenge_expired',
        intent: current,
        expired,
      };
    }

    this.db
      .prepare(
        `UPDATE memory_payment_intents
         SET status = 'aborted',
             abort_reason = ?,
             aborted_at_ms = ?,
             deny_code = '',
             updated_at_ms = ?
         WHERE intent_id = ?`
      )
      .run(reason || null, abortedAtMs, now, intentId);

    return {
      aborted: true,
      idempotent: false,
      deny_code: '',
      intent: this._parsePaymentIntentRow(this._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      })),
      expired,
    };
  }

  _normalizeRiskTuningProfile(raw = {}, fallbackProfileId = '') {
    const src = raw && typeof raw === 'object' ? raw : {};
    const fallback = defaultRiskTuningProfile(0);
    const profileId = String(src.profile_id || fallbackProfileId || '').trim();
    if (!profileId || !/^[A-Za-z0-9._:-]{3,128}$/.test(profileId)) return null;

    const parseNumber = (value, fallbackValue, min, max) => {
      if (value == null || value === '') return Number(fallbackValue);
      const n = Number(value);
      if (!Number.isFinite(n)) return null;
      if (n < min || n > max) return null;
      return n;
    };

    const now = nowMs();
    const out = {
      profile_id: profileId,
      profile_label: String(src.profile_label || '').trim() || profileId,
      vector_weight: parseNumber(src.vector_weight, fallback.vector_weight, 0, 10),
      text_weight: parseNumber(src.text_weight, fallback.text_weight, 0, 10),
      recency_weight: parseNumber(src.recency_weight, fallback.recency_weight, 0, 10),
      risk_weight: parseNumber(src.risk_weight, fallback.risk_weight, 0, 10),
      risk_penalty_low: parseNumber(src.risk_penalty_low, fallback.risk_penalty_low, 0, 10),
      risk_penalty_medium: parseNumber(src.risk_penalty_medium, fallback.risk_penalty_medium, 0, 10),
      risk_penalty_high: parseNumber(src.risk_penalty_high, fallback.risk_penalty_high, 0, 10),
      recall_floor: parseNumber(src.recall_floor, fallback.recall_floor, 0, 1),
      latency_ceiling_ratio: parseNumber(src.latency_ceiling_ratio, fallback.latency_ceiling_ratio, 0.01, 100),
      block_precision_floor: parseNumber(src.block_precision_floor, fallback.block_precision_floor, 0, 1),
      max_recall_drop: parseNumber(src.max_recall_drop, fallback.max_recall_drop, 0, 1),
      max_latency_ratio_increase: parseNumber(src.max_latency_ratio_increase, fallback.max_latency_ratio_increase, 0, 100),
      max_block_precision_drop: parseNumber(src.max_block_precision_drop, fallback.max_block_precision_drop, 0, 1),
      max_online_offline_drift: parseNumber(src.max_online_offline_drift, fallback.max_online_offline_drift, 0, 100),
      created_at_ms: Math.max(0, Number(src.created_at_ms || now)),
      updated_at_ms: Math.max(0, Number(src.updated_at_ms || now)),
    };
    if (Object.values(out).some((v) => v === null)) return null;
    if (!(out.risk_penalty_low <= out.risk_penalty_medium && out.risk_penalty_medium <= out.risk_penalty_high)) return null;
    return out;
  }

  _normalizeRiskTuningMetrics(raw = null) {
    if (!raw || typeof raw !== 'object') return null;
    const recall = Number(raw.recall);
    const latency = Number(raw.p95_latency_ratio);
    const precision = Number(raw.block_precision);
    const meanScore = Number(raw.mean_final_score);
    if (!Number.isFinite(recall) || recall < 0 || recall > 1) return null;
    if (!Number.isFinite(latency) || latency < 0) return null;
    if (!Number.isFinite(precision) || precision < 0 || precision > 1) return null;
    if (!Number.isFinite(meanScore)) return null;
    return {
      recall,
      p95_latency_ratio: latency,
      block_precision: precision,
      mean_final_score: meanScore,
    };
  }

  _parseRiskTuningProfileRow(row) {
    if (!row) return null;
    const parsed = this._safeJsonParse(row.profile_json, null);
    const normalized = this._normalizeRiskTuningProfile(
      parsed && typeof parsed === 'object' ? parsed : {},
      String(row.profile_id || '')
    );
    if (!normalized) return null;
    return {
      ...normalized,
      status: String(row.status || 'candidate'),
      previous_profile_id: row.previous_profile_id != null ? String(row.previous_profile_id || '') : '',
      last_evaluation_id: row.last_evaluation_id != null ? String(row.last_evaluation_id || '') : '',
      promoted_at_ms: Math.max(0, Number(row.promoted_at_ms || 0)),
      rolled_back_at_ms: Math.max(0, Number(row.rolled_back_at_ms || 0)),
      rollback_reason: row.rollback_reason != null ? String(row.rollback_reason || '') : '',
      created_at_ms: Math.max(0, Number(row.created_at_ms || normalized.created_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || normalized.updated_at_ms || 0)),
    };
  }

  _parseRiskTuningEvaluationRow(row) {
    if (!row) return null;
    return {
      evaluation_id: String(row.evaluation_id || ''),
      request_id: row.request_id != null ? String(row.request_id || '') : '',
      profile_id: String(row.profile_id || ''),
      baseline_profile_id: row.baseline_profile_id != null ? String(row.baseline_profile_id || '') : '',
      baseline_metrics: this._safeJsonParse(row.baseline_metrics_json, null),
      holdout_metrics: this._safeJsonParse(row.holdout_metrics_json, null),
      online_metrics: this._safeJsonParse(row.online_metrics_json, null),
      offline_metrics: this._safeJsonParse(row.offline_metrics_json, null),
      accepted: !!Number(row.accepted || 0),
      holdout_passed: !!Number(row.holdout_passed || 0),
      rollback_triggered: !!Number(row.rollback_triggered || 0),
      rollback_to_profile_id: row.rollback_to_profile_id != null ? String(row.rollback_to_profile_id || '') : '',
      deny_code: row.deny_code != null ? String(row.deny_code || '') : '',
      decision: String(row.decision || ''),
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
    };
  }

  _getRiskTuningStateRowRaw() {
    return this.db
      .prepare(
        `SELECT *
         FROM memory_risk_tuning_state
         WHERE state_id = 1
         LIMIT 1`
      )
      .get() || null;
  }

  _getRiskTuningProfileRowRaw(profile_id) {
    const profileId = String(profile_id || '').trim();
    if (!profileId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_risk_tuning_profiles
         WHERE profile_id = ?
         LIMIT 1`
      )
      .get(profileId) || null;
  }

  _getLatestRiskTuningEvaluationRowRaw(profile_id) {
    const profileId = String(profile_id || '').trim();
    if (!profileId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_risk_tuning_evaluations
         WHERE profile_id = ?
         ORDER BY created_at_ms DESC
         LIMIT 1`
      )
      .get(profileId) || null;
  }

  _ensureDefaultRiskTuningProfile() {
    const state = this._getRiskTuningStateRowRaw();
    if (state && this._getRiskTuningProfileRowRaw(String(state.active_profile_id || ''))) {
      return;
    }
    const now = nowMs();
    const baseline = defaultRiskTuningProfile(now);
    this.db.exec('BEGIN;');
    try {
      const exists = this._getRiskTuningProfileRowRaw(DEFAULT_RISK_TUNING_PROFILE_ID);
      if (!exists) {
        this.db
          .prepare(
            `INSERT INTO memory_risk_tuning_profiles(
               profile_id, profile_json, status, previous_profile_id, last_evaluation_id,
               created_at_ms, updated_at_ms, promoted_at_ms, rolled_back_at_ms, rollback_reason
             ) VALUES(?,?,?,?,?,?,?,?,?,?)`
          )
          .run(
            baseline.profile_id,
            JSON.stringify(baseline),
            'active',
            null,
            null,
            baseline.created_at_ms,
            baseline.updated_at_ms,
            baseline.created_at_ms,
            null,
            null
          );
      } else {
        this.db
          .prepare(
            `UPDATE memory_risk_tuning_profiles
             SET status = 'active',
                 updated_at_ms = ?
             WHERE profile_id = ?`
          )
          .run(now, DEFAULT_RISK_TUNING_PROFILE_ID);
      }

      const nextState = this._getRiskTuningStateRowRaw();
      if (!nextState) {
        this.db
          .prepare(
            `INSERT INTO memory_risk_tuning_state(state_id, active_profile_id, stable_profile_id, updated_at_ms)
             VALUES(1, ?, ?, ?)`
          )
          .run(DEFAULT_RISK_TUNING_PROFILE_ID, DEFAULT_RISK_TUNING_PROFILE_ID, now);
      } else {
        this.db
          .prepare(
            `UPDATE memory_risk_tuning_state
             SET active_profile_id = ?,
                 stable_profile_id = COALESCE(stable_profile_id, ?),
                 updated_at_ms = ?
             WHERE state_id = 1`
          )
          .run(
            DEFAULT_RISK_TUNING_PROFILE_ID,
            DEFAULT_RISK_TUNING_PROFILE_ID,
            now
          );
      }
      this.db.exec('COMMIT;');
    } catch (err) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw err;
    }
  }

  getRiskTuningProfileSnapshot({ profile_id } = {}) {
    this._ensureDefaultRiskTuningProfile();
    const state = this._getRiskTuningStateRowRaw();
    const activeProfileId = String(state?.active_profile_id || DEFAULT_RISK_TUNING_PROFILE_ID);
    const stableProfileId = String(state?.stable_profile_id || activeProfileId);
    const requestedProfileId = String(profile_id || '').trim();
    const targetProfileId = requestedProfileId || activeProfileId;
    const profile = this._parseRiskTuningProfileRow(this._getRiskTuningProfileRowRaw(targetProfileId));
    const latestEval = this._parseRiskTuningEvaluationRow(this._getLatestRiskTuningEvaluationRowRaw(targetProfileId));
    return {
      active_profile_id: activeProfileId,
      stable_profile_id: stableProfileId,
      profile: profile || this._parseRiskTuningProfileRow(this._getRiskTuningProfileRowRaw(activeProfileId)),
      latest_evaluation: latestEval,
    };
  }

  _upsertRiskTuningProfile(profile, { status = 'candidate', previous_profile_id = null, last_evaluation_id = null, promoted_at_ms = null, rolled_back_at_ms = null, rollback_reason = null } = {}) {
    const normalized = this._normalizeRiskTuningProfile(profile, String(profile?.profile_id || ''));
    if (!normalized) return null;
    const now = nowMs();
    const existing = this._getRiskTuningProfileRowRaw(normalized.profile_id);
    if (existing) {
      this.db
        .prepare(
          `UPDATE memory_risk_tuning_profiles
           SET profile_json = ?,
               status = ?,
               previous_profile_id = ?,
               last_evaluation_id = ?,
               promoted_at_ms = ?,
               rolled_back_at_ms = ?,
               rollback_reason = ?,
               updated_at_ms = ?
           WHERE profile_id = ?`
        )
        .run(
          JSON.stringify(normalized),
          String(status || 'candidate'),
          previous_profile_id || null,
          last_evaluation_id || null,
          promoted_at_ms || null,
          rolled_back_at_ms || null,
          rollback_reason || null,
          now,
          normalized.profile_id
        );
    } else {
      this.db
        .prepare(
          `INSERT INTO memory_risk_tuning_profiles(
             profile_id, profile_json, status, previous_profile_id, last_evaluation_id,
             created_at_ms, updated_at_ms, promoted_at_ms, rolled_back_at_ms, rollback_reason
           ) VALUES(?,?,?,?,?,?,?,?,?,?)`
        )
        .run(
          normalized.profile_id,
          JSON.stringify(normalized),
          String(status || 'candidate'),
          previous_profile_id || null,
          last_evaluation_id || null,
          Math.max(0, Number(normalized.created_at_ms || now)),
          now,
          promoted_at_ms || null,
          rolled_back_at_ms || null,
          rollback_reason || null
        );
    }
    return this._parseRiskTuningProfileRow(this._getRiskTuningProfileRowRaw(normalized.profile_id));
  }

  rollbackRiskTuningProfile({ reason = '' } = {}) {
    this._ensureDefaultRiskTuningProfile();
    const state = this._getRiskTuningStateRowRaw();
    const activeProfileId = String(state?.active_profile_id || '');
    const stableProfileId = String(state?.stable_profile_id || '');
    if (!activeProfileId || !stableProfileId || activeProfileId === stableProfileId) {
      return {
        rolled_back: false,
        from_profile_id: activeProfileId,
        to_profile_id: stableProfileId || activeProfileId,
      };
    }

    const stableProfile = this._getRiskTuningProfileRowRaw(stableProfileId);
    if (!stableProfile) {
      return {
        rolled_back: false,
        from_profile_id: activeProfileId,
        to_profile_id: stableProfileId,
      };
    }

    const now = nowMs();
    this.db.exec('BEGIN;');
    try {
      this.db
        .prepare(
          `UPDATE memory_risk_tuning_profiles
           SET status = 'rolled_back',
               rolled_back_at_ms = ?,
               rollback_reason = ?,
               updated_at_ms = ?
           WHERE profile_id = ?`
        )
        .run(now, String(reason || 'constraints_violated'), now, activeProfileId);
      this.db
        .prepare(
          `UPDATE memory_risk_tuning_profiles
           SET status = 'active',
               rollback_reason = NULL,
               updated_at_ms = ?
           WHERE profile_id = ?`
        )
        .run(now, stableProfileId);
      this.db
        .prepare(
          `UPDATE memory_risk_tuning_state
           SET active_profile_id = ?,
               stable_profile_id = ?,
               updated_at_ms = ?
           WHERE state_id = 1`
        )
        .run(stableProfileId, stableProfileId, now);
      this.db.exec('COMMIT;');
      return {
        rolled_back: true,
        from_profile_id: activeProfileId,
        to_profile_id: stableProfileId,
      };
    } catch (err) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw err;
    }
  }

  evaluateRiskTuningProfile(fields = {}) {
    this._ensureDefaultRiskTuningProfile();
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    if (requestId) {
      const prior = this.db
        .prepare(
          `SELECT *
           FROM memory_risk_tuning_evaluations
           WHERE request_id = ?
           LIMIT 1`
        )
        .get(requestId);
      if (prior) {
        return this._parseRiskTuningEvaluationRow(prior);
      }
    }

    const state = this._getRiskTuningStateRowRaw();
    const activeProfileId = String(state?.active_profile_id || DEFAULT_RISK_TUNING_PROFILE_ID);
    const suppliedProfileId = String(fields?.profile?.profile_id || '').trim();
    const normalizedProfile = this._normalizeRiskTuningProfile(fields.profile || {}, suppliedProfileId);
    const baselineMetrics = this._normalizeRiskTuningMetrics(fields.baseline_metrics);
    const holdoutMetrics = this._normalizeRiskTuningMetrics(fields.holdout_metrics);
    const onlineMetrics = this._normalizeRiskTuningMetrics(fields.online_metrics);
    const offlineMetrics = this._normalizeRiskTuningMetrics(fields.offline_metrics);
    const autoRollback = !!fields.auto_rollback_on_violation;

    let profileId = suppliedProfileId;
    if (normalizedProfile) profileId = normalizedProfile.profile_id;
    let denyCode = '';
    let holdoutPassed = true;
    let accepted = true;
    let decision = 'ready_for_promotion';
    let rollbackTriggered = false;
    let rollbackToProfileId = '';

    if (!normalizedProfile) {
      accepted = false;
      holdoutPassed = false;
      denyCode = 'profile_invalid';
      decision = 'blocked';
    }

    if (accepted) {
      this._upsertRiskTuningProfile(normalizedProfile, { status: profileId === activeProfileId ? 'active' : 'candidate' });
      if (!baselineMetrics || !holdoutMetrics) {
        accepted = false;
        holdoutPassed = false;
        denyCode = 'holdout_regression';
      } else {
        const recallFloorPass = holdoutMetrics.recall >= normalizedProfile.recall_floor;
        const latencyCeilingPass = holdoutMetrics.p95_latency_ratio <= normalizedProfile.latency_ceiling_ratio;
        const precisionFloorPass = holdoutMetrics.block_precision >= normalizedProfile.block_precision_floor;
        const recallDeltaPass = holdoutMetrics.recall + normalizedProfile.max_recall_drop >= baselineMetrics.recall;
        const latencyDeltaPass = holdoutMetrics.p95_latency_ratio <= (baselineMetrics.p95_latency_ratio + normalizedProfile.max_latency_ratio_increase);
        const precisionDeltaPass = holdoutMetrics.block_precision + normalizedProfile.max_block_precision_drop >= baselineMetrics.block_precision;
        holdoutPassed = recallFloorPass && latencyCeilingPass && precisionFloorPass && recallDeltaPass && latencyDeltaPass && precisionDeltaPass;
        if (!holdoutPassed) {
          accepted = false;
          denyCode = 'holdout_regression';
        }
      }
    }

    if (accepted && (!onlineMetrics || !offlineMetrics)) {
      accepted = false;
      denyCode = 'metrics_missing';
    }

    if (accepted && onlineMetrics && offlineMetrics) {
      const drift = Math.abs(onlineMetrics.mean_final_score - offlineMetrics.mean_final_score);
      const onlineWithinFloor = onlineMetrics.recall >= normalizedProfile.recall_floor
        && onlineMetrics.p95_latency_ratio <= normalizedProfile.latency_ceiling_ratio
        && onlineMetrics.block_precision >= normalizedProfile.block_precision_floor;
      const offlineWithinFloor = offlineMetrics.recall >= normalizedProfile.recall_floor
        && offlineMetrics.p95_latency_ratio <= normalizedProfile.latency_ceiling_ratio
        && offlineMetrics.block_precision >= normalizedProfile.block_precision_floor;
      if (drift > normalizedProfile.max_online_offline_drift || !onlineWithinFloor || !offlineWithinFloor) {
        accepted = false;
        denyCode = drift > normalizedProfile.max_online_offline_drift ? 'online_drift_exceeded' : 'constraints_violated';
      }
    }

    if (!accepted) {
      decision = 'blocked';
      if (profileId && profileId !== activeProfileId) {
        this.db
          .prepare(
            `UPDATE memory_risk_tuning_profiles
             SET status = 'rejected',
                 rollback_reason = ?,
                 updated_at_ms = ?
             WHERE profile_id = ?`
          )
          .run(denyCode || 'constraints_violated', now, profileId);
      }
      if (autoRollback && profileId && profileId === activeProfileId) {
        const rollback = this.rollbackRiskTuningProfile({ reason: denyCode || 'constraints_violated' });
        rollbackTriggered = !!rollback.rolled_back;
        rollbackToProfileId = String(rollback.to_profile_id || '');
        if (rollbackTriggered) {
          decision = 'rollback_triggered';
        }
      }
    }

    const evaluationId = `risk_eval_${uuid()}`;
    this.db
      .prepare(
        `INSERT INTO memory_risk_tuning_evaluations(
           evaluation_id, request_id, profile_id, baseline_profile_id,
           baseline_metrics_json, holdout_metrics_json, online_metrics_json, offline_metrics_json,
           accepted, holdout_passed, rollback_triggered, rollback_to_profile_id,
           deny_code, decision, created_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        evaluationId,
        requestId || null,
        profileId || '',
        activeProfileId || null,
        baselineMetrics ? JSON.stringify(baselineMetrics) : null,
        holdoutMetrics ? JSON.stringify(holdoutMetrics) : null,
        onlineMetrics ? JSON.stringify(onlineMetrics) : null,
        offlineMetrics ? JSON.stringify(offlineMetrics) : null,
        accepted ? 1 : 0,
        holdoutPassed ? 1 : 0,
        rollbackTriggered ? 1 : 0,
        rollbackToProfileId || null,
        denyCode || null,
        decision,
        now
      );

    if (profileId) {
      this.db
        .prepare(
          `UPDATE memory_risk_tuning_profiles
           SET last_evaluation_id = ?,
               updated_at_ms = ?
           WHERE profile_id = ?`
        )
        .run(evaluationId, now, profileId);
    }

    return this._parseRiskTuningEvaluationRow(
      this.db
        .prepare(
          `SELECT *
           FROM memory_risk_tuning_evaluations
           WHERE evaluation_id = ?
           LIMIT 1`
        )
        .get(evaluationId)
    );
  }

  promoteRiskTuningProfile(fields = {}) {
    this._ensureDefaultRiskTuningProfile();
    const now = nowMs();
    const profileId = String(fields.profile_id || '').trim();
    const expectedActiveProfileId = String(fields.expected_active_profile_id || '').trim();
    const rollbackOnViolation = !!fields.rollback_on_violation;
    const state = this._getRiskTuningStateRowRaw();
    const activeProfileId = String(state?.active_profile_id || DEFAULT_RISK_TUNING_PROFILE_ID);
    const stableProfileId = String(state?.stable_profile_id || activeProfileId);

    if (!profileId) {
      return {
        promoted: false,
        rollback_triggered: false,
        active_profile_id: activeProfileId,
        previous_active_profile_id: activeProfileId,
        deny_code: 'profile_invalid',
      };
    }
    if (expectedActiveProfileId && expectedActiveProfileId !== activeProfileId) {
      return {
        promoted: false,
        rollback_triggered: false,
        active_profile_id: activeProfileId,
        previous_active_profile_id: activeProfileId,
        deny_code: 'active_profile_mismatch',
      };
    }

    const targetProfile = this._parseRiskTuningProfileRow(this._getRiskTuningProfileRowRaw(profileId));
    if (!targetProfile) {
      return {
        promoted: false,
        rollback_triggered: false,
        active_profile_id: activeProfileId,
        previous_active_profile_id: activeProfileId,
        deny_code: 'profile_invalid',
      };
    }

    const latestEval = this._parseRiskTuningEvaluationRow(this._getLatestRiskTuningEvaluationRowRaw(profileId));
    if (!latestEval || !latestEval.accepted || !latestEval.holdout_passed) {
      let rollbackTriggered = false;
      let nextActiveId = activeProfileId;
      if (rollbackOnViolation && activeProfileId !== stableProfileId) {
        const rollback = this.rollbackRiskTuningProfile({ reason: latestEval?.deny_code || 'holdout_regression' });
        rollbackTriggered = !!rollback.rolled_back;
        nextActiveId = String(rollback.to_profile_id || nextActiveId);
      }
      return {
        promoted: false,
        rollback_triggered: rollbackTriggered,
        active_profile_id: nextActiveId,
        previous_active_profile_id: activeProfileId,
        deny_code: latestEval?.deny_code ? String(latestEval.deny_code) : 'holdout_regression',
      };
    }

    if (profileId === activeProfileId) {
      return {
        promoted: true,
        rollback_triggered: false,
        active_profile_id: activeProfileId,
        previous_active_profile_id: activeProfileId,
        deny_code: '',
      };
    }

    this.db.exec('BEGIN;');
    try {
      this.db
        .prepare(
          `UPDATE memory_risk_tuning_profiles
           SET status = 'candidate',
               updated_at_ms = ?
           WHERE profile_id = ?`
        )
        .run(now, activeProfileId);
      this.db
        .prepare(
          `UPDATE memory_risk_tuning_profiles
           SET status = 'active',
               previous_profile_id = ?,
               promoted_at_ms = ?,
               rollback_reason = NULL,
               updated_at_ms = ?
           WHERE profile_id = ?`
        )
        .run(activeProfileId, now, now, profileId);
      this.db
        .prepare(
          `UPDATE memory_risk_tuning_state
           SET active_profile_id = ?,
               stable_profile_id = ?,
               updated_at_ms = ?
           WHERE state_id = 1`
        )
        .run(profileId, activeProfileId, now);
      this.db.exec('COMMIT;');
    } catch (err) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw err;
    }

    return {
      promoted: true,
      rollback_triggered: false,
      active_profile_id: profileId,
      previous_active_profile_id: activeProfileId,
      deny_code: '',
    };
  }

  _normalizeSecretVaultScope(value) {
    const raw = String(value || '').trim().toLowerCase();
    if (SECRET_VAULT_SCOPES.has(raw)) return raw;
    return '';
  }

  _normalizeSecretVaultLeaseStatus(value, fallback = 'active') {
    const raw = String(value || '').trim().toLowerCase();
    if (SECRET_VAULT_LEASE_STATUSES.has(raw)) return raw;
    return String(fallback || 'active').trim().toLowerCase() || 'active';
  }

  _normalizeSecretVaultName(value) {
    const raw = String(value || '').trim();
    if (!raw || raw.length > 160) return '';
    if (/[\u0000-\u001f]/.test(raw)) return '';
    return raw;
  }

  _normalizeSecretVaultSensitivity(value, fallback = 'secret') {
    const raw = String(value || '').trim().toLowerCase();
    if (!raw) return String(fallback || 'secret').trim().toLowerCase() || 'secret';
    if (!/^[a-z0-9._:-]{1,64}$/.test(raw)) return String(fallback || 'secret').trim().toLowerCase() || 'secret';
    return raw;
  }

  _secretVaultOwnerFromClient(scope, fields = {}) {
    const normalizedScope = this._normalizeSecretVaultScope(scope);
    if (!normalizedScope) return null;

    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();

    if (!deviceId || !appId) return null;

    switch (normalizedScope) {
      case 'device':
        return {
          scope: normalizedScope,
          owner_device_id: deviceId,
          owner_user_id: '',
          owner_app_id: '',
          owner_project_id: '',
        };
      case 'user':
        if (!userId) return null;
        return {
          scope: normalizedScope,
          owner_device_id: '',
          owner_user_id: userId,
          owner_app_id: '',
          owner_project_id: '',
        };
      case 'app':
        return {
          scope: normalizedScope,
          owner_device_id: '',
          owner_user_id: userId,
          owner_app_id: appId,
          owner_project_id: '',
        };
      case 'project':
        if (!projectId) return null;
        return {
          scope: normalizedScope,
          owner_device_id: '',
          owner_user_id: userId,
          owner_app_id: appId,
          owner_project_id: projectId,
        };
      default:
        return null;
    }
  }

  _secretVaultOwnerMatchesClient(row, fields = {}) {
    if (!row) return false;
    const owner = this._secretVaultOwnerFromClient(row.scope, fields);
    if (!owner) return false;
    return (
      String(row.scope || '') === owner.scope
      && String(row.owner_device_id || '') === owner.owner_device_id
      && String(row.owner_user_id || '') === owner.owner_user_id
      && String(row.owner_app_id || '') === owner.owner_app_id
      && String(row.owner_project_id || '') === owner.owner_project_id
    );
  }

  _parseSecretVaultItemRow(row) {
    if (!row) return null;
    return {
      item_id: String(row.item_id || ''),
      scope: this._normalizeSecretVaultScope(row.scope),
      name: String(row.name || ''),
      sensitivity: this._normalizeSecretVaultSensitivity(row.sensitivity, 'secret'),
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
      owner_device_id: String(row.owner_device_id || ''),
      owner_user_id: String(row.owner_user_id || ''),
      owner_app_id: String(row.owner_app_id || ''),
      owner_project_id: String(row.owner_project_id || ''),
      display_name: row.display_name == null ? '' : String(row.display_name || ''),
      reason: row.reason == null ? '' : String(row.reason || ''),
    };
  }

  _parseSecretVaultLeaseRow(row) {
    if (!row) return null;
    return {
      lease_id: String(row.lease_id || ''),
      use_token_hash: String(row.use_token_hash || ''),
      item_id: String(row.item_id || ''),
      scope: this._normalizeSecretVaultScope(row.scope),
      name: String(row.name || ''),
      purpose: String(row.purpose || ''),
      target: row.target == null ? '' : String(row.target || ''),
      device_id: String(row.device_id || ''),
      user_id: String(row.user_id || ''),
      app_id: String(row.app_id || ''),
      project_id: String(row.project_id || ''),
      status: this._normalizeSecretVaultLeaseStatus(row.status, 'active'),
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      expires_at_ms: Math.max(0, Number(row.expires_at_ms || 0)),
      used_at_ms: Math.max(0, Number(row.used_at_ms || 0)),
      revoked_at_ms: Math.max(0, Number(row.revoked_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    };
  }

  _getSecretVaultLeaseRowRawByTokenHash(useTokenHash) {
    const normalizedTokenHash = String(useTokenHash || '').trim();
    if (!normalizedTokenHash) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM secret_vault_use_leases
         WHERE use_token_hash = ?
         LIMIT 1`
      )
      .get(normalizedTokenHash) || null;
  }

  _getSecretVaultItemRowRawById(itemId) {
    const normalizedItemId = String(itemId || '').trim();
    if (!normalizedItemId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM secret_vault_items
         WHERE item_id = ?
         LIMIT 1`
      )
      .get(normalizedItemId) || null;
  }

  _findSecretVaultItemRowRawByOwnerAndName({
    scope,
    name,
    device_id,
    user_id,
    app_id,
    project_id,
  } = {}) {
    const normalizedScope = this._normalizeSecretVaultScope(scope);
    const normalizedName = this._normalizeSecretVaultName(name);
    const owner = this._secretVaultOwnerFromClient(normalizedScope, {
      device_id,
      user_id,
      app_id,
      project_id,
    });
    if (!normalizedScope || !normalizedName || !owner) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM secret_vault_items
         WHERE scope = ?
           AND owner_device_id = ?
           AND owner_user_id = ?
           AND owner_app_id = ?
           AND owner_project_id = ?
           AND name_key = ?
         LIMIT 1`
      )
      .get(
        normalizedScope,
        owner.owner_device_id,
        owner.owner_user_id,
        owner.owner_app_id,
        owner.owner_project_id,
        normalizedName.toLowerCase()
      ) || null;
  }

  createOrUpdateSecretVaultItem(fields = {}) {
    const now = nowMs();
    const scope = this._normalizeSecretVaultScope(fields.scope);
    const name = this._normalizeSecretVaultName(fields.name);
    const plaintext = String(fields.plaintext ?? '');
    const sensitivity = this._normalizeSecretVaultSensitivity(fields.sensitivity, 'secret');
    const displayName = fields.display_name == null ? null : String(fields.display_name || '').trim() || null;
    const reason = fields.reason == null ? null : String(fields.reason || '').trim() || null;
    const owner = this._secretVaultOwnerFromClient(scope, fields);

    if (!scope || !name || !plaintext || !owner) {
      return {
        ok: false,
        created: false,
        deny_code: !owner && scope ? 'invalid_scope_context' : 'invalid_request',
        item: null,
      };
    }

    const existing = this._findSecretVaultItemRowRawByOwnerAndName({
      scope,
      name,
      device_id: fields.device_id,
      user_id: fields.user_id,
      app_id: fields.app_id,
      project_id: fields.project_id,
    });

    const itemId = existing ? String(existing.item_id || '') : `sv_${uuid()}`;
    const createdAtMs = existing ? Math.max(0, Number(existing.created_at_ms || 0)) : now;
    const rowPayload = {
      item_id: itemId,
      scope,
      name_key: name.toLowerCase(),
      sensitivity,
      owner_device_id: owner.owner_device_id,
      owner_user_id: owner.owner_user_id,
      owner_app_id: owner.owner_app_id,
      owner_project_id: owner.owner_project_id,
      created_at_ms: createdAtMs,
      plaintext,
    };
    const ciphertextText = this._encryptSecretVaultPlaintext(rowPayload);

    this.db.exec('BEGIN;');
    try {
      if (existing) {
        this.db
          .prepare(
            `UPDATE secret_vault_items
             SET sensitivity = ?,
                 display_name = ?,
                 reason = ?,
                 ciphertext_text = ?,
                 updated_at_ms = ?
             WHERE item_id = ?`
          )
          .run(
            sensitivity,
            displayName,
            reason,
            ciphertextText,
            now,
            itemId
          );
      } else {
        this.db
          .prepare(
            `INSERT INTO secret_vault_items(
               item_id, scope, name, name_key, sensitivity, display_name, reason,
               ciphertext_text,
               owner_device_id, owner_user_id, owner_app_id, owner_project_id,
               created_at_ms, updated_at_ms
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
          )
          .run(
            itemId,
            scope,
            name,
            name.toLowerCase(),
            sensitivity,
            displayName,
            reason,
            ciphertextText,
            owner.owner_device_id,
            owner.owner_user_id,
            owner.owner_app_id,
            owner.owner_project_id,
            createdAtMs,
            now
          );
      }
      this.db.exec('COMMIT;');
    } catch (err) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw err;
    }

    return {
      ok: true,
      created: !existing,
      deny_code: '',
      item: this._parseSecretVaultItemRow(this._getSecretVaultItemRowRawById(itemId)),
    };
  }

  _secretVaultAccessibleRowsForClient({
    device_id,
    user_id,
    app_id,
    project_id,
    scope,
    name_prefix,
    limit,
  } = {}) {
    const normalizedScope = this._normalizeSecretVaultScope(scope);
    const normalizedPrefix = String(name_prefix || '').trim().toLowerCase();
    const boundedLimit = Math.max(1, Math.min(500, Number(limit || 200) || 200));
    const rows = this.db
      .prepare(
        `SELECT *
         FROM secret_vault_items
         ORDER BY updated_at_ms DESC, item_id ASC
         LIMIT ?`
      )
      .all(Math.max(50, boundedLimit * 8));

    return rows
      .filter((row) => this._secretVaultOwnerMatchesClient(row, {
        device_id,
        user_id,
        app_id,
        project_id,
      }))
      .filter((row) => !normalizedScope || String(row.scope || '') === normalizedScope)
      .filter((row) => !normalizedPrefix || String(row.name_key || '').startsWith(normalizedPrefix))
      .slice(0, boundedLimit);
  }

  listSecretVaultItems(fields = {}) {
    const rows = this._secretVaultAccessibleRowsForClient(fields);
    const items = rows.map((row) => this._parseSecretVaultItemRow(row)).filter(Boolean);
    return {
      updated_at_ms: items[0]?.updated_at_ms || 0,
      items,
    };
  }

  listSecretVaultItemsForSnapshot({ scope, name_prefix, limit } = {}) {
    const normalizedScope = this._normalizeSecretVaultScope(scope);
    const normalizedPrefix = String(name_prefix || '').trim().toLowerCase();
    const boundedLimit = Math.max(1, Math.min(500, Number(limit || 200) || 200));
    const rows = this.db
      .prepare(
        `SELECT *
         FROM secret_vault_items
         ORDER BY updated_at_ms DESC, item_id ASC
         LIMIT ?`
      )
      .all(boundedLimit * 2);
    const items = rows
      .filter((row) => !normalizedScope || String(row.scope || '') === normalizedScope)
      .filter((row) => !normalizedPrefix || String(row.name_key || '').startsWith(normalizedPrefix))
      .slice(0, boundedLimit)
      .map((row) => this._parseSecretVaultItemRow(row))
      .filter(Boolean);
    return {
      updated_at_ms: items[0]?.updated_at_ms || 0,
      items,
    };
  }

  beginSecretVaultUse(fields = {}) {
    const now = nowMs();
    const itemId = String(fields.item_id || '').trim();
    const scope = this._normalizeSecretVaultScope(fields.scope);
    const name = this._normalizeSecretVaultName(fields.name);
    const purpose = String(fields.purpose || '').trim();
    const target = fields.target == null ? null : String(fields.target || '').trim() || null;
    const ttlMs = Math.max(1000, Math.min(10 * 60 * 1000, Number(fields.ttl_ms || 60 * 1000) || (60 * 1000)));
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();

    if (!deviceId || !appId || !purpose) {
      return {
        ok: false,
        deny_code: 'invalid_request',
        lease: null,
      };
    }

    let row = null;
    if (itemId) {
      row = this._getSecretVaultItemRowRawById(itemId);
      if (!row || !this._secretVaultOwnerMatchesClient(row, {
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      })) {
        return {
          ok: false,
          deny_code: 'secret_vault_item_not_found',
          lease: null,
        };
      }
    } else {
      row = this._findSecretVaultItemRowRawByOwnerAndName({
        scope,
        name,
        device_id: deviceId,
        user_id: userId,
        app_id: appId,
        project_id: projectId,
      });
      if (!row) {
        return {
          ok: false,
          deny_code: 'secret_vault_item_not_found',
          lease: null,
        };
      }
    }

    const leaseId = `svl_${uuid()}`;
    const useToken = `svtok_${uuid()}`;
    const expiresAtMs = now + ttlMs;

    this.db
      .prepare(
        `INSERT INTO secret_vault_use_leases(
           lease_id, use_token_hash, item_id, scope, name, purpose, target,
           device_id, user_id, app_id, project_id,
           status, created_at_ms, expires_at_ms, used_at_ms, revoked_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        leaseId,
        sha256Hex(useToken),
        String(row.item_id || ''),
        String(row.scope || ''),
        String(row.name || ''),
        purpose,
        target,
        deviceId,
        userId,
        appId,
        projectId,
        'active',
        now,
        expiresAtMs,
        null,
        null,
        now
      );

    return {
      ok: true,
      deny_code: '',
      lease: {
        lease_id: leaseId,
        use_token: useToken,
        item_id: String(row.item_id || ''),
        expires_at_ms: expiresAtMs,
      },
    };
  }

  redeemSecretVaultUse(fields = {}) {
    const now = nowMs();
    const useToken = String(fields.use_token || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const consume = fields.consume !== false;

    if (!useToken || !deviceId || !appId) {
      return {
        ok: false,
        deny_code: 'invalid_request',
        plaintext: '',
        item: null,
        lease: null,
      };
    }

    const tokenHash = sha256Hex(useToken);
    const leaseRow = this._getSecretVaultLeaseRowRawByTokenHash(tokenHash);
    if (!leaseRow) {
      return {
        ok: false,
        deny_code: 'secret_vault_use_token_not_found',
        plaintext: '',
        item: null,
        lease: null,
      };
    }

    const lease = this._parseSecretVaultLeaseRow(leaseRow);
    if (!lease) {
      return {
        ok: false,
        deny_code: 'secret_vault_use_token_not_found',
        plaintext: '',
        item: null,
        lease: null,
      };
    }

    const identityMatches = (
      lease.device_id === deviceId
      && lease.user_id === userId
      && lease.app_id === appId
      && lease.project_id === projectId
    );
    if (!identityMatches) {
      return {
        ok: false,
        deny_code: 'secret_vault_use_token_not_found',
        plaintext: '',
        item: null,
        lease: null,
      };
    }

    if (lease.status === 'revoked') {
      return {
        ok: false,
        deny_code: 'secret_vault_use_token_revoked',
        plaintext: '',
        item: null,
        lease: null,
      };
    }
    if (lease.status === 'used') {
      return {
        ok: false,
        deny_code: 'secret_vault_use_token_used',
        plaintext: '',
        item: null,
        lease: null,
      };
    }
    if (lease.expires_at_ms <= now || lease.status === 'expired') {
      this.db
        .prepare(
          `UPDATE secret_vault_use_leases
           SET status = 'expired',
               updated_at_ms = ?
           WHERE lease_id = ?`
        )
        .run(now, lease.lease_id);
      return {
        ok: false,
        deny_code: 'secret_vault_use_token_expired',
        plaintext: '',
        item: null,
        lease: null,
      };
    }

    const itemRow = this._getSecretVaultItemRowRawById(lease.item_id);
    if (!itemRow || !this._secretVaultOwnerMatchesClient(itemRow, {
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
    })) {
      return {
        ok: false,
        deny_code: 'secret_vault_item_not_found',
        plaintext: '',
        item: null,
        lease: null,
      };
    }

    const plaintext = this._decryptSecretVaultPlaintextRow(itemRow);
    if (!plaintext) {
      return {
        ok: false,
        deny_code: 'secret_vault_decrypt_failed',
        plaintext: '',
        item: this._parseSecretVaultItemRow(itemRow),
        lease: null,
      };
    }

    if (consume) {
      this.db
        .prepare(
          `UPDATE secret_vault_use_leases
           SET status = 'used',
               used_at_ms = ?,
               updated_at_ms = ?
           WHERE lease_id = ?`
        )
        .run(now, now, lease.lease_id);
    }

    return {
      ok: true,
      deny_code: '',
      plaintext,
      item: this._parseSecretVaultItemRow(itemRow),
      lease: this._parseSecretVaultLeaseRow(
        this.db
          .prepare(
            `SELECT *
             FROM secret_vault_use_leases
             WHERE lease_id = ?
             LIMIT 1`
          )
          .get(lease.lease_id)
      ),
    };
  }

  _normalizeVoiceRiskLevel(value, fallback = 'high') {
    const raw = String(value || '').trim().toLowerCase();
    if (RISK_LEVELS.has(raw)) return raw;
    return String(fallback || 'high').trim().toLowerCase() || 'high';
  }

  _normalizeVoiceChallengeStatus(value, fallback = 'issued') {
    const raw = String(value || '').trim().toLowerCase();
    if (VOICE_CHALLENGE_STATUSES.has(raw)) return raw;
    return String(fallback || 'issued').trim().toLowerCase() || 'issued';
  }

  _parseVoiceGrantChallengeRow(row) {
    if (!row) return null;
    return {
      challenge_id: String(row.challenge_id || ''),
      request_id: row.request_id != null ? String(row.request_id || '') : '',
      template_id: String(row.template_id || ''),
      action_digest: String(row.action_digest || ''),
      scope_digest: String(row.scope_digest || ''),
      amount_digest: row.amount_digest != null ? String(row.amount_digest || '') : '',
      challenge_code_hash: String(row.challenge_code_hash || ''),
      risk_level: this._normalizeVoiceRiskLevel(row.risk_level, 'high'),
      requires_mobile_confirm: !!Number(row.requires_mobile_confirm || 0),
      allow_voice_only: !!Number(row.allow_voice_only || 0),
      bound_device_id: row.bound_device_id != null ? String(row.bound_device_id || '') : '',
      mobile_terminal_id: row.mobile_terminal_id != null ? String(row.mobile_terminal_id || '') : '',
      status: this._normalizeVoiceChallengeStatus(row.status, 'issued'),
      deny_code: row.deny_code != null ? String(row.deny_code || '') : '',
      transcript_hash: row.transcript_hash != null ? String(row.transcript_hash || '') : '',
      semantic_match_score: Number(row.semantic_match_score || 0),
      challenge_match: row.challenge_match == null ? null : !!Number(row.challenge_match || 0),
      device_binding_ok: row.device_binding_ok == null ? null : !!Number(row.device_binding_ok || 0),
      mobile_confirmed: row.mobile_confirmed == null ? null : !!Number(row.mobile_confirmed || 0),
      issued_at_ms: Math.max(0, Number(row.issued_at_ms || 0)),
      expires_at_ms: Math.max(0, Number(row.expires_at_ms || 0)),
      verified_at_ms: Math.max(0, Number(row.verified_at_ms || 0)),
      updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
      device_id: String(row.device_id || ''),
      user_id: String(row.user_id || ''),
      app_id: String(row.app_id || ''),
      project_id: String(row.project_id || ''),
    };
  }

  _getVoiceGrantChallengeRowRaw(challenge_id) {
    const challengeId = String(challenge_id || '').trim();
    if (!challengeId) return null;
    return this.db
      .prepare(
        `SELECT *
         FROM memory_voice_grant_challenges
         WHERE challenge_id = ?
         LIMIT 1`
      )
      .get(challengeId) || null;
  }

  issueVoiceGrantChallenge(fields = {}) {
    const now = nowMs();
    const requestId = String(fields.request_id || '').trim();
    const templateId = String(fields.template_id || '').trim();
    const actionDigest = String(fields.action_digest || '').trim();
    const scopeDigest = String(fields.scope_digest || '').trim();
    const amountDigest = String(fields.amount_digest || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const riskLevel = this._normalizeVoiceRiskLevel(fields.risk_level, 'high');
    let requiresMobileConfirm = fields.requires_mobile_confirm == null ? true : !!fields.requires_mobile_confirm;
    let allowVoiceOnly = !!fields.allow_voice_only;
    if (riskLevel === 'high') {
      requiresMobileConfirm = true;
      allowVoiceOnly = false;
    }
    if (!templateId || !actionDigest || !scopeDigest || !deviceId || !appId) {
      return {
        issued: false,
        deny_code: 'invalid_request',
        challenge: null,
      };
    }
    const ttlMs = Math.max(10 * 1000, Math.min(10 * 60 * 1000, Number(fields.ttl_ms || (2 * 60 * 1000))));
    const expiresAtMs = now + ttlMs;
    let challengeCode = String(fields.challenge_code || '').trim();
    if (!challengeCode) {
      challengeCode = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
    }
    if (challengeCode.length > 64) {
      return {
        issued: false,
        deny_code: 'invalid_request',
        challenge: null,
      };
    }
    const challengeId = `voice_chal_${uuid()}`;
    const challengeCodeHash = sha256Hex(challengeCode);

    this.db
      .prepare(
        `INSERT INTO memory_voice_grant_challenges(
           challenge_id, request_id, template_id, action_digest, scope_digest, amount_digest,
           challenge_code_hash, risk_level, requires_mobile_confirm, allow_voice_only,
           bound_device_id, mobile_terminal_id, status, deny_code, transcript_hash,
           semantic_match_score, challenge_match, device_binding_ok, mobile_confirmed,
           issued_at_ms, expires_at_ms, verified_at_ms, updated_at_ms,
           device_id, user_id, app_id, project_id
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        challengeId,
        requestId || null,
        templateId,
        actionDigest,
        scopeDigest,
        amountDigest || null,
        challengeCodeHash,
        riskLevel,
        requiresMobileConfirm ? 1 : 0,
        allowVoiceOnly ? 1 : 0,
        fields.bound_device_id ? String(fields.bound_device_id).trim() : null,
        fields.mobile_terminal_id ? String(fields.mobile_terminal_id).trim() : null,
        'issued',
        null,
        null,
        null,
        null,
        null,
        null,
        now,
        expiresAtMs,
        null,
        now,
        deviceId,
        userId,
        appId,
        projectId
      );

    const challenge = this._parseVoiceGrantChallengeRow(this._getVoiceGrantChallengeRowRaw(challengeId));
    return {
      issued: true,
      deny_code: '',
      challenge: challenge
        ? {
            ...challenge,
            challenge_code: challengeCode,
          }
        : null,
    };
  }

  verifyVoiceGrantResponse(fields = {}) {
    const now = nowMs();
    const challengeId = String(fields.challenge_id || '').trim();
    const deviceId = String(fields.device_id || '').trim();
    const userId = String(fields.user_id || '').trim();
    const appId = String(fields.app_id || '').trim();
    const projectId = String(fields.project_id || '').trim();
    const challengeCode = String(fields.challenge_code || '').trim();
    const verifyNonce = String(fields.verify_nonce || '').trim();
    const boundDeviceId = String(fields.bound_device_id || '').trim();
    const mobileConfirmed = !!fields.mobile_confirmed;
    const semanticMatchScore = Number(fields.semantic_match_score || 0);
    const parsedActionDigest = String(fields.parsed_action_digest || '').trim();
    const parsedScopeDigest = String(fields.parsed_scope_digest || '').trim();
    const parsedAmountDigest = String(fields.parsed_amount_digest || '').trim();
    const transcriptHash = String(fields.transcript_hash || '').trim()
      || (fields.transcript ? sha256Hex(String(fields.transcript || '')) : '');

    const denied = (deny_code, extra = {}) => ({
      verified: false,
      decision: 'deny',
      deny_code,
      challenge_id: challengeId,
      transcript_hash: transcriptHash,
      semantic_match_score: Number.isFinite(semanticMatchScore) ? semanticMatchScore : 0,
      challenge_match: !!extra.challenge_match,
      device_binding_ok: !!extra.device_binding_ok,
      mobile_confirmed: !!mobileConfirmed,
    });

    if (!challengeId) return denied('challenge_missing');
    const challenge = this._parseVoiceGrantChallengeRow(this._getVoiceGrantChallengeRowRaw(challengeId));
    if (!challenge) return denied('challenge_missing');
    if (!deviceId || !appId) return denied('invalid_request');
    if (challenge.device_id !== deviceId || challenge.app_id !== appId || challenge.user_id !== userId || challenge.project_id !== projectId) {
      return denied('challenge_missing');
    }
    if (challenge.status !== 'issued') {
      return denied('replay_detected');
    }
    if (now > challenge.expires_at_ms) {
      this.db
        .prepare(
          `UPDATE memory_voice_grant_challenges
           SET status = 'expired',
               deny_code = 'challenge_expired',
               updated_at_ms = ?
           WHERE challenge_id = ?`
        )
        .run(now, challengeId);
      return denied('challenge_expired');
    }

    const challengeMatch = !!challengeCode && sha256Hex(challengeCode) === challenge.challenge_code_hash;
    const semanticThreshold = 0.98;
    const semanticOk = Number.isFinite(semanticMatchScore)
      && semanticMatchScore >= semanticThreshold
      && parsedActionDigest === challenge.action_digest
      && parsedScopeDigest === challenge.scope_digest
      && (!challenge.amount_digest || parsedAmountDigest === challenge.amount_digest);
    const deviceBindingOk = !challenge.bound_device_id || boundDeviceId === challenge.bound_device_id;
    const requiresMobile = challenge.risk_level === 'high' || challenge.requires_mobile_confirm;
    const voiceOnlyAllowed = challenge.risk_level !== 'high' && challenge.allow_voice_only;

    this.db.exec('BEGIN;');
    try {
      if (!verifyNonce) {
        this.db
          .prepare(
            `UPDATE memory_voice_grant_challenges
             SET status = 'denied',
                 deny_code = 'replay_detected',
                 transcript_hash = ?,
                 semantic_match_score = ?,
                 challenge_match = ?,
                 device_binding_ok = ?,
                 mobile_confirmed = ?,
                 updated_at_ms = ?
             WHERE challenge_id = ?`
          )
          .run(
            transcriptHash || null,
            Number.isFinite(semanticMatchScore) ? semanticMatchScore : 0,
            challengeMatch ? 1 : 0,
            deviceBindingOk ? 1 : 0,
            mobileConfirmed ? 1 : 0,
            now,
            challengeId
          );
        this.db.exec('COMMIT;');
        return denied('replay_detected', { challenge_match: challengeMatch, device_binding_ok: deviceBindingOk });
      }

      const nonceHash = sha256Hex(`${challengeId}:${verifyNonce}`);
      const nonceInserted = this.db
        .prepare(
          `INSERT OR IGNORE INTO memory_voice_grant_nonces(nonce_hash, challenge_id, created_at_ms)
           VALUES(?,?,?)`
        )
        .run(nonceHash, challengeId, now);
      if (!Number(nonceInserted?.changes || 0)) {
        this.db
          .prepare(
            `UPDATE memory_voice_grant_challenges
             SET status = 'denied',
                 deny_code = 'replay_detected',
                 transcript_hash = ?,
                 semantic_match_score = ?,
                 challenge_match = ?,
                 device_binding_ok = ?,
                 mobile_confirmed = ?,
                 updated_at_ms = ?
             WHERE challenge_id = ?`
          )
          .run(
            transcriptHash || null,
            Number.isFinite(semanticMatchScore) ? semanticMatchScore : 0,
            challengeMatch ? 1 : 0,
            deviceBindingOk ? 1 : 0,
            mobileConfirmed ? 1 : 0,
            now,
            challengeId
          );
        this.db.exec('COMMIT;');
        return denied('replay_detected', { challenge_match: challengeMatch, device_binding_ok: deviceBindingOk });
      }

      let denyCode = '';
      if (!challengeMatch) {
        denyCode = 'challenge_missing';
      } else if (!semanticOk) {
        denyCode = 'semantic_ambiguous';
      } else if (!deviceBindingOk) {
        denyCode = 'device_not_bound';
      } else if (!mobileConfirmed && (requiresMobile || !voiceOnlyAllowed)) {
        denyCode = challenge.risk_level === 'high' ? 'voice_only_forbidden' : 'mobile_confirmation_required';
      }

      if (denyCode) {
        this.db
          .prepare(
            `UPDATE memory_voice_grant_challenges
             SET status = 'denied',
                 deny_code = ?,
                 transcript_hash = ?,
                 semantic_match_score = ?,
                 challenge_match = ?,
                 device_binding_ok = ?,
                 mobile_confirmed = ?,
                 updated_at_ms = ?
             WHERE challenge_id = ?`
          )
          .run(
            denyCode,
            transcriptHash || null,
            Number.isFinite(semanticMatchScore) ? semanticMatchScore : 0,
            challengeMatch ? 1 : 0,
            deviceBindingOk ? 1 : 0,
            mobileConfirmed ? 1 : 0,
            now,
            challengeId
          );
        this.db.exec('COMMIT;');
        return denied(denyCode, { challenge_match: challengeMatch, device_binding_ok: deviceBindingOk });
      }

      this.db
        .prepare(
          `UPDATE memory_voice_grant_challenges
           SET status = 'verified',
               deny_code = NULL,
               transcript_hash = ?,
               semantic_match_score = ?,
               challenge_match = 1,
               device_binding_ok = 1,
               mobile_confirmed = ?,
               verified_at_ms = ?,
               updated_at_ms = ?
           WHERE challenge_id = ?`
        )
        .run(
          transcriptHash || null,
          Number.isFinite(semanticMatchScore) ? semanticMatchScore : semanticThreshold,
          mobileConfirmed ? 1 : 0,
          now,
          now,
          challengeId
        );
      this.db.exec('COMMIT;');
      return {
        verified: true,
        decision: 'allow',
        deny_code: '',
        challenge_id: challengeId,
        transcript_hash: transcriptHash,
        semantic_match_score: Number.isFinite(semanticMatchScore) ? semanticMatchScore : semanticThreshold,
        challenge_match: true,
        device_binding_ok: true,
        mobile_confirmed: mobileConfirmed,
      };
    } catch (err) {
      try {
        this.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      throw err;
    }
  }

  _normalizeMarkdownEditSessionStatus(value, fallback = 'active') {
    const raw = String(value || '').trim().toLowerCase();
    if (['active', 'expired', 'closed'].includes(raw)) return raw;
    return String(fallback || 'active').trim().toLowerCase() || 'active';
  }

  _normalizeMarkdownPendingChangeStatus(value, fallback = 'draft') {
    const raw = String(value || '').trim().toLowerCase();
    if (['draft', 'reviewed', 'approved', 'written', 'rejected', 'rolled_back'].includes(raw)) return raw;
    return String(fallback || 'draft').trim().toLowerCase() || 'draft';
  }

  _normalizeMarkdownReviewDecision(value, fallback = 'review') {
    const raw = String(value || '').trim().toLowerCase();
    if (['review', 'approve', 'reject'].includes(raw)) return raw;
    return String(fallback || 'review').trim().toLowerCase() || 'review';
  }

  _parseMemoryMarkdownEditSessionRow(row) {
    if (!row) return null;
    const scopeRef = this._safeJsonParse(row.scope_ref_json, {});
    const routePolicy = this._safeJsonParse(row.route_policy_json, {});
    const routeStats = this._safeJsonParse(row.route_stats_json, {});
    const provenanceRefs = this._safeJsonParse(row.provenance_refs_json, []);
    return {
      ...row,
      session_revision: Math.max(0, Number(row.session_revision || 0)),
      scope_ref: scopeRef && typeof scopeRef === 'object' ? scopeRef : {},
      route_policy: routePolicy && typeof routePolicy === 'object' ? routePolicy : {},
      route_stats: routeStats && typeof routeStats === 'object' ? routeStats : {},
      provenance_refs: Array.isArray(provenanceRefs) ? provenanceRefs : [],
    };
  }

  _parseMemoryMarkdownPendingChangeRow(row) {
    if (!row) return null;
    const provenanceRefs = this._safeJsonParse(row.provenance_refs_json, []);
    const routePolicy = this._safeJsonParse(row.route_policy_json, {});
    const reviewFindings = this._safeJsonParse(row.review_findings_json, []);
    return {
      ...row,
      session_revision: Math.max(0, Number(row.session_revision || 0)),
      patch_size_chars: Math.max(0, Number(row.patch_size_chars || 0)),
      patch_line_count: Math.max(0, Number(row.patch_line_count || 0)),
      reviewed_at_ms: row.reviewed_at_ms != null ? Math.max(0, Number(row.reviewed_at_ms || 0)) : null,
      approved_at_ms: row.approved_at_ms != null ? Math.max(0, Number(row.approved_at_ms || 0)) : null,
      written_at_ms: row.written_at_ms != null ? Math.max(0, Number(row.written_at_ms || 0)) : null,
      rolled_back_at_ms: row.rolled_back_at_ms != null ? Math.max(0, Number(row.rolled_back_at_ms || 0)) : null,
      provenance_refs: Array.isArray(provenanceRefs) ? provenanceRefs : [],
      route_policy: routePolicy && typeof routePolicy === 'object' ? routePolicy : {},
      review_findings: Array.isArray(reviewFindings) ? reviewFindings : [],
      reviewed_markdown: row.reviewed_markdown != null ? String(row.reviewed_markdown) : '',
      rollback_ref: row.rollback_ref != null ? String(row.rollback_ref || '') : '',
    };
  }

  _parseMemoryLongtermWritebackCandidateRow(row) {
    if (!row) return null;
    const scopeRef = this._safeJsonParse(row.scope_ref_json, {});
    const provenanceRefs = this._safeJsonParse(row.provenance_refs_json, []);
    const policyDecision = this._safeJsonParse(row.policy_decision_json, {});
    return {
      ...row,
      scope_ref: scopeRef && typeof scopeRef === 'object' ? scopeRef : {},
      provenance_refs: Array.isArray(provenanceRefs) ? provenanceRefs : [],
      policy_decision: policyDecision && typeof policyDecision === 'object' ? policyDecision : {},
      written_at_ms: Math.max(0, Number(row.written_at_ms || 0)),
      rolled_back_at_ms: row.rolled_back_at_ms != null ? Math.max(0, Number(row.rolled_back_at_ms || 0)) : null,
      evidence_ref: row.evidence_ref != null ? String(row.evidence_ref || '') : '',
    };
  }

  _parseMemoryLongtermWritebackChangeLogRow(row) {
    if (!row) return null;
    const scopeRef = this._safeJsonParse(row.scope_ref_json, {});
    const policyDecision = this._safeJsonParse(row.policy_decision_json, {});
    return {
      ...row,
      scope_ref: scopeRef && typeof scopeRef === 'object' ? scopeRef : {},
      policy_decision: policyDecision && typeof policyDecision === 'object' ? policyDecision : {},
      created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
      evidence_ref: row.evidence_ref != null ? String(row.evidence_ref || '') : '',
    };
  }

  createMemoryMarkdownEditSession(fields = {}) {
    const now = nowMs();
    const editSessionId = String(fields.edit_session_id || '').trim() || `medit_${uuid()}`;
    const docId = String(fields.doc_id || '').trim();
    const baseVersion = String(fields.base_version || '').trim();
    const workingVersion = String(fields.working_version || '').trim() || baseVersion;
    const sessionRevision = Math.max(0, Number(fields.session_revision || 0));
    const scopeFilter = String(fields.scope_filter || 'all').trim() || 'all';
    const scopeRefJson = this._safeJsonStringify(fields.scope_ref || fields.scope_ref_json || {});
    const routePolicyJson = this._safeJsonStringify(fields.route_policy || fields.route_policy_json || {});
    const routeStatsJson = this._safeJsonStringify(fields.route_stats || fields.route_stats_json || {});
    const baseMarkdown = String(fields.base_markdown ?? '');
    const workingMarkdown = String(fields.working_markdown ?? fields.base_markdown ?? '');
    const provenanceRefsJson = this._safeJsonStringify(fields.provenance_refs || fields.provenance_refs_json || []);
    const status = this._normalizeMarkdownEditSessionStatus(fields.status, 'active');
    const createdByDeviceId = String(fields.created_by_device_id || '').trim();
    const createdByUserId = fields.created_by_user_id != null ? String(fields.created_by_user_id).trim() : '';
    const createdByAppId = String(fields.created_by_app_id || '').trim();
    const createdByProjectId = fields.created_by_project_id != null ? String(fields.created_by_project_id).trim() : '';
    const createdBySessionId = fields.created_by_session_id != null ? String(fields.created_by_session_id).trim() : '';
    const createdAtMs = Math.max(0, Number(fields.created_at_ms || now));
    const updatedAtMs = Math.max(0, Number(fields.updated_at_ms || createdAtMs));
    const expiresAtMs = Math.max(updatedAtMs + 1, Number(fields.expires_at_ms || (updatedAtMs + (20 * 60 * 1000))));
    const lastPatchAtMs = fields.last_patch_at_ms != null ? Math.max(0, Number(fields.last_patch_at_ms || 0)) : null;
    const lastChangeId = fields.last_change_id != null ? (String(fields.last_change_id || '').trim() || null) : null;

    if (!docId) throw new Error('missing doc_id');
    if (!baseVersion) throw new Error('missing base_version');
    if (!createdByDeviceId || !createdByAppId) throw new Error('missing created_by_device_id/created_by_app_id');

    this.db
      .prepare(
        `INSERT INTO memory_markdown_edit_sessions(
           edit_session_id, doc_id, base_version, working_version, session_revision,
           scope_filter, scope_ref_json, route_policy_json, route_stats_json,
           base_markdown, working_markdown, provenance_refs_json, status,
           created_by_device_id, created_by_user_id, created_by_app_id, created_by_project_id, created_by_session_id,
           created_at_ms, updated_at_ms, expires_at_ms, last_patch_at_ms, last_change_id
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        editSessionId,
        docId,
        baseVersion,
        workingVersion,
        sessionRevision,
        scopeFilter,
        scopeRefJson,
        routePolicyJson,
        routeStatsJson,
        baseMarkdown,
        workingMarkdown,
        provenanceRefsJson,
        status,
        createdByDeviceId,
        createdByUserId || null,
        createdByAppId,
        createdByProjectId || null,
        createdBySessionId || null,
        createdAtMs,
        updatedAtMs,
        expiresAtMs,
        lastPatchAtMs,
        lastChangeId
      );
    return this.getMemoryMarkdownEditSession({ edit_session_id: editSessionId });
  }

  getMemoryMarkdownEditSession({ edit_session_id } = {}) {
    const sessionId = String(edit_session_id || '').trim();
    if (!sessionId) return null;
    const row = this.db
      .prepare(
        `SELECT *
         FROM memory_markdown_edit_sessions
         WHERE edit_session_id = ?
         LIMIT 1`
      )
      .get(sessionId) || null;
    return this._parseMemoryMarkdownEditSessionRow(row);
  }

  expireMemoryMarkdownEditSessions({ now_ms } = {}) {
    const now = Math.max(0, Number(now_ms || nowMs()));
    const info = this.db
      .prepare(
        `UPDATE memory_markdown_edit_sessions
         SET status = 'expired',
             updated_at_ms = CASE WHEN updated_at_ms < ? THEN ? ELSE updated_at_ms END
         WHERE status = 'active' AND expires_at_ms <= ?`
      )
      .run(now, now, now);
    return Math.max(0, Number(info?.changes || 0));
  }

  updateMemoryMarkdownEditSessionOptimistic({
    edit_session_id,
    expected_revision,
    working_version,
    working_markdown,
    status,
    expires_at_ms,
    last_patch_at_ms,
    last_change_id,
    updated_at_ms,
    now_ms,
  } = {}) {
    const sessionId = String(edit_session_id || '').trim();
    if (!sessionId) throw new Error('missing edit_session_id');
    const expectedRevision = Math.max(0, Number(expected_revision || 0));
    const cur = this.getMemoryMarkdownEditSession({ edit_session_id: sessionId });
    if (!cur) throw new Error('edit_session_not_found');

    const now = Math.max(0, Number(now_ms || nowMs()));
    const nextRevision = expectedRevision + 1;
    const nextWorkingVersion = working_version != null
      ? (String(working_version || '').trim() || String(cur.working_version || ''))
      : String(cur.working_version || '');
    const nextWorkingMarkdown = working_markdown != null
      ? String(working_markdown ?? '')
      : String(cur.working_markdown ?? '');
    const nextStatus = status != null
      ? this._normalizeMarkdownEditSessionStatus(status, cur.status)
      : this._normalizeMarkdownEditSessionStatus(cur.status, 'active');
    const nextExpiresAt = expires_at_ms != null
      ? Math.max(0, Number(expires_at_ms || 0))
      : Math.max(0, Number(cur.expires_at_ms || 0));
    const nextLastPatchAt = last_patch_at_ms !== undefined
      ? (last_patch_at_ms != null ? Math.max(0, Number(last_patch_at_ms || 0)) : null)
      : (cur.last_patch_at_ms != null ? Math.max(0, Number(cur.last_patch_at_ms || 0)) : null);
    const nextLastChangeId = last_change_id !== undefined
      ? (last_change_id != null ? (String(last_change_id || '').trim() || null) : null)
      : (cur.last_change_id != null ? String(cur.last_change_id) : null);
    const nextUpdatedAt = updated_at_ms != null
      ? Math.max(0, Number(updated_at_ms || 0))
      : now;

    const info = this.db
      .prepare(
        `UPDATE memory_markdown_edit_sessions
         SET working_version = ?, working_markdown = ?, session_revision = ?, status = ?,
             expires_at_ms = ?, last_patch_at_ms = ?, last_change_id = ?, updated_at_ms = ?
         WHERE edit_session_id = ?
           AND session_revision = ?
           AND status = 'active'
           AND expires_at_ms > ?`
      )
      .run(
        nextWorkingVersion,
        nextWorkingMarkdown,
        nextRevision,
        nextStatus,
        nextExpiresAt,
        nextLastPatchAt,
        nextLastChangeId,
        nextUpdatedAt,
        sessionId,
        expectedRevision,
        now
      );
    if (Math.max(0, Number(info?.changes || 0)) <= 0) return null;
    return this.getMemoryMarkdownEditSession({ edit_session_id: sessionId });
  }

  applyMemoryMarkdownPatchDraft({
    edit_session_id,
    expected_revision,
    working_version,
    working_markdown,
    expires_at_ms,
    last_patch_at_ms,
    updated_at_ms,
    change,
    now_ms,
  } = {}) {
    const sessionId = String(edit_session_id || '').trim();
    if (!sessionId) throw new Error('missing edit_session_id');
    const expectedRevision = Math.max(0, Number(expected_revision || 0));
    const patch = change && typeof change === 'object' ? change : {};

    const now = Math.max(0, Number(now_ms || nowMs()));
    const nextUpdatedAt = updated_at_ms != null ? Math.max(0, Number(updated_at_ms || 0)) : now;
    const nextLastPatchAt = last_patch_at_ms != null ? Math.max(0, Number(last_patch_at_ms || 0)) : now;
    const nextExpiresAt = expires_at_ms != null ? Math.max(0, Number(expires_at_ms || 0)) : null;

    const patchChangeId = String(patch.change_id || '').trim() || `mchange_${uuid()}`;
    const patchDocId = String(patch.doc_id || '').trim();
    const patchBaseVersion = String(patch.base_version || '').trim();
    const patchFromVersion = String(patch.from_version || '').trim();
    const patchToVersion = String(patch.to_version || '').trim();
    const patchStatus = this._normalizeMarkdownPendingChangeStatus(patch.status, 'draft');
    const patchMode = String(patch.patch_mode || 'replace').trim().toLowerCase() || 'replace';
    const patchNote = patch.patch_note != null ? String(patch.patch_note) : null;
    const patchSizeChars = Math.max(0, Number(patch.patch_size_chars || 0));
    const patchLineCount = Math.max(0, Number(patch.patch_line_count || 0));
    const patchSha256 = String(patch.patch_sha256 || '').trim();
    const patchMarkdown = String(patch.patched_markdown ?? '');
    const patchProvenanceJson = this._safeJsonStringify(patch.provenance_refs || patch.provenance_refs_json || []);
    const patchRoutePolicyJson = this._safeJsonStringify(patch.route_policy || patch.route_policy_json || {});
    const patchCreatedByDeviceId = String(patch.created_by_device_id || '').trim();
    const patchCreatedByUserId = patch.created_by_user_id != null ? String(patch.created_by_user_id).trim() : '';
    const patchCreatedByAppId = String(patch.created_by_app_id || '').trim();
    const patchCreatedByProjectId = patch.created_by_project_id != null ? String(patch.created_by_project_id).trim() : '';
    const patchCreatedBySessionId = patch.created_by_session_id != null ? String(patch.created_by_session_id).trim() : '';
    const patchCreatedAt = Math.max(0, Number(patch.created_at_ms || now));
    const patchUpdatedAt = Math.max(0, Number(patch.updated_at_ms || patchCreatedAt));

    if (!patchDocId || !patchBaseVersion || !patchFromVersion || !patchToVersion) {
      throw new Error('missing_patch_version_fields');
    }
    if (!patchSha256) throw new Error('missing patch_sha256');
    if (!patchCreatedByDeviceId || !patchCreatedByAppId) {
      throw new Error('missing_patch_actor');
    }

    this.db.exec('BEGIN;');
    try {
      const row = this.db
        .prepare(
          `SELECT *
           FROM memory_markdown_edit_sessions
           WHERE edit_session_id = ?
           LIMIT 1`
        )
        .get(sessionId) || null;
      const cur = this._parseMemoryMarkdownEditSessionRow(row);
      if (!cur) throw new Error('edit_session_not_found');

      const status = this._normalizeMarkdownEditSessionStatus(cur.status, 'active');
      if (status !== 'active') throw new Error('edit_session_not_active');
      if (Math.max(0, Number(cur.expires_at_ms || 0)) <= now) throw new Error('edit_session_expired');
      if (Math.max(0, Number(cur.session_revision || 0)) !== expectedRevision) throw new Error('version_conflict');

      const nextRevision = expectedRevision + 1;
      const nextWorkingVersion = String(working_version || '').trim() || String(cur.working_version || '');
      const nextWorkingMarkdown = String(working_markdown ?? cur.working_markdown ?? '');
      const finalExpiresAt = nextExpiresAt != null ? nextExpiresAt : Math.max(0, Number(cur.expires_at_ms || 0));

      this.db
        .prepare(
          `UPDATE memory_markdown_edit_sessions
           SET working_version = ?, working_markdown = ?, session_revision = ?,
               updated_at_ms = ?, expires_at_ms = ?, last_patch_at_ms = ?, last_change_id = ?
           WHERE edit_session_id = ?`
        )
        .run(
          nextWorkingVersion,
          nextWorkingMarkdown,
          nextRevision,
          nextUpdatedAt,
          finalExpiresAt,
          nextLastPatchAt,
          patchChangeId,
          sessionId
        );

      this.db
        .prepare(
          `INSERT INTO memory_markdown_pending_changes(
             change_id, edit_session_id, doc_id, base_version, from_version, to_version, session_revision,
             status, patch_mode, patch_note, patch_size_chars, patch_line_count, patch_sha256, patched_markdown,
             provenance_refs_json, route_policy_json,
             created_by_device_id, created_by_user_id, created_by_app_id, created_by_project_id, created_by_session_id,
             created_at_ms, updated_at_ms
           ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
        )
        .run(
          patchChangeId,
          sessionId,
          patchDocId,
          patchBaseVersion,
          patchFromVersion,
          patchToVersion,
          nextRevision,
          patchStatus,
          patchMode,
          patchNote,
          patchSizeChars,
          patchLineCount,
          patchSha256,
          patchMarkdown,
          patchProvenanceJson,
          patchRoutePolicyJson,
          patchCreatedByDeviceId,
          patchCreatedByUserId || null,
          patchCreatedByAppId,
          patchCreatedByProjectId || null,
          patchCreatedBySessionId || null,
          patchCreatedAt,
          patchUpdatedAt
        );

      this.db.exec('COMMIT;');
      return {
        session: this.getMemoryMarkdownEditSession({ edit_session_id: sessionId }),
        change: this.getMemoryMarkdownPendingChange({ change_id: patchChangeId }),
      };
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
  }

  createMemoryMarkdownPendingChange(fields = {}) {
    const now = nowMs();
    const changeId = String(fields.change_id || '').trim() || `mchange_${uuid()}`;
    const editSessionId = String(fields.edit_session_id || '').trim();
    const docId = String(fields.doc_id || '').trim();
    const baseVersion = String(fields.base_version || '').trim();
    const fromVersion = String(fields.from_version || '').trim();
    const toVersion = String(fields.to_version || '').trim();
    const sessionRevision = Math.max(0, Number(fields.session_revision || 0));
    const status = this._normalizeMarkdownPendingChangeStatus(fields.status, 'draft');
    const patchMode = String(fields.patch_mode || 'replace').trim().toLowerCase() || 'replace';
    const patchNote = fields.patch_note != null ? String(fields.patch_note) : null;
    const patchSizeChars = Math.max(0, Number(fields.patch_size_chars || 0));
    const patchLineCount = Math.max(0, Number(fields.patch_line_count || 0));
    const patchSha256 = String(fields.patch_sha256 || '').trim();
    const patchedMarkdown = String(fields.patched_markdown ?? '');
    const provenanceRefsJson = this._safeJsonStringify(fields.provenance_refs || fields.provenance_refs_json || []);
    const routePolicyJson = this._safeJsonStringify(fields.route_policy || fields.route_policy_json || {});
    const createdByDeviceId = String(fields.created_by_device_id || '').trim();
    const createdByUserId = fields.created_by_user_id != null ? String(fields.created_by_user_id).trim() : '';
    const createdByAppId = String(fields.created_by_app_id || '').trim();
    const createdByProjectId = fields.created_by_project_id != null ? String(fields.created_by_project_id).trim() : '';
    const createdBySessionId = fields.created_by_session_id != null ? String(fields.created_by_session_id).trim() : '';
    const createdAtMs = Math.max(0, Number(fields.created_at_ms || now));
    const updatedAtMs = Math.max(0, Number(fields.updated_at_ms || createdAtMs));

    if (!editSessionId) throw new Error('missing edit_session_id');
    if (!docId || !baseVersion || !fromVersion || !toVersion) throw new Error('missing version fields');
    if (!createdByDeviceId || !createdByAppId) throw new Error('missing created_by_device_id/created_by_app_id');
    if (!patchSha256) throw new Error('missing patch_sha256');

    this.db
      .prepare(
        `INSERT INTO memory_markdown_pending_changes(
           change_id, edit_session_id, doc_id, base_version, from_version, to_version, session_revision,
           status, patch_mode, patch_note, patch_size_chars, patch_line_count, patch_sha256, patched_markdown,
           provenance_refs_json, route_policy_json,
           created_by_device_id, created_by_user_id, created_by_app_id, created_by_project_id, created_by_session_id,
           created_at_ms, updated_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        changeId,
        editSessionId,
        docId,
        baseVersion,
        fromVersion,
        toVersion,
        sessionRevision,
        status,
        patchMode,
        patchNote,
        patchSizeChars,
        patchLineCount,
        patchSha256,
        patchedMarkdown,
        provenanceRefsJson,
        routePolicyJson,
        createdByDeviceId,
        createdByUserId || null,
        createdByAppId,
        createdByProjectId || null,
        createdBySessionId || null,
        createdAtMs,
        updatedAtMs
      );
    return this.getMemoryMarkdownPendingChange({ change_id: changeId });
  }

  getMemoryMarkdownPendingChange({ change_id } = {}) {
    const changeId = String(change_id || '').trim();
    if (!changeId) return null;
    const row = this.db
      .prepare(
        `SELECT *
         FROM memory_markdown_pending_changes
         WHERE change_id = ?
         LIMIT 1`
      )
      .get(changeId) || null;
    return this._parseMemoryMarkdownPendingChangeRow(row);
  }

  listMemoryMarkdownPendingChanges({ edit_session_id, status, limit } = {}) {
    const sessionId = String(edit_session_id || '').trim();
    const st = String(status || '').trim().toLowerCase();
    const lim = Math.max(1, Math.min(500, Number(limit || 100)));

    const where = [];
    const args = [];
    if (sessionId) {
      where.push('edit_session_id = ?');
      args.push(sessionId);
    }
    if (st) {
      where.push('status = ?');
      args.push(st);
    }
    args.push(lim);

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const rows = this.db
      .prepare(
        `SELECT *
         FROM memory_markdown_pending_changes
         ${whereSql}
         ORDER BY created_at_ms DESC
         LIMIT ?`
      )
      .all(...args);
    return rows.map((row) => this._parseMemoryMarkdownPendingChangeRow(row)).filter(Boolean);
  }

  reviewMemoryMarkdownPendingChange({
    change_id,
    expected_status,
    decision,
    reviewed_markdown,
    review_findings,
    review_note,
    reviewed_by_device_id,
    reviewed_by_user_id,
    reviewed_by_app_id,
    reviewed_by_project_id,
    reviewed_by_session_id,
    reviewed_at_ms,
    updated_at_ms,
  } = {}) {
    const changeId = String(change_id || '').trim();
    if (!changeId) throw new Error('missing change_id');
    const current = this.getMemoryMarkdownPendingChange({ change_id: changeId });
    if (!current) throw new Error('change_not_found');

    const expected = expected_status != null
      ? this._normalizeMarkdownPendingChangeStatus(expected_status, '')
      : '';
    const curStatus = this._normalizeMarkdownPendingChangeStatus(current.status, 'draft');
    if (expected && curStatus !== expected) throw new Error('version_conflict');
    if (['written', 'rolled_back'].includes(curStatus)) throw new Error('change_not_mutable');

    const decisionNorm = this._normalizeMarkdownReviewDecision(decision, 'review');
    let nextStatus = curStatus;
    if (decisionNorm === 'review') {
      if (!['draft', 'reviewed'].includes(curStatus)) throw new Error('invalid_status_transition');
      nextStatus = 'reviewed';
    } else if (decisionNorm === 'approve') {
      if (!['draft', 'reviewed', 'approved'].includes(curStatus)) throw new Error('invalid_status_transition');
      nextStatus = 'approved';
    } else if (decisionNorm === 'reject') {
      if (!['draft', 'reviewed', 'approved', 'rejected'].includes(curStatus)) throw new Error('invalid_status_transition');
      nextStatus = 'rejected';
    }

    const now = nowMs();
    const reviewedAt = Math.max(0, Number(reviewed_at_ms || now));
    const updatedAt = Math.max(0, Number(updated_at_ms || reviewedAt));
    const findings = Array.isArray(review_findings) ? review_findings : [];
    const findingsJson = this._safeJsonStringify(findings) || '[]';
    const reviewedMarkdown = reviewed_markdown != null
      ? String(reviewed_markdown)
      : (current.reviewed_markdown ? String(current.reviewed_markdown) : String(current.patched_markdown || ''));
    const note = review_note != null ? String(review_note) : null;
    const reviewerDevice = String(reviewed_by_device_id || '').trim();
    const reviewerUser = reviewed_by_user_id != null ? String(reviewed_by_user_id).trim() : '';
    const reviewerApp = String(reviewed_by_app_id || '').trim();
    const reviewerProject = reviewed_by_project_id != null ? String(reviewed_by_project_id).trim() : '';
    const reviewerSession = reviewed_by_session_id != null ? String(reviewed_by_session_id).trim() : '';
    if (!reviewerDevice || !reviewerApp) throw new Error('missing_review_actor');

    const approvedAt = nextStatus === 'approved' ? reviewedAt : null;
    const approvedByDevice = nextStatus === 'approved' ? reviewerDevice : null;
    const approvedByUser = nextStatus === 'approved' ? (reviewerUser || null) : null;
    const approvedByApp = nextStatus === 'approved' ? reviewerApp : null;
    const approvedByProject = nextStatus === 'approved' ? (reviewerProject || null) : null;
    const approvedBySession = nextStatus === 'approved' ? (reviewerSession || null) : null;

    this.db
      .prepare(
        `UPDATE memory_markdown_pending_changes
         SET status = ?,
             reviewed_markdown = ?,
             review_findings_json = ?,
             review_decision = ?,
             review_note = ?,
             reviewed_at_ms = ?,
             reviewed_by_device_id = ?,
             reviewed_by_user_id = ?,
             reviewed_by_app_id = ?,
             reviewed_by_project_id = ?,
             reviewed_by_session_id = ?,
             approved_at_ms = ?,
             approved_by_device_id = ?,
             approved_by_user_id = ?,
             approved_by_app_id = ?,
             approved_by_project_id = ?,
             approved_by_session_id = ?,
             updated_at_ms = ?
         WHERE change_id = ?`
      )
      .run(
        nextStatus,
        reviewedMarkdown,
        findingsJson,
        decisionNorm,
        note,
        reviewedAt,
        reviewerDevice,
        reviewerUser || null,
        reviewerApp,
        reviewerProject || null,
        reviewerSession || null,
        approvedAt,
        approvedByDevice,
        approvedByUser,
        approvedByApp,
        approvedByProject,
        approvedBySession,
        updatedAt,
        changeId
      );
    return this.getMemoryMarkdownPendingChange({ change_id: changeId });
  }

  getMemoryLongtermWritebackCandidate({ candidate_id, change_id } = {}) {
    const candidateId = String(candidate_id || '').trim();
    const changeId = String(change_id || '').trim();
    if (!candidateId && !changeId) return null;
    let row = null;
    if (candidateId) {
      row = this.db
        .prepare(
          `SELECT *
           FROM memory_longterm_writeback_queue
           WHERE candidate_id = ?
           LIMIT 1`
        )
        .get(candidateId) || null;
    } else {
      row = this.db
        .prepare(
          `SELECT *
           FROM memory_longterm_writeback_queue
           WHERE change_id = ?
           LIMIT 1`
        )
        .get(changeId) || null;
    }
    return this._parseMemoryLongtermWritebackCandidateRow(row);
  }

  _normalizeScopeRefObject(value = {}) {
    const v = value && typeof value === 'object' ? value : {};
    return {
      device_id: String(v.device_id || '').trim(),
      user_id: v.user_id != null ? String(v.user_id).trim() : '',
      app_id: String(v.app_id || '').trim(),
      project_id: v.project_id != null ? String(v.project_id).trim() : '',
      thread_id: v.thread_id != null ? String(v.thread_id).trim() : '',
    };
  }

  _scopeRefEquals(left, right) {
    const l = this._normalizeScopeRefObject(left);
    const r = this._normalizeScopeRefObject(right);
    return (
      l.device_id === r.device_id
      && l.user_id === r.user_id
      && l.app_id === r.app_id
      && l.project_id === r.project_id
      && l.thread_id === r.thread_id
    );
  }

  _scopeRefMatchesActor(scopeRef, actor) {
    const scope = this._normalizeScopeRefObject(scopeRef);
    const act = this._normalizeScopeRefObject(actor);
    if (!scope.device_id || !scope.app_id || !act.device_id || !act.app_id) return false;
    if (scope.device_id !== act.device_id) return false;
    if (scope.app_id !== act.app_id) return false;
    if (scope.user_id !== act.user_id && (scope.user_id || act.user_id)) return false;
    if (scope.project_id !== act.project_id && (scope.project_id || act.project_id)) return false;
    if (scope.thread_id !== act.thread_id && (scope.thread_id || act.thread_id)) return false;
    return true;
  }

  _buildLongtermWritebackEvidenceRef({ change, candidate, provenance_refs } = {}) {
    const refs = Array.isArray(provenance_refs) ? provenance_refs : [];
    for (const ref of refs) {
      const s = String(ref || '').trim();
      if (s) return s;
    }
    const c = candidate && typeof candidate === 'object' ? candidate : {};
    const ch = change && typeof change === 'object' ? change : {};
    const docId = String(c.doc_id || ch.doc_id || '').trim();
    const sourceVersion = String(c.source_version || ch.to_version || '').trim();
    const changeId = String(c.change_id || ch.change_id || '').trim();
    return `md:${docId || 'unknown'}:${sourceVersion || 'unknown'}:${changeId || 'unknown'}`;
  }

  getMemoryLongtermWritebackChangeLog({ log_id, change_id, event_type } = {}) {
    const logId = String(log_id || '').trim();
    const changeId = String(change_id || '').trim();
    const evType = String(event_type || '').trim().toLowerCase();
    if (!logId && !changeId) return null;
    let row = null;
    if (logId) {
      row = this.db
        .prepare(
          `SELECT *
           FROM memory_longterm_writeback_changelog
           WHERE log_id = ?
           LIMIT 1`
        )
        .get(logId) || null;
    } else if (evType) {
      row = this.db
        .prepare(
          `SELECT *
           FROM memory_longterm_writeback_changelog
           WHERE change_id = ? AND event_type = ?
           LIMIT 1`
        )
        .get(changeId, evType) || null;
    } else {
      row = this.db
        .prepare(
          `SELECT *
           FROM memory_longterm_writeback_changelog
           WHERE change_id = ?
           ORDER BY created_at_ms DESC
           LIMIT 1`
        )
        .get(changeId) || null;
    }
    return this._parseMemoryLongtermWritebackChangeLogRow(row);
  }

  listMemoryLongtermWritebackChangeLogs({ change_id, event_type, limit } = {}) {
    const changeId = String(change_id || '').trim();
    const evType = String(event_type || '').trim().toLowerCase();
    const lim = Math.max(1, Math.min(500, Number(limit || 100)));
    const where = [];
    const args = [];
    if (changeId) {
      where.push('change_id = ?');
      args.push(changeId);
    }
    if (evType) {
      where.push('event_type = ?');
      args.push(evType);
    }
    args.push(lim);
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const rows = this.db
      .prepare(
        `SELECT *
         FROM memory_longterm_writeback_changelog
         ${whereSql}
         ORDER BY created_at_ms DESC
         LIMIT ?`
      )
      .all(...args);
    return rows.map((row) => this._parseMemoryLongtermWritebackChangeLogRow(row)).filter(Boolean);
  }

  _appendMemoryLongtermWritebackChangeLog({
    log_id,
    event_type,
    change_id,
    candidate_id,
    restored_candidate_id,
    doc_id,
    source_version,
    restored_source_version,
    scope_ref,
    policy_decision,
    evidence_ref,
    actor,
    note,
    created_at_ms,
  } = {}) {
    const eventType = String(event_type || '').trim().toLowerCase();
    if (!['writeback', 'rollback'].includes(eventType)) throw new Error('invalid_change_log_event');
    const changeId = String(change_id || '').trim();
    const docId = String(doc_id || '').trim();
    if (!changeId || !docId) throw new Error('missing_change_log_fields');

    const now = nowMs();
    const createdAt = Math.max(0, Number(created_at_ms || now));
    const logId = String(log_id || '').trim() || `mlog_${uuid()}`;
    const act = actor && typeof actor === 'object' ? actor : {};
    const actorDevice = String(act.device_id || '').trim();
    const actorUser = act.user_id != null ? String(act.user_id).trim() : '';
    const actorApp = String(act.app_id || '').trim();
    const actorProject = act.project_id != null ? String(act.project_id).trim() : '';
    const actorSession = act.session_id != null ? String(act.session_id).trim() : '';
    if (!actorDevice || !actorApp) throw new Error('missing_change_log_actor');

    this.db
      .prepare(
        `INSERT OR IGNORE INTO memory_longterm_writeback_changelog(
           log_id, event_type, change_id, candidate_id, restored_candidate_id, doc_id, source_version, restored_source_version,
           scope_ref_json, policy_decision_json, evidence_ref,
           actor_device_id, actor_user_id, actor_app_id, actor_project_id, actor_session_id,
           note, created_at_ms
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        logId,
        eventType,
        changeId,
        candidate_id != null ? String(candidate_id || '') : null,
        restored_candidate_id != null ? String(restored_candidate_id || '') : null,
        docId,
        source_version != null ? String(source_version || '') : null,
        restored_source_version != null ? String(restored_source_version || '') : null,
        this._safeJsonStringify(scope_ref || {}),
        this._safeJsonStringify(policy_decision || {}),
        evidence_ref != null ? String(evidence_ref || '') : null,
        actorDevice,
        actorUser || null,
        actorApp,
        actorProject || null,
        actorSession || null,
        note != null ? String(note) : null,
        createdAt
      );

    return this.getMemoryLongtermWritebackChangeLog({ change_id: changeId, event_type: eventType });
  }

  _findMemoryLongtermPreviousStableCandidate({ current_candidate } = {}) {
    const cur = current_candidate && typeof current_candidate === 'object' ? current_candidate : null;
    if (!cur) return null;
    const curCandidateId = String(cur.candidate_id || '').trim();
    const curDocId = String(cur.doc_id || '').trim();
    const curDevice = String(cur.created_by_device_id || '').trim();
    const curUser = cur.created_by_user_id != null ? String(cur.created_by_user_id).trim() : '';
    const curApp = String(cur.created_by_app_id || '').trim();
    const curProject = cur.created_by_project_id != null ? String(cur.created_by_project_id).trim() : '';
    const curWrittenAt = Math.max(0, Number(cur.written_at_ms || 0));
    if (!curCandidateId || !curDocId || !curDevice || !curApp) return null;

    const row = this.db
      .prepare(
        `SELECT *
         FROM memory_longterm_writeback_queue
         WHERE doc_id = ?
           AND candidate_id <> ?
           AND status = 'written'
           AND created_by_device_id = ?
           AND created_by_app_id = ?
           AND IFNULL(created_by_user_id, '') = ?
           AND IFNULL(created_by_project_id, '') = ?
           AND written_at_ms <= ?
         ORDER BY written_at_ms DESC, created_at_ms DESC
         LIMIT 1`
      )
      .get(curDocId, curCandidateId, curDevice, curApp, curUser, curProject, curWrittenAt) || null;
    const prev = this._parseMemoryLongtermWritebackCandidateRow(row);
    if (!prev) return null;
    if (!this._scopeRefEquals(cur.scope_ref || {}, prev.scope_ref || {})) return null;
    return prev;
  }

  writebackMemoryMarkdownPendingChange({
    change_id,
    expected_status,
    content_markdown,
    scope_ref,
    provenance_refs,
    policy_decision,
    actor,
    written_at_ms,
    updated_at_ms,
  } = {}) {
    const changeId = String(change_id || '').trim();
    if (!changeId) throw new Error('missing change_id');
    const now = nowMs();
    const writtenAt = Math.max(0, Number(written_at_ms || now));
    const updatedAt = Math.max(0, Number(updated_at_ms || writtenAt));
    const expected = this._normalizeMarkdownPendingChangeStatus(expected_status, 'approved');

    this.db.exec('BEGIN;');
    try {
      const raw = this.db
        .prepare(
          `SELECT *
           FROM memory_markdown_pending_changes
           WHERE change_id = ?
           LIMIT 1`
        )
        .get(changeId) || null;
      const change = this._parseMemoryMarkdownPendingChangeRow(raw);
      if (!change) throw new Error('change_not_found');

      const curStatus = this._normalizeMarkdownPendingChangeStatus(change.status, 'draft');
      if (curStatus === 'written' && change.writeback_ref) {
        const existing = this.getMemoryLongtermWritebackCandidate({ candidate_id: String(change.writeback_ref || '') });
        if (!existing) throw new Error('candidate_not_found');
        const existingLog = this.getMemoryLongtermWritebackChangeLog({ change_id: changeId, event_type: 'writeback' });
        if (!existingLog) throw new Error('writeback_state_corrupt');
        this.db.exec('COMMIT;');
        return { change, candidate: existing, change_log: existingLog };
      }
      if (curStatus !== expected) throw new Error('change_not_approved');

      const act = actor && typeof actor === 'object' ? actor : {};
      const actorDevice = String(act.device_id || '').trim();
      const actorUser = act.user_id != null ? String(act.user_id).trim() : '';
      const actorApp = String(act.app_id || '').trim();
      const actorProject = act.project_id != null ? String(act.project_id).trim() : '';
      const actorSession = act.session_id != null ? String(act.session_id).trim() : '';
      if (!actorDevice || !actorApp) throw new Error('missing_writeback_actor');

      const scopeRefObj = this._normalizeScopeRefObject(scope_ref || {
        device_id: actorDevice,
        user_id: actorUser || '',
        app_id: actorApp,
        project_id: actorProject || '',
        thread_id: '',
      });
      if (!scopeRefObj.device_id || !scopeRefObj.app_id) throw new Error('missing_scope_ref');
      if (!this._scopeRefMatchesActor(scopeRefObj, {
        device_id: actorDevice,
        user_id: actorUser || '',
        app_id: actorApp,
        project_id: actorProject || '',
        thread_id: '',
      })) {
        throw new Error('writeback_scope_mismatch');
      }

      const markdown = content_markdown != null
        ? String(content_markdown)
        : (change.reviewed_markdown ? String(change.reviewed_markdown) : String(change.patched_markdown || ''));
      const candidateId = `mlwb_${uuid()}`;
      const scopeRefJson = this._safeJsonStringify(scopeRefObj);
      const provenanceRefsJson = this._safeJsonStringify(
        Array.isArray(provenance_refs) ? provenance_refs : (Array.isArray(change.provenance_refs) ? change.provenance_refs : [])
      );
      const provenanceRefs = this._safeJsonParse(provenanceRefsJson, []);
      const policyDecisionJson = this._safeJsonStringify(policy_decision || {});
      const evidenceRef = this._buildLongtermWritebackEvidenceRef({
        change,
        candidate: {
          change_id: changeId,
          doc_id: String(change.doc_id || ''),
          source_version: String(change.to_version || ''),
        },
        provenance_refs: Array.isArray(provenanceRefs) ? provenanceRefs : [],
      });

      this.db
        .prepare(
          `INSERT INTO memory_longterm_writeback_queue(
             candidate_id, change_id, edit_session_id, doc_id, base_version, source_version, content_markdown,
             scope_ref_json, provenance_refs_json, policy_decision_json, status,
             created_by_device_id, created_by_user_id, created_by_app_id, created_by_project_id, created_by_session_id,
             created_at_ms, updated_at_ms, written_at_ms, rolled_back_at_ms, evidence_ref
           ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
        )
        .run(
          candidateId,
          changeId,
          String(change.edit_session_id || ''),
          String(change.doc_id || ''),
          String(change.base_version || ''),
          String(change.to_version || ''),
          markdown,
          scopeRefJson,
          provenanceRefsJson,
          policyDecisionJson,
          'written',
          actorDevice,
          actorUser || null,
          actorApp,
          actorProject || null,
          actorSession || null,
          writtenAt,
          updatedAt,
          writtenAt,
          null,
          evidenceRef
        );

      this.db
        .prepare(
          `UPDATE memory_markdown_pending_changes
           SET status = 'written',
               writeback_ref = ?,
               written_at_ms = ?,
               updated_at_ms = ?
           WHERE change_id = ?`
        )
        .run(candidateId, writtenAt, updatedAt, changeId);

      const editSessionId = String(change.edit_session_id || '').trim();
      if (editSessionId) {
        this.db
          .prepare(
            `UPDATE memory_markdown_edit_sessions
             SET status = CASE WHEN status = 'active' THEN 'closed' ELSE status END,
                 updated_at_ms = CASE WHEN updated_at_ms < ? THEN ? ELSE updated_at_ms END
             WHERE edit_session_id = ?`
          )
          .run(updatedAt, updatedAt, editSessionId);
      }

      const nextChange = this.getMemoryMarkdownPendingChange({ change_id: changeId });
      const candidate = this.getMemoryLongtermWritebackCandidate({ candidate_id: candidateId });
      const changeLog = this._appendMemoryLongtermWritebackChangeLog({
        event_type: 'writeback',
        change_id: changeId,
        candidate_id: candidateId,
        restored_candidate_id: null,
        doc_id: String(change.doc_id || ''),
        source_version: String(change.to_version || ''),
        restored_source_version: null,
        scope_ref: scopeRefObj,
        policy_decision: policy_decision || {},
        evidence_ref: evidenceRef,
        actor: {
          device_id: actorDevice,
          user_id: actorUser || null,
          app_id: actorApp,
          project_id: actorProject || null,
          session_id: actorSession || null,
        },
        note: null,
        created_at_ms: writtenAt,
      });
      this.db.exec('COMMIT;');
      return { change: nextChange, candidate, change_log: changeLog };
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
  }

  rollbackMemoryMarkdownPendingChange({
    change_id,
    expected_status,
    actor,
    rollback_note,
    rolled_back_at_ms,
    updated_at_ms,
  } = {}) {
    const changeId = String(change_id || '').trim();
    if (!changeId) throw new Error('missing change_id');
    const expected = this._normalizeMarkdownPendingChangeStatus(expected_status, 'written');
    const now = nowMs();
    const rolledBackAt = Math.max(0, Number(rolled_back_at_ms || now));
    const updatedAt = Math.max(0, Number(updated_at_ms || rolledBackAt));
    const act = actor && typeof actor === 'object' ? actor : {};
    const actorDevice = String(act.device_id || '').trim();
    const actorUser = act.user_id != null ? String(act.user_id).trim() : '';
    const actorApp = String(act.app_id || '').trim();
    const actorProject = act.project_id != null ? String(act.project_id).trim() : '';
    const actorSession = act.session_id != null ? String(act.session_id).trim() : '';
    if (!actorDevice || !actorApp) throw new Error('missing_rollback_actor');

    this.db.exec('BEGIN;');
    try {
      const raw = this.db
        .prepare(
          `SELECT *
           FROM memory_markdown_pending_changes
           WHERE change_id = ?
           LIMIT 1`
        )
        .get(changeId) || null;
      const change = this._parseMemoryMarkdownPendingChangeRow(raw);
      if (!change) throw new Error('change_not_found');

      const curStatus = this._normalizeMarkdownPendingChangeStatus(change.status, 'draft');
      if (curStatus === 'rolled_back' && change.rollback_ref) {
        const existingCandidate = this.getMemoryLongtermWritebackCandidate({ candidate_id: String(change.writeback_ref || '') });
        const existingRestored = this.getMemoryLongtermWritebackCandidate({ candidate_id: String(change.rollback_ref || '') });
        const existingLog = this.getMemoryLongtermWritebackChangeLog({ change_id: changeId, event_type: 'rollback' });
        if (!existingCandidate || !existingRestored || !existingLog) {
          throw new Error('rollback_state_corrupt');
        }
        this.db.exec('COMMIT;');
        return {
          change,
          candidate: existingCandidate,
          restored_candidate: existingRestored,
          change_log: existingLog,
        };
      }
      if (curStatus !== expected) throw new Error('change_not_written');
      const writebackRef = String(change.writeback_ref || '').trim();
      if (!writebackRef) throw new Error('writeback_ref_missing');

      const candidate = this.getMemoryLongtermWritebackCandidate({ candidate_id: writebackRef });
      if (!candidate) throw new Error('candidate_not_found');
      if (String(candidate.status || '').trim().toLowerCase() !== 'written') {
        throw new Error('candidate_not_written');
      }

      if (!this._scopeRefMatchesActor(candidate.scope_ref || {}, {
        device_id: actorDevice,
        user_id: actorUser || '',
        app_id: actorApp,
        project_id: actorProject || '',
        thread_id: '',
      })) {
        throw new Error('rollback_scope_mismatch');
      }

      const restored = this._findMemoryLongtermPreviousStableCandidate({ current_candidate: candidate });
      if (!restored) throw new Error('rollback_target_not_found');
      if (!this._scopeRefEquals(candidate.scope_ref || {}, restored.scope_ref || {})) {
        throw new Error('rollback_scope_mismatch');
      }

      this.db
        .prepare(
          `UPDATE memory_longterm_writeback_queue
           SET status = 'rolled_back',
               rolled_back_at_ms = ?,
               updated_at_ms = ?
           WHERE candidate_id = ?`
        )
        .run(rolledBackAt, updatedAt, String(candidate.candidate_id || ''));

      this.db
        .prepare(
          `UPDATE memory_markdown_pending_changes
           SET status = 'rolled_back',
               rollback_ref = ?,
               rolled_back_at_ms = ?,
               rolled_back_by_device_id = ?,
               rolled_back_by_user_id = ?,
               rolled_back_by_app_id = ?,
               rolled_back_by_project_id = ?,
               rolled_back_by_session_id = ?,
               updated_at_ms = ?
           WHERE change_id = ?`
        )
        .run(
          String(restored.candidate_id || ''),
          rolledBackAt,
          actorDevice,
          actorUser || null,
          actorApp,
          actorProject || null,
          actorSession || null,
          updatedAt,
          changeId
        );

      const evidenceRef = String(candidate.evidence_ref || '').trim()
        || this._buildLongtermWritebackEvidenceRef({
          change,
          candidate,
          provenance_refs: Array.isArray(candidate.provenance_refs) ? candidate.provenance_refs : [],
        });
      const changeLog = this._appendMemoryLongtermWritebackChangeLog({
        event_type: 'rollback',
        change_id: changeId,
        candidate_id: String(candidate.candidate_id || ''),
        restored_candidate_id: String(restored.candidate_id || ''),
        doc_id: String(candidate.doc_id || change.doc_id || ''),
        source_version: String(candidate.source_version || ''),
        restored_source_version: String(restored.source_version || ''),
        scope_ref: candidate.scope_ref || {},
        policy_decision: {
          source: 'longterm_markdown_rollback',
          rollback_note: rollback_note != null ? String(rollback_note) : '',
          rollback_from_candidate_id: String(candidate.candidate_id || ''),
          restored_candidate_id: String(restored.candidate_id || ''),
        },
        evidence_ref: evidenceRef,
        actor: {
          device_id: actorDevice,
          user_id: actorUser || null,
          app_id: actorApp,
          project_id: actorProject || null,
          session_id: actorSession || null,
        },
        note: rollback_note != null ? String(rollback_note) : null,
        created_at_ms: rolledBackAt,
      });

      const nextChange = this.getMemoryMarkdownPendingChange({ change_id: changeId });
      const nextCandidate = this.getMemoryLongtermWritebackCandidate({ candidate_id: String(candidate.candidate_id || '') });
      const nextRestored = this.getMemoryLongtermWritebackCandidate({ candidate_id: String(restored.candidate_id || '') });
      this.db.exec('COMMIT;');
      return {
        change: nextChange,
        candidate: nextCandidate,
        restored_candidate: nextRestored,
        change_log: changeLog,
      };
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
  }

  // -------------------- Pairing (HTTP) --------------------

  getConnectorWebhookReplayGuardStats() {
    const row = this.db
      .prepare(
        `SELECT COUNT(*) AS total
         FROM connector_webhook_replay_guard`
      )
      .get() || null;
    return {
      entries: Math.max(0, Number(row?.total || 0)),
    };
  }

  pruneConnectorWebhookReplayGuard({ now_ms, stale_window_ms } = {}) {
    const now = Math.max(0, Number(now_ms || nowMs()));
    const staleWindowMs = Math.max(0, Number(stale_window_ms || 0));
    let pruned = 0;

    const byExpiry = this.db
      .prepare(
        `DELETE FROM connector_webhook_replay_guard
         WHERE expire_at_ms <= ?`
      )
      .run(now);
    pruned += Math.max(0, Number(byExpiry?.changes || 0));

    if (staleWindowMs > 0) {
      const staleCutoff = Math.max(0, now - staleWindowMs);
      const byStale = this.db
        .prepare(
          `DELETE FROM connector_webhook_replay_guard
           WHERE last_seen_at_ms <= ?`
        )
        .run(staleCutoff);
      pruned += Math.max(0, Number(byStale?.changes || 0));
    }

    const stats = this.getConnectorWebhookReplayGuardStats();
    return {
      pruned,
      entries: Math.max(0, Number(stats.entries || 0)),
    };
  }

  claimConnectorWebhookReplay({
    connector,
    target_id,
    replay_key_hash,
    first_seen_at_ms,
    expire_at_ms,
    max_entries,
    stale_window_ms,
  } = {}) {
    const connectorId = String(connector || '').trim().toLowerCase();
    const targetId = String(target_id || '').trim();
    const replayKeyHash = String(replay_key_hash || '').trim().toLowerCase();
    const firstSeenAtMs = Math.max(0, Number(first_seen_at_ms || nowMs()));
    const expireAtMs = Math.max(firstSeenAtMs + 1, Number(expire_at_ms || (firstSeenAtMs + 1)));
    const maxEntries = Math.max(64, Math.min(1_000_000, Math.floor(Number(max_entries || 20_000))));
    const staleWindowMs = Math.max(0, Number(stale_window_ms || 0));

    if (!connectorId || !targetId || !replayKeyHash) {
      return {
        ok: false,
        deny_code: 'invalid_replay_key',
        entries: Math.max(0, Number(this.getConnectorWebhookReplayGuardStats().entries || 0)),
      };
    }

    this.db.exec('BEGIN;');
    try {
      this.db
        .prepare(
          `DELETE FROM connector_webhook_replay_guard
           WHERE expire_at_ms <= ?`
        )
        .run(firstSeenAtMs);
      if (staleWindowMs > 0) {
        const staleCutoff = Math.max(0, firstSeenAtMs - staleWindowMs);
        this.db
          .prepare(
            `DELETE FROM connector_webhook_replay_guard
             WHERE last_seen_at_ms <= ?`
          )
          .run(staleCutoff);
      }

      const existing = this.db
        .prepare(
          `SELECT expire_at_ms
           FROM connector_webhook_replay_guard
           WHERE connector = ?
             AND target_id = ?
             AND replay_key_hash = ?
           LIMIT 1`
        )
        .get(connectorId, targetId, replayKeyHash) || null;

      if (existing && Number(existing.expire_at_ms || 0) > firstSeenAtMs) {
        const countRow = this.db
          .prepare(`SELECT COUNT(*) AS total FROM connector_webhook_replay_guard`)
          .get() || null;
        const entries = Math.max(0, Number(countRow?.total || 0));
        this.db.exec('COMMIT;');
        return {
          ok: false,
          deny_code: 'replay_detected',
          entries,
          expire_at_ms: Math.max(0, Number(existing.expire_at_ms || 0)),
        };
      }

      if (existing) {
        this.db
          .prepare(
            `UPDATE connector_webhook_replay_guard
             SET first_seen_at_ms = ?,
                 expire_at_ms = ?,
                 last_seen_at_ms = ?
             WHERE connector = ?
               AND target_id = ?
               AND replay_key_hash = ?`
          )
          .run(firstSeenAtMs, expireAtMs, firstSeenAtMs, connectorId, targetId, replayKeyHash);
      } else {
        const countRow = this.db
          .prepare(`SELECT COUNT(*) AS total FROM connector_webhook_replay_guard`)
          .get() || null;
        const entries = Math.max(0, Number(countRow?.total || 0));
        if (entries >= maxEntries) {
          this.db.exec('COMMIT;');
          return {
            ok: false,
            deny_code: 'replay_store_overflow',
            entries,
          };
        }

        this.db
          .prepare(
            `INSERT INTO connector_webhook_replay_guard(
               connector, target_id, replay_key_hash,
               first_seen_at_ms, expire_at_ms, last_seen_at_ms
             ) VALUES(?,?,?,?,?,?)`
          )
          .run(connectorId, targetId, replayKeyHash, firstSeenAtMs, expireAtMs, firstSeenAtMs);
      }

      const countRow = this.db
        .prepare(`SELECT COUNT(*) AS total FROM connector_webhook_replay_guard`)
        .get() || null;
      const entries = Math.max(0, Number(countRow?.total || 0));
      this.db.exec('COMMIT;');
      return {
        ok: true,
        entries,
        expire_at_ms: expireAtMs,
      };
    } catch (e) {
      try { this.db.exec('ROLLBACK;'); } catch { /* ignore */ }
      throw e;
    }
  }

  createPairingRequest(fields) {
    const now = nowMs();
    const pairing_request_id = uuid();
    const pairing_secret_hash = String(fields?.pairing_secret_hash || '').trim();
    const app_id = String(fields?.app_id || '').trim();

    if (!pairing_secret_hash) throw new Error('missing pairing_secret_hash');
    if (!app_id) throw new Error('missing app_id');

    const request_id = fields?.request_id ? String(fields.request_id) : null;
    const claimed_device_id = fields?.claimed_device_id ? String(fields.claimed_device_id) : null;
    const user_id = fields?.user_id ? String(fields.user_id) : null;
    const device_name = fields?.device_name ? String(fields.device_name) : null;
    const device_info_json = fields?.device_info_json ? String(fields.device_info_json) : null;
    const requested_scopes_json = fields?.requested_scopes_json ? String(fields.requested_scopes_json) : null;
    const peer_ip = fields?.peer_ip ? String(fields.peer_ip) : null;
    const created_at_ms = Number(fields?.created_at_ms || 0) > 0 ? Number(fields.created_at_ms) : now;

    this.db
      .prepare(
        `INSERT INTO pairing_requests(
           pairing_request_id, pairing_secret_hash, request_id, claimed_device_id, user_id, app_id,
           device_name, device_info_json, requested_scopes_json, peer_ip,
           status, created_at_ms
         )
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        pairing_request_id,
        pairing_secret_hash,
        request_id,
        claimed_device_id,
        user_id,
        app_id,
        device_name,
        device_info_json,
        requested_scopes_json,
        peer_ip,
        'pending',
        created_at_ms
      );

    return this.getPairingRequest(pairing_request_id);
  }

  getPairingRequest(pairingRequestId) {
    const id = String(pairingRequestId || '').trim();
    if (!id) return null;
    const r = this.db
      .prepare(`SELECT * FROM pairing_requests WHERE pairing_request_id = ? LIMIT 1`)
      .get(id);
    return r || null;
  }

  listPairingRequests(filters) {
    const status = String(filters?.status || '').trim().toLowerCase();
    const lim = Math.max(1, Math.min(500, Number(filters?.limit || 200)));

    const wh = [];
    const args = [];
    if (status && status !== 'all') {
      wh.push('status = ?');
      args.push(status);
    }
    const where = wh.length ? `WHERE ${wh.join(' AND ')}` : '';
    const sql = `SELECT * FROM pairing_requests ${where} ORDER BY created_at_ms DESC LIMIT ${lim}`;
    return this.db.prepare(sql).all(...args);
  }

  approvePairingRequest(pairingRequestId, fields) {
    const id = String(pairingRequestId || '').trim();
    if (!id) throw new Error('missing pairing_request_id');

    const now = nowMs();
    const decided_at_ms = Number(fields?.decided_at_ms || 0) > 0 ? Number(fields.decided_at_ms) : now;
    const approved_device_id = String(fields?.approved_device_id || '').trim();
    const approved_client_token = String(fields?.approved_client_token || '').trim();
    const user_id = fields?.user_id != null ? String(fields.user_id) : null;

    if (!approved_device_id) throw new Error('missing approved_device_id');
    if (!approved_client_token) throw new Error('missing approved_client_token');

    const device_name = fields?.device_name != null ? String(fields.device_name) : null;
    const approved_capabilities_json = fields?.approved_capabilities_json != null ? String(fields.approved_capabilities_json) : null;
    const approved_allowed_cidrs_json = fields?.approved_allowed_cidrs_json != null ? String(fields.approved_allowed_cidrs_json) : null;
    const policy_mode = fields?.policy_mode != null ? String(fields.policy_mode) : 'legacy_grant';
    const approved_trust_profile_json = fields?.approved_trust_profile_json != null ? String(fields.approved_trust_profile_json) : null;

    this.db
      .prepare(
        `UPDATE pairing_requests
         SET status = 'approved',
             user_id = COALESCE(?, user_id),
             device_name = COALESCE(?, device_name),
             deny_reason = NULL,
             approved_device_id = ?,
             approved_client_token = ?,
             approved_capabilities_json = ?,
             approved_allowed_cidrs_json = ?,
             policy_mode = ?,
             approved_trust_profile_json = ?,
             decided_at_ms = ?
         WHERE pairing_request_id = ?`
      )
      .run(
        user_id,
        device_name,
        approved_device_id,
        approved_client_token,
        approved_capabilities_json,
        approved_allowed_cidrs_json,
        policy_mode,
        approved_trust_profile_json,
        decided_at_ms,
        id
      );

    return this.getPairingRequest(id);
  }

  denyPairingRequest(pairingRequestId, fields) {
    const id = String(pairingRequestId || '').trim();
    if (!id) throw new Error('missing pairing_request_id');

    const now = nowMs();
    const decided_at_ms = Number(fields?.decided_at_ms || 0) > 0 ? Number(fields.decided_at_ms) : now;
    const deny_reason = fields?.deny_reason != null ? String(fields.deny_reason) : null;

    this.db
      .prepare(
        `UPDATE pairing_requests
         SET status = 'denied',
             deny_reason = ?,
             decided_at_ms = ?
         WHERE pairing_request_id = ?`
      )
      .run(deny_reason, decided_at_ms, id);

    return this.getPairingRequest(id);
  }

  markPairingTokenClaimed(pairingRequestId, claimedAtMs) {
    const id = String(pairingRequestId || '').trim();
    if (!id) return null;
    const now = nowMs();
    const ts = Number(claimedAtMs || 0) > 0 ? Number(claimedAtMs) : now;
    this.db.prepare(`UPDATE pairing_requests SET token_claimed_at_ms = ? WHERE pairing_request_id = ?`).run(ts, id);
    return this.getPairingRequest(id);
  }
}
