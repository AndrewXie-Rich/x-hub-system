# RHM-091 XT File IPC Runtime Adapter Unsupported Request

## Goal

Prove the runtime adapter candidate rejects unsupported XT request types before
any response write or execution attempt.

This remains fail-closed. Rust does not execute ML, does not write
`hub_status.json`, does not touch live XT directories, and does not become XT
file IPC production authority.

## Behavior

The runtime adapter candidate only accepts XT `generate` requests. If a request
has another `type`, such as `embed`, it returns:

```json
{
  "ok": false,
  "wrote": false,
  "deny_code": "unsupported_request_type"
}
```

No `ai_responses/resp_<req_id>.jsonl` is written. The authority block remains
unchanged:

- `production_authority_change=false`;
- `rust_executes_ml=false`;
- `memory_writer_authority_in_rust=false`;
- `rust_executes_third_party_skills=false`.

## Smoke Coverage

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` now covers four
isolated temporary requests:

- normal fail-closed adapter candidate;
- canceled fail-closed adapter candidate;
- pre-existing response collision;
- unsupported request type rejection.

## Validation

```bash
cargo test -p xhubd runtime_adapter_candidate
node --check tools/xt_file_ipc_runtime_adapter_candidate_smoke.js
bash tools/xt_file_ipc_runtime_adapter_candidate_smoke.command --timeout-ms 30000
```

This is a production cutover prerequisite for keeping non-generation workflows
out of the file IPC generation adapter.
