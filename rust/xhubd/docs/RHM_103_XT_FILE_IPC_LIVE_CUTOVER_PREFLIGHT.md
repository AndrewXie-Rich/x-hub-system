# RHM-103 XT File IPC Live Cutover Preflight

## Scope

`tools/xt_file_ipc_live_cutover_preflight.command` prepares the final live XT
file IPC cutover evidence without applying production env, restarting the
daemon, or calling `write-status`.

## Behavior

- Captures a write-before snapshot of the live `hub_status.json` path:
  existence, size, mtime, SHA-256, parse status, and safe summary fields.
- Runs the production cutover blocker and requires only the expected final
  blockers to remain.
- Runs the rollback rehearsal and requires it to pass.
- Emits the exact apply command, daemon relaunch plan, write-status smoke plan,
  and rollback plan.
- Does not include full `hub_status.json` content in the report.

## Commands

```bash
bash tools/xt_file_ipc_live_cutover_preflight.command \
  --rust-hub-root "/Users/andrew.xie/Documents/AX/rust/rust hub/dist/<package>" \
  --live-base-dir "$HOME/Library/Group Containers/group.rel.flowhub"
```

## Status

Implemented as the final preflight before explicit live apply. It leaves
`apply_performed=false`, `daemon_restarted=false`, and `write_status_called=false`.
