# Repository Layout

Use this page as the navigation map for the active repository surface.

If you only need one rule, it is this:

- `x-hub/` is the active Hub control plane
- `x-terminal/` is the active terminal surface
- `archive/` is history, not runtime

This document explains where the live build, run, pairing, and documentation entrypoints are. It is a navigation document, not a release-scope expansion document.

## Start Here

Global onboarding order:

1. `README.md`
2. `docs/REPO_LAYOUT.md`
3. `X_MEMORY.md`
4. `x-hub/README.md`
5. `x-terminal/README.md`
6. `docs/WORKING_INDEX.md`

If you are already here, continue with the module-level follow-ups below:

Module-level follow-ups:

- `x-hub/macos/README.md`
- `x-hub/grpc-server/README.md`
- `x-hub/python-runtime/README.md`
- `x-terminal/Sources/README.md`
- `x-terminal/scripts/README.md`
- `protocol/README.md`
- `scripts/README.md`
- `specs/README.md`

Memory and constitutional references:

- `X_MEMORY.md`
- `docs/memory-new/xhub-constitution-l0-injection-v2.md`
- `docs/xhub-constitution-l1-guidance-v1.md`
- `docs/xhub-constitution-policy-engine-checklist-v1.md`

If the question is about bounded behavior, risk control, or why execution must fail closed, start with these documents before drilling into feature-specific specs.

## Active Runtime Rule

This repository has one active Hub surface and one active terminal surface:

- `x-hub/` is the only active Hub control plane
- `x-terminal/` is the only active terminal implementation
- `archive/x-terminal-legacy/` is preserved history and must not be used for build, run, pairing, release, or setup entrypoints

## Top-Level Map

| Path | Status | Use |
|---|---|---|
| `x-hub/` | active | Hub app, gRPC server, model routing, grants, trust, pairing, audit, and memory-backed constitutional guardrail surfaces |
| `x-terminal/` | active | Terminal UI, session runtime, supervisor, readiness checks, tools, and local gates |
| `protocol/` | active | Shared contracts between Hub and terminal surfaces |
| `specs/` | active | Executable spec packs and traceability material |
| `docs/` | active | Product docs, release docs, work orders, security docs, and operating guidance |
| `official-agent-skills/` | active | Official Agent skill sources, trust roots, and distribution artifacts used by the active skills surface |
| `scripts/` | active | Repo-level validation, packaging, and reporting scripts |
| `archive/` | archived | Historical material only; not part of the active runtime surface |
| `build/` | generated | Local outputs and machine-readable reports |
| `data/` | generated | Local runtime state, probes, and generated artifacts |

## Fast Entry Points

Use these as the current live entrypoints:

### Hub Build

```bash
x-hub/tools/build_hub_app.command
```

### Hub App Launch

```bash
open build/X-Hub.app
```

### Hub Developer Source Run

```bash
bash x-hub/tools/run_xhub_from_source.command
```

Note: `RELFlowHub` is still the current internal Swift package directory and target family under the hood. The preferred public source-run entrypoint is `x-hub/tools/run_xhub_from_source.command`, and the public product name is `X-Hub`.

### Hub Bridge Run

```bash
bash x-hub/tools/run_xhub_bridge_from_source.command
```

### Terminal Run

```bash
cd x-terminal
swift run XTerminal
```

### Terminal Build

```bash
cd x-terminal
swift build
```

### Terminal Release Gate

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

### Working Index

- `docs/WORKING_INDEX.md`

### Release Drafting

- `RELEASE.md`
- `CHANGELOG.md`
- `docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.md`
- `docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.en.md`

Use these files for GitHub-facing wording and release packaging notes. They must stay inside the validated public mainline and must not be treated as a license to copy internal work-order progress into external messaging.

## Directory Intent

### `x-hub/`

Owns trust, grants, policy enforcement, route control, audit, memory-backed constitutional guidance, and Hub-side runtime services.

For memory control specifically, the user chooses which AI executes memory jobs in X-Hub, `Memory-Core` stays on the governed rule layer, and durable writes stay bounded to `Writer + Gate`.

### `x-terminal/`

Owns interaction, session runtime, supervisor flows, doctor/readiness surfaces, and tool execution UX.

### `protocol/`

Owns shared interfaces and contracts between Hub and terminal surfaces.

### `docs/`

Owns the written operating model: release constraints, work orders, security notes, architectural references, and open-source release templates under `docs/open-source/`.

### `official-agent-skills/`

Owns official Agent skill sources, trust roots, and release-facing distribution metadata used by the active Hub and X-Terminal skills surface.

### `scripts/`

Owns repo-level validation and packaging helpers. Terminal-local validation stays in `x-terminal/scripts/`.

## Archived Path Policy

`archive/x-terminal-legacy/` exists only to preserve old local material.

- Do not point README files, setup docs, or runtime diagnostics at archived paths.
- Do not add new code that resolves skills, tools, or build outputs from archived paths.
- If history must mention an archived path, label it as archived history rather than an active surface.

## Generated Path Policy

These directories are outputs, not source:

- `build/`
- `data/`

Do not treat generated files as durable architecture entrypoints unless a specific contract explicitly says so.

## Root Hygiene

No root-level marker file is part of the active repo architecture.

If stray temporary files appear at the repository root, remove or relocate them instead of treating them as entrypoints, source directories, or durable runtime state.

## Scope Note

Internal work-order packs and operator docs may describe implementation progress beyond the validated public mainline. Use `README.md`, `RELEASE.md`, and the release-note templates to control public claims; use `docs/WORKING_INDEX.md` and work-order docs to navigate internal execution state.
