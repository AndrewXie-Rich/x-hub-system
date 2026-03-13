import assert from 'node:assert/strict';

import {
  buildTelegramApprovalMessage,
  buildTelegramSummaryMessage,
} from './TelegramEgress.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('TelegramEgress approval message carries inline buttons when callback payload fits', () => {
  const out = buildTelegramApprovalMessage({
    delivery_context: {
      provider: 'telegram',
      conversation_id: '-1001234567890',
      thread_key: 'topic:42',
    },
    title: 'Approval Required',
    summary_lines: [
      'Capability: web.fetch',
    ],
    audit_ref: 'audit-1',
    binding_id: 'binding-1',
    scope_type: 'project',
    scope_id: 'project_alpha',
    project_id: 'project_alpha',
    grant_request_id: 'grant_req_1',
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.payload?.chat_id || ''), '-1001234567890');
  assert.equal(Number(out.payload?.message_thread_id || 0), 42);
  assert.match(String(out.payload?.text || ''), /Grant: grant_req_1/);
  assert.equal(String(out.payload?.reply_markup?.inline_keyboard?.[0]?.[0]?.text || ''), 'Approve');
});

run('TelegramEgress summary message includes audit metadata and thread routing', () => {
  const out = buildTelegramSummaryMessage({
    delivery_context: {
      provider: 'telegram',
      conversation_id: '-1001234567890',
      thread_key: 'topic:42',
    },
    title: 'Supervisor Status',
    status: 'supervisor_status',
    project_id: 'project_alpha',
    lines: [
      'Heartbeat: queue_depth=3 wait_ms=9000 risk=medium',
    ],
    audit_ref: 'audit-2',
  });

  assert.equal(!!out.ok, true);
  assert.equal(Number(out.payload?.message_thread_id || 0), 42);
  assert.match(String(out.payload?.text || ''), /Supervisor Status/);
  assert.match(String(out.payload?.text || ''), /Audit: audit-2/);
});
