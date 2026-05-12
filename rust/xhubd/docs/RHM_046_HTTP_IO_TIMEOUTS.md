# RHM-046 HTTP I/O Timeouts

Status: implemented 2026-05-07

## Decision

Rust Hub sets bounded read and write timeouts on each `xhubd serve` HTTP
connection. This protects long-running daemons from slow clients, half-open
connections, or stalled network paths holding a worker thread indefinitely.

This is a stability guard only. It does not change production authority, does
not write canonical memory, does not execute third-party skills, and does not
change XT UI.

## Runtime Behavior

Default settings:

```text
XHUB_RUST_HTTP_READ_TIMEOUT_MS=5000
XHUB_RUST_HTTP_WRITE_TIMEOUT_MS=5000
```

Allowed range:

```text
0..300000 ms
```

`0` disables the corresponding socket timeout. The default keeps local UI and
daemon probes responsive while preventing slowloris-style request reads or
stalled response writes from lasting forever.

## Readiness Signal

`/ready` reports:

```json
{
  "performance": {
    "http_read_timeout_ms": 5000,
    "http_write_timeout_ms": 5000,
    "http_io_timeouts": true
  },
  "capabilities": {
    "http_io_timeouts": true
  }
}
```

## Verification

```bash
cargo test -p xhubd http_io_timeouts
node --check "tools/ops_soak_runner.js"
bash "tools/ops_soak_runner.command" --cycles 2 --interval-ms 100 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
```

The checks verify:

- socket read/write timeouts are applied,
- readiness exposes timeout configuration,
- warm daemon soak sees `http_io_timeouts=true`,
- UI compatibility remains unchanged.
