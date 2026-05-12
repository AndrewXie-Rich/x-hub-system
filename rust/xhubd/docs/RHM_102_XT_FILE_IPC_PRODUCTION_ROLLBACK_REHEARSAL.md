# RHM-102 XT File IPC Production Rollback Rehearsal

## Scope

`tools/xt_file_ipc_production_rollback_rehearsal.command` validates the
production session apply/rollback path without touching the live XT
`hub_status.json`.

## Behavior

- Uses a Rust-Hub-owned non-temp rehearsal base directory under `reports/`.
- Calls `xt_file_ipc_production_session.command --apply` against that rehearsal
  directory, then immediately calls `--rollback`.
- Does not restart the daemon.
- Does not call `POST /xt/classic-hub-compat/write-status`.
- Fails if any rehearsal `hub_status.json` appears.
- Fails if launchctl environment is not restored to its original values after
  rollback.
- Keeps memory writer authority, skills execution authority, and UI authority
  unchanged.

## Commands

```bash
bash tools/xt_file_ipc_production_rollback_rehearsal.command --self-test
bash tools/xt_file_ipc_production_rollback_rehearsal.command \
  --rust-hub-root "rust/xhubd/dist/<package>"
```

## Status

Implemented as the final rollback rehearsal before any live XT file IPC
production apply. It proves the launchctl production cutover keys can be set
and fully restored without writing status files.
