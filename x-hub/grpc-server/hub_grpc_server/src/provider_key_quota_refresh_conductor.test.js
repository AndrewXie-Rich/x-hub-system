import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  addProviderKey,
  getKeyUsage,
  invalidateProviderKeyCache,
  listProviderKeyPools,
  listProviderKeysFull,
} from './provider_key_store.js';
import { runProviderKeyQuotaRefreshConductorTick } from './provider_key_quota_refresh_conductor.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-provider-quota-'));
}

function usagePayload({
  planType = 'plus',
  limitReached = false,
  usedPercent = 25,
  resetAtMs = 0,
  secondaryUsedPercent = Math.min(usedPercent, 65),
  secondaryResetAtMs = 0,
} = {}) {
  const resetAtSeconds = resetAtMs > 0 ? Math.floor(resetAtMs / 1000) : 0;
  const secondaryResetAtSeconds = secondaryResetAtMs > 0 ? Math.floor(secondaryResetAtMs / 1000) : 0;
  return {
    status_code: 200,
    body: JSON.stringify({
      plan_type: planType,
      rate_limit: {
        limit_reached: !!limitReached,
        primary_window: {
          used_percent: usedPercent,
          limit_window_seconds: 5 * 60 * 60,
          reset_after_seconds: resetAtMs > 0 ? Math.max(1, Math.floor((resetAtMs - Date.now()) / 1000)) : 0,
          reset_at: resetAtSeconds,
        },
        secondary_window: {
          used_percent: secondaryUsedPercent,
          limit_window_seconds: 7 * 24 * 60 * 60,
          reset_after_seconds: secondaryResetAtMs > 0 ? Math.max(1, Math.floor((secondaryResetAtMs - Date.now()) / 1000)) : 0,
          reset_at: secondaryResetAtSeconds,
        },
      },
      code_review_rate_limit: {
        limit_reached: false,
        primary_window: {
          used_percent: Math.min(usedPercent, 40),
          limit_window_seconds: 5 * 60 * 60,
          reset_after_seconds: 0,
          reset_at: 0,
        },
        secondary_window: null,
      },
    }),
  };
}

function makeJWT(payload) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.`;
}

await run('runProviderKeyQuotaRefreshConductorTick blocks OpenAI pool members on live quota exhaustion and surfaces retry time', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const addResult = addProviderKey(dir, {
    provider: 'openai',
    email: 'quota@test.local',
    api_key: 'sk-live-quota-1234567890',
    refresh_token: 'rt-live-quota-1234567890',
    auth_type: 'oauth',
    oauth_source_key: 'chatgpt',
    account_id: 'acct-live-quota-1',
    auth_index: 19,
    models: ['openai/gpt-5.4'],
  });
  assert.equal(addResult.ok, true);

  const resetAtMs = Date.now() + 120_000;
  const result = await runProviderKeyQuotaRefreshConductorTick({
    runtimeBaseDir: dir,
    callManagementApiFn: async (params) => {
      assert.equal(String(params.url || ''), 'https://chatgpt.com/backend-api/wham/usage');
      assert.equal(String(params.authIndex || ''), '19');
      return usagePayload({
        planType: 'pro',
        limitReached: true,
        usedPercent: 100,
        resetAtMs,
      });
    },
  });
  assert.equal(result.scheduled, 1);
  assert.equal(result.refreshed, 1);
  assert.equal(result.failed, 0);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.ok(usage);
  assert.equal(String(usage.error_state.status || ''), 'blocked_quota');
  assert.equal(String(usage.error_state.reason_code || ''), 'blocked_quota');
  assert.equal(String(usage.error_state.retry_at_source || ''), 'usage_window');
  assert.ok(Number(usage.error_state.next_retry_at_ms || 0) >= resetAtMs - 1000);
  assert.equal(Number(usage.quota.daily_token_cap || 0), 10000);
  assert.equal(Number(usage.quota.daily_tokens_used || 0), 10000);
  assert.equal(Number(usage.quota.daily_tokens_remaining || 0), 0);
  assert.ok(Number(usage.quota.cooldown_until_ms || 0) >= resetAtMs - 1000);
  const rateLimitWindows = (usage.quota.usage_windows || [])
    .filter((window) => String(window.source || '') === 'rate_limit');
  const fiveHourWindow = rateLimitWindows.find((window) => Number(window.limit_window_seconds || 0) === 5 * 60 * 60);
  const sevenDayWindow = rateLimitWindows.find((window) => Number(window.limit_window_seconds || 0) === 7 * 24 * 60 * 60);
  assert.ok(fiveHourWindow);
  assert.ok(sevenDayWindow);
  assert.equal(String(fiveHourWindow.window_key || ''), 'primary');
  assert.equal(Number(fiveHourWindow.used_percent || 0), 100);
  assert.equal(Number(fiveHourWindow.used_basis_points || 0), 10000);
  assert.equal(Number(fiveHourWindow.remaining_basis_points || 0), 0);
  assert.ok(Number(fiveHourWindow.reset_at_ms || 0) >= resetAtMs - 1000);
  assert.equal(String(sevenDayWindow.window_key || ''), 'secondary');
  assert.equal(Number(sevenDayWindow.used_percent || 0), 65);
  assert.equal(Number(sevenDayWindow.used_basis_points || 0), 6500);
  assert.equal(Number(sevenDayWindow.remaining_basis_points || 0), 3500);

  const pools = listProviderKeyPools(dir, {
    provider: 'openai',
    model_id: 'openai/gpt-5.4',
    include_members: true,
  });
  assert.equal(pools.length, 1);
  assert.equal(String(pools[0].members[0].state || ''), 'cooldown');
  assert.equal(String(pools[0].members[0].reason_code || ''), 'blocked_quota');
  assert.ok(Number(pools[0].members[0].retry_at_ms || 0) >= resetAtMs - 1000);
  assert.equal(String(pools[0].members[0].tier || ''), 'pro');
});

await run('runProviderKeyQuotaRefreshConductorTick clears previous quota blocker when live usage recovers', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const addResult = addProviderKey(dir, {
    provider: 'openai',
    email: 'quota-clear@test.local',
    api_key: 'sk-live-quota-clear-1234567890',
    refresh_token: 'rt-live-quota-clear-1234567890',
    auth_type: 'oauth',
    oauth_source_key: 'chatgpt',
    account_id: 'acct-live-quota-2',
    auth_index: 17,
    models: ['openai/gpt-5.4'],
  });
  assert.equal(addResult.ok, true);

  await runProviderKeyQuotaRefreshConductorTick({
    runtimeBaseDir: dir,
    callManagementApiFn: async () => usagePayload({
      limitReached: true,
      usedPercent: 100,
      resetAtMs: Date.now() + 60_000,
    }),
  });

  await runProviderKeyQuotaRefreshConductorTick({
    runtimeBaseDir: dir,
    callManagementApiFn: async () => usagePayload({
      planType: 'plus',
      limitReached: false,
      usedPercent: 22.5,
      resetAtMs: 0,
    }),
  });

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.ok(usage);
  assert.equal(String(usage.error_state.status || ''), 'healthy');
  assert.equal(String(usage.error_state.reason_code || ''), '');
  assert.equal(Number(usage.error_state.next_retry_at_ms || 0), 0);
  assert.equal(Number(usage.quota.cooldown_until_ms || 0), 0);
  assert.equal(Number(usage.quota.daily_token_cap || 0), 10000);
  assert.equal(Number(usage.quota.daily_tokens_used || 0), 2250);
  assert.equal(Number(usage.quota.daily_tokens_remaining || 0), 7750);
  const sevenDayWindow = (usage.quota.usage_windows || [])
    .find((window) => String(window.source || '') === 'rate_limit' && Number(window.limit_window_seconds || 0) === 7 * 24 * 60 * 60);
  assert.ok(sevenDayWindow);
  assert.equal(Number(sevenDayWindow.used_percent || 0), 22.5);
  assert.equal(Number(sevenDayWindow.used_basis_points || 0), 2250);
});

await run('runProviderKeyQuotaRefreshConductorTick leaves account availability unchanged when quota probe transport fails', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const addResult = addProviderKey(dir, {
    provider: 'openai',
    email: 'quota-timeout@test.local',
    api_key: 'sk-live-quota-timeout-1234567890',
    refresh_token: 'rt-live-quota-timeout-1234567890',
    auth_type: 'oauth',
    oauth_source_key: 'chatgpt',
    account_id: 'acct-live-quota-3',
    auth_index: 23,
    models: ['openai/gpt-5.4'],
  });
  assert.equal(addResult.ok, true);

  const result = await runProviderKeyQuotaRefreshConductorTick({
    runtimeBaseDir: dir,
    callManagementApiFn: async () => {
      const error = new Error('The request timed out.');
      error.code = 'ETIMEDOUT';
      throw error;
    },
  });
  assert.equal(result.scheduled, 1);
  assert.equal(result.refreshed, 0);
  assert.equal(result.failed, 1);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.ok(usage);
  assert.equal(String(usage.error_state.status || ''), 'healthy');
  assert.equal(String(usage.error_state.reason_code || ''), '');
  assert.equal(Number(usage.error_state.next_retry_at_ms || 0), 0);

  const pools = listProviderKeyPools(dir, {
    provider: 'openai',
    model_id: 'openai/gpt-5.4',
    include_members: true,
  });
  assert.equal(pools.length, 1);
  assert.equal(String(pools[0].members[0].state || ''), 'ready');
});

await run('runProviderKeyQuotaRefreshConductorTick derives OpenAI quota metadata from bearer token when auth_index is missing', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const accessToken = makeJWT({
    'https://api.openai.com/auth': {
      chatgpt_account_id: 'acct-derived-7',
    },
    'https://api.openai.com/profile': {
      email: 'derived@test.local',
    },
    exp: Math.floor(Date.now() / 1000) + 3600,
  });

  const addResult = addProviderKey(dir, {
    provider: 'openai',
    email: '',
    api_key: accessToken,
    auth_type: 'api_key',
    models: ['openai/gpt-5.4'],
  });
  assert.equal(addResult.ok, true);

  const result = await runProviderKeyQuotaRefreshConductorTick({
    runtimeBaseDir: dir,
    httpRequestFn: async (request) => {
      assert.equal(String(request.url || ''), 'https://chatgpt.com/backend-api/wham/usage');
      assert.equal(String(request.method || ''), 'GET');
      assert.equal(String(request.headers?.Authorization || ''), `Bearer ${accessToken}`);
      assert.equal(String(request.headers?.['ChatGPT-Account-Id'] || ''), 'acct-derived-7');
      return usagePayload({
        planType: 'plus',
        limitReached: false,
        usedPercent: 37.5,
        resetAtMs: 0,
      });
    },
  });
  assert.equal(result.scheduled, 1);
  assert.equal(result.refreshed, 1);
  assert.equal(result.failed, 0);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.ok(usage);
  assert.equal(Number(usage.quota.daily_token_cap || 0), 10000);
  assert.equal(Number(usage.quota.daily_tokens_used || 0), 3750);
  assert.equal(Number(usage.quota.daily_tokens_remaining || 0), 6250);

  const full = listProviderKeysFull(dir);
  assert.equal(full.length, 1);
  assert.equal(String(full[0].account_id || ''), 'acct-derived-7');
});

await run('runProviderKeyQuotaRefreshConductorTick can delegate OpenAI quota state write to Rust bridge', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const addResult = addProviderKey(dir, {
    provider: 'openai',
    email: 'rust-quota@test.local',
    api_key: 'sk-rust-quota-1234567890',
    refresh_token: 'rt-rust-quota-1234567890',
    auth_type: 'oauth',
    oauth_source_key: 'chatgpt',
    account_id: 'acct-rust-quota',
    auth_index: 29,
    models: ['openai/gpt-5.4'],
  });
  assert.equal(addResult.ok, true);

  const calls = [];
  const result = await runProviderKeyQuotaRefreshConductorTick({
    runtimeBaseDir: dir,
    callManagementApiFn: async () => usagePayload({
      planType: 'pro',
      limitReached: false,
      usedPercent: 41,
    }),
    rustQuotaApplyBridge: {
      applyOpenAIQuotaRefresh: async (input) => {
        calls.push(input);
        return {
          ok: true,
          used: true,
          next_refresh_at_ms: 123456789,
        };
      },
    },
  });

  assert.equal(result.scheduled, 1);
  assert.equal(result.refreshed, 1);
  assert.equal(result.failed, 0);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].runtimeBaseDir, dir);
  assert.equal(calls[0].accountKey, addResult.account_key);
  assert.equal(calls[0].accountId, 'acct-rust-quota');
  assert.equal(calls[0].oauthSourceKey, 'chatgpt');
  assert.equal(calls[0].usage.plan_type, 'pro');

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.ok(usage);
  assert.equal(Number(usage.quota.daily_token_cap || 0), 0);
  assert.equal(String(usage.error_state.status || ''), 'healthy');
});

await run('runProviderKeyQuotaRefreshConductorTick can delegate quota scheduling to Rust plan', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const first = addProviderKey(dir, {
    provider: 'openai',
    email: 'rust-plan-skip@test.local',
    api_key: 'sk-rust-plan-skip-1234567890',
    models: ['openai/gpt-5.4'],
  });
  const second = addProviderKey(dir, {
    provider: 'openai',
    email: 'rust-plan-due@test.local',
    api_key: 'sk-rust-plan-due-1234567890',
    models: ['openai/gpt-5.4'],
  });
  assert.equal(first.ok, true);
  assert.equal(second.ok, true);

  const executed = [];
  const result = await runProviderKeyQuotaRefreshConductorTick({
    runtimeBaseDir: dir,
    executorForAccount: (account) => async () => {
      executed.push(account.account_key);
      return {
        account_updates: { last_refresh_at_ms: 777 },
        next_refresh_at_ms: 123456,
      };
    },
    rustQuotaApplyBridge: {
      planOpenAIQuotaRefresh: async (input) => {
        assert.equal(input.runtimeBaseDir, dir);
        return {
          ok: true,
          used: true,
          account_keys: [second.account_key],
          due_accounts: 1,
          skipped_count: 1,
        };
      },
    },
  });

  assert.equal(result.rust_plan_used, true);
  assert.equal(result.scheduled, 1);
  assert.equal(result.refreshed, 1);
  assert.deepEqual(executed, [second.account_key]);
});

await run('runProviderKeyQuotaRefreshConductorTick can delegate quota failure backoff to Rust', async () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const addResult = addProviderKey(dir, {
    provider: 'openai',
    email: 'rust-failure@test.local',
    api_key: 'sk-rust-failure-1234567890',
    models: ['openai/gpt-5.4'],
  });
  assert.equal(addResult.ok, true);

  const calls = [];
  const result = await runProviderKeyQuotaRefreshConductorTick({
    runtimeBaseDir: dir,
    executorForAccount: () => async () => {
      const error = new Error('quota probe failed');
      error.code = 'ETIMEDOUT';
      throw error;
    },
    rustQuotaApplyBridge: {
      recordOpenAIQuotaRefreshFailure: async (input) => {
        calls.push(input);
        return {
          ok: true,
          used: true,
          failure_count: 3,
          next_refresh_at_ms: 999999,
        };
      },
    },
  });

  assert.equal(result.scheduled, 1);
  assert.equal(result.refreshed, 0);
  assert.equal(result.failed, 1);
  assert.equal(result.rust_failures_recorded, 1);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].accountKey, addResult.account_key);
  assert.equal(calls[0].errorCode, 'ETIMEDOUT');
});
