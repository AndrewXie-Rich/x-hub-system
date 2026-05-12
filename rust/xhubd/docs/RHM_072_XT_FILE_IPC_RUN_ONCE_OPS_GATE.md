# RHM-072 XT File IPC Run Once Ops Gate

Status: implemented 2026-05-07

## Decision

`xhubd_daemon.command ops-gate` now supports an opt-in XT file IPC run-once
smoke gate:

```text
bash tools/daemon_ops_gate.command \
  --xt-file-ipc-run-once-smoke \
  --xt-file-ipc-run-once-smoke-timeout-ms 30000
```

The gate is default-off. When enabled, it runs
`tools/xt_file_ipc_watcher_run_once_smoke.command` against an isolated temporary
daemon and persists the child smoke report next to the ops-gate report.

## Boundary

- Default ops-gate behavior does not start the XT file IPC smoke.
- The smoke uses temporary directories and an isolated temporary daemon.
- It does not touch XT live directories.
- It does not write `hub_status.json`.
- It does not execute ML.
- It does not change production authority.

## Report Fields

The ops-gate report includes:

- `xt_file_ipc_run_once_smoke`
- `xt_file_ipc_run_once_smoke_enabled`
- `xt_file_ipc_run_once_smoke_ok`

If the opt-in smoke fails, ops-gate adds
`xt_file_ipc_run_once_smoke_failed` to `issues`.

## Validation

```bash
node --check tools/xhubd_daemon.js
bash tools/daemon_ops_gate.command --no-require-ready
bash tools/daemon_ops_gate.command \
  --no-require-ready \
  --xt-file-ipc-run-once-smoke \
  --xt-file-ipc-run-once-smoke-timeout-ms 30000
```
