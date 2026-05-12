# RHM-104 XT File IPC Live Heartbeat Soak

## Scope

Adds post-cutover evidence for the live XT file IPC status writer path.

This slice keeps the product UI unchanged and does not enable Rust memory
writer authority or Rust skills execution authority.

## Runtime Behavior

- `xhubd` can refresh the live `hub_status.json` on a heartbeat when
  `XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT=1`.
- The default production session sets the heartbeat interval to `2000ms`.
- `/ready.capabilities.xt_file_ipc_production_surface_ready` is now dynamic:
  it becomes true only when the live status file is fresh and all explicit
  production gates remain enabled.
- mTLS classic gRPC is treated as reachable only under the explicit live
  cutover fallback gate, with TCP reachability checked first.

## Gate

```bash
bash tools/xt_file_ipc_live_heartbeat_soak.command \
  --duration-ms 30000 \
  --interval-ms 2000 \
  --max-status-age-ms 5000
```

The gate checks:

- daemon `/health` and `/ready`;
- dynamic production-surface readiness;
- fresh `hub_status.json` with `xt_live=true`;
- file IPC path and base dir match the live group-container path;
- memory writer authority remains false;
- skills execution authority remains false.
