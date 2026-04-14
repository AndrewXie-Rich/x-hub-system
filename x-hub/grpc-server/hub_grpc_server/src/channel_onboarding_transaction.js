import {
  getSupervisorOperatorChannelBindingById,
  normalizeSupervisorChannelScope,
  normalizeSupervisorScopeType,
  resolveSupervisorOperatorChannelBinding,
  upsertSupervisorOperatorChannelBindingTx,
} from './channel_bindings_store.js';
import { getChannelActionPolicy } from './channel_command_gate.js';
import {
  normalizeChannelAccessGroups,
  getChannelIdentityBinding,
  normalizeChannelRoles,
  upsertChannelIdentityBindingTx,
} from './channel_identity_store.js';
import { normalizeChannelProviderId } from './channel_registry.js';
import { nowMs, uuid } from './util.js';

export const CHANNEL_ONBOARDING_AUTO_BIND_RECEIPT_SCHEMA = 'xhub.channel_onboarding_auto_bind_receipt.v1';
export const CHANNEL_ONBOARDING_AUTO_BIND_REVOCATION_SCHEMA = 'xhub.channel_onboarding_auto_bind_revocation.v1';

const TABLES_INIT = new WeakSet();
const ROLE_PRIORITY = Object.freeze(['viewer', 'operator', 'approval_only_identity', 'release_manager', 'ops_admin']);
const EXACT_BINDING_MATCH_MODES = new Set(['exact_thread', 'conversation_exact']);

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function parseJsonArray(input) {
  if (Array.isArray(input)) return input;
  const text = safeString(input);
  if (!text) return [];
  try {
    const parsed = JSON.parse(text);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function normalizeActionList(input) {
  const rows = Array.isArray(input) ? input : [];
  const out = [];
  const seen = new Set();
  for (const raw of rows) {
    const action = safeString(raw).toLowerCase();
    if (!action || seen.has(action)) continue;
    seen.add(action);
    out.push(action);
  }
  return out;
}

function sameStringSet(left, right) {
  const a = normalizeActionList(left);
  const b = normalizeActionList(right);
  if (a.length !== b.length) return false;
  const wanted = new Set(a);
  return b.every((item) => wanted.has(item));
}

function ensureDb(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.exec !== 'function') {
    throw new Error('channel_onboarding_transaction_db_required');
  }
  db.db.exec(`
    CREATE TABLE IF NOT EXISTS channel_onboarding_auto_bind_receipts (
      receipt_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      ticket_id TEXT NOT NULL UNIQUE,
      decision_id TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL,
      provider TEXT NOT NULL,
      account_id TEXT NOT NULL,
      external_user_id TEXT NOT NULL,
      external_tenant_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      thread_key TEXT NOT NULL,
      hub_user_id TEXT NOT NULL,
      scope_type TEXT NOT NULL,
      scope_id TEXT NOT NULL,
      identity_actor_ref TEXT NOT NULL,
      channel_binding_id TEXT NOT NULL,
      preferred_device_id TEXT NOT NULL,
      allowed_actions_json TEXT NOT NULL,
      created_identity INTEGER NOT NULL,
      updated_identity INTEGER NOT NULL,
      created_channel_binding INTEGER NOT NULL,
      updated_channel_binding INTEGER NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      audit_ref TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_channel_onboarding_auto_bind_receipts_ticket
      ON channel_onboarding_auto_bind_receipts(ticket_id, updated_at_ms DESC);

    CREATE TABLE IF NOT EXISTS channel_onboarding_auto_bind_revocations (
      revocation_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      ticket_id TEXT NOT NULL UNIQUE,
      receipt_id TEXT NOT NULL UNIQUE,
      decision_id TEXT NOT NULL,
      status TEXT NOT NULL,
      provider TEXT NOT NULL,
      account_id TEXT NOT NULL,
      external_user_id TEXT NOT NULL,
      external_tenant_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      thread_key TEXT NOT NULL,
      hub_user_id TEXT NOT NULL,
      scope_type TEXT NOT NULL,
      scope_id TEXT NOT NULL,
      identity_actor_ref TEXT NOT NULL,
      channel_binding_id TEXT NOT NULL,
      revoked_by_hub_user_id TEXT NOT NULL,
      revoked_via TEXT NOT NULL,
      note TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      audit_ref TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_channel_onboarding_auto_bind_revocations_ticket
      ON channel_onboarding_auto_bind_revocations(ticket_id, updated_at_ms DESC);
  `);
  TABLES_INIT.add(db);
}

function parseReceiptRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    schema_version: safeString(row.schema_version) || CHANNEL_ONBOARDING_AUTO_BIND_RECEIPT_SCHEMA,
    receipt_id: safeString(row.receipt_id),
    ticket_id: safeString(row.ticket_id),
    decision_id: safeString(row.decision_id),
    status: safeString(row.status) || 'applied',
    provider: safeString(row.provider).toLowerCase(),
    account_id: safeString(row.account_id),
    external_user_id: safeString(row.external_user_id),
    external_tenant_id: safeString(row.external_tenant_id),
    conversation_id: safeString(row.conversation_id),
    thread_key: safeString(row.thread_key),
    hub_user_id: safeString(row.hub_user_id),
    scope_type: safeString(row.scope_type),
    scope_id: safeString(row.scope_id),
    identity_actor_ref: safeString(row.identity_actor_ref),
    channel_binding_id: safeString(row.channel_binding_id),
    preferred_device_id: safeString(row.preferred_device_id),
    allowed_actions: normalizeActionList(parseJsonArray(row.allowed_actions_json)),
    created_identity: !!Number(row.created_identity || 0),
    updated_identity: !!Number(row.updated_identity || 0),
    created_channel_binding: !!Number(row.created_channel_binding || 0),
    updated_channel_binding: !!Number(row.updated_channel_binding || 0),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

function parseRevocationRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    schema_version: safeString(row.schema_version) || CHANNEL_ONBOARDING_AUTO_BIND_REVOCATION_SCHEMA,
    revocation_id: safeString(row.revocation_id),
    ticket_id: safeString(row.ticket_id),
    receipt_id: safeString(row.receipt_id),
    decision_id: safeString(row.decision_id),
    status: safeString(row.status) || 'revoked',
    provider: safeString(row.provider).toLowerCase(),
    account_id: safeString(row.account_id),
    external_user_id: safeString(row.external_user_id),
    external_tenant_id: safeString(row.external_tenant_id),
    conversation_id: safeString(row.conversation_id),
    thread_key: safeString(row.thread_key),
    hub_user_id: safeString(row.hub_user_id),
    scope_type: safeString(row.scope_type),
    scope_id: safeString(row.scope_id),
    identity_actor_ref: safeString(row.identity_actor_ref),
    channel_binding_id: safeString(row.channel_binding_id),
    revoked_by_hub_user_id: safeString(row.revoked_by_hub_user_id),
    revoked_via: safeString(row.revoked_via),
    note: safeString(row.note),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

function bindingModeThreadKey(ticket, decision) {
  return safeString(decision?.binding_mode) === 'thread_binding'
    ? safeString(ticket?.thread_key)
    : '';
}

function discoveryRouteKey(row = {}) {
  return `${safeString(row.conversation_id)}|${safeString(row.thread_key)}`;
}

function discoveryTicketFreshnessRank(row = {}) {
  return Math.max(
    safeInt(row.last_seen_at_ms, 0),
    safeInt(row.updated_at_ms, 0),
    safeInt(row.created_at_ms, 0)
  );
}

function findSupersedingOpenDiscoveryTicketForIdentity(db, ticket = {}) {
  const provider = normalizeChannelProviderId(ticket.provider) || '';
  const account_id = safeString(ticket.account_id);
  const external_user_id = safeString(ticket.external_user_id);
  const external_tenant_id = safeString(ticket.external_tenant_id || ticket.account_id);
  const ticket_id = safeString(ticket.ticket_id);
  if (!provider || !account_id || !external_user_id || !ticket_id) return null;

  let rows = [];
  try {
    rows = db.db.prepare(
      `SELECT ticket_id, conversation_id, thread_key, proposed_scope_type, proposed_scope_id,
              last_seen_at_ms, updated_at_ms, created_at_ms
       FROM channel_onboarding_discovery_tickets
       WHERE provider = ?
         AND account_id = ?
         AND external_user_id = ?
         AND external_tenant_id = ?
         AND status IN ('pending', 'held')
         AND ticket_id <> ?
         AND expires_at_ms > ?
       ORDER BY last_seen_at_ms DESC, updated_at_ms DESC, created_at_ms DESC
       LIMIT 20`
    ).all(
      provider,
      account_id,
      external_user_id,
      external_tenant_id,
      ticket_id,
      nowMs()
    );
  } catch {
    return null;
  }

  const currentRoute = discoveryRouteKey(ticket);
  const currentRank = discoveryTicketFreshnessRank(ticket);
  for (const row of Array.isArray(rows) ? rows : []) {
    if (discoveryRouteKey(row) === currentRoute) continue;
    if (discoveryTicketFreshnessRank(row) <= currentRank) continue;
    return {
      ticket_id: safeString(row.ticket_id),
      conversation_id: safeString(row.conversation_id),
      thread_key: safeString(row.thread_key),
      proposed_scope_type: safeString(row.proposed_scope_type),
      proposed_scope_id: safeString(row.proposed_scope_id),
      last_seen_at_ms: safeInt(row.last_seen_at_ms, 0),
      updated_at_ms: safeInt(row.updated_at_ms, 0),
    };
  }
  return null;
}

function deriveIdentityRolesFromAllowedActions(allowed_actions = []) {
  const actions = normalizeActionList(allowed_actions);
  if (!actions.length) return [];
  let intersection = null;
  for (const action of actions) {
    const policy = getChannelActionPolicy(action);
    if (!policy) return [];
    const roles = normalizeChannelRoles(policy.allowed_roles || []);
    if (!roles.length) return [];
    intersection = intersection == null
      ? roles
      : intersection.filter((role) => roles.includes(role));
    if (!intersection.length) return [];
  }
  const ranked = [...intersection].sort((left, right) => {
    const leftIdx = ROLE_PRIORITY.indexOf(left);
    const rightIdx = ROLE_PRIORITY.indexOf(right);
    const safeLeft = leftIdx >= 0 ? leftIdx : Number.MAX_SAFE_INTEGER;
    const safeRight = rightIdx >= 0 ? rightIdx : Number.MAX_SAFE_INTEGER;
    return safeLeft - safeRight || left.localeCompare(right);
  });
  return ranked.length ? [ranked[0]] : [];
}

function isApprovalOnlyAllowedActions(allowed_actions = []) {
  const actions = normalizeActionList(allowed_actions);
  return actions.length > 0 && actions.every((action) => {
    const policy = getChannelActionPolicy(action);
    return !!policy && policy.approval_compatible === true;
  });
}

function deriveIdentityAccessGroups({
  ticket = {},
  decision = {},
} = {}) {
  const groups = [];
  const ingressSurface = normalizeSupervisorChannelScope(ticket.ingress_surface, 'group');
  if (ingressSurface === 'dm') groups.push('dm_allowlist');
  else groups.push('group_allowlist');
  if (bindingModeThreadKey(ticket, decision)) groups.push('thread_allowlist');
  if (isApprovalOnlyAllowedActions(decision.allowed_actions || [])) groups.push('approval_only_identity');
  return normalizeChannelAccessGroups(groups);
}

function autoBindDeny(deny_code, detail = {}, extras = {}) {
  return {
    ok: false,
    deny_code: safeString(deny_code) || 'channel_onboarding_auto_bind_rejected',
    detail: detail && typeof detail === 'object' ? detail : {},
    identity_binding: extras.identity_binding || null,
    channel_binding: extras.channel_binding || null,
    receipt: extras.receipt || null,
    audit_logged: false,
  };
}

function autoBindRevokeDeny(deny_code, detail = {}, extras = {}) {
  return {
    ok: false,
    deny_code: safeString(deny_code) || 'channel_onboarding_auto_bind_revoke_rejected',
    detail: detail && typeof detail === 'object' ? detail : {},
    identity_binding: extras.identity_binding || null,
    channel_binding: extras.channel_binding || null,
    receipt: extras.receipt || null,
    revocation: extras.revocation || null,
    audit_logged: false,
  };
}

function buildTicketShapeFromReceipt(receipt = {}) {
  return {
    ticket_id: safeString(receipt.ticket_id),
    provider: safeString(receipt.provider),
    account_id: safeString(receipt.account_id),
    external_user_id: safeString(receipt.external_user_id),
    external_tenant_id: safeString(receipt.external_tenant_id),
    conversation_id: safeString(receipt.conversation_id),
    thread_key: safeString(receipt.thread_key),
  };
}

function buildDecisionShapeFromReceipt(receipt = {}, decision = {}) {
  return {
    decision_id: safeString(decision.decision_id || receipt.decision_id),
    approved_by_hub_user_id: safeString(decision.approved_by_hub_user_id),
    approved_via: safeString(decision.approved_via),
    hub_user_id: safeString(decision.hub_user_id || receipt.hub_user_id),
    scope_type: safeString(decision.scope_type || receipt.scope_type),
    scope_id: safeString(decision.scope_id || receipt.scope_id),
    allowed_actions: normalizeActionList(decision.allowed_actions || receipt.allowed_actions || []),
    preferred_device_id: safeString(decision.preferred_device_id || receipt.preferred_device_id),
  };
}

function appendAutoBindAudit({
  db,
  event_type,
  ticket,
  decision,
  identity_binding = null,
  channel_binding = null,
  receipt = null,
  request_id = '',
  audit = {},
  ok = true,
  deny_code = '',
  error_message = '',
  detail = {},
} = {}) {
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type: safeString(event_type) || 'channel.onboarding.auto_bind.succeeded',
    created_at_ms: nowMs(),
    severity: ok ? 'info' : 'warn',
    device_id: safeString(audit.device_id || 'channel_onboarding_transaction'),
    user_id: safeString(audit.user_id || decision?.approved_by_hub_user_id) || null,
    app_id: safeString(audit.app_id || decision?.approved_via || 'channel_onboarding_transaction'),
    project_id: safeString(decision?.scope_type) === 'project' ? safeString(decision?.scope_id) || null : null,
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: 'channel.onboarding.auto_bind.write',
    model_id: null,
    ok: !!ok,
    error_code: ok ? null : (safeString(deny_code) || 'channel_onboarding_auto_bind_rejected'),
    error_message: ok ? null : (safeString(error_message) || safeString(deny_code) || 'channel_onboarding_auto_bind_rejected'),
    ext_json: JSON.stringify({
      schema_version: CHANNEL_ONBOARDING_AUTO_BIND_RECEIPT_SCHEMA,
      ticket_id: safeString(ticket?.ticket_id),
      decision_id: safeString(decision?.decision_id),
      provider: safeString(ticket?.provider).toLowerCase(),
      account_id: safeString(ticket?.account_id),
      external_user_id: safeString(ticket?.external_user_id),
      external_tenant_id: safeString(ticket?.external_tenant_id),
      conversation_id: safeString(ticket?.conversation_id),
      thread_key: bindingModeThreadKey(ticket, decision),
      ingress_surface: safeString(ticket?.ingress_surface),
      hub_user_id: safeString(decision?.hub_user_id),
      scope_type: safeString(decision?.scope_type),
      scope_id: safeString(decision?.scope_id),
      allowed_actions: normalizeActionList(decision?.allowed_actions || []),
      preferred_device_id: safeString(decision?.preferred_device_id),
      identity_actor_ref: safeString(identity_binding?.actor_ref),
      channel_binding_id: safeString(channel_binding?.binding_id),
      receipt_id: safeString(receipt?.receipt_id),
      detail: detail && typeof detail === 'object' ? detail : {},
    }),
  });
}

export function appendChannelOnboardingAutoBindRejectedAudit(db, {
  ticket = null,
  decision = null,
  identity_binding = null,
  channel_binding = null,
  request_id = '',
  audit = {},
  deny_code = '',
  detail = {},
} = {}) {
  ensureDb(db);
  return appendAutoBindAudit({
    db,
    event_type: 'channel.onboarding.auto_bind.rejected',
    ticket,
    decision,
    identity_binding,
    channel_binding,
    request_id,
    audit,
    ok: false,
    deny_code,
    error_message: safeString(deny_code),
    detail,
  });
}

export function getChannelOnboardingAutoBindReceiptByTicketId(db, { ticket_id } = {}) {
  ensureDb(db);
  const ticketId = safeString(ticket_id);
  if (!ticketId) return null;
  const row = db.db
    .prepare(
      `SELECT *
       FROM channel_onboarding_auto_bind_receipts
       WHERE ticket_id = ?
       LIMIT 1`
    )
    .get(ticketId);
  return parseReceiptRow(row);
}

export function getChannelOnboardingAutoBindRevocationByTicketId(db, { ticket_id } = {}) {
  ensureDb(db);
  const ticketId = safeString(ticket_id);
  if (!ticketId) return null;
  const row = db.db
    .prepare(
      `SELECT *
       FROM channel_onboarding_auto_bind_revocations
       WHERE ticket_id = ?
       LIMIT 1`
    )
    .get(ticketId);
  return parseRevocationRow(row);
}

export function writeApprovedChannelOnboardingAutoBindTx(db, {
  ticket = {},
  decision = {},
  request_id = '',
  audit = {},
} = {}) {
  ensureDb(db);

  const provider = normalizeChannelProviderId(ticket.provider) || '';
  const account_id = safeString(ticket.account_id);
  const external_user_id = safeString(ticket.external_user_id);
  const external_tenant_id = safeString(ticket.external_tenant_id || ticket.account_id);
  const conversation_id = safeString(ticket.conversation_id);
  const binding_mode = safeString(decision.binding_mode) || safeString(ticket.recommended_binding_mode) || 'conversation_binding';
  const thread_key = binding_mode === 'thread_binding' ? safeString(ticket.thread_key) : '';
  const channel_scope = normalizeSupervisorChannelScope(ticket.ingress_surface || 'group', 'group');
  const scope_type = normalizeSupervisorScopeType(decision.scope_type, safeString(ticket.proposed_scope_type) || 'project');
  const scope_id = safeString(decision.scope_id || ticket.proposed_scope_id);
  const hub_user_id = safeString(decision.hub_user_id);
  const allowed_actions = normalizeActionList(decision.allowed_actions || []);

  if (safeString(ticket.ticket_id) === '') return autoBindDeny('ticket_id_missing');
  if (safeString(decision.decision).toLowerCase() !== 'approve') return autoBindDeny('decision_not_approved');
  if (!safeString(decision.decision_id)) return autoBindDeny('decision_id_missing');
  if (!provider) return autoBindDeny('provider_unknown');
  if (!external_user_id) return autoBindDeny('external_user_id_missing');
  if (!conversation_id) return autoBindDeny('conversation_id_missing');
  if (!hub_user_id) return autoBindDeny('hub_user_id_missing');
  if (!scope_id) return autoBindDeny('scope_id_missing');
  if (!allowed_actions.length) return autoBindDeny('allowed_actions_missing');
  if (binding_mode === 'thread_binding' && !thread_key) return autoBindDeny('thread_binding_requires_thread_key');

  const existingReceipt = getChannelOnboardingAutoBindReceiptByTicketId(db, {
    ticket_id: ticket.ticket_id,
  });
  if (existingReceipt) {
    const existingChannelBinding = getSupervisorOperatorChannelBindingById(db, {
      binding_id: existingReceipt.channel_binding_id,
    });
    return {
      ok: true,
      deny_code: '',
      detail: {},
      identity_binding: existingReceipt.identity_actor_ref
        ? getChannelIdentityBinding(db, { provider, external_user_id, external_tenant_id })
        : null,
      channel_binding: existingChannelBinding,
      receipt: existingReceipt,
      audit_logged: false,
      created_identity: false,
      updated_identity: false,
      created_channel_binding: false,
      updated_channel_binding: false,
      idempotent: true,
    };
  }

  const supersedingTicket = findSupersedingOpenDiscoveryTicketForIdentity(db, ticket);
  if (supersedingTicket) {
    return autoBindDeny('identity_route_drift_detected', {
      stale_ticket_id: safeString(ticket.ticket_id),
      stale_conversation_id: conversation_id,
      stale_thread_key: thread_key,
      superseding_ticket_id: safeString(supersedingTicket.ticket_id),
      superseding_conversation_id: safeString(supersedingTicket.conversation_id),
      superseding_thread_key: safeString(supersedingTicket.thread_key),
      superseding_scope_type: safeString(supersedingTicket.proposed_scope_type),
      superseding_scope_id: safeString(supersedingTicket.proposed_scope_id),
    });
  }

  const derivedRoles = deriveIdentityRolesFromAllowedActions(allowed_actions);
  if (!derivedRoles.length) {
    return autoBindDeny('identity_roles_unresolvable', {
      allowed_actions,
    });
  }
  const derivedAccessGroups = deriveIdentityAccessGroups({ ticket, decision });
  const requestedApprovalOnly = derivedAccessGroups.includes('approval_only_identity');

  const existingIdentity = getChannelIdentityBinding(db, {
    provider,
    external_user_id,
    external_tenant_id,
  });
  if (existingIdentity && safeString(existingIdentity.hub_user_id) !== hub_user_id) {
    return autoBindDeny('identity_binding_conflict', {
      existing_hub_user_id: safeString(existingIdentity.hub_user_id),
      requested_hub_user_id: hub_user_id,
    }, {
      identity_binding: existingIdentity,
    });
  }
  if (existingIdentity && existingIdentity.approval_only === true && !requestedApprovalOnly) {
    return autoBindDeny('identity_binding_approval_only_conflict', {}, {
      identity_binding: existingIdentity,
    });
  }

  const identityOut = upsertChannelIdentityBindingTx(db, {
    binding: {
      provider,
      external_user_id,
      external_tenant_id,
      hub_user_id,
      roles: normalizeChannelRoles([
        ...(existingIdentity?.roles || []),
        ...derivedRoles,
      ]),
      access_groups: normalizeChannelAccessGroups([
        ...(existingIdentity?.access_groups || []),
        ...derivedAccessGroups,
      ]),
      approval_only: existingIdentity ? existingIdentity.approval_only === true : requestedApprovalOnly,
      status: 'active',
    },
    request_id,
    audit: {
      ...audit,
      app_id: safeString(audit.app_id || decision.approved_via || 'channel_onboarding_auto_bind'),
    },
  });
  if (!identityOut.ok) {
    return autoBindDeny(identityOut.deny_code, identityOut.detail, {
      identity_binding: identityOut.binding,
    });
  }

  const resolvedRoute = resolveSupervisorOperatorChannelBinding(db, {
    provider,
    account_id,
    conversation_id,
    thread_key,
    channel_scope,
  });
  const existingChannel = EXACT_BINDING_MATCH_MODES.has(safeString(resolvedRoute.binding_match_mode))
    ? resolvedRoute.binding
    : null;
  if (existingChannel) {
    if (
      safeString(existingChannel.scope_type) !== scope_type
      || safeString(existingChannel.scope_id) !== scope_id
    ) {
      return autoBindDeny('channel_binding_conflict', {
        reason: 'scope_mismatch',
        existing_scope_type: safeString(existingChannel.scope_type),
        existing_scope_id: safeString(existingChannel.scope_id),
        requested_scope_type: scope_type,
        requested_scope_id: scope_id,
      }, {
        identity_binding: identityOut.binding,
        channel_binding: existingChannel,
      });
    }
    const existingPreferredDeviceId = safeString(existingChannel.preferred_device_id);
    const requestedPreferredDeviceId = safeString(decision.preferred_device_id);
    if (existingPreferredDeviceId && requestedPreferredDeviceId && existingPreferredDeviceId !== requestedPreferredDeviceId) {
      return autoBindDeny('channel_binding_conflict', {
        reason: 'preferred_device_mismatch',
        existing_preferred_device_id: existingPreferredDeviceId,
        requested_preferred_device_id: requestedPreferredDeviceId,
      }, {
        identity_binding: identityOut.binding,
        channel_binding: existingChannel,
      });
    }
    if (!sameStringSet(existingChannel.allowed_actions, allowed_actions)) {
      return autoBindDeny('channel_binding_conflict', {
        reason: 'allowed_actions_mismatch',
        existing_allowed_actions: normalizeActionList(existingChannel.allowed_actions),
        requested_allowed_actions: allowed_actions,
      }, {
        identity_binding: identityOut.binding,
        channel_binding: existingChannel,
      });
    }
  }

  const channelOut = upsertSupervisorOperatorChannelBindingTx(db, {
    binding: {
      provider,
      account_id,
      conversation_id,
      thread_key,
      channel_scope,
      scope_type,
      scope_id,
      preferred_device_id: safeString(decision.preferred_device_id || existingChannel?.preferred_device_id),
      allowed_actions,
      status: 'active',
    },
    request_id,
    audit: {
      ...audit,
      app_id: safeString(audit.app_id || decision.approved_via || 'channel_onboarding_auto_bind'),
    },
  });
  if (!channelOut.ok) {
    return autoBindDeny(channelOut.deny_code, channelOut.detail, {
      identity_binding: identityOut.binding,
      channel_binding: channelOut.binding,
    });
  }

  const receipt = {
    receipt_id: uuid(),
    schema_version: CHANNEL_ONBOARDING_AUTO_BIND_RECEIPT_SCHEMA,
    ticket_id: safeString(ticket.ticket_id),
    decision_id: safeString(decision.decision_id),
    status: 'applied',
    provider,
    account_id,
    external_user_id,
    external_tenant_id,
    conversation_id,
    thread_key,
    hub_user_id,
    scope_type,
    scope_id,
    identity_actor_ref: safeString(identityOut.binding?.actor_ref),
    channel_binding_id: safeString(channelOut.binding?.binding_id),
    preferred_device_id: safeString(channelOut.binding?.preferred_device_id),
    allowed_actions,
    created_identity: identityOut.created === true,
    updated_identity: identityOut.updated === true,
    created_channel_binding: channelOut.created === true,
    updated_channel_binding: channelOut.updated === true,
    created_at_ms: nowMs(),
    updated_at_ms: nowMs(),
    audit_ref: '',
  };
  const audit_ref = appendAutoBindAudit({
    db,
    event_type: 'channel.onboarding.auto_bind.succeeded',
    ticket,
    decision,
    identity_binding: identityOut.binding,
    channel_binding: channelOut.binding,
    receipt,
    request_id,
    audit,
    ok: true,
  });
  receipt.audit_ref = audit_ref;

  db.db.prepare(
    `INSERT INTO channel_onboarding_auto_bind_receipts(
       receipt_id, schema_version, ticket_id, decision_id, status, provider, account_id,
       external_user_id, external_tenant_id, conversation_id, thread_key, hub_user_id,
       scope_type, scope_id, identity_actor_ref, channel_binding_id, preferred_device_id,
       allowed_actions_json, created_identity, updated_identity, created_channel_binding,
       updated_channel_binding, created_at_ms, updated_at_ms, audit_ref
     ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
  ).run(
    receipt.receipt_id,
    receipt.schema_version,
    receipt.ticket_id,
    receipt.decision_id,
    receipt.status,
    receipt.provider,
    receipt.account_id,
    receipt.external_user_id,
    receipt.external_tenant_id,
    receipt.conversation_id,
    receipt.thread_key,
    receipt.hub_user_id,
    receipt.scope_type,
    receipt.scope_id,
    receipt.identity_actor_ref,
    receipt.channel_binding_id,
    receipt.preferred_device_id,
    JSON.stringify(receipt.allowed_actions),
    receipt.created_identity ? 1 : 0,
    receipt.updated_identity ? 1 : 0,
    receipt.created_channel_binding ? 1 : 0,
    receipt.updated_channel_binding ? 1 : 0,
    receipt.created_at_ms,
    receipt.updated_at_ms,
    receipt.audit_ref
  );

  return {
    ok: true,
    deny_code: '',
    detail: {},
    identity_binding: identityOut.binding,
    channel_binding: channelOut.binding,
    receipt,
    audit_logged: true,
    created_identity: receipt.created_identity,
    updated_identity: receipt.updated_identity,
    created_channel_binding: receipt.created_channel_binding,
    updated_channel_binding: receipt.updated_channel_binding,
    idempotent: false,
  };
}

export function revokeApprovedChannelOnboardingAutoBind(db, {
  ticket = {},
  decision = {},
  revocation = {},
  request_id = '',
  audit = {},
} = {}) {
  ensureDb(db);
  db.db.exec('BEGIN;');
  try {
    const out = revokeApprovedChannelOnboardingAutoBindTx(db, {
      ticket,
      decision,
      revocation,
      request_id,
      audit,
    });
    if (!out.ok) {
      db.db.exec('ROLLBACK;');
      return out;
    }
    db.db.exec('COMMIT;');
    return out;
  } catch (err) {
    try {
      db.db.exec('ROLLBACK;');
    } catch {
      // ignore
    }
    return autoBindRevokeDeny('audit_write_failed', {
      message: safeString(err?.message || 'audit_write_failed'),
    });
  }
}

export function revokeApprovedChannelOnboardingAutoBindTx(db, {
  ticket = {},
  decision = {},
  revocation = {},
  request_id = '',
  audit = {},
} = {}) {
  ensureDb(db);

  const ticketId = safeString(ticket.ticket_id || revocation.ticket_id);
  if (!ticketId) return autoBindRevokeDeny('ticket_id_missing');

  const receipt = getChannelOnboardingAutoBindReceiptByTicketId(db, {
    ticket_id: ticketId,
  });
  if (!receipt) {
    return autoBindRevokeDeny('auto_bind_receipt_missing');
  }

  const existingRevocation = getChannelOnboardingAutoBindRevocationByTicketId(db, {
    ticket_id: ticketId,
  });
  const identityBinding = getChannelIdentityBinding(db, {
    provider: receipt.provider,
    external_user_id: receipt.external_user_id,
    external_tenant_id: receipt.external_tenant_id,
  });
  const channelBinding = getSupervisorOperatorChannelBindingById(db, {
    binding_id: receipt.channel_binding_id,
  });
  if (existingRevocation) {
    return {
      ok: true,
      deny_code: '',
      detail: {},
      identity_binding: identityBinding,
      channel_binding: channelBinding,
      receipt,
      revocation: existingRevocation,
      audit_logged: false,
      updated_identity: false,
      updated_channel_binding: false,
      created_revocation: false,
      idempotent: true,
    };
  }
  if (safeString(receipt.status) !== 'applied') {
    return autoBindRevokeDeny('auto_bind_receipt_not_active', {
      status: safeString(receipt.status),
    }, {
      identity_binding: identityBinding,
      channel_binding: channelBinding,
      receipt,
    });
  }

  const revokedByHubUserId = safeString(
    revocation.revoked_by_hub_user_id
    || revocation.approved_by_hub_user_id
    || revocation.user_id
    || audit.user_id
  );
  if (!revokedByHubUserId) {
    return autoBindRevokeDeny('revoked_by_hub_user_id_missing', {}, {
      identity_binding: identityBinding,
      channel_binding: channelBinding,
      receipt,
    });
  }
  if (!identityBinding) {
    return autoBindRevokeDeny('identity_binding_missing', {}, {
      channel_binding: channelBinding,
      receipt,
    });
  }
  if (!channelBinding) {
    return autoBindRevokeDeny('channel_binding_missing', {}, {
      identity_binding: identityBinding,
      receipt,
    });
  }

  const revokedVia = safeString(
    revocation.revoked_via
    || revocation.approved_via
    || audit.app_id
    || 'hub_local_ui'
  ) || 'hub_local_ui';
  const revokeAudit = {
    ...audit,
    user_id: revokedByHubUserId,
    app_id: revokedVia,
  };

  const identityOut = upsertChannelIdentityBindingTx(db, {
    binding: {
      ...identityBinding,
      status: 'revoked',
    },
    request_id,
    audit: revokeAudit,
  });
  if (!identityOut.ok) {
    return autoBindRevokeDeny(identityOut.deny_code, identityOut.detail, {
      identity_binding: identityOut.binding,
      channel_binding: channelBinding,
      receipt,
    });
  }

  const channelOut = upsertSupervisorOperatorChannelBindingTx(db, {
    binding: {
      ...channelBinding,
      status: 'revoked',
    },
    request_id,
    audit: revokeAudit,
  });
  if (!channelOut.ok) {
    return autoBindRevokeDeny(channelOut.deny_code, channelOut.detail, {
      identity_binding: identityOut.binding,
      channel_binding: channelOut.binding,
      receipt,
    });
  }

  const updatedAtMs = nowMs();
  db.db.prepare(
    `UPDATE channel_onboarding_auto_bind_receipts
     SET status = ?,
         updated_at_ms = ?
     WHERE ticket_id = ?`
  ).run(
    'revoked',
    updatedAtMs,
    ticketId
  );

  const updatedReceipt = {
    ...receipt,
    status: 'revoked',
    updated_at_ms: updatedAtMs,
  };
  const effectiveTicket = safeString(ticket.ticket_id)
    ? ticket
    : buildTicketShapeFromReceipt(receipt);
  const effectiveDecision = buildDecisionShapeFromReceipt(receipt, decision);
  const persistedRevocation = {
    revocation_id: uuid(),
    schema_version: CHANNEL_ONBOARDING_AUTO_BIND_REVOCATION_SCHEMA,
    ticket_id: ticketId,
    receipt_id: safeString(receipt.receipt_id),
    decision_id: safeString(receipt.decision_id),
    status: 'revoked',
    provider: safeString(receipt.provider),
    account_id: safeString(receipt.account_id),
    external_user_id: safeString(receipt.external_user_id),
    external_tenant_id: safeString(receipt.external_tenant_id),
    conversation_id: safeString(receipt.conversation_id),
    thread_key: safeString(receipt.thread_key),
    hub_user_id: safeString(receipt.hub_user_id),
    scope_type: safeString(receipt.scope_type),
    scope_id: safeString(receipt.scope_id),
    identity_actor_ref: safeString(receipt.identity_actor_ref),
    channel_binding_id: safeString(receipt.channel_binding_id),
    revoked_by_hub_user_id: revokedByHubUserId,
    revoked_via: revokedVia,
    note: safeString(revocation.note),
    created_at_ms: updatedAtMs,
    updated_at_ms: updatedAtMs,
    audit_ref: '',
  };
  const audit_ref = appendAutoBindAudit({
    db,
    event_type: 'channel.onboarding.auto_bind.revoked',
    ticket: effectiveTicket,
    decision: effectiveDecision,
    identity_binding: identityOut.binding,
    channel_binding: channelOut.binding,
    receipt: updatedReceipt,
    request_id,
    audit: revokeAudit,
    ok: true,
    detail: {
      revocation_id: persistedRevocation.revocation_id,
      revoked_by_hub_user_id: revokedByHubUserId,
      revoked_via: revokedVia,
      note: persistedRevocation.note,
    },
  });
  persistedRevocation.audit_ref = audit_ref;

  db.db.prepare(
    `INSERT INTO channel_onboarding_auto_bind_revocations(
       revocation_id, schema_version, ticket_id, receipt_id, decision_id, status, provider, account_id,
       external_user_id, external_tenant_id, conversation_id, thread_key, hub_user_id,
       scope_type, scope_id, identity_actor_ref, channel_binding_id, revoked_by_hub_user_id,
       revoked_via, note, created_at_ms, updated_at_ms, audit_ref
     ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
  ).run(
    persistedRevocation.revocation_id,
    persistedRevocation.schema_version,
    persistedRevocation.ticket_id,
    persistedRevocation.receipt_id,
    persistedRevocation.decision_id,
    persistedRevocation.status,
    persistedRevocation.provider,
    persistedRevocation.account_id,
    persistedRevocation.external_user_id,
    persistedRevocation.external_tenant_id,
    persistedRevocation.conversation_id,
    persistedRevocation.thread_key,
    persistedRevocation.hub_user_id,
    persistedRevocation.scope_type,
    persistedRevocation.scope_id,
    persistedRevocation.identity_actor_ref,
    persistedRevocation.channel_binding_id,
    persistedRevocation.revoked_by_hub_user_id,
    persistedRevocation.revoked_via,
    persistedRevocation.note,
    persistedRevocation.created_at_ms,
    persistedRevocation.updated_at_ms,
    persistedRevocation.audit_ref
  );

  return {
    ok: true,
    deny_code: '',
    detail: {},
    identity_binding: identityOut.binding,
    channel_binding: channelOut.binding,
    receipt: updatedReceipt,
    revocation: persistedRevocation,
    audit_logged: true,
    updated_identity: true,
    updated_channel_binding: true,
    created_revocation: true,
    idempotent: false,
  };
}
