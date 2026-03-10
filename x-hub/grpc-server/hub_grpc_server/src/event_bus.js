import { EventEmitter } from 'node:events';
import { nowMs, uuid } from './util.js';

export class HubEventBus {
  constructor() {
    this.ee = new EventEmitter();
  }

  /**
   * @param {import('@grpc/grpc-js').ServerWritableStream<any, any>} call
   * @param {{ filter?: (ev: any) => boolean }} [opts]
   */
  subscribe(call, opts) {
    const filter = opts?.filter;
    const onEvent = (ev) => {
      try {
        if (filter && !filter(ev)) return;
        call.write(ev);
      } catch {
        // ignore; stream likely closed
      }
    };
    this.ee.on('hub_event', onEvent);

    const cleanup = () => {
      this.ee.off('hub_event', onEvent);
    };
    call.on('cancelled', cleanup);
    call.on('close', cleanup);
    call.on('error', cleanup);
  }

  emitHubEvent(ev) {
    this.ee.emit('hub_event', ev);
  }

  // Convenience builders (proto-level shapes).

  modelsUpdated(models) {
    return {
      event_id: `evt_${uuid()}`,
      created_at_ms: nowMs(),
      models_updated: {
        updated_at_ms: nowMs(),
        models: models || [],
      },
    };
  }

  grantDecision({ grant_request_id, decision, grant, deny_reason, client }) {
    return {
      event_id: `evt_${uuid()}`,
      created_at_ms: nowMs(),
      grant_decision: {
        grant_request_id: String(grant_request_id || ''),
        decision: decision || 'GRANT_DECISION_UNSPECIFIED',
        grant: grant || null,
        deny_reason: deny_reason || '',
        client: client || grant?.client || null,
      },
    };
  }

  requestStatus({ request_id, status, error, client }) {
    return {
      event_id: `evt_${uuid()}`,
      created_at_ms: nowMs(),
      request_status: {
        request_id: String(request_id || ''),
        status: String(status || ''),
        updated_at_ms: nowMs(),
        error: error || null,
        client: client || null,
      },
    };
  }

  quotaUpdated({ scope, daily_token_cap, daily_token_used, updated_at_ms }) {
    return {
      event_id: `evt_${uuid()}`,
      created_at_ms: nowMs(),
      quota_updated: {
        scope: String(scope || ''),
        daily_token_cap: Number(daily_token_cap || 0),
        daily_token_used: Number(daily_token_used || 0),
        updated_at_ms: Number(updated_at_ms || nowMs()),
      },
    };
  }

  killSwitchUpdated({ scope, models_disabled, network_disabled, reason, updated_at_ms }) {
    return {
      event_id: `evt_${uuid()}`,
      created_at_ms: nowMs(),
      kill_switch_updated: {
        scope: String(scope || ''),
        models_disabled: !!models_disabled,
        network_disabled: !!network_disabled,
        reason: String(reason || ''),
        updated_at_ms: Number(updated_at_ms || nowMs()),
      },
    };
  }
}
