import {
  buildWhatsAppCloudApprovalMessage,
  buildWhatsAppCloudSummaryMessage,
} from './WhatsAppCloudEgress.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

function deliveryContextFromResult(result = {}) {
  const command = safeObject(result.command);
  const channel = safeObject(command.channel);
  return {
    provider: 'whatsapp_cloud_api',
    account_id: safeString(channel.account_id),
    conversation_id: safeString(channel.conversation_id),
    thread_key: safeString(channel.thread_key),
  };
}

function bindingDeliveryContext(binding = {}) {
  return {
    provider: 'whatsapp_cloud_api',
    account_id: safeString(binding.account_id),
    conversation_id: safeString(binding.conversation_id),
    thread_key: safeString(binding.thread_key),
  };
}

function auditRefFromResult(result = {}) {
  return safeString(result.command?.audit_ref || result.request_id || result.route?.route_id || result.gate?.binding_id);
}

function projectIdFromResult(result = {}) {
  if (safeString(result.execution?.xt_command?.project_id)) return safeString(result.execution.xt_command.project_id);
  if (safeString(result.execution?.query?.project_id)) return safeString(result.execution.query.project_id);
  if (safeString(result.execution?.grant_action?.grant?.client?.project_id)) {
    return safeString(result.execution.grant_action.grant.client.project_id);
  }
  if (safeString(result.gate?.scope_type) === 'project') return safeString(result.gate?.scope_id);
  if (safeString(result.route?.scope_type) === 'project') return safeString(result.route?.scope_id);
  return safeString(result.command?.route_project_id || result.command?.pending_grant?.project_id);
}

function classifyStatus(result = {}) {
  const execution = safeObject(result.execution);
  if (Object.keys(execution).length) {
    const xtStatus = safeString(execution.xt_command?.status);
    if (xtStatus === 'prepared' || xtStatus === 'completed' || xtStatus === 'accepted') return 'xt_command_prepared';
    if (xtStatus === 'queued') return 'xt_command_queued';
    if (xtStatus) return 'xt_command_failed';
    if (execution.ok === false) return 'hub_execution_failed';

    const grantDecision = safeString(execution.grant_action?.decision);
    if (grantDecision === 'approved') return 'grant_approved';
    if (grantDecision === 'denied') return 'grant_denied';

    const queryAction = safeString(execution.query?.action_name);
    if (queryAction === 'supervisor.status.get') return 'supervisor_status';
    if (queryAction === 'supervisor.queue.get') return 'supervisor_queue';
  }

  const dispatchKind = safeString(result.dispatch?.kind);
  if (dispatchKind === 'deny') return 'denied';
  if (dispatchKind === 'route_blocked') return 'route_blocked';
  if (dispatchKind === 'xt_command') return 'routed_to_xt';
  if (dispatchKind === 'runner_command') return 'routed_to_runner';
  if (dispatchKind === 'hub_grant_action') return 'hub_action';
  return 'hub_query';
}

function grantEventAuditRef(event = {}) {
  return safeString(
    `hub_grant_event:${safeString(event.event_id || event.grant_request_id || 'unknown') || 'unknown'}`
  );
}

function buildExecutionSummary(result = {}) {
  const execution = safeObject(result.execution);
  if (!Object.keys(execution).length) return null;

  const route = safeObject(execution.route);
  const query = safeObject(execution.query);
  const grantAction = safeObject(execution.grant_action);
  const xtCommand = safeObject(execution.xt_command);
  const heartbeat = safeObject(query.heartbeat);
  const queue = safeObject(query.queue);
  const actionName = safeString(
    query.action_name
    || grantAction.action_name
    || result.command?.action_name
    || result.gate?.action_name
  );
  const projectId = projectIdFromResult(result);
  const routeMode = safeString(route.route_mode || result.route?.route_mode || result.gate?.route_mode);
  const resolvedDeviceId = safeString(route.resolved_device_id || result.route?.resolved_device_id);
  const auditRef = auditRefFromResult(result);
  const denyCode = safeString(execution.deny_code);

  if (Object.keys(xtCommand).length) {
    const xtStatus = safeString(xtCommand.status);
    return buildWhatsAppCloudSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title: xtStatus === 'queued' ? 'XT Command Queued' : (xtStatus === 'prepared' || xtStatus === 'completed' || xtStatus === 'accepted' ? 'XT Command Prepared' : 'XT Command Failed'),
      status: classifyStatus(result),
      project_id: safeString(xtCommand.project_id || projectId),
      lines: [
        actionName ? `Action: ${actionName}` : '',
        routeMode ? `Route: ${routeMode}` : '',
        safeString(xtCommand.resolved_device_id || resolvedDeviceId) ? `Device: ${safeString(xtCommand.resolved_device_id || resolvedDeviceId)}` : '',
        safeString(xtCommand.command_id) ? `Command: ${safeString(xtCommand.command_id)}` : '',
        xtStatus ? `State: ${xtStatus}` : '',
        safeString(xtCommand.deny_code || denyCode) ? `Reason: ${safeString(xtCommand.deny_code || denyCode)}` : '',
        safeString(xtCommand.detail || execution.detail) ? `Detail: ${safeString(xtCommand.detail || execution.detail)}` : '',
      ].filter(Boolean),
      audit_ref: safeString(xtCommand.audit_ref || auditRef),
    });
  }

  if (execution.ok === false) {
    return buildWhatsAppCloudSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title: 'Hub Command Failed',
      status: classifyStatus(result),
      project_id: projectId,
      lines: [
        actionName ? `Action: ${actionName}` : '',
        routeMode ? `Route: ${routeMode}` : '',
        resolvedDeviceId ? `Device: ${resolvedDeviceId}` : '',
        denyCode ? `Reason: ${denyCode}` : '',
        safeString(execution.detail) ? `Detail: ${safeString(execution.detail)}` : '',
      ].filter(Boolean),
      audit_ref: auditRef,
    });
  }

  if (Object.keys(grantAction).length) {
    const grant = safeObject(grantAction.grant);
    return buildWhatsAppCloudSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title: safeString(grantAction.decision) === 'approved' ? 'Grant Approved' : 'Grant Rejected',
      status: classifyStatus(result),
      project_id: projectId,
      lines: [
        actionName ? `Action: ${actionName}` : '',
        safeString(grantAction.grant_request_id) ? `Grant request: ${safeString(grantAction.grant_request_id)}` : '',
        safeString(grant.grant_id) ? `Grant: ${safeString(grant.grant_id)}` : '',
        safeInt(grant.expires_at_ms) > 0 ? `Expires at ms: ${safeInt(grant.expires_at_ms)}` : '',
        safeString(grantAction.note) ? `Note: ${safeString(grantAction.note)}` : '',
        safeString(grantAction.reason) ? `Reason: ${safeString(grantAction.reason)}` : '',
      ].filter(Boolean),
      audit_ref: auditRef,
    });
  }

  if (Object.keys(query).length) {
    const lines = [
      actionName ? `Action: ${actionName}` : '',
      routeMode ? `Route: ${routeMode}` : '',
      resolvedDeviceId ? `Device: ${resolvedDeviceId}${route.xt_online === true ? ' (online)' : ''}` : '',
      Object.keys(heartbeat).length ? `Heartbeat: queue_depth=${safeInt(heartbeat.queue_depth)} wait_ms=${safeInt(heartbeat.oldest_wait_ms)} risk=${safeString(heartbeat.risk_tier || 'unknown') || 'unknown'}` : 'Heartbeat: no live project heartbeat',
    ].filter(Boolean);

    if (actionName === 'supervisor.queue.get') {
      if (queue.planned === true) {
        const queueItems = safeArray(queue.items).slice(0, 3);
        if (!queueItems.length) {
          lines.push('Queue: no active queued projects');
        } else {
          for (const item of queueItems) {
            lines.push(`Queue item: ${safeString(item.project_id)} depth=${safeInt(item.queue_depth)} wait_ms=${safeInt(item.oldest_wait_ms)} risk=${safeString(item.risk_tier || 'unknown') || 'unknown'}`);
          }
        }
      } else {
        lines.push(`Queue unavailable: ${safeString(queue.deny_code || 'queue_view_unavailable')}`);
      }
    }

    return buildWhatsAppCloudSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title: actionName === 'supervisor.queue.get' ? 'Supervisor Queue' : 'Supervisor Status',
      status: classifyStatus(result),
      project_id: projectId,
      lines,
      audit_ref: auditRef,
    });
  }

  return null;
}

export function buildWhatsAppCloudResultSummary(result = {}) {
  const executionSummary = buildExecutionSummary(result);
  if (executionSummary) return executionSummary;

  const dispatchKind = safeString(result.dispatch?.kind);
  const actionName = safeString(result.command?.action_name || result.gate?.action_name);
  const routeMode = safeString(result.route?.route_mode || result.gate?.route_mode);
  const denyCode = safeString(result.gate?.deny_code || result.route?.deny_code);
  const resolvedDeviceId = safeString(result.route?.resolved_device_id);
  const projectId = projectIdFromResult(result);
  const auditRef = auditRefFromResult(result);

  return buildWhatsAppCloudSummaryMessage({
    delivery_context: deliveryContextFromResult(result),
    title: dispatchKind === 'deny' ? 'Command Denied' : (dispatchKind === 'route_blocked' ? 'Route Blocked' : (dispatchKind === 'xt_command' ? 'Command Routed' : (dispatchKind === 'hub_grant_action' ? 'Hub Approval Action Accepted' : 'Hub Query Accepted'))),
    status: classifyStatus(result),
    project_id: projectId,
    lines: [
      actionName ? `Action: ${actionName}` : '',
      routeMode ? `Route: ${routeMode}` : '',
      resolvedDeviceId ? `Device: ${resolvedDeviceId}` : '',
      denyCode ? `Reason: ${denyCode}` : '',
    ].filter(Boolean).length
      ? [
          actionName ? `Action: ${actionName}` : '',
          routeMode ? `Route: ${routeMode}` : '',
          resolvedDeviceId ? `Device: ${resolvedDeviceId}` : '',
          denyCode ? `Reason: ${denyCode}` : '',
        ].filter(Boolean)
      : ['WhatsApp Cloud operator command accepted by the governed Hub control path.'],
    audit_ref: auditRef,
  });
}

export function buildWhatsAppCloudGrantDecisionSummary({
  event = {},
  binding = {},
} = {}) {
  const grantRequestId = safeString(event.grant_request_id);
  const decision = safeString(event.decision || event.status);
  const projectId = safeString(event.project_id || event.scope_id || event.grant?.client?.project_id);
  return buildWhatsAppCloudSummaryMessage({
    delivery_context: bindingDeliveryContext(binding),
    title: decision === 'approved' ? 'Grant Approved' : 'Grant Rejected',
    status: decision === 'approved' ? 'grant_approved' : 'grant_denied',
    project_id: projectId,
    lines: [
      grantRequestId ? `Grant request: ${grantRequestId}` : '',
      safeString(event.reason) ? `Reason: ${safeString(event.reason)}` : '',
      safeString(event.note) ? `Note: ${safeString(event.note)}` : '',
    ].filter(Boolean),
    audit_ref: grantEventAuditRef(event),
  });
}

export function buildWhatsAppCloudGrantPendingSummary({
  event = {},
  binding = {},
} = {}) {
  const grantRequestId = safeString(event.grant_request_id);
  const projectId = safeString(event.project_id || event.scope_id);
  const capabilityLabel = safeString(event.required_capability || event.capability);
  return buildWhatsAppCloudApprovalMessage({
    delivery_context: bindingDeliveryContext(binding),
    title: 'Approval Required',
    summary_lines: [
      capabilityLabel ? `Capability: ${capabilityLabel}` : '',
      safeString(event.reason) ? `Reason: ${safeString(event.reason)}` : '',
    ].filter(Boolean),
    audit_ref: grantEventAuditRef(event),
    binding_id: safeString(binding.binding_id),
    scope_type: safeString(event.scope_type || 'project'),
    scope_id: safeString(event.scope_id || projectId),
    project_id: projectId,
    grant_request_id: grantRequestId,
    pending_grant_status: safeString(event.status || 'pending') || 'pending',
  });
}

export function createWhatsAppCloudResultPublisher({
  whatsapp_client = null,
} = {}) {
  if (!whatsapp_client || typeof whatsapp_client.postMessage !== 'function') {
    throw new Error('whatsapp_cloud_client_invalid');
  }

  async function publishPayload(message) {
    if (!message || message.ok !== true) {
      return {
        ok: false,
        deny_code: safeString(message?.deny_code || 'message_build_failed') || 'message_build_failed',
      };
    }
    const payload = safeObject(message.payload);
    const response = await whatsapp_client.postMessage({
      to: safeString(payload.to),
      text: safeString(payload.text),
      reply_to_message_id: safeString(payload.reply_to_message_id),
    });
    return {
      ok: true,
      payload,
      response,
    };
  }

  return {
    async publish(result) {
      return await publishPayload(buildWhatsAppCloudResultSummary(result));
    },
    async publishGrantDecision({ event, binding } = {}) {
      return await publishPayload(buildWhatsAppCloudGrantDecisionSummary({ event, binding }));
    },
    async publishGrantPending({ event, binding } = {}) {
      return await publishPayload(buildWhatsAppCloudGrantPendingSummary({ event, binding }));
    },
  };
}
