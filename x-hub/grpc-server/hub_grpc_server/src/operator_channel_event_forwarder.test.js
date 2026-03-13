import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';

import { startOperatorChannelEventForwarder } from './operator_channel_event_forwarder.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function flushAsyncWork() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function makeHubEventStream() {
  const stream = new EventEmitter();
  stream.cancelled = false;
  stream.cancel = () => {
    stream.cancelled = true;
  };
  return stream;
}

run('operator_channel_event_forwarder starts disabled when required dependencies are missing', () => {
  const controller = startOperatorChannelEventForwarder({
    provider: 'slack',
    hub_client: null,
    publish_grant_decision: null,
  });

  assert.equal(!!controller.started, false);
  assert.equal(!!controller.snapshot().subscribed, false);
});

await runAsync('operator_channel_event_forwarder forwards grant decisions only to active approval bindings of the same provider', async () => {
  const stream = makeHubEventStream();
  const delivered = [];
  const listedCalls = [];

  const controller = startOperatorChannelEventForwarder({
    provider: 'slack',
    hub_client: {
      subscribeHubEvents({ on_data, on_error, on_end }) {
        stream.on('data', on_data);
        stream.on('error', on_error);
        stream.on('end', on_end);
        return stream;
      },
      async listSupervisorOperatorChannelBindings(filters) {
        listedCalls.push(filters);
        return {
          bindings: [
            {
              binding_id: 'binding-slack-approval',
              provider: 'slack',
              status: 'active',
              account_id: 'ops-bot',
              conversation_id: 'C123',
              thread_key: '1710000000.0001',
              allowed_actions: ['grant.approve', 'grant.reject'],
            },
            {
              binding_id: 'binding-slack-non-approval',
              provider: 'slack',
              status: 'active',
              account_id: 'ops-bot',
              conversation_id: 'C999',
              thread_key: '',
              allowed_actions: ['deploy.plan'],
            },
            {
              binding_id: 'binding-feishu-approval',
              provider: 'feishu',
              status: 'active',
              account_id: 'tenant-ops',
              conversation_id: 'oc_room_1',
              thread_key: 'om_anchor_1',
              allowed_actions: ['grant.approve'],
            },
          ],
        };
      },
    },
    publish_grant_decision: async ({ event, binding }) => {
      delivered.push({ event, binding });
    },
  });

  assert.equal(!!controller.snapshot().subscribed, true);

  stream.emit('data', {
    event_id: 'evt_approval_1',
    grant_decision: {
      grant_request_id: 'grant_req_1',
      decision: 'GRANT_DECISION_APPROVED',
      grant: {
        grant_id: 'grant_1',
        capability: 'CAPABILITY_WEB_FETCH',
        client: {
          device_id: 'xt-alpha-1',
          project_id: 'project_alpha',
        },
      },
      client: {
        device_id: 'xt-alpha-1',
        project_id: 'project_alpha',
      },
    },
  });
  await flushAsyncWork();

  assert.equal(listedCalls.length, 1);
  assert.equal(String(listedCalls[0]?.provider || ''), 'slack');
  assert.equal(String(listedCalls[0]?.scope_id || ''), 'project_alpha');
  assert.equal(delivered.length, 1);
  assert.equal(String(delivered[0]?.binding?.binding_id || ''), 'binding-slack-approval');
  assert.equal(String(delivered[0]?.event?.grant_request_id || ''), 'grant_req_1');

  await controller.close();
  assert.equal(stream.cancelled, true);
});

await runAsync('operator_channel_event_forwarder suppresses locally initiated grant decisions to avoid duplicate replies', async () => {
  const stream = makeHubEventStream();
  const delivered = [];

  const controller = startOperatorChannelEventForwarder({
    provider: 'slack',
    hub_client: {
      subscribeHubEvents({ on_data, on_error, on_end }) {
        stream.on('data', on_data);
        stream.on('error', on_error);
        stream.on('end', on_end);
        return stream;
      },
      async listSupervisorOperatorChannelBindings() {
        return {
          bindings: [
            {
              binding_id: 'binding-slack-approval',
              provider: 'slack',
              status: 'active',
              account_id: 'ops-bot',
              conversation_id: 'C123',
              thread_key: '1710000000.0001',
              allowed_actions: ['grant.approve', 'grant.reject'],
            },
          ],
        };
      },
    },
    publish_grant_decision: async ({ event, binding }) => {
      delivered.push({ event, binding });
    },
  });

  controller.suppressGrantDecision({
    grant_request_id: 'grant_req_2',
  });

  stream.emit('data', {
    event_id: 'evt_approval_2',
    grant_decision: {
      grant_request_id: 'grant_req_2',
      decision: 'GRANT_DECISION_DENIED',
      deny_reason: 'policy_denied',
      client: {
        device_id: 'xt-alpha-1',
        project_id: 'project_alpha',
      },
    },
  });
  await flushAsyncWork();

  assert.equal(delivered.length, 0);

  await controller.close();
});

await runAsync('operator_channel_event_forwarder forwards queued grant events as pending approvals to active approval bindings', async () => {
  const stream = makeHubEventStream();
  const pendingDelivered = [];
  const decisionDelivered = [];

  const controller = startOperatorChannelEventForwarder({
    provider: 'slack',
    hub_client: {
      subscribeHubEvents({ on_data, on_error, on_end }) {
        stream.on('data', on_data);
        stream.on('error', on_error);
        stream.on('end', on_end);
        return stream;
      },
      async listSupervisorOperatorChannelBindings() {
        return {
          bindings: [
            {
              binding_id: 'binding-slack-approval',
              provider: 'slack',
              status: 'active',
              account_id: 'ops-bot',
              conversation_id: 'C123',
              thread_key: '1710000000.0001',
              scope_type: 'project',
              scope_id: 'project_alpha',
              allowed_actions: ['grant.approve', 'grant.reject'],
            },
          ],
        };
      },
    },
    publish_grant_pending: async ({ event, binding }) => {
      pendingDelivered.push({ event, binding });
    },
    publish_grant_decision: async ({ event, binding }) => {
      decisionDelivered.push({ event, binding });
    },
  });

  stream.emit('data', {
    event_id: 'evt_pending_1',
    grant_decision: {
      grant_request_id: 'grant_req_pending_1',
      decision: 'GRANT_DECISION_QUEUED',
      grant: {
        capability: 'CAPABILITY_WEB_FETCH',
        token_cap: 5000,
        client: {
          device_id: 'xt-alpha-1',
          project_id: 'project_alpha',
        },
      },
      client: {
        device_id: 'xt-alpha-1',
        project_id: 'project_alpha',
      },
    },
  });
  await flushAsyncWork();

  assert.equal(pendingDelivered.length, 1);
  assert.equal(decisionDelivered.length, 0);
  assert.equal(String(pendingDelivered[0]?.event?.grant_request_id || ''), 'grant_req_pending_1');
  assert.equal(String(pendingDelivered[0]?.binding?.binding_id || ''), 'binding-slack-approval');

  await controller.close();
});

await runAsync('operator_channel_event_forwarder fail-closes queued grant delivery when no active approval binding exists', async () => {
  const stream = makeHubEventStream();
  const pendingDelivered = [];

  const controller = startOperatorChannelEventForwarder({
    provider: 'slack',
    hub_client: {
      subscribeHubEvents({ on_data, on_error, on_end }) {
        stream.on('data', on_data);
        stream.on('error', on_error);
        stream.on('end', on_end);
        return stream;
      },
      async listSupervisorOperatorChannelBindings() {
        return {
          bindings: [
            {
              binding_id: 'binding-slack-non-approval',
              provider: 'slack',
              status: 'active',
              account_id: 'ops-bot',
              conversation_id: 'C999',
              thread_key: '',
              scope_type: 'project',
              scope_id: 'project_alpha',
              allowed_actions: ['deploy.plan'],
            },
          ],
        };
      },
    },
    publish_grant_pending: async ({ event, binding }) => {
      pendingDelivered.push({ event, binding });
    },
  });

  stream.emit('data', {
    event_id: 'evt_pending_2',
    grant_decision: {
      grant_request_id: 'grant_req_pending_2',
      decision: 'GRANT_DECISION_QUEUED',
      client: {
        device_id: 'xt-alpha-1',
        project_id: 'project_alpha',
      },
    },
  });
  await flushAsyncWork();

  assert.equal(pendingDelivered.length, 0);

  await controller.close();
});
