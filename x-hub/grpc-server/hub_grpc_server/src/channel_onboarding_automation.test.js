import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { createOrTouchChannelOnboardingDiscoveryTicket, reviewChannelOnboardingDiscoveryTicket } from './channel_onboarding_discovery_store.js';
import { getChannelOnboardingFirstSmokeReceiptByTicketId } from './channel_onboarding_first_smoke.js';
import {
  flushChannelOutboxForTicket,
  retryChannelOnboardingOutbox,
  runApprovedChannelOnboardingAutomation,
} from './channel_onboarding_automation.js';
import { listChannelOutboxItems } from './channel_outbox.js';
import { getChannelOnboardingAutomationState } from './channel_onboarding_status_view.js';

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `channel_onboarding_automation_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

async function withEnvAsync(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

async function withFetchAsync(tempFetch, fn) {
  const previous = globalThis.fetch;
  globalThis.fetch = tempFetch;
  try {
    return await fn();
  } finally {
    globalThis.fetch = previous;
  }
}

await runAsync('XT-W3-24/automation queues first smoke and leaves outbox pending without provider credentials', async () => {
  const dbPath = makeTmp('db', '.db');
  const runtimeBaseDir = makeTmp('runtime');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const db = new HubDB({ dbPath });

  try {
    const seeded = createOrTouchChannelOnboardingDiscoveryTicket(db, {
      request_id: 'automation-test-discovery-1',
      ticket: {
        provider: 'slack',
        account_id: 'T_OPS',
        external_user_id: 'U_ops_1',
        external_tenant_id: 'T_OPS',
        conversation_id: 'C_ops_1',
        thread_key: '171.42',
        ingress_surface: 'group',
        first_message_preview: 'status',
        proposed_scope_type: 'project',
        proposed_scope_id: 'project_alpha',
      },
      audit: {
        app_id: 'test',
      },
    });
    assert.equal(!!seeded.ok, true);

    const reviewed = reviewChannelOnboardingDiscoveryTicket(db, {
      ticket_id: seeded.ticket.ticket_id,
      decision: {
        decision: 'approve',
        approved_by_hub_user_id: 'user_ops_admin',
        approved_via: 'test',
        hub_user_id: 'user_ops_alice',
        scope_type: 'project',
        scope_id: 'project_alpha',
        binding_mode: 'thread_binding',
        preferred_device_id: 'xt-alpha-1',
        allowed_actions: ['supervisor.status.get', 'supervisor.blockers.get'],
        grant_profile: 'low_risk_readonly',
      },
      request_id: 'automation-test-review-1',
      audit: {
        device_id: 'test',
        user_id: 'user_ops_admin',
        app_id: 'test',
      },
    });
    assert.equal(!!reviewed.ok, true);

    const now = Date.now();
    const lineage = db.upsertProjectLineage({
      request_id: 'automation-test-lineage-1',
      device_id: 'xt-alpha-1',
      user_id: 'xt-owner',
      app_id: 'x_terminal',
      root_project_id: 'project_alpha',
      parent_project_id: '',
      project_id: 'project_alpha',
      status: 'active',
      created_at_ms: now - 4_000,
    });
    assert.equal(!!lineage.accepted, true);
    const heartbeat = db.upsertProjectHeartbeat({
      request_id: 'automation-test-heartbeat-1',
      device_id: 'xt-alpha-1',
      user_id: 'xt-owner',
      app_id: 'x_terminal',
      root_project_id: 'project_alpha',
      parent_project_id: '',
      project_id: 'project_alpha',
      queue_depth: 2,
      oldest_wait_ms: 6_000,
      blocked_reason: ['awaiting_security_review'],
      next_actions: ['approve release grant'],
      risk_tier: 'medium',
      heartbeat_seq: 1,
      sent_at_ms: now,
    });
    assert.equal(!!heartbeat.accepted, true);
    const heartbeatGovernance = db.upsertCanonicalItem({
      scope: 'project',
      device_id: 'xt-alpha-1',
      user_id: 'xt-owner',
      app_id: 'x_terminal',
      project_id: 'project_alpha',
      key: 'xterminal.project.heartbeat.summary_json',
      value: JSON.stringify({
        schema_version: 'xt.project_heartbeat.v1',
        project_id: 'project_alpha',
        project_name: 'Alpha',
        updated_at_ms: now,
        last_heartbeat_at_ms: now,
        status_digest: 'Core loop advancing',
        current_state_summary: 'Project is actively moving through the build lane.',
        next_step_summary: 'Queue the next governed pulse review.',
        blocker_summary: 'awaiting_security_review',
        latest_quality_band: 'usable',
        latest_quality_score: 71,
        weak_reasons: ['evidence_thin'],
        open_anomaly_types: ['stale_repeat'],
        project_phase: 'build',
        execution_status: 'active',
        risk_tier: 'medium',
        cadence: {
          reviewPulse: {
            dimension: 'review_pulse',
            configuredSeconds: 900,
            recommendedSeconds: 600,
            effectiveSeconds: 600,
            effectiveReasonCodes: ['quality_usable'],
            nextDueAtMs: now + 600_000,
            nextDueReasonCodes: ['pulse_due_window'],
            isDue: true,
          },
        },
        next_review_kind: 'review_pulse',
        next_review_due_at_ms: now + 600_000,
        next_review_due: true,
      }),
      pinned: false,
    });
    assert.equal(String(heartbeatGovernance?.key || ''), 'xterminal.project.heartbeat.summary_json');

    const automated = runApprovedChannelOnboardingAutomation(db, {
      ticket: reviewed.ticket,
      decision: reviewed.decision,
      auto_bind_receipt: reviewed.auto_bind_receipt,
      request_id: 'automation-test-run-1',
      runtimeBaseDir,
      audit: {
        device_id: 'test',
        user_id: 'user_ops_admin',
        app_id: 'test',
      },
    });
    assert.equal(!!automated.ok, true);
    assert.equal(String(automated.ack_item?.item_kind || ''), 'onboarding_ack');
    assert.equal(String(automated.smoke_item?.item_kind || ''), 'onboarding_first_smoke');
    assert.match(String(automated.ack_item?.payload?.text || ''), /Approval Recorded/);
    assert.match(String(automated.ack_item?.payload?.text || ''), /approval_recorded_pending_smoke/);
    assert.doesNotMatch(String(automated.ack_item?.payload?.text || ''), /Operator Channel Connected/);
    assert.equal(String(automated.receipt?.status || ''), 'query_executed');
    assert.equal(String(automated.receipt?.action_name || ''), 'supervisor.status.get');
    const heartbeatGovernanceSnapshot = JSON.parse(
      String(automated.receipt?.result?.execution?.query?.heartbeat_governance_snapshot_json || '{}')
    );
    assert.equal(String(heartbeatGovernanceSnapshot.project_id || ''), 'project_alpha');
    assert.equal(String(heartbeatGovernanceSnapshot.latest_quality_band || ''), 'usable');
    assert.deepEqual(heartbeatGovernanceSnapshot.open_anomaly_types || [], ['stale_repeat']);
    assert.equal(String(heartbeatGovernanceSnapshot.next_review_due?.kind || ''), 'review_pulse');
    assert.match(String(automated.smoke_item?.payload?.text || ''), /Review pressure: quality=usable anomalies=stale_repeat/);
    assert.match(String(automated.smoke_item?.payload?.text || ''), /Next review: review_pulse due=yes/);

    const storedReceipt = getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
      ticket_id: seeded.ticket.ticket_id,
    });
    assert.equal(String(storedReceipt?.receipt_id || ''), String(automated.receipt?.receipt_id || ''));
    assert.equal(String(storedReceipt?.ack_outbox_item_id || ''), String(automated.ack_item?.item_id || ''));
    assert.equal(String(storedReceipt?.smoke_outbox_item_id || ''), String(automated.smoke_item?.item_id || ''));

    const flushed = await flushChannelOutboxForTicket(db, {
      ticket_id: seeded.ticket.ticket_id,
      request_id: 'automation-test-flush-1',
      env: {},
      fetch_impl: async () => {
        throw new Error('fetch_should_not_be_called_without_credentials');
      },
      audit: {
        device_id: 'test',
        user_id: 'user_ops_admin',
        app_id: 'test',
      },
    });
    assert.equal(!!flushed.ok, true);
    assert.equal(flushed.delivered.length, 0);
    assert.equal(flushed.pending.length, 2);

    const outboxItems = listChannelOutboxItems(db, {
      ticket_id: seeded.ticket.ticket_id,
      limit: 10,
    });
    assert.equal(outboxItems.length, 2);
    assert.equal(outboxItems.every((item) => String(item.status || '') === 'pending'), true);
    assert.equal(outboxItems.every((item) => Number(item.attempt_count || 0) === 1), true);
    assert.equal(
      outboxItems.every((item) => String(item.last_error_code || '') === 'provider_delivery_not_configured'),
      true
    );

    const automationState = getChannelOnboardingAutomationState(db, {
      ticket_id: seeded.ticket.ticket_id,
      env: {},
    });
    assert.equal(String(automationState?.delivery_readiness?.provider || ''), 'slack');
    assert.equal(automationState?.delivery_readiness?.ready, false);
    assert.equal(automationState?.delivery_readiness?.reply_enabled, true);
    assert.equal(automationState?.delivery_readiness?.credentials_configured, false);
    assert.equal(
      String(automationState?.delivery_readiness?.remediation_hint || '').includes('HUB_SLACK_OPERATOR_BOT_TOKEN'),
      true
    );
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

await runAsync('XT-W3-24/automation reports runner-not-ready first smoke without describing the channel as already connected', async () => {
  const dbPath = makeTmp('db', '.db');
  const runtimeBaseDir = makeTmp('runtime');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const db = new HubDB({ dbPath });

  try {
    const seeded = createOrTouchChannelOnboardingDiscoveryTicket(db, {
      request_id: 'automation-test-discovery-runner-1',
      ticket: {
        provider: 'slack',
        account_id: 'T_DEVICE',
        external_user_id: 'U_device_1',
        external_tenant_id: 'T_DEVICE',
        conversation_id: 'C_device_1',
        thread_key: '171.128',
        ingress_surface: 'group',
        first_message_preview: 'device doctor',
        proposed_scope_type: 'device',
        proposed_scope_id: 'xt-alpha-1',
      },
      audit: {
        app_id: 'test',
      },
    });
    assert.equal(!!seeded.ok, true);

    const reviewed = reviewChannelOnboardingDiscoveryTicket(db, {
      ticket_id: seeded.ticket.ticket_id,
      decision: {
        decision: 'approve',
        approved_by_hub_user_id: 'user_ops_admin',
        approved_via: 'test',
        hub_user_id: 'user_ops_alice',
        scope_type: 'device',
        scope_id: 'xt-alpha-1',
        binding_mode: 'thread_binding',
        preferred_device_id: 'xt-alpha-1',
        allowed_actions: ['device.doctor.get'],
        grant_profile: 'low_risk_diagnostics',
      },
      request_id: 'automation-test-review-runner-1',
      audit: {
        device_id: 'test',
        user_id: 'user_ops_admin',
        app_id: 'test',
      },
    });
    assert.equal(!!reviewed.ok, true);

    const automated = runApprovedChannelOnboardingAutomation(db, {
      ticket: reviewed.ticket,
      decision: reviewed.decision,
      auto_bind_receipt: reviewed.auto_bind_receipt,
      request_id: 'automation-test-run-runner-1',
      runtimeBaseDir,
      audit: {
        device_id: 'test',
        user_id: 'user_ops_admin',
        app_id: 'test',
      },
    });
    assert.equal(!!automated.ok, true);
    assert.match(String(automated.ack_item?.payload?.text || ''), /Approval Recorded/);
    assert.doesNotMatch(String(automated.ack_item?.payload?.text || ''), /Connected/);
    assert.equal(String(automated.receipt?.status || ''), 'route_blocked');
    assert.equal(String(automated.receipt?.route_mode || ''), 'runner_not_ready');
    assert.equal(String(automated.receipt?.deny_code || ''), 'runner_device_missing');
    assert.match(String(automated.receipt?.remediation_hint || ''), /trusted runner/i);
    assert.match(String(automated.smoke_item?.payload?.text || ''), /Route Blocked/);
    assert.match(String(automated.smoke_item?.payload?.text || ''), /status=route_blocked/);

    const storedReceipt = getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
      ticket_id: seeded.ticket.ticket_id,
    });
    assert.equal(String(storedReceipt?.status || ''), 'route_blocked');
    assert.equal(String(storedReceipt?.route_mode || ''), 'runner_not_ready');
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

await runAsync('XT-W3-24/automation retry delivers pending onboarding replies after provider credentials are configured', async () => {
  const dbPath = makeTmp('db', '.db');
  const runtimeBaseDir = makeTmp('runtime');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const db = new HubDB({ dbPath });

  try {
    const seeded = createOrTouchChannelOnboardingDiscoveryTicket(db, {
      request_id: 'automation-test-discovery-2',
      ticket: {
        provider: 'slack',
        account_id: 'T_OPS',
        external_user_id: 'U_ops_2',
        external_tenant_id: 'T_OPS',
        conversation_id: 'C_ops_retry',
        thread_key: '171.84',
        ingress_surface: 'group',
        first_message_preview: 'status',
        proposed_scope_type: 'project',
        proposed_scope_id: 'project_alpha',
      },
      audit: {
        app_id: 'test',
      },
    });
    assert.equal(!!seeded.ok, true);

    const reviewed = reviewChannelOnboardingDiscoveryTicket(db, {
      ticket_id: seeded.ticket.ticket_id,
      decision: {
        decision: 'approve',
        approved_by_hub_user_id: 'user_ops_admin',
        approved_via: 'test',
        hub_user_id: 'user_ops_alice',
        scope_type: 'project',
        scope_id: 'project_alpha',
        binding_mode: 'thread_binding',
        preferred_device_id: 'xt-alpha-1',
        allowed_actions: ['supervisor.status.get', 'supervisor.blockers.get'],
        grant_profile: 'low_risk_readonly',
      },
      request_id: 'automation-test-review-2',
      audit: {
        device_id: 'test',
        user_id: 'user_ops_admin',
        app_id: 'test',
      },
    });
    assert.equal(!!reviewed.ok, true);

    const automated = runApprovedChannelOnboardingAutomation(db, {
      ticket: reviewed.ticket,
      decision: reviewed.decision,
      auto_bind_receipt: reviewed.auto_bind_receipt,
      request_id: 'automation-test-run-2',
      runtimeBaseDir,
      audit: {
        device_id: 'test',
        user_id: 'user_ops_admin',
        app_id: 'test',
      },
    });
    assert.equal(!!automated.ok, true);

    const firstAttempt = await flushChannelOutboxForTicket(db, {
      ticket_id: seeded.ticket.ticket_id,
      request_id: 'automation-test-flush-2a',
      env: {},
      fetch_impl: async () => {
        throw new Error('fetch_should_not_be_called_without_credentials');
      },
      audit: {
        device_id: 'test',
        user_id: 'user_ops_admin',
        app_id: 'test',
      },
    });
    assert.equal(firstAttempt.delivered.length, 0);
    assert.equal(firstAttempt.pending.length, 2);

    let fetchCalls = 0;
    await withEnvAsync({
      HUB_SLACK_OPERATOR_REPLY_ENABLE: '1',
      HUB_SLACK_OPERATOR_BOT_TOKEN: 'xoxb-test-token',
    }, async () => {
      await withFetchAsync(async (url, options = {}) => {
        fetchCalls += 1;
        assert.equal(String(url || '').endsWith('/chat.postMessage'), true);
        assert.equal(String(options?.headers?.authorization || ''), 'Bearer xoxb-test-token');
        return {
          ok: true,
          async text() {
            return JSON.stringify({
              ok: true,
              channel: 'C_ops_retry',
              ts: `171.84.${fetchCalls}`,
            });
          },
        };
      }, async () => {
        const retried = await retryChannelOnboardingOutbox(db, {
          ticket: reviewed.ticket,
          request_id: 'automation-test-retry-2',
          audit: {
            device_id: 'test',
            user_id: 'user_ops_admin',
            app_id: 'test',
          },
        });
        assert.equal(!!retried.ok, true);
        assert.equal(retried.delivered_count, 2);
        assert.equal(retried.pending_count, 0);
        assert.equal(retried.automation_state?.outbox_delivered_count, 2);
        assert.equal(retried.automation_state?.outbox_pending_count, 0);
        assert.equal(String(retried.automation_state?.delivery_readiness?.provider || ''), 'slack');
        assert.equal(retried.automation_state?.delivery_readiness?.ready, true);
        assert.equal(retried.automation_state?.delivery_readiness?.reply_enabled, true);
        assert.equal(retried.automation_state?.delivery_readiness?.credentials_configured, true);
        assert.equal(String(retried.automation_state?.delivery_readiness?.deny_code || ''), '');
      });
    });
    assert.equal(fetchCalls, 2);

    const outboxItems = listChannelOutboxItems(db, {
      ticket_id: seeded.ticket.ticket_id,
      limit: 10,
    });
    assert.equal(outboxItems.length, 2);
    assert.equal(outboxItems.every((item) => String(item.status || '') === 'delivered'), true);
    assert.equal(outboxItems.every((item) => Number(item.attempt_count || 0) === 2), true);
    assert.equal(outboxItems.every((item) => String(item.last_error_code || '') === ''), true);
    assert.equal(outboxItems.every((item) => !!String(item.provider_message_ref || '')), true);
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});
