# RHM-048 XT File IPC Shadow Drain Processor

Status: implemented 2026-05-07

## Decision

Rust Hub now exposes a manual, bounded XT file IPC drain operation:

```text
POST /xt/file-ipc-shadow/drain
POST /compat/xt-file-ipc-shadow/drain
```

The existing `POST /xt/file-ipc-shadow/respond-once` also accepts
`{"operation":"drain"}` or `{"drain":true}`.

This is still shadow-only. It scans an explicit temporary `ai_requests`
directory, selects up to `max_requests` safe `req_<id>.json` files, and plans or
writes fail-closed `resp_<id>.jsonl` responses.

## Boundary

- No background watcher is started.
- No heartbeat or live `hub_status.json` publication is added.
- The base directory remains temp-dir-only.
- Writing still requires both body `{"apply": true}` and
  `XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY=1`.
- The shadow responder still requires `XHUB_RUST_XT_FILE_IPC_SHADOW=1`.
- Rust still does not execute ML and does not call the Python local runtime.
- `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY` remains false for real profiles.
- Existing Node/RELFlowHub remains production authority.

## Request Body

```json
{
  "base_dir": "/private/tmp/xhub-file-ipc-smoke",
  "operation": "drain",
  "apply": false,
  "max_requests": 16
}
```

`max_requests` is clamped to `1..64`. Dry-run mode returns the same result shape
without writing response files.

## Result Shape

The response includes a drain summary:

```json
{
  "schema_version": "xhub.rust_hub.xt_file_ipc_shadow.v1",
  "ok": true,
  "ready": false,
  "mode": "shadow_drain_dry_run",
  "wrote": false,
  "drain": {
    "max_requests": 16,
    "pending_request_count": 2,
    "attempted_count": 2,
    "wrote_count": 0,
    "denied_count": 0,
    "remaining_unattempted_count": 0,
    "cancel_observed_count": 0
  }
}
```

When `apply=true` and the apply env gate is enabled, each attempted request gets
the same fail-closed two-line response introduced in `RHM-047`.

## Why This Slice Exists

`RHM-047` proved Rust can parse and respond to one XT-shaped request. `RHM-048`
proves the next operational unit: bounded directory draining, deterministic
request ordering, max-request limiting, and aggregate result reporting. This is
the smallest useful step before a real supervised watcher lifecycle.

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
curl -fsS http://127.0.0.1:50151/xt/file-ipc-shadow
curl -sS -X POST http://127.0.0.1:50151/xt/file-ipc-shadow/drain \
  -H 'Content-Type: application/json' \
  --data '{}'
```

Expected live defaults:

- `/ready.capabilities.xt_file_ipc_shadow_drain_http=true`
- default `POST /xt/file-ipc-shadow/drain` returns fail-closed with
  `wrote=false`
- `/ready.capabilities.xt_file_ipc_production_surface_ready=false`
