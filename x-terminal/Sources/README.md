# X-Terminal Sources

`x-terminal/Sources/` is the active Swift implementation tree for X-Terminal.

This is the code that turns the terminal into a governed runtime surface instead of a thin chat shell.

## Main Areas

| Path | Role |
|---|---|
| `UI/` | Terminal UI, setup flows, status surfaces, and interaction screens |
| `Supervisor/` | Orchestration, doctor/readiness flows, planning, and operational state |
| `Session/` | Session runtime and state lifecycle |
| `Hub/` | Hub-facing clients, pairing, model access, and route handling |
| `Tools/` | Tool execution, summaries, and audit-facing output |
| `Project/` | Project memory, skills compatibility, and project metadata |

## Boundary

Keep implementation code here. Tests belong in `x-terminal/Tests/`. Repo-level scripts and reports belong outside this tree unless they are terminal-local support assets.
