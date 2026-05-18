import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  addProviderKey,
  invalidateProviderKeyCache,
  loadProviderKeyStore,
} from './provider_key_store.js';
import { resolveProviderKeyForModel } from './provider_key_router.js';
import {
  runProviderKeyRuntimeConductorTick,
  startProviderKeyRuntimeConductor,
} from './provider_key_runtime_conductor.js';
import { sleep } from './util.js';

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

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-refresh-'));
}

function makeJWT(payload = {}) {
  const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `header.${encoded}.sig`;
}

function readAccount(runtimeBaseDir, provider = 'openai') {
  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(runtimeBaseDir, 0);
  const account = store.providers?.[provider]?.accounts?.[0] || null;
  assert.ok(account, `missing account for provider ${provider}`);
  return account;
}

async function waitFor(predicate, timeoutMs = 2_000, intervalMs = 20) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = predicate();
    if (result) return result;
    await sleep(intervalMs);
  }
  throw new Error('timeout_waiting_for_condition');
}

await run('runProviderKeyRuntimeConductorTick refreshes due oauth accounts and persists runtime state', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-old-access-token',
    refresh_token: 'refresh-token-1',
    auth_type: 'oauth',
    expires_at_ms: Date.now() + 250,
  });
  assert.equal(addResult.ok, true);

  let calls = 0;
  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    executorForAccount: async (account) => {
      calls += 1;
      assert.equal(account.account_key, addResult.account_key);
      return {
        account_updates: {
          api_key: 'sk-refreshed-access-token',
          expires_at_ms: Date.now() + 60_000,
        },
      };
    },
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.refreshed, 1);
  assert.equal(calls, 1);

  const account = readAccount(dir);
  assert.equal(account.api_key, 'sk-refreshed-access-token');
  assert.ok(Number(account.last_refresh_at_ms || 0) > 0);
  assert.equal(String(account.refresh_state?.status || ''), 'idle');
  assert.equal(Number(account.refresh_state?.failure_count || 0), 0);
  assert.equal(String(account.refresh_state?.last_error_code || ''), '');
});

await run('runProviderKeyRuntimeConductorTick uses the default OpenAI oauth refresh executor for codex accounts', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'codex',
    refresh_token: 'refresh-token-default-openai',
    auth_type: 'oauth',
    oauth_source_key: 'chatgpt',
    expires_at_ms: Date.now() - 1_000,
  });
  assert.equal(addResult.ok, true);

  let calls = 0;
  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    httpRequestFn: async (request) => {
      calls += 1;
      assert.equal(request.url, 'https://auth.openai.com/oauth/token');
      assert.equal(request.method, 'POST');
      assert.match(String(request.headers?.['Content-Type'] || ''), /application\/x-www-form-urlencoded/);
      assert.match(String(request.body || ''), /grant_type=refresh_token/);
      assert.match(String(request.body || ''), /client_id=app_EMoamEEZ73f0CkXaXp7hrann/);
      return {
        statusCode: 200,
        body: JSON.stringify({
          access_token: 'sk-default-openai-refresh-token',
          refresh_token: 'refresh-token-rotated',
          expires_in: 1800,
          id_token: makeJWT({
            email: 'default-refresh@test.local',
            account_id: 'acct-refreshed-1',
          }),
        }),
      };
    },
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.refreshed, 1);
  assert.equal(calls, 1);

  const account = readAccount(dir, 'codex');
  assert.equal(account.api_key, 'sk-default-openai-refresh-token');
  assert.equal(account.refresh_token, 'refresh-token-rotated');
  assert.equal(account.email, 'default-refresh@test.local');
  assert.equal(account.account_id, 'acct-refreshed-1');
  assert.ok(Number(account.expires_at_ms || 0) > Date.now());
  assert.equal(String(account.refresh_state?.status || ''), 'idle');
});

await run('runProviderKeyRuntimeConductorTick uses the default Claude oauth refresh executor', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'claude',
    refresh_token: 'claude-refresh-token',
    auth_type: 'oauth',
    expires_at_ms: Date.now() - 1_000,
  });
  assert.equal(addResult.ok, true);

  let calls = 0;
  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    httpRequestFn: async (request) => {
      calls += 1;
      assert.equal(request.url, 'https://api.anthropic.com/v1/oauth/token');
      assert.equal(request.method, 'POST');
      assert.match(String(request.headers?.['Content-Type'] || ''), /application\/json/);
      const body = JSON.parse(String(request.body || '{}'));
      assert.equal(body.grant_type, 'refresh_token');
      assert.equal(body.refresh_token, 'claude-refresh-token');
      assert.equal(body.client_id, '9d1c250a-e61b-44d9-88ed-5944d1962f5e');
      return {
        statusCode: 200,
        body: JSON.stringify({
          access_token: 'sk-claude-refreshed-token',
          refresh_token: 'claude-refresh-rotated',
          expires_in: 900,
          account: {
            uuid: 'claude-account-1',
            email_address: 'claude-refresh@test.local',
          },
        }),
      };
    },
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.refreshed, 1);
  assert.equal(calls, 1);

  const account = readAccount(dir, 'claude');
  assert.equal(account.api_key, 'sk-claude-refreshed-token');
  assert.equal(account.refresh_token, 'claude-refresh-rotated');
  assert.equal(account.account_id, 'claude-account-1');
  assert.equal(account.email, 'claude-refresh@test.local');
  assert.ok(Number(account.expires_at_ms || 0) > Date.now());
  assert.equal(String(account.refresh_state?.status || ''), 'idle');
});

await run('runProviderKeyRuntimeConductorTick uses the default Gemini oauth refresh executor', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'gemini',
    refresh_token: 'gemini-refresh-token',
    auth_type: 'oauth',
    expires_at_ms: Date.now() - 1_000,
    oauth_refresh_config: {
      token_uri: 'https://oauth2.googleapis.com/token',
      client_id: 'gemini-client-id-test',
      client_secret: 'gemini-client-secret-test',
    },
  });
  assert.equal(addResult.ok, true);

  let calls = 0;
  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    httpRequestFn: async (request) => {
      calls += 1;
      assert.equal(request.url, 'https://oauth2.googleapis.com/token');
      assert.equal(request.method, 'POST');
      assert.match(String(request.headers?.['Content-Type'] || ''), /application\/x-www-form-urlencoded/);
      assert.match(String(request.body || ''), /grant_type=refresh_token/);
      assert.match(String(request.body || ''), /refresh_token=gemini-refresh-token/);
      assert.match(String(request.body || ''), /client_id=gemini-client-id-test/);
      assert.match(String(request.body || ''), /client_secret=gemini-client-secret-test/);
      return {
        statusCode: 200,
        body: JSON.stringify({
          access_token: 'gemini-access-token-1',
          refresh_token: 'gemini-refresh-rotated',
          expires_in: 3600,
        }),
      };
    },
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.refreshed, 1);
  assert.equal(calls, 1);

  const account = readAccount(dir, 'gemini');
  assert.equal(account.api_key, 'gemini-access-token-1');
  assert.equal(account.refresh_token, 'gemini-refresh-rotated');
  assert.ok(Number(account.expires_at_ms || 0) > Date.now());
  assert.equal(String(account.refresh_state?.status || ''), 'idle');
});

await run('runProviderKeyRuntimeConductorTick uses the default Antigravity oauth refresh executor', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'antigravity',
    refresh_token: 'antigravity-refresh-token',
    auth_type: 'oauth',
    expires_at_ms: Date.now() - 1_000,
  });
  assert.equal(addResult.ok, true);

  let calls = 0;
  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    env: {
      HUB_PROVIDER_KEY_ANTIGRAVITY_OAUTH_CLIENT_ID: 'antigravity-client-id-test',
      HUB_PROVIDER_KEY_ANTIGRAVITY_OAUTH_CLIENT_SECRET: 'antigravity-client-secret-test',
    },
    httpRequestFn: async (request) => {
      calls += 1;
      assert.equal(request.url, 'https://oauth2.googleapis.com/token');
      assert.equal(request.method, 'POST');
      assert.match(String(request.headers?.['Content-Type'] || ''), /application\/x-www-form-urlencoded/);
      assert.match(String(request.body || ''), /grant_type=refresh_token/);
      assert.match(String(request.body || ''), /refresh_token=antigravity-refresh-token/);
      assert.match(String(request.body || ''), /client_id=antigravity-client-id-test/);
      assert.match(String(request.body || ''), /client_secret=antigravity-client-secret-test/);
      return {
        statusCode: 200,
        body: JSON.stringify({
          access_token: 'antigravity-access-token-1',
          refresh_token: 'antigravity-refresh-rotated',
          expires_in: 3600,
        }),
      };
    },
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.refreshed, 1);
  assert.equal(calls, 1);

  const account = readAccount(dir, 'antigravity');
  assert.equal(account.api_key, 'antigravity-access-token-1');
  assert.equal(account.refresh_token, 'antigravity-refresh-rotated');
  assert.ok(Number(account.expires_at_ms || 0) > Date.now());
  assert.equal(String(account.refresh_state?.status || ''), 'idle');
});

await run('runProviderKeyRuntimeConductorTick uses the default Kiro oauth refresh executor', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'kiro',
    refresh_token: 'kiro-refresh-token',
    auth_type: 'oauth',
    expires_at_ms: Date.now() - 1_000,
  });
  assert.equal(addResult.ok, true);

  let calls = 0;
  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    httpRequestFn: async (request) => {
      calls += 1;
      assert.equal(request.url, 'https://prod.us-east-1.auth.desktop.kiro.dev/refreshToken');
      assert.equal(request.method, 'POST');
      assert.match(String(request.headers?.['Content-Type'] || ''), /application\/json/);
      const body = JSON.parse(String(request.body || '{}'));
      assert.equal(body.refreshToken, 'kiro-refresh-token');
      return {
        statusCode: 200,
        body: JSON.stringify({
          accessToken: 'kiro-access-token-1',
        }),
      };
    },
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.refreshed, 1);
  assert.equal(calls, 1);

  const account = readAccount(dir, 'kiro');
  assert.equal(account.api_key, 'kiro-access-token-1');
  assert.ok(Number(account.expires_at_ms || 0) > Date.now());
  assert.equal(String(account.refresh_state?.status || ''), 'idle');
});

await run('runProviderKeyRuntimeConductorTick records unsupported refresh schema as a machine-readable blocker without blocking a still-valid token', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'gateway-oauth-access-token',
    refresh_token: 'gateway-oauth-refresh-token',
    auth_type: 'oauth',
    base_url: 'https://gateway.example.com/openai/v1',
    oauth_source_key: 'custom-gateway',
    expires_at_ms: Date.now() + 60_000,
  });
  assert.equal(addResult.ok, true);

  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
  });
  assert.equal(tick.scheduled, 0);

  const account = readAccount(dir, 'openai');
  assert.equal(String(account.refresh_state?.status || ''), 'idle');
  assert.equal(String(account.refresh_state?.last_error_code || ''), 'unsupported_refresh_schema');
  assert.equal(String(account.error_state?.status || ''), 'degraded');
  assert.equal(String(account.error_state?.reason_code || ''), 'unsupported_refresh_schema');
  assert.equal(String(account.error_state?.retry_at_source || ''), 'manual');

  invalidateProviderKeyCache();
  const routed = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.ok(routed.account);
  assert.equal(String(routed.account?.account_key || ''), addResult.account_key);
});

await run('runProviderKeyRuntimeConductorTick clears unsupported refresh schema blocker once an executor becomes available', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'gateway-oauth-access-token-clear',
    refresh_token: 'gateway-oauth-refresh-token-clear',
    auth_type: 'oauth',
    base_url: 'https://gateway.example.com/openai/v1',
    oauth_source_key: 'custom-gateway',
    expires_at_ms: Date.now() + 60_000,
  });
  assert.equal(addResult.ok, true);

  await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
  });

  let account = readAccount(dir, 'openai');
  assert.equal(String(account.error_state?.reason_code || ''), 'unsupported_refresh_schema');

  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    executorForAccount: async () => ({
      account_updates: {
        api_key: 'gateway-supported-access-token',
      },
    }),
  });
  assert.equal(tick.scheduled, 0);

  account = readAccount(dir, 'openai');
  assert.equal(String(account.refresh_state?.last_error_code || ''), '');
  assert.equal(String(account.error_state?.status || ''), 'healthy');
  assert.equal(String(account.error_state?.reason_code || ''), '');
  assert.equal(String(account.error_state?.retry_at_source || ''), '');
});

await run('runProviderKeyRuntimeConductorTick writes failed refresh backoff and router rear-ranks the account', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-refresh-failure-token',
    refresh_token: 'refresh-token-2',
    auth_type: 'oauth',
    expires_at_ms: Date.now() + 250,
  });
  assert.equal(addResult.ok, true);

  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    baseFailureBackoffMs: 100,
    maxFailureBackoffMs: 100,
    executorForAccount: async () => {
      const error = new Error('upstream_refresh_failed');
      error.code = 'refresh_failed';
      throw error;
    },
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.failed, 1);

  const account = readAccount(dir);
  assert.equal(String(account.refresh_state?.status || ''), 'failed');
  assert.equal(String(account.refresh_state?.last_error_code || ''), 'refresh_failed');
  assert.ok(Number(account.refresh_state?.next_refresh_at_ms || 0) > Date.now());
  assert.equal(String(account.error_state?.status || ''), 'blocked_provider');
  assert.equal(String(account.error_state?.reason_code || ''), 'refresh_failed');
  assert.equal(String(account.error_state?.retry_at_source || ''), 'refresh');
  assert.ok(Number(account.error_state?.next_retry_at_ms || 0) > Date.now());

  invalidateProviderKeyCache();
  const routed = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.equal(routed.account, null);
  assert.equal(routed.fallback_reason, 'all_keys_in_cooldown');
});

await run('runProviderKeyRuntimeConductorTick records upstream refresh auth failures from the default executor', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'codex',
    refresh_token: 'refresh-token-upstream-failure',
    auth_type: 'oauth',
    oauth_source_key: 'chatgpt',
    expires_at_ms: Date.now() - 1_000,
  });
  assert.equal(addResult.ok, true);

  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    baseFailureBackoffMs: 100,
    maxFailureBackoffMs: 100,
    httpRequestFn: async () => ({
      statusCode: 401,
      body: JSON.stringify({
        code: 'token_expired',
        detail: 'Your authentication token has expired. Please try signing in again.',
      }),
    }),
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.failed, 1);

  const account = readAccount(dir, 'codex');
  assert.equal(String(account.refresh_state?.status || ''), 'failed');
  assert.equal(String(account.refresh_state?.last_error_code || ''), 'token_expired');
  assert.match(String(account.refresh_state?.last_error_message || ''), /expired/i);
  assert.ok(Number(account.refresh_state?.next_refresh_at_ms || 0) > Date.now());
  assert.equal(String(account.error_state?.status || ''), 'blocked_auth');
  assert.equal(String(account.error_state?.reason_code || ''), 'token_expired');
  assert.equal(String(account.error_state?.retry_at_source || ''), 'refresh');
  assert.ok(Number(account.error_state?.next_retry_at_ms || 0) > Date.now());
  assert.match(String(account.error_state?.status_message || ''), /expired/i);
});

await run('runProviderKeyRuntimeConductorTick surfaces missing oauth metadata as blocked_config in error_state', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'gemini',
    api_key: 'gemini-access-token-metadata',
    refresh_token: 'gemini-refresh-token-metadata',
    auth_type: 'oauth',
    expires_at_ms: Date.now() - 1_000,
  });
  assert.equal(addResult.ok, true);

  const tick = await runProviderKeyRuntimeConductorTick({
    runtimeBaseDir: dir,
    refreshLeadMs: 10_000,
    executorForAccount: async () => {
      const error = new Error('gemini refresh requires oauth client id and secret');
      error.code = 'missing_oauth_client';
      error.status_message = 'gemini refresh requires oauth client id and secret';
      throw error;
    },
  });
  assert.equal(tick.scheduled, 1);
  assert.equal(tick.failed, 1);

  const account = readAccount(dir, 'gemini');
  assert.equal(String(account.refresh_state?.last_error_code || ''), 'missing_oauth_client');
  assert.equal(String(account.error_state?.status || ''), 'blocked_config');
  assert.equal(String(account.error_state?.reason_code || ''), 'missing_oauth_client');
  assert.equal(String(account.error_state?.retry_at_source || ''), 'manual');
  assert.equal(Number(account.error_state?.next_retry_at_ms || 0), 0);
  assert.match(String(account.error_state?.status_message || ''), /client id and secret/i);
});

await run('startProviderKeyRuntimeConductor retries failed accounts after backoff and clears refresh_state on success', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-retry-refresh-token',
    refresh_token: 'refresh-token-3',
    auth_type: 'oauth',
    expires_at_ms: Date.now() + 250,
  });
  assert.equal(addResult.ok, true);

  let calls = 0;
  const stop = startProviderKeyRuntimeConductor({
    runtimeBaseDir: dir,
    intervalMs: 20,
    refreshLeadMs: 10_000,
    baseFailureBackoffMs: 40,
    maxFailureBackoffMs: 40,
    executorForAccount: async () => {
      calls += 1;
      if (calls === 1) {
        const error = new Error('transient_refresh_failure');
        error.code = 'refresh_failed';
        throw error;
      }
      return {
        account_updates: {
          api_key: 'sk-after-retry-success',
          expires_at_ms: Date.now() + 60_000,
        },
      };
    },
  });

  try {
    await waitFor(() => {
      const account = readAccount(dir);
      return String(account.refresh_state?.status || '') === 'failed' ? account : null;
    });

    invalidateProviderKeyCache();
    const blocked = resolveProviderKeyForModel(dir, 'gpt-4o');
    assert.equal(blocked.account, null);

    const account = await waitFor(() => {
      const current = readAccount(dir);
      if (String(current.refresh_state?.status || '') !== 'idle') return null;
      if (String(current.api_key || '') !== 'sk-after-retry-success') return null;
      return current;
    });
    assert.ok(Number(account.last_refresh_at_ms || 0) > 0);
    assert.equal(Number(account.refresh_state?.failure_count || 0), 0);
    assert.ok(calls >= 2);
  } finally {
    stop();
  }
});
