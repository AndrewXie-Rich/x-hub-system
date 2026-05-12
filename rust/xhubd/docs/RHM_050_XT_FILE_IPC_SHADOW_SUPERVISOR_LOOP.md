# RHM-050 XT File IPC Shadow Supervisor Loop

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a bounded, synchronous shadow supervisor loop:

```text
POST /xt/file-ipc-shadow/supervise
POST /compat/xt-file-ipc-shadow/supervise
```

The existing file IPC endpoint also accepts `{"operation":"supervise"}` or
`{"supervise":true}`.

This is a lifecycle skeleton only. It runs up to `max_cycles` manual processor
cycles in the HTTP request, sleeping `cycle_interval_ms` between cycles, and
then stops before returning.

## Boundary

- No background thread or process is left running.
- `max_cycles` is clamped to `1..10`.
- `cycle_interval_ms` is capped at `5000`.
- The base directory remains explicit and temp-dir-only.
- Writing still requires `XHUB_RUST_XT_FILE_IPC_SHADOW=1`,
  `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`, and body `{"apply": true}`.
- The loop writes only Rust-owned shadow processor status and fail-closed
  response files.
- It never writes `hub_status.json`.
- Rust still does not execute ML and does not call the Python local runtime.
- `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY` remains false.
- Existing Node/RELFlowHub remains production authority.

## Request Body

```json
{
  "base_dir": "/private/tmp/xhub-file-ipc-smoke",
  "operation": "supervise",
  "apply": false,
  "max_requests": 16,
  "max_cycles": 3,
  "cycle_interval_ms": 100
}
```

## Result Shape

The result includes bounded lifecycle evidence:

```json
{
  "schema_version": "xhub.rust_hub.xt_file_ipc_shadow.v1",
  "ok": true,
  "ready": false,
  "mode": "shadow_supervise_dry_run",
  "supervisor": {
    "max_cycles": 3,
    "cycle_count": 3,
    "failed_count": 0,
    "status_wrote_count": 0,
    "response_wrote_count": 0,
    "background_watcher_started": false,
    "stopped": true,
    "production_file_ipc_ready": false
  }
}
```

When apply gates are enabled, repeated cycles skip requests whose response file
already exists. That makes the loop idempotent enough for shadow lifecycle
smokes while still leaving request cleanup and real runtime execution for a
future production-grade watcher.

## Why This Slice Exists

`RHM-049` added one manual processor cycle. This slice proves the next lifecycle
primitive: bounded repeated cycles, explicit stop, idempotent response skipping,
and aggregate lifecycle reporting. It is still not a daemonized watcher.

## Validation

Focused test:

```bash
cargo test -p xhubd xt_file_ipc
```

Full local validation:

```bash
cargo test -p xhubd
cargo build --release -p xhubd
bash tools/xhubd_daemon.command launchd-install --replace-running
curl -fsS http://127.0.0.1:50151/ready
curl -sS -X POST http://127.0.0.1:50151/xt/file-ipc-shadow/supervise \
  -H 'Content-Type: application/json' \
  --data '{}'
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_supervise_http=true`
- default `POST /xt/file-ipc-shadow/supervise` returns fail-closed with
  `wrote=false`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
