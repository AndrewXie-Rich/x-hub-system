# RHM-049 XT File IPC Shadow Processor Cycle

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a manual shadow processor cycle:

```text
POST /xt/file-ipc-shadow/cycle
POST /compat/xt-file-ipc-shadow/cycle
```

The existing file IPC endpoint also accepts `{"operation":"cycle"}` or
`{"cycle":true}`.

This cycle wraps the bounded drain from `RHM-048` and writes a Rust-owned
processor status file when explicitly allowed:

```text
<base_dir>/rust_file_ipc_shadow_processor_status.json
```

It never writes `hub_status.json`.

## Boundary

- Manual HTTP cycle only; no background watcher is started.
- The base directory remains explicit and temp-dir-only.
- Writing still requires `XHUB_RUST_XT_FILE_IPC_SHADOW=1`,
  `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`, and body `{"apply": true}`.
- The processor status file is Rust-owned shadow evidence, not an XT liveness
  signal.
- Rust still does not execute ML and does not call the Python local runtime.
- `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY` remains false.
- Existing Node/RELFlowHub remains production authority.

## Processor Status Shape

```json
{
  "schema_version": "xhub.rust_hub.xt_file_ipc_shadow_processor_status.v1",
  "ok": true,
  "ready": false,
  "cycle_id": "cycle-123-1778130000000",
  "pid": 123,
  "mode": "manual_http_cycle_once",
  "watcher_active": false,
  "heartbeat_active": true,
  "production_file_ipc_ready": false,
  "hub_status_written": false,
  "ml_execution": false
}
```

`heartbeat_active=true` only means this manual cycle wrote the shadow processor
status file. It does not mean Rust Hub is an XT production file IPC service.

## Why This Slice Exists

This proves the next lifecycle primitive after manual drain:

- a bounded processor cycle,
- a Rust-owned heartbeat/status artifact,
- no accidental publication of `hub_status.json`,
- no production readiness claim,
- no ML execution.

A future slice can build a supervised, default-off watcher around the same
status shape.

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
curl -sS -X POST http://127.0.0.1:50151/xt/file-ipc-shadow/cycle \
  -H 'Content-Type: application/json' \
  --data '{}'
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_cycle_http=true`
- default `POST /xt/file-ipc-shadow/cycle` returns fail-closed with
  `wrote=false`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
