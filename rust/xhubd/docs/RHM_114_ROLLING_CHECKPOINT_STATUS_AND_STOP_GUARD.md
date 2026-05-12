# RHM-114 Rolling Checkpoint Status And Stop Guard

## Purpose

RHM-113 added a rolling checkpoint sidecar for long live soaks. RHM-114 makes
that sidecar easier to operate during long-running production validation:

- status reports now expose `next_checkpoint_at_iso` and
  `next_checkpoint_remaining_ms`;
- stopped or interrupted sidecars are reported as `incomplete`, not completed;
- SIGTERM/SIGINT are captured and persisted as `stop_requested` with a
  `stop_signal`;
- final reports keep authority flags explicit and continue to fail closed on
  memory writer authority, skills execution authority, UI changes, secret leaks,
  slow-request deltas, or checkpoint issues.

## Operational Notes

Use the same sidecar commands:

```bash
bash tools/production_live_stability_session.command --checkpoint-loop-status
bash tools/production_live_stability_session.command --stop-checkpoint-loop
```

The stop command only targets the rolling checkpoint sidecar. It does not stop
the main 8 hour or 24 hour stability gate, `xhubd`, X-Hub, or the Python local
runtime.

## Verified

- Source syntax gate for `production_live_stability_session.js`: ok.
- Source rolling checkpoint loop with 10 second live checkpoint: ok.
- Source rolling checkpoint status exposes next checkpoint ETA: ok.
- Source rolling checkpoint stop reports `incomplete=true` and
  `stopped=true`: ok.
- Packaged rolling checkpoint loop with one 10 second live checkpoint: ok.
