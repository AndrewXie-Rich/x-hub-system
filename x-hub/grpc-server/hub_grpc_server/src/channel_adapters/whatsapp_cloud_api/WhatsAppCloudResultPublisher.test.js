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

run('WhatsAppCloudResultPublisher renders onboarding discovery summaries for unknown ingress', () => {
  const out = buildWhatsAppCloudResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'supervisor.status.get',
    },
    gate: {
      action_name: 'supervisor.status.get',
      deny_code: 'channel_binding_missing',
      route_mode: 'hub_only_status',
    },
    route: {
      route_mode: 'discovery_ticket',
    },
    dispatch: {
      kind: 'discovery_ticket',
    },
    discovery_ticket: {
      ticket_id: 'disc-whatsapp-1',
      status: 'pending',
      ingress_surface: 'dm',
      proposed_scope_type: 'project',
      proposed_scope_id: 'project_alpha',
      recommended_binding_mode: 'conversation_binding',
      audit_ref: 'audit-disc-whatsapp-1',
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Access Pending Approval/);
  assert.match(String(out.payload?.text || ''), /Requested action: supervisor.status.get/);
  assert.match(String(out.payload?.text || ''), /Ticket: disc-whatsapp-1/);
  assert.match(String(out.payload?.text || ''), /Scope hint: project\/project_alpha/);
  assert.match(String(out.payload?.text || ''), /Status: access_pending_approval/);
  assert.match(String(out.payload?.text || ''), /Audit: audit-disc-whatsapp-1/);
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
  assert.match(String(out.payload?.text || ''), /Project state: awaiting authorization/);
  assert.match(String(out.payload?.text || ''), /Topline: Release train paused on one approval/);
  assert.match(String(out.payload?.text || ''), /Pending grants: 1/);
  assert.match(String(out.payload?.text || ''), /Audit: audit-projection-1/);
});

run('WhatsAppCloudResultPublisher renders governed heartbeat query summaries when execution query data is present', () => {
  const out = buildWhatsAppCloudResultSummary(makeResult({
    command: {
      ...makeResult().command,
      action_name: 'supervisor.blockers.get',
    },
    dispatch: {
      kind: 'hub_query',
    },
    execution: {
      ok: true,
      query: {
        action_name: 'supervisor.blockers.get',
        project_id: 'project_alpha',
        heartbeat_governance_snapshot_json: JSON.stringify({
          status_digest: 'Core loop advancing',
          latest_quality_band: 'usable',
          open_anomaly_types: ['stale_repeat'],
          next_review_due: {
            kind: 'review_pulse',
            due: true,
            due_at_ms: 1710000600000,
          },
        }),
        heartbeat: {
          queue_depth: 3,
          oldest_wait_ms: 9000,
          risk_tier: 'medium',
          blocked_reason: ['awaiting security review'],
          next_actions: ['approve release grant'],
        },
      },
      route: {
        route_mode: 'hub_only_status',
        resolved_device_id: 'xt-alpha-1',
        xt_online: true,
      },
    },
  }));
  assert.equal(!!out.ok, true);
  assert.match(String(out.payload?.text || ''), /Status: supervisor_blockers/);
  assert.match(String(out.payload?.text || ''), /Review pressure: quality=usable anomalies=stale_repeat/);
  assert.match(String(out.payload?.text || ''), /Next review: review_pulse due=yes at_ms=1710000600000/);
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
