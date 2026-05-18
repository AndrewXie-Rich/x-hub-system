import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';

import {
  buildSchedulerShadowCompareArgs,
  createSchedulerShadowComparer,
  normalizePaidAISchedulerSnapshot,
  resolveSchedulerShadowCompareConfig,
} from './rust_scheduler_shadow_compare.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeFakeSpawn(calls) {
  return (command, args, options) => {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.kill = () => {
      child.killed = true;
    };
    calls.push({ command, args, options, child });
    queueMicrotask(() => child.emit('close', 0));
    return child;
  };
}

run('Rust scheduler shadow compare is disabled by default', () => {
  const calls = [];
  const comparer = createSchedulerShadowComparer({
    env: {},
    spawnImpl: makeFakeSpawn(calls),
    existsSync: () => true,
  });
  assert.equal(comparer.config.enabled, false);
  assert.equal(comparer.maybeCompare({ in_flight_total: 1, queue_depth: 2 }), false);
  assert.equal(calls.length, 0);
});

run('Rust scheduler shadow compare spawns Node caller when enabled', () => {
  const calls = [];
  let clock = 10_000;
  const comparer = createSchedulerShadowComparer({
    env: {
      XHUB_RUST_SCHEDULER_SHADOW_COMPARE: '1',
      XHUB_RUST_SCHEDULER_SHADOW_COMPARE_SCRIPT: '/tmp/rust-hub/tools/node_scheduler_shadow_compare.js',
      XHUB_RUST_HUB_RUNNER: '/tmp/rust-hub/tools/run_rust_hub.command',
      XHUB_RUST_SCHEDULER_SHADOW_COMPARE_THROTTLE_MS: '1000',
    },
    spawnImpl: makeFakeSpawn(calls),
    existsSync: () => true,
    now: () => clock,
  });

  assert.equal(comparer.maybeCompare({
    in_flight_total: 2,
    queue_depth: 3,
    oldest_queued_ms: 4,
  }), true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, process.execPath);
  assert.deepEqual(calls[0].args.slice(0, 4), [
    '/tmp/rust-hub/tools/node_scheduler_shadow_compare.js',
    '--runner',
    '/tmp/rust-hub/tools/run_rust_hub.command',
    '--snapshot-json',
  ]);
  const payload = JSON.parse(calls[0].args[4]);
  assert.deepEqual(payload, {
    paid_ai: {
      in_flight_total: 2,
      queue_depth: 3,
      oldest_queued_ms: 4,
    },
  });

  assert.equal(comparer.maybeCompare({ in_flight_total: 0, queue_depth: 0 }), false);
  assert.equal(calls.length, 1);
  clock += 2000;
  calls[0].child.emit('close', 0);
  assert.equal(comparer.maybeCompare({ in_flight_total: 0, queue_depth: 0 }), true);
  assert.equal(calls.length, 2);
});

run('Rust scheduler shadow compare reports missing caller once', () => {
  const warnings = [];
  const comparer = createSchedulerShadowComparer({
    env: {
      XHUB_RUST_SCHEDULER_SHADOW_COMPARE: 'true',
      XHUB_RUST_SCHEDULER_SHADOW_COMPARE_SCRIPT: '/missing/script.js',
      XHUB_RUST_HUB_RUNNER: '/missing/run.command',
    },
    spawnImpl: makeFakeSpawn([]),
    existsSync: () => false,
    logger: { warn: (line) => warnings.push(line) },
  });
  assert.equal(comparer.maybeCompare({}), false);
  assert.equal(comparer.maybeCompare({}), false);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /missing script=/);
});

run('Rust scheduler shadow compare config and args are stable', () => {
  const config = resolveSchedulerShadowCompareConfig({
    XHUB_RUST_SCHEDULER_SHADOW_COMPARE: 'on',
    XHUB_RUST_HUB_ROOT: '/tmp/rust-hub',
  });
  assert.equal(config.enabled, true);
  assert.equal(config.scriptPath, '/tmp/rust-hub/tools/node_scheduler_shadow_compare.js');
  assert.equal(config.runnerPath, '/tmp/rust-hub/tools/run_rust_hub.command');
  assert.deepEqual(normalizePaidAISchedulerSnapshot({
    in_flight_total: '2',
    queue_depth: '3',
    oldest_queued_ms: '4',
  }), {
    in_flight_total: 2,
    queue_depth: 3,
    oldest_queued_ms: 4,
  });
  assert.deepEqual(buildSchedulerShadowCompareArgs({ queue_depth: 1 }, config).slice(0, 4), [
    '/tmp/rust-hub/tools/node_scheduler_shadow_compare.js',
    '--runner',
    '/tmp/rust-hub/tools/run_rust_hub.command',
    '--snapshot-json',
  ]);
});
