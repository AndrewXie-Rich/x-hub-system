# X-Hub gRPC Server

`x-hub/grpc-server/` is the active service-side runtime surface for Hub RPC behavior.

It backs the non-UI side of pairing, grants, route checks, capability flows, and audit/export plumbing.

## What Lives Here

- `hub_grpc_server/`: Node-based service source, runtime handlers, tests, and package metadata

## Responsibilities

- Pairing and device-facing RPC surfaces
- Grant and capability-chain handling
- Skills and memory-adjacent service endpoints
- Audit/export and runtime reporting surfaces
- Service-side routing helpers used by the Hub control plane

## Boundary

Keep native app UI in `x-hub/macos/`. Keep terminal session UX in `x-terminal/`. This directory is for Hub service behavior, not front-end interaction flows.
