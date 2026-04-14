import { getChannelActionPolicy } from './channel_action_router.js';
import { nowMs, uuid } from './util.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function normalizeActionName(input) {
  return safeString(input).toLowerCase();
}

function normalizeAuditPhase(input) {
  const phase = safeString(input).toLowerCase();
  if (
    phase === 'requested'
    || phase === 'approved'
    || phase === 'denied'
    || phase === 'queued'
    || phase === 'executed'
  ) {
    return phase;
  }
  return 'requested';
}

function shallowObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

export function appendOperatorChannelActionAudit({
  db,
  phase = 'requested',
  client = {},
  request_id = '',
  action_name = '',
  actor = {},
  channel = {},
  gate = null,
  route = null,
  pending_grant = null,
  audit_ref = '',
  ok = true,
  deny_code = '',
  detail = '',
  ext = null,
} = {}) {
  if (!db || typeof db.appendAudit !== 'function') {
    throw new Error('audit_unavailable');
  }

  const normalizedPhase = normalizeAuditPhase(phase);
  const normalizedAction = normalizeActionName(action_name || gate?.action_name);
  const policy = getChannelActionPolicy(normalizedAction);
  const routeObj = shallowObject(route);
  const gateObj = shallowObject(gate);
  const actorObj = shallowObject(actor);
  const channelObj = shallowObject(channel);
  const pendingGrantObj = shallowObject(pending_grant);
  const clientObj = shallowObject(client);
  const extObj = shallowObject(ext);
  const projectId = safeString(
    (safeString(routeObj.scope_type) === 'project' ? routeObj.scope_id : '')
    || (safeString(gateObj.scope_type) === 'project' ? gateObj.scope_id : '')
    || pendingGrantObj.project_id
    || clientObj.project_id
  );
  const eventOk = normalizedPhase === 'denied' ? false : !!ok;

  return db.appendAudit({
    event_id: uuid(),
    event_type: `operator_channel.action.${normalizedPhase}`,
    created_at_ms: nowMs(),
    severity: eventOk ? 'info' : 'warn',
    device_id: safeString(clientObj.device_id || routeObj.resolved_device_id || 'hub_operator_channel_connector'),
    user_id: safeString(clientObj.user_id) || null,
    app_id: safeString(clientObj.app_id || 'hub_runtime_channel_execute'),
    project_id: projectId || null,
    session_id: safeString(clientObj.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: normalizedAction ? `channel.command.${normalizedAction}` : 'channel.command.unknown',
    model_id: null,
    ok: eventOk,
    error_code: eventOk ? null : safeString(deny_code || 'operator_channel_action_denied'),
    error_message: eventOk ? null : safeString(detail || deny_code || 'operator_channel_action_denied'),
    ext_json: JSON.stringify({
      phase: normalizedPhase,
      action_name: normalizedAction,
      route_mode: safeString(routeObj.route_mode || gateObj.route_mode || policy?.route_mode),
      risk_tier: safeString(gateObj.risk_tier || policy?.risk_tier),
      required_grant_scope: safeString(gateObj.required_grant_scope || policy?.required_grant_scope),
      binding_id: safeString(gateObj.binding_id),
      actor_ref: safeString(gateObj.actor_ref),
      actor_provider: safeString(actorObj.provider),
      actor_stable_external_id: safeString(actorObj.stable_external_id),
      actor_external_user_id: safeString(actorObj.external_user_id),
      provider: safeString(channelObj.provider || routeObj.provider),
      account_id: safeString(channelObj.account_id || routeObj.account_id),
      conversation_id: safeString(channelObj.conversation_id || routeObj.conversation_id),
      thread_key: safeString(channelObj.thread_key || routeObj.thread_key),
      channel_scope: safeString(channelObj.channel_scope),
      scope_type: safeString(routeObj.scope_type || gateObj.scope_type),
      scope_id: safeString(routeObj.scope_id || gateObj.scope_id),
      resolved_device_id: safeString(routeObj.resolved_device_id),
      pending_grant_request_id: safeString(pendingGrantObj.grant_request_id),
      pending_grant_project_id: safeString(pendingGrantObj.project_id),
      audit_ref: safeString(audit_ref || routeObj.audit_ref),
      detail: safeString(detail),
      deny_code: safeString(deny_code),
      ext: extObj,
    }),
  });
}
