# RHM-099 XT File IPC Prep Session

Rust Hub now has a default-off XT file IPC prep session tool:

```bash
bash tools/xt_file_ipc_prep_session.command --status
bash tools/xt_file_ipc_prep_session.command --apply --rust-hub-root "/path/to/rust-hub-dist"
bash tools/xt_file_ipc_prep_session.command --rollback
```

The tool only sets launchctl session environment required for isolated XT file
IPC shadow, watcher, rollback, runtime-plan, and runtime-adapter candidate
gates. It intentionally does not set:

- `XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER`
- `XHUB_RUST_XT_FILE_IPC_BASE_DIR`

That keeps live XT file IPC production authority closed. Rust can still write
only inside explicitly supplied temp-safe base directories used by smokes and
diagnostics.

Authority invariants:

- `xt_file_ipc_production_surface_ready=false`
- `memory_writer_authority_target=false`
- `skills_execution_authority_target=false`
- `ui_product_change=false`
- `secret_leak=false`

This is a prep cut only. A later production cutover must add a separate live
base-dir contract, explicit production cutover env, rollback evidence, and XT
compatibility evidence.
