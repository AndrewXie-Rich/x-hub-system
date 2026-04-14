import {
  getChannelProviderMeta,
  listChannelProviders,
  normalizeChannelProviderId,
} from './channel_registry.js';
import {
  isChannelRuntimeDegradedState,
  isChannelRuntimeReadyState,
  normalizeChannelRuntimeState,
} from './channel_types.js';
import { buildOperatorChannelRuntimeRepairHints } from './channel_operator_repair_hints.js';
import { nowMs } from './util.js';

export const CHANNEL_RUNTIME_STATUS_SNAPSHOT_SCHEMA = 'xhub.channel_runtime_status_snapshot.v1';

const STATE_PRIORITY = Object.freeze({
  planned: 0,
  disabled: 1,
  not_configured: 2,
  configuring: 3,
  ingress_ready: 4,
  ready: 5,
  degraded: 6,
  error: 7,
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

function maxInt(...values) {
  let out = 0;
  for (const value of values) {
    out = Math.max(out, safeInt(value, 0));
  }
  return out;
}

function defaultStateForMeta(meta) {
  return meta?.release_stage === 'wave1' ? 'not_configured' : 'planned';
}

function statePriority(state) {
  return STATE_PRIORITY[state] ?? -1;
}

function chooseState(current, next) {
  if (!current) return next;
  return statePriority(next) >= statePriority(current) ? next : current;
}

function normalizeRuntimeRow(row, options = {}) {
  const src = row && typeof row === 'object' ? row : {};
  const now = safeInt(options.now_ms, nowMs());
  const provider_raw = safeString(src.provider || src.channel || src.provider_id);
  const provider = normalizeChannelProviderId(provider_raw) || '';
  const provider_known = !!provider;
  const runtime_state = normalizeChannelRuntimeState(
    src.runtime_state || src.state,
    { fallback: provider_known ? 'not_configured' : 'error' }
  );
  const account_id = safeString(src.account_id || src.accountId);
  const updated_at_ms = safeInt(src.updated_at_ms || src.updatedAtMs || src.last_seen_at_ms || src.lastSeenAtMs);
  const active_binding_count = safeInt(
    src.active_binding_count || src.active_bindings || src.binding_count || src.bindings_total
  );
  const enabled = safeBool(src.enabled, true);
  const configured = safeBool(
    src.configured,
    runtime_state !== 'planned' && runtime_state !== 'not_configured'
  );
  const explicitDeliveryReady = Object.prototype.hasOwnProperty.call(src, 'delivery_ready')
    ? safeBool(src.delivery_ready, false)
    : safeBool(src.deliverable, false);
  const explicitCommandReady = Object.prototype.hasOwnProperty.call(src, 'command_entry_ready')
    ? safeBool(src.command_entry_ready, false)
    : false;
  const delivery_queue_depth = safeInt(src.delivery_queue_depth || src.delivery_queue || src.outbox_pending_count);
  const delivery_failed_count = safeInt(src.delivery_failed_count || src.delivery_failures || src.outbox_failed_count);
  const delivery_dead_letter_count = safeInt(src.delivery_dead_letter_count || src.dead_letter_count || src.outbox_dead_letter_count);
  const manual_retry_available = safeBool(src.manual_retry_available, false);
  const last_delivery_success_at_ms = safeInt(src.last_delivery_success_at_ms || src.last_success_at_ms);
  const last_delivery_failure_at_ms = safeInt(src.last_delivery_failure_at_ms || src.last_failure_at_ms);
  const provider_backoff_until_ms = safeInt(src.provider_backoff_until_ms || src.delivery_backoff_until_ms);
  const cooldown_until_ms = safeInt(src.cooldown_until_ms || src.delivery_cooldown_until_ms);
  const last_delivery_error_code = safeString(src.last_delivery_error_code || src.delivery_error_code);
  const delivery_circuit_open = safeBool(src.delivery_circuit_open, false)
    || delivery_dead_letter_count > 0
    || manual_retry_available
    || (
      provider_backoff_until_ms > now
      && (delivery_failed_count > 0 || delivery_queue_depth > 0)
    );
  const effective_runtime_state = delivery_circuit_open && !isChannelRuntimeDegradedState(runtime_state)
    ? 'degraded'
    : runtime_state;
  const effective_delivery_ready = !delivery_circuit_open && explicitDeliveryReady;
  const effective_last_error_code = safeString(src.last_error_code || src.error_code || src.lastErrorCode)
    || (delivery_circuit_open ? last_delivery_error_code : '');
  return {
    provider_raw,
    provider,
    provider_known,
    account_id,
    runtime_state: effective_runtime_state,
    updated_at_ms,
    active_binding_count,
    enabled,
    configured,
    delivery_ready: effective_delivery_ready,
    command_entry_ready: explicitCommandReady,
    last_error_code: effective_last_error_code,
    delivery_queue_depth,
    delivery_failed_count,
    delivery_dead_letter_count,
    manual_retry_available,
    last_delivery_success_at_ms,
    last_delivery_failure_at_ms,
    provider_backoff_until_ms,
    cooldown_until_ms,
    last_delivery_error_code,
    delivery_circuit_open,
  };
}

function makeProviderAggregate(meta) {
  const defaultState = defaultStateForMeta(meta);
  return {
    provider: meta.id,
    label: meta.label,
    detail_label: meta.detail_label,
    release_stage: meta.release_stage,
    automation_path: meta.automation_path,
    threading_mode: meta.threading_mode,
    approval_surface: meta.approval_surface,
    capabilities: [...meta.capabilities],
    endpoint_visibility: meta.endpoint_visibility,
    operator_surface: meta.operator_surface,
    allow_direct_xt: meta.allow_direct_xt === true,
    require_real_evidence: meta.require_real_evidence === true,
    release_blocked: meta.release_stage !== 'wave1' || meta.require_real_evidence === true,
    runtime_state: defaultState,
    account_count: 0,
    configured_accounts: 0,
    ready_accounts: 0,
    degraded_accounts: 0,
    active_binding_count: 0,
    delivery_ready: false,
    command_entry_ready: false,
    last_error_code: '',
    delivery_queue_depth: 0,
    delivery_failed_count: 0,
    delivery_dead_letter_count: 0,
    manual_retry_available: false,
    last_delivery_success_at_ms: 0,
    last_delivery_failure_at_ms: 0,
    provider_backoff_until_ms: 0,
    cooldown_until_ms: 0,
    updated_at_ms: 0,
    repair_hints: [],
  };
}

export function buildChannelRuntimeStatusSnapshot(rows = [], options = {}) {
  const now = safeInt(options.now_ms, nowMs()) || nowMs();
  const normalizedRows = Array.isArray(rows)
    ? rows.map((row) => normalizeRuntimeRow(row, { now_ms: now }))
    : [];
  const providers = listChannelProviders().map((meta) => makeProviderAggregate(meta));
  const byProvider = new Map(providers.map((row) => [row.provider, row]));
  const unknown_provider_rows = [];

  for (const row of normalizedRows) {
    if (!row.provider_known) {
      unknown_provider_rows.push({
        provider_raw: row.provider_raw,
        account_id: row.account_id,
        runtime_state: row.runtime_state,
        updated_at_ms: row.updated_at_ms,
        last_error_code: row.last_error_code,
      });
      continue;
    }
    const aggregate = byProvider.get(row.provider);
    const meta = getChannelProviderMeta(row.provider);
    if (!aggregate || !meta) continue;
    aggregate.account_count += 1;
    if (row.configured) aggregate.configured_accounts += 1;
    if (isChannelRuntimeReadyState(row.runtime_state)) aggregate.ready_accounts += 1;
    if (isChannelRuntimeDegradedState(row.runtime_state)) aggregate.degraded_accounts += 1;
    aggregate.active_binding_count += row.active_binding_count;
    aggregate.delivery_queue_depth += safeInt(row.delivery_queue_depth, 0);
    aggregate.delivery_failed_count += safeInt(row.delivery_failed_count, 0);
    aggregate.delivery_dead_letter_count += safeInt(row.delivery_dead_letter_count, 0);
    aggregate.manual_retry_available = aggregate.manual_retry_available || !!row.manual_retry_available;
    aggregate.last_delivery_success_at_ms = maxInt(
      aggregate.last_delivery_success_at_ms,
      row.last_delivery_success_at_ms
    );
    aggregate.last_delivery_failure_at_ms = maxInt(
      aggregate.last_delivery_failure_at_ms,
      row.last_delivery_failure_at_ms
    );
    aggregate.provider_backoff_until_ms = maxInt(
      aggregate.provider_backoff_until_ms,
      row.provider_backoff_until_ms
    );
    aggregate.cooldown_until_ms = maxInt(
      aggregate.cooldown_until_ms,
      row.cooldown_until_ms
    );
    aggregate.runtime_state = chooseState(aggregate.runtime_state, row.runtime_state);
    aggregate.updated_at_ms = Math.max(aggregate.updated_at_ms, row.updated_at_ms);
    if (row.last_error_code && (!aggregate.last_error_code || row.updated_at_ms >= aggregate.updated_at_ms)) {
      aggregate.last_error_code = row.last_error_code;
    } else if (row.last_error_code && !aggregate.last_error_code) {
      aggregate.last_error_code = row.last_error_code;
    }
    if (!aggregate.release_blocked && row.enabled) {
      if (row.delivery_ready || isChannelRuntimeReadyState(row.runtime_state)) {
        aggregate.delivery_ready = true;
      }
      if (row.command_entry_ready || (isChannelRuntimeReadyState(row.runtime_state) && meta.capabilities.includes('structured_actions'))) {
        aggregate.command_entry_ready = true;
      }
    }
  }

  for (const entry of providers) {
    const deliveryDegraded = entry.delivery_dead_letter_count > 0
      || entry.manual_retry_available
      || (
        entry.provider_backoff_until_ms > now
        && (entry.delivery_failed_count > 0 || entry.delivery_queue_depth > 0)
      );
    if (deliveryDegraded && !isChannelRuntimeDegradedState(entry.runtime_state)) {
      entry.runtime_state = 'degraded';
    }
    if (deliveryDegraded) {
      entry.delivery_ready = false;
      if (!entry.last_error_code) {
        entry.last_error_code = 'channel_delivery_degraded';
      }
    }
    if (!entry.release_blocked && !entry.delivery_ready && entry.ready_accounts > 0) {
      entry.delivery_ready = true;
    }
    if (!entry.release_blocked && !entry.command_entry_ready && entry.ready_accounts > 0 && entry.capabilities.includes('structured_actions')) {
      entry.command_entry_ready = true;
    }
    if (deliveryDegraded) {
      entry.delivery_ready = false;
    }
    entry.repair_hints = buildOperatorChannelRuntimeRepairHints({
      provider: entry.provider,
      runtime_state: entry.runtime_state,
      delivery_ready: entry.delivery_ready,
      command_entry_ready: entry.command_entry_ready,
      last_error_code: entry.last_error_code,
      release_blocked: entry.release_blocked,
    });
  }

  const updated_at_ms = safeInt(options.updated_at_ms, 0)
    || providers.reduce((max, row) => Math.max(max, safeInt(row.updated_at_ms, 0)), 0)
    || nowMs();

  const totals = {
    providers_total: providers.length,
    wave1_total: providers.filter((row) => row.release_stage === 'wave1').length,
    ready_total: providers.filter((row) => row.runtime_state === 'ready').length,
    deliverable_total: providers.filter((row) => row.delivery_ready).length,
    command_entry_ready_total: providers.filter((row) => row.command_entry_ready).length,
    degraded_total: providers.filter((row) => row.runtime_state === 'degraded' || row.runtime_state === 'error').length,
    planned_total: providers.filter((row) => row.release_stage !== 'wave1').length,
    bindings_total: providers.reduce((sum, row) => sum + safeInt(row.active_binding_count, 0), 0),
    unknown_provider_rows: unknown_provider_rows.length,
  };

  return {
    schema_version: CHANNEL_RUNTIME_STATUS_SNAPSHOT_SCHEMA,
    updated_at_ms,
    providers,
    totals,
    unknown_provider_rows,
  };
}
