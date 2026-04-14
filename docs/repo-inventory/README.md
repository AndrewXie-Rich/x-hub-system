# Repository Inventory

This directory is the repo-maintenance layer for active development surfaces, work-order coordination, and manual feature validation.

Use it when the repository feels too wide, when multiple AI collaborators need one shared entrypoint, or when you want to test the system feature-by-feature without mixing active surfaces with generated noise.

## Scope

These inventory docs intentionally focus on the active repository surface:

- `x-hub/`
- `x-terminal/`
- `protocol/`
- `docs/`
- `official-agent-skills/`
- `scripts/`
- `specs/`
- `website/`

These paths are explicitly excluded as source-of-truth development entrypoints:

- `archive/`
- `build/`
- `data/`
- `**/node_modules/`
- `x-terminal/.axcoder/reports/**`
- `x-terminal/.ax-test-cache/`
- `x-terminal/skills/_projects/`
- `x-terminal/voice_supervisor_smoke_project/`
- `x-hub-system/`
- root stray markers: `Scheduler`, `Worker`, `Writer`

## Read Order

If you are resuming work and need one clean starting sequence:

1. `README.md`
2. `X_MEMORY.md`
3. `docs/WORKING_INDEX.md`
4. `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
5. `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
6. this directory

## Documents In This Directory

### `ACTIVE_DEVELOPMENT_SURFACES.md`

Use this file to answer:

- which code roots are actually active
- where `dashboard` really lives
- which directories are generated noise
- where an engineer should start for a given task

### `WORK_ORDER_MASTER_CATALOG.md`

Use this file to answer:

- which work orders are active across the whole repository
- how XT packs and repo-level parent work orders connect
- which families are `P0`, `P1`, `P2`, or frozen
- which paths must be ignored because they are snapshots or generated copies

### `FEATURE_VALIDATION_CHECKLIST.md`

Use this file to answer:

- which capabilities the system is trying to deliver
- what has already landed vs what is only preview-working or still in progress
- how to test each capability deliberately
- which gaps are still expected today

### `AI_HANDOFF_START_HERE.md`

Use this file to answer:

- which files every new AI must read first
- which noisy paths are now explicitly ignored
- which lane a new AI should claim
- which old status files should no longer be treated as the primary handoff truth

### `CAPABILITY_AI_HANDOFF_2026-03-30.md`

Use this file to answer:

- how the capability stack is layered from package truth to route truth
- which write roots belong to capability derivation vs readiness vs runtime deny vs presentation
- which no-regression rules apply before changing grant/readiness semantics
- which narrow tests should be run for capability-focused slices

### `MULTI_AI_SECONDARY_WORK_ORDERS_2026-03-27.md`

Use this file to answer:

- which exact single feature each AI should take in the current round
- which write scopes are intentionally non-overlapping
- which high-conflict branches are explicitly excluded from the round

### `MULTI_AI_LANE_DISPATCH_2026-03-27.md`

Use this file to answer:

- which 4 execution lanes are currently active
- which files each AI should own
- which files each lane should avoid
- which focused validation commands belong to each lane

## Multi-AI Coordination Rules

If multiple AI collaborators continue from this inventory, use these rules:

1. Pick one write surface per AI whenever possible.
   Good splits: `x-hub/macos`, `x-hub/grpc-server`, `x-hub/python-runtime`, `x-terminal/Sources/Supervisor`, `x-terminal/Sources/Project`, `x-terminal/Sources/UI`, `docs`.

2. Pick one primary work-order family per AI.
   Do not let two AIs start from the same pack unless they have disjoint write sets.

3. Always cite four fields before starting implementation:
   - `scope`
   - `priority`
   - `role`
   - `start-here`

4. Do not assign generated or snapshot paths.
   The biggest trap in this repo is accidentally treating `.axcoder` report snapshots or generated release artifacts as live source.

5. Validate against the feature checklist, not only the work order.
   A landed code change should map back to one or more feature rows in `docs/repo-inventory/FEATURE_VALIDATION_CHECKLIST.md`.

## Recommended Workflow

For a fresh work session:

1. choose the feature or bug from `docs/repo-inventory/FEATURE_VALIDATION_CHECKLIST.md`
2. resolve the owning pack in `docs/repo-inventory/WORK_ORDER_MASTER_CATALOG.md`
3. open the relevant code roots from `docs/repo-inventory/ACTIVE_DEVELOPMENT_SURFACES.md`
4. open `docs/repo-inventory/AI_HANDOFF_START_HERE.md` if a new AI is joining the branch
5. open `docs/repo-inventory/MULTI_AI_SECONDARY_WORK_ORDERS_2026-03-27.md` if the work is being split across multiple AI workers
6. make the change
7. update or rerun the relevant tests / gates
8. mark validation evidence back against the feature row
