# RHM-071 XT File IPC Watcher Run Once Report

Status: implemented 2026-05-07

## Decision

The XT file IPC watcher run-once smoke runner now supports persisted JSON
evidence:

```text
bash tools/xt_file_ipc_watcher_run_once_smoke.command \
  --timeout-ms 30000 \
  --report-file reports/xt_file_ipc_watcher_run_once_smoke.json
```

The report is also printed to stdout. When `--report-file` is provided, the
tool creates the parent directory and writes the exact report JSON to disk.

## Boundary

- This changes only smoke evidence collection.
- It does not change Rust Hub runtime behavior.
- It does not touch XT live directories.
- It does not write `hub_status.json`.
- It does not execute ML.
- It does not change production authority.

## Report Schema

```text
xhub.rust_hub.xt_file_ipc_watcher_run_once_smoke.v1
```

The persisted report includes:

- `ok`
- `production_authority_change`
- `temp_root`
- `base_url`
- `request_id`
- `report_file`
- lock/status/response readiness checks

## Validation

```bash
node --check tools/xt_file_ipc_watcher_run_once_smoke.js
bash tools/xt_file_ipc_watcher_run_once_smoke.command \
  --timeout-ms 30000 \
  --report-file /tmp/xhub-xt-file-ipc-run-once-smoke-report.json
```
