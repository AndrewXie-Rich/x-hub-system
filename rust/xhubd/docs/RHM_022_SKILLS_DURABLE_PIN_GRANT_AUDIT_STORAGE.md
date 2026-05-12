# RHM-022 Skills Durable Pin Grant Audit Storage

Status: implemented 2026-05-06

## Decision

Rust Hub can persist skill pins, capability grants, and preflight audit previews
in its local SQLite store. This makes skill policy checks stable across daemon
restarts while keeping Rust skill execution authority disabled.

The durable records are still policy-gate evidence. They do not execute skills,
do not grant OS/network/model access by themselves, and do not change XT UI.

## Implemented Storage

Migration: `migrations/0004_skill_policy.sql`

Tables:

- `rust_hub_skill_pins`
- `rust_hub_skill_capability_grants`
- `rust_hub_skill_preflight_audit`

All tables are namespaced under `rust_hub_*` so they can run side-by-side with
the existing Node Hub state.

## Implemented Commands

```bash
bash "tools/run_rust_hub.command" skills pin --scope-key project:demo --skill-id memory-core --actor operator
bash "tools/run_rust_hub.command" skills grant --scope-key project:demo --skill-id memory-core --capability memory --actor operator
bash "tools/run_rust_hub.command" skills policy --scope-key project:demo --skill-id memory-core
bash "tools/run_rust_hub.command" skills preflight --scope-key project:demo --skill-id memory-core --requested-capabilities memory
```

HTTP equivalents:

- `POST /skills/pin`
- `POST /skills/grant`
- `GET /skills/policy`
- `POST /skills/preflight`

`skills preflight` now merges durable SQLite policy with request-local
`pinned_skill_ids` and `granted_capabilities`. Without a pin and grant it still
denies by default.

## Authority State

| Area | Rust State |
| --- | --- |
| Durable skill pin storage | Enabled |
| Durable capability grant storage | Enabled |
| Durable preflight audit preview | Enabled |
| Skill execution | Disabled |
| Third-party code execution | Disabled |
| XT UI ownership | Unchanged |

The response keeps:

- `execution_authority_in_rust=false`
- `hub_executes_third_party_code=false`
- `authority=policy_gate_only`

## Verification

```bash
cargo test -p xhub-db
cargo test -p xhub-skills
cargo test -p xhubd
bash "tools/skills_catalog_shadow_smoke.command"
bash "tools/skills_catalog_http_smoke.command" --timeout-ms 30000
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
```

The skills smokes verify:

- preflight denies before durable pin/grant exists,
- `skills pin` and `skills grant` write SQLite policy records,
- `skills policy` reads the durable records back,
- preflight allows using durable pin/grant without request override lists,
- preflight audit preview remains secret-free and non-executing.
