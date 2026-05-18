# Rust Migration

Rust migration in XHub is not a rewrite-by-replacement. It is a governed authority migration.

The goal is to move deterministic backend authority into Rust while keeping the native Swift XT experience and the existing Hub contracts stable.

## Current Position

Rust Hub is already a substantial backend lane:

- scheduler
- provider routing
- model inventory
- model routing
- skills policy
- memory read-only retrieval
- daemon readiness and watchdogs
- HTTP diagnostics
- ops gates and soak runners
- XT compatibility probes

Node Hub and Swift XT still hold production authority for many user-facing flows. That is intentional. Rust can be present, tested, and useful before it owns the final decision.

## Why Rust

Rust is a strong fit for:

- deterministic state machines
- DB-backed leases and queues
- low-latency daemon paths
- long-running local services
- bounded memory and I/O behavior
- schema-checked policy gates
- readiness and watchdog loops
- evidence generation that should not depend on UI state

Rust is not being used to replace the native Swift UI. XT should remain the product surface for approval, inspection, project work, and user interaction.

## Migration Pattern

Every authority path should move through the same ladder:

1. scaffold
2. contract mirror
3. read-only implementation
4. CLI smoke
5. HTTP or gRPC bridge
6. shadow compare
7. sustained evidence runner
8. readiness gate
9. default-off authority prep
10. explicit cutover
11. rollback validation

Skipping this ladder creates a system that may appear faster but becomes harder to trust.

## Recommended Authority Order

### 1. Scheduler Authority First

Scheduler is the best first Rust authority cutover.

It is deterministic, DB-backed, lease-oriented, and easy to test. Rust already has scheduler claim, release, cancel, status, lease shadow, readiness, HTTP bridge, authority runner, and live Node Hub authority runner evidence.

The first real cut should be narrow: one scheduler authority path for paid AI slot capacity, default-off, readiness-gated, and reversible.

### 2. Provider And Model Route Second

Provider/model route should follow scheduler, but in two phases:

- candidate audit first
- selected-model authority later

Rust already has provider route shadow compare, provider route cutover readiness, model inventory shadow compare, model route candidate evidence, and selected-model authority dry-run tooling.

The safe route is to let Rust produce candidate evidence and same-account checks before it is allowed to become the selected-model authority. This avoids silently changing paid account selection or quota behavior.

### 3. Memory Read Path Before Writer

Memory should move in this order:

1. read-only retrieval
2. snapshot assembly
3. candidate observation or summary emission
4. governed write proposal
5. durable writer authority

Rust already has memory retrieval and HTTP smoke coverage, but durable memory writer authority should remain late. A bad scheduler decision can be retried or rolled back. A bad memory writer can contaminate long-term project or personal context.

### 4. Skills Governance Before Execution

Skills should move as governance first:

- catalog read
- manifest validation
- package readiness
- policy preflight
- grant and pin checks
- doctor evidence
- retention and revocation events

Third-party skill execution authority should be last. It requires runner sandboxing, ABI stability, signing trust, secret boundaries, callback audit, and fail-closed tests.

### 5. XT Rust Sidecar Only For Hot Paths

XT Rust sidecar should not take over the Swift UI main experience.

It should focus on:

- event subscription
- snapshot assembly
- checkpoint recovery
- low-latency local reads
- background bridge health

Swift should remain responsible for user-facing workflows, approvals, project cockpit, and native interaction.

## Current Best Route

The current route is the right one if it stays disciplined:

- cut scheduler authority first
- keep provider/model route in candidate/audit mode before selected authority
- keep memory writer authority late
- keep skills execution authority late
- keep XT Rust sidecar away from the main UI experience

The main risk is not moving too slowly. The main risk is allowing Rust, Node, and Swift to each grow their own interpretation of contracts.

## Contract Discipline

The migration should converge on shared contracts:

- capability contract
- scheduler event contract
- provider route evidence contract
- model inventory contract
- memory retrieval contract
- skill package and ABI contract
- doctor evidence contract

Rust should consume or generate from those contracts instead of manually re-creating business semantics. This is the difference between a controlled authority migration and a parallel backend that drifts over time.

## Non-Goals

Rust migration should not:

- duplicate Swift UI
- bypass Node Hub contracts
- silently write canonical memory
- execute untrusted skills before sandbox contracts
- mark XT production ready through shadow-only IPC
- hide authority changes behind diagnostics
- change paid provider/model selection without evidence and rollback

## Product Interpretation

For GitHub readers, the Rust migration can be described as:

XHub is moving local agent infrastructure into a Rust control plane for deterministic scheduling, routing, readiness, recovery, and policy evidence, while preserving native XT UX and governed Hub contracts.
