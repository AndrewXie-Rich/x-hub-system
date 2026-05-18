import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  addProviderKey,
  removeProviderKey,
  removeProviderKeys,
  reportKeyUsage,
  reportKeyError,
  getKeyUsage,
  resetKeyErrorState,
  invalidateProviderKeyCache,
  listProviderKeys,
  listProviderKeyPools,
  setProviderRoutingStrategy,
} from './provider_key_store.js';

import {
  resolveProviderKeyForModel,
  resolveProviderKeyWithFallback,
  inferProviderFromModelId,
  isAccountAvailable,
  scoreAccount,
  buildProviderRequestHeaders,
  buildProviderRequestUrl,
} from './provider_key_router.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-p2-'));
}

// ---- provider_key_store quota/error tests ----

await run('reportKeyUsage tracks daily tokens', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-usage-test-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);

  invalidateProviderKeyCache();
  const usageResult = reportKeyUsage(dir, addResult.account_key, { tokens_used: 1000 });
  assert.equal(usageResult.ok, true);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.ok(usage);
  assert.equal(usage.quota.daily_tokens_used, 1000);
  assert.equal(usage.quota.total_tokens_used, 1000);
  assert.ok(usage.quota.last_used_at_ms > 0);
});

await run('reportKeyUsage resets daily counter on new day', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'claude',
    api_key: 'sk-day-reset-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);

  invalidateProviderKeyCache();
  const store = { providers: {} };
  const rawPath = path.join(dir, 'hub_provider_keys.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));
  const account = raw.providers.claude.accounts[0];
  account.quota = {
    daily_token_cap: 10000,
    daily_tokens_used: 9500,
    daily_tokens_remaining: 500,
    total_tokens_used: 50000,
    last_used_at_ms: Date.now() - 86400000,
    last_error_at_ms: 0,
    consecutive_errors: 0,
    cooldown_until_ms: 0,
  };
  fs.writeFileSync(rawPath, JSON.stringify(raw, null, 2));

  invalidateProviderKeyCache();
  const usageResult = reportKeyUsage(dir, addResult.account_key, { tokens_used: 500 });
  assert.equal(usageResult.ok, true);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.equal(usage.quota.daily_tokens_used, 500);
  assert.equal(usage.quota.total_tokens_used, 50500);
});

await run('reportKeyUsage with daily_token_cap updates remaining', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'gemini',
    api_key: 'AIza-cap-test-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);

  invalidateProviderKeyCache();
  const rawPath = path.join(dir, 'hub_provider_keys.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));
  raw.providers.gemini.accounts[0].quota = {
    daily_token_cap: 5000,
    daily_tokens_used: 3000,
    daily_tokens_remaining: 2000,
    total_tokens_used: 10000,
    last_used_at_ms: Date.now(),
    last_error_at_ms: 0,
    consecutive_errors: 0,
    cooldown_until_ms: 0,
  };
  fs.writeFileSync(rawPath, JSON.stringify(raw, null, 2));

  invalidateProviderKeyCache();
  reportKeyUsage(dir, addResult.account_key, { tokens_used: 1500 });

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.equal(usage.quota.daily_tokens_used, 4500);
  assert.equal(usage.quota.daily_tokens_remaining, 500);
});

await run('reportKeyError marks auth_failed and auto-disables', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-auth-err-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);

  invalidateProviderKeyCache();
  const errResult = reportKeyError(dir, addResult.account_key, { error_code: '401' });
  assert.equal(errResult.ok, true);
  assert.equal(errResult.auto_disabled, true);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.equal(usage.error_state.status, 'auth_failed');
  assert.equal(usage.error_state.auto_disabled, true);
});

await run('reportKeyError marks rate_limited with cooldown', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'claude',
    api_key: 'sk-rate-err-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);

  invalidateProviderKeyCache();
  const errResult = reportKeyError(dir, addResult.account_key, { error_code: '429' });
  assert.equal(errResult.ok, true);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.equal(usage.error_state.status, 'rate_limited');
  assert.ok(usage.quota.cooldown_until_ms > Date.now());
  assert.equal(usage.quota.consecutive_errors, 1);
});

await run('reportKeyError auto-disables after 5 consecutive errors', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'gemini',
    api_key: 'AIza-consec-err-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);

  for (let i = 0; i < 5; i++) {
    invalidateProviderKeyCache();
    reportKeyError(dir, addResult.account_key, { error_code: '500' });
  }

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.equal(usage.error_state.status, 'degraded');
  assert.equal(usage.error_state.auto_disabled, true);
});

await run('reportKeyUsage clears consecutive_errors on success', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-clear-err-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);

  invalidateProviderKeyCache();
  reportKeyError(dir, addResult.account_key, { error_code: '500' });
  invalidateProviderKeyCache();
  reportKeyUsage(dir, addResult.account_key, { tokens_used: 100 });

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.equal(usage.quota.consecutive_errors, 0);
  assert.equal(usage.error_state.status, 'healthy');
});

await run('resetKeyErrorState restores healthy state', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'claude',
    api_key: 'sk-reset-err-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);

  invalidateProviderKeyCache();
  reportKeyError(dir, addResult.account_key, { error_code: '401' });

  invalidateProviderKeyCache();
  const resetResult = resetKeyErrorState(dir, addResult.account_key);
  assert.equal(resetResult.ok, true);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, addResult.account_key);
  assert.equal(usage.error_state.status, 'healthy');
  assert.equal(usage.error_state.auto_disabled, false);
  assert.equal(usage.quota.consecutive_errors, 0);
  assert.equal(usage.quota.cooldown_until_ms, 0);
});

await run('getKeyUsage returns null for missing account', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, 'nonexistent:key');
  assert.equal(usage, null);
});

await run('listProviderKeyPools aggregates shared codex/openai GPT-5.4 quota pools and exposes member diagnostics', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const expired = addProviderKey(dir, {
    provider: 'codex',
    email: 'free-expired@example.com',
    api_key: 'codex-access-expired-1234567890',
    refresh_token: 'codex-refresh-expired-1234567890',
    auth_type: 'oauth',
    tier: 'Free',
  });
  assert.equal(expired.ok, true);

  invalidateProviderKeyCache();
  const ready = addProviderKey(dir, {
    provider: 'openai',
    email: 'pro-ready@example.com',
    api_key: 'sk-openai-ready-1234567890',
    auth_type: 'api_key',
    tier: 'Pro',
  });
  assert.equal(ready.ok, true);

  invalidateProviderKeyCache();
  const cooldown = addProviderKey(dir, {
    provider: 'openai',
    email: 'plus-cooldown@example.com',
    api_key: 'sk-openai-cooldown-1234567890',
    auth_type: 'api_key',
    tier: 'Plus',
  });
  assert.equal(cooldown.ok, true);

  invalidateProviderKeyCache();
  const excluded = addProviderKey(dir, {
    provider: 'openai',
    email: 'gpt4o-only@example.com',
    api_key: 'sk-openai-gpt4o-only-1234567890',
    auth_type: 'api_key',
    tier: 'Plus',
    models: ['gpt-4o'],
  });
  assert.equal(excluded.ok, true);

  const rawPath = path.join(dir, 'hub_provider_keys.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));
  const codexExpired = raw.providers.codex.accounts.find((account) => account.email === 'free-expired@example.com');
  codexExpired.expires_at_ms = Date.now() - 60_000;
  codexExpired.quota = {
    daily_token_cap: 2_000,
    daily_tokens_used: 100,
    daily_tokens_remaining: 1_900,
    total_tokens_used: 10_000,
    last_used_at_ms: Date.now() - 120_000,
    last_error_at_ms: 0,
    consecutive_errors: 0,
    cooldown_until_ms: 0,
  };

  const openaiReady = raw.providers.openai.accounts.find((account) => account.email === 'pro-ready@example.com');
  openaiReady.quota = {
    daily_token_cap: 8_000,
    daily_tokens_used: 2_000,
    daily_tokens_remaining: 6_000,
    total_tokens_used: 40_000,
    last_used_at_ms: Date.now() - 30_000,
    last_error_at_ms: 0,
    consecutive_errors: 0,
    cooldown_until_ms: 0,
  };

  const openaiCooldown = raw.providers.openai.accounts.find((account) => account.email === 'plus-cooldown@example.com');
  openaiCooldown.quota = {
    daily_token_cap: 4_000,
    daily_tokens_used: 500,
    daily_tokens_remaining: 3_500,
    total_tokens_used: 6_000,
    last_used_at_ms: Date.now() - 90_000,
    last_error_at_ms: Date.now() - 45_000,
    consecutive_errors: 1,
    cooldown_until_ms: Date.now() + 45_000,
  };
  openaiCooldown.error_state = {
    status: 'rate_limited',
    reason_code: 'rate_limited',
    last_error_code: '429',
    last_error_at_ms: Date.now() - 45_000,
    next_retry_at_ms: Date.now() + 45_000,
    retry_at_source: 'quota',
    auto_disabled: false,
  };

  const openaiExcluded = raw.providers.openai.accounts.find((account) => account.email === 'gpt4o-only@example.com');
  openaiExcluded.quota = {
    daily_token_cap: 4_000,
    daily_tokens_used: 250,
    daily_tokens_remaining: 3_750,
    total_tokens_used: 5_000,
    last_used_at_ms: Date.now() - 15_000,
    last_error_at_ms: 0,
    consecutive_errors: 0,
    cooldown_until_ms: 0,
  };

  fs.writeFileSync(rawPath, JSON.stringify(raw, null, 2));

  invalidateProviderKeyCache();
  const pools = listProviderKeyPools(dir, {
    provider: 'codex',
    model_id: 'openai/gpt-5.4',
    include_members: true,
  });
  assert.equal(pools.length, 1);
  assert.equal(pools[0].provider, 'openai');
  assert.equal(pools[0].model_family, 'gpt-5.4');
  assert.deepEqual(pools[0].source_providers, ['codex', 'openai']);
  assert.equal(pools[0].total_accounts, 3);
  assert.equal(pools[0].ready_accounts, 1);
  assert.equal(pools[0].cooldown_accounts, 1);
  assert.equal(pools[0].expired_accounts, 1);
  assert.equal(pools[0].free_accounts, 1);
  assert.equal(pools[0].paid_accounts, 2);
  assert.equal(pools[0].known_quota_accounts, 3);
  assert.equal(pools[0].removable_accounts, 1);
  assert.equal(pools[0].daily_token_cap, 14_000);
  assert.equal(pools[0].daily_tokens_used, 2_600);
  assert.equal(pools[0].daily_tokens_remaining, 11_400);
  assert.equal(pools[0].total_tokens_used, 56_000);
  assert.ok(pools[0].next_retry_at_ms > Date.now());
  assert.ok(pools[0].blocker_reason_codes.includes('rate_limited'));
  assert.ok(pools[0].blocker_reason_codes.includes('token_expired'));

  const expiredMember = pools[0].members.find((member) => member.email === 'free-expired@example.com');
  assert.ok(expiredMember);
  assert.equal(expiredMember.state, 'expired');
  assert.equal(expiredMember.removable, true);
  assert.equal(expiredMember.removal_reason, 'token_expired');

  const cooldownMember = pools[0].members.find((member) => member.email === 'plus-cooldown@example.com');
  assert.ok(cooldownMember);
  assert.equal(cooldownMember.state, 'cooldown');
  assert.equal(cooldownMember.reason_code, 'rate_limited');

  assert.equal(pools[0].members.some((member) => member.email === 'gpt4o-only@example.com'), false);
});

await run('removeProviderKeys removes multiple accounts and reports missing account keys', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const first = addProviderKey(dir, {
    provider: 'openai',
    email: 'first@example.com',
    api_key: 'sk-batch-remove-1',
    auth_type: 'api_key',
  });
  assert.equal(first.ok, true);

  invalidateProviderKeyCache();
  const second = addProviderKey(dir, {
    provider: 'claude',
    email: 'second@example.com',
    api_key: 'sk-batch-remove-2',
    auth_type: 'api_key',
  });
  assert.equal(second.ok, true);

  invalidateProviderKeyCache();
  const third = addProviderKey(dir, {
    provider: 'gemini',
    email: 'third@example.com',
    api_key: 'AIza-batch-remove-3',
    auth_type: 'api_key',
  });
  assert.equal(third.ok, true);

  invalidateProviderKeyCache();
  const removed = removeProviderKeys(dir, [
    first.account_key,
    'missing:key',
    third.account_key,
  ]);
  assert.equal(removed.ok, true);
  assert.equal(removed.removed, 2);
  assert.deepEqual(removed.missing_account_keys, ['missing:key']);

  invalidateProviderKeyCache();
  const remaining = listProviderKeys(dir);
  assert.equal(remaining.length, 1);
  assert.equal(remaining[0].account_key, second.account_key);
});

// ---- provider_key_router tests ----

await run('inferProviderFromModelId detects openai models', () => {
  assert.equal(inferProviderFromModelId('gpt-4o'), 'openai');
  assert.equal(inferProviderFromModelId('gpt-3.5-turbo'), 'openai');
  assert.equal(inferProviderFromModelId('o1-preview'), 'openai');
  assert.equal(inferProviderFromModelId('o3-mini'), 'openai');
  assert.equal(inferProviderFromModelId('openai/gpt-5.4'), 'openai');
  assert.equal(inferProviderFromModelId('models/gpt-5.4'), 'openai');
  assert.equal(inferProviderFromModelId('openai/gpt-5.3-codex'), 'openai');
});

await run('inferProviderFromModelId detects claude models', () => {
  assert.equal(inferProviderFromModelId('claude-3.5-sonnet'), 'claude');
  assert.equal(inferProviderFromModelId('claude-sonnet-4'), 'claude');
});

await run('inferProviderFromModelId detects gemini models', () => {
  assert.equal(inferProviderFromModelId('gemini-2.0-flash'), 'gemini');
  assert.equal(inferProviderFromModelId('gemini-2.5-pro'), 'gemini');
});

await run('inferProviderFromModelId returns empty for unknown', () => {
  assert.equal(inferProviderFromModelId('unknown-model'), '');
  assert.equal(inferProviderFromModelId(''), '');
});

await run('resolveProviderKeyForModel returns account for known provider', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-route-test-1234567890',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.ok(result.account);
  assert.equal(result.provider, 'openai');
  assert.equal(result.fallback_reason, '');
});

await run('resolveProviderKeyForModel prefers accounts whose model allowlist matches the requested model', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'generic',
    api_key: 'sk-route-generic',
    auth_type: 'api_key',
  });
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'targeted',
    api_key: 'sk-route-targeted',
    auth_type: 'api_key',
    models: ['gpt-4o'],
  });

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.ok(result.account);
  assert.equal(result.account.email, 'targeted');
});

await run('resolveProviderKeyForModel shares the openai execution pool with codex accounts', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'codex',
    api_key: 'codex-oauth-access-token-1234567890',
    auth_type: 'oauth',
    refresh_token: 'codex-oauth-refresh-token-1234567890',
  });

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'openai/gpt-5.4');
  assert.ok(result.account);
  assert.equal(result.provider, 'openai');
  assert.equal(result.account.provider, 'codex');
});

await run('resolveProviderKeyForModel returns no_keys_for_provider when empty', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.equal(result.account, null);
  assert.equal(result.fallback_reason, 'no_keys_for_provider');
});

await run('resolveProviderKeyForModel skips disabled accounts', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-disabled-route-1234567890',
    auth_type: 'api_key',
    enabled: false,
  });

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.equal(result.account, null);
  assert.equal(result.fallback_reason, 'all_keys_disabled');
});

await run('resolveProviderKeyForModel fill-first rear-ranks degraded keys', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const first = addProviderKey(dir, {
    provider: 'openai',
    email: 'bad-scope',
    api_key: 'sk-openai-bad-scope',
    auth_type: 'api_key',
  });
  assert.equal(first.ok, true);
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'healthy',
    api_key: 'sk-openai-healthy',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  reportKeyError(dir, first.account_key, { error_code: 'missing scope:api.responses.write' });

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.ok(result.account);
  assert.equal(result.account.email, 'healthy');
});

await run('resolveProviderKeyForModel skips accounts in cooldown', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'claude',
    api_key: 'sk-cooldown-route-1234567890',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  const rawPath = path.join(dir, 'hub_provider_keys.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));
  raw.providers.claude.accounts[0].quota = {
    daily_token_cap: 0,
    daily_tokens_used: 0,
    daily_tokens_remaining: 0,
    total_tokens_used: 0,
    last_used_at_ms: Date.now(),
    last_error_at_ms: 0,
    consecutive_errors: 1,
    cooldown_until_ms: Date.now() + 60000,
  };
  fs.writeFileSync(rawPath, JSON.stringify(raw, null, 2));

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'claude-3.5-sonnet');
  assert.equal(result.account, null);
  assert.equal(result.fallback_reason, 'all_keys_in_cooldown');
});

await run('resolveProviderKeyForModel respects error_state next_retry_at_ms cooldown windows', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-retry-window',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  const rawPath = path.join(dir, 'hub_provider_keys.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));
  raw.providers.openai.accounts[0].error_state = {
    status: 'blocked_network',
    reason_code: 'provider_timeout',
    next_retry_at_ms: Date.now() + 30000,
    retry_at_source: 'scheduler',
    auto_disabled: false,
  };
  fs.writeFileSync(rawPath, JSON.stringify(raw, null, 2));

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.equal(result.account, null);
  assert.equal(result.fallback_reason, 'all_keys_in_cooldown');
});

await run('resolveProviderKeyForModel reports stale pools distinctly', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-stale-route',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  const rawPath = path.join(dir, 'hub_provider_keys.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));
  raw.providers.openai.accounts[0].error_state = {
    status: 'unknown_stale',
    reason_code: 'runtime_stale',
    auto_disabled: false,
  };
  fs.writeFileSync(rawPath, JSON.stringify(raw, null, 2));

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.equal(result.account, null);
  assert.equal(result.fallback_reason, 'all_keys_stale');
});

await run('resolveProviderKeyForModel skips expired accounts', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'gemini',
    api_key: 'AIza-expired-route-1234567890',
    auth_type: 'api_key',
    expires_at_ms: Date.now() - 1000,
  });

  invalidateProviderKeyCache();
  const result = resolveProviderKeyForModel(dir, 'gemini-2.0-flash');
  assert.equal(result.account, null);
});

await run('resolveProviderKeyForModel with quota-aware strategy picks least used', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'heavy',
    api_key: 'sk-qa-heavy-1234567890',
    auth_type: 'api_key',
  });
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    email: 'light',
    api_key: 'sk-qa-light-1234567890',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  setProviderRoutingStrategy(dir, 'openai', 'quota-aware');

  invalidateProviderKeyCache();
  const rawPath = path.join(dir, 'hub_provider_keys.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));
  raw.providers.openai.accounts[0].quota = {
    daily_token_cap: 10000,
    daily_tokens_used: 9000,
    daily_tokens_remaining: 1000,
    total_tokens_used: 50000,
    last_used_at_ms: Date.now(),
    last_error_at_ms: 0,
    consecutive_errors: 0,
    cooldown_until_ms: 0,
  };
  raw.providers.openai.accounts[1].quota = {
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
  const result = resolveProviderKeyForModel(dir, 'gpt-4o');
  assert.ok(result.account);
  assert.equal(result.account.email, 'light');
});

await run('resolveProviderKeyWithFallback tries fallback providers', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'claude',
    api_key: 'sk-fallback-claude-1234567890',
    auth_type: 'api_key',
  });

  invalidateProviderKeyCache();
  const result = resolveProviderKeyWithFallback(dir, 'gpt-4o', ['claude']);
  assert.ok(result.account);
  assert.equal(result.provider, 'claude');
  assert.ok(result.fallback_reason.includes('fallback_from'));
});

await run('isAccountAvailable returns false for disabled', () => {
  assert.equal(isAccountAvailable({ enabled: false, api_key: 'sk-test' }, Date.now()), false);
});

await run('isAccountAvailable returns false for auth_failed auto_disabled', () => {
  assert.equal(isAccountAvailable({
    enabled: true,
    api_key: 'sk-test',
    error_state: { status: 'auth_failed', auto_disabled: true },
  }, Date.now()), false);
});

await run('isAccountAvailable returns false for unknown_stale', () => {
  assert.equal(isAccountAvailable({
    enabled: true,
    api_key: 'sk-test',
    error_state: { status: 'unknown_stale', reason_code: 'runtime_stale', auto_disabled: false },
  }, Date.now()), false);
});

await run('isAccountAvailable returns false for expired', () => {
  assert.equal(isAccountAvailable({
    enabled: true,
    api_key: 'sk-test',
    expires_at_ms: Date.now() - 1000,
  }, Date.now()), false);
});

await run('isAccountAvailable returns true for healthy account', () => {
  assert.equal(isAccountAvailable({
    enabled: true,
    api_key: 'sk-test',
  }, Date.now()), true);
});

await run('buildProviderRequestHeaders sets Bearer for openai', () => {
  const headers = buildProviderRequestHeaders({
    provider: 'openai',
    api_key: 'sk-test',
    custom_headers: {},
  });
  assert.equal(headers['Authorization'], 'Bearer sk-test');
});

await run('buildProviderRequestHeaders sets x-api-key for claude', () => {
  const headers = buildProviderRequestHeaders({
    provider: 'claude',
    api_key: 'sk-ant-test',
    custom_headers: {},
  });
  assert.equal(headers['x-api-key'], 'sk-ant-test');
  assert.equal(headers['anthropic-version'], '2023-06-01');
});

await run('buildProviderRequestUrl returns correct endpoint for openai', () => {
  const url = buildProviderRequestUrl({
    provider: 'openai',
    base_url: 'https://api.openai.com',
  }, 'gpt-4o');
  assert.equal(url, 'https://api.openai.com/v1/chat/completions');
});

await run('buildProviderRequestUrl returns correct endpoint for claude', () => {
  const url = buildProviderRequestUrl({
    provider: 'claude',
    base_url: 'https://api.anthropic.com',
  }, 'claude-3.5-sonnet');
  assert.equal(url, 'https://api.anthropic.com/v1/messages');
});

await run('buildProviderRequestUrl returns correct endpoint for gemini', () => {
  const url = buildProviderRequestUrl({
    provider: 'gemini',
    base_url: 'https://generativelanguage.googleapis.com',
    api_key: 'AIza-test',
  }, 'gemini-2.0-flash');
  assert.ok(url.includes('/v1beta/models/gemini-2.0-flash:generateContent'));
  assert.ok(url.includes('key=AIza-test'));
});

await run('scoreAccount gives higher score to higher priority', () => {
  const now = Date.now();
  const low = scoreAccount({ enabled: true, api_key: 'sk-low', priority: 1, error_state: { status: 'healthy' }, quota: {} }, now);
  const high = scoreAccount({ enabled: true, api_key: 'sk-high', priority: 5, error_state: { status: 'healthy' }, quota: {} }, now);
  assert.ok(high > low);
});

await run('scoreAccount penalizes rate_limited', () => {
  const now = Date.now();
  const healthy = scoreAccount({ enabled: true, api_key: 'sk-healthy', priority: 0, error_state: { status: 'healthy' }, quota: {} }, now);
  const rateLimited = scoreAccount({ enabled: true, api_key: 'sk-rate-limited', priority: 0, error_state: { status: 'rate_limited' }, quota: {} }, now);
  assert.ok(healthy > rateLimited);
});

process.stdout.write('\nAll Phase 2 tests passed.\n');
