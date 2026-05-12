# RHM-042 XT Classic gRPC Compatibility Probe

Status: implemented 2026-05-07

## Decision

`GET /xt/classic-hub-compat` now has an explicit, fail-closed Rust gRPC
compatibility probe before any default `hub_status.json` publication.

The probe is off by default. When enabled, it calls:

```text
HubRuntime.GetSchedulerStatus
```

against the configured Rust gRPC endpoint and records whether the response
contains the `paid_ai` scheduler status payload XT/Hub bridges already depend
on.

## Boundary

- Rust Hub remains `shadow_http` for the browser/HTTP daemon.
- The HTTP preflight does not start a gRPC server.
- Default diagnostics and launchd profiles still do not write
  `hub_status.json`.
- Rust still does not mark XT `hubInteractive=true`.
- Rust still does not execute ML requests or third-party skill code.
- Existing Node/RELFlowHub remains production authority.

## Opt-In

- `XHUB_RUST_XT_CLASSIC_GRPC_PROBE=1`: enable the gRPC readiness probe.
- `XHUB_RUST_XT_CLASSIC_GRPC_HOST=<host>`: probe host, default Rust Hub host.
- `XHUB_RUST_XT_CLASSIC_GRPC_PORT=<port>`: probe port, default
  `XHUB_RUST_HUB_GRPC_PORT` / `50152`.
- `XHUB_RUST_XT_CLASSIC_GRPC_PROBE_TIMEOUT_MS=<ms>`: probe timeout, default
  `250`, clamped to `50..5000`.

## Gate Semantics

Default result remains:

```text
deny_code=xt_classic_compat_not_enabled
ready=false
can_mark_xt_hub_interactive=false
```

When all preflight flags are enabled but the gRPC probe is disabled:

```text
deny_code=grpc_compat_probe_disabled
```

When the probe is enabled but the endpoint is down or the RPC fails:

```text
deny_code=grpc_compat_not_ready
```

When the probe succeeds without the later explicit rollback/apply/file-IPC and
production-cutover gates, the compatibility gate still returns `ready=false`,
with a deny code such as:

```text
deny_code=rollback_contract_not_ready
ready=false
can_mark_xt_hub_interactive=false
```

That final gate is intentional. A successful probe only proves that a Rust
gRPC surface can answer the required RPC; it does not authorize Rust to publish
classic Hub liveness to XT.

## Response Fields

The existing `xhub.rust_hub.xt_classic_compat.v1` response now includes:

```json
{
  "grpc_compat": {
    "probe_enabled": true,
    "probe_ok": true,
    "endpoint": "http://127.0.0.1:50152",
    "timeout_ms": 250,
    "service": "HubRuntime",
    "method": "GetSchedulerStatus",
    "error_code": "",
    "error_message": "",
    "paid_ai_seen": true,
    "updated_at_ms": 0,
    "queue_depth": 0,
    "in_flight_total": 0
  }
}
```

It also reports:

- `authority.rust_grpc_compat_probe_ready`
- `xt_contract.status_writer_implemented`
- `xt_contract.status_writer_apply_enabled`
- `xt_contract.rollback_contract_ready`
- `xt_contract.file_ipc_surface_ready`
- `xt_contract.production_cutover_authorized`
- checks for `grpc_compat_probe_enabled`, `grpc_compat_ready`,
  `classic_status_writer_implemented`, `rollback_contract_ready`,
  `classic_status_writer_apply_enabled`, `classic_file_ipc_surface_ready`, and
  `production_cutover_authorized`

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
curl -fsS http://127.0.0.1:50151/xt/classic-hub-compat
```

The test suite covers:

- default fail-closed behavior,
- explicit opt-in with local status scan disabled,
- active classic Hub blocking bridge preparation,
- no active classic Hub reaching the disabled-probe gate,
- enabled probe with no gRPC service failing closed,
- enabled probe against a real in-process `HubRuntime.GetSchedulerStatus`
  service advancing only to the next fail-closed cutover gate.

Live E2E evidence captured on 2026-05-07:

- launchd runtime copy installed and ad-hoc signed successfully,
- `/ready` reported `xt_classic_hub_grpc_probe_http=true`,
- default `/xt/classic-hub-compat` reported `probe_enabled=false` and stayed
  fail-closed,
- isolated temporary HTTP + gRPC daemons on loopback ports returned
  `grpc_compat.probe_ok=true`, `paid_ai_seen=true`, a fail-closed deny code,
  and `ready=false`.

## Next Slice

Implement the actual Rust XT local file IPC execution surface before allowing
any real profile to enable the status writer cutover gates.
