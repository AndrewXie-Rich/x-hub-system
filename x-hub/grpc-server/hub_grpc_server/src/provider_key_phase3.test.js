import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  addProviderKey,
  removeProviderKey,
  reportKeyUsage,
  reportKeyError,
  getKeyUsage,
  resetKeyErrorState,
  invalidateProviderKeyCache,
  setProviderRoutingStrategy,
  listProviderKeys,
  providerKeyStoreSummary,
} from './provider_key_store.js';

import {
  resolveProviderKeyForModel,
  resolveProviderKeyWithFallback,
  inferProviderFromModelId,
  isAccountAvailable,
  scoreAccount,
} from './provider_key_router.js';

import { enqueueBridgeAIGenerate } from './bridge_ipc.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-p3-'));
}

// ---- Bridge IPC provider_key integration ----

await run('enqueueBridgeAIGenerate includes provider_key in request file', () => {
  const dir = makeTempDir();
  const bridgeDir = path.join(dir, 'bridge');
  fs.mkdirSync(path.join(bridgeDir, 'bridge_requests'), { recursive: true });
  fs.mkdirSync(path.join(bridgeDir, 'bridge_responses'), { recursive: true });

  const result = enqueueBridgeAIGenerate(bridgeDir, {
    request_id: 'test-pk-001',
    app_id: 'x_terminal',
    model_id: 'gpt-4o',
    prompt: 'hello',
    max_tokens: 100,
    provider_key: {
      account_key: 'openai:test@example.com',
      provider: 'openai',
      api_key: 'sk-test-key-1234567890',
      base_url: 'https://api.openai.com',
      proxy_url: 'https://proxy.example/openai',
      auth_type: 'oauth',
      refresh_token: 'refresh-test-123',
      account_id: 'acct-openai-1',
      oauth_source_key: 'chatgpt',
      auth_index: 3,
      source_type: 'auth_file',
      source_ref: '/tmp/auth19.json',
      custom_headers: { 'X-Custom': 'value' },
    },
  });

  const reqPath = result.filePath;
  assert.ok(fs.existsSync(reqPath));
  const obj = JSON.parse(fs.readFileSync(reqPath, 'utf8'));
  assert.equal(obj.type, 'ai_generate');
  assert.equal(obj.model_id, 'gpt-4o');
  assert.ok(obj.provider_key);
  assert.equal(obj.provider_key.account_key, 'openai:test@example.com');
  assert.equal(obj.provider_key.provider, 'openai');
  assert.equal(obj.provider_key.api_key, 'sk-test-key-1234567890');
  assert.equal(obj.provider_key.base_url, 'https://api.openai.com');
  assert.equal(obj.provider_key.proxy_url, 'https://proxy.example/openai');
  assert.equal(obj.provider_key.auth_type, 'oauth');
  assert.equal(obj.provider_key.refresh_token, 'refresh-test-123');
  assert.equal(obj.provider_key.account_id, 'acct-openai-1');
  assert.equal(obj.provider_key.oauth_source_key, 'chatgpt');
  assert.equal(obj.provider_key.auth_index, 3);
  assert.equal(obj.provider_key.source_type, 'auth_file');
  assert.equal(obj.provider_key.source_ref, '/tmp/auth19.json');
  assert.deepEqual(obj.provider_key.custom_headers, { 'X-Custom': 'value' });
});

await run('enqueueBridgeAIGenerate omits provider_key when not provided', () => {
  const dir = makeTempDir();
  const bridgeDir = path.join(dir, 'bridge');
  fs.mkdirSync(path.join(bridgeDir, 'bridge_requests'), { recursive: true });
  fs.mkdirSync(path.join(bridgeDir, 'bridge_responses'), { recursive: true });

  const result = enqueueBridgeAIGenerate(bridgeDir, {
    request_id: 'test-no-pk-001',
    app_id: 'x_terminal',
    model_id: 'gpt-4o',
    prompt: 'hello',
    max_tokens: 100,
  });

  const obj = JSON.parse(fs.readFileSync(result.filePath, 'utf8'));
  assert.equal(obj.type, 'ai_generate');
  assert.ok(!obj.provider_key);
});

// ---- End-to-end: add key → route → bridge inject ----

await run('E2E: add key → resolve for model → bridge request has provider_key', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-e2e-test-1234567890',
    auth_type: 'api_key',
    base_url: 'https://api.openai.com',
  });

  invalidateProviderKeyCache();
  const route = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.ok(route.account);
  assert.equal(route.provider, 'openai');

  const bridgeDir = path.join(dir, 'bridge');
  fs.mkdirSync(path.join(bridgeDir, 'bridge_requests'), { recursive: true });
  fs.mkdirSync(path.join(bridgeDir, 'bridge_responses'), { recursive: true });

  enqueueBridgeAIGenerate(bridgeDir, {
    request_id: 'e2e-pk-001',
    app_id: 'x_terminal',
    model_id: 'gpt-4o',
    prompt: 'test prompt',
    max_tokens: 100,
    provider_key: {
      account_key: route.account.account_key,
      provider: route.account.provider,
      api_key: route.account.api_key,
      base_url: route.account.base_url,
      proxy_url: route.account.proxy_url,
      auth_type: route.account.auth_type,
      custom_headers: route.account.custom_headers || {},
    },
  });

  const reqPath = path.join(bridgeDir, 'bridge_requests', 'req_e2e-pk-001.json');
  assert.ok(fs.existsSync(reqPath));
  const obj = JSON.parse(fs.readFileSync(reqPath, 'utf8'));
  assert.ok(obj.provider_key);
  assert.equal(obj.provider_key.provider, 'openai');
  assert.equal(obj.provider_key.api_key, 'sk-e2e-test-1234567890');
  assert.equal(obj.provider_key.base_url, 'https://api.openai.com');
});

// ---- E2E: error → auto-disable → fallback to next key ----

await run('E2E: error on key1 → auto-disable → fallback to key2', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'primary',
    api_key: 'sk-primary-1234567890',
    auth_type: 'api_key',
  });
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'backup',
    api_key: 'sk-backup-1234567890',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  const route1 = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.ok(route1.account);
  const firstKey = route1.account.account_key;

  invalidateProviderKeyCache();
  reportKeyError(dir, firstKey, { error_code: '401' });

  invalidateProviderKeyCache();
  const route2 = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.ok(route2.account);
  assert.notEqual(route2.account.account_key, firstKey);
  assert.equal(route2.account.api_key, 'sk-backup-1234567890');
});

// ---- E2E: quota-aware routing with usage tracking ----

await run('E2E: quota-aware routing tracks usage and switches keys', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'claude',
    email: 'heavy',
    api_key: 'sk-ant-heavy-1234567890',
    auth_type: 'api_key',
  });
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'claude',
    email: 'light',
    api_key: 'sk-ant-light-1234567890',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  setProviderRoutingStrategy(dir, 'claude', 'quota-aware');

  invalidateProviderKeyCache();
  const rawPath = path.join(dir, 'hub_provider_keys.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));
  raw.providers.claude.accounts[0].quota = {
    daily_token_cap: 10000,
    daily_tokens_used: 9000,
    daily_tokens_remaining: 1000,
    total_tokens_used: 50000,
    last_used_at_ms: Date.now(),
    last_error_at_ms: 0,
    consecutive_errors: 0,
    cooldown_until_ms: 0,
  };
  raw.providers.claude.accounts[1].quota = {
    daily_token_cap: 10000,
    daily_tokens_used: 1000,
    daily_tokens_remaining: 9000,
    total_tokens_used: 5000,
    last_used_at_ms: Date.now(),
    last_error_at_ms: 0,
    consecutive_errors: 0,
    cooldown_until_ms: 0,
  };
  fs.writeFileSync(rawPath, JSON.stringify(raw, null, 2));

  invalidateProviderKeyCache();
  const route = resolveProviderKeyForModel(dir, 'claude-3.5-sonnet');
  assert.ok(route.account);
  assert.equal(route.account.email, 'light');
});

// ---- E2E: reset error state restores key availability ----

await run('E2E: reset error state restores key availability', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'gemini',
    api_key: 'AIza-reset-e2e-1234567890',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  const route1 = resolveProviderKeyForModel(dir, 'gemini-2.0-flash');
  assert.ok(route1.account);
  const key = route1.account.account_key;

  invalidateProviderKeyCache();
  reportKeyError(dir, key, { error_code: '401' });

  invalidateProviderKeyCache();
  const route2 = resolveProviderKeyForModel(dir, 'gemini-2.0-flash');
  assert.equal(route2.account, null);

  invalidateProviderKeyCache();
  resetKeyErrorState(dir, key);

  invalidateProviderKeyCache();
  const route3 = resolveProviderKeyForModel(dir, 'gemini-2.0-flash');
  assert.ok(route3.account);
  assert.equal(route3.account.account_key, key);
});

// ---- E2E: getKeyUsage returns full quota info ----

await run('E2E: getKeyUsage returns full quota info after usage and error', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-usage-e2e-1234567890',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  const keys = listProviderKeys(dir, 'openai');
  assert.ok(keys.length > 0);
  const key = keys[0].account_key;

  invalidateProviderKeyCache();
  reportKeyUsage(dir, key, { tokens_used: 5000, cost_usd: 0.05 });

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, key);
  assert.ok(usage);
  assert.equal(usage.quota.daily_tokens_used, 5000);
  assert.equal(usage.quota.total_tokens_used, 5000);
  assert.equal(usage.error_state.status, 'healthy');

  invalidateProviderKeyCache();
  reportKeyError(dir, key, { error_code: '429' });

  invalidateProviderKeyCache();
  const usage2 = getKeyUsage(dir, key);
  assert.equal(usage2.error_state.status, 'rate_limited');
  assert.ok(usage2.quota.cooldown_until_ms > Date.now());
});

// ---- provider_key_store summary reflects state ----

await run('E2E: providerKeyStoreSummary reflects enabled/disabled counts', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'active',
    api_key: 'sk-summary-active-1234567890',
    auth_type: 'api_key',
  });
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'disabled',
    api_key: 'sk-summary-disabled-1234567890',
    auth_type: 'api_key',
    enabled: false,
  });

  invalidateProviderKeyCache();
  const summary = providerKeyStoreSummary(dir);
  const openai = summary.providers.find(p => p.provider === 'openai');
  assert.ok(openai);
  assert.equal(openai.total_accounts, 2);
  assert.equal(openai.enabled_accounts, 1);
});

process.stdout.write('\nAll Phase 3 integration tests passed.\n');
