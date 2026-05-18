# Quickstart

This file is a practical starting point for running the system locally.

## Open Hub

The current production Hub is the macOS Hub app in this repository.

Typical paths:

- Hub app source: `x-hub/macos/RELFlowHub`
- Node Hub gRPC server: `x-hub/grpc-server/hub_grpc_server`
- Rust Hub artifacts: use the release package or migration branch only when explicitly included

If a Hub management page cannot be reached, check whether the Hub process and Node sidecar are running before changing configuration.

## Open XT

The current production XT app is Swift-based:

- source: `x-terminal`

The Rust XT workspace is currently a refactor lane:

- source: use the release package or migration branch only when explicitly included
- Swift shell copy and Rust sidecar are not required for the validated public quickstart

## Pair XT to Hub

The first pair is intentionally fail-closed:

- same LAN is required for first pair
- Hub owner approval is required
- invite and preauth replay checks are enforced
- later reconnects can use stored connection material

If first pair fails, use Doctor instead of bypassing pairing checks.

## Add Models

Local models:

- use Hub's local model import/discovery flows
- local model runtime is provider-based, not MLX-only
- local readiness depends on artifact, runtime provider, memory, and capability checks

Paid models:

- add remote provider accounts or import OAuth/API credentials
- paid models are governed by Hub policy, grant, quota, and route truth
- account pool and quota status are shown through Hub model/paid-access surfaces

## Check Doctor

Use XT Doctor for user-facing readiness:

- Hub reachability
- pairing validity
- model route readiness
- skills compatibility
- runtime readiness

Use Hub/Rust ops gates for backend health:

- readiness
- launchd status
- latency metrics
- watchdog reports
- authority boundary drift

## First Things to Verify

- XT can reach Hub.
- Hub Doctor is not blocked.
- A model route is ready.
- Paid model access has valid account/key/quota.
- Local runtime provider is ready if local fallback is expected.
- Skills registry is compatible if project skills are needed.
