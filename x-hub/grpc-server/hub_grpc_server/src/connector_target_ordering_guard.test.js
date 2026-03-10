import assert from 'node:assert/strict';

import { createConnectorTargetOrderingGuard } from './connector_target_ordering_guard.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('CRK-W2-02/target lock blocks concurrent begin on same target', () => {
  const guard = createConnectorTargetOrderingGuard({
    lock_ttl_ms: 5_000,
    seen_ttl_ms: 10_000,
    max_targets: 64,
  });
  const base = {
    connector: 'slack',
    target_id: 'room_lock',
  };

  const first = guard.begin({
    ...base,
    event_id: 'event-lock-1',
    event_sequence: 1,
    now_ms: 1_000,
  });
  assert.equal(!!first.ok, true);

  const second = guard.begin({
    ...base,
    event_id: 'event-lock-2',
    event_sequence: 2,
    now_ms: 1_010,
  });
  assert.equal(!!second.ok, false);
  assert.equal(String(second.deny_code || ''), 'target_locked');
  assert.ok(Number(second.retry_after_ms || 0) > 0);

  const completed = guard.complete({
    ...base,
    lock_token: first.lock_token,
    success: true,
    event_id: 'event-lock-1',
    event_sequence: 1,
    now_ms: 1_020,
  });
  assert.equal(!!completed.ok, true);
});

run('CRK-W2-02/out-of-order and duplicate event are rejected', () => {
  const guard = createConnectorTargetOrderingGuard({
    lock_ttl_ms: 5_000,
    seen_ttl_ms: 30_000,
    max_targets: 64,
  });
  const base = {
    connector: 'slack',
    target_id: 'room_order',
  };

  const s1 = guard.begin({
    ...base,
    event_id: 'event-1',
    event_sequence: 10,
    now_ms: 2_000,
  });
  assert.equal(!!s1.ok, true);
  const c1 = guard.complete({
    ...base,
    lock_token: s1.lock_token,
    success: true,
    event_id: 'event-1',
    event_sequence: 10,
    now_ms: 2_010,
  });
  assert.equal(!!c1.ok, true);

  const outOfOrder = guard.begin({
    ...base,
    event_id: 'event-2',
    event_sequence: 9,
    now_ms: 2_020,
  });
  assert.equal(!!outOfOrder.ok, false);
  assert.equal(String(outOfOrder.deny_code || ''), 'out_of_order_event');

  const duplicate = guard.begin({
    ...base,
    event_id: 'event-1',
    event_sequence: 11,
    now_ms: 2_030,
  });
  assert.equal(!!duplicate.ok, false);
  assert.equal(String(duplicate.deny_code || ''), 'duplicate_event');
});

run('CRK-W2-02/fail-closed on clock failure and bounded target cardinality', () => {
  const failClosedGuard = createConnectorTargetOrderingGuard({
    nowFn() {
      throw new Error('simulated_clock_failure');
    },
  });
  const out = failClosedGuard.begin({
    connector: 'slack',
    target_id: 'room_fail_closed',
    event_id: 'event-fail-closed',
  });
  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'ordering_guard_error');

  const boundedGuard = createConnectorTargetOrderingGuard({
    max_targets: 16,
    stale_window_ms: 60_000,
  });
  for (let i = 0; i < 16; i += 1) {
    const begin = boundedGuard.begin({
      connector: 'slack',
      target_id: `room-${i}`,
      event_id: `event-${i}`,
      now_ms: 10_000 + i,
    });
    assert.equal(!!begin.ok, true);
    const done = boundedGuard.complete({
      connector: 'slack',
      target_id: `room-${i}`,
      lock_token: begin.lock_token,
      success: true,
      event_id: `event-${i}`,
      now_ms: 10_050 + i,
    });
    assert.equal(!!done.ok, true);
  }

  const overflow = boundedGuard.begin({
    connector: 'slack',
    target_id: 'room-overflow',
    event_id: 'event-overflow',
    now_ms: 20_000,
  });
  assert.equal(!!overflow.ok, false);
  assert.equal(String(overflow.deny_code || ''), 'runtime_state_overflow');

  boundedGuard.prune(80_500);
  const snap = boundedGuard.snapshot();
  assert.equal(Number(snap.targets || 0), 0);
});
