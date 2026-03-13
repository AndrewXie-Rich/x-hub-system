import { normalizeChannelProviderId } from '../../channel_registry.js';
import {
  classifyOperatorChannelCommandDispatch,
  createOperatorChannelCommandOrchestrator,
  orchestrateOperatorChannelCommand,
} from '../../operator_channel_command_orchestrator.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function normalizePendingGrant(input = null) {
  const src = safeObject(input);
  const grant_request_id = safeString(src.grant_request_id);
  const project_id = safeString(src.project_id || src.scope_id);
  const status = safeString(src.status || 'pending').toLowerCase() || 'pending';
  if (!grant_request_id && !project_id && !status) return null;
  return {
    grant_request_id,
    project_id,
    status,
  };
}

function normalizeWhatsAppCloudActor(input = {}) {
  const actor = safeObject(input);
  return {
    provider: 'whatsapp_cloud_api',
    external_user_id: safeString(actor.external_user_id || actor.wa_id || actor.user_id || actor.id),
    external_tenant_id: safeString(actor.external_tenant_id || actor.account_id || actor.phone_number_id),
  };
}

function normalizeWhatsAppCloudChannel(input = {}) {
  const channel = safeObject(input);
  const provider = normalizeChannelProviderId(channel.provider || 'whatsapp_cloud_api');
  return {
    provider: provider || 'whatsapp_cloud_api',
    account_id: safeString(channel.account_id || channel.phone_number_id),
    conversation_id: safeString(channel.conversation_id || channel.chat_id || channel.wa_id || channel.from),
    thread_key: safeString(channel.thread_key || channel.message_id),
    channel_scope: 'dm',
  };
}

function normalizeRequestId(source_kind, explicit_request_id, fallback_id, now_ms) {
  const raw = safeString(explicit_request_id || fallback_id || `ts_${Math.max(0, Number(now_ms || Date.now()))}`);
  const suffix = raw.replace(/[^A-Za-z0-9._:-]+/g, '_').slice(0, 96) || `ts_${Math.max(0, Number(now_ms || Date.now()))}`;
  return `whatsapp_cloud_api:${safeString(source_kind || 'command') || 'command'}:${suffix}`;
}

export function normalizeWhatsAppCloudCommandInput(input = {}, { now_ms = Date.now() } = {}) {
  const src = safeObject(input);

  const action = safeObject(src.action);
  if (Object.keys(action).length) {
    const action_name = safeString(action.action_name);
    if (!action_name) {
      return {
        ok: false,
        deny_code: 'action_name_missing',
        retryable: false,
      };
    }
    const pending_grant = normalizePendingGrant(action.pending_grant);
    const scope_type = safeString(action.scope_type);
    const scope_id = safeString(action.scope_id);
    return {
      ok: true,
      source_kind: 'interactive',
      request_id: normalizeRequestId('interactive', src.request_id, src.audit_ref || src.event_id, now_ms),
      actor: normalizeWhatsAppCloudActor(src.actor),
      channel: normalizeWhatsAppCloudChannel(src.channel),
      binding_id: safeString(action.binding_id),
      action_name,
      scope_type,
      scope_id,
      note: safeString(action.note),
      pending_grant,
      audit_ref: safeString(src.audit_ref),
      route_project_id: scope_type === 'project'
        ? scope_id
        : safeString(pending_grant?.project_id),
    };
  }

  const structuredAction = safeObject(src.structured_action);
  const action_name = safeString(structuredAction.action_name);
  if (!action_name) {
    return {
      ok: false,
      deny_code: 'structured_action_missing',
      retryable: false,
    };
  }
  const pending_grant = normalizePendingGrant(structuredAction.pending_grant);
  const scope_type = safeString(structuredAction.scope_type);
  const scope_id = safeString(structuredAction.scope_id);
  return {
    ok: true,
    source_kind: safeString(src.envelope_type || 'event_callback') || 'event_callback',
    request_id: normalizeRequestId(
      safeString(src.envelope_type || 'event_callback') || 'event_callback',
      src.request_id,
      src.event_id || src.replay_key,
      now_ms
    ),
    actor: normalizeWhatsAppCloudActor(src.actor),
    channel: normalizeWhatsAppCloudChannel(src.channel),
    binding_id: safeString(structuredAction.binding_id),
    action_name,
    scope_type,
    scope_id,
    note: safeString(structuredAction.note),
    pending_grant,
    audit_ref: '',
    route_project_id: scope_type === 'project'
      ? scope_id
      : safeString(pending_grant?.project_id),
  };
}

export {
  classifyOperatorChannelCommandDispatch as classifyWhatsAppCloudCommandDispatch,
};

export async function orchestrateWhatsAppCloudCommand({
  input = {},
  hub_client = null,
  now_fn = Date.now,
} = {}) {
  return await orchestrateOperatorChannelCommand({
    input,
    normalize_input: normalizeWhatsAppCloudCommandInput,
    hub_client,
    now_fn,
  });
}

export function createWhatsAppCloudCommandOrchestrator({
  hub_client = null,
  now_fn = Date.now,
} = {}) {
  return createOperatorChannelCommandOrchestrator({
    normalize_input: normalizeWhatsAppCloudCommandInput,
    hub_client,
    now_fn,
  });
}
