# RHM-028 Model Route Prep Sustained Evidence

Status: implemented 2026-05-06

## Goal

Repeat the RHM-026 model-route prep trial across multiple cycles and persist a
single sustained-readiness artifact. This adds confidence before any XT-facing
diagnostics or selected-model authority cutover work, while keeping the system
authority-neutral.

This runner remains non-production:

- Rust selected model output does not override Node `done.actual_model_id`.
- Remote Bridge payload `model_id` and provider account remain Node-selected.
- Local runtime `ai_requests/*.json` `model_id` remains Node-selected.
- Each cycle writes its own RHM-026 prep-trial report.
- The sustained report only summarizes evidence and readiness.
- Production selected-model authority remains disabled.

## Tool

Added:

```text
tools/model_route_prep_sustained_runner.js
tools/model_route_prep_sustained_runner.command
```

The runner repeatedly executes:

```text
tools/model_route_prep_trial_runner.command
```

Each cycle gets a stable child report path under:

```text
reports/model_route_prep_sustained_<stamp>_cycles/
```

The sustained summary report is written under `reports/` by default.

## Report Contract

The persisted sustained report schema is:

```text
xhub.model_route_prep_sustained_report.v1
```

Required authority fields:

```json
{
  "production_authority_change": false,
  "selected_model_authority_enabled": false,
  "authority_mode": "prep_sustained_diagnostic_only",
  "node_remains_model_selection_authority": true,
  "bridge_payload_model_authority_remains_node": true,
  "local_runtime_ipc_model_authority_remains_node": true
}
```

Readiness schema:

```text
xhub.model_route_prep_sustained_readiness.v1
```

Readiness requires:

- every configured cycle to run
- ready cycle count to meet `min_ready_cycles`
- failed cycle count to stay within `max_failed_cycles`
- total remote prep matches to meet threshold
- total local prep matches to meet threshold
- total prep warnings to stay within threshold
- per-cycle Generate latency to stay within threshold
- every child RHM-026 report to exist
- zero production authority changes
- zero selected-model authority enablement
- Node-selected remote and local execution authority to remain preserved

## Commands

Self-test:

```bash
bash "tools/model_route_prep_sustained_runner.command" --self-test
```

Dry run:

```bash
bash "tools/model_route_prep_sustained_runner.command" \
  --dry-run \
  --cycles 2 \
  --remote-runs 1 \
  --local-runs 1 \
  --concurrency 1 \
  --expect-ready
```

Sustained prep evidence:

```bash
bash "tools/model_route_prep_sustained_runner.command" \
  --cycles 2 \
  --remote-runs 1 \
  --local-runs 1 \
  --concurrency 1 \
  --expect-ready \
  --timeout-ms 45000
```

Observed result 2026-05-06:

- `ok=true`
- `readiness.ready=true`
- ready cycles: `2`
- failed cycles: `0`
- total remote prep matches: `2`
- total local prep matches: `2`
- total prep warnings: `0`
- Node authority failures: `0`
- max Generate latency observed: `76ms`
- `production_authority_change=false`
- `selected_model_authority_enabled=false`
- report path:
  `reports/model_route_prep_sustained_20260506T135350Z.json`
- child report paths:
  `reports/model_route_prep_sustained_20260506T135350Z_cycles/cycle_001.json`
  and
  `reports/model_route_prep_sustained_20260506T135350Z_cycles/cycle_002.json`

## Next Boundary

The next step can expose the latest plan/prep/sustained report through a
read-only diagnostics surface for XT and the browser status page. That surface
must not change Generate execution behavior, selected-model authority, provider
account selection, or local runtime IPC payloads.
