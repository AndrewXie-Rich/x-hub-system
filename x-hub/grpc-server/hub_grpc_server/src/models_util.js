export function toProtoModelKind(kindText) {
  const k = String(kindText || '').toLowerCase();
  if (k === 'local_offline') return 'MODEL_KIND_LOCAL_OFFLINE';
  if (k === 'paid_online') return 'MODEL_KIND_PAID_ONLINE';
  return 'MODEL_KIND_UNSPECIFIED';
}

export function toProtoModelVisibility(requiresGrant) {
  return requiresGrant ? 'MODEL_VISIBILITY_REQUESTABLE' : 'MODEL_VISIBILITY_AVAILABLE';
}

export function makeProtoModelInfo(row) {
  if (!row) return null;
  const requires_grant = !!Number(row.requires_grant || 0);
  return {
    model_id: String(row.model_id || ''),
    name: String(row.name || ''),
    kind: toProtoModelKind(row.kind),
    backend: String(row.backend || ''),
    context_length: Number(row.context_length || 0),
    visibility: toProtoModelVisibility(requires_grant),
    requires_grant,
    updated_at_ms: Number(row.updated_at_ms || 0),
  };
}

