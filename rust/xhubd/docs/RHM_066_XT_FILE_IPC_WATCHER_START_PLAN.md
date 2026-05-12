# RHM-066 XT File IPC Watcher Start Plan

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a default-off watcher start plan endpoint:

```text
POST /xt/file-ipc-shadow/watcher-start-plan
POST /compat/xt-file-ipc-shadow/watcher-start-plan
```

The existing file IPC endpoint also accepts
`{"operation":"watcher-start-plan"}` or `{"watcher_start_plan":true}`.

This endpoint does not start a watcher. It composes the watcher readiness gate
with one additional explicit start-plan gate and returns a plan, blockers, and
the lock/status paths a later lifecycle slice would use.

## Boundary

- The endpoint writes no files.
- The endpoint starts no background thread or process.
- `ready` remains false.
- `production_file_ipc_ready` remains false.
- `hub_status.json` is untouched.
- Rust still does not execute ML and does not call the Python local runtime.
- Existing Node/RELFlowHub remains production authority.

## Diagnostic Gates

The endpoint reports blockers for:

- XT file IPC directory shape.
- `XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE`
- `XHUB_RUST_XT_FILE_IPC_RUNTIME_READY`
- `XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY`

Even if all gates pass, the result is only a `start_candidate`; no long-running
watcher exists yet.

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
curl -sS -X POST http://127.0.0.1:50151/xt/file-ipc-shadow/watcher-start-plan \
  -H 'Content-Type: application/json' \
  --data '{}'
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_watcher_start_plan_http=true`
- default `POST /xt/file-ipc-shadow/watcher-start-plan` returns fail-closed with
  `wrote=false`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
