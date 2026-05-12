# RHM-032 Ops Readiness Gate

Status: implemented 2026-05-07

## Decision

Rust Hub has a packageable operational readiness gate for long-running daemon
checks. The gate starts one temporary warm `xhubd serve` process and performs
repeated HTTP checks against the same daemon instead of relying only on
single-shot command smokes.

This is a diagnostics and packaging gate only. It does not switch production
authority, does not execute third-party skills, does not grant OS/network/model
access, and does not change XT UI.

## Implemented Command

```bash
bash "tools/ops_readiness_gate.command" --cycles 3 --interval-ms 250 --timeout-ms 30000
```

Options:

- `--cycles <n>`: number of repeated readiness cycles.
- `--interval-ms <ms>`: delay between cycles.
- `--timeout-ms <ms>`: startup timeout.
- `--max-endpoint-ms <ms>`: per-endpoint latency budget.
- `--max-cycle-ms <ms>`: per-cycle latency budget.
- `--port <port>`: local temporary HTTP port.

The response schema is:

```text
xhub.rust_hub.ops_readiness_gate.v1
```

## Gate Coverage

The gate verifies:

- `/health` starts successfully for one warm daemon,
- `/ready` remains `ready=true` across repeated cycles,
- immediate repeated `/ready` calls use the short-TTL readiness cache,
- endpoint and cycle latency stay inside the configured budgets,
- memory retrieval readiness is ready,
- memory search returns read-only `xt.memory_retrieval_result.v1`,
- secret-seeking memory queries are denied,
- skills readiness is ready,
- skill policy requires pin/grant,
- durable skill pin/grant/preflight works without Rust skill execution
  authority,
- skill policy store readiness returns
  `xhub.skills_policy_store_readiness.v1`,
- policy store readiness sees active pin/grant and audit rows,
- static UI compatibility gate still reports no product UI changes,
- secret-like fixture values, personal memory text, and `detail_json` are not
  returned.

## Authority State

| Area | Rust State |
| --- | --- |
| Warm daemon ops readiness | Enabled |
| Memory retrieval | Read-only shadow |
| Memory writer authority | Disabled |
| Skill policy gate | Enabled |
| Skill execution | Disabled |
| Third-party code execution | Disabled |
| Cross-network auth gate | Required |
| XT UI ownership | Unchanged |

Expected output keeps:

- `node_remains_authority=true`
- `memory_writer_authority_in_rust=false`
- `skills_execution_authority_in_rust=false`
- `cross_network_auth_gate=true`
- `ui_product_change=false`
- `readiness_cache_verified=true`

## Verification

```bash
bash "tools/ops_readiness_gate.command" --cycles 3 --interval-ms 250 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
bash "tools/skills_catalog_http_smoke.command" --timeout-ms 30000
bash "tools/memory_retrieval_http_smoke.command" --timeout-ms 30000
```

The gate is copied into packaged `dist/rust-hub-*` bundles and can be run from
the package without source files.
