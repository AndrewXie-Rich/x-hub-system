# Architecture

XHub is split into product surfaces, authority services, runtime surfaces, and migration lanes.

The current architecture is intentionally hybrid: Swift XT remains the native product shell, Node Hub protects the production contract, and Rust Hub is becoming the deterministic local control plane one authority path at a time.

## High-Level Shape

```text
User
  |
  v
X-Terminal / XT native UI
  |
  v
Node Hub production authority
  |
  +-- Local Python Runtime
  +-- Provider keys / OAuth / paid model bridge
  +-- Official skills catalog and package governance
  +-- Memory truth and export gates
  +-- Pairing / doctor / audit
  |
  v
Rust Hub candidate and cutover authority
```

Rust Hub runs side by side. It is not a UI replacement and not a silent production replacement.

## XT

XT is the product shell:

- project chat and timeline
- Supervisor cockpit
- model and quota settings
- skill governance UI
- doctor and troubleshooting UI
- pairing and Hub connection UX
- approval and denial presentation
- local fallback/cache/edit buffers

XT should not become the durable trust source. When XT caches something, the cache must be treated as cache, fallback, or edit buffer unless a contract says otherwise.

## Node Hub

Node Hub is still the main production authority for:

- gRPC services
- `HubAI.Generate`
- pairing and device trust
- provider key store and OAuth import
- quota refresh and provider account state
- paid model governance
- local runtime bridge
- official skill catalog
- skill signing, vetting, manifest compatibility, and import bridge
- grant and policy enforcement
- memory export gates
- admin HTTP surfaces

This is the "do not break existing users" layer.

## Rust Hub

Rust Hub is the deterministic rewrite lane. It currently focuses on:

- scheduler DB and lease primitives
- scheduler status, shadow, readiness, and default-off authority bridge
- provider route decisions
- model inventory and route decisions
- skills policy preflight and audit
- read-only memory retrieval
- daemon health, readiness, metrics, ops gates, and watchdogs
- XT compatibility probes and file IPC shadow paths

Rust Hub should be promoted by capability, not by broad replacement.

## Authority Migration Order

The recommended authority order is:

1. Scheduler authority first.
2. Provider/model route second, with candidate audit before selected-model authority.
3. Memory read path first, durable writer authority last.
4. Skills governance first, third-party execution authority last.
5. XT Rust sidecar only for hot paths, not Swift UI replacement.

This order matches risk. Scheduler is deterministic and recoverable. Provider/model route affects cost and quota. Memory writes affect future agent behavior. Third-party skill execution affects security. UI replacement risks product regression without improving backend authority.

## Rust XT / Sidecar

Rust XT or `xtd` should target hot runtime paths:

- Hub event subscription
- execution queueing
- checkpoint recovery
- snapshot assembly
- background coordination
- low-latency local reads

It should not replace the Swift product UI.

## Data Truth Boundaries

- Hub owns trust, grants, audit, durable memory truth, kill switches, and authoritative routing decisions.
- XT owns user interaction, local presentation, approvals, and short-lived working state.
- Rust owns candidate deterministic backend kernels until explicit cutover.
- Local Python Runtime owns model-provider execution details, not governance.

## Cutover Requirements

Each authority transfer needs:

- default-off bridge
- documented scope
- shadow compare
- sustained evidence
- readiness gate
- doctor visibility
- rollback path
- no product UI regression
- fail-closed behavior

## Design Rule

If a change makes a subsystem "work" but bypasses the authority boundary, it is a regression.

The best route is not to move everything to Rust quickly. The best route is to move the right authority paths to Rust with evidence, rollback, and contract discipline.
