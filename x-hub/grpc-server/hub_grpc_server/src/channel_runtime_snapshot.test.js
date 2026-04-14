import assert from 'node:assert/strict';

import {
  CHANNEL_RUNTIME_STATUS_SNAPSHOT_SCHEMA,
  buildChannelRuntimeStatusSnapshot,
} from './channel_runtime_snapshot.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('XT-W3-24-G/runtime snapshot aggregates provider rows and keeps unknown provider fail-closed', () => {
  const snapshot = buildChannelRuntimeStatusSnapshot([
    {
      provider: 'slack',
      account_id: 'ops_slack',
      runtime_state: 'ready',
      active_binding_count: 3,
      updated_at_ms: 1000,
    },
    {
      provider: 'tg',
      account_id: 'ops_telegram',
      runtime_state: 'degraded',
      active_binding_count: 2,
      last_error_code: 'provider_timeout',
      updated_at_ms: 1200,
    },
    {
      provider: 'discord',
      account_id: 'rogue',
      runtime_state: 'ready',
      active_binding_count: 99,
      updated_at_ms: 1300,
    },
  ], {
    updated_at_ms: 2000,
  });

  assert.equal(String(snapshot.schema_version || ''), CHANNEL_RUNTIME_STATUS_SNAPSHOT_SCHEMA);
  assert.equal(Number(snapshot.updated_at_ms || 0), 2000);
  assert.equal(Number(snapshot.totals.providers_total || 0), 5);
  assert.equal(Number(snapshot.totals.deliverable_total || 0), 1);
  assert.equal(Number(snapshot.totals.degraded_total || 0), 1);
  assert.equal(Number(snapshot.totals.bindings_total || 0), 5);
  assert.equal(Number(snapshot.totals.unknown_provider_rows || 0), 1);
  assert.equal(Array.isArray(snapshot.unknown_provider_rows), true);
  assert.equal(snapshot.unknown_provider_rows[0].provider_raw, 'discord');

  const slack = snapshot.providers.find((row) => row.provider === 'slack');
  const telegram = snapshot.providers.find((row) => row.provider === 'telegram');
  const cloud = snapshot.providers.find((row) => row.provider === 'whatsapp_cloud_api');

  assert.equal(String(slack?.runtime_state || ''), 'ready');
  assert.equal(!!slack?.delivery_ready, true);
  assert.equal(Number(slack?.active_binding_count || 0), 3);

  assert.equal(String(telegram?.runtime_state || ''), 'degraded');
  assert.equal(String(telegram?.last_error_code || ''), 'provider_timeout');
  assert.equal(!!telegram?.delivery_ready, false);

  assert.equal(String(cloud?.runtime_state || ''), 'planned');
  assert.equal(!!cloud?.release_blocked, true);
  assert.equal(!!cloud?.delivery_ready, false);
});

run('XT-W3-24-G/runtime snapshot defaults known wave1 providers to not_configured when no rows exist', () => {
  const snapshot = buildChannelRuntimeStatusSnapshot([], {
    updated_at_ms: 3000,
  });
  const slack = snapshot.providers.find((row) => row.provider === 'slack');
  const feishu = snapshot.providers.find((row) => row.provider === 'feishu');
  const personal = snapshot.providers.find((row) => row.provider === 'whatsapp_personal_qr');

  assert.equal(String(slack?.runtime_state || ''), 'not_configured');
  assert.equal(String(feishu?.runtime_state || ''), 'not_configured');
  assert.equal(String(personal?.runtime_state || ''), 'planned');
  assert.equal(!!personal?.require_real_evidence, true);
  assert.equal(Number(snapshot.totals.planned_total || 0), 2);
});

run('XT-W3-24-M/runtime snapshot projects delivery dead-letter degradation without hiding command ingress readiness', () => {
  const snapshot = buildChannelRuntimeStatusSnapshot([
    {
      provider: 'slack',
      account_id: 'ops-slack',
      runtime_state: 'ready',
      delivery_ready: true,
      command_entry_ready: true,
      delivery_dead_letter_count: 1,
      manual_retry_available: true,
      last_delivery_error_code: 'slack_rate_limited',
      updated_at_ms: 4100,
    },
  ], {
    updated_at_ms: 5000,
    now_ms: 4500,
  });

  const slack = snapshot.providers.find((row) => row.provider === 'slack');
  assert.equal(String(slack?.runtime_state || ''), 'degraded');
  assert.equal(String(slack?.last_error_code || ''), 'slack_rate_limited');
  assert.equal(!!slack?.delivery_ready, false);
  assert.equal(!!slack?.command_entry_ready, true);
  assert.equal(Number(slack?.delivery_dead_letter_count || 0), 1);
  assert.equal(!!slack?.manual_retry_available, true);
  assert.equal(Number(snapshot.totals.degraded_total || 0), 1);
});

run('XT-W3-24-M/runtime snapshot surfaces invalid token repair hints for governed onboarding repair paths', () => {
  const snapshot = buildChannelRuntimeStatusSnapshot([
    {
      provider: 'feishu',
      account_id: 'tenant_ops',
      runtime_state: 'ingress_ready',
      delivery_ready: false,
      command_entry_ready: false,
      last_error_code: 'verification_token_invalid',
      updated_at_ms: 6100,
    },
    {
      provider: 'whatsapp_cloud_api',
      account_id: 'wa_ops',
      runtime_state: 'ingress_ready',
      delivery_ready: false,
      command_entry_ready: false,
      last_error_code: 'verify_token_invalid',
      updated_at_ms: 6200,
    },
  ], {
    updated_at_ms: 7000,
  });

  const feishu = snapshot.providers.find((row) => row.provider === 'feishu');
  const whatsapp = snapshot.providers.find((row) => row.provider === 'whatsapp_cloud_api');

  assert.equal(
    (feishu?.repair_hints || []).some((item) => String(item || '').includes('HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN')),
    true
  );
  assert.equal(
    (whatsapp?.repair_hints || []).some((item) => String(item || '').includes('HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN')),
    true
  );
});
