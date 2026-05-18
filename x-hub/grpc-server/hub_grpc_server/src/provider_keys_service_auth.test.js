import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import {
  addProviderKey,
  getKeyUsage,
  invalidateProviderKeyCache,
  updateProviderKey,
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

async function waitFor(predicate, {
  timeoutMs = 2_000,
  intervalMs = 25,
} = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await predicate();
    if (value) return value;
    await sleep(intervalMs);
  }
  return null;
}

function makeJWT(payload) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.`;
}

await run('HubProviderKeys list/summary/usage telemetry allow paired client auth but mutations stay admin-only', async () => {
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
        const addResult = addProviderKey(runtimeBaseDir, {
          provider: 'openai',
          email: 'pool@test.local',
          api_key: 'sk-provider-key-test-1234567890',
          auth_type: 'api_key',
          proxy_url: 'https://proxy.example/openai',
          account_id: 'acct-openai-1',
          source_type: 'auth_file',
          source_ref: '/tmp/auth17.json',
          oauth_source_key: 'chatgpt',
          auth_index: 2,
          priority: 4,
        });
        assert.equal(addResult.ok, true);

        const modelStateUpdated = updateProviderKey(runtimeBaseDir, addResult.account_key, {
          model_states: {
            'gpt-5.4': {
              status: 'ready',
              updated_at_ms: Date.now(),
            },
          },
        });
        assert.equal(modelStateUpdated.ok, true);

        const list = await invokeUnary(
          impl.HubProviderKeys.ListProviderKeys,
          makeTransportCall({ provider: 'openai' }, 'client-secret')
        );
        assert.equal(list.err, null);
        assert.equal(list.res.accounts.length, 1);
        assert.equal(String(list.res.accounts[0].provider || ''), 'openai');
        assert.equal(String(list.res.accounts[0].email || ''), 'pool@test.local');
        assert.equal(String(list.res.accounts[0].proxy_url || ''), 'https://proxy.example/openai');
        assert.equal(String(list.res.accounts[0].account_id || ''), 'acct-openai-1');
        assert.equal(String(list.res.accounts[0].source_type || ''), 'auth_file');
        assert.equal(String(list.res.accounts[0].source_ref || ''), '/tmp/auth17.json');
        assert.equal(String(list.res.accounts[0].oauth_source_key || ''), 'chatgpt');
        assert.equal(Number(list.res.accounts[0].auth_index || 0), 2);
        assert.match(String(list.res.accounts[0].pool_id || ''), /^openai:proxy\.example:default:/);
        assert.equal(String(list.res.accounts[0].provider_host || ''), 'proxy.example');
        assert.equal(String(list.res.accounts[0].wire_api || ''), '');
        assert.match(String(list.res.accounts[0].api_key_redacted || ''), /\.\.\.|^\*{4}$/);
        assert.equal(String(list.res.accounts[0].model_states?.['gpt-5.4']?.status || ''), 'ready');

        const summary = await invokeUnary(
          impl.HubProviderKeys.GetProviderKeySummary,
          makeTransportCall({}, 'client-secret')
        );
        assert.equal(summary.err, null);
        assert.equal(summary.res.providers.length, 1);
        assert.equal(String(summary.res.providers[0].provider || ''), 'openai');

        const pools = await invokeUnary(
          impl.HubProviderKeys.ListProviderKeyPools,
          makeTransportCall({ provider: 'codex', model_id: 'openai/gpt-5.4', include_members: true }, 'client-secret')
        );
        assert.equal(pools.err, null);
        assert.equal(pools.res.pools.length, 1);
        assert.equal(String(pools.res.pools[0].provider || ''), 'openai');
        assert.equal(String(pools.res.pools[0].model_family || ''), 'gpt-5.4');
        assert.equal(Number(pools.res.pools[0].members.length || 0), 1);
        assert.equal(String(pools.res.pools[0].members[0].email || ''), 'pool@test.local');

        const runtimeSnapshot = await invokeUnary(
          impl.HubProviderKeys.GetProviderKeyRuntimeSnapshot,
          makeTransportCall({ provider: 'openai' }, 'client-secret')
        );
        assert.equal(runtimeSnapshot.err, null);
        assert.equal(Number(runtimeSnapshot.res.accounts.length || 0), 1);
        assert.equal(String(runtimeSnapshot.res.accounts[0].provider || ''), 'openai');
        assert.equal(String(runtimeSnapshot.res.accounts[0].account_key || ''), addResult.account_key);
        assert.deepEqual(runtimeSnapshot.res.accounts[0].required_refresh_metadata || [], []);

        const routeDecision = await invokeUnary(
          impl.HubProviderKeys.GetProviderKeyRouteDecision,
          makeTransportCall({ model_id: 'openai/gpt-5.4' }, 'client-secret')
        );
        assert.equal(routeDecision.err, null);
        assert.equal(String(routeDecision.res.decision?.requested_provider || ''), 'openai');
        assert.equal(String(routeDecision.res.decision?.selected_account_key || ''), addResult.account_key);
        assert.equal(Number(routeDecision.res.decision?.candidates?.length || 0), 1);
        assert.equal(String(routeDecision.res.decision?.candidates?.[0]?.account_key || ''), addResult.account_key);

        const usageReport = await invokeUnary(
          impl.HubProviderKeys.ReportKeyUsage,
          makeTransportCall({ account_key: addResult.account_key, tokens_used: 321 }, 'client-secret')
        );
        assert.equal(usageReport.err, null);
        assert.equal(usageReport.res.ok, true);

        const usage = getKeyUsage(runtimeBaseDir, addResult.account_key);
        assert.ok(usage);
        assert.equal(usage.quota.daily_tokens_used, 321);

        const usageRead = await invokeUnary(
          impl.HubProviderKeys.GetKeyUsage,
          makeTransportCall({ account_key: addResult.account_key }, 'client-secret')
        );
        assert.equal(usageRead.err, null);
        assert.equal(String(usageRead.res.error_state.reason_code || ''), '');
        assert.equal(Number(usageRead.res.error_state.next_retry_at_ms || 0), 0);
        assert.equal(String(usageRead.res.error_state.retry_at_source || ''), '');
        assert.equal(String(usageRead.res.model_states?.['gpt-5.4']?.status || ''), 'ready');

        const mutateDenied = await invokeUnary(
          impl.HubProviderKeys.AddProviderKey,
          makeTransportCall({ provider: 'openai', api_key: 'sk-denied' }, 'client-secret')
        );
        assert.ok(mutateDenied.err);
        assert.match(String(mutateDenied.err.message || mutateDenied.err), /admin token/i);

        const batchMutateDenied = await invokeUnary(
          impl.HubProviderKeys.RemoveProviderKeys,
          makeTransportCall({ account_keys: [addResult.account_key] }, 'client-secret')
        );
        assert.ok(batchMutateDenied.err);
        assert.match(String(batchMutateDenied.err.message || batchMutateDenied.err), /admin token/i);
      } finally {
        db.close();
      }
    }
  );

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});

await run('HubProviderKeys RemoveProviderKeys batch-removes accounts and returns missing account keys', async () => {
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
        const first = addProviderKey(runtimeBaseDir, {
          provider: 'openai',
          email: 'remove-1@test.local',
          api_key: 'sk-remove-1-1234567890',
          auth_type: 'api_key',
        });
        const second = addProviderKey(runtimeBaseDir, {
          provider: 'claude',
          email: 'remove-2@test.local',
          api_key: 'sk-remove-2-1234567890',
          auth_type: 'api_key',
        });
        assert.equal(first.ok, true);
        assert.equal(second.ok, true);

        const removed = await invokeUnary(
          impl.HubProviderKeys.RemoveProviderKeys,
          makeTransportCall(
            {
              account_keys: [first.account_key, 'missing:key'],
            },
            'admin-secret'
          )
        );
        assert.equal(removed.err, null);
        assert.equal(removed.res.ok, true);
        assert.equal(Number(removed.res.removed || 0), 1);
        assert.deepEqual(removed.res.missing_account_keys, ['missing:key']);

        const remaining = await invokeUnary(
          impl.HubProviderKeys.ListProviderKeys,
          makeTransportCall({}, 'client-secret')
        );
        assert.equal(remaining.err, null);
        assert.equal(remaining.res.accounts.length, 1);
        assert.equal(String(remaining.res.accounts[0].email || ''), 'remove-2@test.local');
      } finally {
        db.close();
      }
    }
  );

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});

await run('HubProviderKeys import surfaces hard failures instead of always returning ok', async () => {
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
        const missingPath = await invokeUnary(
          impl.HubProviderKeys.ImportProviderKeys,
          makeTransportCall({}, 'admin-secret')
        );
        assert.equal(missingPath.err, null);
        assert.equal(missingPath.res.ok, false);
        assert.deepEqual(missingPath.res.errors, ['missing_import_path']);

        const invalidToml = path.join(runtimeBaseDir, 'config.toml');
        fs.writeFileSync(invalidToml, 'not = "a supported auth config"\n', 'utf8');
        const invalid = await invokeUnary(
          impl.HubProviderKeys.ImportProviderKeys,
          makeTransportCall({ config_path: invalidToml }, 'admin-secret')
        );
        assert.equal(invalid.err, null);
        assert.equal(invalid.res.ok, false);
        assert.match(String(invalid.res.errors[0] || ''), /unsupported_toml_config/);
      } finally {
        db.close();
      }
    }
  );

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});

await run('HubProviderKeys OAuth start/status/callback allow paired client auth and fail closed on provider mismatch', async () => {
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
        const start = await invokeUnary(
          impl.HubProviderKeys.StartProviderOAuthLogin,
          makeTransportCall({ provider: 'openai' }, 'client-secret')
        );
        assert.equal(start.err, null);
        assert.equal(start.res.ok, true);
        assert.equal(String(start.res.provider || ''), 'codex');
        assert.match(String(start.res.auth_url || ''), /^https:\/\/auth\.openai\.com\/oauth\/authorize\?/);
        assert.equal(String(start.res.redirect_uri || ''), 'http://localhost:1455/auth/callback');
        assert.equal(String(start.res.status || ''), 'pending');
        assert.match(String(start.res.state || ''), /^[A-Za-z0-9_-]{20,}$/);

        const statusPending = await invokeUnary(
          impl.HubProviderKeys.GetProviderOAuthLoginStatus,
          makeTransportCall({ state: start.res.state }, 'client-secret')
        );
        assert.equal(statusPending.err, null);
        assert.equal(String(statusPending.res.status || ''), 'pending');

        const mismatch = await invokeUnary(
          impl.HubProviderKeys.SubmitProviderOAuthCallback,
          makeTransportCall(
            {
              provider: 'claude',
              state: start.res.state,
              code: 'code-should-not-apply',
            },
            'client-secret'
          )
        );
        assert.equal(mismatch.err, null);
        assert.equal(mismatch.res.ok, false);
        assert.equal(String(mismatch.res.error || ''), 'oauth_provider_mismatch');

        const callbackError = await invokeUnary(
          impl.HubProviderKeys.SubmitProviderOAuthCallback,
          makeTransportCall(
            {
              provider: 'openai',
              state: start.res.state,
              redirect_url: 'http://localhost:1455/auth/callback?state=' + encodeURIComponent(String(start.res.state || ''))
                + '&error=access_denied',
            },
            'client-secret'
          )
        );
        assert.equal(callbackError.err, null);
        assert.equal(callbackError.res.ok, false);
        assert.equal(String(callbackError.res.status || ''), 'error');

        const statusError = await invokeUnary(
          impl.HubProviderKeys.GetProviderOAuthLoginStatus,
          makeTransportCall({ state: start.res.state }, 'client-secret')
        );
        assert.equal(statusError.err, null);
        assert.equal(String(statusError.res.status || ''), 'error');
        assert.equal(String(statusError.res.error || ''), 'access_denied');
      } finally {
        db.close();
      }
    }
  );

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});

await run('HubProviderKeys OAuth success exchanges code, writes managed auth file, and imports account into provider pool', async () => {
  const runtimeBaseDir = makeTempDir('xhub-provider-keys-runtime-');
  const dbPath = path.join(makeTempDir('xhub-provider-keys-db-'), 'hub.sqlite3');
  invalidateProviderKeyCache();

  const httpRequestFn = async (request) => {
    if (String(request.url || '') === 'https://auth.openai.com/oauth/token') {
      assert.match(String(request.body || ''), /grant_type=authorization_code/);
      assert.match(String(request.body || ''), /code=codex-auth-code-1/);
      return {
        statusCode: 200,
        body: {
          access_token: 'codex-access-token-1',
          refresh_token: 'codex-refresh-token-1',
          id_token: makeJWT({
            email: 'oauth-user@example.com',
            chatgpt_account_id: 'acct-openai-oauth-1',
          }),
          expires_in: 3600,
        },
      };
    }
    throw new Error(`unexpected_http_request:${request.url}`);
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
        providerOAuthManagerOptions: { httpRequestFn },
      });
      try {
        const start = await invokeUnary(
          impl.HubProviderKeys.StartProviderOAuthLogin,
          makeTransportCall({ provider: 'codex' }, 'client-secret')
        );
        assert.equal(start.err, null);
        assert.equal(start.res.ok, true);

        const submit = await invokeUnary(
          impl.HubProviderKeys.SubmitProviderOAuthCallback,
          makeTransportCall(
            {
              provider: 'codex',
              state: start.res.state,
              code: 'codex-auth-code-1',
            },
            'client-secret'
          )
        );
        assert.equal(submit.err, null);
        assert.equal(submit.res.ok, true);
        assert.equal(String(submit.res.status || ''), 'processing');

        const finalStatus = await waitFor(async () => {
          const status = await invokeUnary(
            impl.HubProviderKeys.GetProviderOAuthLoginStatus,
            makeTransportCall({ state: start.res.state }, 'client-secret')
          );
          if (status.err) throw status.err;
          return String(status.res.status || '') === 'ok' ? status.res : null;
        });

        assert.ok(finalStatus, 'expected oauth status to reach ok');
        assert.equal(String(finalStatus.provider || ''), 'codex');
        assert.equal(String(finalStatus.email || ''), 'oauth-user@example.com');
        assert.equal(Number(finalStatus.imported || 0), 1);
        assert.match(String(finalStatus.account_key || ''), /^codex:/);
        assert.match(String(finalStatus.auth_file_path || ''), /provider_key_oauth_auth\/codex-oauth-user@example\.com\.json$/);

        const accounts = await invokeUnary(
          impl.HubProviderKeys.ListProviderKeys,
          makeTransportCall({ provider: 'codex' }, 'client-secret')
        );
        assert.equal(accounts.err, null);
        assert.equal(accounts.res.accounts.length, 1);
        assert.equal(String(accounts.res.accounts[0].email || ''), 'oauth-user@example.com');
        assert.equal(String(accounts.res.accounts[0].auth_type || ''), 'oauth');
        assert.equal(String(accounts.res.accounts[0].oauth_source_key || ''), 'chatgpt');
        assert.equal(String(accounts.res.accounts[0].source_type || ''), 'auth_file');
        assert.equal(path.resolve(String(accounts.res.accounts[0].source_ref || '')), path.resolve(String(finalStatus.auth_file_path || '')));

        const authPayload = JSON.parse(fs.readFileSync(String(finalStatus.auth_file_path || ''), 'utf8'));
        assert.equal(String(authPayload.provider || ''), 'codex');
        assert.equal(String(authPayload.refresh_token || ''), 'codex-refresh-token-1');
      } finally {
        db.close();
      }
    }
  );

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});
