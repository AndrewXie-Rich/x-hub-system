# RHM-047 XT File IPC Shadow Responder

Status: implemented 2026-05-07

## Decision

Rust Hub now has a minimal XT local file IPC surface for contract validation:

```text
GET  /xt/file-ipc-shadow
POST /xt/file-ipc-shadow/respond-once
POST /compat/xt-file-ipc-shadow
```

This is not production execution. It is a one-shot shadow responder that reads
an XT-shaped `ai_requests/req_<req_id>.json` from an explicit temporary base
directory and can write a fail-closed `ai_responses/resp_<req_id>.jsonl`.

## Boundary

- GET never writes.
- POST is disabled unless `XHUB_RUST_XT_FILE_IPC_SHADOW=1`.
- Writing requires both request body `{"apply": true}` and
  `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`.
- The base directory must be explicit through body `base_dir`/`baseDir` or
  `XHUB_RUST_XT_FILE_IPC_BASE_DIR`.
- By default, the base directory must canonicalize under the process temp
  directory, `/private/tmp`, or `/tmp`.
- Real XT/RELFlowHub candidate directories remain blocked unless a future
  explicit non-temp cutover gate is designed and approved.
- Rust still does not execute ML, does not watch real request directories, and
  does not set `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`.

## Contract Shape

Request path:

```text
<base_dir>/ai_requests/req_<req_id>.json
```

Response path:

```text
<base_dir>/ai_responses/resp_<req_id>.jsonl
```

Cancel path:

```text
<base_dir>/ai_cancels/cancel_<req_id>.json
```

When apply is allowed, Rust writes two JSONL events:

```json
{"type":"start","req_id":"r1","model_id":"mlx/test","task_type":"text_generate","runtime_provider":"Rust Hub Shadow","execution_path":"rust_file_ipc_shadow","authority":"shadow_only","fail_closed":true}
{"type":"done","req_id":"r1","ok":false,"reason":"rust_file_ipc_not_authoritative","model_id":"mlx/test","task_type":"text_generate","promptTokens":0,"generationTokens":0,"deny_code":"rust_file_ipc_not_authoritative","runtime_provider":"Rust Hub Shadow","execution_path":"rust_file_ipc_shadow","authority":"shadow_only","fail_closed":true}
```

If a cancel file exists before response generation, the done reason becomes
`rust_file_ipc_cancel_observed`. This still remains fail-closed.

## Deny Codes

Common fail-closed deny codes:

```text
base_dir_required
xt_file_ipc_shadow_not_enabled
base_dir_outside_shadow_sandbox
base_dir_missing
request_dir_missing
request_file_missing
request_id_ambiguous
unsafe_request_id
request_read_failed
unsupported_request_type
response_already_exists
xt_file_ipc_shadow_apply_not_enabled
response_write_failed
```

## Relationship To XT Classic Cutover

`RHM-045` introduced the classic `hub_status.json` writer, but that writer
still blocks on `classic_file_ipc_surface_ready`. This slice intentionally does
not satisfy that gate for real profiles. It only proves Rust understands the
file names, request fields, JSONL response shape, cancel marker, and atomic
response writing in isolated temporary directories.

Before Rust may mark XT `hubInteractive`, a later slice still needs a real
watcher/processor lifecycle, status heartbeat, rollback smoke, and either local
ML execution or a governed route to the existing runtime.

## Validation

Focused test:

```bash
cargo test -p xhubd xt_file_ipc
```

Full local validation:

```bash
cargo test -p xhubd
cargo build --release -p xhubd
bash tools/xhubd_daemon.command launchd-install --replace-running
curl -fsS http://127.0.0.1:50151/ready
curl -fsS http://127.0.0.1:50151/xt/file-ipc-shadow
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_responder_http=true`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
- `GET /xt/file-ipc-shadow` returns `ready=false`
- no response file is written without explicit temp-dir opt-in and apply gates
