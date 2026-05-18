# Memory System

XHub uses memory as governed context, not as unbounded chat history.

The goal is to give agents the right working context without letting stale, private, or weakly evidenced information silently become durable truth.

## Core Split

Hub owns durable memory truth.

XT owns:

- local cache
- recent continuity
- fallback snapshots
- edit buffers
- presentation state
- user-facing correction flows

XT local memory should not silently become canonical durable memory.

## Five-Layer Model

The memory design is organized around:

- Raw Vault
- Observations
- Canonical Memory
- Working Set
- Long-term Patterns

Not every layer is equally mature across every surface yet. The strongest production path is around working set, canonical facts, focused briefs, role-aware assembly, and heartbeat projections.

## Role-Aware Assembly

Supervisor and Project Coder should not receive the same memory blob.

Supervisor needs:

- portfolio view
- focused project anchor
- cross-project signals
- conflicts and anomalies
- heartbeat/review evidence
- personal/project dual-plane context

Project Coder needs:

- current project facts
- recent project dialogue
- workflow state
- execution evidence
- guidance
- selected cross-link hints

This keeps high-level supervision and concrete coding execution from polluting each other's context.

## Recent Continuity

Recent raw continuity matters. It prevents the system from becoming a sterile summary-only agent.

The goal is to keep enough recent context to preserve interaction continuity while still using Hub-governed memory for durable truth.

## Rust Memory Role

Rust currently fits best as the memory read path and serving kernel:

- read-only retrieval
- lexical scan/index
- snapshot cache
- readiness and diagnostics
- HTTP retrieval bridge
- future FTS/vector retrieval kernel

Rust should not receive durable memory writer authority until read-path parity, evidence, doctor explainability, and rollback are strong.

## Recommended Cutover Order

Memory should move in this order:

1. Read-only retrieval.
2. Snapshot assembly.
3. Candidate observations.
4. Candidate summaries.
5. Governed write proposals.
6. Durable writer authority.

The writer must come late because memory writes shape future decisions. A wrong model route can be retried. A wrong durable memory can keep misleading the system.

## Writeback Requirements

Before any Rust memory writer authority, the system should have:

- explicit write classes
- source evidence
- confidence and freshness metadata
- personal/project boundary
- redaction and privacy policy
- duplicate and contradiction handling
- user correction path
- rollback or tombstone mechanism
- doctor-visible write reason

Memory should be auditable as a chain of evidence, not just a database row.

## Future Direction

The next memory leap should be:

- unified retrieval substrate
- theme retrieval
- timeline retrieval
- FTS/vector hybrid search
- adaptive serving
- memory assembly explainability
- evidence-linked writeback decisions

## Product Interpretation

For GitHub readers, the short version is:

XHub gives agents governed memory: role-aware context assembly, recent continuity, durable facts, and auditable writeback. Rust strengthens retrieval and serving first; canonical writer authority is deliberately late.
