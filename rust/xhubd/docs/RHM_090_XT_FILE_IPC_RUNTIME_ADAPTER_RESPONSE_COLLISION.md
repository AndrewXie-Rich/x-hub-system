# RHM-090 XT File IPC Runtime Adapter Response Collision

## Goal

Prove the runtime adapter candidate will not overwrite an existing XT response
file by default. This protects responses already written by XT, the classic
Hub, Node, or an earlier Rust shadow run.

This remains fail-closed. Rust does not execute ML, does not write
`hub_status.json`, does not touch live XT directories, and does not become XT
file IPC production authority.

## Behavior

When `ai_responses/resp_<req_id>.jsonl` already exists and
`overwrite_response` is not explicitly true, the runtime adapter candidate
returns:

```json
{
  "ok": false,
  "wrote": false,
  "deny_code": "response_already_exists"
}
```

The existing response file is preserved byte-for-byte. The authority block
continues to report:

- `production_authority_change=false`;
- `rust_executes_ml=false`;
- `memory_writer_authority_in_rust=false`;
- `rust_executes_third_party_skills=false`.

## Smoke Coverage

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` now covers three
isolated temporary requests:

- normal fail-closed adapter candidate;
- canceled fail-closed adapter candidate;
- pre-existing response collision that must not modify the existing response.

## Validation

```bash
cargo test -p xhubd runtime_adapter_candidate
node --check tools/xt_file_ipc_runtime_adapter_candidate_smoke.js
bash tools/xt_file_ipc_runtime_adapter_candidate_smoke.command --timeout-ms 30000
```

This is a production cutover prerequisite for safe retry and resume behavior.
