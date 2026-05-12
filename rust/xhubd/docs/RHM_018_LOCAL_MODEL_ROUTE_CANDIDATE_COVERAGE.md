# RHM-018 Local Model Route Candidate Coverage

Status: implemented 2026-05-06

## Goal

Extend RHM-017 candidate evidence from the paid remote Generate path to the
local runtime Generate path. This proves the Rust model-route candidate bridge
can observe local model execution without changing Node-selected local runtime
authority.

This slice remains authority-neutral:

- Node keeps selecting the local execution model.
- Node still writes the local runtime IPC request.
- The simulated local runtime still writes the JSONL response.
- Rust `/model/route` evidence is audit-only.

## Tool

Added:

```text
tools/model_route_local_candidate_runner.js
tools/model_route_local_candidate_runner.command
```

The runner creates an isolated fixture:

- temporary Node Hub DB
- temporary Rust Hub DB
- temporary runtime base dir
- local `models_state.json` containing `local.summary`
- local `ai_runtime_status.json` with `mlx` ready
- isolated Rust `xhubd serve`
- Node `HubAI.Generate` service invoked in-process
- simulated local runtime response over `ai_responses/*.jsonl`

## Evidence Path

Per Generate request:

1. Node resolves `local.summary` as a local model.
2. Node evaluates local task policy and local runtime readiness.
3. Rust model-route candidate bridge calls:

```text
GET /model/readiness?min_compare_reports=0&max_mismatches=0
GET /model/route?...model_id=local.summary&privacy_mode=local-only...
```

4. Node records:

```text
ai.generate.model_route_candidate
```

5. Node writes:

```text
ai_requests/req_<request_id>.json
```

6. The simulated local runtime writes:

```text
ai_responses/resp_<request_id>.jsonl
```

7. The runner verifies:

- Generate completed successfully.
- `done.actual_model_id` remains `local.summary`.
- `done.execution_path` remains `local_runtime`.
- runtime request `model_id` remains `local.summary`.
- Candidate audit schema is `xhub.rust_model_route_candidate.audit.v1`.
- Rust selected model matches Node selected model.
- Rust selected route kind is `local` and matches Node route kind.
- No candidate fallback occurred.
- No secret-shaped material leaked into audit evidence.

## Readiness Output

The runner emits:

```text
xhub.model_route_local_candidate_audit_readiness.v1
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
bash "tools/model_route_local_candidate_runner.command" --self-test
```

Dry run:

```bash
bash "tools/model_route_local_candidate_runner.command" --dry-run --runs 2 --concurrency 1 --expect-ready
```

E2E readiness:

```bash
bash "tools/model_route_local_candidate_runner.command" \
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
- `execution_path=local_runtime`
- max Generate latency observed: `39ms`

## Next Boundary

Remote and local candidate evidence now exist. Before any selected-model
authority switch, add a persisted candidate evidence report artifact and a
combined remote/local readiness runner so cutover planning consumes durable
evidence rather than one-off console output.
