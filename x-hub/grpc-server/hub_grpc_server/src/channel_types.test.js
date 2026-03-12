import assert from 'node:assert/strict';

import {
  isChannelRuntimeDegradedState,
  isChannelRuntimeReadyState,
  normalizeChannelApprovalSurface,
  normalizeChannelAutomationPath,
  normalizeChannelCapabilities,
  normalizeChannelRuntimeState,
  normalizeChannelThreadingMode,
} from './channel_types.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('XT-W3-24-G/channel types normalize capabilities and drop unknown entries', () => {
  const out = normalizeChannelCapabilities([
    'status_query',
    'push_alerts',
    'push_alerts',
    'not_real',
    ' approval_actions ',
  ]);
  assert.deepEqual(out, [
    'status_query',
    'push_alerts',
    'approval_actions',
  ]);
});

run('XT-W3-24-G/channel types normalize threading/approval/automation with safe fallbacks', () => {
  assert.equal(normalizeChannelThreadingMode('provider_native'), 'provider_native');
  assert.equal(normalizeChannelThreadingMode('topic'), 'none');
  assert.equal(normalizeChannelApprovalSurface('card'), 'card');
  assert.equal(normalizeChannelApprovalSurface('modal'), 'text_only');
  assert.equal(normalizeChannelAutomationPath('trusted_automation_local'), 'trusted_automation_local');
  assert.equal(normalizeChannelAutomationPath('xt_runtime'), 'hub_bridge');
});

run('XT-W3-24-G/channel types runtime states stay fail-closed', () => {
  assert.equal(normalizeChannelRuntimeState('ready'), 'ready');
  assert.equal(normalizeChannelRuntimeState('mystery_state'), 'not_configured');
  assert.equal(isChannelRuntimeReadyState('ready'), true);
  assert.equal(isChannelRuntimeReadyState('ingress_ready'), false);
  assert.equal(isChannelRuntimeDegradedState('degraded'), true);
  assert.equal(isChannelRuntimeDegradedState('error'), true);
  assert.equal(isChannelRuntimeDegradedState('ready'), false);
});
