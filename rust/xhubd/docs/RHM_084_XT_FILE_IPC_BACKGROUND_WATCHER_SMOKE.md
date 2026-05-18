# RHM-084 XT File IPC Background Watcher Smoke

RHM-084 adds a packageable smoke runner for the bounded XT file IPC background
watcher lifecycle:

```bash
tools/xt_file_ipc_background_watcher_smoke.command
```

The runner starts an isolated temporary `xhubd serve`, enables only the shadow
file IPC gates required for the background watcher, creates temporary XT IPC
directories and one request, then validates:

- `/ready.capabilities.xt_file_ipc_shadow_watcher_background_lifecycle_http=true`;
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`;
- `watcher-background-start` succeeds only inside the isolated smoke daemon;
- `watcher-background-status` reports no production authority change;
- `watcher-background-stop` stops the bounded watcher;
- Rust-owned watcher lock is released;
- Rust-owned watcher and processor status files exist;
- fail-closed JSONL response is written;
- `hub_status.json` is not written;
- ML execution remains disabled.

## Report

The runner prints `xhub.rust_hub.xt_file_ipc_background_watcher_smoke.v1` JSON
and accepts:

```bash
--report-file <path>
--timeout-ms <ms>
--port <port>
--keep-temp
```

## Boundaries

The smoke uses temporary directories only. It does not touch XT live paths, does
not execute ML, does not write live `hub_status.json`, and does not change
production authority.
