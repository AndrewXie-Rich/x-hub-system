import assert from 'node:assert/strict';

import {
  buildProviderRouteAuthorityArgs,
  createProviderRouteAuthorityBridge,
  normalizeRustProviderRouteDecision,
  resolveProviderRouteAuthorityConfig,
} from './rust_provider_route_authority_bridge.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeFakeExec(calls, handler = defaultHandler()) {
  return (file, args, options, callback) => {
    calls.push({ file, args, options });
    queueMicrotask(() => {
      try {
        callback(null, JSON.stringify(handler(args, calls.length)), '');
      } catch (error) {
        callback(error, '', '');
      }
    });
  };
}

function makeControlledExec(calls, handler = defaultHandler()) {
  const pending = [];
  const exec = (file, args, options, callback) => {
    calls.push({ file, args, options });
    pending.push({ args, callback });
  };
  exec.resolveNext = () => {
    const item = pending.shift();
    assert.ok(item, 'expected pending exec callback');
    item.callback(null, JSON.stringify(handler(item.args, calls.length)), '');
  };
  return exec;
}

function defaultHandler() {
  return (args) => {
    const command = args[1];
    if (command === 'readiness') {
      return {
        ok: true,
        command,
        ready: true,
        decision: 'ready',
      };
    }
    if (command === 'route') {
      return routeOutput(args, 'acct-openai');
    }
    throw new Error(`unexpected command ${command}`);
  };
}

function routeOutput(args, selectedAccountKey) {
  const modelId = args[args.indexOf('--model-id') + 1];
  const providerIndex = args.indexOf('--provider');
  const provider = providerIndex >= 0 ? args[providerIndex + 1] : 'openai';
  return {
    ok: true,
    command: 'route',
    decision: {
      requested_provider: provider,
      requested_model_id: modelId,
      resolved_provider: provider,
      strategy: 'fill-first',
      selection_scope: `${provider}::default`,
      selected_account_key: selectedAccountKey,
      fallback_reason_code: selectedAccountKey ? '' : 'no_keys_for_provider',
      available_count: selectedAccountKey ? 1 : 0,
      total_count: selectedAccountKey ? 1 : 0,
      candidates: [],
      updated_at_ms: 1234,
    },
  };
}

function routeOutputFromUrl(url, selectedAccountKey) {
  const parsed = new URL(String(url));
  const modelId = parsed.searchParams.get('model_id') || '';
  const provider = parsed.searchParams.get('provider') || 'openai';
  return {
    ok: true,
    command: 'route',
    decision: {
      requested_provider: provider,
      requested_model_id: modelId,
      resolved_provider: provider,
      strategy: 'fill-first',
      selection_scope: `${provider}::http`,
      selected_account_key: selectedAccountKey,
      fallback_reason_code: '',
      available_count: 1,
      total_count: 1,
      candidates: [],
      updated_at_ms: 4321,
    },
  };
}

function readinessOutputFromUrl(url, ready = true) {
  const parsed = new URL(String(url));
  return {
    ok: true,
    command: 'readiness',
    ready,
    decision: ready ? 'ready' : 'not_ready',
    thresholds: {
      min_compare_reports: Number(parsed.searchParams.get('min_compare_reports') || 10),
      max_mismatches: Number(parsed.searchParams.get('max_mismatches') || 0),
    },
    compare: {
      total: ready ? Number(parsed.searchParams.get('min_compare_reports') || 10) : 0,
      matched: ready ? Number(parsed.searchParams.get('min_compare_reports') || 10) : 0,
      mismatched: 0,
    },
  };
}

await run('Rust provider route authority prep is disabled by default', async () => {
  const calls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {},
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });
  const out = await bridge.route({ modelId: 'gpt-4o', provider: 'openai' });
  assert.equal(bridge.config.enabled, false);
  assert.equal(out.used, false);
  assert.equal(out.fallback, true);
  assert.equal(out.error_code, 'rust_provider_route_authority_disabled');
  assert.equal(calls.length, 0);
});

await run('Rust provider route authority observe is separately opt-in and non-blocking', async () => {
  const calls = [];
  const logs = [];
  const warnings = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_VERBOSE: '1',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
    logger: {
      log: (line) => logs.push(line),
      warn: (line) => warnings.push(line),
    },
  });

  const started = bridge.observeRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'acct-openai',
    runtimeBaseDir: '/tmp/runtime',
  });
  assert.equal(started, true);
  assert.equal(calls.length, 0);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(calls.map((call) => call.args[1]), ['route']);
  assert.equal(warnings.length, 0);
  assert.equal(logs.some((line) => /observe match/.test(line)), true);
});

await run('Rust provider route authority observe reports account mismatch without throwing', async () => {
  const calls = [];
  const warnings = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  assert.equal(bridge.observeRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
  }), true);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(calls.length, 1);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /observe mismatch/);
});

await run('Rust provider route authority observe throttles per key and caps in-flight work', async () => {
  const calls = [];
  const logs = [];
  let now = 10_000;
  const exec = makeControlledExec(calls);
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_THROTTLE_MS: '1000',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_MAX_IN_FLIGHT: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_VERBOSE: '1',
    },
    execFileImpl: exec,
    existsSync: () => true,
    nowMsImpl: () => now,
    logger: { log: (line) => logs.push(line) },
  });

  assert.equal(bridge.observeRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'acct-openai',
    runtimeBaseDir: '/tmp/runtime',
  }), true);
  assert.equal(bridge.observeRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'acct-openai',
    runtimeBaseDir: '/tmp/runtime',
  }), false);
  assert.equal(bridge.observeRoute({
    modelId: 'gpt-4o-mini',
    provider: 'openai',
    nodeAccountKey: 'acct-openai',
    runtimeBaseDir: '/tmp/runtime',
  }), false);

  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(calls.length, 1);
  exec.resolveNext();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(logs.some((line) => /observe match/.test(line)), true);

  now += 500;
  assert.equal(bridge.observeRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'acct-openai',
    runtimeBaseDir: '/tmp/runtime',
  }), false);

  now += 600;
  assert.equal(bridge.observeRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'acct-openai',
    runtimeBaseDir: '/tmp/runtime',
  }), true);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(calls.length, 2);
  exec.resolveNext();
  await new Promise((resolve) => setTimeout(resolve, 0));
});

await run('Rust provider route authority prep throttles per key, caps in-flight work, and keeps Node match gate', async () => {
  const calls = [];
  const warnings = [];
  let now = 20_000;
  const exec = makeControlledExec(calls);
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS: '1000',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: exec,
    existsSync: () => true,
    nowMsImpl: () => now,
    logger: { warn: (line) => warnings.push(line) },
  });

  assert.equal(bridge.prepRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  }), true);
  assert.equal(bridge.prepRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  }), false);
  assert.equal(bridge.prepRoute({
    modelId: 'gpt-4o-mini',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  }), false);

  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(calls.length, 1);
  exec.resolveNext();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(warnings.some((line) => /account mismatch/.test(line)), true);

  now += 500;
  assert.equal(bridge.prepRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  }), false);

  now += 600;
  assert.equal(bridge.prepRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  }), true);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(calls.length, 2);
  exec.resolveNext();
});

await run('Rust provider route authority prep routes after readiness passes', async () => {
  const calls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS: '3',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REPORT_LIMIT: '10',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });

  const out = await bridge.route({
    modelId: 'gpt-4o',
    provider: 'openai',
    runtimeBaseDir: '/tmp/runtime',
    nowMs: 1000,
  });

  assert.equal(out.used, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selected, true);
  assert.equal(out.selectedAccountKey, 'acct-openai');
  assert.deepEqual(calls.map((call) => call.args.slice(0, 2).join(' ')), [
    'provider readiness',
    'provider route',
  ]);
  assert.deepEqual(calls[0].args, [
    'provider',
    'readiness',
    '--min-compare-reports',
    '3',
    '--max-mismatches',
    '0',
    '--limit',
    '10',
  ]);
  assert.deepEqual(calls[1].args, [
    'provider',
    'route',
    '--model-id',
    'gpt-4o',
    '--provider',
    'openai',
    '--runtime-base-dir',
    '/tmp/runtime',
    '--now-ms',
    '1000',
  ]);
});

await run('Rust provider route authority prep falls back when Node selected account mismatches Rust', async () => {
  const calls = [];
  const warnings = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  const out = await bridge.route({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
  });

  assert.equal(out.used, true);
  assert.equal(out.fallback, true);
  assert.equal(out.selected, false);
  assert.equal(out.mismatch, true);
  assert.equal(out.error_code, 'rust_provider_route_authority_account_mismatch');
  assert.equal(out.nodeAccountKey, 'node-acct');
  assert.equal(out.selectedAccountKey, 'acct-openai');
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /account mismatch/);
  assert.deepEqual(calls.map((call) => call.args[1]), ['route']);
});

await run('Rust provider route authority prep can explicitly skip Node match gate for observe-only callers', async () => {
  const calls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });

  const out = await bridge.route({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    requireNodeMatch: false,
  });

  assert.equal(out.used, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selected, true);
  assert.equal(out.selectedAccountKey, 'acct-openai');
});

await run('Rust provider route authority candidate is separately opt-in and skips Node match gate', async () => {
  const disabledCalls = [];
  const disabledBridge = createProviderRouteAuthorityBridge({
    env: {},
    execFileImpl: makeFakeExec(disabledCalls),
    existsSync: () => true,
  });
  const disabled = await disabledBridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
  });
  assert.equal(disabledBridge.config.candidateEnabled, false);
  assert.equal(disabled.used, false);
  assert.equal(disabled.error_code, 'rust_provider_route_authority_candidate_disabled');
  assert.equal(disabledCalls.length, 0);

  const calls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });

  const out = await bridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
  });
  assert.equal(bridge.config.enabled, true);
  assert.equal(bridge.config.candidateEnabled, true);
  assert.equal(out.used, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selected, true);
  assert.equal(out.selectedAccountKey, 'acct-openai');
  assert.deepEqual(calls.map((call) => call.args[1]), ['route']);
});

await run('Rust provider route authority can prefer default-off HTTP route endpoint before CLI', async () => {
  const calls = [];
  const httpCalls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL: 'http://127.0.0.1:50151',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS: '250',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    httpGetJsonImpl: async (url, timeoutMs) => {
      httpCalls.push({ url: String(url), timeoutMs });
      return routeOutputFromUrl(url, 'acct-http');
    },
    existsSync: () => true,
  });

  const out = await bridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime dir',
    nowMs: 123,
  });
  assert.equal(out.used, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selectedAccountKey, 'acct-http');
  assert.equal(calls.length, 0);
  assert.equal(httpCalls.length, 1);
  assert.equal(httpCalls[0].timeoutMs, 250);
  const url = new URL(httpCalls[0].url);
  assert.equal(url.pathname, '/provider/route');
  assert.equal(url.searchParams.get('model_id'), 'gpt-4o');
  assert.equal(url.searchParams.get('provider'), 'openai');
  assert.equal(url.searchParams.get('runtime_base_dir'), '/tmp/runtime dir');
  assert.equal(url.searchParams.get('now_ms'), '123');
});

await run('Rust provider route authority can use HTTP readiness and route without CLI runner', async () => {
  const calls = [];
  const httpCalls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS: '3',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_MAX_MISMATCHES: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REPORT_LIMIT: '9',
    },
    execFileImpl: makeFakeExec(calls),
    httpGetJsonImpl: async (url, timeoutMs) => {
      httpCalls.push({ url: String(url), timeoutMs });
      const parsed = new URL(String(url));
      if (parsed.pathname === '/provider/readiness') return readinessOutputFromUrl(url, true);
      if (parsed.pathname === '/provider/route') return routeOutputFromUrl(url, 'acct-http-ready');
      throw new Error(`unexpected ${parsed.pathname}`);
    },
    existsSync: () => false,
  });

  const out = await bridge.route({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'acct-http-ready',
    runtimeBaseDir: '/tmp/runtime',
  });
  assert.equal(out.used, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selectedAccountKey, 'acct-http-ready');
  assert.equal(calls.length, 0);
  assert.deepEqual(httpCalls.map((call) => new URL(call.url).pathname), [
    '/provider/readiness',
    '/provider/route',
  ]);
  const readinessUrl = new URL(httpCalls[0].url);
  assert.equal(readinessUrl.searchParams.get('min_compare_reports'), '3');
  assert.equal(readinessUrl.searchParams.get('max_mismatches'), '0');
  assert.equal(readinessUrl.searchParams.get('limit'), '9');
});

await run('Rust provider route authority HTTP readiness falls back to CLI by default', async () => {
  const calls = [];
  const warnings = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    httpGetJsonImpl: async (url) => {
      const parsed = new URL(String(url));
      if (parsed.pathname === '/provider/readiness') throw new Error('readiness daemon unavailable');
      return routeOutputFromUrl(url, 'acct-http');
    },
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  const out = await bridge.route({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'acct-http',
  });
  assert.equal(out.used, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selectedAccountKey, 'acct-http');
  assert.deepEqual(calls.map((call) => call.args[1]), ['readiness']);
  assert.equal(warnings.some((line) => /HTTP readiness failed; falling back to CLI/.test(line)), true);
});

await run('Rust provider route authority HTTP route falls back to CLI by default', async () => {
  const calls = [];
  const warnings = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL: 'http://127.0.0.1:59999',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    httpGetJsonImpl: async () => {
      throw new Error('daemon unavailable');
    },
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  const out = await bridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
  });
  assert.equal(out.used, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selectedAccountKey, 'acct-openai');
  assert.deepEqual(calls.map((call) => call.args[1]), ['route']);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /HTTP route failed; falling back to CLI/);
});

await run('Rust provider route authority HTTP route can work without CLI runner when readiness is disabled', async () => {
  const calls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '0',
    },
    execFileImpl: makeFakeExec(calls),
    httpGetJsonImpl: async (url) => routeOutputFromUrl(url, 'acct-http-only'),
    existsSync: () => false,
  });

  const out = await bridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
  });
  assert.equal(out.used, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selectedAccountKey, 'acct-http-only');
  assert.equal(calls.length, 0);
});

await run('Rust provider route authority candidate coalesces concurrent calls and reuses short TTL cache', async () => {
  const calls = [];
  let now = 30_000;
  const exec = makeControlledExec(calls);
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE: '1',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS: '1000',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES: '2',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: exec,
    existsSync: () => true,
    nowMsImpl: () => now,
  });

  const first = bridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  });
  const second = bridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(calls.length, 1);
  exec.resolveNext();
  const [firstOut, secondOut] = await Promise.all([first, second]);
  assert.equal(firstOut.selectedAccountKey, 'acct-openai');
  assert.equal(secondOut.selectedAccountKey, 'acct-openai');

  const cached = await bridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  });
  assert.equal(cached.selectedAccountKey, 'acct-openai');
  assert.equal(calls.length, 1);

  now += 1100;
  const afterTtl = bridge.candidateRoute({
    modelId: 'gpt-4o',
    provider: 'openai',
    nodeAccountKey: 'node-acct',
    runtimeBaseDir: '/tmp/runtime',
  });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(calls.length, 2);
  exec.resolveNext();
  assert.equal((await afterTtl).selectedAccountKey, 'acct-openai');
});

await run('Rust provider route authority prep blocks route when readiness is not ready', async () => {
  const calls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: 'true',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls, (args) => {
      if (args[1] === 'readiness') {
        return {
          ok: true,
          command: 'readiness',
          ready: false,
          decision: 'not_ready',
        };
      }
      throw new Error('route should not run');
    }),
    existsSync: () => true,
  });

  const out = await bridge.route({ modelId: 'gpt-4o', provider: 'openai' });
  assert.equal(out.used, false);
  assert.equal(out.fallback, true);
  assert.equal(out.error_code, 'rust_provider_route_authority_not_ready');
  assert.deepEqual(calls.map((call) => call.args[1]), ['readiness']);
});

await run('Rust provider route authority prep caches readiness', async () => {
  const calls = [];
  let now = 10_000;
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_READINESS_CACHE_MS: '1000',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
    nowMsImpl: () => now,
  });

  await bridge.route({ modelId: 'gpt-4o', provider: 'openai' });
  await bridge.route({ modelId: 'gpt-4o', provider: 'openai' });
  assert.deepEqual(calls.map((call) => call.args[1]), ['readiness', 'route', 'route']);
  now += 2000;
  await bridge.route({ modelId: 'gpt-4o', provider: 'openai' });
  assert.deepEqual(calls.map((call) => call.args[1]), ['readiness', 'route', 'route', 'readiness', 'route']);
});

await run('Rust provider route authority prep falls back when Rust has no selected account', async () => {
  const calls = [];
  const bridge = createProviderRouteAuthorityBridge({
    env: {
      XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls, (args) => {
      if (args[1] === 'readiness') return { ok: true, command: 'readiness', ready: true };
      if (args[1] === 'route') return routeOutput(args, '');
      throw new Error(`unexpected ${args[1]}`);
    }),
    existsSync: () => true,
  });

  const out = await bridge.route({ modelId: 'gpt-4o', provider: 'openai' });
  assert.equal(out.used, true);
  assert.equal(out.fallback, true);
  assert.equal(out.selected, false);
  assert.equal(out.error_code, 'no_keys_for_provider');
});

await run('Rust provider route authority prep config and normalization are stable', async () => {
  const config = resolveProviderRouteAuthorityConfig({
    XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP: 'on',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
  });
  assert.equal(config.enabled, true);
  assert.equal(config.prepEnabled, true);
  assert.equal(config.prepThrottleMs, 1000);
  assert.equal(config.prepMaxInFlight, 2);
  assert.equal(config.candidateCacheMs, 250);
  assert.equal(config.candidateCacheMaxEntries, 128);
  assert.equal(config.httpEnabled, false);
  assert.equal(config.httpBaseUrl, 'http://127.0.0.1:50151');
  assert.equal(config.httpTimeoutMs, 750);
  assert.equal(config.httpFallbackToCli, true);
  assert.equal(config.requireNodeMatch, true);
  assert.equal(config.productionAuthority, false);
  assert.equal(config.runnerPath, '/tmp/rust-hub/tools/run_rust_hub.command');
  assert.deepEqual(buildProviderRouteAuthorityArgs('readiness', {}, config).slice(0, 2), [
    'provider',
    'readiness',
  ]);
  assert.deepEqual(buildProviderRouteAuthorityArgs('route', {
    modelId: 'gpt-4o',
    provider: 'openai',
    runtimeBaseDir: '/tmp/runtime',
    nowMs: 123,
  }, config), [
    'provider',
    'route',
    '--model-id',
    'gpt-4o',
    '--provider',
    'openai',
    '--runtime-base-dir',
    '/tmp/runtime',
    '--now-ms',
    '123',
  ]);
  assert.equal(
    normalizeRustProviderRouteDecision({ selected_account_key: 'acct', available_count: '2' })
      .selectedAccountKey,
    'acct'
  );
});

await run('Rust provider route authority production switch is explicit and default-off', async () => {
  const disabled = resolveProviderRouteAuthorityConfig({});
  assert.equal(disabled.enabled, false);
  assert.equal(disabled.productionAuthority, false);

  const enabled = resolveProviderRouteAuthorityConfig({
    XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY: '1',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
  });
  assert.equal(enabled.enabled, true);
  assert.equal(enabled.productionAuthority, true);
  assert.equal(enabled.prepEnabled, false);
  assert.equal(enabled.candidateEnabled, false);
});
