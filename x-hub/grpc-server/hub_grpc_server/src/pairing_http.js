import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { nowMs, uuid } from './util.js';
import { resolveRuntimeBaseDir } from './local_runtime_ipc.js';
import { pushHubNotification } from './hub_ipc.js';
import {
  findClientByToken,
  loadClients,
  findClientByAccessKeyId,
  getClientAuthStatus,
  touchClientUsageByToken,
  generateAccessKeyId,
  redactClientToken,
  invalidateClientsCache,
} from './clients.js';
import { upsertDevicePresence } from './device_presence.js';
import {
  ensureHubTlsMaterial,
  readHubCaCertPem,
  readIssuedClientCertPem,
  signClientCertFromCsr,
  tlsModeFromEnv,
  tlsServerNameFromEnv,
} from './tls_support.js';
import {
  resolveHubIdentity,
  resolveHubInternetHostHint,
} from './hub_identity.js';
import {
  buildNonMessageIngressGateSnapshot,
  buildNonMessageIngressGateSnapshotFromAuditRows,
  buildNonMessageIngressScanStats,
  evaluateConnectorIngressWithAudit,
} from './connector_ingress_authorizer.js';
import { createConnectorReconnectOrchestrator } from './connector_reconnect_orchestrator.js';
import { createConnectorTargetOrderingGuard } from './connector_target_ordering_guard.js';
import { createConnectorDeliveryReceiptCompensator } from './connector_delivery_receipt_compensator.js';
import {
  getChannelOnboardingDiscoveryTicketById,
  getLatestChannelOnboardingApprovalDecisionByTicketId,
  listChannelOnboardingDiscoveryTickets,
  reviewChannelOnboardingDiscoveryTicket,
} from './channel_onboarding_discovery_store.js';
import { buildChannelRuntimeStatusSnapshot } from './channel_runtime_snapshot.js';
import {
  flushChannelOutboxForTicket,
  retryChannelOnboardingOutbox,
  runApprovedChannelOnboardingAutomation,
} from './channel_onboarding_automation.js';
import { listChannelOnboardingDeliveryReadiness } from './channel_onboarding_delivery_readiness.js';
import { getChannelOnboardingAutomationState } from './channel_onboarding_status_view.js';
import {
  getChannelOnboardingAutoBindRevocationByTicketId,
  revokeApprovedChannelOnboardingAutoBind,
} from './channel_onboarding_transaction.js';
import {
  getSkillPackageDoctorReport,
  listOfficialSkillPackageLifecycleRows,
} from './skills_store.js';
import {
  buildOperatorChannelLiveTestEvidenceReport,
  operatorChannelLiveTestProviderRow,
} from './operator_channel_live_test_evidence.js';

const XT_HUB_CONTRACT_ENDPOINT = '/xt/hub-contract';
const XT_HUB_CONTRACT_SCHEMA_VERSION = 'xhub.rust_hub.xt_contract.v1';
const HUB_PRODUCT_BOUNDARY = 'swift_shell_rust_kernel';

function safeString(v) {
  return String(v ?? '').trim();
}

function safeTimingEqual(left, right) {
  const lhs = Buffer.from(String(left || ''), 'utf8');
  const rhs = Buffer.from(String(right || ''), 'utf8');
  if (lhs.length !== rhs.length) return false;
  try {
    return crypto.timingSafeEqual(lhs, rhs);
  } catch {
    return false;
  }
}

function safeShellValue(v) {
  // For copy-pasteable shell snippets (connect_env). Avoid newlines/NUL.
  return String(v ?? '')
    .replaceAll('\u0000', '')
    .replace(/\r|\n/g, ' ')
    .trim();
}

function shellQuoteSingle(v) {
  const s = safeShellValue(v);
  // POSIX shell single-quote escaping: close -> escaped quote -> reopen.
  return `'${s.replaceAll("'", "'\\''")}'`;
}

function safeStringArray(v) {
  if (v == null) return [];
  if (Array.isArray(v)) return v.map((s) => safeString(s)).filter(Boolean);
  const s = safeString(v);
  if (!s) return [];
  return s
    .split(',')
    .map((x) => safeString(x))
    .filter(Boolean);
}

function deriveEffectiveChannelOnboardingStatus(ticket, {
  latestDecision = null,
  revocation = null,
} = {}) {
  const revoked = safeString(revocation?.status).toLowerCase();
  if (revoked === 'revoked') return 'revoked';
  const latest = safeString(latestDecision?.decision).toLowerCase();
  if (latest === 'approve') return 'approved';
  if (latest === 'hold') return 'held';
  if (latest === 'reject') return 'rejected';
  return safeString(ticket?.status).toLowerCase();
}

function toHttpChannelOnboardingTicket(ticket, {
  latestDecision = null,
  revocation = null,
} = {}) {
  if (!ticket || typeof ticket !== 'object') return null;
  return {
    schema_version: safeString(ticket.schema_version),
    ticket_id: safeString(ticket.ticket_id),
    provider: safeString(ticket.provider),
    account_id: safeString(ticket.account_id),
    external_user_id: safeString(ticket.external_user_id),
    external_tenant_id: safeString(ticket.external_tenant_id),
    conversation_id: safeString(ticket.conversation_id),
    thread_key: safeString(ticket.thread_key),
    ingress_surface: safeString(ticket.ingress_surface),
    first_message_preview: safeString(ticket.first_message_preview),
    proposed_scope_type: safeString(ticket.proposed_scope_type),
    proposed_scope_id: safeString(ticket.proposed_scope_id),
    recommended_binding_mode: safeString(ticket.recommended_binding_mode),
    status: safeString(ticket.status),
    effective_status: deriveEffectiveChannelOnboardingStatus(ticket, {
      latestDecision,
      revocation,
    }),
    event_count: Math.max(0, Number(ticket.event_count || 0)),
    first_seen_at_ms: Math.max(0, Number(ticket.first_seen_at_ms || 0)),
    last_seen_at_ms: Math.max(0, Number(ticket.last_seen_at_ms || 0)),
    created_at_ms: Math.max(0, Number(ticket.created_at_ms || 0)),
    updated_at_ms: Math.max(0, Number(ticket.updated_at_ms || 0)),
    expires_at_ms: Math.max(0, Number(ticket.expires_at_ms || 0)),
    last_request_id: safeString(ticket.last_request_id),
    audit_ref: safeString(ticket.audit_ref),
  };
}

function toHttpChannelOnboardingDecision(decision) {
  if (!decision || typeof decision !== 'object') return null;
  return {
    schema_version: safeString(decision.schema_version),
    decision_id: safeString(decision.decision_id),
    ticket_id: safeString(decision.ticket_id),
    decision: safeString(decision.decision),
    approved_by_hub_user_id: safeString(decision.approved_by_hub_user_id),
    approved_via: safeString(decision.approved_via),
    hub_user_id: safeString(decision.hub_user_id),
    scope_type: safeString(decision.scope_type),
    scope_id: safeString(decision.scope_id),
    binding_mode: safeString(decision.binding_mode),
    preferred_device_id: safeString(decision.preferred_device_id),
    allowed_actions: Array.isArray(decision.allowed_actions)
      ? decision.allowed_actions.map((item) => safeString(item)).filter(Boolean)
      : [],
    grant_profile: safeString(decision.grant_profile),
    note: safeString(decision.note),
    created_at_ms: Math.max(0, Number(decision.created_at_ms || 0)),
    audit_ref: safeString(decision.audit_ref),
  };
}

function toHttpChannelOnboardingRevocation(revocation) {
  if (!revocation || typeof revocation !== 'object') return null;
  return {
    schema_version: safeString(revocation.schema_version),
    revocation_id: safeString(revocation.revocation_id),
    ticket_id: safeString(revocation.ticket_id),
    receipt_id: safeString(revocation.receipt_id),
    decision_id: safeString(revocation.decision_id),
    status: safeString(revocation.status),
    provider: safeString(revocation.provider),
    account_id: safeString(revocation.account_id),
    external_user_id: safeString(revocation.external_user_id),
    external_tenant_id: safeString(revocation.external_tenant_id),
    conversation_id: safeString(revocation.conversation_id),
    thread_key: safeString(revocation.thread_key),
    hub_user_id: safeString(revocation.hub_user_id),
    scope_type: safeString(revocation.scope_type),
    scope_id: safeString(revocation.scope_id),
    identity_actor_ref: safeString(revocation.identity_actor_ref),
    channel_binding_id: safeString(revocation.channel_binding_id),
    revoked_by_hub_user_id: safeString(revocation.revoked_by_hub_user_id),
    revoked_via: safeString(revocation.revoked_via),
    note: safeString(revocation.note),
    created_at_ms: Math.max(0, Number(revocation.created_at_ms || 0)),
    updated_at_ms: Math.max(0, Number(revocation.updated_at_ms || 0)),
    audit_ref: safeString(revocation.audit_ref),
  };
}

function toHttpChannelOnboardingAutomationState(state) {
  if (!state || typeof state !== 'object') return null;
  const heartbeatGovernanceSnapshot = (() => {
    const raw = safeString(state?.first_smoke?.heartbeat_governance_snapshot_json);
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
    } catch {
      return null;
    }
  })();
  const firstSmoke = state.first_smoke && typeof state.first_smoke === 'object'
    ? {
        schema_version: safeString(state.first_smoke.schema_version),
        receipt_id: safeString(state.first_smoke.receipt_id),
        ticket_id: safeString(state.first_smoke.ticket_id),
        decision_id: safeString(state.first_smoke.decision_id),
        provider: safeString(state.first_smoke.provider),
        action_name: safeString(state.first_smoke.action_name),
        status: safeString(state.first_smoke.status),
        route_mode: safeString(state.first_smoke.route_mode),
        deny_code: safeString(state.first_smoke.deny_code),
        detail: safeString(state.first_smoke.detail),
        remediation_hint: safeString(state.first_smoke.remediation_hint),
        project_id: safeString(state.first_smoke.project_id),
        binding_id: safeString(state.first_smoke.binding_id),
        ack_outbox_item_id: safeString(state.first_smoke.ack_outbox_item_id),
        smoke_outbox_item_id: safeString(state.first_smoke.smoke_outbox_item_id),
        created_at_ms: Math.max(0, Number(state.first_smoke.created_at_ms || 0)),
        updated_at_ms: Math.max(0, Number(state.first_smoke.updated_at_ms || 0)),
        audit_ref: safeString(state.first_smoke.audit_ref),
        heartbeat_governance_snapshot_json: safeString(state.first_smoke.heartbeat_governance_snapshot_json),
        heartbeat_governance_snapshot: heartbeatGovernanceSnapshot,
      }
    : null;
  const deliveryReadiness = state.delivery_readiness && typeof state.delivery_readiness === 'object'
    ? {
        provider: safeString(state.delivery_readiness.provider),
        ready: !!state.delivery_readiness.ready,
        reply_enabled: !!state.delivery_readiness.reply_enabled,
        credentials_configured: !!state.delivery_readiness.credentials_configured,
        deny_code: safeString(state.delivery_readiness.deny_code),
        remediation_hint: safeString(state.delivery_readiness.remediation_hint),
        repair_hints: Array.isArray(state.delivery_readiness.repair_hints)
          ? state.delivery_readiness.repair_hints.map((item) => safeString(item)).filter(Boolean)
          : [],
      }
    : null;
  return {
    schema_version: safeString(state.schema_version),
    ticket_id: safeString(state.ticket_id),
    first_smoke: firstSmoke,
    outbox_items: Array.isArray(state.outbox_items)
      ? state.outbox_items.map((item) => ({
          schema_version: safeString(item?.schema_version),
          item_id: safeString(item?.item_id),
          provider: safeString(item?.provider),
          item_kind: safeString(item?.item_kind),
          status: safeString(item?.status),
          ticket_id: safeString(item?.ticket_id),
          decision_id: safeString(item?.decision_id),
          receipt_id: safeString(item?.receipt_id),
          attempt_count: Math.max(0, Number(item?.attempt_count || 0)),
          last_error_code: safeString(item?.last_error_code),
          last_error_message: safeString(item?.last_error_message),
          provider_message_ref: safeString(item?.provider_message_ref),
          created_at_ms: Math.max(0, Number(item?.created_at_ms || 0)),
          updated_at_ms: Math.max(0, Number(item?.updated_at_ms || 0)),
          delivered_at_ms: Math.max(0, Number(item?.delivered_at_ms || 0)),
          audit_ref: safeString(item?.audit_ref),
        }))
      : [],
    outbox_pending_count: Math.max(0, Number(state.outbox_pending_count || 0)),
    outbox_delivered_count: Math.max(0, Number(state.outbox_delivered_count || 0)),
    delivery_readiness: deliveryReadiness,
  };
}

function toHttpChannelOnboardingDeliveryReadiness(readiness) {
  if (!readiness || typeof readiness !== 'object') return null;
  return {
    provider: safeString(readiness.provider),
    ready: !!readiness.ready,
    reply_enabled: !!readiness.reply_enabled,
    credentials_configured: !!readiness.credentials_configured,
    deny_code: safeString(readiness.deny_code),
    remediation_hint: safeString(readiness.remediation_hint),
    repair_hints: Array.isArray(readiness.repair_hints)
      ? readiness.repair_hints.map((item) => safeString(item)).filter(Boolean)
      : [],
  };
}

function loadChannelRuntimeStatusSnapshot(runtimeBaseDir = '') {
  const base = safeString(runtimeBaseDir || resolveRuntimeBaseDir());
  const filePath = path.join(base, 'channel_runtime_accounts_status.json');
  let parsed = null;
  try {
    parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    parsed = null;
  }
  return buildChannelRuntimeStatusSnapshot(Array.isArray(parsed?.rows) ? parsed.rows : [], {
    updated_at_ms: Math.max(0, Number(parsed?.updated_at_ms || 0)),
  });
}

function toHttpChannelProviderRuntimeStatus(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    provider: safeString(row.provider),
    label: safeString(row.label),
    detail_label: safeString(row.detail_label),
    release_stage: safeString(row.release_stage),
    automation_path: safeString(row.automation_path),
    threading_mode: safeString(row.threading_mode),
    approval_surface: safeString(row.approval_surface),
    capabilities: Array.isArray(row.capabilities) ? row.capabilities.map((item) => safeString(item)).filter(Boolean) : [],
    endpoint_visibility: safeString(row.endpoint_visibility),
    operator_surface: safeString(row.operator_surface),
    allow_direct_xt: !!row.allow_direct_xt,
    require_real_evidence: !!row.require_real_evidence,
    release_blocked: !!row.release_blocked,
    runtime_state: safeString(row.runtime_state),
    account_count: Math.max(0, Number(row.account_count || 0)),
    configured_accounts: Math.max(0, Number(row.configured_accounts || 0)),
    ready_accounts: Math.max(0, Number(row.ready_accounts || 0)),
    degraded_accounts: Math.max(0, Number(row.degraded_accounts || 0)),
    active_binding_count: Math.max(0, Number(row.active_binding_count || 0)),
    delivery_ready: !!row.delivery_ready,
    command_entry_ready: !!row.command_entry_ready,
    last_error_code: safeString(row.last_error_code),
    updated_at_ms: Math.max(0, Number(row.updated_at_ms || 0)),
    repair_hints: Array.isArray(row.repair_hints)
      ? row.repair_hints.map((item) => safeString(item)).filter(Boolean)
      : [],
  };
}

function toHttpPendingGrantRequest(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    grant_request_id: safeString(row.grant_request_id),
    request_id: safeString(row.request_id),
    client: {
      device_id: safeString(row.device_id),
      user_id: safeString(row.user_id),
      app_id: safeString(row.app_id),
      project_id: safeString(row.project_id),
      session_id: '',
    },
    capability: safeString(row.capability),
    model_id: safeString(row.model_id),
    reason: safeString(row.reason),
    requested_ttl_sec: Math.max(0, Number(row.requested_ttl_sec || 0)),
    requested_token_cap: Math.max(0, Number(row.requested_token_cap || 0)),
    status: safeString(row.status),
    decision: safeString(row.decision),
    created_at_ms: Math.max(0, Number(row.created_at_ms || 0)),
    decided_at_ms: Math.max(0, Number(row.decided_at_ms || 0)),
  };
}

function buildHttpOperatorChannelLiveTestEvidenceReport({
  provider = '',
  verdict = '',
  summary = '',
  performedAt = '',
  evidenceRefs = [],
  readinessRows = [],
  runtimeRows = [],
  ticketDetail = null,
  adminBaseUrl = '',
  requiredNextStep = '',
} = {}) {
  return buildOperatorChannelLiveTestEvidenceReport({
    provider,
    verdict,
    summary,
    performedAt,
    evidenceRefs,
    readiness: operatorChannelLiveTestProviderRow({ providers: readinessRows }, provider),
    runtimeStatus: operatorChannelLiveTestProviderRow({ providers: runtimeRows }, provider),
    ticketDetail,
    adminBaseUrl,
    outputPath: '',
    requiredNextStep,
  });
}

function jsonResponse(res, status, obj) {
  const body = JSON.stringify(obj ?? {});
  res.writeHead(Number(status || 200), {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  res.end(body);
}

function textResponse(res, status, text, headers = {}) {
  const body = String(text ?? '');
  res.writeHead(Number(status || 200), {
    'content-type': 'text/plain; charset=utf-8',
    'cache-control': 'no-store',
    ...headers,
  });
  res.end(body);
}

function readTextFileTrimmed(filePath) {
  const p = safeString(filePath);
  if (!p) return '';
  try {
    return safeString(fs.readFileSync(p, 'utf8'));
  } catch {
    return '';
  }
}

function rustHubHTTPBaseURL() {
  const raw = safeString(
    process.env.XHUB_RUST_HUB_HTTP_BASE_URL
      || process.env.XHUB_RUST_HTTP_BASE_URL
      || process.env.XHUBD_HTTP_BASE_URL
      || 'http://127.0.0.1:50151'
  );
  try {
    const url = new URL(raw);
    if (url.protocol !== 'http:') return 'http://127.0.0.1:50151';
    return url.toString().replace(/\/+$/, '');
  } catch {
    return 'http://127.0.0.1:50151';
  }
}

function rustHubHTTPAccessKey() {
  const direct = safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY || process.env.XHUB_RUST_HUB_ACCESS_KEY);
  if (direct) return direct;

  for (const key of ['XHUB_RUST_HTTP_ACCESS_KEY_FILE', 'XHUB_RUST_HUB_ACCESS_KEY_FILE']) {
    const value = readTextFileTrimmed(process.env[key]);
    if (value) return value;
  }

  const root = safeString(process.env.XHUB_RUST_HUB_ROOT);
  if (root) {
    for (const rel of [
      'secrets/xhubd_http_access_key',
      'secrets/xhubd_domain_access_key',
      'secrets/xhubd_lan_access_key',
    ]) {
      const value = readTextFileTrimmed(path.join(root, rel));
      if (value) return value;
    }
  }
  return '';
}

function fetchRustHubJSONPath(routePath, { timeoutMs = 1500 } = {}) {
  return new Promise((resolve) => {
    const base = rustHubHTTPBaseURL();
    let target;
    try {
      target = new URL(routePath, `${base}/`);
    } catch {
      resolve({
        ok: false,
        status: 500,
        text: '',
        error: 'rust_kernel_base_url_invalid',
      });
      return;
    }

    const accessKey = rustHubHTTPAccessKey();
    const headers = {
      accept: 'application/json',
    };
    if (accessKey) {
      headers.authorization = `Bearer ${accessKey}`;
      headers['x-xhub-access-key'] = accessKey;
    }

    const request = http.request({
      method: 'GET',
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers,
      timeout: Math.max(250, Math.min(10_000, Number(timeoutMs || 0))),
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      response.on('end', () => {
        resolve({
          ok: true,
          status: Number(response.statusCode || 0),
          text: Buffer.concat(chunks).toString('utf8'),
          contentType: safeString(response.headers?.['content-type']) || 'application/json; charset=utf-8',
          sourceBaseURL: base,
        });
      });
    });

    request.on('error', (err) => {
      resolve({
        ok: false,
        status: 503,
        text: '',
        error: safeString(err?.message) || 'rust_kernel_contract_unavailable',
        sourceBaseURL: base,
      });
    });
    request.on('timeout', () => {
      request.destroy(new Error('rust_kernel_contract_timeout'));
    });
    request.end();
  });
}

function sha256Hex(text) {
  return crypto.createHash('sha256').update(String(text || ''), 'utf8').digest('hex');
}

function readTextFileTrimmed(filePath) {
  const p = safeString(filePath);
  if (!p) return '';
  try {
    return fs.readFileSync(p, 'utf8').trim();
  } catch {
    return '';
  }
}

function rustHubHTTPBaseURL() {
  const raw = safeString(
    process.env.XHUB_RUST_HUB_HTTP_BASE_URL
      || process.env.XHUB_RUST_HTTP_BASE_URL
      || process.env.XHUBD_HTTP_BASE_URL
      || 'http://127.0.0.1:50151'
  );
  try {
    const url = new URL(raw);
    if (url.protocol !== 'http:') return 'http://127.0.0.1:50151';
    return url.toString().replace(/\/+$/, '');
  } catch {
    return 'http://127.0.0.1:50151';
  }
}

function rustHubHTTPAccessKey() {
  const direct = safeString(process.env.XHUB_RUST_HTTP_ACCESS_KEY || process.env.XHUB_RUST_HUB_ACCESS_KEY);
  if (direct) return direct;

  for (const key of ['XHUB_RUST_HTTP_ACCESS_KEY_FILE', 'XHUB_RUST_HUB_ACCESS_KEY_FILE']) {
    const value = readTextFileTrimmed(process.env[key]);
    if (value) return value;
  }

  const root = safeString(process.env.XHUB_RUST_HUB_ROOT);
  if (root) {
    for (const rel of [
      'secrets/xhubd_http_access_key',
      'secrets/xhubd_domain_access_key',
      'secrets/xhubd_lan_access_key',
    ]) {
      const value = readTextFileTrimmed(path.join(root, rel));
      if (value) return value;
    }
  }
  return '';
}

function fetchRustHubJSONPath(routePath, { timeoutMs = 1500 } = {}) {
  return new Promise((resolve) => {
    const base = rustHubHTTPBaseURL();
    let target;
    try {
      target = new URL(routePath, `${base}/`);
    } catch {
      resolve({
        ok: false,
        status: 500,
        text: '',
        error: 'rust_kernel_base_url_invalid',
      });
      return;
    }

    const accessKey = rustHubHTTPAccessKey();
    const headers = {
      accept: 'application/json',
    };
    if (accessKey) {
      headers.authorization = `Bearer ${accessKey}`;
      headers['x-xhub-access-key'] = accessKey;
    }

    const request = http.request({
      method: 'GET',
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers,
      timeout: Math.max(250, Math.min(10_000, Number(timeoutMs || 0))),
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      response.on('end', () => {
        resolve({
          ok: true,
          status: Number(response.statusCode || 0),
          text: Buffer.concat(chunks).toString('utf8'),
          contentType: safeString(response.headers?.['content-type']) || 'application/json; charset=utf-8',
          sourceBaseURL: base,
        });
      });
    });

    request.on('error', (err) => {
      resolve({
        ok: false,
        status: 503,
        text: '',
        error: safeString(err?.message) || 'rust_kernel_contract_unavailable',
        sourceBaseURL: base,
      });
    });
    request.on('timeout', () => {
      request.destroy(new Error('rust_kernel_contract_timeout'));
    });
    request.end();
  });
}

function sha256FileHex(filePath) {
  const buf = fs.readFileSync(String(filePath || ''));
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function peerIpFromReq(req) {
  try {
    let ip = safeString(req?.socket?.remoteAddress);
    if (!ip) return '';
    if (ip.startsWith('::ffff:')) ip = ip.slice('::ffff:'.length);
    if (ip === '::1') return '::1';
    return ip;
  } catch {
    return '';
  }
}

function ipv4ToInt(ip) {
  const s = safeString(ip);
  const parts = s.split('.');
  if (parts.length !== 4) return null;
  let out = 0;
  for (const p of parts) {
    if (!/^\d+$/.test(p)) return null;
    const n = Number.parseInt(p, 10);
    if (n < 0 || n > 255) return null;
    out = (out << 8) | n;
  }
  return out >>> 0;
}

function isPrivateIPv4(ip) {
  const n = ipv4ToInt(ip);
  if (n == null) return false;
  const u = n >>> 0;
  if (((u & 0xff000000) >>> 0) === 0x0a000000) return true; // 10.0.0.0/8
  if (((u & 0xfff00000) >>> 0) === 0xac100000) return true; // 172.16.0.0/12
  if (((u & 0xffff0000) >>> 0) === 0xc0a80000) return true; // 192.168.0.0/16
  if (((u & 0xffc00000) >>> 0) === 0x64400000) return true; // 100.64.0.0/10 (RFC 6598), commonly used by Tailscale
  return false;
}

function isLoopbackIp(ip) {
  const s = safeString(ip);
  if (!s) return false;
  if (s === '::1') return true;
  const n = ipv4ToInt(s);
  if (n == null) return false;
  return (((n >>> 0) & 0xff000000) >>> 0) === 0x7f000000; // 127.0.0.0/8
}

function ipv4InCidr(ip, cidrText) {
  const cidr = safeString(cidrText);
  if (!cidr) return false;
  const [baseIp, maskText] = cidr.split('/');
  const maskBits = maskText == null || maskText === '' ? 32 : Number.parseInt(String(maskText), 10);
  if (!Number.isFinite(maskBits) || maskBits < 0 || maskBits > 32) return false;
  const ipN = ipv4ToInt(ip);
  const baseN = ipv4ToInt(baseIp);
  if (ipN == null || baseN == null) return false;
  const mask = maskBits === 0 ? 0 : ((0xffffffff << (32 - maskBits)) >>> 0);
  return (((ipN & mask) >>> 0) === ((baseN & mask) >>> 0));
}

function peerAllowedByRules(peerIp, allowedRules) {
  const ip = safeString(peerIp);
  const rules = Array.isArray(allowedRules) ? allowedRules : [];
  if (!rules.length) return true;
  if (!ip) return false;

  for (const raw of rules) {
    const r = safeString(raw);
    if (!r) continue;
    const lower = r.toLowerCase();
    if (lower === 'any' || lower === '*') return true;
    if (lower === 'loopback' || lower === 'localhost') {
      if (isLoopbackIp(ip)) return true;
      continue;
    }
    if (lower === 'private') {
      if (isPrivateIPv4(ip)) return true;
      continue;
    }
    if (r === ip) return true;
    if (r.includes('/')) {
      if (ipv4InCidr(ip, r)) return true;
      continue;
    }
    if (ipv4InCidr(ip, `${r}/32`)) return true;
  }
  return false;
}

function readJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
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
  const tmp = path.join(dir, `.${fileName}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`);
  try {
    // hub_grpc_clients.json includes bearer tokens; keep it owner-readable only.
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', { encoding: 'utf8', mode: 0o600 });
    fs.renameSync(tmp, outPath);
    try {
      fs.chmodSync(outPath, 0o600);
    } catch {
      // ignore
    }
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

function firstForwardedForIp(req) {
  const raw = safeString(req?.headers?.['x-forwarded-for']);
  if (!raw) return '';
  return safeString(raw.split(',')[0]);
}

function inviteTokenConfigPath(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'hub_external_invite_token.json');
}

function loadInviteTokenRecord(runtimeBaseDir) {
  const obj = readJsonSafe(inviteTokenConfigPath(runtimeBaseDir));
  if (!obj || typeof obj !== 'object') return null;
  const token_id = safeString(obj.token_id);
  const token_secret = safeString(obj.token_secret);
  if (!token_id || !token_secret) return null;
  return {
    token_id,
    token_secret,
    created_at_ms: Math.max(0, Number(obj.created_at_ms || 0)),
  };
}

function pairingProfileEpochFromSnapshot(snapshot) {
  return Math.max(0, Number(snapshot?.updated_at_ms || 0));
}

function buildRoutePackVersion({
  hubIdentity,
  internetHostHint,
  pairingPort,
  grpcPort,
  inviteRecord,
  tlsMode,
  tlsServerName,
} = {}) {
  const ingredients = [
    safeString(hubIdentity?.hub_instance_id),
    safeString(internetHostHint),
    String(Number(pairingPort || 0) || 50052),
    String(Number(grpcPort || 0) || 50051),
    safeString(inviteRecord?.token_id),
    String(Math.max(0, Number(inviteRecord?.created_at_ms || 0))),
    safeString(tlsMode),
    safeString(tlsServerName),
  ];
  return `route_pack_${sha256Hex(ingredients.join('|')).slice(0, 24)}`;
}

function buildPairingRouteMetadata({
  runtimeBaseDir,
  hubIdentity,
  internetHostHint,
  pairingPort,
  grpcPort,
  tlsMode,
  tlsServerName,
  clientsSnapshot = null,
} = {}) {
  const snapshot = clientsSnapshot || readClientsSnapshot(runtimeBaseDir);
  const inviteRecord = loadInviteTokenRecord(runtimeBaseDir);
  return {
    pairing_profile_epoch: pairingProfileEpochFromSnapshot(snapshot),
    route_pack_version: buildRoutePackVersion({
      hubIdentity,
      internetHostHint,
      pairingPort,
      grpcPort,
      inviteRecord,
      tlsMode,
      tlsServerName,
    }),
  };
}

export function shouldRequireInviteTokenForPairingRequest({
  peer_ip = '',
  forwarded_for = '',
  env = process.env,
} = {}) {
  const force = safeString(env?.HUB_PAIRING_REQUIRE_INVITE_TOKEN);
  if (force === '1' || force.toLowerCase() === 'true') {
    return true;
  }
  const peerIp = safeString(peer_ip);
  const forwarded = safeString(forwarded_for);
  const policyPeerIp = forwarded && (isLoopbackIp(peerIp) || isPrivateIPv4(peerIp))
    ? forwarded
    : peerIp;
  return !(isLoopbackIp(policyPeerIp) || isPrivateIPv4(policyPeerIp));
}

function effectivePeerIpForPairingSourcePolicy({
  peer_ip = '',
  forwarded_for = '',
} = {}) {
  const peerIp = safeString(peer_ip);
  const forwarded = safeString(forwarded_for);
  if (forwarded && (isLoopbackIp(peerIp) || isPrivateIPv4(peerIp))) {
    return forwarded;
  }
  return peerIp;
}

export function resolveFirstPairSameLanAllowedCidrs(env = process.env) {
  const explicit = safeStringArray(env?.HUB_PAIRING_FIRST_PAIR_ALLOWED_CIDRS || '');
  const source = explicit.length
    ? explicit
    : safeStringArray(env?.HUB_ALLOWED_CIDRS || env?.HUB_PAIRING_ALLOWED_CIDRS || '');
  const out = [];
  const seen = new Set();
  for (const raw of source) {
    const rule = safeString(raw);
    if (!rule) continue;
    const lower = rule.toLowerCase();
    if (lower === 'any' || lower === '*' || lower === 'private' || lower === 'localhost') {
      continue;
    }
    if (seen.has(lower)) continue;
    seen.add(lower);
    out.push(rule);
  }
  if (out.length === 0) {
    out.push('loopback');
  }
  return out;
}

export function evaluateFirstPairSameLanRequirement({
  peer_ip = '',
  forwarded_for = '',
  env = process.env,
} = {}) {
  const force = safeString(env?.HUB_PAIRING_REQUIRE_SAME_LAN);
  const sameLanRequired = !(force === '0' || force.toLowerCase() === 'false');
  const effectivePeerIp = effectivePeerIpForPairingSourcePolicy({
    peer_ip,
    forwarded_for,
  });
  const allowed_cidrs = resolveFirstPairSameLanAllowedCidrs(env);
  if (!sameLanRequired) {
    return {
      ok: true,
      required: false,
      effective_peer_ip: effectivePeerIp,
      allowed_cidrs,
    };
  }
  return {
    ok: peerAllowedByRules(effectivePeerIp, allowed_cidrs),
    required: true,
    effective_peer_ip: effectivePeerIp,
    allowed_cidrs,
  };
}

function connectorIngressReceiptsFileName() {
  return 'connector_ingress_receipts_status.json';
}

function normalizeConnectorIngressReceiptRow(row = {}) {
  const receipt_id = safeString(row.receipt_id);
  if (!receipt_id) return null;
  return {
    receipt_id,
    request_id: safeString(row.request_id),
    project_id: safeString(row.project_id),
    connector: safeString(row.connector).toLowerCase(),
    target_id: safeString(row.target_id),
    ingress_type: safeString(row.ingress_type).toLowerCase(),
    channel_scope: safeString(row.channel_scope).toLowerCase(),
    source_id: safeString(row.source_id),
    message_id: safeString(row.message_id),
    dedupe_key: safeString(row.dedupe_key),
    received_at_ms: Math.max(0, Number(row.received_at_ms || 0)),
    event_sequence: Math.max(0, Number(row.event_sequence || 0)),
    delivery_state: safeString(row.delivery_state).toLowerCase(),
    runtime_state: safeString(row.runtime_state).toLowerCase(),
  };
}

function appendConnectorIngressReceiptSnapshot(runtimeBaseDir, row = {}) {
  const base = safeString(runtimeBaseDir || resolveRuntimeBaseDir());
  if (!base) return false;

  const normalized = normalizeConnectorIngressReceiptRow(row);
  if (!normalized) return false;

  const existing = readJsonSafe(path.join(base, connectorIngressReceiptsFileName()));
  const items = Array.isArray(existing?.items)
    ? existing.items.map(normalizeConnectorIngressReceiptRow).filter(Boolean)
    : [];
  const deduped = new Map(items.map((item) => [item.receipt_id, item]));
  deduped.set(normalized.receipt_id, normalized);

  const limitRaw = Number.parseInt(safeString(process.env.HUB_CONNECTOR_INGRESS_RECEIPTS_MAX || '240'), 10);
  const maxItems = Math.max(16, Math.min(2000, Number.isFinite(limitRaw) ? limitRaw : 240));
  const merged = Array.from(deduped.values())
    .sort((left, right) => {
      const lts = Math.max(0, Number(left?.received_at_ms || 0));
      const rts = Math.max(0, Number(right?.received_at_ms || 0));
      if (lts !== rts) return rts - lts;
      return safeString(left?.receipt_id).localeCompare(safeString(right?.receipt_id));
    })
    .slice(0, maxItems);

  return writeJsonAtomic(base, connectorIngressReceiptsFileName(), {
    schema_version: 'connector_ingress_receipts_status.v1',
    updated_at_ms: Math.max(normalized.received_at_ms, Date.now()),
    items: merged,
  });
}

function clientsConfigPath(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';
  return path.join(base, 'hub_grpc_clients.json');
}

function defaultClientCaps() {
  // Keep in sync with HubGRPCClientsStore.defaultCapabilities() (Swift).
  return ['models', 'events', 'memory', 'skills', 'ai.generate.local'];
}

function defaultAllowedCidrs() {
  // Default to the Hub's LAN allowlist if configured.
  //
  // When the Hub app launches the embedded gRPC server, it sets HUB_ALLOWED_CIDRS
  // to a safe LAN boundary (private + loopback + detected interface subnets).
  //
  // We use that as the default `allowed_cidrs` for newly approved devices so they
  // inherit the same source-IP boundary as the server itself.
  const fromEnv = safeStringArray(process.env.HUB_ALLOWED_CIDRS || process.env.HUB_PAIRING_ALLOWED_CIDRS || '');
  if (fromEnv.length) return fromEnv;
  return ['private', 'loopback'];
}

const PAID_MODEL_SELECTION_MODES = new Set(['off', 'all_paid_models', 'custom_selected_models']);
const POLICY_MODES = new Set(['new_profile', 'legacy_grant']);
const DEFAULT_PAIRING_DAILY_TOKEN_LIMIT = 500000;
const DEFAULT_PAIRING_SINGLE_REQUEST_TOKEN_LIMIT = 12000;
const XT_ACCESS_KEY_MANAGER_APP_IDS = new Set(['x_terminal', 'xterminal']);
const XT_ACCESS_KEY_MANAGER_SCOPES = new Set([
  'hub_access_keys.manage',
  'hub.access_keys.manage',
  'access_keys.manage',
]);

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

function normalizedPaidModelSelectionMode(value, fallback = 'off') {
  const mode = safeString(value).toLowerCase();
  return PAID_MODEL_SELECTION_MODES.has(mode) ? mode : fallback;
}

function normalizedPolicyMode(value, fallback = 'legacy_grant') {
  const mode = safeString(value).toLowerCase();
  return POLICY_MODES.has(mode) ? mode : fallback;
}

function parseDailyTokenLimit(value, fallback = DEFAULT_PAIRING_DAILY_TOKEN_LIMIT) {
  if (value == null || value === '') return fallback;
  const num = Number(value);
  if (!Number.isInteger(num) || num <= 0) return null;
  return num;
}

function derivePolicyCapabilities(capabilities, { paid_model_selection_mode = 'off', default_web_fetch_enabled = false } = {}) {
  const base = uniqueStrings((Array.isArray(capabilities) && capabilities.length ? capabilities : defaultClientCaps()))
    .filter((item) => item !== 'ai.generate.paid' && item !== 'web.fetch');
  if (paid_model_selection_mode !== 'off') base.push('ai.generate.paid');
  if (default_web_fetch_enabled) base.push('web.fetch');
  return uniqueStrings(base);
}

function buildApprovedTrustProfile({
  device_id,
  device_name,
  capabilities,
  paid_model_selection_mode,
  allowed_paid_models,
  default_web_fetch_enabled,
  daily_token_limit,
  audit_ref,
} = {}) {
  const mode = normalizedPaidModelSelectionMode(paid_model_selection_mode, 'off');
  return {
    schema_version: 'hub.paired_terminal_trust_profile.v1',
    device_id: safeString(device_id),
    device_name: safeString(device_name),
    trust_mode: 'trusted_daily',
    capabilities: derivePolicyCapabilities(capabilities, {
      paid_model_selection_mode: mode,
      default_web_fetch_enabled: default_web_fetch_enabled === true,
    }),
    paid_model_policy: {
      schema_version: 'hub.paired_terminal_paid_model_policy.v1',
      mode,
      allowed_model_ids: mode === 'custom_selected_models' ? uniqueStrings(allowed_paid_models) : [],
    },
    network_policy: {
      default_web_fetch_enabled: default_web_fetch_enabled === true,
    },
    budget_policy: {
      daily_token_limit: Math.max(1, Number(daily_token_limit || DEFAULT_PAIRING_DAILY_TOKEN_LIMIT) || DEFAULT_PAIRING_DAILY_TOKEN_LIMIT),
      single_request_token_limit: DEFAULT_PAIRING_SINGLE_REQUEST_TOKEN_LIMIT,
    },
    audit_ref: safeString(audit_ref),
  };
}

function parseApprovedTrustProfile(raw) {
  if (!raw) return null;
  try {
    const obj = JSON.parse(String(raw));
    return obj && typeof obj === 'object' ? obj : null;
  } catch {
    return null;
  }
}

function readClientsSnapshot(runtimeBaseDir) {
  const fp = clientsConfigPath(runtimeBaseDir);
  const obj = readJsonSafe(fp);
  if (!obj || typeof obj !== 'object') {
    return { schema_version: 'hub_grpc_clients.v2', updated_at_ms: 0, clients: [] };
  }
  const clients = Array.isArray(obj.clients) ? obj.clients : Array.isArray(obj.devices) ? obj.devices : [];
  return {
    schema_version: safeString(obj.schema_version) || 'hub_grpc_clients.v2',
    updated_at_ms: Number(obj.updated_at_ms || 0) || 0,
    clients: Array.isArray(clients) ? clients : [],
  };
}

function upsertClientInSnapshot(snap, entry) {
  const out = snap && typeof snap === 'object' ? { ...snap } : { schema_version: 'hub_grpc_clients.v2', updated_at_ms: 0, clients: [] };
  out.schema_version = safeString(out.schema_version) || 'hub_grpc_clients.v2';
  if (!Array.isArray(out.clients)) out.clients = [];
  const did = safeString(entry?.device_id);
  if (!did) return out;

  let replaced = false;
  out.clients = out.clients.map((c) => {
    const curDid = safeString(c?.device_id ?? c?.id);
    if (curDid && curDid === did) {
      replaced = true;
      return { ...(c && typeof c === 'object' ? c : {}), ...entry };
    }
    return c;
  });
  if (!replaced) out.clients.push(entry);
  out.updated_at_ms = nowMs();
  return out;
}

function writeClientsSnapshot(runtimeBaseDir, snap) {
  const base = safeString(runtimeBaseDir);
  if (!base) return false;
  const ok = writeJsonAtomic(base, 'hub_grpc_clients.json', snap);
  if (ok) invalidateClientsCache();
  return ok;
}

function generateClientToken() {
  const bytes = crypto.randomBytes(32);
  // URL-safe base64 (no padding).
  const b64 = bytes
    .toString('base64')
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
  return `axhub_client_${b64}`;
}

function generateDeviceId() {
  const id = crypto.randomUUID().replaceAll('-', '').toLowerCase();
  return `dev_${id.slice(0, 12)}`;
}

function base64EncodeUtf8(s) {
  try {
    return Buffer.from(String(s || ''), 'utf8').toString('base64');
  } catch {
    return '';
  }
}

function base64DecodeUtf8(s) {
  try {
    return Buffer.from(String(s || ''), 'base64').toString('utf8');
  } catch {
    return '';
  }
}

function bearerTokenFromReq(req) {
  const raw = safeString(req?.headers?.authorization);
  if (!raw) return '';
  const lower = raw.toLowerCase();
  if (lower.startsWith('bearer ')) return raw.slice('bearer '.length).trim();
  return raw;
}

function requireHttpAdmin(req) {
  const expected = safeString(process.env.HUB_ADMIN_TOKEN);
  if (!expected) {
    return { ok: false, status: 503, code: 'admin_token_not_configured', message: 'Admin token is not configured on this Hub' };
  }

  const tok = bearerTokenFromReq(req);
  if (!tok || tok !== expected) return { ok: false, status: 401, code: 'unauthenticated', message: 'Missing/invalid admin token' };

  const peerIp = peerIpFromReq(req);
  const allowRemote = safeString(process.env.HUB_ADMIN_ALLOW_REMOTE) === '1';
  const adminAllowed = safeStringArray(process.env.HUB_ADMIN_ALLOWED_CIDRS || '');
  if (!allowRemote) {
    if (adminAllowed.length) {
      if (!peerAllowedByRules(peerIp, adminAllowed)) {
        return { ok: false, status: 403, code: 'permission_denied', message: 'Admin source IP is not allowed' };
      }
    } else if (!isLoopbackIp(peerIp)) {
      return { ok: false, status: 403, code: 'permission_denied', message: 'Admin endpoints are local-only' };
    }
  }
  return { ok: true };
}

function requireHttpClient(req) {
  const runtimeBaseDir = resolveRuntimeBaseDir();
  const tok = bearerTokenFromReq(req);
  if (!tok) {
    return { ok: false, status: 401, code: 'unauthenticated', message: 'Missing/invalid client token' };
  }

  const client = findClientByToken(runtimeBaseDir, tok);
  if (!client) {
    return { ok: false, status: 401, code: 'unauthenticated', message: 'Missing/invalid client token' };
  }

  const availability = getClientAuthStatus(client);
  if (!availability.usable) {
    const errorCode = safeString(availability.reason_code) || 'unauthenticated';
    const message = errorCode === 'token_revoked'
      ? 'Client token has been revoked'
      : errorCode === 'token_expired'
        ? 'Client token has expired'
        : 'Client token is disabled';
    return { ok: false, status: 401, code: errorCode, message };
  }

  const peerIp = peerIpFromReq(req);
  const allowedCidrs = Array.isArray(client.allowed_cidrs) ? client.allowed_cidrs : [];
  if (allowedCidrs.length > 0 && !peerAllowedByRules(peerIp, allowedCidrs)) {
    return { ok: false, status: 403, code: 'permission_denied', message: 'Client source IP is not allowed' };
  }

  const touchedClient = touchClientUsageByToken(runtimeBaseDir, tok, {
    peer_ip: peerIp,
    transport: 'http',
  }) || client;

  return {
    ok: true,
    runtimeBaseDir,
    peerIp,
    client: touchedClient,
  };
}

function resolveClientConnectHost(req, {
  hostFallback,
  peerIp,
  internetHostHint,
} = {}) {
  const hostHeader = safeString(req?.headers?.host);
  const hostHeaderName = hostHeader.includes(':') ? hostHeader.split(':')[0] : hostHeader;
  return uniqueStrings([
    internetHostHint,
    hostHintFromReq(req, { hostFallback, peerIp }),
    hostHeaderName,
    hostFallback,
  ])[0] || '';
}

function buildClientConnectExport({
  req,
  hostFallback,
  peerIp,
  internetHostHint,
  grpcPort,
  tlsMode,
  tlsServerName,
  client,
  clientToken = '',
} = {}) {
  const hubHost = resolveClientConnectHost(req, {
    hostFallback,
    peerIp,
    internetHostHint,
  });
  if (!hubHost) {
    return {
      connect: null,
      connect_env: '',
      connect_env_template: '',
    };
  }

  const grpcPortNumber = Number(grpcPort || 0) || 50051;
  const serverName = tlsMode !== 'insecure' ? safeString(tlsServerName) : '';
  const tlsEnv =
    tlsMode === 'insecure'
      ? ''
      : `HUB_GRPC_TLS_MODE=${shellQuoteSingle(tlsMode)}\nHUB_GRPC_TLS_SERVER_NAME=${shellQuoteSingle(serverName)}\nHUB_GRPC_TLS_CA_CERT_PATH=$HOME/.axhub/tls/ca.cert.pem\n`
        + (tlsMode === 'mtls'
          ? `HUB_GRPC_TLS_CLIENT_CERT_PATH=$HOME/.axhub/tls/client.cert.pem\nHUB_GRPC_TLS_CLIENT_KEY_PATH=$HOME/.axhub/tls/client.key.pem\n`
          : '');

  const commonEnv =
    `HUB_HOST=${shellQuoteSingle(hubHost)}\n`
    + `HUB_PORT=${grpcPortNumber}\n`
    + `HUB_ACCESS_KEY_ID=${shellQuoteSingle(client?.access_key_id || client?.device_id || '')}\n`
    + `HUB_DEVICE_ID=${shellQuoteSingle(client?.device_id || '')}\n`
    + `HUB_USER_ID=${shellQuoteSingle(client?.user_id || '')}\n`
    + `HUB_APP_ID=${shellQuoteSingle(client?.app_id || '')}\n`;

  return {
    connect: {
      hub_host: hubHost,
      hub_port: grpcPortNumber,
      tls_mode: safeString(tlsMode || 'insecure') || 'insecure',
      tls_server_name: serverName,
      auth_env_key: 'HUB_CLIENT_TOKEN',
    },
    connect_env: clientToken
      ? commonEnv + `HUB_CLIENT_TOKEN=${shellQuoteSingle(clientToken)}\n` + tlsEnv
      : '',
    connect_env_template:
      commonEnv + `HUB_CLIENT_TOKEN=${shellQuoteSingle(redactClientToken(client?.token || '<set-client-token>') || '<set-client-token>')}\n` + tlsEnv,
  };
}

function buildClientOpenAICompatExport({
  req,
  hostFallback,
  peerIp,
  internetHostHint,
  pairingPort,
  schemeFallback,
  client,
  clientToken = '',
} = {}) {
  const hubHost = resolveClientConnectHost(req, {
    hostFallback,
    peerIp,
    internetHostHint,
  });
  const scheme = safeString(req?.headers?.['x-forwarded-proto']) || safeString(schemeFallback) || 'http';
  const portNumber = positiveIntOrZero(pairingPort);
  if (!hubHost) {
    return {
      openai_compat: null,
      openai_compat_env: '',
      openai_compat_env_template: '',
    };
  }

  const authority = (() => {
    const normalizedHost = safeString(hubHost);
    if (!normalizedHost) return '';
    if (normalizedHost.includes(':')) return normalizedHost;
    if ((scheme === 'https' && portNumber === 443) || (scheme === 'http' && portNumber === 80) || portNumber <= 0) {
      return normalizedHost;
    }
    return `${normalizedHost}:${portNumber}`;
  })();
  if (!authority) {
    return {
      openai_compat: null,
      openai_compat_env: '',
      openai_compat_env_template: '',
    };
  }

  const baseUrl = `${scheme}://${authority}/v1`;
  const commonEnv =
    `OPENAI_BASE_URL=${shellQuoteSingle(baseUrl)}\n`
    + `AXHUB_ACCESS_KEY_ID=${shellQuoteSingle(client?.access_key_id || client?.device_id || '')}\n`
    + `AXHUB_DEVICE_ID=${shellQuoteSingle(client?.device_id || '')}\n`
    + `AXHUB_USER_ID=${shellQuoteSingle(client?.user_id || '')}\n`
    + `AXHUB_APP_ID=${shellQuoteSingle(client?.app_id || '')}\n`;

  return {
    openai_compat: {
      base_url: baseUrl,
      models_url: `${baseUrl}/models`,
      chat_completions_url: `${baseUrl}/chat/completions`,
      responses_url: `${baseUrl}/responses`,
      auth_scheme: 'bearer',
      api_key_env_key: 'OPENAI_API_KEY',
      base_url_env_key: 'OPENAI_BASE_URL',
    },
    openai_compat_env: clientToken
      ? commonEnv + `OPENAI_API_KEY=${shellQuoteSingle(clientToken)}\n`
      : '',
    openai_compat_env_template:
      commonEnv + `OPENAI_API_KEY=${shellQuoteSingle(redactClientToken(client?.token || '<set-openai-api-key>') || '<set-openai-api-key>')}\n`,
  };
}

function toHttpClientAccessKey(client, context = {}, options = {}) {
  if (!client || typeof client !== 'object') return null;
  const includeSecretToken = options.include_secret_token === true;
  const secretToken = includeSecretToken ? safeString(options.client_token || client.token) : '';
  const exportInfo = buildClientConnectExport({
    req: context.req,
    hostFallback: context.hostFallback,
    peerIp: context.peerIp,
    internetHostHint: context.internetHostHint,
    grpcPort: context.grpcPort,
    tlsMode: context.tlsMode,
    tlsServerName: context.tlsServerName,
    client,
    clientToken: secretToken,
  });
  const openAICompatInfo = buildClientOpenAICompatExport({
    req: context.req,
    hostFallback: context.hostFallback,
    peerIp: context.peerIp,
    internetHostHint: context.internetHostHint,
    pairingPort: context.pairingPort,
    schemeFallback: context.schemeFallback,
    client,
    clientToken: secretToken,
  });
  return {
    schema_version: 'hub.client_access_key.v1',
    access_key_id: safeString(client.access_key_id || client.device_id),
    auth_kind: safeString(client.auth_kind || 'paired_client') || 'paired_client',
    status: safeString(client.status || ''),
    status_reason: safeString(client.status_reason || ''),
    device_id: safeString(client.device_id),
    user_id: safeString(client.user_id),
    app_id: safeString(client.app_id),
    name: safeString(client.name),
    note: safeString(client.note),
    token_redacted: safeString(client.token_redacted || redactClientToken(client.token)),
    enabled: client.enabled === true,
    created_at_ms: Math.max(0, Number(client.created_at_ms || 0)),
    updated_at_ms: Math.max(0, Number(client.updated_at_ms || 0)),
    expires_at_ms: Math.max(0, Number(client.expires_at_ms || 0)),
    last_used_at_ms: Math.max(0, Number(client.last_used_at_ms || 0)),
    last_used_peer_ip: safeString(client.last_used_peer_ip),
    last_used_transport: safeString(client.last_used_transport),
    revoked_at_ms: Math.max(0, Number(client.revoked_at_ms || 0)),
    revoke_reason: safeString(client.revoke_reason),
    revoked_by_user_id: safeString(client.revoked_by_user_id),
    revoked_via: safeString(client.revoked_via),
    created_by_user_id: safeString(client.created_by_user_id),
    created_by_app_id: safeString(client.created_by_app_id),
    created_via: safeString(client.created_via),
    last_rotated_at_ms: Math.max(0, Number(client.last_rotated_at_ms || 0)),
    rotation_count: Math.max(0, Number(client.rotation_count || 0)),
    capabilities: safeStringArray(client.capabilities),
    scopes: safeStringArray(client.scopes),
    allowed_cidrs: safeStringArray(client.allowed_cidrs),
    policy_mode: safeString(client.policy_mode),
    trust_profile_present: !!client.trust_profile_present,
    approved_trust_profile: client.approved_trust_profile && typeof client.approved_trust_profile === 'object'
      ? client.approved_trust_profile
      : null,
    connect: exportInfo.connect,
    connect_env_template: exportInfo.connect_env_template,
    openai_compat: openAICompatInfo.openai_compat,
    openai_compat_env_template: openAICompatInfo.openai_compat_env_template,
    ...(includeSecretToken ? { connect_env: exportInfo.connect_env } : {}),
    ...(includeSecretToken ? { openai_compat_env: openAICompatInfo.openai_compat_env } : {}),
  };
}

function findClientSnapshotIndex(snapshot, accessKeyId) {
  const rows = Array.isArray(snapshot?.clients) ? snapshot.clients : [];
  for (let index = 0; index < rows.length; index += 1) {
    const item = rows[index];
    const candidateAccessKeyId = safeString(item?.access_key_id || item?.accessKeyId || item?.device_id || item?.id);
    const candidateDeviceId = safeString(item?.device_id || item?.id);
    if (candidateAccessKeyId === accessKeyId || candidateDeviceId === accessKeyId) {
      return index;
    }
  }
  return -1;
}

function buildClientAccessKeyResponseContext(req, {
  hostFallback,
  internetHostHint,
  grpcPort,
} = {}) {
  const tlsMode = tlsModeFromEnv(process.env);
  const pairingPort = positiveIntOrZero(process.env.HUB_PAIRING_PORT || (positiveIntOrZero(grpcPort) + 1));
  return {
    req,
    hostFallback,
    peerIp: peerIpFromReq(req),
    internetHostHint,
    grpcPort,
    pairingPort,
    schemeFallback: safeString(process.env.HUB_PAIRING_PUBLIC_SCHEME || '') || 'http',
    tlsMode,
    tlsServerName: tlsMode === 'insecure' ? '' : tlsServerNameFromEnv(process.env),
  };
}

function makeHubServiceCallPeer(req) {
  const peerIp = peerIpFromReq(req) || '127.0.0.1';
  return `ipv4:${peerIp}:0`;
}

function makeHubServiceMetadata(token = '') {
  const rawToken = safeString(token);
  return {
    get(key) {
      if (safeString(key).toLowerCase() === 'authorization') {
        return rawToken ? [`Bearer ${rawToken}`] : [];
      }
      return [];
    },
  };
}

function makeHubUnaryCall({ req, token = '', request = {} } = {}) {
  return {
    request,
    metadata: makeHubServiceMetadata(token),
    getPeer() {
      return makeHubServiceCallPeer(req);
    },
  };
}

function makeHubStreamingCall({ req, token = '', request = {}, onWrite = null, onEnd = null } = {}) {
  const writes = [];
  let ended = false;
  return {
    request,
    writes,
    get ended() {
      return ended;
    },
    metadata: makeHubServiceMetadata(token),
    getPeer() {
      return makeHubServiceCallPeer(req);
    },
    write(payload) {
      writes.push(payload);
      if (typeof onWrite === 'function') {
        try {
          onWrite(payload);
        } catch {
          // ignore bridge-to-http callback failures
        }
      }
    },
    end() {
      ended = true;
      if (typeof onEnd === 'function') {
        try {
          onEnd();
        } catch {
          // ignore bridge-to-http callback failures
        }
      }
    },
    on() {
      // HTTP gateway only supports request/response for now.
    },
  };
}

function openAIErrorTypeForStatus(status) {
  const code = Number(status || 0);
  if (code === 401) return 'authentication_error';
  if (code === 403) return 'permission_error';
  if (code === 404) return 'not_found_error';
  if (code === 429) return 'rate_limit_error';
  return 'invalid_request_error';
}

function openAIStatusForHubErrorCode(rawCode = '') {
  const code = safeString(rawCode).toLowerCase();
  if (!code) return 503;
  if (code === 'unauthenticated' || code === 'token_revoked' || code === 'token_expired') return 401;
  if (code === 'permission_denied' || code === 'grant_required' || code === 'kill_switch_active') return 403;
  if (code === 'model_not_found') return 404;
  if (code.includes('rate_limit') || code.includes('quota') || code.includes('budget_exceeded')) return 429;
  if (code.includes('invalid') || code.includes('unsupported') || code.includes('bad_')) return 400;
  return 503;
}

function openAIErrorPayload({
  status = 500,
  code = 'gateway_error',
  message = '',
  type = '',
} = {}) {
  return {
    error: {
      message: safeString(message) || safeString(code) || 'gateway_error',
      type: safeString(type) || openAIErrorTypeForStatus(status),
      code: safeString(code) || 'gateway_error',
    },
  };
}

function openAIErrorResponse(res, status, {
  code = 'gateway_error',
  message = '',
  type = '',
} = {}) {
  jsonResponse(res, Number(status || 500), openAIErrorPayload({ status, code, message, type }));
}

function normalizeOpenAIChatMessageContent(rawContent) {
  if (typeof rawContent === 'string') return rawContent;
  if (Array.isArray(rawContent)) {
    return rawContent
      .map((item) => {
        if (typeof item === 'string') return item;
        if (!item || typeof item !== 'object') return '';
        const type = safeString(item.type).toLowerCase();
        if (type === 'text' || type === 'input_text') return safeString(item.text);
        return '';
      })
      .filter(Boolean)
      .join('\n');
  }
  if (rawContent && typeof rawContent === 'object') {
    return safeString(rawContent.text || rawContent.content);
  }
  return '';
}

function toHubGenerateMessages(messages) {
  if (!Array.isArray(messages)) return [];
  return messages
    .map((item) => ({
      role: safeString(item?.role || 'user') || 'user',
      content: normalizeOpenAIChatMessageContent(item?.content),
    }))
    .filter((item) => item.content);
}

function normalizeOpenAIResponsesContent(rawContent) {
  if (typeof rawContent === 'string') return rawContent;
  if (Array.isArray(rawContent)) {
    return rawContent
      .map((item) => {
        if (typeof item === 'string') return item;
        if (!item || typeof item !== 'object') return '';
        const type = safeString(item.type).toLowerCase();
        if (type === 'text' || type === 'input_text' || type === 'output_text') {
          if (typeof item.text === 'string') return item.text;
          if (item.text && typeof item.text === 'object') {
            return safeString(item.text.value || item.text.text);
          }
          return safeString(item.output_text);
        }
        if (type === 'message') return normalizeOpenAIResponsesContent(item.content);
        if (typeof item.content === 'string') return item.content;
        return safeString(item.value);
      })
      .filter(Boolean)
      .join('\n');
  }
  if (rawContent && typeof rawContent === 'object') {
    const type = safeString(rawContent.type).toLowerCase();
    if (type === 'message') return normalizeOpenAIResponsesContent(rawContent.content);
    if (typeof rawContent.text === 'string') return rawContent.text;
    if (rawContent.text && typeof rawContent.text === 'object') {
      return safeString(rawContent.text.value || rawContent.text.text);
    }
    if (typeof rawContent.content === 'string') return rawContent.content;
    return safeString(rawContent.value || rawContent.output_text);
  }
  return '';
}

function toHubGenerateMessagesFromResponsesPayload(payload = {}) {
  const out = [];
  const instructions = normalizeOpenAIResponsesContent(payload.instructions);
  if (instructions) {
    out.push({
      role: 'system',
      content: instructions,
    });
  }

  const input = payload.input;
  if (typeof input === 'string') {
    out.push({
      role: 'user',
      content: input,
    });
    return out.filter((item) => item.content);
  }

  if (!Array.isArray(input)) {
    const content = normalizeOpenAIResponsesContent(input);
    if (content) {
      out.push({
        role: 'user',
        content,
      });
    }
    return out.filter((item) => item.content);
  }

  for (const item of input) {
    if (typeof item === 'string') {
      out.push({
        role: 'user',
        content: item,
      });
      continue;
    }
    if (!item || typeof item !== 'object') continue;
    const type = safeString(item.type).toLowerCase();
    if (type && type !== 'message') {
      const content = normalizeOpenAIResponsesContent(item);
      if (content) {
        out.push({
          role: 'user',
          content,
        });
      }
      continue;
    }

    const role = safeString(item.role || 'user') || 'user';
    const content = normalizeOpenAIResponsesContent(item.content);
    if (!content) continue;
    out.push({
      role,
      content,
    });
  }

  return out.filter((item) => item.content);
}

function normalizeOpenAIFinishReason(reason = '') {
  const token = safeString(reason).toLowerCase();
  if (!token) return 'stop';
  if (token === 'completed' || token === 'eos' || token === 'done') return 'stop';
  return token;
}

function toOpenAIModelInfo(model) {
  const modelId = safeString(model?.model_id);
  if (!modelId) return null;
  return {
    id: modelId,
    object: 'model',
    owned_by: 'axhub',
    backend: safeString(model?.backend).toLowerCase(),
    kind: safeString(model?.kind).toLowerCase(),
    visibility: safeString(model?.visibility).toLowerCase(),
    requires_grant: !!model?.requires_grant,
    context_length: Math.max(0, Number(model?.context_length || 0)),
  };
}

function toOpenAIModelListResponse(response = {}) {
  const rows = (Array.isArray(response?.models) ? response.models : [])
    .map((item) => toOpenAIModelInfo(item))
    .filter(Boolean);
  return {
    object: 'list',
    data: rows,
    count: rows.length,
    trust_profile_present: !!response?.trust_profile_present,
    paid_model_policy_mode: safeString(response?.paid_model_policy_mode),
    daily_token_limit: Math.max(0, Number(response?.daily_token_limit || 0)),
    single_request_token_limit: Math.max(0, Number(response?.single_request_token_limit || 0)),
  };
}

async function invokeHubListModels({ hubServices, req, token = '', request = {} } = {}) {
  const listModels = hubServices?.HubModels?.ListModels;
  if (typeof listModels !== 'function') {
    return {
      ok: false,
      status: 503,
      code: 'hub_models_gateway_unavailable',
      message: 'Hub model service is unavailable',
    };
  }

  const call = makeHubUnaryCall({ req, token, request });
  return new Promise((resolve) => {
    try {
      listModels(call, (error, response) => {
        if (error) {
          const message = safeString(error?.message || 'Hub model service request failed');
          resolve({
            ok: false,
            status: openAIStatusForHubErrorCode(message),
            code: message || 'hub_models_request_failed',
            message,
          });
          return;
        }
        resolve({ ok: true, response: response || {} });
      });
    } catch (error) {
      const message = safeString(error?.message || 'Hub model service request failed');
      resolve({
        ok: false,
        status: 503,
        code: 'hub_models_request_failed',
        message,
      });
    }
  });
}

async function invokeHubCancel({ hubServices, req, token = '', request = {} } = {}) {
  const cancel = hubServices?.HubAI?.Cancel;
  if (typeof cancel !== 'function') {
    return {
      ok: false,
      status: 503,
      code: 'hub_cancel_gateway_unavailable',
      message: 'Hub cancel service is unavailable',
    };
  }

  const call = makeHubUnaryCall({ req, token, request });
  return new Promise((resolve) => {
    try {
      cancel(call, (error, response) => {
        if (error) {
          const message = safeString(error?.message || 'Hub cancel request failed');
          resolve({
            ok: false,
            status: openAIStatusForHubErrorCode(message),
            code: message || 'hub_cancel_request_failed',
            message,
          });
          return;
        }
        resolve({
          ok: !!response?.ok,
          response: response || {},
        });
      });
    } catch (error) {
      const message = safeString(error?.message || 'Hub cancel request failed');
      resolve({
        ok: false,
        status: 503,
        code: 'hub_cancel_request_failed',
        message,
      });
    }
  });
}

async function invokeHubProviderKeysUnary({
  hubServices,
  req,
  token = '',
  method = '',
  request = {},
} = {}) {
  const fn = hubServices?.HubProviderKeys?.[method];
  if (typeof fn !== 'function') {
    return {
      ok: false,
      status: 503,
      code: 'hub_provider_keys_gateway_unavailable',
      message: 'Hub provider key service is unavailable',
    };
  }

  const call = makeHubUnaryCall({ req, token, request });
  return new Promise((resolve) => {
    try {
      fn(call, (error, response) => {
        if (error) {
          const message = safeString(error?.message || 'Hub provider key service request failed');
          resolve({
            ok: false,
            status: openAIStatusForHubErrorCode(message),
            code: message || 'hub_provider_keys_request_failed',
            message,
          });
          return;
        }
        resolve({ ok: true, response: response || {} });
      });
    } catch (error) {
      const message = safeString(error?.message || 'Hub provider key service request failed');
      resolve({
        ok: false,
        status: 503,
        code: 'hub_provider_keys_request_failed',
        message,
      });
    }
  });
}

async function invokeHubGrantsUnary({
  hubServices,
  req,
  token = '',
  method = '',
  request = {},
} = {}) {
  const fn = hubServices?.HubGrants?.[method];
  if (typeof fn !== 'function') {
    return {
      ok: false,
      status: 503,
      code: 'hub_grants_gateway_unavailable',
      message: 'Hub grant service is unavailable',
    };
  }

  const call = makeHubUnaryCall({ req, token, request });
  return new Promise((resolve) => {
    try {
      fn(call, (error, response) => {
        if (error) {
          const message = safeString(error?.message || 'Hub grant service request failed');
          resolve({
            ok: false,
            status: openAIStatusForHubErrorCode(message),
            code: message || 'hub_grants_request_failed',
            message,
          });
          return;
        }
        resolve({ ok: true, response: response || {} });
      });
    } catch (error) {
      const message = safeString(error?.message || 'Hub grant service request failed');
      resolve({
        ok: false,
        status: 503,
        code: 'hub_grants_request_failed',
        message,
      });
    }
  });
}

async function invokeHubGenerate({ hubServices, req, token = '', request = {} } = {}) {
  const generate = hubServices?.HubAI?.Generate;
  if (typeof generate !== 'function') {
    return {
      ok: false,
      status: 503,
      code: 'hub_generate_gateway_unavailable',
      message: 'Hub generate service is unavailable',
    };
  }

  const call = makeHubStreamingCall({ req, token, request });
  try {
    await generate(call);
    return {
      ok: true,
      writes: Array.isArray(call.writes) ? call.writes : [],
      ended: call.ended === true,
    };
  } catch (error) {
    const message = safeString(error?.message || 'Hub generate service request failed');
    return {
      ok: false,
      status: openAIStatusForHubErrorCode(message),
      code: message || 'hub_generate_request_failed',
      message,
    };
  }
}

async function invokeHubGenerateStreaming({
  hubServices,
  req,
  token = '',
  request = {},
  onWrite = null,
  onEnd = null,
} = {}) {
  const generate = hubServices?.HubAI?.Generate;
  if (typeof generate !== 'function') {
    return {
      ok: false,
      status: 503,
      code: 'hub_generate_gateway_unavailable',
      message: 'Hub generate service is unavailable',
      writes: [],
    };
  }

  const call = makeHubStreamingCall({ req, token, request, onWrite, onEnd });
  try {
    await generate(call);
    return {
      ok: true,
      writes: Array.isArray(call.writes) ? call.writes : [],
      ended: call.ended === true,
    };
  } catch (error) {
    const message = safeString(error?.message || 'Hub generate service request failed');
    return {
      ok: false,
      status: openAIStatusForHubErrorCode(message),
      code: message || 'hub_generate_request_failed',
      message,
      writes: Array.isArray(call.writes) ? call.writes : [],
      ended: call.ended === true,
    };
  }
}

function toOpenAIChatCompletionResponse({
  request = {},
  generateWrites = [],
} = {}) {
  let done = null;
  let errorEvent = null;
  let content = '';
  for (const event of Array.isArray(generateWrites) ? generateWrites : []) {
    if (event?.delta?.text) content += String(event.delta.text);
    if (event?.done) done = event.done;
    if (event?.error) errorEvent = event.error;
  }

  if (errorEvent) {
    const errorCode = safeString(errorEvent?.error?.code || errorEvent?.deny_code || errorEvent?.fallback_reason_code) || 'generate_failed';
    const errorMessage = safeString(errorEvent?.error?.message || errorCode) || 'generate_failed';
    return {
      ok: false,
      status: openAIStatusForHubErrorCode(errorCode),
      payload: openAIErrorPayload({
        status: openAIStatusForHubErrorCode(errorCode),
        code: errorCode,
        message: errorMessage,
      }),
    };
  }

  if (!done || done.ok !== true) {
    const errorCode = safeString(done?.deny_code || done?.reason) || 'generate_failed';
    const status = openAIStatusForHubErrorCode(errorCode);
    return {
      ok: false,
      status,
      payload: openAIErrorPayload({
        status,
        code: errorCode,
        message: safeString(done?.reason || errorCode) || 'generate_failed',
      }),
    };
  }

  const usage = done?.usage && typeof done.usage === 'object' ? done.usage : {};
  return {
    ok: true,
    status: 200,
    payload: {
      id: `chatcmpl-axhub-${safeString(done?.request_id || request?.request_id) || uuid()}`,
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model: safeString(done?.actual_model_id || request?.model_id),
      choices: [
        {
          index: 0,
          message: {
            role: 'assistant',
            content,
          },
          finish_reason: normalizeOpenAIFinishReason(done?.reason),
        },
      ],
      usage: {
        prompt_tokens: Math.max(0, Number(usage?.prompt_tokens || 0)),
        completion_tokens: Math.max(0, Number(usage?.completion_tokens || 0)),
        total_tokens: Math.max(0, Number(usage?.total_tokens || 0)),
      },
      x_hub: {
        request_id: safeString(done?.request_id || request?.request_id),
        actual_model_id: safeString(done?.actual_model_id),
        runtime_provider: safeString(done?.runtime_provider),
        execution_path: safeString(done?.execution_path),
        fallback_reason_code: safeString(done?.fallback_reason_code),
        audit_ref: safeString(done?.audit_ref),
        deny_code: safeString(done?.deny_code),
      },
    },
  };
}

function toOpenAIResponsesResponse({
  request = {},
  generateWrites = [],
} = {}) {
  let done = null;
  let errorEvent = null;
  let content = '';
  for (const event of Array.isArray(generateWrites) ? generateWrites : []) {
    if (event?.delta?.text) content += String(event.delta.text);
    if (event?.done) done = event.done;
    if (event?.error) errorEvent = event.error;
  }

  if (errorEvent) {
    const errorCode = safeString(errorEvent?.error?.code || errorEvent?.deny_code || errorEvent?.fallback_reason_code) || 'generate_failed';
    const errorMessage = safeString(errorEvent?.error?.message || errorCode) || 'generate_failed';
    const status = openAIStatusForHubErrorCode(errorCode);
    return {
      ok: false,
      status,
      payload: openAIErrorPayload({
        status,
        code: errorCode,
        message: errorMessage,
      }),
    };
  }

  if (!done || done.ok !== true) {
    const errorCode = safeString(done?.deny_code || done?.reason) || 'generate_failed';
    const status = openAIStatusForHubErrorCode(errorCode);
    return {
      ok: false,
      status,
      payload: openAIErrorPayload({
        status,
        code: errorCode,
        message: safeString(done?.reason || errorCode) || 'generate_failed',
      }),
    };
  }

  const usage = done?.usage && typeof done.usage === 'object' ? done.usage : {};
  const requestId = safeString(done?.request_id || request?.request_id) || uuid();
  const modelId = safeString(done?.actual_model_id || request?.model_id);
  return {
    ok: true,
    status: 200,
    payload: {
      id: `resp-axhub-${requestId}`,
      object: 'response',
      created_at: Math.floor(Date.now() / 1000),
      status: 'completed',
      model: modelId,
      output: [
        {
          id: `msg-axhub-${requestId}`,
          object: 'message',
          type: 'message',
          status: 'completed',
          role: 'assistant',
          content: [
            {
              type: 'output_text',
              text: content,
              annotations: [],
            },
          ],
        },
      ],
      output_text: content,
      usage: {
        input_tokens: Math.max(0, Number(usage?.prompt_tokens || usage?.input_tokens || 0)),
        output_tokens: Math.max(0, Number(usage?.completion_tokens || usage?.output_tokens || 0)),
        total_tokens: Math.max(0, Number(usage?.total_tokens || 0)),
      },
      x_hub: {
        request_id: safeString(done?.request_id || request?.request_id),
        actual_model_id: safeString(done?.actual_model_id),
        runtime_provider: safeString(done?.runtime_provider),
        execution_path: safeString(done?.execution_path),
        fallback_reason_code: safeString(done?.fallback_reason_code),
        audit_ref: safeString(done?.audit_ref),
        deny_code: safeString(done?.deny_code),
      },
    },
  };
}

function startOpenAIEventStream(res) {
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-store',
    connection: 'keep-alive',
    'x-accel-buffering': 'no',
  });
  if (typeof res.flushHeaders === 'function') {
    try {
      res.flushHeaders();
    } catch {
      // ignore
    }
  }
}

function writeOpenAISSE(res, {
  event = '',
  data = '',
} = {}) {
  if (!res || res.writableEnded || res.destroyed) return false;
  let payload = '';
  if (event) payload += `event: ${event}\n`;
  const rawData = typeof data === 'string' ? data : JSON.stringify(data);
  for (const line of String(rawData || '').split('\n')) {
    payload += `data: ${line}\n`;
  }
  payload += '\n';
  try {
    res.write(payload);
    return true;
  } catch {
    return false;
  }
}

function endOpenAIChatCompletionStream(res) {
  writeOpenAISSE(res, { data: '[DONE]' });
  try {
    res.end();
  } catch {
    // ignore
  }
}

function toOpenAIChatCompletionChunk({
  request = {},
  delta = null,
  finishReason = null,
  usage = null,
} = {}) {
  const choice = {
    index: 0,
    delta: delta && typeof delta === 'object' ? delta : {},
    finish_reason: finishReason == null ? null : finishReason,
  };
  const payload = {
    id: `chatcmpl-axhub-${safeString(request?.request_id) || uuid()}`,
    object: 'chat.completion.chunk',
    created: Math.floor(Date.now() / 1000),
    model: safeString(request?.model_id),
    choices: [choice],
  };
  if (usage && typeof usage === 'object') {
    payload.usage = {
      prompt_tokens: Math.max(0, Number(usage.prompt_tokens || 0)),
      completion_tokens: Math.max(0, Number(usage.completion_tokens || 0)),
      total_tokens: Math.max(0, Number(usage.total_tokens || 0)),
    };
  }
  return payload;
}

async function streamOpenAIChatCompletions({
  hubServices,
  req,
  res,
  token = '',
  request = {},
  includeUsage = false,
} = {}) {
  startOpenAIEventStream(res);
  const writes = [];
  const streamRequest = {
    request_id: safeString(request?.request_id) || uuid(),
    model_id: safeString(request?.model_id),
  };
  let started = false;
  let responseFinished = false;
  let cancelRequested = false;

  const requestCancel = () => {
    if (cancelRequested || responseFinished) return;
    cancelRequested = true;
    void invokeHubCancel({
      hubServices,
      req,
      token,
      request: {
        request_id: streamRequest.request_id,
        reason: 'http_client_disconnected',
      },
    });
  };

  res.on('finish', () => {
    responseFinished = true;
  });
  res.on('close', () => {
    if (!responseFinished) requestCancel();
  });

  const ensureStart = () => {
    if (started || responseFinished) return;
    started = true;
    writeOpenAISSE(res, {
      data: toOpenAIChatCompletionChunk({
        request: streamRequest,
        delta: { role: 'assistant' },
      }),
    });
  };

  let finalized = false;
  const finalize = (streamWrites) => {
    if (finalized) return;
    finalized = true;
    const completion = toOpenAIChatCompletionResponse({
      request: streamRequest,
      generateWrites: streamWrites,
    });
    if (completion.ok) {
      ensureStart();
      writeOpenAISSE(res, {
        data: toOpenAIChatCompletionChunk({
          request: {
            request_id: safeString(completion.payload?.x_hub?.request_id || streamRequest.request_id),
            model_id: safeString(completion.payload?.model || streamRequest.model_id),
          },
          delta: {},
          finishReason: completion.payload?.choices?.[0]?.finish_reason ?? 'stop',
          usage: includeUsage ? completion.payload?.usage : null,
        }),
      });
    } else {
      ensureStart();
      writeOpenAISSE(res, { data: completion.payload });
    }
    endOpenAIChatCompletionStream(res);
  };

  const generated = await invokeHubGenerateStreaming({
    hubServices,
    req,
    token,
    request,
    onWrite(payload) {
      writes.push(payload);
      if (payload?.start?.model_id) {
        streamRequest.model_id = safeString(payload.start.model_id) || streamRequest.model_id;
        ensureStart();
        return;
      }
      if (payload?.delta?.text) {
        ensureStart();
        writeOpenAISSE(res, {
          data: toOpenAIChatCompletionChunk({
            request: streamRequest,
            delta: { content: String(payload.delta.text) },
          }),
        });
        return;
      }
      if (payload?.done || payload?.error) {
        finalize(writes);
      }
    },
    onEnd() {
      finalize(writes);
    },
  });

  if (!generated.ok && !finalized) {
    const payload = openAIErrorPayload({
      status: generated.status || 503,
      code: generated.code || 'hub_generate_request_failed',
      message: generated.message || 'Hub generate service request failed',
    });
    writeOpenAISSE(res, { data: payload });
    endOpenAIChatCompletionStream(res);
    return;
  }

  if (!finalized) {
    finalize(Array.isArray(generated.writes) ? generated.writes : writes);
  }
}

async function streamOpenAIResponses({
  hubServices,
  req,
  res,
  token = '',
  request = {},
} = {}) {
  startOpenAIEventStream(res);
  const writes = [];
  const streamRequest = {
    request_id: safeString(request?.request_id) || uuid(),
    model_id: safeString(request?.model_id),
  };
  const responseId = `resp-axhub-${streamRequest.request_id}`;
  const itemId = `msg-axhub-${streamRequest.request_id}`;
  const createdAt = Math.floor(Date.now() / 1000);
  let started = false;
  let responseFinished = false;
  let cancelRequested = false;

  const requestCancel = () => {
    if (cancelRequested || responseFinished) return;
    cancelRequested = true;
    void invokeHubCancel({
      hubServices,
      req,
      token,
      request: {
        request_id: streamRequest.request_id,
        reason: 'http_client_disconnected',
      },
    });
  };

  res.on('finish', () => {
    responseFinished = true;
  });
  res.on('close', () => {
    if (!responseFinished) requestCancel();
  });

  const ensureStart = () => {
    if (started || responseFinished) return;
    started = true;
    writeOpenAISSE(res, {
      event: 'response.created',
      data: {
        type: 'response.created',
        response: {
          id: responseId,
          object: 'response',
          created_at: createdAt,
          status: 'in_progress',
          model: streamRequest.model_id,
        },
      },
    });
    writeOpenAISSE(res, {
      event: 'response.output_item.added',
      data: {
        type: 'response.output_item.added',
        output_index: 0,
        item: {
          id: itemId,
          type: 'message',
          object: 'message',
          status: 'in_progress',
          role: 'assistant',
          content: [],
        },
      },
    });
    writeOpenAISSE(res, {
      event: 'response.content_part.added',
      data: {
        type: 'response.content_part.added',
        output_index: 0,
        content_index: 0,
        item_id: itemId,
        part: {
          type: 'output_text',
          text: '',
          annotations: [],
        },
      },
    });
  };

  let finalized = false;
  const finalize = (streamWrites) => {
    if (finalized) return;
    finalized = true;
    const response = toOpenAIResponsesResponse({
      request: streamRequest,
      generateWrites: streamWrites,
    });
    ensureStart();
    if (response.ok) {
      const text = safeString(response.payload?.output_text);
      writeOpenAISSE(res, {
        event: 'response.output_text.done',
        data: {
          type: 'response.output_text.done',
          item_id: itemId,
          output_index: 0,
          content_index: 0,
          text,
        },
      });
      writeOpenAISSE(res, {
        event: 'response.content_part.done',
        data: {
          type: 'response.content_part.done',
          item_id: itemId,
          output_index: 0,
          content_index: 0,
          part: {
            type: 'output_text',
            text,
            annotations: [],
          },
        },
      });
      writeOpenAISSE(res, {
        event: 'response.output_item.done',
        data: {
          type: 'response.output_item.done',
          output_index: 0,
          item: response.payload?.output?.[0] || null,
        },
      });
      writeOpenAISSE(res, {
        event: 'response.completed',
        data: {
          type: 'response.completed',
          response: response.payload,
        },
      });
    } else {
      writeOpenAISSE(res, {
        event: 'error',
        data: response.payload?.error || response.payload,
      });
    }
    try {
      res.end();
    } catch {
      // ignore
    }
  };

  const generated = await invokeHubGenerateStreaming({
    hubServices,
    req,
    token,
    request,
    onWrite(payload) {
      writes.push(payload);
      if (payload?.start?.model_id) {
        streamRequest.model_id = safeString(payload.start.model_id) || streamRequest.model_id;
        ensureStart();
        return;
      }
      if (payload?.delta?.text) {
        ensureStart();
        writeOpenAISSE(res, {
          event: 'response.output_text.delta',
          data: {
            type: 'response.output_text.delta',
            item_id: itemId,
            output_index: 0,
            content_index: 0,
            delta: String(payload.delta.text),
          },
        });
        return;
      }
      if (payload?.done || payload?.error) {
        finalize(writes);
      }
    },
    onEnd() {
      finalize(writes);
    },
  });

  if (!generated.ok && !finalized) {
    writeOpenAISSE(res, {
      event: 'error',
      data: openAIErrorPayload({
        status: generated.status || 503,
        code: generated.code || 'hub_generate_request_failed',
        message: generated.message || 'Hub generate service request failed',
      }).error,
    });
    try {
      res.end();
    } catch {
      // ignore
    }
    return;
  }

  if (!finalized) {
    finalize(Array.isArray(generated.writes) ? generated.writes : writes);
  }
}

function buildClientAccessKeyActor(rawActor = {}) {
  const actor = rawActor && typeof rawActor === 'object' ? rawActor : {};
  const user_id = safeString(actor.user_id || actor.created_by_user_id);
  const app_id = safeString(actor.app_id || actor.created_by_app_id);
  const created_via = safeString(actor.created_via || actor.via || actor.created_by_app_id || actor.app_id || 'hub_local_ui') || 'hub_local_ui';
  return {
    user_id,
    app_id,
    created_via,
    allow_override: actor.allow_override === true,
  };
}

function manageAccessKeyDenied(message = 'Client is not allowed to manage Hub access keys') {
  return {
    ok: false,
    status: 403,
    code: 'permission_denied',
    message,
  };
}

function requireXtAccessKeyManager(req) {
  const auth = requireHttpClient(req);
  if (!auth.ok) return auth;

  const client = auth.client && typeof auth.client === 'object' ? auth.client : {};
  const authKind = safeString(auth.auth_kind || client.auth_kind).toLowerCase();
  const appId = safeString(client.app_id || auth.app_id).toLowerCase();
  const scopes = uniqueStrings(
    safeStringArray(auth.scopes || client.scopes).map((item) => safeString(item).toLowerCase())
  );
  const hasManageScope = scopes.some((item) => XT_ACCESS_KEY_MANAGER_SCOPES.has(item));
  const trustedXt = authKind === 'paired_client' && XT_ACCESS_KEY_MANAGER_APP_IDS.has(appId);
  if (!trustedXt && !hasManageScope) {
    return manageAccessKeyDenied();
  }

  return {
    ...auth,
    access_key_actor: buildClientAccessKeyActor({
      user_id: safeString(auth.user_id || client.user_id),
      app_id: safeString(client.app_id || auth.app_id || 'x_terminal') || 'x_terminal',
      created_via: trustedXt ? 'xt_settings_access_keys' : 'xt_scoped_access_keys',
      allow_override: false,
    }),
  };
}

function buildListClientAccessKeysResponse({
  runtimeBaseDir,
  req,
  hostFallback,
  internetHostHint,
  grpcPort,
  wantedAuthKind = '',
  wantedStatus = '',
} = {}) {
  const responseContext = buildClientAccessKeyResponseContext(req, {
    hostFallback,
    internetHostHint,
    grpcPort,
  });
  const snapshot = readClientsSnapshot(runtimeBaseDir);
  const accessKeys = loadClients(runtimeBaseDir)
    .filter((item) => {
      if (wantedAuthKind && safeString(item.auth_kind).toLowerCase() !== wantedAuthKind) return false;
      if (wantedStatus && safeString(item.status).toLowerCase() !== wantedStatus) return false;
      return true;
    })
    .sort((left, right) => {
      const lts = Math.max(
        0,
        Number(left?.last_used_at_ms || 0),
        Number(left?.created_at_ms || 0)
      );
      const rts = Math.max(
        0,
        Number(right?.last_used_at_ms || 0),
        Number(right?.created_at_ms || 0)
      );
      if (lts !== rts) return rts - lts;
      return safeString(left?.access_key_id).localeCompare(safeString(right?.access_key_id));
    })
    .map((item) => toHttpClientAccessKey(item, responseContext, {
      include_secret_token: false,
    }))
    .filter(Boolean);

  return {
    ok: true,
    status: 200,
    json: {
      ok: true,
      schema_version: 'hub.client_access_key_list.v1',
      updated_at_ms: Math.max(0, Number(snapshot.updated_at_ms || 0)),
      access_keys: accessKeys,
    },
  };
}

function issueClientAccessKey({
  runtimeBaseDir,
  req,
  hostFallback,
  internetHostHint,
  grpcPort,
  body,
  actor,
} = {}) {
  const obj = body && typeof body === 'object' ? body : {};
  const resolvedActor = buildClientAccessKeyActor(actor);

  const raw_policy_mode = obj.policy_mode == null ? '' : safeString(obj.policy_mode).toLowerCase();
  if (raw_policy_mode && !POLICY_MODES.has(raw_policy_mode)) {
    return {
      ok: false,
      status: 400,
      json: {
        ok: false,
        error: { code: 'policy_mode_invalid', message: 'policy_mode_invalid', retryable: false },
      },
    };
  }
  const requested_policy_mode = raw_policy_mode || 'new_profile';
  const raw_paid_model_selection_mode = obj.paid_model_selection_mode == null ? '' : safeString(obj.paid_model_selection_mode).toLowerCase();
  const requested_paid_model_selection_mode = raw_paid_model_selection_mode || 'off';
  const requested_allowed_paid_models = uniqueStrings(safeStringArray(obj.allowed_paid_models));
  const requested_default_web_fetch_enabled = obj.default_web_fetch_enabled == null ? true : obj.default_web_fetch_enabled === true;
  const requested_daily_token_limit = parseDailyTokenLimit(obj.daily_token_limit, DEFAULT_PAIRING_DAILY_TOKEN_LIMIT);
  if (requested_policy_mode === 'new_profile') {
    if (raw_paid_model_selection_mode && !PAID_MODEL_SELECTION_MODES.has(raw_paid_model_selection_mode)) {
      return {
        ok: false,
        status: 400,
        json: {
          ok: false,
          error: { code: 'paid_model_selection_mode_invalid', message: 'paid_model_selection_mode_invalid', retryable: false },
        },
      };
    }
    if (requested_paid_model_selection_mode === 'custom_selected_models' && requested_allowed_paid_models.length === 0) {
      return {
        ok: false,
        status: 400,
        json: {
          ok: false,
          error: { code: 'custom_selected_models_empty', message: 'custom_selected_models_empty', retryable: false },
        },
      };
    }
    if (requested_daily_token_limit == null) {
      return {
        ok: false,
        status: 400,
        json: {
          ok: false,
          error: { code: 'daily_token_limit_invalid', message: 'daily_token_limit_invalid', retryable: false },
        },
      };
    }
  }

  const createdAtMs = nowMs();
  const ttlSec = Number(obj.ttl_sec || obj.ttlSec || 0);
  const requestedExpiresAtMs = obj.expires_at_ms != null
    ? Number(obj.expires_at_ms)
    : (Number.isFinite(ttlSec) && ttlSec > 0 ? (createdAtMs + (Math.floor(ttlSec) * 1000)) : 0);
  if (requestedExpiresAtMs && (!Number.isFinite(requestedExpiresAtMs) || requestedExpiresAtMs <= createdAtMs)) {
    return {
      ok: false,
      status: 400,
      json: {
        ok: false,
        error: { code: 'expires_at_ms_invalid', message: 'expires_at_ms_invalid', retryable: false },
      },
    };
  }

  const requestedName = uniqueStrings([
    obj.name,
    obj.label,
    obj.device_name,
    obj.note,
  ])[0] || 'Hub Access Key';
  const requestedAccessKeyId = safeString(obj.access_key_id || obj.accessKeyId) || generateAccessKeyId();
  const requestedDeviceId = safeString(obj.device_id || obj.deviceId) || `client_${requestedAccessKeyId.slice(-12)}`;
  const requestedUserId = safeString(obj.user_id || obj.userId) || requestedDeviceId;
  const requestedAppId = safeString(obj.app_id || obj.appId || 'external_terminal') || 'external_terminal';
  const capabilities = safeStringArray(obj.capabilities);
  const scopes = safeStringArray(obj.scopes);
  const allowedCidrs = safeStringArray(obj.allowed_cidrs);
  const baseCapList = capabilities.length ? capabilities : defaultClientCaps();
  const approvedTrustProfile = requested_policy_mode === 'new_profile'
    ? buildApprovedTrustProfile({
        device_id: requestedDeviceId,
        device_name: requestedName,
        capabilities: baseCapList,
        paid_model_selection_mode: requested_paid_model_selection_mode,
        allowed_paid_models: requested_allowed_paid_models,
        default_web_fetch_enabled: requested_default_web_fetch_enabled,
        daily_token_limit: requested_daily_token_limit,
        audit_ref: requestedAccessKeyId,
      })
    : null;
  const capList = approvedTrustProfile
    ? uniqueStrings(approvedTrustProfile.capabilities)
    : uniqueStrings(baseCapList.length ? baseCapList : defaultClientCaps());
  const scopeList = scopes.length ? uniqueStrings(scopes) : uniqueStrings(capList);
  const cidrList = allowedCidrs.length ? uniqueStrings(allowedCidrs) : defaultAllowedCidrs();
  const clientToken = generateClientToken();
  const snapshotBeforeIssue = readClientsSnapshot(runtimeBaseDir);
  const duplicate = (Array.isArray(snapshotBeforeIssue.clients) ? snapshotBeforeIssue.clients : []).some((item) => {
    const candidateAccessKeyId = safeString(item?.access_key_id || item?.accessKeyId || item?.device_id || item?.id);
    const candidateDeviceId = safeString(item?.device_id || item?.id);
    return candidateAccessKeyId === requestedAccessKeyId || candidateDeviceId === requestedDeviceId;
  });
  if (duplicate) {
    return {
      ok: false,
      status: 400,
      json: {
        ok: false,
        error: { code: 'access_key_id_conflict', message: 'access_key_id_conflict', retryable: false },
      },
    };
  }

  const createdByUserId = safeString(
    resolvedActor.allow_override ? (obj.created_by_hub_user_id || obj.created_by_user_id) : ''
  ) || safeString(resolvedActor.user_id);
  const createdByAppId = safeString(
    resolvedActor.allow_override ? (obj.created_by_app_id || obj.created_via) : ''
  ) || safeString(resolvedActor.app_id) || safeString(resolvedActor.created_via) || 'hub_local_ui';
  const createdVia = safeString(
    resolvedActor.allow_override ? obj.created_via : ''
  ) || safeString(resolvedActor.created_via) || 'hub_local_ui';

  const entry = {
    access_key_id: requestedAccessKeyId,
    auth_kind: 'hub_access_key',
    device_id: requestedDeviceId,
    user_id: requestedUserId,
    app_id: requestedAppId,
    name: requestedName,
    note: safeString(obj.note),
    token: clientToken,
    enabled: true,
    created_at_ms: createdAtMs,
    updated_at_ms: createdAtMs,
    expires_at_ms: requestedExpiresAtMs > 0 ? requestedExpiresAtMs : 0,
    capabilities: capList,
    scopes: scopeList,
    allowed_cidrs: cidrList,
    policy_mode: requested_policy_mode,
    created_by_user_id: createdByUserId,
    created_by_app_id: createdByAppId,
    created_via: createdVia,
    ...(approvedTrustProfile ? { approved_trust_profile: approvedTrustProfile } : {}),
  };

  const snapshot = upsertClientInSnapshot(snapshotBeforeIssue, entry);
  if (!writeClientsSnapshot(runtimeBaseDir, snapshot)) {
    return {
      ok: false,
      status: 500,
      json: {
        ok: false,
        error: { code: 'write_failed', message: 'write_failed', retryable: true },
      },
    };
  }

  const responseContext = buildClientAccessKeyResponseContext(req, {
    hostFallback,
    internetHostHint,
    grpcPort,
  });
  const issuedClient = findClientByAccessKeyId(runtimeBaseDir, requestedAccessKeyId) || entry;
  return {
    ok: true,
    status: 200,
    json: {
      ok: true,
      client_token: clientToken,
      access_key: toHttpClientAccessKey(issuedClient, responseContext, {
        include_secret_token: true,
        client_token: clientToken,
      }),
    },
  };
}

function buildClientAccessKeyDetailResponse({
  runtimeBaseDir,
  req,
  hostFallback,
  internetHostHint,
  grpcPort,
  accessKeyId,
  requireHubAccessKeyOnly = false,
} = {}) {
  const client = findClientByAccessKeyId(runtimeBaseDir, accessKeyId);
  if (!client) {
    return {
      ok: false,
      status: 404,
      json: {
        ok: false,
        error: { code: 'access_key_not_found', message: 'access_key_not_found', retryable: false },
      },
    };
  }
  if (requireHubAccessKeyOnly && safeString(client.auth_kind).toLowerCase() !== 'hub_access_key') {
    return {
      ok: false,
      status: 404,
      json: {
        ok: false,
        error: { code: 'access_key_not_found', message: 'access_key_not_found', retryable: false },
      },
    };
  }

  const responseContext = buildClientAccessKeyResponseContext(req, {
    hostFallback,
    internetHostHint,
    grpcPort,
  });
  return {
    ok: true,
    status: 200,
    json: {
      ok: true,
      access_key: toHttpClientAccessKey(client, responseContext),
    },
  };
}

function mutateClientAccessKey({
  runtimeBaseDir,
  req,
  hostFallback,
  internetHostHint,
  grpcPort,
  accessKeyId,
  action,
  body,
  actor,
  requireHubAccessKeyOnly = false,
} = {}) {
  const obj = body && typeof body === 'object' ? body : {};
  const resolvedActor = buildClientAccessKeyActor(actor);
  const snapshot = readClientsSnapshot(runtimeBaseDir);
  const index = findClientSnapshotIndex(snapshot, accessKeyId);
  if (index < 0) {
    return {
      ok: false,
      status: 404,
      json: {
        ok: false,
        error: { code: 'access_key_not_found', message: 'access_key_not_found', retryable: false },
      },
    };
  }

  const rows = Array.isArray(snapshot.clients) ? snapshot.clients : [];
  const current = rows[index] && typeof rows[index] === 'object' ? { ...rows[index] } : null;
  if (!current) {
    return {
      ok: false,
      status: 404,
      json: {
        ok: false,
        error: { code: 'access_key_not_found', message: 'access_key_not_found', retryable: false },
      },
    };
  }

  const currentAuthKind = safeString(current.auth_kind || '').toLowerCase() || 'paired_client';
  if (requireHubAccessKeyOnly && currentAuthKind !== 'hub_access_key') {
    return {
      ok: false,
      status: 404,
      json: {
        ok: false,
        error: { code: 'access_key_not_found', message: 'access_key_not_found', retryable: false },
      },
    };
  }

  const touchedAtMs = nowMs();
  const responseContext = buildClientAccessKeyResponseContext(req, {
    hostFallback,
    internetHostHint,
    grpcPort,
  });

  if (action === 'revoke') {
    const alreadyRevoked = Math.max(0, Number(current.revoked_at_ms || 0)) > 0;
    current.enabled = false;
    current.revoked_at_ms = alreadyRevoked ? Number(current.revoked_at_ms || 0) : touchedAtMs;
    current.revoke_reason = safeString(obj.revoke_reason || obj.note || current.revoke_reason);
    current.revoked_by_user_id = safeString(
      resolvedActor.allow_override ? (obj.revoked_by_hub_user_id || obj.revoked_by_user_id) : ''
    ) || safeString(resolvedActor.user_id) || safeString(current.revoked_by_user_id);
    current.revoked_via = safeString(
      resolvedActor.allow_override ? (obj.revoked_via || obj.app_id) : ''
    ) || safeString(resolvedActor.created_via) || safeString(resolvedActor.app_id) || safeString(current.revoked_via || 'hub_local_ui') || 'hub_local_ui';
    current.updated_at_ms = touchedAtMs;
    snapshot.clients[index] = current;
    snapshot.updated_at_ms = touchedAtMs;

    if (!writeClientsSnapshot(runtimeBaseDir, snapshot)) {
      return {
        ok: false,
        status: 500,
        json: {
          ok: false,
          error: { code: 'write_failed', message: 'write_failed', retryable: true },
        },
      };
    }

    const revokedClient = findClientByAccessKeyId(runtimeBaseDir, accessKeyId) || current;
    return {
      ok: true,
      status: 200,
      json: {
        ok: true,
        idempotent: alreadyRevoked,
        access_key: toHttpClientAccessKey(revokedClient, responseContext),
      },
    };
  }

  if (currentAuthKind !== 'hub_access_key') {
    const code = action === 'update'
      ? 'update_not_supported_for_paired_client'
      : 'rotate_not_supported_for_paired_client';
    return {
      ok: false,
      status: 400,
      json: {
        ok: false,
        error: {
          code,
          message: code,
          retryable: false,
        },
      },
    };
  }
  if (Math.max(0, Number(current.revoked_at_ms || 0)) > 0) {
    const code = action === 'update'
      ? 'update_not_supported_for_revoked_key'
      : 'rotate_not_supported_for_revoked_key';
    return {
      ok: false,
      status: 400,
      json: {
        ok: false,
        error: {
          code,
          message: code,
          retryable: false,
        },
      },
    };
  }

  if (action === 'update') {
    const currentPolicyMode = normalizedPolicyMode(
      current.policy_mode,
      current.approved_trust_profile && typeof current.approved_trust_profile === 'object'
        ? 'new_profile'
        : 'legacy_grant'
    );
    const currentTrustProfile = current.approved_trust_profile && typeof current.approved_trust_profile === 'object'
      ? { ...current.approved_trust_profile }
      : null;
    if (currentPolicyMode !== 'new_profile' || !currentTrustProfile) {
      return {
        ok: false,
        status: 400,
        json: {
          ok: false,
          error: {
            code: 'update_not_supported_without_trust_profile',
            message: 'update_not_supported_without_trust_profile',
            retryable: false,
          },
        },
      };
    }

    const currentBudgetPolicy = currentTrustProfile.budget_policy && typeof currentTrustProfile.budget_policy === 'object'
      ? { ...currentTrustProfile.budget_policy }
      : {};
    const existingDailyTokenLimit = Math.max(
      1,
      Number(currentBudgetPolicy.daily_token_limit || current.daily_token_limit || DEFAULT_PAIRING_DAILY_TOKEN_LIMIT)
        || DEFAULT_PAIRING_DAILY_TOKEN_LIMIT
    );
    const requestedDailyTokenLimit = parseDailyTokenLimit(
      obj.daily_token_limit ?? obj.dailyTokenLimit,
      existingDailyTokenLimit
    );
    if (requestedDailyTokenLimit == null) {
      return {
        ok: false,
        status: 400,
        json: {
          ok: false,
          error: {
            code: 'daily_token_limit_invalid',
            message: 'daily_token_limit_invalid',
            retryable: false,
          },
        },
      };
    }

    current.approved_trust_profile = {
      ...currentTrustProfile,
      budget_policy: {
        ...currentBudgetPolicy,
        daily_token_limit: requestedDailyTokenLimit,
        single_request_token_limit: Math.max(
          1,
          Number(currentBudgetPolicy.single_request_token_limit || DEFAULT_PAIRING_SINGLE_REQUEST_TOKEN_LIMIT)
            || DEFAULT_PAIRING_SINGLE_REQUEST_TOKEN_LIMIT
        ),
      },
    };
    current.policy_mode = 'new_profile';
    current.trust_profile_present = true;
    current.daily_token_limit = requestedDailyTokenLimit;
    current.updated_at_ms = touchedAtMs;
    current.note = obj.note != null ? safeString(obj.note) : safeString(current.note);
    snapshot.clients[index] = current;
    snapshot.updated_at_ms = touchedAtMs;

    if (!writeClientsSnapshot(runtimeBaseDir, snapshot)) {
      return {
        ok: false,
        status: 500,
        json: {
          ok: false,
          error: { code: 'write_failed', message: 'write_failed', retryable: true },
        },
      };
    }

    const updatedClient = findClientByAccessKeyId(runtimeBaseDir, accessKeyId) || current;
    return {
      ok: true,
      status: 200,
      json: {
        ok: true,
        access_key: toHttpClientAccessKey(updatedClient, responseContext),
      },
    };
  }

  const requestedExpiresAtMs = obj.expires_at_ms != null ? Number(obj.expires_at_ms) : Number(current.expires_at_ms || 0);
  if (requestedExpiresAtMs && (!Number.isFinite(requestedExpiresAtMs) || requestedExpiresAtMs <= touchedAtMs)) {
    return {
      ok: false,
      status: 400,
      json: {
        ok: false,
        error: {
          code: 'expires_at_ms_invalid',
          message: 'expires_at_ms_invalid',
          retryable: false,
        },
      },
    };
  }

  const nextToken = generateClientToken();
  current.token = nextToken;
  current.enabled = true;
  current.updated_at_ms = touchedAtMs;
  current.last_rotated_at_ms = touchedAtMs;
  current.rotation_count = Math.max(0, Number(current.rotation_count || 0)) + 1;
  current.expires_at_ms = requestedExpiresAtMs > 0 ? requestedExpiresAtMs : 0;
  current.note = obj.note != null ? safeString(obj.note) : safeString(current.note);
  snapshot.clients[index] = current;
  snapshot.updated_at_ms = touchedAtMs;

  if (!writeClientsSnapshot(runtimeBaseDir, snapshot)) {
    return {
      ok: false,
      status: 500,
      json: {
        ok: false,
        error: { code: 'write_failed', message: 'write_failed', retryable: true },
      },
    };
  }

  const rotatedClient = findClientByAccessKeyId(runtimeBaseDir, accessKeyId) || current;
  return {
    ok: true,
    status: 200,
    json: {
      ok: true,
      client_token: nextToken,
      access_key: toHttpClientAccessKey(rotatedClient, responseContext, {
        include_secret_token: true,
        client_token: nextToken,
      }),
    },
  };
}

function parseQuery(urlObj) {
  const out = {};
  try {
    for (const [k, v] of urlObj.searchParams.entries()) {
      out[String(k || '')] = String(v || '');
    }
  } catch {
    // ignore
  }
  return out;
}

function readBodyJson(req, { maxBytes }) {
  const lim = Math.max(256, Math.min(1024 * 256, Number(maxBytes || 0) || 1024 * 64)); // default 64KB
  return new Promise((resolve) => {
    let settled = false;
    let size = 0;
    let body = '';
    let overflowed = false;
    const finish = (out) => {
      if (settled) return;
      settled = true;
      resolve(out);
    };
    req.on('data', (chunk) => {
      if (settled) return;
      try {
        const s = chunk.toString('utf8');
        size += Buffer.byteLength(s, 'utf8');
        if (size > lim) {
          // Mark overflow and keep draining stream without buffering.
          overflowed = true;
          return;
        }
        if (!overflowed) body += s;
      } catch {
        finish({ ok: false, error: 'bad_body' });
      }
    });
    req.on('end', () => {
      if (settled) return;
      if (overflowed) return finish({ ok: false, error: 'body_too_large' });
      if (!body) return finish({ ok: true, json: {} });
      try {
        const obj = JSON.parse(body);
        finish({ ok: true, json: obj && typeof obj === 'object' ? obj : {} });
      } catch {
        finish({ ok: false, error: 'bad_json' });
      }
    });
    req.on('error', () => finish({ ok: false, error: 'bad_body' }));
  });
}

function boundedInt(raw, { fallback, min, max }) {
  const n = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function parsePositiveInt(raw) {
  const n = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n;
}

function ratio(numerator, denominator) {
  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator <= 0) return 0;
  const r = numerator / denominator;
  if (!Number.isFinite(r) || r <= 0) return 0;
  if (r >= 1) return 1;
  return Number(r.toFixed(6));
}

function rateLimitFromRetryMs(retryAfterMs) {
  const n = Math.max(0, Number(retryAfterMs || 0));
  return Math.ceil(n / 1000);
}

function sourceKeyFromReq(req, queryObj, peerIp) {
  const q = queryObj && typeof queryObj === 'object' ? queryObj : {};
  const headerKey =
    safeString(req?.headers?.['x-source-key'])
    || safeString(req?.headers?.['x-webhook-source-key'])
    || safeString(req?.headers?.['x-source'])
    || safeString(req?.headers?.['x-forwarded-for']);
  return safeString(headerKey || q.source_key || peerIp || 'unknown');
}

function connectionKeyFromReq(req, peerIp, sourceKey) {
  const ip = safeString(req?.socket?.remoteAddress || peerIp || '');
  const remotePort = Math.max(0, Number(req?.socket?.remotePort || 0));
  const localPort = Math.max(0, Number(req?.socket?.localPort || 0));
  const source = safeString(sourceKey || '');
  if (ip && remotePort > 0 && localPort > 0) return `${ip}:${remotePort}->${localPort}`;
  if (ip && remotePort > 0) return `${ip}:${remotePort}`;
  if (ip) return ip;
  return source || 'unknown_connection';
}

function readEnvJsonObject(raw) {
  const text = safeString(raw);
  if (!text) return {};
  try {
    const out = JSON.parse(text);
    return out && typeof out === 'object' ? out : {};
  } catch {
    return {};
  }
}

function combineStringList(...inputs) {
  const out = new Set();
  for (const input of inputs) {
    const arr = safeStringArray(input);
    for (const item of arr) out.add(item);
  }
  return Array.from(out);
}

function connectorIngressPolicyFromEnv(env = process.env) {
  const e = env && typeof env === 'object' ? env : {};
  const fromJson = readEnvJsonObject(e.HUB_CONNECTOR_INGRESS_POLICY_JSON);
  return {
    dm_allow_from: combineStringList(fromJson.dm_allow_from, e.HUB_CONNECTOR_DM_ALLOW_FROM),
    dm_pairing_allow_from: combineStringList(
      fromJson.dm_pairing_allow_from,
      e.HUB_CONNECTOR_DM_PAIRING_ALLOW_FROM,
      e.HUB_CONNECTOR_DM_PAIRING_ALLOWLIST
    ),
    group_allow_from: combineStringList(fromJson.group_allow_from, e.HUB_CONNECTOR_GROUP_ALLOW_FROM),
    webhook_allow_from: combineStringList(fromJson.webhook_allow_from, e.HUB_CONNECTOR_WEBHOOK_ALLOW_FROM),
  };
}

function normalizeIngressTypeFromEvent(input) {
  const raw = safeString(input).toLowerCase();
  if (!raw) return '';
  if (raw === 'message' || raw.startsWith('message.')) return 'message';
  if (raw === 'reaction' || raw.startsWith('reaction') || raw.includes('reaction')) return 'reaction';
  if (raw === 'pin' || raw.startsWith('pin') || raw.includes('pin')) return 'pin';
  if (
    raw === 'member'
    || raw.startsWith('member')
    || raw.includes('member')
    || raw.includes('join')
    || raw.includes('leave')
  ) return 'member';
  if (raw === 'webhook' || raw.startsWith('webhook')) return 'webhook';
  return '';
}

function normalizeChannelScopeFromEvent(input, fallback = 'group') {
  const raw = safeString(input).toLowerCase();
  if (raw === 'dm' || raw === 'direct' || raw === 'direct_message') return 'dm';
  if (raw === 'group' || raw === 'channel' || raw === 'room') return 'group';
  return fallback === 'dm' ? 'dm' : 'group';
}

function senderIdFromEventBody(obj = {}) {
  const body = obj && typeof obj === 'object' ? obj : {};
  const payload = body.payload && typeof body.payload === 'object' ? body.payload : null;
  const candidates = payload ? [body, payload] : [body];
  for (const sample of candidates) {
    if (!sample || typeof sample !== 'object') continue;
    if (sample.sender && typeof sample.sender === 'object') {
      const nested = safeString(sample.sender.id || sample.sender.user_id || sample.sender.member_id);
      if (nested) return nested;
    }
    if (sample.user && typeof sample.user === 'object') {
      const nested = safeString(sample.user.id || sample.user.user_id || sample.user.member_id);
      if (nested) return nested;
    }
    const direct = safeString(
      sample.sender_id
      || sample.actor_id
      || sample.member_id
      || sample.user_id
      || sample.author_id
    );
    if (direct) return direct;
  }
  return '';
}

function connectorIngressEventFromBody({
  connector,
  target_id,
  body,
  replay_key,
  fallbackIngressType = 'message',
} = {}) {
  const obj = body && typeof body === 'object' ? body : {};
  const payload = obj.payload && typeof obj.payload === 'object' ? obj.payload : {};
  const hintedIngressType = normalizeIngressTypeFromEvent(
    obj.ingress_type
    || obj.event_type
    || obj.action
    || obj.type
    || payload.ingress_type
    || payload.event_type
    || payload.action
    || payload.type
  );
  const ingress_type = hintedIngressType || normalizeIngressTypeFromEvent(fallbackIngressType);
  const channelHint = safeString(
    obj.channel_id || obj.room_id || obj.target_id
    || payload.channel_id || payload.room_id || payload.target_id
    || target_id
  ).toLowerCase();
  const scopeFallback = channelHint.startsWith('dm') || channelHint.startsWith('im') ? 'dm' : 'group';
  const channel_scope = normalizeChannelScopeFromEvent(
    obj.channel_scope || obj.scope || obj.channel_type
    || payload.channel_scope || payload.scope || payload.channel_type,
    scopeFallback
  );
  return {
    ingress_type,
    channel_scope,
    sender_id: senderIdFromEventBody(obj),
    channel_id: safeString(obj.channel_id || obj.room_id || obj.thread_id || payload.channel_id || payload.room_id || payload.thread_id || target_id),
    message_id: safeString(obj.message_id || obj.event_id || replay_key || obj.id || payload.message_id || payload.event_id || payload.id),
    event_sequence: parsePositiveInt(
      obj.event_sequence
      || obj.sequence
      || obj.seq
      || payload.event_sequence
      || payload.sequence
      || payload.seq
    ),
    source_id: safeString(obj.source_id || obj.webhook_source_id || payload.source_id || payload.webhook_source_id || `${safeString(connector)}:${safeString(target_id)}`),
    signature_valid: obj.signature_valid !== false && payload.signature_valid !== false,
    replay_detected: obj.replay_detected === true || payload.replay_detected === true,
  };
}

export function createPreauthSurfaceGuard(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const state = new Map(); // source_key -> { count, reset_at_ms, last_seen_ms }
  const stats = {
    total: 0,
    rejected: 0,
    fail_closed: 0,
  };

  const windowMs = boundedInt(opts.window_ms, { fallback: 60_000, min: 1_000, max: 10 * 60_000 });
  const maxPerWindow = boundedInt(opts.max_per_window, { fallback: 12, min: 1, max: 1_000 });
  const maxStateKeys = boundedInt(opts.max_state_keys, { fallback: 2_048, min: 16, max: 100_000 });
  const staleWindowMs = boundedInt(
    opts.stale_window_ms,
    { fallback: Math.max(windowMs * 3, 120_000), min: windowMs, max: 24 * 60 * 60 * 1000 }
  );

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    for (const [key, item] of state.entries()) {
      const resetAtMs = Math.max(0, Number(item?.reset_at_ms || 0));
      const lastSeenMs = Math.max(0, Number(item?.last_seen_ms || 0));
      const staleRef = Math.max(resetAtMs, lastSeenMs);
      if (!staleRef || (ts - staleRef) >= staleWindowMs) state.delete(key);
    }
  }

  function snapshot() {
    const total = Math.max(0, Number(stats.total || 0));
    const rejected = Math.max(0, Number(stats.rejected || 0));
    const failClosed = Math.max(0, Number(stats.fail_closed || 0));
    return {
      total,
      rejected,
      fail_closed: failClosed,
      preauth_reject_rate: ratio(rejected, total),
      state_keys: state.size,
      max_state_keys: maxStateKeys,
      stale_window_ms: staleWindowMs,
      window_ms: windowMs,
      max_per_window: maxPerWindow,
    };
  }

  function check({ source_key, now_ms } = {}) {
    stats.total += 1;
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      const key = safeString(source_key) || 'unknown';
      let cur = state.get(key);
      if (!cur) {
        if (state.size >= maxStateKeys) {
          stats.rejected += 1;
          return {
            ok: false,
            deny_code: 'preauth_state_overflow',
            retry_after_ms: staleWindowMs,
            source_key: key,
          };
        }
        cur = {
          count: 0,
          reset_at_ms: now + windowMs,
          last_seen_ms: now,
        };
      } else {
        const resetAtMs = Math.max(0, Number(cur.reset_at_ms || 0));
        if (!resetAtMs || now >= resetAtMs) {
          cur.count = 0;
          cur.reset_at_ms = now + windowMs;
        }
        cur.last_seen_ms = now;
      }

      if (cur.count >= maxPerWindow) {
        state.set(key, cur);
        stats.rejected += 1;
        return {
          ok: false,
          deny_code: 'rate_limited',
          retry_after_ms: Math.max(1_000, Math.max(0, Number(cur.reset_at_ms || 0) - now)),
          source_key: key,
        };
      }

      cur.count += 1;
      cur.last_seen_ms = now;
      if (!Number(cur.reset_at_ms || 0)) cur.reset_at_ms = now + windowMs;
      state.set(key, cur);
      return {
        ok: true,
        source_key: key,
        remaining: Math.max(0, maxPerWindow - cur.count),
      };
    } catch {
      stats.rejected += 1;
      stats.fail_closed += 1;
      return {
        ok: false,
        deny_code: 'preauth_fail_closed',
        retry_after_ms: staleWindowMs,
        source_key: safeString(source_key) || 'unknown',
      };
    }
  }

  return {
    check,
    snapshot,
    prune,
  };
}

export function createUnauthorizedFloodBreaker(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const state = new Map(); // connection_key -> { unauthorized_count, window_started_ms, penalty_until_ms, last_seen_ms, last_deny_code }
  const stats = {
    checks: 0,
    dropped: 0,
    unauthorized: 0,
    penalties: 0,
    fail_closed: 0,
    sampled_drop_logs: 0,
  };

  const windowMs = boundedInt(opts.window_ms, { fallback: 30_000, min: 1_000, max: 10 * 60_000 });
  const maxUnauthorizedPerWindow = boundedInt(opts.max_unauthorized_per_window, { fallback: 8, min: 1, max: 10_000 });
  const penaltyMs = boundedInt(opts.penalty_ms, { fallback: 15_000, min: 1_000, max: 10 * 60_000 });
  const maxStateKeys = boundedInt(opts.max_state_keys, { fallback: 4_096, min: 16, max: 100_000 });
  const staleWindowMs = boundedInt(
    opts.stale_window_ms,
    { fallback: Math.max(windowMs * 4, 120_000), min: windowMs, max: 24 * 60 * 60 * 1000 }
  );
  const auditSampleEvery = boundedInt(opts.audit_sample_every, { fallback: 5, min: 1, max: 10_000 });

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    for (const [key, item] of state.entries()) {
      const lastSeenMs = Math.max(0, Number(item?.last_seen_ms || 0));
      const penaltyUntilMs = Math.max(0, Number(item?.penalty_until_ms || 0));
      const staleRef = Math.max(lastSeenMs, penaltyUntilMs);
      if (!staleRef || (ts - staleRef) >= staleWindowMs) state.delete(key);
    }
  }

  function dropAuditSampled() {
    if (auditSampleEvery <= 1) return true;
    const dropped = Math.max(0, Number(stats.dropped || 0));
    return (dropped % auditSampleEvery) === 1;
  }

  function ensureStateCapacity() {
    if (state.size < maxStateKeys) return;
    let oldestKey = '';
    let oldestSeen = Number.POSITIVE_INFINITY;
    for (const [key, item] of state.entries()) {
      const seen = Math.max(0, Number(item?.last_seen_ms || 0));
      if (seen < oldestSeen) {
        oldestSeen = seen;
        oldestKey = key;
      }
    }
    if (oldestKey) state.delete(oldestKey);
  }

  function snapshot() {
    return {
      checks: Math.max(0, Number(stats.checks || 0)),
      dropped: Math.max(0, Number(stats.dropped || 0)),
      unauthorized: Math.max(0, Number(stats.unauthorized || 0)),
      penalties: Math.max(0, Number(stats.penalties || 0)),
      fail_closed: Math.max(0, Number(stats.fail_closed || 0)),
      sampled_drop_logs: Math.max(0, Number(stats.sampled_drop_logs || 0)),
      unauthorized_flood_drop_count: Math.max(0, Number(stats.dropped || 0)),
      state_keys: state.size,
      max_state_keys: maxStateKeys,
      window_ms: windowMs,
      penalty_ms: penaltyMs,
      stale_window_ms: staleWindowMs,
      max_unauthorized_per_window: maxUnauthorizedPerWindow,
      audit_sample_every: auditSampleEvery,
    };
  }

  function check({ connection_key, now_ms } = {}) {
    stats.checks += 1;
    const key = safeString(connection_key) || 'unknown_connection';
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      let cur = state.get(key);
      if (!cur) {
        ensureStateCapacity();
        cur = {
          unauthorized_count: 0,
          window_started_ms: now,
          penalty_until_ms: 0,
          last_seen_ms: now,
          last_deny_code: '',
        };
      }
      cur.last_seen_ms = now;
      state.set(key, cur);

      const penaltyUntilMs = Math.max(0, Number(cur.penalty_until_ms || 0));
      if (penaltyUntilMs > now) {
        stats.dropped += 1;
        const sampled = dropAuditSampled();
        if (sampled) stats.sampled_drop_logs += 1;
        return {
          ok: false,
          deny_code: 'unauthorized_flood_dropped',
          retry_after_ms: Math.max(1_000, penaltyUntilMs - now),
          connection_key: key,
          audit_sampled: sampled,
          last_deny_code: safeString(cur.last_deny_code || ''),
        };
      }

      return {
        ok: true,
        connection_key: key,
      };
    } catch {
      stats.dropped += 1;
      stats.fail_closed += 1;
      return {
        ok: false,
        deny_code: 'unauthorized_flood_fail_closed',
        retry_after_ms: windowMs,
        connection_key: key,
        audit_sampled: true,
        last_deny_code: '',
      };
    }
  }

  function recordUnauthorized({ connection_key, deny_code, now_ms } = {}) {
    stats.unauthorized += 1;
    const key = safeString(connection_key) || 'unknown_connection';
    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      prune(now);
      let cur = state.get(key);
      if (!cur) {
        ensureStateCapacity();
        cur = {
          unauthorized_count: 0,
          window_started_ms: now,
          penalty_until_ms: 0,
          last_seen_ms: now,
          last_deny_code: '',
        };
      }

      if ((now - Math.max(0, Number(cur.window_started_ms || 0))) >= windowMs) {
        cur.unauthorized_count = 0;
        cur.window_started_ms = now;
      }

      cur.unauthorized_count = Math.max(0, Number(cur.unauthorized_count || 0)) + 1;
      cur.last_seen_ms = now;
      cur.last_deny_code = safeString(deny_code || '');

      let triggered = false;
      if (cur.unauthorized_count >= maxUnauthorizedPerWindow) {
        cur.penalty_until_ms = Math.max(now + penaltyMs, Math.max(0, Number(cur.penalty_until_ms || 0)));
        cur.unauthorized_count = 0;
        cur.window_started_ms = now;
        triggered = true;
        stats.penalties += 1;
      }

      state.set(key, cur);
      return {
        ok: true,
        triggered,
        connection_key: key,
        penalty_until_ms: Math.max(0, Number(cur.penalty_until_ms || 0)),
      };
    } catch {
      stats.fail_closed += 1;
      return {
        ok: false,
        triggered: true,
        connection_key: key,
        penalty_until_ms: 0,
      };
    }
  }

  return {
    check,
    recordUnauthorized,
    snapshot,
    prune,
  };
}

export function createWebhookReplayGuard(options = {}) {
  const opts = options && typeof options === 'object' ? options : {};
  const clock = typeof opts.nowFn === 'function' ? opts.nowFn : nowMs;
  const db = opts.db && typeof opts.db === 'object' ? opts.db : null;
  const hasPersistentStore = !!(
    db
    && typeof db.claimConnectorWebhookReplay === 'function'
    && typeof db.pruneConnectorWebhookReplayGuard === 'function'
    && typeof db.getConnectorWebhookReplayGuardStats === 'function'
  );
  const seen = new Map(); // replay_key_hash -> { expire_at_ms, last_seen_ms }
  const stats = {
    total: 0,
    blocked: 0,
    fail_closed: 0,
  };
  let replayKeysEstimate = 0;

  const ttlMs = boundedInt(opts.ttl_ms, { fallback: 10 * 60 * 1000, min: 1_000, max: 7 * 24 * 60 * 60 * 1000 });
  const maxKeys = boundedInt(opts.max_keys, { fallback: 20_000, min: 64, max: 1_000_000 });
  const staleWindowMs = boundedInt(opts.stale_window_ms, { fallback: Math.max(ttlMs * 2, 120_000), min: ttlMs, max: 14 * 24 * 60 * 60 * 1000 });

  function prune(now) {
    const ts = Math.max(0, Number(now || clock()) || 0);
    if (hasPersistentStore) {
      const pruned = db.pruneConnectorWebhookReplayGuard({
        now_ms: ts,
        stale_window_ms: staleWindowMs,
      });
      replayKeysEstimate = Math.max(0, Number(pruned?.entries || replayKeysEstimate || 0));
      return;
    }
    for (const [key, item] of seen.entries()) {
      const expireAt = Math.max(0, Number(item?.expire_at_ms || 0));
      const lastSeenMs = Math.max(0, Number(item?.last_seen_ms || 0));
      if (expireAt <= ts || (lastSeenMs > 0 && (ts - lastSeenMs) >= staleWindowMs)) {
        seen.delete(key);
      }
    }
  }

  function snapshot() {
    const total = Math.max(0, Number(stats.total || 0));
    const blocked = Math.max(0, Number(stats.blocked || 0));
    let replayKeys = seen.size;
    if (hasPersistentStore) {
      const storeStats = db.getConnectorWebhookReplayGuardStats();
      replayKeysEstimate = Math.max(0, Number(storeStats?.entries || replayKeysEstimate || 0));
      replayKeys = replayKeysEstimate;
    }
    return {
      total,
      blocked,
      fail_closed: Math.max(0, Number(stats.fail_closed || 0)),
      webhook_replay_block_rate: ratio(blocked, total),
      replay_keys: replayKeys,
      max_keys: maxKeys,
      ttl_ms: ttlMs,
      stale_window_ms: staleWindowMs,
    };
  }

  function claim({
    connector,
    target_id,
    replay_key,
    signature,
    now_ms,
  } = {}) {
    stats.total += 1;
    const c = safeString(connector).toLowerCase();
    const t = safeString(target_id);
    const replayKey = safeString(replay_key);
    const sig = safeString(signature);

    try {
      const now = Math.max(0, Number(now_ms || clock()) || 0);
      if (!c || !t || !replayKey) {
        stats.blocked += 1;
        return {
          ok: false,
          deny_code: 'invalid_replay_key',
          replay_key_hash: '',
        };
      }

      prune(now);
      const replayKeyHash = sha256Hex(`${c}:${t}:${replayKey}:${sig}`);
      if (hasPersistentStore) {
        const persisted = db.claimConnectorWebhookReplay({
          connector: c,
          target_id: t,
          replay_key_hash: replayKeyHash,
          first_seen_at_ms: now,
          expire_at_ms: now + ttlMs,
          max_entries: maxKeys,
          stale_window_ms: staleWindowMs,
        });
        replayKeysEstimate = Math.max(0, Number(persisted?.entries || replayKeysEstimate || 0));
        if (!persisted?.ok) {
          stats.blocked += 1;
          return {
            ok: false,
            deny_code: String(persisted?.deny_code || 'replay_guard_error'),
            replay_key_hash: replayKeyHash,
          };
        }
        return {
          ok: true,
          replay_key_hash: replayKeyHash,
          expire_at_ms: Math.max(0, Number(persisted?.expire_at_ms || (now + ttlMs))),
        };
      }

      const existing = seen.get(replayKeyHash);
      if (existing && Number(existing.expire_at_ms || 0) > now) {
        stats.blocked += 1;
        return {
          ok: false,
          deny_code: 'replay_detected',
          replay_key_hash: replayKeyHash,
        };
      }

      if (!existing && seen.size >= maxKeys) {
        stats.blocked += 1;
        return {
          ok: false,
          deny_code: 'replay_store_overflow',
          replay_key_hash: replayKeyHash,
        };
      }

      seen.set(replayKeyHash, {
        expire_at_ms: now + ttlMs,
        last_seen_ms: now,
      });
      return {
        ok: true,
        replay_key_hash: replayKeyHash,
        expire_at_ms: now + ttlMs,
      };
    } catch {
      stats.blocked += 1;
      stats.fail_closed += 1;
      return {
        ok: false,
        deny_code: 'replay_guard_error',
        replay_key_hash: '',
      };
    }
  }

  return {
    claim,
    snapshot,
    prune,
  };
}

let axhubctlAssetCache = null;
function loadAxhubctlAsset() {
  if (axhubctlAssetCache) return axhubctlAssetCache;
  try {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const assetPath = path.resolve(here, '..', 'assets', 'axhubctl');
    if (!fs.existsSync(assetPath)) return null;
    const content = fs.readFileSync(assetPath, 'utf8');
    const sha256 = sha256FileHex(assetPath);
    axhubctlAssetCache = { path: assetPath, content, sha256 };
    return axhubctlAssetCache;
  } catch {
    return null;
  }
}

let axhubClientKitAssetCache = null;
function resolveAxhubClientKitAssetPath() {
  const overridePath = safeString(process.env.HUB_PAIRING_CLIENT_KIT_ASSET_PATH);
  if (overridePath) return path.resolve(overridePath);
  const here = path.dirname(fileURLToPath(import.meta.url));
  return path.resolve(here, '..', 'assets', 'axhub_client_kit.tgz');
}

function loadAxhubClientKitAsset() {
  // NOTE: This asset is usually injected into the .app bundle by tools/build_hub_app.command.
  // Repo/dev runs may not have it.
  try {
    const assetPath = resolveAxhubClientKitAssetPath();
    if (!fs.existsSync(assetPath)) {
      axhubClientKitAssetCache = null;
      return null;
    }
    const stats = fs.statSync(assetPath);
    const size_bytes = Number(stats?.size || 0) || 0;
    const mtimeMs = Number(stats?.mtimeMs || 0) || 0;
    const ctimeMs = Number(stats?.ctimeMs || 0) || 0;
    const cached = axhubClientKitAssetCache;
    if (
      cached
      && cached.path === assetPath
      && cached.size_bytes === size_bytes
      && cached.mtimeMs === mtimeMs
      && cached.ctimeMs === ctimeMs
    ) {
      return cached;
    }
    const sha256 = sha256FileHex(assetPath);
    axhubClientKitAssetCache = { path: assetPath, sha256, size_bytes, mtimeMs, ctimeMs };
    return axhubClientKitAssetCache;
  } catch {
    axhubClientKitAssetCache = null;
    return null;
  }
}

function publicBaseFromReq(req, { hostFallback, portFallback, schemeFallback }) {
  const xfProto = safeString(req?.headers?.['x-forwarded-proto']);
  const xfHost = safeString(req?.headers?.['x-forwarded-host']);
  const host = xfHost || safeString(req?.headers?.host) || safeString(hostFallback);
  const scheme = xfProto || safeString(schemeFallback) || 'http';
  if (!host) {
    // Last resort: construct from configured host/port (may be 0.0.0.0 which is not client-usable).
    const h2 = safeString(hostFallback);
    const p2 = Number(portFallback || 0) > 0 ? Number(portFallback) : 0;
    if (!h2 || !p2) return '';
    return `${scheme}://${h2}:${p2}`;
  }
  return `${scheme}://${host}`;
}

function positiveIntOrZero(v) {
  const n = Number.parseInt(String(v ?? ''), 10);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n;
}

function hostHintFromReq(req, { hostFallback, peerIp }) {
  const hostHeader = safeString(req?.headers?.host);
  if (hostHeader) {
    // Accept "[ipv6]:port", "host:port", or plain host.
    if (hostHeader.startsWith('[') && hostHeader.includes(']')) {
      return safeString(hostHeader.slice(1, hostHeader.indexOf(']')));
    }
    const idx = hostHeader.indexOf(':');
    if (idx > 0) return safeString(hostHeader.slice(0, idx));
    return hostHeader;
  }
  const fallback = safeString(hostFallback);
  if (fallback && fallback !== '0.0.0.0' && fallback !== '::') return fallback;
  if (isPrivateIPv4(peerIp) || isLoopbackIp(peerIp)) return safeString(peerIp);
  return '';
}

export function startPairingHTTPServer({
  db,
  hubServices,
  preauthGuard,
  unauthorizedFloodBreaker,
  connectorRuntimeOrchestrator,
  connectorTargetOrderingGuard,
  connectorDeliveryReceiptCompensator,
  webhookReplayGuard,
} = {}) {
  const enabled = safeString(process.env.HUB_PAIRING_ENABLE || '1');
  if (enabled === '0' || enabled.toLowerCase() === 'false') {
    // eslint-disable-next-line no-console
    console.log('[hub_pairing] disabled (HUB_PAIRING_ENABLE=0)');
    return () => {};
  }

  const host = safeString(process.env.HUB_PAIRING_HOST) || safeString(process.env.HUB_HOST) || '0.0.0.0';
  const grpcPort = Number(process.env.HUB_PORT || 50051);
  const port = Number(process.env.HUB_PAIRING_PORT || (Number.isFinite(grpcPort) ? grpcPort + 1 : 50052));
  const schemeFallback = safeString(process.env.HUB_PAIRING_PUBLIC_SCHEME || '') || 'http';
  const hostFallback = safeString(process.env.HUB_PAIRING_PUBLIC_HOST || '') || safeString(process.env.HUB_HOST || '');
  const runtimeBaseDir = resolveRuntimeBaseDir();
  const hubIdentity = resolveHubIdentity({
    runtimeBaseDir,
    env: process.env,
  });
  const internetHostHint = resolveHubInternetHostHint({
    runtimeBaseDir,
    env: process.env,
  });

  const allowedCidrs = safeStringArray(process.env.HUB_PAIRING_ALLOWED_CIDRS || 'private,loopback');
  const preauthBodyMaxBytes = boundedInt(process.env.HUB_PREAUTH_BODY_MAX_BYTES, {
    fallback: 64 * 1024,
    min: 256,
    max: 1024 * 256,
  });
  const internalPreauthGuard = preauthGuard && typeof preauthGuard?.check === 'function'
    ? preauthGuard
    : createPreauthSurfaceGuard({
      window_ms: boundedInt(process.env.HUB_PREAUTH_WINDOW_MS, { fallback: 60_000, min: 1_000, max: 10 * 60_000 }),
      max_per_window: boundedInt(process.env.HUB_PAIRING_RL_PER_MIN, { fallback: 12, min: 1, max: 1_000 }),
      max_state_keys: boundedInt(process.env.HUB_PREAUTH_MAX_STATE_KEYS, { fallback: 2_048, min: 16, max: 100_000 }),
      stale_window_ms: boundedInt(process.env.HUB_PREAUTH_STALE_WINDOW_MS, { fallback: 180_000, min: 60_000, max: 24 * 60 * 60 * 1000 }),
    });
  const internalUnauthorizedFloodBreaker = unauthorizedFloodBreaker
    && typeof unauthorizedFloodBreaker?.check === 'function'
    && typeof unauthorizedFloodBreaker?.recordUnauthorized === 'function'
    ? unauthorizedFloodBreaker
    : createUnauthorizedFloodBreaker({
      window_ms: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_WINDOW_MS, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 }),
      max_unauthorized_per_window: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_MAX_PER_WINDOW, { fallback: 8, min: 1, max: 10_000 }),
      penalty_ms: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_PENALTY_MS, { fallback: 15_000, min: 1_000, max: 10 * 60 * 1000 }),
      max_state_keys: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_MAX_STATE_KEYS, { fallback: 4_096, min: 16, max: 100_000 }),
      stale_window_ms: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_STALE_WINDOW_MS, { fallback: 300_000, min: 30_000, max: 24 * 60 * 60 * 1000 }),
      audit_sample_every: boundedInt(process.env.HUB_UNAUTHORIZED_FLOOD_AUDIT_SAMPLE_EVERY, { fallback: 5, min: 1, max: 10_000 }),
    });
  const internalConnectorRuntimeOrchestrator = connectorRuntimeOrchestrator
    && typeof connectorRuntimeOrchestrator?.applySignal === 'function'
    && typeof connectorRuntimeOrchestrator?.snapshot === 'function'
    && typeof connectorRuntimeOrchestrator?.getTarget === 'function'
    ? connectorRuntimeOrchestrator
    : createConnectorReconnectOrchestrator({
      stale_window_ms: boundedInt(process.env.HUB_CONNECTOR_RUNTIME_STALE_WINDOW_MS, { fallback: 15 * 60 * 1000, min: 60 * 1000, max: 7 * 24 * 60 * 60 * 1000 }),
      max_targets: boundedInt(process.env.HUB_CONNECTOR_RUNTIME_MAX_TARGETS, { fallback: 2_048, min: 16, max: 100_000 }),
      reconnect_backoff_base_ms: boundedInt(process.env.HUB_CONNECTOR_RECONNECT_BACKOFF_BASE_MS, { fallback: 1_000, min: 100, max: 60_000 }),
      reconnect_backoff_max_ms: boundedInt(process.env.HUB_CONNECTOR_RECONNECT_BACKOFF_MAX_MS, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 }),
      reconnect_samples_max: boundedInt(process.env.HUB_CONNECTOR_RECONNECT_SAMPLES_MAX, { fallback: 2_048, min: 32, max: 100_000 }),
    });
  const internalConnectorTargetOrderingGuard = connectorTargetOrderingGuard
    && typeof connectorTargetOrderingGuard?.begin === 'function'
    && typeof connectorTargetOrderingGuard?.complete === 'function'
    && typeof connectorTargetOrderingGuard?.snapshot === 'function'
    && typeof connectorTargetOrderingGuard?.getTarget === 'function'
    ? connectorTargetOrderingGuard
    : createConnectorTargetOrderingGuard({
      lock_ttl_ms: boundedInt(process.env.HUB_CONNECTOR_TARGET_LOCK_TTL_MS, { fallback: 30_000, min: 1_000, max: 10 * 60 * 1000 }),
      seen_ttl_ms: boundedInt(process.env.HUB_CONNECTOR_ORDERING_SEEN_TTL_MS, { fallback: 10 * 60 * 1000, min: 10_000, max: 24 * 60 * 60 * 1000 }),
      stale_window_ms: boundedInt(process.env.HUB_CONNECTOR_ORDERING_STALE_WINDOW_MS, { fallback: 15 * 60 * 1000, min: 60 * 1000, max: 7 * 24 * 60 * 60 * 1000 }),
      max_targets: boundedInt(process.env.HUB_CONNECTOR_ORDERING_MAX_TARGETS, { fallback: 2_048, min: 16, max: 100_000 }),
      max_seen_per_target: boundedInt(process.env.HUB_CONNECTOR_ORDERING_MAX_SEEN_PER_TARGET, { fallback: 2_048, min: 16, max: 100_000 }),
    });
  const internalConnectorDeliveryReceiptCompensator = connectorDeliveryReceiptCompensator
    && typeof connectorDeliveryReceiptCompensator?.prepare === 'function'
    && typeof connectorDeliveryReceiptCompensator?.commit === 'function'
    && typeof connectorDeliveryReceiptCompensator?.undo === 'function'
    && typeof connectorDeliveryReceiptCompensator?.runCompensation === 'function'
    && typeof connectorDeliveryReceiptCompensator?.snapshot === 'function'
    && typeof connectorDeliveryReceiptCompensator?.getTarget === 'function'
    ? connectorDeliveryReceiptCompensator
    : createConnectorDeliveryReceiptCompensator({
      stale_window_ms: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_STALE_WINDOW_MS, { fallback: 6 * 60 * 60 * 1000, min: 60 * 1000, max: 14 * 24 * 60 * 60 * 1000 }),
      max_entries: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_MAX_ENTRIES, { fallback: 10_000, min: 64, max: 1_000_000 }),
      default_commit_timeout_ms: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_COMMIT_TIMEOUT_MS, { fallback: 30_000, min: 1_000, max: 24 * 60 * 60 * 1000 }),
      max_compensation_batch: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_COMPENSATION_MAX_JOBS, { fallback: 128, min: 1, max: 10_000 }),
      compensation_retry_ms: boundedInt(process.env.HUB_CONNECTOR_RECEIPT_COMPENSATION_RETRY_MS, { fallback: 5_000, min: 500, max: 10 * 60 * 1000 }),
    });
  const internalWebhookReplayGuard = webhookReplayGuard && typeof webhookReplayGuard?.claim === 'function'
    ? webhookReplayGuard
    : createWebhookReplayGuard({
      db,
      ttl_ms: boundedInt(process.env.HUB_WEBHOOK_REPLAY_TTL_MS, { fallback: 10 * 60 * 1000, min: 1_000, max: 7 * 24 * 60 * 60 * 1000 }),
      max_keys: boundedInt(process.env.HUB_WEBHOOK_REPLAY_MAX_KEYS, { fallback: 20_000, min: 64, max: 1_000_000 }),
      stale_window_ms: boundedInt(process.env.HUB_WEBHOOK_REPLAY_STALE_WINDOW_MS, { fallback: 20 * 60 * 1000, min: 10 * 60 * 1000, max: 14 * 24 * 60 * 60 * 1000 }),
    });
  const connectorIngressPolicy = connectorIngressPolicyFromEnv(process.env);
  const ingressScanMaxEvents = boundedInt(process.env.HUB_CONNECTOR_INGRESS_SCAN_MAX_EVENTS, {
    fallback: 2_000,
    min: 64,
    max: 100_000,
  });
  const ingressScanEntries = [];

  function recordIngressScan(entry) {
    const item = entry && typeof entry === 'object' ? entry : null;
    if (item) {
      ingressScanEntries.push({
        ingress_type: safeString(item.ingress_type),
        policy_checked: item.policy_checked !== false,
        allowed: !!item.allowed,
        blocked: item.blocked === true || item.allowed === false || !!safeString(item.deny_code),
        deny_code: safeString(item.deny_code),
        audit_logged: item.audit_logged !== false,
      });
      if (ingressScanEntries.length > ingressScanMaxEvents) {
        ingressScanEntries.splice(0, ingressScanEntries.length - ingressScanMaxEvents);
      }
    }
    return buildNonMessageIngressScanStats(ingressScanEntries);
  }

  function gateEvidenceFields(stats) {
    const snapshot = buildNonMessageIngressGateSnapshot({ stats });
    return {
      non_message_ingress_gate_schema_version: safeString(snapshot?.schema_version || ''),
      non_message_ingress_gate_measured_at_ms: Math.max(0, Number(snapshot?.measured_at_ms || 0)),
      non_message_ingress_gate_pass: snapshot?.pass === true,
      non_message_ingress_gate_incident_codes: Array.isArray(snapshot?.incident_codes)
        ? snapshot.incident_codes.map((code) => safeString(code)).filter(Boolean)
        : [],
      non_message_ingress_gate_thresholds: snapshot && typeof snapshot.thresholds === 'object'
        ? {
            non_message_ingress_policy_coverage_min: Number(snapshot.thresholds.non_message_ingress_policy_coverage_min || 0),
            blocked_event_miss_rate_max_exclusive: Number(snapshot.thresholds.blocked_event_miss_rate_max_exclusive || 0),
          }
        : {},
      non_message_ingress_gate_checks: Array.isArray(snapshot?.checks)
        ? snapshot.checks.map((check) => ({
            key: safeString(check?.key || ''),
            pass: check?.pass === true,
            comparator: safeString(check?.comparator || ''),
            expected: Number(check?.expected || 0),
            actual: Number(check?.actual || 0),
          }))
        : [],
      non_message_ingress_gate_metrics: snapshot && typeof snapshot.metrics === 'object'
        ? {
            ingress_total: Number(snapshot.metrics.ingress_total || 0),
            non_message_ingress_total: Number(snapshot.metrics.non_message_ingress_total || 0),
            non_message_ingress_policy_checked: Number(snapshot.metrics.non_message_ingress_policy_checked || 0),
            non_message_ingress_policy_coverage: Number(snapshot.metrics.non_message_ingress_policy_coverage || 0),
            blocked_event_total: Number(snapshot.metrics.blocked_event_total || 0),
            blocked_event_audited: Number(snapshot.metrics.blocked_event_audited || 0),
            blocked_event_miss_total: Number(snapshot.metrics.blocked_event_miss_total || 0),
            blocked_event_miss_rate: Number(snapshot.metrics.blocked_event_miss_rate || 0),
          }
        : {},
    };
  }

  function safeGuardSnapshot(guard, fallback) {
    try {
      if (guard && typeof guard.snapshot === 'function') return guard.snapshot();
    } catch {
      // ignore and fallback
    }
    return fallback;
  }

  function parseAuditRowsLimit(raw) {
    return boundedInt(raw, { fallback: 200, min: 1, max: 200 });
  }

  function listConnectorIngressAuditRows(filters = {}) {
    if (!db || typeof db.listAuditEvents !== 'function') return [];
    const f = filters && typeof filters === 'object' ? filters : {};
    const rows = db.listAuditEvents({
      since_ms: Math.max(0, Number(f.since_ms || 0)),
      until_ms: Math.max(0, Number(f.until_ms || 0)),
      device_id: safeString(f.device_id || ''),
      user_id: safeString(f.user_id || ''),
      project_id: safeString(f.project_id || ''),
      request_id: safeString(f.request_id || ''),
    });
    const limit = parseAuditRowsLimit(f.limit);
    const out = [];
    for (const row of Array.isArray(rows) ? rows : []) {
      const eventType = safeString(row?.event_type).toLowerCase();
      if (eventType !== 'connector.ingress.allowed' && eventType !== 'connector.ingress.denied') continue;
      out.push(row);
      if (out.length >= limit) break;
    }
    return out;
  }

  function appendIngressAudit({
    event_type,
    severity,
    ok,
    deny_code,
    error_message,
    ext,
  } = {}) {
    if (!db || typeof db.appendAudit !== 'function') return;
    const preauthMetrics = safeGuardSnapshot(internalPreauthGuard, {
      total: 0,
      rejected: 0,
      fail_closed: 0,
      preauth_reject_rate: 0,
      state_keys: 0,
      max_state_keys: 0,
      stale_window_ms: 0,
      window_ms: 0,
      max_per_window: 0,
    });
    const replayMetrics = safeGuardSnapshot(internalWebhookReplayGuard, {
      total: 0,
      blocked: 0,
      fail_closed: 0,
      webhook_replay_block_rate: 0,
      replay_keys: 0,
      max_keys: 0,
      ttl_ms: 0,
      stale_window_ms: 0,
    });
    const unauthorizedFloodMetrics = safeGuardSnapshot(internalUnauthorizedFloodBreaker, {
      checks: 0,
      dropped: 0,
      unauthorized: 0,
      penalties: 0,
      fail_closed: 0,
      sampled_drop_logs: 0,
      unauthorized_flood_drop_count: 0,
      state_keys: 0,
      max_state_keys: 0,
      window_ms: 0,
      penalty_ms: 0,
      stale_window_ms: 0,
      max_unauthorized_per_window: 0,
      audit_sample_every: 1,
    });
    const connectorRuntimeMetrics = safeGuardSnapshot(internalConnectorRuntimeOrchestrator, {
      targets: 0,
      signals: 0,
      denied: 0,
      fail_closed: 0,
      state_corrupt_incidents: 0,
      fallback_entries: 0,
      reconnect_attempts: 0,
      connector_reconnect_ms_p95: 0,
      reconnect_sample_count: 0,
      by_state: {
        idle: 0,
        connecting: 0,
        ready: 0,
        degraded_polling: 0,
        recovering: 0,
      },
    });
    const orderingMetrics = safeGuardSnapshot(internalConnectorTargetOrderingGuard, {
      targets: 0,
      in_flight_targets: 0,
      begin_total: 0,
      begin_rejected: 0,
      complete_total: 0,
      complete_rejected: 0,
      accepted: 0,
      lock_conflict_count: 0,
      out_of_order_reject_count: 0,
      duplicate_reject_count: 0,
      state_corrupt_incidents: 0,
      fail_closed: 0,
    });
    const receiptMetrics = safeGuardSnapshot(internalConnectorDeliveryReceiptCompensator, {
      entries: 0,
      targets: 0,
      prepare_total: 0,
      prepare_rejected: 0,
      commit_total: 0,
      commit_rejected: 0,
      undo_total: 0,
      undo_rejected: 0,
      timeout_undo_promoted: 0,
      compensation_runs: 0,
      compensation_rejected: 0,
      compensated_total: 0,
      compensation_failures: 0,
      overflow_denied: 0,
      state_corrupt_incidents: 0,
      fail_closed: 0,
      compensation_pending_count: 0,
      by_state: {
        prepared: 0,
        committed: 0,
        undo_pending: 0,
        compensated: 0,
      },
    });
    try {
      db.appendAudit({
        event_type: String(event_type || 'pairing.ingress'),
        created_at_ms: nowMs(),
        severity: String(severity || (ok ? 'info' : 'warn')),
        device_id: 'pairing-http',
        user_id: null,
        app_id: 'pairing-http',
        project_id: null,
        session_id: null,
        request_id: null,
        capability: 'events',
        model_id: null,
        ok: !!ok,
        error_code: deny_code ? String(deny_code) : null,
        error_message: deny_code ? String(error_message || deny_code) : null,
        ext_json: JSON.stringify({
          preauth_reject_rate: Number(preauthMetrics.preauth_reject_rate || 0),
          webhook_replay_block_rate: Number(replayMetrics.webhook_replay_block_rate || 0),
          preauth_total: Number(preauthMetrics.total || 0),
          preauth_rejected: Number(preauthMetrics.rejected || 0),
          preauth_state_keys: Number(preauthMetrics.state_keys || 0),
          webhook_replay_total: Number(replayMetrics.total || 0),
          webhook_replay_blocked: Number(replayMetrics.blocked || 0),
          webhook_replay_keys: Number(replayMetrics.replay_keys || 0),
          unauthorized_flood_drop_count: Number(unauthorizedFloodMetrics.unauthorized_flood_drop_count || 0),
          unauthorized_flood_checks: Number(unauthorizedFloodMetrics.checks || 0),
          unauthorized_flood_unauthorized: Number(unauthorizedFloodMetrics.unauthorized || 0),
          unauthorized_flood_penalties: Number(unauthorizedFloodMetrics.penalties || 0),
          connector_runtime_targets: Number(connectorRuntimeMetrics.targets || 0),
          connector_runtime_denied: Number(connectorRuntimeMetrics.denied || 0),
          connector_runtime_state_corrupt_incidents: Number(connectorRuntimeMetrics.state_corrupt_incidents || 0),
          connector_reconnect_ms_p95: Number(connectorRuntimeMetrics.connector_reconnect_ms_p95 || 0),
          connector_ordering_targets: Number(orderingMetrics.targets || 0),
          connector_target_lock_conflict_count: Number(orderingMetrics.lock_conflict_count || 0),
          connector_out_of_order_reject_count: Number(orderingMetrics.out_of_order_reject_count || 0),
          connector_duplicate_event_reject_count: Number(orderingMetrics.duplicate_reject_count || 0),
          connector_receipt_entries: Number(receiptMetrics.entries || 0),
          connector_receipt_prepare_total: Number(receiptMetrics.prepare_total || 0),
          connector_receipt_commit_total: Number(receiptMetrics.commit_total || 0),
          connector_receipt_undo_total: Number(receiptMetrics.undo_total || 0),
          connector_compensation_pending_count: Number(receiptMetrics.compensation_pending_count || 0),
          connector_compensated_total: Number(receiptMetrics.compensated_total || 0),
          connector_receipt_fail_closed: Number(receiptMetrics.fail_closed || 0),
          ...(ext && typeof ext === 'object' ? ext : {}),
        }),
      });
    } catch {
      // audit sink failures do not flip request outcome
    }
  }

  function callPreauthGuard(sourceKey) {
    try {
      const out = internalPreauthGuard.check({
        source_key: sourceKey,
        now_ms: nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'preauth_fail_closed',
        retry_after_ms: 60_000,
        source_key: safeString(sourceKey),
      };
    } catch {
      return {
        ok: false,
        deny_code: 'preauth_fail_closed',
        retry_after_ms: 60_000,
        source_key: safeString(sourceKey),
      };
    }
  }

  function callUnauthorizedFloodGuard(connectionKey) {
    try {
      const out = internalUnauthorizedFloodBreaker.check({
        connection_key: connectionKey,
        now_ms: nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'unauthorized_flood_fail_closed',
        retry_after_ms: 30_000,
        connection_key: safeString(connectionKey),
        audit_sampled: true,
        last_deny_code: '',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'unauthorized_flood_fail_closed',
        retry_after_ms: 30_000,
        connection_key: safeString(connectionKey),
        audit_sampled: true,
        last_deny_code: '',
      };
    }
  }

  function noteUnauthorizedDeny(connectionKey, denyCode, statusCode) {
    const code = Math.max(0, Number(statusCode || 0));
    if (code !== 401 && code !== 403) return;
    try {
      internalUnauthorizedFloodBreaker.recordUnauthorized({
        connection_key: connectionKey,
        deny_code: denyCode,
        now_ms: nowMs(),
      });
    } catch {
      // ignore: request already denied; breaker failures are handled on check path.
    }
  }

  function callConnectorRuntimeSignal({
    connector,
    target_id,
    signal,
    error_code,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorRuntimeOrchestrator.applySignal({
        connector,
        target_id,
        signal,
        error_code,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'orchestrator_fail_closed',
        state: 'idle',
        retry_after_ms: 1_000,
        action: 'none',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'orchestrator_fail_closed',
        state: 'idle',
        retry_after_ms: 1_000,
        action: 'none',
      };
    }
  }

  function callConnectorOrderingBegin({
    connector,
    target_id,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorTargetOrderingGuard.begin({
        connector,
        target_id,
        event_id,
        event_sequence,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'ordering_guard_error',
        retry_after_ms: 1_000,
      };
    } catch {
      return {
        ok: false,
        deny_code: 'ordering_guard_error',
        retry_after_ms: 1_000,
      };
    }
  }

  function callConnectorOrderingComplete({
    connector,
    target_id,
    lock_token,
    success,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorTargetOrderingGuard.complete({
        connector,
        target_id,
        lock_token,
        success: success === true,
        event_id,
        event_sequence,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'ordering_guard_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'ordering_guard_error',
      };
    }
  }

  function callConnectorReceiptPrepare({
    connector,
    target_id,
    idempotency_key,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorDeliveryReceiptCompensator.prepare({
        connector,
        target_id,
        idempotency_key,
        event_id,
        event_sequence,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    }
  }

  function callConnectorReceiptCommit({
    connector,
    target_id,
    idempotency_key,
    provider_receipt,
    event_id,
    event_sequence,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorDeliveryReceiptCompensator.commit({
        connector,
        target_id,
        idempotency_key,
        provider_receipt,
        event_id,
        event_sequence,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    }
  }

  function callConnectorReceiptUndo({
    connector,
    target_id,
    idempotency_key,
    reason,
    compensate_after_ms,
    now_ms,
  } = {}) {
    try {
      const out = internalConnectorDeliveryReceiptCompensator.undo({
        connector,
        target_id,
        idempotency_key,
        reason,
        compensate_after_ms,
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'receipt_guard_error',
      };
    }
  }

  function callConnectorReceiptCompensationTick({
    now_ms,
    max_jobs,
  } = {}) {
    try {
      const out = internalConnectorDeliveryReceiptCompensator.runCompensation({
        now_ms: Number(now_ms || 0) > 0 ? Number(now_ms) : nowMs(),
        max_jobs,
      });
      if (out && typeof out === 'object') return out;
      return {
        ok: false,
        deny_code: 'compensation_worker_error',
      };
    } catch {
      return {
        ok: false,
        deny_code: 'compensation_worker_error',
      };
    }
  }

  const server = http.createServer(async (req, res) => {
    const method = safeString(req?.method || 'GET').toUpperCase();
    const rawUrl = safeString(req?.url || '/');
    let urlObj;
    try {
      // Dummy base: required for URL parsing.
      urlObj = new URL(rawUrl, `http://${host}:${port}`);
    } catch {
      jsonResponse(res, 400, { ok: false, error: { code: 'bad_url', message: 'bad_url', retryable: false } });
      return;
    }

    const pathname = safeString(urlObj.pathname) || '/';
    const q = parseQuery(urlObj);
    const peerIp = peerIpFromReq(req);

    // Global allowlist for pairing port (defense-in-depth).
    if (allowedCidrs.length && !peerAllowedByRules(peerIp, allowedCidrs)) {
      jsonResponse(res, 403, {
        ok: false,
        error: {
          code: 'forbidden',
          message: 'source_ip_not_allowed',
          retryable: false,
          peer_ip: peerIp || '',
          allowed_cidrs: allowedCidrs,
          hint: 'Use the Hub LAN/VPN IP (not a public IP), or update HUB_PAIRING_ALLOWED_CIDRS on the Hub.',
        },
      });
      return;
    }

    // -------------------- Install assets (unauth) --------------------

    if (method === 'GET' && (pathname === '/install/axhubctl' || pathname === '/install/axhubctl.sh')) {
      const asset = loadAxhubctlAsset();
      if (!asset) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'axhubctl_not_found', retryable: false } });
        return;
      }
      res.writeHead(200, {
        'content-type': 'text/plain; charset=utf-8',
        'cache-control': 'no-store',
        'content-disposition': 'attachment; filename="axhubctl"',
        'x-content-sha256': asset.sha256,
      });
      res.end(asset.content);
      return;
    }

    if (method === 'GET' && pathname === '/install/axhubctl.sha256') {
      const asset = loadAxhubctlAsset();
      if (!asset) {
        textResponse(res, 404, 'not_found\n');
        return;
      }
      textResponse(res, 200, `${asset.sha256}  axhubctl\n`);
      return;
    }

    if (method === 'GET' && pathname === '/install/axhubctl.json') {
      const asset = loadAxhubctlAsset();
      if (!asset) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'axhubctl_not_found', retryable: false } });
        return;
      }
      const base = publicBaseFromReq(req, { hostFallback, portFallback: port, schemeFallback });
      const url = base ? `${base}/install/axhubctl` : '/install/axhubctl';
      jsonResponse(res, 200, { ok: true, name: 'axhubctl', sha256: asset.sha256, url });
      return;
    }

    if (method === 'GET' && pathname === '/install/axhub_client_kit.tgz') {
      const asset = loadAxhubClientKitAsset();
      if (!asset) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'axhub_client_kit_not_found', retryable: false } });
        return;
      }
      res.writeHead(200, {
        'content-type': 'application/gzip',
        'cache-control': 'no-store',
        'content-disposition': 'attachment; filename="axhub_client_kit.tgz"',
        'x-content-sha256': asset.sha256,
        ...(asset.size_bytes ? { 'content-length': String(asset.size_bytes) } : {}),
      });
      const rs = fs.createReadStream(asset.path);
      rs.on('error', () => {
        try {
          res.destroy();
        } catch {
          // ignore
        }
      });
      rs.pipe(res);
      return;
    }

    if (method === 'GET' && pathname === '/install/axhub_client_kit.tgz.sha256') {
      const asset = loadAxhubClientKitAsset();
      if (!asset) {
        textResponse(res, 404, 'not_found\n');
        return;
      }
      textResponse(res, 200, `${asset.sha256}  axhub_client_kit.tgz\n`);
      return;
    }

    if (method === 'GET' && pathname === '/install/axhub_client_kit.json') {
      const asset = loadAxhubClientKitAsset();
      if (!asset) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'axhub_client_kit_not_found', retryable: false } });
        return;
      }
      const base = publicBaseFromReq(req, { hostFallback, portFallback: port, schemeFallback });
      const url = base ? `${base}/install/axhub_client_kit.tgz` : '/install/axhub_client_kit.tgz';
      jsonResponse(res, 200, { ok: true, name: 'axhub_client_kit.tgz', sha256: asset.sha256, url, size_bytes: asset.size_bytes });
      return;
    }

    // Discovery metadata for one-click bootstrap (LAN first, then remote).
    if (method === 'GET' && pathname === '/pairing/discovery') {
      const tlsMode = tlsModeFromEnv(process.env);
      const tlsServerName = tlsMode === 'insecure' ? '' : tlsServerNameFromEnv(process.env);
      const pairingRouteMetadata = buildPairingRouteMetadata({
        runtimeBaseDir,
        hubIdentity,
        internetHostHint,
        pairingPort: port,
        grpcPort,
        tlsMode,
        tlsServerName,
      });
      const payload = {
        ok: true,
        service: 'pairing',
        version: 'pairing.v1',
        now_ms: nowMs(),
        pairing_enabled: true,
        hub_instance_id: safeString(hubIdentity.hub_instance_id),
        lan_discovery_name: safeString(hubIdentity.lan_discovery_name),
        hub_host_hint: hostHintFromReq(req, { hostFallback, peerIp }),
        grpc_port: Number(grpcPort || 0) || 50051,
        pairing_port: Number(port || 0) || 50052,
        tls_mode: tlsMode,
        tls_server_name: tlsServerName,
        pairing_profile_epoch: pairingRouteMetadata.pairing_profile_epoch,
        route_pack_version: pairingRouteMetadata.route_pack_version,
        xt_contract_endpoint: XT_HUB_CONTRACT_ENDPOINT,
        xt_contract_schema_version: XT_HUB_CONTRACT_SCHEMA_VERSION,
        hub_product_boundary: HUB_PRODUCT_BOUNDARY,
        rust_kernel_contract_bridge: true,
      };
      if (internetHostHint) payload.internet_host_hint = internetHostHint;
      const pairingWindowSec = positiveIntOrZero(process.env.HUB_PAIRING_WINDOW_SEC);
      if (pairingWindowSec > 0) payload.pairing_window_sec = pairingWindowSec;
      if (safeString(process.env.HUB_PAIRING_DISCOVERY_INCLUDE_RUNTIME) === '1') {
        payload.runtime_base_dir = resolveRuntimeBaseDir();
      }
      jsonResponse(res, 200, payload);
      return;
    }

    // Swift shell public contract bridge: XT should see one Hub entrypoint
    // while the Rust kernel remains the source of truth.
    if (method === 'GET' && (
      pathname === '/xt/hub-contract'
      || pathname === '/xt/contract'
      || pathname === '/contract/xt'
    )) {
      const upstream = await fetchRustHubJSONPath(XT_HUB_CONTRACT_ENDPOINT);
      if (!upstream.ok) {
        jsonResponse(res, 503, {
          schema_version: XT_HUB_CONTRACT_SCHEMA_VERSION,
          ok: false,
          error: 'rust_kernel_contract_unavailable',
          message: upstream.error || 'rust_kernel_contract_unavailable',
          source: 'swift_shell_pairing_proxy',
        });
        return;
      }

      let payload;
      try {
        payload = JSON.parse(upstream.text || '{}');
      } catch {
        jsonResponse(res, 502, {
          schema_version: XT_HUB_CONTRACT_SCHEMA_VERSION,
          ok: false,
          error: 'rust_kernel_contract_invalid_json',
          message: 'Rust kernel returned invalid Hub contract JSON',
          source: 'swift_shell_pairing_proxy',
        });
        return;
      }
      jsonResponse(res, upstream.status || 502, payload);
      return;
    }

    // Health.
    if (method === 'GET' && pathname === '/health') {
      jsonResponse(res, 200, { ok: true, service: 'pairing', now_ms: nowMs() });
      return;
    }

    if (method === 'GET' && pathname === '/v1/models') {
      const auth = requireHttpClient(req);
      if (!auth.ok) {
        openAIErrorResponse(res, auth.status || 401, {
          code: auth.code || 'unauthenticated',
          message: auth.message || 'Missing/invalid client token',
        });
        return;
      }

      const listed = await invokeHubListModels({
        hubServices,
        req,
        token: safeString(auth.client?.token),
        request: {
          client: {},
        },
      });
      if (!listed.ok) {
        openAIErrorResponse(res, listed.status || 503, {
          code: listed.code || 'hub_models_request_failed',
          message: listed.message || 'Hub model service request failed',
        });
        return;
      }

      jsonResponse(res, 200, toOpenAIModelListResponse(listed.response));
      return;
    }

    if (method === 'POST' && pathname === '/v1/chat/completions') {
      const auth = requireHttpClient(req);
      if (!auth.ok) {
        openAIErrorResponse(res, auth.status || 401, {
          code: auth.code || 'unauthenticated',
          message: auth.message || 'Missing/invalid client token',
        });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 256 * 1024 });
      if (!body.ok) {
        openAIErrorResponse(res, 400, {
          code: body.error || 'bad_json',
          message: body.error || 'bad_json',
        });
        return;
      }

      const payload = body.json && typeof body.json === 'object' ? body.json : {};
      const modelId = safeString(payload.model);
      const messages = toHubGenerateMessages(payload.messages);
      const requestedMaxTokens = payload.max_completion_tokens != null
        ? payload.max_completion_tokens
        : payload.max_tokens;
      if (!modelId) {
        openAIErrorResponse(res, 400, {
          code: 'model_required',
          message: 'model is required',
        });
        return;
      }
      if (!messages.length) {
        openAIErrorResponse(res, 400, {
          code: 'messages_required',
          message: 'messages must contain at least one text message',
        });
        return;
      }

      if (payload.stream === true) {
        await streamOpenAIChatCompletions({
          hubServices,
          req,
          res,
          token: safeString(auth.client?.token),
          request: {
            request_id: safeString(payload.request_id || payload.id) || uuid(),
            client: {
              project_id: safeString(req?.headers?.['x-axhub-project-id']),
              session_id: safeString(req?.headers?.['x-axhub-session-id']),
            },
            model_id: safeString(payload.model),
            messages: toHubGenerateMessages(payload.messages),
            max_tokens: positiveIntOrZero(requestedMaxTokens),
            temperature: Number.isFinite(Number(payload.temperature)) ? Number(payload.temperature) : 0,
            top_p: Number.isFinite(Number(payload.top_p)) ? Number(payload.top_p) : 0,
            stream: false,
            created_at_ms: nowMs(),
            fail_closed_on_downgrade:
              payload.fail_closed_on_downgrade === true
              || safeString(req?.headers?.['x-axhub-fail-closed-on-downgrade']) === '1',
          },
          includeUsage: payload?.stream_options?.include_usage === true,
        });
        return;
      }
      const generated = await invokeHubGenerate({
        hubServices,
        req,
        token: safeString(auth.client?.token),
        request: {
          request_id: safeString(payload.request_id || payload.id) || uuid(),
          client: {
            project_id: safeString(req?.headers?.['x-axhub-project-id']),
            session_id: safeString(req?.headers?.['x-axhub-session-id']),
          },
          model_id: modelId,
          messages,
          max_tokens: positiveIntOrZero(requestedMaxTokens),
          temperature: Number.isFinite(Number(payload.temperature)) ? Number(payload.temperature) : 0,
          top_p: Number.isFinite(Number(payload.top_p)) ? Number(payload.top_p) : 0,
          stream: false,
          created_at_ms: nowMs(),
          fail_closed_on_downgrade:
            payload.fail_closed_on_downgrade === true
            || safeString(req?.headers?.['x-axhub-fail-closed-on-downgrade']) === '1',
        },
      });
      if (!generated.ok) {
        openAIErrorResponse(res, generated.status || 503, {
          code: generated.code || 'hub_generate_request_failed',
          message: generated.message || 'Hub generate service request failed',
        });
        return;
      }

      const completion = toOpenAIChatCompletionResponse({
        request: {
          request_id: safeString(payload.request_id || payload.id),
          model_id: modelId,
        },
        generateWrites: generated.writes,
      });
      jsonResponse(res, completion.status || 200, completion.payload);
      return;
    }

    if (method === 'POST' && pathname === '/v1/responses') {
      const auth = requireHttpClient(req);
      if (!auth.ok) {
        openAIErrorResponse(res, auth.status || 401, {
          code: auth.code || 'unauthenticated',
          message: auth.message || 'Missing/invalid client token',
        });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 256 * 1024 });
      if (!body.ok) {
        openAIErrorResponse(res, 400, {
          code: body.error || 'bad_json',
          message: body.error || 'bad_json',
        });
        return;
      }

      const payload = body.json && typeof body.json === 'object' ? body.json : {};
      const modelId = safeString(payload.model);
      const messages = toHubGenerateMessagesFromResponsesPayload(payload);
      if (!modelId) {
        openAIErrorResponse(res, 400, {
          code: 'model_required',
          message: 'model is required',
        });
        return;
      }
      if (!messages.length) {
        openAIErrorResponse(res, 400, {
          code: 'input_required',
          message: 'input must contain at least one text item',
        });
        return;
      }

      if (payload.stream === true) {
        await streamOpenAIResponses({
          hubServices,
          req,
          res,
          token: safeString(auth.client?.token),
          request: {
            request_id: safeString(payload.request_id || payload.id) || uuid(),
            client: {
              project_id: safeString(req?.headers?.['x-axhub-project-id']),
              session_id: safeString(req?.headers?.['x-axhub-session-id']),
            },
            model_id: safeString(payload.model),
            messages: toHubGenerateMessagesFromResponsesPayload(payload),
            max_tokens: positiveIntOrZero(payload.max_output_tokens),
            temperature: Number.isFinite(Number(payload.temperature)) ? Number(payload.temperature) : 0,
            top_p: Number.isFinite(Number(payload.top_p)) ? Number(payload.top_p) : 0,
            stream: false,
            created_at_ms: nowMs(),
            fail_closed_on_downgrade:
              payload.fail_closed_on_downgrade === true
              || safeString(req?.headers?.['x-axhub-fail-closed-on-downgrade']) === '1',
          },
        });
        return;
      }

      const generated = await invokeHubGenerate({
        hubServices,
        req,
        token: safeString(auth.client?.token),
        request: {
          request_id: safeString(payload.request_id || payload.id) || uuid(),
          client: {
            project_id: safeString(req?.headers?.['x-axhub-project-id']),
            session_id: safeString(req?.headers?.['x-axhub-session-id']),
          },
          model_id: modelId,
          messages,
          max_tokens: positiveIntOrZero(payload.max_output_tokens),
          temperature: Number.isFinite(Number(payload.temperature)) ? Number(payload.temperature) : 0,
          top_p: Number.isFinite(Number(payload.top_p)) ? Number(payload.top_p) : 0,
          stream: false,
          created_at_ms: nowMs(),
          fail_closed_on_downgrade:
            payload.fail_closed_on_downgrade === true
            || safeString(req?.headers?.['x-axhub-fail-closed-on-downgrade']) === '1',
        },
      });
      if (!generated.ok) {
        openAIErrorResponse(res, generated.status || 503, {
          code: generated.code || 'hub_generate_request_failed',
          message: generated.message || 'Hub generate service request failed',
        });
        return;
      }

      const response = toOpenAIResponsesResponse({
        request: {
          request_id: safeString(payload.request_id || payload.id),
          model_id: modelId,
        },
        generateWrites: generated.writes,
      });
      jsonResponse(res, response.status || 200, response.payload);
      return;
    }

    if (method === 'POST' && pathname === '/clients/presence') {
      const auth = requireHttpClient(req);
      if (!auth.ok) {
        jsonResponse(res, auth.status || 403, {
          ok: false,
          error: {
            code: auth.code || 'permission_denied',
            message: auth.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 8 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, {
          ok: false,
          error: {
            code: body.error || 'bad_json',
            message: body.error || 'bad_json',
            retryable: false,
          },
        });
        return;
      }

      const payload = body.json && typeof body.json === 'object' ? body.json : {};
      const client = auth.client || {};
      const boundDeviceId = safeString(client.device_id);
      const boundAppId = safeString(client.app_id);
      const requestedDeviceId = safeString(payload.device_id);
      const requestedAppId = safeString(payload.app_id);

      if (requestedDeviceId && requestedDeviceId !== boundDeviceId) {
        jsonResponse(res, 403, {
          ok: false,
          error: {
            code: 'client_identity_mismatch',
            message: 'device_id does not match authenticated client token',
            retryable: false,
          },
        });
        return;
      }

      if (requestedAppId && boundAppId && requestedAppId !== boundAppId) {
        jsonResponse(res, 403, {
          ok: false,
          error: {
            code: 'client_identity_mismatch',
            message: 'app_id does not match authenticated client token',
            retryable: false,
          },
        });
        return;
      }

      const deviceName = safeString(
        payload.device_name
          || payload.name
          || client.name
          || client.trust_profile?.device_name
          || boundDeviceId
      ) || boundDeviceId;

      const entry = upsertDevicePresence(auth.runtimeBaseDir, {
        device_id: boundDeviceId,
        app_id: boundAppId || requestedAppId,
        name: deviceName,
        peer_ip: auth.peerIp,
        route: safeString(payload.route),
        transport_mode: safeString(payload.transport_mode),
        source: 'pairing_http_presence',
        last_seen_at_ms: nowMs(),
      });

      jsonResponse(res, 200, {
        ok: true,
        device_id: safeString(entry?.device_id || boundDeviceId),
        app_id: safeString(entry?.app_id || boundAppId || requestedAppId),
        last_seen_at_ms: Math.max(0, Number(entry?.last_seen_at_ms || 0)),
      });
      return;
    }

    // -------------------- Connector webhook ingress (pre-auth) --------------------

    if (method === 'POST' && pathname.startsWith('/webhook/connectors/')) {
      const tail = pathname.slice('/webhook/connectors/'.length);
      const parts = tail.split('/').filter(Boolean);
      const connector = safeString(parts[0]).toLowerCase();
      const target_id = safeString(parts[1]);
      if (!connector || !target_id) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const sourceKey = sourceKeyFromReq(req, q, peerIp);
      const connectionKey = connectionKeyFromReq(req, peerIp, sourceKey);
      const floodGate = callUnauthorizedFloodGuard(connectionKey);
      if (!floodGate?.ok) {
        const denyCode = safeString(floodGate?.deny_code) || 'unauthorized_flood_fail_closed';
        const failClosed = denyCode === 'unauthorized_flood_fail_closed';
        if (floodGate.audit_sampled !== false) {
          appendIngressAudit({
            event_type: 'connector.webhook.rejected',
            severity: failClosed ? 'error' : 'warn',
            ok: false,
            deny_code: denyCode,
            error_message: denyCode,
            ext: {
              op: 'connector_webhook_ingress',
              connector,
              target_id,
              source_key: safeString(sourceKey),
              connection_key: safeString(floodGate.connection_key || connectionKey),
              last_unauthorized_deny_code: safeString(floodGate.last_deny_code || ''),
              peer_ip: peerIp || '',
              retry_after_ms: Math.max(0, Number(floodGate?.retry_after_ms || 0)),
            },
          });
        }
        if (failClosed) {
          jsonResponse(res, 503, { ok: false, error: { code: denyCode, message: denyCode, retryable: true } });
          return;
        }
        res.writeHead(429, {
          'content-type': 'application/json; charset=utf-8',
          'retry-after': String(rateLimitFromRetryMs(floodGate?.retry_after_ms)),
        });
        res.end(JSON.stringify({
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        }));
        return;
      }
      const limit = callPreauthGuard(sourceKey);
      if (!limit?.ok) {
        const denyCode = safeString(limit?.deny_code) || 'preauth_fail_closed';
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: denyCode === 'preauth_fail_closed' ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            peer_ip: peerIp || '',
            retry_after_ms: Math.max(0, Number(limit?.retry_after_ms || 0)),
          },
        });
        if (denyCode === 'preauth_fail_closed') {
          jsonResponse(res, 503, { ok: false, error: { code: denyCode, message: denyCode, retryable: true } });
          return;
        }
        res.writeHead(429, {
          'content-type': 'application/json; charset=utf-8',
          'retry-after': String(rateLimitFromRetryMs(limit?.retry_after_ms)),
        });
        res.end(JSON.stringify({
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        }));
        return;
      }

      const body = await readBodyJson(req, { maxBytes: preauthBodyMaxBytes });
      if (!body.ok) {
        jsonResponse(res, 400, {
          ok: false,
          error: { code: body.error, message: body.error, retryable: false },
        });
        return;
      }
      const obj = body.json || {};
      const replay_key = safeString(req?.headers?.['x-replay-key'])
        || safeString(req?.headers?.['x-idempotency-key'])
        || safeString(obj.replay_key || obj.event_id || obj.idempotency_key);
      const signature = safeString(req?.headers?.['x-signature'])
        || safeString(req?.headers?.['x-hub-signature'])
        || safeString(obj.signature);

      let replayClaim;
      try {
        replayClaim = internalWebhookReplayGuard.claim({
          connector,
          target_id,
          replay_key,
          signature,
          now_ms: nowMs(),
        });
      } catch {
        replayClaim = { ok: false, deny_code: 'replay_guard_error', replay_key_hash: '' };
      }

      if (!replayClaim?.ok) {
        const denyCode = safeString(replayClaim?.deny_code) || 'replay_guard_error';
        const failClosed = denyCode === 'replay_guard_error';
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: failClosed ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            replay_key_hash: safeString(replayClaim?.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            peer_ip: peerIp || '',
          },
        });
        if (failClosed) {
          jsonResponse(res, 503, { ok: false, error: { code: denyCode, message: denyCode, retryable: true } });
          return;
        }
        jsonResponse(res, 409, { ok: false, error: { code: denyCode, message: denyCode, retryable: false } });
        return;
      }

      const ingressRequestId = safeString(obj.request_id || replay_key || obj.event_id) || `connector_ingress_${uuid()}`;
      const webhookSourceId = safeString(obj.source_id || obj.webhook_source_id || `${connector}:${target_id}`);
      const authzClient = {
        device_id: 'pairing-http',
        app_id: `connector:${connector}`,
        project_id: target_id,
      };
      const statusForDenyCode = (denyCode) => {
        const dc = safeString(denyCode);
        if (dc === 'invalid_event' || dc === 'ingress_type_unsupported') return 400;
        if (dc === 'webhook_replay_detected') return 409;
        if (dc === 'audit_write_failed') return 503;
        return 403;
      };
      const statusForOrderingDenyCode = (denyCode) => {
        const dc = safeString(denyCode);
        if (dc === 'invalid_request') return 400;
        if (dc === 'target_locked') return 429;
        if (dc === 'out_of_order_event' || dc === 'duplicate_event') return 409;
        return 503;
      };
      const statusForReceiptDenyCode = (denyCode) => {
        const dc = safeString(denyCode);
        if (dc === 'invalid_request') return 400;
        if (dc === 'terminal_not_allowed' || dc === 'commit_timeout') return 409;
        return 503;
      };

      const transportAuthz = evaluateConnectorIngressWithAudit({
        db,
        event: {
          ingress_type: 'webhook',
          channel_scope: 'group',
          source_id: webhookSourceId,
          message_id: ingressRequestId,
          signature_valid: obj.signature_valid !== false,
          replay_detected: false,
        },
        policy: connectorIngressPolicy,
        client: authzClient,
        request_id: ingressRequestId,
      });
      if (transportAuthz.allowed && transportAuthz.audit_logged === false) {
        const denyCode = 'audit_write_failed';
        const transportAuditFailStats = recordIngressScan({
          ingress_type: 'webhook',
          policy_checked: true,
          allowed: false,
          blocked: true,
          deny_code: denyCode,
          audit_logged: true,
        });
        const transportAuditFailEvidence = gateEvidenceFields(transportAuditFailStats);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            source_id: webhookSourceId,
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            ingress_type: 'webhook',
            policy_checked: transportAuthz.policy_checked !== false,
            blocked_event_miss_rate: Number(transportAuditFailStats.blocked_event_miss_rate || 0),
            non_message_ingress_policy_coverage: Number(transportAuditFailStats.non_message_ingress_policy_coverage || 0),
            ...transportAuditFailEvidence,
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, statusForDenyCode(denyCode), {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      if (!transportAuthz.allowed) {
        const transportStats = recordIngressScan(transportAuthz);
        const transportEvidence = gateEvidenceFields(transportStats);
        const denyCode = safeString(transportAuthz.deny_code || 'authz_denied') || 'authz_denied';
        const denyStatus = statusForDenyCode(denyCode);
        noteUnauthorizedDeny(connectionKey, denyCode, denyStatus);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: webhookSourceId,
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            ingress_type: 'webhook',
            policy_checked: transportAuthz.policy_checked !== false,
            blocked_event_miss_rate: Number(transportStats.blocked_event_miss_rate || 0),
            non_message_ingress_policy_coverage: Number(transportStats.non_message_ingress_policy_coverage || 0),
            ...transportEvidence,
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: false,
          },
        });
        return;
      }

      const ingressEvent = connectorIngressEventFromBody({
        connector,
        target_id,
        body: obj,
        replay_key,
        fallbackIngressType: 'webhook',
      });
      const payloadAuthz = evaluateConnectorIngressWithAudit({
        db,
        event: {
          ...ingressEvent,
          source_id: safeString(ingressEvent.source_id || webhookSourceId),
          signature_valid: obj.signature_valid !== false,
          replay_detected: false,
        },
        policy: connectorIngressPolicy,
        client: {
          ...authzClient,
          user_id: safeString(ingressEvent.sender_id) || null,
        },
        request_id: ingressRequestId,
      });
      if (payloadAuthz.allowed && payloadAuthz.audit_logged === false) {
        const denyCode = 'audit_write_failed';
        const payloadAuditFailStats = recordIngressScan({
          ingress_type: safeString(ingressEvent.ingress_type || 'webhook'),
          policy_checked: true,
          allowed: false,
          blocked: true,
          deny_code: denyCode,
          audit_logged: true,
        });
        const payloadAuditFailEvidence = gateEvidenceFields(payloadAuditFailStats);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            policy_checked: payloadAuthz.policy_checked !== false,
            blocked_event_miss_rate: Number(payloadAuditFailStats.blocked_event_miss_rate || 0),
            non_message_ingress_policy_coverage: Number(payloadAuditFailStats.non_message_ingress_policy_coverage || 0),
            ...payloadAuditFailEvidence,
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, statusForDenyCode(denyCode), {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      const payloadStats = recordIngressScan(payloadAuthz);
      if (!payloadAuthz.allowed) {
        const payloadEvidence = gateEvidenceFields(payloadStats);
        const denyCode = safeString(payloadAuthz.deny_code || 'authz_denied') || 'authz_denied';
        const denyStatus = statusForDenyCode(denyCode);
        noteUnauthorizedDeny(connectionKey, denyCode, denyStatus);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            policy_checked: payloadAuthz.policy_checked !== false,
            blocked_event_miss_rate: Number(payloadStats.blocked_event_miss_rate || 0),
            non_message_ingress_policy_coverage: Number(payloadStats.non_message_ingress_policy_coverage || 0),
            ...payloadEvidence,
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: false,
          },
        });
        return;
      }
      const deliveryIdempotencyKey = safeString(
        req?.headers?.['x-idempotency-key']
        || obj.idempotency_key
        || ingressEvent.message_id
        || replay_key
      );
      const orderingBegin = callConnectorOrderingBegin({
        connector,
        target_id,
        event_id: safeString(ingressEvent.message_id || replay_key),
        event_sequence: Number(ingressEvent.event_sequence || 0),
      });
      if (!orderingBegin?.ok) {
        const denyCode = safeString(orderingBegin?.deny_code || 'ordering_guard_error');
        const denyStatus = statusForOrderingDenyCode(denyCode);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: denyStatus >= 500 ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            event_id: safeString(ingressEvent.message_id || replay_key),
            event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
            ordering_retry_after_ms: Math.max(0, Number(orderingBegin?.retry_after_ms || 0)),
            peer_ip: peerIp || '',
          },
        });
        if (denyStatus === 429) {
          res.writeHead(429, {
            'content-type': 'application/json; charset=utf-8',
            'retry-after': String(rateLimitFromRetryMs(orderingBegin?.retry_after_ms)),
          });
          res.end(JSON.stringify({
            ok: false,
            error: {
              code: denyCode,
              message: denyCode,
              retryable: true,
            },
          }));
          return;
        }
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: denyStatus >= 500,
          },
        });
        return;
      }
      const receiptPrepare = callConnectorReceiptPrepare({
        connector,
        target_id,
        idempotency_key: deliveryIdempotencyKey,
        event_id: safeString(ingressEvent.message_id || replay_key),
        event_sequence: Number(ingressEvent.event_sequence || 0),
      });
      if (!receiptPrepare?.ok) {
        callConnectorOrderingComplete({
          connector,
          target_id,
          lock_token: safeString(orderingBegin.lock_token || ''),
          success: false,
          event_id: safeString(ingressEvent.message_id || replay_key),
          event_sequence: Number(ingressEvent.event_sequence || 0),
        });
        const denyCode = safeString(receiptPrepare?.deny_code || 'receipt_guard_error');
        const denyStatus = statusForReceiptDenyCode(denyCode);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: denyStatus >= 500 ? 'error' : 'warn',
          ok: false,
          deny_code: 'connector_delivery_receipt_error',
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            delivery_idempotency_key: deliveryIdempotencyKey,
            receipt_deny_code: denyCode,
            event_id: safeString(ingressEvent.message_id || replay_key),
            event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: 'connector_delivery_receipt_error',
            message: 'connector_delivery_receipt_error',
            retryable: denyStatus >= 500,
          },
        });
        return;
      }
      const runtimeSignal = callConnectorRuntimeSignal({
        connector,
        target_id,
        signal: 'polling_ok',
      });
      if (!runtimeSignal?.ok) {
        const receiptUndo = callConnectorReceiptUndo({
          connector,
          target_id,
          idempotency_key: deliveryIdempotencyKey,
          reason: 'runtime_orchestrator_error',
          compensate_after_ms: 0,
        });
        callConnectorOrderingComplete({
          connector,
          target_id,
          lock_token: safeString(orderingBegin.lock_token || ''),
          success: false,
          event_id: safeString(ingressEvent.message_id || replay_key),
          event_sequence: Number(ingressEvent.event_sequence || 0),
        });
        const denyCode = 'connector_runtime_orchestrator_error';
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: String(runtimeSignal?.deny_code || denyCode),
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            delivery_idempotency_key: deliveryIdempotencyKey,
            receipt_undo_deny_code: safeString(receiptUndo?.deny_code || ''),
            receipt_delivery_state: safeString(receiptUndo?.delivery_state || receiptPrepare?.delivery_state || ''),
            orchestrator_deny_code: safeString(runtimeSignal?.deny_code || ''),
            orchestrator_state: safeString(runtimeSignal?.state || ''),
            orchestrator_retry_after_ms: Math.max(0, Number(runtimeSignal?.retry_after_ms || 0)),
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, 503, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      const orderingComplete = callConnectorOrderingComplete({
        connector,
        target_id,
        lock_token: safeString(orderingBegin.lock_token || ''),
        success: true,
        event_id: safeString(ingressEvent.message_id || replay_key),
        event_sequence: Number(ingressEvent.event_sequence || 0),
      });
      if (!orderingComplete?.ok) {
        const receiptUndo = callConnectorReceiptUndo({
          connector,
          target_id,
          idempotency_key: deliveryIdempotencyKey,
          reason: 'ordering_guard_error',
          compensate_after_ms: 0,
        });
        const denyCode = 'connector_ordering_guard_error';
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: String(orderingComplete?.deny_code || denyCode),
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            delivery_idempotency_key: deliveryIdempotencyKey,
            receipt_undo_deny_code: safeString(receiptUndo?.deny_code || ''),
            receipt_delivery_state: safeString(receiptUndo?.delivery_state || receiptPrepare?.delivery_state || ''),
            ordering_deny_code: safeString(orderingComplete?.deny_code || ''),
            event_id: safeString(ingressEvent.message_id || replay_key),
            event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, 503, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      const receiptCommit = callConnectorReceiptCommit({
        connector,
        target_id,
        idempotency_key: deliveryIdempotencyKey,
        provider_receipt: safeString(obj.provider_receipt || obj.delivery_receipt || ''),
        event_id: safeString(ingressEvent.message_id || replay_key),
        event_sequence: Number(ingressEvent.event_sequence || 0),
      });
      if (!receiptCommit?.ok) {
        const receiptUndo = callConnectorReceiptUndo({
          connector,
          target_id,
          idempotency_key: deliveryIdempotencyKey,
          reason: 'receipt_commit_rejected',
          compensate_after_ms: 0,
        });
        const denyCode = safeString(receiptCommit?.deny_code || 'receipt_guard_error');
        const denyStatus = statusForReceiptDenyCode(denyCode);
        appendIngressAudit({
          event_type: 'connector.webhook.rejected',
          severity: denyStatus >= 500 ? 'error' : 'warn',
          ok: false,
          deny_code: 'connector_delivery_receipt_error',
          error_message: denyCode,
          ext: {
            op: 'connector_webhook_ingress',
            connector,
            target_id,
            source_key: safeString(limit?.source_key || sourceKey),
            connection_key: safeString(connectionKey),
            source_id: safeString(ingressEvent.source_id || webhookSourceId),
            ingress_type: safeString(ingressEvent.ingress_type || ''),
            channel_scope: safeString(ingressEvent.channel_scope || ''),
            sender_id: safeString(ingressEvent.sender_id || ''),
            replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
            replay_key_present: !!replay_key,
            signature_present: !!signature,
            delivery_idempotency_key: deliveryIdempotencyKey,
            receipt_commit_deny_code: denyCode,
            receipt_undo_deny_code: safeString(receiptUndo?.deny_code || ''),
            receipt_delivery_state: safeString(receiptUndo?.delivery_state || ''),
            event_id: safeString(ingressEvent.message_id || replay_key),
            event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
            peer_ip: peerIp || '',
          },
        });
        jsonResponse(res, denyStatus, {
          ok: false,
          error: {
            code: 'connector_delivery_receipt_error',
            message: 'connector_delivery_receipt_error',
            retryable: denyStatus >= 500,
          },
        });
        return;
      }
      const payloadEvidence = gateEvidenceFields(payloadStats);

      appendIngressAudit({
        event_type: 'connector.webhook.received',
        severity: 'info',
        ok: true,
        deny_code: '',
        error_message: '',
        ext: {
          op: 'connector_webhook_ingress',
          connector,
          target_id,
          source_key: safeString(limit?.source_key || sourceKey),
          replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
          signature_present: !!signature,
          source_id: safeString(ingressEvent.source_id || webhookSourceId),
          delivery_idempotency_key: deliveryIdempotencyKey,
          delivery_state: safeString(receiptCommit.delivery_state || ''),
          receipt_prepare_idempotent: receiptPrepare?.idempotent === true,
          receipt_commit_idempotent: receiptCommit?.idempotent === true,
          receipt_compensation_due_at_ms: Math.max(0, Number(receiptCommit.compensation_due_at_ms || receiptPrepare.compensation_due_at_ms || 0)),
          ingress_type: safeString(ingressEvent.ingress_type || ''),
          channel_scope: safeString(ingressEvent.channel_scope || ''),
          sender_id: safeString(ingressEvent.sender_id || ''),
          runtime_state: safeString(runtimeSignal.state || ''),
          runtime_action: safeString(runtimeSignal.action || ''),
          runtime_retry_after_ms: Math.max(0, Number(runtimeSignal.retry_after_ms || 0)),
          ordering_last_sequence: Math.max(0, Number(orderingComplete.last_sequence || 0)),
          ordering_seen_event_count: Math.max(0, Number(orderingComplete.seen_event_count || 0)),
          policy_checked: payloadAuthz.policy_checked !== false,
          blocked_event_miss_rate: Number(payloadStats.blocked_event_miss_rate || 0),
          non_message_ingress_policy_coverage: Number(payloadStats.non_message_ingress_policy_coverage || 0),
          ...payloadEvidence,
          body_size_hint_bytes: Buffer.byteLength(JSON.stringify(obj || {}), 'utf8'),
          peer_ip: peerIp || '',
        },
      });
      appendConnectorIngressReceiptSnapshot(resolveRuntimeBaseDir(), {
        receipt_id: `connector_ingress_${crypto.createHash('sha256')
          .update([
            safeString(target_id),
            safeString(connector),
            safeString(replayClaim.replay_key_hash || deliveryIdempotencyKey || ingressRequestId),
          ].join('|'))
          .digest('hex')
          .slice(0, 24)}`,
        request_id: ingressRequestId,
        project_id: safeString(authzClient.project_id || target_id),
        connector,
        target_id,
        ingress_type: safeString(ingressEvent.ingress_type || 'webhook'),
        channel_scope: safeString(ingressEvent.channel_scope || ''),
        source_id: safeString(ingressEvent.source_id || webhookSourceId),
        message_id: safeString(ingressEvent.message_id || replay_key || ingressRequestId),
        dedupe_key: safeString(replayClaim.replay_key_hash || deliveryIdempotencyKey || ingressRequestId),
        received_at_ms: nowMs(),
        event_sequence: Math.max(0, Number(ingressEvent.event_sequence || 0)),
        delivery_state: safeString(receiptCommit.delivery_state || ''),
        runtime_state: safeString(runtimeSignal.state || ''),
      });

      jsonResponse(res, 202, {
        ok: true,
        accepted: true,
        connector,
        target_id,
        ingress_type: safeString(ingressEvent.ingress_type || ''),
        replay_key_hash: safeString(replayClaim.replay_key_hash || ''),
        delivery_state: safeString(receiptCommit.delivery_state || ''),
        runtime_state: safeString(runtimeSignal.state || ''),
        runtime_action: safeString(runtimeSignal.action || ''),
        ordering_last_sequence: Math.max(0, Number(orderingComplete.last_sequence || 0)),
        received_at_ms: nowMs(),
      });
      return;
    }

    // -------------------- Unauthenticated pairing --------------------

    if (method === 'POST' && pathname === '/pairing/requests') {
      const sourceKey = sourceKeyFromReq(req, q, peerIp);
      const limit = callPreauthGuard(sourceKey);
      if (!limit?.ok) {
        const denyCode = safeString(limit?.deny_code) || 'preauth_fail_closed';
        appendIngressAudit({
          event_type: 'pairing.preauth.rejected',
          severity: denyCode === 'preauth_fail_closed' ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'pairing_request_ingress',
            source_key: safeString(limit?.source_key || sourceKey),
            peer_ip: peerIp || '',
            retry_after_ms: Math.max(0, Number(limit?.retry_after_ms || 0)),
          },
        });
        if (denyCode === 'preauth_fail_closed') {
          jsonResponse(res, 503, { ok: false, error: { code: denyCode, message: denyCode, retryable: true } });
          return;
        }
        res.writeHead(429, {
          'content-type': 'application/json; charset=utf-8',
          'retry-after': String(rateLimitFromRetryMs(limit?.retry_after_ms)),
        });
        res.end(JSON.stringify({
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        }));
        return;
      }

      const body = await readBodyJson(req, { maxBytes: preauthBodyMaxBytes });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};

      const app_id = safeString(obj.app_id);
      if (!app_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'missing_app_id', message: 'missing_app_id', retryable: false } });
        return;
      }

      const firstPairSameLanGate = evaluateFirstPairSameLanRequirement({
        peer_ip: peerIp,
        forwarded_for: firstForwardedForIp(req),
        env: process.env,
      });
      if (!firstPairSameLanGate.ok) {
        const denyCode = 'first_pair_requires_same_lan';
        appendIngressAudit({
          event_type: 'pairing.same_lan.rejected',
          severity: 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'pairing_request_ingress',
            app_id,
            peer_ip: peerIp || '',
            effective_peer_ip: safeString(firstPairSameLanGate.effective_peer_ip || ''),
            forwarded_for: firstForwardedForIp(req),
            allowed_cidrs: firstPairSameLanGate.allowed_cidrs,
          },
        });
        jsonResponse(res, 403, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: false,
            peer_ip: safeString(firstPairSameLanGate.effective_peer_ip || peerIp || ''),
            allowed_cidrs: firstPairSameLanGate.allowed_cidrs,
            hint: 'First pairing must be requested from the same Wi-Fi or local LAN as the Hub.',
          },
        });
        return;
      }

      const inviteTokenRequired = shouldRequireInviteTokenForPairingRequest({
        peer_ip: peerIp,
        forwarded_for: firstForwardedForIp(req),
        env: process.env,
      });
      if (inviteTokenRequired) {
        const inviteToken = safeString(
          obj.invite_token
          || req?.headers?.['x-hub-invite-token']
          || req?.headers?.['x-invite-token']
          || q.invite_token
        );
        const inviteRecord = loadInviteTokenRecord(runtimeBaseDir);
        const denyCode = !inviteRecord || !inviteToken
          ? 'invite_token_required'
          : (safeTimingEqual(inviteRecord.token_secret, inviteToken) ? '' : 'invite_token_invalid');
        if (denyCode) {
          appendIngressAudit({
            event_type: 'pairing.invite.rejected',
            severity: 'warn',
            ok: false,
            deny_code: denyCode,
            error_message: denyCode,
            ext: {
              op: 'pairing_request_ingress',
              invite_token_present: !!inviteToken,
              invite_token_id: safeString(inviteRecord?.token_id || ''),
              peer_ip: peerIp || '',
              forwarded_for: firstForwardedForIp(req),
            },
          });
          jsonResponse(res, 403, { ok: false, error: { code: denyCode, message: denyCode, retryable: false } });
          return;
        }
      }

      // Pairing secret (client-generated). This is used to prevent token leakage via request-id guessing.
      const pairing_secret = safeString(obj.pairing_secret);
      if (!pairing_secret || pairing_secret.length < 12) {
        jsonResponse(res, 400, { ok: false, error: { code: 'missing_pairing_secret', message: 'missing_pairing_secret', retryable: false } });
        return;
      }

      const created_at_ms = Number(obj.created_at_ms || 0) || nowMs();
      const request_id = obj.request_id ? safeString(obj.request_id) : '';
      const claimed_device_id = obj.device_id ? safeString(obj.device_id) : '';
      const user_id = obj.user_id ? safeString(obj.user_id) : '';
      const device_name = obj.device_name ? safeString(obj.device_name) : '';
      const device_info = obj.device_info && typeof obj.device_info === 'object' ? obj.device_info : null;
      const tls_csr_pem_raw = obj.tls_csr_pem ? safeString(obj.tls_csr_pem) : '';
      const tls_csr_b64 = obj.tls_csr_b64 ? safeString(obj.tls_csr_b64) : '';
      const tls_csr_pem = tls_csr_pem_raw || (tls_csr_b64 ? base64DecodeUtf8(tls_csr_b64) : '');
      const device_info2 = (() => {
        // Store TLS CSR (if present) in device_info_json so admin approval can issue a client cert.
        const cur = device_info && typeof device_info === 'object' ? { ...device_info } : {};
        if (tls_csr_pem && tls_csr_pem.includes('BEGIN CERTIFICATE REQUEST')) {
          const tls = cur.tls && typeof cur.tls === 'object' ? { ...cur.tls } : {};
          tls.csr_pem = tls_csr_pem;
          tls.csr_sha256 = sha256Hex(tls_csr_pem);
          cur.tls = tls;
        }
        return cur;
      })();
      const requested_scopes = Array.isArray(obj.requested_scopes) ? obj.requested_scopes.map((s) => safeString(s)).filter(Boolean) : [];

      let row;
      try {
        row = db.createPairingRequest({
          pairing_secret_hash: sha256Hex(pairing_secret),
          request_id: request_id || null,
          claimed_device_id: claimed_device_id || null,
          user_id: user_id || null,
          app_id,
          device_name: device_name || null,
          device_info_json: device_info2 && Object.keys(device_info2).length ? JSON.stringify(device_info2) : null,
          requested_scopes_json: requested_scopes.length ? JSON.stringify(requested_scopes) : null,
          peer_ip: peerIp || null,
          created_at_ms,
        });
      } catch (e) {
        jsonResponse(res, 500, { ok: false, error: { code: 'internal', message: 'internal', retryable: true } });
        return;
      }

      try {
        const runtimeBaseDir = resolveRuntimeBaseDir();
        pushHubNotification(runtimeBaseDir, {
          source: 'Hub',
          title: 'Pairing Request',
          body: `${device_name || claimed_device_id || 'Unknown device'} (${app_id}) requested access from ${peerIp || 'unknown ip'}`,
          dedupe_key: `pairing_request:${String(row?.pairing_request_id || '')}`,
          action_url: null,
          unread: true,
        });
      } catch {
        // ignore
      }

      jsonResponse(res, 201, {
        ok: true,
        pairing_request_id: String(row?.pairing_request_id || ''),
        status: String(row?.status || 'pending'),
        created_at_ms: Number(row?.created_at_ms || created_at_ms),
      });
      return;
    }

    if (method === 'GET' && pathname.startsWith('/pairing/requests/')) {
      const pairing_request_id = safeString(pathname.slice('/pairing/requests/'.length));
      if (!pairing_request_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'bad_request', message: 'bad_request', retryable: false } });
        return;
      }
      const secret = safeString(req?.headers?.['x-pairing-secret'] ?? q.secret);
      if (!secret) {
        jsonResponse(res, 401, { ok: false, error: { code: 'unauthenticated', message: 'missing_pairing_secret', retryable: false } });
        return;
      }
      const row = db.getPairingRequest(pairing_request_id);
      if (!row) {
        // Hide existence to reduce enumeration.
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }
      const expectedHash = safeString(row.pairing_secret_hash);
      if (!expectedHash || expectedHash !== sha256Hex(secret)) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const status = safeString(row.status) || 'pending';
      const out = {
        ok: true,
        pairing_request_id,
        status,
        created_at_ms: Number(row.created_at_ms || 0) || 0,
        decided_at_ms: Number(row.decided_at_ms || 0) || 0,
        deny_reason: row.deny_reason ? String(row.deny_reason) : '',
        approved: null,
      };
      if (status === 'approved') {
        const tlsMode = tlsModeFromEnv(process.env);
        const tlsServerName = tlsMode === 'insecure' ? '' : tlsServerNameFromEnv(process.env);
        const routeMetadata = buildPairingRouteMetadata({
          runtimeBaseDir,
          hubIdentity,
          internetHostHint,
          pairingPort: port,
          grpcPort,
          tlsMode,
          tlsServerName,
        });
        out.pairing_profile_epoch = routeMetadata.pairing_profile_epoch;
        out.route_pack_version = routeMetadata.route_pack_version;
        let caps = [];
        let cidrs = [];
        try {
          caps = JSON.parse(String(row.approved_capabilities_json || '[]'));
        } catch {
          caps = [];
        }
        try {
          cidrs = JSON.parse(String(row.approved_allowed_cidrs_json || '[]'));
        } catch {
          cidrs = [];
        }
        const boundUserId = safeString(row.user_id) || safeString(row.approved_device_id);
        const approvedTrustProfile = parseApprovedTrustProfile(row.approved_trust_profile_json);
        out.approved = {
          access_key_id: safeString(row.approved_device_id),
          auth_kind: 'paired_client',
          device_id: safeString(row.approved_device_id),
          user_id: boundUserId,
          client_token: safeString(row.approved_client_token),
          capabilities: Array.isArray(caps) ? caps.map((s) => safeString(s)).filter(Boolean) : [],
          scopes: Array.isArray(caps) ? caps.map((s) => safeString(s)).filter(Boolean) : [],
          allowed_cidrs: Array.isArray(cidrs) ? cidrs.map((s) => safeString(s)).filter(Boolean) : [],
          policy_mode: normalizedPolicyMode(row.policy_mode, approvedTrustProfile ? 'new_profile' : 'legacy_grant'),
          approved_trust_profile: approvedTrustProfile,
        };

        // TLS bootstrap material (optional):
        // - Provide the Hub CA cert so clients can verify the server cert.
        // - Provide the issued client cert (mTLS mode only).
        if (tlsMode !== 'insecure') {
          // Ensure CA/server cert exist if TLS is enabled.
          try {
            ensureHubTlsMaterial(runtimeBaseDir, { env: process.env });
          } catch {
            // ignore; still allow pairing to complete (client may connect in insecure mode).
          }
          const caPem = readHubCaCertPem(runtimeBaseDir, { env: process.env });
          const serverName = tlsServerNameFromEnv(process.env);
          const did = safeString(row.approved_device_id);
          const clientPem = tlsMode === 'mtls' ? readIssuedClientCertPem(runtimeBaseDir, did, { env: process.env }) : '';

          out.tls = {
            mode: tlsMode,
            server_name: serverName,
            ca_cert_b64: caPem ? base64EncodeUtf8(caPem) : '',
            client_cert_b64: clientPem ? base64EncodeUtf8(clientPem) : '',
          };
        }

        // Convenience for terminals that are bootstrapping without a full client app.
        const hostHeader = safeString(req?.headers?.host);
        const hubHostGuess = hostHeader.includes(':') ? hostHeader.split(':')[0] : hostHeader;
        if (hubHostGuess) {
          out.connect = {
            hub_host: hubHostGuess,
            hub_port: Number(grpcPort || 0) || 50051,
          };
          const serverName = tlsMode !== 'insecure' ? tlsServerName : '';
          const tlsEnv =
            tlsMode === 'insecure'
              ? ''
              : `HUB_GRPC_TLS_MODE=${shellQuoteSingle(tlsMode)}\nHUB_GRPC_TLS_SERVER_NAME=${shellQuoteSingle(serverName)}\nHUB_GRPC_TLS_CA_CERT_PATH=$HOME/.axhub/tls/ca.cert.pem\n` +
                (tlsMode === 'mtls'
                  ? `HUB_GRPC_TLS_CLIENT_CERT_PATH=$HOME/.axhub/tls/client.cert.pem\nHUB_GRPC_TLS_CLIENT_KEY_PATH=$HOME/.axhub/tls/client.key.pem\n`
                  : '');

          out.connect_env =
            `HUB_HOST=${shellQuoteSingle(hubHostGuess)}\n` +
            `HUB_PORT=${Number(grpcPort || 0) || 50051}\n` +
            `HUB_CLIENT_TOKEN=${shellQuoteSingle(row.approved_client_token)}\n` +
            `HUB_DEVICE_ID=${shellQuoteSingle(row.approved_device_id)}\n` +
            `HUB_USER_ID=${shellQuoteSingle(boundUserId)}\n` +
            tlsEnv;
        }

        // Provide install info so a brand new Terminal device can bootstrap `axhubctl`
        // without installing the full Hub app.
        const asset = loadAxhubctlAsset();
        if (asset) {
          const base = publicBaseFromReq(req, { hostFallback, portFallback: port, schemeFallback });
          const url = base ? `${base}/install/axhubctl` : '/install/axhubctl';
          const sha = asset.sha256;
          out.install = {
            axhubctl_url: url,
            axhubctl_sha256: sha,
            // Recommended: download -> verify -> chmod (avoid curl|sh).
            command_sh: [
              `AXHUBCTL_URL='${url}'`,
              `AXHUBCTL_SHA256='${sha}'`,
              'mkdir -p ~/.local/bin',
              'curl -fsSL "$AXHUBCTL_URL" -o ~/.local/bin/axhubctl',
              '(command -v shasum >/dev/null 2>&1 && echo "$AXHUBCTL_SHA256  ~/.local/bin/axhubctl" | shasum -a 256 -c -) || (command -v sha256sum >/dev/null 2>&1 && echo "$AXHUBCTL_SHA256  ~/.local/bin/axhubctl" | sha256sum -c -)',
              'chmod +x ~/.local/bin/axhubctl',
              'echo "Installed: ~/.local/bin/axhubctl (ensure ~/.local/bin is in PATH)"',
            ].join('\n'),
          };
        }
        try {
          if (!Number(row.token_claimed_at_ms || 0)) {
            db.markPairingTokenClaimed(pairing_request_id, nowMs());
          }
        } catch {
          // ignore
        }
      }
      jsonResponse(res, 200, out);
      return;
    }

    // -------------------- Admin pairing --------------------

    if (pathname === '/admin/grant-requests' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const status = safeString(q.status || 'pending').toLowerCase();
      const lim = Math.max(1, Math.min(500, positiveIntOrZero(q.limit) || 200));
      let rows = [];
      if (!status || status === 'pending') {
        try {
          rows = db.listPendingGrantRequests({
            device_id: safeString(q.device_id),
            user_id: safeString(q.user_id),
            app_id: safeString(q.app_id),
            project_id: safeString(q.project_id),
            capability: safeString(q.capability),
            limit: lim,
          });
        } catch {
          rows = [];
        }
      }

      jsonResponse(res, 200, {
        ok: true,
        updated_at_ms: nowMs(),
        requests: rows.map(toHttpPendingGrantRequest).filter(Boolean),
      });
      return;
    }

    if (pathname.startsWith('/admin/grant-requests/') && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const tail = pathname.slice('/admin/grant-requests/'.length);
      const parts = tail.split('/').filter(Boolean);
      const grant_request_id = safeString(parts[0]);
      const action = safeString(parts[1]).toLowerCase();
      if (!grant_request_id || (action !== 'approve' && action !== 'deny')) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 16 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }

      const obj = body.json || {};
      const approverId = safeString(obj.approver_id || obj.approverId || 'hub_admin_local_http') || 'hub_admin_local_http';
      const invoked = await invokeHubGrantsUnary({
        hubServices,
        req,
        token: bearerTokenFromReq(req),
        method: action === 'approve' ? 'ApproveGrant' : 'DenyGrant',
        request: action === 'approve'
          ? {
              grant_request_id,
              ttl_sec: positiveIntOrZero(obj.ttl_sec || obj.ttlSec),
              token_cap: Math.max(0, Number(obj.token_cap || obj.tokenCap || 0) || 0),
              approver_id: approverId,
              note: safeString(obj.note),
            }
          : {
              grant_request_id,
              approver_id: approverId,
              reason: safeString(obj.reason || obj.deny_reason || obj.denyReason || 'denied_via_hub_inbox') || 'denied_via_hub_inbox',
            },
      });
      if (!invoked.ok) {
        jsonResponse(res, invoked.status || 503, { ok: false, error: { code: invoked.code || 'hub_grants_request_failed', message: invoked.message || 'hub_grants_request_failed', retryable: true } });
        return;
      }

      jsonResponse(res, 200, {
        ok: true,
        grant_request_id,
        status: action === 'approve' ? 'approved' : 'denied',
        grant: invoked.response?.grant || null,
      });
      return;
    }

    if (pathname === '/admin/provider-keys/oauth/start' && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 16 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }

      const obj = body.json || {};
      const invoked = await invokeHubProviderKeysUnary({
        hubServices,
        req,
        token: bearerTokenFromReq(req),
        method: 'StartProviderOAuthLogin',
        request: {
          provider: safeString(obj.provider),
          redirect_uri: safeString(obj.redirect_uri || obj.redirectURI),
        },
      });
      if (!invoked.ok) {
        jsonResponse(res, invoked.status || 503, { ok: false, error: { code: invoked.code || 'hub_provider_keys_request_failed', message: invoked.message || 'hub_provider_keys_request_failed', retryable: true } });
        return;
      }
      const response = invoked.response || {};
      if (response.ok !== true) {
        jsonResponse(res, 400, {
          ok: false,
          error: {
            code: safeString(response.error || 'oauth_start_failed') || 'oauth_start_failed',
            message: safeString(response.error || 'oauth_start_failed') || 'oauth_start_failed',
            retryable: false,
          },
          provider: safeString(response.provider),
          status: safeString(response.status || 'error') || 'error',
        });
        return;
      }
      jsonResponse(res, 200, {
        ok: true,
        provider: safeString(response.provider),
        state: safeString(response.state),
        auth_url: safeString(response.auth_url),
        redirect_uri: safeString(response.redirect_uri),
        status: safeString(response.status || 'pending') || 'pending',
        expires_at_ms: Math.max(0, Number(response.expires_at_ms || 0)),
      });
      return;
    }

    if (pathname === '/admin/provider-keys/oauth/status' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const invoked = await invokeHubProviderKeysUnary({
        hubServices,
        req,
        token: bearerTokenFromReq(req),
        method: 'GetProviderOAuthLoginStatus',
        request: {
          state: safeString(q.state),
        },
      });
      if (!invoked.ok) {
        jsonResponse(res, invoked.status || 503, { ok: false, error: { code: invoked.code || 'hub_provider_keys_request_failed', message: invoked.message || 'hub_provider_keys_request_failed', retryable: true } });
        return;
      }
      const response = invoked.response || {};
      jsonResponse(res, 200, {
        ok: response.ok === true,
        error: safeString(response.error),
        provider: safeString(response.provider),
        state: safeString(response.state),
        status: safeString(response.status || 'unknown') || 'unknown',
        expires_at_ms: Math.max(0, Number(response.expires_at_ms || 0)),
        updated_at_ms: Math.max(0, Number(response.updated_at_ms || 0)),
        auth_url: safeString(response.auth_url),
        redirect_uri: safeString(response.redirect_uri),
        status_message: safeString(response.status_message),
        account_key: safeString(response.account_key),
        email: safeString(response.email),
        auth_file_path: safeString(response.auth_file_path),
        imported: Math.max(0, Number(response.imported || 0)),
      });
      return;
    }

    if (pathname === '/admin/provider-keys/oauth/callback' && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 32 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }

      const obj = body.json || {};
      const invoked = await invokeHubProviderKeysUnary({
        hubServices,
        req,
        token: bearerTokenFromReq(req),
        method: 'SubmitProviderOAuthCallback',
        request: {
          provider: safeString(obj.provider),
          state: safeString(obj.state),
          code: safeString(obj.code),
          redirect_url: safeString(obj.redirect_url || obj.redirectURL),
          error: safeString(obj.error),
        },
      });
      if (!invoked.ok) {
        jsonResponse(res, invoked.status || 503, { ok: false, error: { code: invoked.code || 'hub_provider_keys_request_failed', message: invoked.message || 'hub_provider_keys_request_failed', retryable: true } });
        return;
      }
      const response = invoked.response || {};
      jsonResponse(res, response.ok === true ? 200 : 400, {
        ok: response.ok === true,
        error: safeString(response.error),
        provider: safeString(response.provider),
        state: safeString(response.state),
        status: safeString(response.status || 'error') || 'error',
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-ingress/gate-snapshot' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const source = safeString(q.source || 'auto').toLowerCase();
      if (source !== 'auto' && source !== 'audit' && source !== 'scan') {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'invalid source (expected auto|audit|scan)', retryable: false } });
        return;
      }

      const scanStats = buildNonMessageIngressScanStats(ingressScanEntries);
      const scanSnapshot = buildNonMessageIngressGateSnapshot({ stats: scanStats });
      const auditRows = source === 'scan'
        ? []
        : listConnectorIngressAuditRows({
            since_ms: Math.max(0, Number(q.since_ms || 0)),
            until_ms: Math.max(0, Number(q.until_ms || 0)),
            device_id: safeString(q.device_id || ''),
            user_id: safeString(q.user_id || ''),
            project_id: safeString(q.project_id || ''),
            request_id: safeString(q.request_id || ''),
            limit: parseAuditRowsLimit(q.limit),
          });
      const auditSnapshot = buildNonMessageIngressGateSnapshotFromAuditRows(auditRows);
      const sourceUsed = (() => {
        if (source === 'audit' || source === 'scan') return source;
        return auditRows.length > 0 ? 'audit' : 'scan';
      })();
      const snapshot = sourceUsed === 'audit' ? auditSnapshot : scanSnapshot;
      jsonResponse(res, 200, {
        ok: true,
        source_used: sourceUsed,
        data_ready: sourceUsed === 'scan' ? ingressScanEntries.length > 0 : auditRows.length > 0,
        audit_row_count: auditRows.length,
        scan_entry_count: ingressScanEntries.length,
        snapshot,
        snapshot_scan: scanSnapshot,
        snapshot_audit: auditSnapshot,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-runtime/snapshot' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const snapshot = safeGuardSnapshot(internalConnectorRuntimeOrchestrator, {
        targets: 0,
        signals: 0,
        denied: 0,
        fail_closed: 0,
        state_corrupt_incidents: 0,
        fallback_entries: 0,
        reconnect_attempts: 0,
        connector_reconnect_ms_p95: 0,
        reconnect_sample_count: 0,
        by_state: {
          idle: 0,
          connecting: 0,
          ready: 0,
          degraded_polling: 0,
          recovering: 0,
        },
      });
      jsonResponse(res, 200, {
        ok: true,
        snapshot,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-runtime/target' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const connector = safeString(q.connector).toLowerCase();
      const target_id = safeString(q.target_id);
      if (!connector || !target_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector or target_id', retryable: false } });
        return;
      }
      let target = null;
      try {
        target = internalConnectorRuntimeOrchestrator.getTarget({
          connector,
          target_id,
        });
      } catch {
        target = null;
      }
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        target: target || null,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-runtime/signal' && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};
      const connector = safeString(obj.connector).toLowerCase();
      const target_id = safeString(obj.target_id);
      const signal = safeString(obj.signal);
      const error_code = safeString(obj.error_code || '');
      const nowOverride = Math.max(0, Number(obj.now_ms || 0));
      if (!connector || !target_id || !signal) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector/target_id/signal', retryable: false } });
        return;
      }

      const out = callConnectorRuntimeSignal({
        connector,
        target_id,
        signal,
        error_code,
        now_ms: nowOverride > 0 ? nowOverride : undefined,
      });
      if (!out?.ok) {
        const denyCode = safeString(out?.deny_code || 'state_corrupt');
        const statusCode = denyCode === 'invalid_request'
          ? 400
          : (denyCode === 'state_corrupt' ? 409 : 503);
        appendIngressAudit({
          event_type: 'connector.runtime.signal.rejected',
          severity: statusCode >= 500 ? 'error' : 'warn',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_runtime_signal',
            connector,
            target_id,
            signal,
            error_code,
            now_ms: nowOverride > 0 ? nowOverride : 0,
            state: safeString(out.state || ''),
            retry_after_ms: Math.max(0, Number(out.retry_after_ms || 0)),
          },
        });
        jsonResponse(res, statusCode, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: statusCode >= 500,
          },
          state: safeString(out.state || ''),
          retry_after_ms: Math.max(0, Number(out.retry_after_ms || 0)),
        });
        return;
      }

      appendIngressAudit({
        event_type: 'connector.runtime.signal.accepted',
        severity: 'info',
        ok: true,
        deny_code: '',
        error_message: '',
        ext: {
          op: 'connector_runtime_signal',
          connector,
          target_id,
          signal,
          error_code,
          now_ms: nowOverride > 0 ? nowOverride : 0,
          state: safeString(out.state || ''),
          action: safeString(out.action || ''),
          retry_after_ms: Math.max(0, Number(out.retry_after_ms || 0)),
        },
      });
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        signal,
        state: safeString(out.state || ''),
        action: safeString(out.action || ''),
        retry_after_ms: Math.max(0, Number(out.retry_after_ms || 0)),
        next_reconnect_at_ms: Math.max(0, Number(out.next_reconnect_at_ms || 0)),
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-ordering/snapshot' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const snapshot = safeGuardSnapshot(internalConnectorTargetOrderingGuard, {
        targets: 0,
        in_flight_targets: 0,
        begin_total: 0,
        begin_rejected: 0,
        complete_total: 0,
        complete_rejected: 0,
        accepted: 0,
        lock_conflict_count: 0,
        out_of_order_reject_count: 0,
        duplicate_reject_count: 0,
        state_corrupt_incidents: 0,
        fail_closed: 0,
      });
      jsonResponse(res, 200, {
        ok: true,
        snapshot,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-ordering/target' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const connector = safeString(q.connector).toLowerCase();
      const target_id = safeString(q.target_id);
      if (!connector || !target_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector or target_id', retryable: false } });
        return;
      }
      let target = null;
      try {
        target = internalConnectorTargetOrderingGuard.getTarget({
          connector,
          target_id,
        });
      } catch {
        target = null;
      }
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        target: target || null,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-receipt/snapshot' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const snapshot = safeGuardSnapshot(internalConnectorDeliveryReceiptCompensator, {
        entries: 0,
        targets: 0,
        prepare_total: 0,
        prepare_rejected: 0,
        commit_total: 0,
        commit_rejected: 0,
        undo_total: 0,
        undo_rejected: 0,
        timeout_undo_promoted: 0,
        compensation_runs: 0,
        compensation_rejected: 0,
        compensated_total: 0,
        compensation_failures: 0,
        overflow_denied: 0,
        state_corrupt_incidents: 0,
        fail_closed: 0,
        compensation_pending_count: 0,
        by_state: {
          prepared: 0,
          committed: 0,
          undo_pending: 0,
          compensated: 0,
        },
      });
      jsonResponse(res, 200, {
        ok: true,
        snapshot,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-receipt/target' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const connector = safeString(q.connector).toLowerCase();
      const target_id = safeString(q.target_id);
      if (!connector || !target_id) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector or target_id', retryable: false } });
        return;
      }
      let target = null;
      try {
        target = internalConnectorDeliveryReceiptCompensator.getTarget({
          connector,
          target_id,
          limit: Math.max(1, Number(q.limit || 50)),
        });
      } catch {
        target = null;
      }
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        target: target || null,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-receipt/item' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const connector = safeString(q.connector).toLowerCase();
      const target_id = safeString(q.target_id);
      const idempotency_key = safeString(q.idempotency_key);
      if (!connector || !target_id || !idempotency_key) {
        jsonResponse(res, 400, { ok: false, error: { code: 'invalid_request', message: 'missing connector/target_id/idempotency_key', retryable: false } });
        return;
      }
      let receipt = null;
      try {
        receipt = internalConnectorDeliveryReceiptCompensator.getReceipt({
          connector,
          target_id,
          idempotency_key,
        });
      } catch {
        receipt = null;
      }
      jsonResponse(res, 200, {
        ok: true,
        connector,
        target_id,
        idempotency_key,
        receipt: receipt || null,
      });
      return;
    }

    if (pathname === '/admin/pairing/connector-receipt/compensate' && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};
      const nowOverride = Math.max(0, Number(obj.now_ms || 0));
      const maxJobs = Math.max(1, Number(obj.max_jobs || 0) || 0);
      const out = callConnectorReceiptCompensationTick({
        now_ms: nowOverride > 0 ? nowOverride : undefined,
        max_jobs: maxJobs > 0 ? maxJobs : undefined,
      });
      if (!out?.ok) {
        const denyCode = safeString(out?.deny_code || 'compensation_worker_error');
        appendIngressAudit({
          event_type: 'connector.receipt.compensation.rejected',
          severity: 'error',
          ok: false,
          deny_code: denyCode,
          error_message: denyCode,
          ext: {
            op: 'connector_receipt_compensate',
            now_ms: nowOverride > 0 ? nowOverride : 0,
            max_jobs: maxJobs > 0 ? maxJobs : 0,
          },
        });
        jsonResponse(res, 503, {
          ok: false,
          error: {
            code: denyCode,
            message: denyCode,
            retryable: true,
          },
        });
        return;
      }
      appendIngressAudit({
        event_type: 'connector.receipt.compensation.accepted',
        severity: 'info',
        ok: true,
        deny_code: '',
        error_message: '',
        ext: {
          op: 'connector_receipt_compensate',
          now_ms: nowOverride > 0 ? nowOverride : 0,
          max_jobs: maxJobs > 0 ? maxJobs : 0,
          promoted_timeout_undo: Math.max(0, Number(out.promoted_timeout_undo || 0)),
          scanned_due: Math.max(0, Number(out.scanned_due || 0)),
          processed: Math.max(0, Number(out.processed || 0)),
          compensated: Math.max(0, Number(out.compensated || 0)),
          failed: Math.max(0, Number(out.failed || 0)),
          pending_compensation: Math.max(0, Number(out.pending_compensation || 0)),
        },
      });
      jsonResponse(res, 200, {
        ok: true,
        promoted_timeout_undo: Math.max(0, Number(out.promoted_timeout_undo || 0)),
        scanned_due: Math.max(0, Number(out.scanned_due || 0)),
        processed: Math.max(0, Number(out.processed || 0)),
        compensated: Math.max(0, Number(out.compensated || 0)),
        failed: Math.max(0, Number(out.failed || 0)),
        pending_compensation: Math.max(0, Number(out.pending_compensation || 0)),
      });
      return;
    }

    if (pathname === '/admin/operator-channels/onboarding/tickets' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const provider = safeString(q.provider);
      const status = safeString(q.status);
      const limit = Math.max(1, Math.min(200, Number(q.limit || 100) || 100));
      const rows = listChannelOnboardingDiscoveryTickets(db, {
        provider,
        status,
        limit,
      });
      jsonResponse(res, 200, {
        ok: true,
        tickets: rows.map((row) => {
          const ticketId = safeString(row?.ticket_id);
          const latestDecision = ticketId
            ? getLatestChannelOnboardingApprovalDecisionByTicketId(db, { ticket_id: ticketId })
            : null;
          const revocation = ticketId
            ? getChannelOnboardingAutoBindRevocationByTicketId(db, { ticket_id: ticketId })
            : null;
          return toHttpChannelOnboardingTicket(row, { latestDecision, revocation });
        }).filter(Boolean),
      });
      return;
    }

    if (pathname === '/admin/operator-channels/readiness' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      jsonResponse(res, 200, {
        ok: true,
        providers: listChannelOnboardingDeliveryReadiness({
          env: process.env,
        }).map((item) => toHttpChannelOnboardingDeliveryReadiness(item)).filter(Boolean),
      });
      return;
    }

    if (pathname === '/admin/operator-channels/runtime-status' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const snapshot = loadChannelRuntimeStatusSnapshot(resolveRuntimeBaseDir());
      jsonResponse(res, 200, {
        ok: true,
        schema_version: safeString(snapshot.schema_version),
        updated_at_ms: Math.max(0, Number(snapshot.updated_at_ms || 0)),
        providers: Array.isArray(snapshot.providers)
          ? snapshot.providers.map((item) => toHttpChannelProviderRuntimeStatus(item)).filter(Boolean)
          : [],
      });
      return;
    }

    if (pathname === '/admin/operator-channels/live-test/evidence' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const provider = safeString(q.provider).toLowerCase();
      if (!provider) {
        jsonResponse(res, 400, {
          ok: false,
          error: {
            code: 'provider_required',
            message: 'provider_required',
            retryable: false,
          },
        });
        return;
      }

      const ticket_id = safeString(q.ticket_id || q.ticketId);
      let ticketDetail = null;
      if (ticket_id) {
        const ticket = getChannelOnboardingDiscoveryTicketById(db, { ticket_id });
        if (!ticket) {
          jsonResponse(res, 404, {
            ok: false,
            error: {
              code: 'ticket_not_found',
              message: 'ticket_not_found',
              retryable: false,
            },
          });
          return;
        }
        const latestDecision = getLatestChannelOnboardingApprovalDecisionByTicketId(db, { ticket_id });
        const automationState = getChannelOnboardingAutomationState(db, { ticket_id });
        const revocation = getChannelOnboardingAutoBindRevocationByTicketId(db, { ticket_id });
        ticketDetail = {
          ticket: toHttpChannelOnboardingTicket(ticket, { latestDecision, revocation }),
          latest_decision: toHttpChannelOnboardingDecision(latestDecision),
          revocation: toHttpChannelOnboardingRevocation(revocation),
          automation_state: toHttpChannelOnboardingAutomationState(automationState),
        };
      }

      const evidenceRefs = urlObj.searchParams.getAll('evidence_ref')
        .map((value) => safeString(value))
        .filter(Boolean);
      const readinessRows = listChannelOnboardingDeliveryReadiness({
        env: process.env,
      }).map((item) => toHttpChannelOnboardingDeliveryReadiness(item)).filter(Boolean);
      const runtimeSnapshot = loadChannelRuntimeStatusSnapshot(resolveRuntimeBaseDir());
      const runtimeRows = Array.isArray(runtimeSnapshot.providers)
        ? runtimeSnapshot.providers.map((item) => toHttpChannelProviderRuntimeStatus(item)).filter(Boolean)
        : [];

      let report = null;
      try {
        report = buildHttpOperatorChannelLiveTestEvidenceReport({
          provider,
          verdict: safeString(q.verdict),
          summary: safeString(q.summary),
          performedAt: safeString(q.performed_at || q.performedAt),
          evidenceRefs,
          readinessRows,
          runtimeRows,
          ticketDetail,
          adminBaseUrl: publicBaseFromReq(req, {
            hostFallback: host,
            portFallback: port,
            schemeFallback: 'http',
          }),
          requiredNextStep: safeString(q.required_next_step || q.next_step),
        });
      } catch (error) {
        jsonResponse(res, 400, {
          ok: false,
          error: {
            code: 'provider_invalid',
            message: safeString(error?.message || 'provider_invalid') || 'provider_invalid',
            retryable: false,
          },
        });
        return;
      }

      jsonResponse(res, 200, {
        ok: true,
        report,
      });
      return;
    }

    if (pathname === '/admin/official-skills/doctor' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const package_sha256 = safeString(q.package_sha256).toLowerCase();
      if (!package_sha256) {
        jsonResponse(res, 400, {
          ok: false,
          error: {
            code: 'missing_package_sha256',
            message: 'missing_package_sha256',
            retryable: false,
          },
        });
        return;
      }

      const report = getSkillPackageDoctorReport(resolveRuntimeBaseDir(), {
        packageSha256: package_sha256,
        userId: safeString(q.user_id),
        projectId: safeString(q.project_id),
        surface: safeString(q.surface || 'hub_ui') || 'hub_ui',
        xtVersion: safeString(q.xt_version),
      });
      jsonResponse(res, 200, {
        ok: true,
        report,
      });
      return;
    }

    if (pathname === '/admin/official-skills/packages' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const runtimeBaseDir = resolveRuntimeBaseDir();
      const lifecycle = listOfficialSkillPackageLifecycleRows(runtimeBaseDir, {
        surface: safeString(q.surface || 'hub_ui') || 'hub_ui',
        xtVersion: safeString(q.xt_version),
        overallState: safeString(q.overall_state),
        packageState: safeString(q.package_state),
        skillId: safeString(q.skill_id),
        limit: Math.max(1, Math.min(500, Number(q.limit || 200) || 200)),
        refresh: safeString(q.refresh) !== '0',
      });
      jsonResponse(res, 200, {
        ok: true,
        schema_version: safeString(lifecycle.snapshot?.schema_version),
        updated_at_ms: Math.max(0, Number(lifecycle.snapshot?.updated_at_ms || 0)),
        totals: lifecycle.snapshot?.totals || {},
        packages: lifecycle.packages,
      });
      return;
    }

    if (pathname.startsWith('/admin/operator-channels/onboarding/tickets/') && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const ticket_id = safeString(pathname.slice('/admin/operator-channels/onboarding/tickets/'.length)).split('/')[0];
      if (!ticket_id) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }
      const ticket = getChannelOnboardingDiscoveryTicketById(db, { ticket_id });
      if (!ticket) {
        jsonResponse(res, 404, { ok: false, error: { code: 'ticket_not_found', message: 'ticket_not_found', retryable: false } });
        return;
      }
      const latestDecision = getLatestChannelOnboardingApprovalDecisionByTicketId(db, { ticket_id });
      const automationState = getChannelOnboardingAutomationState(db, { ticket_id });
      const revocation = getChannelOnboardingAutoBindRevocationByTicketId(db, { ticket_id });
      jsonResponse(res, 200, {
        ok: true,
        ticket: toHttpChannelOnboardingTicket(ticket, { latestDecision, revocation }),
        latest_decision: toHttpChannelOnboardingDecision(latestDecision),
        revocation: toHttpChannelOnboardingRevocation(revocation),
        automation_state: toHttpChannelOnboardingAutomationState(automationState),
      });
      return;
    }

    if (pathname.startsWith('/admin/operator-channels/onboarding/tickets/') && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const tail = pathname.slice('/admin/operator-channels/onboarding/tickets/'.length);
      const parts = tail.split('/').filter(Boolean);
      const ticket_id = safeString(parts[0]);
      const action = safeString(parts[1]);
      if (!ticket_id || (action !== 'review' && action !== 'retry-outbox' && action !== 'revoke')) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};
      if (action === 'retry-outbox') {
        const ticket = getChannelOnboardingDiscoveryTicketById(db, { ticket_id });
        if (!ticket) {
          jsonResponse(res, 404, {
            ok: false,
            error: {
              code: 'ticket_not_found',
              message: 'ticket_not_found',
              retryable: false,
            },
          });
          return;
        }
        const latestDecision = getLatestChannelOnboardingApprovalDecisionByTicketId(db, { ticket_id });
        const revocation = getChannelOnboardingAutoBindRevocationByTicketId(db, { ticket_id });
        const request_id = safeString(obj.request_id || `http:onboarding:${ticket_id}:${action}:${nowMs()}`);
        const retryAudit = {
          device_id: 'hub_admin_local_http',
          user_id: safeString(obj.approved_by_hub_user_id || obj.hub_user_id || obj.user_id),
          app_id: safeString(obj.approved_via || obj.app_id || 'hub_local_ui') || 'hub_local_ui',
        };
        const retried = await retryChannelOnboardingOutbox(db, {
          ticket,
          request_id,
          audit: retryAudit,
        });
        if (!retried.ok) {
          jsonResponse(res, 400, {
            ok: false,
            error: {
              code: safeString(retried.deny_code || 'channel_onboarding_outbox_retry_rejected'),
              message: safeString(retried.deny_code || 'channel_onboarding_outbox_retry_rejected'),
              retryable: false,
            },
            ticket: toHttpChannelOnboardingTicket(ticket, { latestDecision, revocation }),
            automation_state: toHttpChannelOnboardingAutomationState(retried.automation_state),
          });
          return;
        }
        jsonResponse(res, 200, {
          ok: true,
          ticket: toHttpChannelOnboardingTicket(ticket, { latestDecision, revocation }),
          delivered_count: Math.max(0, Number(retried.delivered_count || 0)),
          pending_count: Math.max(0, Number(retried.pending_count || 0)),
          automation_state: toHttpChannelOnboardingAutomationState(retried.automation_state),
        });
        return;
      }
      if (action === 'revoke') {
        const ticket = getChannelOnboardingDiscoveryTicketById(db, { ticket_id });
        if (!ticket) {
          jsonResponse(res, 404, {
            ok: false,
            error: {
              code: 'ticket_not_found',
              message: 'ticket_not_found',
              retryable: false,
            },
          });
          return;
        }
        const request_id = safeString(obj.request_id || `http:onboarding:${ticket_id}:${action}:${nowMs()}`);
        const latestDecision = getLatestChannelOnboardingApprovalDecisionByTicketId(db, { ticket_id });
        const revokeAudit = {
          device_id: 'hub_admin_local_http',
          user_id: safeString(obj.revoked_by_hub_user_id || obj.approved_by_hub_user_id || obj.user_id),
          app_id: safeString(obj.revoked_via || obj.approved_via || obj.app_id || 'hub_local_ui') || 'hub_local_ui',
        };
        const revoked = revokeApprovedChannelOnboardingAutoBind(db, {
          ticket,
          decision: latestDecision || {},
          revocation: obj,
          request_id,
          audit: revokeAudit,
        });
        if (!revoked.ok) {
          jsonResponse(res, 400, {
            ok: false,
            error: {
              code: safeString(revoked.deny_code || 'channel_onboarding_revoke_rejected'),
              message: safeString(revoked.deny_code || 'channel_onboarding_revoke_rejected'),
              retryable: false,
            },
            ticket: toHttpChannelOnboardingTicket(ticket, {
              latestDecision,
              revocation: revoked.revocation,
            }),
            latest_decision: toHttpChannelOnboardingDecision(latestDecision),
            revocation: toHttpChannelOnboardingRevocation(revoked.revocation),
            automation_state: toHttpChannelOnboardingAutomationState(
              getChannelOnboardingAutomationState(db, { ticket_id })
            ),
          });
          return;
        }
        jsonResponse(res, 200, {
          ok: true,
          ticket: toHttpChannelOnboardingTicket(ticket, {
            latestDecision,
            revocation: revoked.revocation,
          }),
          latest_decision: toHttpChannelOnboardingDecision(latestDecision),
          revocation: toHttpChannelOnboardingRevocation(revoked.revocation),
          automation_state: toHttpChannelOnboardingAutomationState(
            getChannelOnboardingAutomationState(db, { ticket_id })
          ),
        });
        return;
      }
      const request_id = safeString(obj.request_id || `http:onboarding:${ticket_id}:${action}:${nowMs()}`);
      const reviewAudit = {
        device_id: 'hub_admin_local_http',
        user_id: safeString(obj.approved_by_hub_user_id),
        app_id: safeString(obj.approved_via || 'hub_local_ui') || 'hub_local_ui',
      };
      const out = reviewChannelOnboardingDiscoveryTicket(db, {
        ticket_id,
        decision: obj,
        request_id,
        audit: reviewAudit,
      });
      if (!out.ok) {
        jsonResponse(res, 400, {
          ok: false,
          error: {
            code: safeString(out.deny_code || 'channel_onboarding_review_rejected') || 'channel_onboarding_review_rejected',
            message: safeString(out.deny_code || 'channel_onboarding_review_rejected') || 'channel_onboarding_review_rejected',
            retryable: false,
          },
          ticket: toHttpChannelOnboardingTicket(out.ticket, {
            latestDecision: out.decision,
            revocation: null,
          }),
          decision: toHttpChannelOnboardingDecision(out.decision),
        });
        return;
      }
      let automation = null;
      let outbox_flush_scheduled = false;
      if (safeString(out.decision?.decision).toLowerCase() === 'approve') {
        try {
          const executed = runApprovedChannelOnboardingAutomation(db, {
            ticket: out.ticket,
            decision: out.decision,
            auto_bind_receipt: out.auto_bind_receipt,
            request_id,
            runtimeBaseDir: resolveRuntimeBaseDir(),
            audit: reviewAudit,
          });
          automation = {
            ok: executed.ok !== false,
            deny_code: safeString(executed.deny_code),
            ack_outbox_item_id: safeString(executed.ack_item?.item_id),
            first_smoke_receipt_id: safeString(executed.receipt?.receipt_id),
            first_smoke_outbox_item_id: safeString(executed.smoke_item?.item_id),
          };
          if (executed.ok !== false && safeString(out.ticket?.ticket_id)) {
            outbox_flush_scheduled = true;
            Promise.resolve()
              .then(() => flushChannelOutboxForTicket(db, {
                ticket_id: safeString(out.ticket?.ticket_id),
                request_id: `${request_id}:outbox_flush`,
                audit: reviewAudit,
              }))
              .catch(() => {
                // Delivery is best-effort and must not affect the approval result.
              });
          }
        } catch (error) {
          automation = {
            ok: false,
            deny_code: safeString(error?.message || 'channel_onboarding_automation_failed') || 'channel_onboarding_automation_failed',
            ack_outbox_item_id: '',
            first_smoke_receipt_id: '',
            first_smoke_outbox_item_id: '',
          };
        }
      }
      jsonResponse(res, 200, {
        ok: true,
        ticket: toHttpChannelOnboardingTicket(out.ticket, {
          latestDecision: out.decision,
          revocation: null,
        }),
        decision: toHttpChannelOnboardingDecision(out.decision),
        audit_logged: out.audit_logged === true,
        automation,
        automation_state: toHttpChannelOnboardingAutomationState(
          getChannelOnboardingAutomationState(db, { ticket_id: safeString(out.ticket?.ticket_id) })
        ),
        outbox_flush_scheduled,
      });
      return;
    }

    if (pathname === '/xt/clients/access-keys' && method === 'GET') {
      const xt = requireXtAccessKeyManager(req);
      if (!xt.ok) {
        jsonResponse(res, xt.status || 403, {
          ok: false,
          error: {
            code: xt.code || 'permission_denied',
            message: xt.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const wantedStatus = safeString(q.status).toLowerCase();
      const listed = buildListClientAccessKeysResponse({
        runtimeBaseDir,
        req,
        hostFallback,
        internetHostHint,
        grpcPort,
        wantedAuthKind: 'hub_access_key',
        wantedStatus,
      });
      jsonResponse(res, listed.status, listed.json);
      return;
    }

    if (pathname === '/xt/clients/access-keys' && method === 'POST') {
      const xt = requireXtAccessKeyManager(req);
      if (!xt.ok) {
        jsonResponse(res, xt.status || 403, {
          ok: false,
          error: {
            code: xt.code || 'permission_denied',
            message: xt.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, {
          ok: false,
          error: { code: body.error, message: body.error, retryable: false },
        });
        return;
      }

      const issued = issueClientAccessKey({
        runtimeBaseDir,
        req,
        hostFallback,
        internetHostHint,
        grpcPort,
        body: body.json || {},
        actor: xt.access_key_actor,
      });
      jsonResponse(res, issued.status, issued.json);
      return;
    }

    if (pathname.startsWith('/xt/clients/access-keys/') && method === 'GET') {
      const xt = requireXtAccessKeyManager(req);
      if (!xt.ok) {
        jsonResponse(res, xt.status || 403, {
          ok: false,
          error: {
            code: xt.code || 'permission_denied',
            message: xt.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const accessKeyId = safeString(pathname.slice('/xt/clients/access-keys/'.length)).split('/')[0];
      if (!accessKeyId) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const detail = buildClientAccessKeyDetailResponse({
        runtimeBaseDir,
        req,
        hostFallback,
        internetHostHint,
        grpcPort,
        accessKeyId,
        requireHubAccessKeyOnly: true,
      });
      jsonResponse(res, detail.status, detail.json);
      return;
    }

    if (pathname.startsWith('/xt/clients/access-keys/') && method === 'POST') {
      const xt = requireXtAccessKeyManager(req);
      if (!xt.ok) {
        jsonResponse(res, xt.status || 403, {
          ok: false,
          error: {
            code: xt.code || 'permission_denied',
            message: xt.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const tail = pathname.slice('/xt/clients/access-keys/'.length);
      const parts = tail.split('/').filter(Boolean);
      const accessKeyId = safeString(parts[0]);
      const action = safeString(parts[1]);
      if (!accessKeyId || (action !== 'revoke' && action !== 'rotate' && action !== 'update')) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, {
          ok: false,
          error: { code: body.error, message: body.error, retryable: false },
        });
        return;
      }

      const mutated = mutateClientAccessKey({
        runtimeBaseDir,
        req,
        hostFallback,
        internetHostHint,
        grpcPort,
        accessKeyId,
        action,
        body: body.json || {},
        actor: xt.access_key_actor,
        requireHubAccessKeyOnly: true,
      });
      jsonResponse(res, mutated.status, mutated.json);
      return;
    }

    if (pathname === '/admin/clients/access-keys' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, {
          ok: false,
          error: {
            code: admin.code || 'permission_denied',
            message: admin.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const wantedAuthKind = safeString(q.auth_kind).toLowerCase();
      const wantedStatus = safeString(q.status).toLowerCase();
      const listed = buildListClientAccessKeysResponse({
        runtimeBaseDir,
        req,
        hostFallback,
        internetHostHint,
        grpcPort,
        wantedAuthKind,
        wantedStatus,
      });
      jsonResponse(res, listed.status, listed.json);
      return;
    }

    if (pathname === '/admin/clients/access-keys' && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, {
          ok: false,
          error: {
            code: admin.code || 'permission_denied',
            message: admin.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, {
          ok: false,
          error: { code: body.error, message: body.error, retryable: false },
        });
        return;
      }
      const issued = issueClientAccessKey({
        runtimeBaseDir,
        req,
        hostFallback,
        internetHostHint,
        grpcPort,
        body: body.json || {},
        actor: {
          created_via: 'hub_local_ui',
          allow_override: true,
        },
      });
      jsonResponse(res, issued.status, issued.json);
      return;
    }

    if (pathname.startsWith('/admin/clients/access-keys/') && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, {
          ok: false,
          error: {
            code: admin.code || 'permission_denied',
            message: admin.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const accessKeyId = safeString(pathname.slice('/admin/clients/access-keys/'.length)).split('/')[0];
      if (!accessKeyId) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const detail = buildClientAccessKeyDetailResponse({
        runtimeBaseDir,
        req,
        hostFallback,
        internetHostHint,
        grpcPort,
        accessKeyId,
      });
      jsonResponse(res, detail.status, detail.json);
      return;
    }

    if (pathname.startsWith('/admin/clients/access-keys/') && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, {
          ok: false,
          error: {
            code: admin.code || 'permission_denied',
            message: admin.message || 'permission_denied',
            retryable: false,
          },
        });
        return;
      }

      const tail = pathname.slice('/admin/clients/access-keys/'.length);
      const parts = tail.split('/').filter(Boolean);
      const accessKeyId = safeString(parts[0]);
      const action = safeString(parts[1]);
      if (!accessKeyId || (action !== 'revoke' && action !== 'rotate' && action !== 'update')) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, {
          ok: false,
          error: { code: body.error, message: body.error, retryable: false },
        });
        return;
      }
      const mutated = mutateClientAccessKey({
        runtimeBaseDir,
        req,
        hostFallback,
        internetHostHint,
        grpcPort,
        accessKeyId,
        action,
        body: body.json || {},
        actor: {
          created_via: 'hub_local_ui',
          allow_override: true,
        },
      });
      jsonResponse(res, mutated.status, mutated.json);
      return;
    }

    if (pathname === '/admin/pairing/requests' && method === 'GET') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }
      const status = safeString(q.status) || 'pending';
      const lim = Number(q.limit || 200);
      let rows = [];
      try {
        rows = db.listPairingRequests({ status, limit: lim });
      } catch {
        rows = [];
      }

      const requests = rows.map((r) => {
        let info = null;
        let scopes = [];
        try {
          info = r.device_info_json ? JSON.parse(String(r.device_info_json)) : null;
        } catch {
          info = null;
        }
        try {
          scopes = r.requested_scopes_json ? JSON.parse(String(r.requested_scopes_json)) : [];
        } catch {
          scopes = [];
        }
        const approvedTrustProfile = parseApprovedTrustProfile(r.approved_trust_profile_json);
        return {
          pairing_request_id: safeString(r.pairing_request_id),
          request_id: safeString(r.request_id),
          status: safeString(r.status),
          app_id: safeString(r.app_id),
          claimed_device_id: safeString(r.claimed_device_id),
          user_id: safeString(r.user_id),
          device_name: safeString(r.device_name),
          peer_ip: safeString(r.peer_ip),
          created_at_ms: Number(r.created_at_ms || 0) || 0,
          decided_at_ms: Number(r.decided_at_ms || 0) || 0,
          deny_reason: safeString(r.deny_reason),
          device_info: info,
          requested_scopes: Array.isArray(scopes) ? scopes.map((s) => safeString(s)).filter(Boolean) : [],
          approved_device_id: safeString(r.approved_device_id),
          policy_mode: normalizedPolicyMode(r.policy_mode, approvedTrustProfile ? 'new_profile' : 'legacy_grant'),
          approved_trust_profile: approvedTrustProfile,
        };
      });

      jsonResponse(res, 200, { ok: true, requests });
      return;
    }

    if (pathname.startsWith('/admin/pairing/requests/') && method === 'POST') {
      const admin = requireHttpAdmin(req);
      if (!admin.ok) {
        jsonResponse(res, admin.status || 403, { ok: false, error: { code: admin.code || 'permission_denied', message: admin.message || 'permission_denied', retryable: false } });
        return;
      }

      const tail = pathname.slice('/admin/pairing/requests/'.length);
      const parts = tail.split('/').filter(Boolean);
      const pairing_request_id = safeString(parts[0]);
      const action = safeString(parts[1]);
      if (!pairing_request_id || (action !== 'approve' && action !== 'deny')) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const body = await readBodyJson(req, { maxBytes: 64 * 1024 });
      if (!body.ok) {
        jsonResponse(res, 400, { ok: false, error: { code: body.error, message: body.error, retryable: false } });
        return;
      }
      const obj = body.json || {};

      if (action === 'deny') {
        const deny_reason = obj.deny_reason ? safeString(obj.deny_reason) : '';
        let row;
        try {
          row = db.denyPairingRequest(pairing_request_id, { deny_reason: deny_reason || null, decided_at_ms: nowMs() });
        } catch {
          row = null;
        }
        if (!row) {
          jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
          return;
        }
        jsonResponse(res, 200, { ok: true, pairing_request_id, status: 'denied' });
        return;
      }

      // approve
      const rowBeforeApprove = db.getPairingRequest(pairing_request_id);
      if (!rowBeforeApprove) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const raw_policy_mode = obj.policy_mode == null ? '' : safeString(obj.policy_mode).toLowerCase();
      if (raw_policy_mode && !POLICY_MODES.has(raw_policy_mode)) {
        jsonResponse(res, 400, { ok: false, error: { code: 'policy_mode_invalid', message: 'policy_mode_invalid', retryable: false } });
        return;
      }
      const requested_policy_mode = raw_policy_mode || 'new_profile';
      const raw_paid_model_selection_mode = obj.paid_model_selection_mode == null ? '' : safeString(obj.paid_model_selection_mode).toLowerCase();
      const requested_paid_model_selection_mode = raw_paid_model_selection_mode || 'off';
      const requested_allowed_paid_models = uniqueStrings(safeStringArray(obj.allowed_paid_models));
      const requested_default_web_fetch_enabled = obj.default_web_fetch_enabled == null ? true : obj.default_web_fetch_enabled === true;
      const requested_daily_token_limit = parseDailyTokenLimit(obj.daily_token_limit, DEFAULT_PAIRING_DAILY_TOKEN_LIMIT);
      if (requested_policy_mode === 'new_profile') {
        if (raw_paid_model_selection_mode && !PAID_MODEL_SELECTION_MODES.has(raw_paid_model_selection_mode)) {
          jsonResponse(res, 400, { ok: false, error: { code: 'paid_model_selection_mode_invalid', message: 'paid_model_selection_mode_invalid', retryable: false } });
          return;
        }
        if (requested_paid_model_selection_mode === 'custom_selected_models' && requested_allowed_paid_models.length === 0) {
          jsonResponse(res, 400, { ok: false, error: { code: 'custom_selected_models_empty', message: 'custom_selected_models_empty', retryable: false } });
          return;
        }
        if (requested_daily_token_limit == null) {
          jsonResponse(res, 400, { ok: false, error: { code: 'daily_token_limit_invalid', message: 'daily_token_limit_invalid', retryable: false } });
          return;
        }
      }

      const device_name = uniqueStrings([
        obj.device_name,
        rowBeforeApprove.device_name,
        rowBeforeApprove.claimed_device_id,
        rowBeforeApprove.app_id,
      ])[0] || '';
      if (!device_name) {
        jsonResponse(res, 400, { ok: false, error: { code: 'device_name_required', message: 'device_name_required', retryable: false } });
        return;
      }

      const capabilities = safeStringArray(obj.capabilities);
      const allowed_cidrs = safeStringArray(obj.allowed_cidrs);
      const reqUserId = safeString(rowBeforeApprove.user_id);
      const approved_device_id = generateDeviceId();
      const approved_client_token = generateClientToken();
      const requestedUserId = obj.user_id ? safeString(obj.user_id) : '';
      const boundUserId = requestedUserId || reqUserId || approved_device_id;

      const baseCapList = capabilities.length ? capabilities : defaultClientCaps();
      const approvedTrustProfile = requested_policy_mode === 'new_profile'
        ? buildApprovedTrustProfile({
            device_id: approved_device_id,
            device_name,
            capabilities: baseCapList,
            paid_model_selection_mode: requested_paid_model_selection_mode,
            allowed_paid_models: requested_allowed_paid_models,
            default_web_fetch_enabled: requested_default_web_fetch_enabled,
            daily_token_limit: requested_daily_token_limit,
            audit_ref: pairing_request_id,
          })
        : null;
      const capList = approvedTrustProfile
        ? uniqueStrings(approvedTrustProfile.capabilities)
        : uniqueStrings(baseCapList.length ? baseCapList : defaultClientCaps());
      const cidrList = allowed_cidrs.length ? uniqueStrings(allowed_cidrs) : defaultAllowedCidrs();

      const tlsMode = tlsModeFromEnv(process.env);
      let cert_sha256 = '';
      if (tlsMode === 'mtls') {
        const row0 = db.getPairingRequest(pairing_request_id);
        if (!row0) {
          jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
          return;
        }
        let info = null;
        try {
          info = row0?.device_info_json ? JSON.parse(String(row0.device_info_json)) : null;
        } catch {
          info = null;
        }
        const csrPem = safeString(info?.tls?.csr_pem || info?.tls_csr_pem || obj.tls_csr_pem || '');
        const csrB64 = safeString(obj.tls_csr_b64 || '');
        const csrPem2 = csrPem || (csrB64 ? base64DecodeUtf8(csrB64) : '');
        if (!csrPem2 || !csrPem2.includes('BEGIN CERTIFICATE REQUEST')) {
          jsonResponse(res, 400, { ok: false, error: { code: 'missing_tls_csr', message: 'missing_tls_csr', retryable: false } });
          return;
        }
        const runtimeBaseDir = resolveRuntimeBaseDir();
        try {
          ensureHubTlsMaterial(runtimeBaseDir, { env: process.env });
        } catch {
          jsonResponse(res, 500, { ok: false, error: { code: 'tls_init_failed', message: 'tls_init_failed', retryable: true } });
          return;
        }
        try {
          const signed = signClientCertFromCsr(runtimeBaseDir, { deviceId: approved_device_id, csrPem: csrPem2, env: process.env });
          cert_sha256 = safeString(signed?.cert_sha256).toLowerCase();
        } catch {
          jsonResponse(res, 500, { ok: false, error: { code: 'tls_sign_failed', message: 'tls_sign_failed', retryable: true } });
          return;
        }
      }

      const runtimeBaseDir = resolveRuntimeBaseDir();
      const snap0 = readClientsSnapshot(runtimeBaseDir);
      const entry = {
        access_key_id: approved_device_id,
        auth_kind: 'paired_client',
        device_id: approved_device_id,
        user_id: boundUserId || approved_device_id,
        app_id: safeString(obj.app_id || rowBeforeApprove.app_id),
        name: device_name,
        note: safeString(obj.note),
        token: approved_client_token,
        enabled: true,
        created_at_ms: nowMs(),
        updated_at_ms: nowMs(),
        capabilities: capList,
        scopes: uniqueStrings(capList),
        allowed_cidrs: cidrList,
        policy_mode: requested_policy_mode,
        created_by_user_id: safeString(obj.created_by_hub_user_id || rowBeforeApprove.user_id),
        created_by_app_id: safeString(obj.created_via || 'hub_pairing_approve') || 'hub_pairing_approve',
        created_via: 'hub_pairing_approve',
        ...(approvedTrustProfile ? { approved_trust_profile: approvedTrustProfile } : {}),
        ...(cert_sha256 ? { cert_sha256 } : {}),
      };
      const snap1 = upsertClientInSnapshot(snap0, entry);
      if (!writeClientsSnapshot(runtimeBaseDir, snap1)) {
        jsonResponse(res, 500, { ok: false, error: { code: 'write_failed', message: 'write_failed', retryable: true } });
        return;
      }

      let row;
      try {
        row = db.approvePairingRequest(pairing_request_id, {
          decided_at_ms: nowMs(),
          user_id: boundUserId,
          approved_device_id,
          approved_client_token,
          device_name,
          approved_capabilities_json: JSON.stringify(capList),
          approved_allowed_cidrs_json: JSON.stringify(cidrList),
          policy_mode: requested_policy_mode,
          approved_trust_profile_json: approvedTrustProfile ? JSON.stringify(approvedTrustProfile) : null,
        });
      } catch {
        row = null;
      }
      if (!row) {
        jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
        return;
      }

      const tlsServerName = tlsMode === 'insecure' ? '' : tlsServerNameFromEnv(process.env);
      const routeMetadata = buildPairingRouteMetadata({
        runtimeBaseDir,
        hubIdentity,
        internetHostHint,
        pairingPort: port,
        grpcPort,
        tlsMode,
        tlsServerName,
        clientsSnapshot: snap1,
      });
      const issuedClient = findClientByAccessKeyId(runtimeBaseDir, approved_device_id) || entry;
      const peerIp = peerIpFromReq(req);

      jsonResponse(res, 200, {
        ok: true,
        pairing_request_id,
        status: 'approved',
        device_id: approved_device_id,
        client_token: approved_client_token,
        access_key: toHttpClientAccessKey(issuedClient, {
          req,
          hostFallback,
          peerIp,
          internetHostHint,
          grpcPort,
          tlsMode,
          tlsServerName,
        }, {
          include_secret_token: true,
          client_token: approved_client_token,
        }),
        policy_mode: requested_policy_mode,
        approved_trust_profile: approvedTrustProfile,
        pairing_profile_epoch: routeMetadata.pairing_profile_epoch,
        route_pack_version: routeMetadata.route_pack_version,
      });
      return;
    }

    jsonResponse(res, 404, { ok: false, error: { code: 'not_found', message: 'not_found', retryable: false } });
  });

  server.on('clientError', (_err, socket) => {
    try {
      socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    } catch {
      // ignore
    }
  });

  server.on('error', (err) => {
    // Never crash the main gRPC server because pairing port is unavailable.
    // eslint-disable-next-line no-console
    console.log(`[hub_pairing] listen failed on ${host}:${port}: ${String(err?.message || err)}`);
  });

  server.listen(port, host);
  // eslint-disable-next-line no-console
  console.log(`[hub_pairing] listening on ${host}:${port} allowed=${allowedCidrs.join(',') || '(any)'}`);

  return () => {
    try {
      server.close();
    } catch {
      // ignore
    }
  };
}
