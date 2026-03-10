import { nowMs } from './util.js';

function safeString(v) {
  return String(v ?? '').trim();
}

function boundedInt(raw, { fallback, min, max }) {
  const n = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function safeNum(raw, fallback = 0) {
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
}

function percentile(values, p, fallback = 0) {
  const arr = Array.isArray(values)
    ? values.map((x) => safeNum(x, 0)).filter((x) => x >= 0).sort((a, b) => a - b)
    : [];
  if (!arr.length) return fallback;
  const idx = Math.max(0, Math.min(arr.length - 1, Math.ceil((arr.length * p) - 1)));
  return arr[idx];
}

const CONNECTOR_RUNTIME_STATES = new Set([
  'idle',
  'connecting',
  'ready',
  'degraded_polling',
  'recovering',
]);

function normalizeState(v, fallback = 'idle') {
  const s = safeString(v).toLowerCase();
  return CONNECTOR_RUNTIME_STATES.has(s) ? s : fallback;
}

function targetKey(connector, targetId) {
  const c = safeString(connector).toLowerCase();
  const t = safeString(targetId);
  if (!c || !t) return '';
  return `${c}:${t}`;
}

function makeInitialRuntime(now = 0) {
  const ts = Math.max(0, Number(now || 0));
  return {
    state: 'idle',
    updated_at_ms: ts,
    last_seen_ms: ts,
    connecting_since_ms: 0,
    degraded_since_ms: 0,
    recovering_since_ms: 0,
    consecutive_ws_failures: 0,
    next_reconnect_at_ms: 0,
    last_error_code: '',
  };
}

function countByState(runtimes) {
  const out = {
    idle: 0,
    connecting: 0,
    ready: 0,
    degraded_polling: 0,
    recovering: 0,
  };
  for (const runtime of runtimes.values()) {
    const state = normalizeState(runtime?.state, 'idle');
    out[state] += 1;
  }
  return out;
}

export function createConnectorReconnectOrchestrator(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const runtimes = new Map(); // key(connector:target) -> runtime state

  const staleWindowMs = boundedInt(opts.stale_window_ms, { fallback: 15 * 60 * 1000, min: 60 * 1000, max: 7 * 24 * 60 * 60 * 1000 });
  const maxTargets = boundedInt(opts.max_targets, { fallback: 2_048, min: 16, max: 100_000 });
  const reconnectBackoffBaseMs = boundedInt(opts.reconnect_backoff_base_ms, { fallback: 1_000, min: 100, max: 60_000 });
  const reconnectBackoffMaxMs = boundedInt(opts.reconnect_backoff_max_ms, { fallback: 30_000, min: reconnectBackoffBaseMs, max: 10 * 60_000 });
  const reconnectSamplesMax = boundedInt(opts.reconnect_samples_max, { fallback: 2_048, min: 32, max: 100_000 });

  const reconnectSamples = [];
  const stats = {
    signals: 0,
    denied: 0,
    fail_closed: 0,
    state_corrupt_incidents: 0,
    fallback_entries: 0,
    reconnect_attempts: 0,
  };

  function pushReconnectSample(ms) {
    const value = Math.max(0, Math.round(safeNum(ms, 0)));
    if (!Number.isFinite(value) || value <= 0) return;
    reconnectSamples.push(value);
    if (reconnectSamples.length > reconnectSamplesMax) {
      reconnectSamples.splice(0, reconnectSamples.length - reconnectSamplesMax);
    }
  }

  function computeBackoffMs(failures) {
    const f = Math.max(1, Math.floor(safeNum(failures, 1)));
    const exp = Math.min(16, Math.max(0, f - 1));
    const delay = reconnectBackoffBaseMs * (2 ** exp);
    return Math.max(reconnectBackoffBaseMs, Math.min(reconnectBackoffMaxMs, Math.round(delay)));
  }

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    for (const [key, runtime] of runtimes.entries()) {
      const lastSeenMs = Math.max(0, Number(runtime?.last_seen_ms || 0));
      const updatedAtMs = Math.max(0, Number(runtime?.updated_at_ms || 0));
      const ref = Math.max(lastSeenMs, updatedAtMs);
      if (ref > 0 && (ts - ref) >= staleWindowMs) {
        runtimes.delete(key);
      }
    }
  }

  function ensureTargetCapacity(now) {
    if (runtimes.size < maxTargets) return true;
    prune(now);
    if (runtimes.size < maxTargets) return true;
    return false;
  }

  function ensureRuntime(key, now) {
    const ts = Math.max(0, Number(now || 0));
    let runtime = runtimes.get(key);
    if (!runtime) {
      if (!ensureTargetCapacity(ts)) return null;
      runtime = makeInitialRuntime(ts);
      runtimes.set(key, runtime);
    }
    return runtime;
  }

  function deny({ key, deny_code, state, retry_after_ms = 0, fail_closed = false }) {
    stats.denied += 1;
    if (fail_closed) stats.fail_closed += 1;
    if (deny_code === 'state_corrupt') stats.state_corrupt_incidents += 1;
    return {
      ok: false,
      deny_code: safeString(deny_code) || 'state_corrupt',
      connector_target: safeString(key),
      state: normalizeState(state, 'idle'),
      retry_after_ms: Math.max(0, Number(retry_after_ms || 0)),
      action: 'none',
    };
  }

  function snapshot() {
    const byState = countByState(runtimes);
    return {
      targets: runtimes.size,
      signals: Math.max(0, Number(stats.signals || 0)),
      denied: Math.max(0, Number(stats.denied || 0)),
      fail_closed: Math.max(0, Number(stats.fail_closed || 0)),
      state_corrupt_incidents: Math.max(0, Number(stats.state_corrupt_incidents || 0)),
      fallback_entries: Math.max(0, Number(stats.fallback_entries || 0)),
      reconnect_attempts: Math.max(0, Number(stats.reconnect_attempts || 0)),
      connector_reconnect_ms_p95: Math.max(0, percentile(reconnectSamples, 0.95, 0)),
      reconnect_sample_count: reconnectSamples.length,
      by_state: byState,
      stale_window_ms: staleWindowMs,
      max_targets: maxTargets,
      reconnect_backoff_base_ms: reconnectBackoffBaseMs,
      reconnect_backoff_max_ms: reconnectBackoffMaxMs,
    };
  }

  function getTarget({ connector, target_id } = {}) {
    const key = targetKey(connector, target_id);
    if (!key) return null;
    const runtime = runtimes.get(key);
    if (!runtime) return null;
    return {
      connector: safeString(connector).toLowerCase(),
      target_id: safeString(target_id),
      ...runtime,
    };
  }

  function applySignal({
    connector,
    target_id,
    signal,
    error_code,
    now_ms,
  } = {}) {
    stats.signals += 1;
    const sig = safeString(signal).toLowerCase();
    const key = targetKey(connector, target_id);
    if (!key) {
      return deny({
        key,
        deny_code: 'invalid_request',
        state: 'idle',
        fail_closed: true,
      });
    }
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const runtime = ensureRuntime(key, now);
      if (!runtime) {
        return deny({
          key,
          deny_code: 'runtime_state_overflow',
          state: 'idle',
          fail_closed: true,
        });
      }
      runtime.last_seen_ms = now;
      const current = normalizeState(runtime.state, 'idle');
      let action = 'none';
      let reconnectDelayMs = Math.max(0, Number(runtime.next_reconnect_at_ms || 0) - now);

      if (sig === 'boot') {
        runtime.state = current;
      } else if (sig === 'ws_connecting') {
        if (current !== 'idle' && current !== 'degraded_polling' && current !== 'recovering') {
          return deny({ key, deny_code: 'state_corrupt', state: current });
        }
        runtime.state = 'connecting';
        runtime.connecting_since_ms = now;
        runtime.recovering_since_ms = current === 'recovering' ? runtime.recovering_since_ms : 0;
      } else if (sig === 'ws_ready') {
        if (current !== 'connecting' && current !== 'recovering' && current !== 'degraded_polling') {
          return deny({ key, deny_code: 'state_corrupt', state: current });
        }
        const reconnectStart = Math.max(
          0,
          Number(runtime.connecting_since_ms || 0),
          Number(runtime.recovering_since_ms || 0)
        );
        if (reconnectStart > 0 && now > reconnectStart) {
          pushReconnectSample(now - reconnectStart);
        }
        runtime.state = 'ready';
        runtime.connecting_since_ms = 0;
        runtime.recovering_since_ms = 0;
        runtime.degraded_since_ms = 0;
        runtime.consecutive_ws_failures = 0;
        runtime.next_reconnect_at_ms = 0;
        runtime.last_error_code = '';
      } else if (sig === 'ws_failed' || sig === 'force_degraded') {
        if (sig === 'ws_failed' && current !== 'connecting' && current !== 'ready' && current !== 'recovering') {
          return deny({ key, deny_code: 'state_corrupt', state: current });
        }
        const nextFailures = Math.max(1, Number(runtime.consecutive_ws_failures || 0) + 1);
        const delay = computeBackoffMs(nextFailures);
        const enteringFrom = current;
        runtime.state = 'degraded_polling';
        runtime.connecting_since_ms = 0;
        runtime.recovering_since_ms = 0;
        if (!Number(runtime.degraded_since_ms || 0)) runtime.degraded_since_ms = now;
        runtime.consecutive_ws_failures = nextFailures;
        runtime.next_reconnect_at_ms = now + delay;
        runtime.last_error_code = safeString(error_code || '');
        reconnectDelayMs = delay;
        if (enteringFrom !== 'degraded_polling') stats.fallback_entries += 1;
      } else if (sig === 'reconnect_tick') {
        if (current !== 'degraded_polling') {
          reconnectDelayMs = Math.max(0, Number(runtime.next_reconnect_at_ms || 0) - now);
        } else {
          const dueAt = Math.max(0, Number(runtime.next_reconnect_at_ms || 0));
          if (dueAt <= now) {
            runtime.state = 'recovering';
            runtime.recovering_since_ms = now;
            runtime.connecting_since_ms = now;
            action = 'attempt_ws_reconnect';
            stats.reconnect_attempts += 1;
            reconnectDelayMs = 0;
          } else {
            reconnectDelayMs = Math.max(0, dueAt - now);
          }
        }
      } else if (sig === 'polling_ok') {
        if (current === 'degraded_polling' || current === 'recovering') {
          runtime.state = 'degraded_polling';
        }
      } else if (sig === 'shutdown') {
        runtime.state = 'idle';
        runtime.connecting_since_ms = 0;
        runtime.degraded_since_ms = 0;
        runtime.recovering_since_ms = 0;
        runtime.consecutive_ws_failures = 0;
        runtime.next_reconnect_at_ms = 0;
        runtime.last_error_code = '';
      } else {
        return deny({
          key,
          deny_code: 'state_corrupt',
          state: current,
        });
      }

      runtime.updated_at_ms = now;
      runtime.state = normalizeState(runtime.state, current);
      runtimes.set(key, runtime);
      return {
        ok: true,
        connector_target: key,
        state: runtime.state,
        action,
        retry_after_ms: Math.max(0, reconnectDelayMs),
        next_reconnect_at_ms: Math.max(0, Number(runtime.next_reconnect_at_ms || 0)),
      };
    } catch {
      const curState = runtimes.get(key)?.state || 'idle';
      return deny({
        key,
        deny_code: 'orchestrator_fail_closed',
        state: curState,
        retry_after_ms: reconnectBackoffBaseMs,
        fail_closed: true,
      });
    }
  }

  return {
    applySignal,
    getTarget,
    prune,
    snapshot,
  };
}
