# API and Contracts

XHub is contract-heavy by design. The product can move quickly only if each surface knows which layer owns truth, which layer is only a client, and which behaviors must fail closed.

This document summarizes the public-facing contract map. It does not replace the protocol files, skill ABI documents, or implementation tests.

## Primary Contract Surfaces

| Surface | Role | Primary Owner |
| --- | --- | --- |
| `protocol/hub_protocol_v1.proto` | gRPC service and message contract | Hub |
| Hub admin HTTP | local operations, diagnostics, sync, route probes | Hub |
| provider key store | account, quota, OAuth, cooldown state | Hub |
| official skill manifests | package metadata, compatibility, grants | Hub / official skill packages |
| skill import bridge | XT-to-Hub import normalization | Hub + XT |
| memory writer/export gates | durable memory mutation boundary | Hub |
| Rust HTTP/CLI probes | candidate authority and diagnostics | Rust Hub |
| XT Swift adapters | product UI client contract | XT |

## Authority Rule

An API that returns data is not automatically an authority boundary.

For example:

- XT can display provider quota, but Hub owns provider account truth.
- Rust can produce route decisions in shadow mode, but Node Hub remains production route authority until cutover.
- A skill package can declare capabilities, but Hub derives grants and enforces policy.
- A memory UI can stage changes, but durable writes must terminate through Hub gates.

Each API should say whether it is:

- production authority
- client display
- cache
- import bridge
- shadow compare
- diagnostics-only
- candidate authority

## gRPC Contract

The gRPC protocol is the broad XT-to-Hub contract. It should stay backward compatible whenever possible.

Expected discipline:

- add fields instead of repurposing old fields
- keep legacy flattened fields when introducing richer structures
- preserve fail-closed defaults
- treat missing optional fields as older-client compatibility
- avoid exposing secrets in status payloads
- cover behavior with tests before relying on it from XT

Quota is a good example: Hub can add per-window usage data such as 5-hour and 7-day windows while still keeping legacy flattened quota fields for older clients.

## HTTP Contract

Hub admin HTTP and Rust HTTP endpoints are local control surfaces, not public cloud APIs.

They are used for:

- doctor checks
- smoke tests
- local readiness probes
- provider route probes
- model inventory and route evidence
- scheduler status
- skills catalog readiness
- memory retrieval diagnostics
- daemon ops reports

HTTP endpoints should be explicit about whether they are read-only, dry-run, default-off, or capable of mutating local state.

## Skill Contracts

Skills are governed packages, not arbitrary prompt snippets.

The contract chain includes:

- package layout
- manifest compatibility
- publisher trust
- signing and distribution
- vetting
- import normalization
- capability derivation
- grants
- runner boundary
- audit
- revocation and kill switches

Hub must reject ambiguous or incompatible skill packages rather than silently importing something that only appears to work.

## Memory Contracts

Memory has a stricter contract than normal application state because it changes future agent behavior.

Safe memory APIs should preserve:

- read/write separation
- writer gate
- project/user scope
- provenance
- redaction
- export controls
- rollback or audit path
- policy visibility

Rust can safely start with read-only retrieval and snapshot cache work. Durable writer authority should migrate later and only with explicit gates.

## Rust Migration Contracts

Rust endpoints and commands should never imply production authority by existing.

A Rust capability should carry one of these modes:

- `diagnostics-only`
- `shadow`
- `candidate`
- `default-off bridge`
- `production authority`

Promotion requires evidence, rollback, compatibility, and release wording that matches the actual authority mode.

## Contract Drift Risks

The highest-risk drift points are:

- Swift UI assuming a cache is truth
- Rust route decisions silently changing model/account selection
- skill manifests diverging from Hub import logic
- quota windows being collapsed too early
- memory writes bypassing writer gates
- release notes claiming more than the validated slice

When in doubt, keep the old contract stable and add a narrower new surface with tests.

## Reader Summary

XHub APIs are not just integration points. They define who is allowed to decide, who is only allowed to display, and what must happen when evidence is missing.
