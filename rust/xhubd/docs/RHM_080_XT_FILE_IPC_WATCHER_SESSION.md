# RHM-080 XT File IPC Watcher Session

RHM-080 adds a bounded XT file IPC watcher session endpoint:

```text
POST /xt/file-ipc-shadow/watcher-session
POST /compat/xt-file-ipc-shadow/watcher-session
```

The existing file IPC endpoint also accepts
`{"operation":"watcher-session"}` or `{"watcher_session":true}`.

This is not a production watcher. It is a default-off, temporary-dir-only
session that proves the next lifecycle primitive before any long-running
watcher exists:

- compose the existing watcher start plan gates;
- require `XHUB_RUST_XT_FILE_IPC_WATCHER_SESSION_APPLY=1` in addition to the
  shadow, runtime, rollback, and start gates;
- acquire the Rust-owned watcher lock;
- write Rust-owned watcher status;
- run a bounded synchronous supervisor loop;
- write stopped watcher status and release the lock before returning.

## Required Gates

The endpoint only mutates temporary shadow files when all of these are true and
the request body includes `{"apply": true}`:

- `XHUB_RUST_XT_FILE_IPC_SHADOW=1`
- `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE=1`
- `XHUB_RUST_XT_FILE_IPC_RUNTIME_READY=1`
- `XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY=1`
- `XHUB_RUST_XT_FILE_IPC_WATCHER_SESSION_APPLY=1`
- explicit `base_dir` under a shadow-safe temp directory
- XT file IPC directories exist: `ai_requests`, `ai_responses`, `ai_cancels`

## Boundaries

- The endpoint starts no long-running thread or background process.
- The endpoint releases the watcher lock before returning.
- The endpoint writes only Rust-owned shadow status files and fail-closed JSONL
  responses under the explicit temp `base_dir`.
- The endpoint does not write live XT `hub_status.json`.
- The endpoint does not execute ML.
- The endpoint does not mark `xt_file_ipc_production_surface_ready=true`.
- The endpoint does not change production authority.

## Validation

- `cargo test -p xhubd xt_file_ipc`
- full `cargo test -p xhubd`
- release `cargo build --release -p xhubd`
- default live POST remains fail-closed unless every explicit gate is enabled
