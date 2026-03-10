import assert from 'node:assert/strict';

import { createConnectorReconnectOrchestrator } from './connector_reconnect_orchestrator.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('CRK-W2-01/state manager transitions idle -> connecting -> ready -> degraded_polling -> recovering -> ready', () => {
  const orchestrator = createConnectorReconnectOrchestrator({
    reconnect_backoff_base_ms: 1000,
    reconnect_backoff_max_ms: 10_000,
  });
  const target = { connector: 'slack', target_id: 'room_1' };

  const boot = orchestrator.applySignal({ ...target, signal: 'boot', now_ms: 1_000 });
  assert.equal(!!boot.ok, true);
  assert.equal(String(boot.state || ''), 'idle');

  const connecting = orchestrator.applySignal({ ...target, signal: 'ws_connecting', now_ms: 1_100 });
  assert.equal(!!connecting.ok, true);
  assert.equal(String(connecting.state || ''), 'connecting');

  const ready = orchestrator.applySignal({ ...target, signal: 'ws_ready', now_ms: 1_350 });
  assert.equal(!!ready.ok, true);
  assert.equal(String(ready.state || ''), 'ready');

  const failed = orchestrator.applySignal({
    ...target,
    signal: 'ws_failed',
    error_code: 'transport_unavailable',
    now_ms: 2_000,
  });
  assert.equal(!!failed.ok, true);
  assert.equal(String(failed.state || ''), 'degraded_polling');
  assert.ok(Number(failed.retry_after_ms || 0) > 0);

  const notDue = orchestrator.applySignal({ ...target, signal: 'reconnect_tick', now_ms: 2_500 });
  assert.equal(!!notDue.ok, true);
  assert.equal(String(notDue.action || ''), 'none');

  const dueTick = orchestrator.applySignal({ ...target, signal: 'reconnect_tick', now_ms: 3_010 });
  assert.equal(!!dueTick.ok, true);
  assert.equal(String(dueTick.state || ''), 'recovering');
  assert.equal(String(dueTick.action || ''), 'attempt_ws_reconnect');

  const recovered = orchestrator.applySignal({ ...target, signal: 'ws_ready', now_ms: 3_240 });
  assert.equal(!!recovered.ok, true);
  assert.equal(String(recovered.state || ''), 'ready');

  const snap = orchestrator.snapshot();
  assert.ok(Number(snap.reconnect_attempts || 0) >= 1);
  assert.ok(Number(snap.connector_reconnect_ms_p95 || 0) > 0);
});

run('CRK-W2-01/invalid transition is rejected with state_corrupt (fail-closed)', () => {
  const orchestrator = createConnectorReconnectOrchestrator();
  const out = orchestrator.applySignal({
    connector: 'slack',
    target_id: 'room_2',
    signal: 'ws_ready',
    now_ms: 1_000,
  });
  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'state_corrupt');
  const snap = orchestrator.snapshot();
  assert.ok(Number(snap.state_corrupt_incidents || 0) >= 1);
});

run('CRK-W2-01/internal clock error returns orchestrator_fail_closed', () => {
  const orchestrator = createConnectorReconnectOrchestrator({
    nowFn() {
      throw new Error('simulated_clock_failure');
    },
  });
  const out = orchestrator.applySignal({
    connector: 'slack',
    target_id: 'room_3',
    signal: 'boot',
  });
  assert.equal(!!out.ok, false);
  assert.equal(String(out.deny_code || ''), 'orchestrator_fail_closed');
  const snap = orchestrator.snapshot();
  assert.ok(Number(snap.fail_closed || 0) >= 1);
});

run('CRK-W2-01/runtime target set remains bounded with stale prune', () => {
  const orchestrator = createConnectorReconnectOrchestrator({
    max_targets: 16,
    stale_window_ms: 60_000,
  });

  for (let i = 0; i < 16; i += 1) {
    const out = orchestrator.applySignal({
      connector: 'slack',
      target_id: `target-${i}`,
      signal: 'boot',
      now_ms: 1_000 + i,
    });
    assert.equal(!!out.ok, true);
  }

  const overflow = orchestrator.applySignal({
    connector: 'slack',
    target_id: 'target-overflow',
    signal: 'boot',
    now_ms: 2_000,
  });
  assert.equal(!!overflow.ok, false);
  assert.equal(String(overflow.deny_code || ''), 'runtime_state_overflow');

  orchestrator.prune(70_500);
  const afterPrune = orchestrator.snapshot();
  assert.equal(Number(afterPrune.targets || 0), 0);
});
