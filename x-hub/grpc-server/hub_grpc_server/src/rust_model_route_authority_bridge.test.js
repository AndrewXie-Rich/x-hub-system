import assert from 'node:assert/strict';

import {
  buildModelRouteAuthorityArgs,
  createModelRouteAuthorityBridge,
  normalizeRustModelRouteDecision,
  resolveModelRouteAuthorityConfig,
} from './rust_model_route_authority_bridge.js';

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

function defaultHandler() {
  return (args) => {
    const command = args[1];
    if (command === 'readiness') {
      return readinessOutput(true);
    }
    if (command === 'route') {
      return routeOutputFromArgs(args, 'gpt-5.5', 'remote');
    }
    throw new Error(`unexpected command ${command}`);
  };
}

function readinessOutput(ready = true) {
  return {
    ok: true,
    command: 'readiness',
    ready,
    decision: ready ? 'ready' : 'not_ready',
    compare: {
      total: ready ? 10 : 0,
      matched: ready ? 10 : 0,
      mismatched: 0,
    },
  };
}

function routeOutput({ modelId = 'gpt-5.5', routeKind = 'remote', blockingReasonCode = '' } = {}) {
  return {
    ok: true,
    schema_version: 'xhub.model_route_decision.v1',
    command: 'route',
    runtime_base_dir: '/tmp/runtime',
    updated_at_ms: 1234,
    request: {
      task_type: 'text.generate',
      model_id: modelId,
      required_capabilities: ['text.generate'],
      privacy_mode: routeKind === 'local' ? 'local-only' : 'remote-only',
      cost_preference: 'balanced',
    },
    selected_route_kind: blockingReasonCode ? '' : routeKind,
    selected_model_id: blockingReasonCode ? '' : modelId,
    blocking_reason_code: blockingReasonCode,
    selected: blockingReasonCode ? {} : { route_kind: routeKind, model_id: modelId },
    remote_candidates: routeKind === 'remote' ? [{ route_kind: 'remote', model_id: modelId, selected: !blockingReasonCode }] : [],
    local_candidates: routeKind === 'local' ? [{ route_kind: 'local', model_id: modelId, selected: !blockingReasonCode }] : [],
  };
}

function routeOutputFromArgs(args, selectedModelId, routeKind) {
  const modelId = args[args.indexOf('--model-id') + 1] || selectedModelId;
  return routeOutput({ modelId: selectedModelId || modelId, routeKind });
}

function routeOutputFromUrl(url, selectedModelId = 'gpt-5.5', routeKind = 'remote') {
  const parsed = new URL(String(url));
  return routeOutput({
    modelId: selectedModelId || parsed.searchParams.get('model_id') || 'auto',
    routeKind,
  });
}

await run('Rust model route authority prep is disabled by default', async () => {
  const calls = [];
  const bridge = createModelRouteAuthorityBridge({
    env: {},
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });
  const out = await bridge.route({ modelId: 'gpt-5.5', nodeModelId: 'gpt-5.5' });
  assert.equal(bridge.config.enabled, false);
  assert.equal(out.used, false);
  assert.equal(out.fallback, true);
  assert.equal(out.error_code, 'rust_model_route_authority_disabled');
  assert.equal(calls.length, 0);
});

await run('Rust model route authority production switch is explicit and default-off', async () => {
  const disabled = resolveModelRouteAuthorityConfig({});
  assert.equal(disabled.enabled, false);
  assert.equal(disabled.productionAuthority, false);

  const enabled = resolveModelRouteAuthorityConfig({
    XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY: '1',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
  });
  assert.equal(enabled.enabled, true);
  assert.equal(enabled.productionAuthority, true);
  assert.equal(enabled.prepEnabled, false);
  assert.equal(enabled.candidateEnabled, false);
});


await run('Rust model route authority builds CLI route args without provider secrets', async () => {
  const args = buildModelRouteAuthorityArgs('route', {
    runtimeBaseDir: '/tmp/runtime',
    taskType: 'text_generate',
    modelId: 'gpt-5.5',
    requiredCapabilities: ['text.generate', 'code.assist'],
    privacyMode: 'remote-only',
    costPreference: 'balanced',
    nowMs: 123,
  }, resolveModelRouteAuthorityConfig({}));
  assert.deepEqual(args, [
    'model',
    'route',
    '--task-type',
    'text_generate',
    '--model-id',
    'gpt-5.5',
    '--required-capability',
    'text.generate',
    '--required-capability',
    'code.assist',
    '--privacy-mode',
    'remote-only',
    '--cost-preference',
    'balanced',
    '--runtime-base-dir',
    '/tmp/runtime',
    '--now-ms',
    '123',
  ]);
  assert.equal(JSON.stringify(args).includes('api_key'), false);
});

await run('Rust model route authority HTTP path gates on readiness and returns selected model', async () => {
  const urls = [];
  const bridge = createModelRouteAuthorityBridge({
    env: {
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL: 'http://127.0.0.1:50151',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS: '0',
    },
    httpGetJsonImpl: async (url) => {
      urls.push(String(url));
      if (String(url).includes('/model/readiness')) return readinessOutput(true);
      return routeOutputFromUrl(url, 'gpt-5.5', 'remote');
    },
    existsSync: () => false,
  });

  const out = await bridge.route({
    runtimeBaseDir: '/tmp/runtime',
    taskType: 'text_generate',
    modelId: 'gpt-5.5',
    requiredCapabilities: ['text.generate'],
    privacyMode: 'remote-only',
    nodeModelId: 'gpt-5.5',
    nodeRouteKind: 'remote',
  });
  assert.equal(out.used, true);
  assert.equal(out.selected, true);
  assert.equal(out.fallback, false);
  assert.equal(out.selectedModelId, 'gpt-5.5');
  assert.equal(out.selectedRouteKind, 'remote');
  assert.equal(urls.length, 2);
  assert.equal(urls[0].includes('/model/readiness'), true);
  assert.equal(urls[1].includes('/model/route'), true);
});

await run('Rust model route authority fails closed when readiness is not ready', async () => {
  const bridge = createModelRouteAuthorityBridge({
    env: {
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '0',
    },
    httpGetJsonImpl: async () => readinessOutput(false),
    existsSync: () => false,
  });
  const out = await bridge.route({
    modelId: 'gpt-5.5',
    nodeModelId: 'gpt-5.5',
  });
  assert.equal(out.used, false);
  assert.equal(out.fallback, true);
  assert.equal(out.error_code, 'rust_model_route_authority_not_ready');
});

await run('Rust model route authority reports model mismatch without changing Node route', async () => {
  const calls = [];
  const warnings = [];
  const bridge = createModelRouteAuthorityBridge({
    env: {
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls, () => routeOutput({ modelId: 'gpt-4o-mini', routeKind: 'remote' })),
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  const out = await bridge.route({
    modelId: 'gpt-5.5',
    nodeModelId: 'gpt-5.5',
    nodeRouteKind: 'remote',
  });
  assert.equal(out.used, true);
  assert.equal(out.fallback, true);
  assert.equal(out.mismatch, true);
  assert.equal(out.error_code, 'rust_model_route_authority_model_mismatch');
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /model mismatch/);
});

await run('Rust model route authority rejects secret material in Rust response', async () => {
  const warnings = [];
  const bridge = createModelRouteAuthorityBridge({
    env: {
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP: '1',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY: '0',
    },
    httpGetJsonImpl: async () => ({
      ...routeOutput({ modelId: 'gpt-5.5', routeKind: 'remote' }),
      remote_candidates: [
        {
          route_kind: 'remote',
          model_id: 'gpt-5.5',
          api_key: 'sk-should-not-appear-in-route',
        },
      ],
    }),
    existsSync: () => false,
    logger: { warn: (line) => warnings.push(line) },
  });
  const out = await bridge.route({
    modelId: 'gpt-5.5',
    nodeModelId: 'gpt-5.5',
  });
  assert.equal(out.used, false);
  assert.equal(out.fallback, true);
  assert.equal(out.error_code, 'rust_model_route_authority_route_failed');
  assert.match(out.error_message, /secret/);
  assert.equal(warnings.some((line) => /route failed/.test(line)), true);
});

await run('Rust model route authority normalizes route decisions', async () => {
  const decision = normalizeRustModelRouteDecision(routeOutput({
    modelId: 'local.summary',
    routeKind: 'local',
  }));
  assert.equal(decision.schemaVersion, 'xhub.model_route_decision.v1');
  assert.equal(decision.requestedTaskType, 'text.generate');
  assert.equal(decision.selectedModelId, 'local.summary');
  assert.equal(decision.selectedRouteKind, 'local');
  assert.equal(decision.remoteCandidateCount, 0);
  assert.equal(decision.localCandidateCount, 1);
});
