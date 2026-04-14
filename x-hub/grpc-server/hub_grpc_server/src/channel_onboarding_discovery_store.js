import { normalizeSupervisorChannelScope, normalizeSupervisorScopeType } from './channel_bindings_store.js';
import {
  appendChannelOnboardingAutoBindRejectedAudit,
  writeApprovedChannelOnboardingAutoBindTx,
} from './channel_onboarding_transaction.js';
import { normalizeChannelProviderId } from './channel_registry.js';
import { nowMs, uuid } from './util.js';

export const CHANNEL_ONBOARDING_DISCOVERY_TICKET_SCHEMA = 'xhub.channel_onboarding_discovery_ticket.v1';
export const CHANNEL_ONBOARDING_APPROVAL_DECISION_SCHEMA = 'xhub.channel_onboarding_approval_decision.v1';
export const CHANNEL_ONBOARDING_DISCOVERY_TICKET_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export const CHANNEL_ONBOARDING_DISCOVERY_STATUSES = Object.freeze([
  'pending',
  'held',
  'approved',
  'rejected',
  'expired',
]);

const STATUS_SET = new Set(CHANNEL_ONBOARDING_DISCOVERY_STATUSES);
export const CHANNEL_ONBOARDING_APPROVAL_DECISIONS = Object.freeze([
  'approve',
  'hold',
  'reject',
]);
const DECISION_SET = new Set(CHANNEL_ONBOARDING_APPROVAL_DECISIONS);
export const CHANNEL_ONBOARDING_SAFE_ALLOWED_ACTIONS = Object.freeze([
  'supervisor.status.get',
  'supervisor.blockers.get',
  'supervisor.queue.get',
  'device.doctor.get',
  'device.permission_status.get',
]);
const SAFE_ALLOWED_ACTION_SET = new Set(CHANNEL_ONBOARDING_SAFE_ALLOWED_ACTIONS);
const TABLES_INIT = new WeakSet();

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

function normalizePreview(input, maxLen = 160) {
  const text = safeString(input).replace(/\s+/g, ' ').trim();
  if (!text) return '';
  return text.length > maxLen ? text.slice(0, maxLen) : text;
}

export function normalizeChannelOnboardingBindingMode(input, fallback = 'conversation_binding') {
  const text = safeString(input).toLowerCase();
  if (text === 'thread' || text === 'thread_binding') return 'thread_binding';
  if (text === 'conversation' || text === 'conversation_binding') return 'conversation_binding';
  return fallback;
}

export function normalizeChannelOnboardingDiscoveryStatus(input, fallback = 'pending') {
  const status = safeString(input).toLowerCase();
  return STATUS_SET.has(status) ? status : fallback;
}

export function normalizeChannelOnboardingApprovalDecision(input, fallback = '') {
  const decision = safeString(input).toLowerCase();
  return DECISION_SET.has(decision) ? decision : fallback;
}

function normalizeAllowedActionName(input) {
  return safeString(input).toLowerCase();
}

function normalizeSafeAllowedActions(input) {
  const rows = Array.isArray(input) ? input : [];
  const out = [];
  const seen = new Set();
  for (const raw of rows) {
    const action = normalizeAllowedActionName(raw);
    if (!action || seen.has(action)) continue;
    seen.add(action);
    out.push(action);
  }
  return out;
}

function discoveryDedupeKey({
  provider,
  account_id,
  external_user_id,
  external_tenant_id,
  conversation_id,
  thread_key,
}) {
  return [
    safeString(provider).toLowerCase(),
    safeString(account_id),
    safeString(external_tenant_id),
    safeString(external_user_id),
    safeString(conversation_id),
    safeString(thread_key),
  ].join('|');
}

function ensureDb(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.exec !== 'function') {
    throw new Error('channel_onboarding_discovery_store_db_required');
  }
  if (TABLES_INIT.has(db)) return;
  db.db.exec(`
    CREATE TABLE IF NOT EXISTS channel_onboarding_discovery_tickets (
      ticket_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      dedupe_key TEXT NOT NULL,
      provider TEXT NOT NULL,
      account_id TEXT NOT NULL,
      external_user_id TEXT NOT NULL,
      external_tenant_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      thread_key TEXT NOT NULL,
      ingress_surface TEXT NOT NULL,
      first_message_preview TEXT NOT NULL,
      proposed_scope_type TEXT NOT NULL,
      proposed_scope_id TEXT NOT NULL,
      recommended_binding_mode TEXT NOT NULL,
      status TEXT NOT NULL,
      event_count INTEGER NOT NULL,
      first_seen_at_ms INTEGER NOT NULL,
      last_seen_at_ms INTEGER NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      expires_at_ms INTEGER NOT NULL,
      last_request_id TEXT NOT NULL,
      audit_ref TEXT
    );

    CREATE TABLE IF NOT EXISTS channel_onboarding_approval_decisions (
      decision_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      ticket_id TEXT NOT NULL,
      decision TEXT NOT NULL,
      approved_by_hub_user_id TEXT NOT NULL,
      approved_via TEXT NOT NULL,
      hub_user_id TEXT NOT NULL,
      scope_type TEXT NOT NULL,
      scope_id TEXT NOT NULL,
      binding_mode TEXT NOT NULL,
      preferred_device_id TEXT,
      allowed_actions_json TEXT NOT NULL,
      grant_profile TEXT NOT NULL,
      note TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      audit_ref TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_channel_onboarding_discovery_lookup
      ON channel_onboarding_discovery_tickets(dedupe_key, status, updated_at_ms);

    CREATE INDEX IF NOT EXISTS idx_channel_onboarding_discovery_status
      ON channel_onboarding_discovery_tickets(status, updated_at_ms);

    CREATE INDEX IF NOT EXISTS idx_channel_onboarding_discovery_provider
      ON channel_onboarding_discovery_tickets(provider, status, updated_at_ms);

    CREATE INDEX IF NOT EXISTS idx_channel_onboarding_approval_decisions_ticket
      ON channel_onboarding_approval_decisions(ticket_id, created_at_ms DESC);
  `);
  TABLES_INIT.add(db);
}

function parseRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    schema_version: safeString(row.schema_version) || CHANNEL_ONBOARDING_DISCOVERY_TICKET_SCHEMA,
    ticket_id: safeString(row.ticket_id),
    provider: safeString(row.provider).toLowerCase(),
    account_id: safeString(row.account_id),
    external_user_id: safeString(row.external_user_id),
    external_tenant_id: safeString(row.external_tenant_id),
    conversation_id: safeString(row.conversation_id),
    thread_key: safeString(row.thread_key),
    ingress_surface: normalizeSupervisorChannelScope(row.ingress_surface, 'group'),
    first_message_preview: normalizePreview(row.first_message_preview),
    proposed_scope_type: normalizeSupervisorScopeType(row.proposed_scope_type, 'project'),
    proposed_scope_id: safeString(row.proposed_scope_id),
    recommended_binding_mode: normalizeChannelOnboardingBindingMode(row.recommended_binding_mode),
    status: normalizeChannelOnboardingDiscoveryStatus(row.status, 'pending'),
    event_count: safeInt(row.event_count, 0),
    first_seen_at_ms: safeInt(row.first_seen_at_ms, 0),
    last_seen_at_ms: safeInt(row.last_seen_at_ms, 0),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    expires_at_ms: safeInt(row.expires_at_ms, 0),
    last_request_id: safeString(row.last_request_id),
    audit_ref: safeString(row.audit_ref),
  };
}

function parseApprovalDecisionRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    schema_version: safeString(row.schema_version) || CHANNEL_ONBOARDING_APPROVAL_DECISION_SCHEMA,
    decision_id: safeString(row.decision_id),
    ticket_id: safeString(row.ticket_id),
    decision: normalizeChannelOnboardingApprovalDecision(row.decision),
    approved_by_hub_user_id: safeString(row.approved_by_hub_user_id),
    approved_via: safeString(row.approved_via),
    hub_user_id: safeString(row.hub_user_id),
    scope_type: normalizeSupervisorScopeType(row.scope_type, ''),
    scope_id: safeString(row.scope_id),
    binding_mode: normalizeChannelOnboardingBindingMode(row.binding_mode, ''),
    preferred_device_id: safeString(row.preferred_device_id),
    allowed_actions: normalizeSafeAllowedActions(parseJsonArray(row.allowed_actions_json)),
    grant_profile: safeString(row.grant_profile),
    note: normalizePreview(row.note, 500),
    created_at_ms: safeInt(row.created_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

export function normalizeChannelOnboardingDiscoveryTicket(input = {}, options = {}) {
  const now = safeInt(options.now_ms, nowMs()) || nowMs();
  const provider = normalizeChannelProviderId(input.provider || input.channel || input.provider_id) || '';
  const account_id = safeString(input.account_id || input.accountId);
  const external_user_id = safeString(input.external_user_id || input.user_id);
  const external_tenant_id = safeString(input.external_tenant_id || input.tenant_id);
  const conversation_id = safeString(input.conversation_id || input.channel_id || input.to);
  const thread_key = safeString(input.thread_key || input.thread_id || input.threadId);
  const ingress_surface = normalizeSupervisorChannelScope(
    input.ingress_surface || input.channel_scope,
    'group'
  );
  const first_message_preview = normalizePreview(
    input.first_message_preview || input.message_preview || input.action_name
  );
  const proposed_scope_type = normalizeSupervisorScopeType(
    input.proposed_scope_type || input.scope_type,
    'project'
  );
  const proposed_scope_id = safeString(input.proposed_scope_id || input.scope_id);
  const recommended_binding_mode = normalizeChannelOnboardingBindingMode(
    input.recommended_binding_mode,
    thread_key ? 'thread_binding' : 'conversation_binding'
  );
  const status = normalizeChannelOnboardingDiscoveryStatus(input.status, 'pending');
  const event_count = Math.max(1, safeInt(input.event_count, 1));
  const first_seen_at_ms = safeInt(input.first_seen_at_ms, now) || now;
  const last_seen_at_ms = safeInt(input.last_seen_at_ms, now) || now;
  const created_at_ms = safeInt(input.created_at_ms, now) || now;
  const updated_at_ms = safeInt(input.updated_at_ms, now) || now;
  const expires_at_ms = safeInt(input.expires_at_ms, now + CHANNEL_ONBOARDING_DISCOVERY_TICKET_TTL_MS)
    || (now + CHANNEL_ONBOARDING_DISCOVERY_TICKET_TTL_MS);
  const normalized = {
    schema_version: CHANNEL_ONBOARDING_DISCOVERY_TICKET_SCHEMA,
    ticket_id: safeString(input.ticket_id),
    provider,
    account_id,
    external_user_id,
    external_tenant_id,
    conversation_id,
    thread_key,
    ingress_surface,
    first_message_preview,
    proposed_scope_type,
    proposed_scope_id,
    recommended_binding_mode,
    status,
    event_count,
    first_seen_at_ms,
    last_seen_at_ms,
    created_at_ms,
    updated_at_ms,
    expires_at_ms,
    last_request_id: safeString(input.last_request_id),
    audit_ref: safeString(input.audit_ref),
  };
  normalized.dedupe_key = discoveryDedupeKey(normalized);
  return normalized;
}

export function normalizeChannelOnboardingApprovalDecisionDraft(input = {}, options = {}) {
  const now = safeInt(options.now_ms, nowMs()) || nowMs();
  return {
    schema_version: CHANNEL_ONBOARDING_APPROVAL_DECISION_SCHEMA,
    decision_id: safeString(input.decision_id),
    ticket_id: safeString(input.ticket_id),
    decision: normalizeChannelOnboardingApprovalDecision(input.decision),
    approved_by_hub_user_id: safeString(input.approved_by_hub_user_id || input.decided_by_hub_user_id),
    approved_via: safeString(input.approved_via || 'hub_local_ui') || 'hub_local_ui',
    hub_user_id: safeString(input.hub_user_id),
    scope_type: normalizeSupervisorScopeType(input.scope_type, ''),
    scope_id: safeString(input.scope_id),
    binding_mode: normalizeChannelOnboardingBindingMode(input.binding_mode, ''),
    preferred_device_id: safeString(input.preferred_device_id),
    allowed_actions: normalizeSafeAllowedActions(input.allowed_actions || []),
    grant_profile: safeString(input.grant_profile),
    note: normalizePreview(input.note || input.reason, 500),
    created_at_ms: safeInt(input.created_at_ms, now) || now,
    audit_ref: safeString(input.audit_ref),
  };
}

function deny(deny_code, detail = {}, ticket = null) {
  return {
    ok: false,
    deny_code: safeString(deny_code) || 'channel_onboarding_discovery_rejected',
    detail: detail && typeof detail === 'object' ? detail : {},
    ticket,
    audit_logged: false,
    created: false,
    updated: false,
  };
}

function appendAudit({
  db,
  event_type,
  ticket,
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
    device_id: safeString(audit.device_id || 'channel_onboarding_discovery_store'),
    user_id: safeString(audit.user_id) || null,
    app_id: safeString(audit.app_id || 'channel_onboarding_discovery_store'),
    project_id: ticket.proposed_scope_type === 'project' ? safeString(ticket.proposed_scope_id) || null : null,
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id || ticket.last_request_id) || null,
    capability: 'channel.onboarding.discovery.write',
    model_id: null,
    ok: true,
    error_code: null,
    error_message: null,
    ext_json: JSON.stringify({
      schema_version: CHANNEL_ONBOARDING_DISCOVERY_TICKET_SCHEMA,
      ticket_id: ticket.ticket_id,
      provider: ticket.provider,
      account_id: ticket.account_id,
      external_user_id: ticket.external_user_id,
      external_tenant_id: ticket.external_tenant_id,
      conversation_id: ticket.conversation_id,
      thread_key: ticket.thread_key,
      ingress_surface: ticket.ingress_surface,
      first_message_preview: ticket.first_message_preview,
      proposed_scope_type: ticket.proposed_scope_type,
      proposed_scope_id: ticket.proposed_scope_id,
      recommended_binding_mode: ticket.recommended_binding_mode,
      status: ticket.status,
      event_count: ticket.event_count,
      created,
      updated,
    }),
  });
}

function appendApprovalDecisionAudit({
  db,
  ticket,
  decision,
  request_id = '',
  audit = {},
}) {
  const decisionEvent = (() => {
    const key = safeString(decision.decision);
    if (key === 'approve') return 'approved';
    if (key === 'reject') return 'rejected';
    if (key === 'hold') return 'held';
    return 'reviewed';
  })();
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type: `channel.onboarding.discovery.${decisionEvent}`,
    created_at_ms: nowMs(),
    severity: 'info',
    device_id: safeString(audit.device_id || 'channel_onboarding_discovery_store'),
    user_id: safeString(audit.user_id || decision.approved_by_hub_user_id) || null,
    app_id: safeString(audit.app_id || decision.approved_via || 'channel_onboarding_discovery_store'),
    project_id: safeString(decision.scope_type) === 'project'
      ? safeString(decision.scope_id) || null
      : (ticket.proposed_scope_type === 'project' ? safeString(ticket.proposed_scope_id) || null : null),
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id || ticket.last_request_id) || null,
    capability: 'channel.onboarding.discovery.review',
    model_id: null,
    ok: true,
    error_code: null,
    error_message: null,
    ext_json: JSON.stringify({
      ticket,
      decision: {
        schema_version: CHANNEL_ONBOARDING_APPROVAL_DECISION_SCHEMA,
        decision_id: decision.decision_id,
        ticket_id: decision.ticket_id,
        decision: decision.decision,
        approved_by_hub_user_id: decision.approved_by_hub_user_id,
        approved_via: decision.approved_via,
        hub_user_id: decision.hub_user_id,
        scope_type: decision.scope_type,
        scope_id: decision.scope_id,
        binding_mode: decision.binding_mode,
        preferred_device_id: decision.preferred_device_id,
        allowed_actions: decision.allowed_actions,
        grant_profile: decision.grant_profile,
        note: decision.note,
      },
    }),
  });
}

function getOpenTicketByDedupeKey(db, dedupe_key) {
  ensureDb(db);
  const row = db.db.prepare(
    `SELECT *
     FROM channel_onboarding_discovery_tickets
     WHERE dedupe_key = ?
       AND status IN ('pending', 'held')
     ORDER BY updated_at_ms DESC
     LIMIT 1`
  ).get(safeString(dedupe_key));
  return parseRow(row);
}

function markExpiredIfNeeded(db, ticket) {
  if (!ticket || safeInt(ticket.expires_at_ms, 0) > nowMs()) return ticket;
  db.db
    .prepare(
      `UPDATE channel_onboarding_discovery_tickets
       SET status = 'expired',
           updated_at_ms = ?
       WHERE ticket_id = ?`
    )
    .run(nowMs(), safeString(ticket.ticket_id));
  return {
    ...ticket,
    status: 'expired',
    updated_at_ms: nowMs(),
  };
}

export function getChannelOnboardingDiscoveryTicketById(db, { ticket_id } = {}) {
  ensureDb(db);
  const ticketId = safeString(ticket_id);
  if (!ticketId) return null;
  const row = db.db.prepare(
    `SELECT *
     FROM channel_onboarding_discovery_tickets
     WHERE ticket_id = ?
     LIMIT 1`
  ).get(ticketId);
  return markExpiredIfNeeded(db, parseRow(row));
}

export function getLatestChannelOnboardingApprovalDecisionByTicketId(db, { ticket_id } = {}) {
  ensureDb(db);
  const ticketId = safeString(ticket_id);
  if (!ticketId) return null;
  const row = db.db.prepare(
    `SELECT *
     FROM channel_onboarding_approval_decisions
     WHERE ticket_id = ?
     ORDER BY created_at_ms DESC
     LIMIT 1`
  ).get(ticketId);
  return parseApprovalDecisionRow(row);
}

export function listChannelOnboardingDiscoveryTickets(db, filters = {}) {
  ensureDb(db);
  const where = [];
  const args = [];
  const ticket_id = safeString(filters.ticket_id);
  const provider = normalizeChannelProviderId(filters.provider) || '';
  const status = normalizeChannelOnboardingDiscoveryStatus(filters.status, '');
  const external_tenant_id = safeString(filters.external_tenant_id);
  const external_user_id = safeString(filters.external_user_id);
  const conversation_id = safeString(filters.conversation_id);
  const account_id = safeString(filters.account_id);

  if (ticket_id) {
    where.push('ticket_id = ?');
    args.push(ticket_id);
  }
  if (provider) {
    where.push('provider = ?');
    args.push(provider);
  }
  if (status) {
    where.push('status = ?');
    args.push(status);
  }
  if (external_tenant_id) {
    where.push('external_tenant_id = ?');
    args.push(external_tenant_id);
  }
  if (external_user_id) {
    where.push('external_user_id = ?');
    args.push(external_user_id);
  }
  if (conversation_id) {
    where.push('conversation_id = ?');
    args.push(conversation_id);
  }
  if (account_id) {
    where.push('account_id = ?');
    args.push(account_id);
  }

  const limit = Math.min(500, Math.max(1, safeInt(filters.limit, 100) || 100));
  const sql = `
    SELECT *
    FROM channel_onboarding_discovery_tickets
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY updated_at_ms DESC
    LIMIT ?
  `;
  return db.db.prepare(sql).all(...args, limit)
    .map((row) => markExpiredIfNeeded(db, parseRow(row)))
    .filter(Boolean)
    .filter((row) => !status || row.status === status);
}

export function createOrTouchChannelOnboardingDiscoveryTicket(db, {
  ticket = {},
  audit = {},
  request_id = '',
} = {}) {
  ensureDb(db);
  const now = nowMs();
  const normalized = normalizeChannelOnboardingDiscoveryTicket({
    ...ticket,
    last_request_id: safeString(request_id) || safeString(ticket?.last_request_id),
  }, {
    now_ms: now,
  });

  if (!normalized.provider) {
    return deny('provider_unknown');
  }
  if (!normalized.external_user_id) {
    return deny('external_user_id_missing');
  }
  if (!normalized.conversation_id) {
    return deny('conversation_id_missing');
  }
  if (!normalized.dedupe_key) {
    return deny('discovery_dedupe_key_missing');
  }

  let existingOpen = getOpenTicketByDedupeKey(db, normalized.dedupe_key);
  existingOpen = markExpiredIfNeeded(db, existingOpen);
  if (existingOpen && existingOpen.status !== 'expired') {
    db.db.exec('BEGIN;');
    try {
      const persisted = {
        ...existingOpen,
        first_message_preview: normalized.first_message_preview || existingOpen.first_message_preview,
        proposed_scope_type: normalized.proposed_scope_id
          ? normalized.proposed_scope_type
          : existingOpen.proposed_scope_type,
        proposed_scope_id: normalized.proposed_scope_id || existingOpen.proposed_scope_id,
        recommended_binding_mode: normalized.recommended_binding_mode || existingOpen.recommended_binding_mode,
        event_count: Math.max(1, safeInt(existingOpen.event_count, 1) + 1),
        last_seen_at_ms: now,
        updated_at_ms: now,
        expires_at_ms: Math.max(safeInt(existingOpen.expires_at_ms, 0), normalized.expires_at_ms),
        last_request_id: safeString(request_id) || existingOpen.last_request_id,
      };
      const audit_ref = appendAudit({
        db,
        event_type: 'channel.onboarding.discovery.touched',
        ticket: persisted,
        request_id,
        audit,
        created: false,
        updated: true,
      });
      db.db
        .prepare(
          `UPDATE channel_onboarding_discovery_tickets
           SET first_message_preview = ?,
               proposed_scope_type = ?,
               proposed_scope_id = ?,
               recommended_binding_mode = ?,
               event_count = ?,
               last_seen_at_ms = ?,
               updated_at_ms = ?,
               expires_at_ms = ?,
               last_request_id = ?,
               audit_ref = ?
           WHERE ticket_id = ?`
        )
        .run(
          persisted.first_message_preview,
          persisted.proposed_scope_type,
          persisted.proposed_scope_id,
          persisted.recommended_binding_mode,
          persisted.event_count,
          persisted.last_seen_at_ms,
          persisted.updated_at_ms,
          persisted.expires_at_ms,
          persisted.last_request_id,
          audit_ref,
          persisted.ticket_id
        );
      db.db.exec('COMMIT;');
      return {
        ok: true,
        deny_code: '',
        ticket: {
          ...persisted,
          audit_ref,
        },
        audit_logged: true,
        created: false,
        updated: true,
      };
    } catch (error) {
      try {
        db.db.exec('ROLLBACK;');
      } catch {
        // ignore
      }
      return deny('audit_write_failed', {
        error: safeString(error?.message || 'audit_write_failed'),
      }, existingOpen);
    }
  }

  db.db.exec('BEGIN;');
  try {
    const persisted = {
      ...normalized,
      ticket_id: normalized.ticket_id || uuid(),
      created_at_ms: normalized.created_at_ms || now,
      updated_at_ms: now,
      first_seen_at_ms: normalized.first_seen_at_ms || now,
      last_seen_at_ms: normalized.last_seen_at_ms || now,
      event_count: Math.max(1, safeInt(normalized.event_count, 1)),
      last_request_id: safeString(request_id) || normalized.last_request_id,
    };
    const audit_ref = appendAudit({
      db,
      event_type: 'channel.onboarding.discovery.created',
      ticket: persisted,
      request_id,
      audit,
      created: true,
      updated: false,
    });
    db.db
      .prepare(
        `INSERT INTO channel_onboarding_discovery_tickets(
           ticket_id, schema_version, dedupe_key, provider, account_id,
           external_user_id, external_tenant_id, conversation_id, thread_key,
           ingress_surface, first_message_preview, proposed_scope_type, proposed_scope_id,
           recommended_binding_mode, status, event_count, first_seen_at_ms, last_seen_at_ms,
           created_at_ms, updated_at_ms, expires_at_ms, last_request_id, audit_ref
         ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
      )
      .run(
        persisted.ticket_id,
        persisted.schema_version,
        persisted.dedupe_key,
        persisted.provider,
        persisted.account_id,
        persisted.external_user_id,
        persisted.external_tenant_id,
        persisted.conversation_id,
        persisted.thread_key,
        persisted.ingress_surface,
        persisted.first_message_preview,
        persisted.proposed_scope_type,
        persisted.proposed_scope_id,
        persisted.recommended_binding_mode,
        persisted.status,
        persisted.event_count,
        persisted.first_seen_at_ms,
        persisted.last_seen_at_ms,
        persisted.created_at_ms,
        persisted.updated_at_ms,
        persisted.expires_at_ms,
        persisted.last_request_id,
        audit_ref
      );
    db.db.exec('COMMIT;');
    return {
      ok: true,
      deny_code: '',
      ticket: {
        ...persisted,
        audit_ref,
      },
      audit_logged: true,
      created: true,
      updated: false,
    };
  } catch (error) {
    try {
      db.db.exec('ROLLBACK;');
    } catch {
      // ignore
    }
    return deny('audit_write_failed', {
      error: safeString(error?.message || 'audit_write_failed'),
    }, normalized);
  }
}

function reviewDeny(deny_code, detail = {}, ticket = null, decision = null) {
  return {
    ok: false,
    deny_code: safeString(deny_code) || 'channel_onboarding_review_rejected',
    detail: detail && typeof detail === 'object' ? detail : {},
    ticket,
    decision,
    audit_logged: false,
  };
}

export function reviewChannelOnboardingDiscoveryTicket(db, {
  ticket_id = '',
  decision = {},
  audit = {},
  request_id = '',
} = {}) {
  ensureDb(db);
  const now = nowMs();
  const ticket = markExpiredIfNeeded(db, getChannelOnboardingDiscoveryTicketById(db, { ticket_id }));
  if (!ticket) {
    return reviewDeny('ticket_not_found');
  }
  if (ticket.status === 'expired') {
    return reviewDeny('ticket_expired', {}, ticket);
  }
  if (ticket.status !== 'pending' && ticket.status !== 'held') {
    return reviewDeny('ticket_not_open', {
      status: safeString(ticket.status),
    }, ticket);
  }

  const normalizedDecision = normalizeChannelOnboardingApprovalDecisionDraft({
    ...decision,
    ticket_id: safeString(ticket.ticket_id),
    binding_mode: safeString(decision.binding_mode) || safeString(ticket.recommended_binding_mode),
    scope_type: safeString(decision.scope_type) || safeString(ticket.proposed_scope_type),
    scope_id: safeString(decision.scope_id) || safeString(ticket.proposed_scope_id),
  }, {
    now_ms: now,
  });

  if (!normalizedDecision.decision) {
    return reviewDeny('decision_invalid', {}, ticket);
  }
  if (!normalizedDecision.approved_by_hub_user_id) {
    return reviewDeny('approved_by_hub_user_id_missing', {}, ticket);
  }
  if (normalizedDecision.decision === 'approve') {
    if (!normalizedDecision.hub_user_id) {
      return reviewDeny('hub_user_id_missing', {}, ticket, normalizedDecision);
    }
    if (!normalizedDecision.scope_type || !normalizedDecision.scope_id) {
      return reviewDeny('scope_missing', {}, ticket, normalizedDecision);
    }
    if (!normalizedDecision.allowed_actions.length) {
      return reviewDeny('allowed_actions_missing', {}, ticket, normalizedDecision);
    }
    const unsafeActions = normalizedDecision.allowed_actions.filter((action) => !SAFE_ALLOWED_ACTION_SET.has(action));
    if (unsafeActions.length) {
      return reviewDeny('allowed_actions_unsafe', {
        unsafe_actions: unsafeActions,
      }, ticket, normalizedDecision);
    }
    if (normalizedDecision.binding_mode === 'thread_binding' && !safeString(ticket.thread_key)) {
      return reviewDeny('thread_binding_requires_thread_key', {}, ticket, normalizedDecision);
    }
  }

  const nextStatus = normalizedDecision.decision === 'approve'
    ? 'approved'
    : (normalizedDecision.decision === 'reject' ? 'rejected' : 'held');
  const persistedDecision = {
    ...normalizedDecision,
    decision_id: normalizedDecision.decision_id || uuid(),
    grant_profile: normalizedDecision.decision === 'approve'
      ? (safeString(normalizedDecision.grant_profile) || 'low_risk_readonly')
      : '',
  };

  db.db.exec('BEGIN;');
  try {
    let autoBind = null;
    const audit_ref = appendApprovalDecisionAudit({
      db,
      ticket,
      decision: persistedDecision,
      request_id,
      audit,
    });
    db.db.prepare(
      `INSERT INTO channel_onboarding_approval_decisions(
         decision_id, schema_version, ticket_id, decision, approved_by_hub_user_id,
         approved_via, hub_user_id, scope_type, scope_id, binding_mode,
         preferred_device_id, allowed_actions_json, grant_profile, note,
         created_at_ms, audit_ref
       ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
    ).run(
      persistedDecision.decision_id,
      persistedDecision.schema_version,
      persistedDecision.ticket_id,
      persistedDecision.decision,
      persistedDecision.approved_by_hub_user_id,
      persistedDecision.approved_via,
      persistedDecision.hub_user_id,
      persistedDecision.scope_type,
      persistedDecision.scope_id,
      persistedDecision.binding_mode,
      persistedDecision.preferred_device_id || null,
      JSON.stringify(persistedDecision.allowed_actions),
      persistedDecision.grant_profile,
      persistedDecision.note,
      persistedDecision.created_at_ms,
      audit_ref
    );

    if (persistedDecision.decision === 'approve') {
      autoBind = writeApprovedChannelOnboardingAutoBindTx(db, {
        ticket,
        decision: persistedDecision,
        request_id,
        audit,
      });
      if (!autoBind.ok) {
        db.db.exec('ROLLBACK;');
        try {
          appendChannelOnboardingAutoBindRejectedAudit(db, {
            ticket,
            decision: persistedDecision,
            identity_binding: autoBind.identity_binding,
            channel_binding: autoBind.channel_binding,
            request_id,
            audit,
            deny_code: autoBind.deny_code,
            detail: autoBind.detail,
          });
        } catch (rejectAuditError) {
          return reviewDeny('audit_write_failed', {
            error: safeString(rejectAuditError?.message || 'audit_write_failed'),
            auto_bind_deny_code: safeString(autoBind.deny_code),
          }, ticket, normalizedDecision);
        }
        return reviewDeny(autoBind.deny_code, autoBind.detail, ticket, normalizedDecision);
      }
    }

    const nextTicket = {
      ...ticket,
      proposed_scope_type: persistedDecision.decision === 'approve'
        ? (persistedDecision.scope_type || ticket.proposed_scope_type)
        : ticket.proposed_scope_type,
      proposed_scope_id: persistedDecision.decision === 'approve'
        ? (persistedDecision.scope_id || ticket.proposed_scope_id)
        : ticket.proposed_scope_id,
      recommended_binding_mode: persistedDecision.decision === 'approve'
        ? (persistedDecision.binding_mode || ticket.recommended_binding_mode)
        : ticket.recommended_binding_mode,
      status: nextStatus,
      updated_at_ms: now,
      expires_at_ms: nextStatus === 'held'
        ? Math.max(safeInt(ticket.expires_at_ms, 0), now + CHANNEL_ONBOARDING_DISCOVERY_TICKET_TTL_MS)
        : ticket.expires_at_ms,
      audit_ref,
    };
    db.db.prepare(
      `UPDATE channel_onboarding_discovery_tickets
       SET proposed_scope_type = ?,
           proposed_scope_id = ?,
           recommended_binding_mode = ?,
           status = ?,
           updated_at_ms = ?,
           expires_at_ms = ?,
           audit_ref = ?
       WHERE ticket_id = ?`
    ).run(
      nextTicket.proposed_scope_type,
      nextTicket.proposed_scope_id,
      nextTicket.recommended_binding_mode,
      nextTicket.status,
      nextTicket.updated_at_ms,
      nextTicket.expires_at_ms,
      nextTicket.audit_ref,
      nextTicket.ticket_id
    );
    db.db.exec('COMMIT;');
    return {
      ok: true,
      deny_code: '',
      ticket: nextTicket,
      decision: {
        ...persistedDecision,
        audit_ref,
      },
      audit_logged: true,
      auto_bind_receipt: autoBind?.receipt || null,
    };
  } catch (error) {
    try {
      db.db.exec('ROLLBACK;');
    } catch {
      // ignore
    }
    return reviewDeny('audit_write_failed', {
      error: safeString(error?.message || 'audit_write_failed'),
    }, ticket, normalizedDecision);
  }
}
