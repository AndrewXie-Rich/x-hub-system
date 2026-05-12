# RHM-033 Ready Cache Stutter Guard

Status: implemented 2026-05-07

## Decision

Rust Hub caches `/ready` for a short process-local TTL while `xhubd serve` is
running. This reduces repeated filesystem scans, skill catalog scans, and
SQLite scheduler status reads when XT, browser diagnostics, launchd helpers, or
Node bridges poll readiness rapidly.

This is a stutter-control optimization only. It does not change production
authority, does not cache mutating routes, does not execute skills, and does
not change XT UI.

## Runtime Behavior

Default TTL:

```text
XHUB_RUST_READY_CACHE_TTL_MS=250
```

Allowed range:

```text
0..5000 ms
```

`0` disables the cache.

The cached surface is limited to:

```text
GET /ready
GET /readiness
GET /runtime/readiness
```

Other endpoints continue to evaluate each request normally.

`/ready` now reports:

```json
{
  "generated_at_ms": 0,
  "performance": {
    "readiness_cache_ttl_ms": 250,
    "readiness_cache_scope": "process_memory",
    "stutter_guard": true,
    "blocks_production_authority": false
  },
  "capabilities": {
    "readiness_cache_http": true
  }
}
```

## Gate Coverage

`tools/ops_readiness_gate.command` now checks:

- first `/ready` is ready,
- immediate second `/ready` returns the same `generated_at_ms`,
- readiness cache capability is present,
- per-endpoint latency stays under `--max-endpoint-ms`,
- each cycle stays under `--max-cycle-ms`,
- memory retrieval and skills policy gates remain authority-neutral,
- UI compatibility remains unchanged.

Recommended gate:

```bash
bash "tools/ops_readiness_gate.command" --cycles 3 --interval-ms 250 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
```

## Authority State

| Area | Rust State |
| --- | --- |
| `/ready` cache | Enabled |
| Mutating route cache | Disabled |
| Production scheduler authority | Default-off |
| Memory writer authority | Disabled |
| Skill execution authority | Disabled |
| XT UI ownership | Unchanged |

Expected output keeps:

- `readiness_cache_verified=true`
- `memory_writer_authority_in_rust=false`
- `skills_execution_authority_in_rust=false`
- `ui_product_change=false`
- `node_remains_authority=true`
