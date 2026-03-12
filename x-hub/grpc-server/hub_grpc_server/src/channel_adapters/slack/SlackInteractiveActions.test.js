import assert from 'node:assert/strict';

import {
  compileSlackInteractiveAction,
  listSlackInteractiveActionIds,
  mapSlackActionIdToChannelAction,
} from './SlackInteractiveActions.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('SlackInteractiveActions compiles allowlisted block action with audit_ref and grant metadata', () => {
  assert.equal(mapSlackActionIdToChannelAction('xt.grant.approve'), 'grant.approve');
  assert.ok(listSlackInteractiveActionIds().includes('xt.grant.approve'));

  const out = compileSlackInteractiveAction({
    type: 'block_actions',
    trigger_id: '1337.42.abcd',
    team: { id: 'T001' },
    user: { id: 'U123' },
    channel: { id: 'C456' },
    container: { channel_id: 'C456', thread_ts: '1710000000.0001' },
    actions: [{
      action_id: 'xt.grant.approve',
      value: JSON.stringify({
        audit_ref: 'audit-slack-grant-1',
        binding_id: 'binding-slack-1',
        scope_type: 'project',
        scope_id: 'project_alpha',
        pending_grant_request_id: 'grant_req_1',
        pending_grant_project_id: 'project_alpha',
        note: 'approved after manual review',
      }),
    }],
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.audit_ref || ''), 'audit-slack-grant-1');
  assert.equal(String(out.actor?.external_user_id || ''), 'U123');
  assert.equal(String(out.channel?.conversation_id || ''), 'C456');
  assert.equal(String(out.channel?.thread_key || ''), '1710000000.0001');
  assert.equal(String(out.action?.action_name || ''), 'grant.approve');
  assert.equal(String(out.action?.binding_id || ''), 'binding-slack-1');
  assert.equal(String(out.action?.note || ''), 'approved after manual review');
  assert.equal(String(out.action?.pending_grant?.grant_request_id || ''), 'grant_req_1');
});

run('SlackInteractiveActions fails closed on missing audit_ref and unsupported action ids', () => {
  const missingAudit = compileSlackInteractiveAction({
    type: 'block_actions',
    actions: [{
      action_id: 'xt.supervisor.pause',
      value: JSON.stringify({
        binding_id: 'binding-1',
      }),
    }],
  });
  assert.equal(!!missingAudit.ok, false);
  assert.equal(String(missingAudit.deny_code || ''), 'audit_ref_missing');

  const unsupported = compileSlackInteractiveAction({
    type: 'block_actions',
    actions: [{
      action_id: 'xt.unsupported',
      value: JSON.stringify({
        audit_ref: 'audit-1',
      }),
    }],
  });
  assert.equal(!!unsupported.ok, false);
  assert.equal(String(unsupported.deny_code || ''), 'action_unsupported');
});
