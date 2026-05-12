# RHM-112 Production Live Slow Delta Guard

## Purpose

`RHM-112` prevents long-running stability gates from missing transient stutter.
The HTTP metrics recent window is bounded and can age out old samples before an
8 hour or 24 hour run finishes. The stability gate now captures a cumulative
HTTP metrics baseline before the live heartbeat soak, then compares it with the
final daemon ops metrics.

This turns `--max-slow-requests 0` into both:

- a recent-window budget checked by `daemon_ops_gate`; and
- a full-run cumulative slow-request delta budget checked by
  `production_live_stability_gate`.

## Report Fields

`production_live_stability_gate` now reports:

- `http_metrics_baseline`
- `http_metrics_final_summary`
- `slow_request_delta`
- `slow_request_delta_budget_ok`

`slow_request_delta.route_slow_request_deltas` records per-route slow deltas so
the report shows whether `/ready`, `/xt/classic-hub-compat`, or another route
introduced the stutter during the run.

## Behavior

The gate fails closed if:

- baseline HTTP metrics cannot be read;
- final HTTP metrics cannot be read; or
- `slow_request_delta.slow_requests_delta > --max-slow-requests`.

The check is read-only and does not change production authority. It leaves Rust
memory writer authority and Rust skills execution authority disabled.
