import assert from 'node:assert/strict';

import {
  buildSchedulerAuthorityArgs,
  buildSchedulerAuthorityHttpPayload,
  createSchedulerAuthorityBridge,
  resolveSchedulerAuthorityConfig,
  schedulerAuthorityRunId,
} from './rust_scheduler_authority_bridge.js';

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
        const out = handler(args, calls.length);
        callback(null, JSON.stringify(out), '');
      } catch (error) {
        callback(error, '', '');
      }
    });
  };
}

function defaultHandler() {
  return (args) => {
    const command = args[1];
    if (command === 'cutover-readiness') {
      return {
        ok: true,
        command,
        ready: true,
        decision: 'ready',
      };
    }
    if (command === 'claim') {
      return claimOutput(args, { leased: true, inserted: true });
    }
    if (command === 'release') {
      return {
        ok: true,
        command,
        run_id: args[args.indexOf('--run-id') + 1],
        status: 'completed',
      };
    }
    if (command === 'cancel') {
      return {
        ok: true,
        command,
        run_id: args[args.indexOf('--run-id') + 1],
        status: 'canceled',
      };
    }
    throw new Error(`unexpected command ${command}`);
  };
}

function claimOutput(args, { leased, inserted }) {
  const runId = args[args.indexOf('--run-id') + 1];
  const requestId = args[args.indexOf('--request-id') + 1];
  const scopeKey = args[args.indexOf('--scope-key') + 1];
  return {
    ok: true,
    command: 'claim',
    inserted,
    leased,
    run: {
      run_id: runId,
      request_id: requestId,
      scope_key: scopeKey,
      task_type: 'paid_ai',
      status: leased ? 'leased' : 'queued',
    },
    run_id: runId,
    request_id: requestId,
    scope_key: scopeKey,
    task_type: 'paid_ai',
    lease_owner: args[args.indexOf('--lease-owner') + 1],
    lease_token: leased ? `lease-${requestId}` : '',
    lease_expires_at_ms: 123,
    attempt: leased ? 1 : 0,
    queued_ms: leased ? 7 : 0,
    payload_json: '{}',
  };
}

await run('Rust scheduler authority bridge is disabled by default', async () => {
  const calls = [];
  const bridge = createSchedulerAuthorityBridge({
    env: {},
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });
  const out = await bridge.acquireSlot({ requestId: 'req-1', scopeKey: 'project:a' });
  assert.equal(bridge.config.enabled, false);
  assert.equal(out.used, false);
  assert.equal(out.fallback, true);
  assert.equal(out.error_code, 'rust_scheduler_authority_disabled');
  assert.equal(calls.length, 0);
});

await run('Rust scheduler authority bridge claims and releases a Rust lease', async () => {
  const calls = [];
  const bridge = createSchedulerAuthorityBridge({
    env: {
      XHUB_RUST_SCHEDULER_AUTHORITY: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_AUTHORITY_OWNER: 'node-authority-test',
      XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS: '60000',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });

  const claim = await bridge.claimOnce({
    requestId: 'req-1',
    scopeKey: 'project:a',
    project_id: 'a',
    device_id: 'd',
    payload: { source: 'test' },
  });
  assert.equal(claim.used, true);
  assert.equal(claim.leased, true);
  assert.equal(claim.leaseToken, 'lease-req-1');
  assert.equal(claim.queuedMs, 7);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls.map((call) => call.args[1]), ['cutover-readiness', 'claim']);
  assert.equal(calls[1].args[calls[1].args.indexOf('--lease-owner') + 1], 'node-authority-test');
  assert.equal(calls[1].args[calls[1].args.indexOf('--lease-duration-ms') + 1], '60000');

  assert.equal(await bridge.release({ requestId: 'req-1' }), true);
  assert.deepEqual(calls.map((call) => call.args[1]), ['cutover-readiness', 'claim', 'release']);
  assert.equal(calls[2].args[calls[2].args.indexOf('--lease-token') + 1], 'lease-req-1');
  assert.equal(bridge._state.size, 0);
});

await run('Rust scheduler authority CLI can use an isolated Rust DB path', async () => {
  const calls = [];
  const bridge = createSchedulerAuthorityBridge({
    env: {
      XHUB_RUST_SCHEDULER_AUTHORITY: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_AUTHORITY_DB_PATH: '/tmp/rust-hub/data/hub.sqlite3',
    },
    execFileImpl: makeFakeExec(calls),
    existsSync: () => true,
  });

  await bridge.claimOnce({
    requestId: 'req-db-1',
    scopeKey: 'project:db',
  });

  assert.equal(bridge.config.dbPath, '/tmp/rust-hub/data/hub.sqlite3');
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.env.HUB_DB_PATH, '/tmp/rust-hub/data/hub.sqlite3');
  assert.equal(calls[1].options.env.HUB_DB_PATH, '/tmp/rust-hub/data/hub.sqlite3');
});

await run('Rust scheduler authority bridge can use HTTP readiness, claim, and release without CLI runner', async () => {
  const cliCalls = [];
  const httpGets = [];
  const httpPosts = [];
  const logs = [];
  const bridge = createSchedulerAuthorityBridge({
    env: {
      XHUB_RUST_SCHEDULER_AUTHORITY: '1',
      XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: '1',
      XHUB_RUST_SCHEDULER_AUTHORITY_HTTP: '1',
      XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL: 'http://127.0.0.1:55153',
      XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_TIMEOUT_MS: '1234',
      XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_TO_CLI: '0',
      XHUB_RUST_SCHEDULER_AUTHORITY_OWNER: 'node-authority-http',
      XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS: '60000',
      XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS: '0',
      XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS: '0',
      XHUB_RUST_SCHEDULER_AUTHORITY_VERBOSE: '1',
    },
    execFileImpl: makeFakeExec(cliCalls),
    httpGetJsonImpl: (url, timeoutMs) => {
      httpGets.push({ url: String(url), timeoutMs });
      return {
        ok: true,
        command: 'cutover-readiness',
        ready: true,
        decision: 'ready',
      };
    },
    httpPostJsonImpl: (url, payload, timeoutMs) => {
      httpPosts.push({ url: String(url), payload, timeoutMs });
      if (String(url).endsWith('/scheduler/claim')) {
        return {
          ok: true,
          command: 'claim',
          inserted: true,
          leased: true,
          run_id: payload.run_id,
          request_id: payload.request_id,
          scope_key: payload.scope_key,
          lease_token: `lease-${payload.request_id}`,
          queued_ms: 3,
        };
      }
      if (String(url).endsWith('/scheduler/release')) {
        return {
          ok: true,
          command: 'release',
          run_id: payload.run_id,
          status: 'completed',
        };
      }
      throw new Error(`unexpected url ${url}`);
    },
    existsSync: () => false,
    logger: { log: (line) => logs.push(line), warn: () => {} },
  });

  const claim = await bridge.claimOnce({
    requestId: 'req-http-1',
    scopeKey: 'project:http',
    project_id: 'http-project',
    device_id: 'device-http',
    payload: { source: 'http-test' },
  });

  assert.equal(claim.used, true);
  assert.equal(claim.leased, true);
  assert.equal(claim.leaseToken, 'lease-req-http-1');
  assert.equal(await bridge.release({ requestId: 'req-http-1' }), true);
  assert.equal(cliCalls.length, 0);
  assert.equal(httpGets.length, 1);
  assert.equal(httpGets[0].url, 'http://127.0.0.1:55153/scheduler/cutover-readiness?min_compare_reports=0&max_mismatches=0&min_lease_shadow_runs=0&max_stale_active=0&max_orphaned_leases=0&allow_active_runs=1');
  assert.equal(httpGets[0].timeoutMs, 1234);
  assert.deepEqual(httpPosts.map((call) => call.url), [
    'http://127.0.0.1:55153/scheduler/claim',
    'http://127.0.0.1:55153/scheduler/release',
  ]);
  assert.deepEqual(httpPosts[0].payload, {
    run_id: schedulerAuthorityRunId('req-http-1'),
    request_id: 'req-http-1',
    scope_key: 'project:http',
    idempotency_key: 'req-http-1',
    task_type: 'paid_ai',
    lease_owner: 'node-authority-http',
    lease_duration_ms: 60000,
    payload: { source: 'http-test' },
    project_id: 'http-project',
    device_id: 'device-http',
  });
  assert.equal(httpPosts[1].payload.lease_token, 'lease-req-http-1');
  assert.equal(logs.some((line) => /HTTP readiness ok/.test(line)), true);
  assert.equal(logs.some((line) => /HTTP claim ok/.test(line)), true);
});

await run('Rust scheduler authority bridge falls back from HTTP claim to CLI by default', async () => {
  const calls = [];
  const warnings = [];
  const bridge = createSchedulerAuthorityBridge({
    env: {
      XHUB_RUST_SCHEDULER_AUTHORITY: '1',
      XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: '0',
      XHUB_RUST_SCHEDULER_AUTHORITY_HTTP: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls),
    httpPostJsonImpl: () => {
      throw new Error('daemon_down');
    },
    existsSync: () => true,
    logger: { warn: (line) => warnings.push(line) },
  });

  assert.equal(bridge.config.httpFallbackToCli, true);
  const claim = await bridge.claimOnce({ requestId: 'req-http-fallback', scopeKey: 'project:a' });
  assert.equal(claim.used, true);
  assert.equal(claim.leased, true);
  assert.deepEqual(calls.map((call) => call.args[1]), ['claim']);
  assert.equal(warnings.some((line) => /HTTP claim failed; falling back to CLI/.test(line)), true);
});

await run('Rust scheduler authority bridge blocks claims when readiness is not ready', async () => {
  const calls = [];
  const bridge = createSchedulerAuthorityBridge({
    env: {
      XHUB_RUST_SCHEDULER_AUTHORITY: 'true',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
    },
    execFileImpl: makeFakeExec(calls, (args) => {
      if (args[1] === 'cutover-readiness') {
        return {
          ok: true,
          command: 'cutover-readiness',
          ready: false,
          decision: 'not_ready',
        };
      }
      throw new Error('claim should not run');
    }),
    existsSync: () => true,
  });

  const out = await bridge.claimOnce({ requestId: 'req-not-ready', scopeKey: 'project:a' });
  assert.equal(out.used, false);
  assert.equal(out.fallback, true);
  assert.equal(out.error_code, 'rust_scheduler_authority_not_ready');
  assert.deepEqual(calls.map((call) => call.args[1]), ['cutover-readiness']);
});

await run('Rust scheduler authority bridge polls claim until lease is granted', async () => {
  const calls = [];
  const queuedEvents = [];
  let claimCount = 0;
  const bridge = createSchedulerAuthorityBridge({
    env: {
      XHUB_RUST_SCHEDULER_AUTHORITY: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS: '20',
    },
    execFileImpl: makeFakeExec(calls, (args) => {
      if (args[1] === 'cutover-readiness') {
        return { ok: true, command: 'cutover-readiness', ready: true };
      }
      if (args[1] === 'claim') {
        claimCount += 1;
        return claimOutput(args, { leased: claimCount >= 2, inserted: claimCount === 1 });
      }
      if (args[1] === 'release') {
        return { ok: true, command: 'release', status: 'completed' };
      }
      throw new Error(`unexpected ${args[1]}`);
    }),
    existsSync: () => true,
    setTimeoutImpl: (fn) => {
      queueMicrotask(fn);
      return { unref() {} };
    },
  });

  const slot = await bridge.acquireSlot({
    requestId: 'req-poll',
    scopeKey: 'project:a',
    waitMs: 1000,
    onQueued: (event) => queuedEvents.push(event),
  });
  assert.equal(slot.used, true);
  assert.equal(slot.fallback, false);
  assert.equal(slot.runId, schedulerAuthorityRunId('req-poll'));
  assert.equal(claimCount, 2);
  assert.equal(queuedEvents.length, 1);
  assert.equal(queuedEvents[0].authority, 'rust');
});

await run('Rust scheduler authority bridge cancels Rust queued run on timeout', async () => {
  const calls = [];
  let now = 1000;
  const bridge = createSchedulerAuthorityBridge({
    env: {
      XHUB_RUST_SCHEDULER_AUTHORITY: '1',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_AUTHORITY_POLL_MS: '100',
    },
    execFileImpl: makeFakeExec(calls, (args) => {
      if (args[1] === 'cutover-readiness') {
        return { ok: true, command: 'cutover-readiness', ready: true };
      }
      if (args[1] === 'claim') {
        return claimOutput(args, { leased: false, inserted: false });
      }
      if (args[1] === 'cancel') {
        return { ok: true, command: 'cancel', status: 'canceled' };
      }
      throw new Error(`unexpected ${args[1]}`);
    }),
    existsSync: () => true,
    nowMsImpl: () => now,
    setTimeoutImpl: (fn, ms) => {
      now += ms;
      queueMicrotask(fn);
      return { unref() {} };
    },
  });

  await assert.rejects(
    bridge.acquireSlot({
      requestId: 'req-timeout',
      scopeKey: 'project:a',
      waitMs: 1000,
    }),
    /hub_ai_queue_timeout/
  );
  assert.equal(calls.at(-1).args[1], 'cancel');
  assert.equal(calls.at(-1).args[calls.at(-1).args.indexOf('--reason') + 1], 'hub_ai_queue_timeout');
  assert.equal(bridge._state.size, 0);
});

await run('Rust scheduler authority helpers keep stable config and args', async () => {
  const config = resolveSchedulerAuthorityConfig({
    XHUB_RUST_SCHEDULER_AUTHORITY: 'on',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
    XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY: '1',
    XHUB_RUST_SCHEDULER_AUTHORITY_OWNER: 'owner',
    XHUB_RUST_SCHEDULER_AUTHORITY_LEASE_DURATION_MS: '1234',
    XHUB_RUST_SCHEDULER_AUTHORITY_TIMEOUT_MS: '45000',
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_COMPARE_REPORTS: '12',
    XHUB_RUST_SCHEDULER_AUTHORITY_MIN_LEASE_SHADOW_RUNS: '2',
  });
  assert.equal(config.enabled, true);
  assert.equal(config.requireReady, true);
  assert.equal(config.runnerPath, '/tmp/rust-hub/tools/run_rust_hub.command');
  assert.equal(config.httpEnabled, false);
  assert.equal(config.httpBaseUrl, 'http://127.0.0.1:50151');
  assert.equal(config.httpTimeoutMs, 750);
  assert.equal(config.timeoutMs, 45000);
  assert.equal(config.httpFallbackToCli, true);
  assert.equal(config.readiness.minCompareReports, 12);
  assert.equal(config.readiness.minLeaseShadowRuns, 2);
  assert.equal(config.readiness.allowActiveRuns, true);
  assert.equal(schedulerAuthorityRunId('req / 1'), 'node_paid_ai_authority_req_1');
  assert.deepEqual(buildSchedulerAuthorityArgs('claim', {
    requestId: 'req-1',
    scopeKey: 'project:a',
  }, config).slice(0, 18), [
    'scheduler',
    'claim',
    '--run-id',
    'node_paid_ai_authority_req-1',
    '--request-id',
    'req-1',
    '--scope-key',
    'project:a',
    '--idempotency-key',
    'req-1',
    '--task-type',
    'paid_ai',
    '--lease-owner',
    'owner',
    '--lease-duration-ms',
    '1234',
    '--payload-json',
    '{}',
  ]);
  assert.deepEqual(buildSchedulerAuthorityHttpPayload('claim', {
    requestId: 'req-1',
    scopeKey: 'project:a',
  }, config), {
    run_id: 'node_paid_ai_authority_req-1',
    request_id: 'req-1',
    scope_key: 'project:a',
    idempotency_key: 'req-1',
    task_type: 'paid_ai',
    lease_owner: 'owner',
    lease_duration_ms: 1234,
    payload: {},
  });
  assert.deepEqual(buildSchedulerAuthorityArgs('cutover-readiness', {}, config), [
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
    '--allow-active-runs',
  ]);

  const activeBlockedConfig = resolveSchedulerAuthorityConfig({
    XHUB_RUST_SCHEDULER_AUTHORITY: '1',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
    XHUB_RUST_SCHEDULER_AUTHORITY_ALLOW_ACTIVE_RUNS: '0',
  });
  assert.equal(activeBlockedConfig.readiness.allowActiveRuns, false);
  assert.equal(buildSchedulerAuthorityArgs('cutover-readiness', {}, activeBlockedConfig).includes('--allow-active-runs'), false);
});
