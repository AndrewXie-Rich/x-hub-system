# RHM-094 XT File IPC Runtime Adapter Input Size Guard

## Goal

Bound XT file IPC runtime adapter candidate input size so malformed or oversized
requests cannot consume unbounded memory or make the UI appear stuck.

This remains fail-closed. Rust does not execute ML, does not write
`hub_status.json`, does not touch live XT directories, and does not become XT
file IPC production authority.

## Behavior

The shadow request reader now rejects request JSON files larger than 1 MiB
before reading them. After parsing, the runtime execution plan and runtime
adapter candidate reject prompts larger than 200,000 characters.

Oversized prompt requests return:

```json
{
  "ok": false,
  "wrote": false,
  "deny_code": "request_prompt_too_large"
}
```

Oversized request files return:

```json
{
  "ok": false,
  "wrote": false,
  "deny_code": "request_file_too_large"
}
```

No `ai_responses/resp_<req_id>.jsonl` is written. The authority block remains
unchanged:

- `production_authority_change=false`;
- `rust_executes_ml=false`;
- `memory_writer_authority_in_rust=false`;
- `rust_executes_third_party_skills=false`.

## Smoke Coverage

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` now covers seven
isolated temporary request paths:

- normal fail-closed adapter candidate;
- canceled fail-closed adapter candidate;
- pre-existing response collision;
- explicit overwrite request blocked by the overwrite env gate;
- unsupported request type rejection;
- no selected model route blocker;
- oversized prompt rejection.

## Validation

```bash
cargo test -p xhubd runtime_adapter_candidate
node --check tools/xt_file_ipc_runtime_adapter_candidate_smoke.js
bash tools/xt_file_ipc_runtime_adapter_candidate_smoke.command --timeout-ms 30000
```

This is a production cutover prerequisite for avoiding memory pressure and
latency spikes from unexpected XT file IPC request payloads.
