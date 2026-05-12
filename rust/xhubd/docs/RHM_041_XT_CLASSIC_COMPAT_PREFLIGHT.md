# RHM-041 XT Classic Hub Compatibility Preflight

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a non-mutating XT classic Hub compatibility preflight
endpoint:

```text
GET /xt/classic-hub-compat
GET /compat/xt-classic-hub
GET /compat/classic-hub
```

The response schema is:

```text
xhub.rust_hub.xt_classic_compat.v1
```

This endpoint is the first compatibility-bridge slice. It makes the XT classic
Hub contract visible to Rust without advertising Rust as a production Hub.

## Boundary

- Rust Hub remains `shadow_http`.
- Default diagnostics and launchd profiles do not write `hub_status.json`.
- Rust does not mark XT `hubInteractive=true`.
- Rust does not start production-compatible gRPC.
- Rust does not execute ML requests.
- Rust does not execute third-party skill code.
- Rust does not become memory writer authority.
- Existing Node/RELFlowHub remains production authority.

## Behavior

The endpoint reads XT's classic Hub candidate directories in the same order used
by `HubPaths.candidateBaseDirs()`:

1. `~/Library/Group Containers/group.rel.flowhub`
2. `~/Library/Containers/com.rel.flowhub/Data/XHub`
3. `~/Library/Containers/com.rel.flowhub/Data/RELFlowHub`
4. `/private/tmp/XHub`
5. `/private/tmp/RELFlowHub`
6. `~/XHub`
7. `~/RELFlowHub`

For each candidate it reports:

- `hub_status.json` path and existence,
- `ai_runtime_status.json` path and existence,
- `pid`,
- `updatedAt` freshness,
- `ipcMode`,
- `ipcPath`,
- `aiReady`,
- `loadedModelCount`.

It treats a candidate as an active classic Hub only when the status file has a
fresh `updatedAt` and a non-trivial `pid`. This mirrors the XT-side live status
contract closely enough for a preflight gate without probing or killing any
process.

## Gate Semantics

The endpoint defaults fail-closed:

```json
{
  "ready": false,
  "mode": "preflight_only",
  "can_mark_xt_hub_interactive": false,
  "deny_code": "xt_classic_compat_not_enabled"
}
```

Environment variables for future opt-in slices:

- `XHUB_RUST_XT_CLASSIC_COMPAT=1`: enable compatibility preflight progression.
- `XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES=1`: allow Rust Hub to read XT classic
  candidate status files. Default is off so launchd background services do not
  touch `~/Library` container paths without explicit operator intent.
- `XHUB_RUST_XT_CLASSIC_STATUS_WRITER=1`: enable the guarded writer preflight.
- `XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY=1`: allow the writer endpoint to
  apply after all other gates pass.
- `XHUB_RUST_XT_CLASSIC_GRPC_PROBE=1`: enable the guarded
  `HubRuntime.GetSchedulerStatus` compatibility probe.
- `XHUB_RUST_XT_CLASSIC_GRPC_HOST=<host>` and
  `XHUB_RUST_XT_CLASSIC_GRPC_PORT=<port>`: override the gRPC probe endpoint.
- `XHUB_RUST_XT_CLASSIC_GRPC_PROBE_TIMEOUT_MS=<ms>`: bounded probe timeout.
- `XHUB_RUST_XT_CLASSIC_STATUS_TTL_MS=<ms>`: status freshness TTL, default
  `5000`.
- `XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR=<path>`: restrict candidate scan to one
  base directory.
- `XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH=<path>`: override the future preferred
  writer target.
- `XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT=1`: confirm rollback instructions are
  available before any status write can proceed.
- `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY=1`: confirm the target file-IPC surface
  is ready.
- `XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER=1`: explicit production cutover
  authorization. Default is off.

Even with the opt-in flags, `ready` remains false until local-file scanning is
explicitly allowed, the Rust gRPC compatibility probe passes, the status writer
and apply flags are enabled, rollback is documented, file IPC is ready, and
production cutover is explicitly authorized. When a classic X-Hub is already
active, the gate returns:

```text
classic_hub_already_running
```

This prevents Rust from racing or masquerading as the active production Hub.

## Validation

Focused test:

```bash
cargo test -p xhubd xt_compat
```

Live probe against a warm daemon:

```bash
curl -fsS http://127.0.0.1:50151/xt/classic-hub-compat
```

Expected current local result while classic X-Hub is serving:

- `ready=false`
- `can_mark_xt_hub_interactive=false`
- `deny_code=classic_hub_already_running` when all preflight scan/writer
  opt-in flags are enabled, or `xt_classic_compat_not_enabled` by default
- `authority.production_authority_change=false`
- `authority.node_remains_authority=true`

## Writer Boundary

The guarded `POST /xt/classic-hub-compat/write-status` endpoint can write
`hub_status.json` only with all gates passing:

- no active classic Hub,
- explicit operator opt-in,
- explicit local-file scan opt-in,
- valid parent path,
- passing gRPC compatibility probe,
- rollback contract enabled,
- writer apply enabled,
- file IPC surface ready,
- explicit production cutover authorization.

Default launchd/local profiles keep those flags off, so Rust still does not
write `hub_status.json` during diagnostics, ops gates, or normal shadow runs.
