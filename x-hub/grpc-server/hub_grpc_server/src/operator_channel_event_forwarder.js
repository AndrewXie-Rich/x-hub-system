import { normalizeChannelProviderId } from './channel_registry.js';

function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

function safeObject(input) {
  return input && typeof input === 'object' && !Array.isArray(input) ? input : {};
}

function emitLog(log, line) {
  if (typeof log === 'function') log(line);
}

function grantEventFromHubEvent(event = {}) {
  const eventObj = safeObject(event);
  const grantDecision = safeObject(eventObj.grant_decision);
  const decision = safeString(grantDecision.decision).toUpperCase();
  if (!decision) return null;
  if (
    decision !== 'GRANT_DECISION_QUEUED'
    && decision !== 'GRANT_DECISION_APPROVED'
    && decision !== 'GRANT_DECISION_DENIED'
  ) {
    return null;
  }
  const grant = safeObject(grantDecision.grant);
  const grantClient = safeObject(grant.client);
  const client = safeObject(grantDecision.client);
  const resolvedClient = Object.keys(grantClient).length ? grantClient : client;
  const projectId = safeString(grantClient.project_id || client.project_id);
  return {
    event_id: safeString(eventObj.event_id),
    created_at_ms: safeInt(eventObj.created_at_ms, 0),
    grant_request_id: safeString(grantDecision.grant_request_id),
    decision,
    deny_reason: safeString(grantDecision.deny_reason),
    grant,
    client: resolvedClient,
    project_id: projectId,
  };
}

function isPendingGrantEvent(event = {}) {
  return safeString(event?.decision).toUpperCase() === 'GRANT_DECISION_QUEUED';
}

function isFinalGrantDecisionEvent(event = {}) {
  const decision = safeString(event?.decision).toUpperCase();
  return decision === 'GRANT_DECISION_APPROVED' || decision === 'GRANT_DECISION_DENIED';
}

function bindingAllowsGrantDelivery(binding = {}) {
  const allowed = safeArray(binding.allowed_actions)
    .map((action) => safeString(action).toLowerCase())
    .filter(Boolean);
  return allowed.includes('grant.approve') || allowed.includes('grant.reject');
}

function normalizeBindingsResponse(response = {}) {
  if (Array.isArray(response)) return response;
  if (Array.isArray(response?.bindings)) return response.bindings;
  return [];
}

export function startOperatorChannelEventForwarder({
  provider = '',
  hub_client = null,
  publish_grant_decision = null,
  publish_grant_pending = null,
  log = null,
  retry_delay_ms = 1_500,
  max_bindings = 50,
  suppress_ttl_ms = 5_000,
  now_fn = Date.now,
  set_timeout = setTimeout,
  clear_timeout = clearTimeout,
} = {}) {
  const providerId = normalizeChannelProviderId(provider) || '';
  const retryDelayMs = Math.max(250, safeInt(retry_delay_ms, 1_500) || 1_500);
  const maxBindings = Math.max(1, Math.min(200, safeInt(max_bindings, 50) || 50));
  const suppressTtlMs = Math.max(500, safeInt(suppress_ttl_ms, 5_000) || 5_000);
  const suppressedGrantRequestIds = new Map();

  let closed = false;
  let stream = null;
  let reconnectTimer = null;
  let started = false;
  let reconnectCount = 0;

  function nowMs() {
    return typeof now_fn === 'function' ? safeInt(now_fn(), Date.now()) : Date.now();
  }

  function snapshot() {
    return {
      provider: providerId,
      started,
      subscribed: !!stream,
      reconnect_count: reconnectCount,
      suppressed_total: suppressedGrantRequestIds.size,
    };
  }

  function closeCurrentStream() {
    const current = stream;
    stream = null;
    if (!current) return;
    try {
      current.cancel?.();
    } catch {
      // ignore
    }
  }

  function clearReconnectTimer() {
    if (!reconnectTimer) return;
    try {
      clear_timeout(reconnectTimer);
    } catch {
      // ignore
    }
    reconnectTimer = null;
  }

  function pruneSuppressedGrantRequestIds() {
    const now = nowMs();
    for (const [grantRequestId, expiresAtMs] of suppressedGrantRequestIds.entries()) {
      if (!grantRequestId || expiresAtMs <= now) {
        suppressedGrantRequestIds.delete(grantRequestId);
      }
    }
  }

  function suppressGrantDecision({
    grant_request_id = '',
    ttl_ms = suppressTtlMs,
  } = {}) {
    const grantRequestId = safeString(grant_request_id);
    if (!grantRequestId) return false;
    pruneSuppressedGrantRequestIds();
    suppressedGrantRequestIds.set(
      grantRequestId,
      nowMs() + Math.max(500, safeInt(ttl_ms, suppressTtlMs) || suppressTtlMs)
    );
    return true;
  }

  function grantDecisionSuppressed(grantRequestId) {
    const id = safeString(grantRequestId);
    if (!id) return false;
    pruneSuppressedGrantRequestIds();
    const expiresAtMs = safeInt(suppressedGrantRequestIds.get(id), 0);
    if (expiresAtMs <= nowMs()) {
      suppressedGrantRequestIds.delete(id);
      return false;
    }
    suppressedGrantRequestIds.delete(id);
    return true;
  }

  async function publishGrantEventToBindings({
    event = {},
    event_label = 'grant event',
    publish_fn = null,
  } = {}) {
    if (typeof publish_fn !== 'function') return;
    if (!event.project_id) {
      emitLog(
        log,
        `[operator_channel_event_forwarder:${providerId}] dropped ${event_label} without project binding context grant_request_id=${event.grant_request_id}`
      );
      return;
    }

    let listed;
    try {
      listed = await hub_client.listSupervisorOperatorChannelBindings({
        provider: providerId,
        scope_type: 'project',
        scope_id: event.project_id,
        status: 'active',
        limit: maxBindings,
      });
    } catch (error) {
      emitLog(
        log,
        `[operator_channel_event_forwarder:${providerId}] binding lookup failed ${event_label} grant_request_id=${event.grant_request_id} error=${safeString(error?.message || 'binding_lookup_failed') || 'binding_lookup_failed'}`
      );
      return;
    }

    const seenBindingIds = new Set();
    const bindings = normalizeBindingsResponse(listed)
      .filter((binding) => safeString(binding?.provider) === providerId)
      .filter((binding) => safeString(binding?.status || 'active') === 'active')
      .filter((binding) => bindingAllowsGrantDelivery(binding));

    if (!bindings.length) {
      emitLog(
        log,
        `[operator_channel_event_forwarder:${providerId}] dropped ${event_label} without active approval binding grant_request_id=${event.grant_request_id} project_id=${event.project_id}`
      );
      return;
    }

    for (const binding of bindings) {
      const bindingId = safeString(binding?.binding_id);
      if (bindingId && seenBindingIds.has(bindingId)) continue;
      if (bindingId) seenBindingIds.add(bindingId);
      try {
        await publish_fn({
          event,
          binding,
        });
      } catch (error) {
        emitLog(
          log,
          `[operator_channel_event_forwarder:${providerId}] delivery failed ${event_label} grant_request_id=${event.grant_request_id} binding_id=${bindingId || 'unknown'} error=${safeString(error?.message || 'delivery_failed') || 'delivery_failed'}`
        );
      }
    }
  }

  async function forwardGrantDecision(event) {
    if (!isFinalGrantDecisionEvent(event)) return;
    if (grantDecisionSuppressed(event.grant_request_id)) {
      emitLog(
        log,
        `[operator_channel_event_forwarder:${providerId}] suppressed duplicated grant decision grant_request_id=${event.grant_request_id}`
      );
      return;
    }
    await publishGrantEventToBindings({
      event,
      event_label: 'grant decision',
      publish_fn: publish_grant_decision,
    });
  }

  async function forwardPendingGrant(event) {
    if (!isPendingGrantEvent(event)) return;
    await publishGrantEventToBindings({
      event,
      event_label: 'pending grant',
      publish_fn: publish_grant_pending,
    });
  }

  async function forwardGrantEvent(hubEvent) {
    const event = grantEventFromHubEvent(hubEvent);
    if (!event) return;
    if (isPendingGrantEvent(event)) {
      await forwardPendingGrant(event);
      return;
    }
    await forwardGrantDecision(event);
  }

  function scheduleReconnect(reason = 'stream_restart') {
    if (closed || reconnectTimer) return;
    reconnectCount += 1;
    reconnectTimer = set_timeout(() => {
      reconnectTimer = null;
      openStream();
    }, retryDelayMs);
    emitLog(
      log,
      `[operator_channel_event_forwarder:${providerId}] scheduling reconnect reason=${safeString(reason) || 'stream_restart'} delay_ms=${retryDelayMs}`
    );
  }

  function openStream() {
    if (closed) return;
    if (!providerId) return;
    if (!hub_client || typeof hub_client.subscribeHubEvents !== 'function') return;
    if (typeof publish_grant_decision !== 'function') return;
    clearReconnectTimer();

    try {
      const currentStream = hub_client.subscribeHubEvents({
        scopes: ['grants'],
        on_data: (event) => {
          Promise.resolve(forwardGrantEvent(event)).catch((error) => {
            emitLog(
              log,
              `[operator_channel_event_forwarder:${providerId}] event forward failed error=${safeString(error?.message || 'event_forward_failed') || 'event_forward_failed'}`
            );
          });
        },
        on_error: (error) => {
          if (stream !== currentStream) return;
          stream = null;
          if (closed) return;
          emitLog(
            log,
            `[operator_channel_event_forwarder:${providerId}] stream error=${safeString(error?.message || 'stream_error') || 'stream_error'}`
          );
          scheduleReconnect('stream_error');
        },
        on_end: () => {
          if (stream !== currentStream) return;
          stream = null;
          if (closed) return;
          emitLog(
            log,
            `[operator_channel_event_forwarder:${providerId}] stream ended`
          );
          scheduleReconnect('stream_end');
        },
      });
      stream = currentStream;
      if (currentStream && typeof currentStream.on === 'function') {
        currentStream.on('close', () => {
          if (stream !== currentStream) return;
          stream = null;
          if (closed) return;
          emitLog(
            log,
            `[operator_channel_event_forwarder:${providerId}] stream closed`
          );
          scheduleReconnect('stream_close');
        });
      }
      started = !!currentStream;
      if (started) {
        emitLog(
          log,
          `[operator_channel_event_forwarder:${providerId}] subscribed scopes=grants`
        );
      }
    } catch (error) {
      stream = null;
      emitLog(
        log,
        `[operator_channel_event_forwarder:${providerId}] subscribe failed error=${safeString(error?.message || 'subscribe_failed') || 'subscribe_failed'}`
      );
      scheduleReconnect('subscribe_failed');
    }
  }

  const ready = providerId
    && hub_client
    && typeof hub_client.subscribeHubEvents === 'function'
    && typeof hub_client.listSupervisorOperatorChannelBindings === 'function'
    && (
      typeof publish_grant_decision === 'function'
      || typeof publish_grant_pending === 'function'
    );

  if (ready) openStream();

  return {
    provider: providerId,
    started: !!ready,
    suppressGrantDecision,
    snapshot,
    async close() {
      closed = true;
      clearReconnectTimer();
      closeCurrentStream();
    },
  };
}
