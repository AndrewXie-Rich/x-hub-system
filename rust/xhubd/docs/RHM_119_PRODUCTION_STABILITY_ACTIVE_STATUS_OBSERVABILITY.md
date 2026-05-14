# RHM-119 Production Stability Active Status Observability

## Goal

Make a running production stability session observable without stopping or
restarting it.

The long stability gate can run for 8 to 24 hours. Before this change,
`tools/production_live_stability_session.command --status` could report the
top-level gate PID and final report path, but it could not show whether the
active heartbeat child was still running or whether the live `hub_status.json`
evidence was currently fresh.

## Contract

- `--status` is read-only.
- It must not write `hub_status.json`.
- It must not start, stop, or replace the active stability gate.
- It must not change provider/model, scheduler, memory writer, skills execution,
  or UI authority.
- It must keep the existing cross-package active session discovery behavior.
- It must expose enough active state to diagnose a long run while it is still in
  progress.

## Implementation

`tools/production_live_stability_session.js` now adds the following fields to
the status payload:

- `http_base_url`
- `live_base_dir`
- `active_report_file`
- `active_process_tree`
- `active_heartbeat_child`
- `active_heartbeat_report_file`
- `active_live_status_sample`
- `active_live_status_fresh`

`active_process_tree` records the discovered gate PID and the direct
`xt_file_ipc_live_heartbeat_soak.js` child when present. The child record
includes PID, parent PID, root dir, report path, timing, interval, and freshness
budget parsed from the live command line.

`active_live_status_sample` uses a bounded child-process read of the live
`hub_status.json`, mirroring the safety pattern used by the heartbeat soak. It
summarizes only operational metadata:

- status file existence, size, mtime, and parse status
- `updatedAt` age and freshness against the configured budget
- PID, `ipcMode`, `ipcPath`, base dir, `aiReady`, loaded model count
- Rust authority marker and schema version

It does not embed the full status JSON and does not inspect secrets.

## Validation

- `node --check tools/production_live_stability_session.js`
- `tools/production_live_stability_session.command --status` during an active
  long production stability session
- packaged `tools/production_live_stability_session.command --status`

