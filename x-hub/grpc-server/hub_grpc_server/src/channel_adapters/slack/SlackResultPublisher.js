import { buildSlackSummaryMessage } from './SlackEgress.js';

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
    provider: 'slack',
    account_id: safeString(channel.account_id),
    conversation_id: safeString(channel.conversation_id),
    thread_key: safeString(channel.thread_key),
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
    if (queryAction === 'supervisor.blockers.get') return 'supervisor_blockers';
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

function buildExecutionSummary(result = {}) {
  const execution = safeObject(result.execution);
  if (!Object.keys(execution).length) return null;

  const route = safeObject(execution.route);
  const query = safeObject(execution.query);
  const grantAction = safeObject(execution.grant_action);
  const xtCommand = safeObject(execution.xt_command);
  const heartbeat = safeObject(query.heartbeat);
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
    const title = (() => {
      if (xtStatus === 'prepared' || xtStatus === 'completed' || xtStatus === 'accepted') return 'XT Command Prepared';
      if (xtStatus === 'queued') return 'XT Command Queued';
      return 'XT Command Failed';
    })();
    return buildSlackSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title,
      status: classifyStatus(result),
      project_id: safeString(xtCommand.project_id || projectId),
      lines: [
        actionName ? `Action: ${actionName}` : '',
        routeMode ? `Route: ${routeMode}` : '',
        safeString(xtCommand.resolved_device_id || resolvedDeviceId)
          ? `Device: ${safeString(xtCommand.resolved_device_id || resolvedDeviceId)}`
          : '',
        safeString(xtCommand.command_id) ? `Command: ${safeString(xtCommand.command_id)}` : '',
        safeString(xtCommand.run_id) ? `Run: ${safeString(xtCommand.run_id)}` : '',
        xtStatus ? `State: ${xtStatus}` : '',
        safeString(xtCommand.deny_code || denyCode) ? `Reason: ${safeString(xtCommand.deny_code || denyCode)}` : '',
        safeString(xtCommand.detail || execution.detail) ? `Detail: ${safeString(xtCommand.detail || execution.detail)}` : '',
      ].filter(Boolean),
      fields: [
        actionName ? { label: 'Action', value: actionName } : null,
        safeString(xtCommand.resolved_device_id || resolvedDeviceId)
          ? { label: 'Device', value: safeString(xtCommand.resolved_device_id || resolvedDeviceId) }
          : null,
        xtStatus ? { label: 'State', value: xtStatus } : null,
        safeString(xtCommand.run_id) ? { label: 'Run', value: safeString(xtCommand.run_id) } : null,
      ].filter(Boolean),
      audit_ref: safeString(xtCommand.audit_ref || auditRef),
      reply_broadcast: false,
    });
  }

  if (execution.ok === false) {
    return buildSlackSummaryMessage({
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
      fields: [
        actionName ? { label: 'Action', value: actionName } : null,
        routeMode ? { label: 'Route', value: routeMode } : null,
        resolvedDeviceId ? { label: 'Device', value: resolvedDeviceId } : null,
        denyCode ? { label: 'Reason', value: denyCode } : null,
      ].filter(Boolean),
      audit_ref: auditRef,
      reply_broadcast: false,
    });
  }

  if (Object.keys(grantAction).length) {
    const grant = safeObject(grantAction.grant);
    const title = safeString(grantAction.decision) === 'approved' ? 'Grant Approved' : 'Grant Rejected';
    return buildSlackSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title,
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
      fields: [
        actionName ? { label: 'Action', value: actionName } : null,
        safeString(grantAction.grant_request_id) ? { label: 'Request', value: safeString(grantAction.grant_request_id) } : null,
        safeString(grant.grant_id) ? { label: 'Grant', value: safeString(grant.grant_id) } : null,
        safeString(grant.status) ? { label: 'Status', value: safeString(grant.status) } : null,
      ].filter(Boolean),
      audit_ref: auditRef,
      reply_broadcast: false,
    });
  }

  if (Object.keys(query).length) {
    const title = (() => {
      if (actionName === 'supervisor.blockers.get') return 'Supervisor Blockers';
      if (actionName === 'supervisor.queue.get') return 'Supervisor Queue';
      return 'Supervisor Status';
    })();
    const lines = [
      actionName ? `Action: ${actionName}` : '',
      routeMode ? `Route: ${routeMode}` : '',
      resolvedDeviceId ? `Device: ${resolvedDeviceId}${route.xt_online === true ? ' (online)' : ''}` : '',
      safeString(query.root_project_id) && safeString(query.root_project_id) !== projectId
        ? `Root project: ${safeString(query.root_project_id)}`
        : '',
      safeString(dispatch.assigned_agent_profile)
        ? `Dispatch: ${safeString(dispatch.assigned_agent_profile)} priority=${safeInt(dispatch.queue_priority)}`
        : '',
      Object.keys(heartbeat).length
        ? `Heartbeat: queue_depth=${safeInt(heartbeat.queue_depth)} wait_ms=${safeInt(heartbeat.oldest_wait_ms)} risk=${safeString(heartbeat.risk_tier || 'unknown') || 'unknown'}`
        : 'Heartbeat: no live project heartbeat',
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
            lines.push(
              `Queue item: ${safeString(item.project_id)} depth=${safeInt(item.queue_depth)} wait_ms=${safeInt(item.oldest_wait_ms)} risk=${safeString(item.risk_tier || 'unknown') || 'unknown'}`
            );
          }
        }
      } else {
        lines.push(`Queue unavailable: ${safeString(queue.deny_code || 'queue_view_unavailable')}`);
      }
    }

    return buildSlackSummaryMessage({
      delivery_context: deliveryContextFromResult(result),
      title,
      status: classifyStatus(result),
      project_id: projectId,
      lines,
      fields: [
        actionName ? { label: 'Action', value: actionName } : null,
        routeMode ? { label: 'Route', value: routeMode } : null,
        resolvedDeviceId ? { label: 'Device', value: resolvedDeviceId } : null,
        safeString(heartbeat.risk_tier) ? { label: 'Risk', value: safeString(heartbeat.risk_tier) } : null,
        safeString(queue.batch_id) ? { label: 'Batch', value: safeString(queue.batch_id) } : null,
      ].filter(Boolean),
      audit_ref: auditRef,
      reply_broadcast: false,
    });
  }

  return null;
}

export function buildSlackResultSummary(result = {}) {
  const executionSummary = buildExecutionSummary(result);
  if (executionSummary) return executionSummary;

  const dispatchKind = safeString(result.dispatch?.kind);
  const actionName = safeString(result.command?.action_name || result.gate?.action_name);
  const routeMode = safeString(result.route?.route_mode || result.gate?.route_mode);
  const denyCode = safeString(result.gate?.deny_code || result.route?.deny_code);
  const resolvedDeviceId = safeString(result.route?.resolved_device_id);
  const projectId = projectIdFromResult(result);
  const auditRef = auditRefFromResult(result);

  const title = (() => {
    if (dispatchKind === 'deny') return 'Command Denied';
    if (dispatchKind === 'route_blocked') return 'Route Blocked';
    if (dispatchKind === 'xt_command') return 'Command Routed';
    if (dispatchKind === 'runner_command') return 'Runner Command Routed';
    if (dispatchKind === 'hub_grant_action') return 'Hub Approval Action Accepted';
    return 'Hub Query Accepted';
  })();

  const lines = [
    actionName ? `Action: ${actionName}` : '',
    routeMode ? `Route: ${routeMode}` : '',
    resolvedDeviceId ? `Device: ${resolvedDeviceId}` : '',
    denyCode ? `Reason: ${denyCode}` : '',
  ].filter(Boolean);
  if (!lines.length) {
    lines.push('Slack operator command accepted by the governed Hub control path.');
  }

  return buildSlackSummaryMessage({
    delivery_context: deliveryContextFromResult(result),
    title,
    status: classifyStatus(result),
    project_id: projectId,
    lines,
    fields: [
      actionName ? { label: 'Action', value: actionName } : null,
      routeMode ? { label: 'Route', value: routeMode } : null,
      resolvedDeviceId ? { label: 'Device', value: resolvedDeviceId } : null,
      denyCode ? { label: 'Reason', value: denyCode } : null,
    ].filter(Boolean),
    audit_ref: auditRef,
    reply_broadcast: false,
  });
}

export async function publishSlackCommandResult({
  result = {},
  slack_client = null,
  summary_builder = buildSlackResultSummary,
} = {}) {
  if (!slack_client || typeof slack_client.postMessage !== 'function') {
    return {
      ok: false,
      deny_code: 'slack_client_invalid',
    };
  }
  const summary = summary_builder(result);
  if (!summary.ok) return summary;
  const delivered = await slack_client.postMessage(summary.payload);
  return {
    ok: true,
    payload: summary.payload,
    delivery_context: summary.delivery_context,
    delivered,
  };
}

export function createSlackResultPublisher({
  slack_client = null,
  summary_builder = buildSlackResultSummary,
} = {}) {
  return {
    build(result) {
      return summary_builder(result);
    },
    async publish(result) {
      return await publishSlackCommandResult({
        result,
        slack_client,
        summary_builder,
      });
    },
  };
}
