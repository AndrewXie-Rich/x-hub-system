import assert from 'node:assert/strict';

import {
  HUB_CHANNEL_INGRESS_ENVELOPE_SCHEMA,
  HUB_CHANNEL_PROVIDER_EXPOSURE_MATRIX_SCHEMA,
  buildChannelProviderExposureMatrix,
  normalizeHubChannelIngressEnvelope,
} from './channel_ingress_envelope.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('XT-W3-24-G/provider exposure matrix stays machine-readable and aligned to provider registry', () => {
  const out = buildChannelProviderExposureMatrix({
    updated_at_ms: 1710000000000,
  });
  assert.equal(String(out.schema_version || ''), HUB_CHANNEL_PROVIDER_EXPOSURE_MATRIX_SCHEMA);
  assert.equal(Array.isArray(out.providers), true);
  assert.equal(out.providers.length, 5);
  const slack = out.providers.find((row) => row.provider === 'slack');
  assert.equal(String(slack?.listener || ''), 'public_webhook');
  assert.equal(String(slack?.process || ''), 'slack_ingress_worker');
  assert.equal(String(slack?.path || ''), '/slack/events');
  assert.equal(String(slack?.auth_mode || ''), 'slack_signature_v0');
});

run('XT-W3-24-G/hub channel ingress envelope normalizes provider route and contract fields fail-closed', () => {
  const out = normalizeHubChannelIngressEnvelope({
    ok: true,
    envelope_type: 'event_callback',
    event_id: 'Ev001',
    replay_key: 'Ev001',
    signature_valid: true,
    actor: {
      provider: 'Slack',
      external_user_id: 'U123',
      external_tenant_id: 'T001',
    },
    channel: {
      provider: 'slack',
      account_id: 'T001',
      conversation_id: 'C456',
      thread_key: '1710000000.0001',
      channel_scope: 'group',
    },
    structured_action: {
      action_name: 'supervisor.status.get',
      ignored_extra: 'drop_me',
    },
    ingress_event: {
      message_id: 'msg-1',
      source_id: 'slack:C456',
    },
    raw_payload: {
      should_not_pass: true,
    },
  });

  assert.equal(!!out.ok, true);
  assert.equal(String(out.schema_version || ''), HUB_CHANNEL_INGRESS_ENVELOPE_SCHEMA);
  assert.equal(String(out.provider || ''), 'slack');
  assert.equal(String(out.auth_mode || ''), 'slack_signature_v0');
  assert.equal(String(out.replay_mode || ''), 'hub_webhook_replay_guard(event_id|trigger_id|challenge)');
  assert.deepEqual(out.delivery_context, {
    provider: 'slack',
    conversation_id: 'C456',
    account_id: 'T001',
    thread_key: '1710000000.0001',
  });
  assert.equal(String(out.structured_action?.action_name || ''), 'supervisor.status.get');
  assert.equal(Object.prototype.hasOwnProperty.call(out.structured_action || {}, 'ignored_extra'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(out, 'raw_payload'), false);
});

run('XT-W3-24-G/hub channel ingress envelope rejects unknown providers and unsupported envelope types', () => {
  const unknown = normalizeHubChannelIngressEnvelope({
    envelope_type: 'event_callback',
    actor: { provider: 'discord' },
  });
  assert.equal(!!unknown.ok, false);
  assert.equal(String(unknown.deny_code || ''), 'provider_unknown');

  const unsupported = normalizeHubChannelIngressEnvelope({
    envelope_type: 'interactive',
    actor: { provider: 'whatsapp_cloud_api' },
  });
  assert.equal(!!unsupported.ok, false);
  assert.equal(String(unsupported.deny_code || ''), 'envelope_type_unsupported');
});
