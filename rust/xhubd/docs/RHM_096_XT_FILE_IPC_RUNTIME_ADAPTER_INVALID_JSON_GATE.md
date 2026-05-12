# RHM-096 XT File IPC Runtime Adapter Invalid JSON Gate

## Goal

Reject malformed XT file IPC request JSON before model routing or response
writing.

This remains fail-closed. Rust does not execute ML, does not write
`hub_status.json`, does not touch live XT directories, and does not become XT
file IPC production authority.

## Behavior

If `ai_requests/req_<req_id>.json` exists but cannot be parsed as JSON, the
runtime adapter candidate returns HTTP 409 with:

```json
{
  "ok": false,
  "wrote": false,
  "deny_code": "request_json_invalid"
}
```

No `ai_responses/resp_<req_id>.jsonl` is written. The authority block remains:

- `production_authority_change=false`;
- `rust_executes_ml=false`;
- `rust_writes_classic_hub_status=false`;
- `rust_executes_third_party_skills=false`.

## Smoke Coverage

`tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` now includes a
malformed request JSON fixture in an isolated temporary IPC directory and
verifies:

- `request_json_invalid` is returned;
- no response JSONL is written;
- no `hub_status.json` is written;
- production authority and ML execution remain false.

## Validation

```bash
cargo test -p xhubd runtime_adapter_candidate
node --check tools/xt_file_ipc_runtime_adapter_candidate_smoke.js
bash tools/xt_file_ipc_runtime_adapter_candidate_smoke.command --timeout-ms 30000
```

This is a production cutover prerequisite for preventing malformed XT request
files from reaching route selection or producing misleading response files.
