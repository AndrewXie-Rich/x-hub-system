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

function normalizeTelegramActor(input = {}) {
  const actor = safeObject(input);
  return {
    provider: 'telegram',
    external_user_id: safeString(actor.external_user_id || actor.user_id || actor.id),
    external_tenant_id: safeString(actor.external_tenant_id || actor.account_id || actor.tenant_id),
  };
}

function normalizeTelegramChannel(input = {}) {
  const channel = safeObject(input);
  const provider = normalizeChannelProviderId(channel.provider || 'telegram');
  const scope = safeString(channel.channel_scope || channel.chat_type).toLowerCase();
  return {
    provider: provider || 'telegram',
    account_id: safeString(channel.account_id),
    conversation_id: safeString(channel.conversation_id || channel.chat_id || channel.channel_id),
    thread_key: safeString(channel.thread_key),
    channel_scope: scope === 'private' || scope === 'dm' ? 'dm' : 'group',
  };
}

function normalizeRequestId(source_kind, explicit_request_id, fallback_id, now_ms) {
  const raw = safeString(explicit_request_id || fallback_id || `ts_${Math.max(0, Number(now_ms || Date.now()))}`);
  const suffix = raw.replace(/[^A-Za-z0-9._:-]+/g, '_').slice(0, 96) || `ts_${Math.max(0, Number(now_ms || Date.now()))}`;
  return `telegram:${safeString(source_kind || 'command') || 'command'}:${suffix}`;
}

export function normalizeTelegramCommandInput(input = {}, { now_ms = Date.now() } = {}) {
  const src = safeObject(input);

  if (src.action && typeof src.action === 'object') {
    const action = safeObject(src.action);
    const action_name = safeString(action.action_name);
    if (!action_name) {
      return {
        ok: false,
        deny_code: 'action_name_missing',
        retryable: false,
      };
    }
    const scope_type = safeString(action.scope_type);
    const scope_id = safeString(action.scope_id);
    const pending_grant = normalizePendingGrant(action.pending_grant);
    if (pending_grant && !pending_grant.project_id && scope_type === 'project') {
      pending_grant.project_id = scope_id;
    }
    return {
      ok: true,
      source_kind: 'interactive',
      request_id: normalizeRequestId('interactive', src.request_id, src.event_id || src.callback_query_id, now_ms),
      actor: normalizeTelegramActor(src.actor),
      channel: normalizeTelegramChannel(src.channel),
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

  const action = safeObject(src.structured_action);
  const action_name = safeString(action.action_name);
  if (!action_name) {
    return {
      ok: false,
      deny_code: 'structured_action_missing',
      retryable: false,
    };
  }
  const scope_type = safeString(action.scope_type);
  const scope_id = safeString(action.scope_id);
  const pending_grant = normalizePendingGrant(action.pending_grant);
  if (pending_grant && !pending_grant.project_id && scope_type === 'project') {
    pending_grant.project_id = scope_id;
  }
  return {
    ok: true,
    source_kind: safeString(src.envelope_type || 'message') || 'message',
    request_id: normalizeRequestId(
      safeString(src.envelope_type || 'message') || 'message',
      src.request_id,
      src.event_id || src.replay_key,
      now_ms
    ),
    actor: normalizeTelegramActor(src.actor),
    channel: normalizeTelegramChannel(src.channel),
    binding_id: safeString(action.binding_id),
    action_name,
    scope_type,
    scope_id,
    note: safeString(action.note),
    pending_grant,
    audit_ref: '',
    route_project_id: scope_type === 'project'
      ? scope_id
      : safeString(pending_grant?.project_id),
  };
}

export {
  classifyOperatorChannelCommandDispatch as classifyTelegramCommandDispatch,
};

export async function orchestrateTelegramCommand({
  input = {},
  hub_client = null,
  now_fn = Date.now,
} = {}) {
  return await orchestrateOperatorChannelCommand({
    input,
    normalize_input: normalizeTelegramCommandInput,
    hub_client,
    now_fn,
  });
}

export function createTelegramCommandOrchestrator({
  hub_client = null,
  now_fn = Date.now,
} = {}) {
  return createOperatorChannelCommandOrchestrator({
    normalize_input: normalizeTelegramCommandInput,
    hub_client,
    now_fn,
  });
}
