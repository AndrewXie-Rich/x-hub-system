import {
  getSupervisorOperatorChannelBindingById,
  normalizeSupervisorChannelBindingStatus,
  normalizeSupervisorChannelScope,
  normalizeSupervisorScopeType,
  resolveSupervisorOperatorChannelBinding,
} from './channel_bindings_store.js';
import {
  getChannelIdentityBinding,
  makeChannelIdentityActorRef,
  normalizeChannelAccessGroups,
  normalizeChannelRoles,
  normalizeChannelIdentityStatus,
} from './channel_identity_store.js';
import {
  getChannelActionPolicy as getActionPolicy,
  listChannelActionPolicies as listActionPolicies,
  normalizeChannelActionName as normalizeRouterActionName,
} from './channel_action_router.js';
import { normalizeChannelProviderId } from './channel_registry.js';
import { nowMs, uuid } from './util.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function normalizeActionName(input) {
  return normalizeRouterActionName(input);
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

export function listChannelActionPolicies() {
  return listActionPolicies();
}

export function normalizeChannelActionName(input) {
  return normalizeActionName(input);
}

export function getChannelActionPolicy(action_name) {
  return getActionPolicy(action_name);
}

function deny({
  action_name = '',
  deny_code = 'channel_command_denied',
  detail = '',
  identity_binding = null,
  channel_binding = null,
  binding_match_mode = 'none',
  policy = null,
} = {}) {
  return {
    allowed: false,
    deny_code: safeString(deny_code) || 'channel_command_denied',
    detail: safeString(detail) || 'channel_command_denied',
    action_name: normalizeActionName(action_name),
    binding_id: safeString(channel_binding?.binding_id),
    binding_match_mode: safeString(binding_match_mode) || 'none',
    scope_type: safeString(channel_binding?.scope_type),
    scope_id: safeString(channel_binding?.scope_id),
    actor_ref: identity_binding ? makeChannelIdentityActorRef(identity_binding) : '',
    approval_only: identity_binding?.approval_only === true,
    policy_checked: true,
    allowed_roles: Array.isArray(policy?.allowed_roles) ? [...policy.allowed_roles] : [],
    identity_roles: normalizeChannelRoles(identity_binding?.roles || []),
    stable_external_id: safeString(identity_binding?.stable_external_id),
    access_groups: normalizeChannelAccessGroups(identity_binding?.access_groups || []),
    risk_tier: safeString(policy?.risk_tier),
    required_grant_scope: safeString(policy?.required_grant_scope),
    route_mode: safeString(policy?.route_mode),
  };
}

function allow({
  action_name = '',
  identity_binding = null,
  channel_binding = null,
  binding_match_mode = 'none',
  policy = null,
} = {}) {
  return {
    allowed: true,
    deny_code: '',
    detail: 'allow',
    action_name: normalizeActionName(action_name),
    binding_id: safeString(channel_binding?.binding_id),
    binding_match_mode: safeString(binding_match_mode) || 'none',
    scope_type: safeString(channel_binding?.scope_type),
    scope_id: safeString(channel_binding?.scope_id),
    actor_ref: identity_binding ? makeChannelIdentityActorRef(identity_binding) : '',
    approval_only: identity_binding?.approval_only === true,
    policy_checked: true,
    allowed_roles: Array.isArray(policy?.allowed_roles) ? [...policy.allowed_roles] : [],
    identity_roles: normalizeChannelRoles(identity_binding?.roles || []),
    stable_external_id: safeString(identity_binding?.stable_external_id),
    access_groups: normalizeChannelAccessGroups(identity_binding?.access_groups || []),
    risk_tier: safeString(policy?.risk_tier),
    required_grant_scope: safeString(policy?.required_grant_scope),
    route_mode: safeString(policy?.route_mode),
  };
}

function rolesIntersect(policyRoles, identityRoles) {
  const wanted = new Set(normalizeChannelRoles(policyRoles || []));
  const actual = normalizeChannelRoles(identityRoles || []);
  return actual.some((role) => wanted.has(role));
}

function hasIdentityRole(identity_binding, role) {
  return normalizeChannelRoles(identity_binding?.roles || []).includes(normalizeActionName(role));
}

function requiredAccessGroupForRoute(route_context = {}, channel_binding = {}) {
  const channelScope = normalizeSupervisorChannelScope(
    route_context.channel_scope,
    channel_binding.channel_scope || 'group'
  );
  if (channelScope === 'dm') return 'dm_allowlist';
  return safeString(route_context.thread_key || channel_binding.thread_key)
    ? 'thread_allowlist'
    : 'group_allowlist';
}

function denyCodeForAccessGroup(group) {
  if (group === 'dm_allowlist') return 'dm_access_not_allowlisted';
  if (group === 'thread_allowlist') return 'thread_access_not_allowlisted';
  return 'group_access_not_allowlisted';
}

function normalizeAllowedScopeTypes(policy = null) {
  const rows = Array.isArray(policy?.allowed_scope_types) ? policy.allowed_scope_types : [];
  const out = [];
  const seen = new Set();
  for (const raw of rows) {
    const scopeType = normalizeSupervisorScopeType(raw, '');
    if (!scopeType || seen.has(scopeType)) continue;
    seen.add(scopeType);
    out.push(scopeType);
  }
  return out;
}

function resolveRequestedScopeType(required_scope_type = '', channel_binding = null) {
  return normalizeSupervisorScopeType(
    required_scope_type || channel_binding?.scope_type,
    channel_binding?.scope_type || 'project'
  );
}

function normalizePendingGrant(input = {}) {
  if (!input || typeof input !== 'object') return null;
  const project_id = safeString(input.project_id || input.scope_id);
  const status = safeString(input.status || 'pending').toLowerCase();
  return {
    grant_request_id: safeString(input.grant_request_id),
    project_id,
    status,
  };
}

export function authorizeChannelCommand({
  identity_binding = null,
  channel_binding = null,
  binding_match_mode = 'none',
  action_name = '',
  route_context = {},
  required_scope_type = '',
  required_scope_id = '',
  pending_grant = null,
} = {}) {
  const actionName = normalizeActionName(action_name);
  const policy = getChannelActionPolicy(actionName);
  if (!policy) {
    return deny({
      action_name: actionName,
      deny_code: 'action_unsupported',
      detail: 'unsupported channel action',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  if (!identity_binding) {
    return deny({
      action_name: actionName,
      deny_code: 'identity_binding_missing',
      detail: 'identity binding missing',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }
  if (normalizeChannelIdentityStatus(identity_binding.status, 'disabled') !== 'active') {
    return deny({
      action_name: actionName,
      deny_code: 'identity_binding_inactive',
      detail: 'identity binding inactive',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }
  if (!channel_binding) {
    return deny({
      action_name: actionName,
      deny_code: 'channel_binding_missing',
      detail: 'channel binding missing',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }
  if (normalizeSupervisorChannelBindingStatus(channel_binding.status, 'disabled') !== 'active') {
    return deny({
      action_name: actionName,
      deny_code: 'channel_binding_inactive',
      detail: 'channel binding inactive',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  const routeProvider = normalizeChannelProviderId(route_context.provider) || '';
  const routeConversationId = safeString(route_context.conversation_id);
  const routeChannelScope = normalizeSupervisorChannelScope(route_context.channel_scope, channel_binding.channel_scope || 'group');
  const routeThreadKey = safeString(route_context.thread_key);
  if (routeProvider && routeProvider !== channel_binding.provider) {
    return deny({
      action_name: actionName,
      deny_code: 'provider_mismatch',
      detail: 'provider mismatch',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }
  if (routeConversationId && routeConversationId !== channel_binding.conversation_id) {
    return deny({
      action_name: actionName,
      deny_code: 'conversation_mismatch',
      detail: 'conversation mismatch',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }
  if (routeChannelScope !== channel_binding.channel_scope) {
    return deny({
      action_name: actionName,
      deny_code: 'channel_scope_mismatch',
      detail: 'channel scope mismatch',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }
  if (channel_binding.thread_key && routeThreadKey && channel_binding.thread_key !== routeThreadKey) {
    return deny({
      action_name: actionName,
      deny_code: 'thread_scope_mismatch',
      detail: 'thread scope mismatch',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  const expectedScopeType = resolveRequestedScopeType(required_scope_type, channel_binding);
  const allowedScopeTypes = normalizeAllowedScopeTypes(policy);
  if (allowedScopeTypes.length && !allowedScopeTypes.includes(expectedScopeType)) {
    return deny({
      action_name: actionName,
      deny_code: 'scope_switch_required',
      detail: 'action requires a different binding scope',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }
  const expectedScopeId = safeString(required_scope_id || channel_binding.scope_id);
  if (expectedScopeType !== channel_binding.scope_type || (expectedScopeId && expectedScopeId !== channel_binding.scope_id)) {
    return deny({
      action_name: actionName,
      deny_code: 'scope_mismatch',
      detail: 'scope mismatch',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  const allowedActions = Array.isArray(channel_binding.allowed_actions)
    ? channel_binding.allowed_actions.map((item) => normalizeActionName(item))
    : [];
  if (!allowedActions.includes(actionName)) {
    return deny({
      action_name: actionName,
      deny_code: 'action_not_allowlisted',
      detail: 'binding action not allowlisted',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  const accessGroups = normalizeChannelAccessGroups(identity_binding.access_groups || []);
  if (!accessGroups.length) {
    return deny({
      action_name: actionName,
      deny_code: 'access_groups_missing',
      detail: 'identity access groups missing',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  const requiredAccessGroup = requiredAccessGroupForRoute(route_context, channel_binding);
  if (
    requiredAccessGroup
    && !accessGroups.includes(requiredAccessGroup)
    && !hasIdentityRole(identity_binding, 'ops_admin')
  ) {
    return deny({
      action_name: actionName,
      deny_code: denyCodeForAccessGroup(requiredAccessGroup),
      detail: 'identity surface not allowlisted',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  if (
    (safeBool(identity_binding.approval_only, false) || accessGroups.includes('approval_only_identity'))
    && !policy.approval_compatible
  ) {
    return deny({
      action_name: actionName,
      deny_code: 'identity_approval_only',
      detail: 'identity limited to approval actions',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  if (!rolesIntersect(policy.allowed_roles, identity_binding.roles || [])) {
    return deny({
      action_name: actionName,
      deny_code: 'role_not_allowed',
      detail: 'role not allowed',
      identity_binding,
      channel_binding,
      binding_match_mode,
      policy,
    });
  }

  const pendingGrant = normalizePendingGrant(pending_grant);
  if (policy.requires_pending_grant) {
    if (!pendingGrant) {
      return deny({
        action_name: actionName,
        deny_code: 'pending_grant_missing',
        detail: 'pending grant required',
        identity_binding,
        channel_binding,
        binding_match_mode,
        policy,
      });
    }
    if (pendingGrant.status && pendingGrant.status !== 'pending') {
      return deny({
        action_name: actionName,
        deny_code: 'pending_grant_not_pending',
        detail: 'pending grant must be pending',
        identity_binding,
        channel_binding,
        binding_match_mode,
        policy,
      });
    }
    if (channel_binding.scope_type === 'project' && pendingGrant.project_id !== channel_binding.scope_id) {
      return deny({
        action_name: actionName,
        deny_code: 'pending_grant_scope_mismatch',
        detail: 'pending grant scope mismatch',
        identity_binding,
        channel_binding,
        binding_match_mode,
        policy,
      });
    }
  }

  return allow({
    action_name: actionName,
    identity_binding,
    channel_binding,
    binding_match_mode,
    policy,
  });
}

function appendChannelCommandAudit({
  db,
  decision,
  identity_binding,
  channel_binding,
  actor = {},
  channel = {},
  request_id = '',
  pending_grant = null,
  client = {},
} = {}) {
  return db.appendAudit({
    event_id: uuid(),
    event_type: decision.allowed ? 'channel.command.allowed' : 'channel.command.denied',
    created_at_ms: nowMs(),
    severity: decision.allowed ? 'info' : 'warn',
    device_id: safeString(client.device_id || 'channel_command_gate'),
    user_id: safeString(client.user_id || identity_binding?.hub_user_id) || null,
    app_id: safeString(client.app_id || 'channel_command_gate'),
    project_id: channel_binding?.scope_type === 'project'
      ? safeString(channel_binding?.scope_id) || null
      : (safeString(client.project_id) || null),
    session_id: safeString(client.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: decision.action_name ? `channel.command.${decision.action_name}` : 'channel.command.unknown',
    model_id: null,
    ok: !!decision.allowed,
    error_code: decision.allowed ? null : safeString(decision.deny_code || 'channel_command_denied'),
    error_message: decision.allowed ? null : safeString(decision.detail || 'channel_command_denied'),
    ext_json: JSON.stringify({
      action_name: decision.action_name,
      binding_id: safeString(channel_binding?.binding_id),
      binding_match_mode: safeString(decision.binding_match_mode),
      provider: safeString(channel.provider || channel_binding?.provider),
      account_id: safeString(channel.account_id || channel_binding?.account_id),
      conversation_id: safeString(channel.conversation_id || channel_binding?.conversation_id),
      thread_key: safeString(channel.thread_key || channel_binding?.thread_key),
      channel_scope: safeString(channel.channel_scope || channel_binding?.channel_scope),
      scope_type: safeString(channel_binding?.scope_type),
      scope_id: safeString(channel_binding?.scope_id),
      actor_ref: identity_binding ? makeChannelIdentityActorRef(identity_binding) : '',
      actor_provider: safeString(actor.provider || identity_binding?.provider),
      actor_stable_external_id: safeString(actor.stable_external_id || identity_binding?.stable_external_id),
      actor_external_user_id: safeString(actor.external_user_id || identity_binding?.external_user_id),
      actor_hub_user_id: safeString(identity_binding?.hub_user_id),
      approval_only: identity_binding?.approval_only === true,
      allowed_roles: Array.isArray(decision.allowed_roles) ? decision.allowed_roles : [],
      identity_roles: Array.isArray(decision.identity_roles) ? decision.identity_roles : [],
      access_groups: normalizeChannelAccessGroups(identity_binding?.access_groups || []),
      pending_grant_request_id: safeString(pending_grant?.grant_request_id),
      pending_grant_project_id: safeString(pending_grant?.project_id),
      risk_tier: safeString(decision.risk_tier || policy?.risk_tier),
      required_grant_scope: safeString(decision.required_grant_scope || policy?.required_grant_scope),
      route_mode: safeString(decision.route_mode || policy?.route_mode),
      deny_code: safeString(decision.deny_code),
    }),
  });
}

export function evaluateChannelCommandGateWithAudit({
  db,
  actor = {},
  channel = {},
  action = {},
  client = {},
  request_id = '',
} = {}) {
  if (!db || typeof db.appendAudit !== 'function') {
    return deny({
      action_name: action.action_name,
      deny_code: 'audit_write_failed',
      detail: 'audit unavailable',
    });
  }

  const identityBinding = getChannelIdentityBinding(db, {
    stable_external_id: actor.stable_external_id,
    provider: actor.provider,
    external_user_id: actor.external_user_id,
    external_tenant_id: actor.external_tenant_id,
  });
  const resolution = action.binding_id
    ? {
        binding: getSupervisorOperatorChannelBindingById(db, { binding_id: action.binding_id }),
        binding_match_mode: 'binding_id',
      }
    : resolveSupervisorOperatorChannelBinding(db, {
        provider: channel.provider,
        account_id: channel.account_id,
        conversation_id: channel.conversation_id,
        thread_key: channel.thread_key,
        channel_scope: channel.channel_scope,
      });

  const decision = authorizeChannelCommand({
    identity_binding: identityBinding,
    channel_binding: resolution.binding,
    binding_match_mode: resolution.binding_match_mode,
    action_name: action.action_name,
    route_context: channel,
    required_scope_type: action.scope_type,
    required_scope_id: action.scope_id,
    pending_grant: action.pending_grant,
  });

  try {
    appendChannelCommandAudit({
      db,
      decision,
      identity_binding: identityBinding,
      channel_binding: resolution.binding,
      actor,
      channel,
      request_id,
      pending_grant: action.pending_grant,
      client,
    });
    return {
      ...decision,
      audit_logged: true,
    };
  } catch (err) {
    return deny({
      action_name: action.action_name,
      deny_code: 'audit_write_failed',
      detail: safeString(err?.message || 'audit_write_failed'),
      identity_binding: identityBinding,
      channel_binding: resolution.binding,
      binding_match_mode: resolution.binding_match_mode,
      policy: getChannelActionPolicy(action.action_name),
    });
  }
}
