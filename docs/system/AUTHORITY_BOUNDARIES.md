# Authority Boundaries

Authority means which component is allowed to make the final production decision.

In XHub, Rust migration is useful only if authority boundaries remain explicit. A component may provide evidence, candidates, readiness, or shadow reports without owning the final decision.

## Current Principle

Node Hub and Swift XT remain production authority for most product flows unless a specific default-off bridge promotes a path to Rust.

Rust Hub may produce:

- candidate decisions
- shadow compare reports
- readiness gates
- doctor evidence
- low-latency snapshots
- operational health signals

Candidate authority is not production authority.

## Production Authority Today

Node Hub currently owns the main backend production surface:

- pairing and device trust
- provider key store
- paid model execution path
- OAuth import and refresh
- official skills package truth
- official channel sync
- skills import and manifest compatibility
- signing, trusted publisher, vetter, and doctor chains
- gRPC service surface
- policy and grant enforcement
- local runtime bridge

Swift XT currently owns the main product surface:

- native UI
- user workflows
- Supervisor cockpit
- project interaction
- approval and denial presentation
- skill governance presentation
- doctor presentation
- local project registry and caches

Local Python runtime currently owns local model provider execution and loaded-runtime state where that path is used.

## Rust Candidate Authority

Rust Hub is a strong candidate authority for:

- scheduler claim and lease
- scheduler status and recovery evidence
- provider route candidate selection
- model route candidate selection
- model inventory readiness
- skills policy preflight
- memory read-only retrieval
- operational readiness
- daemon watchdog and maintenance evidence

These paths are valuable before cutover because they can be compared against Node/Swift behavior and used to build confidence.

## Paths Closest To Cutover

Scheduler is the closest and best first cutover path.

Rust already has DB-backed scheduler primitives, lease shadow, readiness, HTTP bridge, authority runner, concurrency/queue scenarios, cancel/timeout scenarios, and live Node Hub authority smoke. The correct first cut is a narrow scheduler authority path with explicit enablement and rollback.

Provider/model route should come next, but only after candidate audit and same-account evidence are stable. Rust should not silently change the selected provider account or paid model path.

## Paths That Must Stay Late

Memory writer authority should stay late.

Reason: memory writes affect future behavior and can contaminate long-term project or personal context. Rust should first own read-only retrieval, snapshot assembly, and candidate observations before writing canonical memory.

Third-party skill execution authority should stay late.

Reason: execution requires sandboxing, ABI stability, package signing trust, secret boundary enforcement, callback audit, and fail-closed tests. Rust can govern skills before it executes skills.

XT UI authority should remain Swift.

Reason: Rust sidecar is useful for event subscription, snapshot assembly, checkpoint recovery, and low-latency background paths. It should not replace the native Swift product experience.

## Rust Must Not Silently Own

Rust must not silently take over:

- memory writes
- third-party skill execution
- XT product UI
- pairing trust establishment
- Hub signed package distribution
- official skill package truth
- provider OAuth import
- paid model request payload execution
- real XT file IPC production execution
- capability contract semantics without shared contract validation

## Cutover Requirements

Any authority transfer needs:

- explicit feature flag or configuration
- documented scope
- readiness gate
- shadow compare evidence
- sustained runner evidence
- doctor visibility
- rollback command or rollback path
- no secret leakage
- no product UI regression
- fail-closed behavior on mismatch or bridge failure

The readiness gate must be more than "the daemon is running". It should prove that the candidate authority can make the same decision, preserve lifecycle state, and fail closed when inputs are unsafe.

## Practical Rule

If a path is unclear, treat Node/Swift as production authority and Rust as read-only, shadow, or candidate authority until proven otherwise.

The best XHub route is not maximum Rust coverage. The best route is controlled Rust authority where determinism, evidence, and rollback are stronger than the previous path.
