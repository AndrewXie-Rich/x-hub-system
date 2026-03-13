function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
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
    grant_action: safeObject(out.grant_action),
    xt_command: safeObject(out.xt_command),
    audit_logged: out.audit_logged === true,
  };
}

export function buildTelegramHubActionExecutionRequest(result = {}) {
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

export async function executeTelegramHubAction({
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

  if (!hub_client || typeof hub_client.executeOperatorChannelHubCommand !== 'function') {
    return {
      ...result,
      execution: {
        ok: false,
        deny_code: 'hub_client_invalid',
        detail: 'hub execution client missing',
        gate: {},
        route: {},
        query: {},
        grant_action: {},
        audit_logged: false,
      },
    };
  }

  const request = buildTelegramHubActionExecutionRequest(result);
  try {
    const response = await hub_client.executeOperatorChannelHubCommand(request);
    return {
      ...result,
      execution: normalizeExecutionResponse(response),
    };
  } catch (error) {
    return {
      ...result,
      execution: {
        ok: false,
        deny_code: 'hub_execution_rpc_failed',
        detail: safeString(error?.message || 'hub_execution_rpc_failed') || 'hub_execution_rpc_failed',
        gate: {},
        route: {},
        query: {},
        grant_action: {},
        audit_logged: false,
      },
    };
  }
}

export function createTelegramHubActionExecutor({
  hub_client = null,
} = {}) {
  return {
    buildRequest(result) {
      return buildTelegramHubActionExecutionRequest(result);
    },
    async execute(result) {
      return await executeTelegramHubAction({
        result,
        hub_client,
      });
    },
  };
}
