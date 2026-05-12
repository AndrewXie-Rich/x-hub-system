# RHM-083 XT File IPC Background Watcher Lifecycle

RHM-083 adds a default-off, bounded background watcher lifecycle for the XT file
IPC shadow surface:

```text
POST /xt/file-ipc-shadow/watcher-background-start
POST /xt/file-ipc-shadow/watcher-background-status
POST /xt/file-ipc-shadow/watcher-background-stop
POST /compat/xt-file-ipc-shadow/watcher-background-start
POST /compat/xt-file-ipc-shadow/watcher-background-status
POST /compat/xt-file-ipc-shadow/watcher-background-stop
```

The existing file IPC endpoint also accepts:

- `{"operation":"watcher-background-start"}`
- `{"operation":"watcher-background-status"}`
- `{"operation":"watcher-background-stop"}`

## Gates

Starting the background watcher requires `{"apply": true}` and all gates below:

- `XHUB_RUST_XT_FILE_IPC_SHADOW=1`
- `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE=1`
- `XHUB_RUST_XT_FILE_IPC_RUNTIME_READY=1`
- `XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_BACKGROUND_APPLY=1`
- explicit shadow-safe temp `base_dir`
- `ai_requests`, `ai_responses`, and `ai_cancels` directories exist

## Behavior

The watcher is intentionally bounded. It runs at most the request's
`max_cycles` value, capped by the existing file IPC input parser, and then
stops itself. It can also be stopped explicitly with the stop endpoint.

While active, it:

- holds the Rust-owned watcher lock;
- writes Rust-owned watcher status;
- runs fail-closed shadow cycles over temporary request directories;
- writes only shadow processor status and fail-closed JSONL responses;
- releases the watcher lock when stopped or finished.

## Boundaries

- It is still a shadow surface only.
- It does not write live XT `hub_status.json`.
- It does not mark `xt_file_ipc_production_surface_ready=true`.
- It does not execute ML.
- It does not change production authority.
- It is single-instance within the xhubd process.
- It is not yet the production XT local IPC watcher.

## Validation

- `cargo test -p xhubd xt_file_ipc`
- full `cargo test -p xhubd`
- release `cargo build --release -p xhubd`
- `/ready.capabilities.xt_file_ipc_shadow_watcher_background_lifecycle_http=true`
- default live start POST remains fail-closed with `wrote=false`

