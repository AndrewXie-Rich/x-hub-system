import assert from 'node:assert/strict';

import {
  buildSlackApprovalCard,
  buildSlackPostMessagePayload,
  buildSlackSummaryMessage,
} from './SlackEgress.js';
import { compileSlackInteractiveAction } from './SlackInteractiveActions.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('SlackEgress builds thread-aware postMessage payload with normalized delivery context', () => {
  const out = buildSlackPostMessagePayload({
    delivery_context: {
      provider: 'slack',
      account_id: 'ops_bot',
      conversation_id: 'C123',
      thread_key: '1710000000.0001',
    },
    text: 'Supervisor heartbeat',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.delivery_context?.conversation_id || ''), 'C123');
  assert.equal(String(out.payload?.channel || ''), 'C123');
  assert.equal(String(out.payload?.thread_ts || ''), '1710000000.0001');
  assert.equal(String(out.payload?.text || ''), 'Supervisor heartbeat');
  assert.equal(!!out.payload?.unfurl_links, false);
  assert.equal(!!out.payload?.unfurl_media, false);
});

run('SlackEgress approval card carries audit metadata and round-trips through interactive action parsing', () => {
  const out = buildSlackApprovalCard({
    delivery_context: {
      account_id: 'ops_bot',
      conversation_id: 'C456',
      thread_key: '1710000000.0002',
    },
    title: 'Deploy execution approval',
    summary_lines: [
      'Requested by release manager Alice',
      'Target project: payments-prod',
    ],
    audit_ref: 'audit-slack-approval-1',
    binding_id: 'binding-slack-1',
    scope_type: 'project',
    scope_id: 'payments-prod',
    grant_request_id: 'grant_req_1',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.channel || ''), 'C456');
  assert.equal(String(out.payload?.thread_ts || ''), '1710000000.0002');
  assert.equal(String(out.payload?.metadata?.event_payload?.delivery_class || ''), 'approval_card');

  const actionsBlock = out.payload?.blocks?.find((block) => block?.type === 'actions');
  assert.ok(actionsBlock, 'expected actions block');
  const approve = actionsBlock.elements?.find((item) => item?.action_id === 'xt.grant.approve');
  assert.ok(approve, 'expected approve button');

  const parsed = compileSlackInteractiveAction({
    type: 'block_actions',
    trigger_id: '1337.42.abcd',
    team: { id: 'T001' },
    user: { id: 'U123' },
    channel: { id: 'C456' },
    container: {
      channel_id: 'C456',
      thread_ts: '1710000000.0002',
    },
    message: {
      metadata: out.payload.metadata,
    },
    actions: [
      {
        action_id: approve.action_id,
        value: approve.value,
      },
    ],
  });

  assert.equal(!!parsed.ok, true);
  assert.equal(String(parsed.audit_ref || ''), 'audit-slack-approval-1');
  assert.equal(String(parsed.action?.action_name || ''), 'grant.approve');
  assert.equal(String(parsed.action?.binding_id || ''), 'binding-slack-1');
  assert.equal(String(parsed.action?.scope_id || ''), 'payments-prod');
  assert.equal(String(parsed.action?.pending_grant?.grant_request_id || ''), 'grant_req_1');
});

run('SlackEgress summary builder emits audit-tagged threaded summary blocks', () => {
  const out = buildSlackSummaryMessage({
    delivery_context: {
      conversation_id: 'C789',
      thread_key: '1710000000.0003',
    },
    title: 'Supervisor Summary',
    status: 'healthy',
    project_id: 'search-prod',
    lines: [
      'Queue depth is 0',
      'No pending grants',
    ],
    fields: [
      { label: 'Device', value: 'xt-prod-1' },
    ],
    audit_ref: 'audit-summary-1',
    reply_broadcast: true,
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.channel || ''), 'C789');
  assert.equal(String(out.payload?.thread_ts || ''), '1710000000.0003');
  assert.equal(!!out.payload?.reply_broadcast, true);
  assert.equal(String(out.payload?.metadata?.event_payload?.delivery_class || ''), 'summary');
  assert.equal(String(out.payload?.metadata?.event_payload?.audit_ref || ''), 'audit-summary-1');
  assert.match(String(out.payload?.text || ''), /status=healthy/);
  assert.match(String(out.payload?.text || ''), /Queue depth is 0/);
});

run('SlackEgress fails closed on missing approval audit metadata and channel target', () => {
  const missingAudit = buildSlackApprovalCard({
    delivery_context: {
      conversation_id: 'C456',
    },
    binding_id: 'binding-slack-1',
    scope_type: 'project',
    scope_id: 'payments-prod',
    grant_request_id: 'grant_req_1',
  });
  assert.equal(!!missingAudit.ok, false);
  assert.equal(String(missingAudit.deny_code || ''), 'audit_ref_missing');

  const missingChannel = buildSlackSummaryMessage({
    delivery_context: {
      thread_key: '1710000000.0003',
    },
    audit_ref: 'audit-summary-1',
  });
  assert.equal(!!missingChannel.ok, false);
  assert.equal(String(missingChannel.deny_code || ''), 'conversation_id_missing');
});
