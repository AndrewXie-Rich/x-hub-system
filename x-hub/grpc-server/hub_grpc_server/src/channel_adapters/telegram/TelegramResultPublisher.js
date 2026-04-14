import {
  buildTelegramApprovalMessage,
  buildTelegramSummaryMessage,
} from './TelegramEgress.js';
import { buildOperatorChannelHeartbeatGovernanceSummaryLines } from '../operator_channel_heartbeat_governance_summary.js';

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

function projectionStatusLabel(input) {
  const raw = safeString(input).toLowerCase();
  if (!raw) return '';
  switch (raw) {
    case 'awaiting_authorization':
      return 'awaiting authorization';
    case 'attention_required':
      return 'attention required';
    default:
      return raw.replaceAll('_', ' ');
  }
}

function normalizeCapabilityLabel(input) {
  const raw = safeString(input).toUpperCase();
  if (!raw) return '';
  if (raw.startsWith('CAPABILITY_')) {
    return raw.slice('CAPABILITY_'.length).toLowerCase().replaceAll('_', '.');
  }
  return raw.toLowerCase();
}

function deliveryContextFromResult(result = {}) {
  const command = safeObject(result.command);
  const channel = safeObject(command.channel);
  return {
    provider: 'telegram',
    account_id: safeString(channel.account_id),
    conversation_id: safeString(channel.conversation_id),
    thread_key: safeString(channel.thread_key),
  };
}

function bindingDeliveryContext(binding = {}) {
  return {
    provider: 'telegram',
    account_id: safeString(binding.account_id),
    conversation_id: safeString(binding.conversation_id),
    thread_key: safeString(binding.thread_key),
  };
}

function auditRefFromResult(result = {}) {
  return safeString(
    result.command?.audit_ref
    || result.discovery_ticket?.audit_ref
    || result.request_id
    || result.route?.route_id
    || result.gate?.binding_id
  );
}

function projectIdFromResult(result = {}) {
  if (safeString(result.discovery_ticket?.proposed_scope_type) === 'project' && safeString(result.discovery_ticket?.proposed_scope_id)) {
    return safeString(result.discovery_ticket.proposed_scope_id);
  }
  if (safeString(result.execution?.projection?.project_id)) return safeString(result.execution.projection.project_id);
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
  const dispatchKind = safeString(result.dispatch?.kind);
  if (dispatchKind === 'discovery_ticket') return 'access_pending_approval';

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

    const projection = safeObject(execution.projection);
    const queryAction = safeString(execution.query?.action_name || result.command?.action_name || result.gate?.action_name);
    if (Object.keys(projection).length && queryAction === 'supervisor.status.get') return 'supervisor_status';
    if (queryAction === 'supervisor.status.get') return 'supervisor_status';
    if (queryAction === 'supervisor.blockers.get') return 'supervisor_blockers';
    if (queryAction === 'supervisor.queue.get') return 'supervisor_queue';
  }

  if (dispatchKind === 'deny') return 'denied';
  if (dispatchKind === 'route_blocked') return 'route_blocked';
  if (dispatchKind === 'xt_command') return 'routed_to_xt';
  if (dispatchKind === 'runner_command') return 'routed_to_runner';
  if (dispatchKind === 'hub_grant_action') return 'hub_action';
  return 'hub_query';
}

function buildTelegramDiscoverySummary(result = {}) {
  const ticket = safeObject(result.discovery_ticket);
  if (!safeString(ticket.ticket_id)) return null;
  const actionName = safeString(result.command?.action_name || result.gate?.action_name);
  const scopeHint = safeString(ticket.proposed_scope_type) && safeString(ticket.proposed_scope_id)
    ? `${safeString(ticket.proposed_scope_type)}/${safeString(ticket.proposed_scope_id)}`
    : '';
  return buildTelegramSummaryMessage({
    delivery_context: deliveryContextFromResult(result),
    title: 'Access Pending Approval',
    status: classifyStatus(result),
    project_id: projectIdFromResult(result),
    lines: [
      'This Telegram conversation is not bound to a governed operator scope yet.',
      actionName ? `Requested action: ${actionName}` : '',
      safeString(ticket.ticket_id) ? `Ticket: ${safeString(ticket.ticket_id)}` : '',
      scopeHint ? `Scope hint: ${scopeHint}` : '',
      safeString(ticket.recommended_binding_mode) ? `Binding mode: ${safeString(ticket.recommended_binding_mode)}` : '',
      'A local Hub admin needs to approve this channel once before commands can run.',
    ].filter(Boolean),
    audit_ref: safeString(ticket.audit_ref || auditRefFromResult(result)),
  });
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
  const projection = safeObject(execution.projection);
  const grantAction = safeObject(execution.grant_action);
  const xtCommand = safeObject(execution.xt_command);
  const heartbeat = safeObject(query.heartbeat);
  const heartbeatGovernanceLines = buildOperatorChannelHeartbeatGovernanceSummaryLines(query.heartbeat_governance_snapshot_json);
  const dispatch = safeObject(query.dispatch);
  const queue = safeObject(query.queue);
  const providerStatus = safeObject(query.provider_status);
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
    return buildTelegramSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title: xtStatus === 'queued' ? 'XT Command Queued' : (xtStatus === 'prepared' || xtStatus === 'completed' || xtStatus === 'accepted' ? 'XT Command Prepared' : 'XT Command Failed'),
      status: classifyStatus(result),
      project_id: safeString(xtCommand.project_id || projectId),
      lines: [
        actionName ? `Action: ${actionName}` : '',
        routeMode ? `Route: ${routeMode}` : '',
        safeString(xtCommand.resolved_device_id || resolvedDeviceId) ? `Device: ${safeString(xtCommand.resolved_device_id || resolvedDeviceId)}` : '',
        safeString(xtCommand.command_id) ? `Command: ${safeString(xtCommand.command_id)}` : '',
        safeString(xtCommand.run_id) ? `Run: ${safeString(xtCommand.run_id)}` : '',
        xtStatus ? `State: ${xtStatus}` : '',
        safeString(xtCommand.deny_code || denyCode) ? `Reason: ${safeString(xtCommand.deny_code || denyCode)}` : '',
        safeString(xtCommand.detail || execution.detail) ? `Detail: ${safeString(xtCommand.detail || execution.detail)}` : '',
      ].filter(Boolean),
      audit_ref: safeString(xtCommand.audit_ref || auditRef),
    });
  }

  if (Object.keys(projection).length) {
    const projectionStatus = projectionStatusLabel(projection.status);
    const topline = safeString(projection.topline);
    const criticalBlocker = safeString(projection.critical_blocker);
    const nextBestAction = safeString(projection.next_best_action);
    const cardSummary = safeString(projection.card_summary);
    const pendingGrantCount = safeInt(projection.pending_grant_count, 0);
    return buildTelegramSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title: 'Supervisor Status',
      status: classifyStatus(result),
      project_id: safeString(projection.project_id || projectId),
      lines: [
        actionName ? `Action: ${actionName}` : '',
        projectionStatus ? `Project state: ${projectionStatus}` : '',
        topline ? `Topline: ${topline}` : '',
        criticalBlocker ? `Blocker: ${criticalBlocker}` : '',
        nextBestAction ? `Next: ${nextBestAction}` : '',
        `Pending grants: ${pendingGrantCount}`,
        cardSummary && cardSummary !== topline ? `Summary: ${cardSummary}` : '',
        routeMode ? `Route: ${routeMode}` : '',
        resolvedDeviceId ? `Device: ${resolvedDeviceId}${route.xt_online === true ? ' (online)' : ''}` : '',
      ].filter(Boolean),
      audit_ref: safeString(projection.audit_ref || auditRef),
    });
  }

  if (execution.ok === false) {
    return buildTelegramSummaryMessage({
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
    return buildTelegramSummaryMessage({
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
      safeString(query.root_project_id) && safeString(query.root_project_id) !== projectId ? `Root project: ${safeString(query.root_project_id)}` : '',
      safeString(dispatch.assigned_agent_profile) ? `Dispatch: ${safeString(dispatch.assigned_agent_profile)} priority=${safeInt(dispatch.queue_priority)}` : '',
      Object.keys(heartbeat).length ? `Heartbeat: queue_depth=${safeInt(heartbeat.queue_depth)} wait_ms=${safeInt(heartbeat.oldest_wait_ms)} risk=${safeString(heartbeat.risk_tier || 'unknown') || 'unknown'}` : 'Heartbeat: no live project heartbeat',
      ...heartbeatGovernanceLines,
      safeString(providerStatus.runtime_state) ? `Channel runtime: ${safeString(providerStatus.runtime_state)}` : '',
    ].filter(Boolean);

    if (actionName === 'supervisor.blockers.get') {
      const blockers = safeArray(heartbeat.blocked_reason).map((item) => safeString(item)).filter(Boolean);
      const nextActions = safeArray(heartbeat.next_actions).map((item) => safeString(item)).filter(Boolean);
      lines.push(blockers.length ? `Blockers: ${blockers.join('; ')}` : 'Blockers: none reported');
      if (nextActions.length) lines.push(`Next actions: ${nextActions.join('; ')}`);
    }

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

    return buildTelegramSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title: actionName === 'supervisor.blockers.get' ? 'Supervisor Blockers' : (actionName === 'supervisor.queue.get' ? 'Supervisor Queue' : 'Supervisor Status'),
      status: classifyStatus(result),
      project_id: projectId,
      lines,
      audit_ref: auditRef,
    });
  }

  return null;
}

export function buildTelegramResultSummary(result = {}) {
  const discoverySummary = buildTelegramDiscoverySummary(result);
  if (discoverySummary) return discoverySummary;

  const executionSummary = buildExecutionSummary(result);
  if (executionSummary) return executionSummary;

  const dispatchKind = safeString(result.dispatch?.kind);
  const actionName = safeString(result.command?.action_name || result.gate?.action_name);
  const routeMode = safeString(result.route?.route_mode || result.gate?.route_mode);
  const denyCode = safeString(result.gate?.deny_code || result.route?.deny_code);
  const resolvedDeviceId = safeString(result.route?.resolved_device_id);
  const projectId = projectIdFromResult(result);
  const auditRef = auditRefFromResult(result);

  return buildTelegramSummaryMessage({
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
      : ['Telegram operator command accepted by the governed Hub control path.'],
    audit_ref: auditRef,
  });
}

export function buildTelegramGrantDecisionSummary({
  event = {},
  binding = {},
} = {}) {
  const grant = safeObject(event.grant);
  const client = safeObject(event.client || grant.client);
  const decision = safeString(event.decision).toUpperCase();
  if (decision !== 'GRANT_DECISION_APPROVED' && decision !== 'GRANT_DECISION_DENIED') {
    return {
      ok: false,
      deny_code: 'grant_decision_unsupported',
    };
  }

  const projectId = safeString(event.project_id || grant.client?.project_id || client.project_id);
  const capability = normalizeCapabilityLabel(grant.capability);
  const resolvedDeviceId = safeString(grant.client?.device_id || client.device_id);
  const denyReason = safeString(event.deny_reason);
  const status = decision === 'GRANT_DECISION_APPROVED' ? 'grant_approved' : 'grant_denied';
  const title = decision === 'GRANT_DECISION_APPROVED' ? 'Grant Approved' : 'Grant Rejected';

  return buildTelegramSummaryMessage({
    delivery_context: bindingDeliveryContext(binding),
    title,
    status,
    project_id: projectId,
    lines: [
      safeString(event.grant_request_id) ? `Grant request: ${safeString(event.grant_request_id)}` : '',
      capability ? `Capability: ${capability}` : '',
      resolvedDeviceId ? `Device: ${resolvedDeviceId}` : '',
      safeString(grant.grant_id) ? `Grant: ${safeString(grant.grant_id)}` : '',
      safeInt(grant.expires_at_ms) > 0 ? `Expires at ms: ${safeInt(grant.expires_at_ms)}` : '',
      denyReason ? `Reason: ${denyReason}` : '',
      safeString(event.event_id) ? `Event: ${safeString(event.event_id)}` : '',
    ].filter(Boolean),
    audit_ref: grantEventAuditRef(event),
  });
}

export function buildTelegramGrantPendingMessage({
  event = {},
  binding = {},
} = {}) {
  const decision = safeString(event.decision).toUpperCase();
  if (decision !== 'GRANT_DECISION_QUEUED') {
    return {
      ok: false,
      deny_code: 'grant_pending_unsupported',
    };
  }
  const grant = safeObject(event.grant);
  const client = safeObject(event.client || grant.client);
  const projectId = safeString(event.project_id || grant.client?.project_id || client.project_id);
  const capability = normalizeCapabilityLabel(grant.capability);
  const resolvedDeviceId = safeString(grant.client?.device_id || client.device_id);
  const modelId = safeString(grant.model_id);
  const requestedTokenCap = safeInt(grant.token_cap, 0);

  return buildTelegramApprovalMessage({
    delivery_context: bindingDeliveryContext(binding),
    title: 'Approval Required',
    summary_lines: [
      safeString(event.grant_request_id) ? `Grant request: ${safeString(event.grant_request_id)}` : '',
      capability ? `Capability: ${capability}` : '',
      modelId ? `Model: ${modelId}` : '',
      resolvedDeviceId ? `Device: ${resolvedDeviceId}` : '',
      requestedTokenCap > 0 ? `Requested token cap: ${requestedTokenCap}` : '',
      safeString(event.event_id) ? `Event: ${safeString(event.event_id)}` : '',
    ].filter(Boolean),
    audit_ref: grantEventAuditRef(event),
    binding_id: safeString(binding.binding_id),
    scope_type: safeString(binding.scope_type || 'project') || 'project',
    scope_id: safeString(binding.scope_id || projectId),
    project_id: projectId,
    grant_request_id: safeString(event.grant_request_id),
    pending_grant_status: 'pending',
  });
}

export async function publishTelegramCommandResult({
  result = {},
  telegram_client = null,
  summary_builder = buildTelegramResultSummary,
} = {}) {
  if (!telegram_client || typeof telegram_client.postMessage !== 'function') {
    return {
      ok: false,
      deny_code: 'telegram_client_invalid',
    };
  }
  const summary = summary_builder(result);
  if (!summary.ok) return summary;
  const delivered = await telegram_client.postMessage(summary.payload);
  return {
    ok: true,
    payload: summary.payload,
    delivery_context: summary.delivery_context,
    delivered,
  };
}

export async function publishTelegramGrantDecision({
  event = {},
  binding = {},
  telegram_client = null,
  summary_builder = buildTelegramGrantDecisionSummary,
} = {}) {
  if (!telegram_client || typeof telegram_client.postMessage !== 'function') {
    return {
      ok: false,
      deny_code: 'telegram_client_invalid',
    };
  }
  const summary = summary_builder({
    event,
    binding,
  });
  if (!summary.ok) return summary;
  const delivered = await telegram_client.postMessage(summary.payload);
  return {
    ok: true,
    payload: summary.payload,
    delivery_context: summary.delivery_context,
    delivered,
  };
}

export async function publishTelegramGrantPending({
  event = {},
  binding = {},
  telegram_client = null,
  summary_builder = buildTelegramGrantPendingMessage,
} = {}) {
  if (!telegram_client || typeof telegram_client.postMessage !== 'function') {
    return {
      ok: false,
      deny_code: 'telegram_client_invalid',
    };
  }
  const summary = summary_builder({
    event,
    binding,
  });
  if (!summary.ok) return summary;
  const delivered = await telegram_client.postMessage(summary.payload);
  return {
    ok: true,
    payload: summary.payload,
    delivery_context: summary.delivery_context,
    delivered,
  };
}

export function createTelegramResultPublisher({
  telegram_client = null,
  summary_builder = buildTelegramResultSummary,
  grant_summary_builder = buildTelegramGrantDecisionSummary,
  grant_pending_builder = buildTelegramGrantPendingMessage,
} = {}) {
  return {
    build(result) {
      return summary_builder(result);
    },
    buildGrantDecision({ event = {}, binding = {} } = {}) {
      return grant_summary_builder({
        event,
        binding,
      });
    },
    buildGrantPending({ event = {}, binding = {} } = {}) {
      return grant_pending_builder({
        event,
        binding,
      });
    },
    async publish(result) {
      return await publishTelegramCommandResult({
        result,
        telegram_client,
        summary_builder,
      });
    },
    async publishGrantDecision({ event = {}, binding = {} } = {}) {
      return await publishTelegramGrantDecision({
        event,
        binding,
        telegram_client,
        summary_builder: grant_summary_builder,
      });
    },
    async publishGrantPending({ event = {}, binding = {} } = {}) {
      return await publishTelegramGrantPending({
        event,
        binding,
        telegram_client,
        summary_builder: grant_pending_builder,
      });
    },
  };
}
