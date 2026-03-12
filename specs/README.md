# Specs

`specs/` contains active executable specification packs for this repository.

This is where requirements, design notes, task breakdowns, and traceability artifacts stay grouped as an implementation-facing spec surface.

## What Lives Here

- Requirements documents
- Design documents
- Task breakdowns
- Traceability artifacts

## Why It Matters

This repository is large enough that code alone is not a sufficient navigation system.

The `specs/` directory keeps active, product-owned spec packs close to the implementation without mixing them into runtime code.

## Boundary

- Keep active spec packs here.
- Use neutral, product-owned naming.
- Do not reintroduce vendor-branded or tool-branded spec roots.
- Do not treat this directory as a build output or runtime state location.

## Read Next

- `docs/WORKING_INDEX.md`
- `docs/REPO_LAYOUT.md`
- `specs/xhub-memory-quality-v1/`
