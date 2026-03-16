import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import { startPairingHTTPServer } from './pairing_http.js';
import { resolveSupervisorOperatorChannelBinding } from './channel_bindings_store.js';
import { HubDB } from './db.js';
import { createOrTouchChannelOnboardingDiscoveryTicket } from './channel_onboarding_discovery_store.js';
import { getChannelIdentityBinding } from './channel_identity_store.js';
import { getChannelOnboardingAutoBindReceiptByTicketId } from './channel_onboarding_transaction.js';
import { getChannelOnboardingFirstSmokeReceiptByTicketId } from './channel_onboarding_first_smoke.js';
import { listChannelOutboxItems } from './channel_outbox.js';

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
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

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `channel_onboarding_admin_http_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms || 0))));
}

function requestJson({
  method = 'GET',
  url,
  headers = {},
  body,
  timeout_ms = 2_000,
} = {}) {
  const target = new URL(String(url || ''));
  const payload = body == null ? '' : (typeof body === 'string' ? body : JSON.stringify(body));
  const reqHeaders = { ...headers };
  if (payload) {
    if (!reqHeaders['content-type']) reqHeaders['content-type'] = 'application/json; charset=utf-8';
    reqHeaders['content-length'] = String(Buffer.byteLength(payload, 'utf8'));
  }

  return new Promise((resolve, reject) => {
    const req = http.request({
      method: String(method || 'GET').toUpperCase(),
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers: reqHeaders,
      timeout: Math.max(100, Number(timeout_ms || 0)),
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try {
          json = text ? JSON.parse(text) : null;
        } catch {
          json = null;
        }
        resolve({
          status: Number(res.statusCode || 0),
          text,
          json,
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    if (payload) req.write(payload);
    req.end();
  });
}

async function waitForHealth(baseUrl, timeoutMs = 2_000) {
  const deadline = Date.now() + Math.max(200, Number(timeoutMs || 0));
  while (Date.now() < deadline) {
    try {
      const out = await requestJson({ url: `${baseUrl}/health`, timeout_ms: 300 });
      if (out.status === 200) return;
    } catch {
      // ignore
    }
    await sleep(25);
  }
  throw new Error('pairing_server_not_ready');
}

async function withPairingServer(db, fn) {
  const port = 56000 + Math.floor(Math.random() * 6000);
  const baseUrl = `http://127.0.0.1:${port}`;
  await withEnvAsync({
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_HOST: '127.0.0.1',
    HUB_PORT: '50051',
    HUB_ADMIN_TOKEN: 'admin-token-onboarding-http',
    HUB_PAIRING_ALLOWED_CIDRS: 'any',
  }, async () => {
    const stop = startPairingHTTPServer({ db });
    try {
      await waitForHealth(baseUrl, 3_000);
      await fn({ baseUrl });
    } finally {
      try {
        stop?.();
      } catch {
        // ignore
      }
      await sleep(40);
    }
  });
}

await runAsync('XT-W3-24/http admin onboarding endpoints require admin token', async () => {
  const dbPath = makeTmp('db', '.db');
  const db = new HubDB({ dbPath });
  try {
    await withPairingServer(db, async ({ baseUrl }) => {
      const out = await requestJson({
        url: `${baseUrl}/admin/operator-channels/onboarding/tickets`,
      });
      assert.equal(out.status, 401);
      assert.equal(String(out.json?.error?.code || ''), 'unauthenticated');
    });
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});

await runAsync('XT-W3-24/http admin readiness endpoint reports provider setup state', async () => {
  const dbPath = makeTmp('db', '.db');
  const db = new HubDB({ dbPath });
  try {
    await withEnvAsync({
      HUB_SLACK_OPERATOR_REPLY_ENABLE: '1',
      HUB_SLACK_OPERATOR_BOT_TOKEN: 'xoxb-readiness-http',
      HUB_TELEGRAM_OPERATOR_REPLY_ENABLE: '1',
      HUB_TELEGRAM_OPERATOR_BOT_TOKEN: 'telegram-readiness-http',
    }, async () => {
      await withPairingServer(db, async ({ baseUrl }) => {
        const headers = {
          authorization: 'Bearer admin-token-onboarding-http',
        };
        const out = await requestJson({
          url: `${baseUrl}/admin/operator-channels/readiness`,
          headers,
        });
        assert.equal(out.status, 200);
        assert.equal(out.json?.ok, true);
        assert.deepEqual(
          (out.json?.providers || []).map((item) => String(item?.provider || '')),
          ['slack', 'telegram', 'feishu', 'whatsapp_cloud_api']
        );
        const slack = (out.json?.providers || []).find((item) => String(item?.provider || '') === 'slack');
        const feishu = (out.json?.providers || []).find((item) => String(item?.provider || '') === 'feishu');
        assert.equal(slack?.ready, true);
        assert.equal(slack?.credentials_configured, true);
        assert.equal(feishu?.ready, false);
        assert.equal(feishu?.reply_enabled, false);
        assert.equal(
          String(feishu?.remediation_hint || '').includes('HUB_FEISHU_OPERATOR_REPLY_ENABLE=1'),
          true
        );
      });
    });
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});

await runAsync('XT-W3-24/http admin runtime status endpoint reports command entry state', async () => {
  const dbPath = makeTmp('db', '.db');
  const runtimeBaseDir = makeTmp('runtime');
  const db = new HubDB({ dbPath });
  try {
    fs.mkdirSync(runtimeBaseDir, { recursive: true });
    fs.writeFileSync(
      path.join(runtimeBaseDir, 'channel_runtime_accounts_status.json'),
      JSON.stringify({
        schema_version: 'xhub.channel_runtime_accounts_status.v1',
        updated_at_ms: 1710000005000,
        rows: [
          {
            provider: 'slack',
            account_id: 'ops_slack',
            runtime_state: 'ready',
            delivery_ready: true,
            command_entry_ready: true,
            updated_at_ms: 1710000005000,
          },
          {
            provider: 'feishu',
            account_id: 'tenant_ops',
            runtime_state: 'ingress_ready',
            delivery_ready: false,
            command_entry_ready: false,
            last_error_code: 'verification_token_missing',
            updated_at_ms: 1710000004000,
          },
        ],
      }),
      'utf8'
    );

    await withEnvAsync({
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    }, async () => {
      await withPairingServer(db, async ({ baseUrl }) => {
        const headers = {
          authorization: 'Bearer admin-token-onboarding-http',
        };
        const out = await requestJson({
          url: `${baseUrl}/admin/operator-channels/runtime-status`,
          headers,
        });
        assert.equal(out.status, 200);
        assert.equal(out.json?.ok, true);
        const slack = (out.json?.providers || []).find((item) => String(item?.provider || '') === 'slack');
        const feishu = (out.json?.providers || []).find((item) => String(item?.provider || '') === 'feishu');
        assert.equal(String(slack?.runtime_state || ''), 'ready');
        assert.equal(slack?.command_entry_ready, true);
        assert.equal(slack?.delivery_ready, true);
        assert.equal(String(feishu?.runtime_state || ''), 'ingress_ready');
        assert.equal(feishu?.command_entry_ready, false);
        assert.equal(String(feishu?.last_error_code || ''), 'verification_token_missing');
      });
    });
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
    try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

await runAsync('XT-W3-24/http admin onboarding endpoints list detail and approve tickets', async () => {
  const dbPath = makeTmp('db', '.db');
  const db = new HubDB({ dbPath });
  try {
    const seeded = createOrTouchChannelOnboardingDiscoveryTicket(db, {
      request_id: 'disc-http-create-1',
      ticket: {
        provider: 'feishu',
        account_id: 'tenant-ops',
        external_user_id: 'ou_1',
        external_tenant_id: 'tenant-ops',
        conversation_id: 'oc_room_1',
        thread_key: 'om_1',
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

    await withPairingServer(db, async ({ baseUrl }) => {
      const headers = {
        authorization: 'Bearer admin-token-onboarding-http',
      };
      const listed = await requestJson({
        url: `${baseUrl}/admin/operator-channels/onboarding/tickets`,
        headers,
      });
      assert.equal(listed.status, 200);
      assert.equal(Array.isArray(listed.json?.tickets), true);
      assert.equal(listed.json.tickets.length, 1);

      const detailed = await requestJson({
        url: `${baseUrl}/admin/operator-channels/onboarding/tickets/${seeded.ticket.ticket_id}`,
        headers,
      });
      assert.equal(detailed.status, 200);
      assert.equal(String(detailed.json?.ticket?.ticket_id || ''), String(seeded.ticket.ticket_id || ''));
      assert.equal(detailed.json?.latest_decision, null);

      const reviewed = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/operator-channels/onboarding/tickets/${seeded.ticket.ticket_id}/review`,
        headers,
        body: {
          decision: 'approve',
          approved_by_hub_user_id: 'user_ops_admin',
          approved_via: 'hub_local_ui',
          hub_user_id: 'user_ops_alice',
          scope_type: 'project',
          scope_id: 'project_alpha',
          binding_mode: 'thread_binding',
          preferred_device_id: 'xt-alpha-1',
          allowed_actions: ['supervisor.status.get', 'supervisor.blockers.get'],
          grant_profile: 'low_risk_readonly',
          note: 'approved from local hub ui',
        },
      });
      assert.equal(reviewed.status, 200);
      assert.equal(String(reviewed.json?.ticket?.status || ''), 'approved');
      assert.equal(String(reviewed.json?.decision?.decision || ''), 'approve');
      assert.equal(reviewed.json?.automation?.ok, true);
      assert.equal(!!String(reviewed.json?.automation?.ack_outbox_item_id || ''), true);
      assert.equal(!!String(reviewed.json?.automation?.first_smoke_receipt_id || ''), true);
      assert.equal(!!String(reviewed.json?.automation?.first_smoke_outbox_item_id || ''), true);
      assert.equal(reviewed.json?.outbox_flush_scheduled, true);
      assert.equal(
        String(reviewed.json?.automation_state?.first_smoke?.receipt_id || ''),
        String(reviewed.json?.automation?.first_smoke_receipt_id || '')
      );
      assert.deepEqual(
        (reviewed.json?.automation_state?.outbox_items || []).map((item) => String(item?.item_kind || '')).sort(),
        ['onboarding_ack', 'onboarding_first_smoke']
      );
      assert.equal(String(reviewed.json?.automation_state?.delivery_readiness?.provider || ''), 'feishu');
      assert.equal(reviewed.json?.automation_state?.delivery_readiness?.ready, false);
      assert.equal(reviewed.json?.automation_state?.delivery_readiness?.reply_enabled, false);
      assert.equal(reviewed.json?.automation_state?.delivery_readiness?.credentials_configured, false);
      assert.equal(
        String(reviewed.json?.automation_state?.delivery_readiness?.remediation_hint || '').includes('HUB_FEISHU_OPERATOR_REPLY_ENABLE=1'),
        true
      );

      const after = await requestJson({
        url: `${baseUrl}/admin/operator-channels/onboarding/tickets/${seeded.ticket.ticket_id}`,
        headers,
      });
      assert.equal(after.status, 200);
      assert.equal(String(after.json?.ticket?.status || ''), 'approved');
      assert.equal(String(after.json?.latest_decision?.approved_by_hub_user_id || ''), 'user_ops_admin');
      assert.equal(String(after.json?.automation_state?.ticket_id || ''), String(seeded.ticket.ticket_id || ''));
      assert.equal(String(after.json?.automation_state?.first_smoke?.status || ''), 'query_executed');
      assert.deepEqual(
        (after.json?.automation_state?.outbox_items || []).map((item) => String(item?.item_kind || '')).sort(),
        ['onboarding_ack', 'onboarding_first_smoke']
      );
      assert.equal(String(after.json?.automation_state?.delivery_readiness?.provider || ''), 'feishu');
      assert.equal(after.json?.automation_state?.delivery_readiness?.ready, false);

      const identityBinding = getChannelIdentityBinding(db, {
        provider: 'feishu',
        external_user_id: 'ou_1',
        external_tenant_id: 'tenant-ops',
      });
      assert.equal(String(identityBinding?.hub_user_id || ''), 'user_ops_alice');

      const routeBinding = resolveSupervisorOperatorChannelBinding(db, {
        provider: 'feishu',
        account_id: 'tenant-ops',
        conversation_id: 'oc_room_1',
        thread_key: 'om_1',
        channel_scope: 'group',
      });
      assert.equal(String(routeBinding.binding_match_mode || ''), 'exact_thread');
      assert.deepEqual(routeBinding.binding?.allowed_actions || [], ['supervisor.status.get', 'supervisor.blockers.get']);

      const autoBindReceipt = getChannelOnboardingAutoBindReceiptByTicketId(db, {
        ticket_id: seeded.ticket.ticket_id,
      });
      assert.equal(String(autoBindReceipt?.status || ''), 'applied');

      await sleep(40);

      const firstSmokeReceipt = getChannelOnboardingFirstSmokeReceiptByTicketId(db, {
        ticket_id: seeded.ticket.ticket_id,
      });
      assert.equal(String(firstSmokeReceipt?.ticket_id || ''), String(seeded.ticket.ticket_id || ''));
      assert.equal(String(firstSmokeReceipt?.status || ''), 'query_executed');
      assert.equal(String(firstSmokeReceipt?.action_name || ''), 'supervisor.status.get');
      assert.equal(String(firstSmokeReceipt?.ack_outbox_item_id || ''), String(reviewed.json?.automation?.ack_outbox_item_id || ''));
      assert.equal(String(firstSmokeReceipt?.smoke_outbox_item_id || ''), String(reviewed.json?.automation?.first_smoke_outbox_item_id || ''));

      const outboxItems = listChannelOutboxItems(db, {
        ticket_id: seeded.ticket.ticket_id,
        limit: 10,
      });
      assert.equal(outboxItems.length, 2);
      assert.deepEqual(
        outboxItems.map((item) => String(item.item_kind || '')).sort(),
        ['onboarding_ack', 'onboarding_first_smoke']
      );
      assert.equal(outboxItems.every((item) => String(item.status || '') === 'pending'), true);
      assert.equal(outboxItems.every((item) => Number(item.attempt_count || 0) >= 1), true);
      assert.equal(
        outboxItems.every((item) => String(item.last_error_code || '') === 'provider_delivery_not_configured'),
        true
      );
    });
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});

await runAsync('XT-W3-24/http admin onboarding endpoints fail closed on unsafe approval actions', async () => {
  const dbPath = makeTmp('db', '.db');
  const db = new HubDB({ dbPath });
  try {
    const seeded = createOrTouchChannelOnboardingDiscoveryTicket(db, {
      request_id: 'disc-http-create-unsafe-1',
      ticket: {
        provider: 'slack',
        account_id: 'T001',
        external_user_id: 'U123',
        external_tenant_id: 'T001',
        conversation_id: 'C001',
        thread_key: '171.1',
        ingress_surface: 'group',
        first_message_preview: 'deploy execute',
        proposed_scope_type: 'project',
        proposed_scope_id: 'project_alpha',
      },
      audit: {
        app_id: 'test',
      },
    });
    assert.equal(!!seeded.ok, true);

    await withPairingServer(db, async ({ baseUrl }) => {
      const headers = {
        authorization: 'Bearer admin-token-onboarding-http',
      };
      const reviewed = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/operator-channels/onboarding/tickets/${seeded.ticket.ticket_id}/review`,
        headers,
        body: {
          decision: 'approve',
          approved_by_hub_user_id: 'user_ops_admin',
          approved_via: 'hub_local_ui',
          hub_user_id: 'user_ops_alice',
          scope_type: 'project',
          scope_id: 'project_alpha',
          binding_mode: 'thread_binding',
          allowed_actions: ['deploy.execute'],
        },
      });
      assert.equal(reviewed.status, 400);
      assert.equal(String(reviewed.json?.error?.code || ''), 'allowed_actions_unsafe');
    });
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});

await runAsync('XT-W3-24/http admin onboarding retry endpoint delivers pending outbox after credentials are configured', async () => {
  const dbPath = makeTmp('db', '.db');
  const db = new HubDB({ dbPath });
  try {
    const seeded = createOrTouchChannelOnboardingDiscoveryTicket(db, {
      request_id: 'disc-http-retry-create-1',
      ticket: {
        provider: 'slack',
        account_id: 'T_OPS',
        external_user_id: 'U999',
        external_tenant_id: 'T_OPS',
        conversation_id: 'C_retry_http',
        thread_key: '171.5',
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

    await withPairingServer(db, async ({ baseUrl }) => {
      const headers = {
        authorization: 'Bearer admin-token-onboarding-http',
      };
      const reviewed = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/operator-channels/onboarding/tickets/${seeded.ticket.ticket_id}/review`,
        headers,
        body: {
          decision: 'approve',
          approved_by_hub_user_id: 'user_ops_admin',
          approved_via: 'hub_local_ui',
          hub_user_id: 'user_ops_alice',
          scope_type: 'project',
          scope_id: 'project_alpha',
          binding_mode: 'thread_binding',
          allowed_actions: ['supervisor.status.get', 'supervisor.blockers.get'],
        },
      });
      assert.equal(reviewed.status, 200);

      await sleep(40);

      let fetchCalls = 0;
      await withEnvAsync({
        HUB_SLACK_OPERATOR_REPLY_ENABLE: '1',
        HUB_SLACK_OPERATOR_BOT_TOKEN: 'xoxb-http-retry',
      }, async () => {
        await withFetchAsync(async (url, options = {}) => {
          fetchCalls += 1;
          assert.equal(String(url || '').endsWith('/chat.postMessage'), true);
          assert.equal(String(options?.headers?.authorization || ''), 'Bearer xoxb-http-retry');
          return {
            ok: true,
            async text() {
              return JSON.stringify({
                ok: true,
                channel: 'C_retry_http',
                ts: `171.5.${fetchCalls}`,
              });
            },
          };
        }, async () => {
          const retried = await requestJson({
            method: 'POST',
            url: `${baseUrl}/admin/operator-channels/onboarding/tickets/${seeded.ticket.ticket_id}/retry-outbox`,
            headers,
            body: {
              request_id: 'disc-http-retry-1',
              user_id: 'user_ops_admin',
              app_id: 'hub_local_ui',
            },
          });
          assert.equal(retried.status, 200);
          assert.equal(retried.json?.ok, true);
          assert.equal(Number(retried.json?.delivered_count || 0), 2);
          assert.equal(Number(retried.json?.pending_count || 0), 0);
          assert.equal(Number(retried.json?.automation_state?.outbox_delivered_count || 0), 2);
          assert.equal(Number(retried.json?.automation_state?.outbox_pending_count || 0), 0);
          assert.equal(String(retried.json?.automation_state?.delivery_readiness?.provider || ''), 'slack');
          assert.equal(retried.json?.automation_state?.delivery_readiness?.ready, true);
          assert.equal(retried.json?.automation_state?.delivery_readiness?.reply_enabled, true);
          assert.equal(retried.json?.automation_state?.delivery_readiness?.credentials_configured, true);
          assert.equal(
            (retried.json?.automation_state?.outbox_items || []).every((item) => String(item?.status || '') === 'delivered'),
            true
          );
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
    });
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});
