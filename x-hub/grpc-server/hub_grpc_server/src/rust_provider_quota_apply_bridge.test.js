import assert from 'node:assert/strict';

import {
  createRustProviderQuotaApplyBridge,
  resolveRustProviderQuotaApplyConfig,
} from './rust_provider_quota_apply_bridge.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

await run('Rust provider quota apply bridge is disabled by default', () => {
  const config = resolveRustProviderQuotaApplyConfig({});
  assert.equal(config.enabled, false);
  assert.equal(config.planEnabled, false);
  assert.equal(config.failureEnabled, false);
  assert.equal(config.fallbackOnError, true);
  assert.equal(config.httpBaseUrl, 'http://127.0.0.1:50151');
});

await run('Rust provider quota bridge posts OpenAI plan request', async () => {
  const calls = [];
  const bridge = createRustProviderQuotaApplyBridge({
    env: {
      XHUB_RUST_PROVIDER_QUOTA_APPLY: '1',
      XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP_BASE_URL: 'http://127.0.0.1:55153',
    },
    httpPostJsonImpl: async (url, body, options) => {
      calls.push({ url: String(url), body, options });
      return {
        ok: true,
        command: 'plan-openai-quota',
        result: {
          ok: true,
          accounts: [{ account_key: 'acct-1' }],
          due_accounts: 1,
          eligible_accounts: 2,
          total_accounts: 3,
          skipped_count: 1,
        },
      };
    },
    logger: { warn() {} },
  });

  const out = await bridge.planOpenAIQuotaRefresh({
    runtimeBaseDir: '/tmp/runtime',
    nowMs: 999,
    includeSkipped: true,
    inFlightAccountKeys: ['busy'],
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'http://127.0.0.1:55153/provider/openai-quota-refresh/plan');
  assert.equal(calls[0].body.runtime_base_dir, '/tmp/runtime');
  assert.equal(calls[0].body.now_ms, 999);
  assert.equal(calls[0].body.include_skipped, true);
  assert.deepEqual(calls[0].body.in_flight_account_keys, ['busy']);
  assert.equal(out.ok, true);
  assert.deepEqual(out.account_keys, ['acct-1']);
  assert.equal(out.due_accounts, 1);
});

await run('Rust provider quota apply bridge posts OpenAI usage payload', async () => {
  const calls = [];
  const bridge = createRustProviderQuotaApplyBridge({
    env: {
      XHUB_RUST_PROVIDER_QUOTA_APPLY: '1',
      XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP_BASE_URL: 'http://127.0.0.1:55153',
      XHUB_RUST_PROVIDER_QUOTA_APPLY_TIMEOUT_MS: '2345',
      XHUB_RUST_HTTP_ACCESS_KEY: 'secret',
    },
    httpPostJsonImpl: async (url, body, options) => {
      calls.push({ url: String(url), body, options });
      return {
        ok: true,
        command: 'apply-openai-quota',
        result: {
          ok: true,
          account_key: 'acct-1',
          next_refresh_at_ms: 123456,
          refreshed_at_ms: 123000,
          limited: false,
        },
      };
    },
    logger: { warn() {} },
  });

  const out = await bridge.applyOpenAIQuotaRefresh({
    runtimeBaseDir: '/tmp/runtime',
    accountKey: 'acct-1',
    usage: {
      plan_type: 'plus',
      rate_limit: {
        primary_window: { used_percent: 25, limit_window_seconds: 18000 },
      },
    },
    nowMs: 123000,
    successIntervalMs: 300000,
    highWaterIntervalMs: 60000,
    accountId: 'acct-openai',
    oauthSourceKey: 'chatgpt',
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'http://127.0.0.1:55153/provider/openai-quota-refresh/apply');
  assert.equal(calls[0].options.timeoutMs, 2345);
  assert.equal(calls[0].options.accessKey, 'secret');
  assert.equal(calls[0].body.runtime_base_dir, '/tmp/runtime');
  assert.equal(calls[0].body.account_key, 'acct-1');
  assert.equal(calls[0].body.usage.plan_type, 'plus');
  assert.equal(calls[0].body.now_ms, 123000);
  assert.equal(calls[0].body.account_id, 'acct-openai');
  assert.equal(out.ok, true);
  assert.equal(out.used, true);
  assert.equal(out.next_refresh_at_ms, 123456);
});

await run('Rust provider quota bridge posts OpenAI failure state', async () => {
  const calls = [];
  const bridge = createRustProviderQuotaApplyBridge({
    env: {
      XHUB_RUST_PROVIDER_QUOTA_APPLY: '1',
      XHUB_RUST_PROVIDER_QUOTA_APPLY_HTTP_BASE_URL: 'http://127.0.0.1:55153',
    },
    httpPostJsonImpl: async (url, body, options) => {
      calls.push({ url: String(url), body, options });
      return {
        ok: true,
        command: 'record-openai-quota-failure',
        result: {
          ok: true,
          account_key: 'acct-1',
          failure_count: 2,
          next_refresh_at_ms: 456000,
          failed_at_ms: 123000,
        },
      };
    },
    logger: { warn() {} },
  });

  const out = await bridge.recordOpenAIQuotaRefreshFailure({
    runtimeBaseDir: '/tmp/runtime',
    accountKey: 'acct-1',
    failedAtMs: 123000,
    baseFailureBackoffMs: 60000,
    maxFailureBackoffMs: 900000,
    errorCode: 'ETIMEDOUT',
    errorMessage: 'timeout',
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'http://127.0.0.1:55153/provider/openai-quota-refresh/failure');
  assert.equal(calls[0].body.account_key, 'acct-1');
  assert.equal(calls[0].body.failed_at_ms, 123000);
  assert.equal(calls[0].body.error_code, 'ETIMEDOUT');
  assert.equal(out.ok, true);
  assert.equal(out.failure_count, 2);
  assert.equal(out.next_refresh_at_ms, 456000);
});
