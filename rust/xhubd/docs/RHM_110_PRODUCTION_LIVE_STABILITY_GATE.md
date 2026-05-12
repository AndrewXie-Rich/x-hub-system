# RHM-110 Production Live Stability Gate

## Purpose

`RHM-110` adds a repeatable post-cutover gate for long-running live validation.
It does not change production authority. It composes the existing live heartbeat
soak, daemon ops gate, production runtime guard, UI compatibility gate, and
process sanity checks into one report.
By default it validates the live `launchctl getenv XHUB_RUST_HUB_ROOT` root when
present, so a newer package can run the gate against the currently active
production root without forcing an upgrade.

The gate is intended for short smoke runs, 8 hour soaks, and overnight/24 hour
validation after Rust Hub provider/model/scheduler and XT file IPC live surfaces
are active.

## Command

```bash
bash tools/production_live_stability_gate.command \
  --duration-ms 120000 \
  --interval-ms 2000 \
  --max-status-age-ms 5000 \
  --status-read-timeout-ms 3000 \
  --max-slow-requests 0
```

For an 8 hour run:

```bash
bash tools/production_live_stability_gate.command \
  --duration-ms 28800000 \
  --interval-ms 5000 \
  --max-status-age-ms 7000 \
  --status-read-timeout-ms 3000 \
  --max-slow-requests 0
```

For a 24 hour run:

```bash
bash tools/production_live_stability_gate.command \
  --duration-ms 86400000 \
  --interval-ms 5000 \
  --max-status-age-ms 7000 \
  --status-read-timeout-ms 3000 \
  --max-slow-requests 0
```

## Detached Session

Long runs can be started without blocking the current shell:

```bash
bash tools/production_live_stability_session.command --start --duration-ms 28800000
bash tools/production_live_stability_session.command --status
bash tools/production_live_stability_session.command --checkpoint --duration-ms 10000
```

The session wrapper spawns `production_live_stability_gate.js` detached, records
state in:

```text
reports/production_live_stability/session_state.json
```

and writes the child process output to:

```text
logs/production_live_stability_session_*.log
```

It refuses to start a second active stability session unless `--replace` is
provided. `--stop` sends SIGTERM only to the recorded session PID.
`--checkpoint` performs a short immediate gate without stopping the long
session. If a session was started from a different package root, `--status` and
`--checkpoint` discover the active `production_live_stability_gate.js` process
and report its PID and report path.

## Report

Reports are written to:

```text
reports/production_live_stability_gate_*.json
```

The top-level report includes:

- `live_heartbeat_soak` summary and child report path;
- `daemon_ops_gate` summary and child report path;
- `production_runtime_guard` summary and child report path;
- `ui_compatibility` summary;
- `process_sanity` for launchd `xhubd`, X-Hub/RELFlowHub, Python runtime
  visibility, and accidental `target/debug` or `target/release` xhubd
  processes.

Full child JSON outputs are not embedded by default so 8 hour and 24 hour
reports stay bounded. Add `--include-child-output` only when debugging a failed
short run.

The gate captures `http_metrics_baseline` before the heartbeat soak and compares
it with final daemon ops metrics. `slow_request_delta_budget_ok` fails closed if
any cumulative slow request was introduced during the run when
`--max-slow-requests 0` is used.

## Fail-Closed Boundaries

The gate fails if:

- live XT status heartbeat becomes stale or unreadable;
- `/health`, `/ready`, or `/xt/classic-hub-compat` fail;
- daemon recent slow-request budget is exceeded;
- provider/model or scheduler production authority is not effective in the
  running X-Hub process;
- Rust memory writer authority becomes true;
- Rust skills execution authority becomes true;
- product UI changes are detected;
- secrets are reported as leaked by child gates;
- a temporary `target/debug/xhubd` or `target/release/xhubd` process is left
  running.

The gate itself is read-only except for writing reports.
