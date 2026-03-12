# Repo Scripts

`scripts/` contains repository-level validation, packaging, reporting, and evidence-generation helpers.

These scripts are for cross-cutting repository workflows. They are not a replacement for Hub runtime code or terminal-local gates.

## What Lives Here

- Release-readiness checks
- Export and reporting helpers
- Validation pipelines
- Evidence and traceability support scripts

## Why It Matters

This repository has active runtime surfaces, a validated release slice, and a large amount of machine-readable evidence.

The top-level `scripts/` directory is where repo-wide automation lives when it crosses module boundaries.

## Boundary

- Keep terminal-scoped gates in `x-terminal/scripts/`.
- Keep Hub packaging helpers in `x-hub/tools/`.
- Keep product/runtime logic in source trees, not in shell or report scripts.

## Read Next

- `x-terminal/scripts/README.md`
- `docs/WORKING_INDEX.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
