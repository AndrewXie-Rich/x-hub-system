# RHM-093 XT File IPC Runtime Adapter Overwrite Gate

## Goal

Prevent the runtime adapter candidate from overwriting an existing XT file IPC
response unless a separate operator gate is explicitly enabled.

This remains fail-closed. Rust does not execute ML, does not write
`hub_status.json`, does not touch live XT directories, and does not become XT
file IPC production authority.

## Behavior

If `ai_responses/resp_<req_id>.jsonl` already exists:

- default request behavior still returns `response_already_exists`;
- request body `overwrite_response: true` returns
  `response_overwrite_not_enabled` unless
  `XHUB_RUST_XT_FILE_IPC_OVERWRITE_RESPONSE=1` is set;
- the existing response file is preserved byte-for-byte;
- `production_authority_change=false`;
- `rust_executes_ml=false`.

The overwrite env gate is intentionally separate from the runtime adapter
candidate gates. This prevents broad adapter-candidate enablement from also
granting permission to replace XT-visible response files.

## Smoke Coverage

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` now covers six
isolated temporary request paths:

- normal fail-closed adapter candidate;
- canceled fail-closed adapter candidate;
- pre-existing response collision;
- explicit overwrite request blocked by the overwrite env gate;
- unsupported request type rejection;
- no selected model route blocker.

## Validation

```bash
cargo test -p xhubd runtime_adapter_candidate
node --check tools/xt_file_ipc_runtime_adapter_candidate_smoke.js
bash tools/xt_file_ipc_runtime_adapter_candidate_smoke.command --timeout-ms 30000
```

This is a production cutover prerequisite for ensuring Rust never erases or
replaces XT response files by accident during shadow/runtime-adapter trials.
