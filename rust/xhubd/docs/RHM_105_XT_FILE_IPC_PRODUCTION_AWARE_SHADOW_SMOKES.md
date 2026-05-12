# RHM-105 XT File IPC Production-Aware Shadow Smokes

## Goal

Keep the isolated XT file IPC shadow smokes useful after explicit live cutover.

The smokes must continue proving their own temporary shadow artifacts stay
non-production, while allowing the live daemon's
`xt_file_ipc_production_surface_ready` capability to be true.

## Behavior

The run-once and background watcher smokes now report:

- `production_surface_ready_observed`: the live `/ready` capability value
  observed from the temporary smoke daemon;
- `production_surface_ready_accepted=true`: the smoke accepts either live
  cutover state;
- `shadow_processor_production_file_ipc_ready=true`: the isolated processor
  status stayed non-production.

The legacy `production_file_ipc_ready=false` check remains for compatibility,
but ops validation now also accepts the explicit shadow-processor evidence.

## Ops Gate

`tools/xhubd_daemon.js` now validates XT file IPC child smokes with a
production-aware reducer. The reducer requires:

- child smoke `ok=true`;
- `production_authority_change=false`;
- no `hub_status.json` written in the isolated temporary directory;
- no ML execution in Rust;
- isolated shadow processor status remains non-production;
- live production-surface observation is a boolean when reported.

This prevents `daemon_ops_gate.command --xt-file-ipc-run-once-smoke
--xt-file-ipc-background-watcher-smoke` from failing solely because explicit
live XT file IPC cutover is active.

## Validation

```bash
node --check tools/xt_file_ipc_watcher_run_once_smoke.js
node --check tools/xt_file_ipc_background_watcher_smoke.js
node --check tools/xhubd_daemon.js
bash tools/xt_file_ipc_watcher_run_once_smoke.command --timeout-ms 30000
bash tools/xt_file_ipc_background_watcher_smoke.command --timeout-ms 30000
bash tools/daemon_ops_gate.command --xt-file-ipc-run-once-smoke \
  --xt-file-ipc-background-watcher-smoke --max-slow-requests 1000000
```

The live production heartbeat remains covered separately by RHM-104.
