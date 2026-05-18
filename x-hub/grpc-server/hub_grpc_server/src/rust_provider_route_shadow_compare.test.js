import assert from 'node:assert/strict';

import {
  buildProviderRouteShadowCompareArgs,
  buildProviderRouteShadowCompareHttpPayload,
  compareProviderRouteDecisions,
  createProviderRouteShadowComparer,
  normalizeProviderRouteDecision,
  resolveProviderRouteShadowCompareConfig,
} from './rust_provider_route_shadow_compare.js';

function run(name, fn) {
  try {
    const result = fn();
    if (result && typeof result.then === 'function') {
      return result.then(() => {
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sampleDecision(overrides = {}) {
  return {
    requested_provider: 'openai',
    requested_model_id: 'gpt-4o',
    resolved_provider: 'openai',
    strategy: 'fill-first',
    selection_scope: 'openai::default',
    selected_account_key: 'acct-a',
    fallback_reason_code: '',
    available_count: 1,
    total_count: 1,
    candidates: [
      {
        account_key: 'acct-a',
        provider: 'openai',
        provider_group: 'openai',
        state: 'ready',
        reason_code: 'selected_by_scheduler',
        selected: true,
        score: 1000,
      },
    ],
    updated_at_ms: 1234,
    ...overrides,
  };
}

function makeFakeExecFile(calls, decisionFactory = () => sampleDecision()) {
  return (file, args, options, callback) => {
    calls.push({ file, args, options });
    queueMicrotask(() => {
      callback(null, JSON.stringify({
        schema_version: 'xhub.provider_bridge.v1',
        ok: true,
        command: 'compare',
        report_id: 'provider-route-report-1',
        match: true,
        match_result: 'match',
        node: sampleDecision(),
        rust: decisionFactory(),
        mismatches: [],
      }), '');
    });
  };
}

await run('Rust provider route shadow compare is disabled by default', () => {
  const calls = [];
  const comparer = createProviderRouteShadowComparer({
    env: {},
    execFileImpl: makeFakeExecFile(calls),
    existsSync: () => true,
  });
  assert.equal(comparer.config.enabled, false);
  assert.equal(comparer.maybeCompare({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    nodeDecision: sampleDecision(),
  }), false);
  assert.equal(calls.length, 0);
});

await run('Rust provider route shadow compare invokes xhubd provider route asynchronously', async () => {
  const calls = [];
  let clock = 10_000;
  const comparer = createProviderRouteShadowComparer({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE: '1',
      XHUB_RUST_PROVIDER_ROUTE_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_THROTTLE_MS: '1000',
    },
    execFileImpl: makeFakeExecFile(calls),
    existsSync: () => true,
    now: () => clock,
  });

  const nodeDecision = sampleDecision();
  assert.equal(comparer.maybeCompare({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision,
  }), true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].file, '/tmp/rust-hub/tools/run_rust_hub.command');
  assert.deepEqual(calls[0].args.slice(0, 4), [
    'provider',
    'compare',
    '--node-decision-json',
    JSON.stringify(nodeDecision),
  ]);
  assert.deepEqual(calls[0].args.slice(4), [
    '--model-id',
    'gpt-4o',
    '--provider',
    'openai',
    '--runtime-base-dir',
    '/tmp/runtime',
    '--now-ms',
    '1234',
  ]);

  assert.equal(comparer.maybeCompare({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision,
  }), false);
  await sleep(0);
  clock += 2_000;
  assert.equal(comparer.maybeCompare({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision,
  }), true);
  assert.equal(calls.length, 2);
});

await run('Rust provider route shadow compare reports mismatches without throwing', async () => {
  const calls = [];
  const warnings = [];
  const comparer = createProviderRouteShadowComparer({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE: '1',
      XHUB_RUST_PROVIDER_ROUTE_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: (file, args, options, callback) => {
      calls.push({ file, args, options });
      queueMicrotask(() => {
        callback(null, JSON.stringify({
          schema_version: 'xhub.provider_bridge.v1',
          ok: true,
          command: 'compare',
          report_id: 'provider-route-report-2',
          match: false,
          match_result: 'mismatch',
          mismatches: ['selected_account_key "acct-a" != "acct-b"'],
        }), '');
      });
    },
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  assert.equal(comparer.maybeCompare({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision: sampleDecision(),
  }), true);
  await sleep(0);
  assert.equal(calls.length, 1);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /rust provider route shadow mismatch/);
});

await run('Rust provider route shadow compare prefers HTTP when enabled', async () => {
  const cliCalls = [];
  const httpCalls = [];
  const logs = [];
  const nodeDecision = sampleDecision();
  const comparer = createProviderRouteShadowComparer({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE: '1',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP: '1',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_BASE_URL: 'http://127.0.0.1:55151',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_TIMEOUT_MS: '1234',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_VERBOSE: '1',
    },
    execFileImpl: makeFakeExecFile(cliCalls),
    httpPostJsonImpl: (url, payload, timeoutMs) => {
      httpCalls.push({ url: String(url), payload, timeoutMs });
      return {
        schema_version: 'xhub.provider_bridge.v1',
        ok: true,
        command: 'compare',
        report_id: 'provider-route-http-report-1',
        match: true,
        match_result: 'match',
        mismatches: [],
      };
    },
    existsSync: () => false,
    now: () => 20_000,
    logger: { log: (line) => logs.push(line), warn: () => {} },
  });

  assert.equal(comparer.maybeCompare({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision,
  }), true);
  assert.equal(cliCalls.length, 0);
  assert.equal(httpCalls.length, 1);
  assert.equal(httpCalls[0].url, 'http://127.0.0.1:55151/provider/compare');
  assert.equal(httpCalls[0].timeoutMs, 1234);
  assert.deepEqual(httpCalls[0].payload, {
    runtime_base_dir: '/tmp/runtime',
    model_id: 'gpt-4o',
    provider: 'openai',
    node_decision: nodeDecision,
    now_ms: 1234,
  });
  await sleep(0);
  assert.equal(logs.some((line) => /HTTP compare ok/.test(line)), true);
  assert.equal(logs.some((line) => /shadow match/.test(line)), true);
});

await run('Rust provider route shadow compare falls back from HTTP to CLI by default', async () => {
  const cliCalls = [];
  const httpCalls = [];
  const warnings = [];
  const comparer = createProviderRouteShadowComparer({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE: '1',
      XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE_HTTP: '1',
      XHUB_RUST_PROVIDER_ROUTE_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExecFile(cliCalls),
    httpPostJsonImpl: (url, payload, timeoutMs) => {
      httpCalls.push({ url: String(url), payload, timeoutMs });
      throw new Error('daemon_down');
    },
    existsSync: () => true,
    now: () => 30_000,
    logger: { warn: (line) => warnings.push(line) },
  });

  assert.equal(comparer.config.httpFallbackToCli, true);
  assert.equal(comparer.maybeCompare({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision: sampleDecision(),
  }), true);
  await sleep(0);
  assert.equal(httpCalls.length, 1);
  assert.equal(cliCalls.length, 1);
  assert.equal(warnings.some((line) => /HTTP compare failed; falling back to CLI/.test(line)), true);
});

await run('Rust provider route shadow compare normalization is stable', () => {
  const config = resolveProviderRouteShadowCompareConfig({
    XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE: 'on',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
    XHUB_RUST_HUB_HTTP_PORT: '55151',
  });
  assert.equal(config.enabled, true);
  assert.equal(config.runnerPath, '/tmp/rust-hub/tools/run_rust_hub.command');
  assert.equal(config.httpEnabled, false);
  assert.equal(config.httpBaseUrl, 'http://127.0.0.1:55151');
  assert.equal(config.httpTimeoutMs, 750);
  assert.equal(config.httpFallbackToCli, true);
  assert.deepEqual(buildProviderRouteShadowCompareArgs({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision: sampleDecision(),
  }).slice(0, 4), [
    'provider',
    'compare',
    '--node-decision-json',
    JSON.stringify(sampleDecision()),
  ]);
  assert.deepEqual(buildProviderRouteShadowCompareArgs({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision: sampleDecision(),
  }).slice(4), [
    '--model-id',
    'gpt-4o',
    '--provider',
    'openai',
    '--runtime-base-dir',
    '/tmp/runtime',
    '--now-ms',
    '1234',
  ]);
  assert.deepEqual(buildProviderRouteShadowCompareHttpPayload({
    runtimeBaseDir: '/tmp/runtime',
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeDecision: sampleDecision(),
  }), {
    runtime_base_dir: '/tmp/runtime',
    model_id: 'gpt-4o',
    provider: 'openai',
    node_decision: sampleDecision(),
    now_ms: 1234,
  });
  assert.deepEqual(normalizeProviderRouteDecision(sampleDecision()).candidates, [
    {
      account_key: 'acct-a',
      provider: 'openai',
      provider_group: 'openai',
      state: 'ready',
      reason_code: 'selected_by_scheduler',
      selected: true,
      model_state_key: '',
    },
  ]);
  assert.equal(compareProviderRouteDecisions(sampleDecision(), sampleDecision()).matched, true);
  assert.equal(
    compareProviderRouteDecisions(sampleDecision(), sampleDecision({ selected_account_key: 'acct-b' })).matched,
    false
  );
});
