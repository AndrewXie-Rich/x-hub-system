import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const CLIENTS_SCHEMA_VERSION = 'hub_grpc_clients.v2';
const DEFAULT_USAGE_WRITE_INTERVAL_MS = 30_000;

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

function readJsonSafe(filePath) {
  try {
    return JSON.parse(fs.readFileSync(String(filePath || ''), 'utf8'));
  } catch {
    return null;
  }
}

function writeJsonAtomic(dirPath, fileName, obj) {
  const dir = safeString(dirPath);
  if (!dir) return false;
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // ignore
  }
  const outPath = path.join(dir, fileName);
  const tmpPath = path.join(dir, `.${fileName}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`);
  try {
    fs.writeFileSync(tmpPath, JSON.stringify(obj, null, 2) + '\n', 'utf8');
    fs.renameSync(tmpPath, outPath);
    return true;
  } catch {
    try {
      fs.unlinkSync(tmpPath);
    } catch {
      // ignore
    }
    return false;
  }
}

function normalizeClientAuthKind(value, fallback = 'paired_client') {
  const raw = safeString(value).toLowerCase();
  if (raw === 'hub_access_key' || raw === 'access_key' || raw === 'service_token') return 'hub_access_key';
  if (raw === 'paired_client' || raw === 'paired_terminal' || raw === 'device_pairing') return 'paired_client';
  return fallback;
}

export function redactClientToken(value) {
  const token = safeString(value);
  if (!token) return '';
  if (token.length <= 8) return '****';
  return `${token.slice(0, 8)}...${token.slice(-4)}`;
}

export function generateClientToken() {
  const bytes = crypto.randomBytes(32);
  const b64 = bytes
    .toString('base64')
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
  return `axhub_client_${b64}`;
}

export function generateAccessKeyId() {
  return `hak_${crypto.randomBytes(12).toString('hex')}`;
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

function normalizeSnapshotClients(parsed) {
  const arr = Array.isArray(parsed?.clients)
    ? parsed.clients
    : Array.isArray(parsed?.devices)
      ? parsed.devices
      : null;

  if (Array.isArray(arr)) {
    return arr.map((item) => {
      if (typeof item === 'string') return { token: item };
      return item && typeof item === 'object' ? { ...item } : null;
    }).filter(Boolean);
  }

  if (parsed && typeof parsed === 'object' && parsed.devices && typeof parsed.devices === 'object') {
    const rows = [];
    for (const [deviceId, value] of Object.entries(parsed.devices)) {
      if (typeof value === 'string') {
        rows.push({ device_id: deviceId, token: value, enabled: true });
        continue;
      }
      if (value && typeof value === 'object') {
        rows.push({ device_id: deviceId, ...value });
      }
    }
    return rows;
  }

  return [];
}

export function readClientsSnapshot(runtimeBaseDir) {
  const filePath = clientsConfigPath(runtimeBaseDir);
  const parsed = readJsonSafe(filePath);
  if (!parsed || typeof parsed !== 'object') {
    return { schema_version: CLIENTS_SCHEMA_VERSION, updated_at_ms: 0, clients: [] };
  }
  return {
    schema_version: safeString(parsed.schema_version) || CLIENTS_SCHEMA_VERSION,
    updated_at_ms: safeInt(parsed.updated_at_ms, 0),
    clients: normalizeSnapshotClients(parsed),
  };
}

let cache = {
  loaded_at_ms: 0,
  mtime_ms: 0,
  file_path: '',
  clients: null,
};

export function invalidateClientsCache() {
  cache = {
    loaded_at_ms: 0,
    mtime_ms: 0,
    file_path: '',
    clients: null,
  };
}

export function clientsConfigPath(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'hub_grpc_clients.json');
}

export function writeClientsSnapshot(runtimeBaseDir, snapshot) {
  const base = safeString(runtimeBaseDir);
  if (!base) return false;
  const rows = Array.isArray(snapshot?.clients)
    ? snapshot.clients.map((item) => (item && typeof item === 'object' ? { ...item } : null)).filter(Boolean)
    : [];
  const payload = {
    schema_version: safeString(snapshot?.schema_version) || CLIENTS_SCHEMA_VERSION,
    updated_at_ms: safeInt(snapshot?.updated_at_ms, 0) || Date.now(),
    clients: rows,
  };
  const ok = writeJsonAtomic(base, 'hub_grpc_clients.json', payload);
  if (ok) invalidateClientsCache();
  return ok;
}

function resolveEntryIdentity(entry = {}) {
  const deviceId = safeString(entry.device_id || entry.id);
  const accessKeyId = safeString(entry.access_key_id || entry.accessKeyId || entry.client_id || entry.clientId)
    || deviceId;
  return { deviceId, accessKeyId };
}

export function upsertClientInSnapshot(snapshot, entry) {
  const out = snapshot && typeof snapshot === 'object'
    ? {
        schema_version: safeString(snapshot.schema_version) || CLIENTS_SCHEMA_VERSION,
        updated_at_ms: safeInt(snapshot.updated_at_ms, 0),
        clients: Array.isArray(snapshot.clients)
          ? snapshot.clients.map((item) => (item && typeof item === 'object' ? { ...item } : null)).filter(Boolean)
          : [],
      }
    : {
        schema_version: CLIENTS_SCHEMA_VERSION,
        updated_at_ms: 0,
        clients: [],
      };

  const rawEntry = entry && typeof entry === 'object' ? { ...entry } : null;
  const { deviceId, accessKeyId } = resolveEntryIdentity(rawEntry || {});
  if (!rawEntry || (!deviceId && !accessKeyId)) return out;

  const nextEntry = { ...rawEntry };
  if (!nextEntry.device_id && deviceId) nextEntry.device_id = deviceId;
  if (!nextEntry.access_key_id && accessKeyId) nextEntry.access_key_id = accessKeyId;

  let replaced = false;
  out.clients = out.clients.map((current) => {
    const currentIdentity = resolveEntryIdentity(current);
    const accessKeyMatch = accessKeyId && currentIdentity.accessKeyId === accessKeyId;
    const deviceMatch = deviceId && currentIdentity.deviceId === deviceId;
    if (!accessKeyMatch && !deviceMatch) return current;
    replaced = true;
    return {
      ...(current && typeof current === 'object' ? current : {}),
      ...nextEntry,
    };
  });
  if (!replaced) out.clients.push(nextEntry);
  out.updated_at_ms = Date.now();
  return out;
}

function computeClientAuthStatus(client, nowMs = Date.now()) {
  if (!client || typeof client !== 'object') {
    return {
      status: 'invalid',
      reason_code: 'invalid_token',
      usable: false,
    };
  }
  if (safeInt(client.revoked_at_ms, 0) > 0) {
    return {
      status: 'revoked',
      reason_code: 'token_revoked',
      usable: false,
    };
  }
  if (!safeBool(client.enabled, true)) {
    return {
      status: 'disabled',
      reason_code: 'client_disabled',
      usable: false,
    };
  }
  const expiresAtMs = safeInt(client.expires_at_ms, 0);
  if (expiresAtMs > 0 && expiresAtMs <= Math.max(0, Number(nowMs || 0))) {
    return {
      status: 'expired',
      reason_code: 'token_expired',
      usable: false,
    };
  }
  return {
    status: 'ready',
    reason_code: '',
    usable: true,
  };
}

export function getClientAuthStatus(client, nowMs = Date.now()) {
  return computeClientAuthStatus(client, nowMs);
}

export function isClientAuthUsable(client, nowMs = Date.now()) {
  return computeClientAuthStatus(client, nowMs).usable === true;
}

function normalizeClientEntry(raw, fallbackDeviceId = '', nowMs = Date.now()) {
  const src = asObject(raw);
  const hintedAccessKeyId = safeString(src.access_key_id || src.accessKeyId || src.client_id || src.clientId || src.key_id || src.keyId);
  const device_id = safeString(src.device_id || src.id || fallbackDeviceId || hintedAccessKeyId);
  const token = safeString(src.token || src.client_token || src.clientToken);
  if (!device_id || !token) return null;

  const name = safeString(src.name || src.label || src.access_key_label || src.device_name || src.deviceName);
  const capabilities = uniqueStrings(src.capabilities || src.caps || src.allowed_capabilities || src.allowedCapabilities || []);
  const auth_kind = normalizeClientAuthKind(
    src.auth_kind || src.authKind,
    hintedAccessKeyId && hintedAccessKeyId !== device_id ? 'hub_access_key' : 'paired_client'
  );
  const access_key_id = hintedAccessKeyId || device_id;
  const scopes = safeStringArray(
    src.scopes
      || src.allowed_scopes
      || src.allowedScopes
      || capabilities
  );
  const updated_at_ms = safeInt(
    src.updated_at_ms
      || src.updatedAtMs
      || src.last_rotated_at_ms
      || src.lastRotatedAtMs
      || src.last_used_at_ms
      || src.lastUsedAtMs
      || src.created_at_ms
      || src.createdAtMs,
    0
  );
  const expires_at_ms = safeInt(src.expires_at_ms || src.expiresAtMs, 0);
  const last_used_at_ms = safeInt(src.last_used_at_ms || src.lastUsedAtMs, 0);
  const revoked_at_ms = safeInt(src.revoked_at_ms || src.revokedAtMs, 0);
  const status = computeClientAuthStatus({
    enabled: safeBool(src.enabled, true),
    revoked_at_ms,
    expires_at_ms,
  }, nowMs);

  return {
    device_id,
    access_key_id,
    auth_kind,
    user_id: safeString(src.user_id || src.userId) || device_id,
    app_id: safeString(src.app_id || src.appId || src.application_id || src.applicationId),
    name,
    label: name,
    note: safeString(src.note || src.description || src.comment),
    token,
    token_redacted: redactClientToken(token),
    enabled: safeBool(src.enabled, true),
    created_at_ms: safeInt(src.created_at_ms || src.createdAtMs, 0),
    updated_at_ms,
    expires_at_ms,
    last_used_at_ms,
    last_used_peer_ip: safeString(src.last_used_peer_ip || src.lastUsedPeerIp),
    last_used_transport: safeString(src.last_used_transport || src.lastUsedTransport),
    revoked_at_ms,
    revoke_reason: safeString(src.revoke_reason || src.revokeReason),
    revoked_by_user_id: safeString(src.revoked_by_user_id || src.revokedByUserId),
    revoked_via: safeString(src.revoked_via || src.revokedVia),
    created_by_user_id: safeString(src.created_by_user_id || src.createdByUserId),
    created_by_app_id: safeString(src.created_by_app_id || src.createdByAppId),
    created_via: safeString(src.created_via || src.createdVia),
    last_rotated_at_ms: safeInt(src.last_rotated_at_ms || src.lastRotatedAtMs, 0),
    rotation_count: safeInt(src.rotation_count || src.rotationCount, 0),
    allowed_cidrs: safeStringArray(src.allowed_cidrs || src.allowedCidrs || src.allowed_ip_cidrs || src.allowedIpCidrs),
    scopes,
    capabilities,
    cert_sha256: safeString(src.cert_sha256 || src.certSha256 || src.cert_fingerprint_sha256 || src.certFingerprintSha256),
    status: status.status,
    status_reason: status.reason_code,
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
    return cache.clients.map((item) => ({
      ...item,
      ...computeClientAuthStatus(item, Date.now()),
      status_reason: computeClientAuthStatus(item, Date.now()).reason_code,
    }));
  }

  const snapshot = readClientsSnapshot(runtimeBaseDir);
  const clients = [];
  for (const item of snapshot.clients) {
    const normalized = normalizeClientEntry(item, '', now);
    if (normalized) clients.push(normalized);
  }

  cache = { loaded_at_ms: now, mtime_ms: mtimeMs, file_path: filePath, clients };
  return clients;
}

export function findClientByToken(runtimeBaseDir, token) {
  const wantedToken = safeString(token);
  if (!wantedToken) return null;
  for (const client of loadClients(runtimeBaseDir)) {
    if (safeString(client.token) === wantedToken) return client;
  }
  return null;
}

export function findClientByAccessKeyId(runtimeBaseDir, accessKeyId) {
  const wanted = safeString(accessKeyId);
  if (!wanted) return null;
  for (const client of loadClients(runtimeBaseDir)) {
    if (safeString(client.access_key_id) === wanted) return client;
    if (safeString(client.device_id) === wanted) return client;
  }
  return null;
}

export function touchClientUsageByToken(runtimeBaseDir, token, fields = {}, options = {}) {
  const wantedToken = safeString(token);
  if (!wantedToken) return null;

  const now = Date.now();
  const minIntervalMs = Math.max(
    0,
    safeInt(options.min_interval_ms || options.minIntervalMs, DEFAULT_USAGE_WRITE_INTERVAL_MS)
  );
  const snapshot = readClientsSnapshot(runtimeBaseDir);
  if (!Array.isArray(snapshot.clients) || snapshot.clients.length === 0) return null;

  let touched = null;
  let changed = false;
  snapshot.clients = snapshot.clients.map((item) => {
    const src = item && typeof item === 'object' ? { ...item } : null;
    if (!src) return item;
    const currentToken = safeString(src.token || src.client_token || src.clientToken);
    if (currentToken !== wantedToken) return item;

    const previousUsedAtMs = safeInt(src.last_used_at_ms || src.lastUsedAtMs, 0);
    if (previousUsedAtMs > 0 && now - previousUsedAtMs < minIntervalMs) {
      touched = normalizeClientEntry(src, '', now);
      return src;
    }

    src.last_used_at_ms = now;
    if (fields.peer_ip != null) src.last_used_peer_ip = safeString(fields.peer_ip);
    if (fields.transport != null) src.last_used_transport = safeString(fields.transport);
    src.updated_at_ms = now;
    touched = normalizeClientEntry(src, '', now);
    changed = true;
    return src;
  });

  if (changed) {
    snapshot.updated_at_ms = now;
    writeClientsSnapshot(runtimeBaseDir, snapshot);
  }
  return touched;
}
