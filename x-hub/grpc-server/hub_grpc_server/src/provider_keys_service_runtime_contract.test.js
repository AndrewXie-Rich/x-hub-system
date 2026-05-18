import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import {
  addProviderKey,
  invalidateProviderKeyCache,
  recordProviderKeyImportSourceStatus,
  registerProviderKeyImportSource,
} from './provider_key_store.js';

function run(name, fn) {
  try {
    const maybePromise = fn();
    if (maybePromise && typeof maybePromise.then === 'function') {
      return maybePromise.then(() => {
        process.stdout.write(`ok - ${name}\n`);
      }).catch((error) => {
        process.stderr.write(`not ok - ${name}\n`);
        throw error;
      });
    }
    process.stdout.write(`ok - ${name}\n`);
    return Promise.resolve();
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv)) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  };
  try {
    const result = fn();
    if (result && typeof result.then === 'function') {
      return result.finally(restore);
    }
    restore();
    return result;
  } catch (error) {
    restore();
    throw error;
  }
}

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function makeTransportCall(request = {}, token = '') {
  return {
    request,
    metadata: {
      get(key) {
        if (String(key || '').toLowerCase() !== 'authorization') return [];
        return token ? [`Bearer ${token}`] : [];
      },
    },
    getPeer() {
      return 'ipv4:127.0.0.1:54321';
    },
    sendMetadata() {},
    getDeadline() {
      return Date.now() + 1_000;
    },
  };
}

async function invokeUnary(method, call) {
  return await new Promise((resolve) => {
    method(call, (err, res) => resolve({ err, res }));
  });
}

await run('HubProviderKeys runtime snapshot and route decision expose import/runtime truth additively', async () => {
  const runtimeBaseDir = makeTempDir('xhub-provider-keys-runtime-');
  const dbPath = path.join(makeTempDir('xhub-provider-keys-db-'), 'hub.sqlite3');
  invalidateProviderKeyCache();

  await withEnv(
    {
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_CLIENT_TOKEN: 'client-secret',
      HUB_ADMIN_TOKEN: 'admin-secret',
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    async () => {
      const db = new HubDB({ dbPath });
      const impl = makeServices({ db, bus: new HubEventBus() });
      try {
        const sourceRef = '/tmp/auth19.json';
        const authDirRef = '/tmp/auth';
        const sourceKey = `auth_dir:${authDirRef}`;
        const retryAtMs = Date.now() + 60_000;
        const addResult = addProviderKey(runtimeBaseDir, {
          provider: 'gemini',
          email: 'vision@test.local',
          api_key: 'gemini-access-token-123',
          refresh_token: 'gemini-refresh-token-123',
          auth_type: 'oauth',
          oauth_source_key: 'gemini',
          oauth_refresh_config: {
            client_id: 'gemini-client-id',
          },
          source_type: 'auth_file',
          source_ref: sourceRef,
          source_owners: [sourceKey],
          quota: {
            daily_token_cap: 10000,
            daily_tokens_used: 4250,
            daily_tokens_remaining: 5750,
            usage_windows: [
              {
                key: 'rate_limit:primary:18000',
                source: 'rate_limit',
                window_key: 'primary',
                label: 'primary 5-hour window',
                limit_window_seconds: 5 * 60 * 60,
                used_percent: 42.5,
                used_basis_points: 4250,
                remaining_basis_points: 5750,
                limited: false,
                reset_at_ms: retryAtMs,
                updated_at_ms: retryAtMs - 60_000,
              },
              {
                key: 'rate_limit:secondary:604800',
                source: 'rate_limit',
                window_key: 'secondary',
                label: 'secondary 7-day window',
                limit_window_seconds: 7 * 24 * 60 * 60,
                used_percent: 71.25,
                used_basis_points: 7125,
                remaining_basis_points: 2875,
                limited: false,
                reset_at_ms: retryAtMs + 600_000,
                updated_at_ms: retryAtMs - 60_000,
              },
            ],
          },
          refresh_state: {
            status: 'idle',
          },
          error_state: {
            status: 'healthy',
            reason_code: '',
            last_error_code: '',
            last_error_at_ms: 0,
            next_retry_at_ms: 0,
            retry_at_source: '',
            status_message: '',
          },
          model_states: {
            'gemini-2.0-flash': {
              status: 'cooldown',
              reason_code: 'provider_timeout',
              status_message: 'provider timeout',
              next_retry_at_ms: retryAtMs,
              retry_at_source: 'scheduler',
              updated_at_ms: Date.now(),
            },
          },
        });
        assert.equal(addResult.ok, true);

        const registered = registerProviderKeyImportSource(runtimeBaseDir, {
          kind: 'auth_dir',
          source_ref: authDirRef,
        });
        assert.equal(registered.ok, true);

        const importStatus = recordProviderKeyImportSourceStatus(runtimeBaseDir, {
          kind: 'auth_dir',
          source_ref: authDirRef,
        }, {
          state: 'sync_failed',
          last_sync_at_ms: Date.now(),
          last_imported_count: 1,
          last_error_count: 1,
          last_errors: ['token_expired'],
          refresh_owned_account_count: true,
        });
        assert.equal(importStatus.ok, true);

        const runtimeSnapshot = await invokeUnary(
          impl.HubProviderKeys.GetProviderKeyRuntimeSnapshot,
          makeTransportCall({}, 'client-secret')
        );
        assert.equal(runtimeSnapshot.err, null);
        assert.equal(Number(runtimeSnapshot.res.accounts.length || 0), 1);
        assert.equal(Number(runtimeSnapshot.res.import_source_statuses.length || 0), 1);
        assert.equal(String(runtimeSnapshot.res.accounts[0].provider || ''), 'gemini');
        assert.deepEqual(
          runtimeSnapshot.res.accounts[0].required_refresh_metadata || [],
          ['client_secret', 'token_uri']
        );
        assert.deepEqual(runtimeSnapshot.res.accounts[0].source_owners || [], [sourceKey]);
        assert.equal(String(runtimeSnapshot.res.accounts[0].refresh_state?.status || ''), 'idle');
        const usageWindows = runtimeSnapshot.res.accounts[0].quota?.usage_windows || [];
        assert.equal(usageWindows.length, 2);
        assert.equal(String(usageWindows[0].window_key || ''), 'primary');
        assert.equal(Number(usageWindows[0].limit_window_seconds || 0), 5 * 60 * 60);
        assert.equal(Number(usageWindows[0].used_percent || 0), 42.5);
        assert.equal(Number(usageWindows[0].used_basis_points || 0), 4250);
        assert.equal(String(usageWindows[1].window_key || ''), 'secondary');
        assert.equal(Number(usageWindows[1].limit_window_seconds || 0), 7 * 24 * 60 * 60);
        assert.equal(Number(usageWindows[1].used_percent || 0), 71.25);
        assert.equal(Number(usageWindows[1].remaining_basis_points || 0), 2875);
        assert.equal(
          String(runtimeSnapshot.res.import_source_statuses[0].source_key || ''),
          sourceKey
        );
        assert.deepEqual(runtimeSnapshot.res.import_source_statuses[0].last_errors || [], ['token_expired']);

        const routeDecision = await invokeUnary(
          impl.HubProviderKeys.GetProviderKeyRouteDecision,
          makeTransportCall({ model_id: 'gemini-2.0-flash' }, 'client-secret')
        );
        assert.equal(routeDecision.err, null);
        assert.equal(String(routeDecision.res.decision?.requested_provider || ''), 'gemini');
        assert.equal(String(routeDecision.res.decision?.selected_account_key || ''), '');
        assert.equal(String(routeDecision.res.decision?.fallback_reason_code || ''), 'all_keys_in_cooldown');
        assert.equal(Number(routeDecision.res.decision?.available_count || 0), 0);
        assert.equal(Number(routeDecision.res.decision?.total_count || 0), 1);
        assert.equal(Number(routeDecision.res.decision?.candidates?.length || 0), 1);
        assert.equal(String(routeDecision.res.decision?.candidates?.[0]?.state || ''), 'cooldown');
        assert.equal(String(routeDecision.res.decision?.candidates?.[0]?.reason_code || ''), 'provider_timeout');
        assert.equal(String(routeDecision.res.decision?.candidates?.[0]?.retry_at_source || ''), 'scheduler');
        assert.equal(
          String(routeDecision.res.decision?.candidates?.[0]?.model_state_key || ''),
          'gemini-2.0-flash'
        );
        assert.deepEqual(
          routeDecision.res.decision?.candidates?.[0]?.required_refresh_metadata || [],
          ['client_secret', 'token_uri']
        );
      } finally {
        db.close();
      }
    }
  );

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});

await run('HubProviderKeys read snapshots can be served by Rust provider key snapshot bridge', async () => {
  const runtimeBaseDir = makeTempDir('xhub-provider-keys-rust-snapshot-');
  const dbPath = path.join(makeTempDir('xhub-provider-keys-rust-db-'), 'hub.sqlite3');
  const calls = [];
  const providerKeySnapshotBridge = {
    config: { enabled: true },
    async listProviderKeyPools(input) {
      calls.push(['pools', input]);
      return {
        ok: true,
        used: true,
        pools: [
          {
            pool_id: 'shared',
            capability_pool_id: 'shared#openai:gpt-5.4',
            provider: 'openai',
            model_id: 'gpt-5.4',
            model_family: 'gpt-5.4',
            state: 'ready',
            total_accounts: 2,
            ready_accounts: 2,
            members: [
              {
                account_key: 'acct-rust',
                provider: 'openai',
                state: 'ready',
                api_key_redacted: 'sk-r...test',
              },
            ],
          },
        ],
        updated_at_ms: 321,
        routing_strategy: 'fill-first',
      };
    },
    async getProviderKeyRuntimeSnapshot(input) {
      calls.push(['runtime', input]);
      return {
        ok: true,
        used: true,
        accounts: [
          {
            account_key: 'acct-rust',
            provider: 'openai',
            email: 'rust@test.local',
            enabled: true,
            auth_type: 'oauth',
            quota: {
              usage_windows: [
                {
                  key: 'rate_limit:5h',
                  window_key: '5h',
                  limit_window_seconds: 18_000,
                  used_percent: 33.5,
                },
              ],
            },
            api_key_redacted: 'sk-r...test',
          },
        ],
        import_source_statuses: [],
        updated_at_ms: 654,
        global_routing_strategy: 'priority',
        providers: [{ provider: 'openai', total_accounts: 1, enabled_accounts: 1 }],
      };
    },
  };

  await withEnv(
    {
      HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      HUB_CLIENT_TOKEN: 'client-secret',
      HUB_ADMIN_TOKEN: 'admin-secret',
      HUB_GRPC_TLS_MODE: '',
      HUB_GRPC_CERT: '',
      HUB_GRPC_KEY: '',
      HUB_GRPC_CA: '',
    },
    async () => {
      const db = new HubDB({ dbPath });
      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        providerKeySnapshotBridge,
      });
      try {
        const pools = await invokeUnary(
          impl.HubProviderKeys.ListProviderKeyPools,
          makeTransportCall({ provider: 'openai', model_id: 'gpt-5.4', include_members: true }, 'client-secret')
        );
        assert.equal(pools.err, null);
        assert.equal(pools.res.updated_at_ms, 321);
        assert.equal(pools.res.pools[0].capability_pool_id, 'shared#openai:gpt-5.4');
        assert.equal(pools.res.pools[0].members[0].account_key, 'acct-rust');

        const runtime = await invokeUnary(
          impl.HubProviderKeys.GetProviderKeyRuntimeSnapshot,
          makeTransportCall({ provider: 'openai' }, 'client-secret')
        );
        assert.equal(runtime.err, null);
        assert.equal(runtime.res.updated_at_ms, 654);
        assert.equal(runtime.res.global_routing_strategy, 'priority');
        assert.equal(runtime.res.accounts[0].quota.usage_windows[0].window_key, '5h');
        assert.equal(runtime.res.providers[0].provider, 'openai');

        assert.equal(calls.length, 2);
        assert.equal(calls[0][0], 'pools');
        assert.equal(calls[0][1].runtimeBaseDir, runtimeBaseDir);
        assert.equal(calls[1][0], 'runtime');
      } finally {
        db.close();
      }
    }
  );

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});
