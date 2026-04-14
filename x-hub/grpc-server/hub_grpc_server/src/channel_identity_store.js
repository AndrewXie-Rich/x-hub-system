import { normalizeChannelProviderId } from './channel_registry.js';
import { nowMs, uuid } from './util.js';

export const CHANNEL_IDENTITY_BINDING_SCHEMA = 'xhub.im_identity_binding.v1';
export const CHANNEL_IDENTITY_ROLES = Object.freeze([
  'viewer',
  'operator',
  'approval_only_identity',
  'release_manager',
  'ops_admin',
]);
export const CHANNEL_IDENTITY_ACCESS_GROUPS = Object.freeze([
  'dm_allowlist',
  'group_allowlist',
  'thread_allowlist',
  'approval_only_identity',
]);

export const CHANNEL_IDENTITY_STATUSES = Object.freeze([
  'active',
  'disabled',
  'revoked',
]);

const CHANNEL_IDENTITY_ROLE_SET = new Set(CHANNEL_IDENTITY_ROLES);
const CHANNEL_IDENTITY_ACCESS_GROUP_SET = new Set(CHANNEL_IDENTITY_ACCESS_GROUPS);
const CHANNEL_IDENTITY_STATUS_SET = new Set(CHANNEL_IDENTITY_STATUSES);
const CHANNEL_IDENTITY_TABLES_INIT = new WeakSet();

function safeString(input) {
  return String(input ?? '').trim();
}

function parseBoolLike(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function parseJsonArray(input) {
  if (Array.isArray(input)) return input;
  const text = safeString(input);
  if (!text) return [];
  try {
    const out = JSON.parse(text);
    return Array.isArray(out) ? out : [];
  } catch {
    return [];
  }
}

function normalizeRole(input) {
  const key = safeString(input)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!key) return '';
  if (key === 'approver') return 'approval_only_identity';
  if (key === 'admin' || key === 'opsadmin') return 'ops_admin';
  return CHANNEL_IDENTITY_ROLE_SET.has(key) ? key : key;
}

export function normalizeChannelRoles(input) {
  const rows = Array.isArray(input) ? input : [];
  const out = [];
  const seen = new Set();
  for (const raw of rows) {
    const role = normalizeRole(raw);
    if (!role || seen.has(role)) continue;
    seen.add(role);
    out.push(role);
  }
  return out;
}

function normalizeAccessGroup(input) {
  const key = safeString(input)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!key) return '';
  if (key === 'dm') return 'dm_allowlist';
  if (key === 'group') return 'group_allowlist';
  if (key === 'thread' || key === 'topic') return 'thread_allowlist';
  if (key === 'approver' || key === 'approval_only') return 'approval_only_identity';
  return CHANNEL_IDENTITY_ACCESS_GROUP_SET.has(key) ? key : '';
}

export function normalizeChannelAccessGroups(input) {
  const rows = Array.isArray(input) ? input : [];
  const out = [];
  const seen = new Set();
  for (const raw of rows) {
    const group = normalizeAccessGroup(raw);
    if (!group || seen.has(group)) continue;
    seen.add(group);
    out.push(group);
  }
  return out;
}

export function buildChannelStableExternalId({
  provider,
  stable_external_id = '',
  external_user_id = '',
  external_tenant_id = '',
} = {}) {
  const explicit = safeString(stable_external_id);
  if (explicit) return explicit;
  const providerId = normalizeChannelProviderId(provider) || '';
  const externalUserId = safeString(external_user_id);
  if (!providerId || !externalUserId) return '';
  return `${providerId}/${safeString(external_tenant_id) || '_'}/${externalUserId}`;
}

export function normalizeChannelIdentityStatus(input, fallback = 'active') {
  const status = safeString(input).toLowerCase();
  return CHANNEL_IDENTITY_STATUS_SET.has(status) ? status : fallback;
}

export function makeChannelIdentityActorRef(binding) {
  const stableExternalId = buildChannelStableExternalId(binding);
  return stableExternalId ? `${CHANNEL_IDENTITY_BINDING_SCHEMA}:${stableExternalId}` : '';
}

function identityKey({ stable_external_id }) {
  return safeString(stable_external_id);
}

function ensureColumn(db, tableName, columnName, columnSql) {
  if (db && typeof db._ensureColumn === 'function') {
    db._ensureColumn(tableName, columnName, columnSql);
  }
}

function ensureDb(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.exec !== 'function') {
    throw new Error('channel_identity_store_db_required');
  }
  db.db.exec(`
    CREATE TABLE IF NOT EXISTS channel_identity_bindings (
      identity_key TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      provider TEXT NOT NULL,
      stable_external_id TEXT NOT NULL,
      external_user_id TEXT NOT NULL,
      external_tenant_id TEXT NOT NULL,
      hub_user_id TEXT NOT NULL,
      roles_json TEXT NOT NULL,
      access_groups_json TEXT NOT NULL,
      approval_only INTEGER NOT NULL,
      status TEXT NOT NULL,
      synced_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      audit_ref TEXT
    );

    CREATE UNIQUE INDEX IF NOT EXISTS idx_channel_identity_bindings_lookup
      ON channel_identity_bindings(provider, external_tenant_id, external_user_id);

    CREATE INDEX IF NOT EXISTS idx_channel_identity_bindings_hub_user
      ON channel_identity_bindings(hub_user_id, status, updated_at_ms);
  `);
  ensureColumn(db, 'channel_identity_bindings', 'stable_external_id', `TEXT NOT NULL DEFAULT ''`);
  ensureColumn(db, 'channel_identity_bindings', 'access_groups_json', `TEXT NOT NULL DEFAULT '[]'`);
  try {
    db.db.exec(`
      UPDATE channel_identity_bindings
      SET stable_external_id = lower(trim(provider)) || '/' ||
        CASE
          WHEN trim(coalesce(external_tenant_id, '')) = '' THEN '_'
          ELSE trim(external_tenant_id)
        END || '/' || trim(external_user_id)
      WHERE trim(coalesce(stable_external_id, '')) = ''
    `);
  } catch {
    // best-effort migration
  }
  try {
    db.db.exec(`
      UPDATE channel_identity_bindings
      SET identity_key = stable_external_id
      WHERE trim(coalesce(stable_external_id, '')) <> ''
        AND identity_key <> stable_external_id
    `);
  } catch {
    // best-effort migration
  }
  try {
    db.db.exec(`
      UPDATE channel_identity_bindings
      SET access_groups_json = '[]'
      WHERE trim(coalesce(access_groups_json, '')) = ''
    `);
  } catch {
    // best-effort migration
  }
  try {
    db.db.exec(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_channel_identity_bindings_stable_external
        ON channel_identity_bindings(stable_external_id)
    `);
  } catch {
    // best-effort migration
  }
  CHANNEL_IDENTITY_TABLES_INIT.add(db);
}

function parseIdentityRow(row) {
  if (!row || typeof row !== 'object') return null;
  const binding = {
    schema_version: safeString(row.schema_version) || CHANNEL_IDENTITY_BINDING_SCHEMA,
    provider: safeString(row.provider).toLowerCase(),
    stable_external_id: safeString(row.stable_external_id),
    external_user_id: safeString(row.external_user_id),
    external_tenant_id: safeString(row.external_tenant_id),
    hub_user_id: safeString(row.hub_user_id),
    roles: normalizeChannelRoles(parseJsonArray(row.roles_json)),
    access_groups: normalizeChannelAccessGroups(parseJsonArray(row.access_groups_json)),
    approval_only: !!Number(row.approval_only || 0),
    status: normalizeChannelIdentityStatus(row.status, 'disabled'),
    synced_at_ms: safeInt(row.synced_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
  binding.actor_ref = makeChannelIdentityActorRef(binding);
  return binding;
}

export function normalizeChannelIdentityBinding(input = {}, options = {}) {
  const now = safeInt(options.now_ms, nowMs()) || nowMs();
  const provider = normalizeChannelProviderId(input.provider || input.channel || input.provider_id) || '';
  const external_user_id = safeString(input.external_user_id || input.user_id);
  const external_tenant_id = safeString(input.external_tenant_id || input.tenant_id);
  const hub_user_id = safeString(input.hub_user_id || input.user_ref);
  const roles = normalizeChannelRoles(input.roles || []);
  const stable_external_id = buildChannelStableExternalId({
    provider,
    stable_external_id: input.stable_external_id,
    external_user_id,
    external_tenant_id,
  });
  const access_groups = normalizeChannelAccessGroups(input.access_groups || []);
  const approval_only = parseBoolLike(
    input.approval_only,
    roles.includes('approval_only_identity') || access_groups.includes('approval_only_identity')
  );
  const normalizedAccessGroups = normalizeChannelAccessGroups(
    approval_only ? [...access_groups, 'approval_only_identity'] : access_groups
  );
  const status = normalizeChannelIdentityStatus(input.status, 'active');
  const synced_at_ms = safeInt(input.synced_at_ms, now) || now;
  const updated_at_ms = safeInt(input.updated_at_ms, now) || now;
  const binding = {
    schema_version: CHANNEL_IDENTITY_BINDING_SCHEMA,
    provider,
    stable_external_id,
    external_user_id,
    external_tenant_id,
    hub_user_id,
    roles,
    access_groups: normalizedAccessGroups,
    approval_only: approval_only || roles.includes('approval_only_identity'),
    status,
    synced_at_ms,
    updated_at_ms,
    audit_ref: safeString(input.audit_ref),
  };
  binding.actor_ref = makeChannelIdentityActorRef(binding);
  binding.identity_key = identityKey(binding);
  return binding;
}

function identityDeny(deny_code, detail = {}, binding = null) {
  return {
    ok: false,
    deny_code: safeString(deny_code) || 'identity_binding_rejected',
    detail: detail && typeof detail === 'object' ? detail : {},
    binding,
    audit_logged: false,
    created: false,
    updated: false,
  };
}

function appendIdentityAudit({
  db,
  event_type,
  binding,
  request_id = '',
  audit = {},
  ok = true,
  error_code = '',
  error_message = '',
  created = false,
  updated = false,
}) {
  const created_at_ms = nowMs();
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type,
    created_at_ms,
    severity: ok ? 'info' : 'warn',
    device_id: safeString(audit.device_id || 'channel_identity_store'),
    user_id: safeString(audit.user_id) || null,
    app_id: safeString(audit.app_id || 'channel_identity_store'),
    project_id: safeString(audit.project_id) || null,
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: 'channel.identity_binding.write',
    model_id: null,
    ok: !!ok,
    error_code: ok ? null : (safeString(error_code) || 'identity_binding_rejected'),
    error_message: ok ? null : (safeString(error_message) || 'identity_binding_rejected'),
    ext_json: JSON.stringify({
      schema_version: CHANNEL_IDENTITY_BINDING_SCHEMA,
      provider: binding.provider,
      stable_external_id: binding.stable_external_id,
      external_user_id: binding.external_user_id,
      external_tenant_id: binding.external_tenant_id,
      hub_user_id: binding.hub_user_id,
      roles: binding.roles,
      access_groups: binding.access_groups,
      approval_only: binding.approval_only,
      status: binding.status,
      created,
      updated,
    }),
  });
}

export function getChannelIdentityBinding(db, {
  stable_external_id = '',
  provider,
  external_user_id,
  external_tenant_id = '',
} = {}) {
  ensureDb(db);
  const stableExternalId = safeString(stable_external_id);
  if (stableExternalId) {
    const row = db.db
      .prepare(
        `SELECT *
         FROM channel_identity_bindings
         WHERE stable_external_id = ?
         LIMIT 1`
      )
      .get(stableExternalId);
    return parseIdentityRow(row);
  }
  const providerId = normalizeChannelProviderId(provider) || '';
  const externalUserId = safeString(external_user_id);
  const externalTenantId = safeString(external_tenant_id);
  if (!providerId || !externalUserId) return null;
  const row = db.db
    .prepare(
      `SELECT *
       FROM channel_identity_bindings
       WHERE provider = ?
         AND external_tenant_id = ?
         AND external_user_id = ?
       LIMIT 1`
    )
    .get(providerId, externalTenantId, externalUserId);
  return parseIdentityRow(row);
}

export function listChannelIdentityBindings(db, filters = {}) {
  ensureDb(db);
  const where = [];
  const args = [];
  const provider = normalizeChannelProviderId(filters.provider) || '';
  const stableExternalId = safeString(filters.stable_external_id);
  const hubUserId = safeString(filters.hub_user_id);
  const externalTenantId = safeString(filters.external_tenant_id);
  const status = safeString(filters.status).toLowerCase();

  if (provider) {
    where.push('provider = ?');
    args.push(provider);
  }
  if (stableExternalId) {
    where.push('stable_external_id = ?');
    args.push(stableExternalId);
  }
  if (hubUserId) {
    where.push('hub_user_id = ?');
    args.push(hubUserId);
  }
  if (externalTenantId) {
    where.push('external_tenant_id = ?');
    args.push(externalTenantId);
  }
  if (CHANNEL_IDENTITY_STATUS_SET.has(status)) {
    where.push('status = ?');
    args.push(status);
  }

  const limit = Math.max(1, Math.min(500, safeInt(filters.limit, 200) || 200));
  const sql = `
    SELECT *
    FROM channel_identity_bindings
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY updated_at_ms DESC, provider ASC, stable_external_id ASC
    LIMIT ${limit}
  `;
  return db.db.prepare(sql).all(...args).map((row) => parseIdentityRow(row)).filter(Boolean);
}

export function upsertChannelIdentityBinding(db, {
  binding = {},
  audit = {},
  request_id = '',
} = {}) {
  ensureDb(db);
  db.db.exec('BEGIN;');
  try {
    const out = upsertChannelIdentityBindingTx(db, {
      binding,
      audit,
      request_id,
    });
    if (!out.ok) {
      db.db.exec('ROLLBACK;');
      return out;
    }
    db.db.exec('COMMIT;');
    return out;
  } catch (err) {
    try {
      db.db.exec('ROLLBACK;');
    } catch {
      // ignore
    }
    const normalized = normalizeChannelIdentityBinding(binding);
    return identityDeny('audit_write_failed', {
      message: safeString(err?.message || 'audit_write_failed'),
    }, normalized);
  }
}

export function upsertChannelIdentityBindingTx(db, {
  binding = {},
  audit = {},
  request_id = '',
} = {}) {
  ensureDb(db);
  const normalized = normalizeChannelIdentityBinding(binding);
  if (!normalized.provider) {
    return identityDeny('provider_unknown');
  }
  if (!normalized.stable_external_id) {
    return identityDeny('stable_external_id_missing', {}, normalized);
  }
  if (!normalized.external_user_id) {
    return identityDeny('external_user_id_missing', {}, normalized);
  }
  if (!normalized.hub_user_id) {
    return identityDeny('hub_user_id_missing');
  }
  if (normalized.status === 'active' && !normalized.roles.length) {
    return identityDeny('roles_missing', {}, normalized);
  }
  if (normalized.status === 'active' && !normalized.access_groups.length) {
    return identityDeny('access_groups_missing', {}, normalized);
  }

  const existing = getChannelIdentityBinding(db, normalized);
  const created = !existing;
  const updated = !!existing;
  const auditRef = appendIdentityAudit({
    db,
    event_type: 'channel.identity_binding.upserted',
    binding: normalized,
    request_id,
    audit,
    ok: true,
    created,
    updated,
  });
  const ts = nowMs();
  db.db
    .prepare(
      `INSERT INTO channel_identity_bindings(
         identity_key, schema_version, provider, stable_external_id, external_user_id, external_tenant_id,
         hub_user_id, roles_json, access_groups_json, approval_only, status, synced_at_ms, updated_at_ms, audit_ref
       ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(identity_key) DO UPDATE SET
         schema_version = excluded.schema_version,
         stable_external_id = excluded.stable_external_id,
         hub_user_id = excluded.hub_user_id,
         roles_json = excluded.roles_json,
         access_groups_json = excluded.access_groups_json,
         approval_only = excluded.approval_only,
         status = excluded.status,
         synced_at_ms = excluded.synced_at_ms,
         updated_at_ms = excluded.updated_at_ms,
         audit_ref = excluded.audit_ref`
    )
    .run(
      normalized.identity_key,
      normalized.schema_version,
      normalized.provider,
      normalized.stable_external_id,
      normalized.external_user_id,
      normalized.external_tenant_id,
      normalized.hub_user_id,
      JSON.stringify(normalized.roles),
      JSON.stringify(normalized.access_groups),
      normalized.approval_only ? 1 : 0,
      normalized.status,
      normalized.synced_at_ms,
      ts,
      auditRef
    );
  const row = getChannelIdentityBinding(db, normalized);
  return {
    ok: true,
    deny_code: '',
    detail: {},
    binding: row,
    audit_logged: true,
    created,
    updated,
  };
}
