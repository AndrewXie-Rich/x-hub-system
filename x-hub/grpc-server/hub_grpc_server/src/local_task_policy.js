function safeString(value) {
  return String(value ?? '').trim();
}

function safeBool(value) {
  return value === true || value === 1 || value === '1';
}

function safeStringList(values) {
  if (values == null) return [];
  const out = [];
  const seen = new Set();
  const items = Array.isArray(values) ? values : String(values || '').split(',');
  for (const raw of items) {
    const cleaned = safeString(raw);
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

const LEGACY_LOCAL_AUDIO_CAPABILITY = 'ai.audio.local';
const LOCAL_TTS_CAPABILITY = 'ai.audio.tts.local';

export const LOCAL_TASK_CAPABILITY_BY_KIND = Object.freeze({
  text_generate: 'ai.generate.local',
  embedding: 'ai.embed.local',
  speech_to_text: LEGACY_LOCAL_AUDIO_CAPABILITY,
  text_to_speech: LOCAL_TTS_CAPABILITY,
  vision_understand: 'ai.vision.local',
  ocr: 'ai.vision.local',
});

function capabilityKillSwitchAliases(capability) {
  const normalized = safeString(capability);
  if (normalized === LOCAL_TTS_CAPABILITY) {
    return [LOCAL_TTS_CAPABILITY, LEGACY_LOCAL_AUDIO_CAPABILITY];
  }
  return normalized ? [normalized] : [];
}

export function localTaskCapabilityKey(taskKind) {
  const key = safeString(taskKind).toLowerCase();
  return LOCAL_TASK_CAPABILITY_BY_KIND[key] || '';
}

export function normalizeLocalTaskProvider(provider) {
  return safeString(provider).toLowerCase();
}

export function normalizeLocalTaskDenyCode(rawCode) {
  const raw = safeString(rawCode);
  if (!raw) return '';
  if ([
    'capability_blocked',
    'provider_blocked',
    'task_blocked',
    'provider_unavailable',
    'policy_blocked',
    'modality_unsupported',
    'input_too_large',
  ].includes(raw)) {
    return raw;
  }
  if (raw === 'permission_denied' || raw === 'trusted_automation_capabilities_empty_blocked') {
    return 'capability_blocked';
  }
  if (raw.startsWith('kill_switch_capability:')) {
    return 'capability_blocked';
  }
  if (raw.startsWith('kill_switch_provider:')) {
    return 'provider_blocked';
  }
  if (raw === 'models_disabled') {
    return 'task_blocked';
  }
  if (
    raw.startsWith('trusted_automation_')
    || raw === 'local_embedding_docs_unavailable'
    || raw === 'policy_blocked_secret_audio'
    || raw === 'policy_blocked_secret_image'
  ) {
    return 'policy_blocked';
  }
  if (
    raw === 'embedding_query_too_large'
    || raw === 'audio_file_too_large'
    || raw === 'audio_duration_too_long'
    || raw === 'image_file_too_large'
    || raw === 'image_pixels_too_large'
    || raw === 'image_dimensions_too_large'
    || /_too_large$/.test(raw)
    || /_too_long$/.test(raw)
  ) {
    return 'input_too_large';
  }
  if (
    raw === 'unsupported_audio_format'
    || raw.startsWith('unsupported_audio_format:')
    || raw === 'audio_decode_failed'
    || raw === 'unsupported_image_format'
    || raw.startsWith('unsupported_image_format:')
    || raw === 'image_decode_failed'
    || raw === 'secret_input_not_allowed'
    || raw === 'unsupported_input_modality'
  ) {
    return 'modality_unsupported';
  }
  if (
    raw === 'local_embedding_model_unavailable'
    || raw === 'local_asr_model_unavailable'
    || raw === 'local_tts_model_unavailable'
    || raw === 'text_to_speech_runtime_unavailable'
    || raw === 'tts_native_engine_not_supported'
    || raw === 'tts_native_runtime_failed'
    || raw === 'tts_native_audio_missing'
    || raw === 'tts_native_speaker_unavailable'
    || raw === 'native_dependency_error'
    || raw === 'local_tts_runtime_failed'
    || raw === 'tts_audio_output_missing'
    || raw === 'provider_not_ready'
    || raw === 'provider_unavailable'
    || raw.startsWith('task_not_implemented:')
    || /_model_unavailable$/.test(raw)
  ) {
    return 'provider_unavailable';
  }
  if (
    raw === 'local_task_unsupported'
    || raw === 'task_unsupported'
    || raw.startsWith('task_unsupported:')
    || raw.startsWith('model_task_unsupported:')
  ) {
    return 'task_blocked';
  }
  return raw;
}

export function localTaskGovernanceComponentForFailure({
  denyCode = '',
  rawDenyCode = '',
  blockedBy = '',
} = {}) {
  const deny = safeString(denyCode);
  const raw = safeString(rawDenyCode);
  const blocked = safeString(blockedBy);

  if (
    raw === 'models_disabled'
    || raw.startsWith('kill_switch_')
    || deny === 'policy_blocked'
    || blocked === 'policy'
  ) {
    return 'grant';
  }

  if ([
    'capability_blocked',
    'provider_blocked',
    'task_blocked',
    'provider_unavailable',
    'modality_unsupported',
    'input_too_large',
  ].includes(deny)) {
    return 'capability';
  }

  return '';
}

export function buildLocalTaskFailure({
  taskKind = '',
  provider = '',
  capability = '',
  rawDenyCode = '',
  message = '',
  blockedBy = '',
  ruleIds = [],
} = {}) {
  const normalizedTaskKind = safeString(taskKind).toLowerCase();
  const normalizedProvider = normalizeLocalTaskProvider(provider);
  const normalizedCapability = safeString(capability) || localTaskCapabilityKey(normalizedTaskKind);
  const raw = safeString(rawDenyCode);
  const denyCode = normalizeLocalTaskDenyCode(raw) || 'policy_blocked';
  const resolvedRuleIds = Array.isArray(ruleIds) && ruleIds.length > 0
    ? ruleIds.map((item) => safeString(item)).filter(Boolean)
    : [raw || denyCode];
  const governanceComponent = localTaskGovernanceComponentForFailure({
    denyCode,
    rawDenyCode: raw,
    blockedBy,
  });
  return {
    ok: false,
    task_kind: normalizedTaskKind,
    provider: normalizedProvider,
    capability: normalizedCapability,
    deny_code: denyCode,
    raw_deny_code: raw && raw !== denyCode ? raw : '',
    message: safeString(message) || raw || denyCode,
    blocked_by: safeString(blockedBy),
    rule_ids: resolvedRuleIds,
    governance_component: governanceComponent,
  };
}

export function evaluateLocalTaskPolicyGate({
  taskKind = '',
  provider = '',
  capabilityAllowed = true,
  capabilityDenyCode = '',
  killSwitch = null,
} = {}) {
  const normalizedTaskKind = safeString(taskKind).toLowerCase();
  const normalizedProvider = normalizeLocalTaskProvider(provider);
  const capability = localTaskCapabilityKey(normalizedTaskKind);
  if (!capability) {
    return buildLocalTaskFailure({
      taskKind: normalizedTaskKind,
      provider: normalizedProvider,
      rawDenyCode: 'local_task_unsupported',
      message: normalizedTaskKind ? `local_task_unsupported:${normalizedTaskKind}` : 'local_task_unsupported',
      blockedBy: 'task',
      ruleIds: ['local_task_unsupported'],
    });
  }
  if (!capabilityAllowed) {
    const raw = safeString(capabilityDenyCode) || 'permission_denied';
    return buildLocalTaskFailure({
      taskKind: normalizedTaskKind,
      provider: normalizedProvider,
      capability,
      rawDenyCode: raw,
      message: raw,
      blockedBy: 'capability',
      ruleIds: [raw],
    });
  }

  const disabledCapabilities = safeStringList(killSwitch?.disabled_local_capabilities);
  const disabledProviders = safeStringList(killSwitch?.disabled_local_providers)
    .map((item) => normalizeLocalTaskProvider(item))
    .filter(Boolean);
  const reason = safeString(killSwitch?.reason);

  if (safeBool(killSwitch?.models_disabled)) {
    return buildLocalTaskFailure({
      taskKind: normalizedTaskKind,
      provider: normalizedProvider,
      capability,
      rawDenyCode: 'models_disabled',
      message: reason ? `models_disabled:${reason}` : 'models_disabled',
      blockedBy: 'task',
      ruleIds: ['models_disabled'],
    });
  }
  const blockedCapability = capabilityKillSwitchAliases(capability)
    .find((candidate) => disabledCapabilities.includes(candidate));
  if (blockedCapability) {
    return buildLocalTaskFailure({
      taskKind: normalizedTaskKind,
      provider: normalizedProvider,
      capability,
      rawDenyCode: `kill_switch_capability:${blockedCapability}`,
      message: reason ? `capability_blocked:${reason}` : `capability_blocked:${blockedCapability}`,
      blockedBy: 'capability',
      ruleIds: [`kill_switch_capability:${blockedCapability}`],
    });
  }
  if (normalizedProvider && disabledProviders.includes(normalizedProvider)) {
    return buildLocalTaskFailure({
      taskKind: normalizedTaskKind,
      provider: normalizedProvider,
      capability,
      rawDenyCode: `kill_switch_provider:${normalizedProvider}`,
      message: reason ? `provider_blocked:${reason}` : `provider_blocked:${normalizedProvider}`,
      blockedBy: 'provider',
      ruleIds: [`kill_switch_provider:${normalizedProvider}`],
    });
  }

  return {
    ok: true,
    task_kind: normalizedTaskKind,
    provider: normalizedProvider,
    capability,
    deny_code: '',
    raw_deny_code: '',
    message: '',
    blocked_by: '',
    rule_ids: [],
    governance_component: '',
  };
}
