# RHM-106 XT File IPC Heartbeat Fast Refresh

## Goal

Keep the live XT classic `hub_status.json` heartbeat fresh during long-running
Rust Hub cutover without making every heartbeat depend on the classic gRPC
probe.

## Change

- Initial live status writes still use the full explicit cutover gate and gRPC
  compatibility probe.
- Background heartbeat refreshes now use a dedicated Rust-owned status refresh
  path.
- The heartbeat path refreshes only when an existing preferred status file is
  Rust-owned or a fresh Rust-owned status is already active.
- A fresh non-Rust classic Hub status still blocks writes.
- `GET /xt/classic-hub-compat` uses the same Rust-owned live-status fast path
  after cutover so diagnostics do not block every cycle on classic gRPC.
- Heartbeat refresh does not execute ML, skills, or memory writes.

## Runtime Gates

Heartbeat refresh requires all of:

- `XHUB_RUST_XT_CLASSIC_COMPAT=1`
- `XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES=1`
- `XHUB_RUST_XT_CLASSIC_STATUS_WRITER=1`
- `XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY=1`
- `XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT=1`
- `XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT_MS=1000`
- `XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT=1`
- `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY=1`
- `XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER=1`
- preferred status parent exists
- no fresh non-Rust classic Hub status is active
- Rust-owned status evidence is available

The first heartbeat write uses preferred-status raw evidence only and stamps the
status immediately before the atomic write. After one successful refresh in the
same daemon process, the heartbeat loop switches to trusted fast refresh: no
status read, no gRPC probe, no repeated directory creation, just write-temp and
atomic rename under the same explicit production gates.
If a filesystem write takes long enough that the generated `updatedAt` would be
stale by the time the rename completes, the writer immediately regenerates the
status with a fresh timestamp and retries.
Readiness and compat diagnostics use raw Rust-owned live status summaries after
cutover so `/ready` and `/xt/classic-hub-compat` avoid expensive runtime-status
filesystem scans during steady state.

## Verification

Source gates:

```bash
cargo test -p xhubd xt_compat
cargo test -p xhubd
node --check tools/xt_file_ipc_live_heartbeat_soak.js
```

Ops gate:

```bash
bash tools/daemon_ops_gate.command --max-slow-requests 0
```

Live cutover gate:

```bash
bash tools/xt_file_ipc_live_heartbeat_soak.command --duration-ms 30000 --interval-ms 2000 --max-status-age-ms 5000
```
