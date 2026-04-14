import fs from 'node:fs';
import path from 'node:path';

import { evaluateChannelCommandGateWithAudit } from './channel_command_gate.js';
import { buildChannelRuntimeStatusSnapshot } from './channel_runtime_snapshot.js';
import { buildProjectHeartbeatGovernanceSnapshot } from './project_heartbeat_governance_projection.js';
import { resolveSupervisorChannelRoute } from './supervisor_channel_route_facade.js';
import { upsertSupervisorChannelSessionRoute } from './supervisor_channel_session_store.js';
import { nowMs, uuid } from './util.js';

export const CHANNEL_ONBOARDING_FIRST_SMOKE_RECEIPT_SCHEMA = 'xhub.channel_onboarding_first_smoke_receipt.v1';

const SUPERVISOR_QUERY_ACTIONS = new Set([
  'supervisor.status.get',
  'supervisor.blockers.get',
  'supervisor.queue.get',
]);

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function parseJsonObject(input) {
  if (input && typeof input === 'object' && !Array.isArray(input)) return input;
  const text = safeString(input);
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function ensureDb(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.exec !== 'function') {
    throw new Error('channel_onboarding_first_smoke_db_required');
  }
  db.db.exec(`
    CREATE TABLE IF NOT EXISTS channel_onboarding_first_smoke_receipts (
      receipt_id TEXT PRIMARY KEY,
      schema_version TEXT NOT NULL,
      ticket_id TEXT NOT NULL UNIQUE,
      decision_id TEXT NOT NULL UNIQUE,
      provider TEXT NOT NULL,
      action_name TEXT NOT NULL,
      status TEXT NOT NULL,
      route_mode TEXT NOT NULL,
      deny_code TEXT NOT NULL,
      detail TEXT NOT NULL,
      remediation_hint TEXT NOT NULL,
      project_id TEXT NOT NULL,
      binding_id TEXT NOT NULL,
      ack_outbox_item_id TEXT NOT NULL,
      smoke_outbox_item_id TEXT NOT NULL,
      result_json TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      audit_ref TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_channel_onboarding_first_smoke_ticket
      ON channel_onboarding_first_smoke_receipts(ticket_id, updated_at_ms DESC);
  `);
}

function parseReceiptRow(row) {
  if (!row || typeof row !== 'object') return null;
  return {
    receipt_id: safeString(row.receipt_id),
    schema_version: safeString(row.schema_version) || CHANNEL_ONBOARDING_FIRST_SMOKE_RECEIPT_SCHEMA,
    ticket_id: safeString(row.ticket_id),
    decision_id: safeString(row.decision_id),
    provider: safeString(row.provider).toLowerCase(),
    action_name: safeString(row.action_name),
    status: safeString(row.status),
    route_mode: safeString(row.route_mode),
    deny_code: safeString(row.deny_code),
    detail: safeString(row.detail),
    remediation_hint: safeString(row.remediation_hint),
    project_id: safeString(row.project_id),
    binding_id: safeString(row.binding_id),
    ack_outbox_item_id: safeString(row.ack_outbox_item_id),
    smoke_outbox_item_id: safeString(row.smoke_outbox_item_id),
    result: parseJsonObject(row.result_json),
    created_at_ms: safeInt(row.created_at_ms, 0),
    updated_at_ms: safeInt(row.updated_at_ms, 0),
    audit_ref: safeString(row.audit_ref),
  };
}

function appendFirstSmokeAudit({
  db,
  receipt,
  request_id = '',
  audit = {},
  ok = true,
} = {}) {
  return db.appendAudit({
    event_id: audit.event_id || uuid(),
    event_type: ok ? 'channel.onboarding.first_smoke.completed' : 'channel.onboarding.first_smoke.failed',
    created_at_ms: nowMs(),
    severity: ok ? 'info' : 'warn',
    device_id: safeString(audit.device_id || 'channel_onboarding_first_smoke'),
    user_id: safeString(audit.user_id) || null,
    app_id: safeString(audit.app_id || 'channel_onboarding_first_smoke'),
    project_id: safeString(receipt?.project_id) || null,
    session_id: safeString(audit.session_id) || null,
    request_id: safeString(request_id) || null,
    capability: 'channel.onboarding.first_smoke.write',
    model_id: null,
    ok: !!ok,
    error_code: ok ? null : safeString(receipt?.deny_code || 'channel_onboarding_first_smoke_failed'),
    error_message: ok ? null : safeString(receipt?.detail || receipt?.deny_code || 'channel_onboarding_first_smoke_failed'),
    ext_json: JSON.stringify({
      schema_version: CHANNEL_ONBOARDING_FIRST_SMOKE_RECEIPT_SCHEMA,
      receipt_id: safeString(receipt?.receipt_id),
      ticket_id: safeString(receipt?.ticket_id),
      decision_id: safeString(receipt?.decision_id),
      provider: safeString(receipt?.provider),
      action_name: safeString(receipt?.action_name),
      status: safeString(receipt?.status),
      route_mode: safeString(receipt?.route_mode),
      deny_code: safeString(receipt?.deny_code),
      remediation_hint: safeString(receipt?.remediation_hint),
      project_id: safeString(receipt?.project_id),
      binding_id: safeString(receipt?.binding_id),
    }),
  });
}

function projectIdFromContext({
  gate = {},
  route = {},
} = {}) {
  if (safeString(route.scope_type) === 'project') return safeString(route.scope_id);
  if (safeString(gate.scope_type) === 'project') return safeString(gate.scope_id);
  return '';
}

function maxUpdatedAtMs(rows = []) {
  return (Array.isArray(rows) ? rows : []).reduce(
    (max, row) => Math.max(max, safeInt(row?.updated_at_ms, 0)),
    0
  );
}

function loadChannelRuntimeAccountsSnapshot(runtimeBaseDir = '') {
  const base = safeString(runtimeBaseDir);
  if (!base) {
    return {
      updated_at_ms: 0,
      rows: [],
    };
  }
  const filePath = path.join(base, 'channel_runtime_accounts_status.json');
  try {
    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const rows = Array.isArray(raw?.accounts)
      ? raw.accounts
      : (Array.isArray(raw?.items) ? raw.items : (Array.isArray(raw?.rows) ? raw.rows : []));
    return {
      updated_at_ms: safeInt(raw?.updated_at_ms, 0),
      rows: Array.isArray(rows) ? rows : [],
    };
  } catch {
    return {
      updated_at_ms: 0,
      rows: [],
    };
  }
}

function listActiveChannelBindingCountsByAccount(db) {
  if (!db || typeof db !== 'object' || !db.db || typeof db.db.prepare !== 'function') {
    return [];
  }
  try {
    return db.db.prepare(
      `SELECT provider, account_id, COUNT(*) AS active_binding_count, MAX(updated_at_ms) AS updated_at_ms
       FROM supervisor_operator_channel_bindings
       WHERE status = 'active'
       GROUP BY provider, account_id`
    ).all();
  } catch {
    return [];
  }
}

function buildHubChannelRuntimeStatusSnapshot({
  db,
  runtimeBaseDir = '',
} = {}) {
  const runtimeSnapshot = loadChannelRuntimeAccountsSnapshot(runtimeBaseDir);
  const merged = new Map();

  for (const raw of Array.isArray(runtimeSnapshot.rows) ? runtimeSnapshot.rows : []) {
    const provider = safeString(raw?.provider).toLowerCase();
    const account_id = safeString(raw?.account_id);
    const key = `${provider}|${account_id}`;
    if (!provider) continue;
    merged.set(key, {
      ...raw,
      provider,
      account_id,
      active_binding_count: safeInt(raw?.active_binding_count, 0),
      updated_at_ms: safeInt(raw?.updated_at_ms, 0),
    });
  }

  for (const raw of listActiveChannelBindingCountsByAccount(db)) {
    const provider = safeString(raw?.provider).toLowerCase();
    const account_id = safeString(raw?.account_id);
    const key = `${provider}|${account_id}`;
    if (!provider) continue;
    const existing = merged.get(key) || {
      provider,
      account_id,
      runtime_state: 'not_configured',
      updated_at_ms: 0,
    };
    merged.set(key, {
      ...existing,
      provider,
      account_id,
      active_binding_count: safeInt(raw?.active_binding_count, 0),
      updated_at_ms: Math.max(
        safeInt(existing.updated_at_ms, 0),
        safeInt(raw?.updated_at_ms, 0)
      ),
    });
  }

  const rows = Array.from(merged.values());
  const updated_at_ms = Math.max(
    safeInt(runtimeSnapshot.updated_at_ms, 0),
    maxUpdatedAtMs(rows),
    nowMs()
  );
  return buildChannelRuntimeStatusSnapshot(rows, { updated_at_ms });
}

function loadOperatorChannelProjectState(db, project_id = '') {
  const projectId = safeString(project_id);
  if (!db || !projectId) {
    return {
      project_id: '',
      root_project_id: '',
      lineage: null,
      dispatch: null,
      heartbeat: null,
      heartbeat_governance_snapshot: null,
      owner_identity: null,
    };
  }
  const lineage = typeof db._getProjectLineageRowRawByProjectId === 'function' && typeof db._parseProjectLineageRow === 'function'
    ? db._parseProjectLineageRow(db._getProjectLineageRowRawByProjectId(projectId))
    : null;
  const dispatch = typeof db._getProjectDispatchContextRowRawByProjectId === 'function' && typeof db._parseProjectDispatchContextRow === 'function'
    ? db._parseProjectDispatchContextRow(db._getProjectDispatchContextRowRawByProjectId(projectId))
    : null;
  const heartbeat = typeof db._getProjectHeartbeatRowRawByProjectId === 'function' && typeof db._parseProjectHeartbeatRow === 'function'
    ? db._parseProjectHeartbeatRow(db._getProjectHeartbeatRowRawByProjectId(projectId))
    : null;
  const heartbeat_governance_snapshot = buildProjectHeartbeatGovernanceSnapshot({
    db,
    device_id: safeString(lineage?.device_id || dispatch?.device_id || heartbeat?.device_id),
    user_id: safeString(lineage?.user_id || dispatch?.user_id || heartbeat?.user_id),
    app_id: safeString(lineage?.app_id || dispatch?.app_id || heartbeat?.app_id),
    project_id: projectId,
  });
  const owner_identity = lineage || dispatch || heartbeat || null;
  return {
    project_id: projectId,
    root_project_id: safeString(
      lineage?.root_project_id
      || dispatch?.root_project_id
      || heartbeat?.root_project_id
      || projectId
    ),
    lineage,
    dispatch,
    heartbeat,
    heartbeat_governance_snapshot,
    owner_identity,
  };
}

function buildLocalHubQueryResult({
  db,
  runtimeBaseDir = '',
  request_id = '',
  action_name = '',
  gate = {},
  route = {},
} = {}) {
  const actionName = safeString(action_name).toLowerCase();
  const project_id = projectIdFromContext({
    gate,
    route,
  });
  const projectState = loadOperatorChannelProjectState(db, project_id);
  const snapshot = buildHubChannelRuntimeStatusSnapshot({
    db,
    runtimeBaseDir,
  });
  const provider_status = Array.isArray(snapshot?.providers)
    ? snapshot.providers.find((row) => safeString(row?.provider) === safeString(route.provider))
    : null;
  const query = {
    action_name: actionName,
    project_id: safeString(projectState.project_id),
    root_project_id: safeString(projectState.root_project_id),
    provider_status: provider_status || null,
    dispatch: projectState.dispatch || null,
    heartbeat: projectState.heartbeat || null,
    heartbeat_governance_snapshot_json: projectState.heartbeat_governance_snapshot
      ? JSON.stringify(projectState.heartbeat_governance_snapshot)
      : '',
    queue: null,
  };

  if (actionName !== 'supervisor.queue.get') {
    return {
      ok: true,
      deny_code: '',
      detail: 'query_executed',
      query,
    };
  }

  const owner = projectState.owner_identity;
  if (!safeString(projectState.root_project_id) || !safeString(owner?.device_id) || !safeString(owner?.app_id)) {
    return {
      ok: false,
      deny_code: 'project_scope_missing',
      detail: 'queue view requires project scope',
      query,
    };
  }
  const queue = db.buildProjectDispatchPlan({
    request_id: safeString(request_id),
    device_id: safeString(owner.device_id),
    user_id: safeString(owner.user_id),
    app_id: safeString(owner.app_id),
    root_project_id: safeString(projectState.root_project_id),
    max_projects: 6,
  });
  query.queue = queue || null;
  if (!queue?.planned) {
    return {
      ok: false,
      deny_code: safeString(queue?.deny_code || 'queue_view_unavailable'),
      detail: 'queue view unavailable',
      query,
    };
  }
  return {
    ok: true,
    deny_code: '',
    detail: 'query_executed',
    query,
  };
}

function preferredFirstSmokeAction(allowed_actions = []) {
  const normalized = Array.isArray(allowed_actions)
    ? allowed_actions.map((item) => safeString(item).toLowerCase()).filter(Boolean)
    : [];
  const preferredOrder = [
    'supervisor.status.get',
    'supervisor.blockers.get',
    'supervisor.queue.get',
    'device.doctor.get',
    'device.permission_status.get',
  ];
  return preferredOrder.find((action) => normalized.includes(action)) || '';
}

function remediationHintForReceipt(receipt = {}) {
  const denyCode = safeString(receipt.deny_code);
  const routeMode = safeString(receipt.route_mode);
  if (denyCode === 'first_smoke_action_missing') {
    return 'Approve with supervisor.status.get in allowed_actions to enable the default onboarding smoke check.';
  }
  if (denyCode === 'first_smoke_action_not_supported') {
    return 'Use supervisor.status.get, supervisor.blockers.get, or supervisor.queue.get for the first smoke action.';
  }
  if (routeMode === 'xt_offline') {
    return 'Bring the preferred XT device online or clear the preferred device hint before retrying.';
  }
  if (routeMode === 'runner_not_ready') {
    return 'Bring the trusted runner online before retrying this onboarding smoke.';
  }
  if (denyCode === 'project_scope_missing') {
    return 'Bind the conversation to a concrete project scope before retrying supervisor.queue.get.';
  }
  if (denyCode === 'channel_binding_missing' || denyCode === 'identity_binding_missing') {
    return 'Retry after the auto-bind transaction has completed successfully.';
  }
  return '';
}

function upsertReceipt(db, receipt, {
  request_id = '',
  audit = {},
} = {}) {
  ensureDb(db);
  const now = nowMs();
  const normalized = {
    receipt_id: safeString(receipt.receipt_id) || uuid(),
    schema_version: CHANNEL_ONBOARDING_FIRST_SMOKE_RECEIPT_SCHEMA,
    ticket_id: safeString(receipt.ticket_id),
    decision_id: safeString(receipt.decision_id),
    provider: safeString(receipt.provider).toLowerCase(),
    action_name: safeString(receipt.action_name),
    status: safeString(receipt.status),
    route_mode: safeString(receipt.route_mode),
    deny_code: safeString(receipt.deny_code),
    detail: safeString(receipt.detail),
    remediation_hint: safeString(receipt.remediation_hint),
    project_id: safeString(receipt.project_id),
    binding_id: safeString(receipt.binding_id),
    ack_outbox_item_id: safeString(receipt.ack_outbox_item_id),
    smoke_outbox_item_id: safeString(receipt.smoke_outbox_item_id),
    result: safeObject(receipt.result),
    created_at_ms: safeInt(receipt.created_at_ms, now) || now,
    updated_at_ms: now,
    audit_ref: '',
  };
  const audit_ref = appendFirstSmokeAudit({
    db,
    receipt: normalized,
    request_id,
    audit,
    ok: !safeString(normalized.deny_code),
  });
  normalized.audit_ref = audit_ref;
  db.db.prepare(
    `INSERT INTO channel_onboarding_first_smoke_receipts(
       receipt_id, schema_version, ticket_id, decision_id, provider, action_name, status,
       route_mode, deny_code, detail, remediation_hint, project_id, binding_id,
       ack_outbox_item_id, smoke_outbox_item_id, result_json, created_at_ms, updated_at_ms, audit_ref
     ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
     ON CONFLICT(ticket_id) DO UPDATE SET
       decision_id = excluded.decision_id,
       provider = excluded.provider,
       action_name = excluded.action_name,
       status = excluded.status,
       route_mode = excluded.route_mode,
       deny_code = excluded.deny_code,
       detail = excluded.detail,
       remediation_hint = excluded.remediation_hint,
       project_id = excluded.project_id,
       binding_id = excluded.binding_id,
       ack_outbox_item_id = excluded.ack_outbox_item_id,
       smoke_outbox_item_id = excluded.smoke_outbox_item_id,
       result_json = excluded.result_json,
       updated_at_ms = excluded.updated_at_ms,
       audit_ref = excluded.audit_ref`
  ).run(
    normalized.receipt_id,
    normalized.schema_version,
    normalized.ticket_id,
    normalized.decision_id,
    normalized.provider,
    normalized.action_name,
    normalized.status,
    normalized.route_mode,
    normalized.deny_code,
    normalized.detail,
    normalized.remediation_hint,
    normalized.project_id,
    normalized.binding_id,
    normalized.ack_outbox_item_id,
    normalized.smoke_outbox_item_id,
    JSON.stringify(normalized.result),
    normalized.created_at_ms,
    normalized.updated_at_ms,
    normalized.audit_ref
  );
  return getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
    ticket_id: normalized.ticket_id,
  });
}

export function getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
  ticket_id = '',
} = {}) {
  ensureDb(db);
  const row = db.db
    .prepare(
      `SELECT *
       FROM channel_onboarding_first_smoke_receipts
       WHERE ticket_id = ?
       LIMIT 1`
    )
    .get(safeString(ticket_id));
  return parseReceiptRow(row);
}

export function attachChannelOnboardingFirstSmokeOutboxRefs(db, {
  ticket_id = '',
  ack_outbox_item_id = '',
  smoke_outbox_item_id = '',
  request_id = '',
  audit = {},
} = {}) {
  const existing = getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
    ticket_id,
  });
  if (!existing) return null;
  return upsertReceipt(db, {
    ...existing,
    ack_outbox_item_id: safeString(ack_outbox_item_id || existing.ack_outbox_item_id),
    smoke_outbox_item_id: safeString(smoke_outbox_item_id || existing.smoke_outbox_item_id),
  }, {
    request_id,
    audit,
  });
}

export function runChannelOnboardingFirstSmoke(db, {
  ticket = {},
  decision = {},
  auto_bind_receipt = null,
  request_id = '',
  runtimeBaseDir = '',
  audit = {},
} = {}) {
  ensureDb(db);
  const action_name = preferredFirstSmokeAction(decision.allowed_actions || []);
  const baseReceipt = {
    receipt_id: uuid(),
    ticket_id: safeString(ticket.ticket_id),
    decision_id: safeString(decision.decision_id),
    provider: safeString(ticket.provider),
    action_name,
    status: '',
    route_mode: '',
    deny_code: '',
    detail: '',
    remediation_hint: '',
    project_id: safeString(safeString(decision.scope_type) === 'project' ? decision.scope_id : ''),
    binding_id: safeString(auto_bind_receipt?.channel_binding_id),
    ack_outbox_item_id: '',
    smoke_outbox_item_id: '',
    result: {},
    created_at_ms: nowMs(),
    updated_at_ms: nowMs(),
    audit_ref: '',
  };

  if (!action_name) {
    return {
      ok: false,
      result: null,
      receipt: upsertReceipt(db, {
        ...baseReceipt,
        status: 'action_unavailable',
        deny_code: 'first_smoke_action_missing',
        detail: 'no safe first smoke action available',
        remediation_hint: remediationHintForReceipt({
          deny_code: 'first_smoke_action_missing',
        }),
      }, {
        request_id,
        audit,
      }),
    };
  }

  const command = {
    action_name,
    binding_id: safeString(auto_bind_receipt?.channel_binding_id),
    scope_type: safeString(decision.scope_type),
    scope_id: safeString(decision.scope_id),
    route_project_id: safeString(safeString(decision.scope_type) === 'project' ? decision.scope_id : ''),
    actor: {
      provider: safeString(ticket.provider),
      external_user_id: safeString(ticket.external_user_id),
      external_tenant_id: safeString(ticket.external_tenant_id),
    },
    channel: {
      provider: safeString(ticket.provider),
      account_id: safeString(ticket.account_id),
      conversation_id: safeString(ticket.conversation_id),
      thread_key: safeString(ticket.thread_key),
      channel_scope: safeString(ticket.ingress_surface || 'group'),
    },
    audit_ref: `channel_onboarding_first_smoke:${safeString(ticket.ticket_id || decision.decision_id || 'unknown') || 'unknown'}`,
  };

  const gate = evaluateChannelCommandGateWithAudit({
    db,
    actor: command.actor,
    channel: command.channel,
    action: {
      binding_id: command.binding_id,
      action_name,
      scope_type: command.scope_type,
      scope_id: command.scope_id,
      pending_grant: null,
    },
    client: {
      device_id: safeString(audit.device_id || 'channel_onboarding_first_smoke'),
      user_id: safeString(audit.user_id),
      app_id: safeString(audit.app_id || 'channel_onboarding_first_smoke'),
      project_id: command.route_project_id,
    },
    request_id,
  });

  if (gate.allowed === false) {
    const result = {
      request_id,
      command,
      gate,
      route: null,
      dispatch: {
        kind: 'deny',
      },
      execution: null,
    };
    const receipt = upsertReceipt(db, {
      ...baseReceipt,
      action_name,
      status: 'gate_denied',
      route_mode: safeString(gate.route_mode || ''),
      deny_code: safeString(gate.deny_code || 'channel_command_denied'),
      detail: safeString(gate.detail || gate.deny_code || 'channel_command_denied'),
      result,
      remediation_hint: remediationHintForReceipt({
        deny_code: safeString(gate.deny_code),
        route_mode: safeString(gate.route_mode),
      }),
    }, {
      request_id,
      audit,
    });
    return {
      ok: false,
      result,
      receipt,
    };
  }

  const resolved = resolveSupervisorChannelRoute({
    db,
    binding_id: safeString(gate.binding_id || command.binding_id),
    route_context: {
      ...command.channel,
      project_id: command.route_project_id,
      root_project_id: '',
    },
    action_name,
    runtimeBaseDir,
  });
  let route = resolved;
  if (resolved && safeString(resolved.scope_id)) {
    const persisted = upsertSupervisorChannelSessionRoute(db, {
      route: resolved,
      request_id,
      audit: {
        ...audit,
        app_id: safeString(audit.app_id || 'channel_onboarding_first_smoke'),
      },
    });
    if (persisted.ok && persisted.route) {
      route = {
        ...(persisted.route || {}),
        selected_by: safeString(resolved.selected_by),
        action_name: safeString(resolved.action_name),
      };
    }
  }

  const route_mode = safeString(route?.route_mode || gate.route_mode || '');
  if (!SUPERVISOR_QUERY_ACTIONS.has(action_name)) {
    const dispatchKind = route_mode === 'runner_not_ready' || route_mode === 'xt_offline'
      ? 'route_blocked'
      : (route_mode === 'hub_to_runner' ? 'runner_command' : 'route_blocked');
    const result = {
      request_id,
      command,
      gate,
      route,
      dispatch: {
        kind: dispatchKind,
      },
      execution: null,
    };
    const receipt = upsertReceipt(db, {
      ...baseReceipt,
      action_name,
      status: dispatchKind === 'runner_command' ? 'runner_routed' : 'route_blocked',
      route_mode,
      deny_code: dispatchKind === 'runner_command'
        ? 'first_smoke_action_not_supported'
        : safeString(route?.deny_code || 'first_smoke_action_not_supported'),
      detail: dispatchKind === 'runner_command'
        ? 'first smoke runner action execution not supported yet'
        : safeString(route?.deny_code || 'first smoke route blocked'),
      result,
      remediation_hint: remediationHintForReceipt({
        deny_code: dispatchKind === 'runner_command' ? 'first_smoke_action_not_supported' : safeString(route?.deny_code),
        route_mode,
      }),
    }, {
      request_id,
      audit,
    });
    return {
      ok: dispatchKind === 'runner_command',
      result,
      receipt,
    };
  }

  if (route_mode !== 'hub_only_status') {
    const result = {
      request_id,
      command,
      gate,
      route,
      dispatch: {
        kind: route_mode === 'xt_offline' || route_mode === 'runner_not_ready' ? 'route_blocked' : 'deny',
      },
      execution: {
        ok: false,
        deny_code: safeString(route?.deny_code || 'hub_execution_requires_hub_only_route'),
        detail: route_mode === 'xt_offline' || route_mode === 'runner_not_ready'
          ? 'hub execution blocked by route'
          : 'hub execution requires hub-only route',
        route,
        query: null,
        projection: null,
        grant_action: null,
        xt_command: null,
      },
    };
    const receipt = upsertReceipt(db, {
      ...baseReceipt,
      action_name,
      status: 'route_blocked',
      route_mode,
      deny_code: safeString(route?.deny_code || 'hub_execution_requires_hub_only_route'),
      detail: route_mode === 'xt_offline' || route_mode === 'runner_not_ready'
        ? 'hub execution blocked by route'
        : 'hub execution requires hub-only route',
      result,
      remediation_hint: remediationHintForReceipt({
        deny_code: safeString(route?.deny_code),
        route_mode,
      }),
    }, {
      request_id,
      audit,
    });
    return {
      ok: false,
      result,
      receipt,
    };
  }

  const queryResult = buildLocalHubQueryResult({
    db,
    runtimeBaseDir,
    request_id,
    action_name,
    gate,
    route,
  });
  const result = {
    request_id,
    command,
    gate,
    route,
    dispatch: {
      kind: 'hub_query',
    },
    execution: {
      ok: !!queryResult.ok,
      deny_code: safeString(queryResult.deny_code),
      detail: safeString(queryResult.detail),
      route,
      query: queryResult.query || null,
      projection: null,
      grant_action: null,
      xt_command: null,
    },
  };
  const receipt = upsertReceipt(db, {
    ...baseReceipt,
    action_name,
    status: queryResult.ok ? 'query_executed' : 'query_failed',
    route_mode,
    deny_code: safeString(queryResult.deny_code),
    detail: safeString(queryResult.detail || (queryResult.ok ? 'query_executed' : 'query_failed')),
    result,
    remediation_hint: remediationHintForReceipt({
      deny_code: safeString(queryResult.deny_code),
      route_mode,
    }),
  }, {
    request_id,
    audit,
  });
  return {
    ok: !!queryResult.ok,
    result,
    receipt,
  };
}
