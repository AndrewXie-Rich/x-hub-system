# RHM-088 XT File IPC Runtime Adapter Candidate

## Goal

Add the first writable runtime-adapter candidate for XT file IPC while keeping
execution fail-closed.

This route proves Rust can take an XT request, resolve an adapter from Rust
model-route evidence, and write an XT-readable response file under explicit
temporary-directory gates. It still does not execute ML and does not make Rust
Hub the production XT file IPC authority.

## HTTP Surface

New routes:

```text
POST /xt/file-ipc-shadow/runtime-adapter-candidate
POST /compat/xt-file-ipc-shadow/runtime-adapter-candidate
```

Required gates:

- `XHUB_RUST_XT_FILE_IPC_SHADOW=1`
- `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN=1`
- `XHUB_RUST_XT_FILE_IPC_RUNTIME_ADAPTER_CANDIDATE=1`
- request body has `apply: true`
- `base_dir` is an explicit temporary directory

If any gate is missing, the route returns
`deny_code=runtime_adapter_candidate_blocked` and writes nothing.

## Behavior

When all gates pass, Rust:

1. Reads `ai_requests/req_<req_id>.json`.
2. Reuses the RHM-087 runtime execution plan.
3. Selects an adapter kind such as `local_runtime_file_ipc`.
4. Writes `ai_responses/resp_<req_id>.jsonl`.

The JSONL response is intentionally fail-closed:

```json
{"type":"start","runtime_adapter_candidate":true}
{"type":"done","ok":false,"reason":"rust_runtime_adapter_candidate_not_executing"}
```

Cancel files are still honored as fail-closed cancel observations using
`rust_file_ipc_cancel_observed`.

## Non-Authority Guarantees

The route never:

- writes `hub_status.json`;
- marks `xt_file_ipc_production_surface_ready=true`;
- executes ML;
- starts a live XT watcher;
- touches non-temporary live XT IPC directories by default.

## Smoke

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` starts an isolated
temporary daemon, writes a temporary XT request and local runtime inventory, and
asserts:

- `/ready` exposes `xt_file_ipc_shadow_runtime_adapter_candidate_http`;
- the candidate route writes exactly two JSONL events;
- the `done` event is fail-closed;
- no `hub_status.json` is written;
- production file IPC readiness remains false;
- ML execution remains false.

## Next Boundary

The next step is not production cutover. The next safe step is a real adapter
implementation behind a separate execution gate, with contract tests for
streaming chunks, cancellation, timeouts, runtime failure mapping, and rollback.
