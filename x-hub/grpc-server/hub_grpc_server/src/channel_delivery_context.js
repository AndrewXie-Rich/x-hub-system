import { normalizeChannelProviderId } from './channel_registry.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function normalizeScalar(input) {
  if (typeof input === 'number' && Number.isFinite(input)) {
    return String(Math.trunc(input));
  }
  const text = safeString(input);
  return text || undefined;
}

export function normalizeChannelConversationId(input) {
  return normalizeScalar(input);
}

export function normalizeChannelAccountId(input) {
  return normalizeScalar(input);
}

export function normalizeChannelThreadKey(input) {
  return normalizeScalar(input);
}

export function normalizeChannelDeliveryContext(context) {
  if (!context || typeof context !== 'object') {
    return undefined;
  }
  const provider = normalizeChannelProviderId(
    context.provider || context.channel || context.provider_id
  );
  if (!provider) {
    return undefined;
  }
  const conversation_id = normalizeChannelConversationId(
    context.conversation_id || context.to || context.channel_id
  );
  const account_id = normalizeChannelAccountId(
    context.account_id || context.accountId
  );
  const thread_key = normalizeChannelThreadKey(
    context.thread_key || context.threadId || context.thread_id
  );
  if (!conversation_id && !account_id && !thread_key) {
    return {
      provider,
      conversation_id: undefined,
      account_id: undefined,
      thread_key: undefined,
    };
  }
  return {
    provider,
    conversation_id,
    account_id,
    thread_key,
  };
}

export function mergeChannelDeliveryContext(primary, fallback) {
  const first = normalizeChannelDeliveryContext(primary);
  const second = normalizeChannelDeliveryContext(fallback);
  if (!first && !second) return undefined;
  if (!first) return second;
  if (!second) return first;
  const sameProvider = first.provider === second.provider;
  return normalizeChannelDeliveryContext({
    provider: first.provider,
    conversation_id: first.conversation_id || (sameProvider ? second.conversation_id : undefined),
    account_id: first.account_id || (sameProvider ? second.account_id : undefined),
    thread_key: first.thread_key || (sameProvider ? second.thread_key : undefined),
  });
}

export function channelDeliveryContextKey(context) {
  const normalized = normalizeChannelDeliveryContext(context);
  if (!normalized?.provider || !normalized?.conversation_id) {
    return undefined;
  }
  return [
    normalized.provider,
    normalized.conversation_id,
    normalized.account_id || '',
    normalized.thread_key || '',
  ].join('|');
}

export function normalizeChannelSessionDeliveryFields(source) {
  if (!source || typeof source !== 'object') {
    return {
      delivery_context: undefined,
      last_provider: undefined,
      last_conversation_id: undefined,
      last_account_id: undefined,
      last_thread_key: undefined,
    };
  }
  const merged = mergeChannelDeliveryContext(
    {
      provider: source.last_provider || source.provider,
      conversation_id: source.last_conversation_id || source.conversation_id,
      account_id: source.last_account_id,
      thread_key: source.last_thread_key,
    },
    source.delivery_context
  );
  return {
    delivery_context: merged,
    last_provider: merged?.provider,
    last_conversation_id: merged?.conversation_id,
    last_account_id: merged?.account_id,
    last_thread_key: merged?.thread_key,
  };
}

export function channelDeliveryContextFromSession(entry) {
  if (!entry || typeof entry !== 'object') return undefined;
  return normalizeChannelSessionDeliveryFields({
    provider: entry.provider,
    conversation_id: entry.conversation_id,
    last_provider: entry.last_provider,
    last_conversation_id: entry.last_conversation_id,
    last_account_id: entry.last_account_id,
    last_thread_key: entry.last_thread_key ?? entry.delivery_context?.thread_key ?? entry.origin?.thread_key,
    delivery_context: entry.delivery_context,
  }).delivery_context;
}
