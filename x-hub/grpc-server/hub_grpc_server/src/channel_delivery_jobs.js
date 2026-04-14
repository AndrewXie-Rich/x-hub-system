import { normalizeChannelProviderId } from './channel_registry.js';
import { computeRetryBackoffMs } from './memory_index_consumer.js';
import { nowMs, uuid } from './util.js';

export const CHANNEL_DELIVERY_JOB_SCHEMA = 'xhub.channel_delivery_job.v1';

const DELIVERY_JOB_STATES = new Set([
  'queued',
  'sending',
  'sent',
  'failed',
  'canceled',
  'dead_letter',
]);

const DELIVERY_CLASS_ALIASES = Object.freeze({
  alert: 'alert',
  heartbeat: 'heartbeat',
  cron_summary: 'cron_summary',
  cron: 'cron_summary',
  cronsummary: 'cron_summary',
  run_summary: 'run_summary',
  run: 'run_summary',
  summary: 'run_summary',
  final_result: 'run_summary',
  approval_request: 'approval_request',
  approval: 'approval_request',
  approval_card: 'approval_request',
});

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null) return fallback;
  if (input === 1 || input === '1' || input === 'true') return true;
  if (input === 0 || input === '0' || input === 'false') return false;
  return fallback;
}

function normalizeProvider(input) {
  const normalized = normalizeChannelProviderId(input);
  return normalized || '';
}

function normalizeDeliveryClass(input) {
  const key = safeString(input)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return DELIVERY_CLASS_ALIASES[key] || '';
}

function clampInt(input, { fallback = 0, min = 0, max = Number.MAX_SAFE_INTEGER } = {}) {
  const n = safeInt(input, fallback);
  return Math.max(min, Math.min(max, n));
}

function normalizeJobState(input, fallback = 'queued') {
  const key = safeString(input).toLowerCase();
  return DELIVERY_JOB_STATES.has(key) ? key : fallback;
}

function ensureDb(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.exec !== 'function') {
    throw new Error('channel_delivery_jobs_db_required');
  }
  db.db.exec(`
    CREATE TABLE IF NOT EXISTS channel_delivery_jobs (
      job_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      provider TEXT NOT NULL,
      account_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      thread_key TEXT NOT NULL,
      delivery_class TEXT NOT NULL,
      payload_ref TEXT NOT NULL,
      dedupe_key TEXT NOT NULL UNIQUE,
      state TEXT NOT NULL,
      retry_after_ms INTEGER NOT NULL,
      next_attempt_at_ms INTEGER NOT NULL,
      provider_backoff_until_ms INTEGER NOT NULL,
      cooldown_until_ms INTEGER NOT NULL,
      attempt_count INTEGER NOT NULL,
      max_attempts INTEGER NOT NULL,
      last_error_code TEXT NOT NULL,
      last_error_message TEXT NOT NULL,
      provider_message_ref TEXT NOT NULL,
      last_success_at_ms INTEGER NOT NULL,
      last_failure_at_ms INTEGER NOT NULL,
      dead_letter_at_ms INTEGER NOT NULL,
      manual_retry_available INTEGER NOT NULL,
      originating_run_ref TEXT NOT NULL,
      incident_ref TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      audit_ref TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_channel_delivery_jobs_provider_due
      ON channel_delivery_jobs(provider, account_id, state, next_attempt_at_ms, provider_backoff_until_ms, cooldown_until_ms);

    CREATE INDEX IF NOT EXISTS idx_channel_delivery_jobs_runtime
      ON channel_delivery_jobs(provider, account_id, updated_at_ms DESC);

    CREATE INDEX IF NOT EXISTS idx_channel_delivery_jobs_manual_retry
      ON channel_delivery_jobs(provider, manual_retry_available, updated_at_ms DESC);
  `);
}

function parseRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    job_id: safeString(row.job_id),
    schema_version: safeString(row.schema_version) || CHANNEL_DELIVERY_JOB_SCHEMA,
    provider: safeString(row.provider),
    account_id: safeString(row.account_id),
    conversation_id: safeString(row.conversation_id),
    thread_key: safeString(row.thread_key),
    delivery_class: safeString(row.delivery_class),
    payload_ref: safeString(row.payload_ref),
    dedupe_key: safeString(row.dedupe_key),
    state: normalizeJobState(row.state),
    retry_after_ms: safeInt(row.retry_after_ms, 0),
    next_attempt_at_ms: safeInt(row.next_attempt_at_ms, 0),
    provider_backoff_until_ms: safeInt(row.provider_backoff_until_ms, 0),
    cooldown_until_ms: safeInt(row.cooldown_until_ms, 0),
    attempt_count: safeInt(row.attempt_count, 0),
    max_attempts: safeInt(row.max_attempts, 0),
    last_error_code: safeString(row.last_error_code),
    last_error_message: safeString(row.last_error_message),
    provider_message_ref: safeString(row.provider_message_ref),
    last_success_at_ms: safeInt(row.last_success_at_ms, 0),
    last_failure_at_ms: safeInt(row.last_failure_at_ms, 0),
    dead_letter_at_ms: safeInt(row.dead_letter_at_ms, 0),
    manual_retry_available: safeBool(row.manual_retry_available, false),
    originating_run_ref: safeString(row.originating_run_ref),
    incident_ref: safeString(row.incident_ref),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

function appendDeliveryJobAudit({
  db,
  event_type,
  job,
  request_id = '',
  audit = {},
  ok = true,
  error_code = '',
  error_message = '',
} = {}) {
  if (!db || typeof db.appendAudit !== 'function') return '';
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type: safeString(event_type) || 'channel.delivery_job.updated',
    created_at_ms: nowMs(),
    severity: ok ? 'info' : 'warn',
    device_id: safeString(audit.device_id || 'channel_delivery_jobs'),
    user_id: safeString(audit.user_id) || null,
    app_id: safeString(audit.app_id || 'channel_delivery_jobs'),
    project_id: safeString(audit.project_id) || null,
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: 'channel.delivery_job.write',
    model_id: null,
    ok: !!ok,
    error_code: ok ? null : (safeString(error_code) || 'channel_delivery_job_failed'),
    error_message: ok ? null : (safeString(error_message) || safeString(error_code) || 'channel_delivery_job_failed'),
    ext_json: JSON.stringify({
      schema_version: CHANNEL_DELIVERY_JOB_SCHEMA,
      job_id: safeString(job?.job_id),
      provider: safeString(job?.provider),
      account_id: safeString(job?.account_id),
      conversation_id: safeString(job?.conversation_id),
      delivery_class: safeString(job?.delivery_class),
      state: safeString(job?.state),
      attempt_count: safeInt(job?.attempt_count, 0),
      retry_after_ms: safeInt(job?.retry_after_ms, 0),
      manual_retry_available: !!job?.manual_retry_available,
      audit_ref: safeString(job?.audit_ref),
      incident_ref: safeString(job?.incident_ref),
      originating_run_ref: safeString(job?.originating_run_ref),
    }),
  });
}

function normalizeCreateJob(input = {}, now = nowMs()) {
  const provider = normalizeProvider(input.provider);
  const delivery_class = normalizeDeliveryClass(input.delivery_class);
  const max_attempts = clampInt(input.max_attempts, { fallback: 3, min: 1, max: 10 });
  return {
    job_id: safeString(input.job_id) || uuid(),
    schema_version: CHANNEL_DELIVERY_JOB_SCHEMA,
    provider,
    account_id: safeString(input.account_id),
    conversation_id: safeString(input.conversation_id),
    thread_key: safeString(input.thread_key),
    delivery_class,
    payload_ref: safeString(input.payload_ref),
    dedupe_key: safeString(input.dedupe_key),
    state: 'queued',
    retry_after_ms: 0,
    next_attempt_at_ms: now,
    provider_backoff_until_ms: 0,
    cooldown_until_ms: 0,
    attempt_count: 0,
    max_attempts,
    last_error_code: '',
    last_error_message: '',
    provider_message_ref: '',
    last_success_at_ms: 0,
    last_failure_at_ms: 0,
    dead_letter_at_ms: 0,
    manual_retry_available: false,
    originating_run_ref: safeString(input.originating_run_ref),
    incident_ref: safeString(input.incident_ref),
    created_at_ms: now,
    updated_at_ms: now,
    audit_ref: safeString(input.audit_ref),
  };
}

function updateProviderBackoff(db, {
  provider = '',
  account_id = '',
  exclude_job_id = '',
  until_ms = 0,
} = {}) {
  const providerId = safeString(provider);
  const accountId = safeString(account_id);
  const until = safeInt(until_ms, 0);
  if (!providerId || !accountId || until <= 0) return;
  db.db.prepare(
    `UPDATE channel_delivery_jobs
     SET provider_backoff_until_ms = CASE
       WHEN provider_backoff_until_ms > ? THEN provider_backoff_until_ms
       ELSE ?
     END
     WHERE provider = ?
       AND account_id = ?
       AND job_id <> ?
       AND state IN ('queued', 'failed', 'sending')`
  ).run(
    until,
    until,
    providerId,
    accountId,
    safeString(exclude_job_id)
  );
}

export function getChannelDeliveryJobById(db, {
  job_id = '',
} = {}) {
  ensureDb(db);
  const row = db.db.prepare(
    `SELECT *
     FROM channel_delivery_jobs
     WHERE job_id = ?
     LIMIT 1`
  ).get(safeString(job_id));
  return parseRow(row);
}

export function getChannelDeliveryJobByDedupeKey(db, {
  dedupe_key = '',
} = {}) {
  ensureDb(db);
  const row = db.db.prepare(
    `SELECT *
     FROM channel_delivery_jobs
     WHERE dedupe_key = ?
     LIMIT 1`
  ).get(safeString(dedupe_key));
  return parseRow(row);
}

export function listChannelDeliveryJobs(db, filters = {}) {
  ensureDb(db);
  const where = [];
  const args = [];
  const provider = normalizeProvider(filters.provider);
  const account_id = safeString(filters.account_id);
  const state = normalizeJobState(filters.state, '');
  const delivery_class = normalizeDeliveryClass(filters.delivery_class);
  const limit = clampInt(filters.limit, { fallback: 100, min: 1, max: 500 });
  const dueOnly = safeBool(filters.due_only, false);
  const manualRetryOnly = safeBool(filters.manual_retry_only, false);
  const now = clampInt(filters.now_ms, { fallback: nowMs(), min: 0 });

  if (provider) {
    where.push('provider = ?');
    args.push(provider);
  }
  if (account_id) {
    where.push('account_id = ?');
    args.push(account_id);
  }
  if (state) {
    where.push('state = ?');
    args.push(state);
  }
  if (delivery_class) {
    where.push('delivery_class = ?');
    args.push(delivery_class);
  }
  if (dueOnly) {
    where.push(`state IN ('queued', 'failed')`);
    where.push('manual_retry_available = 0');
    where.push('next_attempt_at_ms <= ?');
    where.push('provider_backoff_until_ms <= ?');
    where.push('cooldown_until_ms <= ?');
    args.push(now, now, now);
  }
  if (manualRetryOnly) {
    where.push('manual_retry_available = 1');
  }

  const sql = `
    SELECT *
    FROM channel_delivery_jobs
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY updated_at_ms DESC, created_at_ms DESC
    LIMIT ${limit}
  `;
  return db.db.prepare(sql).all(...args).map((row) => parseRow(row)).filter(Boolean);
}

export function enqueueChannelDeliveryJob(db, {
  job = {},
  request_id = '',
  audit = {},
} = {}) {
  ensureDb(db);
  const normalized = normalizeCreateJob(job, nowMs());
  if (!normalized.provider) {
    return { ok: false, deny_code: 'provider_invalid', job: null, created: false, audit_logged: false };
  }
  if (!normalized.account_id) {
    return { ok: false, deny_code: 'account_id_missing', job: null, created: false, audit_logged: false };
  }
  if (!normalized.conversation_id) {
    return { ok: false, deny_code: 'conversation_id_missing', job: null, created: false, audit_logged: false };
  }
  if (!normalized.delivery_class) {
    return { ok: false, deny_code: 'delivery_class_invalid', job: null, created: false, audit_logged: false };
  }
  if (!normalized.payload_ref) {
    return { ok: false, deny_code: 'payload_ref_missing', job: null, created: false, audit_logged: false };
  }
  if (!normalized.dedupe_key) {
    return { ok: false, deny_code: 'dedupe_key_missing', job: null, created: false, audit_logged: false };
  }
  if (!normalized.audit_ref) {
    return { ok: false, deny_code: 'audit_ref_missing', job: null, created: false, audit_logged: false };
  }

  const existing = getChannelDeliveryJobByDedupeKey(db, {
    dedupe_key: normalized.dedupe_key,
  });
  if (existing) {
    return {
      ok: true,
      deny_code: '',
      job: existing,
      created: false,
      audit_logged: false,
    };
  }

  const audit_ref = appendDeliveryJobAudit({
    db,
    event_type: 'channel.delivery_job.queued',
    job: normalized,
    request_id,
    audit,
    ok: true,
  }) || normalized.audit_ref;

  db.db.prepare(
    `INSERT INTO channel_delivery_jobs(
      job_id, schema_version, provider, account_id, conversation_id, thread_key,
      delivery_class, payload_ref, dedupe_key, state, retry_after_ms, next_attempt_at_ms,
      provider_backoff_until_ms, cooldown_until_ms, attempt_count, max_attempts,
      last_error_code, last_error_message, provider_message_ref, last_success_at_ms,
      last_failure_at_ms, dead_letter_at_ms, manual_retry_available, originating_run_ref,
      incident_ref, created_at_ms, updated_at_ms, audit_ref
    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
  ).run(
    normalized.job_id,
    normalized.schema_version,
    normalized.provider,
    normalized.account_id,
    normalized.conversation_id,
    normalized.thread_key,
    normalized.delivery_class,
    normalized.payload_ref,
    normalized.dedupe_key,
    normalized.state,
    normalized.retry_after_ms,
    normalized.next_attempt_at_ms,
    normalized.provider_backoff_until_ms,
    normalized.cooldown_until_ms,
    normalized.attempt_count,
    normalized.max_attempts,
    normalized.last_error_code,
    normalized.last_error_message,
    normalized.provider_message_ref,
    normalized.last_success_at_ms,
    normalized.last_failure_at_ms,
    normalized.dead_letter_at_ms,
    normalized.manual_retry_available ? 1 : 0,
    normalized.originating_run_ref,
    normalized.incident_ref,
    normalized.created_at_ms,
    normalized.updated_at_ms,
    audit_ref
  );

  return {
    ok: true,
    deny_code: '',
    job: getChannelDeliveryJobById(db, {
      job_id: normalized.job_id,
    }),
    created: true,
    audit_logged: true,
  };
}

export function claimChannelDeliveryJobs(db, {
  provider = '',
  account_id = '',
  limit = 20,
  now_ms = nowMs(),
  request_id = '',
  audit = {},
} = {}) {
  ensureDb(db);
  const where = [
    `state IN ('queued', 'failed')`,
    'manual_retry_available = 0',
    'next_attempt_at_ms <= ?',
    'provider_backoff_until_ms <= ?',
    'cooldown_until_ms <= ?',
  ];
  const args = [
    clampInt(now_ms, { fallback: nowMs(), min: 0 }),
    clampInt(now_ms, { fallback: nowMs(), min: 0 }),
    clampInt(now_ms, { fallback: nowMs(), min: 0 }),
  ];
  const providerId = normalizeProvider(provider);
  const accountId = safeString(account_id);
  if (providerId) {
    where.push('provider = ?');
    args.push(providerId);
  }
  if (accountId) {
    where.push('account_id = ?');
    args.push(accountId);
  }
  const due = db.db.prepare(
    `SELECT *
     FROM channel_delivery_jobs
     WHERE ${where.join(' AND ')}
     ORDER BY created_at_ms ASC, updated_at_ms ASC
     LIMIT ${clampInt(limit, { fallback: 20, min: 1, max: 200 })}`
  ).all(...args).map((row) => parseRow(row)).filter(Boolean);
  const claimed = [];
  const updatedAt = clampInt(now_ms, { fallback: nowMs(), min: 0 });
  for (const row of due) {
    db.db.prepare(
      `UPDATE channel_delivery_jobs
       SET state = 'sending',
           updated_at_ms = ?
       WHERE job_id = ?
         AND state IN ('queued', 'failed')
         AND manual_retry_available = 0`
    ).run(
      updatedAt,
      row.job_id
    );
    const claimedRow = getChannelDeliveryJobById(db, {
      job_id: row.job_id,
    });
    if (!claimedRow || claimedRow.state !== 'sending') continue;
    appendDeliveryJobAudit({
      db,
      event_type: 'channel.delivery_job.claimed',
      job: claimedRow,
      request_id,
      audit,
      ok: true,
    });
    claimed.push(claimedRow);
  }
  return claimed;
}

export function recordChannelDeliveryJobAttempt(db, {
  job_id = '',
  delivered = false,
  deny_code = '',
  error_message = '',
  provider_message_ref = '',
  retry_after_ms = 0,
  provider_backoff_ms = 0,
  cooldown_ms = 0,
  dead_letter = false,
  request_id = '',
  audit = {},
  now_ms = nowMs(),
} = {}) {
  ensureDb(db);
  const existing = getChannelDeliveryJobById(db, {
    job_id,
  });
  if (!existing) {
    return { ok: false, deny_code: 'channel_delivery_job_not_found', job: null, audit_logged: false };
  }
  if (existing.state === 'sent' || existing.state === 'canceled') {
    return { ok: false, deny_code: 'channel_delivery_job_terminal', job: existing, audit_logged: false };
  }

  const now = clampInt(now_ms, { fallback: nowMs(), min: 0 });
  const attempt_count = safeInt(existing.attempt_count, 0) + 1;

  if (delivered) {
    db.db.prepare(
      `UPDATE channel_delivery_jobs
       SET state = 'sent',
           retry_after_ms = 0,
           next_attempt_at_ms = 0,
           provider_backoff_until_ms = 0,
           cooldown_until_ms = 0,
           attempt_count = ?,
           last_error_code = '',
           last_error_message = '',
           provider_message_ref = ?,
           last_success_at_ms = ?,
           updated_at_ms = ?,
           manual_retry_available = 0
       WHERE job_id = ?`
    ).run(
      attempt_count,
      safeString(provider_message_ref),
      now,
      now,
      existing.job_id
    );
    const updated = getChannelDeliveryJobById(db, {
      job_id: existing.job_id,
    });
    appendDeliveryJobAudit({
      db,
      event_type: 'channel.delivery_job.sent',
      job: updated,
      request_id,
      audit,
      ok: true,
    });
    return {
      ok: true,
      deny_code: '',
      job: updated,
      audit_logged: true,
    };
  }

  const last_error_code = safeString(deny_code) || 'channel_delivery_failed';
  const last_error_message = safeString(error_message) || last_error_code;
  const computedRetryAfterMs = clampInt(
    retry_after_ms || computeRetryBackoffMs(attempt_count, 1_000, 5 * 60 * 1000),
    { fallback: 1_000, min: 0, max: 24 * 60 * 60 * 1000 }
  );
  const providerBackoffMs = Math.max(
    computedRetryAfterMs,
    clampInt(provider_backoff_ms, { fallback: 0, min: 0, max: 24 * 60 * 60 * 1000 })
  );
  const cooldownMs = clampInt(cooldown_ms, { fallback: 0, min: 0, max: 24 * 60 * 60 * 1000 });
  const shouldDeadLetter = !!dead_letter || attempt_count >= Math.max(1, safeInt(existing.max_attempts, 1));
  const next_attempt_at_ms = shouldDeadLetter ? 0 : now + computedRetryAfterMs;
  const provider_backoff_until_ms = providerBackoffMs > 0 ? now + providerBackoffMs : 0;
  const cooldown_until_ms = cooldownMs > 0 ? now + cooldownMs : 0;
  const state = shouldDeadLetter ? 'dead_letter' : 'failed';
  const manual_retry_available = shouldDeadLetter ? 1 : 0;
  const dead_letter_at_ms = shouldDeadLetter ? now : safeInt(existing.dead_letter_at_ms, 0);

  db.db.prepare(
    `UPDATE channel_delivery_jobs
     SET state = ?,
         retry_after_ms = ?,
         next_attempt_at_ms = ?,
         provider_backoff_until_ms = ?,
         cooldown_until_ms = ?,
         attempt_count = ?,
         last_error_code = ?,
         last_error_message = ?,
         last_failure_at_ms = ?,
         dead_letter_at_ms = ?,
         updated_at_ms = ?,
         manual_retry_available = ?
     WHERE job_id = ?`
  ).run(
    state,
    computedRetryAfterMs,
    next_attempt_at_ms,
    provider_backoff_until_ms,
    cooldown_until_ms,
    attempt_count,
    last_error_code,
    last_error_message,
    now,
    dead_letter_at_ms,
    now,
    manual_retry_available,
    existing.job_id
  );

  if (provider_backoff_until_ms > 0) {
    updateProviderBackoff(db, {
      provider: existing.provider,
      account_id: existing.account_id,
      exclude_job_id: existing.job_id,
      until_ms: provider_backoff_until_ms,
    });
  }

  const updated = getChannelDeliveryJobById(db, {
    job_id: existing.job_id,
  });
  appendDeliveryJobAudit({
    db,
    event_type: shouldDeadLetter
      ? 'channel.delivery_job.dead_lettered'
      : 'channel.delivery_job.failed',
    job: updated,
    request_id,
    audit,
    ok: false,
    error_code: last_error_code,
    error_message: last_error_message,
  });
  return {
    ok: true,
    deny_code: '',
    job: updated,
    audit_logged: true,
  };
}

export function retryChannelDeliveryJobManual(db, {
  job_id = '',
  request_id = '',
  audit = {},
  now_ms = nowMs(),
} = {}) {
  ensureDb(db);
  const existing = getChannelDeliveryJobById(db, {
    job_id,
  });
  if (!existing) {
    return { ok: false, deny_code: 'channel_delivery_job_not_found', job: null, audit_logged: false };
  }
  if (existing.state !== 'dead_letter' && existing.state !== 'failed') {
    return { ok: false, deny_code: 'channel_delivery_job_not_retryable', job: existing, audit_logged: false };
  }

  const now = clampInt(now_ms, { fallback: nowMs(), min: 0 });
  db.db.prepare(
    `UPDATE channel_delivery_jobs
     SET state = 'queued',
         retry_after_ms = 0,
         next_attempt_at_ms = ?,
         provider_backoff_until_ms = 0,
         cooldown_until_ms = 0,
         manual_retry_available = 0,
         updated_at_ms = ?
     WHERE job_id = ?`
  ).run(
    now,
    now,
    existing.job_id
  );
  const updated = getChannelDeliveryJobById(db, {
    job_id: existing.job_id,
  });
  appendDeliveryJobAudit({
    db,
    event_type: 'channel.delivery_job.manual_retry_queued',
    job: updated,
    request_id,
    audit,
    ok: true,
  });
  return {
    ok: true,
    deny_code: '',
    job: updated,
    audit_logged: true,
  };
}

export function listChannelDeliveryJobRuntimeRows(db, {
  provider = '',
  account_id = '',
  now_ms = nowMs(),
} = {}) {
  ensureDb(db);
  const rows = listChannelDeliveryJobs(db, {
    provider,
    account_id,
    limit: 500,
  });
  const now = clampInt(now_ms, { fallback: nowMs(), min: 0 });
  const byKey = new Map();

  for (const row of rows) {
    const key = `${row.provider}|${row.account_id}`;
    if (!byKey.has(key)) {
      byKey.set(key, {
        provider: row.provider,
        account_id: row.account_id,
        delivery_queue_depth: 0,
        delivery_failed_count: 0,
        delivery_dead_letter_count: 0,
        manual_retry_available: false,
        last_delivery_success_at_ms: 0,
        last_delivery_failure_at_ms: 0,
        last_delivery_error_code: '',
        provider_backoff_until_ms: 0,
        cooldown_until_ms: 0,
        updated_at_ms: 0,
      });
    }
    const agg = byKey.get(key);
    const rowFailureAt = Math.max(safeInt(row.last_failure_at_ms, 0), safeInt(row.dead_letter_at_ms, 0));
    if (row.state === 'queued' || row.state === 'failed' || row.state === 'sending') {
      agg.delivery_queue_depth += 1;
    }
    if (row.state === 'failed') {
      agg.delivery_failed_count += 1;
    }
    if (row.state === 'dead_letter') {
      agg.delivery_dead_letter_count += 1;
    }
    if (row.manual_retry_available) {
      agg.manual_retry_available = true;
    }
    agg.last_delivery_success_at_ms = Math.max(agg.last_delivery_success_at_ms, safeInt(row.last_success_at_ms, 0));
    if (rowFailureAt >= agg.last_delivery_failure_at_ms) {
      agg.last_delivery_failure_at_ms = rowFailureAt;
      if (row.last_error_code) {
        agg.last_delivery_error_code = row.last_error_code;
      }
    }
    agg.provider_backoff_until_ms = Math.max(agg.provider_backoff_until_ms, safeInt(row.provider_backoff_until_ms, 0));
    agg.cooldown_until_ms = Math.max(agg.cooldown_until_ms, safeInt(row.cooldown_until_ms, 0));
    agg.updated_at_ms = Math.max(agg.updated_at_ms, safeInt(row.updated_at_ms, 0));
  }

  return Array.from(byKey.values()).map((row) => ({
    ...row,
    delivery_circuit_open: row.delivery_dead_letter_count > 0
      || row.manual_retry_available
      || (
        row.provider_backoff_until_ms > now
        && (row.delivery_failed_count > 0 || row.delivery_queue_depth > 0)
      ),
  }));
}
