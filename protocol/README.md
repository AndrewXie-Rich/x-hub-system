# Protocol

`protocol/` is the shared contract layer between X-Hub and X-Terminal.

This directory does not own product UX or runtime policy. It owns the agreements that let the active Hub and terminal surfaces talk to each other without drifting apart.

## What Lives Here

- Human-readable interface contracts
- gRPC protocol definitions
- Shared request and response structure references

## Why It Matters

The Hub and terminal are intentionally separated.

That separation only works if the contract layer stays explicit, stable, and reviewable. This directory is where those contracts live.

## Key Files

| Path | Role |
|---|---|
| `hub_protocol_v1.md` | Human-readable protocol contract |
| `hub_protocol_v1.proto` | gRPC protocol definition |

## Boundary

- Keep shared interfaces here.
- Keep Hub implementation details in `x-hub/`.
- Keep terminal implementation details in `x-terminal/`.
- Do not turn this directory into a runtime surface or a dumping ground for app-local notes.

## Read Next

- `docs/REPO_LAYOUT.md`
- `x-hub/README.md`
- `x-terminal/README.md`
