# RHM-026 Model Route Prep Trial Smoke

Status: implemented 2026-05-06

## Goal

Run a default-off model-route prep trial against Node `HubAI.Generate` while
proving execution authority stays with Node. This is the first smoke that
enables:

```text
XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP=1
```

The trial remains non-production:

- Rust selected model output does not override Node `done.actual_model_id`.
- Remote Bridge payload `model_id` and provider account remain Node-selected.
- Local runtime `ai_requests/*.json` `model_id` remains Node-selected.
- Candidate audit mode is disabled for this trial so the services path reaches
  `prepRoute`.
- Production selected-model authority remains disabled.

## Tools

Added:

```text
tools/model_route_prep_trial_runner.js
tools/model_route_prep_trial_runner.command
```

Extended:

```text
tools/model_route_generate_candidate_runner.js --prep-trial
tools/model_route_local_candidate_runner.js --prep-trial
```

## Report Contract

The persisted report schema is:

```text
xhub.model_route_prep_trial_report.v1
```

Required authority fields:

```json
{
  "production_authority_change": false,
  "selected_model_authority_enabled": false,
  "authority_mode": "prep_trial_only",
  "node_remains_model_selection_authority": true,
  "bridge_payload_model_authority_remains_node": true,
  "local_runtime_ipc_model_authority_remains_node": true
}
```

Readiness schema:

```text
xhub.model_route_prep_trial_readiness.v1
```

Readiness requires remote and local prep runners to pass, remote and local
`prep match` counts to meet threshold, prep warnings to stay at zero, remote
Bridge payload authority to remain Node-selected, local runtime IPC authority
to remain Node-selected, and production selected-model authority to remain
disabled.

## Commands

Remote prep path:

```bash
bash "tools/model_route_generate_candidate_runner.command" \
  --prep-trial \
  --runs 1 \
  --concurrency 1 \
  --expect-ready \
  --min-prep-matches 1 \
  --timeout-ms 45000
```

Local prep path:

```bash
bash "tools/model_route_local_candidate_runner.command" \
  --prep-trial \
  --runs 1 \
  --concurrency 1 \
  --expect-ready \
  --min-prep-matches 1 \
  --timeout-ms 45000
```

Combined prep trial:

```bash
bash "tools/model_route_prep_trial_runner.command" \
  --remote-runs 1 \
  --local-runs 1 \
  --concurrency 1 \
  --expect-ready \
  --timeout-ms 45000
```

Observed result 2026-05-06:

- `ok=true`
- `readiness.ready=true`
- remote prep matches: `1`
- local prep matches: `1`
- prep warnings: `0`
- remote Node authority preserved: `true`
- local Node authority preserved: `true`
- `production_authority_change=false`
- `selected_model_authority_enabled=false`
- report path:
  `reports/model_route_prep_trial_20260506T133254Z.json`

## Next Boundary

The next step can repeat the prep trial with a larger run count and then add an
XT-facing diagnostics surface for the latest plan/prep report. Production
selected-model authority should remain blocked until a separate explicit
cutover task changes the Node/XT contract.
