import { normalizeChannelProviderId } from '../../channel_registry.js';

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

function normalizeSlackActor(input = {}) {
  const actor = safeObject(input);
  return {
    provider: 'slack',
    external_user_id: safeString(actor.external_user_id || actor.user_id || actor.id),
    external_tenant_id: safeString(actor.external_tenant_id || actor.tenant_id || actor.team_id),
  };
}

function normalizeSlackChannel(input = {}) {
  const channel = safeObject(input);
  const provider = normalizeChannelProviderId(channel.provider || 'slack');
  return {
    provider: provider || 'slack',
    account_id: safeString(channel.account_id),
    conversation_id: safeString(channel.conversation_id || channel.channel_id),
    thread_key: safeString(channel.thread_key || channel.thread_ts),
    channel_scope: safeString(channel.channel_scope || (safeString(channel.conversation_id || channel.channel_id).startsWith('D') ? 'dm' : 'group')) || 'group',
  };
}

function normalizeRequestId(source_kind, explicit_request_id, fallback_id, now_ms) {
  const raw = safeString(explicit_request_id || fallback_id || `ts_${Math.max(0, Number(now_ms || Date.now()))}`);
  const suffix = raw.replace(/[^A-Za-z0-9._:-]+/g, '_').slice(0, 96) || `ts_${Math.max(0, Number(now_ms || Date.now()))}`;
  return `slack:${safeString(source_kind || 'command') || 'command'}:${suffix}`;
}

export function normalizeSlackCommandInput(input = {}, { now_ms = Date.now() } = {}) {
  const src = safeObject(input);

  if (src.signature_valid === false) {
    return {
      ok: false,
      deny_code: 'signature_invalid',
      retryable: false,
    };
  }

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
    const pending_grant = normalizePendingGrant(action.pending_grant);
    const scope_type = safeString(action.scope_type);
    const scope_id = safeString(action.scope_id);
    return {
      ok: true,
      source_kind: 'interactive',
      request_id: normalizeRequestId('interactive', src.request_id, src.audit_ref || src.trigger_id, now_ms),
      actor: normalizeSlackActor(src.actor),
      channel: normalizeSlackChannel(src.channel),
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
  const pending_grant = normalizePendingGrant(action.pending_grant);
  return {
    ok: true,
    source_kind: safeString(src.envelope_type || 'event_callback') || 'event_callback',
    request_id: normalizeRequestId(
      safeString(src.envelope_type || 'event_callback') || 'event_callback',
      src.request_id,
      src.event_id || src.replay_key,
      now_ms
    ),
    actor: normalizeSlackActor(src.actor),
    channel: normalizeSlackChannel(src.channel),
    binding_id: safeString(action.binding_id),
    action_name,
    scope_type: safeString(action.scope_type),
    scope_id: safeString(action.scope_id),
    note: safeString(action.note),
    pending_grant,
    audit_ref: '',
    route_project_id: safeString(pending_grant?.project_id),
  };
}

export function classifySlackCommandDispatch({
  gate = {},
  route = {},
  action_name = '',
} = {}) {
  const normalizedAction = safeString(action_name || gate.action_name).toLowerCase();
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

export async function orchestrateSlackCommand({
  input = {},
  hub_client = null,
  now_fn = Date.now,
} = {}) {
  const now_ms = typeof now_fn === 'function' ? Number(now_fn()) : Date.now();
  const command = normalizeSlackCommandInput(input, { now_ms });
  if (!command.ok) return command;

  if (!hub_client || typeof hub_client.evaluateChannelCommandGate !== 'function' || typeof hub_client.resolveSupervisorChannelRoute !== 'function') {
    return {
      ok: false,
      deny_code: 'hub_client_invalid',
      retryable: false,
      request_id: command.request_id,
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
      request_id: command.request_id,
      command,
      detail: safeString(error?.message || 'gate_rpc_failed'),
    };
  }

  const gate = safeObject(gateResponse.decision);
  if (gate.allowed === false) {
    return {
      ok: true,
      request_id: command.request_id,
      command,
      gate,
      route: null,
      audit_logged: gateResponse.audit_logged === true,
      dispatch: classifySlackCommandDispatch({
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
      request_id: command.request_id,
      command,
      gate,
      detail: safeString(error?.message || 'route_rpc_failed'),
    };
  }

  const route = safeObject(routeResponse.route);
  return {
    ok: true,
    request_id: command.request_id,
    command,
    gate,
    route,
    gate_audit_logged: gateResponse.audit_logged === true,
    route_audit_logged: routeResponse.audit_logged === true,
    route_created: routeResponse.created === true,
    route_updated: routeResponse.updated === true,
    dispatch: classifySlackCommandDispatch({
      gate,
      route,
      action_name: command.action_name,
    }),
  };
}

export function createSlackCommandOrchestrator({
  hub_client = null,
  now_fn = Date.now,
} = {}) {
  return {
    normalize(input) {
      return normalizeSlackCommandInput(input, {
        now_ms: typeof now_fn === 'function' ? Number(now_fn()) : Date.now(),
      });
    },
    async handle(input) {
      return await orchestrateSlackCommand({
        input,
        hub_client,
        now_fn,
      });
    },
  };
}
