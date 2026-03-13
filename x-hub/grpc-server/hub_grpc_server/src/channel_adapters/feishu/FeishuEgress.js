import { normalizeChannelDeliveryContext } from '../../channel_delivery_context.js';

function safeString(input) {
  return String(input ?? '').trim();
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

function normalizeFeishuDeliveryContext(input = {}) {
  const raw = safeObject(input);
  const rawProvider = safeString(raw.provider || raw.channel || raw.provider_id);
  if (rawProvider && rawProvider.toLowerCase() !== 'feishu') {
    return {
      ok: false,
      deny_code: 'provider_mismatch',
    };
  }
  const context = normalizeChannelDeliveryContext({
    provider: 'feishu',
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
      provider: 'feishu',
      account_id: safeString(context?.account_id),
      conversation_id: safeString(context?.conversation_id),
      thread_key: safeString(context?.thread_key),
    },
  };
}

function buildBulletLines(lines = []) {
  const rows = safeStringArray(lines);
  if (!rows.length) return '';
  return rows.map((line) => `- ${line}`).join('\n');
}

function buildFieldsMarkdown(fields = []) {
  const items = Array.isArray(fields) ? fields : [];
  const lines = [];
  for (const field of items) {
    const row = safeObject(field);
    const label = safeString(row.label);
    const value = safeString(row.value);
    if (!label || !value) continue;
    lines.push(`**${label}**: ${value}`);
  }
  return lines.join('\n');
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
  return {
    audit_ref: safeString(audit_ref),
    binding_id: safeString(binding_id),
    scope_type: safeString(scope_type),
    scope_id: safeString(scope_id),
    project_id: safeString(project_id),
    pending_grant_request_id: safeString(grant_request_id),
    pending_grant_project_id: safeString(project_id),
    pending_grant_status: safeString(pending_grant_status || 'pending') || 'pending',
  };
}

function buildMarkdownCard({
  title = '',
  markdown = '',
  actions = [],
} = {}) {
  const elements = [];
  const md = safeString(markdown);
  if (md) {
    elements.push({
      tag: 'markdown',
      content: md,
    });
  }
  if (Array.isArray(actions) && actions.length) {
    elements.push({
      tag: 'action',
      actions,
    });
  }
  return {
    schema: '2.0',
    config: {
      wide_screen_mode: true,
    },
    header: {
      title: {
        tag: 'plain_text',
        content: safeString(title) || 'Supervisor Message',
      },
      template: 'blue',
    },
    body: {
      elements,
    },
  };
}

export function buildFeishuSendMessagePayload({
  delivery_context = {},
  text = '',
  card = null,
  reply_in_thread = true,
} = {}) {
  const normalized = normalizeFeishuDeliveryContext(delivery_context);
  if (!normalized.ok) return normalized;
  const threadKey = safeString(normalized.context.thread_key);
  const payload = {
    receive_id: normalized.context.conversation_id,
    receive_id_type: 'chat_id',
    reply_to_message_id: threadKey,
    reply_in_thread: !!threadKey && reply_in_thread === true,
    msg_type: card ? 'interactive' : 'text',
    content: card
      ? JSON.stringify(card)
      : JSON.stringify({ text: safeString(text) }),
  };
  if (!card && !safeString(text)) {
    return {
      ok: false,
      deny_code: 'text_missing',
    };
  }
  return {
    ok: true,
    delivery_context: normalized.context,
    payload,
  };
}

export function buildFeishuApprovalCard({
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
  const markdown = [
    buildFieldsMarkdown([
      projectId ? { label: 'Project', value: projectId } : null,
      { label: 'Grant', value: grantRequestId },
      { label: 'Audit', value: auditRef },
    ]),
    buildBulletLines(summary_lines),
  ].filter(Boolean).join('\n\n');
  const sharedValue = approvalActionValue({
    audit_ref: auditRef,
    binding_id: bindingId,
    scope_type: scopeType,
    scope_id: scopeId,
    project_id: projectId,
    grant_request_id: grantRequestId,
    pending_grant_status,
  });

  const card = buildMarkdownCard({
    title,
    markdown: markdown || 'Review the pending grant request and choose an explicit action.',
    actions: [
      {
        tag: 'button',
        type: 'primary',
        text: {
          tag: 'plain_text',
          content: 'Approve',
        },
        action_id: 'xt.grant.approve',
        value: sharedValue,
      },
      {
        tag: 'button',
        type: 'danger',
        text: {
          tag: 'plain_text',
          content: 'Reject',
        },
        action_id: 'xt.grant.reject',
        value: sharedValue,
      },
    ],
  });

  return buildFeishuSendMessagePayload({
    delivery_context,
    card,
    reply_in_thread: true,
  });
}

export function buildFeishuSummaryMessage({
  delivery_context = {},
  title = 'Supervisor Summary',
  status = '',
  project_id = '',
  lines = [],
  fields = [],
  audit_ref = '',
} = {}) {
  const auditRef = safeString(audit_ref);
  if (!auditRef) {
    return {
      ok: false,
      deny_code: 'audit_ref_missing',
    };
  }
  const projectId = safeString(project_id);
  const markdown = [
    buildFieldsMarkdown([
      projectId ? { label: 'Project', value: projectId } : null,
      safeString(status) ? { label: 'Status', value: safeString(status) } : null,
      ...((Array.isArray(fields) ? fields : [])),
      { label: 'Audit', value: auditRef },
    ]),
    buildBulletLines(lines),
  ].filter(Boolean).join('\n\n');

  return buildFeishuSendMessagePayload({
    delivery_context,
    card: buildMarkdownCard({
      title,
      markdown: markdown || '**Audit**: ' + auditRef,
    }),
    reply_in_thread: true,
  });
}
