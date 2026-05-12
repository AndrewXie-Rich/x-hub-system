# RHM-020 Model Route Combined Candidate Evidence Report

Status: implemented 2026-05-06

## Goal

Persist one authority-neutral evidence artifact that combines remote paid-model
and local runtime model-route candidate coverage. RHM-017 and RHM-018 proved
the two paths separately; this slice makes the evidence durable so future
authority planning consumes a report file instead of one-off console output.

This runner remains default-off and audit-only:

- Node keeps selecting the execution model.
- Remote Bridge payloads remain Node-selected.
- Local runtime IPC requests remain Node-selected.
- Rust `/model/route` decisions remain candidate evidence only.
- No production model authority changes are made.

## Tool

Added:

```text
tools/model_route_candidate_evidence_runner.js
tools/model_route_candidate_evidence_runner.command
```

The runner executes:

```text
tools/model_route_generate_candidate_runner.command
tools/model_route_local_candidate_runner.command
```

It then writes a JSON report under `reports/` by default.

## Report Contract

The persisted report schema is:

```text
xhub.model_route_candidate_evidence_report.v1
```

Required authority fields:

```json
{
  "production_authority_change": false,
  "authority_mode": "candidate_audit_only"
}
```

The combined readiness schema is:

```text
xhub.model_route_candidate_evidence_readiness.v1
```

Readiness requires:

- remote runner exit code `0`
- local runner exit code `0`
- remote candidate readiness `ready=true`
- local candidate readiness `ready=true`
- configured minimum remote candidate audits
- configured minimum local candidate audits
- zero selected-model mismatches by default
- zero route-kind mismatches by default
- zero candidate fallbacks by default
- zero secret leakage
- Generate latency under the configured threshold

## Commands

Self-test:

```bash
bash "tools/model_route_candidate_evidence_runner.command" --self-test
```

Dry run:

```bash
bash "tools/model_route_candidate_evidence_runner.command" \
  --dry-run \
  --remote-runs 1 \
  --local-runs 1 \
  --concurrency 1 \
  --expect-ready
```

Combined E2E readiness:

```bash
bash "tools/model_route_candidate_evidence_runner.command" \
  --remote-runs 1 \
  --local-runs 1 \
  --concurrency 1 \
  --expect-ready \
  --timeout-ms 45000
```

Observed result 2026-05-06:

- `ok=true`
- `readiness.ready=true`
- `production_authority_change=false`
- `authority_mode=candidate_audit_only`
- remote candidate audits: `1`
- local candidate audits: `1`
- remote selected-model mismatches: `0`
- local selected-model mismatches: `0`
- route-kind mismatches: `0`
- candidate fallbacks: `0`
- secret leakage: `0`
- max Generate latency observed: `76ms`
- report path:
  `reports/model_route_candidate_evidence_20260506T080127Z.json`

## Next Boundary

The next model-route step can consume the persisted report to draft a
default-off selected-model authority plan. The authority switch remains blocked
until the plan has an explicit rollback gate, UI compatibility remains green,
and a larger repeated combined evidence run is available.
