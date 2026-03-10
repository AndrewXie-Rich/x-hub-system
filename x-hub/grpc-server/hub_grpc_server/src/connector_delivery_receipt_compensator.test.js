import assert from 'node:assert/strict';

import { createConnectorDeliveryReceiptCompensator } from './connector_delivery_receipt_compensator.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('CRK-W2-03/prepare-commit-undo-compensate transitions are stable and idempotent', () => {
  const compensator = createConnectorDeliveryReceiptCompensator({
    default_commit_timeout_ms: 30_000,
    max_entries: 128,
  });
  const base = {
    connector: 'slack',
    target_id: 'room_receipt',
    idempotency_key: 'idem-001',
    event_id: 'event-001',
    event_sequence: 1,
  };

  const firstPrepare = compensator.prepare({
    ...base,
    now_ms: 1_000,
  });
  assert.equal(!!firstPrepare.ok, true);
  assert.equal(!!firstPrepare.idempotent, false);
  assert.equal(String(firstPrepare.delivery_state || ''), 'prepared');

  const secondPrepare = compensator.prepare({
    ...base,
    now_ms: 1_010,
  });
  assert.equal(!!secondPrepare.ok, true);
  assert.equal(!!secondPrepare.idempotent, true);
  assert.equal(String(secondPrepare.delivery_state || ''), 'prepared');

  const committed = compensator.commit({
    ...base,
    provider_receipt: 'provider:ack-001',
    now_ms: 1_020,
  });
  assert.equal(!!committed.ok, true);
  assert.equal(String(committed.delivery_state || ''), 'committed');

  const committedAgain = compensator.commit({
    ...base,
    provider_receipt: 'provider:ack-001',
    now_ms: 1_030,
  });
  assert.equal(!!committedAgain.ok, true);
  assert.equal(!!committedAgain.idempotent, true);

  const undo = compensator.undo({
    ...base,
    reason: 'downstream_revert',
    compensate_after_ms: 0,
    now_ms: 1_040,
  });
  assert.equal(!!undo.ok, true);
  assert.equal(String(undo.delivery_state || ''), 'undo_pending');

  const tick = compensator.runCompensation({
    now_ms: 1_041,
    max_jobs: 10,
  });
  assert.equal(!!tick.ok, true);
  assert.equal(Number(tick.compensated || 0), 1);

  const prepareAfterCompensated = compensator.prepare({
    ...base,
    now_ms: 1_050,
  });
  assert.equal(!!prepareAfterCompensated.ok, false);
  assert.equal(String(prepareAfterCompensated.deny_code || ''), 'terminal_not_allowed');
});

run('CRK-W2-03/commit-timeout auto-promotes undo_pending then compensates', () => {
  const compensator = createConnectorDeliveryReceiptCompensator({
    default_commit_timeout_ms: 100,
    max_entries: 128,
  });
  const base = {
    connector: 'slack',
    target_id: 'room_timeout',
    idempotency_key: 'idem-timeout-1',
    event_id: 'event-timeout-1',
    event_sequence: 9,
  };
  const prepared = compensator.prepare({
    ...base,
    now_ms: 5_000,
  });
  assert.equal(!!prepared.ok, true);

  const tick = compensator.runCompensation({
    now_ms: 6_200,
    max_jobs: 5,
  });
  assert.equal(!!tick.ok, true);
  assert.ok(Number(tick.promoted_timeout_undo || 0) >= 1);
  assert.equal(Number(tick.compensated || 0), 1);

  const receipt = compensator.getReceipt(base);
  assert.ok(receipt, 'expected receipt after compensation');
  assert.equal(String(receipt.delivery_state || ''), 'compensated');
});

run('CRK-W2-03/compensation worker failure is fail-closed and retryable', () => {
  const compensator = createConnectorDeliveryReceiptCompensator({
    default_commit_timeout_ms: 60_000,
    max_entries: 128,
    compensation_retry_ms: 200,
  });
  const base = {
    connector: 'slack',
    target_id: 'room_retry',
    idempotency_key: 'idem-retry-1',
    event_id: 'event-retry-1',
    event_sequence: 1,
  };
  const prepared = compensator.prepare({
    ...base,
    now_ms: 20_000,
  });
  assert.equal(!!prepared.ok, true);
  const undo = compensator.undo({
    ...base,
    reason: 'runtime_error',
    compensate_after_ms: 0,
    now_ms: 20_010,
  });
  assert.equal(!!undo.ok, true);

  const failedTick = compensator.runCompensation({
    now_ms: 20_020,
    max_jobs: 5,
    compensate_fn() {
      return { ok: false, deny_code: 'temporary_unavailable', retry_after_ms: 200 };
    },
  });
  assert.equal(!!failedTick.ok, true);
  assert.equal(Number(failedTick.failed || 0), 1);
  assert.equal(Number(failedTick.compensated || 0), 0);
  assert.equal(Number(failedTick.pending_compensation || 0), 1);

  const notDueYet = compensator.runCompensation({
    now_ms: 20_100,
    max_jobs: 5,
  });
  assert.equal(!!notDueYet.ok, true);
  assert.equal(Number(notDueYet.processed || 0), 0);

  const retryTick = compensator.runCompensation({
    now_ms: 20_600,
    max_jobs: 5,
  });
  assert.equal(!!retryTick.ok, true);
  assert.equal(Number(retryTick.compensated || 0), 1);
});

run('CRK-W2-03/fail-closed on clock error and bounded receipt cardinality', () => {
  const failClosed = createConnectorDeliveryReceiptCompensator({
    nowFn() {
      throw new Error('simulated_clock_failure');
    },
  });
  const out = failClosed.prepare({
    connector: 'slack',
    target_id: 'room_fail_closed',
    idempotency_key: 'idem-fail-closed',
  });
  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'receipt_guard_error');

  const bounded = createConnectorDeliveryReceiptCompensator({
    max_entries: 64,
    stale_window_ms: 1_000,
  });
  for (let i = 0; i < 64; i += 1) {
    const prepared = bounded.prepare({
      connector: 'slack',
      target_id: `room-${i}`,
      idempotency_key: `idem-${i}`,
      now_ms: 1_000 + i,
    });
    assert.equal(!!prepared.ok, true);
  }
  const overflow = bounded.prepare({
    connector: 'slack',
    target_id: 'room-overflow',
    idempotency_key: 'idem-overflow',
    now_ms: 2_000,
  });
  assert.equal(!!overflow.ok, false);
  assert.equal(String(overflow.deny_code || ''), 'receipt_store_overflow');

  bounded.prune(200_000);
  const snap = bounded.snapshot();
  assert.equal(Number(snap.entries || 0), 0);
});
