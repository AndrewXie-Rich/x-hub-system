import { normalizeChannelDeliveryContext } from '../../channel_delivery_context.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeBool(input, fallback = false) {
  if (typeof input === 'boolean') return input;
  if (input == null || input === '') return fallback;
  const text = safeString(input).toLowerCase();
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') return true;
  if (text === '0' || text === 'false' || text === 'no' || text === 'off') return false;
  return fallback;
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function safeStringArray(input) {
  const rows = Array.isArray(input) ? input : [];
  const out = [];
  for (const raw of rows) {
    const text = safeString(raw);
    if (!text) continue;
    out.push(text);
  }
  return out;
}

function normalizeSlackDeliveryContext(input = {}) {
  const raw = safeObject(input);
  const rawProvider = safeString(raw.provider || raw.channel || raw.provider_id);
  if (rawProvider && rawProvider.toLowerCase() !== 'slack') {
    return {
      ok: false,
      deny_code: 'provider_mismatch',
    };
  }
  const context = normalizeChannelDeliveryContext({
    provider: 'slack',
    ...raw,
  });
  if (!safeString(context?.conversation_id)) {
    return {
      ok: false,
      deny_code: 'conversation_id_missing',
    };
  }
  return {
    ok: true,
    context: {
      provider: 'slack',
      account_id: safeString(context?.account_id),
      conversation_id: safeString(context?.conversation_id),
      thread_key: safeString(context?.thread_key),
    },
  };
}

function normalizeMetadata(input = {}) {
  const obj = safeObject(input);
  const event_type = safeString(obj.event_type || 'xt_operator_message') || 'xt_operator_message';
  const event_payload = safeObject(obj.event_payload);
  return {
    event_type,
    event_payload,
  };
}

function buildMrkdwnSection(text) {
  const value = safeString(text);
  if (!value) return null;
  return {
    type: 'section',
    text: {
      type: 'mrkdwn',
      text: value,
    },
  };
}

function buildContextBlock(lines = []) {
  const elements = safeStringArray(lines).map((line) => ({
    type: 'mrkdwn',
    text: line,
  }));
  if (!elements.length) return null;
  return {
    type: 'context',
    elements,
  };
}

function buildFieldsBlock(fields = []) {
  const items = Array.isArray(fields) ? fields : [];
  const rendered = [];
  for (const field of items) {
    const row = safeObject(field);
    const label = safeString(row.label);
    const value = safeString(row.value);
    if (!label || !value) continue;
    rendered.push({
      type: 'mrkdwn',
      text: `*${label}*\n${value}`,
    });
    if (rendered.length >= 10) break;
  }
  if (!rendered.length) return null;
  return {
    type: 'section',
    fields: rendered,
  };
}

function buildBulletLines(lines = []) {
  const rows = safeStringArray(lines);
  if (!rows.length) return '';
  return rows.map((line) => `• ${line}`).join('\n');
}

function pushBlock(blocks, block) {
  if (block && typeof block === 'object') blocks.push(block);
}

export function buildSlackPostMessagePayload({
  delivery_context = {},
  text = '',
  blocks = [],
  metadata = null,
  reply_broadcast = false,
} = {}) {
  const normalized = normalizeSlackDeliveryContext(delivery_context);
  if (!normalized.ok) return normalized;
  const fallback = safeString(text);
  if (!fallback) {
    return {
      ok: false,
      deny_code: 'text_missing',
    };
  }
  const payload = {
    channel: normalized.context.conversation_id,
    text: fallback,
    unfurl_links: false,
    unfurl_media: false,
  };
  const threadKey = safeString(normalized.context.thread_key);
  if (threadKey) payload.thread_ts = threadKey;
  if (threadKey && safeBool(reply_broadcast, false)) payload.reply_broadcast = true;
  if (Array.isArray(blocks) && blocks.length) payload.blocks = blocks;
  if (metadata) payload.metadata = normalizeMetadata(metadata);
  return {
    ok: true,
    delivery_context: normalized.context,
    payload,
  };
}

function approvalActionValue({
  audit_ref,
  binding_id,
  scope_type,
  scope_id,
  project_id,
  grant_request_id,
  pending_grant_status = 'pending',
} = {}) {
  return JSON.stringify({
    audit_ref: safeString(audit_ref),
    binding_id: safeString(binding_id),
    scope_type: safeString(scope_type),
    scope_id: safeString(scope_id),
    project_id: safeString(project_id),
    pending_grant_request_id: safeString(grant_request_id),
    pending_grant_project_id: safeString(project_id),
    pending_grant_status: safeString(pending_grant_status || 'pending') || 'pending',
  });
}

export function buildSlackApprovalCard({
  delivery_context = {},
  title = 'Approval Required',
  summary_lines = [],
  audit_ref = '',
  binding_id = '',
  scope_type = '',
  scope_id = '',
  project_id = '',
  grant_request_id = '',
  pending_grant_status = 'pending',
} = {}) {
  const auditRef = safeString(audit_ref);
  if (!auditRef) {
    return {
      ok: false,
      deny_code: 'audit_ref_missing',
    };
  }
  const bindingId = safeString(binding_id);
  if (!bindingId) {
    return {
      ok: false,
      deny_code: 'binding_id_missing',
    };
  }
  const scopeType = safeString(scope_type);
  const scopeId = safeString(scope_id);
  if (!scopeType || !scopeId) {
    return {
      ok: false,
      deny_code: 'scope_missing',
    };
  }
  const grantRequestId = safeString(grant_request_id);
  if (!grantRequestId) {
    return {
      ok: false,
      deny_code: 'grant_request_id_missing',
    };
  }
  const projectId = safeString(project_id || (scopeType === 'project' ? scopeId : ''));
  const details = buildBulletLines(summary_lines);
  const contextLines = [
    projectId ? `*Project*: ${projectId}` : '',
    `*Grant*: ${grantRequestId}`,
    `*Audit*: ${auditRef}`,
  ];
  const actionValue = {
    audit_ref: auditRef,
    binding_id: bindingId,
    scope_type: scopeType,
    scope_id: scopeId,
    project_id: projectId,
    grant_request_id: grantRequestId,
    pending_grant_status,
  };
  const blocks = [];
  pushBlock(blocks, buildMrkdwnSection(`*${safeString(title) || 'Approval Required'}*`));
  pushBlock(blocks, buildMrkdwnSection(details || 'Review the pending grant request and choose an explicit action.'));
  pushBlock(blocks, buildContextBlock(contextLines));
  blocks.push({
    type: 'actions',
    block_id: `xt_approval_${grantRequestId.slice(0, 48)}`,
    elements: [
      {
        type: 'button',
        action_id: 'xt.grant.approve',
        text: {
          type: 'plain_text',
          text: 'Approve',
        },
        style: 'primary',
        value: approvalActionValue(actionValue),
      },
      {
        type: 'button',
        action_id: 'xt.grant.reject',
        text: {
          type: 'plain_text',
          text: 'Reject',
        },
        style: 'danger',
        value: approvalActionValue(actionValue),
      },
    ],
  });

  return buildSlackPostMessagePayload({
    delivery_context,
    text: [
      safeString(title) || 'Approval Required',
      projectId ? `project=${projectId}` : '',
      `grant=${grantRequestId}`,
      'action=approve_or_reject',
    ].filter(Boolean).join(' | '),
    blocks,
    metadata: {
      event_type: 'xt_operator_approval',
      event_payload: {
        delivery_class: 'approval_card',
        audit_ref: auditRef,
        binding_id: bindingId,
        scope_type: scopeType,
        scope_id: scopeId,
        project_id: projectId,
        grant_request_id: grantRequestId,
        pending_grant_request_id: grantRequestId,
        pending_grant_project_id: projectId,
        pending_grant_status: safeString(pending_grant_status || 'pending') || 'pending',
      },
    },
  });
}

export function buildSlackSummaryMessage({
  delivery_context = {},
  title = 'Supervisor Summary',
  status = '',
  project_id = '',
  lines = [],
  fields = [],
  audit_ref = '',
  reply_broadcast = false,
} = {}) {
  const auditRef = safeString(audit_ref);
  if (!auditRef) {
    return {
      ok: false,
      deny_code: 'audit_ref_missing',
    };
  }
  const projectId = safeString(project_id);
  const statusLine = safeString(status);
  const detailLines = buildBulletLines(lines);
  const blocks = [];
  pushBlock(blocks, buildMrkdwnSection(`*${safeString(title) || 'Supervisor Summary'}*`));
  pushBlock(blocks, buildFieldsBlock([
    projectId ? { label: 'Project', value: projectId } : null,
    statusLine ? { label: 'Status', value: statusLine } : null,
    ...((Array.isArray(fields) ? fields : [])),
  ]));
  pushBlock(blocks, buildMrkdwnSection(detailLines));
  pushBlock(blocks, buildContextBlock([
    `*Audit*: ${auditRef}`,
    statusLine ? `*State*: ${statusLine}` : '',
  ]));

  return buildSlackPostMessagePayload({
    delivery_context,
    text: [
      safeString(title) || 'Supervisor Summary',
      projectId ? `project=${projectId}` : '',
      statusLine ? `status=${statusLine}` : '',
      ...safeStringArray(lines),
    ].filter(Boolean).join(' | '),
    blocks,
    metadata: {
      event_type: 'xt_operator_summary',
      event_payload: {
        delivery_class: 'summary',
        audit_ref: auditRef,
        project_id: projectId,
        status: statusLine,
      },
    },
    reply_broadcast,
  });
}
