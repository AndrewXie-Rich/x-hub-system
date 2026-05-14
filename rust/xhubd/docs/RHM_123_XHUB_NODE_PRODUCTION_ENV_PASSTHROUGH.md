# RHM-123 X-Hub Node Production Env Passthrough

## Status

Implemented and live-verified on 2026-05-13.

## Problem

After provider/model and scheduler production authority were applied through the
user launchd session, a normal X-Hub.app relaunch could still start the Node
sidecar with embedded Rust Hub defaults:

- `XHUB_RUST_HUB_ROOT` pointed at the app embedded package instead of the live
  production package root.
- provider/model and scheduler authority keys were overwritten to `0`.
- memory and skills authority keys were passed to Node as explicit `0` values,
  which made runtime guards classify them as unrelated production authority
  surface in the process environment.

That made live production authority fragile across ordinary app restarts.

## Change

The non-UI X-Hub launcher support now:

- sanitizes the Node sidecar base environment before launch;
- removes memory writer and skills execution authority keys from Node;
- removes explicit false provider/model/scheduler authority defaults;
- preserves launchd-provided provider/model/scheduler production authority keys;
- preserves the launchd-provided `XHUB_RUST_HUB_ROOT` and derives the matching
  `tools/run_rust_hub.command` runner path.

This does not modify SwiftUI/product UI surfaces and does not grant Rust memory
writer or Rust skills execution authority.

## Verification

- `swift test --filter RustHubRuntimeSupportTests`: ok
- `x-hub/tools/build_hub_app.command`: ok
- rebuilt X-Hub.app Node relaunch production runtime guard: ok
- rebuilt X-Hub.app scheduler production authority status: ok
- live heartbeat soak after rebuilt X-Hub.app relaunch: ok
- daemon ops gate after rebuilt X-Hub.app relaunch: ok
- production live checkpoint after rebuilt X-Hub.app relaunch: ok
- Rust Hub UI compatibility gate: ok

## Authority Boundary

Allowed:

- provider/model route authority in Rust, when the production session and
  runtime guard are both green;
- scheduler authority in Rust, when the scheduler production session and
  runtime guard are both green;
- XT classic status writer heartbeat under explicit live cutover gates.

Still blocked:

- Rust memory writer authority;
- Rust skills execution authority;
- SwiftUI/product UI changes.
