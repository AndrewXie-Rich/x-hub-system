function safeString(value) {
  return String(value == null ? '' : value).trim();
}

function safeStringArray(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  const out = [];
  for (const raw of value) {
    const normalized = safeString(raw);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function parseBoolLike(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return Number.isFinite(v) ? v !== 0 : null;
  const s = String(v ?? '').trim().toLowerCase();
  if (!s) return null;
  if (['1', 'true', 'yes', 'y', 'on'].includes(s)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(s)) return false;
  return null;
}

function normalizedRiskLevel(raw) {
  const text = safeString(raw).toLowerCase();
  if (text === 'moderate') return 'medium';
  if (text === 'low' || text === 'medium' || text === 'high' || text === 'critical') return text;
  return '';
}

const HIGH_RISK_CAPABILITY_RE = [
  /^connectors?\./i,
  /^web\./i,
  /^network\./i,
  /^ai\.generate\.paid$/i,
  /^ai\.generate\.remote$/i,
  /^payments?\./i,
  /^shell\./i,
  /^filesystem\./i,
  /^fs\./i,
];

function isHighRiskCapability(capability) {
  const cap = safeString(capability).toLowerCase();
  return !!cap && HIGH_RISK_CAPABILITY_RE.some((re) => re.test(cap));
}

const CAPABILITY_FAMILY_META = Object.freeze({
  'skills.discover': {
    grant_floor: 'none',
    approval_floor: 'none',
    runtime_surface_families: ['xt_builtin', 'hub_bridge_network'],
  },
  'skills.manage': {
    grant_floor: 'none',
    approval_floor: 'local_approval',
    runtime_surface_families: ['xt_builtin', 'hub_bridge_network'],
  },
  'repo.read': {
    grant_floor: 'none',
    approval_floor: 'none',
    runtime_surface_families: ['xt_builtin', 'project_local_fs'],
  },
  'repo.mutate': {
    grant_floor: 'none',
    approval_floor: 'local_approval',
    runtime_surface_families: ['xt_builtin', 'project_local_fs'],
  },
  'repo.verify': {
    grant_floor: 'none',
    approval_floor: 'local_approval',
    runtime_surface_families: ['xt_builtin', 'project_local_runtime'],
  },
  'repo.delivery': {
    grant_floor: 'privileged',
    approval_floor: 'hub_grant_plus_local_approval',
    runtime_surface_families: ['xt_builtin', 'project_local_runtime', 'hub_bridge_network'],
  },
  'memory.inspect': {
    grant_floor: 'none',
    approval_floor: 'none',
    runtime_surface_families: ['xt_builtin', 'supervisor_runtime'],
  },
  'web.live': {
    grant_floor: 'privileged',
    approval_floor: 'none',
    runtime_surface_families: ['hub_bridge_network', 'managed_browser_runtime'],
  },
  'browser.observe': {
    grant_floor: 'privileged',
    approval_floor: 'none',
    runtime_surface_families: ['managed_browser_runtime'],
  },
  'browser.interact': {
    grant_floor: 'privileged',
    approval_floor: 'local_approval',
    runtime_surface_families: ['managed_browser_runtime'],
  },
  'browser.secret_fill': {
    grant_floor: 'privileged',
    approval_floor: 'owner_confirmation',
    runtime_surface_families: ['managed_browser_runtime'],
  },
  'device.observe': {
    grant_floor: 'none',
    approval_floor: 'local_approval',
    runtime_surface_families: ['trusted_device_runtime'],
  },
  'device.act': {
    grant_floor: 'none',
    approval_floor: 'owner_confirmation',
    runtime_surface_families: ['trusted_device_runtime'],
  },
  'connector.deliver': {
    grant_floor: 'privileged',
    approval_floor: 'hub_grant_plus_local_approval',
    runtime_surface_families: ['connector_runtime'],
  },
  'voice.playback': {
    grant_floor: 'none',
    approval_floor: 'none',
    runtime_surface_families: ['xt_builtin', 'supervisor_runtime'],
  },
  'supervisor.orchestrate': {
    grant_floor: 'none',
    approval_floor: 'none',
    runtime_surface_families: ['supervisor_runtime'],
  },
});

const CAPABILITY_PROFILE_RULES = Object.freeze([
  { profile_id: 'observe_only' },
  { profile_id: 'skill_management' },
  { profile_id: 'coding_execute' },
  { profile_id: 'browser_research' },
  { profile_id: 'browser_operator' },
  { profile_id: 'browser_operator_with_secrets' },
  { profile_id: 'delivery' },
  { profile_id: 'device_governed' },
  { profile_id: 'supervisor_full' },
]);

const GRANT_FLOOR_PRIORITY = Object.freeze({
  none: 0,
  readonly: 1,
  privileged: 2,
  critical: 3,
});

const APPROVAL_FLOOR_PRIORITY = Object.freeze({
  none: 0,
  local_approval: 1,
  hub_grant: 2,
  hub_grant_plus_local_approval: 3,
  owner_confirmation: 4,
});

function uniq(values) {
  return safeStringArray(values);
}

function maxGrantFloor(floors) {
  let best = 'none';
  for (const floor of safeStringArray(floors)) {
    if ((GRANT_FLOOR_PRIORITY[floor] || 0) > (GRANT_FLOOR_PRIORITY[best] || 0)) {
      best = floor;
    }
  }
  return best;
}

function maxApprovalFloor(floors) {
  let best = 'none';
  for (const floor of safeStringArray(floors)) {
    if ((APPROVAL_FLOOR_PRIORITY[floor] || 0) > (APPROVAL_FLOOR_PRIORITY[best] || 0)) {
      best = floor;
    }
  }
  return best;
}

function inferIntentFamiliesFromDispatch(dispatch) {
  const out = [];
  const tool = safeString(dispatch?.tool).toLowerCase();
  const passthroughArgs = safeStringArray(dispatch?.passthrough_args).map((it) => it.toLowerCase());
  const fixedArgs = dispatch && typeof dispatch.fixed_args === 'object' && !Array.isArray(dispatch.fixed_args)
    ? dispatch.fixed_args
    : {};

  switch (tool) {
    case 'skills.search':
      out.push('skills.discover');
      break;
    case 'skills.pin':
      out.push('skills.manage');
      break;
    case 'memory_snapshot':
      out.push('memory.inspect');
      if (String(fixedArgs.mode || '').toLowerCase() === 'supervisor_orchestration' || fixedArgs.retrospective === true) {
        out.push('supervisor.orchestrate');
      }
      break;
    case 'project_snapshot':
      out.push('memory.inspect');
      break;
    case 'summarize':
      out.push('repo.read');
      if (passthroughArgs.includes('url')) out.push('web.fetch_live');
      break;
    case 'web_search':
      out.push('web.search_live');
      break;
    case 'web_fetch':
      out.push('web.fetch_live');
      break;
    case 'browser_read':
      out.push('web.fetch_live', 'browser.observe');
      break;
    case 'device.browser.control':
      out.push('web.fetch_live', 'browser.observe');
      if (
        passthroughArgs.includes('selector')
        || passthroughArgs.includes('field_role')
        || passthroughArgs.includes('path')
        || passthroughArgs.includes('text')
        || passthroughArgs.includes('content')
        || passthroughArgs.includes('value')
      ) {
        out.push('browser.interact');
      }
      if (
        passthroughArgs.includes('secret_item_id')
        || passthroughArgs.includes('secret_scope')
        || passthroughArgs.includes('secret_name')
        || passthroughArgs.includes('secret_project_id')
      ) {
        out.push('browser.secret_fill');
      }
      break;
    case 'supervisor.voice.playback':
      out.push('voice.playback');
      break;
    case 'run_command':
    case 'process_start':
      out.push('repo.verify');
      break;
    case 'process_status':
    case 'process_logs':
      out.push('repo.read');
      break;
    case 'git_push':
    case 'pr_create':
    case 'ci_trigger':
      out.push('repo.deliver');
      break;
    case 'git_commit':
    case 'git_apply':
      out.push('repo.modify');
      break;
    default:
      break;
  }
  return uniq(out);
}

function inferIntentFamiliesFromVariants(variants) {
  const out = [];
  for (const variant of Array.isArray(variants) ? variants : []) {
    out.push(...inferIntentFamiliesFromDispatch(variant?.dispatch));
    const actions = safeStringArray(variant?.actions).map((it) => it.toLowerCase());
    if (actions.some((it) => ['click', 'tap', 'type', 'fill', 'input', 'enter', 'upload', 'attach'].includes(it))) {
      out.push('browser.interact');
    }
    if (actions.some((it) => ['snapshot', 'inspect', 'extract', 'read', 'read_page', 'read-page', 'fetch'].includes(it))) {
      out.push('browser.observe');
    }
  }
  return uniq(out);
}

function inferIntentFamiliesFromCapabilities(capabilities) {
  const out = [];
  for (const raw of safeStringArray(capabilities)) {
    const cap = raw.toLowerCase();
    if (cap.startsWith('skills.search') || cap.startsWith('skills.discover')) out.push('skills.discover');
    if (
      cap.startsWith('skills.pin')
      || cap.startsWith('skills.manage')
      || cap.startsWith('skills.install')
      || cap.startsWith('skills.enable')
      || cap.startsWith('skills.import')
    ) out.push('skills.manage');

    if (
      cap.startsWith('repo.read')
      || cap.startsWith('filesystem.read')
      || cap.startsWith('fs.read')
      || cap === 'document.read'
      || cap === 'git.status'
      || cap === 'git.diff'
      || cap === 'project.snapshot'
    ) out.push('repo.read');

    if (
      cap.startsWith('repo.write')
      || cap.startsWith('repo.mutate')
      || cap.startsWith('repo.modify')
      || cap.startsWith('repo.delete')
      || cap.startsWith('repo.move')
      || cap === 'git.apply'
      || cap === 'git.commit'
    ) out.push('repo.modify');

    if (
      cap.startsWith('repo.verify')
      || cap.startsWith('repo.test')
      || cap.startsWith('repo.build')
      || cap === 'run_command'
      || cap.startsWith('process.')
    ) out.push('repo.verify');

    if (
      cap.startsWith('repo.delivery')
      || cap === 'git.push'
      || cap === 'pr.create'
      || cap === 'ci.trigger'
    ) out.push('repo.deliver');

    if (cap.startsWith('web.search')) out.push('web.search_live');
    if (cap.startsWith('web.fetch') || cap.startsWith('web.live')) out.push('web.fetch_live');
    if (cap.startsWith('browser.read') || cap.startsWith('browser.observe')) out.push('browser.observe');
    if (cap === 'device.browser.control' || cap.startsWith('browser.interact')) {
      out.push('browser.observe', 'browser.interact');
    }
    if (cap.startsWith('browser.secret_fill')) out.push('browser.secret_fill');
    if (cap.startsWith('device.ui.observe') || cap.startsWith('device.screen.capture')) out.push('device.observe');
    if (
      cap.startsWith('device.ui.act')
      || cap.startsWith('device.ui.step')
      || cap.startsWith('device.applescript')
      || cap.startsWith('device.clipboard.write')
    ) out.push('device.act');
    if (cap.startsWith('memory.snapshot') || cap.startsWith('memory.inspect') || cap === 'project.snapshot') out.push('memory.inspect');
    if (cap.startsWith('supervisor.voice.playback')) out.push('voice.playback');
    if (cap.startsWith('supervisor.orchestrate')) out.push('supervisor.orchestrate');
    if (cap.startsWith('connectors.') || cap.startsWith('connector.')) out.push('repo.deliver');
  }
  return uniq(out);
}

function inferIntentFamiliesFromSkillId(skillId) {
  const sid = safeString(skillId).toLowerCase();
  if (!sid) return [];
  const out = [];
  if (sid === 'find-skills') out.push('skills.discover');
  if (sid === 'request-skill-enable') out.push('skills.manage');
  if (sid === 'supervisor-voice') out.push('voice.playback');
  if (sid === 'self-improving-agent') out.push('memory.inspect', 'supervisor.orchestrate');
  if (sid === 'agent-browser') out.push('browser.observe', 'browser.interact', 'browser.secret_fill', 'web.fetch_live');
  if (sid.includes('websearch')) out.push('web.search_live');
  return uniq(out);
}

function canonicalCapabilityFamiliesFromIntentFamilies(intentFamilies) {
  const out = [];
  for (const raw of safeStringArray(intentFamilies)) {
    switch (raw) {
      case 'skills.discover':
      case 'skills.manage':
      case 'repo.read':
      case 'repo.verify':
      case 'browser.observe':
      case 'browser.interact':
      case 'browser.secret_fill':
      case 'device.observe':
      case 'device.act':
      case 'memory.inspect':
      case 'voice.playback':
      case 'supervisor.orchestrate':
        out.push(raw);
        break;
      case 'repo.modify':
        out.push('repo.mutate');
        break;
      case 'repo.deliver':
        out.push('repo.delivery');
        break;
      case 'web.search_live':
      case 'web.fetch_live':
        out.push('web.live');
        break;
      default:
        break;
    }
  }
  return uniq(out);
}

function canonicalCapabilityProfilesFromFamilies(families) {
  const familySet = new Set(safeStringArray(families));
  const profiles = new Set();

  const add = (profile) => {
    if (!profile) return;
    profiles.add(profile);
  };

  if (familySet.has('skills.manage')) add('skill_management');
  if (familySet.has('repo.mutate') || familySet.has('repo.verify')) add('coding_execute');
  if (familySet.has('web.live') || familySet.has('browser.observe')) add('browser_research');
  if (familySet.has('browser.interact')) add('browser_operator');
  if (familySet.has('browser.secret_fill')) add('browser_operator_with_secrets');
  if (familySet.has('repo.delivery') || familySet.has('connector.deliver')) add('delivery');
  if (familySet.has('device.observe') || familySet.has('device.act')) add('device_governed');
  if (
    familySet.has('supervisor.orchestrate')
    && (familySet.has('skills.manage') || familySet.has('repo.delivery') || familySet.has('device.act'))
  ) add('supervisor_full');

  if (
    profiles.size === 0
    || familySet.has('skills.discover')
    || familySet.has('repo.read')
    || familySet.has('memory.inspect')
    || familySet.has('voice.playback')
  ) {
    add('observe_only');
  }

  if (profiles.has('supervisor_full')) {
    add('device_governed');
    add('delivery');
    add('skill_management');
  }
  if (profiles.has('device_governed')) {
    add('browser_operator');
  }
  if (profiles.has('browser_operator_with_secrets')) {
    add('browser_operator');
  }
  if (profiles.has('browser_operator')) {
    add('browser_research');
  }
  if (profiles.has('delivery')) {
    add('coding_execute');
  }
  if (profiles.has('coding_execute') || profiles.has('browser_research') || profiles.has('skill_management')) {
    add('observe_only');
  }

  const ordered = CAPABILITY_PROFILE_RULES
    .map((rule) => rule.profile_id)
    .filter((profile) => profiles.has(profile));
  return uniq(ordered);
}

function runtimeSurfaceFamiliesFromCapabilityFamilies(families) {
  const out = [];
  for (const family of safeStringArray(families)) {
    const meta = CAPABILITY_FAMILY_META[family];
    if (!meta) continue;
    out.push(...safeStringArray(meta.runtime_surface_families));
  }
  return uniq(out);
}

function deriveSkillCapabilitySemantics(input) {
  const obj = input && typeof input === 'object' ? input : {};
  const risk_level = normalizedRiskLevel(obj.risk_level || obj.riskLevel || obj.risk_profile);
  const requires_grant = parseBoolLike(obj.requires_grant ?? obj.requiresGrant);

  const intents = uniq([
    ...safeStringArray(obj.intent_families),
    ...inferIntentFamiliesFromDispatch(obj.governed_dispatch),
    ...inferIntentFamiliesFromVariants(obj.governed_dispatch_variants),
    ...inferIntentFamiliesFromCapabilities(obj.capabilities_required),
    ...inferIntentFamiliesFromSkillId(obj.skill_id || obj.id),
  ]);

  const capability_families = canonicalCapabilityFamiliesFromIntentFamilies(intents);
  const capability_profiles = canonicalCapabilityProfilesFromFamilies(capability_families);

  const familyGrantFloors = capability_families.map((family) => CAPABILITY_FAMILY_META[family]?.grant_floor || 'none');
  const familyApprovalFloors = capability_families.map((family) => CAPABILITY_FAMILY_META[family]?.approval_floor || 'none');

  let grant_floor = maxGrantFloor(familyGrantFloors);
  if (grant_floor === 'none' && requires_grant === true) {
    grant_floor = risk_level === 'critical' ? 'critical' : (risk_level === 'high' ? 'privileged' : 'readonly');
  }
  let approval_floor = maxApprovalFloor(familyApprovalFloors);
  if (approval_floor === 'none' && capability_families.includes('browser.secret_fill')) {
    approval_floor = 'owner_confirmation';
  }
  if (approval_floor === 'none' && capability_families.includes('device.act')) {
    approval_floor = 'owner_confirmation';
  }
  if (approval_floor === 'none' && capability_families.includes('repo.mutate')) {
    approval_floor = 'local_approval';
  }
  if (approval_floor === 'none' && capability_families.includes('repo.delivery')) {
    approval_floor = 'hub_grant_plus_local_approval';
  }

  return {
    intent_families: intents,
    capability_families,
    capability_profiles,
    grant_floor,
    approval_floor,
    runtime_surface_families: runtimeSurfaceFamiliesFromCapabilityFamilies(capability_families),
  };
}

function sameStringSet(left, right) {
  const l = uniq(left);
  const r = uniq(right);
  if (l.length !== r.length) return false;
  const rightSet = new Set(r);
  return l.every((item) => rightSet.has(item));
}

function validateSkillCapabilityHints(input, derived) {
  const obj = input && typeof input === 'object' ? input : {};
  const intentHints = safeStringArray(obj.intent_families);
  const profileHints = safeStringArray(obj.capability_profile_hints || obj.capability_profiles);
  const approvalFloorHint = safeString(obj.approval_floor_hint);
  const risk = normalizedRiskLevel(obj.risk_level || obj.riskLevel || obj.risk_profile);
  const publisherId = safeString(obj.publisher_id || obj?.publisher?.publisher_id);
  const sourceId = safeString(obj.source_id || obj.sourceId);
  const isOfficial = sourceId === 'builtin:catalog' || publisherId === 'xhub.official';
  const isHighRisk = risk === 'high' || risk === 'critical';

  const mismatches = [];
  if (intentHints.length > 0 && !sameStringSet(intentHints, derived.intent_families)) {
    mismatches.push({
      field: 'intent_families',
      expected: derived.intent_families,
      actual: intentHints,
    });
  }
  if (profileHints.length > 0 && !sameStringSet(profileHints, derived.capability_profiles)) {
    mismatches.push({
      field: 'capability_profile_hints',
      expected: derived.capability_profiles,
      actual: profileHints,
    });
  }
  if (approvalFloorHint && approvalFloorHint !== safeString(derived.approval_floor)) {
    mismatches.push({
      field: 'approval_floor_hint',
      expected: safeString(derived.approval_floor),
      actual: approvalFloorHint,
    });
  }

  return {
    checked: intentHints.length > 0 || profileHints.length > 0 || !!approvalFloorHint,
    isOfficial,
    isHighRisk,
    fail_closed: mismatches.length > 0 && (isOfficial || isHighRisk),
    mismatches,
  };
}

export {
  CAPABILITY_FAMILY_META,
  CAPABILITY_PROFILE_RULES,
  deriveSkillCapabilitySemantics,
  validateSkillCapabilityHints,
};
