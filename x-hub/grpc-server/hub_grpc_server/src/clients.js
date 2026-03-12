import fs from 'node:fs';
import path from 'node:path';

function safeString(value) {
  return String(value ?? '').trim();
}

function safeBool(value, fallback = true) {
  if (value == null) return fallback;
  if (typeof value === 'boolean') return value;
  const cleaned = safeString(value).toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(cleaned)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(cleaned)) return false;
  return fallback;
}

function safeInt(value, fallback = 0) {
  if (value == null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

function uniqueStrings(values) {
  const out = [];
  const seen = new Set();
  for (const raw of Array.isArray(values) ? values : []) {
    const cleaned = safeString(raw);
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

function safeStringArray(value) {
  if (value == null) return [];
  if (Array.isArray(value)) return uniqueStrings(value);
  const cleaned = safeString(value);
  if (!cleaned) return [];
  return uniqueStrings(cleaned.split(','));
}

function asObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function normalizeClientTrustProfileFields(raw, { device_id, name, capabilities }) {
  const src = asObject(raw);
  const approvedTrustProfile = asObject(src.approved_trust_profile || src.approvedTrustProfile || src.trust_profile || src.trustProfile);
  const paidPolicy = asObject(src.paid_model_policy || src.paidModelPolicy || approvedTrustProfile.paid_model_policy || approvedTrustProfile.paidModelPolicy);
  const budgetPolicy = asObject(src.budget_policy || src.budgetPolicy || approvedTrustProfile.budget_policy || approvedTrustProfile.budgetPolicy);
  const networkPolicy = asObject(src.network_policy || src.networkPolicy || approvedTrustProfile.network_policy || approvedTrustProfile.networkPolicy);

  const policyMode = safeString(src.policy_mode || src.policyMode) || (Object.keys(approvedTrustProfile).length > 0 ? 'new_profile' : 'legacy_grant');
  const trustMode = safeString(src.trust_mode || src.trustMode || approvedTrustProfile.trust_mode || approvedTrustProfile.trustMode);
  const paidModelPolicyMode = safeString(
    src.paid_model_policy_mode
      || src.paidModelPolicyMode
      || paidPolicy.mode
      || paidPolicy.policy_mode
  ).toLowerCase();
  const paidModelAllowedModelIds = safeStringArray(
    src.allowed_model_ids
      || src.allowedModelIds
      || src.paid_model_allowed_model_ids
      || src.paidModelAllowedModelIds
      || paidPolicy.allowed_model_ids
      || paidPolicy.allowedModelIds
  );
  const defaultWebFetchEnabled = safeBool(
    src.default_web_fetch_enabled
      ?? src.defaultWebFetchEnabled
      ?? networkPolicy.default_web_fetch_enabled
      ?? networkPolicy.defaultWebFetchEnabled,
    false
  );
  const dailyTokenLimit = safeInt(
    src.daily_token_limit
      ?? src.dailyTokenLimit
      ?? budgetPolicy.daily_token_limit
      ?? budgetPolicy.dailyTokenLimit,
    0
  );
  const singleRequestTokenLimit = safeInt(
    src.single_request_token_limit
      ?? src.singleRequestTokenLimit
      ?? budgetPolicy.single_request_token_limit
      ?? budgetPolicy.singleRequestTokenLimit,
    0
  );
  const auditRef = safeString(src.audit_ref || src.auditRef || approvedTrustProfile.audit_ref || approvedTrustProfile.auditRef);
  const rawTrustedAutomationMode = safeString(
    src.trusted_automation_mode
      || src.trustedAutomationMode
      || src.mode
      || approvedTrustProfile.trusted_automation_mode
      || approvedTrustProfile.trustedAutomationMode
      || approvedTrustProfile.mode
  ).toLowerCase();
  const trustedAutomationMode = rawTrustedAutomationMode
    || (trustMode === 'trusted_automation' ? 'trusted_automation' : (Object.keys(approvedTrustProfile).length > 0 ? 'standard' : ''));
  const rawTrustedAutomationState = safeString(
    src.trusted_automation_state
      || src.trustedAutomationState
      || src.state
      || approvedTrustProfile.trusted_automation_state
      || approvedTrustProfile.trustedAutomationState
      || approvedTrustProfile.state
  ).toLowerCase();
  const trustedAutomationState = rawTrustedAutomationState
    || (trustedAutomationMode === 'trusted_automation' ? 'armed' : (Object.keys(approvedTrustProfile).length > 0 ? 'off' : ''));
  const allowedProjectIds = safeStringArray(
    src.allowed_project_ids
      || src.allowedProjectIds
      || approvedTrustProfile.allowed_project_ids
      || approvedTrustProfile.allowedProjectIds
  );
  const allowedWorkspaceRoots = safeStringArray(
    src.allowed_workspace_roots
      || src.allowedWorkspaceRoots
      || approvedTrustProfile.allowed_workspace_roots
      || approvedTrustProfile.allowedWorkspaceRoots
  );
  const xtBindingRequired = safeBool(
    src.xt_binding_required
      ?? src.xtBindingRequired
      ?? approvedTrustProfile.xt_binding_required
      ?? approvedTrustProfile.xtBindingRequired,
    trustedAutomationMode === 'trusted_automation'
  );
  const autoGrantProfile = safeString(
    src.auto_grant_profile
      || src.autoGrantProfile
      || approvedTrustProfile.auto_grant_profile
      || approvedTrustProfile.autoGrantProfile
  );
  const devicePermissionOwnerRef = safeString(
    src.device_permission_owner_ref
      || src.devicePermissionOwnerRef
      || approvedTrustProfile.device_permission_owner_ref
      || approvedTrustProfile.devicePermissionOwnerRef
  );

  const trustProfilePresent = Object.keys(approvedTrustProfile).length > 0
    || policyMode === 'new_profile'
    || !!trustMode
    || !!paidModelPolicyMode
    || paidModelAllowedModelIds.length > 0
    || dailyTokenLimit > 0
    || singleRequestTokenLimit > 0
    || !!trustedAutomationMode
    || !!trustedAutomationState
    || allowedProjectIds.length > 0
    || allowedWorkspaceRoots.length > 0
    || !!autoGrantProfile
    || !!devicePermissionOwnerRef;

  const normalizedTrustProfile = trustProfilePresent
    ? {
        schema_version: safeString(approvedTrustProfile.schema_version || approvedTrustProfile.schemaVersion) || 'hub.paired_terminal_trust_profile.v1',
        device_id,
        device_name: safeString(approvedTrustProfile.device_name || approvedTrustProfile.deviceName || src.device_name || src.deviceName || name),
        trust_mode: trustMode || 'trusted_daily',
        mode: trustedAutomationMode || 'standard',
        state: trustedAutomationState || 'off',
        capabilities: uniqueStrings(
          Array.isArray(approvedTrustProfile.capabilities) && approvedTrustProfile.capabilities.length > 0
            ? approvedTrustProfile.capabilities
            : capabilities
        ),
        allowed_project_ids: allowedProjectIds,
        allowed_workspace_roots: allowedWorkspaceRoots,
        xt_binding_required: !!xtBindingRequired,
        auto_grant_profile: autoGrantProfile,
        device_permission_owner_ref: devicePermissionOwnerRef,
        paid_model_policy: {
          schema_version: safeString(paidPolicy.schema_version || paidPolicy.schemaVersion) || 'hub.paired_terminal_paid_model_policy.v1',
          mode: paidModelPolicyMode || 'off',
          allowed_model_ids: paidModelPolicyMode === 'custom_selected_models' ? paidModelAllowedModelIds : [],
        },
        network_policy: {
          default_web_fetch_enabled: defaultWebFetchEnabled,
        },
        budget_policy: {
          daily_token_limit: dailyTokenLimit,
          single_request_token_limit: singleRequestTokenLimit,
        },
        audit_ref: auditRef,
      }
    : null;

  return {
    policy_mode: policyMode,
    trust_profile_present: trustProfilePresent,
    trust_profile_schema_version: normalizedTrustProfile ? normalizedTrustProfile.schema_version : '',
    trust_mode: normalizedTrustProfile ? normalizedTrustProfile.trust_mode : '',
    paid_model_policy_mode: normalizedTrustProfile ? normalizedTrustProfile.paid_model_policy.mode : '',
    paid_model_allowed_model_ids: normalizedTrustProfile ? normalizedTrustProfile.paid_model_policy.allowed_model_ids : [],
    default_web_fetch_enabled: normalizedTrustProfile ? !!normalizedTrustProfile.network_policy.default_web_fetch_enabled : false,
    daily_token_limit: normalizedTrustProfile ? safeInt(normalizedTrustProfile.budget_policy.daily_token_limit, 0) : 0,
    single_request_token_limit: normalizedTrustProfile ? safeInt(normalizedTrustProfile.budget_policy.single_request_token_limit, 0) : 0,
    trusted_automation_mode: normalizedTrustProfile ? safeString(normalizedTrustProfile.mode).toLowerCase() : '',
    trusted_automation_state: normalizedTrustProfile ? safeString(normalizedTrustProfile.state).toLowerCase() : '',
    allowed_project_ids: normalizedTrustProfile ? safeStringArray(normalizedTrustProfile.allowed_project_ids) : [],
    allowed_workspace_roots: normalizedTrustProfile ? safeStringArray(normalizedTrustProfile.allowed_workspace_roots) : [],
    xt_binding_required: normalizedTrustProfile ? !!normalizedTrustProfile.xt_binding_required : false,
    auto_grant_profile: normalizedTrustProfile ? safeString(normalizedTrustProfile.auto_grant_profile) : '',
    device_permission_owner_ref: normalizedTrustProfile ? safeString(normalizedTrustProfile.device_permission_owner_ref) : '',
    audit_ref: normalizedTrustProfile ? safeString(normalizedTrustProfile.audit_ref) : '',
    trust_profile: normalizedTrustProfile,
    approved_trust_profile: normalizedTrustProfile,
  };
}

let cache = {
  loaded_at_ms: 0,
  mtime_ms: 0,
  file_path: '',
  clients: null,
};

export function clientsConfigPath(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'hub_grpc_clients.json');
}

function normalizeClientEntry(raw, fallbackDeviceId = '') {
  const src = asObject(raw);
  const device_id = safeString(src.device_id || src.id || fallbackDeviceId);
  const token = safeString(src.token || src.client_token || src.clientToken);
  if (!device_id || !token) return null;

  const name = safeString(src.name || src.device_name || src.deviceName);
  const capabilities = uniqueStrings(src.capabilities || src.caps || src.allowed_capabilities || src.allowedCapabilities || []);

  return {
    device_id,
    user_id: safeString(src.user_id || src.userId) || device_id,
    name,
    token,
    enabled: safeBool(src.enabled, true),
    created_at_ms: safeInt(src.created_at_ms || src.createdAtMs, 0),
    capabilities,
    allowed_cidrs: safeStringArray(src.allowed_cidrs || src.allowedCidrs || src.allowed_ip_cidrs || src.allowedIpCidrs),
    cert_sha256: safeString(src.cert_sha256 || src.certSha256 || src.cert_fingerprint_sha256 || src.certFingerprintSha256),
    ...normalizeClientTrustProfileFields(src, { device_id, name, capabilities }),
  };
}

export function loadClients(runtimeBaseDir, maxAgeMs = 1200) {
  const filePath = clientsConfigPath(runtimeBaseDir);
  if (!filePath) return [];

  const now = Date.now();
  let stat = null;
  try {
    stat = fs.statSync(filePath);
  } catch {
    stat = null;
  }
  const mtimeMs = stat ? Number(stat.mtimeMs || 0) : 0;

  if (
    Array.isArray(cache.clients)
    && cache.file_path === filePath
    && cache.mtime_ms === mtimeMs
    && now - cache.loaded_at_ms <= Math.max(200, Number(maxAgeMs || 0))
  ) {
    return cache.clients;
  }

  let parsed = null;
  try {
    parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    parsed = null;
  }

  const clients = [];
  const arr = Array.isArray(parsed?.clients)
    ? parsed.clients
    : Array.isArray(parsed?.devices)
      ? parsed.devices
      : null;

  if (Array.isArray(arr)) {
    for (const item of arr) {
      const normalized = normalizeClientEntry(item);
      if (normalized) clients.push(normalized);
    }
  } else if (parsed && typeof parsed === 'object' && parsed.devices && typeof parsed.devices === 'object') {
    for (const [deviceId, value] of Object.entries(parsed.devices)) {
      if (typeof value === 'string') {
        const normalized = normalizeClientEntry({ device_id: deviceId, token: value, enabled: true }, deviceId);
        if (normalized) clients.push(normalized);
        continue;
      }
      const normalized = normalizeClientEntry(value, deviceId);
      if (normalized) clients.push(normalized);
    }
  }

  cache = { loaded_at_ms: now, mtime_ms: mtimeMs, file_path: filePath, clients };
  return clients;
}

export function findClientByToken(runtimeBaseDir, token) {
  const wantedToken = safeString(token);
  if (!wantedToken) return null;
  for (const client of loadClients(runtimeBaseDir)) {
    if (!client?.enabled) continue;
    if (safeString(client.token) === wantedToken) return client;
  }
  return null;
}
