# RHM-030 Skills Policy Store Readiness

Status: implemented 2026-05-06

## Decision

Rust Hub can summarize durable skill policy storage health without exposing
stored audit details. This gives long-running daemon deployments a lightweight
readiness and maintenance signal for active pins, active grants, preflight
audit rows, and policy event rows.

This slice adds read-only diagnostics only. It does not add a background prune
loop, does not execute skills, does not grant OS/network/model access by
itself, and does not change XT UI.

## Implemented Commands

```bash
bash "tools/run_rust_hub.command" skills policy-readiness --max-preflight-audit-rows 100000 --max-policy-event-rows 100000
```

Aliases:

- `skills policy-maintenance`
- `skills maintenance`

HTTP equivalents:

- `GET /skills/policy-readiness`
- `POST /skills/policy-readiness`
- `GET /skills/policy-maintenance`
- `POST /skills/policy-maintenance`

Supported thresholds:

- CLI: `--max-preflight-audit-rows`, `--max-policy-event-rows`
- HTTP query/body: `max_preflight_audit_rows`,
  `max_policy_event_rows`
- HTTP camelCase body aliases: `maxPreflightAuditRows`,
  `maxPolicyEventRows`

The response schema is `xhub.skills_policy_store_readiness.v1`.

It reports:

- active pin count,
- active grant count,
- preflight audit row count,
- policy event row count,
- latest preflight audit timestamp,
- latest policy event timestamp,
- configured maintenance thresholds,
- readiness issue codes when row counts exceed thresholds.

Responses keep `detail_json_included=false`; stored audit and policy-event
detail payloads are not returned.

## Authority State

| Area | Rust State |
| --- | --- |
| Skill policy store readiness | Enabled |
| Explicit policy maintenance signal | Enabled |
| Automatic prune loop | Disabled |
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
bash "tools/memory_retrieval_http_smoke.command" --timeout-ms 30000
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
```

The skills smokes verify that:

- policy-readiness returns the expected schema,
- row counts include durable pin/grant, preflight audit, and policy events,
- thresholds drive `ready=true|false` without changing execution authority,
- responses do not expose stored `detail_json`,
- Rust still does not execute third-party skill code.
