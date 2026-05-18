# Roadmap

The XHub roadmap is an authority migration roadmap, not a rewrite checklist.

The goal is to move deterministic backend control into Rust where it improves reliability, while preserving Swift XT as the product shell and Node Hub as the production contract until each path is ready.

## Phase 1: Public Documentation And Status

Current focus:

- rewrite public description files into human-readable GitHub documentation
- label major areas as production, shadow, candidate, or planned
- explain the current Rust migration order
- separate product claims from internal future design
- keep older deep design notes as appendices or internal references

Exit condition:

- a new reader can understand what XHub does today, what Rust owns today, and what is still intentionally gated.

## Phase 2: Scheduler Authority Cutover

Scheduler is the cleanest first authority cutover because it is deterministic, DB-backed, lease-oriented, and recoverable.

Required before cutover:

- sustained scheduler authority evidence
- queued, cancel, timeout, and concurrency coverage
- clean lease shadow reports
- no stale active work or orphaned leases
- status read bridge working
- doctor/readiness proof
- clear rollback to Node scheduler
- no mixed Node/Rust scheduling under load

Exit condition:

- one narrow scheduler authority path can be enabled default-off, proven under sustained runner evidence, and disabled without data loss.

## Phase 3: Provider And Model Route Authority

Provider/model route should follow scheduler, but candidate audit comes before selected authority.

Required before cutover:

- provider route shadow compare with real account pools
- model route candidate evidence across remote and local paths
- selected-model authority dry-run reports
- same-account and same-model mismatch checks
- quota-aware route decisions, including 5-hour and 7-day windows when available
- no secret leakage in route reports
- explainable fallback reasons
- rollback to Node-selected route

Exit condition:

- Rust can produce the same selected provider/model decision for a narrow path, explain why, and fail closed on mismatch.

## Phase 4: Memory Read Path Hardening

Rust can own more memory read paths before it owns write authority.

Targets:

- read-only retrieval parity
- memory snapshot cache
- theme retrieval
- timeline retrieval
- FTS/vector hybrid retrieval
- role-aware retrieval profiles
- doctor evidence for memory assembly

Exit condition:

- Rust retrieval can serve stable, explainable memory snapshots without writing canonical memory.

Memory writer authority remains later than read-path parity.

## Phase 5: Skills Policy Before Skills Execution

Rust should continue to own deterministic policy gates before executing any third-party skill code.

Targets:

- durable policy readiness
- preflight audit ledger
- pin/grant revocation
- policy event retention
- ABI compatibility checks
- package trust evidence
- doctor-readable failure reasons

Exit condition:

- Rust can explain whether a skill is allowed under package, trust, capability, grant, and runtime policy without becoming the execution runner.

Third-party execution authority requires a separate hardening phase.

## Phase 6: XT Sidecar Hot Paths

Rust XT sidecar should target performance and reliability, not product UI replacement.

Good targets:

- event subscription
- execution queue processing
- checkpoint recovery
- snapshot assembly
- local IPC supervision
- low-latency background reads

Avoid:

- replacing SwiftUI product surfaces
- duplicating Hub trust policy in XT
- creating a second durable truth source
- marking shadow IPC as production UI readiness

Exit condition:

- Rust sidecar improves hot-path reliability while Swift XT remains the primary user experience.

## Phase 7: Capability Lease And Evidence Ledger

The next major product leap should be:

- capability lease
- unified evidence ledger
- governance simulator
- quota/account portfolio optimizer
- multi-axis readiness
- contract-generated capability semantics

These features turn the system from a set of gates into an explainable capability negotiation platform.

## Route Discipline

The roadmap should reject broad, ambiguous cutovers. Each migration should answer:

- What exactly becomes authoritative?
- What remains Node/Swift authority?
- What evidence proves parity?
- How does it fail closed?
- How is it rolled back?
- What user-facing behavior changes?

This discipline is what lets XHub move fast without becoming a parallel set of drifting backends.
