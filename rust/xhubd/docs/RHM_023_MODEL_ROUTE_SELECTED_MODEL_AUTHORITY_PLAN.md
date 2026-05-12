# RHM-023 Model Route Selected-Model Authority Plan

Status: implemented 2026-05-06

## Goal

Turn the persisted RHM-020 remote/local model-route candidate evidence into a
default-off selected-model authority plan. This is not a production authority
switch. It is a durable dry-run artifact that says whether a manual prep trial
is ready, which environment variables would be needed, and how to roll back.

The plan remains authority-neutral:

- Node keeps selecting `done.actual_model_id`.
- Remote Bridge payload `model_id` remains Node-selected.
- Local runtime `ai_requests/*.json` `model_id` remains Node-selected.
- Rust `/model/route` output is used only for prep/candidate comparison.
- The Node/Rust selected model and route-kind match gate remains required.

## Tool

Added:

```text
tools/model_route_authority_plan_runner.js
tools/model_route_authority_plan_runner.command
```

The runner executes:

```text
tools/model_route_candidate_evidence_runner.command
```

It then writes a plan JSON under `reports/` by default.

## Plan Contract

The persisted plan schema is:

```text
xhub.model_route_selected_model_authority_dry_run_plan.v1
```

Required authority fields:

```json
{
  "mode": "dry_run_only",
  "production_authority_change": false,
  "node_remains_model_selection_authority": true,
  "bridge_payload_model_authority_remains_node": true,
  "local_runtime_ipc_model_authority_remains_node": true,
  "production_cutover_implemented": false,
  "selected_model_authority_enabled": false
}
```

Readiness requires:

- combined candidate evidence runner exit code `0`
- combined candidate evidence readiness `ready=true`
- persisted candidate evidence report exists
- remote candidate path ready
- local candidate path ready
- production selected-model authority remains disabled
- Node/Rust selected model and route-kind match gate remains required

## Commands

Self-test:

```bash
bash "tools/model_route_authority_plan_runner.command" --self-test
```

Dry run:

```bash
bash "tools/model_route_authority_plan_runner.command" \
  --dry-run \
  --remote-runs 1 \
  --local-runs 1 \
  --concurrency 1 \
  --expect-ready
```

E2E plan:

```bash
bash "tools/model_route_authority_plan_runner.command" \
  --remote-runs 1 \
  --local-runs 1 \
  --concurrency 1 \
  --expect-ready \
  --timeout-ms 45000
```

Observed result 2026-05-06:

- `ok=true`
- `plan.ready=true`
- `decision=ready_for_manual_prep_trial`
- `production_authority_change=false`
- `selected_model_authority_enabled=false`
- remote candidate audits: `1`
- local candidate audits: `1`
- selected-model mismatches: `0`
- route-kind mismatches: `0`
- candidate fallbacks: `0`
- secret leakage: `0`
- plan path:
  `reports/model_route_authority_plan_20260506T123610Z.json`
- evidence report path:
  `reports/model_route_candidate_evidence_20260506T123610Z.json`

## Manual Prep Trial Boundary

When the plan is ready, it may list environment variables for a manual prep
trial, including:

```text
XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP=1
XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE=1
XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP=1
XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY=1
XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH=1
XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR=1
```

These variables enable readiness-gated prep/candidate comparison only. They do
not allow Rust selected model output to override Node execution authority.

Rollback is unsetting every `XHUB_RUST_MODEL_ROUTE_AUTHORITY_*` variable listed
in `env_to_unset_for_rollback`.

## Next Boundary

The next step can add a manual prep-trial smoke that starts a warm Rust daemon,
runs Node `HubAI.Generate` with `XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP=1`, and
verifies the generated plan stays true: Node-selected remote and local models
remain the execution authority while Rust prep evidence matches.
