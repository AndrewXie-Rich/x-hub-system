import assert from 'node:assert/strict';

import {
  buildWhatsAppCloudGrantDecisionSummary,
  buildWhatsAppCloudGrantPendingSummary,
  buildWhatsAppCloudResultSummary,
  createWhatsAppCloudResultPublisher,
} from './WhatsAppCloudResultPublisher.js';

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

function makeResult(overrides = {}) {
  return {
    request_id: 'whatsapp_cloud_api:messages:wamid.1',
    command: {
      action_name: 'deploy.plan',
      audit_ref: 'audit-1',
      route_project_id: 'project_alpha',
      channel: {
        provider: 'whatsapp_cloud_api',
        account_id: 'ops_whatsapp_cloud',
        conversation_id: '15551234567',
        thread_key: 'wamid.1',
      },
    },
    gate: {
      action_name: 'deploy.plan',
      scope_type: 'project',
      scope_id: 'project_alpha',
      route_mode: 'hub_to_xt',
      deny_code: '',
    },
    route: {
      route_mode: 'hub_to_xt',
      resolved_device_id: 'xt-alpha-1',
      deny_code: '',
    },
    dispatch: {
      kind: 'xt_command',
    },
    ...overrides,
  };
}

run('WhatsAppCloudResultPublisher builds routed summary payload', () => {
  const out = buildWhatsAppCloudResultSummary(makeResult());
  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.to || ''), '15551234567');
  assert.equal(String(out.payload?.reply_to_message_id || ''), 'wamid.1');
  assert.match(String(out.payload?.text || ''), /project_alpha/);
});

run('WhatsAppCloudResultPublisher renders supervisor brief projection summaries when projection data is present', () => {
  const out = buildWhatsAppCloudResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'supervisor.status.get',
    },
    dispatch: {
      kind: 'hub_query',
    },
    execution: {
      ok: true,
      projection: {
        projection_kind: 'progress_brief',
        project_id: 'project_alpha',
        trigger: 'awaiting_authorization',
        status: 'awaiting_authorization',
        topline: 'Release train paused on one approval',
        critical_blocker: 'awaiting security review',
        next_best_action: 'Review 1 pending grant request',
        pending_grant_count: 1,
        card_summary: 'One pending grant is blocking the release train.',
        audit_ref: 'audit-projection-1',
      },
      route: {
        route_mode: 'hub_only_status',
        resolved_device_id: 'xt-alpha-1',
        xt_online: true,
      },
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Status: supervisor_status/);
  assert.match(String(out.payload?.text || ''), /Topline: Release train paused on one approval/);
  assert.match(String(out.payload?.text || ''), /Pending grants: 1/);
  assert.match(String(out.payload?.text || ''), /Audit: audit-projection-1/);
});

run('WhatsAppCloudResultPublisher builds proactive grant decision summaries', () => {
  const out = buildWhatsAppCloudGrantDecisionSummary({
    event: {
      event_id: 'evt_grant_1',
      grant_request_id: 'grant-req-1',
      decision: 'approved',
      project_id: 'project_alpha',
      reason: 'release_ready',
    },
    binding: {
      provider: 'whatsapp_cloud_api',
      conversation_id: '15551234567',
      thread_key: 'wamid.1',
    },
  });
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Grant Approved/);
});

run('WhatsAppCloudResultPublisher builds proactive pending approval text with manual commands', () => {
  const out = buildWhatsAppCloudGrantPendingSummary({
    event: {
      event_id: 'evt_grant_pending_1',
      grant_request_id: 'grant-req-2',
      status: 'pending',
      scope_type: 'project',
      scope_id: 'project_alpha',
      project_id: 'project_alpha',
      required_capability: 'CAPABILITY_WEB_FETCH',
    },
    binding: {
      binding_id: 'binding-wa-approval',
      provider: 'whatsapp_cloud_api',
      conversation_id: '15551234567',
      thread_key: 'wamid.1',
      scope_type: 'project',
      scope_id: 'project_alpha',
    },
  });
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Approve: grant approve grant-req-2 project project_alpha/);
  assert.match(String(out.payload?.text || ''), /Reject: grant reject grant-req-2 project project_alpha reason/);
});

await runAsync('WhatsAppCloudResultPublisher posts messages through WhatsApp client shape', async () => {
  const calls = [];
  const publisher = createWhatsAppCloudResultPublisher({
    whatsapp_client: {
      async postMessage(payload) {
        calls.push(payload);
        return {
          ok: true,
          message_id: 'wamid.outbound.1',
        };
      },
    },
  });

  const out = await publisher.publish(makeResult());
  assert.equal(!!out.ok, true);
  assert.equal(calls.length, 1);
});

await runAsync('WhatsAppCloudResultPublisher factory fails closed when client is invalid', async () => {
  await assert.rejects(
    async () => {
      createWhatsAppCloudResultPublisher({
        whatsapp_client: null,
      });
    },
    /whatsapp_cloud_client_invalid/
  );
});
