function safeString(value) {
  return String(value ?? '').trim();
}

function uniqueOrdered(values) {
  const out = [];
  const seen = new Set();
  for (const raw of Array.isArray(values) ? values : []) {
    const value = safeString(raw);
    if (!value || seen.has(value)) continue;
    seen.add(value);
    out.push(value);
  }
  return out;
}

const XT_COMPONENT_KEY_BY_PLANE = Object.freeze({
  route: 'route_ready',
  capability: 'capability_ready',
  grant: 'grant_ready',
  checkpoint_recovery: 'checkpoint_recovery_ready',
  evidence_export: 'evidence_export_ready',
});

function displayNameForPlane(plane) {
  switch (safeString(plane)) {
    case 'route':
      return 'route readiness';
    case 'capability':
      return 'capability readiness';
    case 'grant':
      return 'grant readiness';
    case 'checkpoint_recovery':
      return 'checkpoint / recovery readiness';
    case 'evidence_export':
      return 'evidence / export readiness';
    default:
      return safeString(plane) || 'readiness';
  }
}

export function governanceRuntimeReasonText(code) {
  switch (safeString(code)) {
    case 'governance_fail_closed':
      return '治理冲突触发 fail-closed';
    case 'runtime_surface_not_configured_full':
      return '完整执行面还没配置到 trusted_openclaw_mode';
    case 'runtime_surface_kill_switch':
      return 'kill-switch 已生效';
    case 'runtime_surface_ttl_expired':
      return 'runtime surface TTL 已过期';
    case 'runtime_surface_clamped_guided':
      return '执行面被收束到 guided';
    case 'runtime_surface_clamped_manual':
      return '执行面被收束到 manual';
    case 'trusted_automation_not_ready':
      return '受治理自动化未就绪';
    case 'permission_owner_not_ready':
      return '权限宿主未就绪';
    case 'capability_device_tools_unavailable':
      return 'A4 基线 device tools 未打开';
    case 'checkpoint_recovery_contract_not_ready':
      return 'checkpoint / recovery 合同还没就绪';
    case 'evidence_export_contract_not_ready':
      return 'evidence / export 合同还没就绪';
    case 'legacy_grant_flow_required':
      return '旧版 grant 链路仍未切走';
    case 'trusted_automation_capabilities_empty_blocked':
      return 'trusted automation 明确能力清单为空';
    case 'trusted_automation_profile_missing':
      return 'trusted automation profile 缺失';
    case 'trusted_automation_mode_off':
      return 'trusted automation 未开启';
    case 'trusted_automation_project_not_bound':
      return 'trusted automation 未绑定当前 project';
    case 'trusted_automation_workspace_mismatch':
      return 'trusted automation workspace 不匹配';
    case 'device_permission_owner_missing':
      return 'XT binding 需要本地 permission owner';
    case 'events_capability_missing':
      return 'events capability 缺失';
    case 'memory_capability_missing':
      return 'memory capability 缺失';
    case 'permission_denied':
      return '请求能力未授权';
    case 'kill_switch_active':
      return 'kill-switch 已阻断当前执行';
    default:
      return safeString(code).replaceAll('_', ' ');
  }
}

export function governanceRuntimeReasonSummary(codes) {
  const normalized = uniqueOrdered(codes).map(governanceRuntimeReasonText);
  return normalized.length > 0 ? normalized.join(' / ') : '无';
}

export function governanceRuntimePlaneForDenyCode(denyCode, preferredPlane = '') {
  const preferred = safeString(preferredPlane);
  if (preferred && XT_COMPONENT_KEY_BY_PLANE[preferred]) return preferred;

  const raw = safeString(denyCode);
  if (!raw) return '';
  if (
    raw === 'runtime_surface_not_configured_full'
    || raw === 'runtime_surface_clamped_guided'
    || raw === 'runtime_surface_clamped_manual'
  ) {
    return 'route';
  }
  if (
    raw === 'trusted_automation_capabilities_empty_blocked'
    || raw === 'permission_denied'
    || raw === 'capability_blocked'
  ) {
    return 'capability';
  }
  if (
    raw === 'governance_fail_closed'
    || raw === 'runtime_surface_kill_switch'
    || raw === 'kill_switch_active'
    || raw === 'runtime_surface_ttl_expired'
    || raw === 'legacy_grant_flow_required'
    || raw === 'device_permission_owner_missing'
    || raw.startsWith('trusted_automation_')
  ) {
    return 'grant';
  }
  if (
    raw === 'checkpoint_recovery_contract_not_ready'
    || raw === 'events_capability_missing'
  ) {
    return 'checkpoint_recovery';
  }
  if (
    raw === 'evidence_export_contract_not_ready'
    || raw === 'memory_capability_missing'
  ) {
    return 'evidence_export';
  }
  return '';
}

export function supervisorRouteGovernanceComponentForDenyCode(denyCode = '') {
  const raw = safeString(denyCode);
  if (!raw) return '';
  if ([
    'trusted_automation_mode_off',
    'trusted_automation_project_not_bound',
    'device_permission_owner_missing',
    'preferred_device_project_scope_mismatch',
  ].includes(raw)) {
    return 'grant';
  }
  if ([
    'supervisor_intent_unknown',
    'project_id_required',
    'preferred_device_missing',
    'preferred_device_offline',
    'xt_device_missing',
    'runner_device_missing',
    'xt_route_ambiguous',
    'runner_route_ambiguous',
  ].includes(raw)) {
    return 'route';
  }
  return '';
}

export function governanceRuntimeMissingReasonCodesForPlane(plane, denyCode) {
  const resolvedPlane = governanceRuntimePlaneForDenyCode(denyCode, plane);
  const raw = safeString(denyCode);
  if (!raw) return [];

  if (raw === 'trusted_automation_capabilities_empty_blocked') {
    return ['capability_device_tools_unavailable'];
  }
  if (raw === 'device_permission_owner_missing') {
    return ['permission_owner_not_ready'];
  }
  if (
    raw === 'trusted_automation_profile_missing'
    || raw === 'trusted_automation_mode_off'
    || raw === 'trusted_automation_project_not_bound'
    || raw === 'trusted_automation_workspace_mismatch'
  ) {
    return ['trusted_automation_not_ready'];
  }
  if (raw === 'kill_switch_active') {
    return ['runtime_surface_kill_switch'];
  }
  if (raw === 'events_capability_missing' && resolvedPlane === 'checkpoint_recovery') {
    return ['checkpoint_recovery_contract_not_ready'];
  }
  if (raw === 'memory_capability_missing' && resolvedPlane === 'checkpoint_recovery') {
    return ['checkpoint_recovery_contract_not_ready'];
  }
  if (raw === 'memory_capability_missing' && resolvedPlane === 'evidence_export') {
    return ['evidence_export_contract_not_ready'];
  }
  return [raw];
}

export function augmentGovernanceRuntimeComponent(plane, component = {}) {
  const resolvedPlane = safeString(plane);
  const current = component && typeof component === 'object' ? component : {};
  const required = current.required !== false;
  const ready = current.ready === true;
  const reported = current.reported !== false;
  const denyCode = safeString(current.deny_code);
  const xtComponentKey = XT_COMPONENT_KEY_BY_PLANE[resolvedPlane] || '';
  const missingReasonCodes = reported && required && !ready
    ? governanceRuntimeMissingReasonCodesForPlane(resolvedPlane, denyCode)
    : [];
  const sourceDenyCodes = denyCode ? [denyCode] : [];

  let state = 'not_reported';
  if (reported) {
    state = required ? (ready ? 'ready' : 'blocked') : 'not_required';
  }

  let summaryLine = safeString(current.summary);
  if (!summaryLine) {
    const label = displayNameForPlane(resolvedPlane);
    switch (state) {
      case 'ready':
        summaryLine = `${label} 已就绪。`;
        break;
      case 'blocked':
        summaryLine = `当前还缺 ${governanceRuntimeReasonSummary(missingReasonCodes)}${denyCode ? `；原始 deny=${denyCode}` : ''}。`;
        break;
      case 'not_required':
        summaryLine = `当前路径不要求 ${label}。`;
        break;
      default:
        summaryLine = `当前 deny 链路未返回 ${label} 检查结果。`;
        break;
    }
  }

  return {
    ...current,
    component: resolvedPlane,
    xt_component_key: xtComponentKey,
    state,
    missing_reason_codes: uniqueOrdered(missingReasonCodes),
    source_deny_codes: sourceDenyCodes,
    summary_line: summaryLine,
  };
}

export function buildGovernanceRuntimeReadinessProjection({
  schema_version = 'xhub.governance_runtime_readiness.v1',
  source = 'hub',
  governance_surface = 'a4_agent',
  context = '',
  configured = false,
  project_id = '',
  workspace_root = '',
  components = {},
} = {}) {
  const planes = Object.keys(XT_COMPONENT_KEY_BY_PLANE);
  const augmentedComponents = {};
  for (const plane of planes) {
    augmentedComponents[plane] = augmentGovernanceRuntimeComponent(plane, components[plane] || {
      component: plane,
      required: false,
      ready: false,
      reported: false,
      deny_code: '',
      summary: '',
    });
  }

  const blockers = [];
  const missingReasonCodes = [];
  const blockedComponentKeys = [];
  const componentsByXTKey = {};

  for (const plane of planes) {
    const component = augmentedComponents[plane];
    const xtComponentKey = safeString(component.xt_component_key);
    if (xtComponentKey) componentsByXTKey[xtComponentKey] = component;
    if (component.required && component.ready !== true) {
      const denyCode = safeString(component.deny_code);
      blockers.push(denyCode ? `${plane}:${denyCode}` : plane);
    }
    if (component.state === 'blocked') {
      if (xtComponentKey) blockedComponentKeys.push(xtComponentKey);
      missingReasonCodes.push(...(Array.isArray(component.missing_reason_codes) ? component.missing_reason_codes : []));
    }
  }

  const uniqueMissingReasonCodes = uniqueOrdered(missingReasonCodes);
  const runtimeReady = !!configured && blockers.length === 0;
  const state = !configured ? 'not_required' : (runtimeReady ? 'ready' : 'blocked');
  const summaryLine = state === 'not_required'
    ? '当前没有 project scope 绑定，不要求 A4 runtime readiness。'
    : (state === 'ready'
      ? 'A4 Agent runtime readiness 已就绪。'
      : 'A4 Agent runtime readiness 仍有缺口。');

  return {
    schema_version: safeString(schema_version) || 'xhub.governance_runtime_readiness.v1',
    source: safeString(source) || 'hub',
    governance_surface: safeString(governance_surface) || 'a4_agent',
    context: safeString(context),
    configured: !!configured,
    state,
    runtime_ready: runtimeReady,
    project_id: safeString(project_id),
    workspace_root: safeString(workspace_root),
    blockers,
    blocked_component_keys: blockedComponentKeys,
    missing_reason_codes: uniqueMissingReasonCodes,
    summary_line: summaryLine,
    missing_summary_line: state === 'blocked'
      ? `缺口：${governanceRuntimeReasonSummary(uniqueMissingReasonCodes)}`
      : '',
    components: augmentedComponents,
    components_by_xt_key: componentsByXTKey,
  };
}

export function buildGovernanceRuntimeReadinessFromDenyCode({
  rawDenyCode = '',
  plane = '',
  source = 'hub',
  context = 'deny',
  governance_surface = 'a4_agent',
  project_id = '',
  workspace_root = '',
} = {}) {
  const denyCode = safeString(rawDenyCode);
  if (!denyCode) return null;
  const resolvedPlane = governanceRuntimePlaneForDenyCode(denyCode, plane);
  if (!resolvedPlane) return null;

  const components = {};
  for (const currentPlane of Object.keys(XT_COMPONENT_KEY_BY_PLANE)) {
    components[currentPlane] = currentPlane === resolvedPlane
      ? {
          component: currentPlane,
          required: true,
          ready: false,
          reported: true,
          deny_code: denyCode,
          summary: '',
        }
      : {
          component: currentPlane,
          required: false,
          ready: false,
          reported: false,
          deny_code: '',
          summary: '',
        };
  }

  return buildGovernanceRuntimeReadinessProjection({
    source,
    governance_surface,
    context,
    configured: true,
    project_id,
    workspace_root,
    components,
  });
}

export function buildSupervisorRouteGovernanceRuntimeReadinessProjection({
  route = {},
  intent = '',
  require_xt = false,
  require_runner = false,
  auth_kind = '',
  client_capability = 'events',
  trust_profile_present = false,
  trusted_automation_mode = '',
  trusted_automation_state = '',
} = {}) {
  const configured = !!require_xt || !!require_runner;
  const denyCode = safeString(route?.deny_code);
  const deniedComponent = supervisorRouteGovernanceComponentForDenyCode(denyCode)
    || (denyCode ? 'route' : '');
  const routePlaneDenyCode = deniedComponent === 'route' ? denyCode : '';
  const grantPlaneDenyCode = deniedComponent === 'grant' ? denyCode : '';

  return buildGovernanceRuntimeReadinessProjection({
    schema_version: 'xhub.governance_runtime_readiness.v1',
    source: 'hub',
    governance_surface: 'a4_agent',
    context: 'supervisor_route',
    configured,
    project_id: safeString(route?.project_id),
    workspace_root: '',
    components: {
      route: {
        component: 'route',
        required: configured,
        ready: configured ? !routePlaneDenyCode : true,
        deny_code: configured ? routePlaneDenyCode : '',
        summary: configured
          ? (!routePlaneDenyCode
              ? `supervisor route ready: ${safeString(route?.decision) || 'hub_only'}`
              : `supervisor route blocked: ${routePlaneDenyCode}`)
          : 'hub_only_route_not_requested',
        decision: safeString(route?.decision),
        intent: safeString(intent),
        preferred_device_id: safeString(route?.preferred_device_id),
        resolved_device_id: safeString(route?.resolved_device_id),
        runner_required: !!route?.runner_required,
        xt_online: !!route?.xt_online,
        same_project_scope: !!route?.same_project_scope,
      },
      capability: {
        component: 'capability',
        required: configured,
        ready: true,
        deny_code: '',
        summary: configured
          ? 'supervisor control-plane surface ready'
          : 'hub_only_route_not_requested',
        auth_kind: safeString(auth_kind),
        client_capability: safeString(client_capability || 'events'),
      },
      grant: {
        component: 'grant',
        required: configured,
        ready: configured ? !grantPlaneDenyCode : true,
        deny_code: configured ? grantPlaneDenyCode : '',
        summary: configured
          ? (!grantPlaneDenyCode
              ? 'supervisor route governance gate armed'
              : `supervisor route governance blocked: ${grantPlaneDenyCode}`)
          : 'hub_only_route_not_requested',
        auth_kind: safeString(auth_kind),
        trust_profile_present: !!trust_profile_present,
        trusted_automation_mode: safeString(trusted_automation_mode),
        trusted_automation_state: safeString(trusted_automation_state),
      },
      checkpoint_recovery: {
        component: 'checkpoint_recovery',
        required: configured,
        ready: true,
        deny_code: '',
        summary: configured
          ? 'supervisor route decision is checkpoint/retry ready'
          : 'hub_only_route_not_requested',
        audit_ref_present: !!safeString(route?.audit_ref),
        request_id_present: !!safeString(route?.request_id),
        retry_supported: true,
      },
      evidence_export: {
        component: 'evidence_export',
        required: configured,
        ready: true,
        deny_code: '',
        summary: configured
          ? 'supervisor route decision is audit-backed'
          : 'hub_only_route_not_requested',
        audit_ref_present: !!safeString(route?.audit_ref),
        audit_trail_available: true,
      },
    },
  });
}
