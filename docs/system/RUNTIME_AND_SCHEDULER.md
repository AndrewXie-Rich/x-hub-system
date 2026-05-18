# Runtime and Scheduler

XHub treats runtime as recoverable work, not as a simple prompt loop. A run should be schedulable, observable, cancellable, resumable, and explainable after interruption.

## Runtime Chain

```text
user goal
  -> Supervisor intake
  -> recipe or run request
  -> launch gate
  -> prepared run
  -> active run
  -> checkpoint
  -> retry / hold / resume / recover
  -> delivery closure
```

The important product promise is not just "the agent can run". It is "the system knows what is running, why it was allowed to run, what owns the slot, and what should happen after failure or restart".

## Main Actors

Project Coder is the execution loop:

- follows project context
- executes bounded steps
- calls tools and skills through governed surfaces
- verifies after actions
- records blockers
- writes structured progress
- respects capability, scheduler, model, memory, and skill policy

Supervisor is the governance loop:

- decides whether to start or resume runs
- reviews heartbeat and project state
- injects guidance at safe points
- escalates drift, blocker, or weak completion
- summarizes progress for the user
- prevents silent runaway execution

The scheduler is the authority layer between "a run wants capacity" and "a run owns capacity". It should not depend on UI state, prompt wording, or ad hoc process memory.

## Why Scheduler Moves First To Rust

Scheduler authority is the best first Rust cutover because it is deterministic and state-machine-shaped:

- requests can be assigned stable ids
- leases can be acquired and released atomically
- concurrency can be bounded per scope
- queued work can be cancelled before execution
- stale active work can be detected
- terminal states are explicit
- rollback can fall back to the existing Node path

This is exactly the kind of backend authority Rust should own before higher-risk areas such as memory writes or third-party skill execution.

## Current Rust Reality

Rust Hub already has a real scheduler lane:

- SQLite-backed scheduler schema
- enqueue, claim, acquire, heartbeat, release, cancel, and status commands
- idempotent `scheduler claim` for enqueue-and-fair-lease behavior
- per-scope concurrency and queue handling
- lease shadow reports
- scheduler status HTTP bridge
- scheduler authority HTTP bridge smoke
- Node shadow compare tooling
- scheduler cutover readiness runner
- authority runner with queued, cancel, timeout, and concurrency scenarios
- live Node Hub authority runner using shared Node/Rust SQLite state

This means the scheduler is no longer only a future design. It already has the core evidence needed for an explicit, default-off authority switch.

## Authority Boundary Today

The current safe interpretation is:

- Node Hub still owns production scheduler behavior unless the explicit Rust scheduler authority bridge is enabled.
- Rust can provide status, shadow evidence, readiness evidence, and an opt-in authority path.
- Rust authority must remain default-off and readiness-gated.
- A failed Rust readiness check must fall back to Node, not partially run through Rust.
- XT should observe scheduler truth but should not become the scheduler authority.

This boundary matters because a scheduler bug can duplicate paid model requests, starve a project, lose cancellation, or leave a run stuck active after the real work ended.

## Cutover Path

The recommended cutover order is:

1. Keep Node production authority while Rust mirrors scheduler lifecycle events.
2. Require clean shadow compare reports and lease shadow reports.
3. Require cutover readiness to report healthy state: no stale active work, no orphaned leases, and no mismatch evidence.
4. Enable Rust status read bridge first so UI and doctor can observe Rust scheduler truth.
5. Enable Rust scheduler authority only for a narrow paid AI slot path.
6. Run sustained authority evidence: single run, queued concurrency, queued cancel, queued timeout, and live Node Hub process smoke.
7. Keep rollback simple: disable the authority bridge and return to Node scheduling.

The key discipline is to cut one authority path cleanly instead of moving the whole runtime at once.

## Checkpoint And Recovery

A recoverable run should carry:

- stable run id
- recipe id
- request id
- attempt count
- scope key
- lease owner
- state
- checkpoint timestamp
- retry budget
- cancellation token
- resume token
- audit reference

Retry answers: should this step be tried again?

Recovery answers: after interruption or restart, should this run be resumed, held, scavenged, cancelled, or suppressed?

Scheduler authority should not itself decide model choice, memory writes, or skill permissions. It should provide the reliable slot and lifecycle truth that those other systems consume.

## Recommended Next Work

The next best work is to harden the scheduler authority lane before moving broader runtime authority:

- promote the scheduler authority gate from smoke-level to release-level evidence
- expose scheduler doctor truth in a human-readable form
- connect checkpoint recovery to scheduler leases so stale work has an explicit recovery action
- define a stable runtime event schema for run requested, queued, leased, heartbeat, released, cancelled, timed out, resumed, and recovered
- keep XT sidecar responsibilities focused on event subscription, snapshot assembly, and checkpoint recovery

The product-level goal is simple: XHub should make long-running agent work feel like a managed local service, not a hidden chat session.
