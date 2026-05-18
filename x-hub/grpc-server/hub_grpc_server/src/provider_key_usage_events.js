import {
  reportKeyError,
  reportKeyUsage,
} from './provider_key_store.js';

function safeString(value) {
  return String(value ?? '').trim();
}

function safeInt(value, fallback = 0) {
  const number = Number(value || 0);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

function normalizedToken(value) {
  return safeString(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function normalizedOutcome(value) {
  switch (normalizedToken(value)) {
    case 'success':
      return 'success';
    case 'auth_error':
      return 'auth_error';
    case 'quota_error':
      return 'quota_error';
    case 'network_error':
      return 'network_error';
    case 'provider_error':
      return 'provider_error';
    case 'config_error':
      return 'config_error';
    default:
      return '';
  }
}

function inferredReasonCode(rawReasonCode, statusMessage, httpStatus) {
  const explicitReason = normalizedToken(rawReasonCode);
  if (explicitReason && !/^\d{3}$/.test(explicitReason)) {
    return explicitReason;
  }

  const message = safeString(statusMessage).toLowerCase();
  if (message.includes('api.responses.write')
      || message.includes('responses.write')
      || message.includes('missing scope')
      || message.includes('缺少生成 scope')) {
    return 'missing_scope';
  }
  if (message.includes('token_expired')
      || message.includes('token has expired')
      || message.includes('authentication token has expired')
      || message.includes('token has expired. please try signing in again')) {
    return 'token_expired';
  }
  if (message.includes('invalid api key')
      || message.includes('incorrect api key')
      || message.includes('authentication_failed')) {
    return 'invalid_api_key';
  }
  if (message.includes('no api key available')
      || message.includes('api key is empty')
      || message.includes('auth_missing')) {
    return 'auth_missing';
  }
  if (message.includes('input must be a list')) {
    return 'invalid_request_shape';
  }
  if (message.includes('invalid base url')) {
    return 'invalid_base_url';
  }
  if (message.includes('model_not_found')
      || message.includes('no available channel for model')
      || message.includes('model unsupported')
      || message.includes('model_unsupported')) {
    return 'model_not_supported';
  }
  if (message.includes('insufficient_quota')
      || (message.includes('quota') && message.includes('exceeded'))
      || message.includes('额度已用尽')) {
    return 'quota_exceeded';
  }
  if (message.includes('rate limit')
      || message.includes('too many requests')
      || message.includes('rate_limited')) {
    return 'rate_limited';
  }
  if (message.includes('timed out')
      || message.includes('time-out')
      || message.includes('gateway time-out')) {
    return 'provider_timeout';
  }
  if (message.includes('network unreachable')
      || message.includes('network is unreachable')
      || message.includes('could not resolve')
      || message.includes('dns')
      || message.includes('fetch_failed')
      || message.includes('ehostunreach')
      || message.includes('enotfound')
      || message.includes('econnrefused')
      || message.includes('econnreset')) {
    return 'network_unreachable';
  }

  const status = safeInt(httpStatus, 0);
  if (status === 401 || status === 403) return 'auth_failed';
  if (status === 402 || status === 429) return 'quota_exceeded';
  if (status === 408 || status === 504) return 'provider_timeout';
  if (status === 404) return 'model_not_supported';
  if (status === 400) return 'invalid_request';
  if (status > 0) return `http_${status}`;
  if (/^\d{3}$/.test(safeString(rawReasonCode))) return `http_${safeString(rawReasonCode)}`;
  return explicitReason || 'provider_error';
}

function inferredOutcome(rawOutcome, reasonCode, httpStatus, statusMessage) {
  const explicitOutcome = normalizedOutcome(rawOutcome);
  if (explicitOutcome) return explicitOutcome;

  const reason = normalizedToken(reasonCode);
  const message = safeString(statusMessage).toLowerCase();
  const status = safeInt(httpStatus, 0);

  if (
    ['missing_scope', 'token_expired', 'invalid_api_key', 'auth_failed'].includes(reason)
    || status === 401
    || status === 403
  ) {
    return 'auth_error';
  }
  if (
    ['quota_exceeded', 'rate_limited'].includes(reason)
    || status === 402
    || status === 429
  ) {
    return 'quota_error';
  }
  if (
    ['network_unreachable', 'provider_timeout'].includes(reason)
    || status === 408
    || status === 504
    || message.includes('timed out')
    || message.includes('network unreachable')
    || message.includes('fetch_failed')
  ) {
    return 'network_error';
  }
  if (
    ['auth_missing', 'invalid_base_url', 'invalid_request_shape', 'invalid_request'].includes(reason)
    || (status === 400 && reason === 'invalid_request')
  ) {
    return 'config_error';
  }
  return 'provider_error';
}

export function normalizeProviderKeyRuntimeEvent(rawEvent) {
  const accountKey = safeString(rawEvent?.account_key || rawEvent?.accountKey);
  const provider = safeString(rawEvent?.provider);
  const modelId = safeString(rawEvent?.model_id || rawEvent?.modelId);
  const httpStatus = safeInt(rawEvent?.http_status || rawEvent?.httpStatus, 0);
  const statusMessage = safeString(
    rawEvent?.status_message
    || rawEvent?.statusMessage
    || rawEvent?.message
    || rawEvent?.detail
  );
  const reasonCode = inferredReasonCode(
    rawEvent?.reason_code || rawEvent?.reasonCode || rawEvent?.error_code || rawEvent?.errorCode,
    statusMessage,
    httpStatus
  );
  const outcome = inferredOutcome(rawEvent?.outcome, reasonCode, httpStatus, statusMessage);

  return {
    schema_version: 'provider_key_runtime_event.v1',
    account_key: accountKey,
    provider,
    model_id: modelId,
    outcome,
    http_status: httpStatus,
    reason_code: reasonCode,
    status_message: statusMessage,
    tokens_used: safeInt(rawEvent?.tokens_used || rawEvent?.tokensUsed, 0),
    cost_usd: Number(rawEvent?.cost_usd || rawEvent?.costUsd || 0),
    latency_ms: safeInt(rawEvent?.latency_ms || rawEvent?.latencyMs, 0),
    occurred_at_ms: safeInt(rawEvent?.occurred_at_ms || rawEvent?.occurredAtMs, 0),
    next_retry_at_ms: safeInt(rawEvent?.next_retry_at_ms || rawEvent?.nextRetryAtMs, 0),
    retry_at_source: safeString(rawEvent?.retry_at_source || rawEvent?.retryAtSource),
  };
}

export function recordProviderKeyRuntimeEvent(runtimeBaseDir, rawEvent) {
  const event = normalizeProviderKeyRuntimeEvent(rawEvent);
  if (!event.account_key) {
    return {
      ok: false,
      error: 'missing_account_key',
      event,
    };
  }

  if (event.outcome === 'success') {
    const result = reportKeyUsage(runtimeBaseDir, event.account_key, {
      tokens_used: event.tokens_used,
      cost_usd: event.cost_usd,
      model_id: event.model_id,
      latency_ms: event.latency_ms,
      occurred_at_ms: event.occurred_at_ms,
    });
    return {
      ...result,
      event,
    };
  }

  const result = reportKeyError(runtimeBaseDir, event.account_key, {
    error_code: event.reason_code,
    model_id: event.model_id,
    outcome: event.outcome,
    http_status: event.http_status,
    reason_code: event.reason_code,
    status_message: event.status_message,
    latency_ms: event.latency_ms,
    occurred_at_ms: event.occurred_at_ms,
    next_retry_at_ms: event.next_retry_at_ms,
    retry_at_source: event.retry_at_source,
  });
  return {
    ...result,
    event,
  };
}
