# X-Terminal

`x-terminal/` is the active terminal surface for X-Hub.

It is where interaction, session runtime, supervisor workflows, readiness checks, and tool execution UX live. It is not the trust anchor.

## What This Module Owns

- Hub pairing UX and terminal-side diagnostics
- Session runtime and tool routing
- Supervisor orchestration and readiness/doctor flows
- Terminal-local tests, probes, and release gates
- Repo-local skills used by the active terminal implementation

## Design Position

X-Terminal is intentionally powerful but not sovereign.

It can present rich runtime state, guide the user through pairing and readiness, and execute governed flows, but trust, grants, and final policy authority remain in `x-hub/`.

## Main Surfaces

| Path | Role |
|---|---|
| `Sources/` | Swift source for UI, session runtime, Hub client, supervisor, and tools |
| `Tests/` | Terminal test targets |
| `scripts/` | Terminal-local gates, probes, fixtures, and support utilities |
| `work-orders/` | Scoped implementation packs and execution references |
| `skills/` | Active repo-local skills used during terminal development |

## Active Entry Points

Run locally:

```bash
cd x-terminal
swift run XTerminal
```

Build locally:

```bash
cd x-terminal
swift build
```

Run the release gate:

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

Run the stricter gate mode:

```bash
cd x-terminal
XT_GATE_MODE=strict bash scripts/ci/xt_release_gate.sh
```

## Operational Boundaries

- Do not use `archive/x-terminal-legacy/` for build, run, setup, or documentation entrypoints.
- Keep grant authority, pairing authority, and policy enforcement in `x-hub/`.
- Avoid reintroducing duplicate terminal surfaces outside `x-terminal/`.

## Read Next

- `x-terminal/Sources/README.md`
- `x-terminal/scripts/README.md`
- `docs/REPO_LAYOUT.md`
