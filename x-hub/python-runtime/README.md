# X-Hub Python Runtime

`x-hub/python-runtime/` contains the Python-side runtime integration used by the active Hub surface.

This is where model runtime glue, workers, and Python service adapters live for the Hub control plane.

## What Lives Here

| Path | Role |
|---|---|
| `python_service/` | Runtime service implementation and worker entrypoints |
| `python_client/` | Client-side helpers and adapters |

## Why It Matters

The Hub needs a runtime layer that can host model-serving and execution-side integrations without moving trust decisions into terminals.

This directory is part of that Hub-side runtime boundary.

## Boundary

- Keep model runtime glue here.
- Keep native app UX in `x-hub/macos/`.
- Keep terminal orchestration and interaction logic in `x-terminal/`.
- Keep shared contracts in `protocol/`.

## Read Next

- `x-hub/README.md`
- `x-hub/macos/README.md`
- `docs/WORKING_INDEX.md`
