import {
  createConnectorDeliveryReceiptCompensator,
} from './connector_delivery_receipt_compensator.js';
import {
  createConnectorTargetOrderingGuard,
} from './connector_target_ordering_guard.js';
import { nowMs } from './util.js';
import {
  createPreauthSurfaceGuard,
  createUnauthorizedFloodBreaker,
  createWebhookReplayGuard,
} from './pairing_http.js';

export const CHANNEL_INGRESS_PRIMITIVE_EXPORTS = Object.freeze([
  'createPreauthSurfaceGuard',
  'createUnauthorizedFloodBreaker',
  'createWebhookReplayGuard',
  'createConnectorTargetOrderingGuard',
  'createConnectorDeliveryReceiptCompensator',
]);

function safeString(input) {
  return String(input ?? '').trim();
}

function boundedInt(raw, { fallback, min, max }) {
  const n = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

export function listChannelIngressPrimitiveExports() {
  return CHANNEL_INGRESS_PRIMITIVE_EXPORTS;
}

export function createChannelIngressPrimitiveSet({
  env = process.env,
  db = null,
  now_fn = nowMs,
} = {}) {
  const sourceEnv = env && typeof env === 'object' ? env : {};
  return {
    preauth_guard: createPreauthSurfaceGuard({
      nowFn: now_fn,
      window_ms: boundedInt(sourceEnv.HUB_PREAUTH_WINDOW_MS, { fallback: 60_000, min: 1_000, max: 10 * 60_000 }),
      max_per_window: boundedInt(sourceEnv.HUB_PAIRING_RL_PER_MIN, { fallback: 12, min: 1, max: 1_000 }),
      max_state_keys: boundedInt(sourceEnv.HUB_PREAUTH_MAX_STATE_KEYS, { fallback: 2_048, min: 16, max: 100_000 }),
      stale_window_ms: boundedInt(sourceEnv.HUB_PREAUTH_STALE_WINDOW_MS, { fallback: 180_000, min: 60_000, max: 24 * 60 * 60 * 1000 }),
    }),
    unauthorized_flood_breaker: createUnauthorizedFloodBreaker({
      nowFn: now_fn,
      window_ms: boundedInt(sourceEnv.HUB_UNAUTHORIZED_FLOOD_WINDOW_MS, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 }),
      max_unauthorized_per_window: boundedInt(sourceEnv.HUB_UNAUTHORIZED_FLOOD_MAX_PER_WINDOW, { fallback: 8, min: 1, max: 10_000 }),
      penalty_ms: boundedInt(sourceEnv.HUB_UNAUTHORIZED_FLOOD_PENALTY_MS, { fallback: 15_000, min: 1_000, max: 10 * 60 * 1000 }),
      max_state_keys: boundedInt(sourceEnv.HUB_UNAUTHORIZED_FLOOD_MAX_STATE_KEYS, { fallback: 4_096, min: 16, max: 100_000 }),
      stale_window_ms: boundedInt(sourceEnv.HUB_UNAUTHORIZED_FLOOD_STALE_WINDOW_MS, { fallback: 300_000, min: 30_000, max: 24 * 60 * 60 * 1000 }),
      audit_sample_every: boundedInt(sourceEnv.HUB_UNAUTHORIZED_FLOOD_AUDIT_SAMPLE_EVERY, { fallback: 5, min: 1, max: 10_000 }),
    }),
    webhook_replay_guard: createWebhookReplayGuard({
      nowFn: now_fn,
      db,
      ttl_ms: boundedInt(sourceEnv.HUB_WEBHOOK_REPLAY_TTL_MS, { fallback: 10 * 60 * 1000, min: 1_000, max: 7 * 24 * 60 * 60 * 1000 }),
      max_keys: boundedInt(sourceEnv.HUB_WEBHOOK_REPLAY_MAX_KEYS, { fallback: 20_000, min: 64, max: 1_000_000 }),
      stale_window_ms: boundedInt(sourceEnv.HUB_WEBHOOK_REPLAY_STALE_WINDOW_MS, { fallback: 20 * 60 * 1000, min: 10 * 60 * 1000, max: 14 * 24 * 60 * 60 * 1000 }),
    }),
    target_ordering_guard: createConnectorTargetOrderingGuard({
      nowFn: now_fn,
      lock_ttl_ms: boundedInt(sourceEnv.HUB_CONNECTOR_TARGET_LOCK_TTL_MS, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 }),
      seen_ttl_ms: boundedInt(sourceEnv.HUB_CONNECTOR_ORDERING_SEEN_TTL_MS, { fallback: 10 * 60 * 1000, min: 10_000, max: 24 * 60 * 60 * 1000 }),
      stale_window_ms: boundedInt(sourceEnv.HUB_CONNECTOR_ORDERING_STALE_WINDOW_MS, { fallback: 15 * 60 * 1000, min: 60 * 1000, max: 7 * 24 * 60 * 60 * 1000 }),
      max_targets: boundedInt(sourceEnv.HUB_CONNECTOR_ORDERING_MAX_TARGETS, { fallback: 2_048, min: 16, max: 100_000 }),
      max_seen_per_target: boundedInt(sourceEnv.HUB_CONNECTOR_ORDERING_MAX_SEEN_PER_TARGET, { fallback: 2_048, min: 16, max: 100_000 }),
    }),
    delivery_receipt_compensator: createConnectorDeliveryReceiptCompensator({
      nowFn: now_fn,
      stale_window_ms: boundedInt(sourceEnv.HUB_CONNECTOR_RECEIPT_STALE_WINDOW_MS, { fallback: 6 * 60 * 60 * 1000, min: 60 * 1000, max: 14 * 24 * 60 * 60 * 1000 }),
      max_entries: boundedInt(sourceEnv.HUB_CONNECTOR_RECEIPT_MAX_ENTRIES, { fallback: 10_000, min: 64, max: 1_000_000 }),
      default_commit_timeout_ms: boundedInt(sourceEnv.HUB_CONNECTOR_RECEIPT_COMMIT_TIMEOUT_MS, { fallback: 30_000, min: 1_000, max: 24 * 60 * 60 * 1000 }),
      max_compensation_batch: boundedInt(sourceEnv.HUB_CONNECTOR_RECEIPT_COMPENSATION_MAX_JOBS, { fallback: 128, min: 1, max: 10_000 }),
      compensation_retry_ms: boundedInt(sourceEnv.HUB_CONNECTOR_RECEIPT_COMPENSATION_RETRY_MS, { fallback: 5_000, min: 500, max: 10 * 60 * 1000 }),
    }),
  };
}

export function describeChannelIngressPrimitiveSet(set = {}) {
  return {
    preauth_guard: typeof set.preauth_guard?.check === 'function',
    unauthorized_flood_breaker: typeof set.unauthorized_flood_breaker?.recordUnauthorized === 'function',
    webhook_replay_guard: typeof set.webhook_replay_guard?.claim === 'function',
    target_ordering_guard: typeof set.target_ordering_guard?.begin === 'function',
    delivery_receipt_compensator: typeof set.delivery_receipt_compensator?.prepare === 'function',
  };
}

export {
  createPreauthSurfaceGuard,
  createUnauthorizedFloodBreaker,
  createWebhookReplayGuard,
  createConnectorTargetOrderingGuard,
  createConnectorDeliveryReceiptCompensator,
};

export function describeChannelIngressPrimitiveError(input) {
  return safeString(input);
}
