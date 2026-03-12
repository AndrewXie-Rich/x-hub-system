import { channelDeliveryContextKey } from './channel_delivery_context.js';
import { normalizeChannelProviderId } from './channel_registry.js';
import {
  normalizeSupervisorChannelScope,
  normalizeSupervisorScopeType,
} from './channel_bindings_store.js';
import { nowMs, uuid } from './util.js';

export const SUPERVISOR_CHANNEL_SESSION_ROUTE_SCHEMA = 'xhub.supervisor_channel_session_route.v1';

export const SUPERVISOR_CHANNEL_ROUTE_MODES = Object.freeze([
  'hub_only_status',
  'hub_to_xt',
  'hub_to_runner',
  'xt_offline',
  'runner_not_ready',
]);

const ROUTE_MODE_SET = new Set(SUPERVISOR_CHANNEL_ROUTE_MODES);
const SESSION_ROUTE_TABLES_INIT = new WeakSet();

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

export function normalizeSupervisorChannelRouteMode(input, fallback = 'hub_only_status') {
  const mode = safeString(input).toLowerCase();
  return ROUTE_MODE_SET.has(mode) ? mode : fallback;
}

function ensureDb(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.exec !== 'function') {
    throw new Error('supervisor_channel_session_store_db_required');
  }
  if (SESSION_ROUTE_TABLES_INIT.has(db)) return;
  db.db.exec(`
    CREATE TABLE IF NOT EXISTS supervisor_channel_session_routes (
      route_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      provider TEXT NOT NULL,
      account_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      thread_key TEXT NOT NULL,
      session_route_key TEXT NOT NULL,
      scope_type TEXT NOT NULL,
      scope_id TEXT NOT NULL,
      supervisor_session_id TEXT NOT NULL,
      preferred_device_id TEXT,
      resolved_device_id TEXT,
      route_mode TEXT NOT NULL,
      xt_online INTEGER NOT NULL,
      runner_required INTEGER NOT NULL,
      same_project_scope INTEGER NOT NULL,
      deny_code TEXT,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      audit_ref TEXT
    );

    CREATE UNIQUE INDEX IF NOT EXISTS idx_supervisor_channel_session_routes_key
      ON supervisor_channel_session_routes(provider, account_id, conversation_id, thread_key);

    CREATE INDEX IF NOT EXISTS idx_supervisor_channel_session_routes_scope
      ON supervisor_channel_session_routes(scope_type, scope_id, updated_at_ms);
  `);
  SESSION_ROUTE_TABLES_INIT.add(db);
}

function parseSessionRouteRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    schema_version: safeString(row.schema_version) || SUPERVISOR_CHANNEL_SESSION_ROUTE_SCHEMA,
    route_id: safeString(row.route_id),
    provider: safeString(row.provider).toLowerCase(),
    account_id: safeString(row.account_id),
    conversation_id: safeString(row.conversation_id),
    thread_key: safeString(row.thread_key),
    session_route_key: safeString(row.session_route_key),
    scope_type: normalizeSupervisorScopeType(row.scope_type, 'project'),
    scope_id: safeString(row.scope_id),
    supervisor_session_id: safeString(row.supervisor_session_id),
    preferred_device_id: safeString(row.preferred_device_id),
    resolved_device_id: safeString(row.resolved_device_id),
    route_mode: normalizeSupervisorChannelRouteMode(row.route_mode, 'hub_only_status'),
    xt_online: !!Number(row.xt_online || 0),
    runner_required: !!Number(row.runner_required || 0),
    same_project_scope: !!Number(row.same_project_scope || 0),
    deny_code: safeString(row.deny_code),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

export function normalizeSupervisorChannelSessionRoute(input = {}, options = {}) {
  const now = safeInt(options.now_ms, nowMs()) || nowMs();
  const provider = normalizeChannelProviderId(input.provider || input.channel || input.provider_id) || '';
  const account_id = safeString(input.account_id || input.accountId);
  const conversation_id = safeString(input.conversation_id || input.channel_id || input.to);
  const thread_key = safeString(input.thread_key || input.threadId || input.thread_id);
  return {
    schema_version: SUPERVISOR_CHANNEL_SESSION_ROUTE_SCHEMA,
    route_id: safeString(input.route_id),
    provider,
    account_id,
    conversation_id,
    thread_key,
    session_route_key: channelDeliveryContextKey({
      provider,
      account_id,
      conversation_id,
      thread_key,
    }) || '',
    scope_type: normalizeSupervisorScopeType(input.scope_type, 'project'),
    scope_id: safeString(input.scope_id),
    supervisor_session_id: safeString(input.supervisor_session_id),
    preferred_device_id: safeString(input.preferred_device_id),
    resolved_device_id: safeString(input.resolved_device_id),
    route_mode: normalizeSupervisorChannelRouteMode(input.route_mode, 'hub_only_status'),
    xt_online: safeBool(input.xt_online, false),
    runner_required: safeBool(input.runner_required, false),
    same_project_scope: safeBool(input.same_project_scope, false),
    deny_code: safeString(input.deny_code),
    created_at_ms: safeInt(input.created_at_ms, now) || now,
    updated_at_ms: safeInt(input.updated_at_ms, now) || now,
    audit_ref: safeString(input.audit_ref),
  };
}

function appendRouteAudit({
  db,
  route,
  request_id = '',
  audit = {},
  created = false,
  updated = false,
}) {
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type: 'channel.session_route.upserted',
    created_at_ms: nowMs(),
    severity: route.route_mode === 'xt_offline' || route.route_mode === 'runner_not_ready' ? 'warn' : 'info',
    device_id: safeString(audit.device_id || 'supervisor_channel_session_store'),
    user_id: safeString(audit.user_id) || null,
    app_id: safeString(audit.app_id || 'supervisor_channel_session_store'),
    project_id: route.scope_type === 'project' ? route.scope_id : (safeString(audit.project_id) || null),
    session_id: safeString(audit.session_id || route.supervisor_session_id) || null,
    request_id: safeString(request_id) || null,
    capability: 'channel.session_route.write',
    model_id: null,
    ok: route.route_mode !== 'xt_offline' && route.route_mode !== 'runner_not_ready',
    error_code: route.route_mode === 'xt_offline' || route.route_mode === 'runner_not_ready'
      ? safeString(route.deny_code || route.route_mode)
      : null,
    error_message: route.route_mode === 'xt_offline' || route.route_mode === 'runner_not_ready'
      ? safeString(route.route_mode)
      : null,
    ext_json: JSON.stringify({
      schema_version: SUPERVISOR_CHANNEL_SESSION_ROUTE_SCHEMA,
      route_id: route.route_id,
      provider: route.provider,
      account_id: route.account_id,
      conversation_id: route.conversation_id,
      thread_key: route.thread_key,
      scope_type: route.scope_type,
      scope_id: route.scope_id,
      preferred_device_id: route.preferred_device_id,
      resolved_device_id: route.resolved_device_id,
      route_mode: route.route_mode,
      xt_online: route.xt_online,
      runner_required: route.runner_required,
      same_project_scope: route.same_project_scope,
      deny_code: route.deny_code,
      created,
      updated,
    }),
  });
}

function routeDeny(deny_code, detail = {}, route = null) {
  return {
    ok: false,
    deny_code: safeString(deny_code) || 'session_route_rejected',
    detail: detail && typeof detail === 'object' ? detail : {},
    route,
    audit_logged: false,
    created: false,
    updated: false,
  };
}

export function resolveSupervisorChannelSessionRoute(db, {
  provider,
  account_id = '',
  conversation_id,
  thread_key = '',
} = {}) {
  ensureDb(db);
  const providerId = normalizeChannelProviderId(provider) || '';
  const accountId = safeString(account_id);
  const conversationId = safeString(conversation_id);
  const threadKey = safeString(thread_key);
  if (!providerId || !conversationId) return null;
  const row = db.db
    .prepare(
      `SELECT *
       FROM supervisor_channel_session_routes
       WHERE provider = ?
         AND account_id = ?
         AND conversation_id = ?
         AND thread_key = ?
       LIMIT 1`
    )
    .get(providerId, accountId, conversationId, threadKey);
  return parseSessionRouteRow(row);
}

export function getSupervisorChannelSessionRouteById(db, { route_id } = {}) {
  ensureDb(db);
  const routeId = safeString(route_id);
  if (!routeId) return null;
  const row = db.db
    .prepare(
      `SELECT *
       FROM supervisor_channel_session_routes
       WHERE route_id = ?
       LIMIT 1`
    )
    .get(routeId);
  return parseSessionRouteRow(row);
}

export function upsertSupervisorChannelSessionRoute(db, {
  route = {},
  audit = {},
  request_id = '',
} = {}) {
  ensureDb(db);
  const normalized = normalizeSupervisorChannelSessionRoute(route);
  if (!normalized.provider) {
    return routeDeny('provider_unknown');
  }
  if (!normalized.conversation_id) {
    return routeDeny('conversation_id_missing');
  }
  if (!normalized.scope_id) {
    return routeDeny('scope_id_missing', {}, normalized);
  }
  if (!normalized.session_route_key) {
    return routeDeny('session_route_key_missing', {}, normalized);
  }

  const existing = resolveSupervisorChannelSessionRoute(db, normalized);
  if (existing && (
    existing.scope_type !== normalized.scope_type
    || existing.scope_id !== normalized.scope_id
  )) {
    return routeDeny('session_scope_conflict', {
      existing_scope_type: existing.scope_type,
      existing_scope_id: existing.scope_id,
      requested_scope_type: normalized.scope_type,
      requested_scope_id: normalized.scope_id,
    }, normalized);
  }

  const routeId = existing?.route_id || normalized.route_id || uuid();
  const supervisorSessionId = existing?.supervisor_session_id || normalized.supervisor_session_id || routeId;
  const createdAtMs = existing?.created_at_ms || normalized.created_at_ms || nowMs();
  const created = !existing;
  const updated = !!existing;

  db.db.exec('BEGIN;');
  try {
    const persistedRoute = {
      ...normalized,
      route_id: routeId,
      supervisor_session_id: supervisorSessionId,
      created_at_ms: createdAtMs,
      updated_at_ms: nowMs(),
    };
    const auditRef = appendRouteAudit({
      db,
      route: persistedRoute,
      request_id,
      audit,
      created,
      updated,
    });
    db.db
      .prepare(
        `INSERT INTO supervisor_channel_session_routes(
           route_id, schema_version, provider, account_id, conversation_id, thread_key,
           session_route_key, scope_type, scope_id, supervisor_session_id,
           preferred_device_id, resolved_device_id, route_mode, xt_online,
           runner_required, same_project_scope, deny_code, created_at_ms, updated_at_ms, audit_ref
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(route_id) DO UPDATE SET
           schema_version = excluded.schema_version,
           provider = excluded.provider,
           account_id = excluded.account_id,
           conversation_id = excluded.conversation_id,
           thread_key = excluded.thread_key,
           session_route_key = excluded.session_route_key,
           scope_type = excluded.scope_type,
           scope_id = excluded.scope_id,
           supervisor_session_id = excluded.supervisor_session_id,
           preferred_device_id = excluded.preferred_device_id,
           resolved_device_id = excluded.resolved_device_id,
           route_mode = excluded.route_mode,
           xt_online = excluded.xt_online,
           runner_required = excluded.runner_required,
           same_project_scope = excluded.same_project_scope,
           deny_code = excluded.deny_code,
           updated_at_ms = excluded.updated_at_ms,
           audit_ref = excluded.audit_ref`
      )
      .run(
        persistedRoute.route_id,
        persistedRoute.schema_version,
        persistedRoute.provider,
        persistedRoute.account_id,
        persistedRoute.conversation_id,
        persistedRoute.thread_key,
        persistedRoute.session_route_key,
        persistedRoute.scope_type,
        persistedRoute.scope_id,
        persistedRoute.supervisor_session_id,
        persistedRoute.preferred_device_id || null,
        persistedRoute.resolved_device_id || null,
        persistedRoute.route_mode,
        persistedRoute.xt_online ? 1 : 0,
        persistedRoute.runner_required ? 1 : 0,
        persistedRoute.same_project_scope ? 1 : 0,
        persistedRoute.deny_code || null,
        persistedRoute.created_at_ms,
        persistedRoute.updated_at_ms,
        auditRef
      );
    const row = getSupervisorChannelSessionRouteById(db, { route_id: routeId });
    db.db.exec('COMMIT;');
    return {
      ok: true,
      deny_code: '',
      detail: {},
      route: row,
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
    return routeDeny('audit_write_failed', {
      message: safeString(err?.message || 'audit_write_failed'),
    }, normalized);
  }
}
