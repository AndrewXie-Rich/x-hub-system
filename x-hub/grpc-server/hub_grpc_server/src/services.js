import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

import { nowMs, uuid, estimateTokens, requireHttpsUrl, chunkText } from './util.js';
import { requireAdminAuth, requireClientAuth } from './auth.js';
import { loadClients } from './clients.js';
import { loadQuotaConfig, resolveDeviceDailyTokenCap, utcDayKey } from './quota.js';
import { pushHubNotification } from './hub_ipc.js';
import {
  enqueueBridgeAIGenerate,
  enqueueBridgeFetch,
  ensureBridgeEnabledUntil,
  readBridgeStatus,
  resolveBridgeBaseDir,
  waitBridgeAIGenerateResult,
  waitBridgeFetchResult,
  waitForBridgeEnabled,
} from './bridge_ipc.js';
import { makeProtoModelInfo } from './models_util.js';
import { isRuntimeAlive, resolveRuntimeBaseDir, responsePathForRequest, runtimeModelMeta, runtimeModelsSnapshot, tailResponseJsonl, writeCancelRequest, writeGenerateRequest } from './mlx_runtime_ipc.js';
import {
  evaluateSkillExecutionGate,
  getSkillManifest,
  listResolvedSkills,
  normalizeSkillStoreError,
  readSkillPackage,
  resolveSkillsWithTrace,
  searchSkills,
  setSkillPin,
  uploadSkillPackage,
} from './skills_store.js';
import { stripPrivateTagsFailClosed } from './private_tags.js';
import { runMemoryRetrievalPipeline } from './memory_retrieval_pipeline.js';
import { buildTrustShardHitStats, routeMemoryByTrustShards } from './memory_trust_router.js';
import { buildMemoryScoreExplainPayload } from './memory_score_explain.js';
import { attachMemoryMetrics } from './memory_metrics_schema.js';
import { evaluatePromptRemoteExportGate } from './memory_remote_export_gate.js';
import { buildLongtermMarkdownExport } from './memory_markdown_projection.js';
import { buildLongtermMarkdownPatchCandidate, normalizeMarkdownPatchMode } from './memory_markdown_edit.js';
import {
  analyzeLongtermMarkdownFindings,
  normalizeReviewDecision,
  normalizeSecretHandling,
  sanitizeLongtermMarkdown,
} from './memory_markdown_review.js';
import { getVoiceWakeProfile, setVoiceWakeProfile } from './voicewake.js';


function safeStringList(values) {
  if (values == null) return [];
  const out = [];
  const seen = new Set();
  const items = Array.isArray(values) ? values : String(values || '').split(',');
  for (const raw of items) {
    const cleaned = String(raw || '').trim();
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
  }
  return out;
}

function nonNegativeInt(value, fallback = 0) {
  if (value == null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

export function findRuntimeClientConfig(runtimeBaseDir, deviceId) {
  const wantedDeviceId = String(deviceId || '').trim();
  if (!wantedDeviceId) return null;
  try {
    const clients = loadClients(runtimeBaseDir, 500);
    return (clients || []).find((client) => String(client?.device_id || '').trim() === wantedDeviceId) || null;
  } catch {
    return null;
  }
}

export function resolvePaidModelRuntimeAccess({
  runtimeClient,
  capabilityAllowed,
  capabilityDenyCode = '',
  modelId,
  requestedTotalTokensEstimate = 0,
  usedTokensToday = 0,
} = {}) {
  const client = runtimeClient && typeof runtimeClient === 'object' ? runtimeClient : null;
  const trustProfile = client?.approved_trust_profile && typeof client.approved_trust_profile === 'object'
    ? client.approved_trust_profile
    : (client?.trust_profile && typeof client.trust_profile === 'object' ? client.trust_profile : null);
  const trustProfilePresent = !!(client?.trust_profile_present || trustProfile);
  const paidModelPolicyMode = String(client?.paid_model_policy_mode || trustProfile?.paid_model_policy?.mode || '').trim().toLowerCase() || 'off';
  const allowedModelIds = safeStringList(client?.paid_model_allowed_model_ids || trustProfile?.paid_model_policy?.allowed_model_ids || []);
  const dailyTokenLimit = nonNegativeInt(client?.daily_token_limit ?? trustProfile?.budget_policy?.daily_token_limit, 0);
  const singleRequestTokenLimit = nonNegativeInt(client?.single_request_token_limit ?? trustProfile?.budget_policy?.single_request_token_limit, 0);
  const requestedTokens = nonNegativeInt(requestedTotalTokensEstimate, 0);
  const usedTokens = nonNegativeInt(usedTokensToday, 0);
  const explicitCapabilityDenyCode = String(capabilityDenyCode || '').trim();
  const resolved = {
    allow: false,
    trust_profile_present: trustProfilePresent,
    policy_mode: String(client?.policy_mode || (trustProfilePresent ? 'new_profile' : 'legacy_grant')).trim().toLowerCase(),
    device_id: String(client?.device_id || trustProfile?.device_id || '').trim(),
    device_name: String(client?.name || trustProfile?.device_name || client?.device_id || '').trim(),
    paid_model_policy_mode: paidModelPolicyMode,
    allowed_model_ids: allowedModelIds,
    daily_token_limit: dailyTokenLimit,
    single_request_token_limit: singleRequestTokenLimit,
    default_web_fetch_enabled: !!(client?.default_web_fetch_enabled ?? trustProfile?.network_policy?.default_web_fetch_enabled),
    requested_total_tokens_estimate: requestedTokens,
    used_tokens_today: usedTokens,
    requires_legacy_grant: !trustProfilePresent,
    deny_code: !trustProfilePresent ? 'legacy_grant_flow_required' : '',
    reason: !trustProfilePresent ? 'legacy_grant_flow_required' : '',
  };
  if (!trustProfilePresent) return resolved;
  if (!capabilityAllowed && explicitCapabilityDenyCode === 'trusted_automation_capabilities_empty_blocked') {
    resolved.deny_code = explicitCapabilityDenyCode;
    resolved.reason = explicitCapabilityDenyCode;
    return resolved;
  }
  if (!capabilityAllowed || !paidModelPolicyMode || paidModelPolicyMode === 'off') {
    resolved.deny_code = 'device_paid_model_disabled';
    resolved.reason = 'device_paid_model_disabled';
    return resolved;
  }
  if (paidModelPolicyMode === 'custom_selected_models') {
    const wantedModelId = String(modelId || '').trim();
    if (!wantedModelId || !allowedModelIds.includes(wantedModelId)) {
      resolved.deny_code = 'device_paid_model_not_allowed';
      resolved.reason = 'device_paid_model_not_allowed';
      return resolved;
    }
  }
  if (singleRequestTokenLimit > 0 && requestedTokens > singleRequestTokenLimit) {
    resolved.deny_code = 'device_single_request_token_exceeded';
    resolved.reason = 'device_single_request_token_exceeded';
    return resolved;
  }
  if (dailyTokenLimit > 0) {
    const projectedTokens = usedTokens + requestedTokens;
    if (usedTokens >= dailyTokenLimit || projectedTokens > dailyTokenLimit) {
      resolved.deny_code = 'device_daily_token_budget_exceeded';
      resolved.reason = 'device_daily_token_budget_exceeded';
      return resolved;
    }
  }
  resolved.allow = true;
  resolved.deny_code = '';
  resolved.reason = 'trusted_profile_allow';
  return resolved;
}

function renderPromptFromMessages(messages) {
  const arr = Array.isArray(messages) ? messages : [];
  const parts = [];
  for (const m of arr) {
    const role = String(m?.role || 'user').trim().toUpperCase();
    const content = String(m?.content || '');
    if (!content.trim()) continue;
    parts.push(`${role}:\n${content}`);
  }
  return parts.join('\n\n').trim();
}

function renderWorkingSetFromTurnRows(rows) {
  const out = [];
  for (const r of rows) {
    const role = String(r?.role || '').trim().toUpperCase();
    const content = String(r?.content || '');
    if (!role || !content.trim()) continue;
    out.push(`${role}:\n${content}`);
  }
  return out.join('\n\n').trim();
}

function renderCanonicalItems(items) {
  const rows = Array.isArray(items) ? items : [];
  const lines = [];
  for (const it of rows) {
    const k = String(it?.key || '').trim();
    const v = String(it?.value || '').trim();
    if (!k || !v) continue;
    lines.push(`- ${k}: ${v}`);
  }
  return lines.join('\n').trim();
}

function renderPromptFromHubMemory({ canonicalItems, workingSetRows }) {
  const parts = [];
  const canon = renderCanonicalItems(canonicalItems);
  if (canon) {
    parts.push('[CANONICAL MEMORY]');
    parts.push(canon);
    parts.push('[END_CANONICAL MEMORY]');
  }

  const ws = renderWorkingSetFromTurnRows(workingSetRows);
  if (ws) {
    parts.push('[WORKING SET]');
    parts.push(ws);
    parts.push('[END_WORKING SET]');
  }

  return parts.join('\n\n').trim();
}

function latestQueryFromMessages(messages, fallbackText = '') {
  const rows = Array.isArray(messages) ? messages : [];
  for (let i = rows.length - 1; i >= 0; i -= 1) {
    const m = rows[i] || {};
    const role = String(m.role || '').trim().toLowerCase();
    if (!role || role === 'system') continue;
    const content = String(m.content || '').trim();
    if (content) return content;
  }
  return String(fallbackText || '').trim();
}

function looksSecretLikeText(input) {
  const text = String(input || '');
  if (!text.trim()) return false;
  const patterns = [
    /\[private\]/i,
    /\b(sk-|ghp_|xox[abprs]-|bearer\s+[a-z0-9\-_\.]+)/i,
    /\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp|payment[_\s-]*(pin|code)|qr[_\s-]*code)\b/i,
    /\b(password|passcode|authorization|auth[_\s-]*code)\b/i,
    /[0-9a-f]{32,}/i,
  ];
  return patterns.some((p) => p.test(text));
}

function inferMemorySensitivity({ sourceType, key, text }) {
  const k = String(key || '');
  const t = String(text || '');
  if (looksSecretLikeText(`${k}\n${t}`)) return 'secret';
  if (String(sourceType || '') === 'canonical') return 'internal';
  if (String(sourceType || '') === 'turn') return 'internal';
  return 'public';
}

function buildMemoryRetrievalDocs({ canonicalProject, canonicalThread, workingRows, scopeRef }) {
  const docs = [];
  const projRows = Array.isArray(canonicalProject) ? canonicalProject : [];
  const threadRows = Array.isArray(canonicalThread) ? canonicalThread : [];
  const turns = Array.isArray(workingRows) ? workingRows : [];
  const scope = scopeRef && typeof scopeRef === 'object' ? scopeRef : {};
  const device_id = String(scope.device_id || '');
  const user_id = String(scope.user_id || '');
  const app_id = String(scope.app_id || '');
  const project_id = String(scope.project_id || '');
  const thread_id = String(scope.thread_id || '');

  let seq = 0;
  const pushCanonical = (row, scopeName) => {
    const key = String(row?.key || '').trim();
    const value = String(row?.value || '').trim();
    if (!key || !value) return;
    seq += 1;
    const itemScope = String(scopeName || '').trim().toLowerCase() === 'thread' ? 'thread' : 'project';
    const itemThread = itemScope === 'thread' ? thread_id : '';
    docs.push({
      id: `canonical:${itemScope}:${itemThread || '~'}:${key}:${seq}`,
      title: key,
      text: value,
      tags: ['canonical', itemScope],
      sensitivity: inferMemorySensitivity({ sourceType: 'canonical', key, text: value }),
      trust_level: 'trusted',
      scope: {
        device_id,
        user_id,
        app_id,
        project_id,
        thread_id: itemThread,
      },
      created_at_ms: Number(row?.updated_at_ms || 0),
      source_type: 'canonical',
      source_payload: {
        key,
        value,
      },
    });
  };

  for (const row of projRows) pushCanonical(row, 'project');
  for (const row of threadRows) pushCanonical(row, 'thread');

  for (let i = 0; i < turns.length; i += 1) {
    const row = turns[i] || {};
    const role = String(row?.role || '').trim();
    const content = String(row?.content || '').trim();
    if (!role || !content) continue;
    const createdAt = Number(row?.created_at_ms || 0);
    docs.push({
      id: `turn:${createdAt || 0}:${i + 1}`,
      title: role,
      text: content,
      tags: ['working_set', role.toLowerCase()],
      sensitivity: inferMemorySensitivity({ sourceType: 'turn', key: role, text: content }),
      trust_level: 'trusted',
      scope: {
        device_id,
        user_id,
        app_id,
        project_id,
        thread_id,
      },
      created_at_ms: createdAt,
      source_type: 'turn',
      source_payload: {
        role,
        content,
        created_at_ms: createdAt,
      },
    });
  }

  return docs;
}

function toProtoCapability(cap) {
  const c = String(cap || '').toUpperCase();
  if (c.includes('AI_GENERATE_LOCAL')) return 'CAPABILITY_AI_GENERATE_LOCAL';
  if (c.includes('AI_GENERATE_PAID')) return 'CAPABILITY_AI_GENERATE_PAID';
  if (c.includes('WEB_FETCH')) return 'CAPABILITY_WEB_FETCH';
  // Allow legacy string form used by HTTP docs.
  if (String(cap || '') === 'ai.generate.local') return 'CAPABILITY_AI_GENERATE_LOCAL';
  if (String(cap || '') === 'ai.generate.paid') return 'CAPABILITY_AI_GENERATE_PAID';
  if (String(cap || '') === 'web.fetch') return 'CAPABILITY_WEB_FETCH';
  return 'CAPABILITY_UNSPECIFIED';
}

function capabilityDbKey(capEnumOrText) {
  // We store capability in DB as stable string values.
  const c = toProtoCapability(capEnumOrText);
  if (c === 'CAPABILITY_AI_GENERATE_LOCAL') return 'ai.generate.local';
  if (c === 'CAPABILITY_AI_GENERATE_PAID') return 'ai.generate.paid';
  if (c === 'CAPABILITY_WEB_FETCH') return 'web.fetch';
  return 'unknown';
}

function grantDecisionEnum(decisionText) {
  const s = String(decisionText || '').toLowerCase();
  if (s === 'approved') return 'GRANT_DECISION_APPROVED';
  if (s === 'denied') return 'GRANT_DECISION_DENIED';
  if (s === 'queued') return 'GRANT_DECISION_QUEUED';
  if (s === 'revoked') return 'GRANT_DECISION_REVOKED';
  return 'GRANT_DECISION_UNSPECIFIED';
}

function toProtoSkillPinScope(scope) {
  const s = String(scope || '').toUpperCase().trim();
  if (s === 'SKILL_PIN_SCOPE_MEMORY_CORE' || s === 'MEMORY_CORE') return 'SKILL_PIN_SCOPE_MEMORY_CORE';
  if (s === 'SKILL_PIN_SCOPE_GLOBAL' || s === 'GLOBAL') return 'SKILL_PIN_SCOPE_GLOBAL';
  if (s === 'SKILL_PIN_SCOPE_PROJECT' || s === 'PROJECT') return 'SKILL_PIN_SCOPE_PROJECT';
  return 'SKILL_PIN_SCOPE_UNSPECIFIED';
}

function makeProtoSkillMeta(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    skill_id: String(row.skill_id || ''),
    name: String(row.name || row.skill_id || ''),
    version: String(row.version || ''),
    description: String(row.description || ''),
    publisher_id: String(row.publisher_id || ''),
    capabilities_required: Array.isArray(row.capabilities_required)
      ? row.capabilities_required.map((s) => String(s || '')).filter(Boolean)
      : [],
    source_id: String(row.source_id || ''),
    package_sha256: String(row.package_sha256 || ''),
    install_hint: String(row.install_hint || ''),
  };
}

const SKILL_IMPORT_DENY_REMEDIATION = Object.freeze({
  invalid_manifest: '检查 skill.json 是否包含 skill_id/version/entrypoint.command；若使用旧字段别名请参考 skills_abi_compat.v1 映射表。',
  invalid_manifest_json: '修复 manifest_json 为合法 JSON（可先执行: jq . skill.json）。',
  missing_manifest_json: '请在上传请求里传入 manifest_json，或确保包内包含可解析的 skill.json。',
  invalid_package_bytes: '重新打包技能并确认 --file 指向 .tgz/.zip 二进制内容。',
  source_not_allowlisted: '请改用 allowlist 内的 source_id，或先在 skills_store/skill_sources.json 增加该来源。',
  signature_missing: '该技能缺少签名；生产默认拒绝。请使用受信 publisher 私钥签名后重传。',
  signature_invalid: '签名验签失败。请确认 canonical manifest（去 signature）与签名原文一致。',
  signature_algorithm_unsupported: '仅支持 ed25519 签名算法；请按规范重新签名。',
  signature_key_invalid: 'publisher 公钥无效。请检查 trusted_publishers.json 或 manifest.publisher.public_key_ed25519。',
  publisher_untrusted: 'publisher 未被信任。请先更新 trusted_publishers.json 并启用该 publisher。',
  publisher_key_mismatch: 'manifest 公钥与 trusted publisher 公钥不一致，已 fail-closed 阻断。',
  hash_mismatch: '包哈希或文件哈希不匹配，请重新打包并更新 manifest.files[].sha256。',
  archive_corrupt: '技能包结构损坏（tar/zip 解析失败）。请重新导出技能包。',
  archive_path_invalid: '包内存在非法路径（绝对路径/路径穿越）。请修复后重试。',
  archive_duplicate_path: '包内存在重复文件路径，可能导致执行歧义，已阻断。',
  archive_unsupported: '暂不支持该压缩特性（如加密 zip/不支持的压缩方法）。请改用标准 tgz。',
  revoked: '该技能或包已撤销（revoked）；Hub 分发与 Runner 执行都会阻断。',
  skills_store_unavailable: '检查 HUB_RUNTIME_BASE_DIR 是否可写，并确认 skills_store 目录可创建。',
  package_too_large: '压缩包体积超限；请缩小包体积或提升 HUB_SKILLS_MAX_PACKAGE_MB 配置。',
  missing_user_id: '请在 client identity 里传入 user_id（paired token 会覆盖为绑定值）。',
  missing_project_id: 'project scope pin 必须携带 project_id，请补齐后重试。',
  unsupported_scope: 'scope 仅支持 global/project，memory_core 为保留系统层。',
  package_not_found: '请先执行 upload/import 让 package_sha256 入库，再执行 pin。',
  skill_package_mismatch: 'pin 的 skill_id 与 package_sha256 不匹配，请使用上传返回的 skill_id。',
  invalid_pin_request: '请确认 skill_id/package_sha256 均已填写且格式正确。',
  permission_denied: '当前 token 未启用 skills capability；请重新安装客户端令牌或更新 capability allowlist。',
  skill_upload_failed: '请查看 Hub 审计中的 deny_code 与 fix_suggestion 字段并按提示修复。',
  skill_pin_failed: '请查看 Hub 审计中的 deny_code 与 fix_suggestion 字段并按提示修复。',
});

function parseSkillErrorCode(rawMessage) {
  const msg = String(rawMessage || '').trim();
  if (!msg) return 'skill_upload_failed';
  const direct = /^([a-z0-9_]+)(?::|\b)/i.exec(msg);
  if (!direct) return 'skill_upload_failed';
  return String(direct[1] || '').toLowerCase() || 'skill_upload_failed';
}

function explainSkillFailure(rawMessage, fallbackCode) {
  const message = String(rawMessage || '').trim();
  const deny_code = parseSkillErrorCode(message) || String(fallbackCode || 'skill_upload_failed');
  const fix_suggestion = String(SKILL_IMPORT_DENY_REMEDIATION[deny_code] || SKILL_IMPORT_DENY_REMEDIATION[String(fallbackCode || '')] || SKILL_IMPORT_DENY_REMEDIATION.skill_upload_failed);
  return {
    deny_code,
    message: message || deny_code,
    fix_suggestion,
  };
}

function makeProtoGrant(row) {
  if (!row) return null;
  return {
    grant_id: String(row.grant_id || ''),
    client: {
      device_id: String(row.device_id || ''),
      user_id: row.user_id ? String(row.user_id) : '',
      app_id: String(row.app_id || ''),
      project_id: row.project_id ? String(row.project_id) : '',
      session_id: '',
    },
    capability: toProtoCapability(row.capability),
    model_id: row.model_id ? String(row.model_id) : '',
    token_cap: Number(row.token_cap || 0),
    token_used: Number(row.token_used || 0),
    expires_at_ms: Number(row.expires_at_ms || 0),
    status: String(row.status || ''),
  };
}

function makeProtoPendingGrantItem(row) {
  if (!row) return null;
  return {
    grant_request_id: String(row.grant_request_id || ''),
    request_id: String(row.request_id || ''),
    client: {
      device_id: String(row.device_id || ''),
      user_id: row.user_id ? String(row.user_id) : '',
      app_id: String(row.app_id || ''),
      project_id: row.project_id ? String(row.project_id) : '',
      session_id: '',
    },
    capability: toProtoCapability(row.capability),
    model_id: row.model_id ? String(row.model_id) : '',
    reason: row.reason ? String(row.reason) : '',
    requested_ttl_sec: Number(row.requested_ttl_sec || 0),
    requested_token_cap: Number(row.requested_token_cap || 0),
    status: String(row.status || ''),
    decision: row.decision ? String(row.decision) : '',
    created_at_ms: Number(row.created_at_ms || 0),
    decided_at_ms: Number(row.decided_at_ms || 0),
  };
}

function makeProtoConnectorIngressReceipt(row) {
  if (!row) return null;
  const receipt_id = String(row.receipt_id || '').trim();
  if (!receipt_id) return null;
  return {
    receipt_id,
    request_id: String(row.request_id || '').trim(),
    project_id: String(row.project_id || '').trim(),
    connector: String(row.connector || '').trim().toLowerCase(),
    target_id: String(row.target_id || '').trim(),
    ingress_type: String(row.ingress_type || '').trim().toLowerCase(),
    channel_scope: String(row.channel_scope || '').trim().toLowerCase(),
    source_id: String(row.source_id || '').trim(),
    message_id: String(row.message_id || '').trim(),
    dedupe_key: String(row.dedupe_key || '').trim(),
    received_at_ms: Number(row.received_at_ms || 0),
    event_sequence: Number(row.event_sequence || 0),
    delivery_state: String(row.delivery_state || '').trim().toLowerCase(),
    runtime_state: String(row.runtime_state || '').trim().toLowerCase(),
  };
}

function makeProtoAutonomyPolicyOverrideItem(row) {
  if (!row) return null;
  const project_id = String(row.project_id || '').trim();
  const override_mode = String(row.override_mode || '').trim().toLowerCase();
  if (!project_id || !override_mode) return null;
  if (!['none', 'clamp_guided', 'clamp_manual', 'kill_switch'].includes(override_mode)) {
    return null;
  }
  return {
    project_id,
    override_mode,
    updated_at_ms: Number(row.updated_at_ms || 0),
    reason: String(row.reason || '').trim(),
    audit_ref: String(row.audit_ref || '').trim(),
  };
}

function makeProtoProjectLineageNode(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    root_project_id: String(row.root_project_id || ''),
    parent_project_id: String(row.parent_project_id || ''),
    project_id: String(row.project_id || ''),
    lineage_path: String(row.lineage_path || ''),
    parent_task_id: String(row.parent_task_id || ''),
    split_round: Math.max(0, Number(row.split_round || 0)),
    split_reason: String(row.split_reason || ''),
    child_index: Math.max(0, Number(row.child_index || 0)),
    status: String(row.status || 'active'),
    created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
    updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
  };
}

function makeProtoProjectDispatchContext(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    root_project_id: String(row.root_project_id || ''),
    parent_project_id: String(row.parent_project_id || ''),
    project_id: String(row.project_id || ''),
    assigned_agent_profile: String(row.assigned_agent_profile || ''),
    parallel_lane_id: String(row.parallel_lane_id || ''),
    budget_class: String(row.budget_class || ''),
    queue_priority: Math.floor(Number(row.queue_priority || 0)),
    expected_artifacts: Array.isArray(row.expected_artifacts)
      ? row.expected_artifacts.map((v) => String(v || '')).filter(Boolean)
      : [],
    attached_at_ms: Math.max(0, Number(row.attached_at_ms || 0)),
    attach_source: String(row.attach_source || ''),
  };
}

function makeProtoRiskTuningProfile(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    profile_id: String(row.profile_id || ''),
    profile_label: String(row.profile_label || row.profile_id || ''),
    vector_weight: Number(row.vector_weight || 0),
    text_weight: Number(row.text_weight || 0),
    recency_weight: Number(row.recency_weight || 0),
    risk_weight: Number(row.risk_weight || 0),
    risk_penalty_low: Number(row.risk_penalty_low || 0),
    risk_penalty_medium: Number(row.risk_penalty_medium || 0),
    risk_penalty_high: Number(row.risk_penalty_high || 0),
    recall_floor: Number(row.recall_floor || 0),
    latency_ceiling_ratio: Number(row.latency_ceiling_ratio || 0),
    block_precision_floor: Number(row.block_precision_floor || 0),
    max_recall_drop: Number(row.max_recall_drop || 0),
    max_latency_ratio_increase: Number(row.max_latency_ratio_increase || 0),
    max_block_precision_drop: Number(row.max_block_precision_drop || 0),
    max_online_offline_drift: Number(row.max_online_offline_drift || 0),
    created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
    updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
  };
}

function makeProtoVoiceGrantChallenge(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    challenge_id: String(row.challenge_id || ''),
    template_id: String(row.template_id || ''),
    action_digest: String(row.action_digest || ''),
    scope_digest: String(row.scope_digest || ''),
    amount_digest: String(row.amount_digest || ''),
    challenge_code: String(row.challenge_code || ''),
    risk_level: String(row.risk_level || 'high'),
    requires_mobile_confirm: !!row.requires_mobile_confirm,
    allow_voice_only: !!row.allow_voice_only,
    bound_device_id: String(row.bound_device_id || ''),
    mobile_terminal_id: String(row.mobile_terminal_id || ''),
    issued_at_ms: Math.max(0, Number(row.issued_at_ms || 0)),
    expires_at_ms: Math.max(0, Number(row.expires_at_ms || 0)),
  };
}

function makeProtoVoiceWakeProfile(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    schema_version: String(row.schema_version || 'xt.supervisor_voice_wake_profile.v1'),
    profile_id: String(row.profile_id || 'default'),
    trigger_words: Array.isArray(row.trigger_words) ? row.trigger_words.map((item) => String(item || '')).filter(Boolean) : [],
    updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    scope: String(row.scope || 'paired_device_group'),
    source: String(row.source || 'hub_pairing_sync'),
    wake_mode: String(row.wake_mode || 'wake_phrase'),
    requires_pairing_ready: !!row.requires_pairing_ready,
    audit_ref: String(row.audit_ref || ''),
  };
}

function makeProtoAgentCapsule(row) {
  if (!row || typeof row !== 'object') return null;
  let allowedEgress = [];
  if (Array.isArray(row.allowed_egress)) {
    allowedEgress = row.allowed_egress.map((item) => String(item || '')).filter(Boolean);
  } else {
    try {
      const parsed = JSON.parse(String(row.allowed_egress_json || '[]'));
      if (Array.isArray(parsed)) {
        allowedEgress = parsed.map((item) => String(item || '')).filter(Boolean);
      }
    } catch {
      allowedEgress = [];
    }
  }
  return {
    capsule_id: String(row.capsule_id || ''),
    agent_name: String(row.agent_name || ''),
    agent_version: String(row.agent_version || ''),
    platform: String(row.platform || ''),
    sha256: String(row.sha256 || ''),
    signature: String(row.signature || ''),
    sbom_hash: String(row.sbom_hash || ''),
    allowed_egress: allowedEgress,
    risk_profile: String(row.risk_profile || ''),
    status: String(row.status || ''),
    deny_code: String(row.deny_code || ''),
    verification_report_ref: String(row.verification_report_ref || ''),
    active_generation: Math.max(0, Number(row.active_generation || 0)),
    verified_at_ms: Math.max(0, Number(row.verified_at_ms || 0)),
    activated_at_ms: Math.max(0, Number(row.activated_at_ms || 0)),
    created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
    updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
  };
}

function makeProtoPaymentIntent(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    intent_id: String(row.intent_id || ''),
    request_id: String(row.request_id || ''),
    client: {
      device_id: String(row.device_id || ''),
      user_id: row.user_id ? String(row.user_id) : '',
      app_id: String(row.app_id || ''),
      project_id: row.project_id ? String(row.project_id) : '',
      session_id: '',
    },
    status: String(row.status || 'prepared'),
    amount_minor: Math.max(0, Math.floor(Number(row.amount_minor || 0))),
    currency: String(row.currency || ''),
    merchant_id: String(row.merchant_id || ''),
    source_terminal_id: String(row.source_terminal_id || ''),
    allowed_mobile_terminal_id: String(row.allowed_mobile_terminal_id || ''),
    challenge_id: String(row.challenge_id || ''),
    created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
    updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    expires_at_ms: Math.max(0, Number(row.expires_at_ms || 0)),
    challenge_expires_at_ms: Math.max(0, Number(row.challenge_expires_at_ms || 0)),
    evidence_verified_at_ms: Math.max(0, Number(row.evidence_verified_at_ms || 0)),
    authorized_at_ms: Math.max(0, Number(row.authorized_at_ms || 0)),
    committed_at_ms: Math.max(0, Number(row.committed_at_ms || 0)),
    aborted_at_ms: Math.max(0, Number(row.aborted_at_ms || 0)),
    expired_at_ms: Math.max(0, Number(row.expired_at_ms || 0)),
    commit_txn_id: String(row.commit_txn_id || ''),
    deny_code: String(row.deny_code || ''),
    receipt_delivery_state: String(row.receipt_delivery_state || ''),
    receipt_commit_deadline_at_ms: Math.max(0, Number(row.receipt_commit_deadline_at_ms || 0)),
    receipt_compensation_due_at_ms: Math.max(0, Number(row.receipt_compensation_due_at_ms || 0)),
    receipt_compensated_at_ms: Math.max(0, Number(row.receipt_compensated_at_ms || 0)),
    receipt_compensation_reason: String(row.receipt_compensation_reason || ''),
  };
}

function makeProtoProjectHeartbeat(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    root_project_id: String(row.root_project_id || ''),
    parent_project_id: String(row.parent_project_id || ''),
    project_id: String(row.project_id || ''),
    lineage_depth: Math.max(0, Math.floor(Number(row.lineage_depth || 0))),
    queue_depth: Math.max(0, Math.floor(Number(row.queue_depth || 0))),
    oldest_wait_ms: Math.max(0, Number(row.oldest_wait_ms || 0)),
    blocked_reason: Array.isArray(row.blocked_reason)
      ? row.blocked_reason.map((item) => String(item || '')).filter(Boolean)
      : [],
    next_actions: Array.isArray(row.next_actions)
      ? row.next_actions.map((item) => String(item || '')).filter(Boolean)
      : [],
    risk_tier: String(row.risk_tier || ''),
    heartbeat_seq: Math.max(0, Number(row.heartbeat_seq || 0)),
    sent_at_ms: Math.max(0, Number(row.sent_at_ms || 0)),
    received_at_ms: Math.max(0, Number(row.received_at_ms || 0)),
    expires_at_ms: Math.max(0, Number(row.expires_at_ms || 0)),
    conservative_only: !!row.conservative_only,
  };
}

function makeProtoDispatchPlanItem(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    root_project_id: String(row.root_project_id || ''),
    parent_project_id: String(row.parent_project_id || ''),
    project_id: String(row.project_id || ''),
    priority_score: Number(row.priority_score || 0),
    prewarm_targets: Array.isArray(row.prewarm_targets)
      ? row.prewarm_targets.map((item) => String(item || '')).filter(Boolean)
      : [],
    batch_id: String(row.batch_id || ''),
    fairness_bucket: String(row.fairness_bucket || ''),
    lineage_priority_boost: Math.max(0, Math.floor(Number(row.lineage_priority_boost || 0))),
    split_group_id: String(row.split_group_id || ''),
    risk_tier: String(row.risk_tier || ''),
    conservative_only: !!row.conservative_only,
    queue_depth: Math.max(0, Math.floor(Number(row.queue_depth || 0))),
    oldest_wait_ms: Math.max(0, Number(row.oldest_wait_ms || 0)),
  };
}

function redactPrivateContent(text) {
  return stripPrivateTagsFailClosed(text, { placeholder: '[PRIVATE]' });
}

function parseBoolLike(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return Number.isFinite(v) ? v !== 0 : null;
  const s = String(v ?? '').trim().toLowerCase();
  if (!s) return null;
  if (['1', 'true', 'yes', 'y', 'on', 'ok'].includes(s)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(s)) return false;
  return null;
}

function parseNonNegativeInt(v) {
  if (v == null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  return Math.max(0, Math.floor(n));
}

function parseIntInRange(v, fallback, minValue, maxValue) {
  const raw = Number(v);
  if (!Number.isFinite(raw)) return Math.max(minValue, Math.min(maxValue, Math.floor(fallback)));
  const n = Math.floor(raw);
  return Math.max(minValue, Math.min(maxValue, n));
}

function firstMetadataValue(call, key) {
  const k = String(key || '').trim().toLowerCase();
  if (!k) return '';
  try {
    const vals = call?.metadata?.get?.(k);
    if (!Array.isArray(vals) || vals.length <= 0) return '';
    return String(vals[0] || '').trim();
  } catch {
    return '';
  }
}

function resolveMemoryScoreExplainControl(call) {
  const envEnabled = parseBoolLike(process.env.HUB_MEMORY_SCORE_EXPLAIN);
  const mdEnabled = parseBoolLike(
    firstMetadataValue(call, 'x-memory-score-explain')
    || firstMetadataValue(call, 'x-debug-memory-score-explain')
  );
  const enabled = mdEnabled == null ? envEnabled === true : !!mdEnabled;

  const rawLimit = firstMetadataValue(call, 'x-memory-score-explain-limit') || process.env.HUB_MEMORY_SCORE_EXPLAIN_LIMIT;
  const limit = parseIntInRange(rawLimit, 3, 1, 10);

  const envTrace = parseBoolLike(process.env.HUB_MEMORY_SCORE_EXPLAIN_TRACE);
  const mdTrace = parseBoolLike(firstMetadataValue(call, 'x-memory-score-trace'));
  const includeTrace = mdTrace == null ? envTrace === true : !!mdTrace;

  return {
    enabled,
    limit,
    include_trace: includeTrace,
  };
}

function resolveMemoryMarkdownEditLimits() {
  const maxPatchChars = parseIntInRange(
    process.env.HUB_MEMORY_MARKDOWN_PATCH_MAX_CHARS,
    32 * 1024,
    512,
    512 * 1024
  );
  const maxPatchLines = parseIntInRange(
    process.env.HUB_MEMORY_MARKDOWN_PATCH_MAX_LINES,
    1200,
    10,
    50000
  );
  const defaultTtlMs = parseIntInRange(
    process.env.HUB_MEMORY_MARKDOWN_EDIT_TTL_MS,
    20 * 60 * 1000,
    60 * 1000,
    24 * 60 * 60 * 1000
  );
  const maxEditTtlMs = parseIntInRange(
    process.env.HUB_MEMORY_MARKDOWN_EDIT_MAX_TTL_MS,
    defaultTtlMs,
    defaultTtlMs,
    24 * 60 * 60 * 1000
  );
  return {
    max_patch_chars: maxPatchChars,
    max_patch_lines: maxPatchLines,
    default_ttl_ms: defaultTtlMs,
    max_edit_ttl_ms: Math.max(defaultTtlMs, maxEditTtlMs),
  };
}

function parseObjectFromMaybeJson(raw) {
  const s = String(raw ?? '').trim();
  if (!s || !s.startsWith('{')) return null;
  try {
    const obj = JSON.parse(s);
    return obj && typeof obj === 'object' ? obj : null;
  } catch {
    return null;
  }
}

function parsePolicyAckFields(input) {
  const inObj = input && typeof input === 'object' ? input : {};
  let userAck = parseBoolLike(inObj.user_ack_understood);
  let explainRounds = parseNonNegativeInt(inObj.explain_rounds);
  let optionsPresented = parseBoolLike(inObj.options_presented);

  const rawTexts = [inObj.note, inObj.reason].map((v) => String(v ?? '').trim()).filter(Boolean);
  for (const raw of rawTexts) {
    const parsed = parseObjectFromMaybeJson(raw);
    if (parsed && typeof parsed === 'object') {
      const nested = parsed.policy_eval && typeof parsed.policy_eval === 'object' ? parsed.policy_eval : parsed;
      if (userAck == null) userAck = parseBoolLike(nested.user_ack_understood);
      if (explainRounds == null) explainRounds = parseNonNegativeInt(nested.explain_rounds);
      if (optionsPresented == null) optionsPresented = parseBoolLike(nested.options_presented);
    }

    if (userAck == null) {
      const m = raw.match(/\buser_ack_understood\s*[:=]\s*(true|false|1|0|yes|no)\b/i);
      if (m && m[1]) userAck = parseBoolLike(m[1]);
    }
    if (explainRounds == null) {
      const m = raw.match(/\bexplain_rounds\s*[:=]\s*(\d+)\b/i);
      if (m && m[1]) explainRounds = parseNonNegativeInt(m[1]);
    }
    if (optionsPresented == null) {
      const m = raw.match(/\boptions_presented\s*[:=]\s*(true|false|1|0|yes|no)\b/i);
      if (m && m[1]) optionsPresented = parseBoolLike(m[1]);
    }
  }

  return {
    user_ack_understood: userAck == null ? false : !!userAck,
    explain_rounds: explainRounds == null ? 0 : explainRounds,
    options_presented: optionsPresented == null ? false : !!optionsPresented,
  };
}

function compactObject(obj) {
  const out = {};
  const src = obj && typeof obj === 'object' ? obj : {};
  for (const [k, v] of Object.entries(src)) {
    if (v == null) continue;
    if (Array.isArray(v) && v.length === 0) continue;
    out[k] = v;
  }
  return out;
}

function normalizeAgentRiskTier(value, fallback = 'high') {
  const raw = String(value || '').trim().toLowerCase();
  if (['low', 'medium', 'high', 'critical'].includes(raw)) return raw;
  return String(fallback || 'high').trim().toLowerCase() || 'high';
}

function parseAgentRiskTier(value) {
  const raw = String(value || '').trim().toLowerCase();
  if (['low', 'medium', 'high', 'critical'].includes(raw)) return raw;
  return '';
}

function agentRiskTierRank(value) {
  const tier = normalizeAgentRiskTier(value, 'high');
  if (tier === 'critical') return 4;
  if (tier === 'high') return 3;
  if (tier === 'medium') return 2;
  return 1;
}

function normalizeAgentToolDecision(value, fallback = 'pending') {
  const raw = String(value || '').trim().toLowerCase();
  if (['pending', 'approve', 'deny', 'downgrade'].includes(raw)) return raw;
  return String(fallback || 'pending').trim().toLowerCase() || 'pending';
}

function isHighRiskTier(value) {
  const tier = normalizeAgentRiskTier(value, 'high');
  return tier === 'high' || tier === 'critical';
}

function buildAgentToolCapabilityTokenAudit(toolReq, { required = false } = {}) {
  const tokenKind = String(toolReq?.capability_token_kind || '').trim();
  const tokenId = String(toolReq?.capability_token_id || '').trim();
  const tokenNonce = String(toolReq?.capability_token_nonce || '').trim();
  const tokenState = String(toolReq?.capability_token_state || '').trim();
  const tokenExpiresAtMs = Math.max(0, Number(toolReq?.capability_token_expires_at_ms || 0));
  const boundRequestId = String(toolReq?.capability_token_bound_request_id || '').trim();
  const consumedAtMs = Math.max(0, Number(toolReq?.capability_token_consumed_at_ms || 0));
  const revokedAtMs = Math.max(0, Number(toolReq?.capability_token_revoked_at_ms || 0));
  const revokeReason = String(toolReq?.capability_token_revoke_reason || '').trim();
  if (!required && !tokenKind && !tokenId && !tokenNonce && !tokenState && !tokenExpiresAtMs && !boundRequestId && !consumedAtMs && !revokedAtMs && !revokeReason) {
    return null;
  }
  return compactObject({
    required: required ? true : null,
    contract: tokenKind || 'one_time',
    token_id: tokenId || null,
    nonce: tokenNonce || null,
    state: tokenState || (tokenId ? 'issued' : null),
    expires_at_ms: tokenExpiresAtMs > 0 ? tokenExpiresAtMs : null,
    bound_request_id: boundRequestId || null,
    consumed_at_ms: consumedAtMs > 0 ? consumedAtMs : null,
    revoked_at_ms: revokedAtMs > 0 ? revokedAtMs : null,
    revoke_reason: revokeReason || null,
  });
}

function classifyAgentRiskTier({ tool_name, risk_tier, required_grant_scope }) {
  const hinted = parseAgentRiskTier(risk_tier);
  const toolName = String(tool_name || '').trim().toLowerCase();
  const scope = String(required_grant_scope || '').trim().toLowerCase();
  const highRiskPatterns = [
    /payment/,
    /transfer/,
    /purchase/,
    /wire/,
    /shell/,
    /exec/,
    /deploy/,
    /delete/,
    /write/,
    /grant/,
    /sudo/,
    /terminal\.(exec|write|delete|grant|sudo|deploy|shell)/,
  ];
  let inferred = 'medium';
  if (
    scope.includes('high')
    || scope.includes('critical')
    || scope.includes('privileged')
    || scope.includes('write')
    || scope.includes('payment')
  ) {
    inferred = 'high';
  } else if (highRiskPatterns.some((re) => re.test(toolName))) {
    inferred = 'high';
  } else if (
    toolName.includes('read')
    || toolName.includes('list')
    || toolName.includes('search')
    || toolName.includes('view')
    || toolName.includes('get')
  ) {
    inferred = 'low';
  }
  if (!hinted) return inferred;
  return agentRiskTierRank(hinted) >= agentRiskTierRank(inferred) ? hinted : inferred;
}

function defaultAgentToolPolicy({ risk_tier, required_grant_scope }) {
  const tier = normalizeAgentRiskTier(risk_tier, 'high');
  const scope = String(required_grant_scope || '').trim().toLowerCase();
  if (scope.includes('deny')) {
    return {
      decision: 'deny',
      deny_code: 'policy_denied',
    };
  }
  if (isHighRiskTier(tier) || scope.includes('manual_approval')) {
    return {
      decision: 'pending',
      deny_code: 'grant_pending',
    };
  }
  return {
    decision: 'approve',
    deny_code: '',
    grant_ttl_ms: 5 * 60 * 1000,
  };
}

function normalizeExecutionArgv(argv) {
  const rows = Array.isArray(argv) ? argv : [];
  if (rows.length <= 0 || rows.length > 128) return [];
  const out = [];
  for (const item of rows) {
    if (typeof item !== 'string') return [];
    const value = item;
    if (value.includes('\u0000') || value.length > 4096) return [];
    out.push(value);
  }
  return out;
}

function parseExecutionArgvJson(rawJson) {
  const raw = String(rawJson || '').trim();
  if (!raw) return [];
  try {
    return normalizeExecutionArgv(JSON.parse(raw));
  } catch {
    return [];
  }
}

function isSkillRunnerToolName(value) {
  const tool = String(value || '').trim().toLowerCase();
  if (!tool) return false;
  const prefixes = [
    'skills.execute',
    'skills.run',
    'skill.execute',
    'skill.run',
  ];
  return prefixes.some((prefix) => (
    tool === prefix
    || tool.startsWith(`${prefix}.`)
    || tool.startsWith(`${prefix}:`)
    || tool.startsWith(`${prefix}/`)
  ));
}

function normalizeSkillPackageSha(value) {
  const raw = String(value || '').trim().toLowerCase();
  if (!raw) return '';
  return /^[a-f0-9]{64}$/.test(raw) ? raw : '';
}

function extractSkillExecutionGateBinding(execArgv) {
  const argv = Array.isArray(execArgv) ? execArgv : [];
  const packageFlagNames = new Set([
    '--package-sha256',
    '--package_sha256',
    '--skill-package-sha256',
    '--skill_package_sha256',
  ]);
  const skillIdFlagNames = new Set([
    '--skill-id',
    '--skill_id',
    '--skill',
    '--skill-name',
    '--skill_name',
  ]);
  let packageSha = '';
  let packageShaSource = '';
  let skillId = '';
  let skillIdSource = '';

  for (let i = 0; i < argv.length; i += 1) {
    const token = String(argv[i] || '');
    const lower = token.toLowerCase();
    if (!packageSha && packageFlagNames.has(lower)) {
      const next = normalizeSkillPackageSha(argv[i + 1]);
      if (next) {
        packageSha = next;
        packageShaSource = `argv[${i + 1}]`;
      }
    }
    if (!skillId && skillIdFlagNames.has(lower)) {
      const next = String(argv[i + 1] || '').trim();
      if (next) {
        skillId = next;
        skillIdSource = `argv[${i + 1}]`;
      }
    }
    if (!packageSha) {
      const inlinePackage = token.match(
        /(?:^|[\s"'`])(?:--)?(?:skill[_-]?package[_-]?sha256|package[_-]?sha256)\s*(?:=|\s)\s*([a-fA-F0-9]{64})(?=$|[\s"'`])/i
      );
      if (inlinePackage && inlinePackage[1]) {
        const normalized = normalizeSkillPackageSha(inlinePackage[1]);
        if (normalized) {
          packageSha = normalized;
          packageShaSource = `argv[${i}]`;
        }
      }
    }
    if (!skillId) {
      const inlineSkillId = token.match(
        /(?:^|[\s"'`])(?:--)?(?:skill[_-]?id|skill[_-]?name)\s*(?:=|\s)\s*([a-zA-Z0-9._:-]{1,128})(?=$|[\s"'`])/i
      );
      if (inlineSkillId && inlineSkillId[1]) {
        const normalizedSkillId = String(inlineSkillId[1] || '').trim();
        if (normalizedSkillId) {
          skillId = normalizedSkillId;
          skillIdSource = `argv[${i}]`;
        }
      }
    }
  }

  return {
    package_sha256: packageSha,
    package_sha256_source: packageShaSource,
    skill_id: skillId,
    skill_id_source: skillIdSource,
  };
}

function resolveCanonicalExecutionCwd(rawCwd) {
  const input = String(rawCwd ?? '');
  if (!input || input.includes('\u0000') || input.length > 4096) {
    return { ok: false, deny_code: 'approval_cwd_invalid', canonical: '', input: '' };
  }
  if (!path.isAbsolute(input)) {
    return { ok: false, deny_code: 'approval_cwd_invalid', canonical: '', input };
  }
  try {
    const absolute = path.resolve(input);
    const canonical = fs.realpathSync.native(absolute);
    const stat = fs.statSync(canonical);
    if (!stat.isDirectory()) {
      return { ok: false, deny_code: 'approval_cwd_invalid', canonical: '', input };
    }
    return {
      ok: true,
      deny_code: '',
      canonical: path.normalize(canonical),
      input,
    };
  } catch {
    return { ok: false, deny_code: 'approval_cwd_invalid', canonical: '', input };
  }
}

function computeApprovalIdentityHash({
  device_id,
  user_id,
  app_id,
  project_id,
  session_id,
  agent_instance_id,
  tool_name,
  tool_args_hash,
  exec_argv,
  exec_cwd_canonical,
} = {}) {
  const payload = {
    schema_version: 'approval.identity.v1',
    device_id: String(device_id || ''),
    user_id: String(user_id || ''),
    app_id: String(app_id || ''),
    project_id: String(project_id || ''),
    session_id: String(session_id || ''),
    agent_instance_id: String(agent_instance_id || ''),
    tool_name: String(tool_name || ''),
    tool_args_hash: String(tool_args_hash || ''),
    exec_argv: normalizeExecutionArgv(exec_argv),
    exec_cwd_canonical: String(exec_cwd_canonical || ''),
  };
  return crypto.createHash('sha256').update(JSON.stringify(payload), 'utf8').digest('hex');
}

function metricsChannel(remoteMode) {
  return remoteMode ? 'remote' : 'local';
}

function parseRoutePolicyRemoteMode(routePolicy, fallback = false) {
  const policy = routePolicy && typeof routePolicy === 'object' ? routePolicy : {};
  if (policy.remote_mode == null) return !!fallback;
  return !!policy.remote_mode;
}

function isPaidModelMeta(model) {
  return String(model?.kind || '').toLowerCase() === 'paid_online' || !!Number(model?.requires_grant || 0);
}

function resolveLocalFallbackModelId({ db, runtimeBaseDir, preferred_model_id = '' } = {}) {
  const preferredModelId = String(preferred_model_id || process.env.HUB_REMOTE_EXPORT_DOWNGRADE_MODEL_ID || '').trim();
  const candidates = [];
  if (preferredModelId) candidates.push(preferredModelId);

  try {
    const snap = runtimeModelsSnapshot(runtimeBaseDir);
    if (snap.ok && Array.isArray(snap.models)) {
      for (const row of snap.models) {
        if (!row || typeof row !== 'object') continue;
        if (isPaidModelMeta(row)) continue;
        const mid = String(row.model_id || '').trim();
        if (mid) candidates.push(mid);
      }
    }
  } catch {
    // ignore
  }

  try {
    const rows = db.listModels();
    for (const row of rows) {
      if (!row || typeof row !== 'object') continue;
      if (isPaidModelMeta(row)) continue;
      const mid = String(row.model_id || '').trim();
      if (mid) candidates.push(mid);
    }
  } catch {
    // ignore
  }

  const seen = new Set();
  for (const modelId of candidates) {
    if (!modelId || seen.has(modelId)) continue;
    seen.add(modelId);
    let meta = null;
    try {
      meta = db.getModel(modelId) || runtimeModelMeta(runtimeBaseDir, modelId);
    } catch {
      meta = null;
    }
    if (meta && !isPaidModelMeta(meta)) return modelId;
  }
  return '';
}

function withMemoryMetricsExt(baseExt, metricsInput) {
  return attachMemoryMetrics(baseExt, metricsInput);
}

function buildMetricsScope({
  scope_kind = '',
  device_id = '',
  user_id = '',
  app_id = '',
  project_id = '',
  thread_id = '',
} = {}) {
  const out = {
    kind: String(scope_kind || '').trim(),
    device_id: String(device_id || '').trim(),
    user_id: String(user_id || '').trim(),
    app_id: String(app_id || '').trim(),
    project_id: String(project_id || '').trim(),
    thread_id: String(thread_id || '').trim(),
  };
  return compactObject(out);
}

export function makeServices({ db, bus }) {
  // In-flight cancellation map.
  const cancels = new Map(); // request_id -> { canceled: bool }

  // Track "device connected" presence for HubEvents.Subscribe (streaming) sessions.
  // This is the most reliable signal that a client is "actively connected" without
  // needing to treat every unary RPC as a heartbeat.
  const eventSubsByDeviceId = new Map(); // device_id -> { count, name, peer_ip, connected_at_ms, last_seen_at_ms }

  // Paid-model requests are routed through Bridge. Keep a fair in-memory queue so
  // one busy project cannot monopolize all Bridge AI slots.
  const paidAIGlobalConcurrency = parseIntInRange(process.env.HUB_PAID_AI_GLOBAL_CONCURRENCY, 6, 1, 64);
  const paidAIPerProjectConcurrency = parseIntInRange(process.env.HUB_PAID_AI_PER_PROJECT_CONCURRENCY, 2, 1, 16);
  const paidAIQueueLimit = parseIntInRange(process.env.HUB_PAID_AI_QUEUE_LIMIT, 128, 1, 4096);
  const paidAIQueueTimeoutMs = parseIntInRange(process.env.HUB_PAID_AI_QUEUE_TIMEOUT_MS, 20000, 1000, 300000);

  let paidAIInFlightTotal = 0;
  const paidAIInFlightByScope = new Map(); // scopeKey -> number
  const paidAIQueue = []; // [{ requestId, scopeKey, enqueuedAtMs, resolve, reject, timer, settled, shouldAbort }]
  const paidAIQueuedByRequestId = new Map(); // request_id -> queueEntry
  let paidAIQueueCursor = 0;

  function paidAIScopeKey({ project_id, device_id }) {
    const pid = String(project_id || '').trim();
    if (pid) return `project:${pid}`;
    const did = String(device_id || '').trim() || 'unknown';
    return `device:${did}`;
  }

  function paidAICurrentInFlightForScope(scopeKey) {
    return Number(paidAIInFlightByScope.get(scopeKey) || 0);
  }

  function paidAIHasCapacityForScope(scopeKey) {
    if (paidAIInFlightTotal >= paidAIGlobalConcurrency) return false;
    return paidAICurrentInFlightForScope(scopeKey) < paidAIPerProjectConcurrency;
  }

  function paidAIAcquireScope(scopeKey) {
    paidAIInFlightTotal += 1;
    const cur = paidAICurrentInFlightForScope(scopeKey);
    paidAIInFlightByScope.set(scopeKey, cur + 1);
  }

  function paidAIReleaseScope(scopeKey) {
    paidAIInFlightTotal = Math.max(0, paidAIInFlightTotal - 1);
    const cur = paidAICurrentInFlightForScope(scopeKey);
    if (cur <= 1) {
      paidAIInFlightByScope.delete(scopeKey);
    } else {
      paidAIInFlightByScope.set(scopeKey, cur - 1);
    }
  }

  function makePaidAISlotRelease(scopeKey) {
    let released = false;
    return () => {
      if (released) return;
      released = true;
      paidAIReleaseScope(scopeKey);
      paidAIDrainQueue();
    };
  }

  function paidAIRemoveQueueEntry(entry, { markSettled = true } = {}) {
    if (!entry) return;
    if (entry.settled && markSettled) return;
    if (markSettled) entry.settled = true;
    if (entry.timer) {
      clearTimeout(entry.timer);
      entry.timer = null;
    }
    const rid = String(entry.requestId || '').trim();
    if (rid) paidAIQueuedByRequestId.delete(rid);
    const idx = paidAIQueue.indexOf(entry);
    if (idx >= 0) {
      paidAIQueue.splice(idx, 1);
      if (paidAIQueue.length <= 0) {
        paidAIQueueCursor = 0;
      } else if (paidAIQueueCursor >= paidAIQueue.length) {
        paidAIQueueCursor = paidAIQueueCursor % paidAIQueue.length;
      }
    }
  }

  function paidAIDrainQueue() {
    if (paidAIQueue.length <= 0) return;

    let guard = paidAIQueue.length + 4;
    while (guard > 0) {
      guard -= 1;
      if (paidAIInFlightTotal >= paidAIGlobalConcurrency) break;
      if (paidAIQueue.length <= 0) break;

      let picked = -1;
      const n = paidAIQueue.length;
      for (let i = 0; i < n; i += 1) {
        const idx = (paidAIQueueCursor + i) % n;
        const item = paidAIQueue[idx];
        if (!item || item.settled) continue;
        if (item.shouldAbort && item.shouldAbort()) {
          paidAIRemoveQueueEntry(item);
          try {
            item.reject(new Error('canceled'));
          } catch {
            // ignore
          }
          continue;
        }
        if (!paidAIHasCapacityForScope(item.scopeKey)) continue;
        picked = idx;
        break;
      }

      if (picked < 0) break;

      const entry = paidAIQueue[picked];
      const nextCursorBase = paidAIQueue.length > 1 ? picked : 0;
      paidAIRemoveQueueEntry(entry, { markSettled: false });
      if (paidAIQueue.length > 0) {
        paidAIQueueCursor = nextCursorBase % paidAIQueue.length;
      } else {
        paidAIQueueCursor = 0;
      }
      if (!entry || entry.settled) continue;
      if (entry.shouldAbort && entry.shouldAbort()) {
        entry.settled = true;
        try {
          entry.reject(new Error('canceled'));
        } catch {
          // ignore
        }
        continue;
      }

      paidAIAcquireScope(entry.scopeKey);
      try {
        entry.settled = true;
        entry.resolve({
          release: makePaidAISlotRelease(entry.scopeKey),
          queuedMs: Math.max(0, nowMs() - Number(entry.enqueuedAtMs || nowMs())),
        });
      } catch {
        paidAIReleaseScope(entry.scopeKey);
      }
    }
  }

  function cancelPaidAIQueueWait(requestId, reason = 'canceled') {
    const rid = String(requestId || '').trim();
    if (!rid) return false;
    const entry = paidAIQueuedByRequestId.get(rid);
    if (!entry || entry.settled) return false;
    paidAIRemoveQueueEntry(entry);
    try {
      entry.reject(new Error(String(reason || 'canceled')));
    } catch {
      // ignore
    }
    return true;
  }

  async function acquirePaidAISlot({
    requestId,
    project_id,
    device_id,
    waitMs = paidAIQueueTimeoutMs,
    shouldAbort,
    onQueued,
  }) {
    const rid = String(requestId || '').trim();
    const scopeKey = paidAIScopeKey({ project_id, device_id });
    const shouldStop = typeof shouldAbort === 'function' ? shouldAbort : () => false;

    if (shouldStop()) throw new Error('canceled');

    if (paidAIHasCapacityForScope(scopeKey)) {
      paidAIAcquireScope(scopeKey);
      return {
        release: makePaidAISlotRelease(scopeKey),
        queuedMs: 0,
      };
    }

    if (paidAIQueue.length >= paidAIQueueLimit) {
      throw new Error('hub_ai_queue_full');
    }

    return await new Promise((resolve, reject) => {
      const entry = {
        requestId: rid,
        scopeKey,
        enqueuedAtMs: nowMs(),
        resolve,
        reject,
        timer: null,
        settled: false,
        shouldAbort: shouldStop,
      };

      paidAIQueue.push(entry);
      if (rid) paidAIQueuedByRequestId.set(rid, entry);

      const timeoutMs = parseIntInRange(waitMs, paidAIQueueTimeoutMs, 1000, 300000);
      entry.timer = setTimeout(() => {
        if (entry.settled) return;
        paidAIRemoveQueueEntry(entry);
        try {
          reject(new Error('hub_ai_queue_timeout'));
        } catch {
          // ignore
        }
      }, timeoutMs);

      if (typeof onQueued === 'function') {
        try {
          onQueued({
            depth: paidAIQueue.length,
            wait_timeout_ms: timeoutMs,
          });
        } catch {
          // ignore
        }
      }
    });
  }

  function isLoopbackIp(ip) {
    const s = String(ip || '').trim();
    if (!s) return false;
    if (s === '::1') return true;
    if (s === '127.0.0.1') return true;
    if (s.startsWith('127.')) return true; // 127.0.0.0/8
    return false;
  }

  function policyAckForGrantRequest(grantRequestId) {
    const gid = String(grantRequestId || '').trim();
    if (!gid) {
      return { user_ack_understood: false, explain_rounds: 0, options_presented: false };
    }
    try {
      const row = db.getGrantRequest(gid);
      return parsePolicyAckFields({
        user_ack_understood: row?.user_ack_understood,
        explain_rounds: row?.explain_rounds,
        options_presented: row?.options_presented,
        note: row?.note,
      });
    } catch {
      return { user_ack_understood: false, explain_rounds: 0, options_presented: false };
    }
  }

  function appendPolicyEvalAudit({
    created_at_ms,
    device_id,
    user_id,
    app_id,
    project_id,
    session_id,
    request_id,
    capability,
    model_id,
    decision,
    policy_scope,
    rule_ids,
    ttl_sec,
    phase,
    grant_request_id,
    grant_id,
    user_ack_understood,
    explain_rounds,
    options_presented,
    ok,
    error_code,
    error_message,
    ext,
  }) {
    const dec = String(decision || '').trim().toLowerCase() || 'allow';
    const denied = dec === 'deny' || dec === 'denied' || dec === 'blocked' || dec === 'revoked';
    const sev = denied ? 'security' : dec === 'queued' ? 'warn' : 'info';
    const ruleIds = Array.isArray(rule_ids)
      ? Array.from(new Set(rule_ids.map((s) => String(s || '').trim()).filter(Boolean)))
      : [];
    const extObj = compactObject({
      phase: String(phase || '').trim() || null,
      policy_decision: dec,
      policy_scope: String(policy_scope || '').trim() || null,
      rule_ids: ruleIds,
      ttl_sec: parseNonNegativeInt(ttl_sec),
      grant_request_id: String(grant_request_id || '').trim() || null,
      grant_id: String(grant_id || '').trim() || null,
      user_ack_understood: user_ack_understood == null ? false : !!user_ack_understood,
      explain_rounds: parseNonNegativeInt(explain_rounds) ?? 0,
      options_presented: options_presented == null ? false : !!options_presented,
      ...(ext && typeof ext === 'object' ? ext : {}),
    });

    db.appendAudit({
      event_type: 'policy_eval',
      created_at_ms: Number(created_at_ms || nowMs()),
      severity: sev,
      device_id: String(device_id || 'unknown'),
      user_id: user_id ? String(user_id) : null,
      app_id: String(app_id || 'unknown'),
      project_id: project_id ? String(project_id) : null,
      session_id: session_id ? String(session_id) : null,
      request_id: request_id ? String(request_id) : null,
      capability: capability ? String(capability) : null,
      model_id: model_id ? String(model_id) : null,
      ok: typeof ok === 'boolean' ? ok : !denied,
      error_code: error_code ? String(error_code) : null,
      error_message: error_message ? String(error_message) : null,
      ext_json: JSON.stringify(extObj),
    });
  }

  function writeJsonAtomic(filePath, obj) {
    const out = String(filePath || '').trim();
    if (!out) return false;
    try {
      fs.mkdirSync(path.dirname(out), { recursive: true });
    } catch {
      // ignore
    }
    const tmp = `${out}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
    try {
      fs.writeFileSync(tmp, JSON.stringify(obj), { encoding: 'utf8' });
      fs.renameSync(tmp, out);
      return true;
    } catch {
      try {
        fs.unlinkSync(tmp);
      } catch {
        // ignore
      }
      return false;
    }
  }

  function writeGrpcDevicesStatus(runtimeBaseDir) {
    const base = String(runtimeBaseDir || '').trim();
    if (!base) return;

    const quotaDay = utcDayKey(Date.now());
    let quotaCfg = null;
    try {
      quotaCfg = loadQuotaConfig(base, 5000);
    } catch {
      quotaCfg = null;
    }

    let runtimeClients = [];
    try {
      runtimeClients = loadClients(base, 500);
    } catch {
      runtimeClients = [];
    }
    const runtimeClientsByDeviceId = new Map(
      (runtimeClients || [])
        .map((client) => [String(client?.device_id || '').trim(), client])
        .filter(([deviceId]) => !!deviceId)
    );

    const deviceIds = new Set([
      ...Array.from(eventSubsByDeviceId.keys()),
      ...Array.from(runtimeClientsByDeviceId.keys()),
    ]);

    const devices = [];
    for (const device_id of deviceIds) {
      if (!device_id) continue;
      const st = eventSubsByDeviceId.get(device_id) || null;
      const runtimeClient = runtimeClientsByDeviceId.get(device_id) || null;
      const scope = `device:${device_id}`;
      const quotaUsed = db.getQuotaUsageDaily(scope, quotaDay);
      const legacyCap = quotaCfg ? resolveDeviceDailyTokenCap(quotaCfg, device_id) : 0;

      let usageSummary = null;
      try {
        usageSummary = db.getTerminalUsageSummaryDaily({ device_id, day_bucket: quotaDay });
      } catch {
        usageSummary = null;
      }
      const modelBreakdown = (() => {
        try {
          return db.listTerminalModelUsageDaily({ device_id, day_bucket: quotaDay, limit: 5 });
        } catch {
          return [];
        }
      })();

      let lastActivity = null;
      try {
        const row = db.getLatestDeviceActivity(device_id);
        if (row) {
          lastActivity = {
            event_type: String(row.event_type || ''),
            created_at_ms: Number(row.created_at_ms || 0),
            capability: row.capability != null ? String(row.capability || '') : '',
            model_id: row.model_id != null ? String(row.model_id || '') : '',
            total_tokens: row.total_tokens != null ? Number(row.total_tokens || 0) : 0,
            network_allowed: row.network_allowed != null ? !!Number(row.network_allowed || 0) : false,
            ok: !!Number(row.ok || 0),
            error_code: row.error_code != null ? String(row.error_code || '') : '',
            error_message: row.error_message != null ? String(row.error_message || '') : '',
          };
        }
      } catch {
        lastActivity = null;
      }

      const nowAtMs = Date.now();
      const windowMs = 60 * 60 * 1000;
      const bucketMs = 5 * 60 * 1000;
      const sinceMs = Math.max(0, nowAtMs - windowMs);
      const startBucket = Math.floor(sinceMs / bucketMs);
      const startMs = startBucket * bucketMs;
      const bucketCount = Math.max(1, Math.ceil(windowMs / bucketMs));
      let seriesPoints = [];
      try {
        const raw = db.listDeviceTokenBuckets({ device_id, since_ms: startMs, bucket_ms: bucketMs });
        const byStart = new Map((raw || []).map((row) => [Number(row.bucket_start_ms || 0), Number(row.tokens || 0)]));
        for (let index = 0; index < bucketCount; index += 1) {
          const bucketStart = startMs + index * bucketMs;
          seriesPoints.push({ t_ms: bucketStart, tokens: byStart.get(bucketStart) || 0 });
        }
      } catch {
        seriesPoints = [];
      }

      const profileLimit = nonNegativeInt(runtimeClient?.daily_token_limit, 0);
      const dailyTokenLimit = profileLimit > 0 ? profileLimit : nonNegativeInt(legacyCap, 0);
      const summaryTokens = nonNegativeInt(usageSummary?.total_tokens, 0);
      const dailyTokenUsed = runtimeClient?.trust_profile_present ? summaryTokens : Math.max(summaryTokens, nonNegativeInt(quotaUsed, 0));
      const remainingBudget = dailyTokenLimit > 0 ? Math.max(0, dailyTokenLimit - dailyTokenUsed) : 0;
      const resolvedName = String(
        st?.name
        || runtimeClient?.name
        || runtimeClient?.trust_profile?.device_name
        || modelBreakdown[0]?.device_name
        || device_id
      ).trim() || device_id;

      devices.push({
        device_id,
        name: resolvedName,
        device_name: resolvedName,
        peer_ip: String(st?.peer_ip || '').trim(),
        connected: Number(st?.count || 0) > 0,
        active_event_subscriptions: Number(st?.count || 0),
        connected_at_ms: Number(st?.connected_at_ms || 0),
        last_seen_at_ms: Number(st?.last_seen_at_ms || 0),
        quota_day: quotaDay,
        daily_token_used: dailyTokenUsed,
        daily_token_cap: dailyTokenLimit,
        daily_token_limit: dailyTokenLimit,
        daily_token_remaining: remainingBudget,
        remaining_daily_token_budget: remainingBudget,
        requests_today: nonNegativeInt(usageSummary?.request_count, 0),
        blocked_today: nonNegativeInt(usageSummary?.blocked_count, 0),
        paid_model_policy_mode: String(runtimeClient?.paid_model_policy_mode || (runtimeClient?.trust_profile_present ? 'off' : 'legacy_grant')).trim(),
        default_web_fetch_enabled: !!runtimeClient?.default_web_fetch_enabled,
        trust_profile_present: !!runtimeClient?.trust_profile_present,
        trust_mode: String(runtimeClient?.trust_mode || '').trim(),
        top_model: String(usageSummary?.top_model || modelBreakdown[0]?.model_id || '').trim(),
        last_blocked_reason: String(usageSummary?.last_blocked_reason || '').trim(),
        last_deny_code: String(usageSummary?.last_deny_code || '').trim(),
        model_breakdown: (modelBreakdown || []).map((row) => ({
          device_id: String(row.device_id || device_id),
          device_name: String(row.device_name || resolvedName),
          model_id: String(row.model_id || ''),
          day_bucket: String(row.day_bucket || quotaDay),
          prompt_tokens: nonNegativeInt(row.prompt_tokens, 0),
          completion_tokens: nonNegativeInt(row.completion_tokens, 0),
          total_tokens: nonNegativeInt(row.total_tokens, 0),
          request_count: nonNegativeInt(row.request_count, 0),
          blocked_count: nonNegativeInt(row.blocked_count, 0),
          last_used_at_ms: nonNegativeInt(row.last_used_at_ms, 0),
          last_blocked_at_ms: nonNegativeInt(row.last_blocked_at_ms, 0),
          last_blocked_reason: String(row.last_blocked_reason || '').trim(),
          last_deny_code: String(row.last_deny_code || '').trim(),
        })),
        last_activity: lastActivity,
        token_series_5m_1h: {
          window_ms: windowMs,
          bucket_ms: bucketMs,
          start_ms: startMs,
          points: seriesPoints,
        },
      });
    }
    devices.sort((left, right) => {
      const leftName = String(left.name || left.device_id || '').toLowerCase();
      const rightName = String(right.name || right.device_id || '').toLowerCase();
      if (leftName !== rightName) return leftName < rightName ? -1 : 1;
      return String(left.device_id || '').localeCompare(String(right.device_id || ''));
    });

    writeJsonAtomic(path.join(base, 'grpc_devices_status.json'), {
      schema_version: 'grpc_devices_status.v2',
      updated_at_ms: Date.now(),
      devices,
    });
  }

  function buildPaidAISchedulerSnapshot({ includeQueueItems = true, queueItemsLimit = 100 } = {}) {
    const now = Date.now();
    const queueByScope = new Map();
    const queueItems = [];
    let oldestQueuedMs = 0;

    for (const item of paidAIQueue) {
      if (!item || item.settled) continue;
      const scopeKey = String(item.scopeKey || '').trim() || 'unknown';
      queueByScope.set(scopeKey, Number(queueByScope.get(scopeKey) || 0) + 1);
      const enqueuedAt = Number(item.enqueuedAtMs || now);
      const queuedMs = Math.max(0, now - enqueuedAt);
      if (queuedMs > oldestQueuedMs) oldestQueuedMs = queuedMs;
      queueItems.push({
        request_id: String(item.requestId || '').trim(),
        scope_key: scopeKey,
        enqueued_at_ms: enqueuedAt,
        queued_ms: queuedMs,
      });
    }

    const inFlightByScope = Array.from(paidAIInFlightByScope.entries())
      .map(([scopeKey, n]) => ({
        scope_key: String(scopeKey || '').trim() || 'unknown',
        in_flight: Number(n || 0),
      }))
      .sort((a, b) => b.in_flight - a.in_flight || a.scope_key.localeCompare(b.scope_key));

    const queuedByScope = Array.from(queueByScope.entries())
      .map(([scopeKey, n]) => ({
        scope_key: String(scopeKey || '').trim() || 'unknown',
        queued: Number(n || 0),
      }))
      .sort((a, b) => b.queued - a.queued || a.scope_key.localeCompare(b.scope_key));

    queueItems.sort((a, b) => b.queued_ms - a.queued_ms || a.request_id.localeCompare(b.request_id));

    const wantedQueueLimit = parseIntInRange(queueItemsLimit, 100, 1, 500);
    return {
      updated_at_ms: now,
      global_concurrency: paidAIGlobalConcurrency,
      per_project_concurrency: paidAIPerProjectConcurrency,
      queue_limit: paidAIQueueLimit,
      queue_timeout_ms: paidAIQueueTimeoutMs,
      in_flight_total: paidAIInFlightTotal,
      queue_depth: queueItems.length,
      oldest_queued_ms: oldestQueuedMs,
      in_flight_by_scope: inFlightByScope,
      queued_by_scope: queuedByScope,
      queue_items: includeQueueItems ? queueItems.slice(0, wantedQueueLimit) : [],
    };
  }

  function writePaidAISchedulerStatus(runtimeBaseDir) {
    const base = String(runtimeBaseDir || '').trim();
    if (!base) return;
    const snapshot = buildPaidAISchedulerSnapshot({ includeQueueItems: true, queueItemsLimit: 100 });

    writeJsonAtomic(path.join(base, 'paid_ai_scheduler_status.json'), {
      schema_version: 'paid_ai_scheduler_status.v1',
      updated_at_ms: snapshot.updated_at_ms,
      config: {
        global_concurrency: snapshot.global_concurrency,
        per_project_concurrency: snapshot.per_project_concurrency,
        queue_limit: snapshot.queue_limit,
        queue_timeout_ms: snapshot.queue_timeout_ms,
      },
      state: {
        in_flight_total: snapshot.in_flight_total,
        queue_depth: snapshot.queue_depth,
        oldest_queued_ms: snapshot.oldest_queued_ms,
      },
      in_flight_by_scope: snapshot.in_flight_by_scope,
      queued_by_scope: snapshot.queued_by_scope,
      queue_items: snapshot.queue_items,
    });
  }

  function buildPendingGrantRequestsSnapshot({
    deviceId = '',
    userId = '',
    appId = '',
    projectId = '',
    limit = 200,
  } = {}) {
    const rows = db.listPendingGrantRequests({
      device_id: deviceId,
      user_id: userId,
      app_id: appId,
      project_id: projectId,
      limit: parseIntInRange(limit, 200, 1, 500),
    });
    return {
      updated_at_ms: nowMs(),
      items: Array.isArray(rows) ? rows.map(makeProtoPendingGrantItem).filter(Boolean) : [],
    };
  }

  function buildConnectorIngressReceiptsSnapshot({
    projectId = '',
    limit = 200,
  } = {}) {
    const base = String(resolveRuntimeBaseDir() || '').trim();
    const filePath = base ? path.join(base, 'connector_ingress_receipts_status.json') : '';
    let decoded = null;
    if (filePath) {
      try {
        decoded = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      } catch {
        decoded = null;
      }
    }

    const normalizedProjectId = String(projectId || '').trim();
    const boundedLimit = parseIntInRange(limit, 200, 1, 500);
    const rows = Array.isArray(decoded?.items) ? decoded.items : [];
    const items = rows
      .map(makeProtoConnectorIngressReceipt)
      .filter(Boolean)
      .filter((row) => !normalizedProjectId || String(row.project_id || '').trim() === normalizedProjectId)
      .sort((left, right) => {
        const lts = Number(left?.received_at_ms || 0);
        const rts = Number(right?.received_at_ms || 0);
        if (lts !== rts) return rts - lts;
        return String(left?.receipt_id || '').localeCompare(String(right?.receipt_id || ''));
      })
      .slice(0, boundedLimit);

    return {
      updated_at_ms: Number(decoded?.updated_at_ms || 0),
      items,
    };
  }

  function buildAutonomyPolicyOverridesSnapshot({
    projectId = '',
    limit = 200,
  } = {}) {
    const base = String(resolveRuntimeBaseDir() || '').trim();
    const filePath = base ? path.join(base, 'autonomy_policy_overrides_status.json') : '';
    let decoded = null;
    if (filePath) {
      try {
        decoded = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      } catch {
        decoded = null;
      }
    }

    const normalizedProjectId = String(projectId || '').trim();
    const boundedLimit = parseIntInRange(limit, 200, 1, 500);
    const rows = Array.isArray(decoded?.items) ? decoded.items : [];
    const items = rows
      .map(makeProtoAutonomyPolicyOverrideItem)
      .filter(Boolean)
      .filter((row) => !normalizedProjectId || String(row.project_id || '').trim() === normalizedProjectId)
      .sort((left, right) => {
        const lts = Number(left?.updated_at_ms || 0);
        const rts = Number(right?.updated_at_ms || 0);
        if (lts !== rts) return rts - lts;
        return String(left?.project_id || '').localeCompare(String(right?.project_id || ''));
      })
      .slice(0, boundedLimit);

    const updatedAtMs = Number(decoded?.updated_at_ms || 0);
    return {
      updated_at_ms: updatedAtMs > 0 ? updatedAtMs : (items[0]?.updated_at_ms || 0),
      items,
    };
  }

  function writePendingGrantRequestsStatus(runtimeBaseDir) {
    const base = String(runtimeBaseDir || '').trim();
    if (!base) return;
    const snapshot = buildPendingGrantRequestsSnapshot({
      deviceId: '',
      userId: '',
      appId: '',
      projectId: '',
      limit: 400,
    });
    writeJsonAtomic(path.join(base, 'pending_grant_requests_status.json'), {
      schema_version: 'pending_grant_requests_status.v1',
      updated_at_ms: snapshot.updated_at_ms,
      items: snapshot.items,
    });
  }

  function writeAutonomyPolicyOverridesStatus(runtimeBaseDir) {
    const base = String(runtimeBaseDir || '').trim();
    if (!base) return;
    const filePath = path.join(base, 'autonomy_policy_overrides_status.json');
    const snapshot = buildAutonomyPolicyOverridesSnapshot({
      projectId: '',
      limit: 400,
    });
    if (!fs.existsSync(filePath) && (!Array.isArray(snapshot.items) || snapshot.items.length === 0)) {
      return;
    }
    writeJsonAtomic(filePath, {
      schema_version: 'autonomy_policy_overrides_status.v1',
      updated_at_ms: Number(snapshot.updated_at_ms || 0),
      items: Array.isArray(snapshot.items) ? snapshot.items : [],
    });
  }

  // Periodically refresh the exported snapshot so the Hub UI can render near-real-time
  // token usage without requiring reconnects.
  const statusIntervalMs = Math.max(500, Number(process.env.HUB_GRPC_STATUS_EXPORT_MS || 2000));
  const statusTimer = setInterval(() => {
    try {
      writeGrpcDevicesStatus(resolveRuntimeBaseDir());
      writePaidAISchedulerStatus(resolveRuntimeBaseDir());
      writePendingGrantRequestsStatus(resolveRuntimeBaseDir());
      writeAutonomyPolicyOverridesStatus(resolveRuntimeBaseDir());
    } catch {
      // ignore
    }
  }, statusIntervalMs);
  if (typeof statusTimer.unref === 'function') statusTimer.unref();

  // Keep payment intent timeout rollback bounded even when there are no incoming payment RPCs.
  const paymentExpireSweepMs = parseIntInRange(process.env.HUB_PAYMENT_INTENT_SWEEP_MS, 1000, 50, 5000);
  const paymentExpireSweepLimit = parseIntInRange(process.env.HUB_PAYMENT_INTENT_SWEEP_LIMIT, 200, 1, 500);
  const paymentCompensationSweepLimit = parseIntInRange(process.env.HUB_PAYMENT_RECEIPT_COMPENSATION_SWEEP_LIMIT, 200, 1, 500);
  const paymentExpireTimer = setInterval(() => {
    try {
      const expiredRows = db.expireStalePaymentIntents({
        now_ms: nowMs(),
        limit: paymentExpireSweepLimit,
      });
      if (Array.isArray(expiredRows) && expiredRows.length > 0) {
        appendPaymentExpiredAudits({
          expiredRows,
          client: {},
          request_id: '',
          op: 'payment_expire_sweep',
        });
      }
      const compensation = db.runPaymentReceiptCompensationWorker({
        now_ms: nowMs(),
        limit: paymentCompensationSweepLimit,
      });
      if (Array.isArray(compensation?.compensated) && compensation.compensated.length > 0) {
        appendPaymentCompensatedAudits({
          compensatedRows: compensation.compensated,
          op: 'payment_receipt_compensation_sweep',
        });
      }
    } catch {
      // ignore
    }
  }, paymentExpireSweepMs);
  if (typeof paymentExpireTimer.unref === 'function') paymentExpireTimer.unref();

  function clientAllows(auth, capabilityKey) {
    const requiresExplicitCapabilities = (() => {
      const policyMode = String(auth?.policy_mode || '').trim().toLowerCase();
      const trustMode = String(auth?.trust_mode || '').trim().toLowerCase();
      const trustedAutomationMode = String(
        auth?.trusted_automation_mode
        || auth?.approved_trust_profile?.mode
        || ''
      ).trim().toLowerCase();
      return policyMode === 'new_profile'
        || trustMode === 'trusted_automation'
        || trustedAutomationMode === 'trusted_automation';
    })();
    const wanted = String(capabilityKey || '').trim();
    if (!wanted) {
      if (auth && typeof auth === 'object') auth.capability_deny_code = '';
      return true;
    }
    const caps = Array.isArray(auth?.capabilities)
      ? auth.capabilities.map((c) => String(c || '').trim()).filter(Boolean)
      : [];
    if (caps.length === 0) {
      const denyCode = requiresExplicitCapabilities ? 'trusted_automation_capabilities_empty_blocked' : '';
      if (auth && typeof auth === 'object') auth.capability_deny_code = denyCode;
      return !denyCode;
    }
    // Backward compatibility: existing clients created before HubSkills shipped only had
    // "memory" capability. Allow skills APIs for those clients to avoid a hard break.
    // Set HUB_REQUIRE_SKILLS_CAP=1 to require an explicit "skills" capability entry.
    if (wanted === 'skills' && String(process.env.HUB_REQUIRE_SKILLS_CAP || '').trim() !== '1' && caps.includes('memory')) {
      if (auth && typeof auth === 'object') auth.capability_deny_code = '';
      return true;
    }
    const allowed = caps.includes(wanted);
    if (auth && typeof auth === 'object') auth.capability_deny_code = allowed ? '' : 'permission_denied';
    return allowed;
  }

  function capabilityDenyCode(auth) {
    const code = String(auth?.trusted_automation_deny_code || auth?.capability_deny_code || '').trim();
    return code || 'permission_denied';
  }

  function trustedAutomationMode(auth) {
    return String(
      auth?.trusted_automation_mode
      || auth?.approved_trust_profile?.mode
      || auth?.trust_mode
      || ''
    ).trim().toLowerCase();
  }

  function trustedAutomationState(auth) {
    return String(
      auth?.trusted_automation_state
      || auth?.approved_trust_profile?.state
      || ''
    ).trim().toLowerCase();
  }

  function trustedAutomationEnabled(auth) {
    return trustedAutomationMode(auth) === 'trusted_automation';
  }

  function normalizeTrustedAutomationRoot(value) {
    const raw = String(value || '').trim();
    if (!raw) return '';
    try {
      return path.resolve(raw);
    } catch {
      return raw;
    }
  }

  function trustedAutomationPathWithinRoot(candidate, root) {
    const target = normalizeTrustedAutomationRoot(candidate);
    const base = normalizeTrustedAutomationRoot(root);
    if (!target || !base) return false;
    const rel = path.relative(base, target);
    return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
  }

  function trustedAutomationScopeFromRequest(req, client) {
    const request = req && typeof req === 'object' ? req : {};
    const actor = client && typeof client === 'object' ? client : {};
    return {
      project_id: String(
        actor.project_id
        || actor.projectId
        || request.project_id
        || request.projectId
        || ''
      ).trim(),
      workspace_root: normalizeTrustedAutomationRoot(
        actor.workspace_root
        || actor.workspaceRoot
        || actor.project_root
        || actor.projectRoot
        || request.workspace_root
        || request.workspaceRoot
        || request.project_root
        || request.projectRoot
        || ''
      ),
    };
  }

  function trustedAutomationScopeWithProject(scope, ...projectIds) {
    const base = scope && typeof scope === 'object' ? scope : {};
    const project_id = projectIds
      .map((value) => String(value || '').trim())
      .find(Boolean) || String(base.project_id || '').trim();
    return {
      project_id,
      workspace_root: normalizeTrustedAutomationRoot(base.workspace_root || ''),
    };
  }

  function setTrustedAutomationDenyCode(auth, code) {
    if (auth && typeof auth === 'object') {
      auth.trusted_automation_deny_code = String(code || '').trim();
    }
  }

  function trustedAutomationAllows(auth, scope = {}) {
    setTrustedAutomationDenyCode(auth, '');
    if (!trustedAutomationEnabled(auth)) return true;

    const trustProfilePresent = !!(auth?.trust_profile_present || auth?.approved_trust_profile);
    if (!trustProfilePresent) {
      setTrustedAutomationDenyCode(auth, 'trusted_automation_profile_missing');
      return false;
    }

    const state = trustedAutomationState(auth);
    if (!state || state === 'off' || state === 'blocked') {
      setTrustedAutomationDenyCode(auth, 'trusted_automation_mode_off');
      return false;
    }

    const allowedProjectIds = safeStringList(
      auth?.allowed_project_ids
      || auth?.approved_trust_profile?.allowed_project_ids
      || []
    );
    const allowedWorkspaceRoots = safeStringList(
      auth?.allowed_workspace_roots
      || auth?.approved_trust_profile?.allowed_workspace_roots
      || []
    )
      .map((root) => normalizeTrustedAutomationRoot(root))
      .filter(Boolean);
    const xtBindingRequired = !!(
      auth?.xt_binding_required
      ?? auth?.approved_trust_profile?.xt_binding_required
    );
    const devicePermissionOwnerRef = String(
      auth?.device_permission_owner_ref
      || auth?.approved_trust_profile?.device_permission_owner_ref
      || ''
    ).trim();
    if (xtBindingRequired && !devicePermissionOwnerRef) {
      setTrustedAutomationDenyCode(auth, 'device_permission_owner_missing');
      return false;
    }

    const projectId = String(scope?.project_id || '').trim();
    const workspaceRoot = normalizeTrustedAutomationRoot(scope?.workspace_root || '');
    const hasProjectBindings = allowedProjectIds.length > 0;
    const hasWorkspaceBindings = allowedWorkspaceRoots.length > 0;
    if (xtBindingRequired && !hasProjectBindings && !hasWorkspaceBindings) {
      setTrustedAutomationDenyCode(auth, 'trusted_automation_project_not_bound');
      return false;
    }

    const projectProvided = !!projectId;
    const workspaceProvided = !!workspaceRoot;
    const projectMatched = hasProjectBindings && projectProvided && allowedProjectIds.includes(projectId);
    const workspaceMatched = hasWorkspaceBindings
      && workspaceProvided
      && allowedWorkspaceRoots.some((root) => trustedAutomationPathWithinRoot(workspaceRoot, root));

    if (hasProjectBindings && projectProvided && !projectMatched) {
      setTrustedAutomationDenyCode(auth, 'trusted_automation_project_not_bound');
      return false;
    }
    if (hasWorkspaceBindings && workspaceProvided && !workspaceMatched) {
      setTrustedAutomationDenyCode(auth, 'trusted_automation_workspace_mismatch');
      return false;
    }
    if (hasProjectBindings || hasWorkspaceBindings) {
      if (projectMatched || workspaceMatched) return true;
      if (hasProjectBindings && !projectProvided && !(hasWorkspaceBindings && workspaceMatched)) {
        setTrustedAutomationDenyCode(auth, 'trusted_automation_project_not_bound');
        return false;
      }
      if (hasWorkspaceBindings && !workspaceProvided && !(hasProjectBindings && projectMatched)) {
        setTrustedAutomationDenyCode(auth, 'trusted_automation_workspace_mismatch');
        return false;
      }
    }

    return true;
  }

  function effectiveClientIdentity(raw, auth) {
    const base = raw && typeof raw === 'object' ? { ...raw } : {};
    const did = String(auth?.device_id || '').trim();
    if (did) base.device_id = did;
    const uid = String(auth?.user_id || '').trim();
    if (uid) base.user_id = uid;
    return base;
  }

  // -------------------- HubModels --------------------
  function ListModels(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'models')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    // Prefer the runtime-published models_state.json when available (authoritative list of configured models).
    const runtimeBaseDir = resolveRuntimeBaseDir();
    const snap = runtimeModelsSnapshot(runtimeBaseDir);
    if (snap.ok && Array.isArray(snap.models) && snap.models.length) {
      const models = snap.models.map(makeProtoModelInfo).filter(Boolean);
      callback(null, { updated_at_ms: Number(snap.updated_at_ms || nowMs()), models });
      return;
    }

    // Fallback: DB seeds (mostly for dev/smoke).
    const rows = db.listModels();
    const models = rows.map(makeProtoModelInfo).filter(Boolean);
    callback(null, { updated_at_ms: nowMs(), models });
  }

  // -------------------- HubGrants --------------------
  function RequestGrant(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    if (trustedAutomationScope.project_id) client.project_id = trustedAutomationScope.project_id;
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const request_id = String(req.request_id || '').trim();
    const capability = capabilityDbKey(req.capability);
    const model_id = (req.model_id || '').toString().trim();

    if (!device_id || !app_id || !request_id || capability === 'unknown') {
      callback(new Error('invalid grant request: missing device_id/app_id/request_id/capability'));
      return;
    }
    if (!clientAllows(auth, capability)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    if (capability === 'ai.generate.paid' && !model_id) {
      callback(new Error('invalid grant request: missing model_id for ai.generate.paid'));
      return;
    }
    if (capability === 'ai.generate.paid') {
      const runtimeBaseDir = resolveRuntimeBaseDir();
      const m = (db.getModel(model_id) || runtimeModelMeta(runtimeBaseDir, model_id)) ?? null;
      if (!m) {
        callback(new Error('invalid grant request: unknown model_id'));
        return;
      }
      const isPaid = isPaidModelMeta(m);
      if (!isPaid) {
        callback(new Error('invalid grant request: model does not require paid grant'));
        return;
      }
    }

    // Idempotency: return the previous decision if already created.
    const existing = db.findGrantRequestByIdempotency(device_id, request_id);
    if (existing && existing.grant_request_id) {
      const decision = String(existing.decision || '').toLowerCase();
      const out = {
        grant_request_id: String(existing.grant_request_id),
        decision: grantDecisionEnum(decision),
        grant: null,
        deny_reason: existing.deny_reason ? String(existing.deny_reason) : '',
      };
      if (decision === 'approved') {
        // Best-effort: pick the most recent active grant for this device/capability/model.
        const g = db.findActiveGrant({
          device_id,
          user_id: client.user_id ? String(client.user_id) : '',
          app_id,
          capability,
          model_id: model_id || null,
        });
        out.grant = makeProtoGrant(g);
      }
      callback(null, out);
      return;
    }

    const requested_ttl_sec = Math.max(10, Number(req.requested_ttl_sec || 0));
    const requested_token_cap = Math.max(0, Number(req.requested_token_cap || 0));

    // Kill-switch gate: deny grants for disabled capabilities.
    try {
      const ks = db.getEffectiveKillSwitch({
        device_id,
        user_id: client.user_id ? String(client.user_id) : '',
        project_id: client.project_id ? String(client.project_id) : '',
      });
      const blocked =
        (!!ks.models_disabled && (capability === 'ai.generate.local' || capability === 'ai.generate.paid')) ||
        (!!ks.network_disabled && (capability === 'web.fetch' || capability === 'ai.generate.paid'));
      if (blocked) {
        const created = db.createGrantRequest({
          request_id,
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: client.project_id ? String(client.project_id) : null,
          capability,
          model_id: model_id || null,
          reason: req.reason ? String(req.reason) : null,
          requested_ttl_sec,
          requested_token_cap,
        });
        const denyReason = ks.reason ? `kill_switch_active: ${ks.reason}` : 'kill_switch_active';
        const ackFields = parsePolicyAckFields({ reason: req.reason || '' });
        db.decideGrantRequest(created.grant_request_id, {
          status: 'denied',
          decision: 'denied',
          deny_reason: denyReason,
          approver_id: 'system',
          user_ack_understood: ackFields.user_ack_understood,
          explain_rounds: ackFields.explain_rounds,
          options_presented: ackFields.options_presented,
        });
        db.appendAudit({
          event_type: 'grant.request.denied',
          created_at_ms: nowMs(),
          severity: 'security',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: client.project_id ? String(client.project_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          ok: false,
          error_code: 'kill_switch_active',
          error_message: denyReason,
        });
        appendPolicyEvalAudit({
          created_at_ms: nowMs(),
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: client.project_id ? String(client.project_id) : null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          decision: 'deny',
          policy_scope: 'grant_request',
          rule_ids: ['kill_switch_active'],
          phase: 'explain',
          grant_request_id: created.grant_request_id,
          user_ack_understood: ackFields.user_ack_understood,
          explain_rounds: ackFields.explain_rounds,
          options_presented: ackFields.options_presented,
          ok: false,
          error_code: 'kill_switch_active',
          error_message: denyReason,
        });
        bus.emitHubEvent(
          bus.grantDecision({
            grant_request_id: created.grant_request_id,
            decision: 'GRANT_DECISION_DENIED',
            grant: null,
            deny_reason: denyReason,
            client,
          })
        );
        callback(null, { grant_request_id: created.grant_request_id, decision: 'GRANT_DECISION_DENIED', grant: null, deny_reason: denyReason });
        return;
      }
    } catch {
      // ignore kill-switch evaluation errors; fail open in MVP
    }

    const created = db.createGrantRequest({
      request_id,
      device_id,
      user_id: client.user_id ? String(client.user_id) : null,
      app_id,
      project_id: client.project_id ? String(client.project_id) : null,
      capability,
      model_id: model_id || null,
      reason: req.reason ? String(req.reason) : null,
      requested_ttl_sec,
      requested_token_cap,
    });

    // Auto-approve simple grants (MVP).
    const maxTtl = Math.max(10, Number(process.env.HUB_AUTO_APPROVE_TTL_SEC || 1800));
    const maxCap = Math.max(0, Number(process.env.HUB_AUTO_APPROVE_TOKEN_CAP || 5000));
    const autoOk = requested_ttl_sec <= maxTtl && requested_token_cap <= maxCap;

    if (!autoOk) {
      const ackFields = parsePolicyAckFields({ reason: req.reason || '' });
      db.decideGrantRequest(created.grant_request_id, {
        status: 'pending',
        decision: 'queued',
        user_ack_understood: ackFields.user_ack_understood,
        explain_rounds: ackFields.explain_rounds,
        options_presented: ackFields.options_presented,
      });
      db.appendAudit({
        event_type: 'grant.request.queued',
        created_at_ms: nowMs(),
        severity: 'info',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: client.project_id ? String(client.project_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        ok: true,
      });
      appendPolicyEvalAudit({
        created_at_ms: nowMs(),
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: client.project_id ? String(client.project_id) : null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        decision: 'queued',
        policy_scope: 'grant_request',
        rule_ids: ['requires_admin_approval'],
        phase: 'explain',
        grant_request_id: created.grant_request_id,
        user_ack_understood: ackFields.user_ack_understood,
        explain_rounds: ackFields.explain_rounds,
        options_presented: ackFields.options_presented,
        ok: true,
      });
      const ev = bus.grantDecision({
        grant_request_id: created.grant_request_id,
        decision: 'GRANT_DECISION_QUEUED',
        grant: null,
        deny_reason: '',
        client,
      });
      bus.emitHubEvent(ev);
      callback(null, { grant_request_id: created.grant_request_id, decision: 'GRANT_DECISION_QUEUED', grant: null, deny_reason: '' });
      return;
    }

    const expires_at_ms = nowMs() + requested_ttl_sec * 1000;
    const autoAck = parsePolicyAckFields({ reason: req.reason || '' });
    db.decideGrantRequest(created.grant_request_id, {
      status: 'approved',
      decision: 'approved',
      approver_id: 'auto',
      note: 'auto_approve',
      user_ack_understood: autoAck.user_ack_understood,
      explain_rounds: autoAck.explain_rounds,
      options_presented: autoAck.options_presented,
    });
    const grantRow = db.createGrant({
      grant_request_id: created.grant_request_id,
      device_id,
      user_id: client.user_id ? String(client.user_id) : null,
      app_id,
      project_id: client.project_id ? String(client.project_id) : null,
      capability,
      model_id: model_id || null,
      token_cap: requested_token_cap,
      expires_at_ms,
    });
    const grant = makeProtoGrant(grantRow);
    if (capability === 'ai.generate.paid' || capability === 'web.fetch') {
      // Best-effort: ensure Bridge stays enabled at least until the grant expires.
      try {
        ensureBridgeEnabledUntil(resolveBridgeBaseDir(), Number(expires_at_ms || 0) / 1000.0);
      } catch {
        // ignore
      }
    }

    db.appendAudit({
      event_type: 'grant.request.auto_approved',
      created_at_ms: nowMs(),
      severity: 'security',
      device_id,
      user_id: client.user_id ? String(client.user_id) : null,
      app_id,
      project_id: client.project_id ? String(client.project_id) : null,
      request_id,
      capability,
      model_id: model_id || null,
      ok: true,
      ext_json: JSON.stringify({ grant_id: grant?.grant_id || '' }),
    });
    appendPolicyEvalAudit({
      created_at_ms: nowMs(),
      device_id,
      user_id: client.user_id ? String(client.user_id) : null,
      app_id,
      project_id: client.project_id ? String(client.project_id) : null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id,
      capability,
      model_id: model_id || null,
      decision: 'auto_approved',
      policy_scope: 'grant_request',
      rule_ids: ['auto_approve_threshold'],
      ttl_sec: requested_ttl_sec,
      phase: 'confirm',
      grant_request_id: created.grant_request_id,
      grant_id: grant?.grant_id || '',
      user_ack_understood: autoAck.user_ack_understood,
      explain_rounds: autoAck.explain_rounds,
      options_presented: autoAck.options_presented,
      ok: true,
    });

    const ev = bus.grantDecision({
      grant_request_id: created.grant_request_id,
      decision: 'GRANT_DECISION_APPROVED',
      grant,
      deny_reason: '',
      client,
    });
    bus.emitHubEvent(ev);

    callback(null, { grant_request_id: created.grant_request_id, decision: 'GRANT_DECISION_APPROVED', grant, deny_reason: '' });
  }

  function ApproveGrant(call, callback) {
    const auth = requireAdminAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }

    const req = call.request || {};
    const ackFields = parsePolicyAckFields(req);
    const grant_request_id = String(req.grant_request_id || '').trim();
    if (!grant_request_id) {
      callback(new Error('missing grant_request_id'));
      return;
    }

    const gr = db.getGrantRequest(grant_request_id);
    if (!gr) {
      callback(new Error('grant_request_not_found'));
      return;
    }
    if (String(gr.status || '') !== 'pending') {
      callback(new Error(`grant_request_not_pending (${String(gr.status || '')})`));
      return;
    }

    const ttl_sec = Math.max(10, Number(req.ttl_sec || gr.requested_ttl_sec || 1800));
    const token_cap = Math.max(0, Number(req.token_cap || gr.requested_token_cap || 0));
    const expires_at_ms = nowMs() + ttl_sec * 1000;

    db.decideGrantRequest(grant_request_id, {
      status: 'approved',
      decision: 'approved',
      approver_id: req.approver_id || '',
      note: req.note || '',
      user_ack_understood: ackFields.user_ack_understood,
      explain_rounds: ackFields.explain_rounds,
      options_presented: ackFields.options_presented,
    });

    const grantRow = db.createGrant({
      grant_request_id,
      device_id: String(gr.device_id || ''),
      user_id: gr.user_id ? String(gr.user_id) : null,
      app_id: String(gr.app_id || ''),
      project_id: gr.project_id ? String(gr.project_id) : null,
      capability: String(gr.capability || ''),
      model_id: gr.model_id ? String(gr.model_id) : null,
      token_cap,
      expires_at_ms,
    });

    const grant = makeProtoGrant(grantRow);
    if (String(grantRow?.capability || '') === 'ai.generate.paid' || String(grantRow?.capability || '') === 'web.fetch') {
      try {
        ensureBridgeEnabledUntil(resolveBridgeBaseDir(), Number(expires_at_ms || 0) / 1000.0);
      } catch {
        // ignore
      }
    }
    db.appendAudit({
      event_type: 'grant.approved',
      created_at_ms: nowMs(),
      severity: 'security',
      device_id: grantRow?.device_id || 'unknown',
      user_id: grantRow?.user_id || null,
      app_id: grantRow?.app_id || 'unknown',
      project_id: grantRow?.project_id || null,
      request_id: null,
      capability: grantRow?.capability || null,
      model_id: grantRow?.model_id || null,
      ok: true,
      ext_json: JSON.stringify({ grant_request_id, approver_id: req.approver_id || '', note: req.note || '' }),
    });
    appendPolicyEvalAudit({
      created_at_ms: nowMs(),
      device_id: grantRow?.device_id || 'unknown',
      user_id: grantRow?.user_id || null,
      app_id: grantRow?.app_id || 'unknown',
      project_id: grantRow?.project_id || null,
      session_id: null,
      request_id: null,
      capability: grantRow?.capability || null,
      model_id: grantRow?.model_id || null,
      decision: 'allow',
      policy_scope: 'grant_approval',
      rule_ids: ['user_confirmed'],
      ttl_sec,
      phase: 'confirm',
      grant_request_id,
      grant_id: grant?.grant_id || '',
      user_ack_understood: ackFields.user_ack_understood,
      explain_rounds: ackFields.explain_rounds,
      options_presented: ackFields.options_presented,
      ok: true,
    });
    bus.emitHubEvent(bus.grantDecision({ grant_request_id, decision: 'GRANT_DECISION_APPROVED', grant, deny_reason: '' }));

    callback(null, { grant });
  }

  function DenyGrant(call, callback) {
    const auth = requireAdminAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    const req = call.request || {};
    const grant_request_id = String(req.grant_request_id || '').trim();
    if (!grant_request_id) {
      callback(new Error('missing grant_request_id'));
      return;
    }
    const gr = db.getGrantRequest(grant_request_id);
    if (!gr) {
      callback(new Error('grant_request_not_found'));
      return;
    }
    if (String(gr.status || '') !== 'pending') {
      callback(new Error(`grant_request_not_pending (${String(gr.status || '')})`));
      return;
    }

    const ackFields = parsePolicyAckFields(req);
    db.decideGrantRequest(grant_request_id, {
      status: 'denied',
      decision: 'denied',
      deny_reason: req.reason || 'denied',
      approver_id: req.approver_id || '',
      user_ack_understood: ackFields.user_ack_understood,
      explain_rounds: ackFields.explain_rounds,
      options_presented: ackFields.options_presented,
    });
    db.appendAudit({
      event_type: 'grant.denied',
      created_at_ms: nowMs(),
      severity: 'security',
      device_id: String(gr.device_id || 'unknown'),
      user_id: gr.user_id ? String(gr.user_id) : null,
      app_id: String(gr.app_id || 'hub_admin'),
      project_id: gr.project_id ? String(gr.project_id) : null,
      request_id: null,
      capability: gr.capability ? String(gr.capability) : null,
      model_id: gr.model_id ? String(gr.model_id) : null,
      ok: true,
      ext_json: JSON.stringify({ grant_request_id, approver_id: req.approver_id || '', reason: req.reason || '' }),
    });
    appendPolicyEvalAudit({
      created_at_ms: nowMs(),
      device_id: String(gr.device_id || 'unknown'),
      user_id: gr.user_id ? String(gr.user_id) : null,
      app_id: String(gr.app_id || 'hub_admin'),
      project_id: gr.project_id ? String(gr.project_id) : null,
      session_id: null,
      request_id: null,
      capability: gr.capability ? String(gr.capability) : null,
      model_id: gr.model_id ? String(gr.model_id) : null,
      decision: 'deny',
      policy_scope: 'grant_approval',
      rule_ids: ['user_denied'],
      phase: 'confirm',
      grant_request_id,
      user_ack_understood: ackFields.user_ack_understood,
      explain_rounds: ackFields.explain_rounds,
      options_presented: ackFields.options_presented,
      ok: false,
    });
    bus.emitHubEvent(
      bus.grantDecision({
        grant_request_id,
        decision: 'GRANT_DECISION_DENIED',
        grant: null,
        deny_reason: req.reason || '',
        client: {
          device_id: String(gr.device_id || ''),
          user_id: gr.user_id ? String(gr.user_id) : '',
          app_id: String(gr.app_id || ''),
          project_id: gr.project_id ? String(gr.project_id) : '',
          session_id: '',
        },
      })
    );
    callback(null, { grant_request_id });
  }

  function RevokeGrant(call, callback) {
    const auth = requireAdminAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    const req = call.request || {};
    const grant_id = String(req.grant_id || '').trim();
    if (!grant_id) {
      callback(new Error('missing grant_id'));
      return;
    }
    const row = db.revokeGrant(grant_id, { revoker_id: req.approver_id || '', reason: req.reason || '' });
    const grant = makeProtoGrant(row);
    db.appendAudit({
      event_type: 'grant.revoked',
      created_at_ms: nowMs(),
      severity: 'security',
      device_id: row?.device_id || 'unknown',
      user_id: row?.user_id || null,
      app_id: row?.app_id || 'unknown',
      project_id: row?.project_id || null,
      request_id: null,
      capability: row?.capability || null,
      model_id: row?.model_id || null,
      ok: true,
      ext_json: JSON.stringify({ grant_id, revoker_id: req.approver_id || '', reason: req.reason || '' }),
    });
    callback(null, { grant_id });

    // Push a grant decision update (revoked) to the owning device.
    bus.emitHubEvent(
      bus.grantDecision({
        grant_request_id: row?.grant_request_id || '',
        decision: 'GRANT_DECISION_REVOKED',
        grant,
        deny_reason: req.reason || 'revoked',
        client: grant?.client || null,
      })
    );
  }

  // -------------------- HubAI --------------------
  async function Generate(call) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      call.end();
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const request_id = String(req.request_id || uuid());
    const device_id = String(client.device_id || '').trim() || 'unknown';
    const app_id = String(client.app_id || '').trim() || 'unknown';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const model_id = String(req.model_id || '').trim();
    const failClosedOnDowngrade =
      req.fail_closed_on_downgrade === true
      || String(req.fail_closed_on_downgrade || '').trim() === '1';
    const created_at_ms = Number(req.created_at_ms || nowMs());
    const quota_day = utcDayKey(created_at_ms || nowMs());
    const quota_scope = `device:${device_id}`;

    let killSwitch = null;
    try {
      killSwitch = db.getEffectiveKillSwitch({
        device_id,
        user_id: client.user_id ? String(client.user_id) : '',
        project_id: project_id || '',
      });
    } catch {
      killSwitch = null;
    }
    if (killSwitch?.models_disabled) {
      const msg = killSwitch?.reason ? `kill_switch_active: ${killSwitch.reason}` : 'kill_switch_active';
      const error = { code: 'kill_switch_active', message: msg, retryable: false };
      call.write({ error: { request_id, error } });
      call.end();
      db.appendAudit({
        event_type: 'ai.generate.denied',
        created_at_ms: nowMs(),
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'unknown',
        model_id: model_id || null,
        network_allowed: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        ext_json: JSON.stringify(withMemoryMetricsExt(
          { created_at_ms },
          {
            event_kind: 'ai.generate.denied',
            op: 'generate',
            job_type: 'ai_generate',
            channel: 'unknown',
            remote_mode: false,
            scope: buildMetricsScope({
              scope_kind: 'project',
              device_id,
              user_id: client.user_id ? String(client.user_id) : '',
              app_id,
              project_id,
            }),
            security: {
              blocked: true,
              deny_code: error.code,
            },
          }
        )),
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      return;
    }

    const runtimeBaseDir = resolveRuntimeBaseDir();
    const model = model_id ? (db.getModel(model_id) || runtimeModelMeta(runtimeBaseDir, model_id)) : null;
    if (!model) {
      const error = { code: 'model_not_found', message: 'model_not_found', retryable: false };
      call.write({ error: { request_id, error } });
      call.end();
      db.appendAudit({
        event_type: 'ai.generate.denied',
        created_at_ms: nowMs(),
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'unknown',
        model_id: model_id || null,
        network_allowed: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        ext_json: JSON.stringify(withMemoryMetricsExt(
          { created_at_ms },
          {
            event_kind: 'ai.generate.denied',
            op: 'generate',
            job_type: 'ai_generate',
            channel: 'unknown',
            remote_mode: false,
            scope: buildMetricsScope({
              scope_kind: 'project',
              device_id,
              user_id: client.user_id ? String(client.user_id) : '',
              app_id,
              project_id,
            }),
            security: {
              blocked: true,
              deny_code: error.code,
            },
          }
        )),
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      return;
    }

    const isPaid = isPaidModelMeta(model);
    const bridgeBaseDir = isPaid ? resolveBridgeBaseDir() : runtimeBaseDir;
    const capability = isPaid ? 'ai.generate.paid' : 'ai.generate.local';
    const runtimeClientConfig = isPaid ? findRuntimeClientConfig(runtimeBaseDir, device_id) : null;
    const capabilityAllowed = clientAllows(auth, capability);
    const deviceDisplayName = String(
      runtimeClientConfig?.name
      || runtimeClientConfig?.trust_profile?.device_name
      || auth?.client_name
      || device_id
    ).trim() || device_id;
    let trustedPaidAccess = isPaid
      ? resolvePaidModelRuntimeAccess({
          runtimeClient: runtimeClientConfig,
          capabilityAllowed,
          capabilityDenyCode: capabilityDenyCode(auth),
          modelId: model_id,
          requestedTotalTokensEstimate: 0,
          usedTokensToday: 0,
        })
      : null;
    const denyPaidModelWithContext = ({ code, message, ruleIds = [], phase = 'execute', optionsPresented = false, extraExt = {} } = {}) => {
      const error = {
        code: String(code || 'permission_denied'),
        message: String(message || code || 'permission_denied'),
        retryable: false,
      };
      try {
        call.write({ error: { request_id, error } });
      } catch {
        // ignore
      }
      try {
        call.end();
      } catch {
        // ignore
      }
      db.appendAudit({
        event_type: 'ai.generate.denied',
        created_at_ms: nowMs(),
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        network_allowed: isPaid,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        ext_json: JSON.stringify(withMemoryMetricsExt(
          {
            created_at_ms,
            device_name: deviceDisplayName,
            ...extraExt,
          },
          {
            event_kind: 'ai.generate.denied',
            op: 'generate',
            job_type: 'ai_generate',
            channel: metricsChannel(isPaid),
            remote_mode: isPaid,
            scope: buildMetricsScope({
              scope_kind: 'project',
              device_id,
              user_id: client.user_id ? String(client.user_id) : '',
              app_id,
              project_id,
            }),
            security: {
              blocked: true,
              deny_code: error.code,
              deny_reason: error.message,
            },
          }
        )),
      });
      try {
        if (isPaid && model_id) {
          db.recordTerminalModelBlockedDaily({
            device_id,
            device_name: deviceDisplayName,
            model_id,
            day_bucket: quota_day,
            last_blocked_at_ms: nowMs(),
            last_blocked_reason: error.message,
            last_deny_code: error.code,
          });
          writeGrpcDevicesStatus(runtimeBaseDir);
        }
      } catch {
        // ignore
      }
      appendPolicyEvalAudit({
        created_at_ms: nowMs(),
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        decision: 'deny',
        policy_scope: 'ai_generate',
        rule_ids: Array.isArray(ruleIds) && ruleIds.length > 0 ? ruleIds : [error.code],
        phase,
        user_ack_understood: false,
        explain_rounds: 0,
        options_presented: !!optionsPresented,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        ext: {
          device_name: deviceDisplayName,
          ...extraExt,
        },
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      cancels.delete(request_id);
      return error;
    };
    if (isPaid && trustedPaidAccess?.trust_profile_present && !trustedPaidAccess.allow && trustedPaidAccess.deny_code === 'device_paid_model_disabled') {
      denyPaidModelWithContext({
        code: trustedPaidAccess.deny_code,
        message: `${deviceDisplayName}: paid model access is disabled for ${model_id}`,
        ruleIds: ['device_paid_model_disabled'],
        phase: 'execute',
        optionsPresented: false,
        extraExt: trustedPaidAccess,
      });
      return;
    }
    if (!capabilityAllowed) {
      const denyCode = capabilityDenyCode(auth);
      const error = { code: denyCode, message: denyCode, retryable: false };
      call.write({ error: { request_id, error } });
      call.end();
      db.appendAudit({
        event_type: 'ai.generate.denied',
        created_at_ms: nowMs(),
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        network_allowed: isPaid,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        ext_json: JSON.stringify(withMemoryMetricsExt(
          { peer_ip: auth?.peer_ip || '' },
          {
            event_kind: 'ai.generate.denied',
            op: 'generate',
            job_type: 'ai_generate',
            channel: metricsChannel(isPaid),
            remote_mode: isPaid,
            scope: buildMetricsScope({
              scope_kind: 'project',
              device_id,
              user_id: client.user_id ? String(client.user_id) : '',
              app_id,
              project_id,
            }),
            security: {
              blocked: true,
              deny_code: error.code,
            },
          }
        )),
      });
      appendPolicyEvalAudit({
        created_at_ms: nowMs(),
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        decision: 'deny',
        policy_scope: 'ai_generate',
        rule_ids: [denyCode],
        phase: 'execute',
        user_ack_understood: false,
        explain_rounds: 0,
        options_presented: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      denyPaidModelWithContext({
        code: denyCode,
        message: denyCode,
        ruleIds: [denyCode],
        phase: 'scope_bind',
        optionsPresented: false,
        extraExt: {
          project_binding_checked: true,
          workspace_binding_checked: !!trustedAutomationScope.workspace_root,
        },
      });
      return;
    }
    if (isPaid && killSwitch?.network_disabled) {
      const msg = killSwitch?.reason ? `kill_switch_active: ${killSwitch.reason}` : 'kill_switch_active';
      const error = { code: 'kill_switch_active', message: msg, retryable: false };
      call.write({ error: { request_id, error } });
      call.end();
      db.appendAudit({
        event_type: 'ai.generate.denied',
        created_at_ms: nowMs(),
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        network_allowed: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        ext_json: JSON.stringify(withMemoryMetricsExt(
          { created_at_ms },
          {
            event_kind: 'ai.generate.denied',
            op: 'generate',
            job_type: 'ai_generate',
            channel: metricsChannel(isPaid),
            remote_mode: isPaid,
            scope: buildMetricsScope({
              scope_kind: 'project',
              device_id,
              user_id: client.user_id ? String(client.user_id) : '',
              app_id,
              project_id,
            }),
            security: {
              blocked: true,
              deny_code: error.code,
            },
          }
        )),
      });
      appendPolicyEvalAudit({
        created_at_ms: nowMs(),
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        decision: 'deny',
        policy_scope: 'ai_generate',
        rule_ids: ['kill_switch_active'],
        phase: 'execute',
        user_ack_understood: false,
        explain_rounds: 0,
        options_presented: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      return;
    }
    if (isPaid && trustedPaidAccess?.trust_profile_present && !trustedPaidAccess.allow) {
      denyPaidModelWithContext({
        code: trustedPaidAccess.deny_code || 'device_paid_model_not_allowed',
        message: `${deviceDisplayName}: paid model policy denied ${model_id}`,
        ruleIds: [String(trustedPaidAccess.deny_code || 'device_paid_model_not_allowed')],
        phase: 'execute',
        optionsPresented: false,
        extraExt: trustedPaidAccess,
      });
      return;
    }
    const grantRow = isPaid && !trustedPaidAccess?.trust_profile_present
      ? db.findActiveGrant({
          device_id,
          user_id: client.user_id ? String(client.user_id) : '',
          app_id,
          capability: 'ai.generate.paid',
          model_id,
        })
      : null;
    if (isPaid && !grantRow && !trustedPaidAccess?.trust_profile_present) {
      denyPaidModelWithContext({
        code: 'legacy_grant_flow_required',
        message: `${deviceDisplayName}: legacy grant required for ${model_id}`,
        ruleIds: ['legacy_grant_flow_required'],
        phase: 'explain',
        optionsPresented: true,
        extraExt: trustedPaidAccess || {},
      });
      return;
    }

    // Quota gate (MVP): per-device daily token cap. See `hub_quotas.json` in runtime base dir.
    let quotaCap = 0;
    try {
      const quotaCfg = loadQuotaConfig(runtimeBaseDir);
      const cap = resolveDeviceDailyTokenCap(quotaCfg, device_id);
      const shouldApplyLegacyQuotaGate = !(isPaid && trustedPaidAccess?.trust_profile_present);
      quotaCap = shouldApplyLegacyQuotaGate ? cap : nonNegativeInt(runtimeClientConfig?.daily_token_limit, 0);
      if (shouldApplyLegacyQuotaGate && cap > 0) {
        const used = db.getQuotaUsageDaily(quota_scope, quota_day);
        if (used >= cap) {
          const error = { code: 'quota_exceeded', message: `Daily quota exceeded (${used}/${cap})`, retryable: false };
          call.write({ error: { request_id, error } });
          call.end();
          db.appendAudit({
            event_type: 'ai.generate.denied',
            created_at_ms: nowMs(),
            severity: 'security',
            device_id,
            user_id: client.user_id ? String(client.user_id) : null,
            app_id,
            project_id: project_id || null,
            session_id: client.session_id ? String(client.session_id) : null,
            request_id,
            capability,
            model_id: model_id || null,
            network_allowed: isPaid,
            ok: false,
            error_code: error.code,
            error_message: error.message,
            ext_json: JSON.stringify(withMemoryMetricsExt(
              { created_at_ms, quota_day, quota_scope, quota_used: used, quota_cap: cap },
              {
                event_kind: 'ai.generate.denied',
                op: 'generate',
                job_type: 'ai_generate',
                channel: metricsChannel(isPaid),
                remote_mode: isPaid,
                scope: buildMetricsScope({
                  scope_kind: 'project',
                  device_id,
                  user_id: client.user_id ? String(client.user_id) : '',
                  app_id,
                  project_id,
                }),
                security: {
                  blocked: true,
                  deny_code: error.code,
                },
              }
            )),
          });
          appendPolicyEvalAudit({
            created_at_ms: nowMs(),
            device_id,
            user_id: client.user_id ? String(client.user_id) : null,
            app_id,
            project_id: project_id || null,
            session_id: client.session_id ? String(client.session_id) : null,
            request_id,
            capability,
            model_id: model_id || null,
            decision: 'deny',
            policy_scope: 'ai_generate',
            rule_ids: ['quota_exceeded'],
            phase: 'explain',
            user_ack_understood: false,
            explain_rounds: 0,
            options_presented: true,
            ok: false,
            error_code: error.code,
            error_message: error.message,
            ext: { quota_day, quota_scope, quota_used: used, quota_cap: cap },
          });
          bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
          return;
        }
      }
    } catch {
      // ignore quota read/eval errors; fail open in MVP
    }
    if (isPaid && grantRow) {
      const ackFields = policyAckForGrantRequest(grantRow.grant_request_id || '');
      appendPolicyEvalAudit({
        created_at_ms: nowMs(),
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        decision: 'allow',
        policy_scope: 'ai_generate',
        rule_ids: ['grant_active'],
        ttl_sec: Number(grantRow.expires_at_ms || 0) > 0 ? Math.max(0, Math.floor((Number(grantRow.expires_at_ms || 0) - nowMs()) / 1000)) : 0,
        phase: 'execute',
        grant_request_id: grantRow.grant_request_id || '',
        grant_id: grantRow.grant_id || '',
        user_ack_understood: ackFields.user_ack_understood,
        explain_rounds: ackFields.explain_rounds,
        options_presented: ackFields.options_presented,
        ok: true,
      });
    }
    if (isPaid && grantRow?.expires_at_ms) {
      // Best-effort: keep Bridge enabled while a paid-model grant is active.
      try {
        ensureBridgeEnabledUntil(bridgeBaseDir, Number(grantRow.expires_at_ms || 0) / 1000.0);
      } catch {
        // ignore
      }
    }

    const cancelState = { canceled: false, runtime_base_dir: runtimeBaseDir, use_runtime_cancel: !isPaid };
    cancels.set(request_id, cancelState);

    const cancelRuntime = (reason) => {
      if (cancelState.canceled) return;
      cancelState.canceled = true;
      cancelPaidAIQueueWait(request_id, reason || 'canceled');
      if (cancelState.use_runtime_cancel) {
        try {
          writeCancelRequest(runtimeBaseDir, { request_id, reason: reason || 'canceled' });
        } catch {
          // ignore
        }
      }
    };
    call.on('cancelled', () => cancelRuntime('grpc_cancelled'));
    call.on('close', () => cancelRuntime('grpc_closed'));
    call.on('error', () => cancelRuntime('grpc_error'));

    const hub_started_at_ms = nowMs();
    let started_at_ms = hub_started_at_ms;
    let startedSent = false;

    const thread_id = String(req.thread_id || '').trim();
    const working_set_limit = Math.max(
      1,
      Math.min(200, Number(req.working_set_limit || process.env.HUB_MEMORY_WORKING_SET_LIMIT || 20))
    );

    let promptText = renderPromptFromMessages(req.messages);
    const max_tokens = Number(req.max_tokens || 512);
    const temperature = Number(req.temperature ?? 0.2);
    const top_p = Number(req.top_p ?? 0.95);
    const auto_load = String(process.env.HUB_AI_AUTO_LOAD || '1').trim() !== '0';

    let completionCharCount = 0;
    let assistantText = '';
    let sawDone = false;
    let memoryRouteSnapshot = null;
    let memoryRouteDurationMs = null;
    const memoryScoreExplainControl = resolveMemoryScoreExplainControl(call);

    const runtimeAlive = isRuntimeAlive(runtimeBaseDir, 15_000);
    const timeoutAliveMs = Math.max(1000, Number(process.env.HUB_MLX_RESPONSE_TIMEOUT_MS || 180_000));
    const timeoutNoRuntimeMs = Math.max(1000, Number(process.env.HUB_MLX_RESPONSE_TIMEOUT_NO_RUNTIME_MS || 8_000));
    const timeoutMs = runtimeAlive ? timeoutAliveMs : timeoutNoRuntimeMs;

    // If a response file already exists for this request_id (retries), start tailing from EOF
    // to avoid replaying stale events.
    let tailStartOffset = 0;
    try {
      const rp = responsePathForRequest(runtimeBaseDir, request_id);
      if (fs.existsSync(rp)) {
        tailStartOffset = Number(fs.statSync(rp).size || 0);
      }
    } catch {
      tailStartOffset = 0;
    }

    if (thread_id) {
      const thread = db.getThread(thread_id);
      if (!thread) {
        const error = { code: 'thread_not_found', message: 'thread_not_found', retryable: false };
        call.write({ error: { request_id, error } });
        call.end();
        db.appendAudit({
          event_type: 'ai.generate.denied',
          created_at_ms: nowMs(),
          severity: 'security',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          network_allowed: isPaid,
          ok: false,
          error_code: error.code,
          error_message: error.message,
          ext_json: JSON.stringify(withMemoryMetricsExt(
            { thread_id },
            {
              event_kind: 'ai.generate.denied',
              op: 'generate',
              job_type: 'ai_generate',
              channel: metricsChannel(isPaid),
              remote_mode: isPaid,
              scope: buildMetricsScope({
                scope_kind: 'thread',
                device_id,
                user_id: client.user_id ? String(client.user_id) : '',
                app_id,
                project_id,
                thread_id,
              }),
              security: {
                blocked: true,
                deny_code: error.code,
              },
            }
          )),
        });
        bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
        cancels.delete(request_id);
        return;
      }
      if (String(thread.device_id || '') !== device_id || String(thread.app_id || '') !== app_id || String(thread.project_id || '') !== project_id) {
        const error = { code: 'permission_denied', message: 'permission_denied', retryable: false };
        call.write({ error: { request_id, error } });
        call.end();
        db.appendAudit({
          event_type: 'ai.generate.denied',
          created_at_ms: nowMs(),
          severity: 'security',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          network_allowed: isPaid,
          ok: false,
          error_code: error.code,
          error_message: error.message,
          ext_json: JSON.stringify(withMemoryMetricsExt(
            { thread_id },
            {
              event_kind: 'ai.generate.denied',
              op: 'generate',
              job_type: 'ai_generate',
              channel: metricsChannel(isPaid),
              remote_mode: isPaid,
              scope: buildMetricsScope({
                scope_kind: 'thread',
                device_id,
                user_id: client.user_id ? String(client.user_id) : '',
                app_id,
                project_id,
                thread_id,
              }),
              security: {
                blocked: true,
                deny_code: error.code,
              },
            }
          )),
        });
        bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
        cancels.delete(request_id);
        return;
      }

      // Append new turns to the thread (thin client mode). Drop/redact <private> by default.
      try {
        const baseTs = created_at_ms || nowMs();
        const turns = [];
        const msgs = Array.isArray(req.messages) ? req.messages : [];
        for (let i = 0; i < msgs.length; i += 1) {
          const m = msgs[i] || {};
          const role = String(m.role || '').trim();
          if (!role || role === 'system') continue;
          const raw = String(m.content ?? '');
          if (!raw) continue;
          const red = redactPrivateContent(raw);
          const cleaned = String(red.text || '').trim();
          if (!cleaned) continue;
          turns.push({ role, content: cleaned, is_private: red.had_private ? 1 : 0, created_at_ms: baseTs + i });
        }
        if (turns.length) {
          db.appendTurns({ thread_id, request_id, turns });
        }
      } catch {
        // Best-effort; do not fail generation on memory append errors.
      }

      // Assemble memory prompt through fixed retrieval pipeline with trust-layer routing.
      const memoryRouteStartedAtMs = nowMs();
      try {
        const userId = client.user_id ? String(client.user_id) : '';
        const canonThread = db.listCanonicalItems({
          scope: 'thread',
          thread_id,
          device_id,
          user_id: userId,
          app_id,
          project_id,
          limit: 50,
        });
        const canonProject = db.listCanonicalItems({
          scope: 'project',
          thread_id: '',
          device_id,
          user_id: userId,
          app_id,
          project_id,
          limit: 50,
        });
        const working = db.listTurns({ thread_id, limit: working_set_limit }).reverse();
        const retrievalDocs = buildMemoryRetrievalDocs({
          canonicalProject: canonProject,
          canonicalThread: canonThread,
          workingRows: working,
          scopeRef: { device_id, user_id: userId, app_id, project_id, thread_id },
        });

        const routeResult = routeMemoryByTrustShards({
          documents: retrievalDocs,
          remote_mode: isPaid,
          allow_untrusted: false,
        });
        const retrievalTraceEnabled =
          memoryScoreExplainControl.include_trace
          || String(process.env.HUB_MEMORY_RETRIEVAL_TRACE || '').trim() === '1';
        const retrievalQuery = latestQueryFromMessages(req.messages, promptText);
        const retrieval = runMemoryRetrievalPipeline({
          documents: routeResult.documents,
          query: retrievalQuery,
          scope: { device_id, user_id: userId, app_id, project_id },
          allowed_sensitivity: routeResult.policy.allowed_sensitivity,
          allow_untrusted: routeResult.policy.allow_untrusted,
          top_k: Math.max(1, Math.min(200, working_set_limit + 50)),
          remote_mode: isPaid,
          risk_penalty_enabled: true,
          trace_enabled: retrievalTraceEnabled,
        });
        const hitStats = buildTrustShardHitStats({
          routeResult,
          retrievalResults: retrieval.results,
        });
        const scoreExplain = memoryScoreExplainControl.enabled
          ? buildMemoryScoreExplainPayload({
              retrieval,
              limit: memoryScoreExplainControl.limit,
              include_trace: memoryScoreExplainControl.include_trace,
            })
          : null;

        memoryRouteSnapshot = {
          schema_version: 'xhub.memory.route.v1',
          remote_mode: isPaid,
          policy: routeResult.policy,
          route_stats: routeResult.stats,
          retrieval: {
            blocked: !!retrieval.blocked,
            deny_reason: String(retrieval.deny_reason || ''),
            results_count: Array.isArray(retrieval.results) ? retrieval.results.length : 0,
          },
          shard_hits: hitStats,
          debug: {
            score_explain_enabled: memoryScoreExplainControl.enabled,
            score_explain_limit: memoryScoreExplainControl.enabled ? memoryScoreExplainControl.limit : 0,
            score_explain_trace: memoryScoreExplainControl.enabled ? memoryScoreExplainControl.include_trace : false,
          },
        };
        if (scoreExplain) memoryRouteSnapshot.score_explain = scoreExplain;

        if (!retrieval.blocked && Array.isArray(retrieval.results) && retrieval.results.length > 0) {
          const docById = new Map(retrievalDocs.map((d) => [String(d.id || ''), d]));
          const selectedDocs = retrieval.results
            .map((row) => docById.get(String(row?.id || '')))
            .filter(Boolean);
          const hasRemoteSecret = isPaid && selectedDocs.some((d) => String(d?.sensitivity || '') === 'secret');
          if (!hasRemoteSecret) {
            const canonicalItems = [];
            const canonicalSeen = new Set();
            const workingRows = [];
            for (const doc of selectedDocs) {
              if (String(doc?.source_type || '') === 'canonical') {
                const key = String(doc?.source_payload?.key || '').trim();
                const value = String(doc?.source_payload?.value || '').trim();
                if (!key || !value) continue;
                const dedupeKey = `${key}\n${value}`;
                if (canonicalSeen.has(dedupeKey)) continue;
                canonicalSeen.add(dedupeKey);
                canonicalItems.push({ key, value });
                continue;
              }
              if (String(doc?.source_type || '') === 'turn') {
                const role = String(doc?.source_payload?.role || '').trim();
                const content = String(doc?.source_payload?.content || '').trim();
                if (!role || !content) continue;
                workingRows.push({
                  role,
                  content,
                  created_at_ms: Number(doc?.source_payload?.created_at_ms || 0),
                });
              }
            }
            workingRows.sort((a, b) => Number(a.created_at_ms || 0) - Number(b.created_at_ms || 0));
            const memPrompt = renderPromptFromHubMemory({
              canonicalItems,
              workingSetRows: workingRows,
            });
            if (memPrompt) promptText = memPrompt;
          } else {
            memoryRouteSnapshot.retrieval.blocked = true;
            memoryRouteSnapshot.retrieval.deny_reason = 'remote_secret_denied_defense_in_depth';
            memoryRouteSnapshot.retrieval.results_count = 0;
          }
        }
      } catch {
        // ignore; fall back to client-provided promptText
      } finally {
        memoryRouteDurationMs = Math.max(0, nowMs() - memoryRouteStartedAtMs);
      }
    }

    if (thread_id && memoryRouteSnapshot) {
      try {
        const routeAuditAtMs = nowMs();
        const blocked = !!memoryRouteSnapshot?.retrieval?.blocked;
        const denyReason = String(memoryRouteSnapshot?.retrieval?.deny_reason || '');
        const routeStats = memoryRouteSnapshot?.route_stats || {};
        const droppedSecretRemote = Number(routeStats?.dropped_secret_remote || 0);
        const memoryRouteExt = withMemoryMetricsExt(memoryRouteSnapshot, {
          event_kind: 'memory.route.applied',
          op: 'memory_route',
          job_type: 'memory_route',
          channel: metricsChannel(isPaid),
          remote_mode: isPaid,
          scope: buildMetricsScope({
            scope_kind: 'thread',
            device_id,
            user_id: client.user_id ? String(client.user_id) : '',
            app_id,
            project_id,
            thread_id,
          }),
          latency: {
            duration_ms: memoryRouteDurationMs,
          },
          quality: {
            result_count: Number(memoryRouteSnapshot?.retrieval?.results_count || 0),
            score_explain_enabled: !!memoryRouteSnapshot?.debug?.score_explain_enabled,
          },
          security: {
            blocked,
            downgraded: blocked || droppedSecretRemote > 0,
            deny_code: denyReason,
          },
        });
        db.appendAudit({
          event_type: 'memory.route.applied',
          created_at_ms: routeAuditAtMs,
          severity: blocked || droppedSecretRemote > 0 ? 'warn' : 'info',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          network_allowed: isPaid,
          ok: !blocked,
          error_code: blocked ? 'memory_route_blocked' : null,
          error_message: blocked ? (denyReason || 'memory_route_blocked') : null,
          ext_json: JSON.stringify(memoryRouteExt),
        });
      } catch {
        // ignore
      }
    }

    let executionRemoteMode = isPaid;
    let executionModelId = model_id;
    let remoteExportGate = null;
    if (isPaid) {
      remoteExportGate = evaluatePromptRemoteExportGate({
        export_class: 'prompt_bundle',
        prompt_text: promptText,
      });
      if (remoteExportGate?.prompt_text && String(remoteExportGate.prompt_text) !== promptText) {
        promptText = String(remoteExportGate.prompt_text || promptText);
      }

      const gateDenyCode = String(remoteExportGate?.deny_code || remoteExportGate?.gate_reason || 'remote_export_blocked');
      const policyGateAction = String(remoteExportGate?.action || '');
      const effectiveGateAction =
        remoteExportGate?.blocked && policyGateAction === 'downgrade_to_local' && failClosedOnDowngrade
          ? 'error'
          : policyGateAction;
      const effectiveDowngraded = remoteExportGate?.blocked
        ? effectiveGateAction === 'downgrade_to_local'
        : !!remoteExportGate?.downgraded;
      const gateExtBase = {
        created_at_ms,
        export_class: String(remoteExportGate?.export_class || 'prompt_bundle'),
        job_sensitivity: String(remoteExportGate?.job_sensitivity || ''),
        gate_reason: String(remoteExportGate?.gate_reason || ''),
        blocked: !!remoteExportGate?.blocked,
        downgraded: effectiveDowngraded,
        policy_gate_action: policyGateAction,
        gate_action: effectiveGateAction,
        requested_fail_closed_on_downgrade: failClosedOnDowngrade,
        findings_summary: remoteExportGate?.findings_summary || {},
        gate_order: Array.isArray(remoteExportGate?.gate_order) ? remoteExportGate.gate_order : [],
        requested_model_id: model_id,
      };

      if (remoteExportGate?.blocked && effectiveGateAction === 'error') {
        const error = {
          code: gateDenyCode || 'remote_export_blocked',
          message: `remote_export_blocked:${gateDenyCode || 'unknown'}`,
          retryable: false,
        };
        call.write({ error: { request_id, error } });
        call.end();
        db.appendAudit({
          event_type: 'ai.generate.denied',
          created_at_ms: nowMs(),
          severity: 'security',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          network_allowed: true,
          ok: false,
          error_code: error.code,
          error_message: error.message,
          ext_json: JSON.stringify(withMemoryMetricsExt(
            gateExtBase,
            {
              event_kind: 'ai.generate.denied',
              op: 'generate',
              job_type: 'ai_generate',
              channel: 'remote',
              remote_mode: true,
              scope: buildMetricsScope({
                scope_kind: thread_id ? 'thread' : 'project',
                device_id,
                user_id: client.user_id ? String(client.user_id) : '',
                app_id,
                project_id,
                thread_id,
              }),
              security: {
                blocked: true,
                deny_code: error.code,
              },
            }
          )),
        });
        appendPolicyEvalAudit({
          created_at_ms: nowMs(),
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          decision: 'deny',
          policy_scope: 'ai_generate',
          rule_ids: [`remote_export_gate:${error.code}`],
          phase: 'execute',
          user_ack_understood: false,
          explain_rounds: 0,
          options_presented: false,
          ok: false,
          error_code: error.code,
          error_message: error.message,
        });
        bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
        cancels.delete(request_id);
        return;
      }

      if (remoteExportGate?.blocked && effectiveGateAction === 'downgrade_to_local') {
        const fallbackModelId = resolveLocalFallbackModelId({ db, runtimeBaseDir });
        if (!fallbackModelId) {
          const error = {
            code: 'downgrade_local_model_unavailable',
            message: 'remote_export_blocked:downgrade_local_model_unavailable',
            retryable: false,
          };
          call.write({ error: { request_id, error } });
          call.end();
          db.appendAudit({
            event_type: 'ai.generate.denied',
            created_at_ms: nowMs(),
            severity: 'security',
            device_id,
            user_id: client.user_id ? String(client.user_id) : null,
            app_id,
            project_id: project_id || null,
            session_id: client.session_id ? String(client.session_id) : null,
            request_id,
            capability,
            model_id: model_id || null,
            network_allowed: true,
            ok: false,
            error_code: error.code,
            error_message: error.message,
            ext_json: JSON.stringify(withMemoryMetricsExt(
              { ...gateExtBase, gate_reason: error.code },
              {
                event_kind: 'ai.generate.denied',
                op: 'generate',
                job_type: 'ai_generate',
                channel: 'remote',
                remote_mode: true,
                scope: buildMetricsScope({
                  scope_kind: thread_id ? 'thread' : 'project',
                  device_id,
                  user_id: client.user_id ? String(client.user_id) : '',
                  app_id,
                  project_id,
                  thread_id,
                }),
                security: {
                  blocked: true,
                  deny_code: error.code,
                },
              }
            )),
          });
          bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
          cancels.delete(request_id);
          return;
        }

        executionRemoteMode = false;
        executionModelId = fallbackModelId;
        cancelState.use_runtime_cancel = true;
        const downgradeAuditAtMs = nowMs();
        db.appendAudit({
          event_type: 'ai.generate.downgraded_to_local',
          created_at_ms: downgradeAuditAtMs,
          severity: 'warn',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: executionModelId || null,
          network_allowed: false,
          ok: true,
          error_code: gateDenyCode || null,
          error_message: gateDenyCode ? `remote_export_blocked:${gateDenyCode}` : null,
          ext_json: JSON.stringify(withMemoryMetricsExt(
            {
              ...gateExtBase,
              downgraded_model_id: executionModelId,
            },
            {
              event_kind: 'ai.generate.downgraded_to_local',
              op: 'generate',
              job_type: 'ai_generate',
              channel: 'local',
              remote_mode: false,
              scope: buildMetricsScope({
                scope_kind: thread_id ? 'thread' : 'project',
                device_id,
                user_id: client.user_id ? String(client.user_id) : '',
                app_id,
                project_id,
                thread_id,
              }),
              security: {
                blocked: true,
                downgraded: true,
                deny_code: gateDenyCode,
              },
            }
          )),
        });
      }
    }

    if (isPaid && executionRemoteMode && trustedPaidAccess?.trust_profile_present) {
      let usageSummary = null;
      try {
        usageSummary = db.getTerminalUsageSummaryDaily({ device_id, day_bucket: quota_day });
      } catch {
        usageSummary = null;
      }
      const requestedTotalTokensEstimate = Math.max(0, estimateTokens(promptText)) + Math.max(0, Number(max_tokens || 0));
      trustedPaidAccess = resolvePaidModelRuntimeAccess({
        runtimeClient: runtimeClientConfig,
        capabilityAllowed,
        modelId: model_id,
        requestedTotalTokensEstimate,
        usedTokensToday: usageSummary?.total_tokens || 0,
      });
      quotaCap = nonNegativeInt(trustedPaidAccess.daily_token_limit, quotaCap);
      if (!trustedPaidAccess.allow) {
        denyPaidModelWithContext({
          code: trustedPaidAccess.deny_code,
          message: `${deviceDisplayName}: ${trustedPaidAccess.deny_code} for ${model_id}`,
          ruleIds: [String(trustedPaidAccess.deny_code || 'trusted_profile_denied')],
          phase: 'execute',
          optionsPresented: false,
          extraExt: {
            ...trustedPaidAccess,
            projected_tokens_today: Math.max(0, Number(trustedPaidAccess.used_tokens_today || 0))
              + Math.max(0, Number(trustedPaidAccess.requested_total_tokens_estimate || 0)),
          },
        });
        return;
      }
    }

    // Paid/remote models are served via Bridge (network-capable helper). The MLX runtime
    // is offline-only and will return model_not_loaded for remote ids.
    if (executionRemoteMode) {
      let releasePaidAISlot = null;
      let paidAIQueueWaitMs = 0;
      try {
        try {
          const slot = await acquirePaidAISlot({
            requestId: request_id,
            project_id,
            device_id,
            waitMs: paidAIQueueTimeoutMs,
            shouldAbort: () => cancelState.canceled,
            onQueued: () => {
              bus.emitHubEvent(bus.requestStatus({ request_id, status: 'queued', error: null, client }));
            },
          });
          releasePaidAISlot = slot.release;
          paidAIQueueWaitMs = Number(slot.queuedMs || 0);
        } catch (e) {
          const raw = String(e?.message || e || 'hub_ai_queue_failed');
          const lower = raw.toLowerCase();
          if (cancelState.canceled || lower.includes('canceled')) {
            const usage = {
              prompt_tokens: estimateTokens(promptText),
              completion_tokens: 0,
              total_tokens: estimateTokens(promptText),
              cost_usd_estimate: 0,
            };
            try {
              call.write({ done: { request_id, ok: false, reason: 'canceled', usage, finished_at_ms: nowMs() } });
            } catch {
              // ignore
            }
            try {
              call.end();
            } catch {
              // ignore
            }
            bus.emitHubEvent(bus.requestStatus({ request_id, status: 'canceled', error: null, client }));
            cancels.delete(request_id);
            return;
          }

          let code = 'hub_ai_queue_failed';
          if (lower.includes('queue_full')) code = 'hub_ai_queue_full';
          else if (lower.includes('queue_timeout')) code = 'hub_ai_queue_timeout';
          const error = { code, message: raw || code, retryable: true };
          try {
            call.write({ error: { request_id, error } });
          } catch {
            // ignore
          }
          try {
            call.end();
          } catch {
            // ignore
          }
          db.appendAudit({
            event_type: 'ai.generate.failed',
            created_at_ms: nowMs(),
            severity: 'warn',
            device_id,
            user_id: client.user_id ? String(client.user_id) : null,
            app_id,
            project_id: project_id || null,
            session_id: client.session_id ? String(client.session_id) : null,
            request_id,
            capability,
            model_id: model_id || null,
            network_allowed: true,
            ok: false,
            error_code: error.code,
            error_message: error.message,
            ext_json: JSON.stringify(withMemoryMetricsExt({
              created_at_ms,
              queue_wait_ms: paidAIQueueWaitMs,
              queue_depth: paidAIQueue.length,
              queue_limit: paidAIQueueLimit,
              queue_timeout_ms: paidAIQueueTimeoutMs,
            }, {
              event_kind: 'ai.generate.failed',
              op: 'generate',
              job_type: 'ai_generate',
              channel: 'remote',
              remote_mode: true,
              scope: buildMetricsScope({
                scope_kind: thread_id ? 'thread' : 'project',
                device_id,
                user_id: client.user_id ? String(client.user_id) : '',
                app_id,
                project_id,
                thread_id,
              }),
              latency: {
                queue_wait_ms: paidAIQueueWaitMs,
              },
              security: {
                blocked: false,
                deny_code: error.code,
              },
            })),
          });
          bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
          cancels.delete(request_id);
          return;
        }

        bus.emitHubEvent(bus.requestStatus({ request_id, status: 'running', error: null, client }));

      const st0 = readBridgeStatus(bridgeBaseDir);
      if (!st0.alive) {
        const error = { code: 'bridge_unavailable', message: 'Bridge is not running', retryable: true };
        try {
          call.write({ error: { request_id, error } });
        } catch {
          // ignore
        }
        try {
          call.end();
        } catch {
          // ignore
        }
        db.appendAudit({
          event_type: 'ai.generate.failed',
          created_at_ms: nowMs(),
          severity: 'warn',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          network_allowed: true,
          ok: false,
          error_code: error.code,
          error_message: error.message,
          ext_json: JSON.stringify(withMemoryMetricsExt(
            { created_at_ms, bridge_base_dir: bridgeBaseDir, queue_wait_ms: paidAIQueueWaitMs },
            {
              event_kind: 'ai.generate.failed',
              op: 'generate',
              job_type: 'ai_generate',
              channel: 'remote',
              remote_mode: true,
              scope: buildMetricsScope({
                scope_kind: thread_id ? 'thread' : 'project',
                device_id,
                user_id: client.user_id ? String(client.user_id) : '',
                app_id,
                project_id,
                thread_id,
              }),
              latency: {
                queue_wait_ms: paidAIQueueWaitMs,
              },
              security: {
                blocked: false,
                deny_code: error.code,
              },
            }
          )),
        });
        bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
        cancels.delete(request_id);
        return;
      }

      // If the bridge is alive but currently "off", wait briefly for it to enable (grants may have just extended it).
      const st = st0.enabled ? st0 : await waitForBridgeEnabled(bridgeBaseDir, 1500);
      if (!st.enabled) {
        const error = { code: 'bridge_disabled', message: 'Bridge is disabled', retryable: true };
        try {
          call.write({ error: { request_id, error } });
        } catch {
          // ignore
        }
        try {
          call.end();
        } catch {
          // ignore
        }
        db.appendAudit({
          event_type: 'ai.generate.denied',
          created_at_ms: nowMs(),
          severity: 'security',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          network_allowed: true,
          ok: false,
          error_code: error.code,
          error_message: error.message,
          ext_json: JSON.stringify(withMemoryMetricsExt(
            { created_at_ms, bridge_base_dir: bridgeBaseDir, queue_wait_ms: paidAIQueueWaitMs },
            {
              event_kind: 'ai.generate.denied',
              op: 'generate',
              job_type: 'ai_generate',
              channel: 'remote',
              remote_mode: true,
              scope: buildMetricsScope({
                scope_kind: thread_id ? 'thread' : 'project',
                device_id,
                user_id: client.user_id ? String(client.user_id) : '',
                app_id,
                project_id,
                thread_id,
              }),
              latency: {
                queue_wait_ms: paidAIQueueWaitMs,
              },
              security: {
                blocked: true,
                deny_code: error.code,
              },
            }
          )),
        });
        bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
        cancels.delete(request_id);
        return;
      }

      // Emit start early so clients can render "running" while Bridge works.
      started_at_ms = nowMs();
      startedSent = true;
      try {
        call.write({ start: { request_id, model_id: model_id || '', started_at_ms } });
      } catch {
        // ignore
      }

      const timeoutSec = Math.max(5, Number(process.env.HUB_BRIDGE_AI_TIMEOUT_SEC || 120));
      let ok = false;
      let status = 0;
      let text = '';
      let errText = '';
      let usageObj = null;

      try {
        enqueueBridgeAIGenerate(bridgeBaseDir, {
          request_id,
          app_id,
          project_id,
          queued_at_ms: nowMs(),
          model_id,
          prompt: promptText,
          max_tokens,
          temperature,
          top_p,
          timeout_sec: timeoutSec,
        });
        const resp = await waitBridgeAIGenerateResult(bridgeBaseDir, request_id, timeoutSec * 1000 + 5000);
        ok = !!resp?.ok;
        status = Number(resp?.status || 0);
        text = String(resp?.text || '');
        errText = String(resp?.error || '');
        usageObj = resp?.usage && typeof resp.usage === 'object' ? resp.usage : null;
      } catch (e) {
        errText = String(e?.message || e || 'bridge_ai_failed');
      }

      const finished_at_ms = nowMs();

      // If the request was canceled mid-flight, report canceled (best-effort) and stop.
      if (cancelState.canceled) {
        const usage = {
          prompt_tokens: estimateTokens(promptText),
          completion_tokens: 0,
          total_tokens: estimateTokens(promptText),
          cost_usd_estimate: 0,
        };
        try {
          call.write({ done: { request_id, ok: false, reason: 'canceled', usage, finished_at_ms } });
        } catch {
          // ignore
        }
        try {
          call.end();
        } catch {
          // ignore
        }
        db.appendAudit({
          event_type: 'ai.generate.canceled',
          created_at_ms: finished_at_ms,
          severity: 'warn',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability,
          model_id: model_id || null,
          network_allowed: true,
          ok: false,
          error_code: 'canceled',
          error_message: 'canceled',
          duration_ms: Math.max(0, finished_at_ms - started_at_ms),
          ext_json: JSON.stringify(withMemoryMetricsExt(
            { created_at_ms, bridge_base_dir: bridgeBaseDir, queue_wait_ms: paidAIQueueWaitMs },
            {
              event_kind: 'ai.generate.canceled',
              op: 'generate',
              job_type: 'ai_generate',
              channel: 'remote',
              remote_mode: true,
              scope: buildMetricsScope({
                scope_kind: thread_id ? 'thread' : 'project',
                device_id,
                user_id: client.user_id ? String(client.user_id) : '',
                app_id,
                project_id,
                thread_id,
              }),
              latency: {
                duration_ms: Math.max(0, finished_at_ms - started_at_ms),
                queue_wait_ms: paidAIQueueWaitMs,
              },
              cost: {
                prompt_tokens: usage.prompt_tokens,
                completion_tokens: usage.completion_tokens,
                total_tokens: usage.total_tokens,
                cost_usd_estimate: usage.cost_usd_estimate,
              },
              security: {
                blocked: false,
                deny_code: 'canceled',
              },
            }
          )),
        });
        bus.emitHubEvent(bus.requestStatus({ request_id, status: 'canceled', error: null, client }));
        cancels.delete(request_id);
        return;
      }

      if (ok && text) {
        let seq = 0;
        for (const chunk of chunkText(text, 800)) {
          seq += 1;
          completionCharCount += chunk.length;
          assistantText += chunk;
          try {
            call.write({ delta: { request_id, seq, text: chunk } });
          } catch {
            // ignore
          }
        }
      }

      const reason = ok ? 'eos' : String(errText || (status ? `http_${status}` : 'bridge_failed'));

      let prompt_tokens = Number(usageObj?.prompt_tokens || usageObj?.promptTokens || 0);
      let completion_tokens = Number(usageObj?.completion_tokens || usageObj?.completionTokens || 0);
      let total_tokens = Number(usageObj?.total_tokens || usageObj?.totalTokens || 0);
      if (!prompt_tokens) prompt_tokens = estimateTokens(promptText);
      if (!completion_tokens) completion_tokens = Math.max(0, Math.ceil(completionCharCount / 3.2));
      if (!total_tokens) total_tokens = prompt_tokens + completion_tokens;
      const usage = { prompt_tokens, completion_tokens, total_tokens, cost_usd_estimate: 0 };

      try {
        call.write({ done: { request_id, ok: !!ok, reason, usage, finished_at_ms } });
      } catch {
        // ignore
      }
      try {
        call.end();
      } catch {
        // ignore
      }

      if (thread_id && ok) {
        try {
          const txt = String(assistantText || '').trim();
          if (txt) {
            db.appendTurns({
              thread_id,
              request_id,
              turns: [{ role: 'assistant', content: txt, is_private: 0, created_at_ms: finished_at_ms }],
            });
          }
        } catch {
          // ignore
        }
      }

      if (grantRow && ok) {
        try {
          db.addGrantUsage(String(grantRow.grant_id || ''), total_tokens);
        } catch {
          // ignore
        }
      }

      if (ok) {
        try {
          db.addQuotaUsageDaily(quota_scope, quota_day, total_tokens);
          try {
            const usedNow = db.getQuotaUsageDaily(quota_scope, quota_day);
            bus.emitHubEvent(bus.quotaUpdated({ scope: quota_scope, daily_token_cap: quotaCap, daily_token_used: usedNow }));
          } catch {
            // ignore
          }
        } catch {
          // ignore
        }
      }
      if (ok && isPaid && executionRemoteMode) {
        try {
          db.recordTerminalModelUsageDaily({
            device_id,
            device_name: deviceDisplayName,
            model_id: executionModelId || model_id,
            day_bucket: quota_day,
            prompt_tokens,
            completion_tokens,
            total_tokens,
            last_used_at_ms: finished_at_ms,
          });
          writeGrpcDevicesStatus(runtimeBaseDir);
        } catch {
          // ignore
        }
      }

      db.appendAudit({
        event_type: ok ? 'ai.generate.completed' : 'ai.generate.failed',
        created_at_ms: finished_at_ms,
        severity: ok ? 'info' : 'warn',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: model_id || null,
        prompt_tokens,
        completion_tokens,
        total_tokens,
        network_allowed: true,
        ok: !!ok,
        error_code: ok ? null : 'bridge_failed',
        error_message: ok ? null : reason,
        duration_ms: Math.max(0, finished_at_ms - started_at_ms),
        ext_json: JSON.stringify(withMemoryMetricsExt(
          { created_at_ms, bridge_base_dir: bridgeBaseDir, status, queue_wait_ms: paidAIQueueWaitMs },
          {
            event_kind: ok ? 'ai.generate.completed' : 'ai.generate.failed',
            op: 'generate',
            job_type: 'ai_generate',
            channel: 'remote',
            remote_mode: true,
            scope: buildMetricsScope({
              scope_kind: thread_id ? 'thread' : 'project',
              device_id,
              user_id: client.user_id ? String(client.user_id) : '',
              app_id,
              project_id,
              thread_id,
            }),
            latency: {
              duration_ms: Math.max(0, finished_at_ms - started_at_ms),
              queue_wait_ms: paidAIQueueWaitMs,
            },
            cost: {
              prompt_tokens,
              completion_tokens,
              total_tokens,
              cost_usd_estimate: usage.cost_usd_estimate,
            },
            security: {
              blocked: false,
              deny_code: ok ? '' : 'bridge_failed',
            },
          }
        )),
      });

      bus.emitHubEvent(bus.requestStatus({ request_id, status: ok ? 'done' : 'failed', error: null, client }));
      cancels.delete(request_id);
      return;
      } finally {
        if (typeof releasePaidAISlot === 'function') {
          try {
            releasePaidAISlot();
          } catch {
            // ignore
          }
        }
      }
    }

    bus.emitHubEvent(bus.requestStatus({ request_id, status: 'running', error: null, client }));

    const startedWriteAtMs = nowMs();
    try {
      writeGenerateRequest(runtimeBaseDir, {
        request_id,
        created_at_ms,
        app_id,
        model_id: executionModelId,
        task_type: '',
        preferred_model_id: '',
        prompt: promptText,
        max_tokens,
        temperature,
        top_p,
        auto_load: auto_load && !executionRemoteMode,
      });
    } catch (e) {
      const error = { code: 'runtime_write_failed', message: String(e?.message || e || 'runtime_write_failed'), retryable: true };
      try {
        call.write({ error: { request_id, error } });
      } catch {
        // ignore
      }
      try {
        call.end();
      } catch {
        // ignore
      }
      db.appendAudit({
        event_type: 'ai.generate.failed',
        created_at_ms: nowMs(),
        severity: 'error',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: executionModelId || null,
        network_allowed: executionRemoteMode,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        duration_ms: Math.max(0, nowMs() - startedWriteAtMs),
        ext_json: JSON.stringify(withMemoryMetricsExt(
          { created_at_ms, runtime_base_dir: runtimeBaseDir },
          {
            event_kind: 'ai.generate.failed',
            op: 'generate',
            job_type: 'ai_generate',
            channel: metricsChannel(executionRemoteMode),
            remote_mode: executionRemoteMode,
            scope: buildMetricsScope({
              scope_kind: thread_id ? 'thread' : 'project',
              device_id,
              user_id: client.user_id ? String(client.user_id) : '',
              app_id,
              project_id,
              thread_id,
            }),
            latency: {
              duration_ms: Math.max(0, nowMs() - startedWriteAtMs),
            },
            security: {
              blocked: false,
              deny_code: error.code,
            },
          }
        )),
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      cancels.delete(request_id);
      return;
    }

    const writeStartIfNeeded = (modelIdForStart) => {
      if (startedSent) return;
      startedSent = true;
      try {
        call.write({ start: { request_id, model_id: String(modelIdForStart || executionModelId || ''), started_at_ms } });
      } catch {
        // ignore
      }
    };

    const finish = ({ ok, reason, usage, finished_at_ms }) => {
      sawDone = true;
      try {
        call.write({
          done: {
            request_id,
            ok: !!ok,
            reason: String(reason || (ok ? 'eos' : 'failed')),
            usage: usage || { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0, cost_usd_estimate: 0 },
            finished_at_ms: Number(finished_at_ms || nowMs()),
          },
        });
      } catch {
        // ignore
      }
      try {
        call.end();
      } catch {
        // ignore
      }
    };

    let runtime_error = null;
    try {
      for await (const ev of tailResponseJsonl(runtimeBaseDir, request_id, {
        poll_ms: 20,
        timeout_ms: timeoutMs,
        start_offset: tailStartOffset,
        should_stop: () => cancelState.canceled,
      })) {
        const typ = String(ev?.type || '').trim().toLowerCase();
        if (typ === 'start') {
          const sec = Number(ev?.started_at || 0);
          if (sec > 0) started_at_ms = Math.floor(sec * 1000);
          writeStartIfNeeded(String(ev?.model_id || executionModelId));
          continue;
        }
        if (typ === 'delta') {
          writeStartIfNeeded(executionModelId);
          const text = String(ev?.text || '');
          completionCharCount += text.length;
          assistantText += text;
          call.write({ delta: { request_id, seq: Number(ev?.seq || 0), text } });
          continue;
        }
        if (typ === 'done') {
          writeStartIfNeeded(executionModelId);
          const ok = !!ev?.ok;
          const reason = String(ev?.reason || (ok ? 'eos' : 'failed'));
          const elapsed_ms = Number(ev?.elapsed_ms || 0);
          const finished_at_ms = elapsed_ms > 0 ? started_at_ms + elapsed_ms : nowMs();

          let prompt_tokens = Number(ev?.promptTokens || ev?.prompt_tokens || 0);
          let completion_tokens = Number(ev?.generationTokens || ev?.completion_tokens || 0);
          if (!prompt_tokens) prompt_tokens = estimateTokens(promptText);
          if (!completion_tokens) completion_tokens = Math.max(0, Math.ceil(completionCharCount / 3.2));
          const total_tokens = prompt_tokens + completion_tokens;
          const usage = { prompt_tokens, completion_tokens, total_tokens, cost_usd_estimate: 0 };

          finish({ ok, reason, usage, finished_at_ms });

          if (thread_id && ok) {
            try {
              const txt = String(assistantText || '').trim();
              if (txt) {
                db.appendTurns({
                  thread_id,
                  request_id,
                  turns: [{ role: 'assistant', content: txt, is_private: 0, created_at_ms: finished_at_ms }],
                });
              }
            } catch {
              // ignore
            }
          }

          if (grantRow && ok && executionRemoteMode) {
            try {
              db.addGrantUsage(String(grantRow.grant_id || ''), total_tokens);
            } catch {
              // ignore
            }
          }

          if (ok) {
            try {
              db.addQuotaUsageDaily(quota_scope, quota_day, total_tokens);
              try {
                const usedNow = db.getQuotaUsageDaily(quota_scope, quota_day);
                bus.emitHubEvent(bus.quotaUpdated({ scope: quota_scope, daily_token_cap: quotaCap, daily_token_used: usedNow }));
              } catch {
                // ignore
              }
            } catch {
              // ignore
            }
          }
          if (ok && isPaid && executionRemoteMode) {
            try {
              db.recordTerminalModelUsageDaily({
                device_id,
                device_name: deviceDisplayName,
                model_id: executionModelId || model_id,
                day_bucket: quota_day,
                prompt_tokens,
                completion_tokens,
                total_tokens,
                last_used_at_ms: finished_at_ms,
              });
              writeGrpcDevicesStatus(runtimeBaseDir);
            } catch {
              // ignore
            }
          }

          const evType =
            ok ? 'ai.generate.completed' : reason.toLowerCase().includes('canceled') ? 'ai.generate.canceled' : 'ai.generate.failed';
          db.appendAudit({
            event_type: evType,
            created_at_ms: finished_at_ms,
            severity: ok ? 'info' : 'warn',
            device_id,
            user_id: client.user_id ? String(client.user_id) : null,
            app_id,
            project_id: project_id || null,
            session_id: client.session_id ? String(client.session_id) : null,
            request_id,
            capability,
            model_id: executionModelId || null,
            prompt_tokens,
            completion_tokens,
            total_tokens,
            network_allowed: executionRemoteMode,
            ok,
            error_code: ok ? null : 'runtime_failed',
            error_message: ok ? null : reason,
            duration_ms: Math.max(0, finished_at_ms - started_at_ms),
            ext_json: JSON.stringify(withMemoryMetricsExt(
              { created_at_ms, runtime_base_dir: runtimeBaseDir, runtime_alive: runtimeAlive, thread_id: thread_id || '' },
              {
                event_kind: evType,
                op: 'generate',
                job_type: 'ai_generate',
                channel: metricsChannel(executionRemoteMode),
                remote_mode: executionRemoteMode,
                scope: buildMetricsScope({
                  scope_kind: thread_id ? 'thread' : 'project',
                  device_id,
                  user_id: client.user_id ? String(client.user_id) : '',
                  app_id,
                  project_id,
                  thread_id,
                }),
                latency: {
                  duration_ms: Math.max(0, finished_at_ms - started_at_ms),
                },
                cost: {
                  prompt_tokens,
                  completion_tokens,
                  total_tokens,
                  cost_usd_estimate: usage.cost_usd_estimate,
                },
                security: {
                  blocked: false,
                  deny_code: ok ? '' : 'runtime_failed',
                },
              }
            )),
          });

          bus.emitHubEvent(bus.requestStatus({ request_id, status: ok ? 'done' : reason === 'canceled' ? 'canceled' : 'failed', error: null, client }));
          break;
        }
      }
    } catch (e) {
      runtime_error = e;
    }

    // If the runtime loop ended without emitting `done`, treat as canceled/failed.
    if (!sawDone) {
      const finished_at_ms = nowMs();
      const ok = false;
      const reason = cancelState.canceled ? 'canceled' : String(runtime_error?.message || 'runtime_failed');
      const error = { code: cancelState.canceled ? 'canceled' : 'runtime_failed', message: reason, retryable: !cancelState.canceled };
      writeStartIfNeeded(executionModelId);
      finish({
        ok,
        reason,
        usage: { prompt_tokens: estimateTokens(promptText), completion_tokens: 0, total_tokens: estimateTokens(promptText), cost_usd_estimate: 0 },
        finished_at_ms,
      });

      db.appendAudit({
        event_type: cancelState.canceled ? 'ai.generate.canceled' : 'ai.generate.failed',
        created_at_ms: finished_at_ms,
        severity: cancelState.canceled ? 'warn' : 'error',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability,
        model_id: executionModelId || null,
        network_allowed: executionRemoteMode,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        duration_ms: Math.max(0, finished_at_ms - hub_started_at_ms),
        ext_json: JSON.stringify(withMemoryMetricsExt(
          { created_at_ms, runtime_base_dir: runtimeBaseDir, runtime_alive: runtimeAlive, thread_id: thread_id || '' },
          {
            event_kind: cancelState.canceled ? 'ai.generate.canceled' : 'ai.generate.failed',
            op: 'generate',
            job_type: 'ai_generate',
            channel: metricsChannel(executionRemoteMode),
            remote_mode: executionRemoteMode,
            scope: buildMetricsScope({
              scope_kind: thread_id ? 'thread' : 'project',
              device_id,
              user_id: client.user_id ? String(client.user_id) : '',
              app_id,
              project_id,
              thread_id,
            }),
            latency: {
              duration_ms: Math.max(0, finished_at_ms - hub_started_at_ms),
            },
            cost: {
              prompt_tokens: estimateTokens(promptText),
              completion_tokens: 0,
              total_tokens: estimateTokens(promptText),
              cost_usd_estimate: 0,
            },
            security: {
              blocked: false,
              deny_code: error.code,
            },
          }
        )),
      });

      bus.emitHubEvent(bus.requestStatus({ request_id, status: cancelState.canceled ? 'canceled' : 'failed', error: cancelState.canceled ? null : error, client }));
    }

    cancels.delete(request_id);
  }

  function Cancel(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    const req = call.request || {};
    const request_id = String(req.request_id || '').trim();
    if (!request_id) {
      callback(new Error('missing request_id'));
      return;
    }
    const st = cancels.get(request_id);
    if (st) {
      st.canceled = true;
      if (st.use_runtime_cancel) {
        try {
          writeCancelRequest(st.runtime_base_dir || resolveRuntimeBaseDir(), { request_id, reason: req.reason || '' });
        } catch {
          // ignore
        }
      }
      callback(null, { request_id, ok: true });
      return;
    }

    // Best-effort cancel for unknown in-flight state.
    try {
      writeCancelRequest(resolveRuntimeBaseDir(), { request_id, reason: req.reason || '' });
      callback(null, { request_id, ok: true });
      return;
    } catch {
      callback(null, { request_id, ok: false });
      return;
    }
  }

  // -------------------- HubWeb --------------------
  async function Fetch(call) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      call.end();
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const request_id = String(req.request_id || uuid());
    const device_id = String(client.device_id || '').trim() || 'unknown';
    const app_id = String(client.app_id || '').trim() || 'unknown';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;

    if (!clientAllows(auth, 'web.fetch')) {
      const denyCode = capabilityDenyCode(auth);
      const finished_at_ms = nowMs();
      const error = { code: denyCode, message: denyCode, retryable: false };
      try {
        call.write({
          done: {
            request_id,
            ok: false,
            status: 0,
            final_url: '',
            content_type: '',
            truncated: false,
            bytes: 0,
            text: '',
            finished_at_ms,
            error,
          },
        });
      } catch {
        // ignore
      }
      try {
        call.end();
      } catch {
        // ignore
      }
      db.appendAudit({
        event_type: 'web.fetch.denied',
        created_at_ms: finished_at_ms,
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        network_allowed: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        ext_json: JSON.stringify({ peer_ip: auth?.peer_ip || '' }),
      });
      appendPolicyEvalAudit({
        created_at_ms: finished_at_ms,
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        decision: 'deny',
        policy_scope: 'web_fetch',
        rule_ids: [denyCode],
        phase: 'execute',
        user_ack_understood: false,
        explain_rounds: 0,
        options_presented: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      const finished_at_ms = nowMs();
      const error = { code: denyCode, message: denyCode, retryable: false };
      try {
        call.write({
          done: {
            request_id,
            ok: false,
            status: 0,
            final_url: '',
            content_type: '',
            truncated: false,
            bytes: 0,
            text: '',
            finished_at_ms,
            error,
          },
        });
      } catch {
        // ignore
      }
      try {
        call.end();
      } catch {
        // ignore
      }
      db.appendAudit({
        event_type: 'web.fetch.denied',
        created_at_ms: finished_at_ms,
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        network_allowed: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        ext_json: JSON.stringify({
          project_binding_checked: true,
          workspace_binding_checked: !!trustedAutomationScope.workspace_root,
        }),
      });
      appendPolicyEvalAudit({
        created_at_ms: finished_at_ms,
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        decision: 'deny',
        policy_scope: 'web_fetch',
        rule_ids: [denyCode],
        phase: 'scope_bind',
        user_ack_understood: false,
        explain_rounds: 0,
        options_presented: false,
        ok: false,
        error_code: error.code,
        error_message: error.message,
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      return;
    }

    // Kill-switch gate (network).
    try {
      const ks = db.getEffectiveKillSwitch({
        device_id,
        user_id: client.user_id ? String(client.user_id) : '',
        project_id: project_id || '',
      });
      if (ks?.network_disabled) {
        const finished_at_ms = nowMs();
        const msg = ks.reason ? `kill_switch_active: ${ks.reason}` : 'kill_switch_active';
        const error = { code: 'kill_switch_active', message: msg, retryable: false };
        call.write({
          done: {
            request_id,
            ok: false,
            status: 0,
            final_url: '',
            content_type: '',
            truncated: false,
            bytes: 0,
            text: '',
            finished_at_ms,
            error,
          },
        });
        call.end();
        db.appendAudit({
          event_type: 'web.fetch.denied',
          created_at_ms: finished_at_ms,
          severity: 'security',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability: 'web.fetch',
          model_id: null,
          network_allowed: false,
          ok: false,
          error_code: error.code,
          error_message: error.message,
        });
        appendPolicyEvalAudit({
          created_at_ms: finished_at_ms,
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability: 'web.fetch',
          model_id: null,
          decision: 'deny',
          policy_scope: 'web_fetch',
          rule_ids: ['kill_switch_active'],
          phase: 'execute',
          user_ack_understood: false,
          explain_rounds: 0,
          options_presented: false,
          ok: false,
          error_code: error.code,
          error_message: error.message,
        });
        bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
        return;
      }
    } catch {
      // ignore kill-switch evaluation errors; fail open in MVP
    }

    const requireGrant = String(process.env.HUB_WEB_FETCH_REQUIRES_GRANT || '1').trim() !== '0';
    let grantRow = null;
    if (requireGrant) {
      const g = db.findActiveGrant({
        device_id,
        user_id: client.user_id ? String(client.user_id) : '',
        app_id,
        capability: 'web.fetch',
        model_id: null,
      });
      if (!g) {
        const finished_at_ms = nowMs();
        call.write({
          done: {
            request_id,
            ok: false,
            status: 0,
            final_url: '',
            content_type: '',
            truncated: false,
            bytes: 0,
            text: '',
            finished_at_ms,
            error: { code: 'grant_required', message: 'Active web.fetch grant required', retryable: false },
          },
        });
        call.end();
        db.appendAudit({
          event_type: 'web.fetch.denied',
          created_at_ms: finished_at_ms,
          severity: 'security',
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability: 'web.fetch',
          model_id: null,
          network_allowed: true,
          ok: false,
          error_code: 'grant_required',
          error_message: 'Active web.fetch grant required',
        });
        appendPolicyEvalAudit({
          created_at_ms: finished_at_ms,
          device_id,
          user_id: client.user_id ? String(client.user_id) : null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
          request_id,
          capability: 'web.fetch',
          model_id: null,
          decision: 'deny',
          policy_scope: 'web_fetch',
          rule_ids: ['grant_required'],
          phase: 'explain',
          user_ack_understood: false,
          explain_rounds: 0,
          options_presented: true,
          ok: false,
          error_code: 'grant_required',
          error_message: 'Active web.fetch grant required',
        });
        bus.emitHubEvent(
          bus.requestStatus({
            request_id,
            status: 'failed',
            error: { code: 'grant_required', message: 'grant_required', retryable: false },
            client,
          })
        );
        return;
      }
      grantRow = g;
      const ackFields = policyAckForGrantRequest(grantRow.grant_request_id || '');
      appendPolicyEvalAudit({
        created_at_ms: nowMs(),
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        decision: 'allow',
        policy_scope: 'web_fetch',
        rule_ids: ['grant_active'],
        ttl_sec: Number(grantRow.expires_at_ms || 0) > 0 ? Math.max(0, Math.floor((Number(grantRow.expires_at_ms || 0) - nowMs()) / 1000)) : 0,
        phase: 'execute',
        grant_request_id: grantRow.grant_request_id || '',
        grant_id: grantRow.grant_id || '',
        user_ack_understood: ackFields.user_ack_understood,
        explain_rounds: ackFields.explain_rounds,
        options_presented: ackFields.options_presented,
        ok: true,
      });
    }

    const urlText = String(req.url || '').trim();
    const parsed = requireHttpsUrl(urlText);
    if (!parsed.ok) {
      const finished_at_ms = nowMs();
      call.write({
        done: {
          request_id,
          ok: false,
          status: 0,
          final_url: urlText,
          content_type: '',
          truncated: false,
          bytes: 0,
          text: '',
          finished_at_ms,
          error: { code: parsed.error, message: parsed.error, retryable: false },
        },
      });
      call.end();

      db.appendAudit({
        event_type: 'web.fetch.denied',
        created_at_ms: finished_at_ms,
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        network_allowed: true,
        ok: false,
        error_code: parsed.error,
        error_message: parsed.error,
      });
      appendPolicyEvalAudit({
        created_at_ms: finished_at_ms,
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        decision: 'deny',
        policy_scope: 'web_fetch',
        rule_ids: ['invalid_url', String(parsed.error || '').trim() || 'invalid_url'],
        phase: 'explain',
        user_ack_understood: false,
        explain_rounds: 0,
        options_presented: true,
        ok: false,
        error_code: String(parsed.error || 'invalid_url'),
        error_message: String(parsed.error || 'invalid_url'),
        ext: { url: urlText },
      });

      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error: { code: parsed.error, message: parsed.error, retryable: false }, client }));
      return;
    }

    const u = parsed.url;
    const method = String(req.method || 'GET').toUpperCase();
    const timeout_sec = Math.max(2, Math.min(60, Number(req.timeout_sec || 12)));
    const max_bytes = Math.max(1, Math.min(5_000_000, Number(req.max_bytes || 1_000_000)));

    const started_at_ms = nowMs();
    call.write({ start: { request_id, url: u.toString(), started_at_ms } });

    const bridgeBaseDir = resolveBridgeBaseDir();
    if (grantRow && grantRow.expires_at_ms) {
      // Best-effort: extend Bridge enablement to the grant expiry.
      try {
        ensureBridgeEnabledUntil(bridgeBaseDir, Number(grantRow.expires_at_ms || 0) / 1000.0);
      } catch {
        // ignore
      }
    }

    // Require Bridge to be running; this keeps the core Hub process offline.
    const st0 = readBridgeStatus(bridgeBaseDir);
    if (!st0.alive) {
      const finished_at_ms = nowMs();
      const error = { code: 'bridge_unavailable', message: 'Bridge is not running', retryable: true };
      call.write({
        done: {
          request_id,
          ok: false,
          status: 0,
          final_url: u.toString(),
          content_type: '',
          truncated: false,
          bytes: 0,
          text: '',
          finished_at_ms,
          error,
        },
      });
      call.end();
      db.appendAudit({
        event_type: 'web.fetch.failed',
        created_at_ms: finished_at_ms,
        severity: 'warn',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        network_allowed: true,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        duration_ms: Math.max(0, finished_at_ms - started_at_ms),
        ext_json: JSON.stringify({ url: u.toString() }),
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      return;
    }

    // If the bridge is alive but currently "off", wait briefly for it to enable (grants may have just extended it).
    const st = st0.enabled ? st0 : await waitForBridgeEnabled(bridgeBaseDir, 1500);
    if (!st.enabled) {
      const finished_at_ms = nowMs();
      const error = { code: 'bridge_disabled', message: 'Bridge is disabled', retryable: true };
      call.write({
        done: {
          request_id,
          ok: false,
          status: 0,
          final_url: u.toString(),
          content_type: '',
          truncated: false,
          bytes: 0,
          text: '',
          finished_at_ms,
          error,
        },
      });
      call.end();
      db.appendAudit({
        event_type: 'web.fetch.denied',
        created_at_ms: finished_at_ms,
        severity: 'security',
        device_id,
        user_id: client.user_id ? String(client.user_id) : null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id,
        capability: 'web.fetch',
        model_id: null,
        network_allowed: true,
        ok: false,
        error_code: error.code,
        error_message: error.message,
        duration_ms: Math.max(0, finished_at_ms - started_at_ms),
        ext_json: JSON.stringify({ url: u.toString() }),
      });
      bus.emitHubEvent(bus.requestStatus({ request_id, status: 'failed', error, client }));
      return;
    }

    let ok = false;
    let status = 0;
    let content_type = '';
    let final_url = u.toString();
    let truncated = false;
    let bytes = 0;
    let text = '';
    let errText = '';

    try {
      enqueueBridgeFetch(bridgeBaseDir, { request_id, url: u.toString(), method, timeout_sec, max_bytes });
      const resp = await waitBridgeFetchResult(bridgeBaseDir, request_id, timeout_sec * 1000 + 5000);
      ok = !!resp?.ok;
      status = Number(resp?.status || 0);
      final_url = String(resp?.final_url || final_url);
      content_type = String(resp?.content_type || '');
      truncated = !!resp?.truncated;
      bytes = Number(resp?.bytes || 0);
      text = String(resp?.text || '');
      errText = String(resp?.error || '');
    } catch (e) {
      errText = String(e?.message || e || 'fetch_failed');
    }

    const finished_at_ms = nowMs();
    const errorObj = ok ? null : { code: 'fetch_failed', message: errText || 'fetch_failed', retryable: false };
    call.write({
      done: {
        request_id,
        ok,
        status,
        final_url,
        content_type,
        truncated,
        bytes,
        text,
        finished_at_ms,
        error: errorObj,
      },
    });
    call.end();

    db.appendAudit({
      event_type: ok ? 'web.fetch.completed' : 'web.fetch.failed',
      created_at_ms: finished_at_ms,
      severity: ok ? 'info' : 'warn',
      device_id,
      user_id: client.user_id ? String(client.user_id) : null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id,
      capability: 'web.fetch',
      model_id: null,
      prompt_tokens: null,
      completion_tokens: null,
      total_tokens: null,
      network_allowed: true,
      ok,
      error_code: ok ? null : errorObj.code,
      error_message: ok ? null : errorObj.message,
      duration_ms: Math.max(0, finished_at_ms - started_at_ms),
      ext_json: JSON.stringify({ final_url, status, truncated, bytes }),
    });

    bus.emitHubEvent(
      bus.requestStatus({
        request_id,
        status: ok ? 'done' : 'failed',
        error: ok ? null : errorObj,
        client,
      })
    );
  }

  // -------------------- HubEvents --------------------
  function Subscribe(call) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      call.end();
      return;
    }
    if (!clientAllows(auth, 'events')) {
      call.end();
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = String(client.user_id || '').trim();
    const project_id = trustedAutomationScope.project_id;
    const scopes = Array.isArray(req.scopes) ? req.scopes.map((s) => String(s || '').trim().toLowerCase()).filter(Boolean) : [];
    const scopeSet = new Set(scopes);
    const wantsAll = scopeSet.size === 0;

    // Identity is required for safe filtering.
    if (!device_id || !app_id) {
      call.end();
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      call.end();
      return;
    }

    // Device presence + inbox reminder.
    // Only notify on "real" remote devices (ignore loopback callers).
    const runtimeBaseDirForIPC = resolveRuntimeBaseDir();
    const peerIp = String(auth?.peer_ip || '').trim();
    const deviceName = String(auth?.client_name || '').trim() || device_id;
    let cleanedUp = false;

    const prev = eventSubsByDeviceId.get(device_id) || {
      count: 0,
      name: deviceName,
      peer_ip: peerIp,
      connected_at_ms: 0,
      last_seen_at_ms: 0,
    };
    const wasConnected = Number(prev.count || 0) > 0;
    const next = {
      ...prev,
      count: Number(prev.count || 0) + 1,
      name: deviceName || prev.name,
      peer_ip: peerIp || prev.peer_ip,
      last_seen_at_ms: Date.now(),
      connected_at_ms: wasConnected ? Number(prev.connected_at_ms || 0) : Date.now(),
    };
    eventSubsByDeviceId.set(device_id, next);
    writeGrpcDevicesStatus(runtimeBaseDirForIPC);

    if (!wasConnected && peerIp && !isLoopbackIp(peerIp)) {
      // Dedupe per device so reconnects update instead of spamming the inbox.
      try {
        pushHubNotification(runtimeBaseDirForIPC, {
          source: 'Hub',
          title: 'Device Connected',
          body: `${deviceName} (${device_id}) connected from ${peerIp}`,
          dedupe_key: `grpc_device:${device_id}:status`,
          action_url: null,
          unread: true,
        });
      } catch {
        // ignore
      }
    }

    const cleanupPresence = () => {
      if (cleanedUp) return;
      cleanedUp = true;
      const cur = eventSubsByDeviceId.get(device_id);
      if (!cur) return;
      const before = Number(cur.count || 0);
      const after = Math.max(0, before - 1);
      const stillConnected = after > 0;
      eventSubsByDeviceId.set(device_id, {
        ...cur,
        count: after,
        last_seen_at_ms: Date.now(),
      });
      writeGrpcDevicesStatus(runtimeBaseDirForIPC);

      if (before > 0 && !stillConnected && peerIp && !isLoopbackIp(peerIp)) {
        try {
          pushHubNotification(runtimeBaseDirForIPC, {
            source: 'Hub',
            title: 'Device Disconnected',
            body: `${deviceName} (${device_id}) disconnected`,
            dedupe_key: `grpc_device:${device_id}:status`,
            action_url: null,
            // Surface disconnects in the Hub inbox so operators notice drop-offs.
            unread: true,
          });
        } catch {
          // ignore
        }
      }
    };
    call.on('cancelled', cleanupPresence);
    call.on('close', cleanupPresence);
    call.on('error', cleanupPresence);

    // Optionally push a models snapshot right away.
    if (wantsAll || scopeSet.has('models')) {
      try {
        const runtimeBaseDir = resolveRuntimeBaseDir();
        const snap = runtimeModelsSnapshot(runtimeBaseDir);
        if (snap.ok && Array.isArray(snap.models) && snap.models.length) {
          const models = snap.models.map(makeProtoModelInfo).filter(Boolean);
          call.write(bus.modelsUpdated(models));
        } else {
          const rows = db.listModels();
          const models = rows.map(makeProtoModelInfo).filter(Boolean);
          call.write(bus.modelsUpdated(models));
        }
      } catch {
        // ignore
      }
    }

    bus.subscribe(call, {
      filter: (ev) => {
        const kind = ev.models_updated
          ? 'models'
          : ev.grant_decision
            ? 'grants'
            : ev.quota_updated
              ? 'quota'
              : ev.kill_switch_updated
                ? 'killswitch'
                : ev.request_status
                  ? 'requests'
                  : ev.voice_wake_profile_changed
                    ? 'voicewake'
                  : 'unknown';

        if (!wantsAll && !scopeSet.has(kind)) return false;

        // Device-scoped events: do not leak cross-device information by default.
        if (kind === 'grants') {
          const d = String(ev?.grant_decision?.client?.device_id || '').trim();
          return d && d === device_id;
        }
        if (kind === 'requests') {
          const d = String(ev?.request_status?.client?.device_id || '').trim();
          return d && d === device_id;
        }
        if (kind === 'quota') {
          const s = String(ev?.quota_updated?.scope || '').trim();
          if (!s) return false;
          if (s.startsWith('device:')) return s === `device:${device_id}`;
          if (s.startsWith('user:')) return user_id && s === `user:${user_id}`;
          if (s.startsWith('project:')) return project_id && s === `project:${project_id}`;
          return true; // global:* or other shared scopes
        }
        if (kind === 'killswitch') {
          const s = String(ev?.kill_switch_updated?.scope || '').trim();
          if (!s) return false;
          if (s.startsWith('device:')) return s === `device:${device_id}`;
          if (s.startsWith('user:')) return user_id && s === `user:${user_id}`;
          if (s.startsWith('project:')) return project_id && s === `project:${project_id}`;
          return true; // global:* or other shared scopes
        }
        return true;
      },
    });
  }

  // -------------------- HubRuntime --------------------
  function runtimeScopedClientFromRequest(req, auth) {
    const client = effectiveClientIdentity(req?.client || {}, auth);
    const scope = trustedAutomationScopeFromRequest(req, client);
    return {
      device_id: String(client.device_id || '').trim(),
      user_id: String(client.user_id || '').trim(),
      app_id: String(client.app_id || '').trim(),
      project_id: String(scope.project_id || '').trim(),
      workspace_root: String(scope.workspace_root || '').trim(),
      session_id: String(client.session_id || '').trim(),
    };
  }

  function grantRequestAllowedForRuntimeClient(grantRequestRow, scopedClient) {
    if (!grantRequestRow || !scopedClient) return false;
    const grantDeviceId = String(grantRequestRow.device_id || '').trim();
    if (!grantDeviceId || grantDeviceId !== String(scopedClient.device_id || '').trim()) {
      return false;
    }

    const scopedUserId = String(scopedClient.user_id || '').trim();
    if (scopedUserId) {
      const grantUserId = String(grantRequestRow.user_id || '').trim();
      if (grantUserId && grantUserId !== scopedUserId) {
        return false;
      }
    }

    const scopedProjectId = String(scopedClient.project_id || '').trim();
    if (scopedProjectId) {
      const grantProjectId = String(grantRequestRow.project_id || '').trim();
      if (!grantProjectId || grantProjectId !== scopedProjectId) {
        return false;
      }
    }
    return true;
  }

  function grantRequestClientFromRow(row) {
    return {
      device_id: String(row?.device_id || ''),
      user_id: row?.user_id ? String(row.user_id) : '',
      app_id: String(row?.app_id || ''),
      project_id: row?.project_id ? String(row.project_id) : '',
      session_id: '',
    };
  }

  function GetSchedulerStatus(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'events')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const includeQueueItems = req.include_queue_items !== false;
    const queueItemsLimit = parseIntInRange(req.queue_items_limit, 100, 1, 500);
    const paid_ai = buildPaidAISchedulerSnapshot({
      includeQueueItems,
      queueItemsLimit,
    });
    callback(null, { paid_ai });
  }

  function GetPendingGrantRequests(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'events')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = runtimeScopedClientFromRequest(req, auth);
    const device_id = String(client.device_id || '').trim();
    const user_id = String(client.user_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    if (!device_id || !app_id) {
      callback(new Error('invalid_client_identity'));
      return;
    }
    if (!trustedAutomationAllows(auth, client)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const reqProjectId = String(req.project_id || '').trim();
    const project_id = reqProjectId || String(client.project_id || '').trim();
    const limit = parseIntInRange(req.limit, 200, 1, 500);

    const snapshot = buildPendingGrantRequestsSnapshot({
      deviceId: device_id,
      userId: user_id,
      appId: '',
      projectId: project_id,
      limit,
    });
    callback(null, snapshot);
  }

  function GetConnectorIngressReceipts(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'events')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = runtimeScopedClientFromRequest(req, auth);
    const device_id = String(client.device_id || '').trim();
    const user_id = String(client.user_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    if (!device_id || !app_id) {
      callback(new Error('invalid_client_identity'));
      return;
    }
    if (!trustedAutomationAllows(auth, client)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const reqProjectId = String(req.project_id || '').trim();
    const project_id = reqProjectId || String(client.project_id || '').trim();
    const limit = parseIntInRange(req.limit, 200, 1, 500);

    const snapshot = buildConnectorIngressReceiptsSnapshot({
      projectId: project_id,
      limit,
    });
    callback(null, snapshot);
  }

  function GetAutonomyPolicyOverrides(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'events')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = runtimeScopedClientFromRequest(req, auth);
    const device_id = String(client.device_id || '').trim();
    const user_id = String(client.user_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    if (!device_id || !app_id) {
      callback(new Error('invalid_client_identity'));
      return;
    }
    if (!trustedAutomationAllows(auth, client)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const reqProjectId = String(req.project_id || '').trim();
    const project_id = reqProjectId || String(client.project_id || '').trim();
    const limit = parseIntInRange(req.limit, 200, 1, 500);

    const snapshot = buildAutonomyPolicyOverridesSnapshot({
      projectId: project_id,
      limit,
    });
    callback(null, snapshot);
  }

  function ApprovePendingGrantRequest(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'events')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = runtimeScopedClientFromRequest(req, auth);
    if (!client.device_id || !client.app_id) {
      callback(new Error('invalid_client_identity'));
      return;
    }
    if (!trustedAutomationAllows(auth, client)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const grant_request_id = String(req.grant_request_id || '').trim();
    if (!grant_request_id) {
      callback(new Error('missing grant_request_id'));
      return;
    }

    const gr = db.getGrantRequest(grant_request_id);
    if (!gr) {
      callback(new Error('grant_request_not_found'));
      return;
    }
    if (String(gr.status || '').trim() !== 'pending') {
      callback(new Error(`grant_request_not_pending (${String(gr.status || '')})`));
      return;
    }
    if (!grantRequestAllowedForRuntimeClient(gr, client)) {
      callback(new Error('permission_denied'));
      return;
    }

    const ttlRaw = Number(req.ttl_sec);
    const defaultTtl = Math.max(10, Number(gr.requested_ttl_sec || 1800));
    const ttl_sec = Number.isFinite(ttlRaw) && ttlRaw > 0 ? Math.max(10, Math.floor(ttlRaw)) : defaultTtl;

    const tokenRaw = Number(req.token_cap);
    const defaultTokenCap = Math.max(0, Number(gr.requested_token_cap || 0));
    const token_cap = Number.isFinite(tokenRaw) && tokenRaw > 0 ? Math.max(0, Math.floor(tokenRaw)) : defaultTokenCap;

    const ackFields = parsePolicyAckFields({ note: req.note || '' });
    const approverId = client.user_id || client.device_id || 'runtime_client';
    const expires_at_ms = nowMs() + ttl_sec * 1000;

    db.decideGrantRequest(grant_request_id, {
      status: 'approved',
      decision: 'approved',
      approver_id: approverId,
      note: req.note || '',
      user_ack_understood: ackFields.user_ack_understood,
      explain_rounds: ackFields.explain_rounds,
      options_presented: ackFields.options_presented,
    });

    const grantRow = db.createGrant({
      grant_request_id,
      device_id: String(gr.device_id || ''),
      user_id: gr.user_id ? String(gr.user_id) : null,
      app_id: String(gr.app_id || ''),
      project_id: gr.project_id ? String(gr.project_id) : null,
      capability: String(gr.capability || ''),
      model_id: gr.model_id ? String(gr.model_id) : null,
      token_cap,
      expires_at_ms,
    });
    const grant = makeProtoGrant(grantRow);

    if (String(grantRow?.capability || '') === 'ai.generate.paid' || String(grantRow?.capability || '') === 'web.fetch') {
      try {
        ensureBridgeEnabledUntil(resolveBridgeBaseDir(), Number(expires_at_ms || 0) / 1000.0);
      } catch {
        // ignore
      }
    }

    db.appendAudit({
      event_type: 'grant.request.approved',
      created_at_ms: nowMs(),
      severity: 'security',
      device_id: String(gr.device_id || client.device_id || 'unknown'),
      user_id: gr.user_id ? String(gr.user_id) : (client.user_id || null),
      app_id: String(gr.app_id || client.app_id || 'x_terminal'),
      project_id: gr.project_id ? String(gr.project_id) : (client.project_id || null),
      request_id: gr.request_id ? String(gr.request_id) : null,
      capability: gr.capability ? String(gr.capability) : null,
      model_id: gr.model_id ? String(gr.model_id) : null,
      ok: true,
      ext_json: JSON.stringify({
        grant_request_id,
        approver_id: approverId,
        note: req.note || '',
        source: 'runtime_client',
      }),
    });
    appendPolicyEvalAudit({
      created_at_ms: nowMs(),
      device_id: String(gr.device_id || client.device_id || 'unknown'),
      user_id: gr.user_id ? String(gr.user_id) : (client.user_id || null),
      app_id: String(gr.app_id || client.app_id || 'x_terminal'),
      project_id: gr.project_id ? String(gr.project_id) : (client.project_id || null),
      session_id: client.session_id || null,
      request_id: gr.request_id ? String(gr.request_id) : null,
      capability: gr.capability ? String(gr.capability) : null,
      model_id: gr.model_id ? String(gr.model_id) : null,
      decision: 'allow',
      policy_scope: 'grant_request',
      rule_ids: ['runtime_client_confirmed'],
      ttl_sec,
      phase: 'confirm',
      grant_request_id,
      grant_id: grant?.grant_id || '',
      user_ack_understood: ackFields.user_ack_understood,
      explain_rounds: ackFields.explain_rounds,
      options_presented: ackFields.options_presented,
      ok: true,
    });
    bus.emitHubEvent(
      bus.grantDecision({
        grant_request_id,
        decision: 'GRANT_DECISION_APPROVED',
        grant,
        deny_reason: '',
        client: grantRequestClientFromRow(gr),
      })
    );

    callback(null, { grant_request_id, grant });
  }

  function DenyPendingGrantRequest(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'events')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = runtimeScopedClientFromRequest(req, auth);
    if (!client.device_id || !client.app_id) {
      callback(new Error('invalid_client_identity'));
      return;
    }
    if (!trustedAutomationAllows(auth, client)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const grant_request_id = String(req.grant_request_id || '').trim();
    if (!grant_request_id) {
      callback(new Error('missing grant_request_id'));
      return;
    }

    const gr = db.getGrantRequest(grant_request_id);
    if (!gr) {
      callback(new Error('grant_request_not_found'));
      return;
    }
    if (String(gr.status || '').trim() !== 'pending') {
      callback(new Error(`grant_request_not_pending (${String(gr.status || '')})`));
      return;
    }
    if (!grantRequestAllowedForRuntimeClient(gr, client)) {
      callback(new Error('permission_denied'));
      return;
    }

    const reason = String(req.reason || '').trim() || 'denied';
    const ackFields = parsePolicyAckFields({ reason });
    const approverId = client.user_id || client.device_id || 'runtime_client';

    db.decideGrantRequest(grant_request_id, {
      status: 'denied',
      decision: 'denied',
      deny_reason: reason,
      approver_id: approverId,
      user_ack_understood: ackFields.user_ack_understood,
      explain_rounds: ackFields.explain_rounds,
      options_presented: ackFields.options_presented,
    });
    db.appendAudit({
      event_type: 'grant.request.denied',
      created_at_ms: nowMs(),
      severity: 'security',
      device_id: String(gr.device_id || client.device_id || 'unknown'),
      user_id: gr.user_id ? String(gr.user_id) : (client.user_id || null),
      app_id: String(gr.app_id || client.app_id || 'x_terminal'),
      project_id: gr.project_id ? String(gr.project_id) : (client.project_id || null),
      request_id: gr.request_id ? String(gr.request_id) : null,
      capability: gr.capability ? String(gr.capability) : null,
      model_id: gr.model_id ? String(gr.model_id) : null,
      ok: true,
      ext_json: JSON.stringify({
        grant_request_id,
        approver_id: approverId,
        reason,
        source: 'runtime_client',
      }),
    });
    appendPolicyEvalAudit({
      created_at_ms: nowMs(),
      device_id: String(gr.device_id || client.device_id || 'unknown'),
      user_id: gr.user_id ? String(gr.user_id) : (client.user_id || null),
      app_id: String(gr.app_id || client.app_id || 'x_terminal'),
      project_id: gr.project_id ? String(gr.project_id) : (client.project_id || null),
      session_id: client.session_id || null,
      request_id: gr.request_id ? String(gr.request_id) : null,
      capability: gr.capability ? String(gr.capability) : null,
      model_id: gr.model_id ? String(gr.model_id) : null,
      decision: 'deny',
      policy_scope: 'grant_request',
      rule_ids: ['runtime_client_denied'],
      phase: 'confirm',
      grant_request_id,
      user_ack_understood: ackFields.user_ack_understood,
      explain_rounds: ackFields.explain_rounds,
      options_presented: ackFields.options_presented,
      ok: false,
    });
    bus.emitHubEvent(
      bus.grantDecision({
        grant_request_id,
        decision: 'GRANT_DECISION_DENIED',
        grant: null,
        deny_reason: reason,
        client: grantRequestClientFromRow(gr),
      })
    );
    callback(null, { grant_request_id });
  }

  // -------------------- HubAudit --------------------
  function ListAuditEvents(call, callback) {
    const auth = requireAdminAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }

    const req = call.request || {};
    const rows = db.listAuditEvents(req);
    const events = rows.map((r) => ({
      schema_version: 'audit.v1',
      event_id: String(r.event_id || ''),
      event_type: String(r.event_type || ''),
      created_at_ms: Number(r.created_at_ms || 0),
      actor: {
        device_id: String(r.device_id || ''),
        user_id: r.user_id ? String(r.user_id) : '',
        app_id: String(r.app_id || ''),
        project_id: r.project_id ? String(r.project_id) : '',
        session_id: r.session_id ? String(r.session_id) : '',
      },
      request_id: r.request_id ? String(r.request_id) : '',
      capability: toProtoCapability(r.capability || ''),
      model_id: r.model_id ? String(r.model_id) : '',
      usage: {
        prompt_tokens: Number(r.prompt_tokens || 0),
        completion_tokens: Number(r.completion_tokens || 0),
        total_tokens: Number(r.total_tokens || 0),
        cost_usd_estimate: Number(r.cost_usd_estimate || 0),
      },
      network_allowed: r.network_allowed != null ? !!Number(r.network_allowed) : false,
      ok: !!Number(r.ok || 0),
      error: r.error_code
        ? { code: String(r.error_code || ''), message: String(r.error_message || ''), retryable: false }
        : null,
    }));
    callback(null, { events });
  }

  // -------------------- HubMemory --------------------
	  function GetOrCreateThread(call, callback) {
	    const auth = requireClientAuth(call);
	    if (!auth.ok) {
	      callback(new Error(auth.message));
	      return;
	    }
	    if (!clientAllows(auth, 'memory')) {
	      callback(new Error(capabilityDenyCode(auth)));
	      return;
	    }
	    const req = call.request || {};
	    const client = effectiveClientIdentity(req.client || {}, auth);
	    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const thread_key = String(req.thread_key || 'default').trim() || 'default';

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.thread.opened',
        error_message: 'thread_open_denied',
        op: 'get_or_create_thread',
        client,
        request_id: '',
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          created: false,
          thread_key,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let row;
    try {
      row = db.getOrCreateThread({ device_id, user_id, app_id, project_id, thread_key });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'thread_error')));
      return;
    }

    callback(null, {
      thread: {
        thread_id: String(row?.thread_id || ''),
        client: {
          device_id,
          user_id,
          app_id,
          project_id,
          session_id: '',
        },
        thread_key: String(row?.thread_key || thread_key),
        created_at_ms: Number(row?.created_at_ms || 0),
        updated_at_ms: Number(row?.updated_at_ms || 0),
      },
    });
  }

	  function AppendTurns(call, callback) {
	    const auth = requireClientAuth(call);
	    if (!auth.ok) {
	      callback(new Error(auth.message));
	      return;
	    }
	    if (!clientAllows(auth, 'memory')) {
	      callback(new Error(capabilityDenyCode(auth)));
	      return;
	    }
	    const req = call.request || {};
	    const client = effectiveClientIdentity(req.client || {}, auth);
	    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const thread_id = String(req.thread_id || '').trim();
    const request_id = String(req.request_id || '').trim();
    const allow_private = !!req.allow_private;

    if (!device_id || !app_id || !thread_id) {
      callback(new Error('invalid request: missing device_id/app_id/thread_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const thread = db.getThread(thread_id);
    if (!thread) {
      callback(new Error('thread_not_found'));
      return;
    }
    if (String(thread.device_id || '') !== device_id) {
      callback(new Error('permission_denied'));
      return;
    }
    if (String(thread.app_id || '') !== app_id || String(thread.project_id || '') !== project_id) {
      callback(new Error('permission_denied'));
      return;
    }

    const baseTs = Number(req.created_at_ms || nowMs());
    const turns = [];
    const msgs = Array.isArray(req.messages) ? req.messages : [];
    for (let i = 0; i < msgs.length; i += 1) {
      const m = msgs[i] || {};
      const role = String(m.role || '').trim();
      const raw = String(m.content ?? '');
      if (!role || !raw) continue;
      if (allow_private) {
        turns.push({ role, content: raw, is_private: 0, created_at_ms: baseTs + i });
      } else {
        const red = redactPrivateContent(raw);
        const cleaned = String(red.text || '').trim();
        if (!cleaned) continue;
        turns.push({ role, content: cleaned, is_private: red.had_private ? 1 : 0, created_at_ms: baseTs + i });
      }
    }

    let appended = 0;
    try {
      appended = db.appendTurns({ thread_id, request_id: request_id || null, turns });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'append_failed')));
      return;
    }

    db.appendAudit({
      event_type: 'memory.turns.appended',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: request_id || null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({ thread_id, appended }),
    });

    callback(null, { thread_id, appended });
  }

	  function GetWorkingSet(call, callback) {
	    const auth = requireClientAuth(call);
	    if (!auth.ok) {
	      callback(new Error(auth.message));
	      return;
	    }
	    if (!clientAllows(auth, 'memory')) {
	      callback(new Error(capabilityDenyCode(auth)));
	      return;
	    }
	    const req = call.request || {};
	    const client = effectiveClientIdentity(req.client || {}, auth);
	    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const thread_id = String(req.thread_id || '').trim();
    const limit = Math.max(1, Math.min(200, Number(req.limit || 50)));

    if (!device_id || !app_id || !thread_id) {
      callback(new Error('invalid request: missing device_id/app_id/thread_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const thread = db.getThread(thread_id);
    if (!thread) {
      callback(new Error('thread_not_found'));
      return;
    }
    if (String(thread.device_id || '') !== device_id) {
      callback(new Error('permission_denied'));
      return;
    }
    if (String(thread.app_id || '') !== app_id || String(thread.project_id || '') !== project_id) {
      callback(new Error('permission_denied'));
      return;
    }

    const rows = db.listTurns({ thread_id, limit });
    const msgs = rows
      .map((r) => ({ role: String(r.role || ''), content: String(r.content || ''), created_at_ms: Number(r.created_at_ms || 0) }))
      .reverse()
      .map((m) => ({ role: m.role, content: m.content }));

    callback(null, { thread_id, messages: msgs });
  }

	  function UpsertCanonicalMemory(call, callback) {
	    const auth = requireClientAuth(call);
	    if (!auth.ok) {
	      callback(new Error(auth.message));
	      return;
	    }
	    if (!clientAllows(auth, 'memory')) {
	      callback(new Error(capabilityDenyCode(auth)));
	      return;
	    }
	    const req = call.request || {};
	    const client = effectiveClientIdentity(req.client || {}, auth);
	    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const scope = String(req.scope || '').trim() || 'thread';
    const thread_id = String(req.thread_id || '').trim();
    const key = String(req.key || '').trim();
    const value = String(req.value ?? '').trim();
    const pinned = !!req.pinned;

    if (!device_id || !app_id || !key) {
      callback(new Error('invalid request: missing device_id/app_id/key'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    if (scope === 'thread' && !thread_id) {
      callback(new Error('invalid request: missing thread_id for scope=thread'));
      return;
    }

    let row;
    try {
      row = db.upsertCanonicalItem({
        scope,
        thread_id: thread_id || '',
        device_id,
        user_id,
        app_id,
        project_id,
        key,
        value,
        pinned,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'upsert_failed')));
      return;
    }

    callback(null, {
      item: {
        item_id: String(row?.item_id || ''),
        scope: String(row?.scope || scope),
        thread_id: String(row?.thread_id || thread_id || ''),
        key: String(row?.key || key),
        value: String(row?.value || value),
        pinned: !!Number(row?.pinned || 0),
        updated_at_ms: Number(row?.updated_at_ms || 0),
      },
    });
  }

  function ListCanonicalMemory(call, callback) {
	    const auth = requireClientAuth(call);
	    if (!auth.ok) {
	      callback(new Error(auth.message));
	      return;
	    }
	    if (!clientAllows(auth, 'memory')) {
	      callback(new Error(capabilityDenyCode(auth)));
	      return;
	    }
	    const req = call.request || {};
	    const client = effectiveClientIdentity(req.client || {}, auth);
	    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const rows = db.listCanonicalItems({
      scope: req.scope ? String(req.scope).trim() : '',
      thread_id: req.thread_id ? String(req.thread_id).trim() : '',
      device_id,
      user_id,
      app_id,
      project_id,
      limit: Number(req.limit || 100),
    });
    const items = rows.map((r) => ({
      item_id: String(r.item_id || ''),
      scope: String(r.scope || ''),
      thread_id: String(r.thread_id || ''),
      key: String(r.key || ''),
      value: String(r.value || ''),
      pinned: !!Number(r.pinned || 0),
      updated_at_ms: Number(r.updated_at_ms || 0),
    }));
	    callback(null, { items });
	  }

  function appendProjectRejectAudit({
    event_type,
    error_message,
    op,
    client,
    request_id,
    project_id,
    deny_code,
    ext,
  } = {}) {
    const actor = client && typeof client === 'object' ? client : {};
    db.appendAudit({
      event_type: String(event_type || 'project.lineage.rejected'),
      created_at_ms: nowMs(),
      severity: 'warn',
      device_id: String(actor.device_id || ''),
      user_id: actor.user_id ? String(actor.user_id) : null,
      app_id: String(actor.app_id || ''),
      project_id: project_id ? String(project_id) : null,
      session_id: actor.session_id ? String(actor.session_id) : null,
      request_id: request_id ? String(request_id) : null,
      capability: 'unknown',
      model_id: null,
      ok: false,
      error_code: String(deny_code || 'permission_denied'),
      error_message: String(error_message || 'project_request_rejected'),
      ext_json: JSON.stringify({
        op: String(op || ''),
        deny_code: String(deny_code || 'permission_denied'),
        ...(ext && typeof ext === 'object' ? ext : {}),
      }),
    });
  }

  function appendDeniedAudit({
    event_type,
    error_message,
    op,
    client,
    request_id,
    project_id,
    severity,
    deny_code,
    ext,
  } = {}) {
    const actor = client && typeof client === 'object' ? client : {};
    try {
      db.appendAudit({
        event_type: String(event_type || 'request.denied'),
        created_at_ms: nowMs(),
        severity: String(severity || 'warn'),
        device_id: String(actor.device_id || ''),
        user_id: actor.user_id ? String(actor.user_id) : null,
        app_id: String(actor.app_id || ''),
        project_id: project_id ? String(project_id) : null,
        session_id: actor.session_id ? String(actor.session_id) : null,
        request_id: request_id ? String(request_id) : null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: String(deny_code || 'permission_denied'),
        error_message: String(error_message || 'request_denied'),
        ext_json: JSON.stringify({
          op: String(op || ''),
          deny_code: String(deny_code || 'permission_denied'),
          ...(ext && typeof ext === 'object' ? ext : {}),
        }),
      });
    } catch {
      // preserve fail-closed deny response even if audit sink fails
    }
  }

  function UpsertProjectLineage(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const request_id = String(req.request_id || '').trim();
    const expected_root_project_id = String(req.expected_root_project_id || '').trim();
    const lineage = req.lineage && typeof req.lineage === 'object' ? req.lineage : {};
    const root_project_id = String(lineage.root_project_id || '').trim();
    const parent_project_id = String(lineage.parent_project_id || '').trim();
    const project_id = String(lineage.project_id || '').trim();
    const lineage_path = String(lineage.lineage_path || '').trim();
    const parent_task_id = String(lineage.parent_task_id || '').trim();
    const split_round = Math.max(0, Math.floor(Number(lineage.split_round || 0)));
    const split_reason = String(lineage.split_reason || '').trim();
    const child_index = Math.max(0, Math.floor(Number(lineage.child_index || 0)));
    const status = String(lineage.status || '').trim() || 'active';
    const created_at_ms = Math.max(0, Number(lineage.created_at_ms || 0));
    const trustedAutomationScope = trustedAutomationScopeWithProject(
      trustedAutomationScopeFromRequest(req, client),
      root_project_id,
      project_id,
    );
    const now = nowMs();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!root_project_id || !project_id) {
      db.appendAudit({
        event_type: 'project.lineage.rejected',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: 'invalid_request',
        error_message: 'project_lineage_invalid_request',
        ext_json: JSON.stringify({
          op: 'upsert_project_lineage',
          deny_code: 'invalid_request',
          reason: 'missing lineage.root_project_id/project_id',
        }),
      });
      callback(null, {
        accepted: false,
        created: false,
        deny_code: 'invalid_request',
      });
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendProjectRejectAudit({
        event_type: 'project.lineage.rejected',
        error_message: 'project_lineage_rejected',
        op: 'upsert_project_lineage',
        client,
        request_id,
        project_id: project_id || root_project_id || null,
        deny_code: denyCode,
        ext: {
          root_project_id,
          parent_project_id,
          project_id,
          lineage_path,
          split_round,
          child_index,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.upsertProjectLineage({
        request_id,
        device_id,
        user_id,
        app_id,
        root_project_id,
        parent_project_id,
        project_id,
        lineage_path,
        parent_task_id,
        split_round,
        split_reason,
        child_index,
        status,
        expected_root_project_id,
        created_at_ms: created_at_ms || now,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'lineage_upsert_failed')));
      return;
    }

    if (!out?.accepted) {
      db.appendAudit({
        event_type: 'project.lineage.rejected',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: String(out?.deny_code || 'lineage_rejected'),
        error_message: 'project_lineage_rejected',
        ext_json: JSON.stringify({
          op: 'upsert_project_lineage',
          root_project_id,
          parent_project_id,
          project_id,
          lineage_path,
          split_round,
          child_index,
          deny_code: String(out?.deny_code || 'lineage_rejected'),
        }),
      });
      callback(null, {
        accepted: false,
        created: false,
        deny_code: String(out?.deny_code || 'lineage_rejected'),
      });
      return;
    }

    const lineageNode = makeProtoProjectLineageNode(out?.lineage);
    db.appendAudit({
      event_type: 'project.lineage.upserted',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: String(lineageNode?.project_id || project_id || ''),
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: request_id || null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        op: 'upsert_project_lineage',
        created: !!out?.created,
        root_project_id: String(lineageNode?.root_project_id || ''),
        parent_project_id: String(lineageNode?.parent_project_id || ''),
        project_id: String(lineageNode?.project_id || ''),
        lineage_path: String(lineageNode?.lineage_path || ''),
        split_round: Number(lineageNode?.split_round || 0),
        child_index: Number(lineageNode?.child_index || 0),
        status: String(lineageNode?.status || ''),
      }),
    });

    callback(null, {
      accepted: true,
      created: !!out?.created,
      deny_code: '',
      lineage: lineageNode,
    });
  }

  function GetProjectLineageTree(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const root_project_id = String(req.root_project_id || '').trim();
    const project_id = String(req.project_id || '').trim();
    const max_depth = Number(req.max_depth || 0);
    const include_archived = !!req.include_archived;
    const trustedAutomationScope = trustedAutomationScopeWithProject(
      trustedAutomationScopeFromRequest(req, client),
      root_project_id,
      project_id,
    );

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!root_project_id) {
      callback(new Error('invalid request: missing root_project_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendProjectRejectAudit({
        event_type: 'project.lineage.rejected',
        error_message: 'project_lineage_rejected',
        op: 'get_project_lineage_tree',
        client,
        request_id: '',
        project_id: root_project_id || project_id || null,
        deny_code: denyCode,
        ext: {
          root_project_id,
          project_id,
          max_depth,
          include_archived,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.getProjectLineageTree({
        root_project_id,
        project_id,
        max_depth,
        include_archived,
        device_id,
        user_id,
        app_id,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'lineage_tree_failed')));
      return;
    }

    callback(null, {
      root_project_id: String(out?.root_project_id || root_project_id),
      nodes: Array.isArray(out?.nodes)
        ? out.nodes.map((row) => makeProtoProjectLineageNode(row)).filter(Boolean)
        : [],
      generated_at_ms: Math.max(0, Number(out?.generated_at_ms || nowMs())),
    });
  }

  function AttachDispatchContext(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const request_id = String(req.request_id || '').trim();
    const dispatch = req.dispatch && typeof req.dispatch === 'object' ? req.dispatch : {};
    const root_project_id = String(dispatch.root_project_id || '').trim();
    const parent_project_id = String(dispatch.parent_project_id || '').trim();
    const project_id = String(dispatch.project_id || '').trim();
    const assigned_agent_profile = String(dispatch.assigned_agent_profile || '').trim();
    const parallel_lane_id = String(dispatch.parallel_lane_id || '').trim();
    const budget_class = String(dispatch.budget_class || '').trim();
    const queue_priority = Math.floor(Number(dispatch.queue_priority || 0));
    const expected_artifacts = Array.isArray(dispatch.expected_artifacts)
      ? dispatch.expected_artifacts.map((v) => String(v || '').trim()).filter(Boolean)
      : [];
    const attached_at_ms = Math.max(0, Number(dispatch.attached_at_ms || nowMs()));
    const attach_source = String(dispatch.attach_source || '').trim() || 'x_terminal';
    const trustedAutomationScope = trustedAutomationScopeWithProject(
      trustedAutomationScopeFromRequest(req, client),
      root_project_id,
      project_id,
    );

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!root_project_id || !project_id || !assigned_agent_profile) {
      db.appendAudit({
        event_type: 'project.lineage.rejected',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: 'invalid_request',
        error_message: 'project_dispatch_invalid_request',
        ext_json: JSON.stringify({
          op: 'attach_dispatch_context',
          deny_code: 'invalid_request',
          reason: 'missing dispatch.root_project_id/project_id/assigned_agent_profile',
        }),
      });
      callback(null, {
        attached: false,
        deny_code: 'invalid_request',
      });
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendProjectRejectAudit({
        event_type: 'project.lineage.rejected',
        error_message: 'project_dispatch_rejected',
        op: 'attach_dispatch_context',
        client,
        request_id,
        project_id: project_id || root_project_id || null,
        deny_code: denyCode,
        ext: {
          root_project_id,
          parent_project_id,
          project_id,
          assigned_agent_profile,
          parallel_lane_id,
          budget_class,
          queue_priority,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.attachProjectDispatchContext({
        request_id,
        device_id,
        user_id,
        app_id,
        root_project_id,
        parent_project_id,
        project_id,
        assigned_agent_profile,
        parallel_lane_id,
        budget_class,
        queue_priority,
        expected_artifacts,
        attached_at_ms,
        attach_source,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'dispatch_attach_failed')));
      return;
    }

    if (!out?.attached) {
      db.appendAudit({
        event_type: 'project.lineage.rejected',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: String(out?.deny_code || 'dispatch_rejected'),
        error_message: 'project_dispatch_rejected',
        ext_json: JSON.stringify({
          op: 'attach_dispatch_context',
          root_project_id,
          parent_project_id,
          project_id,
          assigned_agent_profile,
          parallel_lane_id,
          budget_class,
          queue_priority,
          deny_code: String(out?.deny_code || 'dispatch_rejected'),
        }),
      });
      callback(null, {
        attached: false,
        deny_code: String(out?.deny_code || 'dispatch_rejected'),
      });
      return;
    }

    const dispatchOut = makeProtoProjectDispatchContext(out?.dispatch);
    db.appendAudit({
      event_type: 'project.dispatch.lineage_attached',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: String(dispatchOut?.project_id || project_id || ''),
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: request_id || null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        op: 'attach_dispatch_context',
        root_project_id: String(dispatchOut?.root_project_id || ''),
        parent_project_id: String(dispatchOut?.parent_project_id || ''),
        project_id: String(dispatchOut?.project_id || ''),
        assigned_agent_profile: String(dispatchOut?.assigned_agent_profile || ''),
        parallel_lane_id: String(dispatchOut?.parallel_lane_id || ''),
        budget_class: String(dispatchOut?.budget_class || ''),
        queue_priority: Number(dispatchOut?.queue_priority || 0),
        expected_artifacts_count: Array.isArray(dispatchOut?.expected_artifacts)
          ? dispatchOut.expected_artifacts.length
          : 0,
      }),
    });

    callback(null, {
      attached: true,
      deny_code: '',
      dispatch: dispatchOut,
    });
  }

  function GetRiskTuningProfile(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }

    let out;
    try {
      out = db.getRiskTuningProfileSnapshot({
        profile_id: String(req.profile_id || '').trim(),
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'risk_profile_failed')));
      return;
    }

    callback(null, {
      active_profile_id: String(out?.active_profile_id || ''),
      stable_profile_id: String(out?.stable_profile_id || ''),
      profile: makeProtoRiskTuningProfile(out?.profile),
      latest_evaluation_id: String(out?.latest_evaluation?.evaluation_id || ''),
      latest_evaluation_decision: String(out?.latest_evaluation?.decision || ''),
      latest_deny_code: String(out?.latest_evaluation?.deny_code || ''),
    });
  }

  function EvaluateRiskTuningProfile(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.risk_tuning.evaluated',
        error_message: 'risk_tuning_evaluation_denied',
        op: 'evaluate_risk_tuning_profile',
        client,
        request_id: String(req.request_id || '').trim(),
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          profile_id: String(req?.profile?.profile_id || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.evaluateRiskTuningProfile({
        request_id: String(req.request_id || '').trim(),
        profile: req.profile && typeof req.profile === 'object' ? req.profile : {},
        baseline_metrics: req.baseline_metrics && typeof req.baseline_metrics === 'object' ? req.baseline_metrics : null,
        holdout_metrics: req.holdout_metrics && typeof req.holdout_metrics === 'object' ? req.holdout_metrics : null,
        online_metrics: req.online_metrics && typeof req.online_metrics === 'object' ? req.online_metrics : null,
        offline_metrics: req.offline_metrics && typeof req.offline_metrics === 'object' ? req.offline_metrics : null,
        auto_rollback_on_violation: !!req.auto_rollback_on_violation,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'risk_evaluate_failed')));
      return;
    }

    const denyCode = String(out?.deny_code || '');
    const requestId = String(req.request_id || '').trim();
    db.appendAudit({
      event_type: 'memory.risk_tuning.evaluated',
      created_at_ms: nowMs(),
      severity: out?.accepted ? 'info' : 'warn',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: requestId || null,
      capability: 'unknown',
      model_id: null,
      ok: !!out?.accepted,
      error_code: out?.accepted ? null : (denyCode || 'risk_tuning_blocked'),
      error_message: out?.accepted ? null : 'risk_tuning_evaluation_denied',
      ext_json: JSON.stringify({
        op: 'evaluate_risk_tuning_profile',
        profile_id: String(out?.profile_id || ''),
        evaluation_id: String(out?.evaluation_id || ''),
        holdout_passed: !!out?.holdout_passed,
        decision: String(out?.decision || ''),
        rollback_triggered: !!out?.rollback_triggered,
        rollback_to_profile_id: String(out?.rollback_to_profile_id || ''),
      }),
    });
    if (out?.rollback_triggered) {
      db.appendAudit({
        event_type: 'memory.risk_tuning.rollback',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: requestId || null,
        capability: 'unknown',
        model_id: null,
        ok: true,
        ext_json: JSON.stringify({
          op: 'risk_tuning_auto_rollback',
          evaluation_id: String(out?.evaluation_id || ''),
          profile_id: String(out?.profile_id || ''),
          rollback_to_profile_id: String(out?.rollback_to_profile_id || ''),
          deny_code: denyCode,
        }),
      });
    }

    callback(null, {
      evaluation_id: String(out?.evaluation_id || ''),
      profile_id: String(out?.profile_id || ''),
      accepted: !!out?.accepted,
      holdout_passed: !!out?.holdout_passed,
      rollback_triggered: !!out?.rollback_triggered,
      rollback_to_profile_id: String(out?.rollback_to_profile_id || ''),
      deny_code: denyCode,
      decision: String(out?.decision || ''),
    });
  }

  function PromoteRiskTuningProfile(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.risk_tuning.promoted',
        error_message: 'risk_tuning_promotion_denied',
        op: 'promote_risk_tuning_profile',
        client,
        request_id: String(req.request_id || '').trim(),
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          profile_id: String(req.profile_id || ''),
          expected_active_profile_id: String(req.expected_active_profile_id || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.promoteRiskTuningProfile({
        request_id: String(req.request_id || '').trim(),
        profile_id: String(req.profile_id || '').trim(),
        rollback_on_violation: !!req.rollback_on_violation,
        expected_active_profile_id: String(req.expected_active_profile_id || '').trim(),
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'risk_promote_failed')));
      return;
    }

    const denyCode = String(out?.deny_code || '');
    const requestId = String(req.request_id || '').trim();
    db.appendAudit({
      event_type: 'memory.risk_tuning.promoted',
      created_at_ms: nowMs(),
      severity: out?.promoted ? 'info' : 'warn',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: requestId || null,
      capability: 'unknown',
      model_id: null,
      ok: !!out?.promoted,
      error_code: out?.promoted ? null : (denyCode || 'risk_tuning_promotion_denied'),
      error_message: out?.promoted ? null : 'risk_tuning_promotion_denied',
      ext_json: JSON.stringify({
        op: 'promote_risk_tuning_profile',
        profile_id: String(req.profile_id || ''),
        active_profile_id: String(out?.active_profile_id || ''),
        previous_active_profile_id: String(out?.previous_active_profile_id || ''),
        rollback_triggered: !!out?.rollback_triggered,
      }),
    });
    if (out?.rollback_triggered) {
      db.appendAudit({
        event_type: 'memory.risk_tuning.rollback',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: requestId || null,
        capability: 'unknown',
        model_id: null,
        ok: true,
        ext_json: JSON.stringify({
          op: 'risk_tuning_rollback_from_promote',
          profile_id: String(req.profile_id || ''),
          active_profile_id: String(out?.active_profile_id || ''),
          deny_code: denyCode,
        }),
      });
    }

    callback(null, {
      promoted: !!out?.promoted,
      rollback_triggered: !!out?.rollback_triggered,
      active_profile_id: String(out?.active_profile_id || ''),
      previous_active_profile_id: String(out?.previous_active_profile_id || ''),
      deny_code: denyCode,
    });
  }

  function GetVoiceWakeProfile(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'supervisor.voice.denied',
        error_message: 'voice_wake_profile_get_denied',
        op: 'get_voice_wake_profile',
        client,
        request_id: null,
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          desired_wake_mode: String(req.desired_wake_mode || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = getVoiceWakeProfile(resolveRuntimeBaseDir(), String(req.desired_wake_mode || '').trim());
    } catch (e) {
      callback(new Error(String(e?.message || e || 'voice_wake_profile_get_failed')));
      return;
    }

    callback(null, {
      profile: makeProtoVoiceWakeProfile(out?.profile),
    });

    db.appendAudit({
      event_type: 'supervisor.voice.wake_profile_fetched',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        op: 'get_voice_wake_profile',
        desired_wake_mode: String(req.desired_wake_mode || ''),
        profile_id: String(out?.profile?.profile_id || ''),
      }),
    });
  }

  function SetVoiceWakeProfile(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'supervisor.voice.denied',
        error_message: 'voice_wake_profile_set_denied',
        op: 'set_voice_wake_profile',
        client,
        request_id: null,
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          profile_id: String(req?.profile?.profile_id || ''),
          wake_mode: String(req?.profile?.wake_mode || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = setVoiceWakeProfile(resolveRuntimeBaseDir(), req.profile || {}, client);
    } catch (e) {
      callback(new Error(String(e?.message || e || 'voice_wake_profile_set_failed')));
      return;
    }

    callback(null, {
      profile: makeProtoVoiceWakeProfile(out?.profile),
    });

    bus.emitHubEvent(bus.voiceWakeProfileChanged(out?.changed || {}));

    db.appendAudit({
      event_type: 'supervisor.voice.wake_profile_updated',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        op: 'set_voice_wake_profile',
        profile_id: String(out?.profile?.profile_id || ''),
        trigger_words: Array.isArray(out?.profile?.trigger_words) ? out.profile.trigger_words : [],
        updated_at_ms: Number(out?.profile?.updated_at_ms || 0),
      }),
    });
  }

  function IssueVoiceGrantChallenge(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'supervisor.voice.denied',
        error_message: 'voice_challenge_issue_denied',
        op: 'issue_voice_grant_challenge',
        client,
        request_id: String(req.request_id || '').trim(),
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          template_id: String(req.template_id || ''),
          risk_level: String(req.risk_level || ''),
          mobile_terminal_id: String(req.mobile_terminal_id || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.issueVoiceGrantChallenge({
        request_id: String(req.request_id || '').trim(),
        template_id: String(req.template_id || '').trim(),
        action_digest: String(req.action_digest || '').trim(),
        scope_digest: String(req.scope_digest || '').trim(),
        amount_digest: String(req.amount_digest || '').trim(),
        challenge_code: String(req.challenge_code || '').trim(),
        risk_level: String(req.risk_level || '').trim(),
        bound_device_id: String(req.bound_device_id || '').trim(),
        mobile_terminal_id: String(req.mobile_terminal_id || '').trim(),
        allow_voice_only: !!req.allow_voice_only,
        requires_mobile_confirm: req.requires_mobile_confirm,
        ttl_ms: Number(req.ttl_ms || 0),
        device_id,
        user_id,
        app_id,
        project_id,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'voice_challenge_issue_failed')));
      return;
    }

    const denyCode = String(out?.deny_code || '');
    const requestId = String(req.request_id || '').trim();
    db.appendAudit({
      event_type: out?.issued ? 'supervisor.voice.challenge_issued' : 'supervisor.voice.denied',
      created_at_ms: nowMs(),
      severity: out?.issued ? 'info' : 'warn',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: requestId || null,
      capability: 'unknown',
      model_id: null,
      ok: !!out?.issued,
      error_code: out?.issued ? null : (denyCode || 'voice_challenge_issue_denied'),
      error_message: out?.issued ? null : 'voice_challenge_issue_denied',
      ext_json: JSON.stringify({
        op: 'issue_voice_grant_challenge',
        challenge_id: String(out?.challenge?.challenge_id || ''),
        template_id: String(out?.challenge?.template_id || req.template_id || ''),
        risk_level: String(out?.challenge?.risk_level || req.risk_level || 'high'),
        requires_mobile_confirm: !!out?.challenge?.requires_mobile_confirm,
      }),
    });

    callback(null, {
      challenge: makeProtoVoiceGrantChallenge(out?.challenge),
    });
  }

  function VerifyVoiceGrantResponse(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'supervisor.voice.denied',
        error_message: 'voice_grant_verify_denied',
        op: 'verify_voice_grant_response',
        client,
        request_id: String(req.request_id || '').trim(),
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          challenge_id: String(req.challenge_id || ''),
          transcript_hash: String(req.transcript_hash || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.verifyVoiceGrantResponse({
        request_id: String(req.request_id || '').trim(),
        challenge_id: String(req.challenge_id || '').trim(),
        challenge_code: String(req.challenge_code || '').trim(),
        transcript: String(req.transcript || ''),
        transcript_hash: String(req.transcript_hash || '').trim(),
        semantic_match_score: Number(req.semantic_match_score || 0),
        parsed_action_digest: String(req.parsed_action_digest || '').trim(),
        parsed_scope_digest: String(req.parsed_scope_digest || '').trim(),
        parsed_amount_digest: String(req.parsed_amount_digest || '').trim(),
        verify_nonce: String(req.verify_nonce || '').trim(),
        bound_device_id: String(req.bound_device_id || '').trim(),
        mobile_confirmed: !!req.mobile_confirmed,
        device_id,
        user_id,
        app_id,
        project_id,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'voice_challenge_verify_failed')));
      return;
    }

    const requestId = String(req.request_id || '').trim();
    db.appendAudit({
      event_type: out?.verified ? 'supervisor.voice.verified' : 'supervisor.voice.denied',
      created_at_ms: nowMs(),
      severity: out?.verified ? 'info' : 'warn',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: requestId || null,
      capability: 'unknown',
      model_id: null,
      ok: !!out?.verified,
      error_code: out?.verified ? null : String(out?.deny_code || 'voice_verify_denied'),
      error_message: out?.verified ? null : 'voice_grant_verify_denied',
      ext_json: JSON.stringify({
        op: 'verify_voice_grant_response',
        challenge_id: String(out?.challenge_id || req.challenge_id || ''),
        transcript_hash: String(out?.transcript_hash || ''),
        semantic_match_score: Number(out?.semantic_match_score || 0),
        challenge_match: !!out?.challenge_match,
        device_binding_ok: !!out?.device_binding_ok,
        mobile_confirmed: !!out?.mobile_confirmed,
        deny_code: String(out?.deny_code || ''),
      }),
    });

    callback(null, {
      verified: !!out?.verified,
      decision: String(out?.decision || (out?.verified ? 'allow' : 'deny')),
      deny_code: String(out?.deny_code || ''),
      challenge_id: String(out?.challenge_id || req.challenge_id || ''),
      transcript_hash: String(out?.transcript_hash || ''),
      semantic_match_score: Number(out?.semantic_match_score || 0),
      challenge_match: !!out?.challenge_match,
      device_binding_ok: !!out?.device_binding_ok,
      mobile_confirmed: !!out?.mobile_confirmed,
    });
  }

  function RegisterAgentCapsule(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'agent.capsule.denied',
        error_message: 'agent_capsule_register_denied',
        op: 'register_agent_capsule',
        client,
        request_id,
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          capsule_id: String(req.capsule_id || ''),
          agent_name: String(req.agent_name || ''),
          agent_version: String(req.agent_version || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }
    let out;
    try {
      out = db.registerAgentCapsule({
        request_id,
        device_id,
        user_id,
        app_id,
        project_id,
        capsule_id: String(req.capsule_id || '').trim(),
        agent_name: String(req.agent_name || '').trim(),
        agent_version: String(req.agent_version || '').trim(),
        platform: String(req.platform || '').trim(),
        sha256: String(req.sha256 || '').trim(),
        signature: String(req.signature || '').trim(),
        sbom_hash: String(req.sbom_hash || '').trim(),
        manifest_payload: String(req.manifest_payload || '').trim(),
        sbom_payload: String(req.sbom_payload || '').trim(),
        allowed_egress: Array.isArray(req.allowed_egress)
          ? req.allowed_egress.map((item) => String(item || '').trim()).filter(Boolean)
          : [],
        risk_profile: String(req.risk_profile || '').trim(),
      });
    } catch {
      out = {
        registered: false,
        created: false,
        deny_code: 'runtime_error',
        capsule: null,
      };
    }
    const denyCode = String(out?.deny_code || '');
    try {
      db.appendAudit({
        event_type: out?.registered ? 'agent.capsule.registered' : 'agent.capsule.denied',
        created_at_ms: nowMs(),
        severity: out?.registered ? 'info' : 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: !!out?.registered,
        error_code: out?.registered ? null : (denyCode || 'capsule_register_denied'),
        error_message: out?.registered ? null : 'agent_capsule_register_denied',
        ext_json: JSON.stringify({
          op: 'register_agent_capsule',
          capsule_id: String(out?.capsule?.capsule_id || req.capsule_id || ''),
          created: !!out?.created,
          deny_code: denyCode,
          status: String(out?.capsule?.status || ''),
        }),
      });
    } catch {
      // keep fail-closed behavior
    }

    callback(null, {
      registered: !!out?.registered,
      created: !!out?.created,
      deny_code: denyCode,
      capsule: makeProtoAgentCapsule(out?.capsule),
    });
  }

  function VerifyAgentCapsule(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'agent.capsule.denied',
        error_message: 'agent_capsule_verify_denied',
        op: 'verify_agent_capsule',
        client,
        request_id,
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          capsule_id: String(req.capsule_id || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }
    let out;
    try {
      out = db.verifyAgentCapsule({
        request_id,
        capsule_id: String(req.capsule_id || '').trim(),
        device_id,
        user_id,
        app_id,
      });
    } catch {
      out = {
        verified: false,
        deny_code: 'runtime_error',
        verification_report_ref: '',
        capsule: null,
      };
    }
    const denyCode = String(out?.deny_code || '');
    try {
      db.appendAudit({
        event_type: out?.verified ? 'agent.capsule.verified' : 'agent.capsule.denied',
        created_at_ms: nowMs(),
        severity: out?.verified ? 'info' : 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: !!out?.verified,
        error_code: out?.verified ? null : (denyCode || 'capsule_verify_denied'),
        error_message: out?.verified ? null : 'agent_capsule_verify_denied',
        ext_json: JSON.stringify({
          op: 'verify_agent_capsule',
          capsule_id: String(out?.capsule?.capsule_id || req.capsule_id || ''),
          deny_code: denyCode,
          verification_report_ref: String(out?.verification_report_ref || ''),
          active_generation: Number(out?.capsule?.active_generation || 0),
        }),
      });
    } catch {
      // keep fail-closed behavior
    }

    callback(null, {
      verified: !!out?.verified,
      deny_code: denyCode,
      verification_report_ref: String(out?.verification_report_ref || ''),
      active_generation: Math.max(0, Number(out?.capsule?.active_generation || 0)),
      capsule: makeProtoAgentCapsule(out?.capsule),
    });
  }

  function ActivateAgentCapsule(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'agent.capsule.denied',
        error_message: 'agent_capsule_activate_denied',
        op: 'activate_agent_capsule',
        client,
        request_id,
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          capsule_id: String(req.capsule_id || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }
    let out;
    try {
      out = db.activateAgentCapsule({
        request_id,
        capsule_id: String(req.capsule_id || '').trim(),
        device_id,
        user_id,
        app_id,
      });
    } catch {
      out = {
        activated: false,
        idempotent: false,
        deny_code: 'runtime_error',
        capsule: null,
        runtime_state: null,
      };
    }
    const denyCode = String(out?.deny_code || '');
    const runtimeState = out?.runtime_state || {};
    try {
      db.appendAudit({
        event_type: out?.activated ? 'agent.capsule.activated' : 'agent.capsule.denied',
        created_at_ms: nowMs(),
        severity: out?.activated ? 'info' : 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: !!out?.activated,
        error_code: out?.activated ? null : (denyCode || 'capsule_activate_denied'),
        error_message: out?.activated ? null : 'agent_capsule_activate_denied',
        ext_json: JSON.stringify({
          op: 'activate_agent_capsule',
          capsule_id: String(out?.capsule?.capsule_id || req.capsule_id || ''),
          deny_code: denyCode,
          idempotent: !!out?.idempotent,
          active_generation: Number(out?.capsule?.active_generation || 0),
          previous_active_generation: Number(runtimeState.previous_active_generation || 0),
          previous_active_capsule_id: String(runtimeState.previous_active_capsule_id || ''),
        }),
      });
    } catch {
      // keep fail-closed behavior
    }

    callback(null, {
      activated: !!out?.activated,
      idempotent: !!out?.idempotent,
      deny_code: denyCode,
      capsule: makeProtoAgentCapsule(out?.capsule),
      active_generation: Math.max(0, Number(out?.capsule?.active_generation || 0)),
      previous_active_generation: Math.max(0, Number(runtimeState.previous_active_generation || 0)),
      previous_active_capsule_id: String(runtimeState.previous_active_capsule_id || ''),
    });
  }

  function AgentSessionOpen(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const agent_instance_id = String(req.agent_instance_id || '').trim();
    const agent_name = String(req.agent_name || '').trim();
    const agent_version = String(req.agent_version || '').trim();
    const gateway_provider = String(req.gateway_provider || '').trim();

    const openedAt = nowMs();
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'agent.session.denied',
        error_message: 'agent_session_open_denied',
        op: 'agent_session_open',
        client,
        request_id,
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          created: false,
          agent_instance_id,
          agent_name,
          agent_version,
          gateway_provider,
        },
      });
      callback(new Error(denyCode));
      return;
    }
    let out;
    try {
      out = db.openAgentSession({
        request_id,
        device_id,
        user_id,
        app_id,
        project_id,
        agent_instance_id,
        agent_name,
        agent_version,
        gateway_provider,
      });
    } catch {
      out = {
        opened: false,
        created: false,
        deny_code: 'runtime_error',
        session: null,
      };
    }

    const denyCode = String(out?.deny_code || '');
    try {
      db.appendAudit({
        event_type: out?.opened ? 'agent.session.opened' : 'agent.session.denied',
        created_at_ms: openedAt,
        severity: out?.opened ? 'info' : 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: out?.session?.session_id ? String(out.session.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: !!out?.opened,
        error_code: out?.opened ? null : (denyCode || 'session_open_failed'),
        error_message: out?.opened ? null : 'agent_session_open_denied',
        ext_json: JSON.stringify({
          op: 'agent_session_open',
          deny_code: denyCode,
          created: !!out?.created,
          agent_instance_id,
          agent_name,
          agent_version,
          gateway_provider,
        }),
      });
    } catch {
      // fail-closed response remains machine-readable even if audit write fails
    }

    callback(null, {
      opened: !!out?.opened,
      created: !!out?.created,
      session_id: String(out?.session?.session_id || ''),
      deny_code: denyCode,
      opened_at_ms: Math.max(0, Number(out?.session?.created_at_ms || openedAt)),
    });
  }

  function AgentToolRequest(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const session_id = String(req.session_id || '').trim();
    const agent_instance_id = String(req.agent_instance_id || '').trim();
    const tool_name = String(req.tool_name || '').trim();
    const tool_args_hash = String(req.tool_args_hash || '').trim();
    let sessionBinding = null;
    let sessionBindingLookupFailedClosed = false;
    try {
      sessionBinding = session_id && typeof db.getAgentSession === 'function'
        ? db.getAgentSession({
          session_id,
          device_id,
          user_id,
          app_id,
        })
        : null;
    } catch {
      sessionBinding = null;
      sessionBindingLookupFailedClosed = true;
    }
    if (sessionBindingLookupFailedClosed) {
      const denyCode = 'runtime_error';
      try {
        db.appendAudit({
          event_type: 'grant.denied',
          created_at_ms: nowMs(),
          severity: 'warn',
          device_id,
          user_id: user_id || null,
          app_id,
          project_id: project_id || null,
          session_id: session_id || null,
          request_id: request_id || null,
          capability: 'unknown',
          model_id: null,
          ok: false,
          error_code: denyCode,
          error_message: 'agent_tool_request_session_lookup_failed',
          ext_json: JSON.stringify({
            op: 'agent_tool_request',
            deny_code: denyCode,
            reason: 'session_binding_lookup_failed',
          }),
        });
      } catch {
        // keep fail-closed response machine-readable even if audit sink fails
      }
      callback(null, {
        accepted: false,
        tool_request_id: '',
        risk_tier: normalizeAgentRiskTier(req.risk_tier, 'high'),
        decision: 'deny',
        grant_id: '',
        deny_code: denyCode,
        expires_at_ms: 0,
      });
      return;
    }
    const bindingProjectId = String(sessionBinding?.project_id || project_id || '').trim();
    const sessionGatewayProvider = String(sessionBinding?.gateway_provider || '').trim();
    const auditProjectId = bindingProjectId || project_id;
    if (!trustedAutomationAllows(auth, {
      project_id: bindingProjectId,
      workspace_root: trustedAutomationScope.workspace_root,
    })) {
      const denyCode = capabilityDenyCode(auth);
      try {
        db.appendAudit({
          event_type: 'grant.denied',
          created_at_ms: nowMs(),
          severity: 'warn',
          device_id,
          user_id: user_id || null,
          app_id,
          project_id: auditProjectId || null,
          session_id: session_id || null,
          request_id: request_id || null,
          capability: 'unknown',
          model_id: null,
          ok: false,
          error_code: denyCode,
          error_message: 'agent_tool_request_trusted_automation_denied',
          ext_json: JSON.stringify({
            op: 'agent_tool_request',
            deny_code: denyCode,
            project_binding_checked: true,
          }),
        });
      } catch {
        // keep fail-closed response machine-readable even if audit sink fails
      }
      callback(null, {
        accepted: false,
        tool_request_id: '',
        risk_tier: normalizeAgentRiskTier(req.risk_tier, 'high'),
        decision: 'deny',
        grant_id: '',
        deny_code: denyCode,
        expires_at_ms: 0,
      });
      return;
    }
    const execArgv = normalizeExecutionArgv(req.exec_argv);
    const execArgvJson = execArgv.length > 0 ? JSON.stringify(execArgv) : '';
    const execCwd = resolveCanonicalExecutionCwd(req.exec_cwd);
    const approvalIdentityHash = execArgv.length > 0 && execCwd.ok
      ? computeApprovalIdentityHash({
        device_id,
        user_id,
        app_id,
        project_id: bindingProjectId,
        session_id,
        agent_instance_id,
        tool_name,
        tool_args_hash,
        exec_argv: execArgv,
        exec_cwd_canonical: execCwd.canonical,
      })
      : '';
    const required_grant_scope = String(req.required_grant_scope || '').trim();
    if (
      !request_id
      || !session_id
      || !agent_instance_id
      || !tool_name
      || !tool_args_hash
      || !execArgvJson
      || !execCwd.ok
      || !approvalIdentityHash
    ) {
      const bindingDenyCode = !execArgvJson || !execCwd.ok || !approvalIdentityHash
        ? (!execCwd.ok ? String(execCwd.deny_code || 'approval_binding_invalid') : 'approval_binding_invalid')
        : 'invalid_request';
      try {
        db.appendAudit({
          event_type: 'grant.denied',
          created_at_ms: nowMs(),
          severity: 'warn',
          device_id,
          user_id: user_id || null,
          app_id,
          project_id: auditProjectId || null,
          session_id: session_id || null,
          request_id: request_id || null,
          capability: 'unknown',
          model_id: null,
          ok: false,
          error_code: bindingDenyCode,
          error_message: 'agent_tool_request_invalid',
          ext_json: JSON.stringify({
            op: 'agent_tool_request',
            deny_code: bindingDenyCode,
            reason: 'missing request_id/session_id/agent_instance_id/tool_name/tool_args_hash/exec_argv/exec_cwd',
          }),
        });
      } catch {
        // keep invalid_request response machine-readable even if audit sink fails
      }
      callback(null, {
        accepted: false,
        tool_request_id: '',
        risk_tier: normalizeAgentRiskTier(req.risk_tier, 'high'),
        decision: 'deny',
        grant_id: '',
        deny_code: bindingDenyCode,
        expires_at_ms: 0,
      });
      return;
    }
    const risk_tier = classifyAgentRiskTier({
      tool_name,
      risk_tier: req.risk_tier,
      required_grant_scope,
    });
    const hintedRiskTier = parseAgentRiskTier(req.risk_tier);
    const riskFloorApplied = !!hintedRiskTier && agentRiskTierRank(risk_tier) > agentRiskTierRank(hintedRiskTier);

    let policy = null;
    let policyFailedClosed = false;
    try {
      if (typeof db.evaluateAgentToolPolicy === 'function') {
        policy = db.evaluateAgentToolPolicy({
          request_id,
          session_id,
          tool_name,
          risk_tier,
          required_grant_scope,
          client: {
            device_id,
            user_id,
            app_id,
            project_id: bindingProjectId,
          },
        });
      } else {
        policy = defaultAgentToolPolicy({ risk_tier, required_grant_scope });
      }
    } catch {
      policyFailedClosed = true;
      policy = {
        decision: 'deny',
        deny_code: 'gateway_fail_closed',
      };
    }

    let decision = normalizeAgentToolDecision(policy?.decision, policyFailedClosed ? 'deny' : 'pending');
    let denyCode = String(policy?.deny_code || '').trim();
    if (policyFailedClosed || !['pending', 'approve', 'deny', 'downgrade'].includes(decision)) {
      decision = 'deny';
      denyCode = 'gateway_fail_closed';
    } else if (!denyCode && decision === 'pending') {
      denyCode = 'grant_pending';
    } else if (!denyCode && decision === 'deny') {
      denyCode = 'policy_denied';
    } else if (!denyCode && decision === 'downgrade') {
      denyCode = 'downgrade_to_local';
    }

    let createOut;
    try {
      createOut = db.createAgentToolRequest({
        request_id,
        session_id,
        device_id,
        user_id,
        app_id,
        project_id: bindingProjectId,
        agent_instance_id,
        gateway_provider: sessionGatewayProvider,
        tool_name,
        tool_args_hash,
        approval_argv_json: execArgvJson,
        approval_cwd_input: execCwd.input,
        approval_cwd_canonical: execCwd.canonical,
        approval_identity_hash: approvalIdentityHash,
        required_grant_scope,
        risk_tier,
        policy_decision: decision,
        deny_code: denyCode,
        grant_ttl_ms: Number(policy?.grant_ttl_ms || 0),
        grant_decided_by: policyFailedClosed ? 'fail_closed' : 'policy_engine',
        grant_note: policyFailedClosed ? 'policy_gateway_failed' : '',
      });
    } catch {
      createOut = {
        accepted: false,
        created: false,
        deny_code: 'runtime_error',
        tool_request: null,
      };
    }

    const toolReq = createOut?.tool_request || null;
    const accepted = !!createOut?.accepted;
    let finalDecision = normalizeAgentToolDecision(toolReq?.policy_decision || decision, decision);
    let finalDenyCode = String(createOut?.deny_code || toolReq?.deny_code || denyCode || '');
    if (!accepted && finalDenyCode !== 'downgrade_to_local') finalDecision = 'deny';
    if (!finalDenyCode && finalDecision === 'pending') finalDenyCode = 'grant_pending';
    const grantId = String(toolReq?.grant_id || '');
    const grantExpiresAtMs = Math.max(0, Number(toolReq?.grant_expires_at_ms || 0));
    const requestedAtMs = nowMs();
    const baseExt = {
      op: 'agent_tool_request',
      session_id,
      tool_request_id: String(toolReq?.tool_request_id || ''),
      agent_instance_id,
      gateway_provider: String(toolReq?.gateway_provider || sessionGatewayProvider || ''),
      tool_name,
      tool_args_hash,
      exec_argv_hash: crypto.createHash('sha256').update(execArgvJson, 'utf8').digest('hex'),
      exec_cwd_canonical: execCwd.canonical,
      approval_identity_hash: approvalIdentityHash,
      risk_tier,
      risk_tier_hint: hintedRiskTier,
      risk_floor_applied: riskFloorApplied,
      required_grant_scope,
      decision: finalDecision,
      deny_code: finalDenyCode,
      grant_id: grantId,
      grant_expires_at_ms: grantExpiresAtMs,
      capability_token: buildAgentToolCapabilityTokenAudit(toolReq, { required: isHighRiskTier(risk_tier) }),
      policy_fail_closed: policyFailedClosed,
      ingress: true,
      risk_classified: true,
      policy_evaluated: true,
      grant_bound: finalDecision === 'approve' || finalDecision === 'pending',
    };

    try {
      db.appendAudit({
        event_type: 'agent.tool.requested',
        created_at_ms: requestedAtMs,
        severity: accepted ? 'info' : 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: auditProjectId || null,
        session_id: session_id || null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: accepted,
        error_code: accepted ? null : (finalDenyCode || 'tool_request_rejected'),
        error_message: accepted ? null : 'agent_tool_request_rejected',
        ext_json: JSON.stringify(baseExt),
      });
    } catch {
      // fail-closed response remains machine-readable even if audit write fails
    }

    const grantEventType = (!accepted || finalDecision === 'deny' || finalDecision === 'downgrade')
      ? 'grant.denied'
      : (finalDecision === 'pending'
      ? 'grant.pending'
      : 'grant.approved');
    try {
      db.appendAudit({
        event_type: grantEventType,
        created_at_ms: nowMs(),
        severity: finalDecision === 'approve' ? 'info' : 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: auditProjectId || null,
        session_id: session_id || null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: finalDecision === 'approve' || finalDecision === 'pending',
        error_code: finalDecision === 'approve' || finalDecision === 'pending'
          ? null
          : (finalDenyCode || 'grant_denied'),
        error_message: finalDecision === 'approve' || finalDecision === 'pending'
          ? null
          : 'grant_denied',
        ext_json: JSON.stringify(baseExt),
      });
    } catch {
      // fail-closed response remains machine-readable even if audit write fails
    }

    callback(null, {
      accepted,
      tool_request_id: String(toolReq?.tool_request_id || ''),
      risk_tier,
      decision: finalDecision,
      grant_id: grantId,
      deny_code: finalDenyCode,
      expires_at_ms: grantExpiresAtMs,
    });
  }

  function AgentToolGrantDecision(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const session_id = String(req.session_id || '').trim();
    const tool_request_id = String(req.tool_request_id || '').trim();
    const decision = normalizeAgentToolDecision(req.decision, 'deny');
    const ttl_ms = Math.max(0, Number(req.ttl_ms || 0));
    const approver_id = String(req.approver_id || '').trim();
    const note = String(req.note || '').trim();
    const deny_code = String(req.deny_code || '').trim();
    const existingToolReq = tool_request_id && typeof db.getAgentToolRequest === 'function'
      ? db.getAgentToolRequest({
        tool_request_id,
        session_id,
        device_id,
        user_id,
        app_id,
      })
      : null;
    const trustedAutomationProjectId = String(existingToolReq?.project_id || project_id || '').trim();
    if (!trustedAutomationAllows(auth, {
      project_id: trustedAutomationProjectId,
      workspace_root: trustedAutomationScope.workspace_root,
    })) {
      const denyCode = capabilityDenyCode(auth);
      callback(null, {
        applied: false,
        idempotent: false,
        tool_request_id,
        decision: 'deny',
        grant_id: '',
        deny_code: denyCode,
        expires_at_ms: 0,
      });
      return;
    }

    let out;
    try {
      out = db.decideAgentToolGrant({
        session_id,
        tool_request_id,
        device_id,
        user_id,
        app_id,
        decision,
        ttl_ms,
        approver_id,
        note,
        deny_code,
      });
    } catch {
      out = {
        applied: false,
        idempotent: false,
        deny_code: 'runtime_error',
        tool_request: null,
      };
    }

    const toolReq = out?.tool_request || null;
    const applied = !!out?.applied;
    let finalDecision = normalizeAgentToolDecision(toolReq?.policy_decision || decision, decision);
    const finalDenyCode = String(out?.deny_code || toolReq?.deny_code || '');
    if (!applied && finalDenyCode !== 'downgrade_to_local') finalDecision = 'deny';
    const grantId = String(toolReq?.grant_id || '');
    const grantExpiresAtMs = Math.max(0, Number(toolReq?.grant_expires_at_ms || 0));
    const idempotent = !!out?.idempotent;
    const auditProjectId = String(toolReq?.project_id || project_id || '').trim();

    const grantEventType = applied && finalDecision === 'approve' ? 'grant.approved' : 'grant.denied';
    try {
      db.appendAudit({
        event_type: grantEventType,
        created_at_ms: nowMs(),
        severity: finalDecision === 'approve' ? 'info' : 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: auditProjectId || null,
        session_id: session_id || null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: applied && finalDecision === 'approve',
        error_code: applied && finalDecision === 'approve'
          ? null
          : (finalDenyCode || (applied ? 'grant_denied' : 'grant_decision_failed')),
        error_message: applied && finalDecision === 'approve'
          ? null
          : 'agent_tool_grant_decision_denied',
        ext_json: JSON.stringify({
            op: 'agent_tool_grant_decision',
            tool_request_id,
            gateway_provider: String(toolReq?.gateway_provider || ''),
            decision: finalDecision,
            deny_code: finalDenyCode,
            grant_id: grantId,
            grant_expires_at_ms: grantExpiresAtMs,
            capability_token: buildAgentToolCapabilityTokenAudit(toolReq, { required: isHighRiskTier(toolReq?.risk_tier) }),
            idempotent,
            approver_id,
        }),
      });
    } catch {
      // fail-closed response remains machine-readable even if audit write fails
    }

    callback(null, {
      applied,
      idempotent,
      tool_request_id,
      decision: finalDecision,
      grant_id: grantId,
      deny_code: finalDenyCode,
      expires_at_ms: grantExpiresAtMs,
    });
  }

  function AgentToolExecute(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const session_id = String(req.session_id || '').trim();
    const tool_request_id = String(req.tool_request_id || '').trim();
    const tool_name = String(req.tool_name || '').trim();
    const tool_args_hash = String(req.tool_args_hash || '').trim();
    const grant_id = String(req.grant_id || '').trim();
    const execArgv = normalizeExecutionArgv(req.exec_argv);
    const execArgvJson = execArgv.length > 0 ? JSON.stringify(execArgv) : '';
    const execCwd = resolveCanonicalExecutionCwd(req.exec_cwd);
    let auditProjectId = project_id;

    if (!request_id || !session_id || !tool_request_id || !tool_name || !tool_args_hash || !execArgvJson || !execCwd.ok) {
      const bindingDenyCode = !execArgvJson || !execCwd.ok
        ? (!execCwd.ok ? String(execCwd.deny_code || 'approval_binding_invalid') : 'approval_binding_invalid')
        : 'invalid_request';
      try {
        db.appendAudit({
          event_type: 'agent.tool.executed',
          created_at_ms: nowMs(),
          severity: 'warn',
          device_id,
          user_id: user_id || null,
          app_id,
          project_id: project_id || null,
          session_id: session_id || null,
          request_id: request_id || null,
          capability: 'unknown',
          model_id: null,
          ok: false,
          error_code: bindingDenyCode,
          error_message: 'agent_tool_execute_invalid',
          ext_json: JSON.stringify({
            op: 'agent_tool_execute',
            tool_request_id,
            tool_name,
            tool_args_hash,
            deny_code: bindingDenyCode,
            reason: 'missing request_id/session_id/tool_request_id/tool_name/tool_args_hash/exec_argv/exec_cwd',
          }),
        });
      } catch {
        // keep invalid_request response machine-readable even if audit sink fails
      }
      callback(null, {
        executed: false,
        idempotent: false,
        execution_id: '',
        deny_code: bindingDenyCode,
        result_json: '',
        executed_at_ms: nowMs(),
      });
      return;
    }
    let trustedAutomationProjectId = String(project_id || '').trim();
    try {
      const existingToolReq = tool_request_id && typeof db.getAgentToolRequest === 'function'
        ? db.getAgentToolRequest({
          tool_request_id,
          session_id,
          device_id,
          user_id,
          app_id,
        })
        : null;
      trustedAutomationProjectId = String(existingToolReq?.project_id || trustedAutomationProjectId || '').trim();
    } catch {
      // ignore and fall back to request scope
    }
    if (!trustedAutomationAllows(auth, {
      project_id: trustedAutomationProjectId,
      workspace_root: trustedAutomationScope.workspace_root,
    })) {
      const denyCode = capabilityDenyCode(auth);
      callback(null, {
        executed: false,
        idempotent: false,
        execution_id: '',
        deny_code: denyCode,
        result_json: '',
        executed_at_ms: nowMs(),
      });
      return;
    }

    try {
      const existingExec = db.getAgentToolExecutionByIdempotency({
        request_id,
        session_id,
        device_id,
        user_id,
        app_id,
      });
      if (existingExec) {
        const replayTampered = (
          String(existingExec.tool_request_id || '') !== tool_request_id
          || String(existingExec.tool_name || '') !== tool_name
          || String(existingExec.tool_args_hash || '') !== tool_args_hash
          || String(existingExec.exec_argv_json || '') !== execArgvJson
          || String(existingExec.exec_cwd_canonical || '') !== execCwd.canonical
          || String(existingExec.grant_id || '') !== grant_id
        );
        if (replayTampered) {
          const replayDenyCode = 'request_tampered';
          auditProjectId = String(existingExec.project_id || auditProjectId || '').trim();
          try {
            db.appendAudit({
              event_type: 'agent.tool.executed',
              created_at_ms: nowMs(),
              severity: 'warn',
              device_id,
              user_id: user_id || null,
              app_id,
              project_id: auditProjectId || null,
              session_id: session_id || null,
              request_id: request_id || null,
              capability: 'unknown',
              model_id: null,
              ok: false,
              error_code: replayDenyCode,
              error_message: 'agent_tool_execute_replay_tampered',
              ext_json: JSON.stringify({
                op: 'agent_tool_execute',
                replay_tampered: true,
                execution_id: String(existingExec.execution_id || ''),
                tool_request_id,
                tool_name,
                tool_args_hash,
                deny_code: replayDenyCode,
              }),
            });
          } catch {
            // keep fail-closed response machine-readable if audit sink fails
          }
          callback(null, {
            executed: false,
            idempotent: false,
            execution_id: String(existingExec.execution_id || ''),
            deny_code: replayDenyCode,
            result_json: '',
            executed_at_ms: nowMs(),
          });
          return;
        }
        callback(null, {
          executed: String(existingExec.status || '') === 'executed',
          idempotent: true,
          execution_id: String(existingExec.execution_id || ''),
          deny_code: String(existingExec.deny_code || ''),
          result_json: String(existingExec.result_json || ''),
          executed_at_ms: Math.max(0, Number(existingExec.updated_at_ms || existingExec.created_at_ms || nowMs())),
        });
        return;
      }

      let toolReq = db.getAgentToolRequest({
        tool_request_id,
        session_id,
        device_id,
        user_id,
        app_id,
      });
      auditProjectId = String(toolReq?.project_id || project_id || '').trim();

      let denyCode = '';
      if (!toolReq) {
        denyCode = 'tool_request_not_found';
      } else if (
        !String(toolReq.approval_identity_hash || '')
        || !String(toolReq.approval_argv_json || '')
        || !String(toolReq.approval_cwd_canonical || '')
      ) {
        denyCode = 'approval_binding_missing';
      } else {
        const expectedStoredArgv = parseExecutionArgvJson(toolReq.approval_argv_json);
        const expectedStoredHash = computeApprovalIdentityHash({
          device_id,
          user_id,
          app_id,
          project_id: String(toolReq.project_id || ''),
          session_id,
          agent_instance_id: String(toolReq.agent_instance_id || ''),
          tool_name: String(toolReq.tool_name || ''),
          tool_args_hash: String(toolReq.tool_args_hash || ''),
          exec_argv: expectedStoredArgv,
          exec_cwd_canonical: String(toolReq.approval_cwd_canonical || ''),
        });
        if (!expectedStoredHash || expectedStoredHash !== String(toolReq.approval_identity_hash || '')) {
          denyCode = 'approval_binding_corrupt';
        } else if (String(toolReq.tool_name || '') !== tool_name || String(toolReq.tool_args_hash || '') !== tool_args_hash) {
          denyCode = 'request_tampered';
        } else if (String(toolReq.approval_argv_json || '') !== execArgvJson) {
          denyCode = 'approval_argv_mismatch';
        } else if (String(toolReq.approval_cwd_canonical || '') !== execCwd.canonical) {
          denyCode = 'approval_cwd_mismatch';
        } else {
          const incomingHash = computeApprovalIdentityHash({
            device_id,
            user_id,
            app_id,
            project_id: String(toolReq.project_id || ''),
            session_id,
            agent_instance_id: String(toolReq.agent_instance_id || ''),
            tool_name,
            tool_args_hash,
            exec_argv: execArgv,
            exec_cwd_canonical: execCwd.canonical,
          });
          if (!incomingHash || incomingHash !== String(toolReq.approval_identity_hash || '')) {
            denyCode = 'approval_identity_mismatch';
          }
        }
      }
      if (!denyCode) {
        const hasCapabilityTokenContract = isHighRiskTier(toolReq.risk_tier)
          && (
            String(toolReq.capability_token_kind || '') === 'one_time'
            || !!String(toolReq.capability_token_id || '')
            || !!String(toolReq.capability_token_state || '')
          );
        if (hasCapabilityTokenContract) {
          const consumeOut = db.consumeAgentToolCapabilityToken({
            request_id,
            session_id,
            tool_request_id,
            device_id,
            user_id,
            app_id,
            grant_id,
          });
          if (consumeOut?.tool_request) {
            toolReq = consumeOut.tool_request;
            auditProjectId = String(toolReq?.project_id || auditProjectId || '').trim();
          }
          if (!consumeOut?.consumed) {
            denyCode = String(consumeOut?.deny_code || 'grant_missing');
          }
        } else if (toolReq.policy_decision === 'deny' || toolReq.policy_decision === 'downgrade') {
          denyCode = String(toolReq.deny_code || (toolReq.policy_decision === 'downgrade' ? 'downgrade_to_local' : 'policy_denied'));
        } else if (isHighRiskTier(toolReq.risk_tier)) {
          if (!grant_id || !String(toolReq.grant_id || '')) {
            denyCode = 'grant_missing';
          } else if (grant_id !== String(toolReq.grant_id || '')) {
            denyCode = 'request_tampered';
          } else if (Number(toolReq.grant_expires_at_ms || 0) <= nowMs()) {
            denyCode = 'grant_expired';
          }
        } else if (grant_id && String(toolReq.grant_id || '') && grant_id !== String(toolReq.grant_id || '')) {
          denyCode = 'request_tampered';
        }
      }

      const capabilityTokenAudit = buildAgentToolCapabilityTokenAudit(toolReq, { required: isHighRiskTier(toolReq?.risk_tier) });
      const skillRunnerTool = isSkillRunnerToolName(tool_name);
      let skillExecutionBinding = null;
      let skillExecutionGate = null;
      if (!denyCode && skillRunnerTool) {
        skillExecutionBinding = extractSkillExecutionGateBinding(execArgv);
        const packageSha = String(skillExecutionBinding.package_sha256 || '');
        if (!packageSha) {
          denyCode = 'request_tampered';
          skillExecutionGate = {
            allowed: false,
            deny_code: 'missing_package_sha256',
            detail: {
              reason: 'skill_execution_package_sha_missing',
            },
          };
        } else {
          try {
            skillExecutionGate = evaluateSkillExecutionGate(resolveRuntimeBaseDir(), {
              packageSha256: packageSha,
              skillId: String(skillExecutionBinding.skill_id || ''),
            });
          } catch {
            skillExecutionGate = {
              allowed: false,
              deny_code: 'runtime_error',
              detail: {
                reason: 'skill_execution_gate_runtime_error',
              },
            };
          }
          if (!skillExecutionGate || !skillExecutionGate.allowed) {
            denyCode = String(skillExecutionGate?.deny_code || 'runtime_error');
          }
        }
      }

      const execResult = denyCode
        ? null
        : {
            ok: true,
            tool_request_id,
            grant_id: String(toolReq?.grant_id || grant_id || ''),
            executed_by: 'hub_grant_chain',
            skill_execution_gate_checked: skillRunnerTool,
          };
      const executionBindingHash = String(toolReq?.approval_identity_hash || '')
        || computeApprovalIdentityHash({
          device_id,
          user_id,
          app_id,
          project_id: String(toolReq?.project_id || project_id || ''),
          session_id,
          agent_instance_id: String(toolReq?.agent_instance_id || ''),
          tool_name,
          tool_args_hash,
          exec_argv: execArgv,
          exec_cwd_canonical: execCwd.canonical,
        });
      const executionOut = db.recordAgentToolExecution({
        request_id,
        session_id,
        tool_request_id,
        device_id,
        user_id,
        app_id,
        project_id: auditProjectId,
        grant_id: String(toolReq?.grant_id || grant_id || ''),
        gateway_provider: String(toolReq?.gateway_provider || ''),
        tool_name,
        tool_args_hash,
        exec_argv_json: execArgvJson,
        exec_cwd_input: execCwd.input,
        exec_cwd_canonical: execCwd.canonical,
        approval_identity_hash: executionBindingHash,
        status: denyCode ? 'denied' : 'executed',
        deny_code: denyCode,
        result_json: execResult,
      });
      const execution = executionOut?.execution || null;
      const executed = !denyCode && String(execution?.status || '') === 'executed';

      try {
        db.appendAudit({
          event_type: 'agent.tool.executed',
          created_at_ms: nowMs(),
          severity: executed ? 'info' : 'warn',
          device_id,
          user_id: user_id || null,
          app_id,
          project_id: auditProjectId || null,
          session_id: session_id || null,
          request_id: request_id || null,
          capability: 'unknown',
          model_id: null,
          ok: executed,
          error_code: executed ? null : (denyCode || 'execute_denied'),
          error_message: executed ? null : 'agent_tool_execute_denied',
          ext_json: JSON.stringify({
            op: 'agent_tool_execute',
            tool_request_id,
            gateway_provider: String(toolReq?.gateway_provider || ''),
            grant_id: String(toolReq?.grant_id || grant_id || ''),
            requested_grant_id: grant_id,
            tool_name,
            tool_args_hash,
            exec_argv_hash: crypto.createHash('sha256').update(execArgvJson, 'utf8').digest('hex'),
            exec_cwd_canonical: execCwd.canonical,
            risk_tier: String(toolReq?.risk_tier || ''),
            policy_decision: String(toolReq?.policy_decision || ''),
            capability_token: capabilityTokenAudit,
            deny_code: denyCode,
            chain: 'ingress->risk_classify->policy->capability_token->execute->audit',
            skill_execution_gate_checked: skillRunnerTool,
            skill_execution_gate_binding: skillExecutionBinding ? compactObject({
              package_sha256: String(skillExecutionBinding.package_sha256 || ''),
              package_sha256_source: String(skillExecutionBinding.package_sha256_source || ''),
              skill_id: String(skillExecutionBinding.skill_id || ''),
              skill_id_source: String(skillExecutionBinding.skill_id_source || ''),
            }) : null,
            skill_execution_gate: skillExecutionGate ? compactObject({
              allowed: skillExecutionGate.allowed === true,
              deny_code: String(skillExecutionGate.deny_code || ''),
              detail: skillExecutionGate.detail && typeof skillExecutionGate.detail === 'object'
                ? skillExecutionGate.detail
                : null,
            }) : null,
          }),
        });
      } catch {
        // fail-closed response remains machine-readable even if audit write fails
      }

      callback(null, {
        executed,
        idempotent: !executionOut?.created,
        execution_id: String(execution?.execution_id || ''),
        deny_code: denyCode,
        result_json: String(execution?.result_json || ''),
        executed_at_ms: Math.max(0, Number(execution?.updated_at_ms || execution?.created_at_ms || nowMs())),
      });
      return;
    } catch {
      try {
        db.appendAudit({
          event_type: 'agent.tool.executed',
          created_at_ms: nowMs(),
          severity: 'warn',
          device_id,
          user_id: user_id || null,
          app_id,
          project_id: auditProjectId || null,
          session_id: session_id || null,
          request_id: request_id || null,
          capability: 'unknown',
          model_id: null,
          ok: false,
          error_code: 'runtime_error',
          error_message: 'agent_tool_execute_runtime_error',
          ext_json: JSON.stringify({
            op: 'agent_tool_execute',
            tool_request_id,
            tool_name,
            deny_code: 'runtime_error',
          }),
        });
      } catch {
        // ignore
      }
      callback(null, {
        executed: false,
        idempotent: false,
        execution_id: '',
        deny_code: 'runtime_error',
        result_json: '',
        executed_at_ms: nowMs(),
      });
    }
  }

  function appendPaymentAudit({
    event_type,
    client,
    request_id,
    project_id,
    intent_id,
    ok,
    deny_code,
    error_message,
    ext,
  } = {}) {
    const actor = client && typeof client === 'object' ? client : {};
    db.appendAudit({
      event_type: String(event_type || 'payment.event'),
      created_at_ms: nowMs(),
      severity: ok ? 'info' : 'warn',
      device_id: String(actor.device_id || ''),
      user_id: actor.user_id ? String(actor.user_id) : null,
      app_id: String(actor.app_id || ''),
      project_id: project_id ? String(project_id) : (actor.project_id ? String(actor.project_id) : null),
      session_id: actor.session_id ? String(actor.session_id) : null,
      request_id: request_id ? String(request_id) : null,
      capability: 'unknown',
      model_id: null,
      ok: !!ok,
      error_code: deny_code ? String(deny_code) : null,
      error_message: deny_code ? String(error_message || 'payment_denied') : null,
      ext_json: JSON.stringify({
        intent_id: intent_id ? String(intent_id) : '',
        ...(ext && typeof ext === 'object' ? ext : {}),
      }),
    });
  }

  function appendPaymentExpiredAudits({ expiredRows, client, request_id, op }) {
    const rows = Array.isArray(expiredRows) ? expiredRows : [];
    for (const row of rows) {
      const parsed = makeProtoPaymentIntent(row);
      const parsedClient = parsed?.client && typeof parsed.client === 'object' ? parsed.client : {};
      const actor = {
        device_id: String(parsedClient.device_id || client?.device_id || ''),
        user_id: String(parsedClient.user_id || client?.user_id || ''),
        app_id: String(parsedClient.app_id || client?.app_id || ''),
        project_id: String(parsedClient.project_id || client?.project_id || ''),
        session_id: String(parsedClient.session_id || client?.session_id || ''),
      };
      appendPaymentAudit({
        event_type: 'payment.expired',
        client: actor,
        request_id,
        project_id: String(actor.project_id || ''),
        intent_id: String(parsed?.intent_id || ''),
        ok: true,
        deny_code: '',
        ext: {
          op: String(op || ''),
          status: String(parsed?.status || 'expired'),
          expires_at_ms: Number(parsed?.expires_at_ms || 0),
          challenge_expires_at_ms: Number(parsed?.challenge_expires_at_ms || 0),
        },
      });
    }
  }

  function appendPaymentCompensatedAudits({ compensatedRows, op }) {
    const rows = Array.isArray(compensatedRows) ? compensatedRows : [];
    for (const row of rows) {
      const parsed = makeProtoPaymentIntent(row);
      const parsedClient = parsed?.client && typeof parsed.client === 'object' ? parsed.client : {};
      appendPaymentAudit({
        event_type: 'payment.aborted',
        client: parsedClient,
        request_id: '',
        project_id: String(parsedClient.project_id || ''),
        intent_id: String(parsed?.intent_id || ''),
        ok: true,
        deny_code: '',
        ext: {
          op: String(op || 'payment_receipt_compensated'),
          status: String(parsed?.status || ''),
          receipt_delivery_state: String(parsed?.receipt_delivery_state || ''),
          receipt_compensation_reason: String(parsed?.receipt_compensation_reason || ''),
          receipt_compensation_due_at_ms: Number(parsed?.receipt_compensation_due_at_ms || 0),
          receipt_compensated_at_ms: Number(parsed?.receipt_compensated_at_ms || 0),
        },
      });
    }
  }

  function CreatePaymentIntent(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const amount_minor = Math.floor(Number(req.amount_minor || 0));
    const currency = String(req.currency || '').trim().toUpperCase();
    const merchant_id = String(req.merchant_id || '').trim();
    const source_terminal_id = String(req.source_terminal_id || '').trim();
    const allowed_mobile_terminal_id = String(req.allowed_mobile_terminal_id || '').trim();
    const expected_photo_hash = String(req.expected_photo_hash || '').trim();
    const expected_geo_hash = String(req.expected_geo_hash || '').trim();
    const expected_qr_payload_hash = String(req.expected_qr_payload_hash || '').trim();
    const ttl_ms = Number(req.ttl_ms || 0);
    const challenge_ttl_ms = Number(req.challenge_ttl_ms || 0);
    const created_at_ms = Math.max(0, Number(req.created_at_ms || 0));

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendPaymentAudit({
        event_type: 'payment.intent.created',
        client,
        request_id,
        project_id: project_id || null,
        intent_id: '',
        ok: false,
        deny_code: denyCode,
        error_message: 'payment_intent_create_rejected',
        ext: {
          op: 'create_payment_intent',
          created: false,
          amount_minor,
          currency,
          merchant_id,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.createPaymentIntent({
        request_id,
        device_id,
        user_id,
        app_id,
        project_id,
        amount_minor,
        currency,
        merchant_id,
        source_terminal_id,
        allowed_mobile_terminal_id,
        expected_photo_hash,
        expected_geo_hash,
        expected_qr_payload_hash,
        ttl_ms,
        challenge_ttl_ms,
        created_at_ms,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'payment_intent_create_failed')));
      return;
    }

    const expiredRows = Array.isArray(out?.expired)
      ? out.expired
      : (Array.isArray(out?.detail?.expired) ? out.detail.expired : []);
    appendPaymentExpiredAudits({ expiredRows, client, request_id, op: 'create_payment_intent' });

    const intent = makeProtoPaymentIntent(out?.intent);
    const accepted = !!out?.accepted;
    const created = !!out?.created;
    const deny_code = accepted ? '' : String(out?.deny_code || 'invalid_request');
    appendPaymentAudit({
      event_type: 'payment.intent.created',
      client,
      request_id,
      project_id: String(intent?.client?.project_id || project_id || ''),
      intent_id: String(intent?.intent_id || ''),
      ok: accepted,
      deny_code,
      error_message: 'payment_intent_create_rejected',
      ext: {
        op: 'create_payment_intent',
        created,
        amount_minor,
        currency,
        merchant_id,
      },
    });

    callback(null, {
      accepted,
      created,
      deny_code,
      intent,
    });
  }

  function AttachPaymentEvidence(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const intent_id = String(req.intent_id || '').trim();
    const evidence = req.evidence && typeof req.evidence === 'object' ? req.evidence : {};
    const photo_hash = String(evidence.photo_hash || '').trim();
    const price_amount_minor = Math.floor(Number(evidence.price_amount_minor || 0));
    const currency = String(evidence.currency || '').trim().toUpperCase();
    const merchant_id = String(evidence.merchant_id || '').trim();
    const geo_hash = String(evidence.geo_hash || '').trim();
    const qr_payload_hash = String(evidence.qr_payload_hash || '').trim();
    const nonce = String(evidence.nonce || '').trim();
    const captured_at_ms = Math.max(0, Number(evidence.captured_at_ms || 0));
    const device_signature = String(evidence.device_signature || '').trim();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendPaymentAudit({
        event_type: 'payment.evidence.verified',
        client,
        request_id,
        project_id: project_id || null,
        intent_id,
        ok: false,
        deny_code: denyCode,
        error_message: 'payment_evidence_rejected',
        ext: {
          op: 'attach_payment_evidence',
          price_amount_minor,
          currency,
          merchant_id,
          nonce,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.attachPaymentEvidence({
        request_id,
        device_id,
        user_id,
        app_id,
        project_id,
        intent_id,
        evidence: {
          photo_hash,
          price_amount_minor,
          currency,
          merchant_id,
          geo_hash,
          qr_payload_hash,
          nonce,
          captured_at_ms,
          device_signature,
        },
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'payment_evidence_attach_failed')));
      return;
    }

    const expiredRows = Array.isArray(out?.expired)
      ? out.expired
      : (Array.isArray(out?.detail?.expired) ? out.detail.expired : []);
    appendPaymentExpiredAudits({ expiredRows, client, request_id, op: 'attach_payment_evidence' });

    const intent = makeProtoPaymentIntent(out?.intent || out?.detail?.intent);
    const accepted = !!out?.accepted;
    const deny_code = accepted ? '' : String(out?.deny_code || 'payment_evidence_rejected');
    appendPaymentAudit({
      event_type: 'payment.evidence.verified',
      client,
      request_id,
      project_id: String(intent?.client?.project_id || project_id || ''),
      intent_id: String(intent?.intent_id || intent_id || ''),
      ok: accepted,
      deny_code,
      error_message: 'payment_evidence_rejected',
      ext: {
        op: 'attach_payment_evidence',
        price_amount_minor,
        currency,
        merchant_id,
        nonce,
        signature_scheme: String(out?.signature_scheme || out?.detail?.signature_scheme || ''),
      },
    });

    callback(null, {
      accepted,
      deny_code,
      intent,
    });
  }

  function IssuePaymentChallenge(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const intent_id = String(req.intent_id || '').trim();
    const mobile_terminal_id = String(req.mobile_terminal_id || '').trim();
    const challenge_nonce = String(req.challenge_nonce || '').trim();
    const issued_at_ms = Math.max(0, Number(req.issued_at_ms || 0));

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendPaymentAudit({
        event_type: 'payment.challenge.issued',
        client,
        request_id,
        project_id: project_id || null,
        intent_id,
        ok: false,
        deny_code: denyCode,
        error_message: 'payment_challenge_rejected',
        ext: {
          op: 'issue_payment_challenge',
          mobile_terminal_id,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.issuePaymentChallenge({
        request_id,
        device_id,
        user_id,
        app_id,
        project_id,
        intent_id,
        mobile_terminal_id,
        challenge_nonce,
        issued_at_ms,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'payment_challenge_issue_failed')));
      return;
    }

    const expiredRows = Array.isArray(out?.expired)
      ? out.expired
      : (Array.isArray(out?.detail?.expired) ? out.detail.expired : []);
    appendPaymentExpiredAudits({ expiredRows, client, request_id, op: 'issue_payment_challenge' });

    const intent = makeProtoPaymentIntent(out?.intent || out?.detail?.intent);
    const issued = !!out?.issued;
    const deny_code = issued ? '' : String(out?.deny_code || 'payment_challenge_rejected');
    appendPaymentAudit({
      event_type: 'payment.challenge.issued',
      client,
      request_id,
      project_id: String(intent?.client?.project_id || project_id || ''),
      intent_id: String(intent?.intent_id || intent_id || ''),
      ok: issued,
      deny_code,
      error_message: 'payment_challenge_rejected',
      ext: {
        op: 'issue_payment_challenge',
        mobile_terminal_id,
        challenge_id: String(out?.challenge_id || ''),
        expires_at_ms: Number(out?.expires_at_ms || 0),
      },
    });

    callback(null, {
      issued,
      deny_code,
      challenge_id: String(out?.challenge_id || ''),
      challenge_nonce: String(out?.challenge_nonce || ''),
      expires_at_ms: Math.max(0, Number(out?.expires_at_ms || 0)),
      intent,
    });
  }

  function ConfirmPaymentIntent(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const intent_id = String(req.intent_id || '').trim();
    const challenge_id = String(req.challenge_id || '').trim();
    const mobile_terminal_id = String(req.mobile_terminal_id || '').trim();
    const auth_factor = String(req.auth_factor || '').trim();
    const confirm_nonce = String(req.confirm_nonce || '').trim();
    const confirmed_at_ms = Math.max(0, Number(req.confirmed_at_ms || 0));

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendPaymentAudit({
        event_type: 'payment.confirmed',
        client,
        request_id,
        project_id: project_id || null,
        intent_id,
        ok: false,
        deny_code: denyCode,
        error_message: 'payment_confirm_rejected',
        ext: {
          op: 'confirm_payment_intent',
          challenge_id,
          mobile_terminal_id,
          auth_factor: auth_factor || 'tap_only',
          idempotent: false,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.confirmPaymentIntent({
        request_id,
        device_id,
        user_id,
        app_id,
        project_id,
        intent_id,
        challenge_id,
        mobile_terminal_id,
        auth_factor,
        confirm_nonce,
        confirmed_at_ms,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'payment_confirm_failed')));
      return;
    }

    const expiredRows = Array.isArray(out?.expired)
      ? out.expired
      : (Array.isArray(out?.detail?.expired) ? out.detail.expired : []);
    appendPaymentExpiredAudits({ expiredRows, client, request_id, op: 'confirm_payment_intent' });

    const intent = makeProtoPaymentIntent(out?.intent || out?.detail?.intent);
    const committed = !!out?.committed;
    const idempotent = !!out?.idempotent;
    const deny_code = committed ? '' : String(out?.deny_code || 'payment_confirm_rejected');
    appendPaymentAudit({
      event_type: 'payment.confirmed',
      client,
      request_id,
      project_id: String(intent?.client?.project_id || project_id || ''),
      intent_id: String(intent?.intent_id || intent_id || ''),
      ok: committed,
      deny_code,
      error_message: 'payment_confirm_rejected',
      ext: {
        op: 'confirm_payment_intent',
        challenge_id,
        mobile_terminal_id,
        auth_factor: auth_factor || 'tap_only',
        idempotent,
        status: String(intent?.status || ''),
        receipt_delivery_state: String(intent?.receipt_delivery_state || ''),
        receipt_commit_deadline_at_ms: Number(intent?.receipt_commit_deadline_at_ms || 0),
      },
    });

    callback(null, {
      committed,
      idempotent,
      deny_code,
      intent,
    });
  }

  function AbortPaymentIntent(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const request_id = String(req.request_id || '').trim();
    const intent_id = String(req.intent_id || '').trim();
    const reason = String(req.reason || '').trim();
    const aborted_at_ms = Math.max(0, Number(req.aborted_at_ms || 0));

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendPaymentAudit({
        event_type: 'payment.aborted',
        client,
        request_id,
        project_id: project_id || null,
        intent_id,
        ok: false,
        deny_code: denyCode,
        error_message: 'payment_abort_rejected',
        ext: {
          op: 'abort_payment_intent',
          reason,
          idempotent: false,
          compensation_pending: false,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.abortPaymentIntent({
        request_id,
        device_id,
        user_id,
        app_id,
        project_id,
        intent_id,
        reason,
        aborted_at_ms,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'payment_abort_failed')));
      return;
    }

    const expiredRows = Array.isArray(out?.expired)
      ? out.expired
      : (Array.isArray(out?.detail?.expired) ? out.detail.expired : []);
    appendPaymentExpiredAudits({ expiredRows, client, request_id, op: 'abort_payment_intent' });

    const intent = makeProtoPaymentIntent(out?.intent || out?.detail?.intent);
    const aborted = !!out?.aborted;
    const idempotent = !!out?.idempotent;
    const deny_code = aborted ? '' : String(out?.deny_code || 'payment_abort_rejected');
    const compensation_pending = aborted
      && String(intent?.status || '') === 'committed'
      && String(intent?.receipt_delivery_state || '') === 'undo_pending';
    appendPaymentAudit({
      event_type: 'payment.aborted',
      client,
      request_id,
      project_id: String(intent?.client?.project_id || project_id || ''),
      intent_id: String(intent?.intent_id || intent_id || ''),
      ok: aborted,
      deny_code,
      error_message: 'payment_abort_rejected',
      ext: {
        op: 'abort_payment_intent',
        reason,
        idempotent,
        compensation_pending,
        status: String(intent?.status || ''),
        receipt_delivery_state: String(intent?.receipt_delivery_state || ''),
        receipt_compensation_due_at_ms: Number(intent?.receipt_compensation_due_at_ms || 0),
      },
    });

    callback(null, {
      aborted,
      idempotent,
      deny_code,
      intent,
      compensation_pending,
    });
  }

  function ProjectHeartbeat(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const request_id = String(req.request_id || '').trim();
    const heartbeat = req.heartbeat && typeof req.heartbeat === 'object' ? req.heartbeat : {};
    const root_project_id = String(heartbeat.root_project_id || '').trim();
    const parent_project_id = String(heartbeat.parent_project_id || '').trim();
    const project_id = String(heartbeat.project_id || '').trim();
    const queue_depth = Math.max(0, Math.floor(Number(heartbeat.queue_depth || 0)));
    const oldest_wait_ms = Math.max(0, Math.floor(Number(heartbeat.oldest_wait_ms || 0)));
    const blocked_reason = Array.isArray(heartbeat.blocked_reason)
      ? heartbeat.blocked_reason.map((item) => String(item || '').trim()).filter(Boolean)
      : [];
    const next_actions = Array.isArray(heartbeat.next_actions)
      ? heartbeat.next_actions.map((item) => String(item || '').trim()).filter(Boolean)
      : [];
    const risk_tier = String(heartbeat.risk_tier || '').trim();
    const heartbeat_seq = Math.max(0, Math.floor(Number(heartbeat.heartbeat_seq || 0)));
    const sent_at_ms = Math.max(0, Number(heartbeat.sent_at_ms || 0));
    const trustedAutomationScope = trustedAutomationScopeWithProject(
      trustedAutomationScopeFromRequest(req, client),
      root_project_id,
      project_id,
    );
    const now = nowMs();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!root_project_id || !project_id || heartbeat_seq <= 0) {
      db.appendAudit({
        event_type: 'project.heartbeat.rejected',
        created_at_ms: now,
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: 'invalid_request',
        error_message: 'project_heartbeat_invalid_request',
        ext_json: JSON.stringify({
          op: 'project_heartbeat',
          deny_code: 'invalid_request',
          reason: 'missing heartbeat.root_project_id/project_id/heartbeat_seq',
        }),
      });
      callback(null, {
        accepted: false,
        created: false,
        deny_code: 'invalid_request',
      });
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendProjectRejectAudit({
        event_type: 'project.heartbeat.rejected',
        error_message: 'project_heartbeat_rejected',
        op: 'project_heartbeat',
        client,
        request_id,
        project_id: project_id || root_project_id || null,
        deny_code: denyCode,
        ext: {
          root_project_id,
          parent_project_id,
          project_id,
          heartbeat_seq,
          queue_depth,
          oldest_wait_ms,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.upsertProjectHeartbeat({
        request_id,
        device_id,
        user_id,
        app_id,
        root_project_id,
        parent_project_id,
        project_id,
        queue_depth,
        oldest_wait_ms,
        blocked_reason,
        next_actions,
        risk_tier,
        heartbeat_seq,
        sent_at_ms: sent_at_ms || now,
        received_at_ms: now,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'project_heartbeat_failed')));
      return;
    }

    if (!out?.accepted) {
      db.appendAudit({
        event_type: 'project.heartbeat.rejected',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: String(out?.deny_code || 'heartbeat_rejected'),
        error_message: 'project_heartbeat_rejected',
        ext_json: JSON.stringify({
          op: 'project_heartbeat',
          root_project_id,
          parent_project_id,
          project_id,
          heartbeat_seq,
          queue_depth,
          oldest_wait_ms,
          deny_code: String(out?.deny_code || 'heartbeat_rejected'),
        }),
      });
      callback(null, {
        accepted: false,
        created: false,
        deny_code: String(out?.deny_code || 'heartbeat_rejected'),
      });
      return;
    }

    const heartbeatOut = makeProtoProjectHeartbeat(out?.heartbeat);
    db.appendAudit({
      event_type: 'project.heartbeat.received',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: String(heartbeatOut?.project_id || project_id || ''),
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: request_id || null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        op: 'project_heartbeat',
        created: !!out?.created,
        root_project_id: String(heartbeatOut?.root_project_id || ''),
        parent_project_id: String(heartbeatOut?.parent_project_id || ''),
        project_id: String(heartbeatOut?.project_id || ''),
        queue_depth: Number(heartbeatOut?.queue_depth || 0),
        oldest_wait_ms: Number(heartbeatOut?.oldest_wait_ms || 0),
        risk_tier: String(heartbeatOut?.risk_tier || ''),
        heartbeat_seq: Number(heartbeatOut?.heartbeat_seq || 0),
        expires_at_ms: Number(heartbeatOut?.expires_at_ms || 0),
        conservative_only: !!heartbeatOut?.conservative_only,
      }),
    });

    callback(null, {
      accepted: true,
      created: !!out?.created,
      deny_code: '',
      heartbeat: heartbeatOut,
    });
  }

  function GetDispatchPlan(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const request_id = String(req.request_id || '').trim();
    const root_project_id = String(req.root_project_id || '').trim();
    const max_projects = Math.max(1, Math.floor(Number(req.max_projects || 0)));
    const trustedAutomationScope = trustedAutomationScopeWithProject(
      trustedAutomationScopeFromRequest(req, client),
      root_project_id,
    );
    const now = nowMs();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!root_project_id) {
      db.appendAudit({
        event_type: 'project.dispatch.rejected',
        created_at_ms: now,
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: 'invalid_request',
        error_message: 'project_dispatch_plan_invalid_request',
        ext_json: JSON.stringify({
          op: 'get_dispatch_plan',
          deny_code: 'invalid_request',
          reason: 'missing root_project_id',
        }),
      });
      callback(null, {
        planned: false,
        deny_code: 'invalid_request',
        batch_id: '',
        generated_at_ms: now,
        conservative_mode: true,
        items: [],
      });
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendProjectRejectAudit({
        event_type: 'project.dispatch.rejected',
        error_message: 'project_dispatch_plan_rejected',
        op: 'get_dispatch_plan',
        client,
        request_id,
        project_id: root_project_id || null,
        deny_code: denyCode,
        ext: {
          root_project_id,
          max_projects,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    let out;
    try {
      out = db.buildProjectDispatchPlan({
        request_id,
        device_id,
        user_id,
        app_id,
        root_project_id,
        max_projects,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'dispatch_plan_failed')));
      return;
    }

    if (!out?.planned) {
      db.appendAudit({
        event_type: 'project.dispatch.rejected',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: root_project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: String(out?.deny_code || 'dispatch_rejected'),
        error_message: 'project_dispatch_plan_rejected',
        ext_json: JSON.stringify({
          op: 'get_dispatch_plan',
          root_project_id,
          deny_code: String(out?.deny_code || 'dispatch_rejected'),
        }),
      });
      callback(null, {
        planned: false,
        deny_code: String(out?.deny_code || 'dispatch_rejected'),
        batch_id: '',
        generated_at_ms: Math.max(0, Number(out?.generated_at_ms || nowMs())),
        conservative_mode: true,
        items: [],
      });
      return;
    }

    const planItems = Array.isArray(out?.items)
      ? out.items.map((item) => makeProtoDispatchPlanItem(item)).filter(Boolean)
      : [];
    const prewarmTargets = Array.from(new Set(
      planItems.flatMap((item) => (Array.isArray(item?.prewarm_targets) ? item.prewarm_targets : []))
    ));
    const batchId = String(out?.batch_id || '');
    const conservativeMode = !!out?.conservative_mode;
    db.appendAudit({
      event_type: 'project.dispatch.planned',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: root_project_id,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: request_id || null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        op: 'get_dispatch_plan',
        root_project_id,
        batch_id: batchId,
        plan_size: planItems.length,
        conservative_mode: conservativeMode,
        ttl_pruned: Math.max(0, Number(out?.ttl_pruned || 0)),
        total_candidates: Math.max(0, Number(out?.total_candidates || 0)),
      }),
    });
    if (prewarmTargets.length > 0) {
      db.appendAudit({
        event_type: 'project.prewarm.applied',
        created_at_ms: nowMs(),
        severity: conservativeMode ? 'warn' : 'info',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: root_project_id,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: true,
        ext_json: JSON.stringify({
          op: 'get_dispatch_plan',
          batch_id: batchId,
          root_project_id,
          prewarm_targets: prewarmTargets,
          conservative_mode: conservativeMode,
        }),
      });
    }

    callback(null, {
      planned: true,
      deny_code: '',
      batch_id: batchId,
      generated_at_ms: Math.max(0, Number(out?.generated_at_ms || nowMs())),
      conservative_mode: conservativeMode,
      items: planItems,
    });
  }

  function buildLongtermMarkdownProjectionForClient({
    device_id,
    user_id,
    app_id,
    project_id,
    scope,
    thread_id,
    remote_mode,
    allow_untrusted,
    allowed_sensitivity,
    limit,
    max_markdown_chars,
  } = {}) {
    const rows = db.listCanonicalItems({
      scope,
      thread_id,
      device_id,
      user_id,
      app_id,
      project_id,
      limit: Math.max(limit, Math.min(500, Math.max(100, limit * 3))),
    });
    return buildLongtermMarkdownExport({
      rows,
      scope_filter: scope || 'all',
      scope_ref: {
        device_id,
        user_id,
        app_id,
        project_id,
        thread_id: thread_id || '',
      },
      remote_mode,
      allow_untrusted,
      allowed_sensitivity,
      limit,
      max_markdown_chars,
    });
  }

  function markdownEditSessionOwnedByClient(session, clientScope = {}) {
    const s = session && typeof session === 'object' ? session : {};
    const c = clientScope && typeof clientScope === 'object' ? clientScope : {};
    const sameDevice = String(s.created_by_device_id || '') === String(c.device_id || '');
    const sameApp = String(s.created_by_app_id || '') === String(c.app_id || '');
    const sameProject = String(s.created_by_project_id || '') === String(c.project_id || '');
    const sessionUser = String(s.created_by_user_id || '');
    const clientUser = String(c.user_id || '');
    const sameUser = !sessionUser || sessionUser === clientUser;
    return sameDevice && sameApp && sameProject && sameUser;
  }

  function LongtermMarkdownExport(call, callback) {
    const opStartedAtMs = nowMs();
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const scope = req.scope ? String(req.scope).trim() : '';
    const thread_id = req.thread_id ? String(req.thread_id).trim() : '';
    const remote_mode = !!req.remote_mode;
    const allow_untrusted = !!req.allow_untrusted;
    const allowed_sensitivity = Array.isArray(req.allowed_sensitivity)
      ? req.allowed_sensitivity.map((s) => String(s || '').trim()).filter(Boolean)
      : [];
    const limit = Math.max(1, Math.min(500, Number(req.limit || 200)));
    const expectedVersion = String(req.expected_version || '').trim();
    const maxMarkdownChars = Math.max(
      1024,
      Math.min(512 * 1024, Number(process.env.HUB_MEMORY_MARKDOWN_EXPORT_MAX_CHARS || (48 * 1024)))
    );

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.longterm_markdown.exported',
        error_message: 'markdown_export_denied',
        op: 'markdown_export',
        client,
        request_id: '',
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          scope: scope || 'all',
          thread_id: thread_id || '',
          remote_mode,
          allow_untrusted,
        },
      });
      callback(new Error(denyCode));
      return;
    }
    if (scope === 'thread' && !thread_id) {
      callback(new Error('invalid request: missing thread_id for scope=thread'));
      return;
    }

    let projection;
    try {
      projection = buildLongtermMarkdownProjectionForClient({
        device_id,
        user_id,
        app_id,
        project_id,
        scope,
        thread_id,
        remote_mode,
        allow_untrusted,
        allowed_sensitivity,
        limit,
        max_markdown_chars: maxMarkdownChars,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'markdown_export_failed')));
      return;
    }

    if (expectedVersion && expectedVersion !== String(projection?.version || '')) {
      callback(new Error('version_conflict'));
      return;
    }

    const exportedAtMs = nowMs();
    const appliedSensitivity = Array.isArray(projection?.applied_sensitivity)
      ? projection.applied_sensitivity
      : [];
    const secretRequested = allowed_sensitivity.includes('secret');
    const secretApplied = appliedSensitivity.includes('secret');
    const exportExt = withMemoryMetricsExt({
      doc_id: String(projection?.doc_id || ''),
      version: String(projection?.version || ''),
      scope: scope || 'all',
      thread_id: thread_id || '',
      remote_mode,
      allow_untrusted,
      allowed_sensitivity,
      applied_sensitivity: appliedSensitivity,
      total_items: Math.max(0, Number(projection?.total_items || 0)),
      included_items: Math.max(0, Number(projection?.included_items || 0)),
      truncated: !!projection?.truncated,
    }, {
      event_kind: 'memory.longterm_markdown.exported',
      op: 'markdown_export',
      job_type: 'markdown_export',
      channel: metricsChannel(remote_mode),
      remote_mode,
      scope: buildMetricsScope({
        scope_kind: scope || 'all',
        device_id,
        user_id,
        app_id,
        project_id,
        thread_id,
      }),
      latency: {
        duration_ms: Math.max(0, exportedAtMs - opStartedAtMs),
      },
      quality: {
        result_count: Math.max(0, Number(projection?.included_items || 0)),
        total_items: Math.max(0, Number(projection?.total_items || 0)),
        included_items: Math.max(0, Number(projection?.included_items || 0)),
        truncated: !!projection?.truncated,
      },
      freshness: {
        exported_at_ms: Number(projection?.exported_at_ms || exportedAtMs),
        snapshot_version: String(projection?.version || ''),
      },
      security: {
        blocked: false,
        downgraded: !!(remote_mode && secretRequested && !secretApplied),
      },
    });

    db.appendAudit({
      event_type: 'memory.longterm_markdown.exported',
      created_at_ms: exportedAtMs,
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify(exportExt),
    });

    callback(null, {
      doc_id: String(projection?.doc_id || ''),
      version: String(projection?.version || ''),
      markdown: String(projection?.markdown || ''),
      provenance_refs: Array.isArray(projection?.provenance_refs)
        ? projection.provenance_refs.map((r) => String(r || '')).filter(Boolean)
        : [],
      exported_at_ms: Number(projection?.exported_at_ms || nowMs()),
      truncated: !!projection?.truncated,
      total_items: Math.max(0, Number(projection?.total_items || 0)),
      included_items: Math.max(0, Number(projection?.included_items || 0)),
      applied_sensitivity: Array.isArray(projection?.applied_sensitivity)
        ? projection.applied_sensitivity.map((s) => String(s || '')).filter(Boolean)
        : [],
    });
  }

  function LongtermMarkdownBeginEdit(call, callback) {
    const opStartedAtMs = nowMs();
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const scope = req.scope ? String(req.scope).trim() : '';
    const thread_id = req.thread_id ? String(req.thread_id).trim() : '';
    const remote_mode = !!req.remote_mode;
    const allow_untrusted = !!req.allow_untrusted;
    const allowed_sensitivity = Array.isArray(req.allowed_sensitivity)
      ? req.allowed_sensitivity.map((s) => String(s || '').trim()).filter(Boolean)
      : [];
    const limit = Math.max(1, Math.min(500, Number(req.limit || 200)));
    const maxMarkdownChars = Math.max(
      1024,
      Math.min(512 * 1024, Number(process.env.HUB_MEMORY_MARKDOWN_EXPORT_MAX_CHARS || (48 * 1024)))
    );
    const editLimits = resolveMemoryMarkdownEditLimits();
    const requestedTtl = parseIntInRange(
      req.ttl_ms,
      editLimits.default_ttl_ms,
      60 * 1000,
      editLimits.max_edit_ttl_ms
    );
    const now = nowMs();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.longterm_markdown.begin_edit',
        error_message: 'markdown_begin_edit_denied',
        op: 'markdown_begin_edit',
        client,
        request_id: '',
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          scope: scope || 'all',
          thread_id: thread_id || '',
          remote_mode,
          allow_untrusted,
        },
      });
      callback(new Error(denyCode));
      return;
    }
    if (scope === 'thread' && !thread_id) {
      callback(new Error('invalid request: missing thread_id for scope=thread'));
      return;
    }

    try {
      db.expireMemoryMarkdownEditSessions({ now_ms: now });
    } catch {
      // ignore best-effort cleanup
    }

    let projection;
    try {
      projection = buildLongtermMarkdownProjectionForClient({
        device_id,
        user_id,
        app_id,
        project_id,
        scope,
        thread_id,
        remote_mode,
        allow_untrusted,
        allowed_sensitivity,
        limit,
        max_markdown_chars: maxMarkdownChars,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'markdown_export_failed')));
      return;
    }

    let session;
    try {
      session = db.createMemoryMarkdownEditSession({
        doc_id: String(projection?.doc_id || ''),
        base_version: String(projection?.version || ''),
        working_version: String(projection?.version || ''),
        scope_filter: scope || 'all',
        scope_ref: {
          device_id,
          user_id,
          app_id,
          project_id,
          thread_id: thread_id || '',
        },
        route_policy: projection?.route_policy || {
          remote_mode,
          allow_untrusted,
          allowed_sensitivity,
        },
        route_stats: projection?.route_stats || {},
        base_markdown: String(projection?.markdown || ''),
        working_markdown: String(projection?.markdown || ''),
        provenance_refs: Array.isArray(projection?.provenance_refs) ? projection.provenance_refs : [],
        status: 'active',
        created_by_device_id: device_id,
        created_by_user_id: user_id || null,
        created_by_app_id: app_id,
        created_by_project_id: project_id || null,
        created_by_session_id: client.session_id ? String(client.session_id) : null,
        created_at_ms: now,
        updated_at_ms: now,
        expires_at_ms: now + requestedTtl,
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'begin_edit_failed')));
      return;
    }

    const beginEditAuditAtMs = nowMs();
    const beginEditExt = withMemoryMetricsExt({
      edit_session_id: String(session?.edit_session_id || ''),
      doc_id: String(session?.doc_id || ''),
      base_version: String(session?.base_version || ''),
      scope: scope || 'all',
      thread_id: thread_id || '',
      remote_mode,
      allow_untrusted,
      allowed_sensitivity,
      max_patch_chars: editLimits.max_patch_chars,
      max_patch_lines: editLimits.max_patch_lines,
      ttl_ms: requestedTtl,
    }, {
      event_kind: 'memory.longterm_markdown.begin_edit',
      op: 'markdown_begin_edit',
      job_type: 'markdown_begin_edit',
      channel: metricsChannel(remote_mode),
      remote_mode,
      scope: buildMetricsScope({
        scope_kind: scope || 'all',
        device_id,
        user_id,
        app_id,
        project_id,
        thread_id,
      }),
      latency: {
        duration_ms: Math.max(0, beginEditAuditAtMs - opStartedAtMs),
      },
      quality: {
        total_items: Math.max(0, Number(projection?.total_items || 0)),
        included_items: Math.max(0, Number(projection?.included_items || 0)),
        session_revision: Number(session?.session_revision || 0),
      },
      freshness: {
        exported_at_ms: Number(projection?.exported_at_ms || now),
        snapshot_version: String(session?.base_version || ''),
      },
      security: {
        blocked: false,
      },
    });

    db.appendAudit({
      event_type: 'memory.longterm_markdown.begin_edit',
      created_at_ms: beginEditAuditAtMs,
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify(beginEditExt),
    });

    callback(null, {
      edit_session_id: String(session?.edit_session_id || ''),
      doc_id: String(session?.doc_id || ''),
      base_version: String(session?.base_version || ''),
      working_version: String(session?.working_version || ''),
      session_revision: Number(session?.session_revision || 0),
      markdown: String(session?.working_markdown || ''),
      provenance_refs: Array.isArray(session?.provenance_refs)
        ? session.provenance_refs.map((v) => String(v || '')).filter(Boolean)
        : [],
      created_at_ms: Number(session?.created_at_ms || now),
      updated_at_ms: Number(session?.updated_at_ms || now),
      expires_at_ms: Number(session?.expires_at_ms || (now + requestedTtl)),
      max_patch_chars: editLimits.max_patch_chars,
      max_patch_lines: editLimits.max_patch_lines,
      max_edit_ttl_ms: editLimits.max_edit_ttl_ms,
    });
  }

  function LongtermMarkdownApplyPatch(call, callback) {
    const opStartedAtMs = nowMs();
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const edit_session_id = String(req.edit_session_id || '').trim();
    const base_version = String(req.base_version || '').trim();
    const session_revision_raw = parseNonNegativeInt(req.session_revision);
    const patch_mode = normalizeMarkdownPatchMode(req.patch_mode || 'replace');
    const patch_markdown = String(req.patch_markdown ?? '');
    const patch_note = req.patch_note != null ? String(req.patch_note) : '';
    const now = nowMs();
    const limits = resolveMemoryMarkdownEditLimits();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.longterm_markdown.patch_applied',
        error_message: 'markdown_apply_patch_denied',
        op: 'markdown_apply_patch',
        client,
        request_id: '',
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          edit_session_id,
          base_version,
          patch_mode: String(patch_mode || ''),
        },
      });
      callback(new Error(denyCode));
      return;
    }
    if (!edit_session_id) {
      callback(new Error('invalid request: missing edit_session_id'));
      return;
    }
    if (!base_version) {
      callback(new Error('invalid request: missing base_version'));
      return;
    }
    if (session_revision_raw == null) {
      callback(new Error('invalid request: missing session_revision'));
      return;
    }
    if (!patch_mode) {
      callback(new Error('unsupported_patch_mode'));
      return;
    }

    try {
      db.expireMemoryMarkdownEditSessions({ now_ms: now });
    } catch {
      // ignore best-effort cleanup
    }

    const session = db.getMemoryMarkdownEditSession({ edit_session_id });
    if (!session) {
      callback(new Error('edit_session_not_found'));
      return;
    }
    if (!markdownEditSessionOwnedByClient(session, { device_id, user_id, app_id, project_id })) {
      callback(new Error('permission_denied'));
      return;
    }
    const status = String(session.status || '').trim().toLowerCase();
    if (status !== 'active') {
      callback(new Error('edit_session_not_active'));
      return;
    }
    if (Math.max(0, Number(session.expires_at_ms || 0)) <= now) {
      callback(new Error('edit_session_expired'));
      return;
    }
    if (String(session.base_version || '') !== base_version) {
      callback(new Error('version_conflict'));
      return;
    }
    if (Number(session.session_revision || 0) !== Number(session_revision_raw || 0)) {
      callback(new Error('version_conflict'));
      return;
    }

    let candidate;
    try {
      candidate = buildLongtermMarkdownPatchCandidate({
        session,
        patch_mode,
        patch_markdown,
        patch_note,
        max_patch_chars: limits.max_patch_chars,
        max_patch_lines: limits.max_patch_lines,
      });
    } catch (e) {
      const msg = String(e?.message || e || 'patch_apply_failed');
      if (
        msg === 'unsupported_patch_mode'
        || msg === 'empty_patch'
        || msg.startsWith('patch_limit_exceeded')
      ) {
        callback(new Error(msg));
        return;
      }
      callback(new Error('patch_apply_failed'));
      return;
    }

    let applied;
    try {
      applied = db.applyMemoryMarkdownPatchDraft({
        edit_session_id,
        expected_revision: Number(session_revision_raw || 0),
        working_version: String(candidate.to_version || ''),
        working_markdown: String(candidate.patched_markdown || ''),
        last_patch_at_ms: now,
        updated_at_ms: now,
        change: {
          doc_id: String(session.doc_id || ''),
          base_version: String(session.base_version || ''),
          from_version: String(candidate.from_version || ''),
          to_version: String(candidate.to_version || ''),
          status: 'draft',
          patch_mode: String(candidate.patch_mode || 'replace'),
          patch_note: String(candidate.patch_note || ''),
          patch_size_chars: Number(candidate.patch_size_chars || 0),
          patch_line_count: Number(candidate.patch_line_count || 0),
          patch_sha256: String(candidate.patch_sha256 || ''),
          patched_markdown: String(candidate.patched_markdown || ''),
          provenance_refs: Array.isArray(session.provenance_refs) ? session.provenance_refs : [],
          route_policy: session.route_policy || {},
          created_by_device_id: device_id,
          created_by_user_id: user_id || null,
          created_by_app_id: app_id,
          created_by_project_id: project_id || null,
          created_by_session_id: client.session_id ? String(client.session_id) : null,
          created_at_ms: now,
          updated_at_ms: now,
        },
      });
    } catch (e) {
      const msg = String(e?.message || e || 'patch_apply_failed');
      if (
        msg === 'version_conflict'
        || msg === 'edit_session_expired'
        || msg === 'edit_session_not_active'
        || msg === 'edit_session_not_found'
      ) {
        callback(new Error(msg));
        return;
      }
      callback(new Error('patch_apply_failed'));
      return;
    }

    const nextSession = applied?.session || null;
    const pendingChange = applied?.change || null;
    if (!nextSession || !pendingChange) {
      callback(new Error('patch_apply_failed'));
      return;
    }

    const routeRemoteMode = parseRoutePolicyRemoteMode(nextSession?.route_policy, false);
    const patchAuditAtMs = nowMs();
    const patchExt = withMemoryMetricsExt({
      edit_session_id,
      pending_change_id: String(pendingChange.change_id || ''),
      doc_id: String(nextSession.doc_id || ''),
      base_version: String(nextSession.base_version || ''),
      from_version: String(candidate.from_version || ''),
      to_version: String(candidate.to_version || ''),
      session_revision: Number(nextSession.session_revision || 0),
      patch_mode: String(candidate.patch_mode || 'replace'),
      patch_size_chars: Number(candidate.patch_size_chars || 0),
      patch_line_count: Number(candidate.patch_line_count || 0),
    }, {
      event_kind: 'memory.longterm_markdown.patch_applied',
      op: 'markdown_apply_patch',
      job_type: 'markdown_apply_patch',
      channel: metricsChannel(routeRemoteMode),
      remote_mode: routeRemoteMode,
      scope: buildMetricsScope({
        scope_kind: String(nextSession?.scope_filter || '').trim() || 'all',
        device_id,
        user_id,
        app_id,
        project_id,
        thread_id: String(nextSession?.scope_ref?.thread_id || ''),
      }),
      latency: {
        duration_ms: Math.max(0, patchAuditAtMs - opStartedAtMs),
      },
      quality: {
        patch_size_chars: Number(candidate.patch_size_chars || 0),
        patch_line_count: Number(candidate.patch_line_count || 0),
        session_revision: Number(nextSession.session_revision || 0),
      },
      freshness: {
        snapshot_version: String(candidate.to_version || ''),
      },
      security: {
        blocked: false,
      },
    });

    db.appendAudit({
      event_type: 'memory.longterm_markdown.patch_applied',
      created_at_ms: patchAuditAtMs,
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify(patchExt),
    });

    callback(null, {
      edit_session_id: String(nextSession.edit_session_id || ''),
      doc_id: String(nextSession.doc_id || ''),
      base_version: String(nextSession.base_version || ''),
      working_version: String(nextSession.working_version || ''),
      session_revision: Number(nextSession.session_revision || 0),
      pending_change_id: String(pendingChange.change_id || ''),
      status: String(pendingChange.status || 'draft'),
      patch_mode: String(candidate.patch_mode || 'replace'),
      patch_size_chars: Number(candidate.patch_size_chars || 0),
      patch_line_count: Number(candidate.patch_line_count || 0),
      updated_at_ms: Number(nextSession.updated_at_ms || now),
      expires_at_ms: Number(nextSession.expires_at_ms || now),
      markdown: String(nextSession.working_markdown || ''),
    });
  }

  function markdownPendingChangeOwnedByClient(change, clientScope = {}) {
    const c = change && typeof change === 'object' ? change : {};
    const s = clientScope && typeof clientScope === 'object' ? clientScope : {};
    const sameDevice = String(c.created_by_device_id || '') === String(s.device_id || '');
    const sameApp = String(c.created_by_app_id || '') === String(s.app_id || '');
    const sameProject = String(c.created_by_project_id || '') === String(s.project_id || '');
    const changeUser = String(c.created_by_user_id || '');
    const clientUser = String(s.user_id || '');
    const sameUser = !changeUser || changeUser === clientUser;
    return sameDevice && sameApp && sameProject && sameUser;
  }

  function LongtermMarkdownReview(call, callback) {
    const opStartedAtMs = nowMs();
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const pending_change_id = String(req.pending_change_id || '').trim();
    const expected_status = String(req.expected_status || '').trim();
    const review_decision = normalizeReviewDecision(req.review_decision || 'review');
    const on_secret = normalizeSecretHandling(req.on_secret || 'deny') || 'deny';
    const review_note = req.review_note != null ? String(req.review_note) : '';
    const now = nowMs();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.longterm_markdown.reviewed',
        error_message: 'markdown_review_denied',
        op: 'markdown_review',
        client,
        request_id: '',
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          pending_change_id,
          expected_status,
          review_decision,
          on_secret,
        },
      });
      callback(new Error(denyCode));
      return;
    }
    if (!pending_change_id) {
      callback(new Error('invalid request: missing pending_change_id'));
      return;
    }
    if (!review_decision) {
      callback(new Error('invalid request: review_decision must be review|approve|reject'));
      return;
    }
    if (!['deny', 'sanitize'].includes(on_secret)) {
      callback(new Error('invalid request: on_secret must be deny|sanitize'));
      return;
    }

    const change = db.getMemoryMarkdownPendingChange({ change_id: pending_change_id });
    if (!change) {
      callback(new Error('change_not_found'));
      return;
    }
    if (!markdownPendingChangeOwnedByClient(change, { device_id, user_id, app_id, project_id })) {
      callback(new Error('permission_denied'));
      return;
    }

    const inputMarkdown = String(change.reviewed_markdown || change.patched_markdown || '');
    const analysis = analyzeLongtermMarkdownFindings(inputMarkdown);
    let findings = Array.isArray(analysis.findings) ? analysis.findings : [];
    let reviewedMarkdown = inputMarkdown;
    let policyDecision = 'allow';
    let redactedCount = 0;
    let statusDecision = review_decision;
    let autoRejected = false;

    if ((analysis.has_credential || analysis.has_secret) && review_decision !== 'reject') {
      if (on_secret === 'sanitize') {
        const sanitized = sanitizeLongtermMarkdown(inputMarkdown);
        reviewedMarkdown = String(sanitized.markdown || '');
        redactedCount = Math.max(0, Number(sanitized.redacted_count || 0));
        const after = analyzeLongtermMarkdownFindings(reviewedMarkdown);
        findings = Array.isArray(after.findings) ? after.findings : [];
        if (after.has_credential) {
          policyDecision = 'deny_after_sanitize';
          statusDecision = 'reject';
          autoRejected = true;
        } else {
          policyDecision = 'sanitize_allow';
        }
      } else {
        policyDecision = 'deny';
        statusDecision = 'reject';
        autoRejected = true;
      }
    }

    let reviewed;
    try {
      reviewed = db.reviewMemoryMarkdownPendingChange({
        change_id: pending_change_id,
        expected_status: expected_status || null,
        decision: statusDecision,
        reviewed_markdown: reviewedMarkdown,
        review_findings: findings,
        review_note: review_note || null,
        reviewed_by_device_id: device_id,
        reviewed_by_user_id: user_id || null,
        reviewed_by_app_id: app_id,
        reviewed_by_project_id: project_id || null,
        reviewed_by_session_id: client.session_id ? String(client.session_id) : null,
        reviewed_at_ms: now,
        updated_at_ms: now,
      });
    } catch (e) {
      const msg = String(e?.message || e || 'review_failed');
      if (
        msg === 'version_conflict'
        || msg === 'change_not_found'
        || msg === 'change_not_mutable'
        || msg === 'invalid_status_transition'
      ) {
        callback(new Error(msg));
        return;
      }
      callback(new Error('review_failed'));
      return;
    }

    const reviewRemoteMode = parseRoutePolicyRemoteMode(change?.route_policy, false);
    const reviewAuditAtMs = nowMs();
    const reviewBlocked = statusDecision === 'reject' || policyDecision.startsWith('deny');
    const reviewExt = withMemoryMetricsExt({
      pending_change_id,
      edit_session_id: String(reviewed?.edit_session_id || ''),
      doc_id: String(reviewed?.doc_id || ''),
      requested_decision: review_decision,
      applied_decision: statusDecision,
      on_secret,
      policy_decision: policyDecision,
      auto_rejected: autoRejected,
      findings_count: findings.length,
      redacted_count: redactedCount,
      status: String(reviewed?.status || ''),
    }, {
      event_kind: 'memory.longterm_markdown.reviewed',
      op: 'markdown_review',
      job_type: 'markdown_review',
      channel: metricsChannel(reviewRemoteMode),
      remote_mode: reviewRemoteMode,
      scope: buildMetricsScope({
        scope_kind: String(change?.scope_filter || '').trim() || 'project',
        device_id,
        user_id,
        app_id,
        project_id,
        thread_id: String(change?.scope_ref?.thread_id || ''),
      }),
      latency: {
        duration_ms: Math.max(0, reviewAuditAtMs - opStartedAtMs),
      },
      quality: {
        findings_count: findings.length,
        redacted_count: redactedCount,
        auto_rejected: autoRejected,
      },
      freshness: {
        snapshot_version: String(reviewed?.to_version || change?.to_version || ''),
      },
      security: {
        blocked: reviewBlocked,
        downgraded: policyDecision.includes('sanitize'),
        deny_code: reviewBlocked ? policyDecision : '',
      },
    });

    db.appendAudit({
      event_type: 'memory.longterm_markdown.reviewed',
      created_at_ms: reviewAuditAtMs,
      severity: policyDecision.startsWith('deny') ? 'security' : 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify(reviewExt),
    });

    callback(null, {
      pending_change_id: String(reviewed?.change_id || ''),
      edit_session_id: String(reviewed?.edit_session_id || ''),
      doc_id: String(reviewed?.doc_id || ''),
      status: String(reviewed?.status || ''),
      review_decision: String(statusDecision || ''),
      policy_decision: policyDecision,
      findings_json: JSON.stringify(findings),
      redacted_count: redactedCount,
      reviewed_at_ms: Number(reviewed?.reviewed_at_ms || now),
      approved_at_ms: Number(reviewed?.approved_at_ms || 0),
      markdown: String(reviewed?.reviewed_markdown || reviewedMarkdown || ''),
      auto_rejected: autoRejected,
    });
  }

  function LongtermMarkdownWriteback(call, callback) {
    const opStartedAtMs = nowMs();
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const pending_change_id = String(req.pending_change_id || '').trim();
    const expected_status = String(req.expected_status || '').trim() || 'approved';
    const writeback_note = req.writeback_note != null ? String(req.writeback_note) : '';
    const now = nowMs();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.longterm_markdown.written',
        error_message: 'markdown_writeback_denied',
        op: 'markdown_writeback',
        client,
        request_id: '',
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          pending_change_id,
          expected_status,
        },
      });
      callback(new Error(denyCode));
      return;
    }
    if (!pending_change_id) {
      callback(new Error('invalid request: missing pending_change_id'));
      return;
    }

    const change = db.getMemoryMarkdownPendingChange({ change_id: pending_change_id });
    if (!change) {
      callback(new Error('change_not_found'));
      return;
    }
    if (!markdownPendingChangeOwnedByClient(change, { device_id, user_id, app_id, project_id })) {
      callback(new Error('permission_denied'));
      return;
    }

    const changeStatus = String(change.status || '').trim().toLowerCase();
    const isIdempotentWritten = changeStatus === 'written' && !!String(change.writeback_ref || '').trim();
    if (changeStatus !== expected_status && !(expected_status === 'approved' && isIdempotentWritten)) {
      callback(new Error('change_not_approved'));
      return;
    }

    const content = String(change.reviewed_markdown || change.patched_markdown || '');
    const beforeWriteScan = analyzeLongtermMarkdownFindings(content);
    if (beforeWriteScan.has_credential) {
      callback(new Error('writeback_policy_violation:credential'));
      return;
    }

    let result;
    try {
      result = db.writebackMemoryMarkdownPendingChange({
        change_id: pending_change_id,
        expected_status,
        content_markdown: content,
        scope_ref: {
          device_id,
          user_id,
          app_id,
          project_id,
          thread_id: '',
        },
        provenance_refs: Array.isArray(change.provenance_refs) ? change.provenance_refs : [],
        policy_decision: {
          source: 'longterm_markdown_writeback',
          findings_count: Array.isArray(beforeWriteScan.findings) ? beforeWriteScan.findings.length : 0,
          writeback_note,
        },
        actor: {
          device_id,
          user_id: user_id || null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
        },
        written_at_ms: now,
        updated_at_ms: now,
      });
    } catch (e) {
      const msg = String(e?.message || e || 'writeback_failed');
      if (
        msg === 'change_not_found'
        || msg === 'change_not_approved'
        || msg === 'missing_writeback_actor'
        || msg === 'candidate_not_found'
        || msg === 'missing_scope_ref'
        || msg === 'writeback_scope_mismatch'
        || msg === 'writeback_state_corrupt'
      ) {
        callback(new Error(msg));
        return;
      }
      callback(new Error('writeback_failed'));
      return;
    }

    const nextChange = result?.change || null;
    const candidate = result?.candidate || null;
    const changeLog = result?.change_log || null;

    const writebackRemoteMode = parseRoutePolicyRemoteMode(change?.route_policy, false);
    const writebackAuditAtMs = nowMs();
    const writebackExt = withMemoryMetricsExt({
      pending_change_id,
      candidate_id: String(candidate?.candidate_id || ''),
      edit_session_id: String(nextChange?.edit_session_id || ''),
      doc_id: String(nextChange?.doc_id || ''),
      status: String(nextChange?.status || ''),
      writeback_note,
      change_log_id: String(changeLog?.log_id || ''),
      policy_decision: changeLog?.policy_decision || {},
      evidence_ref: String(changeLog?.evidence_ref || candidate?.evidence_ref || ''),
    }, {
      event_kind: 'memory.longterm_markdown.written',
      op: 'markdown_writeback',
      job_type: 'markdown_writeback',
      channel: metricsChannel(writebackRemoteMode),
      remote_mode: writebackRemoteMode,
      scope: buildMetricsScope({
        scope_kind: String(change?.scope_filter || '').trim() || 'project',
        device_id,
        user_id,
        app_id,
        project_id,
      }),
      latency: {
        duration_ms: Math.max(0, writebackAuditAtMs - opStartedAtMs),
      },
      quality: {
        findings_count: Array.isArray(beforeWriteScan.findings) ? beforeWriteScan.findings.length : 0,
      },
      freshness: {
        snapshot_version: String(nextChange?.to_version || candidate?.source_version || ''),
      },
      security: {
        blocked: false,
      },
    });

    db.appendAudit({
      event_type: 'memory.longterm_markdown.written',
      created_at_ms: writebackAuditAtMs,
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify(writebackExt),
    });

    callback(null, {
      pending_change_id: String(nextChange?.change_id || pending_change_id),
      status: String(nextChange?.status || ''),
      candidate_id: String(candidate?.candidate_id || ''),
      queue_status: String(candidate?.status || ''),
      written_at_ms: Number(nextChange?.written_at_ms || candidate?.written_at_ms || now),
      doc_id: String(nextChange?.doc_id || ''),
      source_version: String(nextChange?.to_version || ''),
      change_log_id: String(changeLog?.log_id || ''),
      evidence_ref: String(changeLog?.evidence_ref || candidate?.evidence_ref || ''),
    });
  }

  function LongtermMarkdownRollback(call, callback) {
    const opStartedAtMs = nowMs();
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'memory')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    const user_id = client.user_id ? String(client.user_id) : '';
    const pending_change_id = String(req.pending_change_id || '').trim();
    const expected_status = String(req.expected_status || '').trim() || 'written';
    const rollback_note = req.rollback_note != null ? String(req.rollback_note) : '';
    const now = nowMs();

    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      appendDeniedAudit({
        event_type: 'memory.longterm_markdown.rolled_back',
        error_message: 'markdown_rollback_denied',
        op: 'markdown_rollback',
        client,
        request_id: '',
        project_id: project_id || null,
        deny_code: denyCode,
        ext: {
          pending_change_id,
          expected_status,
        },
      });
      callback(new Error(denyCode));
      return;
    }
    if (!pending_change_id) {
      callback(new Error('invalid request: missing pending_change_id'));
      return;
    }

    const change = db.getMemoryMarkdownPendingChange({ change_id: pending_change_id });
    if (!change) {
      callback(new Error('change_not_found'));
      return;
    }
    if (!markdownPendingChangeOwnedByClient(change, { device_id, user_id, app_id, project_id })) {
      callback(new Error('permission_denied'));
      return;
    }

    let result;
    try {
      result = db.rollbackMemoryMarkdownPendingChange({
        change_id: pending_change_id,
        expected_status,
        actor: {
          device_id,
          user_id: user_id || null,
          app_id,
          project_id: project_id || null,
          session_id: client.session_id ? String(client.session_id) : null,
        },
        rollback_note,
        rolled_back_at_ms: now,
        updated_at_ms: now,
      });
    } catch (e) {
      const msg = String(e?.message || e || 'rollback_failed');
      if (
        msg === 'change_not_found'
        || msg === 'change_not_written'
        || msg === 'writeback_ref_missing'
        || msg === 'candidate_not_found'
        || msg === 'candidate_not_written'
        || msg === 'rollback_target_not_found'
        || msg === 'rollback_scope_mismatch'
        || msg === 'missing_rollback_actor'
        || msg === 'rollback_state_corrupt'
      ) {
        callback(new Error(msg));
        return;
      }
      callback(new Error('rollback_failed'));
      return;
    }

    const nextChange = result?.change || null;
    const rolledCandidate = result?.candidate || null;
    const restoredCandidate = result?.restored_candidate || null;
    const changeLog = result?.change_log || null;

    const rollbackRemoteMode = parseRoutePolicyRemoteMode(change?.route_policy, false);
    const rollbackAuditAtMs = nowMs();
    const rollbackExt = withMemoryMetricsExt({
      pending_change_id,
      candidate_id: String(rolledCandidate?.candidate_id || ''),
      restored_candidate_id: String(restoredCandidate?.candidate_id || ''),
      status: String(nextChange?.status || ''),
      rollback_note,
      change_log_id: String(changeLog?.log_id || ''),
      policy_decision: changeLog?.policy_decision || {},
      evidence_ref: String(changeLog?.evidence_ref || rolledCandidate?.evidence_ref || ''),
    }, {
      event_kind: 'memory.longterm_markdown.rolled_back',
      op: 'markdown_rollback',
      job_type: 'markdown_rollback',
      channel: metricsChannel(rollbackRemoteMode),
      remote_mode: rollbackRemoteMode,
      scope: buildMetricsScope({
        scope_kind: String(change?.scope_filter || '').trim() || 'project',
        device_id,
        user_id,
        app_id,
        project_id,
      }),
      latency: {
        duration_ms: Math.max(0, rollbackAuditAtMs - opStartedAtMs),
      },
      quality: {
        result_count: 1,
      },
      freshness: {
        snapshot_version: String(restoredCandidate?.source_version || ''),
      },
      security: {
        blocked: false,
      },
    });

    db.appendAudit({
      event_type: 'memory.longterm_markdown.rolled_back',
      created_at_ms: rollbackAuditAtMs,
      severity: 'security',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify(rollbackExt),
    });

    callback(null, {
      pending_change_id: String(nextChange?.change_id || pending_change_id),
      status: String(nextChange?.status || ''),
      rolled_back_candidate_id: String(rolledCandidate?.candidate_id || ''),
      restored_candidate_id: String(restoredCandidate?.candidate_id || ''),
      rolled_back_at_ms: Number(nextChange?.rolled_back_at_ms || rolledCandidate?.rolled_back_at_ms || now),
      doc_id: String(nextChange?.doc_id || rolledCandidate?.doc_id || ''),
      restored_source_version: String(restoredCandidate?.source_version || ''),
      change_log_id: String(changeLog?.log_id || ''),
      evidence_ref: String(changeLog?.evidence_ref || rolledCandidate?.evidence_ref || ''),
    });
  }

  // -------------------- HubSkills --------------------
  function appendSkillsAudit({
    event_type,
    device_id,
    user_id,
    app_id,
    project_id,
    session_id,
    request_id,
    ok,
    error_code,
    ext,
    severity,
  }) {
    db.appendAudit({
      event_type: String(event_type || 'skills.operation'),
      created_at_ms: nowMs(),
      severity: severity ? String(severity) : (ok ? 'info' : 'security'),
      device_id: String(device_id || 'unknown'),
      user_id: user_id ? String(user_id) : null,
      app_id: String(app_id || 'unknown'),
      project_id: project_id ? String(project_id) : null,
      session_id: session_id ? String(session_id) : null,
      request_id: request_id ? String(request_id) : null,
      capability: 'unknown',
      model_id: null,
      ok: !!ok,
      error_code: error_code ? String(error_code) : null,
      ext_json: JSON.stringify(ext && typeof ext === 'object' ? ext : {}),
    });
  }

  function skillsIdentityFromRequest(req, auth) {
    const client = effectiveClientIdentity(req?.client || {}, auth);
    const scope = trustedAutomationScopeFromRequest(req, client);
    return {
      client,
      device_id: String(client.device_id || '').trim(),
      user_id: client.user_id ? String(client.user_id) : '',
      app_id: String(client.app_id || '').trim(),
      project_id: scope.project_id,
      workspace_root: scope.workspace_root,
      session_id: client.session_id ? String(client.session_id) : '',
    };
  }

  function SearchSkills(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'skills')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      const denyCode = capabilityDenyCode(auth);
      const query = String(req.query || '').trim();
      const source_filter = String(req.source_filter || '').trim();
      const limit = Math.max(1, Math.min(100, Number(req.limit || 20)));
      appendSkillsAudit({
        event_type: 'skills.search.performed',
        device_id,
        user_id,
        app_id,
        project_id,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: '',
        ok: false,
        error_code: denyCode,
        ext: {
          query,
          source_filter,
          limit,
        },
      });
      callback(new Error(denyCode));
      return;
    }

    const runtimeBaseDir = resolveRuntimeBaseDir();
    const query = String(req.query || '').trim();
    const source_filter = String(req.source_filter || '').trim();
    const limit = Math.max(1, Math.min(100, Number(req.limit || 20)));
    const results = searchSkills(runtimeBaseDir, { query, sourceFilter: source_filter, limit })
      .map((r) => makeProtoSkillMeta(r))
      .filter(Boolean);

    db.appendAudit({
      event_type: 'skills.search.performed',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        query,
        source_filter,
        result_count: results.length,
      }),
    });

    callback(null, { updated_at_ms: nowMs(), results });
  }

  function UploadSkillPackage(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'skills')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    let packageBytes = null;
    if (Buffer.isBuffer(req.package_bytes)) {
      packageBytes = req.package_bytes;
    } else if (typeof req.package_bytes === 'string' && req.package_bytes.trim()) {
      try {
        packageBytes = Buffer.from(req.package_bytes, 'base64');
      } catch {
        packageBytes = null;
      }
    }
    if (!packageBytes || packageBytes.length <= 0) {
      callback(new Error('invalid_package_bytes'));
      return;
    }

    const maxMbRaw = Number.parseInt(String(process.env.HUB_SKILLS_MAX_PACKAGE_MB || process.env.HUB_GRPC_MAX_MESSAGE_MB || '32'), 10);
    const maxBytes = Number.isFinite(maxMbRaw) && maxMbRaw > 0 ? maxMbRaw * 1024 * 1024 : 32 * 1024 * 1024;
    if (packageBytes.length > maxBytes) {
      callback(new Error(`package_too_large: max=${maxBytes}`));
      return;
    }

    const runtimeBaseDir = resolveRuntimeBaseDir();
    const source_id = String(req.source_id || 'local:upload').trim() || 'local:upload';
    const request_id = String(req.request_id || '').trim();

    let out;
    try {
      out = uploadSkillPackage(runtimeBaseDir, {
        packageBytes,
        manifestJson: String(req.manifest_json || ''),
        sourceId: source_id,
      });
    } catch (e) {
      const normalized = normalizeSkillStoreError(e, 'skill_upload_failed');
      const failure = explainSkillFailure(normalized.code, 'skill_upload_failed');
      db.appendAudit({
        event_type: 'skills.package.imported',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: failure.deny_code,
        error_message: normalized.message,
        ext_json: JSON.stringify({
          source_id,
          deny_code: failure.deny_code,
          fix_suggestion: failure.fix_suggestion,
          deny_detail: normalized.detail,
        }),
      });
      callback(new Error(failure.deny_code));
      return;
    }

    db.appendAudit({
      event_type: 'skills.package.imported',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: project_id || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: request_id || null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        source_id,
        package_sha256: String(out.package_sha256 || ''),
        manifest_sha256: String(out.manifest_sha256 || ''),
        abi_compat_version: String(out.abi_compat_version || ''),
        compatibility_state: String(out.compatibility_state || ''),
        mapping_aliases_used: Array.isArray(out.mapping_aliases_used) ? out.mapping_aliases_used : [],
        defaults_applied: Array.isArray(out.defaults_applied) ? out.defaults_applied : [],
        skill_id: String(out?.skill?.skill_id || ''),
        version: String(out?.skill?.version || ''),
        entrypoint_command: String(out?.skill?.entrypoint_command || ''),
        entrypoint_runtime: String(out?.skill?.entrypoint_runtime || ''),
        entrypoint_args: Array.isArray(out?.skill?.entrypoint_args) ? out.skill.entrypoint_args : [],
        package_size_bytes: packageBytes.length,
        already_present: !!out.already_present,
        security_profile: String(out?.security?.security_profile || ''),
        signature_verified: !!out?.security?.signature?.verified,
        signature_bypassed: !!out?.security?.signature?.signature_bypassed,
        package_format: String(out?.security?.hashes?.package_format || ''),
        file_hash_count: Number(out?.security?.hashes?.file_count || 0),
      }),
    });

    callback(null, {
      package_sha256: String(out.package_sha256 || ''),
      already_present: !!out.already_present,
      skill: makeProtoSkillMeta(out.skill),
    });
  }

  function SetSkillPin(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'skills')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id) {
      callback(new Error('invalid client identity: missing device_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    if (!user_id) {
      callback(new Error('missing_user_id'));
      return;
    }

    const request_id = String(req.request_id || '').trim();
    const scope = toProtoSkillPinScope(req.scope);
    const skill_id = String(req.skill_id || '').trim();
    const package_sha256 = String(req.package_sha256 || '').trim().toLowerCase();
    const projectForPin = scope === 'SKILL_PIN_SCOPE_GLOBAL' ? '' : project_id;

    let out;
    try {
      out = setSkillPin(resolveRuntimeBaseDir(), {
        scope,
        userId: user_id,
        projectId: projectForPin,
        skillId: skill_id,
        packageSha256: package_sha256,
        note: req.note ? String(req.note) : '',
      });
    } catch (e) {
      const normalized = normalizeSkillStoreError(e, 'skill_pin_failed');
      const failure = explainSkillFailure(normalized.code, 'skill_pin_failed');
      db.appendAudit({
        event_type: 'skills.pin.updated',
        created_at_ms: nowMs(),
        severity: 'warn',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: projectForPin || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: request_id || null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: failure.deny_code,
        error_message: normalized.message,
        ext_json: JSON.stringify({
          scope,
          skill_id,
          package_sha256,
          deny_code: failure.deny_code,
          fix_suggestion: failure.fix_suggestion,
          deny_detail: normalized.detail,
        }),
      });
      callback(new Error(failure.deny_code));
      return;
    }

    db.appendAudit({
      event_type: 'skills.pin.updated',
      created_at_ms: nowMs(),
      severity: 'info',
      device_id,
      user_id: user_id || null,
      app_id,
      project_id: projectForPin || null,
      session_id: client.session_id ? String(client.session_id) : null,
      request_id: request_id || null,
      capability: 'unknown',
      model_id: null,
      ok: true,
      ext_json: JSON.stringify({
        scope: String(out.scope || ''),
        skill_id: String(out.skill_id || ''),
        previous_package_sha256: String(out.previous_package_sha256 || ''),
        package_sha256: String(out.package_sha256 || ''),
      }),
    });

    callback(null, {
      scope: toProtoSkillPinScope(out.scope),
      user_id: String(out.user_id || ''),
      project_id: String(out.project_id || ''),
      skill_id: String(out.skill_id || ''),
      package_sha256: String(out.package_sha256 || ''),
      previous_package_sha256: String(out.previous_package_sha256 || ''),
      updated_at_ms: Number(out.updated_at_ms || 0),
    });
  }

  function ListResolvedSkills(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'skills')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const req = call.request || {};
    const client = effectiveClientIdentity(req.client || {}, auth);
    const device_id = String(client.device_id || '').trim();
    const user_id = client.user_id ? String(client.user_id) : '';
    const app_id = String(client.app_id || '').trim();
    const trustedAutomationScope = trustedAutomationScopeFromRequest(req, client);
    const project_id = trustedAutomationScope.project_id;
    if (!device_id || !app_id || !user_id) {
      callback(new Error('invalid client identity: missing device_id/user_id/app_id'));
      return;
    }
    if (!trustedAutomationAllows(auth, trustedAutomationScope)) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }

    const resolved = resolveSkillsWithTrace(resolveRuntimeBaseDir(), { userId: user_id, projectId: project_id });
    const rows = Array.isArray(resolved?.resolved) ? resolved.resolved : listResolvedSkills(resolveRuntimeBaseDir(), { userId: user_id, projectId: project_id });
    const skills = rows
      .map((r) => {
        const skill = makeProtoSkillMeta(r.skill || {});
        if (!skill) return null;
        return { scope: toProtoSkillPinScope(r.scope), skill };
      })
      .filter(Boolean);
    if (Array.isArray(resolved?.blocked) && resolved.blocked.length > 0) {
      db.appendAudit({
        event_type: 'skills.resolve.blocked',
        created_at_ms: nowMs(),
        severity: 'security',
        device_id,
        user_id: user_id || null,
        app_id,
        project_id: project_id || null,
        session_id: client.session_id ? String(client.session_id) : null,
        request_id: null,
        capability: 'unknown',
        model_id: null,
        ok: false,
        error_code: 'resolve_blocked',
        ext_json: JSON.stringify({
          blocked: resolved.blocked,
          blocked_count: resolved.blocked.length,
        }),
      });
    }
    callback(null, { skills });
  }

  function GetSkillManifest(call, callback) {
    const auth = requireClientAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    if (!clientAllows(auth, 'skills')) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    const req = call.request || {};
    const identity = skillsIdentityFromRequest(req, auth);
    const {
      device_id,
      user_id,
      app_id,
      project_id,
      workspace_root,
      session_id,
    } = identity;
    const package_sha256 = String(req.package_sha256 || '').trim().toLowerCase();
    if (!package_sha256) {
      callback(new Error('missing_package_sha256'));
      return;
    }
    if (!trustedAutomationAllows(auth, { project_id, workspace_root })) {
      callback(new Error(capabilityDenyCode(auth)));
      return;
    }
    let manifest_json = '';
    try {
      manifest_json = String(getSkillManifest(resolveRuntimeBaseDir(), package_sha256) || '').trim();
    } catch (e) {
      const normalized = normalizeSkillStoreError(e, 'manifest_not_found');
      appendSkillsAudit({
        event_type: 'skills.manifest.requested',
        device_id,
        user_id,
        app_id,
        project_id,
        session_id,
        request_id: '',
        ok: false,
        error_code: normalized.code,
        ext: {
          package_sha256,
          deny_detail: normalized.detail,
        },
      });
      callback(new Error(normalized.code));
      return;
    }
    if (!manifest_json) {
      appendSkillsAudit({
        event_type: 'skills.manifest.requested',
        device_id,
        user_id,
        app_id,
        project_id,
        session_id,
        request_id: '',
        ok: false,
        error_code: 'manifest_not_found',
        ext: { package_sha256 },
      });
      callback(new Error('manifest_not_found'));
      return;
    }
    appendSkillsAudit({
      event_type: 'skills.manifest.requested',
      device_id,
      user_id,
      app_id,
      project_id,
      session_id,
      request_id: '',
      ok: true,
      ext: { package_sha256 },
    });
    callback(null, { package_sha256, manifest_json });
  }

  function DownloadSkillPackage(call) {
    const auth = requireClientAuth(call);
    const req = call.request || {};
    const identity = auth.ok ? skillsIdentityFromRequest(req, auth) : null;
    const closeErr = (msg) => {
      try {
        call.destroy(new Error(msg));
      } catch {
        try {
          call.end();
        } catch {
          // ignore
        }
      }
    };

    if (!auth.ok) {
      closeErr(auth.message || 'unauthenticated');
      return;
    }
    if (!clientAllows(auth, 'skills')) {
      closeErr(capabilityDenyCode(auth));
      return;
    }
    if (!trustedAutomationAllows(auth, { project_id: identity?.project_id, workspace_root: identity?.workspace_root })) {
      closeErr(capabilityDenyCode(auth));
      return;
    }

    const package_sha256 = String(req.package_sha256 || '').trim().toLowerCase();
    if (!package_sha256) {
      closeErr('missing_package_sha256');
      return;
    }

    let data = null;
    try {
      data = readSkillPackage(resolveRuntimeBaseDir(), package_sha256);
    } catch (e) {
      const normalized = normalizeSkillStoreError(e, 'package_not_found');
      if (identity) {
        appendSkillsAudit({
          event_type: 'skills.package.downloaded',
          device_id: identity.device_id,
          user_id: identity.user_id,
          app_id: identity.app_id,
          project_id: identity.project_id,
          session_id: identity.session_id,
          request_id: '',
          ok: false,
          error_code: normalized.code,
          ext: {
            package_sha256,
            deny_detail: normalized.detail,
          },
        });
      }
      closeErr(normalized.code);
      return;
    }
    if (!Buffer.isBuffer(data) || data.length <= 0) {
      if (identity) {
        appendSkillsAudit({
          event_type: 'skills.package.downloaded',
          device_id: identity.device_id,
          user_id: identity.user_id,
          app_id: identity.app_id,
          project_id: identity.project_id,
          session_id: identity.session_id,
          request_id: '',
          ok: false,
          error_code: 'package_not_found',
          ext: { package_sha256 },
        });
      }
      closeErr('package_not_found');
      return;
    }

    const chunkSize = Math.max(4096, Math.min(1024 * 1024, Number(process.env.HUB_SKILLS_DOWNLOAD_CHUNK_BYTES || 256 * 1024)));
    let seq = 0;
    for (let off = 0; off < data.length; off += chunkSize) {
      const chunk = data.slice(off, Math.min(data.length, off + chunkSize));
      call.write({ package_sha256, seq, data: chunk, eof: false });
      seq += 1;
    }
    call.write({ package_sha256, seq, data: Buffer.alloc(0), eof: true });
    if (identity) {
      appendSkillsAudit({
        event_type: 'skills.package.downloaded',
        device_id: identity.device_id,
        user_id: identity.user_id,
        app_id: identity.app_id,
        project_id: identity.project_id,
        session_id: identity.session_id,
        request_id: '',
        ok: true,
        ext: {
          package_sha256,
          bytes: data.length,
          chunks: seq + 1,
        },
      });
    }
    call.end();
  }

  // -------------------- HubAdmin --------------------
  function SetKillSwitch(call, callback) {
    const auth = requireAdminAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    const req = call.request || {};
    const scope = String(req.scope || '').trim();
    if (!scope) {
      callback(new Error('missing scope'));
      return;
    }

    let row;
    try {
      row = db.upsertKillSwitch({
        scope,
        models_disabled: !!req.models_disabled,
        network_disabled: !!req.network_disabled,
        reason: req.reason ? String(req.reason) : '',
      });
    } catch (e) {
      callback(new Error(String(e?.message || e || 'killswitch_failed')));
      return;
    }

    const ks = {
      scope: String(row?.scope || scope),
      models_disabled: !!Number(row?.models_disabled || 0),
      network_disabled: !!Number(row?.network_disabled || 0),
      reason: row?.reason ? String(row.reason) : '',
      updated_at_ms: Number(row?.updated_at_ms || nowMs()),
    };

    // Audit + push.
    const admin = req.admin || {};
    db.appendAudit({
      event_type: 'killswitch.set',
      created_at_ms: nowMs(),
      severity: 'security',
      device_id: String(admin.device_id || 'hub_admin'),
      user_id: admin.user_id ? String(admin.user_id) : null,
      app_id: String(admin.app_id || 'hub_admin'),
      project_id: admin.project_id ? String(admin.project_id) : null,
      session_id: admin.session_id ? String(admin.session_id) : null,
      request_id: req.request_id ? String(req.request_id) : null,
      capability: 'unknown',
      model_id: null,
      network_allowed: null,
      ok: true,
      ext_json: JSON.stringify({ scope, models_disabled: ks.models_disabled, network_disabled: ks.network_disabled }),
    });

    bus.emitHubEvent(bus.killSwitchUpdated(ks));
    callback(null, { kill_switch: ks });
  }

  function GetKillSwitch(call, callback) {
    const auth = requireAdminAuth(call);
    if (!auth.ok) {
      callback(new Error(auth.message));
      return;
    }
    const req = call.request || {};
    const scope = String(req.scope || '').trim();
    if (!scope) {
      callback(new Error('missing scope'));
      return;
    }
    const row = db.getKillSwitch(scope);
    const ks = row
      ? {
          scope: String(row.scope || scope),
          models_disabled: !!Number(row.models_disabled || 0),
          network_disabled: !!Number(row.network_disabled || 0),
          reason: row.reason ? String(row.reason) : '',
          updated_at_ms: Number(row.updated_at_ms || 0),
        }
      : { scope, models_disabled: false, network_disabled: false, reason: '', updated_at_ms: 0 };
    callback(null, { kill_switch: ks });
  }

  return {
    HubModels: { ListModels },
    HubGrants: { RequestGrant, ApproveGrant, DenyGrant, RevokeGrant },
    HubAI: { Generate, Cancel },
    HubWeb: { Fetch },
    HubEvents: { Subscribe },
    HubRuntime: {
      GetSchedulerStatus,
      GetPendingGrantRequests,
      GetConnectorIngressReceipts,
      GetAutonomyPolicyOverrides,
      ApprovePendingGrantRequest,
      DenyPendingGrantRequest,
    },
    HubAudit: { ListAuditEvents },
    HubMemory: {
      GetOrCreateThread,
      AppendTurns,
      GetWorkingSet,
      UpsertCanonicalMemory,
      ListCanonicalMemory,
      UpsertProjectLineage,
      GetProjectLineageTree,
      AttachDispatchContext,
      GetRiskTuningProfile,
      EvaluateRiskTuningProfile,
      PromoteRiskTuningProfile,
      GetVoiceWakeProfile,
      SetVoiceWakeProfile,
      IssueVoiceGrantChallenge,
      VerifyVoiceGrantResponse,
      RegisterAgentCapsule,
      VerifyAgentCapsule,
      ActivateAgentCapsule,
      AgentSessionOpen,
      AgentToolRequest,
      AgentToolGrantDecision,
      AgentToolExecute,
      CreatePaymentIntent,
      AttachPaymentEvidence,
      IssuePaymentChallenge,
      ConfirmPaymentIntent,
      AbortPaymentIntent,
      ProjectHeartbeat,
      GetDispatchPlan,
      LongtermMarkdownExport,
      LongtermMarkdownBeginEdit,
      LongtermMarkdownApplyPatch,
      LongtermMarkdownReview,
      LongtermMarkdownWriteback,
      LongtermMarkdownRollback,
    },
    HubSkills: { SearchSkills, UploadSkillPackage, SetSkillPin, ListResolvedSkills, GetSkillManifest, DownloadSkillPackage },
    HubAdmin: { SetKillSwitch, GetKillSwitch },
  };
}
