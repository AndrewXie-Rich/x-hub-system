import { createSlackCommandOrchestrator } from './SlackCommandOrchestrator.js';

function safeString(input) {
  return String(input ?? '').trim();
}

export function createSlackCommandIngressBridge({
  hub_client = null,
  now_fn = Date.now,
  on_result = null,
} = {}) {
  const orchestrator = createSlackCommandOrchestrator({
    hub_client,
    now_fn,
  });

  return {
    normalize(input) {
      return orchestrator.normalize(input);
    },
    async handleEnvelope(input) {
      const normalized = orchestrator.normalize(input);
      if (!normalized.ok) {
        if (safeString(normalized.deny_code) === 'structured_action_missing') {
          return {
            ok: true,
            handled: false,
            reason: 'structured_action_missing',
          };
        }
        return {
          ok: false,
          handled: false,
          deny_code: safeString(normalized.deny_code || 'normalize_failed'),
          retryable: normalized.retryable === true,
        };
      }

      const result = await orchestrator.handle(input);
      if (!result.ok) {
        return {
          ok: false,
          handled: false,
          deny_code: safeString(result.deny_code || 'orchestrator_failed'),
          retryable: result.retryable === true,
          request_id: safeString(result.request_id),
        };
      }

      if (typeof on_result === 'function') {
        try {
          await on_result(result);
        } catch (error) {
          return {
            ok: true,
            handled: true,
            request_id: safeString(result.request_id),
            dispatch_kind: safeString(result.dispatch?.kind),
            route_mode: safeString(result.route?.route_mode || result.gate?.route_mode),
            reply_delivery_ok: false,
            reply_delivery_error: safeString(error?.message || 'reply_delivery_failed') || 'reply_delivery_failed',
          };
        }
      }

      return {
        ok: true,
        handled: true,
        request_id: safeString(result.request_id),
        dispatch_kind: safeString(result.dispatch?.kind),
        route_mode: safeString(result.route?.route_mode || result.gate?.route_mode),
        reply_delivery_ok: true,
      };
    },
  };
}
