import {
  normalizeChannelConversationId,
  normalizeChannelDeliveryContext,
  normalizeChannelThreadKey,
} from './channel_delivery_context.js';
import {
  getChannelProviderMeta,
  listChannelProviders,
  normalizeChannelProviderId,
} from './channel_registry.js';
import { nowMs } from './util.js';

export const HUB_CHANNEL_INGRESS_ENVELOPE_SCHEMA = 'xhub.channel_ingress_envelope.v1';
export const HUB_CHANNEL_PROVIDER_EXPOSURE_MATRIX_SCHEMA = 'xhub.channel_provider_exposure_matrix.v1';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null) return fallback;
  if (input === 1 || input === '1' || input === 'true') return true;
  if (input === 0 || input === '0' || input === 'false') return false;
  return fallback;
}

function normalizeChannelAccountId(input) {
  if (typeof input === 'number' && Number.isFinite(input)) {
    return String(Math.trunc(input));
  }
  return safeString(input);
}

function normalizeChannelScope(input, fallback = 'group') {
  const raw = safeString(input).toLowerCase();
  if (raw === 'dm' || raw === 'direct' || raw === 'private') return 'dm';
  if (raw === 'group' || raw === 'channel' || raw === 'room' || raw === 'supergroup') return 'group';
  return fallback === 'dm' ? 'dm' : 'group';
}

function normalizePendingGrant(input = null) {
  if (!input || typeof input !== 'object') return null;
  const grant_request_id = safeString(input.grant_request_id);
  const project_id = safeString(input.project_id || input.scope_id);
  const status = safeString(input.status || 'pending').toLowerCase() || 'pending';
  if (!grant_request_id && !project_id && !status) return null;
  return {
    grant_request_id,
    project_id,
    status,
  };
}

function normalizeActionLike(input = null) {
  if (!input || typeof input !== 'object') return null;
  const action_name = safeString(input.action_name);
  if (!action_name) return null;
  return {
    action_name,
    binding_id: safeString(input.binding_id),
    scope_type: safeString(input.scope_type),
    scope_id: safeString(input.scope_id),
    note: safeString(input.note),
    pending_grant: normalizePendingGrant(input.pending_grant),
  };
}

function normalizeActor(input = null, provider = '') {
  if (!input || typeof input !== 'object') return null;
  const external_user_id = safeString(
    input.external_user_id || input.user_id || input.id
  );
  const external_tenant_id = safeString(
    input.external_tenant_id || input.external_team_id || input.tenant_id || input.team_id || input.account_id
  );
  if (!external_user_id && !external_tenant_id) return null;
  return {
    provider,
    external_user_id,
    external_tenant_id,
  };
}

function normalizeChannel(input = null, provider = '') {
  if (!input || typeof input !== 'object') return null;
  const conversation_id = normalizeChannelConversationId(
    input.conversation_id || input.channel_id || input.chat_id || input.room_id
  );
  const account_id = normalizeChannelAccountId(input.account_id);
  const thread_key = normalizeChannelThreadKey(
    input.thread_key || input.thread_id || input.thread_ts || input.message_id
  );
  const fallbackScope = safeString(conversation_id).startsWith('D') ? 'dm' : 'group';
  const channel_scope = normalizeChannelScope(input.channel_scope, fallbackScope);
  if (!conversation_id && !account_id && !thread_key) return null;
  return {
    provider,
    account_id: account_id || '',
    conversation_id: conversation_id || '',
    thread_key: thread_key || '',
    channel_scope,
  };
}

function normalizeIngressType(envelope_type = '', fallback = '') {
  const raw = safeString(envelope_type).toLowerCase();
  if (raw === 'event_callback' || raw === 'message' || raw === 'messages') return 'message';
  if (raw === 'callback_query' || raw === 'interactive') return 'interactive';
  if (raw === 'statuses') return 'status';
  if (raw === 'url_verification') return 'verification';
  return safeString(fallback).toLowerCase();
}

function normalizeIngressEvent(input = null, {
  provider = '',
  channel = null,
  actor = null,
  envelope_type = '',
  signature_valid = true,
} = {}) {
  const src = input && typeof input === 'object' ? input : {};
  const ingress_type = normalizeIngressType(
    src.ingress_type || envelope_type,
    envelope_type
  );
  const channel_scope = normalizeChannelScope(
    src.channel_scope,
    channel?.channel_scope || 'group'
  );
  const sender_id = safeString(
    src.sender_id || actor?.external_user_id
  );
  const channel_id = safeString(
    src.channel_id || channel?.conversation_id
  );
  const message_id = safeString(
    src.message_id || channel?.thread_key
  );
  const source_id = safeString(
    src.source_id || (provider && channel_id ? `${provider}:${channel_id}` : '')
  );
  const field = safeString(src.field);
  const status = safeString(src.status);
  const phone_number_id = safeString(src.phone_number_id);
  const message_type = safeString(src.message_type);
  const event_sequence = Math.max(0, Number(src.event_sequence || 0));
  const replay_detected = safeBool(src.replay_detected, false);
  if (
    !ingress_type
    && !sender_id
    && !channel_id
    && !message_id
    && !field
    && !status
    && !phone_number_id
    && !message_type
  ) return null;
  return {
    ingress_type,
    channel_scope,
    sender_id,
    channel_id,
    message_id,
    event_sequence,
    source_id,
    signature_valid: safeBool(src.signature_valid, signature_valid),
    replay_detected,
    field,
    status,
    phone_number_id,
    message_type,
  };
}

const CHANNEL_PROVIDER_EXPOSURE_ROWS = Object.freeze([
  Object.freeze({
    provider: 'slack',
    listener: 'public_webhook',
    process: 'slack_ingress_worker',
    path: '/slack/events',
    auth_mode: 'slack_signature_v0',
    replay_mode: 'hub_webhook_replay_guard(event_id|trigger_id|challenge)',
    body_cap: '256KiB',
    rate_limit: 'preauth_surface_guard(12/min/source)+webhook_replay_guard',
    allowed_envelope_types: Object.freeze(['event_callback', 'interactive', 'url_verification']),
  }),
  Object.freeze({
    provider: 'telegram',
    listener: 'provider_polling',
    process: 'telegram_polling_worker',
    path: 'telegram:getUpdates',
    auth_mode: 'telegram_bot_token_local',
    replay_mode: 'provider_update_id',
    body_cap: 'provider_poll_response',
    rate_limit: 'provider_poll_timeout+hub_command_gate',
    allowed_envelope_types: Object.freeze(['message', 'callback_query']),
  }),
  Object.freeze({
    provider: 'feishu',
    listener: 'public_webhook',
    process: 'feishu_ingress_worker',
    path: '/feishu/events',
    auth_mode: 'feishu_verification_token',
    replay_mode: 'hub_webhook_replay_guard(event_id|request_id|challenge)',
    body_cap: '256KiB',
    rate_limit: 'preauth_surface_guard(12/min/source)+webhook_replay_guard',
    allowed_envelope_types: Object.freeze(['event_callback', 'interactive', 'url_verification']),
  }),
  Object.freeze({
    provider: 'whatsapp_cloud_api',
    listener: 'public_webhook',
    process: 'whatsapp_cloud_ingress_worker',
    path: '/whatsapp/events',
    auth_mode: 'meta_app_secret_signature+verify_token_get',
    replay_mode: 'hub_webhook_replay_guard(message_id|status_id)',
    body_cap: '256KiB',
    rate_limit: 'preauth_surface_guard(12/min/source)+webhook_replay_guard',
    allowed_envelope_types: Object.freeze(['messages', 'statuses']),
  }),
  Object.freeze({
    provider: 'whatsapp_personal_qr',
    listener: 'local_runner_session',
    process: 'whatsapp_personal_qr_runner',
    path: 'runner://whatsapp-personal-qr',
    auth_mode: 'trusted_local_runner_session',
    replay_mode: 'runner_local_idempotency_key',
    body_cap: 'local_runtime_only',
    rate_limit: 'runner_local_backpressure',
    allowed_envelope_types: Object.freeze(['messages', 'statuses']),
  }),
]);

const CHANNEL_PROVIDER_EXPOSURE_BY_ID = new Map(
  CHANNEL_PROVIDER_EXPOSURE_ROWS.map((row) => [row.provider, row])
);

export function getChannelProviderExposure(provider) {
  const providerId = normalizeChannelProviderId(provider);
  return providerId ? (CHANNEL_PROVIDER_EXPOSURE_BY_ID.get(providerId) || null) : null;
}

export function listChannelProviderExposureRows() {
  return CHANNEL_PROVIDER_EXPOSURE_ROWS;
}

export function buildChannelProviderExposureMatrix({ updated_at_ms = 0 } = {}) {
  const rows = listChannelProviders().map((meta) => {
    const exposure = getChannelProviderExposure(meta.id) || {};
    return {
      provider: meta.id,
      label: meta.label,
      aliases: [...meta.aliases],
      capabilities: [...meta.capabilities],
      threading_mode: meta.threading_mode,
      approval_surface: meta.approval_surface,
      release_stage: meta.release_stage,
      automation_path: meta.automation_path,
      require_real_evidence: meta.require_real_evidence === true,
      listener: safeString(exposure.listener),
      process: safeString(exposure.process),
      path: safeString(exposure.path),
      auth_mode: safeString(exposure.auth_mode),
      replay_mode: safeString(exposure.replay_mode),
      body_cap: safeString(exposure.body_cap),
      rate_limit: safeString(exposure.rate_limit),
      allowed_envelope_types: Array.isArray(exposure.allowed_envelope_types)
        ? [...exposure.allowed_envelope_types]
        : [],
    };
  });
  return {
    schema_version: HUB_CHANNEL_PROVIDER_EXPOSURE_MATRIX_SCHEMA,
    updated_at_ms: Math.max(0, Number(updated_at_ms || 0)) || nowMs(),
    providers: rows,
  };
}

export function normalizeHubChannelIngressEnvelope(input = {}, { provider = '' } = {}) {
  const src = input && typeof input === 'object' ? input : {};
  const providerId = normalizeChannelProviderId(
    provider
    || src.provider
    || src.actor?.provider
    || src.channel?.provider
  );
  if (!providerId) {
    return {
      ok: false,
      deny_code: 'provider_unknown',
      retryable: false,
    };
  }
  const exposure = getChannelProviderExposure(providerId);
  if (!exposure) {
    return {
      ok: false,
      deny_code: 'provider_not_registered',
      retryable: false,
    };
  }
  const envelope_type = safeString(src.envelope_type).toLowerCase();
  if (!envelope_type || !exposure.allowed_envelope_types.includes(envelope_type)) {
    return {
      ok: false,
      deny_code: 'envelope_type_unsupported',
      retryable: false,
    };
  }

  const actor = normalizeActor(src.actor, providerId);
  const channel = normalizeChannel(src.channel, providerId);
  const delivery_context = channel
    ? normalizeChannelDeliveryContext({
      provider: providerId,
      conversation_id: channel.conversation_id,
      account_id: channel.account_id,
      thread_key: channel.thread_key,
    })
    : undefined;
  const signature_valid = safeBool(src.signature_valid, true);
  const token_valid = safeBool(src.token_valid, true);
  const action = normalizeActionLike(src.action);
  const structured_action = normalizeActionLike(src.structured_action);
  const ingress_event = normalizeIngressEvent(src.ingress_event, {
    provider: providerId,
    channel,
    actor,
    envelope_type,
    signature_valid,
  });
  const meta = getChannelProviderMeta(providerId);

  return {
    ok: true,
    schema_version: HUB_CHANNEL_INGRESS_ENVELOPE_SCHEMA,
    provider: providerId,
    provider_label: safeString(meta?.label),
    envelope_type,
    event_id: safeString(src.event_id),
    replay_key: safeString(src.replay_key),
    request_id: safeString(src.request_id),
    audit_ref: safeString(src.audit_ref),
    challenge: safeString(src.challenge),
    signature_valid,
    token_valid,
    listener: exposure.listener,
    process: exposure.process,
    path: exposure.path,
    auth_mode: exposure.auth_mode,
    replay_mode: exposure.replay_mode,
    body_cap: exposure.body_cap,
    rate_limit: exposure.rate_limit,
    actor,
    channel,
    delivery_context,
    source_id: safeString(
      src.source_id
      || ingress_event?.source_id
      || (channel?.conversation_id ? `${providerId}:${channel.conversation_id}` : '')
    ),
    ingress_event,
    action,
    structured_action,
  };
}
