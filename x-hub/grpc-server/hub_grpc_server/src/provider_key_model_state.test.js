import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  addProviderKey,
  getKeyUsage,
  invalidateProviderKeyCache,
  listProviderKeyPools,
  reportKeyError,
  reportKeyUsage,
  updateProviderKey,
} from './provider_key_store.js';
import { resolveProviderKeyForModel } from './provider_key_router.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-model-state-'));
}

await run('model_states let one provider key stay ready for one model while another model is blocked', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const first = addProviderKey(dir, {
    provider: 'openai',
    email: 'gpt4o@test.local',
    api_key: 'sk-model-state-1-1234567890',
    auth_type: 'api_key',
  });
  const second = addProviderKey(dir, {
    provider: 'openai',
    email: 'o1@test.local',
    api_key: 'sk-model-state-2-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(first.ok, true);
  assert.equal(second.ok, true);

  const firstUpdated = updateProviderKey(dir, first.account_key, {
    error_state: {
      status: 'blocked_provider',
      reason_code: 'model_not_supported',
      status_message: 'aggregate provider state should not poison all models',
    },
    model_states: {
      'gpt-4o': {
        status: 'ready',
        updated_at_ms: Date.now(),
      },
      o1: {
        status: 'blocked',
        reason_code: 'model_not_supported',
        status_message: 'o1 unavailable on first key',
        updated_at_ms: Date.now(),
      },
    },
  });
  const secondUpdated = updateProviderKey(dir, second.account_key, {
    error_state: {
      status: 'blocked_provider',
      reason_code: 'model_not_supported',
      status_message: 'aggregate provider state should not poison all models',
    },
    model_states: {
      'gpt-4o': {
        status: 'blocked',
        reason_code: 'model_not_supported',
        status_message: 'gpt-4o unavailable on second key',
        updated_at_ms: Date.now(),
      },
      o1: {
        status: 'ready',
        updated_at_ms: Date.now(),
      },
    },
  });
  assert.equal(firstUpdated.ok, true);
  assert.equal(secondUpdated.ok, true);

  invalidateProviderKeyCache();
  const gpt4oRoute = resolveProviderKeyForModel(dir, 'gpt-4o');
  const o1Route = resolveProviderKeyForModel(dir, 'o1');
  assert.equal(gpt4oRoute.account?.account_key, first.account_key);
  assert.equal(o1Route.account?.account_key, second.account_key);

  invalidateProviderKeyCache();
  const gpt4oPools = listProviderKeyPools(dir, {
    provider: 'openai',
    model_id: 'gpt-4o',
    include_members: true,
  });
  assert.equal(gpt4oPools.length, 1);
  assert.equal(gpt4oPools[0].ready_accounts, 1);
  assert.equal(gpt4oPools[0].blocked_accounts, 1);
  assert.equal(
    gpt4oPools[0].members.find((member) => member.account_key === first.account_key)?.state,
    'ready'
  );
  assert.equal(
    gpt4oPools[0].members.find((member) => member.account_key === second.account_key)?.reason_code,
    'model_not_supported'
  );

  invalidateProviderKeyCache();
  const firstUsage = getKeyUsage(dir, first.account_key);
  assert.equal(firstUsage?.model_states?.o1?.status, 'blocked');
  assert.equal(firstUsage?.model_states?.['gpt-4o']?.status, 'ready');
});

await run('reportKeyError and reportKeyUsage update model_states when model_id is provided', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const added = addProviderKey(dir, {
    provider: 'openai',
    email: 'usage@test.local',
    api_key: 'sk-model-state-usage-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(added.ok, true);

  invalidateProviderKeyCache();
  const errorResult = reportKeyError(dir, added.account_key, {
    error_code: 'rate_limited',
    model_id: 'gpt-4o',
  });
  assert.equal(errorResult.ok, true);

  invalidateProviderKeyCache();
  const afterError = getKeyUsage(dir, added.account_key);
  assert.equal(afterError?.model_states?.['gpt-4o']?.status, 'cooldown');
  assert.ok(Number(afterError?.model_states?.['gpt-4o']?.next_retry_at_ms || 0) > Date.now());

  invalidateProviderKeyCache();
  const usageResult = reportKeyUsage(dir, added.account_key, {
    tokens_used: 42,
    model_id: 'gpt-4o',
  });
  assert.equal(usageResult.ok, true);

  invalidateProviderKeyCache();
  const afterUsage = getKeyUsage(dir, added.account_key);
  assert.equal(afterUsage?.model_states?.['gpt-4o']?.status, 'ready');
  assert.equal(afterUsage?.model_states?.['gpt-4o']?.reason_code, '');
});
