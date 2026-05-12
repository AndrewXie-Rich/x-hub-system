# RHM-068 XT File IPC Watcher Run Once Smoke

Status: implemented 2026-05-07

## Decision

Rust Hub now includes a source/package smoke runner for the default-off
one-shot XT file IPC watcher lifecycle:

```text
tools/xt_file_ipc_watcher_run_once_smoke.command
tools/xt_file_ipc_watcher_run_once_smoke.js
```

The smoke starts an isolated temporary `xhubd serve` process with all required
shadow gates enabled, creates a temporary XT file IPC directory, writes one
`req_<id>.json`, calls `POST /xt/file-ipc-shadow/watcher-run-once`, and
validates the resulting shadow artifacts.

## Boundary

- It uses a temporary base directory under the system temp directory.
- It does not touch XT's live file IPC directory.
- It does not write `hub_status.json`.
- It does not start or modify launchd.
- It does not execute ML and expects a fail-closed response JSONL.
- It stops the temporary `xhubd` process before returning.
- It reports `production_authority_change=false`.

## Evidence Checked

- `/ready` exposes `xt_file_ipc_shadow_watcher_run_once_http=true`.
- `/ready` keeps `xt_file_ipc_production_surface_ready=false`.
- The run-once endpoint succeeds only in the isolated gated process.
- The Rust watcher lock is released.
- Watcher status exists and is stopped.
- Processor status exists and remains shadow-only.
- XT response JSONL contains `start` then fail-closed `done`.
- `hub_status.json` is absent.
- No background watcher or ML execution is reported.

## Validation

```bash
bash tools/xt_file_ipc_watcher_run_once_smoke.command --timeout-ms 30000
```

Expected report schema:

```text
xhub.rust_hub.xt_file_ipc_watcher_run_once_smoke.v1
```
