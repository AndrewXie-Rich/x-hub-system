# RHM-025 Skills Policy Revocation

Status: implemented 2026-05-06

## Decision

Rust Hub can revoke durable skill pins and capability grants. This closes the
long-running operations gap where policy could be added but not removed.

Revocation uses the existing `revoked_at_ms` columns from
`migrations/0004_skill_policy.sql`. No new schema migration is required.

This remains policy-gate maintenance only. Rust still does not execute skills,
does not grant OS/network/model access by itself, and does not change XT UI.

## Implemented Commands

```bash
bash "tools/run_rust_hub.command" skills unpin --scope-key project:demo --skill-id memory-core --actor operator
bash "tools/run_rust_hub.command" skills revoke-grant --scope-key project:demo --skill-id memory-core --capability memory --actor operator
```

HTTP equivalents:

- `POST /skills/unpin`
- `POST /skills/revoke-pin`
- `POST /skills/revoke-grant`

`skills policy` and `skills preflight` only consider records with
`revoked_at_ms=0`. After revocation, preflight returns to fail-closed deny
until the pin/grant is explicitly added again.

## Authority State

| Area | Rust State |
| --- | --- |
| Durable skill pin revoke | Enabled |
| Durable capability grant revoke | Enabled |
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

- durable pin/grant allows preflight,
- durable grant revoke and pin revoke both update policy state,
- `skills policy` no longer reports active pin/grant after revocation,
- preflight denies again after revocation,
- Rust still does not execute third-party skill code.
