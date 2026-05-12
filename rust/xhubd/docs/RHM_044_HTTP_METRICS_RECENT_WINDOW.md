# RHM-044 HTTP Metrics Recent Window

Status: implemented 2026-05-07

## Decision

Rust Hub keeps a bounded recent HTTP latency window inside `xhubd serve`.
This gives long-running daemons a current stutter signal instead of relying
only on lifetime counters.

This is diagnostics only. It does not record request bodies, query strings, or
stored `detail_json`. It does not switch production authority, does not execute
skills, does not write canonical memory, and does not change XT UI.

## Runtime Behavior

Recent sample capacity:

```text
XHUB_RUST_HTTP_METRICS_RECENT_LIMIT=256
```

Allowed range:

```text
0..10000 samples
```

When the limit is greater than zero, each handled HTTP route records only:

- completion timestamp,
- sanitized route path without query or fragment,
- HTTP status,
- elapsed milliseconds,
- slow flag.

The endpoint includes at most 64 recent samples in the JSON response, newest
first. Aggregate recent route summaries cover the full in-memory recent window.

## Metrics Fields

`GET /runtime/http-metrics` and `GET /http/metrics` keep the existing
`xhub.rust_hub.http_metrics.v1` schema and add:

```json
{
  "recent_sample_capacity": 256,
  "recent_sample_count": 0,
  "recent_samples_output_limit": 64,
  "recent_samples_included": 0,
  "recent_dropped_samples": 0,
  "recent_slow_requests": 0,
  "recent_avg_elapsed_ms": 0,
  "recent_max_elapsed_ms": 0,
  "recent_route_count": 0,
  "recent_routes": [],
  "recent_samples_newest_first": []
}
```

Readiness also reports:

```json
{
  "performance": {
    "http_metrics_recent_limit": 256
  },
  "capabilities": {
    "http_metrics_recent_window": true
  }
}
```

## Ops Gate

`daemon_ops_gate.command` now applies `--max-slow-requests` to
`recent_slow_requests` when the daemon exposes the recent window. If the gate
talks to an older daemon, it falls back to lifetime `slow_requests`.

This prevents one historical slow request from making a long-running daemon
fail every future daily/manual gate after the current window is healthy.

## Verification

```bash
cargo test -p xhubd http_metrics
node --check "tools/xhubd_daemon.js"
node --check "tools/ops_soak_runner.js"
bash "tools/ops_soak_runner.command" --cycles 2 --interval-ms 100 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
bash "tools/daemon_ops_gate.command" --max-slow-requests 0 --maintenance-max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
```

The checks verify:

- recent samples are bounded,
- query strings and secret-like fragments are not exposed,
- recent slow request count is available,
- ops gate uses recent-window slow budget when available,
- UI compatibility remains unchanged.
