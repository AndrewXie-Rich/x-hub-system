import { getChannelProviderMeta, normalizeChannelProviderId } from './channel_registry.js';
import { channelDeliveryContextKey } from './channel_delivery_context.js';
import {
  normalizeChannelApprovalSurface,
  normalizeChannelThreadingMode,
} from './channel_types.js';
import { nowMs, uuid } from './util.js';

export const SUPERVISOR_OPERATOR_CHANNEL_BINDING_SCHEMA = 'xhub.supervisor_operator_channel_binding.v1';

export const SUPERVISOR_CHANNEL_BINDING_STATUSES = Object.freeze([
  'active',
  'disabled',
  'revoked',
]);

export const SUPERVISOR_CHANNEL_SCOPES = Object.freeze([
  'dm',
  'group',
]);

export const SUPERVISOR_SCOPE_TYPES = Object.freeze([
  'project',
  'incident',
  'device',
]);

const BINDING_STATUS_SET = new Set(SUPERVISOR_CHANNEL_BINDING_STATUSES);
const CHANNEL_SCOPE_SET = new Set(SUPERVISOR_CHANNEL_SCOPES);
const SCOPE_TYPE_SET = new Set(SUPERVISOR_SCOPE_TYPES);
const CHANNEL_BINDINGS_TABLES_INIT = new WeakSet();

function safeString(input) {
  return String(input ?? '').trim();
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

function normalizeActionName(input) {
  return safeString(input).toLowerCase();
}

function normalizeActionList(input) {
  const rows = Array.isArray(input) ? input : [];
  const out = [];
  const seen = new Set();
  for (const raw of rows) {
    const action = normalizeActionName(raw);
    if (!action || seen.has(action)) continue;
    seen.add(action);
    out.push(action);
  }
  return out;
}

export function normalizeSupervisorChannelBindingStatus(input, fallback = 'active') {
  const status = safeString(input).toLowerCase();
  return BINDING_STATUS_SET.has(status) ? status : fallback;
}

export function normalizeSupervisorChannelScope(input, fallback = 'group') {
  const scope = safeString(input).toLowerCase();
  if (scope === 'direct' || scope === 'direct_message') return 'dm';
  if (scope === 'channel' || scope === 'room') return 'group';
  return CHANNEL_SCOPE_SET.has(scope) ? scope : fallback;
}

export function normalizeSupervisorScopeType(input, fallback = 'project') {
  const scopeType = safeString(input).toLowerCase();
  return SCOPE_TYPE_SET.has(scopeType) ? scopeType : fallback;
}

function ensureDb(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.exec !== 'function') {
    throw new Error('channel_bindings_store_db_required');
  }
  if (CHANNEL_BINDINGS_TABLES_INIT.has(db)) return;
  db.db.exec(`
    CREATE TABLE IF NOT EXISTS supervisor_operator_channel_bindings (
      binding_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      provider TEXT NOT NULL,
      account_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      thread_key TEXT NOT NULL,
      route_key TEXT NOT NULL,
      channel_scope TEXT NOT NULL,
      scope_type TEXT NOT NULL,
      scope_id TEXT NOT NULL,
      preferred_device_id TEXT,
      allowed_actions_json TEXT NOT NULL,
      approval_surface TEXT NOT NULL,
      threading_mode TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      audit_ref TEXT
    );

    CREATE UNIQUE INDEX IF NOT EXISTS idx_supervisor_channel_bindings_route
      ON supervisor_operator_channel_bindings(provider, account_id, conversation_id, thread_key, channel_scope);

    CREATE INDEX IF NOT EXISTS idx_supervisor_channel_bindings_scope
      ON supervisor_operator_channel_bindings(scope_type, scope_id, status, updated_at_ms);

    CREATE INDEX IF NOT EXISTS idx_supervisor_channel_bindings_lookup
      ON supervisor_operator_channel_bindings(provider, account_id, conversation_id, channel_scope, status, updated_at_ms);
  `);
  CHANNEL_BINDINGS_TABLES_INIT.add(db);
}

function parseBindingRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    schema_version: safeString(row.schema_version) || SUPERVISOR_OPERATOR_CHANNEL_BINDING_SCHEMA,
    binding_id: safeString(row.binding_id),
    provider: safeString(row.provider).toLowerCase(),
    account_id: safeString(row.account_id),
    conversation_id: safeString(row.conversation_id),
    thread_key: safeString(row.thread_key),
    route_key: safeString(row.route_key),
    channel_scope: normalizeSupervisorChannelScope(row.channel_scope, 'group'),
    scope_type: normalizeSupervisorScopeType(row.scope_type, 'project'),
    scope_id: safeString(row.scope_id),
    preferred_device_id: safeString(row.preferred_device_id),
    allowed_actions: normalizeActionList(parseJsonArray(row.allowed_actions_json)),
    approval_surface: normalizeChannelApprovalSurface(row.approval_surface, 'text_only'),
    threading_mode: normalizeChannelThreadingMode(row.threading_mode, 'none'),
    status: normalizeSupervisorChannelBindingStatus(row.status, 'disabled'),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

function getExactSupervisorOperatorChannelBinding(db, {
  provider,
  account_id = '',
  conversation_id,
  thread_key = '',
  channel_scope = 'group',
} = {}) {
  ensureDb(db);
  const providerId = normalizeChannelProviderId(provider) || '';
  const accountId = safeString(account_id);
  const conversationId = safeString(conversation_id);
  const threadKey = safeString(thread_key);
  const channelScope = normalizeSupervisorChannelScope(channel_scope, 'group');
  if (!providerId || !conversationId) return null;
  const row = db.db
    .prepare(
      `SELECT *
       FROM supervisor_operator_channel_bindings
       WHERE provider = ?
         AND account_id = ?
         AND conversation_id = ?
         AND thread_key = ?
         AND channel_scope = ?
       LIMIT 1`
    )
    .get(providerId, accountId, conversationId, threadKey, channelScope);
  return parseBindingRow(row);
}

export function normalizeSupervisorOperatorChannelBinding(input = {}, options = {}) {
  const now = safeInt(options.now_ms, nowMs()) || nowMs();
  const provider = normalizeChannelProviderId(input.provider || input.channel || input.provider_id) || '';
  const providerMeta = provider ? getChannelProviderMeta(provider) : null;
  const account_id = safeString(input.account_id || input.accountId);
  const conversation_id = safeString(input.conversation_id || input.channel_id || input.to);
  const thread_key = safeString(input.thread_key || input.threadId || input.thread_id);
  const route_key = channelDeliveryContextKey({
    provider,
    account_id,
    conversation_id,
    thread_key,
  }) || '';
  const channel_scope = normalizeSupervisorChannelScope(input.channel_scope, 'group');
  const scope_type = normalizeSupervisorScopeType(input.scope_type, 'project');
  const scope_id = safeString(input.scope_id);
  const preferred_device_id = safeString(input.preferred_device_id);
  const allowed_actions = normalizeActionList(input.allowed_actions || []);
  const approval_surface = normalizeChannelApprovalSurface(
    input.approval_surface,
    providerMeta?.approval_surface || 'text_only'
  );
  const threading_mode = normalizeChannelThreadingMode(
    input.threading_mode,
    providerMeta?.threading_mode || 'none'
  );
  const status = normalizeSupervisorChannelBindingStatus(input.status, 'active');
  return {
    schema_version: SUPERVISOR_OPERATOR_CHANNEL_BINDING_SCHEMA,
    binding_id: safeString(input.binding_id),
    provider,
    account_id,
    conversation_id,
    thread_key,
    route_key,
    channel_scope,
    scope_type,
    scope_id,
    preferred_device_id,
    allowed_actions,
    approval_surface,
    threading_mode,
    status,
    created_at_ms: safeInt(input.created_at_ms, now) || now,
    updated_at_ms: safeInt(input.updated_at_ms, now) || now,
    audit_ref: safeString(input.audit_ref),
  };
}

function bindingDeny(deny_code, detail = {}, binding = null) {
  return {
    ok: false,
    deny_code: safeString(deny_code) || 'channel_binding_rejected',
    detail: detail && typeof detail === 'object' ? detail : {},
    binding,
    binding_match_mode: 'none',
    audit_logged: false,
    created: false,
    updated: false,
  };
}

function appendBindingAudit({
  db,
  event_type,
  binding,
  request_id = '',
  audit = {},
  created = false,
  updated = false,
}) {
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type,
    created_at_ms: nowMs(),
    severity: 'info',
    device_id: safeString(audit.device_id || 'channel_bindings_store'),
    user_id: safeString(audit.user_id) || null,
    app_id: safeString(audit.app_id || 'channel_bindings_store'),
    project_id: binding.scope_type === 'project' ? binding.scope_id : (safeString(audit.project_id) || null),
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: 'channel.binding.write',
    model_id: null,
    ok: true,
    error_code: null,
    error_message: null,
    ext_json: JSON.stringify({
      schema_version: SUPERVISOR_OPERATOR_CHANNEL_BINDING_SCHEMA,
      binding_id: binding.binding_id,
      provider: binding.provider,
      account_id: binding.account_id,
      conversation_id: binding.conversation_id,
      thread_key: binding.thread_key,
      channel_scope: binding.channel_scope,
      scope_type: binding.scope_type,
      scope_id: binding.scope_id,
      allowed_actions: binding.allowed_actions,
      status: binding.status,
      created,
      updated,
    }),
  });
}

export function getSupervisorOperatorChannelBindingById(db, { binding_id } = {}) {
  ensureDb(db);
  const bindingId = safeString(binding_id);
  if (!bindingId) return null;
  const row = db.db
    .prepare(
      `SELECT *
       FROM supervisor_operator_channel_bindings
       WHERE binding_id = ?
       LIMIT 1`
    )
    .get(bindingId);
  return parseBindingRow(row);
}

export function listSupervisorOperatorChannelBindings(db, filters = {}) {
  ensureDb(db);
  const where = [];
  const args = [];
  const provider = normalizeChannelProviderId(filters.provider) || '';
  const accountId = safeString(filters.account_id);
  const conversationId = safeString(filters.conversation_id);
  const scopeType = safeString(filters.scope_type).toLowerCase();
  const scopeId = safeString(filters.scope_id);
  const channelScope = safeString(filters.channel_scope).toLowerCase();
  const status = safeString(filters.status).toLowerCase();

  if (provider) {
    where.push('provider = ?');
    args.push(provider);
  }
  if (accountId) {
    where.push('account_id = ?');
    args.push(accountId);
  }
  if (conversationId) {
    where.push('conversation_id = ?');
    args.push(conversationId);
  }
  if (SCOPE_TYPE_SET.has(scopeType)) {
    where.push('scope_type = ?');
    args.push(scopeType);
  }
  if (scopeId) {
    where.push('scope_id = ?');
    args.push(scopeId);
  }
  if (CHANNEL_SCOPE_SET.has(channelScope)) {
    where.push('channel_scope = ?');
    args.push(channelScope);
  }
  if (BINDING_STATUS_SET.has(status)) {
    where.push('status = ?');
    args.push(status);
  }

  const limit = Math.max(1, Math.min(500, safeInt(filters.limit, 200) || 200));
  const sql = `
    SELECT *
    FROM supervisor_operator_channel_bindings
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY updated_at_ms DESC, provider ASC, conversation_id ASC, thread_key ASC
    LIMIT ${limit}
  `;
  return db.db.prepare(sql).all(...args).map((row) => parseBindingRow(row)).filter(Boolean);
}

export function resolveSupervisorOperatorChannelBinding(db, {
  provider,
  account_id = '',
  conversation_id,
  thread_key = '',
  channel_scope = 'group',
} = {}) {
  ensureDb(db);
  const providerId = normalizeChannelProviderId(provider) || '';
  const accountId = safeString(account_id);
  const conversationId = safeString(conversation_id);
  const threadKey = safeString(thread_key);
  const channelScope = normalizeSupervisorChannelScope(channel_scope, 'group');
  if (!providerId || !conversationId) {
    return { binding: null, binding_match_mode: 'none' };
  }

  const exactRow = getExactSupervisorOperatorChannelBinding(db, {
    provider: providerId,
    account_id: accountId,
    conversation_id: conversationId,
    thread_key: threadKey,
    channel_scope: channelScope,
  });
  if (exactRow) {
    return {
      binding: exactRow,
      binding_match_mode: threadKey ? 'exact_thread' : 'conversation_exact',
    };
  }
  if (!threadKey) {
    return { binding: null, binding_match_mode: 'none' };
  }

  const fallbackRow = getExactSupervisorOperatorChannelBinding(db, {
    provider: providerId,
    account_id: accountId,
    conversation_id: conversationId,
    thread_key: '',
    channel_scope: channelScope,
  });
  return {
    binding: fallbackRow,
    binding_match_mode: fallbackRow ? 'conversation_fallback' : 'none',
  };
}

export function upsertSupervisorOperatorChannelBinding(db, {
  binding = {},
  audit = {},
  request_id = '',
} = {}) {
  ensureDb(db);
  const normalized = normalizeSupervisorOperatorChannelBinding(binding);
  if (!normalized.provider) {
    return bindingDeny('provider_unknown');
  }
  if (!normalized.conversation_id) {
    return bindingDeny('conversation_id_missing');
  }
  if (!normalized.scope_id) {
    return bindingDeny('scope_id_missing', {}, normalized);
  }
  if (!normalized.allowed_actions.length && normalized.status === 'active') {
    return bindingDeny('allowed_actions_missing', {}, normalized);
  }

  const existing = getExactSupervisorOperatorChannelBinding(db, normalized);
  const created = !existing;
  const updated = !!existing;
  const bindingId = existing?.binding_id || normalized.binding_id || uuid();
  const createdAtMs = existing?.created_at_ms || normalized.created_at_ms || nowMs();

  db.db.exec('BEGIN;');
  try {
    const auditRef = appendBindingAudit({
      db,
      event_type: 'channel.binding.upserted',
      binding: {
        ...normalized,
        binding_id: bindingId,
        created_at_ms: createdAtMs,
      },
      request_id,
      audit,
      created,
      updated,
    });
    const updatedAtMs = nowMs();
    db.db
      .prepare(
        `INSERT INTO supervisor_operator_channel_bindings(
           binding_id, schema_version, provider, account_id, conversation_id, thread_key, route_key,
           channel_scope, scope_type, scope_id, preferred_device_id, allowed_actions_json,
           approval_surface, threading_mode, status, created_at_ms, updated_at_ms, audit_ref
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(binding_id) DO UPDATE SET
           schema_version = excluded.schema_version,
           provider = excluded.provider,
           account_id = excluded.account_id,
           conversation_id = excluded.conversation_id,
           thread_key = excluded.thread_key,
           route_key = excluded.route_key,
           channel_scope = excluded.channel_scope,
           scope_type = excluded.scope_type,
           scope_id = excluded.scope_id,
           preferred_device_id = excluded.preferred_device_id,
           allowed_actions_json = excluded.allowed_actions_json,
           approval_surface = excluded.approval_surface,
           threading_mode = excluded.threading_mode,
           status = excluded.status,
           updated_at_ms = excluded.updated_at_ms,
           audit_ref = excluded.audit_ref`
      )
      .run(
        bindingId,
        normalized.schema_version,
        normalized.provider,
        normalized.account_id,
        normalized.conversation_id,
        normalized.thread_key,
        normalized.route_key,
        normalized.channel_scope,
        normalized.scope_type,
        normalized.scope_id,
        normalized.preferred_device_id || null,
        JSON.stringify(normalized.allowed_actions),
        normalized.approval_surface,
        normalized.threading_mode,
        normalized.status,
        createdAtMs,
        updatedAtMs,
        auditRef
      );
    const row = getSupervisorOperatorChannelBindingById(db, { binding_id: bindingId });
    db.db.exec('COMMIT;');
    return {
      ok: true,
      deny_code: '',
      detail: {},
      binding: row,
      binding_match_mode: existing ? (normalized.thread_key ? 'exact_thread' : 'conversation_exact') : 'none',
      audit_logged: true,
      created,
      updated,
    };
  } catch (err) {
    try {
      db.db.exec('ROLLBACK;');
    } catch {
      // ignore
    }
    return bindingDeny('audit_write_failed', {
      message: safeString(err?.message || 'audit_write_failed'),
    }, normalized);
  }
}
