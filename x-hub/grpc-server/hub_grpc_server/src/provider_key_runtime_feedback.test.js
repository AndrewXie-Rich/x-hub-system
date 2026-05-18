import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  addProviderKey,
  getKeyUsage,
  invalidateProviderKeyCache,
} from './provider_key_store.js';
import {
  normalizeProviderKeyRuntimeEvent,
  recordProviderKeyRuntimeEvent,
} from './provider_key_usage_events.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-runtime-feedback-'));
}

await run('normalizeProviderKeyRuntimeEvent derives missing_scope auth event', () => {
  const event = normalizeProviderKeyRuntimeEvent({
    account_key: 'openai:test',
    model_id: 'gpt-5.4',
    http_status: 403,
    status_message: 'Provider 权限不足，缺少生成 scope:api.responses.write。',
  });

  assert.equal(event.outcome, 'auth_error');
  assert.equal(event.reason_code, 'missing_scope');
});

await run('recordProviderKeyRuntimeEvent keeps missing_scope blocked but not auto-disabled', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const added = addProviderKey(dir, {
    provider: 'openai',
    email: 'scope@test.local',
    api_key: 'sk-scope-test-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(added.ok, true);

  const result = recordProviderKeyRuntimeEvent(dir, {
    account_key: added.account_key,
    model_id: 'gpt-5.4',
    http_status: 403,
    status_message: 'Provider 权限不足，缺少生成 scope:api.responses.write。',
  });
  assert.equal(result.ok, true);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, added.account_key);
  assert.equal(usage?.error_state?.status, 'blocked_auth');
  assert.equal(usage?.error_state?.reason_code, 'missing_scope');
  assert.equal(usage?.error_state?.auto_disabled, false);
  assert.equal(usage?.model_states?.['gpt-5.4']?.status, 'blocked');
});

await run('recordProviderKeyRuntimeEvent puts provider timeouts into cooldown windows', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const added = addProviderKey(dir, {
    provider: 'openai',
    email: 'timeout@test.local',
    api_key: 'sk-timeout-test-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(added.ok, true);

  const result = recordProviderKeyRuntimeEvent(dir, {
    account_key: added.account_key,
    model_id: 'gpt-4o',
    status_message: 'fetch_failed: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."',
  });
  assert.equal(result.ok, true);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, added.account_key);
  assert.equal(usage?.error_state?.status, 'blocked_network');
  assert.equal(usage?.error_state?.reason_code, 'provider_timeout');
  assert.equal(usage?.error_state?.retry_at_source, 'scheduler');
  assert.ok(Number(usage?.error_state?.next_retry_at_ms || 0) > Date.now());
  assert.equal(usage?.model_states?.['gpt-4o']?.status, 'cooldown');
});

await run('success events clear runtime error state for the reported model', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const added = addProviderKey(dir, {
    provider: 'openai',
    email: 'success@test.local',
    api_key: 'sk-success-test-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(added.ok, true);

  recordProviderKeyRuntimeEvent(dir, {
    account_key: added.account_key,
    model_id: 'gpt-4o',
    status_message: 'fetch_failed: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."',
  });

  invalidateProviderKeyCache();
  const result = recordProviderKeyRuntimeEvent(dir, {
    account_key: added.account_key,
    model_id: 'gpt-4o',
    outcome: 'success',
    tokens_used: 128,
  });
  assert.equal(result.ok, true);

  invalidateProviderKeyCache();
  const usage = getKeyUsage(dir, added.account_key);
  assert.equal(usage?.error_state?.status, 'healthy');
  assert.equal(usage?.model_states?.['gpt-4o']?.status, 'ready');
});
