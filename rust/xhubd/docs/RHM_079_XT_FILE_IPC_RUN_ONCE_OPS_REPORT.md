# RHM-079 XT File IPC Run Once Ops Report

RHM-079 wires the isolated XT file IPC watcher run-once smoke into the daemon
ops report as optional evidence.

```bash
tools/daemon_ops_report.command \
  --xt-file-ipc-run-once-smoke \
  --xt-file-ipc-run-once-smoke-timeout-ms 30000
```

The check is default-off. Without the flag, `ops-report` records:

```json
{
  "xt_file_ipc_run_once_smoke": {
    "ok": true,
    "enabled": false,
    "skipped": true,
    "reason": "xt_file_ipc_run_once_smoke_not_requested",
    "production_authority_change": false
  }
}
```

When enabled, the report runs the existing isolated smoke runner against a
temporary daemon and temporary XT IPC directories, then embeds the child report
summary and child `report_path`.

## Boundaries

- Default `ops-report` behavior remains non-mutating for XT file IPC.
- Opt-in smoke uses temporary directories only.
- The smoke must not write live XT `hub_status.json`.
- The smoke must not start a long-running watcher.
- The smoke must not execute ML.
- The smoke must not mark `xt_file_ipc_production_surface_ready=true`.
- The smoke must not change production authority.

## Report Fields

- `xt_file_ipc_run_once_smoke`
- `xt_file_ipc_run_once_smoke_enabled`
- `xt_file_ipc_run_once_smoke_ok`

If the opt-in smoke fails, `ops-report.ok=false`. Default skipped smoke remains
`ok=true` because no XT authority check was requested.

## Validation

- `node --check tools/xhubd_daemon.js`
- default `tools/daemon_ops_report.command --report-path ...`
- opt-in `tools/daemon_ops_report.command --xt-file-ipc-run-once-smoke ...`
- package includes the docs and script changes
