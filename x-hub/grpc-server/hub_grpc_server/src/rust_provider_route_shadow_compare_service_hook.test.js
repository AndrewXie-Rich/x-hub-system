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
} from './provider_key_store.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function withEnv(tempEnv, fn) {
  const previous = new Map();
  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  };
  for (const [key, value] of Object.entries(tempEnv)) {
    previous.set(key, process.env[key]);
    if (value == null) delete process.env[key];
    else process.env[key] = String(value);
  }
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
  };
}

async function invokeUnary(method, call) {
  return await new Promise((resolve) => {
    method(call, (err, res) => resolve({ err, res }));
  });
}

await run('GetProviderKeyRouteDecision triggers opt-in Rust provider route shadow comparer after response', async () => {
  const runtimeBaseDir = makeTempDir('xhub-provider-route-shadow-runtime-');
  const dbPath = path.join(makeTempDir('xhub-provider-route-shadow-db-'), 'hub.sqlite3');
  const calls = [];
  invalidateProviderKeyCache();

  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: 'client-secret',
    HUB_GRPC_TLS_MODE: '',
    HUB_GRPC_CERT: '',
    HUB_GRPC_KEY: '',
    HUB_GRPC_CA: '',
  }, async () => {
    const db = new HubDB({ dbPath });
    try {
      const addResult = addProviderKey(runtimeBaseDir, {
        provider: 'openai',
        api_key: 'sk-provider-route-shadow-test',
        auth_type: 'api_key',
        models: ['gpt-4o'],
        priority: 3,
      });
      assert.equal(addResult.ok, true);

      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        providerRouteShadowComparer: {
          maybeCompare(input) {
            calls.push(input);
            return true;
          },
        },
      });

      const routeDecision = await invokeUnary(
        impl.HubProviderKeys.GetProviderKeyRouteDecision,
        makeTransportCall({ model_id: 'gpt-4o' }, 'client-secret')
      );
      assert.equal(routeDecision.err, null);
      assert.equal(
        String(routeDecision.res.decision?.selected_account_key || ''),
        addResult.account_key
      );
      assert.equal(calls.length, 1);
      assert.equal(calls[0].runtimeBaseDir, runtimeBaseDir);
      assert.equal(calls[0].modelId, 'gpt-4o');
      assert.equal(calls[0].provider, '');
      assert.equal(calls[0].nodeDecision.selected_account_key, addResult.account_key);
    } finally {
      db.close();
    }
  });

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});

await run('GetProviderKeyRouteDecision triggers opt-in Rust provider route authority prep after response', async () => {
  const runtimeBaseDir = makeTempDir('xhub-provider-route-authority-prep-runtime-');
  const dbPath = path.join(makeTempDir('xhub-provider-route-authority-prep-db-'), 'hub.sqlite3');
  const prepCalls = [];
  const shadowCalls = [];
  invalidateProviderKeyCache();

  await withEnv({
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: 'client-secret',
    HUB_GRPC_TLS_MODE: '',
    HUB_GRPC_CERT: '',
    HUB_GRPC_KEY: '',
    HUB_GRPC_CA: '',
  }, async () => {
    const db = new HubDB({ dbPath });
    try {
      const addResult = addProviderKey(runtimeBaseDir, {
        provider: 'openai',
        api_key: 'sk-provider-route-authority-prep-test',
        auth_type: 'api_key',
        models: ['gpt-4o'],
        priority: 3,
      });
      assert.equal(addResult.ok, true);

      const impl = makeServices({
        db,
        bus: new HubEventBus(),
        providerRouteShadowComparer: {
          maybeCompare(input) {
            shadowCalls.push(input);
            return true;
          },
        },
        providerRouteAuthorityBridge: {
          config: { prepEnabled: true },
          prepRoute(input) {
            prepCalls.push(input);
            return true;
          },
        },
      });

      const routeDecision = await invokeUnary(
        impl.HubProviderKeys.GetProviderKeyRouteDecision,
        makeTransportCall({ model_id: 'gpt-4o', provider: 'openai' }, 'client-secret')
      );
      assert.equal(routeDecision.err, null);
      assert.equal(
        String(routeDecision.res.decision?.selected_account_key || ''),
        addResult.account_key
      );

      assert.equal(shadowCalls.length, 1);
      assert.equal(prepCalls.length, 1);
      assert.equal(prepCalls[0].runtimeBaseDir, runtimeBaseDir);
      assert.equal(prepCalls[0].modelId, 'gpt-4o');
      assert.equal(prepCalls[0].provider, 'openai');
      assert.equal(prepCalls[0].nodeAccountKey, addResult.account_key);
    } finally {
      db.close();
    }
  });

  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
  try { fs.rmSync(path.dirname(dbPath), { recursive: true, force: true }); } catch {}
});
