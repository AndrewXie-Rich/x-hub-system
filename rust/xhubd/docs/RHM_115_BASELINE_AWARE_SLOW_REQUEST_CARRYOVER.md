# RHM-115 Baseline-Aware Slow Request Carryover

## Purpose

Rolling live checkpoints should catch new stutters without stopping forever
because a slow sample already existed in the recent HTTP metrics window before
the checkpoint began. RHM-115 makes the production live stability gate
baseline-aware:

- it still reads HTTP metrics before and after the checkpoint;
- it still fails closed when `slow_requests_delta` exceeds the configured
  budget;
- if `daemon_ops_gate` fails only because a pre-existing recent slow sample is
  still in the bounded recent window, and the checkpoint delta is within budget,
  the stability gate records a warning and continues;
- UI, memory writer authority, skills execution authority, secret leak, process,
  heartbeat, and production runtime guard failures remain blocking.

## Evidence Fields

Reports include:

- `baseline_slow_request_carryover_ok`
- `warnings[].code = baseline_slow_request_carryover_delta_ok`
- `slow_request_delta`
- `http_metrics_baseline`
- `http_metrics_final_summary`

## Verified

- Source syntax gate for `production_live_stability_gate.js`: ok.
- Source syntax gate for `production_live_stability_session.js`: ok.
- Source rolling checkpoint with pre-existing recent slow request and
  `slow_requests_delta=0`: ok.
- Packaged rolling checkpoint with pre-existing recent slow request and
  `slow_requests_delta=0`: ok.
