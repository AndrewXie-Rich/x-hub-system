const MANAGER_SCOPES = new Set(['hub_access_keys.manage', 'hub.access_keys.manage', 'access_keys.manage']);
const AI_CAPABILITIES = new Set(['models', 'ai.generate.local', 'ai.generate.paid']);

export function hasAccessKeyManagementScope(client) {
  return !client?.managed_by_access_key_id
    && Array.isArray(client?.scopes)
    && client.scopes.some((scope) => MANAGER_SCOPES.has(scope));
}

export function ownsDelegatedAccessKey(parent, child) {
  return !!parent?.access_key_id
    && child?.managed_by_access_key_id === parent.access_key_id
    && child?.created_by_user_id === parent.user_id
    && child?.managed_by_device_id === parent.device_id;
}

export function delegatedKeyPolicyError(parent, child, nowMs = Date.now()) {
  if (!hasAccessKeyManagementScope(parent)) return 'access_key_management_scope_required';
  if (!ownsDelegatedAccessKey(parent, child)) return 'access_key_not_found';
  if (child.auth_kind !== 'hub_access_key' || child.app_id !== 'external_terminal'
    || child.policy_mode !== 'new_profile' || child.user_id !== parent.user_id) return 'delegation_identity_denied';
  const profile = child.approved_trust_profile;
  const parentCaps = new Set(parent.capabilities || []);
  const parentScopes = new Set(parent.scopes || []);
  if (!profile || !Array.isArray(child.capabilities) || !child.capabilities.length
    || child.capabilities.some((capability) => !AI_CAPABILITIES.has(capability) || !parentCaps.has(capability) || !parentScopes.has(capability))
    || child.scopes?.some((scope) => !child.capabilities.includes(scope))
    || child.capabilities.some((capability) => !child.scopes?.includes(capability))
    || profile.capabilities?.some((capability) => !child.capabilities.includes(capability))) return 'delegation_capability_denied';
  const dailyLimit = Number(profile.budget_policy?.daily_token_limit);
  const singleLimit = Number(profile.budget_policy?.single_request_token_limit);
  if (!Number.isSafeInteger(parent.daily_token_limit) || parent.daily_token_limit <= 0
    || !Number.isSafeInteger(dailyLimit) || dailyLimit <= 0 || dailyLimit > parent.daily_token_limit
    || !Number.isSafeInteger(singleLimit) || singleLimit <= 0
    || !Number.isSafeInteger(parent.single_request_token_limit)
    || parent.single_request_token_limit <= 0 || singleLimit > parent.single_request_token_limit) return 'delegation_budget_denied';
  if (!Number.isSafeInteger(child.expires_at_ms) || child.expires_at_ms <= nowMs
    || (parent.expires_at_ms > 0 && child.expires_at_ms > parent.expires_at_ms)) return 'delegation_expiry_denied';
  if (profile.network_policy?.default_web_fetch_enabled !== false) return 'delegation_capability_denied';
  if (!Array.isArray(child.allowed_cidrs) || child.allowed_cidrs.length === 0
    || child.allowed_cidrs.some((rule) => !(parent.allowed_cidrs || []).includes(rule))) return 'delegation_source_denied';
  const mode = profile.paid_model_policy?.mode;
  if (!['off', 'all_paid_models', 'custom_selected_models'].includes(mode)) return 'delegation_paid_model_denied';
  if (mode !== 'off') {
    if (!parentCaps.has('ai.generate.paid') || parent.paid_model_policy_mode === 'off'
      || !['all_paid_models', 'custom_selected_models'].includes(parent.paid_model_policy_mode)) return 'delegation_paid_model_denied';
    if (parent.paid_model_policy_mode === 'custom_selected_models'
      && (mode !== 'custom_selected_models'
        || !profile.paid_model_policy.allowed_model_ids?.length
        || profile.paid_model_policy.allowed_model_ids.some((model) => !(parent.paid_model_allowed_model_ids || []).includes(model)))) return 'delegation_paid_model_denied';
  }
  if ((parent.allowed_project_ids || []).length || (parent.allowed_workspace_roots || []).length
    || parent.xt_binding_required || parent.trusted_automation_mode === 'trusted_automation') return 'delegation_restricted_parent';
  return '';
}

export function delegatedBudgetReservation(parent, child, siblings, nowMs = Date.now()) {
  const day = new Date(nowMs).toISOString().slice(0, 10);
  const dayStart = Date.parse(`${day}T00:00:00.000Z`);
  const budgetFor = (key) => {
    const reserved = key.delegation_budget_day === day ? Number(key.delegation_budget_reserved || 0) : 0;
    const active = key.enabled !== false && !key.revoked_at_ms && Number(key.expires_at_ms) > dayStart;
    return Math.max(reserved, active ? Number(key.approved_trust_profile?.budget_policy?.daily_token_limit || 0) : 0);
  };
  const previous = siblings.find((key) => key.access_key_id === child.access_key_id);
  const reserved = Math.max(budgetFor(child), previous ? budgetFor(previous) : 0);
  const total = siblings.filter((key) => key.managed_by_access_key_id === parent.access_key_id && key.access_key_id !== child.access_key_id)
    .reduce((sum, key) => sum + budgetFor(key), reserved);
  if (!Number.isSafeInteger(total) || total > parent.daily_token_limit) return null;
  return { delegation_budget_day: day, delegation_budget_reserved: reserved };
}
