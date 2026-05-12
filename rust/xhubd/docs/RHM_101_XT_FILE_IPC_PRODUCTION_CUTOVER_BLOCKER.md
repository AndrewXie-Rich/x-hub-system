# RHM-101 XT File IPC Production Cutover Blocker

## Scope

`tools/xt_file_ipc_production_cutover_blocker.command` is a read-only guard
before any XT file IPC live cutover. It collects Rust daemon health/readiness,
classic Hub compatibility preflight, XT file IPC prep session state, production
session state, the intended live base directory, and UI compatibility evidence.

## Behavior

- It never applies launchctl environment.
- It never calls `POST /xt/classic-hub-compat/write-status`.
- It always reports `production_apply_allowed=false`; the output is a blocker
  and evidence report, not an apply approval.
- It verifies the intended live base directory exists and is not under `/tmp`
  or `/private/tmp`.
- It keeps memory writer authority and skills execution authority false.
- It preserves the UI boundary by requiring the UI compatibility gate to pass.

## Commands

```bash
bash tools/xt_file_ipc_production_cutover_blocker.command
bash tools/xt_file_ipc_production_cutover_blocker.command \
  --live-base-dir "$HOME/Library/Group Containers/group.rel.flowhub"
bash tools/xt_file_ipc_production_cutover_blocker.command --self-test
```

## Status

Implemented as the live-cutover stop line before applying
`tools/xt_file_ipc_production_session.command`. The live writer remains disabled
until the explicit production session is applied, the daemon is relaunched with
that environment, and the guarded write-status endpoint is called.
