# RHM-111 Production Live Stability Checkpoint

## Purpose

`RHM-111` adds a short, read-only checkpoint mode for long-running production
live stability sessions. It lets operators verify current health while an 8 hour
or 24 hour session is still running, without stopping the session or waiting for
the final report.

## Commands

Check the currently running session, including cross-package discovery:

```bash
bash tools/production_live_stability_session.command --status
```

Run an immediate 10 second checkpoint:

```bash
bash tools/production_live_stability_session.command \
  --checkpoint \
  --duration-ms 10000 \
  --interval-ms 2000 \
  --max-status-age-ms 7000 \
  --status-read-timeout-ms 3000 \
  --max-slow-requests 0
```

## Behavior

The checkpoint mode runs `production_live_stability_gate.js` for a short window
and writes:

```text
reports/production_live_stability/production_live_stability_checkpoint_*.json
```

It checks the same production boundaries as the full gate:

- live XT heartbeat freshness;
- daemon health, readiness, and recent slow-request budget;
- cumulative slow-request delta during the checkpoint window;
- provider/model and scheduler authority in the running X-Hub process;
- no Rust memory writer authority;
- no Rust skills execution authority;
- no product UI drift;
- no secret leak;
- no temporary `target/debug` or `target/release` xhubd process.

When the local session state belongs to a different package, `--status` and
`--checkpoint` discover the running `production_live_stability_gate.js` process,
parse its report path and timing from the process command, and still report the
active PID.
