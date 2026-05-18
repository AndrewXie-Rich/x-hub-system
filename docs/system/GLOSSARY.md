# Glossary

## A-Tier

Project AI autonomy tier. It defines how far Project Coder may go in project execution.

## S-Tier

Supervisor intervention tier. It defines how deeply and actively Supervisor reviews and intervenes.

## Heartbeat

Structured progress and vitality signal. It is not the same as review and not the same as user notification.

## Review

Supervisor analysis of whether progress is meaningful, safe, on-plan, and sufficiently evidenced.

## Safe Point

A boundary where guidance or intervention can be injected without corrupting an active tool/action step.

## Authority

The component allowed to make the final production decision for a path.

## Shadow

A non-authoritative implementation that observes or computes in parallel for comparison.

## Candidate Authority

A path that can become authority after readiness, evidence, and rollback criteria are met.

## Cutover

Explicit transfer of production authority from one implementation to another.

## Grant

Hub-authorized permission for a capability or action scope.

## Capability Family

Atomic semantic capability such as `repo.read` or `browser.secret_fill`.

## Capability Profile

Derived capability bundle used by policy and UI, such as `coding_execute` or `browser_operator_with_secrets`.

## Capability Bundle

Project-level ceiling for what capabilities are allowed at an autonomy tier.

## Runtime Surface

The actual available execution surface at this moment, such as browser runtime, trusted automation, local tools, or Hub bridge.

## Capability Lease

Proposed time-bounded, scoped capability authorization with target, TTL, secret class, and revocation.

## Doctor Truth

Structured diagnosis of what is ready or blocked and why.

## Route Truth

Structured explanation of how a model/provider route was selected, blocked, or fallbacked.

## Governance Truth

Structured explanation of policy/capability/grant/runtime-surface decisions.

## Evidence Ledger

Proposed unified record linking route, doctor, skill, grant, scheduler, memory, and runtime decisions.

## Hub-First

The rule that trust, grants, durable memory, audit, and authority belong to Hub before local UI caches.

## Fail-Closed

When required evidence or authority is missing, the system denies or holds rather than guessing open.
