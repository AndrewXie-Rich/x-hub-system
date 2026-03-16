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
    assert.equal(String(automated.receipt?.status || ''), 'query_executed');
    assert.equal(String(automated.receipt?.action_name || ''), 'supervisor.status.get');

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
