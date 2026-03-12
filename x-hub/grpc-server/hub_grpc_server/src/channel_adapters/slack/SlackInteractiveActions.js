function safeString(input) {
  return String(input ?? '').trim();
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

function normalizeSlackChannelScope(channelId) {
  return safeString(channelId).startsWith('D') ? 'dm' : 'group';
}

function normalizeOperatorNote(input) {
  const text = safeString(input);
  return text ? text.slice(0, 500) : '';
}

const SLACK_ACTION_ID_MAP = Object.freeze({
  'xt.supervisor.status': 'supervisor.status.get',
  'xt.supervisor.blockers': 'supervisor.blockers.get',
  'xt.supervisor.queue': 'supervisor.queue.get',
  'xt.grant.approve': 'grant.approve',
  'xt.grant.reject': 'grant.reject',
  'xt.deploy.plan': 'deploy.plan',
  'xt.deploy.execute': 'deploy.execute',
  'xt.supervisor.pause': 'supervisor.pause',
  'xt.supervisor.resume': 'supervisor.resume',
  'xt.device.doctor': 'device.doctor.get',
  'xt.device.permissions': 'device.permission_status.get',
});

export function listSlackInteractiveActionIds() {
  return Object.freeze(Object.keys(SLACK_ACTION_ID_MAP));
}

export function mapSlackActionIdToChannelAction(actionId) {
  const key = safeString(actionId).toLowerCase();
  return SLACK_ACTION_ID_MAP[key] || '';
}

function resolveSlackActionMetadata(payload = {}, action = null) {
  const viewMeta = safeJsonObject(payload.view?.private_metadata);
  const actionValue = safeJsonObject(action?.value);
  const messageMeta = safeJsonObject(payload.message?.metadata?.event_payload);
  return {
    ...viewMeta,
    ...messageMeta,
    ...actionValue,
  };
}

export function compileSlackInteractiveAction(payload = {}) {
  if (!payload || typeof payload !== 'object') {
    return {
      ok: false,
      deny_code: 'payload_invalid',
    };
  }
  if (safeString(payload.type).toLowerCase() !== 'block_actions') {
    return {
      ok: false,
      deny_code: 'interactive_type_unsupported',
    };
  }

  const action = Array.isArray(payload.actions) ? payload.actions[0] : null;
  if (!action || typeof action !== 'object') {
    return {
      ok: false,
      deny_code: 'action_missing',
    };
  }

  const metadata = resolveSlackActionMetadata(payload, action);
  const action_name = safeString(metadata.action_name || mapSlackActionIdToChannelAction(action.action_id));
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

  const teamId = safeString(payload.team?.id || payload.team?.enterprise_id || metadata.account_id);
  const channelId = safeString(payload.channel?.id || payload.container?.channel_id || metadata.conversation_id);
  const threadKey = safeString(
    payload.container?.thread_ts
    || payload.message?.thread_ts
    || payload.message?.ts
    || metadata.thread_key
  );
  const grant_request_id = safeString(
    metadata.grant_request_id
    || metadata.pending_grant_request_id
  );
  const note = normalizeOperatorNote(metadata.note || metadata.reason);

  return {
    ok: true,
    deny_code: '',
    request_id: safeString(payload.trigger_id || action.action_ts || payload.container?.message_ts),
    audit_ref,
    actor: {
      provider: 'slack',
      external_user_id: safeString(payload.user?.id),
      external_tenant_id: teamId,
    },
    channel: {
      provider: 'slack',
      account_id: teamId,
      conversation_id: channelId,
      thread_key: threadKey,
      channel_scope: normalizeSlackChannelScope(channelId),
    },
    action: {
      binding_id: safeString(metadata.binding_id),
      action_name,
      scope_type: safeString(metadata.scope_type),
      scope_id: safeString(metadata.scope_id),
      note,
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
