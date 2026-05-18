# Testing and Evidence

XHub should prove behavior with machine-readable evidence, not just manual observation.

This matters because XHub is migrating authority across Swift XT, Node Hub, and Rust Hub. A path is not ready because it works once. It is ready when it preserves contracts, fails closed, and can be rolled back.

## Evidence Types

Useful evidence includes:

- unit tests
- integration tests
- smoke tests
- HTTP bridge smokes
- gRPC compatibility tests
- shadow compare reports
- readiness gates
- sustained runners
- doctor exports
- ops reports
- watchdog reports
- audit ledgers

The strongest evidence combines tests with durable reports that can be inspected after the run.

## Shadow Compare

Shadow compare is used when Rust implements a candidate path while Node or Swift remains production authority.

It should compare:

- selected account
- selected provider
- selected model
- route kind
- deny reason
- fallback behavior
- readiness decision
- quota interpretation
- capability decision
- secret leakage

Shadow compare should not change production behavior. It should produce evidence for or against future cutover.

## Readiness Gate

A readiness gate should fail closed when evidence is missing, stale, or weak.

Good readiness output includes:

- schema version
- component
- checked authority mode
- pass/fail
- reason codes
- evidence paths
- mismatch counts
- freshness timestamps
- secret leak status
- rollback status
- `production_authority_change=false` unless the command explicitly performs a cutover

Readiness should mean more than "the daemon is alive".

## Sustained Runner

One-shot success is not enough for authority migration.

Use sustained runners for:

- latency stability
- repeated route decisions
- daemon readiness
- cache behavior
- model inventory parity
- provider route parity
- scheduler lease behavior
- queued work behavior
- cancel and timeout behavior

For scheduler authority, sustained evidence should cover single run, queued concurrency, queued cancel, queued timeout, clean release, and clean final status.

For provider/model authority, sustained evidence should cover same-account selection, same-model selection, quota windows, fallback reasons, and mismatch fail-closed behavior.

## Ops Evidence

Rust Hub operational evidence includes:

- `/ready`
- HTTP metrics
- recent slow requests
- daemon ops report
- maintenance dry-run
- ops gate
- watchdog
- launchd status
- authority boundary checks

Ops evidence should prove that background services are reliable without silently enabling production authority.

## Test Policy

For high-risk changes:

- test the success path
- test the fail-closed path
- test rollback or fallback
- test no secret leakage
- test old client compatibility
- test authority boundary preservation
- test stale or missing evidence
- test cancellation and timeout if the path can block

## Documentation Policy

Public documentation should not claim production authority based only on shadow evidence.

Use clear terms:

- production: owns the final decision
- candidate: can produce a proposed decision
- shadow: compares against current authority without changing behavior
- diagnostic: reports state only
- planned: designed but not implemented

This vocabulary keeps users and contributors from mistaking diagnostics for authority.
