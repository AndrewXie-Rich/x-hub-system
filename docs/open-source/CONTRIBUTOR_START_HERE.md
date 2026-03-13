# Contributor Start Here

This page is the shortest contributor onramp for the public repository.

Use it when you want to answer four questions quickly:

1. What should I read first?
2. What is safe to change in a first pull request?
3. Which areas need help right now?
4. Which kinds of changes need discussion before code is written?

This page is intentionally shorter and more action-oriented than `X_MEMORY.md`.

## Read This First

If this is your first pass through the repository, read in this order:

1. `README.md`
2. `CONTRIBUTING.md`
3. `docs/REPO_LAYOUT.md`
4. `docs/WORKING_INDEX.md`

After that, pick one contribution lane below instead of trying to absorb every internal planning document at once.

## Best First Contribution Lanes

These are the highest-signal paths for a first contribution.

### 1. Docs And Release Wording

Best for contributors who want to learn the repo shape before touching runtime code.

Good first changes:

- tighten unclear wording in `README.md`, module `README.md` files, or `docs/REPO_LAYOUT.md`
- fix drift between docs and live entrypoints
- improve setup, run, or validation instructions
- clarify validated public scope without expanding claims

Avoid on a first PR:

- broad product rewrites
- release-scope expansion
- copying roadmap material into public claims

### 2. Tests, Gates, And Regression Coverage

Best for contributors who want to improve correctness without redesigning architecture.

Good first changes:

- add focused tests around fail-closed behavior
- cover pairing, grant, routing, audit, or readiness regressions
- add missing validation to CI or local gate scripts
- tighten doc-to-test traceability for already-shipped paths

Likely entrypoints:

- `x-terminal/Tests/`
- `x-hub/grpc-server/hub_grpc_server/src/*.test.js`
- `scripts/`
- `.github/workflows/`

### 3. Runtime Diagnostics And Recovery

Best for contributors who want to improve day-one usability while staying inside existing architecture.

Good first changes:

- better error messages
- clearer blocked-capability reporting
- launch recovery and diagnostics export improvements
- operator-facing status visibility

Likely entrypoints:

- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/`
- `x-terminal/Sources/UI/`
- `x-terminal/Sources/Session/`

### 4. Hub Service Reliability

Best for contributors comfortable with Node service code, SQLite-backed flows, and protocol-boundary work.

Good first changes:

- targeted fixes in gRPC service handlers
- provider compatibility and route-readiness improvements
- audit/event correctness fixes
- memory retrieval or gating correctness improvements

Likely entrypoints:

- `x-hub/grpc-server/hub_grpc_server/src/server.js`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`

### 5. X-Terminal UX And Supervisor Surfaces

Best for contributors working on terminal interaction, session UX, and multi-project operator flows.

Good first changes:

- UI polish for readiness, routing, or diagnostics
- session and supervisor usability improvements
- tool-surface clarity improvements
- isolated bug fixes in project or supervisor views

Likely entrypoints:

- `x-terminal/Sources/UI/`
- `x-terminal/Sources/Supervisor/`
- `x-terminal/Sources/Project/`
- `x-terminal/Sources/Hub/`

## Changes That Need Discussion First

Open an issue before writing code if the change would do any of the following:

- change protocol contracts in `protocol/`
- move trust, grant, policy, or audit authority out of the Hub
- expand public release claims beyond the validated mainline
- redesign cross-module architecture
- rename large parts of the repository
- weaken fail-closed behavior on high-risk paths

If the change touches trust boundaries, grants, route control, audit integrity, or constitutional guardrails, explain the boundary impact before implementation.

## Safe First Pull Request Shape

The fastest-moving first PRs usually look like this:

- one bug, one test, one narrow doc update
- one diagnostics improvement with before/after evidence
- one missing regression test for existing behavior
- one setup or runbook fix verified locally

Try to keep your first contribution inside one module or one operational concern.

## How To Pick A Task

Use this rule:

- if you want the shortest path to merging, start with docs or tests
- if you want to learn the runtime, start with diagnostics or isolated bug fixes
- if you want to change architecture, start with an issue instead of a pull request

If you are unsure where a task belongs, use `docs/WORKING_INDEX.md` and the module `README.md` files before opening files at random.

Starter issue pool:

- `docs/open-source/STARTER_ISSUES_v1.md`

## What To Avoid As A First Change

These usually require more repo context than a first contribution provides:

- large cross-cutting refactors
- protocol changes without accompanying compatibility notes
- security-boundary rewrites
- mixing docs cleanup, runtime fixes, and UI work in the same PR
- editing archived paths as if they were active runtime surfaces

## Validation Checklist

Before opening a pull request, include:

- the commands you ran
- the tests you ran
- the files or modules affected
- risk notes for operationally sensitive changes
- rollback notes when the change alters runtime behavior

If you could not run a relevant test, say so directly.

## Solo-Maintainer Reality

X-Hub-System is currently maintained primarily by one person.

That means:

- small, sharply scoped PRs get reviewed faster than ambitious rewrites
- explicit validation notes save review time
- issue-first discussion is preferred for feature or architecture changes

## Next Documents

After this page, use the more detailed references that match your task:

- starter issues: `docs/open-source/STARTER_ISSUES_v1.md`
- repo navigation: `docs/REPO_LAYOUT.md`
- active code and task map: `docs/WORKING_INDEX.md`
- current project state and priorities: `X_MEMORY.md`
- Hub module entrypoints: `x-hub/README.md`
- X-Terminal module entrypoints: `x-terminal/README.md`
