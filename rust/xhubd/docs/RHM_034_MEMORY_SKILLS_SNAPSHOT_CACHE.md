# RHM-034 Memory Skills Snapshot Cache

Status: implemented 2026-05-07

## Decision

Rust Hub caches read-only memory index snapshots and skills catalog scans for a
short process-local TTL while `xhubd serve` is running. This reduces repeated
disk scans when XT, browser diagnostics, or Node bridge probes hit memory and
skills readiness paths in bursts.

This is a stutter-control optimization only. It does not cache mutating skill
policy routes, does not execute skills, does not grant OS/network/model access,
and does not change XT UI.

## Runtime Behavior

Default TTLs:

```text
XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS=500
XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS=500
```

Allowed range:

```text
0..10000 ms
```

`0` disables the related cache.

Cached read-only memory surfaces:

```text
GET /memory/readiness
GET /memory/search
POST /memory/retrieve
```

Cached read-only skills surfaces:

```text
GET /skills/catalog
GET /skills/readiness
```

Not cached:

```text
POST /skills/pin
POST /skills/grant
POST /skills/unpin
POST /skills/revoke-grant
GET/POST /skills/policy
GET/POST /skills/policy-events
POST /skills/*-prune
POST /skills/preflight
```

Memory retrieval remains fail-closed. If a memory scan fails, retrieval returns
the same deny path as the uncached scanner.

## Readiness Signal

`/ready` reports:

```json
{
  "performance": {
    "memory_snapshot_cache_ttl_ms": 500,
    "skills_catalog_cache_ttl_ms": 500,
    "read_only_snapshot_cache_scope": "process_memory"
  },
  "capabilities": {
    "memory_snapshot_cache_http": true,
    "skills_catalog_cache_http": true
  }
}
```

## Gate Coverage

`tools/ops_readiness_gate.command` verifies:

- memory snapshot cache capability is present,
- skills catalog cache capability is present,
- immediate repeated memory readiness is stable inside the TTL,
- immediate repeated skills readiness is stable inside the TTL,
- endpoint and cycle latency budgets still pass,
- memory writer authority remains disabled,
- skill execution authority remains disabled,
- UI compatibility remains unchanged.

Recommended gate:

```bash
bash "tools/ops_readiness_gate.command" --cycles 3 --interval-ms 250 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
```

## Authority State

| Area | Rust State |
| --- | --- |
| Memory snapshot cache | Enabled |
| Skills catalog cache | Enabled |
| Skill policy mutation cache | Disabled |
| Memory writer authority | Disabled |
| Skill execution authority | Disabled |
| XT UI ownership | Unchanged |

Expected output keeps:

- `memory_snapshot_cache_verified=true`
- `skills_catalog_cache_verified=true`
- `memory_writer_authority_in_rust=false`
- `skills_execution_authority_in_rust=false`
- `ui_product_change=false`
