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

function targetKey(connector, targetId) {
  const c = safeString(connector).toLowerCase();
  const t = safeString(targetId);
  if (!c || !t) return '';
  return `${c}:${t}`;
}

function parseEventSequence(v) {
  const n = Number.parseInt(String(v ?? ''), 10);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n;
}

function lockToken() {
  return crypto.randomBytes(16).toString('hex');
}

function makeTargetState(now = 0) {
  const ts = Math.max(0, Number(now || 0));
  return {
    last_sequence: 0,
    in_flight_token: '',
    in_flight_event_id: '',
    in_flight_sequence: 0,
    in_flight_acquired_at_ms: 0,
    seen_event_ids: new Map(), // event_id -> expire_at_ms
    updated_at_ms: ts,
    last_seen_ms: ts,
  };
}

export function createConnectorTargetOrderingGuard(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const states = new Map(); // key(connector:target) -> target state

  const lockTtlMs = boundedInt(opts.lock_ttl_ms, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 });
  const seenTtlMs = boundedInt(opts.seen_ttl_ms, { fallback: 10 * 60 * 1000, min: 10_000, max: 24 * 60 * 60 * 1000 });
  const staleWindowMs = boundedInt(opts.stale_window_ms, { fallback: 15 * 60 * 1000, min: 60 * 1000, max: 7 * 24 * 60 * 60 * 1000 });
  const maxTargets = boundedInt(opts.max_targets, { fallback: 2_048, min: 16, max: 100_000 });
  const maxSeenPerTarget = boundedInt(opts.max_seen_per_target, { fallback: 2_048, min: 16, max: 100_000 });

  const stats = {
    begin_total: 0,
    begin_rejected: 0,
    complete_total: 0,
    complete_rejected: 0,
    accepted: 0,
    lock_conflicts: 0,
    out_of_order_rejects: 0,
    duplicate_rejects: 0,
    state_corrupt_incidents: 0,
    fail_closed: 0,
  };

  function deny(code, extra = {}) {
    const denyCode = safeString(code) || 'ordering_guard_error';
    if (denyCode === 'target_locked') stats.lock_conflicts += 1;
    if (denyCode === 'out_of_order_event') stats.out_of_order_rejects += 1;
    if (denyCode === 'duplicate_event') stats.duplicate_rejects += 1;
    if (denyCode === 'state_corrupt') stats.state_corrupt_incidents += 1;
    if (denyCode === 'ordering_guard_error') stats.fail_closed += 1;
    return {
      ok: false,
      deny_code: denyCode,
      ...extra,
    };
  }

  function evictSeenEventOverflow(target) {
    while (target.seen_event_ids.size > maxSeenPerTarget) {
      const first = target.seen_event_ids.keys().next();
      if (first.done) break;
      target.seen_event_ids.delete(first.value);
    }
  }

  function pruneSeenEvents(target, now) {
    const ts = Math.max(0, Number(now || 0));
    for (const [eventId, expireAtMs] of target.seen_event_ids.entries()) {
      if (Math.max(0, Number(expireAtMs || 0)) <= ts) target.seen_event_ids.delete(eventId);
    }
    evictSeenEventOverflow(target);
  }

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    for (const [key, target] of states.entries()) {
      const lockExpireAtMs = Math.max(0, Number(target.in_flight_acquired_at_ms || 0)) + lockTtlMs;
      if (target.in_flight_token && lockExpireAtMs > 0 && lockExpireAtMs <= ts) {
        target.in_flight_token = '';
        target.in_flight_event_id = '';
        target.in_flight_sequence = 0;
        target.in_flight_acquired_at_ms = 0;
      }

      pruneSeenEvents(target, ts);
      const lastSeenMs = Math.max(0, Number(target.last_seen_ms || 0));
      const updatedAtMs = Math.max(0, Number(target.updated_at_ms || 0));
      const ref = Math.max(lastSeenMs, updatedAtMs);
      const hasLock = !!safeString(target.in_flight_token);
      if (!hasLock && ref > 0 && (ts - ref) >= staleWindowMs) {
        states.delete(key);
      } else states.set(key, target);
    }
  }

  function ensureCapacity(now) {
    if (states.size < maxTargets) return true;
    prune(now);
    return states.size < maxTargets;
  }

  function ensureTarget(key, now) {
    let target = states.get(key);
    if (!target) {
      if (!ensureCapacity(now)) return null;
      target = makeTargetState(now);
      states.set(key, target);
    }
    return target;
  }

  function begin({
    connector,
    target_id,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    stats.begin_total += 1;
    const key = targetKey(connector, target_id);
    const eventId = safeString(event_id);
    const sequence = parseEventSequence(event_sequence);
    if (!key) {
      stats.begin_rejected += 1;
      return deny('invalid_request', {
        connector_target: '',
        retry_after_ms: 0,
      });
    }

    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const target = ensureTarget(key, now);
      if (!target) {
        stats.begin_rejected += 1;
        return deny('runtime_state_overflow', {
          connector_target: key,
          retry_after_ms: staleWindowMs,
        });
      }

      target.last_seen_ms = now;
      pruneSeenEvents(target, now);

      const activeToken = safeString(target.in_flight_token);
      if (activeToken) {
        const lockAgeMs = Math.max(0, now - Math.max(0, Number(target.in_flight_acquired_at_ms || 0)));
        if (lockAgeMs < lockTtlMs) {
          stats.begin_rejected += 1;
          states.set(key, target);
          return deny('target_locked', {
            connector_target: key,
            retry_after_ms: Math.max(0, lockTtlMs - lockAgeMs),
          });
        }
        target.in_flight_token = '';
        target.in_flight_event_id = '';
        target.in_flight_sequence = 0;
        target.in_flight_acquired_at_ms = 0;
      }

      if (eventId && target.seen_event_ids.has(eventId)) {
        stats.begin_rejected += 1;
        states.set(key, target);
        return deny('duplicate_event', {
          connector_target: key,
          retry_after_ms: Math.max(1_000, Math.floor(seenTtlMs / 2)),
        });
      }

      const lastSequence = Math.max(0, Number(target.last_sequence || 0));
      if (sequence > 0 && lastSequence > 0 && sequence <= lastSequence) {
        stats.begin_rejected += 1;
        states.set(key, target);
        return deny('out_of_order_event', {
          connector_target: key,
          retry_after_ms: 0,
          last_sequence: lastSequence,
          event_sequence: sequence,
        });
      }

      const token = lockToken();
      target.in_flight_token = token;
      target.in_flight_event_id = eventId;
      target.in_flight_sequence = sequence;
      target.in_flight_acquired_at_ms = now;
      target.updated_at_ms = now;
      states.set(key, target);
      return {
        ok: true,
        connector_target: key,
        lock_token: token,
        last_sequence: lastSequence,
        event_sequence: sequence,
      };
    } catch {
      stats.begin_rejected += 1;
      return deny('ordering_guard_error', {
        connector_target: key,
        retry_after_ms: lockTtlMs,
      });
    }
  }

  function complete({
    connector,
    target_id,
    lock_token,
    success = false,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    stats.complete_total += 1;
    const key = targetKey(connector, target_id);
    const token = safeString(lock_token);
    const eventId = safeString(event_id);
    const sequence = parseEventSequence(event_sequence);
    if (!key || !token) {
      stats.complete_rejected += 1;
      return deny('invalid_request', { connector_target: key });
    }

    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const target = states.get(key);
      if (!target) {
        stats.complete_rejected += 1;
        return deny('state_corrupt', { connector_target: key });
      }

      if (safeString(target.in_flight_token) !== token) {
        stats.complete_rejected += 1;
        return deny('state_corrupt', { connector_target: key });
      }

      if (success) {
        if (eventId) {
          target.seen_event_ids.set(eventId, now + seenTtlMs);
          evictSeenEventOverflow(target);
        }
        const lastSequence = Math.max(0, Number(target.last_sequence || 0));
        if (sequence > lastSequence) target.last_sequence = sequence;
        stats.accepted += 1;
      }

      target.in_flight_token = '';
      target.in_flight_event_id = '';
      target.in_flight_sequence = 0;
      target.in_flight_acquired_at_ms = 0;
      target.last_seen_ms = now;
      target.updated_at_ms = now;
      states.set(key, target);
      return {
        ok: true,
        connector_target: key,
        last_sequence: Math.max(0, Number(target.last_sequence || 0)),
        seen_event_count: target.seen_event_ids.size,
      };
    } catch {
      stats.complete_rejected += 1;
      return deny('ordering_guard_error', { connector_target: key });
    }
  }

  function getTarget({ connector, target_id } = {}) {
    const key = targetKey(connector, target_id);
    if (!key) return null;
    const target = states.get(key);
    if (!target) return null;
    return {
      connector: safeString(connector).toLowerCase(),
      target_id: safeString(target_id),
      last_sequence: Math.max(0, Number(target.last_sequence || 0)),
      in_flight: !!safeString(target.in_flight_token),
      in_flight_event_id: safeString(target.in_flight_event_id),
      in_flight_sequence: Math.max(0, Number(target.in_flight_sequence || 0)),
      in_flight_acquired_at_ms: Math.max(0, Number(target.in_flight_acquired_at_ms || 0)),
      seen_event_count: target.seen_event_ids.size,
      updated_at_ms: Math.max(0, Number(target.updated_at_ms || 0)),
      last_seen_ms: Math.max(0, Number(target.last_seen_ms || 0)),
    };
  }

  function snapshot() {
    let inFlightTargets = 0;
    for (const target of states.values()) {
      if (safeString(target.in_flight_token)) inFlightTargets += 1;
    }
    return {
      targets: states.size,
      in_flight_targets: inFlightTargets,
      begin_total: Math.max(0, Number(stats.begin_total || 0)),
      begin_rejected: Math.max(0, Number(stats.begin_rejected || 0)),
      complete_total: Math.max(0, Number(stats.complete_total || 0)),
      complete_rejected: Math.max(0, Number(stats.complete_rejected || 0)),
      accepted: Math.max(0, Number(stats.accepted || 0)),
      lock_conflict_count: Math.max(0, Number(stats.lock_conflicts || 0)),
      out_of_order_reject_count: Math.max(0, Number(stats.out_of_order_rejects || 0)),
      duplicate_reject_count: Math.max(0, Number(stats.duplicate_rejects || 0)),
      state_corrupt_incidents: Math.max(0, Number(stats.state_corrupt_incidents || 0)),
      fail_closed: Math.max(0, Number(stats.fail_closed || 0)),
      stale_window_ms: staleWindowMs,
      lock_ttl_ms: lockTtlMs,
      seen_ttl_ms: seenTtlMs,
      max_targets: maxTargets,
      max_seen_per_target: maxSeenPerTarget,
    };
  }

  return {
    begin,
    complete,
    getTarget,
    prune,
    snapshot,
  };
}
