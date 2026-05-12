# RHM-027 Skills Policy Event Audit Trail

Status: implemented 2026-05-06

## Decision

Rust Hub records durable skill policy changes in an append-only event table.
This gives long-running, multi-device deployments a local audit trail for who
added or removed a skill pin or capability grant.

Migration: `migrations/0005_skill_policy_events.sql`

Table:

- `rust_hub_skill_policy_events`

This remains policy-gate evidence only. Rust still does not execute skills,
does not grant OS/network/model access by itself, and does not change XT UI.

## Implemented Commands

```bash
bash "tools/run_rust_hub.command" skills policy-events --scope-key project:demo --skill-id memory-core --limit 20
```

HTTP equivalents:

- `GET /skills/policy-events`
- `GET /skills/policy-audit`

The event list includes operation metadata for:

- `pin`
- `grant`
- `revoke_grant`
- `unpin`

Responses omit stored `detail_json` and keep `detail_json_included=false`.

## Authority State

| Area | Rust State |
| --- | --- |
| Durable policy event storage | Enabled |
| Policy event summary HTTP | Enabled |
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

- pin/grant/revoke-grant/unpin write policy event rows,
- `skills policy-events` returns all four operation types,
- policy event responses do not expose stored `detail_json`,
- Rust still does not execute third-party skill code.
