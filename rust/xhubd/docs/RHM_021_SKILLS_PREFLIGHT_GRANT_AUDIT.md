# RHM-021 Skills Preflight Grant Audit

Status: implemented 2026-05-06

## Decision

Rust Hub can evaluate a skill request before execution, but it still does not
execute third-party skill code. The preflight gate is fail-closed and produces a
secret-free audit preview for future Node/XT integration.

## Implemented Surface

- `xhubd skills preflight`
- `xhubd skills pin`
- `xhubd skills grant`
- `xhubd skills policy`
- `POST /skills/preflight`
- `POST /skills/pin`
- `POST /skills/grant`
- `GET /skills/policy`
- query-string support for diagnostic `GET /skills/preflight`
- `/ready` fields:
  - `skills.preflight_shadow_http=true`
  - `skills.preflight_schema=xhub.skills_preflight.v1`
  - `skills.preflight_audit_schema=xhub.skills_preflight.audit.v1`
  - `capabilities.skills_preflight_http=true`

## Policy Rules

The preflight decision returns `allow` only when all of these are true:

1. the skills catalog is ready,
2. the target skill exists,
3. the target skill is not blocked,
4. the skill is explicitly pinned,
5. every requested capability is declared by the skill manifest,
6. every requested capability is explicitly granted,
7. no request field contains secret-shaped content.

Any failure returns `deny` with machine-readable reason codes such as:

- `skill_pin_required`
- `capability_grant_required`
- `capability_not_declared`
- `skill_not_found`
- `skill_blocked`
- `skills_catalog_not_ready`
- `preflight_secret_pattern_denied`

## Authority State

| Area | Rust State |
| --- | --- |
| Skill catalog | Enabled |
| Skill readiness | Enabled |
| Skill request preflight | Enabled |
| Audit preview | Enabled |
| Skill execution | Disabled |
| Capability grant storage | Durable shadow policy, not execution authority |
| XT UI ownership | Unchanged |

The response always keeps:

- `execution_authority_in_rust=false`
- `hub_executes_third_party_code=false`
- `requires_pin_or_grant=true`

## Verification

```bash
cargo test -p xhub-skills
cargo test -p xhubd
bash "tools/skills_catalog_shadow_smoke.command"
bash "tools/skills_catalog_http_smoke.command" --timeout-ms 30000
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
```

The skills smokes now verify both preflight denial without pin/grant and
preflight allow with explicit pin and capability grant. The HTTP smoke starts an
isolated warm daemon and confirms the process is cleaned up afterwards.

## Next Cutover Requirements

Before this can influence production skill execution:

1. persist signed pin/grant records in durable storage,
2. verify skill signatures or local trust roots,
3. write real audit events through Hub audit storage,
4. add sandbox policy and kill-switch enforcement,
5. wire Node/XT only behind default-off flags,
6. keep XT UI unchanged under RHM-015.
