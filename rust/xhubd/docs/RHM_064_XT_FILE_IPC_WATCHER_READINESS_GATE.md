# RHM-064 XT File IPC Watcher Readiness Gate

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a default-off watcher readiness gate:

```text
POST /xt/file-ipc-shadow/watcher-readiness
POST /compat/xt-file-ipc-shadow/watcher-readiness
```

The existing file IPC endpoint also accepts `{"operation":"watcher-readiness"}`
or `{"watcher_readiness":true}`.

This endpoint is read-only. It checks whether a temporary XT file IPC directory
has the minimum shape required for a future watcher and reports explicit
blockers for watcher enablement, runtime readiness, and rollback readiness.

## Boundary

- The base directory remains explicit and temp-dir-only.
- The endpoint writes no files.
- The endpoint starts no background watcher.
- `ready` is always false.
- `production_file_ipc_ready` is always false.
- Candidate readiness is diagnostic only and does not satisfy the classic Hub
  status writer's `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY` gate.
- Rust still does not execute ML and does not call the Python local runtime.
- Existing Node/RELFlowHub remains production authority.

## Required Directory Shape

The temporary base directory must contain:

```text
ai_requests/
ai_responses/
ai_cancels/
```

## Diagnostic Gates

The endpoint reports these environment gates:

- `XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE`
- `XHUB_RUST_XT_FILE_IPC_RUNTIME_READY`
- `XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY`

Even when all diagnostic gates pass, the endpoint returns `ready=false`; a later
slice must wire real watcher execution and production cutover evidence.

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
curl -sS -X POST http://127.0.0.1:50151/xt/file-ipc-shadow/watcher-readiness \
  -H 'Content-Type: application/json' \
  --data '{}'
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_watcher_readiness_http=true`
- default `POST /xt/file-ipc-shadow/watcher-readiness` returns fail-closed with
  `wrote=false`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
