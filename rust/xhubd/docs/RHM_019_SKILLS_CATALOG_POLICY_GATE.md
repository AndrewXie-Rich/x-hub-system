# RHM-019 Skills Catalog Policy Gate

Status: implemented 2026-05-06

## Decision

Rust Hub owns a read-only skill catalog and readiness policy gate before it owns
any skill execution. This gives the long-running daemon a stable view of local
skills across devices while keeping execution authority outside Rust until a
separate cutover is approved.

The Rust path does not change XT UI, does not execute third-party code, does
not read provider secrets, and does not grant filesystem/network/model
capabilities by itself.

## Implemented Surface

- `xhubd skills catalog`
- `xhubd skills readiness`
- `GET /skills/catalog`
- `GET /skills/readiness`
- `/ready` fields:
  - `skills.catalog_shadow_http=true`
  - `skills.execution_authority_in_rust=false`
  - `skills.hub_executes_third_party_code=false`
  - `skills.requires_pin_or_grant=true`
  - `capabilities.skills_catalog_http=true`

## Policy Boundary

Rust accepts local manifests only as catalog metadata:

- `SKILL.md`
- `skill.json`

Secret-shaped manifest content is denied with
`manifest_secret_pattern_denied`. The catalog response returns public metadata,
reason codes, and capability tags only. Raw manifest bodies and secret-shaped
fields are not serialized.

## Authority State

| Area | Rust State |
| --- | --- |
| Catalog scan | Enabled |
| Readiness gate | Enabled |
| Skill execution | Disabled |
| Third-party code execution | Disabled |
| Capability grant | Requires future explicit grant/pin |
| XT UI ownership | Unchanged |

## Verification

```bash
cargo test -p xhub-skills
cargo test -p xhubd
bash "tools/skills_catalog_shadow_smoke.command"
bash "tools/skills_catalog_http_smoke.command" --timeout-ms 30000
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
```

The HTTP smoke starts an isolated local `xhubd serve`, validates `/ready`,
`/skills/readiness`, and `/skills/catalog`, then checks a leaky manifest is
blocked without returning the secret value.

## Next Cutover Requirements

Before Rust can execute skills, add separate gates for:

1. signed/pinned skill manifest trust,
2. explicit capability grants,
3. sandbox policy,
4. audit events,
5. timeout and kill-switch behavior,
6. XT fallback behavior,
7. UI preservation review under RHM-015.
