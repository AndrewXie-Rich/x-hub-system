import fs from 'node:fs';
import path from 'node:path';

import {
  getSupervisorOperatorChannelBindingById,
  normalizeSupervisorScopeType,
  resolveSupervisorOperatorChannelBinding,
} from './channel_bindings_store.js';
import { getChannelActionPolicy } from './channel_command_gate.js';
import { loadClients } from './clients.js';
import {
  SUPERVISOR_CHANNEL_SESSION_ROUTE_SCHEMA,
  normalizeSupervisorChannelRouteMode,
  upsertSupervisorChannelSessionRoute,
} from './supervisor_channel_session_store.js';
import { buildSupervisorRouteGovernanceRuntimeReadinessProjection } from './governance_runtime_readiness_projection.js';
import { nowMs } from './util.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

function safeStringArray(input) {
  const rows = Array.isArray(input) ? input : [];
  const out = [];
  const seen = new Set();
  for (const raw of rows) {
    const text = safeString(raw);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

function normalizeDevicesStatusSnapshot(input = {}) {
  const src = input && typeof input === 'object' ? input : {};
  const rows = Array.isArray(src.devices) ? src.devices : [];
  return {
    schema_version: safeString(src.schema_version || 'grpc_devices_status.v2') || 'grpc_devices_status.v2',
    updated_at_ms: safeInt(src.updated_at_ms, 0),
    devices: rows.map((row) => ({
      device_id: safeString(row?.device_id),
      connected: safeBool(row?.connected, false),
      last_seen_at_ms: safeInt(row?.last_seen_at_ms, 0),
      connected_at_ms: safeInt(row?.connected_at_ms, 0),
    })).filter((row) => row.device_id),
  };
}

export function loadGrpcDevicesStatusSnapshot(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return normalizeDevicesStatusSnapshot();
  const filePath = path.join(base, 'grpc_devices_status.json');
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return normalizeDevicesStatusSnapshot(JSON.parse(raw));
  } catch {
    return normalizeDevicesStatusSnapshot();
  }
}

function buildRoutableDevices({
  runtimeBaseDir = '',
  clients_snapshot = null,
  devices_status_snapshot = null,
} = {}) {
  const clients = Array.isArray(clients_snapshot) ? clients_snapshot : loadClients(runtimeBaseDir, 0);
  const deviceStatus = devices_status_snapshot
    ? normalizeDevicesStatusSnapshot(devices_status_snapshot)
    : loadGrpcDevicesStatusSnapshot(runtimeBaseDir);
  const byStatus = new Map(
    (deviceStatus.devices || []).map((row) => [row.device_id, row])
  );

  const devices = [];
  for (const client of Array.isArray(clients) ? clients : []) {
    const status = byStatus.get(safeString(client?.device_id)) || null;
    devices.push({
      device_id: safeString(client?.device_id),
      enabled: safeBool(client?.enabled, true),
      connected: safeBool(status?.connected, false),
      xt_online: safeBool(client?.enabled, true) && safeBool(status?.connected, false),
      last_seen_at_ms: safeInt(status?.last_seen_at_ms, 0),
      trusted_automation_mode: safeString(client?.trusted_automation_mode).toLowerCase(),
      trusted_automation_state: safeString(client?.trusted_automation_state).toLowerCase(),
      xt_binding_required: safeBool(client?.xt_binding_required, false),
      device_permission_owner_ref: safeString(client?.device_permission_owner_ref),
      allowed_project_ids: safeStringArray(client?.allowed_project_ids || []),
      trust_profile_present: safeBool(client?.trust_profile_present, !!client?.approved_trust_profile),
    });
  }
  return devices;
}

function resolveActionRouteMode(action_name) {
  const policy = getChannelActionPolicy(action_name);
  return normalizeSupervisorChannelRouteMode(policy?.route_mode, 'hub_only_status');
}

function resolveScopeProjectId(binding, route_context = {}) {
  const explicitProjectId = safeString(route_context.project_id || route_context.root_project_id);
  if (explicitProjectId) return explicitProjectId;
  if (safeString(binding?.scope_type) === 'project') return safeString(binding?.scope_id);
  return '';
}

function deviceSupportsProjectScope(device, projectId) {
  const project = safeString(projectId);
  const allowed = safeStringArray(device?.allowed_project_ids || []);
  if (!project) return true;
  if (!allowed.length) return true;
  return allowed.includes(project);
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

function resolveRouteScopeType(binding, route_context = {}) {
  return normalizeSupervisorScopeType(
    route_context.scope_type || binding?.scope_type,
    binding?.scope_type || 'project'
  );
}

function routeRequiresScopeSwitch(binding, action_name, route_context = {}) {
  const policy = getChannelActionPolicy(action_name);
  const allowedScopeTypes = normalizeAllowedScopeTypes(policy);
  if (!policy || !allowedScopeTypes.length) return false;
  return !allowedScopeTypes.includes(resolveRouteScopeType(binding, route_context));
}

function runnerReadyForScope(device, projectId) {
  if (!device) {
    return {
      ready: false,
      deny_code: 'runner_device_missing',
    };
  }
  if (!device.xt_online) {
    return {
      ready: false,
      deny_code: 'preferred_device_offline',
    };
  }
  if (safeString(device.trusted_automation_mode) !== 'trusted_automation') {
    return {
      ready: false,
      deny_code: 'trusted_automation_mode_off',
    };
  }
  const state = safeString(device.trusted_automation_state);
  if (!state || state === 'off' || state === 'blocked') {
    return {
      ready: false,
      deny_code: 'trusted_automation_mode_off',
    };
  }
  if (device.xt_binding_required && !safeString(device.device_permission_owner_ref)) {
    return {
      ready: false,
      deny_code: 'device_permission_owner_missing',
    };
  }
  const allowedProjects = safeStringArray(device.allowed_project_ids || []);
  const scopeProjectId = safeString(projectId);
  if (device.xt_binding_required && !allowedProjects.length) {
    return {
      ready: false,
      deny_code: 'trusted_automation_project_not_bound',
    };
  }
  if (scopeProjectId && allowedProjects.length && !allowedProjects.includes(scopeProjectId)) {
    return {
      ready: false,
      deny_code: 'trusted_automation_project_not_bound',
    };
  }
  return {
    ready: true,
    deny_code: '',
  };
}

function selectDevice({
  devices = [],
  preferred_device_id = '',
  scope_type = '',
  scope_id = '',
  route_mode = 'hub_only_status',
  project_id = '',
} = {}) {
  const preferredId = safeString(preferred_device_id)
    || (safeString(scope_type) === 'device' ? safeString(scope_id) : '');
  const byId = new Map(devices.map((row) => [row.device_id, row]));
  const explicit = preferredId ? (byId.get(preferredId) || null) : null;
  if (explicit) {
    return {
      device: explicit,
      selected_by: preferred_device_id ? 'preferred_device' : 'scope_device',
      same_project_scope: deviceSupportsProjectScope(explicit, project_id),
      explicit_preferred: !!preferred_device_id,
    };
  }

  if (route_mode === 'hub_only_status') {
    return {
      device: null,
      selected_by: 'none',
      same_project_scope: false,
      explicit_preferred: false,
    };
  }

  const scopeAware = devices.filter((device) => {
    if (!device.xt_online) return false;
    if (route_mode === 'hub_to_runner') {
      return runnerReadyForScope(device, project_id).ready;
    }
    return deviceSupportsProjectScope(device, project_id);
  });
  if (scopeAware.length === 1) {
    return {
      device: scopeAware[0],
      selected_by: 'single_candidate',
      same_project_scope: route_mode === 'hub_to_runner'
        ? runnerReadyForScope(scopeAware[0], project_id).ready
        : deviceSupportsProjectScope(scopeAware[0], project_id),
      explicit_preferred: false,
    };
  }
  return {
    device: null,
    selected_by: scopeAware.length > 1 ? 'ambiguous' : 'none',
    same_project_scope: false,
    explicit_preferred: false,
  };
}

function buildRouteResult({
  binding,
  action_name,
  route_mode,
  resolved_device_id = '',
  xt_online = false,
  runner_required = false,
  same_project_scope = false,
  deny_code = '',
  selected_by = 'none',
  governance_runtime_readiness = null,
} = {}) {
  return {
    schema_version: SUPERVISOR_CHANNEL_SESSION_ROUTE_SCHEMA,
    route_id: '',
    provider: safeString(binding?.provider),
    account_id: safeString(binding?.account_id),
    conversation_id: safeString(binding?.conversation_id),
    thread_key: safeString(binding?.thread_key),
    scope_type: safeString(binding?.scope_type),
    scope_id: safeString(binding?.scope_id),
    supervisor_session_id: '',
    preferred_device_id: safeString(binding?.preferred_device_id),
    resolved_device_id: safeString(resolved_device_id),
    route_mode: normalizeSupervisorChannelRouteMode(route_mode, 'hub_only_status'),
    xt_online: !!xt_online,
    runner_required: !!runner_required,
    same_project_scope: !!same_project_scope,
    deny_code: safeString(deny_code),
    action_name: safeString(action_name).toLowerCase(),
    selected_by,
    governance_runtime_readiness: governance_runtime_readiness && typeof governance_runtime_readiness === 'object'
      ? governance_runtime_readiness
      : null,
    updated_at_ms: nowMs(),
  };
}

export function resolveSupervisorChannelRoute({
  db = null,
  binding = null,
  binding_id = '',
  route_context = {},
  action_name = '',
  runtimeBaseDir = '',
  clients_snapshot = null,
  devices_status_snapshot = null,
} = {}) {
  const channelBinding = (() => {
    if (binding && typeof binding === 'object') return binding;
    if (db && binding_id) {
      return getSupervisorOperatorChannelBindingById(db, { binding_id });
    }
    if (db && route_context?.provider && route_context?.conversation_id) {
      return resolveSupervisorOperatorChannelBinding(db, {
        provider: route_context.provider,
        account_id: route_context.account_id,
        conversation_id: route_context.conversation_id,
        thread_key: route_context.thread_key,
        channel_scope: route_context.channel_scope,
      }).binding;
    }
    return null;
  })();

  if (!channelBinding) {
    return buildRouteResult({
      binding: route_context,
      action_name,
      route_mode: 'hub_only_status',
      deny_code: 'channel_binding_missing',
      selected_by: 'none',
    });
  }

  const actionRouteMode = resolveActionRouteMode(action_name);
  if (routeRequiresScopeSwitch(channelBinding, action_name, route_context)) {
    return buildRouteResult({
      binding: channelBinding,
      action_name,
      route_mode: 'hub_only_status',
      deny_code: 'scope_switch_required',
      selected_by: 'none',
    });
  }
  const scopeProjectId = resolveScopeProjectId(channelBinding, route_context);
  const devices = buildRoutableDevices({
    runtimeBaseDir,
    clients_snapshot,
    devices_status_snapshot,
  });
  const selection = selectDevice({
    devices,
    preferred_device_id: channelBinding.preferred_device_id,
    scope_type: channelBinding.scope_type,
    scope_id: channelBinding.scope_id,
    route_mode: actionRouteMode,
    project_id: scopeProjectId,
  });
  const buildRouteGovernanceRuntimeReadiness = ({
    route_mode,
    resolved_device_id = '',
    xt_online = false,
    runner_required = false,
    same_project_scope = false,
    deny_code = '',
    selected_by = selection.selected_by,
    device = selection.device,
  } = {}) => {
    const routePreview = {
      project_id: scopeProjectId,
      decision: safeString(route_mode),
      preferred_device_id: safeString(channelBinding.preferred_device_id || (safeString(channelBinding.scope_type) === 'device' ? channelBinding.scope_id : '')),
      resolved_device_id: safeString(resolved_device_id),
      runner_required: !!runner_required,
      xt_online: !!xt_online,
      same_project_scope: !!same_project_scope,
      deny_code: safeString(deny_code),
      selected_by: safeString(selected_by),
    };
    return buildSupervisorRouteGovernanceRuntimeReadinessProjection({
      route: routePreview,
      intent: safeString(action_name),
      require_xt: actionRouteMode === 'hub_to_xt' || actionRouteMode === 'hub_to_runner',
      require_runner: actionRouteMode === 'hub_to_runner',
      auth_kind: 'client',
      client_capability: 'events',
      trust_profile_present: !!device?.trust_profile_present,
      trusted_automation_mode: safeString(device?.trusted_automation_mode),
      trusted_automation_state: safeString(device?.trusted_automation_state),
    });
  };

  if (actionRouteMode === 'hub_only_status') {
    const xtOnline = !!selection.device?.xt_online;
    return buildRouteResult({
      binding: channelBinding,
      action_name,
      route_mode: 'hub_only_status',
      resolved_device_id: selection.device?.device_id || '',
      xt_online: xtOnline,
      runner_required: false,
      same_project_scope: selection.device
        ? deviceSupportsProjectScope(selection.device, scopeProjectId)
        : false,
      deny_code: '',
      selected_by: selection.selected_by,
      governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
        route_mode: 'hub_only_status',
        resolved_device_id: selection.device?.device_id || '',
        xt_online: xtOnline,
        runner_required: false,
        same_project_scope: selection.device
          ? deviceSupportsProjectScope(selection.device, scopeProjectId)
          : false,
        deny_code: '',
        device: selection.device,
      }),
    });
  }

  if (actionRouteMode === 'hub_to_xt') {
    if (!selection.device) {
      return buildRouteResult({
        binding: channelBinding,
        action_name,
        route_mode: 'xt_offline',
        deny_code: selection.selected_by === 'ambiguous'
          ? 'project_device_ambiguous'
          : 'preferred_device_missing',
        selected_by: selection.selected_by,
        governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
          route_mode: 'xt_offline',
          deny_code: selection.selected_by === 'ambiguous'
            ? 'project_device_ambiguous'
            : 'preferred_device_missing',
          device: null,
        }),
      });
    }
    if (!selection.device.xt_online) {
      return buildRouteResult({
        binding: channelBinding,
        action_name,
        route_mode: 'xt_offline',
        resolved_device_id: selection.device.device_id,
        xt_online: false,
        same_project_scope: selection.same_project_scope,
        deny_code: 'preferred_device_offline',
        selected_by: selection.selected_by,
        governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
          route_mode: 'xt_offline',
          resolved_device_id: selection.device.device_id,
          xt_online: false,
          same_project_scope: selection.same_project_scope,
          deny_code: 'preferred_device_offline',
          device: selection.device,
        }),
      });
    }
    if (!selection.same_project_scope) {
      return buildRouteResult({
        binding: channelBinding,
        action_name,
        route_mode: 'xt_offline',
        resolved_device_id: selection.device.device_id,
        xt_online: true,
        same_project_scope: false,
        deny_code: 'preferred_device_project_scope_mismatch',
        selected_by: selection.selected_by,
        governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
          route_mode: 'xt_offline',
          resolved_device_id: selection.device.device_id,
          xt_online: true,
          same_project_scope: false,
          deny_code: 'preferred_device_project_scope_mismatch',
          device: selection.device,
        }),
      });
    }
    return buildRouteResult({
      binding: channelBinding,
      action_name,
      route_mode: 'hub_to_xt',
      resolved_device_id: selection.device.device_id,
      xt_online: true,
      runner_required: false,
      same_project_scope: true,
      deny_code: '',
      selected_by: selection.selected_by,
      governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
        route_mode: 'hub_to_xt',
        resolved_device_id: selection.device.device_id,
        xt_online: true,
        runner_required: false,
        same_project_scope: true,
        deny_code: '',
        device: selection.device,
      }),
    });
  }

  const runnerDevice = selection.device;
  const runnerReadiness = runnerReadyForScope(runnerDevice, scopeProjectId);
  if (!runnerDevice) {
    return buildRouteResult({
      binding: channelBinding,
      action_name,
      route_mode: 'runner_not_ready',
      runner_required: true,
      deny_code: selection.selected_by === 'ambiguous'
        ? 'runner_device_ambiguous'
        : 'runner_device_missing',
      selected_by: selection.selected_by,
      governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
        route_mode: 'runner_not_ready',
        runner_required: true,
        deny_code: selection.selected_by === 'ambiguous'
          ? 'runner_device_ambiguous'
          : 'runner_device_missing',
        device: null,
      }),
    });
  }
  if (!runnerDevice.xt_online) {
    return buildRouteResult({
      binding: channelBinding,
      action_name,
      route_mode: 'xt_offline',
      resolved_device_id: runnerDevice.device_id,
      xt_online: false,
      runner_required: true,
      same_project_scope: selection.same_project_scope,
      deny_code: 'preferred_device_offline',
      selected_by: selection.selected_by,
      governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
        route_mode: 'xt_offline',
        resolved_device_id: runnerDevice.device_id,
        xt_online: false,
        runner_required: true,
        same_project_scope: selection.same_project_scope,
        deny_code: 'preferred_device_offline',
        device: runnerDevice,
      }),
    });
  }
  if (!runnerReadiness.ready) {
    return buildRouteResult({
      binding: channelBinding,
      action_name,
      route_mode: 'runner_not_ready',
      resolved_device_id: runnerDevice.device_id,
      xt_online: true,
      runner_required: true,
      same_project_scope: selection.same_project_scope,
      deny_code: runnerReadiness.deny_code,
      selected_by: selection.selected_by,
      governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
        route_mode: 'runner_not_ready',
        resolved_device_id: runnerDevice.device_id,
        xt_online: true,
        runner_required: true,
        same_project_scope: selection.same_project_scope,
        deny_code: runnerReadiness.deny_code,
        device: runnerDevice,
      }),
    });
  }
  return buildRouteResult({
    binding: channelBinding,
    action_name,
    route_mode: 'hub_to_runner',
    resolved_device_id: runnerDevice.device_id,
    xt_online: true,
    runner_required: true,
    same_project_scope: true,
    deny_code: '',
    selected_by: selection.selected_by,
    governance_runtime_readiness: buildRouteGovernanceRuntimeReadiness({
      route_mode: 'hub_to_runner',
      resolved_device_id: runnerDevice.device_id,
      xt_online: true,
      runner_required: true,
      same_project_scope: true,
      deny_code: '',
      device: runnerDevice,
    }),
  });
}

export function evaluateSupervisorChannelRouteWithStore({
  db,
  binding = null,
  binding_id = '',
  route_context = {},
  action_name = '',
  runtimeBaseDir = '',
  clients_snapshot = null,
  devices_status_snapshot = null,
  audit = {},
  request_id = '',
} = {}) {
  const resolved = resolveSupervisorChannelRoute({
    db,
    binding,
    binding_id,
    route_context,
    action_name,
    runtimeBaseDir,
    clients_snapshot,
    devices_status_snapshot,
  });
  if (!db) {
    return {
      ok: true,
      deny_code: '',
      detail: {},
      route: resolved,
      audit_logged: false,
      created: false,
      updated: false,
    };
  }
  return upsertSupervisorChannelSessionRoute(db, {
    route: resolved,
    audit,
    request_id,
  });
}
