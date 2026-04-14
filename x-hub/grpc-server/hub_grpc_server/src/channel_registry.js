import {
  normalizeChannelApprovalSurface,
  normalizeChannelAutomationPath,
  normalizeChannelCapabilities,
  normalizeChannelReleaseStage,
  normalizeChannelThreadingMode,
} from './channel_types.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function normalizeLookupKey(input) {
  return safeString(input)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function freezeMeta(entry) {
  return Object.freeze({
    id: entry.id,
    order: Number(entry.order || 0),
    label: safeString(entry.label),
    detail_label: safeString(entry.detail_label),
    aliases: Object.freeze([...(Array.isArray(entry.aliases) ? entry.aliases : [])]),
    capabilities: Object.freeze(normalizeChannelCapabilities(entry.capabilities)),
    threading_mode: normalizeChannelThreadingMode(entry.threading_mode, 'none'),
    approval_surface: normalizeChannelApprovalSurface(entry.approval_surface, 'text_only'),
    release_stage: normalizeChannelReleaseStage(entry.release_stage, 'p1'),
    automation_path: normalizeChannelAutomationPath(entry.automation_path, 'hub_bridge'),
    require_real_evidence: entry.require_real_evidence === true,
    allow_direct_xt: false,
    endpoint_visibility: 'domain_or_relay_only',
    operator_surface: 'hub_supervisor_facade',
  });
}

export const HUB_CHANNEL_PROVIDER_ORDER = Object.freeze([
  'slack',
  'telegram',
  'feishu',
  'whatsapp_cloud_api',
  'whatsapp_personal_qr',
]);

const META_BY_ID = Object.freeze({
  slack: freezeMeta({
    id: 'slack',
    order: 10,
    label: 'Slack',
    detail_label: 'Slack Operator',
    aliases: ['slack_bot', 'slack_app'],
    capabilities: [
      'status_query',
      'blockers_query',
      'queue_query',
      'approval_actions',
      'push_alerts',
      'push_summaries',
      'structured_actions',
      'thread_native',
      'project_binding',
      'preferred_device_hint',
    ],
    threading_mode: 'provider_native',
    approval_surface: 'inline_buttons',
    release_stage: 'wave1',
    automation_path: 'hub_bridge',
  }),
  telegram: freezeMeta({
    id: 'telegram',
    order: 20,
    label: 'Telegram',
    detail_label: 'Telegram Operator',
    aliases: ['telegram_bot', 'tg'],
    capabilities: [
      'status_query',
      'blockers_query',
      'queue_query',
      'approval_actions',
      'push_alerts',
      'push_summaries',
      'structured_actions',
      'thread_native',
      'project_binding',
      'preferred_device_hint',
    ],
    threading_mode: 'provider_native',
    approval_surface: 'inline_buttons',
    release_stage: 'wave1',
    automation_path: 'hub_bridge',
  }),
  feishu: freezeMeta({
    id: 'feishu',
    order: 30,
    label: 'Feishu',
    detail_label: 'Feishu Operator',
    aliases: ['lark', 'larksuite', 'feishu_bot'],
    capabilities: [
      'status_query',
      'blockers_query',
      'queue_query',
      'approval_actions',
      'push_alerts',
      'push_summaries',
      'structured_actions',
      'thread_native',
      'project_binding',
      'preferred_device_hint',
    ],
    threading_mode: 'provider_native',
    approval_surface: 'card',
    release_stage: 'wave1',
    automation_path: 'hub_bridge',
  }),
  whatsapp_cloud_api: freezeMeta({
    id: 'whatsapp_cloud_api',
    order: 40,
    label: 'WhatsApp Cloud API',
    detail_label: 'WhatsApp Cloud Operator',
    aliases: ['whatsapp_cloud', 'whatsapp_cloudapi', 'wa_cloud'],
    capabilities: [
      'status_query',
      'queue_query',
      'approval_actions',
      'push_alerts',
      'push_summaries',
      'structured_actions',
      'project_binding',
      'preferred_device_hint',
    ],
    threading_mode: 'none',
    approval_surface: 'text_only',
    release_stage: 'p1',
    automation_path: 'hub_bridge',
    require_real_evidence: true,
  }),
  whatsapp_personal_qr: freezeMeta({
    id: 'whatsapp_personal_qr',
    order: 50,
    label: 'WhatsApp Personal QR',
    detail_label: 'WhatsApp Personal Runner',
    aliases: ['whatsapp_personal', 'whatsapp_qr', 'wa_personal', 'wa_qr', 'whatsapp_personal_runner'],
    capabilities: [
      'status_query',
      'push_alerts',
      'push_summaries',
      'preferred_device_hint',
      'trusted_local_runner',
    ],
    threading_mode: 'none',
    approval_surface: 'text_only',
    release_stage: 'p1',
    automation_path: 'trusted_automation_local',
    require_real_evidence: true,
  }),
});

const DIRECT_ALIAS_TO_ID = Object.freeze((() => {
  const out = {};
  for (const providerId of HUB_CHANNEL_PROVIDER_ORDER) {
    out[providerId] = providerId;
    const meta = META_BY_ID[providerId];
    for (const alias of meta.aliases) {
      out[normalizeLookupKey(alias)] = providerId;
    }
  }
  out.telegrambot = 'telegram';
  out.slackbot = 'slack';
  out.whatsappcloudapi = 'whatsapp_cloud_api';
  return out;
})());

const AMBIGUOUS_PROVIDER_ALIASES = Object.freeze(new Set([
  'whatsapp',
  'wa',
]));

export const HUB_CHANNEL_OPENCLAW_REUSE_MAP = Object.freeze({
  registry: Object.freeze({
    reuse_class: 'direct_logic',
    source_path: '/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/channels/registry.ts',
    notes: 'Reuse provider order/meta/alias normalization shape only.',
  }),
  delivery_context: Object.freeze({
    reuse_class: 'direct_logic',
    source_path: '/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/utils/delivery-context.ts',
    notes: 'Reuse normalized provider+conversation+thread route-key shape.',
  }),
  ingress_envelope: Object.freeze({
    reuse_class: 'shape_only',
    source_path: '/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/channels/registry.ts',
    notes: 'Freeze one provider-normalized ingress envelope so adapters only emit fail-closed contract fields.',
  }),
  provider_exposure_matrix: Object.freeze({
    reuse_class: 'shape_only',
    source_path: '/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/channels/registry.ts',
    notes: 'Keep listener/process/path/auth/replay/body-cap metadata machine-readable instead of adapter-local constants.',
  }),
  command_gate: Object.freeze({
    reuse_class: 'shape_only',
    source_path: '/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/channels/command-gating.ts',
    notes: 'Reuse pure gating contract shape; Hub adds role+scope+grant semantics later.',
  }),
  xt_runtime_tokens: Object.freeze({
    reuse_class: 'forbidden',
    source_path: '',
    notes: 'Do not move provider tokens, cookies, QR sessions, or webhook secrets into XT runtime.',
  }),
  natural_language_side_effects: Object.freeze({
    reuse_class: 'forbidden',
    source_path: '',
    notes: 'Do not allow natural language to bypass structured_action -> policy -> grant -> audit.',
  }),
});

export function listChannelProviders() {
  return HUB_CHANNEL_PROVIDER_ORDER.map((providerId) => META_BY_ID[providerId]);
}

export function listChannelProviderAliases() {
  return Object.freeze(Object.keys(DIRECT_ALIAS_TO_ID).sort());
}

export function listAmbiguousChannelProviderAliases() {
  return Object.freeze(Array.from(AMBIGUOUS_PROVIDER_ALIASES).sort());
}

export function normalizeChannelProviderId(raw) {
  const key = normalizeLookupKey(raw);
  if (!key || AMBIGUOUS_PROVIDER_ALIASES.has(key)) return null;
  return DIRECT_ALIAS_TO_ID[key] || null;
}

export function isKnownChannelProvider(raw) {
  return !!normalizeChannelProviderId(raw);
}

export function getChannelProviderMeta(providerId) {
  const id = normalizeChannelProviderId(providerId);
  return id ? META_BY_ID[id] : null;
}

export function explainChannelProviderInput(raw) {
  const key = normalizeLookupKey(raw);
  if (!key) {
    return {
      ok: false,
      normalized_input: '',
      provider_id: '',
      ambiguous: false,
      reason: 'provider_missing',
    };
  }
  if (AMBIGUOUS_PROVIDER_ALIASES.has(key)) {
    return {
      ok: false,
      normalized_input: key,
      provider_id: '',
      ambiguous: true,
      reason: 'provider_alias_ambiguous',
    };
  }
  const providerId = DIRECT_ALIAS_TO_ID[key] || '';
  if (!providerId) {
    return {
      ok: false,
      normalized_input: key,
      provider_id: '',
      ambiguous: false,
      reason: 'provider_unknown',
    };
  }
  return {
    ok: true,
    normalized_input: key,
    provider_id: providerId,
    ambiguous: false,
    reason: '',
  };
}
