# X-Hub

`x-hub/` is the trusted control plane of this repository.

If the repository root README explains the product, this directory explains where the Hub trust surface actually lives.

Public product name: `X-Hub`

Developer note: the macOS Swift package under `macos/RELFlowHub/` still uses the historical internal codename `RELFlowHub` for package / target names. Treat that as implementation debt, not public branding. The preferred source-run executable alias is now `XHub`.

Release scope note: this module README explains the active Hub trust surface and operator entrypoints. Public release claims still follow the validated-mainline-only scope defined in the repository root `README.md`, `RELEASE.md`, and the open-source release templates.

## What This Module Owns

- Pairing and trust-profile authority
- Grant and policy enforcement
- Routing for local and paid models
- Memory-backed constitutional guidance and Hub-side policy boundaries
- Hub-side audit, readiness, and export surfaces
- Shared runtime services used by terminals

## Why It Matters

The Hub exists so terminals do not become the trust anchor.

That means keys, grants, policy checks, route selection, and execution safety stay inside the Hub-side control plane instead of leaking into desktop clients or terminal-local glue code.

It also means long-lived behavioral constraints can be anchored on the Hub side. In this repository, that includes the X-Constitution path: memory-backed constitutional guidance, triggerable L0 constraints, and policy-engine reinforcement for high-risk behavior.

## Recommended Host Hardware

For real deployments, prefer Apple silicon desktop Macs as the Hub host.

- **Mac mini** is the default recommendation for most X-Hub deployments.
- **Mac Studio** is the higher-capacity recommendation when you want more local-model headroom, more memory, or heavier always-on runtime load.

This repository is a macOS-native Hub surface, and the Hub runtime also includes an MLX-aligned local runtime path, so Apple silicon desktop Macs are the most natural recommendation.

## Main Surfaces

| Path | Role |
|---|---|
| `macos/` | X-Hub app, bridge app, dock agent, and native Hub UI/runtime surfaces |
| `grpc-server/` | Node-based Hub service layer for pairing, grants, audit, and runtime RPCs |
| `python-runtime/` | Python-side runtime integration surface |
| `tools/` | Build and support scripts for Hub packaging and local operations |

## Active Entry Points

Build the Hub app bundle:

```bash
x-hub/tools/build_hub_app.command
```

Launch the built Hub app:

```bash
open build/X-Hub.app
```

Developer source run:

```bash
cd x-hub/macos/RELFlowHub
swift run XHub
```

Bridge runtime from source:

```bash
cd x-hub/macos/RELFlowHub
swift run XHubBridge
```

## Operational Boundaries

- Terminal UX, session UX, and supervisor UI belong in `x-terminal/`.
- Do not add new trust authority to terminal-local code if it belongs in the Hub.
- Do not route active build or runtime paths through archived surfaces.
- Do not reduce Hub-side constitutional and policy controls to terminal-only prompt text.

## Read Next

- `X_MEMORY.md`
- `x-hub/macos/README.md`
- `x-hub/grpc-server/README.md`
- `x-hub/python-runtime/README.md`
- `docs/REPO_LAYOUT.md`
- `docs/WORKING_INDEX.md`
