# RHM-113 Production Live Rolling Checkpoint Sidecar

## Purpose

The 8 hour or 24 hour live stability session is intentionally long running.
RHM-112 added slow-request delta detection inside each stability gate, but an
already-running session can still be on an older package. RHM-113 adds a
separate rolling checkpoint sidecar that can run short, frequent checkpoints
beside the long session without restarting X-Hub, restarting `xhubd`, changing
authority, or touching the product UI.

## Commands

Start a rolling sidecar:

```bash
bash tools/production_live_stability_session.command \
  --start-checkpoint-loop \
  --duration-ms 28800000 \
  --checkpoint-duration-ms 10000 \
  --checkpoint-interval-ms 900000 \
  --interval-ms 2000 \
  --max-status-age-ms 7000 \
  --status-read-timeout-ms 3000 \
  --max-slow-requests 0
```

Inspect it:

```bash
bash tools/production_live_stability_session.command --checkpoint-loop-status
```

Stop only the sidecar:

```bash
bash tools/production_live_stability_session.command --stop-checkpoint-loop
```

## Behavior

- The sidecar writes a compact loop report under
  `reports/production_live_stability/production_live_stability_checkpoint_loop_*.json`.
- Every cycle writes a normal checkpoint report with RHM-112 slow-request delta
  evidence.
- It is read-only with respect to authority and live state.
- It fails closed if a checkpoint reports a slow-request delta over budget,
  memory writer authority in Rust, skills execution authority in Rust, product
  UI changes, secret leaks, missing live processes, or runtime guard failure.
- It can run while the main detached stability session is active and reports
  the discovered main session PID in each checkpoint summary.

## Verified

- Source syntax gate for `production_live_stability_session.js`: ok.
- Foreground rolling checkpoint loop with two live checkpoints: ok.
- Detached rolling checkpoint sidecar start/status with one live checkpoint: ok.
- Packaged rolling checkpoint loop with one live checkpoint: ok.
- No temporary `target/debug/xhubd` or `target/release/xhubd` process required.
