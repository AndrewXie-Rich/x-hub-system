import { nowMs } from './util.js';

function safeInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.floor(n);
}

function clamp(v, min, max, fallback) {
  const x = safeInt(v, fallback);
  return Math.max(min, Math.min(max, x));
}

function normalizeConsumerId(v) {
  const id = String(v || '').trim();
  if (!id) throw new Error('missing consumer_id');
  return id.length > 128 ? id.slice(0, 128) : id;
}

function normalizeErrorMessage(err) {
  if (!err) return 'unknown_error';
  if (typeof err === 'string') return err || 'unknown_error';
  if (err instanceof Error) return String(err.message || err.name || 'error');
  return String(err);
}

export function computeRetryBackoffMs(attempt, baseMs, capMs) {
  const att = Math.max(1, safeInt(attempt, 1));
  const base = Math.max(1, safeInt(baseMs, 50));
  const cap = Math.max(base, safeInt(capMs, 5000));
  const raw = base * (2 ** (att - 1));
  return Math.min(cap, raw);
}

export function consumeMemoryIndexChangelogBatch(opts = {}) {
  const db = opts?.db;
  const onEvent = opts?.on_event;
  if (!db || typeof db.listMemoryIndexChangelog !== 'function') {
    throw new Error('missing db adapter');
  }
  if (typeof onEvent !== 'function') {
    throw new Error('missing on_event handler');
  }

  const consumerId = normalizeConsumerId(opts?.consumer_id);
  const limit = clamp(opts?.batch_limit, 1, 1000, 100);
  const maxRetries = clamp(opts?.max_retries, 1, 10, 3);
  const retryBaseMs = clamp(opts?.retry_backoff_base_ms, 1, 60_000, 50);
  const retryCapMs = clamp(opts?.retry_backoff_cap_ms, retryBaseMs, 10 * 60_000, 5000);
  const startedAtMs = Math.max(0, safeInt(opts?.now_ms, nowMs()));

  let checkpoint = db.getMemoryIndexConsumerCheckpoint({
    consumer_id: consumerId,
    create_if_missing: true,
  }) || {};
  let nextSeq = Math.max(0, safeInt(checkpoint.checkpoint_seq, 0));

  db.upsertMemoryIndexConsumerCheckpoint({
    consumer_id: consumerId,
    checkpoint_seq: nextSeq,
    status: 'running',
    retry_count: Math.max(0, safeInt(checkpoint.retry_count, 0)),
    updated_at_ms: startedAtMs,
  });

  const rows = db.listMemoryIndexChangelog({
    since_seq: nextSeq,
    limit,
  });

  const out = {
    ok: true,
    consumer_id: consumerId,
    from_seq: nextSeq,
    next_seq: nextSeq,
    fetched: rows.length,
    applied: 0,
    skipped: 0,
    failed: 0,
    retries: 0,
    drained: rows.length < limit,
    status: 'idle',
    last_error: '',
    suggested_backoff_ms: 0,
  };

  for (const row of rows) {
    const eventId = String(row?.event_id || '').trim();
    const eventType = String(row?.event_type || '').trim().toLowerCase();
    const tableName = String(row?.table_name || '').trim();
    const source = String(row?.source || '').trim() || 'unknown';
    const seq = Math.max(0, safeInt(row?.seq, 0));
    const ts = Math.max(0, safeInt(row?.created_at_ms, startedAtMs));

    if (!eventId || !eventType || !tableName || seq <= 0) {
      const errMsg = 'invalid_changelog_event_row';
      out.ok = false;
      out.failed += 1;
      out.status = 'error';
      out.last_error = errMsg;
      out.suggested_backoff_ms = computeRetryBackoffMs(1, retryBaseMs, retryCapMs);
      db.upsertMemoryIndexConsumerCheckpoint({
        consumer_id: consumerId,
        checkpoint_seq: nextSeq,
        last_event_id: eventId || null,
        status: 'error',
        retry_count: Math.max(1, safeInt(checkpoint.retry_count, 0) + 1),
        last_error: errMsg,
        last_failed_at_ms: startedAtMs,
      });
      return out;
    }

    if (db.hasMemoryIndexConsumerProcessedEvent({ consumer_id: consumerId, event_id: eventId })) {
      nextSeq = Math.max(nextSeq, seq);
      out.next_seq = nextSeq;
      out.skipped += 1;
      db.upsertMemoryIndexConsumerCheckpoint({
        consumer_id: consumerId,
        checkpoint_seq: nextSeq,
        last_event_id: eventId,
        status: 'running',
        retry_count: 0,
        last_error: null,
        last_processed_at_ms: ts,
      });
      continue;
    }

    let applied = false;
    let lastErrMsg = '';
    for (let attempt = 1; attempt <= maxRetries; attempt += 1) {
      try {
        onEvent(row, {
          consumer_id: consumerId,
          attempt,
          from_seq: out.from_seq,
          checkpoint_seq: nextSeq,
          started_at_ms: startedAtMs,
        });
        const inserted = db.recordMemoryIndexConsumerProcessedEvent({
          consumer_id: consumerId,
          event_id: eventId,
          seq,
          event_type: eventType,
          table_name: tableName,
          source,
          processed_at_ms: nowMs(),
        });

        nextSeq = Math.max(nextSeq, seq);
        out.next_seq = nextSeq;
        if (inserted) out.applied += 1;
        else out.skipped += 1;

        db.upsertMemoryIndexConsumerCheckpoint({
          consumer_id: consumerId,
          checkpoint_seq: nextSeq,
          last_event_id: eventId,
          status: 'running',
          retry_count: 0,
          last_error: null,
          last_processed_at_ms: nowMs(),
        });
        applied = true;
        break;
      } catch (err) {
        lastErrMsg = normalizeErrorMessage(err);
        if (attempt < maxRetries) out.retries += 1;
      }
    }

    if (!applied) {
      out.ok = false;
      out.failed += 1;
      out.status = 'error';
      out.last_error = lastErrMsg || 'consume_failed';
      const retryCount = Math.max(1, safeInt(checkpoint.retry_count, 0) + 1);
      out.suggested_backoff_ms = computeRetryBackoffMs(retryCount, retryBaseMs, retryCapMs);
      db.upsertMemoryIndexConsumerCheckpoint({
        consumer_id: consumerId,
        checkpoint_seq: nextSeq,
        last_event_id: eventId,
        status: 'error',
        retry_count: retryCount,
        last_error: out.last_error,
        last_failed_at_ms: nowMs(),
      });
      return out;
    }

    checkpoint = db.getMemoryIndexConsumerCheckpoint({
      consumer_id: consumerId,
      create_if_missing: false,
    }) || checkpoint;
  }

  db.upsertMemoryIndexConsumerCheckpoint({
    consumer_id: consumerId,
    checkpoint_seq: nextSeq,
    status: 'idle',
    retry_count: 0,
    last_error: null,
    updated_at_ms: nowMs(),
  });
  return out;
}
