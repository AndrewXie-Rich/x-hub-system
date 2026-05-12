# RHM-029 Skills Policy Event Retention

Status: implemented 2026-05-06

## Decision

Rust Hub can explicitly prune durable skill policy event rows while keeping the
newest events. This gives long-running deployments an operator-controlled
maintenance path for `rust_hub_skill_policy_events`.

The command is explicit only. There is no background deletion loop in this
slice.

This remains policy-gate evidence maintenance only. Rust still does not execute
skills, does not grant OS/network/model access by itself, and does not change
XT UI.

## Implemented Commands

```bash
bash "tools/run_rust_hub.command" skills policy-events-prune --max-rows 10000
```

HTTP equivalents:

- `POST /skills/policy-events-prune`
- `POST /skills/policy-audit-prune`

`skills policy-events-prune` keeps the newest `max_rows` policy event rows and
deletes older rows. Responses omit stored `detail_json` and keep
`detail_json_included=false`.

## Authority State

| Area | Rust State |
| --- | --- |
| Durable policy event retention prune | Enabled |
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

- policy event rows are recorded for pin/grant/revoke-grant/unpin,
- `policy-events-prune --max-rows 2` keeps two newest rows,
- prune responses do not expose stored `detail_json`,
- Rust still does not execute third-party skill code.
