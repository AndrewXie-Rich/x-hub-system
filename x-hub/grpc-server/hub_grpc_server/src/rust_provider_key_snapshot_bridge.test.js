import assert from 'node:assert/strict';

import {
  createRustProviderKeySnapshotBridge,
  resolveRustProviderKeySnapshotConfig,
} from './rust_provider_key_snapshot_bridge.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

await run('Rust provider key snapshot bridge is disabled by default', () => {
  const config = resolveRustProviderKeySnapshotConfig({});
  assert.equal(config.enabled, false);
  assert.equal(config.fallbackOnError, true);
  assert.equal(config.httpBaseUrl, 'http://127.0.0.1:50151');
});

await run('Rust provider key snapshot bridge fetches pool snapshot', async () => {
  const calls = [];
  const bridge = createRustProviderKeySnapshotBridge({
    env: {
      XHUB_RUST_PROVIDER_KEY_SNAPSHOT: '1',
      XHUB_RUST_HUB_HTTP_BASE_URL: 'http://127.0.0.1:55151',
      XHUB_RUST_PROVIDER_KEY_SNAPSHOT_TIMEOUT_MS: '1234',
      XHUB_RUST_HTTP_ACCESS_KEY: 'secret',
    },
    httpGetJsonImpl: async (url, options) => {
      calls.push({ url: String(url), options });
      return {
        ok: true,
        command: 'pools',
        snapshot: {
          pools: [
            {
              pool_id: 'shared',
              capability_pool_id: 'shared#openai:gpt-5.4',
              provider: 'openai',
              ready_accounts: 2,
            },
          ],
          updated_at_ms: 123,
          routing_strategy: 'fill-first',
        },
      };
    },
    logger: { warn() {} },
  });

  const out = await bridge.listProviderKeyPools({
    runtimeBaseDir: '/tmp/runtime',
    provider: 'openai',
    modelId: 'gpt-5.4',
    includeMembers: true,
    nowMs: 999,
  });

  assert.equal(calls.length, 1);
  assert.equal(
    calls[0].url,
    'http://127.0.0.1:55151/provider/pools?runtime_base_dir=%2Ftmp%2Fruntime&provider=openai&model_id=gpt-5.4&include_members=1&now_ms=999'
  );
  assert.equal(calls[0].options.timeoutMs, 1234);
  assert.equal(calls[0].options.accessKey, 'secret');
  assert.equal(out.ok, true);
  assert.equal(out.pools.length, 1);
  assert.equal(out.pools[0].capability_pool_id, 'shared#openai:gpt-5.4');
  assert.equal(out.updated_at_ms, 123);
});

await run('Rust provider key snapshot bridge fetches runtime snapshot with quota windows', async () => {
  const bridge = createRustProviderKeySnapshotBridge({
    env: {
      XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP: '1',
      XHUB_RUST_PROVIDER_KEY_SNAPSHOT_HTTP_BASE_URL: 'http://127.0.0.1:55152',
    },
    httpGetJsonImpl: async (url) => {
      assert.equal(
        String(url),
        'http://127.0.0.1:55152/provider/runtime-snapshot?runtime_base_dir=%2Ftmp%2Fruntime&provider=openai'
      );
      return {
        ok: true,
        command: 'runtime-snapshot',
        snapshot: {
          accounts: [
            {
              account_key: 'acct-1',
              provider: 'openai',
              quota: {
                usage_windows: [
                  {
                    key: 'rate_limit:5h',
                    window_key: '5h',
                    used_percent: 25,
                  },
                ],
              },
            },
          ],
          import_source_statuses: [],
          updated_at_ms: 456,
          global_routing_strategy: 'priority',
          providers: [{ provider: 'openai', total_accounts: 1, enabled_accounts: 1 }],
        },
      };
    },
    logger: { warn() {} },
  });

  const out = await bridge.getProviderKeyRuntimeSnapshot({
    runtimeBaseDir: '/tmp/runtime',
    provider: 'openai',
  });

  assert.equal(out.ok, true);
  assert.equal(out.accounts[0].quota.usage_windows[0].window_key, '5h');
  assert.equal(out.global_routing_strategy, 'priority');
  assert.equal(out.providers.length, 1);
});
