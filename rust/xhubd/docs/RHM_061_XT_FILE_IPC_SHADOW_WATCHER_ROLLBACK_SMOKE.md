# RHM-061 XT File IPC Shadow Watcher Rollback Smoke

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a bounded watcher rollback smoke endpoint:

```text
POST /xt/file-ipc-shadow/watcher-rollback-smoke
POST /compat/xt-file-ipc-shadow/watcher-rollback-smoke
```

The existing file IPC endpoint also accepts
`{"operation":"watcher-rollback-smoke"}` or
`{"watcher_rollback_smoke":true}`.

This is a rollback smoke only. It plans, and only when explicitly applied
removes, Rust-owned shadow watcher/processor artifacts from an explicit
temporary base directory.

## Boundary

- The base directory remains explicit and temp-dir-only.
- Writing requires `XHUB_RUST_XT_FILE_IPC_SHADOW=1`,
  `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`,
  `XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY=1`, and body `{"apply": true}`.
- Only these Rust-owned files are eligible for removal:
  - `rust_file_ipc_shadow_watcher.lock`
  - `rust_file_ipc_shadow_watcher_status.json`
  - `rust_file_ipc_shadow_processor_status.json`
- The rollback smoke never removes `hub_status.json`.
- The rollback smoke never removes XT `ai_responses/*.jsonl`.
- Rust still does not execute ML and does not call the Python local runtime.
- `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY` remains false.
- Existing Node/RELFlowHub remains production authority.

## Request Body

```json
{
  "base_dir": "/private/tmp/xhub-file-ipc-smoke",
  "operation": "watcher-rollback-smoke",
  "apply": false
}
```

## Result Shape

```json
{
  "schema_version": "xhub.rust_hub.xt_file_ipc_shadow.v1",
  "ok": true,
  "ready": false,
  "mode": "shadow_watcher_rollback_smoke_dry_run",
  "rollback": {
    "planned_remove_count": 3,
    "removed_count": 0,
    "hub_status_removed": false,
    "xt_response_files_removed": false,
    "production_file_ipc_ready": false
  }
}
```

## Why This Slice Exists

`RHM-059` proved watcher lock/status lifecycle semantics. This slice proves the
rollback primitive required before any real default-off background watcher can
be considered: Rust can clean only its own shadow artifacts while leaving XT
production status and response files untouched.

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
curl -sS -X POST http://127.0.0.1:50151/xt/file-ipc-shadow/watcher-rollback-smoke \
  -H 'Content-Type: application/json' \
  --data '{}'
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_watcher_rollback_smoke_http=true`
- default `POST /xt/file-ipc-shadow/watcher-rollback-smoke` returns
  fail-closed with `wrote=false`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
