function safeString(input) {
  return String(input ?? '').trim();
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function buildLines(lines = []) {
  return safeArray(lines)
    .map((line) => safeString(line))
    .filter(Boolean)
    .join('\n');
}

function normalizeDeliveryContext(input = {}) {
  const src = safeObject(input);
  const conversationId = safeString(src.conversation_id || src.wa_id || src.to);
  if (!conversationId) {
    return {
      ok: false,
      deny_code: 'conversation_id_missing',
    };
  }
  return {
    ok: true,
    context: {
      provider: 'whatsapp_cloud_api',
      account_id: safeString(src.account_id),
      conversation_id: conversationId,
      thread_key: safeString(src.thread_key),
    },
  };
}

export function buildWhatsAppCloudSendMessagePayload({
  delivery_context = {},
  text = '',
} = {}) {
  const normalized = normalizeDeliveryContext(delivery_context);
  if (!normalized.ok) return normalized;
  const bodyText = safeString(text);
  if (!bodyText) {
    return {
      ok: false,
      deny_code: 'text_missing',
    };
  }
  return {
    ok: true,
    delivery_context: normalized.context,
    payload: {
      to: normalized.context.conversation_id,
      text: bodyText,
      reply_to_message_id: safeString(normalized.context.thread_key),
    },
  };
}

export function buildWhatsAppCloudApprovalMessage({
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
  const bindingId = safeString(binding_id);
  const scopeType = safeString(scope_type);
  const scopeId = safeString(scope_id);
  const grantRequestId = safeString(grant_request_id);
  const projectId = safeString(project_id || (scopeType === 'project' ? scopeId : ''));
  if (!auditRef) {
    return {
      ok: false,
      deny_code: 'audit_ref_missing',
    };
  }
  if (!bindingId) {
    return {
      ok: false,
      deny_code: 'binding_id_missing',
    };
  }
  if (!scopeType || !scopeId) {
    return {
      ok: false,
      deny_code: 'scope_missing',
    };
  }
  if (!grantRequestId) {
    return {
      ok: false,
      deny_code: 'grant_request_id_missing',
    };
  }

  return buildWhatsAppCloudSendMessagePayload({
    delivery_context,
    text: buildLines([
      safeString(title) || 'Approval Required',
      projectId ? `Project: ${projectId}` : '',
      `Grant: ${grantRequestId}`,
      `Audit: ${auditRef}`,
      `Binding: ${bindingId}`,
      `Status: ${safeString(pending_grant_status || 'pending') || 'pending'}`,
      ...safeArray(summary_lines),
      `Approve: grant approve ${grantRequestId}${projectId ? ` project ${projectId}` : ''}`,
      `Reject: grant reject ${grantRequestId}${projectId ? ` project ${projectId}` : ''} reason <why>`,
    ]),
  });
}

export function buildWhatsAppCloudSummaryMessage({
  delivery_context = {},
  title = 'Supervisor Summary',
  status = '',
  project_id = '',
  lines = [],
  audit_ref = '',
} = {}) {
  const auditRef = safeString(audit_ref);
  if (!auditRef) {
    return {
      ok: false,
      deny_code: 'audit_ref_missing',
    };
  }
  return buildWhatsAppCloudSendMessagePayload({
    delivery_context,
    text: buildLines([
      safeString(title) || 'Supervisor Summary',
      safeString(status) ? `Status: ${safeString(status)}` : '',
      safeString(project_id) ? `Project: ${safeString(project_id)}` : '',
      ...safeArray(lines),
      `Audit: ${auditRef}`,
    ]),
  });
}
