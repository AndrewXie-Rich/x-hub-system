import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  importAuthDir,
  invalidateProviderKeyCache,
  loadProviderKeyStore,
} from './provider_key_store.js';
import { startProviderKeySourceWatcher } from './provider_key_source_watcher.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-provider-key-watch-'));
}

async function waitFor(predicate, timeoutMs = 4000, intervalMs = 80) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  throw new Error('waitFor timeout');
}

await run('provider key source watcher imports added auth files and prunes deleted ones', async () => {
  const runtimeBaseDir = makeTempDir();
  const authDir = path.join(runtimeBaseDir, 'auth');
  fs.mkdirSync(authDir, { recursive: true });
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(authDir, 'auth17.json'), JSON.stringify({
    provider: 'openai',
    access_token: 'sk-watch-a',
    account_id: 'acct-watch-a',
  }, null, 2));

  const first = importAuthDir(runtimeBaseDir, authDir);
  assert.equal(first.ok, true);
  assert.equal(first.imported, 1);

  const stop = startProviderKeySourceWatcher({
    runtimeBaseDir,
    pollIntervalMs: 100,
    logger: { warn() {} },
  });

  try {
    fs.writeFileSync(path.join(authDir, 'auth19.json'), JSON.stringify({
      provider: 'openai',
      access_token: 'sk-watch-b',
      account_id: 'acct-watch-b',
    }, null, 2));

    await waitFor(() => {
      invalidateProviderKeyCache();
      const store = loadProviderKeyStore(runtimeBaseDir, 0);
      return (store.providers.openai?.accounts || []).length === 2;
    });

    fs.unlinkSync(path.join(authDir, 'auth17.json'));

    await waitFor(() => {
      invalidateProviderKeyCache();
      const store = loadProviderKeyStore(runtimeBaseDir, 0);
      const accounts = store.providers.openai?.accounts || [];
      const sourceKey = `auth_dir:${authDir}`;
      const status = store.import_source_statuses?.[sourceKey];
      return accounts.length === 1
        && accounts[0].account_id === 'acct-watch-b'
        && status?.state === 'ready'
        && status?.owned_account_count === 1;
    });

    fs.rmSync(authDir, { recursive: true, force: true });

    await waitFor(() => {
      invalidateProviderKeyCache();
      const store = loadProviderKeyStore(runtimeBaseDir, 0);
      const accounts = store.providers.openai?.accounts || [];
      const sourceKey = `auth_dir:${authDir}`;
      const status = store.import_source_statuses?.[sourceKey];
      return accounts.length === 0
        && status?.state === 'missing'
        && status?.owned_account_count === 0
        && Array.isArray(status?.last_errors)
        && status.last_errors.includes('source_path_missing');
    });
  } finally {
    stop();
  }
});

process.stdout.write('\nAll provider_key_source_watcher tests passed.\n');
