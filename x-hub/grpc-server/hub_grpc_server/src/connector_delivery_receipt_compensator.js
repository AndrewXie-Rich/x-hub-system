import crypto from 'node:crypto';

import { nowMs } from './util.js';

function safeString(v) {
  return String(v ?? '').trim();
}

function safeNum(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function boundedInt(raw, { fallback, min, max }) {
  const n = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function parsePositiveInt(v) {
  const n = Number.parseInt(String(v ?? ''), 10);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n;
}

function targetKey(connector, targetId) {
  const c = safeString(connector).toLowerCase();
  const t = safeString(targetId);
  if (!c || !t) return '';
  return `${c}:${t}`;
}

function receiptKey(connector, targetId, idempotencyKey) {
  const tKey = targetKey(connector, targetId);
  const idem = safeString(idempotencyKey);
  if (!tKey || !idem) return '';
  return `${tKey}:${idem}`;
}

function receiptToken() {
  return crypto.randomBytes(16).toString('hex');
}

function cloneReceipt(receipt) {
  if (!receipt || typeof receipt !== 'object') return null;
  return {
    connector: safeString(receipt.connector).toLowerCase(),
    target_id: safeString(receipt.target_id),
    idempotency_key: safeString(receipt.idempotency_key),
    receipt_token: safeString(receipt.receipt_token),
    event_id: safeString(receipt.event_id),
    event_sequence: Math.max(0, Number(receipt.event_sequence || 0)),
    delivery_state: safeString(receipt.delivery_state || 'prepared'),
    provider_receipt: safeString(receipt.provider_receipt),
    prepared_at_ms: Math.max(0, Number(receipt.prepared_at_ms || 0)),
    commit_deadline_at_ms: Math.max(0, Number(receipt.commit_deadline_at_ms || 0)),
    committed_at_ms: Math.max(0, Number(receipt.committed_at_ms || 0)),
    undo_requested_at_ms: Math.max(0, Number(receipt.undo_requested_at_ms || 0)),
    compensation_due_at_ms: Math.max(0, Number(receipt.compensation_due_at_ms || 0)),
    compensated_at_ms: Math.max(0, Number(receipt.compensated_at_ms || 0)),
    compensation_reason: safeString(receipt.compensation_reason),
    compensation_attempts: Math.max(0, Number(receipt.compensation_attempts || 0)),
    updated_at_ms: Math.max(0, Number(receipt.updated_at_ms || 0)),
    last_seen_at_ms: Math.max(0, Number(receipt.last_seen_at_ms || 0)),
  };
}

function initialStateCounts() {
  return {
    prepared: 0,
    committed: 0,
    undo_pending: 0,
    compensated: 0,
  };
}

export function createConnectorDeliveryReceiptCompensator(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const compensateFn = typeof opts.compensateFn === 'function' ? opts.compensateFn : null;

  const staleWindowMs = boundedInt(opts.stale_window_ms, {
    fallback: 6 * 60 * 60 * 1000,
    min: 60 * 1000,
    max: 14 * 24 * 60 * 60 * 1000,
  });
  const maxEntries = boundedInt(opts.max_entries, {
    fallback: 10_000,
    min: 64,
    max: 1_000_000,
  });
  const defaultCommitTimeoutMs = boundedInt(opts.default_commit_timeout_ms, {
    fallback: 30_000,
    min: 1_000,
    max: 24 * 60 * 60 * 1000,
  });
  const maxCompensationBatch = boundedInt(opts.max_compensation_batch, {
    fallback: 128,
    min: 1,
    max: 10_000,
  });
  const compensationRetryMs = boundedInt(opts.compensation_retry_ms, {
    fallback: 5_000,
    min: 500,
    max: 10 * 60 * 1000,
  });

  const receipts = new Map(); // key(connector:target:idempotency) -> receipt
  const targetIndex = new Map(); // key(connector:target) -> Set(receiptKey)
  const stats = {
    prepare_total: 0,
    prepare_rejected: 0,
    commit_total: 0,
    commit_rejected: 0,
    undo_total: 0,
    undo_rejected: 0,
    timeout_undo_promoted: 0,
    compensation_runs: 0,
    compensation_rejected: 0,
    compensated_total: 0,
    compensation_failures: 0,
    overflow_denied: 0,
    state_corrupt_incidents: 0,
    fail_closed: 0,
  };

  function addTargetIndex(tKey, rKey) {
    let set = targetIndex.get(tKey);
    if (!set) {
      set = new Set();
      targetIndex.set(tKey, set);
    }
    set.add(rKey);
  }

  function removeTargetIndex(tKey, rKey) {
    const set = targetIndex.get(tKey);
    if (!set) return;
    set.delete(rKey);
    if (!set.size) targetIndex.delete(tKey);
  }

  function removeReceipt(rKey, receipt) {
    const rec = receipt && typeof receipt === 'object' ? receipt : receipts.get(rKey);
    if (!rec) return;
    const tKey = targetKey(rec.connector, rec.target_id);
    receipts.delete(rKey);
    if (tKey) removeTargetIndex(tKey, rKey);
  }

  function stateCountsForReceipts(iterable) {
    const counts = initialStateCounts();
    for (const receipt of iterable) {
      const state = safeString(receipt?.delivery_state || '');
      if (state === 'prepared') counts.prepared += 1;
      else if (state === 'committed') counts.committed += 1;
      else if (state === 'undo_pending') counts.undo_pending += 1;
      else if (state === 'compensated') counts.compensated += 1;
    }
    return counts;
  }

function normalizeCompensationDueAt({
  now,
  commitDeadlineAtMs,
  compensate_after_ms,
} = {}) {
  if (compensate_after_ms != null && String(compensate_after_ms).trim() !== '') {
    const overrideDelayRaw = Math.floor(safeNum(compensate_after_ms, -1));
    if (Number.isFinite(overrideDelayRaw) && overrideDelayRaw >= 0) return now + overrideDelayRaw;
  }
  if (commitDeadlineAtMs > 0) return commitDeadlineAtMs;
  return now + defaultCommitTimeoutMs;
}

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    for (const [rKey, receipt] of receipts.entries()) {
      const rec = receipt && typeof receipt === 'object' ? receipt : {};
      const state = safeString(rec.delivery_state || 'prepared');
      const updatedAtMs = Math.max(0, Number(rec.updated_at_ms || 0));
      const lastSeenAtMs = Math.max(0, Number(rec.last_seen_at_ms || 0));
      const ref = Math.max(updatedAtMs, lastSeenAtMs);
      const ageMs = ref > 0 ? Math.max(0, ts - ref) : 0;

      if (state === 'committed' || state === 'compensated') {
        if (ageMs >= staleWindowMs) removeReceipt(rKey, rec);
        continue;
      }
      if (state === 'prepared' || state === 'undo_pending') {
        if (ageMs >= (staleWindowMs * 2)) removeReceipt(rKey, rec);
      }
    }
  }

  function ensureCapacity(now) {
    if (receipts.size < maxEntries) return true;
    prune(now);
    return receipts.size < maxEntries;
  }

  function deny(code, extra = {}, { op = '', fail_closed = false } = {}) {
    const denyCode = safeString(code) || 'receipt_guard_error';
    if (op === 'prepare') stats.prepare_rejected += 1;
    else if (op === 'commit') stats.commit_rejected += 1;
    else if (op === 'undo') stats.undo_rejected += 1;
    else if (op === 'compensate') stats.compensation_rejected += 1;
    if (denyCode === 'receipt_store_overflow') stats.overflow_denied += 1;
    if (denyCode === 'state_corrupt') stats.state_corrupt_incidents += 1;
    if (fail_closed || denyCode === 'receipt_guard_error' || denyCode === 'compensation_worker_error') {
      stats.fail_closed += 1;
    }
    return {
      ok: false,
      deny_code: denyCode,
      ...extra,
    };
  }

  function resolveReceipt({
    connector,
    target_id,
    idempotency_key,
  } = {}) {
    const c = safeString(connector).toLowerCase();
    const t = safeString(target_id);
    const idem = safeString(idempotency_key);
    const rKey = receiptKey(c, t, idem);
    if (!c || !t || !idem || !rKey) return null;
    return {
      connector: c,
      target_id: t,
      idempotency_key: idem,
      receipt_key: rKey,
      receipt: receipts.get(rKey) || null,
    };
  }

  function prepare({
    connector,
    target_id,
    idempotency_key,
    event_id,
    event_sequence,
    now_ms,
    commit_timeout_ms,
  } = {}) {
    stats.prepare_total += 1;
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const resolved = resolveReceipt({
        connector,
        target_id,
        idempotency_key,
      });
      if (!resolved) {
        return deny('invalid_request', { connector_target: '', retry_after_ms: 0 }, { op: 'prepare', fail_closed: true });
      }

      if (resolved.receipt) {
        const existing = resolved.receipt;
        const state = safeString(existing.delivery_state || '');
        existing.last_seen_at_ms = now;
        existing.updated_at_ms = now;
        receipts.set(resolved.receipt_key, existing);
        if (state === 'prepared' || state === 'committed') {
          return {
            ok: true,
            idempotent: true,
            connector_target: targetKey(resolved.connector, resolved.target_id),
            idempotency_key: resolved.idempotency_key,
            delivery_state: state,
            receipt_token: safeString(existing.receipt_token),
            commit_deadline_at_ms: Math.max(0, Number(existing.commit_deadline_at_ms || 0)),
            compensation_due_at_ms: Math.max(0, Number(existing.compensation_due_at_ms || 0)),
          };
        }
        return deny('terminal_not_allowed', {
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
          delivery_state: state,
          retry_after_ms: 0,
        }, { op: 'prepare' });
      }

      if (!ensureCapacity(now)) {
        return deny('receipt_store_overflow', {
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
          retry_after_ms: staleWindowMs,
        }, { op: 'prepare', fail_closed: true });
      }

      const commitTimeoutMs = boundedInt(commit_timeout_ms, {
        fallback: defaultCommitTimeoutMs,
        min: 1_000,
        max: 24 * 60 * 60 * 1000,
      });
      const commitDeadlineAtMs = now + commitTimeoutMs;
      const receipt = {
        connector: resolved.connector,
        target_id: resolved.target_id,
        idempotency_key: resolved.idempotency_key,
        receipt_token: receiptToken(),
        event_id: safeString(event_id),
        event_sequence: parsePositiveInt(event_sequence),
        delivery_state: 'prepared',
        provider_receipt: '',
        prepared_at_ms: now,
        commit_deadline_at_ms: commitDeadlineAtMs,
        committed_at_ms: 0,
        undo_requested_at_ms: 0,
        compensation_due_at_ms: commitDeadlineAtMs,
        compensated_at_ms: 0,
        compensation_reason: '',
        compensation_attempts: 0,
        updated_at_ms: now,
        last_seen_at_ms: now,
      };
      receipts.set(resolved.receipt_key, receipt);
      addTargetIndex(targetKey(resolved.connector, resolved.target_id), resolved.receipt_key);
      return {
        ok: true,
        idempotent: false,
        connector_target: targetKey(resolved.connector, resolved.target_id),
        idempotency_key: resolved.idempotency_key,
        delivery_state: 'prepared',
        receipt_token: safeString(receipt.receipt_token),
        commit_deadline_at_ms: commitDeadlineAtMs,
        compensation_due_at_ms: commitDeadlineAtMs,
      };
    } catch {
      return deny('receipt_guard_error', {
        connector_target: targetKey(connector, target_id),
        idempotency_key: safeString(idempotency_key),
      }, { op: 'prepare', fail_closed: true });
    }
  }

  function commit({
    connector,
    target_id,
    idempotency_key,
    provider_receipt,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    stats.commit_total += 1;
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const resolved = resolveReceipt({
        connector,
        target_id,
        idempotency_key,
      });
      if (!resolved) {
        return deny('invalid_request', { connector_target: '', retry_after_ms: 0 }, { op: 'commit', fail_closed: true });
      }
      const receipt = resolved.receipt;
      if (!receipt) {
        return deny('state_corrupt', {
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
          retry_after_ms: defaultCommitTimeoutMs,
        }, { op: 'commit', fail_closed: true });
      }
      const state = safeString(receipt.delivery_state || '');
      receipt.last_seen_at_ms = now;

      if (state === 'committed') {
        receipt.updated_at_ms = now;
        receipts.set(resolved.receipt_key, receipt);
        return {
          ok: true,
          idempotent: true,
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
          delivery_state: 'committed',
          provider_receipt: safeString(receipt.provider_receipt || provider_receipt),
          committed_at_ms: Math.max(0, Number(receipt.committed_at_ms || now)),
          compensation_due_at_ms: Math.max(0, Number(receipt.compensation_due_at_ms || 0)),
        };
      }
      if (state !== 'prepared') {
        return deny('terminal_not_allowed', {
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
          delivery_state: state,
          retry_after_ms: 0,
        }, { op: 'commit' });
      }

      const commitDeadlineAtMs = Math.max(0, Number(receipt.commit_deadline_at_ms || 0));
      if (commitDeadlineAtMs > 0 && now > commitDeadlineAtMs) {
        receipt.delivery_state = 'undo_pending';
        receipt.undo_requested_at_ms = now;
        receipt.compensation_due_at_ms = normalizeCompensationDueAt({
          now,
          commitDeadlineAtMs,
        });
        receipt.compensation_reason = safeString(receipt.compensation_reason || 'commit_timeout');
        receipt.updated_at_ms = now;
        receipts.set(resolved.receipt_key, receipt);
        stats.timeout_undo_promoted += 1;
        return deny('commit_timeout', {
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
          delivery_state: 'undo_pending',
          retry_after_ms: Math.max(0, Number(receipt.compensation_due_at_ms || now) - now),
        }, { op: 'commit' });
      }

      receipt.delivery_state = 'committed';
      receipt.provider_receipt = safeString(provider_receipt || receipt.provider_receipt);
      receipt.event_id = safeString(event_id || receipt.event_id);
      const sequence = parsePositiveInt(event_sequence);
      if (sequence > 0) receipt.event_sequence = sequence;
      receipt.committed_at_ms = now;
      receipt.updated_at_ms = now;
      receipts.set(resolved.receipt_key, receipt);
      return {
        ok: true,
        idempotent: false,
        connector_target: targetKey(resolved.connector, resolved.target_id),
        idempotency_key: resolved.idempotency_key,
        delivery_state: 'committed',
        provider_receipt: safeString(receipt.provider_receipt),
        committed_at_ms: now,
        compensation_due_at_ms: Math.max(0, Number(receipt.compensation_due_at_ms || 0)),
      };
    } catch {
      return deny('receipt_guard_error', {
        connector_target: targetKey(connector, target_id),
        idempotency_key: safeString(idempotency_key),
      }, { op: 'commit', fail_closed: true });
    }
  }

  function undo({
    connector,
    target_id,
    idempotency_key,
    reason,
    compensate_after_ms,
    now_ms,
  } = {}) {
    stats.undo_total += 1;
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const resolved = resolveReceipt({
        connector,
        target_id,
        idempotency_key,
      });
      if (!resolved) {
        return deny('invalid_request', { connector_target: '', retry_after_ms: 0 }, { op: 'undo', fail_closed: true });
      }
      const receipt = resolved.receipt;
      if (!receipt) {
        return deny('state_corrupt', {
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
        }, { op: 'undo', fail_closed: true });
      }
      const state = safeString(receipt.delivery_state || '');
      if (state === 'undo_pending' || state === 'compensated') {
        receipt.last_seen_at_ms = now;
        receipt.updated_at_ms = now;
        receipts.set(resolved.receipt_key, receipt);
        return {
          ok: true,
          idempotent: true,
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
          delivery_state: state,
          compensation_due_at_ms: Math.max(0, Number(receipt.compensation_due_at_ms || 0)),
        };
      }
      if (state !== 'prepared' && state !== 'committed') {
        return deny('terminal_not_allowed', {
          connector_target: targetKey(resolved.connector, resolved.target_id),
          idempotency_key: resolved.idempotency_key,
          delivery_state: state,
        }, { op: 'undo' });
      }

      const commitDeadlineAtMs = Math.max(0, Number(receipt.commit_deadline_at_ms || 0));
      receipt.delivery_state = 'undo_pending';
      receipt.undo_requested_at_ms = now;
      receipt.compensation_due_at_ms = normalizeCompensationDueAt({
        now,
        commitDeadlineAtMs,
        compensate_after_ms,
      });
      receipt.compensation_reason = safeString(reason || receipt.compensation_reason || 'delivery_failed');
      receipt.updated_at_ms = now;
      receipt.last_seen_at_ms = now;
      receipts.set(resolved.receipt_key, receipt);
      return {
        ok: true,
        idempotent: false,
        connector_target: targetKey(resolved.connector, resolved.target_id),
        idempotency_key: resolved.idempotency_key,
        delivery_state: 'undo_pending',
        compensation_due_at_ms: Math.max(0, Number(receipt.compensation_due_at_ms || 0)),
      };
    } catch {
      return deny('receipt_guard_error', {
        connector_target: targetKey(connector, target_id),
        idempotency_key: safeString(idempotency_key),
      }, { op: 'undo', fail_closed: true });
    }
  }

  function promoteTimeoutUndo(now) {
    let promoted = 0;
    for (const receipt of receipts.values()) {
      const state = safeString(receipt.delivery_state || '');
      if (state !== 'prepared') continue;
      const deadline = Math.max(0, Number(receipt.commit_deadline_at_ms || 0));
      if (deadline <= 0 || deadline > now) continue;
      receipt.delivery_state = 'undo_pending';
      receipt.undo_requested_at_ms = now;
      receipt.compensation_due_at_ms = Math.max(0, Number(receipt.compensation_due_at_ms || 0)) || deadline;
      receipt.compensation_reason = safeString(receipt.compensation_reason || 'commit_timeout');
      receipt.updated_at_ms = now;
      receipt.last_seen_at_ms = now;
      promoted += 1;
    }
    if (promoted > 0) stats.timeout_undo_promoted += promoted;
    return promoted;
  }

  function runCompensation({
    now_ms,
    max_jobs,
    compensate_fn,
  } = {}) {
    stats.compensation_runs += 1;
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const promoted = promoteTimeoutUndo(now);
      const limit = boundedInt(max_jobs, {
        fallback: maxCompensationBatch,
        min: 1,
        max: maxCompensationBatch,
      });
      const due = [];
      for (const receipt of receipts.values()) {
        if (safeString(receipt.delivery_state || '') !== 'undo_pending') continue;
        const dueAt = Math.max(0, Number(receipt.compensation_due_at_ms || 0));
        if (dueAt <= now) due.push(receipt);
      }
      due.sort((a, b) => {
        const aDue = Math.max(0, Number(a.compensation_due_at_ms || 0));
        const bDue = Math.max(0, Number(b.compensation_due_at_ms || 0));
        if (aDue !== bDue) return aDue - bDue;
        return Math.max(0, Number(a.updated_at_ms || 0)) - Math.max(0, Number(b.updated_at_ms || 0));
      });

      const worker = typeof compensate_fn === 'function' ? compensate_fn : compensateFn;
      const selected = due.slice(0, limit);
      let compensated = 0;
      let failed = 0;
      for (const receipt of selected) {
        let outcome = { ok: true };
        if (worker) {
          try {
            const out = worker(cloneReceipt(receipt));
            if (out && typeof out === 'object') outcome = out;
          } catch {
            outcome = { ok: false, deny_code: 'compensation_worker_error' };
          }
        }

        if (outcome?.ok === false) {
          failed += 1;
          stats.compensation_failures += 1;
          receipt.compensation_attempts = Math.max(0, Number(receipt.compensation_attempts || 0)) + 1;
          receipt.compensation_due_at_ms = now + Math.max(500, Number(outcome.retry_after_ms || compensationRetryMs));
          receipt.updated_at_ms = now;
          receipt.last_seen_at_ms = now;
          continue;
        }

        receipt.delivery_state = 'compensated';
        receipt.compensated_at_ms = now;
        receipt.compensation_attempts = Math.max(0, Number(receipt.compensation_attempts || 0)) + 1;
        if (outcome && typeof outcome === 'object' && safeString(outcome.provider_receipt)) {
          receipt.provider_receipt = safeString(outcome.provider_receipt);
        }
        receipt.updated_at_ms = now;
        receipt.last_seen_at_ms = now;
        compensated += 1;
      }
      stats.compensated_total += compensated;

      const snapshotNow = snapshot();
      return {
        ok: true,
        promoted_timeout_undo: promoted,
        scanned_due: due.length,
        processed: selected.length,
        compensated,
        failed,
        pending_compensation: Math.max(0, Number(snapshotNow.compensation_pending_count || 0)),
      };
    } catch {
      return deny('compensation_worker_error', {}, { op: 'compensate', fail_closed: true });
    }
  }

  function getReceipt({
    connector,
    target_id,
    idempotency_key,
  } = {}) {
    try {
      const resolved = resolveReceipt({
        connector,
        target_id,
        idempotency_key,
      });
      if (!resolved || !resolved.receipt) return null;
      return cloneReceipt(resolved.receipt);
    } catch {
      return null;
    }
  }

  function getTarget({
    connector,
    target_id,
    limit,
  } = {}) {
    const c = safeString(connector).toLowerCase();
    const t = safeString(target_id);
    const tKey = targetKey(c, t);
    if (!tKey) return null;
    const set = targetIndex.get(tKey);
    const receiptsForTarget = [];
    for (const rKey of set || []) {
      const receipt = receipts.get(rKey);
      if (receipt) receiptsForTarget.push(receipt);
    }
    receiptsForTarget.sort((a, b) => Math.max(0, Number(b.updated_at_ms || 0)) - Math.max(0, Number(a.updated_at_ms || 0)));
    const lim = boundedInt(limit, { fallback: 50, min: 1, max: 500 });
    const state_counts = stateCountsForReceipts(receiptsForTarget);
    let earliestCompensationDueAtMs = 0;
    for (const receipt of receiptsForTarget) {
      if (safeString(receipt.delivery_state || '') !== 'undo_pending') continue;
      const dueAt = Math.max(0, Number(receipt.compensation_due_at_ms || 0));
      if (dueAt <= 0) continue;
      if (!earliestCompensationDueAtMs || dueAt < earliestCompensationDueAtMs) {
        earliestCompensationDueAtMs = dueAt;
      }
    }
    return {
      connector: c,
      target_id: t,
      receipts: receiptsForTarget.slice(0, lim).map((x) => cloneReceipt(x)),
      receipt_count: receiptsForTarget.length,
      state_counts,
      earliest_compensation_due_at_ms: earliestCompensationDueAtMs,
    };
  }

  function snapshot() {
    const stateCounts = stateCountsForReceipts(receipts.values());
    return {
      entries: receipts.size,
      targets: targetIndex.size,
      prepare_total: Math.max(0, Number(stats.prepare_total || 0)),
      prepare_rejected: Math.max(0, Number(stats.prepare_rejected || 0)),
      commit_total: Math.max(0, Number(stats.commit_total || 0)),
      commit_rejected: Math.max(0, Number(stats.commit_rejected || 0)),
      undo_total: Math.max(0, Number(stats.undo_total || 0)),
      undo_rejected: Math.max(0, Number(stats.undo_rejected || 0)),
      timeout_undo_promoted: Math.max(0, Number(stats.timeout_undo_promoted || 0)),
      compensation_runs: Math.max(0, Number(stats.compensation_runs || 0)),
      compensation_rejected: Math.max(0, Number(stats.compensation_rejected || 0)),
      compensated_total: Math.max(0, Number(stats.compensated_total || 0)),
      compensation_failures: Math.max(0, Number(stats.compensation_failures || 0)),
      overflow_denied: Math.max(0, Number(stats.overflow_denied || 0)),
      state_corrupt_incidents: Math.max(0, Number(stats.state_corrupt_incidents || 0)),
      fail_closed: Math.max(0, Number(stats.fail_closed || 0)),
      compensation_pending_count: Math.max(0, Number(stateCounts.undo_pending || 0)),
      by_state: stateCounts,
      stale_window_ms: staleWindowMs,
      max_entries: maxEntries,
      default_commit_timeout_ms: defaultCommitTimeoutMs,
      max_compensation_batch: maxCompensationBatch,
      compensation_retry_ms: compensationRetryMs,
    };
  }

  return {
    prepare,
    commit,
    undo,
    runCompensation,
    getReceipt,
    getTarget,
    snapshot,
    prune,
  };
}
