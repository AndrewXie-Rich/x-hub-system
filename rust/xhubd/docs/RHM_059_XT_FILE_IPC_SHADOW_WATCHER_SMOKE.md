# RHM-059 XT File IPC Shadow Watcher Smoke

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a bounded watcher lifecycle smoke endpoint:

```text
POST /xt/file-ipc-shadow/watcher-smoke
POST /compat/xt-file-ipc-shadow/watcher-smoke
```

The existing file IPC endpoint also accepts `{"operation":"watcher-smoke"}` or
`{"watcher_smoke":true}`.

This is a lifecycle smoke only. It acquires a Rust-owned lock, writes a
Rust-owned watcher status file, runs the bounded synchronous shadow supervisor,
writes a stopped watcher status file, releases the lock, and returns. It does
not leave a background watcher running.

## Boundary

- The base directory remains explicit and temp-dir-only.
- Writing still requires `XHUB_RUST_XT_FILE_IPC_SHADOW=1`,
  `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`, and body `{"apply": true}`.
- The lock file is `rust_file_ipc_shadow_watcher.lock`.
- The watcher status file is `rust_file_ipc_shadow_watcher_status.json`.
- The watcher status file is Rust-owned shadow evidence, not `hub_status.json`.
- Busy lock detection fails closed with `deny_code=watcher_lock_busy`.
- The watcher always stops before the HTTP response is returned.
- Rust still does not execute ML and does not call the Python local runtime.
- `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY` remains false.
- Existing Node/RELFlowHub remains production authority.

## Request Body

```json
{
  "base_dir": "/private/tmp/xhub-file-ipc-smoke",
  "operation": "watcher-smoke",
  "apply": false,
  "max_requests": 16,
  "max_cycles": 3,
  "cycle_interval_ms": 100
}
```

## Result Shape

The result includes lifecycle and lock evidence:

```json
{
  "schema_version": "xhub.rust_hub.xt_file_ipc_shadow.v1",
  "ok": true,
  "ready": false,
  "mode": "shadow_watcher_smoke_dry_run",
  "watcher": {
    "lock_acquired": false,
    "lock_released": false,
    "start_status_wrote": false,
    "stop_status_wrote": false,
    "response_wrote": false,
    "background_watcher_started": false,
    "stopped": true,
    "production_file_ipc_ready": false,
    "hub_status_written": false
  }
}
```

In apply mode, the endpoint writes only shadow watcher status, shadow processor
status, and fail-closed response files under the explicit temporary base
directory. It never writes XT's live status file.

## Why This Slice Exists

`RHM-050` proved bounded repeated processor cycles. This slice proves the next
watcher lifecycle primitive: exclusive lock, starting/stopped status, bounded
work, lock release, and fail-closed busy-lock behavior. It is still not the real
production file IPC watcher.

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
curl -sS -X POST http://127.0.0.1:50151/xt/file-ipc-shadow/watcher-smoke \
  -H 'Content-Type: application/json' \
  --data '{}'
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_watcher_smoke_http=true`
- default `POST /xt/file-ipc-shadow/watcher-smoke` returns fail-closed with
  `wrote=false`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
