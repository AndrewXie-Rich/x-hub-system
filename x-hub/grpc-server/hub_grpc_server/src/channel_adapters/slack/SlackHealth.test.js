import assert from 'node:assert/strict';

import { buildSlackHealthSnapshot } from './SlackHealth.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('SlackHealth reports ready only when bot token and webhook signing secret are present', () => {
  const ready = buildSlackHealthSnapshot({
    account_id: 'T001',
    bot_token_present: true,
    signing_secret_present: true,
    interactive_enabled: true,
    active_binding_count: 3,
    updated_at_ms: 1000,
  });
  assert.equal(String(ready.provider || ''), 'slack');
  assert.equal(String(ready.runtime_state || ''), 'ready');
  assert.equal(!!ready.delivery_ready, true);
  assert.equal(!!ready.command_entry_ready, true);
  assert.equal(Number(ready.active_binding_count || 0), 3);

  const notConfigured = buildSlackHealthSnapshot({
    account_id: 'T002',
    bot_token_present: true,
    signing_secret_present: false,
  });
  assert.equal(String(notConfigured.runtime_state || ''), 'not_configured');
  assert.equal(!!notConfigured.delivery_ready, false);
});

run('SlackHealth reports degraded when the adapter has a last error', () => {
  const degraded = buildSlackHealthSnapshot({
    account_id: 'T003',
    bot_token_present: true,
    signing_secret_present: true,
    last_error_code: 'slack_api_timeout',
  });
  assert.equal(String(degraded.runtime_state || ''), 'degraded');
  assert.equal(String(degraded.last_error_code || ''), 'slack_api_timeout');
  assert.equal(!!degraded.delivery_ready, false);
});
