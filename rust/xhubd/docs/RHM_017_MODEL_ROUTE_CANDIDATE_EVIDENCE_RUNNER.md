# RHM-017 Model Route Candidate Evidence Runner

Status: implemented 2026-05-06

## Goal

Add sustained E2E evidence for the RHM-016 default-off model route authority
prep bridge. The runner proves Node `HubAI.Generate` can collect Rust
`/model/route` candidate evidence without changing execution authority.

This runner is still authority-neutral:

- Node keeps selecting the execution model.
- XT UI behavior is unchanged.
- The fake Bridge receives the same Node-selected paid model and provider key
  payload.
- Rust route evidence is audit-only.

## Tool

Added:

```text
tools/model_route_generate_candidate_runner.js
tools/model_route_generate_candidate_runner.command
```

The runner creates an isolated fixture:

- temporary Node Hub DB
- temporary Rust Hub DB
- temporary runtime base dir
- temporary fake Bridge IPC dir
- isolated Rust `xhubd serve` on a caller-selected or generated port
- Node `HubAI.Generate` service invoked in-process
- Node `rust_model_route_authority_bridge.js` configured HTTP-first against the
  isolated Rust daemon

## Evidence Path

Per Generate request:

1. Node resolves the requested paid model.
2. Node resolves the provider key from the isolated provider store.
3. Rust model-route candidate bridge calls:

```text
GET /model/readiness?min_compare_reports=0&max_mismatches=0
GET /model/route?...model_id=<node-selected-model>...
```

4. Node records:

```text
ai.generate.model_route_candidate
```

5. The fake Bridge returns a successful paid-model response.
6. The runner verifies:

- Generate completed successfully.
- `done.actual_model_id` remains the Node-selected model.
- `done.execution_path` remains `remote_model`.
- Bridge payload model and provider key remain Node-selected.
- Candidate audit schema is `xhub.rust_model_route_candidate.audit.v1`.
- Rust selected model matches Node selected model.
- Rust selected route kind matches Node selected route kind.
- No candidate fallback occurred.
- No provider secret material leaked into audit evidence.

## Readiness Output

The runner emits:

```text
xhub.model_route_candidate_audit_readiness.v1
```

Readiness checks:

- `candidate_audit_min_events`
- `candidate_audit_missing`
- `candidate_audit_schema`
- `candidate_audit_not_ok`
- `candidate_audit_model_mismatch`
- `candidate_audit_route_kind_mismatch`
- `candidate_audit_match_unknown`
- `candidate_audit_fallback`
- `candidate_audit_secret_leak`
- `generate_latency_max_ms`

## Commands

Self-test:

```bash
bash "tools/model_route_generate_candidate_runner.command" --self-test
```

Dry run:

```bash
bash "tools/model_route_generate_candidate_runner.command" --dry-run --runs 2 --concurrency 1 --expect-ready
```

E2E readiness:

```bash
bash "tools/model_route_generate_candidate_runner.command" \
  --runs 2 \
  --concurrency 1 \
  --expect-ready \
  --min-candidate-audits 2 \
  --timeout-ms 45000
```

Observed result 2026-05-06:

- `ok=true`
- `candidate_readiness.ready=true`
- `candidate_audit_count=2`
- `model_mismatch=0`
- `route_kind_mismatch=0`
- `fallback=0`
- `secret_leak=0`
- `generate_ok=true`
- max Generate latency observed: `75ms`

## Next Boundary

Before model route authority can switch from candidate audit to selected-model
authority, add one more runner slice for local runtime route evidence or a
larger repeated remote candidate run with a persisted report artifact. The
authority switch remains blocked until RHM-015 UI compatibility gates and the
candidate readiness gate are both green.
