import { buildChannelStableExternalId } from '../../channel_identity_store.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function safeJsonObject(input) {
  if (!input) return {};
  if (input && typeof input === 'object' && !Array.isArray(input)) return input;
  const text = safeString(input);
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function normalizeFeishuChannelScope(chatType, conversationId) {
  const type = safeString(chatType).toLowerCase();
  const conversation = safeString(conversationId);
  if (type === 'p2p' || type === 'private') return 'dm';
  if (!type && !conversation) return 'group';
  return 'group';
}

function normalizeOperatorNote(input) {
  const text = safeString(input);
  return text ? text.slice(0, 500) : '';
}

const FEISHU_ACTION_ID_MAP = Object.freeze({
  'xt.supervisor.status': 'supervisor.status.get',
  'xt.supervisor.blockers': 'supervisor.blockers.get',
  'xt.supervisor.queue': 'supervisor.queue.get',
  'xt.grant.approve': 'grant.approve',
  'xt.grant.reject': 'grant.reject',
  'xt.deploy.plan': 'deploy.plan',
});

export function listFeishuCardActionIds() {
  return Object.freeze(Object.keys(FEISHU_ACTION_ID_MAP));
}

export function mapFeishuActionIdToChannelAction(actionId) {
  const key = safeString(actionId).toLowerCase();
  return FEISHU_ACTION_ID_MAP[key] || '';
}

function resolveFeishuActionMetadata(payload = {}, rawEvent = {}) {
  const envelope = safeObject(payload);
  const event = safeObject(rawEvent);
  const action = safeObject(event.action);
  const actionValue = safeJsonObject(action.value);
  const formValue = safeJsonObject(event.form_value);
  const context = safeObject(event.context);
  return {
    ...context,
    ...formValue,
    ...actionValue,
  };
}

function resolveFeishuOperatorId(rawEvent = {}, context = {}) {
  const operator = safeObject(rawEvent.operator);
  const operatorId = safeObject(operator.operator_id || operator);
  return {
    external_user_id: safeString(
      operatorId.open_id
      || operatorId.user_id
      || operatorId.union_id
      || context.open_id
      || context.user_id
    ),
    external_tenant_id: safeString(
      operator.tenant_key
      || rawEvent.tenant_key
    ),
  };
}

export function compileFeishuCardAction(payload = {}) {
  const envelope = safeObject(payload);
  const rawEvent = safeObject(envelope.event && typeof envelope.event === 'object' ? envelope.event : payload);
  if (!Object.keys(rawEvent).length) {
    return {
      ok: false,
      deny_code: 'event_missing',
    };
  }

  const header = safeObject(envelope.header);
  const action = safeObject(rawEvent.action);
  const context = safeObject(rawEvent.context);
  const metadata = resolveFeishuActionMetadata(envelope, rawEvent);
  const action_name = safeString(
    metadata.action_name
    || metadata.command_action
    || metadata.command
    || mapFeishuActionIdToChannelAction(action.action_id || metadata.action_id)
  );
  if (!action_name) {
    return {
      ok: false,
      deny_code: 'action_unsupported',
    };
  }

  const audit_ref = safeString(metadata.audit_ref);
  if (!audit_ref) {
    return {
      ok: false,
      deny_code: 'audit_ref_missing',
    };
  }

  const operatorId = resolveFeishuOperatorId(rawEvent, context);
  const tenantKey = safeString(
    operatorId.external_tenant_id
    || header.tenant_key
    || metadata.account_id
  );
  const conversationId = safeString(
    context.open_chat_id
    || context.chat_id
    || metadata.conversation_id
    || context.chat_id
  );
  const threadKey = safeString(
    context.open_message_id
    || context.message_id
    || metadata.thread_key
    || rawEvent.token
  );
  const grant_request_id = safeString(
    metadata.grant_request_id
    || metadata.pending_grant_request_id
  );

  return {
    ok: true,
    deny_code: '',
    request_id: safeString(header.event_id || rawEvent.token || context.open_message_id),
    audit_ref,
    actor: {
      provider: 'feishu',
      stable_external_id: buildChannelStableExternalId({
        provider: 'feishu',
        stable_external_id: metadata.stable_external_id,
        external_user_id: operatorId.external_user_id,
        external_tenant_id: tenantKey,
      }),
      external_user_id: operatorId.external_user_id,
      external_tenant_id: tenantKey,
    },
    channel: {
      provider: 'feishu',
      account_id: tenantKey,
      conversation_id: conversationId || safeString(context.open_id || context.user_id),
      thread_key: threadKey,
      channel_scope: normalizeFeishuChannelScope(context.chat_type || metadata.chat_type, conversationId),
    },
    action: {
      binding_id: safeString(metadata.binding_id),
      action_name,
      scope_type: safeString(metadata.scope_type),
      scope_id: safeString(metadata.scope_id),
      note: normalizeOperatorNote(metadata.note || metadata.reason),
      pending_grant: grant_request_id
        ? {
            grant_request_id,
            project_id: safeString(metadata.project_id || metadata.pending_grant_project_id),
            status: safeString(metadata.pending_grant_status || 'pending') || 'pending',
          }
        : null,
    },
  };
}
