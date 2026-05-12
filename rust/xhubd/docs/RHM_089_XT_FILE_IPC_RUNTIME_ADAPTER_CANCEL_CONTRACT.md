# RHM-089 XT File IPC Runtime Adapter Cancel Contract

## Goal

Extend the runtime adapter candidate evidence with an explicit XT cancel-file
case. This proves Rust observes `ai_cancels/cancel_<req_id>.json` before any
future runtime execution authority can be considered.

This remains fail-closed. Rust still does not execute ML, does not write
`hub_status.json`, does not touch live XT directories, and does not become XT
file IPC production authority.

## Behavior

When all runtime adapter candidate gates are enabled and a cancel marker exists,
`POST /xt/file-ipc-shadow/runtime-adapter-candidate` writes only a
temporary-directory response JSONL:

1. `start`
2. fail-closed `done`

The `done` event reports:

```json
{
  "ok": false,
  "reason": "rust_file_ipc_cancel_observed",
  "runtime_adapter_candidate": true
}
```

The response is intentionally not successful. The candidate path reports:

- `cancel_observed=true`;
- `executes_ml=false`;
- `production_file_ipc_ready=false`;
- `production_authority_change=false`;
- `rust_executes_ml=false`.

## Smoke Coverage

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` now writes two
isolated temporary requests:

- a normal runtime adapter candidate request;
- a canceled runtime adapter candidate request with
  `ai_cancels/cancel_<req_id>.json`.

The smoke asserts both response streams are fail-closed and that the canceled
request uses `rust_file_ipc_cancel_observed`.

## Validation

```bash
cargo test -p xhubd runtime_adapter_candidate
node --check tools/xt_file_ipc_runtime_adapter_candidate_smoke.js
bash tools/xt_file_ipc_runtime_adapter_candidate_smoke.command --timeout-ms 30000
```

This reduces cutover risk before any real execution adapter is allowed.
