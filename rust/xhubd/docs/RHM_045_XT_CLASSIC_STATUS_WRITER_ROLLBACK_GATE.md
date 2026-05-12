# RHM-045 XT Classic Status Writer Rollback Gate

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a separate writer endpoint for the XT classic Hub status
contract:

```text
POST /xt/classic-hub-compat/write-status
POST /compat/xt-classic-hub/write-status
POST /compat/classic-hub/write-status
```

`GET /xt/classic-hub-compat` remains read-only. It reports the writer plan,
rollback contract, and every gate required before Rust may publish a classic
`hub_status.json`.

## Boundary

- GET preflight never writes.
- The writer endpoint rejects non-POST requests.
- The writer is explicit-cutover-only.
- Default launchd/local daemon configuration cannot write `hub_status.json`.
- Rust still does not execute XT local file IPC requests in real profiles.
- Existing Node/RELFlowHub remains production authority unless every explicit
  cutover gate is enabled.

## Required Gates

The writer only writes when all of these are true:

- `XHUB_RUST_XT_CLASSIC_COMPAT=1`
- `XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES=1`
- `XHUB_RUST_XT_CLASSIC_STATUS_WRITER=1`
- `XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY=1`
- `XHUB_RUST_XT_CLASSIC_GRPC_PROBE=1`
- `XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT=1`
- `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY=1`
- `XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER=1`
- preferred status parent exists,
- no active classic Hub status is detected,
- `HubRuntime.GetSchedulerStatus` probe succeeds.

`XHUB_RUST_XT_CLASSIC_FILE_IPC_READY` is intentionally separate from the gRPC
probe. XT's current local path uses `ipcMode=file|socket`; a successful gRPC
readiness probe alone is not enough to make XT local IPC work.

## Deny Codes

After the gRPC probe succeeds, common fail-closed deny codes are:

```text
rollback_contract_not_ready
classic_status_writer_apply_disabled
classic_file_ipc_surface_not_ready
production_cutover_not_authorized
```

The default live daemon still returns `xt_classic_compat_not_enabled` and
cannot write through the POST endpoint.

## Written Status Shape

When every explicit gate passes, the writer atomically writes a status shaped
for XT's current `HubStatus` decoder:

```json
{
  "pid": 12345,
  "startedAt": 1778130000.0,
  "updatedAt": 1778130000.0,
  "ipcMode": "file",
  "ipcPath": "/path/to/ipc_events",
  "baseDir": "/path/to/base",
  "protocolVersion": 1,
  "aiReady": true,
  "loadedModelCount": 0,
  "modelsUpdatedAt": 1778130000.0,
  "rustHub": {
    "schema_version": "xhub.rust_hub.xt_classic_status.v1",
    "authority": "explicit_cutover_only"
  }
}
```

Unknown fields are tolerated by XT's current decoder.

## Rollback

Rollback is included in both preflight and writer responses:

- unset all `XHUB_RUST_XT_CLASSIC_*` variables,
- restart Rust Hub with
  `bash tools/xhubd_daemon.command launchd-install --replace-running`,
- remove only the Rust-owned `hub_status.json` target if it was written during
  an explicit cutover trial,
- restart classic X-Hub/RELFlowHub and verify XT reports the classic Hub again.

## Validation

Focused test:

```bash
cargo test -p xhubd xt_compat
```

Full local validation:

```bash
cargo test -p xhubd
cargo build --release -p xhubd
bash tools/xhubd_daemon.command launchd-install --replace-running
curl -fsS http://127.0.0.1:50151/ready
curl -sS -X POST http://127.0.0.1:50151/xt/classic-hub-compat/write-status
```

The test suite covers:

- default fail-closed preflight,
- disabled local scan gate,
- active classic Hub blocking,
- disabled and failed gRPC probe gates,
- successful gRPC probe advancing to rollback gate,
- rollback/apply enabled but file IPC surface missing,
- full explicit-gate write to a temporary status path.

Live evidence captured on 2026-05-07:

- launchd runtime reinstall succeeded after one transient macOS bootstrap retry,
- `/ready` reported `xt_classic_hub_status_writer_http=true` and
  `xt_classic_hub_status_writer_authority=explicit_cutover_only`,
- default live POST returned `ok=false`, `wrote=false`,
  `deny_code=xt_classic_compat_not_enabled`,
  `production_authority_change=false`, and
  `rust_writes_classic_hub_status=false`.

## Next Slice

Implement the actual Rust XT local file IPC execution surface before enabling
`XHUB_RUST_XT_CLASSIC_FILE_IPC_READY` in any real profile.
