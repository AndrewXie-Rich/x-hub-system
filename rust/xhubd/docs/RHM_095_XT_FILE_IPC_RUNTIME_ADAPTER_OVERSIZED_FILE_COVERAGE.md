# RHM-095 XT File IPC Runtime Adapter Oversized File Coverage

## Goal

Prove the runtime adapter candidate rejects oversized XT request JSON files
before parsing, so malformed or unexpectedly large files cannot create memory
pressure or UI stalls.

This remains fail-closed. Rust does not execute ML, does not write
`hub_status.json`, does not touch live XT directories, and does not become XT
file IPC production authority.

## Behavior

Request JSON files larger than 1 MiB return:

```json
{
  "ok": false,
  "wrote": false,
  "deny_code": "request_file_too_large"
}
```

The file is rejected from metadata before `read_to_string` and JSON parsing. No
`ai_responses/resp_<req_id>.jsonl` is written.

The authority block remains unchanged:

- `production_authority_change=false`;
- `rust_executes_ml=false`;
- `memory_writer_authority_in_rust=false`;
- `rust_executes_third_party_skills=false`.

## Smoke Coverage

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` now covers eight
isolated temporary request paths:

- normal fail-closed adapter candidate;
- canceled fail-closed adapter candidate;
- pre-existing response collision;
- explicit overwrite request blocked by the overwrite env gate;
- unsupported request type rejection;
- no selected model route blocker;
- oversized prompt rejection;
- oversized request file rejection.

## Validation

```bash
cargo test -p xhubd runtime_adapter_candidate
node --check tools/xt_file_ipc_runtime_adapter_candidate_smoke.js
bash tools/xt_file_ipc_runtime_adapter_candidate_smoke.command --timeout-ms 30000
```

This is a production cutover prerequisite for avoiding memory spikes from large
XT file IPC payloads.
