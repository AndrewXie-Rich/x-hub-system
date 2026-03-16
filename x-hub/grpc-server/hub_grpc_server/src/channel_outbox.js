import { nowMs, uuid } from './util.js';

export const CHANNEL_OUTBOX_ITEM_SCHEMA = 'xhub.channel_outbox_item.v1';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function parseJsonObject(input) {
  if (input && typeof input === 'object' && !Array.isArray(input)) return input;
  const text = safeString(input);
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function ensureDb(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.exec !== 'function') {
    throw new Error('channel_outbox_db_required');
  }
  db.db.exec(`
    CREATE TABLE IF NOT EXISTS channel_outbox_items (
      item_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      provider TEXT NOT NULL,
      item_kind TEXT NOT NULL,
      status TEXT NOT NULL,
      ticket_id TEXT NOT NULL,
      decision_id TEXT NOT NULL,
      receipt_id TEXT NOT NULL,
      dedupe_key TEXT NOT NULL UNIQUE,
      delivery_context_json TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      attempt_count INTEGER NOT NULL,
      last_error_code TEXT NOT NULL,
      last_error_message TEXT NOT NULL,
      provider_message_ref TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      delivered_at_ms INTEGER NOT NULL,
      audit_ref TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_channel_outbox_items_ticket
      ON channel_outbox_items(ticket_id, updated_at_ms DESC);

    CREATE INDEX IF NOT EXISTS idx_channel_outbox_items_provider_status
      ON channel_outbox_items(provider, status, updated_at_ms DESC);
  `);
}

function parseRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    item_id: safeString(row.item_id),
    schema_version: safeString(row.schema_version) || CHANNEL_OUTBOX_ITEM_SCHEMA,
    provider: safeString(row.provider).toLowerCase(),
    item_kind: safeString(row.item_kind),
    status: safeString(row.status) || 'pending',
    ticket_id: safeString(row.ticket_id),
    decision_id: safeString(row.decision_id),
    receipt_id: safeString(row.receipt_id),
    dedupe_key: safeString(row.dedupe_key),
    delivery_context: parseJsonObject(row.delivery_context_json),
    payload: parseJsonObject(row.payload_json),
    attempt_count: safeInt(row.attempt_count, 0),
    last_error_code: safeString(row.last_error_code),
    last_error_message: safeString(row.last_error_message),
    provider_message_ref: safeString(row.provider_message_ref),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    delivered_at_ms: safeInt(row.delivered_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

function appendOutboxAudit({
  db,
  event_type,
  item,
  request_id = '',
  audit = {},
  ok = true,
  error_code = '',
  error_message = '',
} = {}) {
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type: safeString(event_type) || 'channel.outbox.updated',
    created_at_ms: nowMs(),
    severity: ok ? 'info' : 'warn',
    device_id: safeString(audit.device_id || 'channel_outbox'),
    user_id: safeString(audit.user_id) || null,
    app_id: safeString(audit.app_id || 'channel_outbox'),
    project_id: safeString(audit.project_id) || null,
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: 'channel.outbox.write',
    model_id: null,
    ok: !!ok,
    error_code: ok ? null : (safeString(error_code) || 'channel_outbox_delivery_failed'),
    error_message: ok ? null : (safeString(error_message) || safeString(error_code) || 'channel_outbox_delivery_failed'),
    ext_json: JSON.stringify({
      schema_version: CHANNEL_OUTBOX_ITEM_SCHEMA,
      item_id: safeString(item?.item_id),
      provider: safeString(item?.provider),
      item_kind: safeString(item?.item_kind),
      ticket_id: safeString(item?.ticket_id),
      decision_id: safeString(item?.decision_id),
      receipt_id: safeString(item?.receipt_id),
      dedupe_key: safeString(item?.dedupe_key),
      status: safeString(item?.status),
      attempt_count: safeInt(item?.attempt_count, 0),
      provider_message_ref: safeString(item?.provider_message_ref),
    }),
  });
}

export function getChannelOutboxItemByDedupeKey(db, {
  dedupe_key = '',
} = {}) {
  ensureDb(db);
  const row = db.db
    .prepare(
      `SELECT *
       FROM channel_outbox_items
       WHERE dedupe_key = ?
       LIMIT 1`
    )
    .get(safeString(dedupe_key));
  return parseRow(row);
}

export function getChannelOutboxItemById(db, {
  item_id = '',
} = {}) {
  ensureDb(db);
  const row = db.db
    .prepare(
      `SELECT *
       FROM channel_outbox_items
       WHERE item_id = ?
       LIMIT 1`
    )
    .get(safeString(item_id));
  return parseRow(row);
}

export function listChannelOutboxItems(db, filters = {}) {
  ensureDb(db);
  const where = [];
  const args = [];
  const provider = safeString(filters.provider).toLowerCase();
  const item_kind = safeString(filters.item_kind);
  const status = safeString(filters.status);
  const ticket_id = safeString(filters.ticket_id);
  const decision_id = safeString(filters.decision_id);
  if (provider) {
    where.push('provider = ?');
    args.push(provider);
  }
  if (item_kind) {
    where.push('item_kind = ?');
    args.push(item_kind);
  }
  if (status) {
    where.push('status = ?');
    args.push(status);
  }
  if (ticket_id) {
    where.push('ticket_id = ?');
    args.push(ticket_id);
  }
  if (decision_id) {
    where.push('decision_id = ?');
    args.push(decision_id);
  }
  const limit = Math.max(1, Math.min(200, safeInt(filters.limit, 100) || 100));
  const sql = `
    SELECT *
    FROM channel_outbox_items
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY created_at_ms ASC
    LIMIT ${limit}
  `;
  return db.db.prepare(sql).all(...args).map((row) => parseRow(row)).filter(Boolean);
}

export function enqueueChannelOutboxItem(db, {
  item = {},
  request_id = '',
  audit = {},
} = {}) {
  ensureDb(db);
  const now = nowMs();
  const normalized = {
    item_id: safeString(item.item_id) || uuid(),
    schema_version: CHANNEL_OUTBOX_ITEM_SCHEMA,
    provider: safeString(item.provider).toLowerCase(),
    item_kind: safeString(item.item_kind),
    status: 'pending',
    ticket_id: safeString(item.ticket_id),
    decision_id: safeString(item.decision_id),
    receipt_id: safeString(item.receipt_id),
    dedupe_key: safeString(item.dedupe_key),
    delivery_context: safeObject(item.delivery_context),
    payload: safeObject(item.payload),
    attempt_count: 0,
    last_error_code: '',
    last_error_message: '',
    provider_message_ref: '',
    created_at_ms: now,
    updated_at_ms: now,
    delivered_at_ms: 0,
    audit_ref: '',
  };
  if (!normalized.provider) {
    return {
      ok: false,
      deny_code: 'provider_missing',
      item: null,
      audit_logged: false,
    };
  }
  if (!normalized.item_kind) {
    return {
      ok: false,
      deny_code: 'item_kind_missing',
      item: null,
      audit_logged: false,
    };
  }
  if (!normalized.ticket_id) {
    return {
      ok: false,
      deny_code: 'ticket_id_missing',
      item: null,
      audit_logged: false,
    };
  }
  if (!normalized.dedupe_key) {
    return {
      ok: false,
      deny_code: 'dedupe_key_missing',
      item: null,
      audit_logged: false,
    };
  }

  const existing = getChannelOutboxItemByDedupeKey(db, {
    dedupe_key: normalized.dedupe_key,
  });
  if (existing) {
    return {
      ok: true,
      deny_code: '',
      item: existing,
      audit_logged: false,
      created: false,
    };
  }

  const audit_ref = appendOutboxAudit({
    db,
    event_type: 'channel.outbox.queued',
    item: normalized,
    request_id,
    audit,
    ok: true,
  });
  db.db.prepare(
    `INSERT INTO channel_outbox_items(
       item_id, schema_version, provider, item_kind, status, ticket_id, decision_id,
       receipt_id, dedupe_key, delivery_context_json, payload_json, attempt_count,
       last_error_code, last_error_message, provider_message_ref,
       created_at_ms, updated_at_ms, delivered_at_ms, audit_ref
     ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
  ).run(
    normalized.item_id,
    normalized.schema_version,
    normalized.provider,
    normalized.item_kind,
    normalized.status,
    normalized.ticket_id,
    normalized.decision_id,
    normalized.receipt_id,
    normalized.dedupe_key,
    JSON.stringify(normalized.delivery_context),
    JSON.stringify(normalized.payload),
    normalized.attempt_count,
    normalized.last_error_code,
    normalized.last_error_message,
    normalized.provider_message_ref,
    normalized.created_at_ms,
    normalized.updated_at_ms,
    normalized.delivered_at_ms,
    audit_ref
  );
  return {
    ok: true,
    deny_code: '',
    item: getChannelOutboxItemById(db, {
      item_id: normalized.item_id,
    }),
    audit_logged: true,
    created: true,
  };
}

export function recordChannelOutboxDeliveryResult(db, {
  item_id = '',
  delivered = false,
  deny_code = '',
  error_message = '',
  provider_message_ref = '',
  request_id = '',
  audit = {},
} = {}) {
  ensureDb(db);
  const existing = getChannelOutboxItemById(db, {
    item_id,
  });
  if (!existing) {
    return {
      ok: false,
      deny_code: 'outbox_item_not_found',
      item: null,
      audit_logged: false,
    };
  }

  const updated = {
    ...existing,
    status: delivered ? 'delivered' : 'pending',
    attempt_count: safeInt(existing.attempt_count, 0) + 1,
    last_error_code: delivered ? '' : safeString(deny_code),
    last_error_message: delivered ? '' : safeString(error_message || deny_code),
    provider_message_ref: delivered ? safeString(provider_message_ref) : safeString(existing.provider_message_ref),
    delivered_at_ms: delivered ? nowMs() : safeInt(existing.delivered_at_ms, 0),
    updated_at_ms: nowMs(),
  };
  const audit_ref = appendOutboxAudit({
    db,
    event_type: delivered ? 'channel.outbox.delivered' : 'channel.outbox.delivery_failed',
    item: updated,
    request_id,
    audit,
    ok: delivered,
    error_code: deny_code,
    error_message,
  });
  db.db.prepare(
    `UPDATE channel_outbox_items
     SET status = ?,
         attempt_count = ?,
         last_error_code = ?,
         last_error_message = ?,
         provider_message_ref = ?,
         updated_at_ms = ?,
         delivered_at_ms = ?,
         audit_ref = ?
     WHERE item_id = ?`
  ).run(
    updated.status,
    updated.attempt_count,
    updated.last_error_code,
    updated.last_error_message,
    updated.provider_message_ref,
    updated.updated_at_ms,
    updated.delivered_at_ms,
    audit_ref,
    updated.item_id
  );
  return {
    ok: true,
    deny_code: '',
    item: getChannelOutboxItemById(db, {
      item_id: updated.item_id,
    }),
    audit_logged: true,
  };
}
