function safeString(input) {
  return String(input ?? '').trim();
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function shouldCreateDiscoveryTicket(gate = {}) {
  const denyCode = safeString(gate.deny_code);
  return denyCode === 'identity_binding_missing' || denyCode === 'channel_binding_missing';
}

function buildDiscoveryTicketDraft(command = {}) {
  const actor = safeObject(command.actor);
  const channel = safeObject(command.channel);
  const pendingGrant = safeObject(command.pending_grant);
  const proposedScopeId = safeString(
    (safeString(command.scope_type).toLowerCase() === 'project' ? command.scope_id : '')
    || pendingGrant.project_id
    || command.route_project_id
  );
  return {
    provider: safeString(channel.provider || actor.provider),
    account_id: safeString(channel.account_id),
    external_user_id: safeString(actor.external_user_id),
    external_tenant_id: safeString(actor.external_tenant_id || channel.account_id),
    conversation_id: safeString(channel.conversation_id),
    thread_key: safeString(channel.thread_key),
    ingress_surface: safeString(channel.channel_scope || 'group'),
    first_message_preview: safeString(command.action_name),
    proposed_scope_type: proposedScopeId ? 'project' : safeString(command.scope_type || ''),
    proposed_scope_id: proposedScopeId,
    recommended_binding_mode: safeString(channel.thread_key) ? 'thread_binding' : 'conversation_binding',
  };
}

export function classifyOperatorChannelCommandDispatch({
  gate = {},
  route = {},
  action_name = '',
} = {}) {
  const normalizedAction = safeString(action_name || gate.action_name).toLowerCase();
  if (safeString(route.route_mode) === 'discovery_ticket') {
    return {
      kind: 'discovery_ticket',
      execute_via: 'none',
      terminal: true,
    };
  }
  if (gate && gate.allowed === false) {
    return {
      kind: 'deny',
      execute_via: 'none',
      terminal: true,
    };
  }

  const route_mode = safeString(route.route_mode || gate.route_mode || 'hub_only_status');
  if (route_mode === 'hub_to_xt') {
    return {
      kind: 'xt_command',
      execute_via: 'xt',
      terminal: false,
    };
  }
  if (route_mode === 'hub_to_runner') {
    return {
      kind: 'runner_command',
      execute_via: 'runner',
      terminal: false,
    };
  }
  if (route_mode === 'xt_offline' || route_mode === 'runner_not_ready') {
    return {
      kind: 'route_blocked',
      execute_via: 'none',
      terminal: true,
    };
  }
  if (normalizedAction === 'grant.approve' || normalizedAction === 'grant.reject') {
    return {
      kind: 'hub_grant_action',
      execute_via: 'hub',
      terminal: false,
    };
  }
  return {
    kind: 'hub_query',
    execute_via: 'hub',
    terminal: false,
  };
}

export async function orchestrateOperatorChannelCommand({
  input = {},
  normalize_input = null,
  hub_client = null,
  now_fn = Date.now,
} = {}) {
  if (typeof normalize_input !== 'function') {
    return {
      ok: false,
      deny_code: 'normalize_input_invalid',
      retryable: false,
    };
  }

  const now_ms = typeof now_fn === 'function' ? Number(now_fn()) : Date.now();
  const command = normalize_input(input, { now_ms });
  if (!command || command.ok !== true) return command;

  if (
    !hub_client
    || typeof hub_client.evaluateChannelCommandGate !== 'function'
    || typeof hub_client.resolveSupervisorChannelRoute !== 'function'
  ) {
    return {
      ok: false,
      deny_code: 'hub_client_invalid',
      retryable: false,
      request_id: safeString(command.request_id),
      command,
    };
  }

  let gateResponse;
  try {
    gateResponse = await hub_client.evaluateChannelCommandGate({
      request_id: command.request_id,
      actor: command.actor,
      channel: command.channel,
      binding_id: command.binding_id,
      action_name: command.action_name,
      scope_type: command.scope_type,
      scope_id: command.scope_id,
      pending_grant: command.pending_grant,
    });
  } catch (error) {
    return {
      ok: false,
      deny_code: 'gate_rpc_failed',
      retryable: true,
      request_id: safeString(command.request_id),
      command,
      detail: safeString(error?.message || 'gate_rpc_failed'),
    };
  }

  const gate = safeObject(gateResponse.decision);
  if (gate.allowed === false) {
    if (
      shouldCreateDiscoveryTicket(gate)
      && hub_client
      && typeof hub_client.createOrTouchChannelOnboardingDiscoveryTicket === 'function'
    ) {
      let discoveryResponse;
      try {
        discoveryResponse = await hub_client.createOrTouchChannelOnboardingDiscoveryTicket(
          buildDiscoveryTicketDraft(command),
          command.request_id
        );
      } catch (error) {
        return {
          ok: false,
          deny_code: 'discovery_ticket_rpc_failed',
          retryable: true,
          request_id: safeString(command.request_id),
          command,
          gate,
          detail: safeString(error?.message || 'discovery_ticket_rpc_failed'),
        };
      }

      if (!discoveryResponse || discoveryResponse.ok !== true) {
        return {
          ok: false,
          deny_code: safeString(discoveryResponse?.deny_code || 'discovery_ticket_rejected'),
          retryable: safeString(discoveryResponse?.deny_code) === 'audit_write_failed',
          request_id: safeString(command.request_id),
          command,
          gate,
        };
      }

      const discoveryTicket = safeObject(discoveryResponse.ticket);
      return {
        ok: true,
        request_id: safeString(command.request_id),
        command,
        gate,
        route: {
          route_mode: 'discovery_ticket',
        },
        discovery_ticket: discoveryTicket,
        gate_audit_logged: gateResponse.audit_logged === true,
        discovery_audit_logged: discoveryResponse.audit_logged === true,
        discovery_created: discoveryResponse.created === true,
        discovery_updated: discoveryResponse.updated === true,
        dispatch: {
          kind: 'discovery_ticket',
          execute_via: 'none',
          terminal: true,
        },
      };
    }
    return {
      ok: true,
      request_id: safeString(command.request_id),
      command,
      gate,
      route: null,
      audit_logged: gateResponse.audit_logged === true,
      dispatch: classifyOperatorChannelCommandDispatch({
        gate,
        action_name: command.action_name,
      }),
    };
  }

  let routeResponse;
  try {
    routeResponse = await hub_client.resolveSupervisorChannelRoute({
      request_id: command.request_id,
      binding_id: safeString(gate.binding_id || command.binding_id),
      channel: command.channel,
      action_name: safeString(gate.action_name || command.action_name),
      project_id: safeString(
        (safeString(gate.scope_type) === 'project' ? gate.scope_id : '')
        || command.route_project_id
      ),
      root_project_id: '',
    });
  } catch (error) {
    return {
      ok: false,
      deny_code: 'route_rpc_failed',
      retryable: true,
      request_id: safeString(command.request_id),
      command,
      gate,
      detail: safeString(error?.message || 'route_rpc_failed'),
    };
  }

  const route = safeObject(routeResponse.route);
  return {
    ok: true,
    request_id: safeString(command.request_id),
    command,
    gate,
    route,
    gate_audit_logged: gateResponse.audit_logged === true,
    route_audit_logged: routeResponse.audit_logged === true,
    route_created: routeResponse.created === true,
    route_updated: routeResponse.updated === true,
    dispatch: classifyOperatorChannelCommandDispatch({
      gate,
      route,
      action_name: command.action_name,
    }),
  };
}

export function createOperatorChannelCommandOrchestrator({
  normalize_input = null,
  hub_client = null,
  now_fn = Date.now,
} = {}) {
  return {
    normalize(input) {
      if (typeof normalize_input !== 'function') {
        return {
          ok: false,
          deny_code: 'normalize_input_invalid',
          retryable: false,
        };
      }
      return normalize_input(input, {
        now_ms: typeof now_fn === 'function' ? Number(now_fn()) : Date.now(),
      });
    },
    async handle(input) {
      return await orchestrateOperatorChannelCommand({
        input,
        normalize_input,
        hub_client,
        now_fn,
      });
    },
  };
}
