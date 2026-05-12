# RHM-092 XT File IPC Runtime Adapter No Selected Model

## Goal

Prove the runtime adapter candidate blocks before any response write when Rust
model routing cannot select a model for an XT file IPC request.

This remains fail-closed. Rust does not execute ML, does not write
`hub_status.json`, does not touch live XT directories, and does not become XT
file IPC production authority.

## Behavior

If the request is otherwise valid but model routing returns no
`selected_model_id`, the runtime adapter candidate returns HTTP 409 with:

```json
{
  "ok": false,
  "wrote": false,
  "deny_code": "runtime_adapter_candidate_blocked",
  "runtime_adapter_candidate": {
    "blockers": ["runtime_execution_plan_not_candidate"]
  },
  "runtime_execution_plan": {
    "execution_adapter_plan": {
      "blockers": ["model_route_no_selected_model"]
    }
  }
}
```

No `ai_responses/resp_<req_id>.jsonl` is written. The authority block remains
unchanged:

- `production_authority_change=false`;
- `rust_executes_ml=false`;
- `memory_writer_authority_in_rust=false`;
- `rust_executes_third_party_skills=false`.

## Smoke Coverage

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` now covers five
isolated temporary request paths:

- normal fail-closed adapter candidate;
- canceled fail-closed adapter candidate;
- pre-existing response collision;
- unsupported request type rejection;
- no selected model route blocker.

The no-selected-model case uses a separate temporary IPC directory with no
runtime model inventory, so the test proves no response is written when routing
is not ready.

## Validation

```bash
cargo test -p xhubd runtime_adapter_candidate
node --check tools/xt_file_ipc_runtime_adapter_candidate_smoke.js
bash tools/xt_file_ipc_runtime_adapter_candidate_smoke.command --timeout-ms 30000
```

This is a production cutover prerequisite for avoiding stuck or misleading XT
file IPC responses when local runtime inventory is missing or stale.
