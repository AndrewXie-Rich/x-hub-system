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

function normalizeRuntimeRow(row) {
  const src = row && typeof row === 'object' ? row : {};
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
  return {
    provider_raw,
    provider,
    provider_known,
    account_id,
    runtime_state,
    updated_at_ms,
    active_binding_count,
    enabled,
    configured,
    delivery_ready: explicitDeliveryReady,
    command_entry_ready: explicitCommandReady,
    last_error_code: safeString(src.last_error_code || src.error_code || src.lastErrorCode),
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
    updated_at_ms: 0,
  };
}

export function buildChannelRuntimeStatusSnapshot(rows = [], options = {}) {
  const normalizedRows = Array.isArray(rows) ? rows.map((row) => normalizeRuntimeRow(row)) : [];
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
    if (!entry.release_blocked && !entry.delivery_ready && entry.ready_accounts > 0) {
      entry.delivery_ready = true;
    }
    if (!entry.release_blocked && !entry.command_entry_ready && entry.ready_accounts > 0 && entry.capabilities.includes('structured_actions')) {
      entry.command_entry_ready = true;
    }
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
