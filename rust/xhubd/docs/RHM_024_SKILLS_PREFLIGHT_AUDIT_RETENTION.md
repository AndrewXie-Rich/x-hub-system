# RHM-024 Skills Preflight Audit Retention

Status: implemented 2026-05-06

## Decision

Rust Hub can summarize and explicitly prune durable skill preflight audit rows.
This prevents the local SQLite audit table from growing without an operator
control path during long-running daemon use.

This remains policy-gate maintenance only. Rust still does not execute skills,
does not grant OS/network/model access by itself, and does not change XT UI.

## Implemented Commands

```bash
bash "tools/run_rust_hub.command" skills audit --scope-key project:demo --skill-id memory-core --limit 20
bash "tools/run_rust_hub.command" skills audit-prune --max-rows 10000
```

HTTP equivalents:

- `GET /skills/audit`
- `POST /skills/audit-prune`

`skills audit` returns summary counts and recent row metadata only. It omits
stored `detail_json` and keeps `detail_json_included=false`.

`skills audit-prune` keeps the newest `max_rows` preflight audit rows and
deletes older rows. The command is explicit; there is no background deletion
loop in this slice.

## Authority State

| Area | Rust State |
| --- | --- |
| Skill preflight audit summary | Enabled |
| Explicit audit retention prune | Enabled |
| Skill execution | Disabled |
| Third-party code execution | Disabled |
| XT UI ownership | Unchanged |

Responses keep:

- `authority=policy_gate_only`
- `execution_authority_in_rust=false`
- `hub_executes_third_party_code=false`

## Verification

```bash
cargo test -p xhub-db -p xhub-skills -p xhubd
bash "tools/skills_catalog_shadow_smoke.command"
bash "tools/skills_catalog_http_smoke.command" --timeout-ms 30000
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
```

The skills smokes verify that:

- preflight writes deny and allow audit rows,
- `skills audit` reports total/allow/deny counts,
- audit responses do not expose stored `detail_json`,
- `skills audit-prune --max-rows 1` bounds retained rows,
- Rust still does not execute third-party skill code.
