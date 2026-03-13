function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function makeExecutionFailure({
  deny_code = '',
  detail = '',
} = {}) {
  return {
    ok: false,
    deny_code: safeString(deny_code),
    detail: safeString(detail),
    gate: {},
    route: {},
    query: {},
    projection: {},
    grant_action: {},
    xt_command: {},
    audit_logged: false,
  };
}

function projectIdFromResult(result = {}) {
  const command = safeObject(result.command);
  if (safeString(command.scope_type) === 'project' && safeString(command.scope_id)) {
    return safeString(command.scope_id);
  }
  if (safeString(command.route_project_id)) return safeString(command.route_project_id);
  if (safeString(command.pending_grant?.project_id)) return safeString(command.pending_grant.project_id);
  return '';
}

function normalizeExecutionResponse(response = {}) {
  const out = safeObject(response);
  return {
    ok: out.ok === true,
    deny_code: safeString(out.deny_code),
    detail: safeString(out.detail),
    gate: safeObject(out.gate),
    route: safeObject(out.route),
    query: safeObject(out.query),
    projection: safeObject(out.projection),
    grant_action: safeObject(out.grant_action),
    xt_command: safeObject(out.xt_command),
    audit_logged: out.audit_logged === true,
  };
}

function shouldUseSupervisorBriefProjection(result = {}) {
  return (
    safeString(result.dispatch?.kind) === 'hub_query'
    && safeString(result.command?.action_name).toLowerCase() === 'supervisor.status.get'
    && !!projectIdFromResult(result)
  );
}

export function buildSlackHubActionExecutionRequest(result = {}) {
  const command = safeObject(result.command);
  return {
    request_id: safeString(result.request_id),
    actor: safeObject(command.actor),
    channel: safeObject(command.channel),
    binding_id: safeString(command.binding_id),
    action_name: safeString(command.action_name),
    scope_type: safeString(command.scope_type),
    scope_id: safeString(command.scope_id),
    pending_grant: command.pending_grant || null,
    note: safeString(command.note),
  };
}

export function buildSlackSupervisorBriefProjectionRequest(result = {}) {
  return {
    request_id: safeString(result.request_id),
    project_id: projectIdFromResult(result),
    projection_kind: 'progress_brief',
    trigger: 'user_query',
    include_card_summary: true,
    include_tts_script: false,
    max_evidence_refs: 4,
  };
}

export async function executeSlackHubAction({
  result = {},
  hub_client = null,
} = {}) {
  const dispatchKind = safeString(result.dispatch?.kind);
  if (dispatchKind !== 'hub_query' && dispatchKind !== 'hub_grant_action' && dispatchKind !== 'xt_command') {
    return {
      ...result,
      execution: null,
    };
  }

  if (shouldUseSupervisorBriefProjection(result)) {
    if (!hub_client || typeof hub_client.getSupervisorBriefProjection !== 'function') {
      return {
        ...result,
        execution: makeExecutionFailure({
          deny_code: 'hub_client_invalid',
          detail: 'hub supervisor projection client missing',
        }),
      };
    }

    const request = buildSlackSupervisorBriefProjectionRequest(result);
    try {
      const response = await hub_client.getSupervisorBriefProjection(request);
      return {
        ...result,
        execution: normalizeExecutionResponse(response),
      };
    } catch (error) {
      return {
        ...result,
        execution: makeExecutionFailure({
          deny_code: 'hub_execution_rpc_failed',
          detail: safeString(error?.message || 'hub_execution_rpc_failed') || 'hub_execution_rpc_failed',
        }),
      };
    }
  }

  if (!hub_client || typeof hub_client.executeOperatorChannelHubCommand !== 'function') {
    return {
      ...result,
      execution: makeExecutionFailure({
        deny_code: 'hub_client_invalid',
        detail: 'hub execution client missing',
      }),
    };
  }

  const request = buildSlackHubActionExecutionRequest(result);
  try {
    const response = await hub_client.executeOperatorChannelHubCommand(request);
    return {
      ...result,
      execution: normalizeExecutionResponse(response),
    };
  } catch (error) {
    return {
      ...result,
      execution: makeExecutionFailure({
        deny_code: 'hub_execution_rpc_failed',
        detail: safeString(error?.message || 'hub_execution_rpc_failed') || 'hub_execution_rpc_failed',
      }),
    };
  }
}

export function createSlackHubActionExecutor({
  hub_client = null,
} = {}) {
  return {
    buildRequest(result) {
      return buildSlackHubActionExecutionRequest(result);
    },
    async execute(result) {
      return await executeSlackHubAction({
        result,
        hub_client,
      });
    },
  };
}
