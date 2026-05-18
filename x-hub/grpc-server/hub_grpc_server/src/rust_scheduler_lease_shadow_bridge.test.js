import assert from 'node:assert/strict';

import {
  buildSchedulerLeaseArgs,
  buildSchedulerLeaseHttpPayload,
  createSchedulerLeaseShadowBridge,
  resolveSchedulerLeaseShadowConfig,
  schedulerShadowRunId,
} from './rust_scheduler_lease_shadow_bridge.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeFakeExec(calls) {
  return (file, args, options, callback) => {
    calls.push({ file, args, options });
    const command = args[1];
    if (command === 'enqueue') {
      queueMicrotask(() => callback(null, JSON.stringify({
        ok: true,
        command: 'enqueue',
        inserted: true,
        run: {
          run_id: args[args.indexOf('--run-id') + 1],
          request_id: args[args.indexOf('--request-id') + 1],
          scope_key: args[args.indexOf('--scope-key') + 1],
          task_type: 'paid_ai',
          status: 'queued',
        },
      }), ''));
      return;
    }
    if (command === 'acquire-run') {
      queueMicrotask(() => callback(null, JSON.stringify({
        ok: true,
        command: 'acquire-run',
        leased: true,
        run_id: args[args.indexOf('--run-id') + 1],
        request_id: 'req-1',
        scope_key: 'project:a',
        task_type: 'paid_ai',
        lease_owner: args[args.indexOf('--lease-owner') + 1],
        lease_token: 'lease-1',
        lease_expires_at_ms: 123,
        attempt: 1,
        queued_ms: 0,
        payload_json: '{}',
      }), ''));
      return;
    }
    if (command === 'release') {
      queueMicrotask(() => callback(null, JSON.stringify({
        ok: true,
        command: 'release',
        run_id: args[args.indexOf('--run-id') + 1],
        status: 'completed',
      }), ''));
      return;
    }
    if (command === 'cancel') {
      queueMicrotask(() => callback(null, JSON.stringify({
        ok: true,
        command: 'cancel',
        run_id: args[args.indexOf('--run-id') + 1],
        status: 'canceled',
      }), ''));
      return;
    }
    queueMicrotask(() => callback(new Error(`unexpected command ${command}`), '', ''));
  };
}

function makeFakeHttpPost(calls) {
  return (url, payload, timeoutMs) => {
    const parsedUrl = url instanceof URL ? url : new URL(String(url));
    calls.push({ url: parsedUrl, payload, timeoutMs });
    if (parsedUrl.pathname === '/scheduler/enqueue') {
      return Promise.resolve({
        ok: true,
        command: 'enqueue',
        inserted: true,
        run: {
          run_id: payload.run_id,
          request_id: payload.request_id,
          scope_key: payload.scope_key,
          task_type: 'paid_ai',
          status: 'queued',
        },
      });
    }
    if (parsedUrl.pathname === '/scheduler/acquire-run') {
      return Promise.resolve({
        ok: true,
        command: 'acquire-run',
        leased: true,
        run_id: payload.run_id,
        request_id: 'req-1',
        scope_key: 'project:a',
        task_type: 'paid_ai',
        lease_owner: payload.lease_owner,
        lease_token: 'lease-http-1',
        lease_expires_at_ms: 123,
        attempt: 1,
        queued_ms: 0,
        payload_json: '{}',
      });
    }
    if (parsedUrl.pathname === '/scheduler/release') {
      return Promise.resolve({
        ok: true,
        command: 'release',
        run_id: payload.run_id,
        status: 'completed',
      });
    }
    if (parsedUrl.pathname === '/scheduler/cancel') {
      return Promise.resolve({
        ok: true,
        command: 'cancel',
        run_id: payload.run_id,
        status: 'canceled',
      });
    }
    return Promise.reject(new Error(`unexpected path ${parsedUrl.pathname}`));
  };
}

await run('Rust scheduler lease shadow is disabled by default', async () => {
  const calls = [];
  const bridge = createSchedulerLeaseShadowBridge({
    env: {},
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });
  assert.equal(bridge.config.enabled, false);
  assert.equal(bridge.mirrorImmediateAcquire({ requestId: 'req-1', scopeKey: 'project:a' }), false);
  await bridge.flush();
  assert.equal(calls.length, 0);
});

await run('Rust scheduler lease shadow mirrors immediate acquire and release in order', async () => {
  const calls = [];
  const bridge = createSchedulerLeaseShadowBridge({
    env: {
      XHUB_RUST_SCHEDULER_LEASE_SHADOW: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_OWNER: 'node-test',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_DURATION_MS: '60000',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });
  assert.equal(bridge.mirrorImmediateAcquire({
    requestId: 'req-1',
    scopeKey: 'project:a',
    project_id: 'a',
    device_id: 'd',
  }), true);
  assert.equal(bridge.mirrorRelease({ requestId: 'req-1' }), true);
  await bridge.flush();

  assert.equal(calls.length, 3);
  assert.deepEqual(calls.map((call) => call.args[1]), ['enqueue', 'acquire-run', 'release']);
  assert.equal(calls[0].args[calls[0].args.indexOf('--run-id') + 1], 'node_paid_ai_req-1');
  assert.equal(calls[1].args[calls[1].args.indexOf('--lease-owner') + 1], 'node-test');
  assert.equal(calls[2].args[calls[2].args.indexOf('--lease-token') + 1], 'lease-1');
  assert.equal(bridge._state.size, 0);
});

await run('Rust scheduler lease shadow can mirror over HTTP without CLI runner', async () => {
  const execCalls = [];
  const httpCalls = [];
  const warnings = [];
  const logs = [];
  const bridge = createSchedulerLeaseShadowBridge({
    env: {
      XHUB_RUST_SCHEDULER_LEASE_SHADOW: '1',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP: '1',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL: 'http://127.0.0.1:59999',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_TIMEOUT_MS: '1234',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_OWNER: 'node-http-shadow',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_DURATION_MS: '60000',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_VERBOSE: '1',
    },
    execFileImpl: makeFakeExec(execCalls),
    httpPostJsonImpl: makeFakeHttpPost(httpCalls),
    existsSync: () => false,
    logger: {
      warn: (line) => warnings.push(String(line)),
      log: (line) => logs.push(String(line)),
    },
  });
  assert.equal(bridge.mirrorImmediateAcquire({
    requestId: 'req-http-1',
    scopeKey: 'project:http',
    project_id: 'http-project',
    device_id: 'http-device',
    payload: { source: 'test' },
  }), true);
  assert.equal(bridge.mirrorRelease({ requestId: 'req-http-1' }), true);
  await bridge.flush();

  assert.equal(execCalls.length, 0);
  assert.deepEqual(httpCalls.map((call) => call.url.pathname), [
    '/scheduler/enqueue',
    '/scheduler/acquire-run',
    '/scheduler/release',
  ]);
  assert.equal(httpCalls[0].payload.request_id, 'req-http-1');
  assert.equal(httpCalls[0].payload.project_id, 'http-project');
  assert.equal(httpCalls[1].payload.lease_owner, 'node-http-shadow');
  assert.equal(httpCalls[1].payload.lease_duration_ms, 60000);
  assert.equal(httpCalls[2].payload.lease_token, 'lease-http-1');
  assert.equal(httpCalls[0].timeoutMs, 1234);
  assert.equal(warnings.length, 0);
  assert(logs.some((line) => line.includes('HTTP enqueue ok')));
  assert.equal(bridge._state.size, 0);
});

await run('Rust scheduler lease shadow falls back to CLI when HTTP fails by default', async () => {
  const execCalls = [];
  const httpCalls = [];
  const warnings = [];
  const bridge = createSchedulerLeaseShadowBridge({
    env: {
      XHUB_RUST_SCHEDULER_LEASE_SHADOW: '1',
      XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(execCalls),
    httpPostJsonImpl: (url, payload, timeoutMs) => {
      httpCalls.push({ url, payload, timeoutMs });
      return Promise.reject(new Error('http_down'));
    },
    existsSync: () => true,
    logger: {
      warn: (line) => warnings.push(String(line)),
    },
  });
  assert.equal(bridge.mirrorImmediateAcquire({ requestId: 'req-fallback', scopeKey: 'project:fallback' }), true);
  assert.equal(bridge.mirrorRelease({ requestId: 'req-fallback' }), true);
  await bridge.flush();

  assert.deepEqual(execCalls.map((call) => call.args[1]), ['enqueue', 'acquire-run', 'release']);
  assert.deepEqual(httpCalls.map((call) => (call.url instanceof URL ? call.url.pathname : new URL(String(call.url)).pathname)), [
    '/scheduler/enqueue',
    '/scheduler/acquire-run',
    '/scheduler/release',
  ]);
  assert(warnings.some((line) => line.includes('HTTP enqueue failed; falling back to CLI')));
  assert.equal(bridge._state.size, 0);
});

await run('Rust scheduler lease shadow mirrors queued cancel', async () => {
  const calls = [];
  const bridge = createSchedulerLeaseShadowBridge({
    env: {
      XHUB_RUST_SCHEDULER_LEASE_SHADOW: 'true',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });
  assert.equal(bridge.mirrorEnqueue({ requestId: 'req/cancel', scopeKey: 'device:d' }), true);
  assert.equal(bridge.mirrorCancel({ requestId: 'req/cancel', reason: 'canceled' }), true);
  await bridge.flush();
  assert.deepEqual(calls.map((call) => call.args[1]), ['enqueue', 'cancel']);
  assert.equal(calls[1].args[calls[1].args.indexOf('--reason') + 1], 'canceled');
  assert.equal(bridge._state.size, 0);
});

await run('Rust scheduler lease shadow helpers keep stable args', async () => {
  const config = resolveSchedulerLeaseShadowConfig({
    XHUB_RUST_SCHEDULER_LEASE_SHADOW: 'on',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
  });
  assert.equal(config.enabled, true);
  assert.equal(config.runnerPath, '/tmp/rust-hub/tools/run_rust_hub.command');
  assert.equal(schedulerShadowRunId('req / 1'), 'node_paid_ai_req_1');
  assert.deepEqual(buildSchedulerLeaseArgs('acquire-run', {
    requestId: 'req-1',
  }, {
    leaseOwner: 'owner',
    leaseDurationMs: 1234,
  }), [
    'scheduler',
    'acquire-run',
    '--run-id',
    'node_paid_ai_req-1',
    '--lease-owner',
    'owner',
    '--lease-duration-ms',
    '1234',
  ]);
  assert.deepEqual(buildSchedulerLeaseHttpPayload('enqueue', {
    requestId: 'req-1',
    scopeKey: 'project:a',
    project_id: 'a',
    payload: { ok: true },
  }), {
    run_id: 'node_paid_ai_req-1',
    request_id: 'req-1',
    scope_key: 'project:a',
    idempotency_key: 'req-1',
    task_type: 'paid_ai',
    payload: { ok: true },
    project_id: 'a',
  });
  assert.deepEqual(buildSchedulerLeaseHttpPayload('acquire-run', {
    requestId: 'req-1',
  }, {
    leaseOwner: 'owner',
    leaseDurationMs: 1234,
  }), {
    run_id: 'node_paid_ai_req-1',
    lease_owner: 'owner',
    lease_duration_ms: 1234,
  });
});
