# RHM-100 XT File IPC Production Session

## Scope

`tools/xt_file_ipc_production_session.command` adds a reversible production
session tool for the XT file IPC cutover path. It manages only the explicit
file-IPC and classic Hub compatibility environment gates needed for a live
`hub_status.json` writer trial.

## Guardrails

- `--apply` requires `--live-base-dir` and `--confirm-live-cutover`.
- The live base directory must already exist and must not be under `/tmp` or
  `/private/tmp`.
- The tool sets rollback, scan, gRPC probe, file-IPC ready, and production
  cutover gates together so the Rust writer remains fail-closed if any runtime
  check fails.
- It does not manage memory writer authority, skills execution authority, UI
  files, provider keys, or model routing keys.
- `GET /xt/classic-hub-compat` remains a preflight. The guarded
  `POST /xt/classic-hub-compat/write-status` is the only route that can write
  `hub_status.json`, and it still requires all Rust-side gates to pass.

## Commands

```bash
bash tools/xt_file_ipc_production_session.command --status
bash tools/xt_file_ipc_production_session.command --self-test
bash tools/xt_file_ipc_production_session.command \
  --apply \
  --live-base-dir "$HOME/Library/Group Containers/group.rel.flowhub" \
  --confirm-live-cutover
bash tools/xt_file_ipc_production_session.command --rollback
```

## Status

Implemented as a production cutover session primitive. Applying the session
only changes launchd session environment; the running Rust daemon still needs a
controlled relaunch before the new env can affect its classic compatibility
writer gates.
