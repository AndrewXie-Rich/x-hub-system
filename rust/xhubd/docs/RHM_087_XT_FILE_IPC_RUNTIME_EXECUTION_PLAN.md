# RHM-087 XT File IPC Runtime Execution Plan

## Goal

Add a shadow-only bridge from an XT file IPC request to Rust model-route
selection, so Rust can prove which runtime adapter it would use before it is
allowed to execute anything.

This does not execute ML, does not write `resp_<req_id>.jsonl`, does not write
`hub_status.json`, and does not mark Rust Hub as XT file IPC production
authority.

## HTTP Surface

New routes:

```text
POST /xt/file-ipc-shadow/runtime-execution-plan
POST /compat/xt-file-ipc-shadow/runtime-execution-plan
```

The route accepts:

```json
{
  "base_dir": "/tmp/isolated-xt-ipc",
  "runtime_base_dir": "/tmp/isolated-runtime",
  "req_id": "request-id"
}
```

It is bounded by the same shadow rules as the rest of XT file IPC:

- `base_dir` must be an explicit temporary directory;
- `XHUB_RUST_XT_FILE_IPC_SHADOW=1` is required;
- no live XT directories are touched by default;
- no response or status authority files are written.

## Plan Output

The response includes:

- normalized XT request contract;
- Rust `xhub.model_route_decision.v1`;
- `execution_adapter_plan`.

`execution_adapter_plan` reports:

- `adapter_kind`: `local_runtime_file_ipc`, `remote_provider_route`, or `none`;
- `selected_route_kind`;
- `selected_model_id`;
- `dry_run_candidate`;
- `production_candidate`;
- blockers for missing runtime/cutover gates.

`production_candidate` only becomes true when all explicit gates are present:

- `XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN=1`;
- model route selects a model;
- `XHUB_RUST_XT_FILE_IPC_RUNTIME_READY=1`;
- `XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER=1`.

Even then, this route itself still does not execute. It only reports the plan.

## Smoke

`tools/xt_file_ipc_runtime_execution_plan_smoke.command` starts an isolated
temporary daemon, writes a temporary XT request plus local runtime inventory, and
asserts:

- `/ready` exposes `xt_file_ipc_shadow_runtime_execution_plan_http`;
- model route selects the local fixture model;
- `dry_run_candidate=true`;
- `production_candidate=false`;
- no response JSONL is written;
- no `hub_status.json` is written;
- production file IPC readiness stays false;
- ML execution stays false.

## Next Boundary

The next step is a real execution adapter candidate behind separate gates. It
must keep the same rollback contract and must not be enabled for live XT until
response streaming, cancellation, runtime failures, and timeout behavior are
contract-tested end to end.
