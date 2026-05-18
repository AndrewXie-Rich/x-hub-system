import assert from 'node:assert/strict';

import {
  buildSchedulerCutoverReadinessArgs,
  buildSchedulerStatusArgs,
  createSchedulerStatusBridge,
  normalizeRustSchedulerStatus,
  resolveSchedulerStatusBridgeConfig,
} from './rust_scheduler_bridge.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

await run('Rust scheduler status bridge is disabled by default', async () => {
  const calls = [];
  const bridge = createSchedulerStatusBridge({
    env: {},
    execFileSyncImpl: (...args) => {
      calls.push(args);
      return '{}';
    },
    existsSync: () => true,
  });
  const fallback = { queue_depth: 2, in_flight_total: 1 };
  const out = await bridge.maybeReadStatus({ fallback });
  assert.equal(bridge.config.enabled, false);
  assert.equal(out.used, false);
  assert.equal(out.paid_ai, fallback);
  assert.equal(calls.length, 0);
});

await run('Rust scheduler status bridge reads and normalizes Rust status JSON', async () => {
  const calls = [];
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_STATUS_TIMEOUT_MS: '900',
    },
    execFileSyncImpl: (file, args, options) => {
      calls.push({ file, args, options });
      return JSON.stringify({
        ok: true,
        updated_at_ms: 123,
        in_flight_total: 2,
        queue_depth: 3,
        oldest_queued_ms: 400,
        in_flight_by_scope: [{ scope_key: 'project:a', count: 2 }],
        queued_by_scope: [{ scope_key: 'project:b', count: 3 }],
        queue_items: [
          { request_id: 'req-1', scope_key: 'project:b', enqueued_at_ms: 10, queued_ms: 4 },
          { request_id: 'req-2', scope_key: 'project:c', enqueued_at_ms: 11, queued_ms: 3 },
        ],
      });
    },
    existsSync: () => true,
  });

  const out = await bridge.maybeReadStatus({
    includeQueueItems: true,
    queueItemsLimit: 1,
    fallback: {
      global_concurrency: 6,
      per_project_concurrency: 2,
      queue_limit: 128,
      queue_timeout_ms: 20000,
    },
  });

  assert.equal(out.ok, true);
  assert.equal(out.used, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].file, '/tmp/rust-hub/tools/run_rust_hub.command');
  assert.deepEqual(calls[0].args, [
    'scheduler',
    'status',
    '--queue-items-limit',
    '1',
    '--include-queue-items',
  ]);
  assert.equal(calls[0].options.timeout, 900);
  assert.deepEqual(out.paid_ai, {
    updated_at_ms: 123,
    global_concurrency: 6,
    per_project_concurrency: 2,
    queue_limit: 128,
    queue_timeout_ms: 20000,
    in_flight_total: 2,
    queue_depth: 3,
    oldest_queued_ms: 400,
    in_flight_by_scope: [{ scope_key: 'project:a', in_flight: 2 }],
    queued_by_scope: [{ scope_key: 'project:b', queued: 3 }],
    queue_items: [
      { request_id: 'req-1', scope_key: 'project:b', enqueued_at_ms: 10, queued_ms: 4 },
    ],
  });
});

await run('Rust scheduler status bridge uses async execFile path by default', async () => {
  const calls = [];
  let callbackFired = false;
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_STATUS_TIMEOUT_MS: '800',
    },
    execFileImpl: (file, args, options, callback) => {
      calls.push({ file, args, options });
      setImmediate(() => {
        callbackFired = true;
        callback(null, JSON.stringify({
          ok: true,
          updated_at_ms: 321,
          in_flight_total: 0,
          queue_depth: 0,
          oldest_queued_ms: 0,
        }), '');
      });
    },
    existsSync: () => true,
  });

  const pending = bridge.maybeReadStatus({ fallback: {} });
  assert.equal(typeof pending?.then, 'function');
  assert.equal(callbackFired, false);

  const out = await pending;

  assert.equal(callbackFired, true);
  assert.equal(out.ok, true);
  assert.equal(out.used, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].options.timeout, 800);
  assert.equal(calls[0].options.maxBuffer, 1024 * 1024);
});

await run('Rust scheduler status bridge caches short polling bursts', async () => {
  let now = 1000;
  let calls = 0;
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_STATUS_CACHE_MS: '500',
    },
    execFileSyncImpl: () => {
      calls += 1;
      return JSON.stringify({
        ok: true,
        updated_at_ms: 111,
        in_flight_total: 0,
        queue_depth: calls,
        oldest_queued_ms: 0,
      });
    },
    existsSync: () => true,
    nowMsImpl: () => now,
  });

  const first = await bridge.maybeReadStatus({ fallback: { global_concurrency: 3 } });
  const second = await bridge.maybeReadStatus({ fallback: { global_concurrency: 9 } });
  now += 501;
  const third = await bridge.maybeReadStatus({ fallback: { global_concurrency: 3 } });

  assert.equal(calls, 2);
  assert.equal(first.cache_hit, false);
  assert.equal(second.cache_hit, true);
  assert.equal(second.paid_ai.queue_depth, 1);
  assert.equal(second.paid_ai.global_concurrency, 9);
  assert.equal(third.cache_hit, false);
  assert.equal(third.paid_ai.queue_depth, 2);
});

await run('Rust scheduler status bridge coalesces concurrent reads', async () => {
  const calls = [];
  let finish = null;
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_STATUS_CACHE_MS: '0',
    },
    execFileImpl: (file, args, options, callback) => {
      calls.push({ file, args, options });
      finish = () => callback(null, JSON.stringify({
        ok: true,
        updated_at_ms: 222,
        in_flight_total: 1,
        queue_depth: 2,
        oldest_queued_ms: 3,
      }), '');
    },
    existsSync: () => true,
  });

  const first = bridge.maybeReadStatus({ fallback: {} });
  const second = bridge.maybeReadStatus({ fallback: {} });
  assert.equal(calls.length, 1);
  finish();
  const [firstOut, secondOut] = await Promise.all([first, second]);

  assert.equal(firstOut.used, true);
  assert.equal(secondOut.used, true);
  assert.equal(firstOut.paid_ai.queue_depth, 2);
  assert.equal(secondOut.paid_ai.in_flight_total, 1);
});

await run('Rust scheduler status bridge blocks Rust reads when cutover readiness is not ready', async () => {
  const calls = [];
  const warnings = [];
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_STATUS_MIN_COMPARE_REPORTS: '12',
      XHUB_RUST_SCHEDULER_STATUS_MAX_MISMATCHES: '0',
      XHUB_RUST_SCHEDULER_STATUS_MIN_LEASE_SHADOW_RUNS: '2',
      XHUB_RUST_SCHEDULER_STATUS_MAX_STALE_ACTIVE: '0',
      XHUB_RUST_SCHEDULER_STATUS_MAX_ORPHANED_LEASES: '0',
    },
    execFileSyncImpl: (file, args) => {
      calls.push({ file, args });
      assert.equal(args[1], 'cutover-readiness');
      return JSON.stringify({
        ok: true,
        ready: false,
        decision: 'blocked',
      });
    },
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  const fallback = { queue_depth: 7 };
  const out = await bridge.maybeReadStatus({ fallback });

  assert.equal(out.ok, false);
  assert.equal(out.used, false);
  assert.equal(out.error_code, 'rust_scheduler_cutover_not_ready');
  assert.equal(out.paid_ai, fallback);
  assert.equal(out.readiness.ready, false);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].args, [
    'scheduler',
    'cutover-readiness',
    '--min-compare-reports',
    '12',
    '--max-mismatches',
    '0',
    '--min-lease-shadow-runs',
    '2',
    '--max-stale-active',
    '0',
    '--max-orphaned-leases',
    '0',
  ]);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /cutover readiness not ready/);
});

await run('Rust scheduler status bridge reads Rust status after cutover readiness passes', async () => {
  const calls = [];
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: 'true',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileSyncImpl: (file, args, options) => {
      calls.push({ file, args, options });
      if (args[1] === 'cutover-readiness') {
        return JSON.stringify({
          ok: true,
          ready: true,
          decision: 'ready',
        });
      }
      assert.equal(args[1], 'status');
      return JSON.stringify({
        ok: true,
        updated_at_ms: 456,
        in_flight_total: 0,
        queue_depth: 1,
        oldest_queued_ms: 2,
        queued_by_scope: [{ scope_key: 'project:ready', queued: 1 }],
      });
    },
    existsSync: () => true,
  });

  const out = await bridge.maybeReadStatus({ includeQueueItems: false, fallback: {} });

  assert.equal(out.ok, true);
  assert.equal(out.used, true);
  assert.equal(out.readiness.ready, true);
  assert.equal(out.paid_ai.queue_depth, 1);
  assert.deepEqual(calls.map((call) => call.args[1]), ['cutover-readiness', 'status']);
  assert.deepEqual(calls[1].args, [
    'scheduler',
    'status',
    '--queue-items-limit',
    '100',
  ]);
});

await run('Rust scheduler status bridge prefers HTTP status when enabled', async () => {
  const cliCalls = [];
  const httpCalls = [];
  const logs = [];
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_SCHEDULER_STATUS_HTTP: '1',
      XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL: 'http://127.0.0.1:55152',
      XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS: '1234',
      XHUB_RUST_SCHEDULER_STATUS_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_SCHEDULER_STATUS_VERBOSE: '1',
    },
    execFileSyncImpl: (...args) => {
      cliCalls.push(args);
      return '{}';
    },
    httpGetJsonImpl: (url, timeoutMs) => {
      httpCalls.push({ url: String(url), timeoutMs });
      return {
        ok: true,
        command: 'status',
        updated_at_ms: 789,
        in_flight_total: 0,
        queue_depth: 4,
        oldest_queued_ms: 5,
      };
    },
    existsSync: () => false,
    logger: { log: (line) => logs.push(line), warn: () => {} },
  });

  const out = await bridge.maybeReadStatus({
    includeQueueItems: false,
    queueItemsLimit: 7,
    fallback: { global_concurrency: 3 },
  });

  assert.equal(out.ok, true);
  assert.equal(out.used, true);
  assert.equal(out.paid_ai.queue_depth, 4);
  assert.equal(out.paid_ai.global_concurrency, 3);
  assert.equal(cliCalls.length, 0);
  assert.equal(httpCalls.length, 1);
  assert.equal(httpCalls[0].url, 'http://127.0.0.1:55152/scheduler/status?include_queue_items=0&queue_items_limit=7');
  assert.equal(httpCalls[0].timeoutMs, 1234);
  assert.equal(logs.some((line) => /HTTP status ok/.test(line)), true);
});

await run('Rust scheduler status bridge uses HTTP readiness and status without CLI runner', async () => {
  const httpCalls = [];
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: '1',
      XHUB_RUST_SCHEDULER_STATUS_HTTP: '1',
      XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL: 'http://127.0.0.1:55152',
      XHUB_RUST_SCHEDULER_STATUS_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_SCHEDULER_STATUS_MIN_COMPARE_REPORTS: '0',
      XHUB_RUST_SCHEDULER_STATUS_MIN_LEASE_SHADOW_RUNS: '0',
    },
    httpGetJsonImpl: (url) => {
      httpCalls.push(String(url));
      if (String(url).includes('/scheduler/cutover-readiness')) {
        return {
          ok: true,
          command: 'cutover-readiness',
          ready: true,
          decision: 'ready',
        };
      }
      return {
        ok: true,
        command: 'status',
        updated_at_ms: 999,
        in_flight_total: 1,
        queue_depth: 0,
        oldest_queued_ms: 0,
      };
    },
    existsSync: () => false,
  });

  const out = await bridge.maybeReadStatus({ includeQueueItems: true, queueItemsLimit: 2, fallback: {} });

  assert.equal(out.ok, true);
  assert.equal(out.used, true);
  assert.equal(out.readiness.ready, true);
  assert.equal(out.paid_ai.in_flight_total, 1);
  assert.deepEqual(httpCalls, [
    'http://127.0.0.1:55152/scheduler/cutover-readiness?min_compare_reports=0&max_mismatches=0&min_lease_shadow_runs=0&max_stale_active=0&max_orphaned_leases=0',
    'http://127.0.0.1:55152/scheduler/status?include_queue_items=1&queue_items_limit=2',
  ]);
});

await run('Rust scheduler status bridge falls back from HTTP status to CLI by default', async () => {
  const cliCalls = [];
  const warnings = [];
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_SCHEDULER_STATUS_HTTP: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileSyncImpl: (file, args) => {
      cliCalls.push({ file, args });
      return JSON.stringify({
        ok: true,
        updated_at_ms: 101,
        in_flight_total: 0,
        queue_depth: 1,
        oldest_queued_ms: 0,
      });
    },
    httpGetJsonImpl: () => {
      throw new Error('daemon_down');
    },
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  assert.equal(bridge.config.httpFallbackToCli, true);
  const out = await bridge.maybeReadStatus({ fallback: {} });
  assert.equal(out.ok, true);
  assert.equal(out.used, true);
  assert.equal(out.paid_ai.queue_depth, 1);
  assert.equal(cliCalls.length, 1);
  assert.equal(warnings.some((line) => /HTTP status failed; falling back to CLI/.test(line)), true);
});

await run('Rust scheduler status bridge falls back when cutover readiness check fails', async () => {
  const calls = [];
  const warnings = [];
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: '1',
      XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileSyncImpl: (file, args) => {
      calls.push({ file, args });
      throw new Error('boom');
    },
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  const fallback = { queue_depth: 9 };
  const out = await bridge.maybeReadStatus({ fallback });
  await bridge.maybeReadStatus({ fallback });

  assert.equal(out.ok, false);
  assert.equal(out.used, false);
  assert.equal(out.error_code, 'rust_scheduler_cutover_readiness_failed');
  assert.equal(out.paid_ai, fallback);
  assert.equal(calls.length, 2);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /cutover readiness check failed/);
});

await run('Rust scheduler status bridge falls back when runner is missing', async () => {
  const warnings = [];
  const bridge = createSchedulerStatusBridge({
    env: {
      XHUB_RUST_SCHEDULER_STATUS_READ: 'true',
      XHUB_RUST_HUB_RUNNER: '/missing/run_rust_hub.command',
    },
    existsSync: () => false,
    logger: { warn: (line) => warnings.push(line) },
  });
  const fallback = { queue_depth: 0 };
  assert.deepEqual(await bridge.maybeReadStatus({ fallback }), {
    ok: false,
    used: false,
    error_code: 'rust_scheduler_runner_missing',
    paid_ai: fallback,
  });
  await bridge.maybeReadStatus({ fallback });
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /missing runner=/);
});

await run('Rust scheduler status helpers keep stable config and args', async () => {
  const config = resolveSchedulerStatusBridgeConfig({
    XHUB_RUST_SCHEDULER_STATUS_READ: 'on',
    XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY: 'on',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
    XHUB_RUST_SCHEDULER_STATUS_MIN_COMPARE_REPORTS: '12',
    XHUB_RUST_SCHEDULER_STATUS_MIN_LEASE_SHADOW_RUNS: '2',
  });
  assert.equal(config.enabled, true);
  assert.equal(config.requireReady, true);
  assert.equal(config.runnerPath, '/tmp/rust-hub/tools/run_rust_hub.command');
  assert.equal(config.httpEnabled, false);
  assert.equal(config.httpBaseUrl, 'http://127.0.0.1:50151');
  assert.equal(config.httpTimeoutMs, 750);
  assert.equal(config.httpFallbackToCli, true);
  assert.equal(config.readiness.minCompareReports, 12);
  assert.equal(config.readiness.minLeaseShadowRuns, 2);
  assert.deepEqual(buildSchedulerStatusArgs({
    includeQueueItems: false,
    queueItemsLimit: '12',
  }), [
    'scheduler',
    'status',
    '--queue-items-limit',
    '12',
  ]);
  assert.deepEqual(buildSchedulerCutoverReadinessArgs({
    minCompareReports: '12',
    maxMismatches: '0',
    minLeaseShadowRuns: '2',
    maxStaleActive: '0',
    maxOrphanedLeases: '0',
  }), [
    'scheduler',
    'cutover-readiness',
    '--min-compare-reports',
    '12',
    '--max-mismatches',
    '0',
    '--min-lease-shadow-runs',
    '2',
    '--max-stale-active',
    '0',
    '--max-orphaned-leases',
    '0',
  ]);
  assert.deepEqual(normalizeRustSchedulerStatus({
    ok: true,
    in_flight_by_scope: [{ scope_key: 'project:z', count: '4' }],
    queued_by_scope: [{ scope_key: 'project:y', queued: '3' }],
  }, {
    includeQueueItems: false,
    fallback: { updated_at_ms: 88 },
  }).queue_items, []);
});
