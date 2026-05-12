# RHM-031 Model Route Report Diagnostics

Status: implemented 2026-05-06

## Goal

Expose the latest model-route authority-plan, prep-trial, sustained-prep, and
candidate-evidence reports through a read-only diagnostics surface. This gives
XT and the Rust Hub browser page one stable place to inspect route cutover
evidence without changing execution behavior.

This surface remains non-production:

- Rust selected model output does not override Node `done.actual_model_id`.
- Remote Bridge payload `model_id` and provider account remain Node-selected.
- Local runtime `ai_requests/*.json` `model_id` remains Node-selected.
- Diagnostics reads report files under `reports/` only.
- Diagnostics returns sanitized summaries, not raw runner stderr or env blocks.
- Production selected-model authority remains disabled.

## Surfaces

Added CLI:

```bash
cargo run --bin xhubd -- model diagnostics --limit 1
```

Added HTTP:

```text
GET /model/diagnostics?limit=1
GET /model/route-diagnostics?limit=1
```

Added readiness capability:

```json
{
  "capabilities": {
    "model_route_diagnostics_http": true
  }
}
```

The browser status page now links to:

```text
/model/diagnostics
```

## Contract

The diagnostics schema is:

```text
xhub.model_route_diagnostics.v1
```

Required authority fields:

```json
{
  "read_only": true,
  "diagnostics_only": true,
  "production_authority_change": false,
  "selected_model_authority_enabled": false
}
```

Readiness requires:

- `reports/` exists
- latest authority-plan report exists and is ready
- latest prep-trial report exists and is ready
- latest sustained-prep report exists and is ready
- zero observed production authority changes
- zero observed selected-model authority enablement
- zero observed Node authority preservation failures

Candidate evidence is included when present, but it is not a blocking
diagnostics readiness dependency because the authority-plan already references
candidate evidence.

## Sanitization

Diagnostics intentionally returns summaries only:

- report kind, schema, filename, relative report path, generated time
- readiness decision and selected safe readiness metrics
- authority-mode and authority-neutral flags

It does not return:

- raw `required_env_for_manual_prep_trial`
- raw `env_to_unset_for_rollback`
- raw runner `stderr`
- provider API keys, OAuth tokens, or secret-shaped fields

## Observed Result

Observed result 2026-05-06:

- CLI `model diagnostics --limit 1`: `ready=true`
- HTTP `/model/diagnostics?limit=1`: `ready=true`
- `/ready` capability `model_route_diagnostics_http=true`
- browser `/` contains `Model Diagnostics`
- latest authority plan:
  `reports/model_route_authority_plan_20260506T123610Z.json`
- latest prep trial:
  `reports/model_route_prep_trial_20260506T133254Z.json`
- latest sustained prep:
  `reports/model_route_prep_sustained_20260506T135350Z.json`
- `production_authority_change=false`
- `selected_model_authority_enabled=false`
- `node_authority_failures=0`

## Next Boundary

The next step can wire XT to consume `/model/diagnostics` as a read-only
status panel. XT must not use diagnostics output to change selected model,
provider account routing, local runtime IPC payloads, or Generate execution
authority.
