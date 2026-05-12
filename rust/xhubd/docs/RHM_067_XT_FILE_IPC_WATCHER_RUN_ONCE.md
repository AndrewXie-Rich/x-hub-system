# RHM-067 XT File IPC Watcher Run Once

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a default-off one-shot watcher run endpoint:

```text
POST /xt/file-ipc-shadow/watcher-run-once
POST /compat/xt-file-ipc-shadow/watcher-run-once
```

The existing file IPC endpoint also accepts
`{"operation":"watcher-run-once"}` or `{"watcher_run_once":true}`.

This endpoint is not a production watcher. When all explicit gates pass and the
request body sets `{"apply": true}`, it acquires the Rust-owned watcher lock,
writes watcher starting status, runs one bounded shadow processor cycle, writes
stopped status, releases the lock, and returns.

## Boundary

- The base directory remains explicit and temp-dir-only.
- The endpoint starts no long-running background thread or process.
- The processor cycle still writes only Rust-owned shadow status and
  fail-closed XT response JSONL.
- `ready` remains false.
- `production_file_ipc_ready` remains false.
- `hub_status.json` is untouched.
- Rust still does not execute ML and does not call the Python local runtime.
- Existing Node/RELFlowHub remains production authority.

## Required Gates

Writing requires all of:

- `XHUB_RUST_XT_FILE_IPC_SHADOW=1`
- `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE=1`
- `XHUB_RUST_XT_FILE_IPC_RUNTIME_READY=1`
- `XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_RUN_ONCE_APPLY=1`
- body `{"apply": true}`

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
curl -sS -X POST http://127.0.0.1:50151/xt/file-ipc-shadow/watcher-run-once \
  -H 'Content-Type: application/json' \
  --data '{}'
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_watcher_run_once_http=true`
- default `POST /xt/file-ipc-shadow/watcher-run-once` returns fail-closed with
  `wrote=false`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
