# RHM-036 HTTP Latency Metrics

Status: implemented 2026-05-07

## Decision

Rust Hub records lightweight route-level HTTP latency metrics inside
`xhubd serve`. This gives long-running deployments a local way to see which
diagnostic, memory, skills, provider, model, or scheduler route is contributing
to perceived stutter.

This is diagnostics only. It does not record request bodies, does not expose
stored `detail_json`, does not switch production authority, and does not change
XT UI.

## Runtime Behavior

Slow threshold:

```text
XHUB_RUST_HTTP_SLOW_MS=2000
```

Allowed range:

```text
1..300000 ms
```

Routes at or above the threshold increment `slow_count` and emit a sanitized
stderr line with route, status, elapsed time, and threshold. The log line does
not include query strings or request bodies.

## Metrics Endpoint

```text
GET /runtime/http-metrics
GET /http/metrics
```

Schema:

```text
xhub.rust_hub.http_metrics.v1
```

Response fields include:

- total request count,
- slow request count,
- average elapsed milliseconds,
- max elapsed milliseconds,
- current in-flight request count,
- configured max in-flight,
- slow threshold,
- per-route count, average, max, last elapsed, slow count, and last status.

Expected authority fields:

```json
{
  "authority": "diagnostics_only",
  "production_authority_change": false,
  "detail_json_included": false
}
```

## Readiness Signal

`/ready` reports:

```json
{
  "performance": {
    "http_slow_ms": 2000,
    "http_metrics": true
  },
  "capabilities": {
    "http_metrics": true
  }
}
```

## Verification

```bash
cargo test -p xhubd
bash "tools/ops_readiness_gate.command" --cycles 3 --interval-ms 250 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
```

The ops gate verifies:

- `/ready` exposes HTTP metrics capability,
- `/runtime/http-metrics` returns the expected schema,
- route rows include `/ready`,
- no request-body, secret, or `detail_json` payload is returned,
- memory writer authority remains disabled,
- skill execution authority remains disabled,
- UI compatibility remains unchanged.
