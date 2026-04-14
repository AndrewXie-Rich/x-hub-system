function safeString(input) {
  return String(input ?? '').trim();
}

function normalizeActionName(input) {
  return safeString(input).toLowerCase();
}

function freezeActionPolicy(entry) {
  return Object.freeze({
    action_name: normalizeActionName(entry.action_name),
    allowed_roles: Object.freeze([...(Array.isArray(entry.allowed_roles) ? entry.allowed_roles : [])]),
    allowed_scope_types: Object.freeze([...(Array.isArray(entry.allowed_scope_types) ? entry.allowed_scope_types : [])]),
    approval_compatible: entry.approval_compatible === true,
    requires_pending_grant: entry.requires_pending_grant === true,
    route_mode: safeString(entry.route_mode),
    risk_tier: safeString(entry.risk_tier),
    required_grant_scope: safeString(entry.required_grant_scope),
  });
}

const ACTION_POLICIES = Object.freeze({
  'supervisor.status.get': freezeActionPolicy({
    action_name: 'supervisor.status.get',
    allowed_roles: ['viewer', 'operator', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['project', 'incident'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_only_status',
    risk_tier: 'low',
    required_grant_scope: 'none',
  }),
  'supervisor.blockers.get': freezeActionPolicy({
    action_name: 'supervisor.blockers.get',
    allowed_roles: ['viewer', 'operator', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['project', 'incident'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_only_status',
    risk_tier: 'low',
    required_grant_scope: 'none',
  }),
  'supervisor.queue.get': freezeActionPolicy({
    action_name: 'supervisor.queue.get',
    allowed_roles: ['viewer', 'operator', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['project', 'incident'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_only_status',
    risk_tier: 'low',
    required_grant_scope: 'none',
  }),
  'grant.approve': freezeActionPolicy({
    action_name: 'grant.approve',
    allowed_roles: ['approval_only_identity', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['project'],
    approval_compatible: true,
    requires_pending_grant: true,
    route_mode: 'hub_only_status',
    risk_tier: 'high',
    required_grant_scope: 'project_approval',
  }),
  'grant.reject': freezeActionPolicy({
    action_name: 'grant.reject',
    allowed_roles: ['approval_only_identity', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['project'],
    approval_compatible: true,
    requires_pending_grant: true,
    route_mode: 'hub_only_status',
    risk_tier: 'high',
    required_grant_scope: 'project_approval',
  }),
  'deploy.plan': freezeActionPolicy({
    action_name: 'deploy.plan',
    allowed_roles: ['operator', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['project'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_to_xt',
    risk_tier: 'medium',
    required_grant_scope: 'project_operate',
  }),
  'deploy.execute': freezeActionPolicy({
    action_name: 'deploy.execute',
    allowed_roles: ['release_manager', 'ops_admin'],
    allowed_scope_types: ['project'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_to_xt',
    risk_tier: 'critical',
    required_grant_scope: 'project_release',
  }),
  'supervisor.pause': freezeActionPolicy({
    action_name: 'supervisor.pause',
    allowed_roles: ['operator', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['project'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_to_xt',
    risk_tier: 'medium',
    required_grant_scope: 'project_operate',
  }),
  'supervisor.resume': freezeActionPolicy({
    action_name: 'supervisor.resume',
    allowed_roles: ['operator', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['project'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_to_xt',
    risk_tier: 'medium',
    required_grant_scope: 'project_operate',
  }),
  'device.doctor.get': freezeActionPolicy({
    action_name: 'device.doctor.get',
    allowed_roles: ['operator', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['device'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_to_runner',
    risk_tier: 'high',
    required_grant_scope: 'device_observe',
  }),
  'device.permission_status.get': freezeActionPolicy({
    action_name: 'device.permission_status.get',
    allowed_roles: ['operator', 'release_manager', 'ops_admin'],
    allowed_scope_types: ['device'],
    approval_compatible: false,
    requires_pending_grant: false,
    route_mode: 'hub_to_runner',
    risk_tier: 'high',
    required_grant_scope: 'device_observe',
  }),
});

export function normalizeChannelActionName(input) {
  return normalizeActionName(input);
}

export function listChannelActionPolicies() {
  return Object.values(ACTION_POLICIES);
}

export function listChannelStructuredActionNames() {
  return Object.freeze(Object.keys(ACTION_POLICIES));
}

export function getChannelActionPolicy(action_name) {
  const actionName = normalizeActionName(action_name);
  return ACTION_POLICIES[actionName] || null;
}
