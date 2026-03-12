function safeString(input) {
  return String(input ?? '').trim();
}

function toFrozenValues(values) {
  return Object.freeze([...values]);
}

export const CHANNEL_CAPABILITIES = toFrozenValues([
  'status_query',
  'blockers_query',
  'queue_query',
  'approval_actions',
  'push_alerts',
  'push_summaries',
  'structured_actions',
  'thread_native',
  'project_binding',
  'preferred_device_hint',
  'trusted_local_runner',
]);

export const CHANNEL_THREADING_MODES = toFrozenValues([
  'none',
  'provider_native',
]);

export const CHANNEL_APPROVAL_SURFACES = toFrozenValues([
  'text_only',
  'inline_buttons',
  'card',
]);

export const CHANNEL_RELEASE_STAGES = toFrozenValues([
  'wave1',
  'p1',
]);

export const CHANNEL_AUTOMATION_PATHS = toFrozenValues([
  'hub_bridge',
  'trusted_automation_local',
]);

export const CHANNEL_RUNTIME_STATES = toFrozenValues([
  'planned',
  'not_configured',
  'configuring',
  'ingress_ready',
  'ready',
  'degraded',
  'disabled',
  'error',
]);

const CHANNEL_CAPABILITY_SET = new Set(CHANNEL_CAPABILITIES);
const CHANNEL_THREADING_MODE_SET = new Set(CHANNEL_THREADING_MODES);
const CHANNEL_APPROVAL_SURFACE_SET = new Set(CHANNEL_APPROVAL_SURFACES);
const CHANNEL_RELEASE_STAGE_SET = new Set(CHANNEL_RELEASE_STAGES);
const CHANNEL_AUTOMATION_PATH_SET = new Set(CHANNEL_AUTOMATION_PATHS);
const CHANNEL_RUNTIME_STATE_SET = new Set(CHANNEL_RUNTIME_STATES);

export function normalizeChannelCapability(input) {
  const key = safeString(input).toLowerCase();
  return CHANNEL_CAPABILITY_SET.has(key) ? key : '';
}

export function normalizeChannelCapabilities(input) {
  const rows = Array.isArray(input) ? input : [];
  const out = [];
  const seen = new Set();
  for (const raw of rows) {
    const capability = normalizeChannelCapability(raw);
    if (!capability || seen.has(capability)) continue;
    seen.add(capability);
    out.push(capability);
  }
  return out;
}

export function normalizeChannelThreadingMode(input, fallback = 'none') {
  const key = safeString(input).toLowerCase();
  return CHANNEL_THREADING_MODE_SET.has(key) ? key : fallback;
}

export function normalizeChannelApprovalSurface(input, fallback = 'text_only') {
  const key = safeString(input).toLowerCase();
  return CHANNEL_APPROVAL_SURFACE_SET.has(key) ? key : fallback;
}

export function normalizeChannelReleaseStage(input, fallback = 'p1') {
  const key = safeString(input).toLowerCase();
  return CHANNEL_RELEASE_STAGE_SET.has(key) ? key : fallback;
}

export function normalizeChannelAutomationPath(input, fallback = 'hub_bridge') {
  const key = safeString(input).toLowerCase();
  return CHANNEL_AUTOMATION_PATH_SET.has(key) ? key : fallback;
}

export function normalizeChannelRuntimeState(input, { fallback = 'not_configured' } = {}) {
  const key = safeString(input).toLowerCase();
  return CHANNEL_RUNTIME_STATE_SET.has(key) ? key : fallback;
}

export function isChannelRuntimeReadyState(input) {
  return normalizeChannelRuntimeState(input, { fallback: '' }) === 'ready';
}

export function isChannelRuntimeDegradedState(input) {
  const state = normalizeChannelRuntimeState(input, { fallback: '' });
  return state === 'degraded' || state === 'error';
}
