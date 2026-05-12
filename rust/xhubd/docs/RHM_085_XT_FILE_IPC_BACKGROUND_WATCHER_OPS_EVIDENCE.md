# RHM-085 XT File IPC Background Watcher Ops Evidence

## Goal

Make the XT file IPC background watcher lifecycle visible to the daemon ops
report and ops gate without making it part of the default production path.

This is an evidence step only. It must not write `hub_status.json`, must not
touch live XT directories, must not execute ML, and must not mark Rust Hub as
the production file IPC authority.

## Commands

`tools/daemon_ops_report.command` and `tools/daemon_ops_gate.command` accept:

```bash
--xt-file-ipc-background-watcher-smoke
--xt-file-ipc-background-watcher-smoke-timeout-ms <n>
```

When the flag is absent, the report records a skipped check:

```json
{
  "enabled": false,
  "skipped": true,
  "reason": "xt_file_ipc_background_watcher_smoke_not_requested"
}
```

When the flag is present, the daemon tool runs
`tools/xt_file_ipc_background_watcher_smoke.command` against an isolated
temporary daemon and persists the child JSON evidence next to the parent ops
report.

## Required Evidence

The parent report only treats the smoke as passing when the child report proves:

- background watcher start/status/stop succeeded;
- the watcher lock was released;
- watcher status reached `stopped`;
- processor status remained shadow-only;
- response JSONL was fail-closed;
- no `hub_status.json` was written;
- `production_file_ipc_ready` stayed false;
- `ml_execution_in_rust` stayed false;
- `production_authority_change` stayed false.

## Fail-Closed Behavior

If the child command is missing, exits non-zero, writes invalid JSON, or any
required invariant is false, the parent check fails:

- ops report sets `xt_file_ipc_background_watcher_smoke_ok=false`;
- ops gate adds `xt_file_ipc_background_watcher_smoke_failed`.

The check is still default-off so routine daemon health checks do not start
temporary watcher smoke tests unless explicitly requested.

## Cutover Boundary

Passing this evidence does not mean XT can use Rust Hub as its live Hub. The
remaining cutover gates still require real file IPC runtime compatibility,
gRPC/API compatibility, rollback proof, and explicit production cutover flags.
