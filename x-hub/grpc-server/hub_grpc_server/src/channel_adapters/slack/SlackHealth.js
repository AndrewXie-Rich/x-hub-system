import { nowMs } from '../../util.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

export function buildSlackHealthSnapshot(input = {}) {
  const bot_token_present = safeBool(input.bot_token_present, false);
  const signing_secret_present = safeBool(input.signing_secret_present, false);
  const interactive_enabled = safeBool(input.interactive_enabled, true);
  const ingress_mode = safeString(input.ingress_mode || 'webhook') || 'webhook';
  const last_error_code = safeString(input.last_error_code);

  const runtime_state = (() => {
    if (!bot_token_present) return 'not_configured';
    if (ingress_mode === 'webhook' && !signing_secret_present) return 'not_configured';
    if (last_error_code) return 'degraded';
    return 'ready';
  })();

  return {
    provider: 'slack',
    account_id: safeString(input.account_id),
    runtime_state,
    delivery_ready: runtime_state === 'ready',
    command_entry_ready: runtime_state === 'ready' && interactive_enabled,
    active_binding_count: safeInt(input.active_binding_count, 0),
    last_error_code,
    updated_at_ms: safeInt(input.updated_at_ms, nowMs()) || nowMs(),
    ingress_mode,
    bot_token_present,
    signing_secret_present,
    interactive_enabled,
  };
}
