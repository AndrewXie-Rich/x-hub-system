# X-Hub

`x-hub/` is the trusted control plane of this repository.

If the repository root README explains the product, this directory explains where the Hub trust surface actually lives.

Public product name: `X-Hub`

Developer note: the macOS Swift package still lives under `macos/RELFlowHub/` for compatibility. Treat that as implementation debt, not public branding. The preferred public source-run entrypoint is `bash x-hub/tools/run_xhub_from_source.command`.

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

## Remote Channels And Paired Surfaces

The Hub is also the ingress boundary for the external world.

In the current architecture direction:

- remote channels such as Slack, Telegram, Feishu, and WhatsApp Cloud should enter the Hub first
- the Hub owns ingress authorization, replay protection, grant handling, memory truth, audit, routing, and Supervisor-facing state projection
- X-Terminal acts as a paired high-trust surface for richer local interaction, including voice-driven brief and authorization flows
- mobile companions, wearables, robots, and other trusted runners can become execution or confirmation surfaces, but they should not bypass the Hub and hold final grant authority directly

Compressed design rule:

`All external-world events enter the Hub first. High-trust interaction is then projected from the Hub to X-Terminal, mobile, or runner surfaces for execution or confirmation.`

## High-Autonomy Projects Still Terminate In Hub Governance

Higher-autonomy project modes do not remove Hub authority.

Even when a project is running in a more autonomous execution posture, the Hub should still remain the place that can:

- clamp execution down to a safer mode
- enforce TTL and expiry
- hold final grant and policy authority
- preserve audit and intervention truth
- trigger kill-switch behavior when the run should not continue

That is the important distinction between "more autonomy" and "sovereign terminal-local agent."

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

Launch the built Hub app with staged local dev Agent skills:

```bash
bash x-hub/tools/run_xhub_app_with_local_dev_agent_skills.command
```

Developer source run:

```bash
bash x-hub/tools/run_xhub_from_source.command
```

Developer source run with staged local dev Agent skills:

```bash
bash x-hub/tools/run_xhub_from_source_with_local_dev_agent_skills.command
```

Bridge runtime from source:

```bash
bash x-hub/tools/run_xhub_bridge_from_source.command
```

Bridge runtime from source with staged local dev Agent skills:

```bash
bash x-hub/tools/run_xhub_bridge_from_source_with_local_dev_agent_skills.command
```

Validate the staged local dev Agent baseline end to end:

```bash
bash x-hub/tools/run_local_dev_agent_skills_baseline_smoke.command
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
