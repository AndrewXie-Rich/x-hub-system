# Current Status

Updated for the current Rust Hub / XT rewrite phase.

The system is no longer at the "from zero design" stage. It is in a staged authority migration: Rust Hub is becoming the deterministic local control plane, while Node Hub and Swift XT still protect the production contract and product experience.

## Production Authority

These paths are currently treated as production authority:

- Swift XT product UI and project interaction.
- Node Hub gRPC services.
- Node Hub pairing, device trust, and admin surfaces.
- Node Hub provider key store, paid model execution, OAuth import, and quota refresh.
- Node Hub official skills catalog, package validation, signing/vetting, and import bridge.
- Node/Python local model runtime bridge.
- XT Supervisor and Project Coder product surfaces.
- XT skill governance and runtime policy enforcement.

## Rust Implemented, Shadow or Candidate

Rust Hub has real implementation in these areas, but they are not blanket production authority:

- Scheduler DB, enqueue, claim, lease, heartbeat, release, cancel, and status.
- Scheduler authority bridge, default-off and readiness gated, with queued, cancel, timeout, concurrency, and live Node Hub smoke coverage.
- Provider route decision CLI/HTTP and Node shadow compare.
- Model inventory and model route CLI/HTTP.
- Model route candidate evidence and selected-model authority dry-run plans.
- Skills catalog readiness, durable pin/grant policy, preflight, audit, retention, revocation.
- Memory read-only retrieval and snapshot cache.
- HTTP readiness cache, latency metrics, recent slow-request diagnostics, backpressure, and I/O timeouts.
- Launchd daemon operation, ops report, maintenance dry-run, ops gate, watchdog, timer support.
- XT classic compatibility preflight and file IPC shadow responder/drain/loop.

## Not Yet Production Authority

These are intentionally not complete production authority yet:

- Rust memory writer authority.
- Rust third-party skill execution authority.
- Rust full replacement for `HubAI.Generate`.
- Rust full XT file IPC production responder.
- Rust replacement for Swift XT UI.
- Rust replacement for Node Hub pairing and skill package distribution.

## Recently Strengthened

- The recommended authority order is now clear: scheduler first, provider/model route second, memory writer late, skills execution last, XT Rust sidecar only on hot paths.
- Provider quota design now treats separate ChatGPT-style usage windows, such as 5-hour and 7-day windows, as first-class account-pool inputs when upstream returns them.
- Rust daemon operations are now guarded by report-only gates and watchdogs.
- Rust model/provider route evidence has moved from one-shot smoke to sustained readiness style.
- XT Rust workspace is buildable, but Swift UI remains the primary shell.

## Main Open Gaps

- Scheduler authority should be the first narrow cutover instead of trying to move the full runtime at once.
- Product documentation needs to distinguish production, shadow, and candidate authority.
- Capability contract still risks drift across Swift, Node, and Rust.
- Memory deep substrate is not equally mature across all surfaces.
- Small-task fast lane needs to stay lightweight so governance does not slow trivial work.
