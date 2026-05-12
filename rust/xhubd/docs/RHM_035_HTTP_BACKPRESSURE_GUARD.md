# RHM-035 HTTP Backpressure Guard

Status: implemented 2026-05-07

## Decision

Rust Hub limits concurrent business HTTP request handling inside `xhubd serve`.
This prevents multi-device polling bursts, browser diagnostics, or bridge
misconfiguration from pushing unbounded work through the daemon.

`/health` remains exempt so launchd and local process managers can still probe
the daemon during pressure.

This is a stutter-control optimization only. It does not switch production
authority, does not cache mutating policy routes, does not execute skills, and
does not change XT UI.

## Runtime Behavior

Default limit:

```text
XHUB_RUST_HTTP_MAX_IN_FLIGHT=128
```

Allowed range:

```text
1..10000
```

When the limit is reached, business routes return:

```text
HTTP/1.1 503 Service Unavailable
```

with a JSON body:

```json
{
  "ok": false,
  "error": "http_backpressure",
  "message": "Rust Hub HTTP in-flight limit reached",
  "in_flight": 128,
  "max_in_flight": 128,
  "retry_after_ms": 250
}
```

## Exempt Route

```text
GET /health
```

`/health` does not consume an in-flight slot and remains unauthenticated, as
before.

## Readiness Signal

`/ready` reports:

```json
{
  "performance": {
    "http_max_in_flight": 128,
    "http_backpressure": true
  },
  "capabilities": {
    "http_backpressure": true
  }
}
```

## Verification

```bash
cargo test -p xhubd
bash "tools/ops_readiness_gate.command" --cycles 3 --interval-ms 250 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
```

Unit coverage verifies:

- `/health` is exempt from in-flight accounting,
- business requests acquire slots,
- a second business request over a limit of one receives
  `http_backpressure`,
- slots are released when request handling exits.

## Authority State

| Area | Rust State |
| --- | --- |
| HTTP business-route backpressure | Enabled |
| `/health` process-manager probe | Exempt |
| Production scheduler authority | Default-off |
| Memory writer authority | Disabled |
| Skill execution authority | Disabled |
| XT UI ownership | Unchanged |

Expected output keeps:

- `http_backpressure_enabled=true`
- `node_remains_authority=true`
- `memory_writer_authority_in_rust=false`
- `skills_execution_authority_in_rust=false`
- `ui_product_change=false`
