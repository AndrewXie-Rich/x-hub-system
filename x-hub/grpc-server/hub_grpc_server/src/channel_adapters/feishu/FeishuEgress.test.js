import assert from 'node:assert/strict';

import {
  buildFeishuApprovalCard,
  buildFeishuSendMessagePayload,
  buildFeishuSummaryMessage,
} from './FeishuEgress.js';
import { compileFeishuCardAction } from './FeishuCards.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('FeishuEgress builds thread-aware send payload with normalized delivery context', () => {
  const out = buildFeishuSendMessagePayload({
    delivery_context: {
      provider: 'feishu',
      account_id: 'tenant-ops',
      conversation_id: 'oc_room_1',
      thread_key: 'om_anchor_1',
    },
    card: { schema: '2.0' },
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.delivery_context?.conversation_id || ''), 'oc_room_1');
  assert.equal(String(out.payload?.receive_id || ''), 'oc_room_1');
  assert.equal(String(out.payload?.reply_to_message_id || ''), 'om_anchor_1');
  assert.equal(!!out.payload?.reply_in_thread, true);
  assert.equal(String(out.payload?.msg_type || ''), 'interactive');
});

run('FeishuEgress approval card carries audit metadata and round-trips through card action parsing', () => {
  const out = buildFeishuApprovalCard({
    delivery_context: {
      account_id: 'tenant-ops',
      conversation_id: 'oc_room_approve',
      thread_key: 'om_anchor_2',
    },
    title: 'Deploy execution approval',
    summary_lines: [
      'Requested by release manager Alice',
      'Target project: payments-prod',
    ],
    audit_ref: 'audit-feishu-approval-1',
    binding_id: 'binding-feishu-1',
    scope_type: 'project',
    scope_id: 'payments-prod',
    grant_request_id: 'grant_req_1',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.receive_id || ''), 'oc_room_approve');
  assert.equal(String(out.payload?.reply_to_message_id || ''), 'om_anchor_2');

  const card = JSON.parse(String(out.payload?.content || '{}'));
  const actionsBlock = card.body?.elements?.find((block) => block?.tag === 'action');
  assert.ok(actionsBlock, 'expected action block');
  const approve = actionsBlock.actions?.find((item) => item?.action_id === 'xt.grant.approve');
  assert.ok(approve, 'expected approve button');

  const parsed = compileFeishuCardAction({
    header: {
      event_id: 'evt_1',
      tenant_key: 'tenant-ops',
    },
    event: {
      operator: {
        operator_id: {
          open_id: 'ou_approver_1',
        },
      },
      token: 'card_trigger_1',
      action: {
        action_id: approve.action_id,
        value: approve.value,
      },
      context: {
        open_chat_id: 'oc_room_approve',
        open_message_id: 'om_anchor_2',
        chat_type: 'group',
      },
    },
  });

  assert.equal(!!parsed.ok, true);
  assert.equal(String(parsed.action?.action_name || ''), 'grant.approve');
  assert.equal(String(parsed.action?.binding_id || ''), 'binding-feishu-1');
  assert.equal(String(parsed.action?.pending_grant?.grant_request_id || ''), 'grant_req_1');
});

run('FeishuEgress summary builder emits audit-tagged threaded summary cards', () => {
  const out = buildFeishuSummaryMessage({
    delivery_context: {
      conversation_id: 'oc_room_3',
      thread_key: 'om_anchor_3',
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
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.receive_id || ''), 'oc_room_3');
  assert.equal(String(out.payload?.reply_to_message_id || ''), 'om_anchor_3');
  const card = JSON.parse(String(out.payload?.content || '{}'));
  const markdown = String(card.body?.elements?.[0]?.content || '');
  assert.match(markdown, /Status/);
  assert.match(markdown, /Queue depth is 0/);
  assert.match(markdown, /audit-summary-1/);
});

run('FeishuEgress fails closed on missing approval audit metadata and channel target', () => {
  const missingAudit = buildFeishuApprovalCard({
    delivery_context: {
      conversation_id: 'oc_room_1',
    },
    binding_id: 'binding-feishu-1',
    scope_type: 'project',
    scope_id: 'payments-prod',
    grant_request_id: 'grant_req_1',
  });
  assert.equal(!!missingAudit.ok, false);
  assert.equal(String(missingAudit.deny_code || ''), 'audit_ref_missing');

  const missingChannel = buildFeishuSummaryMessage({
    delivery_context: {
      thread_key: 'om_anchor_3',
    },
    audit_ref: 'audit-summary-1',
  });
  assert.equal(!!missingChannel.ok, false);
  assert.equal(String(missingChannel.deny_code || ''), 'conversation_id_missing');
});
